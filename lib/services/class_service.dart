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
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'account_service.dart';
import 'analytics.dart';

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
  /// Sınıf profil fotoğrafı — küçük thumbnail base64 (data URL). Boşsa
  /// varsayılan sınıf ikonu gösterilir. (Firebase Storage yok; ~10KB doc'a sığar.)
  final String photoB64;
  /// Öğretmenin sınıf için yazdığı durum mesajı.
  final String statusMessage;
  /// Sınıfın not sistemi/müfredat ülke kodu (öğretmenden gelir). Ebeveyn/öğrenci
  /// de notları AYNI müfredat skalasında görsün diye sınıf belgesine yazılır.
  /// Boş → görüntüleyenin kendi seçimi / generic'e düşülür.
  final String gradingCountry;
  /// Sınıfın TAM profil kimliği (ör. 'us' veya 'gpa4') — gradingCountry tek
  /// başına aynı ülkedeki birden fazla profili ayırt edemez.
  final String gradingProfile;

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
    this.photoB64 = '',
    this.statusMessage = '',
    this.gradingCountry = '',
    this.gradingProfile = '',
  });

  /// Gösterim/paylaşım için 5 haneli kod (eski "SINIF-XXXXX" önekini atar).
  String get shortCode =>
      code.startsWith('SINIF-') ? code.substring(6) : code;

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
      photoB64: (m['photoB64'] ?? '').toString(),
      statusMessage: (m['statusMessage'] ?? '').toString(),
      gradingCountry: (m['gradingCountry'] ?? '').toString(),
      gradingProfile: (m['gradingProfile'] ?? '').toString(),
    );
  }
}

class ClassStudent {
  final String uid;
  final String username;
  final String displayName;
  final String avatar;
  final DateTime joinedAt;
  /// Öğretmenin bu sınıf için belirlediği görünen ad (gerçek ad veya lakap).
  /// Boşsa öğrencinin kendi adı/kullanıcı adı kullanılır.
  final String teacherAlias;
  // ── Öğrenci profili alanları — öğretmen paneli öğrenciyi PROFİLİNDEKİ
  //    haliyle görsün diye (foto, seviye, ülke, durum mesajı). Katılımda
  //    kopyalanır + studentsWithProfilesStream canlı profille tazeler.
  /// Profil fotoğrafı (base64 data URL) — boşsa emoji avatar kullanılır.
  final String avatarData;
  /// Öğrencinin profilindeki sınıf seviyesi (ör. "9. Sınıf").
  final String grade;
  /// Ülke kodu (ör. 'TR').
  final String country;
  /// Öğrencinin kendi yazdığı durum mesajı / kısa biyografi.
  final String statusMessage;

  const ClassStudent({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.avatar,
    required this.joinedAt,
    this.teacherAlias = '',
    this.avatarData = '',
    this.grade = '',
    this.country = '',
    this.statusMessage = '',
  });

  /// Sınıf listesinde gösterilecek ad — öncelik: öğretmen lakabı > öğrencinin
  /// kendi adı > @kullanıcı adı.
  String get displayLabel {
    if (teacherAlias.trim().isNotEmpty) return teacherAlias.trim();
    if (displayName.trim().isNotEmpty) return displayName.trim();
    return '@$username';
  }

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
      teacherAlias: (m['teacherAlias'] ?? '').toString(),
      avatarData: (m['avatarData'] ?? '').toString(),
      grade: (m['grade'] ?? '').toString(),
      country: (m['country'] ?? '').toString(),
      statusMessage: (m['statusMessage'] ?? '').toString(),
    );
  }
}

/// Öğretmenin öğrenciye girdiği yazılı/sözlü notu.
/// Firestore: classes/{classId}/students/{uid}/grades/{gradeId}
class StudentGrade {
  final String id;
  /// Kategori anahtarı (müfredata göre: 'yazili'|'sozlu'|'exam'|'quiz'…).
  final String type;
  /// Kaçıncı sınav (1, 2, 3…). Sözlü için de sıra numarası.
  final int order;
  /// Dönem (1 veya 2).
  final int term;
  /// Skala üzerindeki ham not (müfredata göre 0-100 / 1-5 / 0-20 / GPA…).
  /// Ondalık desteklenir (Fransa 14,5 · Almanya 2,3 · GPA 3,7).
  final double score;
  /// Bu notun dönem ortalamasına ETKİSİ (ağırlık, yüzde 1-100).
  /// 0 = ağırlık belirtilmemiş (eski kayıt) → eşit ağırlık gibi davranılır.
  final int weight;
  /// Sınav tarihi.
  final DateTime date;

  const StudentGrade({
    required this.id,
    required this.type,
    required this.order,
    required this.term,
    required this.score,
    this.weight = 0,
    required this.date,
  });

  bool get isOral => type == 'sozlu';

  /// "1. Yazılı" / "2. Sözlü" gibi okunur ad.
  String get label => '$order. ${isOral ? 'Sözlü' : 'Yazılı'}';

