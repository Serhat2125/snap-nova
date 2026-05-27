// ═══════════════════════════════════════════════════════════════════════════
//  ClassService — Öğretmen sınıf yönetimi.
//
//  Firestore yapısı:
//    classes/{classId}                      → sınıf bilgisi
//        {teacherUid, name, schoolName, code, subject, level, createdAt}
//    classes/{classId}/students/{studentUid}  → sınıftaki öğrenciler
//        {username, displayName, avatar, joinedAt, status}
//    classes/{classId}/content/{contentId}    → öğretmenin dağıttığı içerik
//        {type: 'summary'|'test', title, topic, subject, sharedAt, payload}
//    users/{uid}/joined_classes/{classId}     → öğrencinin katıldığı sınıflar
//        {className, teacherDisplayName, joinedAt}
//
//  Sınıf kodu: SINIF-XXXXX (5 alfanümerik, ambiguous karakter yok).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum JoinClassResult {
  success, invalidCode, classNotFound, alreadyJoined, selfJoin, notAuthed, error,
}

class TeacherClass {
  final String id;
  final String teacherUid;
  final String name;
  final String schoolName;
  final String code;
  final String subject;
  final String level;
  final DateTime createdAt;
  final int studentCount;

  const TeacherClass({
    required this.id,
    required this.teacherUid,
    required this.name,
    required this.schoolName,
    required this.code,
    required this.subject,
    required this.level,
    required this.createdAt,
    this.studentCount = 0,
  });

