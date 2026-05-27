// ═══════════════════════════════════════════════════════════════════════════
//  HomeworkService — Öğretmen ödev oluşturma + sınıfa dağıtım + auto-reminder.
//
//  Akış:
//    1) Öğretmen ödev parametrelerini seçer (ders/konu/soru tipi/sayı/bitiş)
//    2) GeminiService.generateHomeworkBatch() → AI soruları üretir
//    3) HomeworkService.assignToClass() → Firestore'a yazar
//    4) Auto-reminder: bitiş saatine 2 saat kala submission'ı olmayanlara
//       Firestore'da notification doc'u oluşturur — PushService (FCM) yakalar.
//
//  Auto-reminder business logic:
//    - Periyodik (her 30 dk) checkPendingReminders() çağrılır
//    - dueAt - now <= 2h ve reminderSent=false ödevler için trigger
//    - Submission'ı pending olan öğrencilere notification doc'u yazılır
//    - HomeworkModel.reminderSent = true (idempotency)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/education_models.dart';

class HomeworkService {
  HomeworkService._();
  static final _fs = FirebaseFirestore.instance;
  static String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  // ── ÖĞRETMEN: Ödev oluştur ──────────────────────────────────────────────
  /// Sınıfa AI ile üretilmiş ödev gönderir.
  /// `questions` AI tarafından üretilmiş soru listesi.
  /// Submission slots tüm öğrenciler için 'pending' olarak otomatik açılır.
  static Future<String?> assignToClass({
    required String classId,
    required String title,
    required String subject,
    required String topic,
    required String level,
    required List<HomeworkQuestionType> types,
    required int questionCount,
    required DateTime dueAt,
    required List<Map<String, dynamic>> questions,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return null;
    try {
      final hwRef = _fs.collection('classes').doc(classId)
          .collection('homeworks').doc();
      final hw = HomeworkModel(
        id: hwRef.id,
        classId: classId,
        teacherUid: myUid,
        title: title,
        subject: subject,
        topic: topic,
        level: level,
        types: types,
        questionCount: questionCount,
        assignedAt: DateTime.now(),
        dueAt: dueAt,
        questions: questions,
      );
      // Ödev doc'u
      await hwRef.set(hw.toJson()..['assignedAt'] = FieldValue.serverTimestamp());

      // Tüm sınıf öğrencileri için pending submission slot'ları aç.
      // (Öğrenci ödeve tıklayınca status → in_progress)
      final students = await _fs.collection('classes').doc(classId)
          .collection('students').get();
      final batch = _fs.batch();
      for (final s in students.docs) {
        final sd = s.data();
        batch.set(
          hwRef.collection('submissions').doc(s.id),
          HomeworkSubmissionModel(
            studentUid: s.id,
            studentUsername: (sd['username'] ?? '').toString(),
            studentDisplayName: (sd['displayName'] ?? '').toString(),
            status: 'pending',
          ).toJson(),
        );
        // Yeni ödev bildirimi (push trigger)
        batch.set(
          _fs.collection('notifications').doc(s.id)
              .collection('items').doc(),
          {
            'type': 'homework_assigned',
            'fromUsername': 'Öğretmen',
            'fromDisplayName': title,
            'when': FieldValue.serverTimestamp(),
            'read': false,
            'classId': classId,
            'homeworkId': hwRef.id,
            'dueAt': Timestamp.fromDate(dueAt),
          },
        );
      }
      await batch.commit();
      return hwRef.id;
    } catch (e) {
      debugPrint('[HomeworkService] assign fail: $e');
      return null;
    }
  }

  /// Sınıfın aktif ödevlerini stream — öğretmen dashboard için.
  static Stream<List<HomeworkModel>> classHomeworksStream(String classId) {
    return _fs.collection('classes').doc(classId)
        .collection('homeworks')
        .orderBy('assignedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(HomeworkModel.fromDoc).toList());
  }

  /// Belirli bir ödevin tüm submission'ları stream.
  static Stream<List<HomeworkSubmissionModel>> submissionsStream(
      String classId, String homeworkId) {
    return _fs.collection('classes').doc(classId)
        .collection('homeworks').doc(homeworkId)
        .collection('submissions')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => HomeworkSubmissionModel.fromMap(d.data()))
            .toList());
  }