  factory StudentGrade.fromMap(String id, Map<String, dynamic> m) {
    DateTime when = DateTime.now();
    final ts = m['date'];
    if (ts is Timestamp) when = ts.toDate();
    return StudentGrade(
      id: id,
      type: (m['type'] ?? 'yazili').toString(),
      order: (m['order'] as num?)?.toInt() ?? 1,
      term: (m['term'] as num?)?.toInt() ?? 1,
      score: (m['score'] as num?)?.toDouble() ?? 0,
      weight: (m['weight'] as num?)?.toInt() ?? 0,
      date: when,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'order': order,
        'term': term,
        'score': score,
        'weight': weight,
        'date': Timestamp.fromDate(date),
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// Öğretmenin öğrenci hakkında yazdığı bir not (Öğrenim sekmesi).
/// Firestore: classes/{classId}/students/{uid}/notes/{noteId}
class StudentNote {
  final String id;
  final String text;
  final DateTime createdAt;
  /// Ebeveyn panelinde görünür mü? (false = öğretmene özel gözlem)
  final bool sharedWithParent;
  /// 'note' = normal not | 'praise' = takdir/hızlı geri bildirim (👏)
  final String kind;

  const StudentNote({
    required this.id,
    required this.text,
    required this.createdAt,
    this.sharedWithParent = false,
    this.kind = 'note',
  });

  bool get isPraise => kind == 'praise';

  factory StudentNote.fromMap(String id, Map<String, dynamic> m) {
    DateTime when = DateTime.now();
    final ts = m['createdAt'];
    if (ts is Timestamp) when = ts.toDate();
    return StudentNote(
      id: id,
      text: (m['text'] ?? '').toString(),
      createdAt: when,
      sharedWithParent: m['sharedWithParent'] == true,
      kind: (m['kind'] ?? 'note').toString(),
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

/// Öğretmenin "öğrenci ara & davet" akışında bir arama sonucu.
class StudentSearchResult {
  final String uid;
  final String username;
  final String displayName;
  final String avatar;
  const StudentSearchResult({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.avatar,
  });
}

class ClassService {
  ClassService._();
  static final _fs = FirebaseFirestore.instance;
  static String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  /// Oturum açık bir uid döndürür. Test modunda giriş atlandığından anonim
  /// oturum henüz hazır olmayabilir → yoksa bir kez anonim oturum dener.
  /// Anonim auth Firebase Console'da kapalıysa null döner (ve loglanır).
  static Future<String?> _ensureUid() async {
    final existing = _myUid;
    if (existing != null) return existing;
    try {
      final cred = await FirebaseAuth.instance
          .signInAnonymously()
          .timeout(const Duration(seconds: 8));
      return cred.user?.uid;
    } catch (e) {
      debugPrint('[ClassService] anonim oturum açılamadı (Console\'da '
          'Anonymous sign-in kapalı olabilir): $e');
      return null;
    }
  }

  // ── Kod üretimi (5 alfanümerik, ambiguous karakter yok) ─────────────
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static String _generateCode() {
    final rng = math.Random.secure();
    final buf = StringBuffer();
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
    final myUid = await _ensureUid();
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
      // Öğretmenin not sistemi/müfredat ülkesi → sınıfa gömülür ki ebeveyn ve
      // öğrenci de notları aynı skalada görsün.
      final gradingCountry = AccountService.instance.gradingCountry ?? '';
      final gradingProfile = AccountService.instance.gradingProfile ?? '';
      final batch = _fs.batch();
      batch.set(newDoc, {
        'teacherUid': myUid,
        'name': name.trim(),
        'schoolName': schoolName.trim(),
        'code': code,
        'subject': subject.trim(),
        'level': level.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        if (gradingCountry.isNotEmpty) 'gradingCountry': gradingCountry,
        if (gradingProfile.isNotEmpty) 'gradingProfile': gradingProfile,
      });
      // Reverse index: code → classId
      batch.set(_fs.collection('class_codes').doc(code), {
        'classId': classId,
        'teacherUid': myUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      Analytics.logFeatureAction('teacher_panel', 'class_created');
      return TeacherClass(
        id: classId,
        teacherUid: myUid,
        name: name,
        schoolName: schoolName,
        code: code,
        subject: subject,
        level: level,
        createdAt: DateTime.now(),
        gradingCountry: gradingCountry,
        gradingProfile: gradingProfile,
      );
    } catch (e) {
      debugPrint('[ClassService] createClass fail: $e');
      return null;
    }
  }

  /// Sınıfın not sistemi (müfredat) ülke kodunu döndürür — ebeveyn/öğrenci de
  /// notları AYNI skalada görsün diye. Boşsa ve çağıran sınıfın SAHİBİ öğretmense
  /// (kendi seçimi varsa) sınıfa geriye doldurur → eski sınıflar da düzelir.
  static Future<String> gradingCountryForClass(String classId) async {
    try {
      final doc = await _fs.collection('classes').doc(classId).get();
      final data = doc.data();
      final stored = (data?['gradingCountry'] ?? '').toString();
      if (stored.isNotEmpty) return stored;
      final myUid = _myUid;
      final ownerUid = (data?['teacherUid'] ?? '').toString();
      final mine = AccountService.instance.gradingCountry ?? '';
      if (myUid != null && myUid == ownerUid && mine.isNotEmpty) {
        await _fs
            .collection('classes')
            .doc(classId)
            .set({'gradingCountry': mine}, SetOptions(merge: true));
        return mine;
      }
      return '';
    } catch (e) {
      debugPrint('[ClassService] gradingCountryForClass fail: $e');
      return '';
    }
  }

  /// Sınıfın TAM not profili kimliğini döndürür (bkz. gradingCountryForClass) —
  /// gradingCountry tek başına aynı ülkedeki birden fazla profili (ör. US →
  /// 'us'/'gpa4') ayırt edemediği için ayrı saklanır.
  static Future<String> gradingProfileForClass(String classId) async {
    try {
      final doc = await _fs.collection('classes').doc(classId).get();
      final data = doc.data();
      final stored = (data?['gradingProfile'] ?? '').toString();
      if (stored.isNotEmpty) return stored;
      final myUid = _myUid;
      final ownerUid = (data?['teacherUid'] ?? '').toString();
      final mine = AccountService.instance.gradingProfile ?? '';
      if (myUid != null && myUid == ownerUid && mine.isNotEmpty) {
        await _fs
            .collection('classes')
            .doc(classId)
            .set({'gradingProfile': mine}, SetOptions(merge: true));
        return mine;
      }
      return '';
    } catch (e) {
      debugPrint('[ClassService] gradingProfileForClass fail: $e');
      return '';
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

  /// users/{uid} public profil önbelleği (uid → data) — aynı oturumda her
  /// öğrenci için profil bir kez okunur; sınıf listesi her snapshot'ta
  /// Firestore'u yeniden taramaz.
  static final _profileCache = <String, Map<String, dynamic>>{};

  /// [studentsStream] + her öğrencinin GÜNCEL public profili (users/{uid}).
  /// Sınıf dokümanındaki kopya katılım ANININ fotoğrafıdır; öğrenci daha
  /// sonra adını/fotoğrafını/seviyesini değiştirirse öğretmen yine profildeki
  /// güncel halini görsün diye canlı profille birleştirilir. Profil
  /// okunamazsa (offline vb.) katılım kopyası kullanılır.
  static Stream<List<ClassStudent>> studentsWithProfilesStream(
      String classId) {
    String pick(dynamic v, String fallback) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? fallback : s;
    }

    return studentsStream(classId).asyncMap((list) async {
      final out = <ClassStudent>[];
      for (final s in list) {
        Map<String, dynamic>? p = _profileCache[s.uid];
        if (p == null) {
          try {
            final doc = await _fs.collection('users').doc(s.uid).get();
            p = doc.data();
            if (p != null) _profileCache[s.uid] = p;
          } catch (_) {/* offline → kopyayla devam */}
        }
        if (p == null) {
          out.add(s);
          continue;
        }
        out.add(ClassStudent(
          uid: s.uid,
          username: pick(p['username'], s.username),
          displayName: pick(p['displayName'], s.displayName),
          avatar: pick(p['avatar'], s.avatar),
          joinedAt: s.joinedAt,
          teacherAlias: s.teacherAlias,
          // Foto/durum profilden gelir — profilde silinmişse boş görünür
          // (bayat kopya gösterilmez).
          avatarData: (p['avatarData'] ?? '').toString(),
          grade: pick(p['grade'], s.grade),
          country: pick(p['country'], s.country),
          statusMessage: (p['statusMessage'] ?? '').toString(),
        ));
      }
      return out;
    });
  }

  /// Bir sınıftaki öğrenci sayısı (canlı) — demo öğrenciler dahil tüm
  /// öğrenciler sayılır (demo öğrenciler bilinçli olarak ekleniyor ve sınıf
  /// listesinde göründüğünden rozet de onları yansıtır).
  static Stream<int> studentCountStream(String classId) {
    return _fs
        .collection('classes')
        .doc(classId)
        .collection('students')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// Öğretmen, bir öğrencinin sınıftaki görünen adını belirler (gerçek ad
  /// ya da lakap). Boş string verilirse öğretmen lakabı temizlenir ve öğrenci
  /// yeniden kendi adı/kullanıcı adıyla görünür. Firestore kuralları yalnızca
  /// sınıfın öğretmenine bu yazmayı izin verir.
  static Future<bool> setStudentAlias(
      String classId, String studentUid, String alias) async {
    if (_myUid == null) return false;
    try {
      await _fs
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentUid)
          .set({'teacherAlias': alias.trim()}, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[ClassService] setStudentAlias fail: $e');
      return false;
    }
  }

  /// Öğretmenin bir öğrenci hakkındaki notları (canlı, yeni → eski).
  /// [onlyShared] true → yalnızca ebeveynle paylaşılanlar (ebeveyn paneli).
  static Stream<List<StudentNote>> notesStream(
      String classId, String studentUid, {bool onlyShared = false}) {
    Query<Map<String, dynamic>> q = _fs
        .collection('classes')
        .doc(classId)
        .collection('students')
        .doc(studentUid)
        .collection('notes');
    if (onlyShared) {
      q = q.where('sharedWithParent', isEqualTo: true);
    }
    return q.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => StudentNote.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Yeni not ekler. [sharedWithParent] true → ebeveyn panelinde görünür.
  /// [kind] 'praise' → takdir/hızlı geri bildirim (her zaman paylaşılır).
  static Future<bool> addNote(
      String classId, String studentUid, String text,
      {bool sharedWithParent = false, String kind = 'note'}) async {
    if (_myUid == null) return false;
    try {
      await _fs
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentUid)
          .collection('notes')
          .add({
        'text': text.trim(),
        'sharedWithParent': sharedWithParent || kind == 'praise',
        'kind': kind,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[ClassService] addNote fail: $e');
      return false;
    }
  }

  /// Mevcut bir notu günceller (metin + paylaşım durumu).
  static Future<bool> updateNote(String classId, String studentUid,
      String noteId, String text, {bool? sharedWithParent}) async {
    if (_myUid == null) return false;
    try {
      await _fs
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentUid)
          .collection('notes')
          .doc(noteId)
          .set({
        'text': text.trim(),
        if (sharedWithParent != null) 'sharedWithParent': sharedWithParent,
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[ClassService] updateNote fail: $e');
      return false;
    }
  }

  /// Bir notu siler.
  static Future<bool> deleteNote(
      String classId, String studentUid, String noteId) async {
    if (_myUid == null) return false;
    try {
      await _fs
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentUid)
          .collection('notes')
          .doc(noteId)
          .delete();
      return true;
    } catch (e) {
      debugPrint('[ClassService] deleteNote fail: $e');
      return false;
    }
  }

  /// Öğrencinin yazılı/sözlü notları (canlı, tarihe göre yeni → eski).
  static Stream<List<StudentGrade>> gradesStream(
      String classId, String studentUid) {
    return _fs
        .collection('classes')
        .doc(classId)
        .collection('students')
        .doc(studentUid)
        .collection('grades')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => StudentGrade.fromMap(d.id, d.data()))
          .toList();
      // Önce dönem (artan), sonra tarih (yeni → eski).
      list.sort((a, b) {
        if (a.term != b.term) return a.term.compareTo(b.term);
        return b.date.compareTo(a.date);
      });
      return list;
    });
  }

  /// Yeni yazılı/sözlü notu ekler. Başarılıysa true.
  static Future<bool> addGrade(
      String classId, String studentUid, StudentGrade grade) async {
    if (_myUid == null) return false;
    try {
      await _fs
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentUid)
          .collection('grades')
          .add(grade.toMap());
      return true;
    } catch (e) {
      debugPrint('[ClassService] addGrade fail: $e');
      return false;
    }
  }

  /// Mevcut bir yazılı/sözlü notunu günceller (öğretmen düzenleyebilir).
  static Future<bool> updateGrade(
      String classId, String studentUid, StudentGrade grade) async {
    if (_myUid == null || grade.id.isEmpty) return false;
    try {
      await _fs
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentUid)
          .collection('grades')
          .doc(grade.id)
          .set({
        'type': grade.type,
        'order': grade.order,
        'term': grade.term,
        'score': grade.score,
        'date': Timestamp.fromDate(grade.date),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[ClassService] updateGrade fail: $e');
      return false;
    }
  }

  /// Bir notu siler.
  static Future<bool> deleteGrade(
      String classId, String studentUid, String gradeId) async {
    if (_myUid == null) return false;
    try {
      await _fs
          .collection('classes')
          .doc(classId)
          .collection('students')
          .doc(studentUid)
          .collection('grades')
          .doc(gradeId)
          .delete();
      return true;
    } catch (e) {
      debugPrint('[ClassService] deleteGrade fail: $e');
      return false;
    }
  }

  /// Sınıfın durum/duyuru mesajını tek seferlik okur (yoksa boş string).
  /// Ebeveyn paneli "Öğretmenden duyuru" şeridi için kullanır.
  static Future<String> classStatusMessage(String classId) async {
    try {
      final snap = await _fs.collection('classes').doc(classId).get();
      return (snap.data()?['statusMessage'] as String?)?.trim() ?? '';
    } catch (e) {
      debugPrint('[ClassService] classStatusMessage fail: $e');
      return '';
    }
  }

  /// Sınıf profilini günceller — fotoğraf (thumbnail base64) ve/veya durum
  /// mesajı. Yalnızca verilen alanlar yazılır. Firestore kuralları sınıf
  /// güncellemesini sadece öğretmene izin verir.
  static Future<bool> updateClassProfile(
    String classId, {
    String? photoB64,
    String? statusMessage,
  }) async {
    if (_myUid == null) return false;
    try {
      final data = <String, dynamic>{};
      if (photoB64 != null) data['photoB64'] = photoB64;
      if (statusMessage != null) data['statusMessage'] = statusMessage.trim();
      if (data.isEmpty) return true;
      await _fs
          .collection('classes')
          .doc(classId)
          .set(data, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[ClassService] updateClassProfile fail: $e');
      return false;
    }
  }

  /// Sınıfın adını değiştirir. Boş ad reddedilir.
  static Future<bool> renameClass(String classId, String newName) async {
    if (_myUid == null) return false;
    final name = newName.trim();
    if (name.isEmpty) return false;
    try {
      await _fs
          .collection('classes')
          .doc(classId)
          .set({'name': name}, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[ClassService] renameClass fail: $e');
      return false;
    }
  }

  /// Sınıf bilgilerini günceller: ad (name), okul/başlık (schoolName) ve
  /// durum mesajı (statusMessage). Yalnızca verilen alanlar yazılır.
  static Future<bool> updateClassInfo(
    String classId, {
    String? name,
    String? schoolName,
    String? statusMessage,
  }) async {
    if (_myUid == null) return false;
    try {
      final data = <String, dynamic>{};
      if (name != null && name.trim().isNotEmpty) data['name'] = name.trim();
      if (schoolName != null) data['schoolName'] = schoolName.trim();
      if (statusMessage != null) data['statusMessage'] = statusMessage.trim();
      if (data.isEmpty) return true;
      await _fs
          .collection('classes')
          .doc(classId)
          .set(data, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[ClassService] updateClassInfo fail: $e');
      return false;
    }
  }

  /// Öğrenciyi sınıftan çıkarır — öğrenci dökümanı + tüm ödev teslimleri +
  /// yazılı/sözlü notları + karne notları kalıcı silinir. Yetim veri kalmasın
  /// diye alt koleksiyonlar tek tek temizlenir. Sadece sınıf öğretmeni yapabilir.
  ///
  /// Not: Öğrencinin `users/{uid}/joined_classes/{classId}` kaydını öğretmen
  /// (kurallar gereği) silemez; o kayıt öğrenci tarafında, sınıf üyeliği
  /// bulunamayınca otomatik temizlenir.
  static Future<bool> removeStudent(String classId, String studentUid) async {
    if (_myUid == null) return false;
    try {
      final classRef = _fs.collection('classes').doc(classId);
      // 1) Her ödevdeki bu öğrencinin teslimi (yoksa no-op).
      final hwSnap = await classRef.collection('homeworks').get();
      for (final hw in hwSnap.docs) {
        await hw.reference.collection('submissions').doc(studentUid).delete();
      }
      // 2) Öğrencinin grades & notes alt koleksiyonları.
      final studRef = classRef.collection('students').doc(studentUid);
      await _deleteAllDocs(studRef.collection('grades'));
      await _deleteAllDocs(studRef.collection('notes'));
      // 3) Öğrenci dökümanı.
      await studRef.delete();
      return true;
    } catch (e) {
      debugPrint('[ClassService] removeStudent fail: $e');
      return false;
    }
  }

  /// Sınıf sil. Alt koleksiyonları (students, content, homeworks + her ödevin
  /// submissions'ı) da temizler — Firestore döküman silince alt koleksiyonu
  /// otomatik silmediği için aksi halde yetim veri kalırdı.
  ///
  /// Not: Öğrencilerin `users/{uid}/joined_classes/{classId}` kaydını öğretmen
  /// (kurallar gereği) silemez; o kayıt öğrenci tarafında, sınıf bulunamayınca
  /// otomatik temizlenir (bkz. [myJoinedClassesStream] self-heal).
  static Future<bool> deleteClass(String classId, String code) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      final classRef = _fs.collection('classes').doc(classId);

      // 1) Alt koleksiyonlar (sınıf dökümanı SİLİNMEDEN önce — silme kuralları
      //    teacherUid için class dökümanını okuduğundan hâlâ var olmalı).
      // Öğrencilerin grades/notes alt koleksiyonlarını da temizle; aksi halde
      // sınıf dökümanı silinince bu kayıtlar yetim kalır (kurallar classId'yi
      // okuyamayınca hem okunamaz hem silinemez hale gelir).
      final studSnap = await classRef.collection('students').get();
      for (final st in studSnap.docs) {
        await _deleteAllDocs(st.reference.collection('grades'));
        await _deleteAllDocs(st.reference.collection('notes'));
      }
      await _deleteAllDocs(classRef.collection('students'));
      await _deleteAllDocs(classRef.collection('content'));
      final hwSnap = await classRef.collection('homeworks').get();
      for (final hw in hwSnap.docs) {
        await _deleteAllDocs(hw.reference.collection('submissions'));
        await hw.reference.delete();
      }

      // 2) Sınıf dökümanı + kod reverse-index.
      final batch = _fs.batch();
      batch.delete(classRef);
      batch.delete(_fs.collection('class_codes').doc(code));
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[ClassService] deleteClass fail: $e');
      return false;
    }
  }

  /// Bir koleksiyondaki tüm dökümanları 400'lük partiler halinde siler
  /// (Firestore batch limiti 500).
  static Future<void> _deleteAllDocs(
      CollectionReference<Map<String, dynamic>> col) async {
    final snap = await col.get();
    if (snap.docs.isEmpty) return;
    var batch = _fs.batch();
    var n = 0;
    for (final d in snap.docs) {
      batch.delete(d.reference);
      if (++n == 400) {
        await batch.commit();
        batch = _fs.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  }

  // ── ÖĞRENCİ: Sınıfa katıl (kod ile) ─────────────────────────────────
  static Future<JoinClassResult> joinByCode(String rawCode) async {
    final myUid = _myUid;
    if (myUid == null) return JoinClassResult.notAuthed;
    // Girişi normalize et: boşlukları sil, "SINIF-" önekini (varsa) ayır →
    // 5 haneli çekirdek kodu elde et. Yeni kodlar 5 hanelidir; eski sınıflar
    // "SINIF-XXXXX" formatında saklanmış olabilir, ikisini de destekliyoruz.
    final raw = rawCode.trim().toUpperCase().replaceAll(' ', '');
    final core = raw.startsWith('SINIF-') ? raw.substring(6) : raw;
    if (!RegExp(r'^[A-Z0-9]{5}$').hasMatch(core)) {
      return JoinClassResult.invalidCode;
    }
    try {
      // Önce yeni format (5 hane), bulunamazsa eski format (SINIF-XXXXX).
      var codeDoc = await _fs.collection('class_codes').doc(core).get();
      if (!codeDoc.exists) {
        codeDoc = await _fs.collection('class_codes').doc('SINIF-$core').get();
      }
      if (!codeDoc.exists) return JoinClassResult.classNotFound;
      final classId = codeDoc.data()?['classId'] as String?;
      final teacherUid = codeDoc.data()?['teacherUid'] as String?;
      if (classId == null) return JoinClassResult.error;
      return _completeJoin(classId, teacherUid);
    } catch (e) {
      debugPrint('[ClassService] join fail: $e');
      return JoinClassResult.error;
    }
  }

  // ── ÖĞRENCİ: Daveti kabul et (classId ile doğrudan katıl) ────────────
  /// Öğretmen davetiyle gelen bildirimde "Katıl" → kod gerekmez.
  static Future<JoinClassResult> joinByClassId(String classId) async {
    try {
      final classDoc = await _fs.collection('classes').doc(classId).get();
      if (!classDoc.exists) return JoinClassResult.classNotFound;
      final teacherUid = classDoc.data()?['teacherUid'] as String?;
      return _completeJoin(classId, teacherUid);
    } catch (e) {
      debugPrint('[ClassService] joinByClassId fail: $e');
      return JoinClassResult.error;
    }
  }

  /// Ortak katılım mantığı — öğrenci KENDİNİ sınıfa ekler (rules: isOwner).
  static Future<JoinClassResult> _completeJoin(
      String classId, String? teacherUid) async {
    final myUid = _myUid;
    if (myUid == null) return JoinClassResult.notAuthed;
    if (teacherUid == myUid) return JoinClassResult.selfJoin;
    try {
      final existing = await _fs
          .collection('classes').doc(classId)
          .collection('students').doc(myUid)
          .get();
      if (existing.exists) return JoinClassResult.alreadyJoined;

      final myProfile = await _fs.collection('users').doc(myUid).get();
      final myData = myProfile.data() ?? const <String, dynamic>{};
      final classDoc = await _fs.collection('classes').doc(classId).get();
      final classData = classDoc.data() ?? const <String, dynamic>{};
      final teacherProfile = (teacherUid == null || teacherUid.isEmpty)
          ? null
          : await _fs.collection('users').doc(teacherUid).get();
      final teacherData = teacherProfile?.data() ?? const <String, dynamic>{};

      final batch = _fs.batch();
      final now = FieldValue.serverTimestamp();
      batch.set(
        _fs.collection('classes').doc(classId)
            .collection('students').doc(myUid),
        {
          'username': myData['username'] ?? '',
          'displayName': myData['displayName'] ?? '',
          'avatar': myData['avatar'] ?? '👤',
          // Profilin geri kalanı — öğretmen paneli öğrenciyi profilindeki
          // haliyle (foto, seviye, ülke, durum mesajı) görsün.
          'avatarData': myData['avatarData'] ?? '',
          'grade': myData['grade'] ?? '',
          'country': myData['country'] ?? '',
          'statusMessage': myData['statusMessage'] ?? '',
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
      // Sınıf öğretmenine "yeni öğrenci katıldı" bildirimi.
      if (teacherUid != null && teacherUid.isNotEmpty) {
        batch.set(
          _fs.collection('notifications').doc(teacherUid)
              .collection('items').doc(),
          {
            'type': 'student_joined',
            'fromDisplayName': myData['displayName'] ??
                myData['username'] ?? 'Bir öğrenci',
            'className': classData['name'] ?? '',
            'classId': classId,
            'when': now,
            'read': false,
          },
        );
      }
      await batch.commit();
      return JoinClassResult.success;
    } catch (e) {
      debugPrint('[ClassService] completeJoin fail: $e');
      return JoinClassResult.error;
    }
  }

  // ── ÖĞRETMEN: Öğrenci ara (username ön ekiyle) ───────────────────────
  /// users koleksiyonunda username prefix araması. Kendini ve öğretmenleri
  /// hariç tutar. Tek alanlı range — composite index gerekmez.
  static Future<List<StudentSearchResult>> searchStudents(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final myUid = _myUid;
    try {
      final snap = await _fs
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: q + String.fromCharCode(0xf8ff))
          .limit(20)
          .get();
      return snap.docs
          .where((d) => d.id != myUid)
          .map((d) {
            final m = d.data();
            return StudentSearchResult(
              uid: d.id,
              username: (m['username'] ?? '').toString(),
              displayName: (m['displayName'] ?? '').toString(),
              avatar: (m['avatar'] ?? '👤').toString(),
            );
          })
          .where((r) => r.username.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[ClassService] searchStudents fail: $e');
      return const [];
    }
  }

  // ── ÖĞRETMEN: Öğrenciyi sınıfa davet et (bildirimle) ─────────────────
  /// Öğrenciye 'class_invite' bildirimi yazar. Öğrenci bildirimden onaylar
  /// (joinByClassId) — students'a KENDİSİ yazar, böylece rules ihlal olmaz.
  static Future<bool> inviteStudent({
    required String classId,
    required String className,
    required String subject,
    required String studentUid,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      // Zaten sınıfta mı?
      final existing = await _fs.collection('classes').doc(classId)
          .collection('students').doc(studentUid).get();
      if (existing.exists) return false;

      final me = await _fs.collection('users').doc(myUid).get();
      final teacherName = (me.data()?['displayName'] ??
          me.data()?['username'] ?? 'Öğretmen').toString();

      await _fs.collection('notifications').doc(studentUid)
          .collection('items').doc().set({
        'type': 'class_invite',
        'classId': classId,
        'className': className,
        'subject': subject,
        'fromDisplayName': teacherName,
        'when': FieldValue.serverTimestamp(),
        'read': false,
      });
      return true;
    } catch (e) {
      debugPrint('[ClassService] inviteStudent fail: $e');
      return false;
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
        .asyncMap((snap) async {
          final raw = snap.docs
              .map((d) => JoinedClass.fromMap(d.id, d.data()))
              .toList();
          // Sınıfı silinmiş kayıtları ayıkla + kendi stale kaydını temizle.
          final list = await _filterAliveClasses(myUid, raw, heal: true);
          list.sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
          return list;
        });
  }

  /// joined_classes listesinden, `classes/{classId}` dökümanı artık VAR OLMAYAN
  /// (öğretmenin sildiği) kayıtları çıkarır. [heal] true ise — yalnız kendi
  /// kayıtlarımız için geçerli — stale kaydı sessizce siler (öğrenci kendi
  /// joined_classes'ının sahibi olduğu için bu silme kurallarca serbesttir).
  static Future<List<JoinedClass>> _filterAliveClasses(
      String uid, List<JoinedClass> items, {bool heal = false}) async {
    if (items.isEmpty) return items;
    final alive = <JoinedClass>[];
    for (final c in items) {
      try {
        final doc = await _fs.collection('classes').doc(c.classId).get();
        if (doc.exists) {
          alive.add(c);
        } else if (heal) {
          _fs
              .collection('users').doc(uid)
              .collection('joined_classes').doc(c.classId)
              .delete()
              .catchError((_) {});
        }
      } catch (_) {
        alive.add(c); // okuma hatasında kaydı KORU (yanlışlıkla gizleme yok)
      }
    }
    return alive;
  }

  /// Belirli bir kullanıcının (örn. bağlı çocuk) katıldığı sınıflar — ebeveyn
  /// panelinde çocuğun ödevlerini görmek için tek seferlik okuma.
  static Future<List<JoinedClass>> joinedClassesFor(String uid) async {
    if (uid.trim().isEmpty) return const <JoinedClass>[];
    try {
      final snap = await _fs
          .collection('users').doc(uid)
          .collection('joined_classes').get();
      final raw = snap.docs
          .map((d) => JoinedClass.fromMap(d.id, d.data()))
          .toList();
      // Silinmiş sınıfları gizle (heal yok — ebeveyn çocuğun kaydının sahibi değil).
      final list = await _filterAliveClasses(uid, raw, heal: false);
      list.sort((a, b) => b.joinedAt.compareTo(a.joinedAt));
      return list;
    } catch (e) {
      debugPrint('[ClassService] joinedClassesFor fail: $e');
      return const <JoinedClass>[];
    }
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

  // ── DUYURU YAYINLA (öğretmen → sınıf) ────────────────────────────────
  /// Öğretmen bir sınıfa duyuru gönderir:
  ///   1) Her öğrenciye 'class_announcement' bildirimi (push function yakalar)
  ///   2) Sınıf içerik akışına 'announcement' kaydı (kalıcı görünür)
  ///   3) Sınıf statusMessage'ı güncellenir (ebeveyn "Öğretmenden duyuru" şeridi)
  /// Dönüş: bildirim gönderilen öğrenci sayısı (hata → -1).
  static Future<int> publishAnnouncement({
    required String classId,
    required String className,
    required String subject,
    required String message,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return -1;
    final text = message.trim();
    if (text.isEmpty) return -1;
    try {
      final me = await _fs.collection('users').doc(myUid).get();
      final teacherName = (me.data()?['displayName'] ??
          me.data()?['username'] ?? 'Öğretmen').toString();

      // Öğrenci uid'leri
      final studSnap = await _fs.collection('classes').doc(classId)
          .collection('students').get();

      // Bildirimleri batch ile yaz (500 limitine takılmamak için parça parça).
      int sent = 0;
      var batch = _fs.batch();
      int ops = 0;
      for (final d in studSnap.docs) {
        final ref = _fs.collection('notifications').doc(d.id)
            .collection('items').doc();
        batch.set(ref, {
          'type': 'class_announcement',
          'classId': classId,
          'className': className,
          'message': text,
          'fromDisplayName': teacherName,
          'when': FieldValue.serverTimestamp(),
          'read': false,
        });
        sent++;
        if (++ops >= 400) {
          await batch.commit();
          batch = _fs.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();

      // İçerik akışına kalıcı duyuru kaydı.
      await _fs.collection('classes').doc(classId)
          .collection('content').doc().set({
        'teacherUid': myUid,
        'type': 'announcement',
        'title': 'Duyuru',
        'topic': '',
        'subject': subject,
        'payload': {'message': text, 'teacherName': teacherName},
        'sharedAt': FieldValue.serverTimestamp(),
      });

      // Ebeveyn şeridi için son duyuruyu sınıf dokümanına yansıt.
      try {
        await _fs.collection('classes').doc(classId).set({
          'statusMessage': text,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      return sent;
    } catch (e) {
      debugPrint('[ClassService] publishAnnouncement fail: $e');
      return -1;
    }
  }

  /// Duyuruyu ileri tarihe ZAMANLAR. Anında bildirim göndermez; yalnızca
  /// classes/{id}/scheduled_announcements altına bekleyen kayıt düşer.
  /// Yayın anı gelince publishScheduledAnnouncements function gerçek dağıtımı
  /// (öğrenci bildirimi + içerik akışı + ebeveyn şeridi) yapar.
  /// Dönen: hedef öğrenci sayısı (tahmini), hata durumunda -1.
  static Future<int> scheduleAnnouncement({
    required String classId,
    required String className,
    required String subject,
    required String message,
    required DateTime publishAt,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return -1;
    final text = message.trim();
    if (text.isEmpty) return -1;
    try {
      final me = await _fs.collection('users').doc(myUid).get();
      final teacherName = (me.data()?['displayName'] ??
          me.data()?['username'] ?? 'Öğretmen').toString();

      final studSnap = await _fs.collection('classes').doc(classId)
          .collection('students').get();

      await _fs.collection('classes').doc(classId)
          .collection('scheduled_announcements').doc().set({
        'teacherUid': myUid,
        'className': className,
        'subject': subject,
        'message': text,
        'teacherName': teacherName,
        'publishAt': Timestamp.fromDate(publishAt),
        'announceNotified': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return studSnap.docs.length;
    } catch (e) {
      debugPrint('[ClassService] scheduleAnnouncement fail: $e');
      return -1;
    }
  }

  // ── KAYNAK/MATERYAL PAYLAŞ (öğretmen → sınıf) ────────────────────────
  /// Yapay zeka dışı hazır kaynak paylaşımı: web linki, PDF (yüklü dosya ya
  /// da link) veya ders notu. Sınıf içerik akışına 'material' tipinde yazılır.
  ///   kind: 'link' | 'pdf' | 'note'
  static Future<bool> shareMaterial({
    required String classId,
    required String subject,
    required String kind,
    required String title,
    String url = '',
    String note = '',
    String fileName = '',
  }) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    if (title.trim().isEmpty) return false;
    try {
      await _fs.collection('classes').doc(classId)
          .collection('content').doc().set({
        'teacherUid': myUid,
        'type': 'material',
        'title': title.trim(),
        'topic': kind,
        'subject': subject,
        'payload': {
          'kind': kind,
          if (url.trim().isNotEmpty) 'url': url.trim(),
          if (note.trim().isNotEmpty) 'note': note.trim(),
          if (fileName.trim().isNotEmpty) 'fileName': fileName.trim(),
        },
        'sharedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[ClassService] shareMaterial fail: $e');
      return false;
    }
  }

  /// Sınıf içerik akışından bir kaydı (kaynak/duyuru) siler. Yalnızca sınıf
  /// öğretmeni yazabilir (firestore.rules). Dönen: silindi mi.
  static Future<bool> deleteContent({
    required String classId,
    required String contentId,
  }) async {
    if (_myUid == null) return false;
    try {
      await _fs.collection('classes').doc(classId)
          .collection('content').doc(contentId).delete();
      return true;
    } catch (e) {
      debugPrint('[ClassService] deleteContent fail: $e');
      return false;
    }
  }

  /// Öğretmenin seçtiği PDF dosyasını Firebase Storage'a yükler ve indirme
  /// URL'ini döndürür. Yol: class_materials/{classId}/{ts}_{ad}.pdf
  /// Yalnızca sınıfın öğretmeni yazabilir (storage.rules), max 25 MB.
  ///
  /// Dönüş: (url, error). Başarıda url dolu/error null; hatada url null ve
  /// error kullanıcıya gösterilebilecek kısa bir neden (ör. 'unauthorized',
  /// 'object-not-found' → Storage henüz kurulmamış/kural deploy edilmemiş).
  static Future<({String? url, String? error})> uploadClassPdf({
    required String classId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return (url: null, error: 'oturum-yok');
    try {
      final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref('class_materials/$classId/${ts}_$safe');
      final task = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final url = await task.ref.getDownloadURL();
      return (url: url, error: null);
    } on FirebaseException catch (e) {
      // En sık: 'unauthorized' (kural deploy değil) / 'object-not-found' veya
      // 'unknown' (Storage konsolda hiç etkinleştirilmemiş → bucket yok).
      debugPrint('[ClassService] uploadClassPdf FirebaseException: '
          '${e.code} | ${e.message}');
      return (url: null, error: e.code);
    } catch (e) {
      debugPrint('[ClassService] uploadClassPdf fail: $e');
      return (url: null, error: e.toString());
    }
  }
}
