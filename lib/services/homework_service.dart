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
import 'analytics.dart';

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
    DateTime? publishAt,
    bool draft = false, // true → taslak: atanmaz, öğrenciye görünmez
    // Ödevin başında öğrenciye görünen öğretmen mesajı (isteğe bağlı).
    String teacherNote = '',
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
        publishAt: publishAt,
        questions: questions,
        teacherNote: teacherNote.trim(),
        status: draft ? 'draft' : 'published',
      );
      // Ödev doc'u
      await hwRef.set(hw.toJson()..['assignedAt'] = FieldValue.serverTimestamp());

      // Taslak: submission slot'ları ve bildirim YOK — öğretmen onayını bekler.
      if (!draft) {
        await _materializeAssignment(
          classId: classId, hwId: hwRef.id, title: title, dueAt: dueAt,
          publishAt: publishAt,
        );
        // Öğretmene "ödev yayınlandı" geri bildirimi (hemen yayınlandıysa).
        final publishedNow =
            publishAt == null || !publishAt.isAfter(DateTime.now());
        if (publishedNow) {
          try {
            final cls = await _fs.collection('classes').doc(classId).get();
            final className = (cls.data()?['name'] ?? '').toString();
            await _fs.collection('notifications').doc(myUid)
                .collection('items').doc().set({
              'type': 'homework_published',
              'homeworkTitle': title,
              'className': className,
              'classId': classId,
              'homeworkId': hwRef.id,
              'when': FieldValue.serverTimestamp(),
              'read': false,
            });
          } catch (_) {}
        }
      }
      Analytics.logFeatureAction(
          'teacher_panel', draft ? 'homework_draft_saved' : 'homework_assigned');
      return hwRef.id;
    } catch (e) {
      debugPrint('[HomeworkService] assign fail: $e');
      return null;
    }
  }

  /// Atanmış ödev için öğrenci submission slot'larını açar ve (yayındaysa)
  /// bildirim gönderir. assignToClass ve publishDraft ortak kullanır.
  static Future<void> _materializeAssignment({
    required String classId,
    required String hwId,
    required String title,
    required DateTime dueAt,
    DateTime? publishAt,
  }) async {
    // Yayın zamanı gelecekteyse ödev gizli atanır; öğrenciye o ana kadar
    // bildirim de gitmez (öğrenci listesi publishAt'a göre filtreler;
    // yayın anı bildirimi scheduled function ile gönderilir).
    final publishedNow =
        publishAt == null || !publishAt.isAfter(DateTime.now());
    final hwRef = _fs.collection('classes').doc(classId)
        .collection('homeworks').doc(hwId);
    final students = await _fs.collection('classes').doc(classId)
        .collection('students').get();
    final batch = _fs.batch();
    for (final s in students.docs) {
      final sd = s.data();
      // Onay bekleyen (pending) öğrenci ödev almaz — öğretmen onaylayınca
      // ClassService.approveStudent mevcut ödevlerin slotlarını açar.
      if ((sd['status'] ?? 'active').toString() == 'pending') continue;
      batch.set(
        hwRef.collection('submissions').doc(s.id),
        HomeworkSubmissionModel(
          studentUid: s.id,
          studentUsername: (sd['username'] ?? '').toString(),
          studentDisplayName: (sd['displayName'] ?? '').toString(),
          status: 'pending',
        ).toJson(),
        SetOptions(merge: true),
      );
      if (publishedNow) {
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
            'homeworkId': hwId,
            'dueAt': Timestamp.fromDate(dueAt),
          },
        );
      }
    }
    // Yayın zamanı geçmişse publishNotified=true işaretle (function atlamasın).
    if (publishedNow) {
      batch.set(hwRef, {'publishNotified': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Taslak ödevi günceller (öğretmen Bekleyenler'de düzenler).
  static Future<bool> updateDraft({
    required String classId,
    required String hwId,
    String? title,
    DateTime? dueAt,
    DateTime? publishAt,
    bool clearPublishAt = false,
    List<Map<String, dynamic>>? questions,
    // null → dokunma; '' → mesajı sil; dolu → güncelle.
    String? teacherNote,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (teacherNote != null) {
        data['teacherNote'] = teacherNote.trim().isEmpty
            ? FieldValue.delete()
            : teacherNote.trim();
      }
      if (dueAt != null) data['dueAt'] = Timestamp.fromDate(dueAt);
      if (clearPublishAt) {
        data['publishAt'] = FieldValue.delete();
      } else if (publishAt != null) {
        data['publishAt'] = Timestamp.fromDate(publishAt);
      }
      if (questions != null) {
        data['questions'] = questions;
        data['questionCount'] = questions.length;
      }
      if (data.isEmpty) return true;
      await _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(hwId).set(data, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[HomeworkService] updateDraft fail: $e');
      return false;
    }
  }

  /// Taslağı YAYINLA: status→published, slot'ları aç, (yayındaysa) bildir.
  /// İsteğe bağlı dueAt/publishAt verilerek son anda zamanlama güncellenir.
  static Future<bool> publishDraft({
    required String classId,
    required String hwId,
    DateTime? dueAt,
    DateTime? publishAt,
    bool clearPublishAt = false,
  }) async {
    try {
      final ref = _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(hwId);
      final snap = await ref.get();
      if (!snap.exists) return false;
      final hw = HomeworkModel.fromDoc(snap);
      final newDue = dueAt ?? hw.dueAt;
      final newPublish = clearPublishAt ? null : (publishAt ?? hw.publishAt);
      // status + zamanlama güncelle
      final upd = <String, dynamic>{
        'status': 'published',
        'dueAt': Timestamp.fromDate(newDue),
        'publishNotified': false,
        // Taslakken dueAt yakın bir saate denk gelip checkPendingReminders
        // tarafından erkenden true'lanmış olabilir — yayınlanınca sıfırla,
        // yoksa bu ödev için 2-saat-kaldı hatırlatması hiç gitmez.
        'reminderSent': false,
      };
      if (clearPublishAt) {
        upd['publishAt'] = FieldValue.delete();
      } else if (newPublish != null) {
        upd['publishAt'] = Timestamp.fromDate(newPublish);
      }
      await ref.set(upd, SetOptions(merge: true));
      await _materializeAssignment(
        classId: classId, hwId: hwId, title: hw.title, dueAt: newDue,
        publishAt: newPublish,
      );
      // Öğretmene "ödev yayınlandı" geri bildirimi (hemen yayınlandıysa).
      final publishedNow =
          newPublish == null || !newPublish.isAfter(DateTime.now());
      final myUid = _myUid;
      if (publishedNow && myUid != null) {
        try {
          final cls = await _fs.collection('classes').doc(classId).get();
          final className = (cls.data()?['name'] ?? '').toString();
          await _fs.collection('notifications').doc(myUid)
              .collection('items').doc().set({
            'type': 'homework_published',
            'homeworkTitle': hw.title,
            'className': className,
            'classId': classId,
            'homeworkId': hwId,
            'when': FieldValue.serverTimestamp(),
            'read': false,
          });
        } catch (_) {}
      }
      Analytics.logFeatureAction('teacher_panel', 'homework_draft_published');
      return true;
    } catch (e) {
      debugPrint('[HomeworkService] publishDraft fail: $e');
      return false;
    }
  }

  /// ÖĞRETMEN: Ödevin cevap anahtarını öğrencilere AÇAR/KAPATIR.
  /// Açılınca teslim etmiş her öğrenciye "cevaplar paylaşıldı" bildirimi
  /// gider; öğrenci kendi cevabını + doğru cevabı + soru çözümünü görür.
  /// (Teslim etmemiş öğrenciye bildirim gitmez ve cevaplar görünmez —
  /// kopya riskine karşı öğrenci tarafı yalnız teslimden sonra gösterir.)
  static Future<bool> setAnswersShared({
    required String classId,
    required String homeworkId,
    required bool share,
  }) async {
    if (_myUid == null) return false;
    try {
      final ref = _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(homeworkId);
      await ref.set({
        'answersSharedAt':
            share ? FieldValue.serverTimestamp() : FieldValue.delete(),
      }, SetOptions(merge: true));
      if (share) {
        // Teslim etmiş öğrencilere bildirim (best-effort).
        try {
          final hwDoc = await ref.get();
          final hwTitle = (hwDoc.data()?['title'] ?? 'Ödev').toString();
          final cls = await _fs.collection('classes').doc(classId).get();
          final className = (cls.data()?['name'] ?? '').toString();
          final subs = await ref.collection('submissions').get();
          var batch = _fs.batch();
          int ops = 0;
          for (final s in subs.docs) {
            final st = (s.data()['status'] ?? 'pending').toString();
            if (st != 'submitted' && st != 'late') continue;
            batch.set(
              _fs.collection('notifications').doc(s.id)
                  .collection('items').doc(),
              {
                'type': 'homework_answers_shared',
                'homeworkTitle': hwTitle,
                'className': className,
                'classId': classId,
                'homeworkId': homeworkId,
                'when': FieldValue.serverTimestamp(),
                'read': false,
              },
            );
            if (++ops >= 400) {
              await batch.commit();
              batch = _fs.batch();
              ops = 0;
            }
          }
          if (ops > 0) await batch.commit();
        } catch (_) {}
      }
      Analytics.logFeatureAction('teacher_panel',
          share ? 'answers_shared' : 'answers_unshared');
      return true;
    } catch (e) {
      debugPrint('[HomeworkService] setAnswersShared fail: $e');
      return false;
    }
  }

  /// ÖĞRETMEN: Cevap anahtarını TEK BİR ÖĞRENCİYE açar/kapatır (submission
  /// dokümanına answersSharedAt yazar). Sınıf geneli setAnswersShared'dan
  /// bağımsızdır — öğrenci tarafı ikisinden biri açıksa cevapları gösterir.
  /// Açılınca öğrenciye "cevaplar paylaşıldı" bildirimi gider.
  static Future<bool> shareAnswersWithStudent({
    required String classId,
    required String homeworkId,
    required String studentUid,
    required bool share,
  }) async {
    if (_myUid == null || studentUid.isEmpty) return false;
    try {
      final hwRef = _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(homeworkId);
      await hwRef.collection('submissions').doc(studentUid).set({
        'answersSharedAt':
            share ? FieldValue.serverTimestamp() : FieldValue.delete(),
      }, SetOptions(merge: true));
      if (share) {
        // Öğrenciye bildirim (best-effort).
        try {
          final hwDoc = await hwRef.get();
          final hwTitle = (hwDoc.data()?['title'] ?? 'Ödev').toString();
          final cls = await _fs.collection('classes').doc(classId).get();
          final className = (cls.data()?['name'] ?? '').toString();
          await _fs.collection('notifications').doc(studentUid)
              .collection('items').add({
            'type': 'homework_answers_shared',
            'homeworkTitle': hwTitle,
            'className': className,
            'classId': classId,
            'homeworkId': homeworkId,
            'when': FieldValue.serverTimestamp(),
            'read': false,
          });
        } catch (_) {}
      }
      Analytics.logFeatureAction('teacher_panel',
          share ? 'answers_shared_student' : 'answers_unshared_student');
      return true;
    } catch (e) {
      debugPrint('[HomeworkService] shareAnswersWithStudent fail: $e');
      return false;
    }
  }

  /// Bir ödevi/taslağı tamamen sil (alt submission'larıyla birlikte).
  static Future<bool> deleteHomework(String classId, String hwId) async {
    try {
      final ref = _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(hwId);
      final subs = await ref.collection('submissions').get();
      final batch = _fs.batch();
      for (final s in subs.docs) {
        batch.delete(s.reference);
      }
      batch.delete(ref);
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('[HomeworkService] deleteHomework fail: $e');
      return false;
    }
  }

  /// Öğretmenin BEKLEYEN ödevleri (taslak + yayın zamanı gelecek olanlar).
  static Stream<List<HomeworkModel>> pendingHomeworksStream(String classId) {
    return _fs.collection('classes').doc(classId)
        .collection('homeworks')
        .orderBy('assignedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .map(HomeworkModel.fromDoc)
            .where((hw) => hw.isDraft || hw.isScheduledPending)
            .toList());
  }

  /// Öğretmen ana ekranı özeti: ad + sınıf/öğrenci/bu-hafta-ödev/bekleyen
  /// sayıları. Tüm sınıflar üzerinden tek seferde toplar.
  static Future<
      ({String name, int classes, int students, int weekHomeworks, int pending})>
      teacherHomeSummary() async {
    final myUid = _myUid;
    if (myUid == null) {
      return (name: '', classes: 0, students: 0, weekHomeworks: 0, pending: 0);
    }
    int students = 0, week = 0, pending = 0, classCount = 0;
    String name = '';
    try {
      final me = await _fs.collection('users').doc(myUid).get();
      name = (me.data()?['displayName'] ?? me.data()?['username'] ?? '')
          .toString();
      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final clsSnap = await _fs.collection('classes')
          .where('teacherUid', isEqualTo: myUid).get();
      classCount = clsSnap.docs.length;
      for (final c in clsSnap.docs) {
        final sc = await c.reference.collection('students').count().get();
        students += sc.count ?? 0;
        final hwSnap = await c.reference.collection('homeworks').get();
        for (final d in hwSnap.docs) {
          final hw = HomeworkModel.fromDoc(d);
          if (hw.assignedAt.isAfter(weekStart)) week++;
          if (hw.isDraft || hw.isScheduledPending) pending++;
        }
      }
    } catch (e) {
      debugPrint('[HomeworkService] teacherHomeSummary fail: $e');
    }
    return (
      name: name,
      classes: classCount,
      students: students,
      weekHomeworks: week,
      pending: pending,
    );
  }

  /// Öğretmenin TÜM sınıflarındaki bekleyen (taslak + zamanlanmış) ödevleri
  /// sınıf adıyla birlikte döndürür (birleşik bekleyenler ekranı için).
  static Future<List<PendingHomeworkItem>> allPendingForTeacher() async {
    final myUid = _myUid;
    final out = <PendingHomeworkItem>[];
    if (myUid == null) return out;
    try {
      final clsSnap = await _fs.collection('classes')
          .where('teacherUid', isEqualTo: myUid).get();
      for (final c in clsSnap.docs) {
        final className = (c.data()['name'] ?? '').toString();
        final hwSnap = await c.reference.collection('homeworks').get();
        for (final d in hwSnap.docs) {
          final hw = HomeworkModel.fromDoc(d);
          if (hw.isDraft || hw.isScheduledPending) {
            out.add(PendingHomeworkItem(hw: hw, className: className));
          }
        }
      }
      out.sort((a, b) => b.hw.assignedAt.compareTo(a.hw.assignedAt));
    } catch (e) {
      debugPrint('[HomeworkService] allPendingForTeacher fail: $e');
    }
    return out;
  }

  /// Bir sınıftaki YAYINDA (aktif, taslak/zamanlanmış değil) ödev sayısı.
  static Stream<int> activeHomeworkCountStream(String classId) {
    return _fs.collection('classes').doc(classId)
        .collection('homeworks')
        .snapshots()
        .map((snap) => snap.docs
            .map(HomeworkModel.fromDoc)
            .where((hw) => hw.isPublished)
            .length);
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
      // "Herkes bitirdi" bildirimini yalnızca ilk tamamlamada tetiklemek için
      // önceki durumu oku (yeniden teslimde tekrar bildirim gitmesin).
      final prevSubSnap = await _fs.collection('classes').doc(classId)
          .collection('homeworks').doc(homeworkId)
          .collection('submissions').doc(myUid).get();
      final prevStatus =
          (prevSubSnap.data()?['status'] ?? 'pending').toString();
      final firstCompletion =
          prevStatus == 'pending' || prevStatus == 'in_progress';
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
      // Sınıf öğretmenine "ödev teslim edildi" bildirimi (best-effort).
      try {
        final teacherUid = (hwDoc.data()?['teacherUid'] ?? '').toString();
        if (teacherUid.isNotEmpty && teacherUid != myUid) {
          final hwTitle = (hwDoc.data()?['title'] ?? 'Ödev').toString();
          final stu = await _fs.collection('classes').doc(classId)
              .collection('students').doc(myUid).get();
          final sd = stu.data() ?? const <String, dynamic>{};
          final sName = (sd['teacherAlias'] ??
              sd['displayName'] ?? sd['username'] ?? 'Bir öğrenci').toString();
          await _fs.collection('notifications').doc(teacherUid)
              .collection('items').doc().set({
            'type': 'homework_submission',
            'fromDisplayName': sName,
            'homeworkTitle': hwTitle,
            'classId': classId,
            'homeworkId': homeworkId,
            'when': FieldValue.serverTimestamp(),
            'read': false,
          });
        }
      } catch (_) {}
      // Tüm öğrenciler tamamladıysa öğretmene tek seferlik "herkes bitirdi"
      // bildirimi (yalnızca bu öğrencinin İLK tamamlamasında kontrol edilir).
      if (firstCompletion) {
        try {
          final teacherUid = (hwDoc.data()?['teacherUid'] ?? '').toString();
          if (teacherUid.isNotEmpty) {
            final subs = await _fs.collection('classes').doc(classId)
                .collection('homeworks').doc(homeworkId)
                .collection('submissions').get();
            final allDone = subs.docs.isNotEmpty && subs.docs.every((d) {
              final st = (d.data()['status'] ?? 'pending').toString();
              return st != 'pending' && st != 'in_progress';
            });
            if (allDone) {
              final hwTitle = (hwDoc.data()?['title'] ?? 'Ödev').toString();
              final cls = await _fs.collection('classes').doc(classId).get();
              final className = (cls.data()?['name'] ?? '').toString();
              await _fs.collection('notifications').doc(teacherUid)
                  .collection('items').doc().set({
                'type': 'homework_all_done',
                'homeworkTitle': hwTitle,
                'className': className,
                'classId': classId,
                'homeworkId': homeworkId,
                'when': FieldValue.serverTimestamp(),
                'read': false,
              });
            }
          }
        } catch (_) {}
      }
      Analytics.logFeatureAction('homework', 'submitted',
          {'score': score.round()});
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
    if (_myUid == null) return false;
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
        // Firestore sayıyı double döndürebilir → güvenli int dönüşümü.
        final idx = (a['index'] as num?)?.toInt() ?? -1;
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
      // Öğrenciye "ödevin değerlendirildi" bildirimi — daha önce bu yön hiç
      // yoktu, öğrenci notunun güncellendiğini fark etmenin tek yolu ödevi
      // elle tekrar açmaktı.
      try {
        final hwDoc = await _fs.collection('classes').doc(classId)
            .collection('homeworks').doc(homeworkId).get();
        final hwTitle = (hwDoc.data()?['title'] ?? 'Ödev').toString();
        await _fs.collection('notifications').doc(studentUid)
            .collection('items').doc().set({
          'type': 'homework_graded',
          'homeworkTitle': hwTitle,
          'classId': classId,
          'homeworkId': homeworkId,
          'when': FieldValue.serverTimestamp(),
          'read': false,
        });
      } catch (_) {}
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
          if (hw.isDraft) continue; // yayınlanmamış ödev — reminderSent'i tüketme
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
    // false → yalnız cache'i döndür; AI çağrısı YAPMA ve submission'a YAZMA.
    // Ebeveyn çocuğun teslimine yazamaz (rules), bu yüzden ebeveyn salt-okur.
    bool allowGenerate = true,
  }) async {
    if (cached != null && cached.trim().isNotEmpty) return cached;
    if (!allowGenerate) return null;
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

  /// Sınıftaki bir ödevin (newest-first) listesini döndürür — Özet filtresi
  /// için. En son verilen ödev en üstte.
  static Future<List<HomeworkModel>> classHomeworks(String classId) async {
    try {
      final snap = await _fs.collection('classes').doc(classId)
          .collection('homeworks').get();
      final list = snap.docs.map(HomeworkModel.fromDoc).toList();
      list.sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
      return list;
    } catch (e) {
      debugPrint('[HomeworkService] classHomeworks fail: $e');
      return [];
    }
  }

  /// Sınıftaki TÜM öğrencilerin toplam soru/doğru/yanlış/boş + başarı %
  /// kırılımını döndürür (Özet tablo). En başarılı en üstte sıralı.
  /// Hiç teslimi olmayan öğrenciler de 0 değerleriyle listelenir.
  /// [homeworkId] verilirse sadece o ödevin sonuçları toplanır.
  static Future<List<StudentGradeSummary>> classGradeSummary(
      String classId, {String? homeworkId}) async {
    try {
      final aggs = <String, _GradeAgg>{};

      // 1) Tüm sınıf öğrencilerini ekle (teslimi olmayanlar da görünsün).
      final studSnap = await _fs.collection('classes').doc(classId)
          .collection('students').get();
      for (final d in studSnap.docs) {
        final m = d.data();
        // Onay bekleyen öğrenci henüz sınıfta sayılmaz — özet tabloya girmez.
        if ((m['status'] ?? 'active').toString() == 'pending') continue;
        final alias = (m['teacherAlias'] ?? '').toString().trim();
        final dispName = (m['displayName'] ?? '').toString().trim();
        final uname = (m['username'] ?? '').toString().trim();
        final name = alias.isNotEmpty
            ? alias
            : dispName.isNotEmpty
                ? dispName
                : '@$uname';
        aggs[d.id] = _GradeAgg(name);
      }

      // 2) Ödev teslimlerinden soru/doğru/yanlış/boş topla.
      //    Belirli ödev seçiliyse yalnızca onu işle.
      final List<HomeworkModel> homeworks;
      if (homeworkId != null) {
        final d = await _fs.collection('classes').doc(classId)
            .collection('homeworks').doc(homeworkId).get();
        homeworks = d.exists ? [HomeworkModel.fromDoc(d)] : [];
      } else {
        final hwSnap = await _fs.collection('classes').doc(classId)
            .collection('homeworks').get();
        homeworks = hwSnap.docs.map(HomeworkModel.fromDoc).toList();
      }
      for (final hw in homeworks) {
        final subs = await _fs.collection('classes').doc(classId)
            .collection('homeworks').doc(hw.id)
            .collection('submissions').get();
        for (final sd in subs.docs) {
          final sub = HomeworkSubmissionModel.fromMap(sd.data());
          if (!sub.isSubmitted) continue;
          final a = aggs.putIfAbsent(sub.studentUid, () => _GradeAgg(
              sub.studentDisplayName.isEmpty
                  ? '@${sub.studentUsername}'
                  : sub.studentDisplayName));
          final qCount =
              hw.questionCount > 0 ? hw.questionCount : sub.answers.length;
          a.total += qCount;
          if (sub.answers.isNotEmpty) {
            for (final ans in sub.answers) {
              if (ans.studentAnswer.trim().isEmpty) {
                a.empty++;
              } else if (ans.isCorrect == true) {
                a.correct++;
              } else if (ans.isCorrect == false) {
                a.wrong++;
              }
            }
            // Cevap dizisinde olmayan (atlanan) sorular boş sayılır.
            if (qCount > sub.answers.length) {
              a.empty += qCount - sub.answers.length;
            }
          } else {
            final c = sub.correct ?? 0;
            final w = sub.wrong ?? 0;
            a.correct += c;
            a.wrong += w;
            a.empty += (qCount - c - w).clamp(0, qCount);
          }
        }
      }

      final out = aggs.entries
          .map((e) => StudentGradeSummary(
                uid: e.key,
                name: e.value.name,
                totalQuestions: e.value.total,
                correct: e.value.correct,
                wrong: e.value.wrong,
                empty: e.value.empty,
              ))
          .toList()
        // En iyi en üstte; eşitlikte daha çok soru çözen üstte.
        ..sort((x, y) {
          final c = y.pct.compareTo(x.pct);
          if (c != 0) return c;
          return y.totalQuestions.compareTo(x.totalQuestions);
        });
      return out;
    } catch (e) {
      debugPrint('[HomeworkService] classGradeSummary fail: $e');
      return [];
    }
  }
}

/// Birleşik "bekleyen ödevler" öğesi — ödev + sınıf adı.
class PendingHomeworkItem {
  final HomeworkModel hw;
  final String className;
  const PendingHomeworkItem({required this.hw, required this.className});
}

// ─── Analitik veri modelleri ───────────────────────────────────────────────

/// Sınıf özeti — bir öğrencinin TÜM ödevlerdeki toplam soru/doğru/yanlış/boş
/// kırılımı ve toplam başarı yüzdesi (Excel benzeri özet tablo satırı).
class StudentGradeSummary {
  final String uid;
  final String name;
  final int totalQuestions;
  final int correct;
  final int wrong;
  final int empty;
  const StudentGradeSummary({
    required this.uid,
    required this.name,
    required this.totalQuestions,
    required this.correct,
    required this.wrong,
    required this.empty,
  });

  /// Başarı yüzdesi — TOPLAM sorulan soru üzerinden.
  double get pct =>
      totalQuestions > 0 ? correct * 100 / totalQuestions : 0;
}

/// classGradeSummary iç toplayıcısı.
class _GradeAgg {
  String name;
  int total = 0, correct = 0, wrong = 0, empty = 0;
  _GradeAgg(this.name);
}

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
