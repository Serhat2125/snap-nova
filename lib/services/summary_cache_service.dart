// ═══════════════════════════════════════════════════════════════════════════════
//  SummaryCacheService — Konu özeti topluluk cache'i.
//
//  AKIŞ (read-through):
//    1) Kullanıcı "Yeni Konu Özeti" der → cacheKey(country|level|grade|subject|topic)
//    2) Firestore `summary_cache/{key}` doc'u oku:
//       • status='canonical' → canonical adayı döndür (AI çağrısı YOK)
//       • aday sayısı < 100 → fresh AI üret, aday olarak ekle, kullanıcıya ver
//       • aday sayısı = 100 → judge Cloud Function'ı tetikle, mevcut en yüksek
//         puanlı adayı ver
//    3) Kullanıcı 1-10 arası 5 boyutta rating bırakır → aday dokümanına yaz
//
//  CANONICAL SEÇİMİ:
//    • İlk 100 aday biriktikten sonra Cloud Function:
//        1. Heuristik eleme (çok kısa, başlıksız vs. → eliminated)
//        2. Turnuva 5'li grup (AI judge) → kazanan canonical
//    • Canonical olduktan sonra TÜM kullanıcılar bunu görür.
//    • Kullanıcı 3+ olumsuz puan → status='judging' → yeniden seçim.
//
//  ŞEMASI:
//    summary_cache/{topicKey}
//      country, level, grade, subjectKey, topicKey
//      status: 'collecting'|'judging'|'canonical'
//      candidateCount: int
//      canonicalDocId: string?
//      curriculumVersion: string
//      createdAt, updatedAt: Timestamp
//
//      /candidates/{docId}
//        body: <markdown özet>
//        generatedBy: <uid|anonymous>
//        generatedAt: Timestamp
//        model: 'gemini-2.5-flash'
//        ratings: {sum: int, count: int, byDimension: {accuracy: ..., ...}}
//        ratingsByUser: {<uid>: {accuracy: 8, clarity: 9, ...}}  (max 1/user)
//        status: 'active'|'eliminated'
//        eliminationReason: string?
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'app_settings_service.dart';
import 'education_profile.dart';
import 'error_logger.dart';

/// Cache aday seçim sürecinin durumları.
enum SummaryCacheStatus {
  collecting,   // İlk 100 aday biriktiriliyor; ilk yazan canonical (cold start).
  judging,      // 100 aday birikti; Cloud Function judge çalışıyor / yeniden seçim.
  canonical,    // En iyi seçilmiş, kalıcı.
}

/// Cache'ten dönen sonuç + meta.
class CachedSummary {
  /// Markdown özet metni.
  final String body;
  /// Canonical mi yoksa geçici aday mı?
  final bool isCanonical;
  /// Bu adayın doc ID'si (rating gönderirken gerekli).
  final String candidateDocId;
  /// Bu cache key'inin parent doc ID'si.
  final String cacheDocId;
  /// Hangi modelle üretilmiş.
  final String model;
  /// Ortalama puan (yoksa null).
  final double? avgRating;
  /// Kaç kişi puanladı.
  final int ratingCount;

  const CachedSummary({
    required this.body,
    required this.isCanonical,
    required this.candidateDocId,
    required this.cacheDocId,
    required this.model,
    this.avgRating,
    this.ratingCount = 0,
  });
}

class SummaryCacheService {
  SummaryCacheService._();

  static const _collection = 'summary_cache';
  static const _candidatesSub = 'candidates';

  /// Aday üst sınırı. Burada toplanınca judge tetiklenir.
  static const int kCandidateThreshold = 100;

  /// Müfredat versiyonu — bumplandığında tüm cache invalidate olur.
  /// MEB / sistem güncellemelerinde elle değiştirilir.
  static const String kCurriculumVersion = '2026-v1';

  // ─── Cache key oluşturma ──────────────────────────────────────────────────

  /// Profil + ders + konu → stable cache anahtarı.
  /// Aynı sınıf seviyesindeki aynı konuyu farklı yazımlar (örn. "dünyanın
  /// şekli ve hareketleri" / "dünya hareketleri") aynı anahtara map eder.
  static String makeCacheKey({
    required EduProfile profile,
    required String subject,
    required String topic,
  }) {
    final country = profile.country;
    final level = profile.level;
    final grade = profile.grade;
    final subjectNorm = _normalize(subject);
    final topicNorm = _normalize(topic);
    return '$country|$level|$grade|$subjectNorm|$topicNorm';
  }