  factory TeacherClass.fromDoc(DocumentSnapshot<Map<String, dynamic>> d, {int students = 0}) {
    final m = d.data() ?? const <String, dynamic>{};
    DateTime when = DateTime.now();
    final ts = m['createdAt'];
    if (ts is Timestamp) when = ts.toDate();
    return TeacherClass(
      id: d.id,
      teacherUid: (m['teacherUid'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      schoolName: (m['schoolName'] ?? '').toString(),
      code: (m['code'] ?? '').toString(),
      subject: (m['subject'] ?? '').toString(),
      level: (m['level'] ?? '').toString(),
      createdAt: when,
      studentCount: students,
    );
  }
}

class ClassStudent {
  final String uid;
  final String username;
  final String displayName;
  final String avatar;
  final DateTime joinedAt;

  const ClassStudent({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.avatar,
    required this.joinedAt,
  });

  factory ClassStudent.fromMap(String uid, Map<String, dynamic> m) {
    DateTime when = DateTime.now();
    final ts = m['joinedAt'];
    if (ts is Timestamp) when = ts.toDate();
    return ClassStudent(
      uid: uid,
      username: (m['username'] ?? '').toString(),
      displayName: (m['displayName'] ?? '').toString(),
      avatar: (m['avatar'] ?? '👤').toString(),
      joinedAt: when,
    );
  }
}

class JoinedClass {
  final String classId;
  final String className;
  final String teacherDisplayName;
  final DateTime joinedAt;

  const JoinedClass({
    required this.classId,
    required this.className,
    required this.teacherDisplayName,
    required this.joinedAt,
  });

  factory JoinedClass.fromMap(String classId, Map<String, dynamic> m) {
    DateTime when = DateTime.now();
    final ts = m['joinedAt'];
    if (ts is Timestamp) when = ts.toDate();
    return JoinedClass(
      classId: classId,
      className: (m['className'] ?? '').toString(),
      teacherDisplayName: (m['teacherDisplayName'] ?? '').toString(),
      joinedAt: when,
    );
  }
}

class ClassService {
  ClassService._();
  static final _fs = FirebaseFirestore.instance;
  static String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  // ── Kod üretimi (SINIF-XXXXX) ───────────────────────────────────────
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static String _generateCode() {
    final rng = math.Random.secure();
    final buf = StringBuffer('SINIF-');
    for (int i = 0; i < 5; i++) {
      buf.write(_alphabet[rng.nextInt(_alphabet.length)]);
    }
    return buf.toString();
  }

  // ── ÖĞRETMEN: Sınıf oluştur ─────────────────────────────────────────
  static Future<TeacherClass?> createClass({
    required String name,
    required String schoolName,
    required String subject,
    required String level,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return null;
    try {
      // Benzersiz kod garanti et (max 5 deneme)
      String? code;
      for (int attempt = 0; attempt < 5; attempt++) {
        final candidate = _generateCode();
        final existing = await _fs
            .collection('class_codes')
            .doc(candidate)
            .get();
        if (!existing.exists) {
          code = candidate;
          break;
        }
      }
      if (code == null) return null;
      final newDoc = _fs.collection('classes').doc();
      final classId = newDoc.id;
      final batch = _fs.batch();
      batch.set(newDoc, {
        'teacherUid': myUid,
        'name': name.trim(),
        'schoolName': schoolName.trim(),
        'code': code,
        'subject': subject.trim(),
        'level': level.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Reverse index: code → classId
      batch.set(_fs.collection('class_codes').doc(code), {
        'classId': classId,
        'teacherUid': myUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return TeacherClass(
        id: classId,
        teacherUid: myUid,
        name: name,
        schoolName: schoolName,
        code: code,
        subject: subject,
        level: level,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[ClassService] createClass fail: $e');
      return null;
    }
  }

  /// Öğretmenin tüm sınıfları stream — dashboard için.
  /// Not: composite index gereksinimini ortadan kaldırmak için sıralama
  /// client-side yapılıyor (where + orderBy aynı sorguda index ister).
  static Stream<List<TeacherClass>> myClassesStream() {
    final myUid = _myUid;
    if (myUid == null) return Stream.value(const <TeacherClass>[]);
    return _fs
        .collection('classes')
        .where('teacherUid', isEqualTo: myUid)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map(TeacherClass.fromDoc).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Bir sınıfın öğrencilerini stream.
  /// orderBy tek alan (joinedAt) — composite index gerekmiyor; doğrudan
  /// Firestore'a sıralatıyoruz.
  static Stream<List<ClassStudent>> studentsStream(String classId) {
    return _fs
        .collection('classes')
        .doc(classId)
        .collection('students')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => ClassStudent.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
          return list;
        });
  }

  /// Sınıf sil.
  static Future<bool> deleteClass(String classId, String code) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      final batch = _fs.batch();
      batch.delete(_fs.collection('classes').doc(classId));
      batch.delete(_fs.collection('class_codes').doc(code));
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[ClassService] deleteClass fail: $e');
      return false;
    }
  }

  // ── ÖĞRENCİ: Sınıfa katıl ───────────────────────────────────────────
  static Future<JoinClassResult> joinByCode(String rawCode) async {
    final myUid = _myUid;
    if (myUid == null) return JoinClassResult.notAuthed;
    final code = rawCode.trim().toUpperCase();
    if (!RegExp(r'^SINIF-[A-Z0-9]{5}$').hasMatch(code)) {
      return JoinClassResult.invalidCode;
    }
    try {
      final codeDoc = await _fs.collection('class_codes').doc(code).get();
      if (!codeDoc.exists) return JoinClassResult.classNotFound;
      final classId = codeDoc.data()?['classId'] as String?;
      final teacherUid = codeDoc.data()?['teacherUid'] as String?;
      if (classId == null) return JoinClassResult.error;
      if (teacherUid == myUid) return JoinClassResult.selfJoin;

      // Zaten katılmış mı?
      final existing = await _fs
          .collection('classes').doc(classId)
          .collection('students').doc(myUid)
          .get();
      if (existing.exists) return JoinClassResult.alreadyJoined;

      // Öğrenci profilini al
      final myProfile = await _fs.collection('users').doc(myUid).get();
      final myData = myProfile.data() ?? const <String, dynamic>{};

      // Sınıf bilgisini al (öğrencinin joined_classes'ına yazmak için)
      final classDoc = await _fs.collection('classes').doc(classId).get();
      final classData = classDoc.data() ?? const <String, dynamic>{};

      // Öğretmen bilgisini al
      final teacherProfile = await _fs
          .collection('users').doc(teacherUid).get();
      final teacherData = teacherProfile.data() ?? const <String, dynamic>{};

      final batch = _fs.batch();
      final now = FieldValue.serverTimestamp();
      batch.set(
        _fs.collection('classes').doc(classId)
            .collection('students').doc(myUid),
        {
          'username': myData['username'] ?? '',
          'displayName': myData['displayName'] ?? '',
          'avatar': myData['avatar'] ?? '👤',
          'joinedAt': now,
          'status': 'active',
        },
      );
      batch.set(
        _fs.collection('users').doc(myUid)
            .collection('joined_classes').doc(classId),
        {
          'className': classData['name'] ?? '',
          'subject': classData['subject'] ?? '',
          'teacherDisplayName': teacherData['displayName'] ??
                                teacherData['username'] ?? '',
          'joinedAt': now,
        },
      );
      await batch.commit();
      return JoinClassResult.success;
    } catch (e) {
      debugPrint('[ClassService] join fail: $e');
      return JoinClassResult.error;
    }
  }

  /// Öğrencinin katıldığı sınıflar stream.
  /// Tek alanlı orderBy — composite index gerekmiyor; client-side sıralama
  /// boş veri durumunda da spinner takılmasın diye Stream.value fallback'i.
  static Stream<List<JoinedClass>> myJoinedClassesStream() {
    final myUid = _myUid;
    if (myUid == null) return Stream.value(const <JoinedClass>[]);
    return _fs
        .collection('users')
        .doc(myUid)
        .collection('joined_classes')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => JoinedClass.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
          return list;
        });
  }

  /// Öğrenci sınıftan ayrıl.
  static Future<bool> leaveClass(String classId) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      final batch = _fs.batch();
      batch.delete(
        _fs.collection('classes').doc(classId)
            .collection('students').doc(myUid),
      );
      batch.delete(
        _fs.collection('users').doc(myUid)
            .collection('joined_classes').doc(classId),
      );
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[ClassService] leave fail: $e');
      return false;
    }
  }

  // ── İÇERİK PAYLAŞIMI (öğretmen → sınıf) ─────────────────────────────
  /// Öğretmenin sınıfa içerik (özet/test) göndermesi.
  static Future<bool> shareToClass({
    required String classId,
    required String type,    // 'summary' | 'test'
    required String title,
    required String topic,
    required String subject,
    required Map<String, dynamic> payload,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      await _fs.collection('classes').doc(classId)
          .collection('content').doc()
          .set({
        'teacherUid': myUid,
        'type': type,
        'title': title,
        'topic': topic,
        'subject': subject,
        'payload': payload,
        'sharedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[ClassService] shareToClass fail: $e');
      return false;
    }
  }

  /// Sınıfın içerik akışı (her iki taraf okur).
  static Stream<List<Map<String, dynamic>>> classContentStream(String classId) {
    return _fs
        .collection('classes').doc(classId)
        .collection('content')
        .orderBy('sharedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = Map<String, dynamic>.from(d.data());
              m['_id'] = d.id;
              return m;
            }).toList());
  }
}
