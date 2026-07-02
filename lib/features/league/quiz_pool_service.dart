// ═══════════════════════════════════════════════════════════════════════════════
//  QuizPoolService — Bilgi Ligi soru havuzu yöneticisi.
//
//  Tasarım hedefi: Aynı (country × level × grade × subject × topic) için
//  ilk 100 test havuza yazılır; sonraki kullanıcılar AI'ı tetiklemeden
//  havuzdan rastgele 10 soru çeker. Maliyet: ilk 100 üretim, sonsuz çekim.
//
//  Akış:
//    1) `fetchPoolQuestions(poolKey, count)` → havuzdan rastgele N soru
//       (havuz boşsa veya yetersizse [] döner).
//    2) Yetersizse çağıran taraf `GeminiService.generateLeagueQuiz()` ile
//       yeni soru üretir, sonra `addToPool()` ile havuza yazar.
//    3) `poolSize(poolKey)` → cap kontrolü (default 100).
//
//  Random sampling: Firestore native `aggregate.count()` yok, küçük
//  havuzlar için `limit + skip` yerine Fisher-Yates ile client tarafı.
//  Havuz boyutu sınırlı (≤100 doküman) olduğu için tüm liste çekilebilir.
//
//  Rules: read=auth, create=createdBy==uid (admin update/delete).
//  Index: poolKey + createdAt (orderBy için).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../services/education_profile.dart';
import '../../services/locale_service.dart';

/// Firestore fetch timeout — offline / yavaş ağda UI sonsuza kadar dönmesin.
const Duration _poolTimeout = Duration(seconds: 8);

/// Havuz cap'i — bu sayıya ulaşınca yeni test havuza yazılmaz.
/// Sonraki kullanıcılar yalnızca havuzdan rastgele 10 soru alır.
const int kQuizPoolCap = 100;

class QuizPoolService {
  static final _col = FirebaseFirestore.instance.collection('quiz_pool');

  /// Havuz anahtarı: country × level × grade × subject × topic × DİL
  /// kombinasyonu. `topic` boş ya da null ise "*" kullanılır (ders bazlı havuz).
  ///
  /// Dil anahtara dahil değildi → aynı (ülke/seviye/sınıf/ders/konu) için
  /// havuz TÜM kullanıcılar arasında paylaşılıyordu, uygulama dilinden
  /// bağımsız olarak. Örn. İngilizce arayüzdeki bir kullanıcı, havuzu ilk
  /// dolduran Türkçe arayüzlü kullanıcının Türkçe sorularını görüyordu.
  /// Artık her uygulama dili kendi ayrı havuzuna yazar/okur.
  static String poolKey({
    required String country,
    required String level,
    required String grade,
    required String subjectKey,
    String? topic,
  }) {
    final t = (topic ?? '').isEmpty ? '*' : topic!;
    final lang = LocaleService.global?.localeCode ?? 'tr';
    return '$country|$level|$grade|$subjectKey|$t|$lang';
  }

  /// Havuzdaki test sayısı. Cap kontrolü için kullanılır.
  /// Doc count: küçük havuzlarda direkt fetch ile sayım maliyeti düşük;
  /// üretim havuzları büyürse `aggregate().count()` API'sine geçilebilir.
  static Future<int> poolSize(String key) async {
    try {
      final snap = await _col
          .where('poolKey', isEqualTo: key)
          .count()
          .get()
          .timeout(_poolTimeout);
      return snap.count ?? 0;
    } on TimeoutException {
      debugPrint('[QuizPool] poolSize timeout — varsayılan 0');
      return 0;
    } catch (e) {
      debugPrint('[QuizPool] poolSize fail: $e');
      return 0;
    }
  }

  /// Havuzdan rastgele `count` soru çeker.
  /// Her test belgesinde 10 soru var; biz hem birden fazla testten karışım
  /// alıyor hem de tekil sorular çıkarıyoruz: önce N test çek, sonra
  /// içlerinden `count` soru rastgele seç. (10×N soru havuzu → şanslı çeşitlilik.)
  /// [seed] verilirse Fisher-Yates `Random(seed)` ile yapılır → AYNI seed,
  /// AYNI havuz = AYNI sorular. Periyot rotasyonu için kullanılır
  /// (günlük/haftalık/aylık challenge: tüm kullanıcılar aynı 10 soruyu çözer).
  /// Null verilirse her çağrıda rastgele seçim.
  static Future<List<Map<String, dynamic>>> fetchPoolQuestions({
    required String key,
    int count = 10,
    int sampleTests = 5,
    int? seed,
  }) async {
    try {
      // Tüm testleri çek (havuz cap ≤100, yük az). createdAt ile
      // deterministik sıraya gerek yok; ama index uyumlu olsun diye sıralı.
      final snap = await _col
          .where('poolKey', isEqualTo: key)
          .orderBy('createdAt', descending: false)
          .get()
          .timeout(_poolTimeout);
      if (snap.docs.isEmpty) return const [];

      // Tüm testlerin sorularını topla
      final allQuestions = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final qs = data['questions'];
        if (qs is List) {
          for (final q in qs) {
            if (q is Map) {
              allQuestions.add(q.cast<String, dynamic>());
            }
          }
        }
      }
      if (allQuestions.isEmpty) return const [];

      // Fisher-Yates shuffle — seed varsa deterministik, yoksa rastgele.
      final rng = seed != null ? math.Random(seed) : math.Random();
      for (int i = allQuestions.length - 1; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final tmp = allQuestions[i];
        allQuestions[i] = allQuestions[j];
        allQuestions[j] = tmp;
      }
      return allQuestions.length > count
          ? allQuestions.sublist(0, count)
          : allQuestions;
    } on TimeoutException {
      debugPrint('[QuizPool] fetch timeout');
      return const [];
    } catch (e) {
      debugPrint('[QuizPool] fetch fail: $e');
      return const [];
    }
  }

  /// Havuza yeni test ekle (cap kontrolü ile).
  /// Cap'e ulaşılmışsa yazma yapılmaz, false döner.
  static Future<bool> addToPool({
    required String key,
    required EduProfile profile,
    required String subjectKey,
    String? topic,
    required List<Map<String, dynamic>> questions,
  }) async {
    if (questions.isEmpty) return false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      final size = await poolSize(key);
      if (size >= kQuizPoolCap) return false;

      // Soru schema'sını sade tut — pool'da minimum alanlar yeter.
      final cleanQuestions = questions
          .map((q) => {
                'q': q['q'] ?? '',
                'options': q['options'] ?? const [],
                'correct': q['correct'] ?? 0,
                'explanation': q['explanation'] ?? '',
              })
          .toList();

      await _col.add({
        'poolKey': key,
        'country': profile.country,
        'level': profile.level,
        'grade': profile.grade,
        'subjectKey': subjectKey,
        'topic': (topic ?? '').isEmpty ? '*' : topic,
        'questions': cleanQuestions,
        'questionCount': cleanQuestions.length,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