  /// Türkçe karakter koruyarak slug üret.
  static String _normalize(String raw) {
    if (raw.isEmpty) return 'unknown';
    var s = raw.toLowerCase().trim();
    // Türkçe karakterleri sadeleştir (cache key'de tutarlılık için)
    const tr = {'ı':'i','İ':'i','ç':'c','ğ':'g','ö':'o','ş':'s','ü':'u','â':'a','î':'i','û':'u'};
    tr.forEach((k, v) => s = s.replaceAll(k, v));
    // Sadece alfanumerik + alt çizgi bırak
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_|_$'), '');
    if (s.isEmpty) return 'unknown';
    // Firestore doc ID 1500 char limit; 80 yeterli
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  // ─── Read-through: cache'ten al, yoksa null ────────────────────────────────

  /// Canonical varsa direkt döner. Yoksa rastgele bir adaydan veya null.
  /// Caller, null gelirse AI üretmeli ve sonra `addCandidate()` çağırmalı.
  static Future<CachedSummary?> read({
    required EduProfile profile,
    required String subject,
    required String topic,
  }) async {
    try {
      final key = makeCacheKey(
          profile: profile, subject: subject, topic: topic);
      final docRef = FirebaseFirestore.instance
          .collection(_collection)
          .doc(key);
      final docSnap = await docRef.get();
      if (!docSnap.exists) return null;
      final data = docSnap.data() ?? const <String, dynamic>{};

      // Müfredat versiyonu eşleşmiyorsa cache'i yok say (yeniden başlat).
      final cv = data['curriculumVersion'] as String?;
      if (cv != kCurriculumVersion) return null;

      final statusStr = (data['status'] as String?) ?? 'collecting';
      final canonicalId = data['canonicalDocId'] as String?;

      if (statusStr == 'canonical' && canonicalId != null) {
        // Cache hit — canonical'ı çek
        final canonicalSnap =
            await docRef.collection(_candidatesSub).doc(canonicalId).get();
        if (!canonicalSnap.exists) return null;
        return _toCachedSummary(
            canonicalSnap.data()!, canonicalSnap.id, docSnap.id,
            isCanonical: true);
      }

      // Collecting modu: aday sayısı 5+ ise ortalama puanı en yüksek adayı dön
      // (cold start fallback). Yoksa null → fresh AI üretilsin.
      final count = (data['candidateCount'] as int?) ?? 0;
      if (count < 5) return null;

      // En yüksek puanlı (en az 1 puan almış) adayı seç
      final query = await docRef
          .collection(_candidatesSub)
          .where('status', isEqualTo: 'active')
          .orderBy('ratings.avg', descending: true)
          .limit(1)
          .get();
      if (query.docs.isEmpty) return null;
      final pick = query.docs.first;
      return _toCachedSummary(pick.data(), pick.id, docSnap.id,
          isCanonical: false);
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'summary_cache.read');
      return null;
    }
  }

  // ─── Yeni aday ekle ────────────────────────────────────────────────────────

