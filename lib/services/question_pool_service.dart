// ═══════════════════════════════════════════════════════════════════════════════
//  QuestionPoolService — 5000 soruluk konu havuzu okuma.
//
//  HAVUZ STRATEJİSİ (kullanıcı tarafı):
//    1. Kullanıcı "Sınav Soruları" der → poolKey(country|level|grade|subject|topic)
//    2. Firestore `question_pool/{key}` doc'u oku:
//       • status='ready' → havuzdan N adet rastgele soru çek (kullanıcı görmediği)
//       • status='generating' → fallback: AI'dan tek seferlik N soru üret
//       • status yoksa → Cloud Function tetikle (Cloud Scheduler 5000 üretene
//         kadar arka planda çalışır), kullanıcıya ilk batch (50 soru) ver
//    3. Çekilen sorular `user_question_history/{uid}` doc'una kaydedilir
//       (kullanıcı aynı soruyu bir daha görmez).
//
//  ÜRETİM (Cloud Function tarafı — bkz: functions/src/question_pool_generator.ts):
//    • Cloud Scheduler her saat 1 batch (50 soru) üretir.
//    • Embedding dedup ile %95+ benzer sorular elenir.
//    • 5000'e ulaşınca status='frozen'.
//    • 1 yıl sonra veya müfredat değişince re-generate.
//
//  ŞEMASI:
//    question_pool/{topicKey}
//      country, level, grade, subjectKey, topicKey
//      status: 'generating'|'ready'|'frozen'
//      acceptedCount: int (dedup sonrası)
//      generatedCount: int (toplam üretim)
//      curriculumVersion: string
//      lastBatchAt: Timestamp
//      createdAt, updatedAt
//
//      /questions/{qid}
//        stem: string
//        options: [string, string, string, string]
//        correctIndex: int
//        explanation: string
//        difficulty: 'easy'|'medium'|'hard'|'exam'
//        bloomLevel: 'remember'|'understand'|'apply'|'analyze'|'evaluate'|'create'
//        subtopic: string
//        questionType: 'mcq'|'tf'|'short'|'problem'|'match'
//        embedding: [number]  (dedup için)
//        timesServed: int
//        errorReports: int
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'education_profile.dart';
import 'error_logger.dart';
import 'summary_cache_service.dart' show SummaryCacheService;

/// Bir soru.
class PoolQuestion {
  final String id;
  final String stem;
  final List<String> options;
  final int correctIndex;
  final String? explanation;
  final String difficulty;
  final String bloomLevel;
  final String? subtopic;
  final String questionType;

  const PoolQuestion({
    required this.id,
    required this.stem,
    required this.options,
    required this.correctIndex,
    this.explanation,
    required this.difficulty,
    required this.bloomLevel,
    this.subtopic,
    required this.questionType,
  });

