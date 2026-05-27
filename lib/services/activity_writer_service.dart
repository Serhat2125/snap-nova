// ═══════════════════════════════════════════════════════════════════════════
//  ActivityWriterService — Kullanıcının günlük aktivitelerini Firestore'a
//  yazar. Ebeveyn dashboard'unun veri kaynağı.
//
//  Yol: users/{uid}/activity/{yyyy-MM-dd}
//
//  Şema (atomic increment'lerle güncelleniyor):
//    {
//      "dateKey": "2026-05-23",
//      "focusSeconds": 4500,
//      "subjectDurations": { "Matematik": 1800, "Fizik": 2700 },
//      "summariesCreated": 3,
//      "photoQuestionsSolved": 7,
//      "testsSolved": 2,
//      "correctAnswers": 14,
//      "wrongAnswers": 4,
//      "blankAnswers": 2,
//      "successPercent": 78.0,
//      "lastUpdate": Timestamp,
//    }
//
//  Çağrı noktaları (uygulamadaki olaylar):
//    • Pomodoro fazı bittiğinde       → recordFocus(seconds, subject)
//    • Konu özeti oluşturulduğunda   → recordSummaryCreated()
//    • Fotoğraf-soru çözüldüğünde    → recordPhotoQuestion(subject)
//    • Test tamamlandığında          → recordTestCompleted(correct, wrong, blank)
//
//  Tüm yazımlar `FieldValue.increment` ile atomic → race condition yok.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ActivityWriterService {
  ActivityWriterService._();
  static final _fs = FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static DocumentReference<Map<String, dynamic>>? _todayDoc() {
    final uid = _uid;
    if (uid == null) return null;
    return _fs
        .collection('users')
        .doc(uid)
        .collection('activity')
        .doc(_todayKey());
  }

  /// Pomodoro fazı bittiğinde çağrılır. `seconds` faz süresi (saniye),
  /// `subject` çalışılan ders adı (varsa).
  static Future<void> recordFocus(int seconds, [String? subject]) async {
    final doc = _todayDoc();
    if (doc == null || seconds <= 0) return;
    try {
      final update = <String, dynamic>{
        'dateKey': _todayKey(),
        'focusSeconds': FieldValue.increment(seconds),
        'lastUpdate': FieldValue.serverTimestamp(),
      };
      if (subject != null && subject.trim().isNotEmpty) {
        update['subjectDurations.${subject.trim()}'] =
            FieldValue.increment(seconds);
      }
      await doc.set(update, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ActivityWriter] focus fail: $e');
    }
  }

  /// Konu özeti üretildiğinde çağrılır.
  static Future<void> recordSummaryCreated([String? subject]) async {
    final doc = _todayDoc();
    if (doc == null) return;
    try {
      final update = <String, dynamic>{
        'dateKey': _todayKey(),
        'summariesCreated': FieldValue.increment(1),
        'lastUpdate': FieldValue.serverTimestamp(),
      };
      if (subject != null && subject.trim().isNotEmpty) {
        update['summariesBySubject.${subject.trim()}'] =
            FieldValue.increment(1);
      }
      await doc.set(update, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ActivityWriter] summary fail: $e');
    }
  }

  /// Fotoğraftan bir soru çözüldüğünde.
  static Future<void> recordPhotoQuestion([String? subject]) async {
    final doc = _todayDoc();
    if (doc == null) return;
    try {
      final update = <String, dynamic>{
        'dateKey': _todayKey(),
        'photoQuestionsSolved': FieldValue.increment(1),
        'lastUpdate': FieldValue.serverTimestamp(),
      };
      if (subject != null && subject.trim().isNotEmpty) {
        update['photoBySubject.${subject.trim()}'] =
            FieldValue.increment(1);
      }
      await doc.set(update, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[ActivityWriter] photo fail: $e');
    }
  }

  /// Test tamamlandığında — doğru/yanlış/boş sayılarını ekler ve
  /// rolling success percent'i günceller.
  static Future<void> recordTestCompleted({
    required int correct,
    required int wrong,
    required int blank,
    String? subject,
  }) async {
    final doc = _todayDoc();
    if (doc == null) return;
    try {
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(doc);
        final current = snap.data() ?? const <String, dynamic>{};
        final c0 = (current['correctAnswers'] as num?)?.toInt() ?? 0;
        final w0 = (current['wrongAnswers'] as num?)?.toInt() ?? 0;
        final b0 = (current['blankAnswers'] as num?)?.toInt() ?? 0;
        final t0 = (current['testsSolved'] as num?)?.toInt() ?? 0;
        final newCorrect = c0 + correct;
        final newWrong = w0 + wrong;
        final newBlank = b0 + blank;
        final totalAnswered = newCorrect + newWrong;
        final successPercent = totalAnswered > 0
            ? (newCorrect * 100.0 / totalAnswered)
            : 0.0;
        tx.set(doc, {
          'dateKey': _todayKey(),
          'testsSolved': t0 + 1,
          'correctAnswers': newCorrect,
          'wrongAnswers': newWrong,
          'blankAnswers': newBlank,
          'successPercent': successPercent,
          if (subject != null && subject.trim().isNotEmpty)
            'subjectScores.${subject.trim()}': successPercent,
          'lastUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('[ActivityWriter] test fail: $e');
    }
  }
}