  /// AI üretiminden sonra çağrılır. Cache parent doc'u + aday alt-doküman
  /// oluşturur. 100'üncü aday yazılırsa parent status'ü 'judging'e geçer
  /// (Cloud Function trigger).
  ///
  /// Döner: oluşturulan adayın doc ID'si (kullanıcı puan göndermek için
  /// bunu UI'a iletmen lazım).
  static Future<String?> addCandidate({
    required EduProfile profile,
    required String subject,
    required String topic,
    required String body,
    String model = 'gemini-2.5-flash',
  }) async {
    // "Topluluk verisi" kapalıysa kullanıcının ürettiği özet topluluk havuzuna
    // KATKI olarak yazılmaz (opt-out). Okuma/cache kullanımı etkilenmez.
    if (!AppSettingsService.instance.communityData) return null;
    try {
      final key = makeCacheKey(
          profile: profile, subject: subject, topic: topic);
      final docRef = FirebaseFirestore.instance
          .collection(_collection)
          .doc(key);
      final user = FirebaseAuth.instance.currentUser;
      final now = FieldValue.serverTimestamp();

      // Parent doc upsert (atomik increment ile counter)
      await docRef.set({
        'country': profile.country,
        'level': profile.level,
        'grade': profile.grade,
        'subjectKey': _normalize(subject),
        'subjectName': subject,
        'topicKey': _normalize(topic),
        'topicName': topic,
        'status': 'collecting', // canonical'a sadece judge yazsın
        'candidateCount': FieldValue.increment(1),
        'curriculumVersion': kCurriculumVersion,
        'createdAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      // Aday alt-dokümanı ekle
      final candidateRef = await docRef.collection(_candidatesSub).add({
        'body': body,
        'generatedBy': user?.uid ?? 'anonymous',
        'generatedAt': now,
        'model': model,
        'curriculumVersion': kCurriculumVersion,
        'ratings': {
          'sum': 0,
          'count': 0,
          'avg': 0.0,
          'byDimension': <String, double>{
            'accuracy': 0.0,
            'clarity': 0.0,
            'coverage': 0.0,
            'layout': 0.0,
            'overall': 0.0,
          },
        },
        'status': 'active',
        'reportCount': 0,
      });

      return candidateRef.id;
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'summary_cache.addCandidate');
      return null;
    }
  }

  // ─── Rating kaydet (1-10 × 5 boyut) ────────────────────────────────────────

  /// Kullanıcının bir adaya 1-10 puanlama göndermesi.
  /// Aynı kullanıcı yeniden puanlarsa eski puanı SİLER, yeni puana göre
  /// ortalama yeniden hesaplanır (race-condition için transaction).
  ///
  /// `dimensions` map'i: {accuracy:8, clarity:9, coverage:7, layout:8, overall:8}
  /// Her değer 1..10 aralığında olmalı.
  static Future<bool> submitRating({
    required String cacheDocId,
    required String candidateDocId,
    required Map<String, int> dimensions,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('[SummaryCache] rating reddedildi: oturum yok');
        return false;
      }

      // Doğrulama: dimensionlar 1..10 aralığında, hepsi mevcut
      const requiredDims = {'accuracy', 'clarity', 'coverage', 'layout', 'overall'};
      for (final d in requiredDims) {
        final v = dimensions[d];
        if (v == null || v < 1 || v > 10) {
          debugPrint('[SummaryCache] rating reddedildi: $d geçersiz ($v)');
          return false;
        }
      }

      final candRef = FirebaseFirestore.instance
          .collection(_collection)
          .doc(cacheDocId)
          .collection(_candidatesSub)
          .doc(candidateDocId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(candRef);
        if (!snap.exists) throw Exception('candidate yok');
        final data = snap.data() ?? const <String, dynamic>{};
        final ratings =
            (data['ratings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final byUserRaw = (data['ratingsByUser'] as Map<String, dynamic>?) ??
            <String, dynamic>{};

        // Eski puan var mı?
        final old = byUserRaw[user.uid] as Map<String, dynamic>?;

        // Boyut başına yeni toplam hesapla
        final byDimRaw =
            ratings['byDimension'] as Map<String, dynamic>? ?? const {};
        final byDim = <String, double>{
          for (final entry in byDimRaw.entries)
            entry.key: (entry.value as num).toDouble(),
        };
        var count = (ratings['count'] as int?) ?? 0;
        var sum = (ratings['sum'] as int?) ?? 0;

        // Eski puanı düşür
        if (old != null) {
          for (final dim in requiredDims) {
            final oldVal = (old[dim] as int?) ?? 0;
            final cur = (byDim[dim] ?? 0) * count;
            final adjusted = (cur - oldVal) / (count == 0 ? 1 : count);
            byDim[dim] = adjusted < 0 ? 0 : adjusted;
            sum -= oldVal;
          }
          // count düşme YOK — aynı kullanıcı sayılır (1 oy)
          count -= 1;
        }

        // Yeni puanı ekle
        for (final dim in requiredDims) {
          final newVal = dimensions[dim]!;
          final cur = (byDim[dim] ?? 0) * count;
          byDim[dim] = (cur + newVal) / (count + 1);
          sum += newVal;
        }
        count += 1;

        // Genel ortalama (5 boyut × 1..10 → her boyutun ortalaması, sonra
        // boyutların ortalaması alınır)
        final avg = byDim.values.fold<double>(0, (a, b) => a + b) /
            byDim.length;

        tx.update(candRef, {
          'ratings.sum': sum,
          'ratings.count': count,
          'ratings.avg': avg,
          'ratings.byDimension': byDim,
          'ratingsByUser.${user.uid}': dimensions,
        });
      });
      return true;
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'summary_cache.submitRating');
      return false;
    }
  }

  // ─── Hata bildir ───────────────────────────────────────────────────────────

  /// Kullanıcı "Bu özette hata var" der → reportCount++ → 3+ rapor varsa
  /// status='judging'e geçer ve Cloud Function yeniden seçim yapar.
  static Future<bool> reportError({
    required String cacheDocId,
    required String candidateDocId,
    String? reason,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final candRef = FirebaseFirestore.instance
          .collection(_collection)
          .doc(cacheDocId)
          .collection(_candidatesSub)
          .doc(candidateDocId);
      await candRef.update({
        'reportCount': FieldValue.increment(1),
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
      ErrorLogger.instance.capture(e, st, context: 'summary_cache.reportError');
      return false;
    }
  }

  // ─── Yardımcı ──────────────────────────────────────────────────────────────

  static CachedSummary _toCachedSummary(
    Map<String, dynamic> data,
    String candidateId,
    String cacheDocId, {
    required bool isCanonical,
  }) {
    final ratings =
        (data['ratings'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return CachedSummary(
      body: (data['body'] as String?) ?? '',
      isCanonical: isCanonical,
      candidateDocId: candidateId,
      cacheDocId: cacheDocId,
      model: (data['model'] as String?) ?? 'unknown',
      avgRating: (ratings['avg'] as num?)?.toDouble(),
      ratingCount: (ratings['count'] as int?) ?? 0,
    );
  }
}
