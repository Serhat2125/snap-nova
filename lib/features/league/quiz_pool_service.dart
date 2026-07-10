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
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    Set<String>? exclude,
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

      // Kullanıcıya daha önce SUNULMUŞ sorular hariç tutulur (replay'de
      // aynı soruların tekrar gelmemesi için). Kalan soru `count`'un
      // altına düşerse eksik liste döner — çağıran taraf zaten <10 soruda
      // AI'dan TAZE soru üretip havuza ekliyor; havuz böylece büyür.
      if (exclude != null && exclude.isNotEmpty) {
        allQuestions.removeWhere(
            (q) => exclude.contains(questionHash((q['q'] ?? '').toString())));
        if (allQuestions.isEmpty) return const [];
      }

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

  // ── Sunulmuş soru takibi (yerel) — replay'de aynı sorular gelmesin ────────
  // Kullanıcının gördüğü her sorunun hash'i poolKey bazında SharedPreferences
  // listesinde tutulur (en yeni 300). fetchPoolQuestions(exclude:) bu seti
  // eleyerek örnekler; havuzda yeni soru kalmazsa çağıran taraf AI'dan taze
  // üretir. Deterministik (kova ilk denemesi) seçim de kaydedilir ki replay
  // onları hariç tutabilsin.
  static const _servedPrefix = 'quiz_served_v1_';
  static const _servedCap = 300;

  /// Soru metninden platformdan bağımsız kısa hash (FNV-1a hex).
  static String questionHash(String q) {
    var h = 0x811c9dc5;
    for (final cu in q.trim().codeUnits) {
      h ^= cu;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  static String _servedPrefKey(String poolKey) =>
      '$_servedPrefix${questionHash(poolKey)}';

  /// Bu havuz için kullanıcıya daha önce sunulmuş soru hash'leri.
  static Future<Set<String>> servedHashes(String poolKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_servedPrefKey(poolKey)) ?? const [])
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  /// Sunulan soruları işaretle — liste cap'i aşarsa en eskiler düşer.
  static Future<void> markServed(
      String poolKey, List<Map<String, dynamic>> questions) async {
    if (questions.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final k = _servedPrefKey(poolKey);
      final list = prefs.getStringList(k) ?? <String>[];
      for (final q in questions) {
        final h = questionHash((q['q'] ?? '').toString());
        list.remove(h); // varsa sona taşı (en yeni)
        list.add(h);
      }
      final trimmed = list.length > _servedCap
          ? list.sublist(list.length - _servedCap)
          : list;
      await prefs.setStringList(k, trimmed);
    } catch (e) {
      debugPrint('[QuizPool] markServed fail: $e');
    }
  }

  /// Havuza yeni test ekle — SUNUCU doğrulamalı (addQuizPoolTest CF).
  /// Havuz tavanı, şema doğrulama ve rate limit sunucuda uygulanır;
  /// istemci quiz_pool'a doğrudan YAZAMAZ (rules admin-only).
  /// Cap dolmuşsa veya doğrulama geçmezse false döner — çağıran taraf
  /// için davranış eskisiyle aynı (yazılamadı = sessizce devam).
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
      // Soru schema'sını sade tut — pool'da minimum alanlar yeter.
      final cleanQuestions = questions
          .map((q) => {
                'q': q['q'] ?? '',
                'options': q['options'] ?? const [],
                'correct': q['correct'] ?? 0,
                'explanation': q['explanation'] ?? '',
              })
          .toList();

      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
            'addQuizPoolTest',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<Map<dynamic, dynamic>>({
        'poolKey': key,
        'country': profile.country,
        'level': profile.level,
        'grade': profile.grade,
        'subjectKey': subjectKey,
        'topic': (topic ?? '').isEmpty ? '*' : topic,
        'questions': cleanQuestions,
      }).timeout(_poolTimeout + const Duration(seconds: 14));
      return res.data['accepted'] == true;
    } catch (e) {
      debugPrint('[QuizPool] addToPool fail: $e');
      return false;
    }
  }
}