  factory PoolQuestion.fromFirestore(
      String id, Map<String, dynamic> data) {
    return PoolQuestion(
      id: id,
      stem: (data['stem'] as String?) ?? '',
      options: (data['options'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      correctIndex: (data['correctIndex'] as int?) ?? 0,
      explanation: data['explanation'] as String?,
      difficulty: (data['difficulty'] as String?) ?? 'medium',
      bloomLevel: (data['bloomLevel'] as String?) ?? 'understand',
      subtopic: data['subtopic'] as String?,
      questionType: (data['questionType'] as String?) ?? 'mcq',
    );
  }
}

class QuestionPoolService {
  QuestionPoolService._();

  static const _collection = 'question_pool';
  static const _questionsSub = 'questions';
  static const _historyKeyPrefix = 'qpool_seen_v1::';

  /// Bir kullanıcı oturumunda max N soruluk paket.
  static const int kDefaultBatchSize = 20;

  // ─── Pool key oluştur ──────────────────────────────────────────────────────

  /// Aynı şema: country|level|grade|subject|topic.
  static String makePoolKey({
    required EduProfile profile,
    required String subject,
    required String topic,
  }) {
    // SummaryCacheService ile aynı normalizasyon (tutarlı anahtar).
    return SummaryCacheService.makeCacheKey(
      profile: profile,
      subject: subject,
      topic: topic,
    );
  }

  // ─── Havuzdan soru çek ─────────────────────────────────────────────────────

  /// Havuzdan rastgele [count] adet soru çeker. Kullanıcının daha önce
  /// gördüğü soruları otomatik dışlar. Havuz hazır değilse null döner →
  /// caller AI fallback'e geçer.
  ///
  /// İsteğe bağlı [difficulty] filtresi: 'easy'|'medium'|'hard'|'exam'.
  static Future<List<PoolQuestion>?> drawQuestions({
    required EduProfile profile,
    required String subject,
    required String topic,
    int count = kDefaultBatchSize,
    String? difficulty,
  }) async {
    try {
      final key = makePoolKey(
          profile: profile, subject: subject, topic: topic);
      final docRef =
          FirebaseFirestore.instance.collection(_collection).doc(key);
      final doc = await docRef.get();

      if (!doc.exists) {
        // Pool yok — caller AI fallback'e geçer, bu arada generator tetiklenir.
        // (Cloud Function'da Firestore trigger ile pool oluşturulur.)
        await _initPool(docRef, profile, subject, topic);
        return null;
      }

      final data = doc.data() ?? const <String, dynamic>{};
      final status = (data['status'] as String?) ?? 'generating';
      final accepted = (data['acceptedCount'] as int?) ?? 0;

      // Havuz eşiği — kalite ve çeşitlilik için 50'nin altındayken AI'a düşer.
      // İlk öğrenciler AI ile soru üretir → bu sorular pool'a yazılır
      // (insertQuestions) → 50'ye ulaşınca pool aktifleşir.
      if (accepted < 50) {
        return null;
      }

      // Kullanıcının görmüş listesini oku
      final seenIds = await _readSeenIds(key);

      // Firestore'dan rastgele N+seenIds kadar çek, sonra client-side filtrele.
      // Optimum: random ordering yok; bunun yerine `__name__` sıralayıp
      // skip + limit ile rastgele başlangıç noktası seç.
      Query<Map<String, dynamic>> q = docRef.collection(_questionsSub);
      if (difficulty != null && difficulty.isNotEmpty) {
        q = q.where('difficulty', isEqualTo: difficulty);
      }

      // Basit "shuffle": serverside random olmadığı için 3 farklı startAt
      // ile küçük batch'ler topla. acceptedCount büyükse iyi kapsama olur.
      final rng = math.Random();
      final fetchMultiplier = 3; // seen filtreleri için fazla çek
      final fetchCount = count * fetchMultiplier;

      final results = <PoolQuestion>[];
      try {
        final randomOffset = accepted > fetchCount
            ? rng.nextInt(accepted - fetchCount)
            : 0;
        final snap = await q
            .orderBy(FieldPath.documentId)
            .limit(fetchCount + randomOffset)
            .get();
        final docs = snap.docs.skip(randomOffset).toList();
        docs.shuffle(rng);
        for (final d in docs) {
          if (results.length >= count) break;
          if (seenIds.contains(d.id)) continue;
          // Kalite filtresi: 3+ kez "yanlış" raporlanmış sorular VEYA
          // AI judge tarafından karantinaya alınmış (quarantined=true)
          // sorular havuzdan gelmesin. Composite index gerektirmeyecek
          // şekilde client-side filtrele.
          final data = d.data();
          final reports = (data['errorReports'] as int?) ?? 0;
          if (reports >= 3) continue;
          final quarantined = (data['quarantined'] as bool?) ?? false;
          if (quarantined) continue;
          results.add(PoolQuestion.fromFirestore(d.id, data));
        }
      } catch (e, st) {
        ErrorLogger.instance.capture(e, st,
            context: 'question_pool.draw_query');
        return null;
      }

      if (results.isEmpty) return null;

      // Görüldü işaretle (atomic, telemetri için fire-and-forget)
      unawaited(_markServed(
          key: key,
          poolKey: key,
          docRef: docRef,
          questionIds: results.map((q) => q.id).toList()));

      // Status info log
      if (status == 'frozen') {
        debugPrint('[QuestionPool] frozen pool hit: $accepted soru');
      }
      return results;
    } catch (e, st) {
      ErrorLogger.instance
          .capture(e, st, context: 'question_pool.drawQuestions');
      return null;
    }
  }

  // ─── Havuza soru yaz — organik doluş (AI test başarılı olunca) ────────────

  /// AI bir kullanıcı için test üretti → o test'in sorularını da havuza
  /// yaz ki sonraki öğrenciler havuzdan çeksin. Fire-and-forget olarak
  /// `_generateAttemptForSummary`'den çağrılır; başarısız olursa sessizce
  /// atlar (kullanıcı akışını bozmaz).
  ///
  /// `questions` parametresinin Map anahtarları:
  ///   `stem` (String, soru metni)
  ///   `options` (string listesi, A..E sırasında)
  ///   `correctIndex` (int, 0..4)
  ///   `explanation` (String?, çözüm açıklaması)
  ///   `difficulty` (String, 'easy'|'medium'|'hard')
  ///
  /// Heuristik kalite gate'i:
  ///   • stem >= 20 karakter
  ///   • options >= 2 eleman, hepsi non-empty
  ///   • correctIndex aralıkta
  ///   • Aynı stem hash'i pool'da varsa skip (dedup)
  ///
  /// [return]: havuza eklenen soru sayısı.
  static Future<int> insertQuestions({
    required EduProfile profile,
    required String subject,
    required String topic,
    required List<Map<String, dynamic>> questions,
  }) async {
    if (questions.isEmpty) return 0;
    try {
      final key = makePoolKey(
          profile: profile, subject: subject, topic: topic);
      final docRef =
          FirebaseFirestore.instance.collection(_collection).doc(key);

      // Pool yoksa init et (status='generating' doc'u oluştur).
      final doc = await docRef.get();
      if (!doc.exists) {
        await _initPool(docRef, profile, subject, topic);
      }

      // Önce mevcut soruların hash'lerini topla (dedup için).
      // Performans: sadece son 200 soruyu kontrol et — pool büyürse de
      // ilk 200 zaten yeterli kapsama sağlar.
      final existingHashes = <int>{};
      try {
        final snap = await docRef
            .collection(_questionsSub)
            .orderBy('createdAt', descending: true)
            .limit(200)
            .get();
        for (final d in snap.docs) {
          final h = d.data()['questionHash'];
          if (h is int) existingHashes.add(h);
        }
      } catch (_) {
        // Index yoksa veya boşsa sessizce devam — dedup eksik kalır,
        // duplicate olursa Cloud Function tarafında temizlenir.
      }

      final batch = FirebaseFirestore.instance.batch();
      int inserted = 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        final stem = (q['stem'] as String?)?.trim() ?? '';
        final options =
            (q['options'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        final correctIndex = (q['correctIndex'] as int?) ?? 0;
        final difficulty =
            (q['difficulty'] as String?) ?? 'medium';
        final explanation = (q['explanation'] as String?) ?? '';

        // ── Heuristik kalite kontrolü ─────────────────────────────────────
        if (stem.length < 20) continue;
        if (options.length < 2) continue;
        if (options.any((o) => o.trim().isEmpty)) continue;
        if (correctIndex < 0 || correctIndex >= options.length) continue;

        // ── Dedup hash — normalize edilmiş stem ───────────────────────────
        final norm = stem
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final hash = norm.hashCode;
        if (existingHashes.contains(hash)) continue;
        existingHashes.add(hash); // aynı batch içinde de dedup

        // ── Soru ID — hash + timestamp (collision'a karşı)
        final qId = 'org_${hash.abs().toRadixString(36)}_${nowMs}_$i';

        batch.set(docRef.collection(_questionsSub).doc(qId), {
          'stem': stem,
          'options': options,
          'correctIndex': correctIndex,
          'explanation': explanation,
          'difficulty': difficulty,
          'bloomLevel': 'understand',
          'questionType': 'mcq',
          'source': 'user_ai', // organik AI üretim (Cloud Function değil)
          'questionHash': hash,
          'timesServed': 0,
          'errorReports': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        inserted++;
      }

      if (inserted > 0) {
        // Parent doc'un sayaçlarını güncelle.
        batch.set(docRef, {
          'acceptedCount': FieldValue.increment(inserted),
          'generatedCount': FieldValue.increment(inserted),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await batch.commit();
        debugPrint(
            '[QuestionPool] insertQuestions: $inserted soru havuza eklendi → $key');
      }
      return inserted;
    } catch (e, st) {
      ErrorLogger.instance
          .capture(e, st, context: 'question_pool.insertQuestions');
      return 0;
    }
  }

  // ─── Pool yoksa init (Cloud Function trigger) ──────────────────────────────

  /// İlk kez bu (country×level×grade×subject×topic) için pool yoksa,
  /// boş bir parent doc oluştur. Cloud Function `onPoolCreated` trigger'ı
  /// buna tepkiyle generator başlatır.
  static Future<void> _initPool(
    DocumentReference<Map<String, dynamic>> docRef,
    EduProfile profile,
    String subject,
    String topic,
  ) async {
    try {
      await docRef.set({
        'country': profile.country,
        'level': profile.level,
        'grade': profile.grade,
        'subjectKey': SummaryCacheService.makeCacheKey(
          profile: profile,
          subject: subject,
          topic: '_',
        ).split('|')[3],
        'subjectName': subject,
        'topicName': topic,
        'status': 'generating',
        'acceptedCount': 0,
        'generatedCount': 0,
        'curriculumVersion': SummaryCacheService.kCurriculumVersion,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      ErrorLogger.instance
          .capture(e, st, context: 'question_pool.initPool');
    }
  }

  // ─── Kullanıcının görmüş soru listesi ──────────────────────────────────────

  static Future<Set<String>> _readSeenIds(String poolKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('$_historyKeyPrefix$poolKey');
      return raw?.toSet() ?? <String>{};
    } catch (e, st) {
      ErrorLogger.instance
          .capture(e, st, context: 'question_pool.readSeenIds');
      return <String>{};
    }
  }

  static Future<void> _markServed({
    required String key,
    required String poolKey,
    required DocumentReference<Map<String, dynamic>> docRef,
    required List<String> questionIds,
  }) async {
    if (questionIds.isEmpty) return;
    try {
      // 1) Lokal görüldü listesine ekle
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList('$_historyKeyPrefix$poolKey') ?? [];
      seen.addAll(questionIds);
      // Maks 2000 ID tut (eski olanları at)
      final trimmed = seen.length > 2000
          ? seen.sublist(seen.length - 2000)
          : seen;
      await prefs.setStringList('$_historyKeyPrefix$poolKey', trimmed);

      // 2) Server-side `timesServed` increment (telemetri)
      // Batch update (transaction yerine, çok hızlı)
      final batch = FirebaseFirestore.instance.batch();
      for (final qid in questionIds) {
        batch.update(
          docRef.collection(_questionsSub).doc(qid),
          {'timesServed': FieldValue.increment(1)},
        );
      }
      await batch.commit();
    } catch (e, st) {
      ErrorLogger.instance
          .capture(e, st, context: 'question_pool.markServed');
    }
  }

  // ─── Topluluk kıyaslaması — test sonucu istatistik ────────────────────

  /// Kullanıcı bir testi bitirdiğinde havuz dokümanına atomik artış uygular:
  /// `totalAttempts` +1, `totalCorrectSum` += correct, `totalQuestionsSum`
  /// += total. Anonim — kim olduğu kaydedilmez, sadece toplam.
  ///
  /// Read tarafı bu sayaçlardan ortalama hesaplar:
  ///   avgPct = totalCorrectSum / totalQuestionsSum * 100
  ///
  /// Fire-and-forget olarak çağrılır; çökerse kullanıcı akışını bozmaz.
  static Future<void> recordAttempt({
    required EduProfile profile,
    required String subject,
    required String topic,
    required int correct,
    required int total,
  }) async {
    if (total <= 0) return;
    try {
      final key = makePoolKey(
          profile: profile, subject: subject, topic: topic);
      final docRef =
          FirebaseFirestore.instance.collection(_collection).doc(key);
      // Doc yoksa init et — havuz yokken bile istatistik tutulmalı.
      final doc = await docRef.get();
      if (!doc.exists) {
        await _initPool(docRef, profile, subject, topic);
      }
      await docRef.set({
        'totalAttempts': FieldValue.increment(1),
        'totalCorrectSum': FieldValue.increment(correct),
        'totalQuestionsSum': FieldValue.increment(total),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      ErrorLogger.instance
          .capture(e, st, context: 'question_pool.recordAttempt');
    }
  }

  /// Topluluk ortalamasını okur — TestResultPage'de "Bu konuda N öğrenci
  /// ortalama %M çözdü" kartı için. Veri yoksa null döner.
  static Future<({int attempts, int avgPct})?> readCommunityStats({
    required EduProfile profile,
    required String subject,
    required String topic,
  }) async {
    try {
      final key = makePoolKey(
          profile: profile, subject: subject, topic: topic);
      final docRef =
          FirebaseFirestore.instance.collection(_collection).doc(key);
      final doc = await docRef.get();
      if (!doc.exists) return null;
      final data = doc.data() ?? const <String, dynamic>{};
      final attempts = (data['totalAttempts'] as int?) ?? 0;
      final correctSum = (data['totalCorrectSum'] as int?) ?? 0;
      final questionsSum = (data['totalQuestionsSum'] as int?) ?? 0;
      // Anlamlı kıyas için en az 3 farklı deneme + 10 soru olsun.
      if (attempts < 3 || questionsSum < 10) return null;
      final avgPct = ((correctSum / questionsSum) * 100).round();
      return (attempts: attempts, avgPct: avgPct);
    } catch (e, st) {
      ErrorLogger.instance
          .capture(e, st, context: 'question_pool.readCommunityStats');
      return null;
    }
  }

  // ─── Hata bildir ───────────────────────────────────────────────────────────

  /// Kullanıcı bir soruyu "hatalı" diye bildirdiğinde çağrılır.
  static Future<bool> reportQuestionError({
    required EduProfile profile,
    required String subject,
    required String topic,
    required String questionId,
    String? reason,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final key = makePoolKey(
          profile: profile, subject: subject, topic: topic);
      final qRef = FirebaseFirestore.instance
          .collection(_collection)
          .doc(key)
          .collection(_questionsSub)
          .doc(questionId);
      await qRef.update({
        'errorReports': FieldValue.increment(1),
        'reports': FieldValue.arrayUnion([
          {
            'by': user?.uid ?? 'anonymous',
            'at': Timestamp.now(),
            'reason': reason ?? '',
          }
        ]),
      });
      return true;
    } catch (e, st) {
      ErrorLogger.instance
          .capture(e, st, context: 'question_pool.reportError');
      return false;
    }
  }
}