  // ── ÖĞRENCİ TARAFI ──────────────────────────────────────────────────────
  /// Öğrenci sınıftaki ödeve tıklayınca status → 'in_progress'.
  static Future<bool> markInProgress(String classId, String homeworkId) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    try {
      await _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(homeworkId)
          .collection('submissions').doc(myUid)
          .set({'status': 'in_progress',
                'startedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
      return true;
    } catch (_) { return false; }
  }

  /// Öğrenci ödevi tamamladığında çağrılır.
  static Future<bool> submitAnswers({
    required String classId,
    required String homeworkId,
    required int correct,
    required int wrong,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    final total = correct + wrong;
    final score = total > 0 ? (correct * 100.0 / total) : 0.0;
    final now = DateTime.now();
    try {
      // Geç teslim mi?
      final hwDoc = await _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(homeworkId).get();
      final dueRaw = hwDoc.data()?['dueAt'];
      final due = dueRaw is Timestamp ? dueRaw.toDate() : DateTime.now();
      final status = now.isAfter(due) ? 'late' : 'submitted';
      await _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(homeworkId)
          .collection('submissions').doc(myUid)
          .set({
        'correct': correct,
        'wrong': wrong,
        'scorePercent': score,
        'status': status,
        'submittedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[HomeworkService] submit fail: $e');
      return false;
    }
  }

  // ── AUTO-REMINDER BUSINESS LOGIC ───────────────────────────────────────
  /// Periyodik olarak (örn her 30 dk) çağrılır — bitiş saatine ≤ 2 saat
  /// kalmış ödevler için pending submission'ı olan öğrencilere bildirim.
  /// Idempotent: reminderSent=true ödevler atlanır.
  ///
  /// Production'da bu Cloud Function'a taşınmalı (scheduler trigger).
  /// MVP: app açıkken öğretmen dashboard'ında 30dk timer'la çalışır.
  static Future<int> checkPendingReminders() async {
    final myUid = _myUid;
    if (myUid == null) return 0;
    int triggered = 0;
    try {
      // Öğretmenin tüm sınıfları
      final classes = await _fs.collection('classes')
          .where('teacherUid', isEqualTo: myUid).get();
      final now = DateTime.now();
      final twoHoursFromNow = now.add(const Duration(hours: 2));

      for (final cls in classes.docs) {
        // Aktif ödevler: dueAt > now (henüz geçmedi) ve dueAt <= now+2h
        final hwQuery = await cls.reference
            .collection('homeworks')
            .where('reminderSent', isEqualTo: false)
            .get();
        for (final hwDoc in hwQuery.docs) {
          final hw = HomeworkModel.fromDoc(hwDoc);
          if (hw.dueAt.isBefore(now)) continue; // geçmiş ödev
          if (hw.dueAt.isAfter(twoHoursFromNow)) continue; // henüz vakit var

          // Pending submission'ları bul
          final pending = await hwDoc.reference.collection('submissions')
              .where('status', isEqualTo: 'pending').get();
          final batch = _fs.batch();
          for (final sub in pending.docs) {
            batch.set(
              _fs.collection('notifications').doc(sub.id)
                  .collection('items').doc(),
              {
                'type': 'homework_reminder',
                'fromUsername': 'Öğretmen',
                'fromDisplayName':
                    '${hw.title} — 2 saatten az kaldı',
                'when': FieldValue.serverTimestamp(),
                'read': false,
                'classId': cls.id,
                'homeworkId': hw.id,
                'dueAt': Timestamp.fromDate(hw.dueAt),
              },
            );
            triggered++;
          }
          // Idempotency işareti
          batch.update(hwDoc.reference, {'reminderSent': true});
          await batch.commit();
        }
      }
    } catch (e) {
      debugPrint('[HomeworkService] reminders fail: $e');
    }
    return triggered;
  }

  /// Öğretmen dashboard açıldığında reminder timer başlatır.
  /// 30 dakikada bir checkPendingReminders çağırır.
  /// Dashboard kapanınca cancel edilmeli.
  static Timer? _reminderTimer;
  static void startReminderTimer() {
    _reminderTimer?.cancel();
    // İlk anda bir kez çalıştır
    unawaited(checkPendingReminders());
    _reminderTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(checkPendingReminders()),
    );
  }

  static void stopReminderTimer() {
    _reminderTimer?.cancel();
    _reminderTimer = null;
  }
}
