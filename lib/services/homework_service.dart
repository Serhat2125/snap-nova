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
import 'ai_provider_service.dart';

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
    List<Map<String, dynamic>> answers = const [],
    DateTime? startedAt,
    int? activeMs,
    int? passiveMs,
  }) async {
    final myUid = _myUid;
    if (myUid == null) return false;
    // Not: açık uçlu sorular öğretmen puanlayana kadar correct/wrong'a
    // KATILMAZ — bu yüzden score "ön skor"dur, puanlama sonrası güncellenir.
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
        if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt),
        if (activeMs != null) 'activeMs': activeMs,
        if (passiveMs != null) 'passiveMs': passiveMs,
        if (answers.isNotEmpty) 'answers': answers,
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[HomeworkService] submit fail: $e');
      return false;
    }
  }

  /// ÖĞRETMEN: açık uçlu cevapları manuel puanlar.
  /// [grades]: soru index → doğru (true) / yanlış (false).
  /// Submission'ın answers'ını güncelleyip correct/wrong/score'u yeniden hesaplar
  /// (artık otomatik + öğretmen puanları birlikte).
  static Future<bool> gradeOpenAnswers({
    required String classId,
    required String homeworkId,
    required String studentUid,
    required Map<int, bool> grades,
  }) async {
    try {
      final ref = _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(homeworkId)
          .collection('submissions').doc(studentUid);
      final snap = await ref.get();
      final data = snap.data();
      if (data == null) return false;
      final answers = ((data['answers'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      for (final a in answers) {
        final idx = (a['index'] ?? -1) as int;
        if (grades.containsKey(idx)) a['isCorrect'] = grades[idx];
      }
      int correct = 0;
      int wrong = 0;
      for (final a in answers) {
        if (a['isCorrect'] == true) {
          correct++;
        } else if (a['isCorrect'] == false) {
          wrong++;
        }
      }
      final total = correct + wrong;
      final score = total > 0 ? correct * 100.0 / total : 0.0;
      await ref.set({
        'answers': answers,
        'correct': correct,
        'wrong': wrong,
        'scorePercent': score,
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[HomeworkService] gradeOpenAnswers fail: $e');
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

  // ── AI: Teslim performans yorumu ────────────────────────────────────────
  /// Bir teslim için kısa (1-2 cümle) Türkçe performans yorumu döner.
  /// İlk üretimde Firestore'a `aiComment` olarak cache'lenir; sonraki
  /// açılışlarda doğrudan cache'ten döner (tekrar AI çağrısı yok).
  static Future<String?> ensureSubmissionComment({
    required String classId,
    required String homeworkId,
    required String studentUid,
    required String studentName,
    required String homeworkTitle,
    required String subject,
    required String topic,
    required int correct,
    required int wrong,
    required int blank,
    Duration? active,
    Duration? passive,
    String? cached,
  }) async {
    if (cached != null && cached.trim().isNotEmpty) return cached;
    final total = correct + wrong + blank;
    if (total == 0) return null;
    final pct = (correct + wrong) > 0
        ? (correct * 100 / (correct + wrong)).round()
        : 0;
    String fmt(Duration? d) {
      if (d == null) return 'bilinmiyor';
      if (d.inMinutes < 1) return '${d.inSeconds} sn';
      return '${d.inMinutes} dk';
    }

    final prompt =
        '$studentName adlı öğrenci "$homeworkTitle" ödevini ($subject · $topic) '
        'çözdü. Sonuç: $correct doğru, $wrong yanlış, $blank boş (toplam $total '
        'soru, başarı %$pct). Ekran önünde aktif ${fmt(active)}, dışarıda pasif '
        '${fmt(passive)} geçirdi. Bu öğrencinin bu ödevdeki performansını '
        'öğretmenine 1-2 kısa cümleyle, yapıcı ve net biçimde özetle. '
        'Sadece yorumu yaz, başlık veya madde ekleme.';
    try {
      final txt = await AiProviderService.ask(
        prompt: prompt,
        system: 'Sen deneyimli bir eğitim koçusun. Türkçe, kısa ve yapıcı '
            'geri bildirim verirsin.',
        maxTokens: 160,
      );
      final comment = txt.trim();
      if (comment.isEmpty) return null;
      await _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(homeworkId)
          .collection('submissions').doc(studentUid)
          .set({'aiComment': comment}, SetOptions(merge: true));
      return comment;
    } catch (e) {
      debugPrint('[HomeworkService] aiComment fail: $e');
      return null;
    }
  }

  // ── ANALİTİK: Öğrenci karnesi (drill-down) ──────────────────────────────
  /// Bir öğrencinin sınıftaki TÜM ödevlerdeki sonuçlarını toplar.
  /// Her ödev için (varsa) o öğrencinin submission'ı eşlenir.
  /// assignedAt'e göre yeniden→eskiye sıralı döner.
  static Future<List<StudentReportEntry>> studentReport(
      String classId, String studentUid) async {
    try {
      final hwSnap = await _fs.collection('classes').doc(classId)
          .collection('homeworks').get();
      final homeworks = hwSnap.docs.map(HomeworkModel.fromDoc).toList()
        ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
      final out = <StudentReportEntry>[];
      for (final hw in homeworks) {
        final subDoc = await _fs.collection('classes').doc(classId)
            .collection('homeworks').doc(hw.id)
            .collection('submissions').doc(studentUid).get();
        HomeworkSubmissionModel? sub;
        if (subDoc.exists && subDoc.data() != null) {
          sub = HomeworkSubmissionModel.fromMap(subDoc.data()!);
        }
        out.add(StudentReportEntry(homework: hw, submission: sub));
      }
      return out;
    } catch (e) {
      debugPrint('[HomeworkService] studentReport fail: $e');
      return const [];
    }
  }

  // ── ANALİTİK: Sınıf-geneli rapor ────────────────────────────────────────
  /// Sınıfın tüm ödev + submission'larını tarayıp özet çıkarır:
  /// teslim oranı, sınıf ortalaması, en zor konular, öğrenci sıralaması.
  static Future<ClassReport> classReport(String classId) async {
    try {
      final hwSnap = await _fs.collection('classes').doc(classId)
          .collection('homeworks').get();
      final homeworks = hwSnap.docs.map(HomeworkModel.fromDoc).toList();

      final students = <String, _StudentAgg>{};
      final topics = <TopicDifficulty>[];
      int totalExpected = 0;
      int totalSubmitted = 0;
      final classScores = <double>[];

      for (final hw in homeworks) {
        final subs = await _fs.collection('classes').doc(classId)
            .collection('homeworks').doc(hw.id)
            .collection('submissions').get();
        final topicScores = <double>[];
        for (final sd in subs.docs) {
          final sub = HomeworkSubmissionModel.fromMap(sd.data());
          totalExpected++;
          final agg = students.putIfAbsent(sub.studentUid,
              () => _StudentAgg(
                    uid: sub.studentUid,
                    name: sub.studentDisplayName.isEmpty
                        ? '@${sub.studentUsername}'
                        : sub.studentDisplayName,
                  ));
          agg.assigned++;
          if (sub.isSubmitted) {
            totalSubmitted++;
            agg.submitted++;
            if (sub.scorePercent != null) {
              agg.scores.add(sub.scorePercent!);
              classScores.add(sub.scorePercent!);
              topicScores.add(sub.scorePercent!);
            }
          }
        }
        if (topicScores.isNotEmpty) {
          topics.add(TopicDifficulty(
            subject: hw.subject,
            topic: hw.topic,
            avgScore: topicScores.reduce((a, b) => a + b) / topicScores.length,
            sampleCount: topicScores.length,
          ));
        }
      }

      final standings = students.values
          .map((a) => StudentStanding(
                uid: a.uid,
                name: a.name,
                avgScore: a.scores.isEmpty
                    ? null
                    : a.scores.reduce((x, y) => x + y) / a.scores.length,
                submitted: a.submitted,
                assigned: a.assigned,
              ))
          .toList()
        ..sort((a, b) => (b.avgScore ?? -1).compareTo(a.avgScore ?? -1));

      topics.sort((a, b) => a.avgScore.compareTo(b.avgScore)); // en zor başta

      return ClassReport(
        homeworkCount: homeworks.length,
        studentCount: students.length,
        avgScore: classScores.isEmpty
            ? null
            : classScores.reduce((a, b) => a + b) / classScores.length,
        submissionRate:
            totalExpected == 0 ? 0 : totalSubmitted / totalExpected,
        hardestTopics: topics,
        standings: standings,
      );
    } catch (e) {
      debugPrint('[HomeworkService] classReport fail: $e');
      return const ClassReport(
        homeworkCount: 0, studentCount: 0, avgScore: null,
        submissionRate: 0, hardestTopics: [], standings: [],
      );
    }
  }
}

// ─── Analitik veri modelleri ───────────────────────────────────────────────

/// Bir öğrencinin tek bir ödevdeki durumu (karne satırı).
class StudentReportEntry {
  final HomeworkModel homework;
  final HomeworkSubmissionModel? submission;
  const StudentReportEntry({required this.homework, this.submission});

  bool get isDone => submission?.isSubmitted ?? false;
}

/// Bir konunun (ders·konu) sınıftaki zorluk göstergesi.
class TopicDifficulty {
  final String subject;
  final String topic;
  final double avgScore;   // teslim edilen submission'ların ortalama %'si
  final int sampleCount;   // kaç teslim üzerinden
  const TopicDifficulty({
    required this.subject,
    required this.topic,
    required this.avgScore,
    required this.sampleCount,
  });
}

/// Sınıf sıralamasında bir öğrenci.
class StudentStanding {
  final String uid;
  final String name;
  final double? avgScore;  // teslim ettiği ödevlerin ortalaması (yoksa null)
  final int submitted;
  final int assigned;
  const StudentStanding({
    required this.uid,
    required this.name,
    required this.avgScore,
    required this.submitted,
    required this.assigned,
  });

  /// Risk altındaki öğrenci: ortalaması düşük veya teslim oranı zayıf.
  bool get isAtRisk {
    final lowScore = avgScore != null && avgScore! < 50;
    final lowSubmit = assigned > 0 && submitted / assigned < 0.5;
    return lowScore || lowSubmit;
  }
}

/// Sınıf-geneli analitik özeti.
class ClassReport {
  final int homeworkCount;
  final int studentCount;
  final double? avgScore;       // sınıf ortalaması (teslim edilenler)
  final double submissionRate;  // 0..1
  final List<TopicDifficulty> hardestTopics; // en zor başta
  final List<StudentStanding> standings;     // en başarılı başta
  const ClassReport({
    required this.homeworkCount,
    required this.studentCount,
    required this.avgScore,
    required this.submissionRate,
    required this.hardestTopics,
    required this.standings,
  });

  List<StudentStanding> get atRiskStudents =>
      standings.where((s) => s.isAtRisk).toList();
}

/// Sınıf raporu hesaplaması için geçici öğrenci toplayıcı (internal).
class _StudentAgg {
  final String uid;
  final String name;
  final List<double> scores = [];
  int submitted = 0;
  int assigned = 0;
  _StudentAgg({required this.uid, required this.name});
}
