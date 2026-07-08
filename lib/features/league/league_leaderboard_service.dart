// ═══════════════════════════════════════════════════════════════════════════════
//  LeagueLeaderboardService — Bilgi Ligi liderlik sorguları (Firestore).
//
//  Filtre kombinasyonu (3×3×4 = 36 mantıksal görünüm; hepsi 9 composite
//  index ile karşılanır):
//    • Scope    : city / country / world          → scopeCity/scopeCountry/scopeWorld
//    • Mode     : overall / subject / topic       → subject/topic equality filter
//    • Period   : daily / weekly / monthly / all  → istemci tarafı when filtresi
//
//  Strateji:
//    1) Firestore query: scope eşleşmesi + (varsa) subject/topic eşleşmesi
//       + score DESC + limit 200.
//    2) İstemci tarafı: kullanıcı bazında en yüksek skor (per-uid dedupe),
//       periyot penceresi filtresi, top-N kesimi.
//    3) Auth yok / location yok / Firestore boş → mock fallback.
//
//  Backend büyüdükçe Cloud Functions ile pre-aggregate edilebilir
//  (`leaderboards/{scopeKey_period_subject_topic}`). Şu an basit ve yeterli.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../services/education_profile.dart';
import '../leaderboard/domain/user_location.dart';
import 'league_scores.dart';

/// Firestore query timeout — offline / yavaş bağlantıda UI sonsuza kadar
/// dönmez. 10sn'de sonuç gelmezse boş liste döner, UI mock fallback'e geçer.
const Duration _leagueFetchTimeout = Duration(seconds: 10);

enum LeagueScope { city, country, world }

enum LeagueMode { subject, topic, overall }

class LeagueLeaderRow {
  final String uid;
  final String displayName;
  final String avatar;
  final String location; // şehir veya bayrak+ülke string
  final double score;
  /// Toplam çözüm süresi (saniye). Aynı puan tiebreaker'ı: az süre = üst sıra.
  final int durationSec;
  final bool isMe;

  const LeagueLeaderRow({
    required this.uid,
    required this.displayName,
    required this.avatar,
    required this.location,
    required this.score,
    this.durationSec = 0,
    this.isMe = false,
  });
}

class LeagueLeaderboardService {
  /// Liderlik tablosu çek.
  /// `subjectKey` mode=subject veya topic için zorunlu, overall'da görmezden gelinir.
  /// `topic` mode=topic için zorunlu, diğerlerinde görmezden gelinir.
  /// Sonuç: skor DESC sıralı, top `limit` kullanıcı (her kullanıcı bir kez).
  static Future<List<LeagueLeaderRow>> fetch({
    required EduProfile profile,
    required UserLocation location,
    required LeagueScope scope,
    required LeagueMode mode,
    required LeaguePeriod period,
    String? subjectKey,
    String? topic,
    int limit = 50,
  }) async {
    if (location.countryCode.isEmpty) return const [];

    // ── 0) ÖNCE league_totals (ölçeklenebilir, kesin toplam) ────────────────
    // Attempts üzerinden top-N tekil skor çekip istemcide toplamak 10 bin
    // kullanıcıda yanlış sıralama üretir; totals koleksiyonu kullanıcı ×
    // periyot kovası başına hazır toplam tutar → sorgu doğrudan doğru.
    // Boş dönerse (eski veri / index henüz yok) legacy attempts yoluna düşer.
    try {
      final totalRows = await _fetchFromTotals(
        profile: profile,
        location: location,
        scope: scope,
        mode: mode,
        period: period,
        subjectKey: subjectKey,
        topic: topic,
        limit: limit,
      );
      if (totalRows.isNotEmpty) return totalRows;
    } catch (e) {
      debugPrint('[LeagueLeaderboard] totals fetch fail → legacy: $e');
    }

    return _fetchLegacy(
      profile: profile,
      location: location,
      scope: scope,
      mode: mode,
      period: period,
      subjectKey: subjectKey,
      topic: topic,
      limit: limit,
    );
  }

  /// ESKİ yol — attempts üzerinden istemci tarafı toplama. Totals koleksiyonu
  /// dolana kadar (geçiş dönemi) fallback olarak kullanılır.
  static Future<List<LeagueLeaderRow>> _fetchLegacy({
    required EduProfile profile,
    required UserLocation location,
    required LeagueScope scope,
    required LeagueMode mode,
    required LeaguePeriod period,
    String? subjectKey,
    String? topic,
    required int limit,
  }) async {
    final col = FirebaseFirestore.instance.collection('league_attempts');

    Query<Map<String, dynamic>> q = col;

    // 1) Scope filter — composite scope key
    switch (scope) {
      case LeagueScope.city:
        if (location.cityCode.isEmpty) return const [];
        q = q.where(
          'scopeCity',
          isEqualTo:
              '${location.countryCode}|${location.cityCode}|${profile.level}|${profile.grade}',
        );
        break;
      case LeagueScope.country:
        q = q.where(
          'scopeCountry',
          isEqualTo: '${location.countryCode}|${profile.level}|${profile.grade}',
        );
        break;
      case LeagueScope.world:
        // Dünya = tek küresel havuz (level/grade'e bölünmez). CF yazımıyla
        // birebir: league_submit.ts → scopeWorld = "world".
        q = q.where('scopeWorld', isEqualTo: 'world');
        break;
    }

    // 2) Mode filter
    switch (mode) {
      case LeagueMode.overall:
        // Subject/topic kısıtlaması yok.
        break;
      case LeagueMode.subject:
        if (subjectKey == null || subjectKey.isEmpty) return const [];
        q = q.where('subjectKey', isEqualTo: subjectKey);
        break;
      case LeagueMode.topic:
        if (subjectKey == null || subjectKey.isEmpty) return const [];
        if (topic == null || topic.isEmpty) return const [];
        q = q
            .where('subjectKey', isEqualTo: subjectKey)
            .where('topic', isEqualTo: topic);
        break;
    }

    // 3) Order + limit (skor DESC). Periyot client-side, çünkü when range
    //    + score order birlikte ek index gerektirir; bu mimaride basit tutuyoruz.
    q = q.orderBy('score', descending: true).limit(limit * 4);

    // Timeout + hata yutmama. Offline veya yavaş bağlantıda UI donmasın.
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await q.get().timeout(_leagueFetchTimeout);
    } on TimeoutException {
      debugPrint('[LeagueLeaderboard] timeout — boş liste');
      return const [];
    } catch (e) {
      debugPrint('[LeagueLeaderboard] fetch fail: $e');
      return const [];
    }

    return _aggregateRows(
      docs: snap.docs.map((d) => d.data()).toList(),
      scope: scope,
      period: period,
      limit: limit,
    );
  }

  /// Real-time leaderboard stream — Firestore snapshots üzerinden.
  /// Aynı filtre parametreleri; her doküman değişiminde yeni liste yayar.
  /// Hata/timeout durumunda boş liste yayar, asla bırakmaz.
  static Stream<List<LeagueLeaderRow>> watch({
    required EduProfile profile,
    required UserLocation location,
    required LeagueScope scope,
    required LeagueMode mode,
    required LeaguePeriod period,
    String? subjectKey,
    String? topic,
    int limit = 50,
  }) {
    if (Firebase.apps.isEmpty || location.countryCode.isEmpty) {
      return Stream.value(const <LeagueLeaderRow>[]);
    }

    // ── league_totals canlı akışı (ölçeklenebilir, kesin toplam) ────────────
    final col = FirebaseFirestore.instance.collection('league_totals');
    Query<Map<String, dynamic>> q = col;

    switch (scope) {
      case LeagueScope.city:
        if (location.cityCode.isEmpty) {
          return Stream.value(const <LeagueLeaderRow>[]);
        }
        q = q.where(
          'scopeCity',
          isEqualTo:
              '${location.countryCode}|${location.cityCode}|${profile.level}|${profile.grade}',
        );
        break;
      case LeagueScope.country:
        q = q.where(
          'scopeCountry',
          isEqualTo: '${location.countryCode}|${profile.level}|${profile.grade}',
        );
        break;
      case LeagueScope.world:
        // Dünya = tek küresel havuz (level/grade'e bölünmez). CF yazımıyla
        // birebir: league_submit.ts → scopeWorld = "world".
        q = q.where('scopeWorld', isEqualTo: 'world');
        break;
    }

    final String modeKey;
    switch (mode) {
      case LeagueMode.overall:
        modeKey = 'all';
        break;
      case LeagueMode.subject:
        if (subjectKey == null || subjectKey.isEmpty) {
          return Stream.value(const <LeagueLeaderRow>[]);
        }
        modeKey = 's:$subjectKey';
        break;
      case LeagueMode.topic:
        if (subjectKey == null || subjectKey.isEmpty) {
          return Stream.value(const <LeagueLeaderRow>[]);
        }
        if (topic == null || topic.isEmpty) {
          return Stream.value(const <LeagueLeaderRow>[]);
        }
        modeKey = 't:$subjectKey|$topic';
        break;
    }

    q = q
        .where('bucket', isEqualTo: LeagueScores.bucketFor(period))
        .where('modeKey', isEqualTo: modeKey)
        .orderBy('score', descending: true)
        .limit(limit);

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return q.snapshots().asyncMap((snap) async {
      if (snap.docs.isNotEmpty) {
        return snap.docs.map((d) {
          final m = d.data();
          return LeagueLeaderRow(
            uid: (m['uid'] ?? '').toString(),
            displayName: (m['displayName'] ?? '').toString(),
            avatar: (m['avatar'] ?? '').toString(),
            location: _formatLocation(scope, m),
            score: (m['score'] as num?)?.toDouble() ?? 0.0,
            durationSec: (m['durationSec'] as num?)?.toInt() ?? 0,
            isMe: (m['uid'] ?? '').toString() == myUid,
          );
        }).toList();
      }
      // Totals boş (eski veri / index bekliyor) → legacy attempts'ten tek
      // seferlik doldur; totals dolmaya başlayınca akış otomatik oraya döner.
      return _fetchLegacy(
        profile: profile,
        location: location,
        scope: scope,
        mode: mode,
        period: period,
        subjectKey: subjectKey,
        topic: topic,
        limit: limit,
      );
      // handleError'da `return` DEĞER YAYMAZ — hata anında UI spinner'da
      // takılırdı; transformer sink'e boş liste basar.
    }).transform(
        StreamTransformer<List<LeagueLeaderRow>, List<LeagueLeaderRow>>.fromHandlers(
      handleError: (e, st, sink) {
        debugPrint('[LeagueLeaderboard] watch fail: $e');
        sink.add(const <LeagueLeaderRow>[]);
      },
    ));
  }

  /// league_totals koleksiyonundan sıralama — kullanıcı × kova × mod başına
  /// hazır toplamlar. Sorgu: scope eşitliği + bucket + modeKey + score DESC.
  /// Kesin ve ölçeklenebilir (10 bin+ kullanıcıda da doğru).
  static Future<List<LeagueLeaderRow>> _fetchFromTotals({
    required EduProfile profile,
    required UserLocation location,
    required LeagueScope scope,
    required LeagueMode mode,
    required LeaguePeriod period,
    String? subjectKey,
    String? topic,
    required int limit,
  }) async {
    final col = FirebaseFirestore.instance.collection('league_totals');
    Query<Map<String, dynamic>> q = col;

    switch (scope) {
      case LeagueScope.city:
        if (location.cityCode.isEmpty) return const [];
        q = q.where(
          'scopeCity',
          isEqualTo:
              '${location.countryCode}|${location.cityCode}|${profile.level}|${profile.grade}',
        );
        break;
      case LeagueScope.country:
        q = q.where(
          'scopeCountry',
          isEqualTo:
              '${location.countryCode}|${profile.level}|${profile.grade}',
        );
        break;
      case LeagueScope.world:
        // Dünya = tek küresel havuz (level/grade'e bölünmez). CF yazımıyla
        // birebir: league_submit.ts → scopeWorld = "world".
        q = q.where('scopeWorld', isEqualTo: 'world');
        break;
    }

    final String modeKey;
    switch (mode) {
      case LeagueMode.overall:
        modeKey = 'all';
        break;
      case LeagueMode.subject:
        if (subjectKey == null || subjectKey.isEmpty) return const [];
        modeKey = 's:$subjectKey';
        break;
      case LeagueMode.topic:
        if (subjectKey == null || subjectKey.isEmpty) return const [];
        if (topic == null || topic.isEmpty) return const [];
        modeKey = 't:$subjectKey|$topic';
        break;
    }

    q = q
        .where('bucket', isEqualTo: LeagueScores.bucketFor(period))
        .where('modeKey', isEqualTo: modeKey)
        .orderBy('score', descending: true)
        .limit(limit);

    final snap = await q.get().timeout(_leagueFetchTimeout);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return snap.docs.map((d) {
      final m = d.data();
      return LeagueLeaderRow(
        uid: (m['uid'] ?? '').toString(),
        displayName: (m['displayName'] ?? '').toString(),
        avatar: (m['avatar'] ?? '').toString(),
        location: _formatLocation(scope, m),
        score: (m['score'] as num?)?.toDouble() ?? 0.0,
        durationSec: (m['durationSec'] as num?)?.toInt() ?? 0,
        isMe: (m['uid'] ?? '').toString() == myUid,
      );
    }).toList();
  }

  /// Doc map listesini periyot penceresi + uid başına dedupe + sıralama
  /// pipeline'ından geçirip top-`limit` döner. Hem `fetch()` hem `watch()`
  /// burayı kullanır.
  static List<LeagueLeaderRow> _aggregateRows({
    required List<Map<String, dynamic>> docs,
    required LeagueScope scope,
    required LeaguePeriod period,
    required int limit,
  }) {
    // Periyot filtresi totals ile AYNI takvim kovası — kayan pencere değil.
    final bucket = period == LeaguePeriod.allTime
        ? null
        : LeagueScores.bucketFor(period);
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    final totalsScore = <String, double>{};
    final totalsDuration = <String, int>{};
    final earliestWhen = <String, DateTime>{};
    final infos = <String, Map<String, dynamic>>{};

    for (final m in docs) {
      final uid = (m['uid'] ?? '').toString();
      if (uid.isEmpty) continue;
      final score = (m['score'] as num?)?.toDouble() ?? 0.0;
      final dur = (m['durationSec'] as num?)?.toInt() ?? 0;
      final whenTs = m['when'];
      DateTime? when;
      if (whenTs is Timestamp) when = whenTs.toDate();
      if (bucket != null) {
        if (when == null) continue;
        final b = switch (period) {
          LeaguePeriod.daily => LeagueScores.dayBucket(when),
          LeaguePeriod.weekly => LeagueScores.weekBucket(when),
          LeaguePeriod.monthly => LeagueScores.monthBucket(when),
          LeaguePeriod.allTime => 'all',
        };
        if (b != bucket) continue;
      }

      totalsScore[uid] = (totalsScore[uid] ?? 0) + score;
      totalsDuration[uid] = (totalsDuration[uid] ?? 0) + dur;
      if (when != null) {
        final prev = earliestWhen[uid];
        if (prev == null || when.isBefore(prev)) {
          earliestWhen[uid] = when;
        }
      }
      infos[uid] ??= m;
    }

    final list = totalsScore.entries.map((e) {
      final uid = e.key;
      final m = infos[uid]!;
      return _RowWithWhen(
        LeagueLeaderRow(
          uid: uid,
          displayName: (m['displayName'] ?? '').toString(),
          avatar: (m['avatar'] ?? '').toString(),
          location: _formatLocation(scope, m),
          score: e.value,
          durationSec: totalsDuration[uid] ?? 0,
          isMe: uid == myUid,
        ),
        earliestWhen[uid],
      );
    }).toList()
      // Sıralama:
      //   1) Toplam puan DESC
      //   2) Tiebreaker — puan başı süre (saniye/puan) ASC — verimlilik:
      //      10 test atan (toplam 600sn / 50 puan = 12 sn/puan) 1 test
      //      atan (60sn / 5 puan = 12 sn/puan) ile aynı verimlilikte sayılır.
      //      Yüksek hacimli oyuncu kandırılmaz, hızlı çözen ödüllendirilir.
      //   3) Erken başlayan üstte (kayıt sırası)
      ..sort((a, b) {
        final cmpScore = b.row.score.compareTo(a.row.score);
        if (cmpScore != 0) return cmpScore;
        final aEff = a.row.score == 0
            ? double.infinity
            : a.row.durationSec / a.row.score;
        final bEff = b.row.score == 0
            ? double.infinity
            : b.row.durationSec / b.row.score;
        final cmpEff = aEff.compareTo(bEff);
        if (cmpEff != 0) return cmpEff;
        final aw = a.when;
        final bw = b.when;
        if (aw == null && bw == null) return 0;
        if (aw == null) return 1;
        if (bw == null) return -1;
        return aw.compareTo(bw);
      });
    final rows = list.map((e) => e.row).toList();
    return rows.length > limit ? rows.sublist(0, limit) : rows;
  }

  /// Kullanıcının KESİN sırası — listede kaçıncı olursa olsun (200. de
  /// 20.000. de) doğru döner.
  ///
  /// Yöntem: kendi totals dokümanı deterministik id'den okunur
  /// (uid_bucket_mode), sonra aynı scope+bucket+mode filtresiyle
  /// `score > benimki` olan doküman sayısı Firestore aggregate count() ile
  /// sayılır → sıra = üstümdeki kişi sayısı + 1. Mevcut composite
  /// indexler (scope + bucket + modeKey + score) bu sorguyu karşılar.
  ///
  /// Not: Eşit puanlılar arasında liste, süre verimliliği tiebreaker'ı ile
  /// ayrışır; count() bu inceliği bilemez — eşit puanlı herkes aynı sırayı
  /// görür (ör. iki kişi de "3."). Kabul edilebilir ve tutarlı.
  static Future<int?> myRank({
    required EduProfile profile,
    required UserLocation location,
    required LeagueScope scope,
    required LeagueMode mode,
    required LeaguePeriod period,
    String? subjectKey,
    String? topic,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.isEmpty) return null;
    if (location.countryCode.isEmpty) return null;

    // Scope alanı + değeri
    final String scopeField;
    final String scopeValue;
    switch (scope) {
      case LeagueScope.city:
        if (location.cityCode.isEmpty) return null;
        scopeField = 'scopeCity';
        scopeValue =
            '${location.countryCode}|${location.cityCode}|${profile.level}|${profile.grade}';
        break;
      case LeagueScope.country:
        scopeField = 'scopeCountry';
        scopeValue =
            '${location.countryCode}|${profile.level}|${profile.grade}';
        break;
      case LeagueScope.world:
        // Dünya = tek küresel havuz; CF yazımıyla birebir ("world").
        scopeField = 'scopeWorld';
        scopeValue = 'world';
        break;
    }

    // Mode anahtarı
    final String modeKey;
    switch (mode) {
      case LeagueMode.overall:
        modeKey = 'all';
        break;
      case LeagueMode.subject:
        if (subjectKey == null || subjectKey.isEmpty) return null;
        modeKey = 's:$subjectKey';
        break;
      case LeagueMode.topic:
        if (subjectKey == null || subjectKey.isEmpty) return null;
        if (topic == null || topic.isEmpty) return null;
        modeKey = 't:$subjectKey|$topic';
        break;
    }

    try {
      final my = await LeagueScores.myCloudTotal(
        modeKey: modeKey,
        period: period,
      );
      if (my == null || my.score <= 0) return null;

      final agg = await FirebaseFirestore.instance
          .collection('league_totals')
          .where(scopeField, isEqualTo: scopeValue)
          .where('bucket', isEqualTo: LeagueScores.bucketFor(period))
          .where('modeKey', isEqualTo: modeKey)
          .where('score', isGreaterThan: my.score)
          .count()
          .get()
          .timeout(_leagueFetchTimeout);
      return (agg.count ?? 0) + 1;
    } catch (e) {
      debugPrint('[LeagueLeaderboard] myRank count fail: $e');
      // Fallback — eski yöntem: top-200 içinde ara (geçiş dönemi verisi).
      final all = await fetch(
        profile: profile,
        location: location,
        scope: scope,
        mode: mode,
        period: period,
        subjectKey: subjectKey,
        topic: topic,
        limit: 200,
      );
      for (int i = 0; i < all.length; i++) {
        if (all[i].uid == myUid) return i + 1;
      }
      return null;
    }
  }

  /// Kullanıcı top listede görünmüyorsa liste altına eklenen
  /// "⋮ → 2 üst + ben + 2 alt" bölümü için komşu rakipleri çeker.
  ///
  /// Yöntem: kendi totals dokümanı deterministik id'den okunur, sonra aynı
  /// scope+bucket+mode filtresiyle iki sorgu atılır:
  ///   • üst komşular — `score > benimki`, score ASC, limit `span`
  ///     (en yakın üsttekiler; composite index DESC tanımlı ama Firestore
  ///     indexleri tam ters yönde de tarayabilir → ek index gerekmez)
  ///   • alt komşular — `score < benimki`, score DESC, limit `span`
  ///
  /// Dönen listeler skor DESC (görüntü) sırasındadır; `me` kullanıcının
  /// kendi totals satırıdır. Skoru yoksa / auth yoksa null.
  ///
  /// Not: Eşit puanlı kullanıcılar kesin eşitsizlik (`>`/`<`) dışında
  /// kaldığından komşu olarak görünmez — myRank()'in eşit-puan davranışıyla
  /// tutarlı, kabul edilebilir.
  static Future<
      ({
        List<LeagueLeaderRow> above,
        LeagueLeaderRow me,
        List<LeagueLeaderRow> below,
      })?> fetchNeighbors({
    required EduProfile profile,
    required UserLocation location,
    required LeagueScope scope,
    required LeagueMode mode,
    required LeaguePeriod period,
    String? subjectKey,
    String? topic,
    int span = 2,
  }) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.isEmpty) return null;
    if (location.countryCode.isEmpty) return null;

    // Scope alanı + değeri (myRank ile aynı eşleme)
    final String scopeField;
    final String scopeValue;
    switch (scope) {
      case LeagueScope.city:
        if (location.cityCode.isEmpty) return null;
        scopeField = 'scopeCity';
        scopeValue =
            '${location.countryCode}|${location.cityCode}|${profile.level}|${profile.grade}';
        break;
      case LeagueScope.country:
        scopeField = 'scopeCountry';
        scopeValue =
            '${location.countryCode}|${profile.level}|${profile.grade}';
        break;
      case LeagueScope.world:
        scopeField = 'scopeWorld';
        scopeValue = 'world';
        break;
    }

    // Mode anahtarı
    final String modeKey;
    switch (mode) {
      case LeagueMode.overall:
        modeKey = 'all';
        break;
      case LeagueMode.subject:
        if (subjectKey == null || subjectKey.isEmpty) return null;
        modeKey = 's:$subjectKey';
        break;
      case LeagueMode.topic:
        if (subjectKey == null || subjectKey.isEmpty) return null;
        if (topic == null || topic.isEmpty) return null;
        modeKey = 't:$subjectKey|$topic';
        break;
    }

    try {
      final col = FirebaseFirestore.instance.collection('league_totals');

      // Kendi satırım — tek doküman okuması (uid_bucket_mode).
      final myDoc = await col
          .doc(LeagueScores.totalsDocId(
              uid: myUid, modeKey: modeKey, period: period))
          .get()
          .timeout(_leagueFetchTimeout);
      final myData = myDoc.data();
      final myScore = (myData?['score'] as num?)?.toDouble() ?? 0.0;
      if (myData == null || myScore <= 0) return null;

      Query<Map<String, dynamic>> base = col
          .where(scopeField, isEqualTo: scopeValue)
          .where('bucket', isEqualTo: LeagueScores.bucketFor(period))
          .where('modeKey', isEqualTo: modeKey);

      final results = await Future.wait([
        base
            .where('score', isGreaterThan: myScore)
            .orderBy('score') // ASC → en yakın üsttekiler önce
            .limit(span)
            .get()
            .timeout(_leagueFetchTimeout),
        base
            .where('score', isLessThan: myScore)
            .orderBy('score', descending: true) // en yakın alttakiler önce
            .limit(span)
            .get()
            .timeout(_leagueFetchTimeout),
      ]);

      LeagueLeaderRow rowOf(Map<String, dynamic> m) => LeagueLeaderRow(
            uid: (m['uid'] ?? '').toString(),
            displayName: (m['displayName'] ?? '').toString(),
            avatar: (m['avatar'] ?? '').toString(),
            location: _formatLocation(scope, m),
            score: (m['score'] as num?)?.toDouble() ?? 0.0,
            durationSec: (m['durationSec'] as num?)?.toInt() ?? 0,
            isMe: (m['uid'] ?? '').toString() == myUid,
          );

      // Üst komşular ASC geldi → görüntü için DESC'e çevir.
      final above =
          results[0].docs.map((d) => rowOf(d.data())).toList().reversed.toList();
      final below = results[1].docs.map((d) => rowOf(d.data())).toList();
      return (above: above, me: rowOf(myData), below: below);
    } catch (e) {
      debugPrint('[LeagueLeaderboard] fetchNeighbors fail: $e');
      return null;
    }
  }

  static String _formatLocation(LeagueScope scope, Map<String, dynamic> doc) {
    switch (scope) {
      case LeagueScope.city:
        return _humanCity((doc['cityCode'] ?? '').toString());
      case LeagueScope.country:
        return _humanCity((doc['cityCode'] ?? '').toString());
      case LeagueScope.world:
        final cc = (doc['countryCode'] ?? '').toString().toUpperCase();
        return '${_flag(cc)} ${_countryName(cc)}';
    }
  }

  /// GLOBAL-FIRST ülke adı: önce kAllCountries'teki YEREL (native) ad —
  /// her dildeki kullanıcı için nötr; yoksa TR harita, o da yoksa ham kod.
  static String _countryName(String cc) {
    final lc = cc.toLowerCase() == 'gb' ? 'uk' : cc.toLowerCase();
    for (final c in kAllCountries) {
      if (c.key == lc) return c.name;
    }
    return _countryNameTr[cc] ?? cc;
  }

  /// ISO ülke kodu → Türkçe ülke adı (Bilgi Ligi UI Türkçe odaklı).
  /// Bilinmeyen kodlar için ham kod döner.
  static const _countryNameTr = <String, String>{
    'TR': 'Türkiye',
    'DE': 'Almanya',
    'US': 'ABD',
    'FR': 'Fransa',
    'JP': 'Japonya',
    'GB': 'İngiltere',
    'UK': 'İngiltere',
    'KR': 'Güney Kore',
    'IT': 'İtalya',
    'ES': 'İspanya',
    'BR': 'Brezilya',
    'NL': 'Hollanda',
    'PT': 'Portekiz',
    'RU': 'Rusya',
    'CN': 'Çin',
    'IN': 'Hindistan',
    'CA': 'Kanada',
    'AU': 'Avustralya',
    'MX': 'Meksika',
    'AR': 'Arjantin',
    'EG': 'Mısır',
    'AZ': 'Azerbaycan',
    'GR': 'Yunanistan',
    'BG': 'Bulgaristan',
    'IR': 'İran',
    'IQ': 'Irak',
    'SY': 'Suriye',
    'SA': 'Suudi Arabistan',
    'AE': 'BAE',
    'PK': 'Pakistan',
    'BD': 'Bangladeş',
    'TH': 'Tayland',
    'VN': 'Vietnam',
    'ID': 'Endonezya',
    'PH': 'Filipinler',
    'PL': 'Polonya',
    'UA': 'Ukrayna',
    'RO': 'Romanya',
    'CZ': 'Çekya',
    'AT': 'Avusturya',
    'CH': 'İsviçre',
    'BE': 'Belçika',
    'SE': 'İsveç',
    'NO': 'Norveç',
    'DK': 'Danimarka',
    'FI': 'Finlandiya',
    'IE': 'İrlanda',
    'IL': 'İsrail',
    'JO': 'Ürdün',
    'LB': 'Lübnan',
    'KZ': 'Kazakistan',
    'UZ': 'Özbekistan',
    'KG': 'Kırgızistan',
    'TM': 'Türkmenistan',
    'GE': 'Gürcistan',
    'AM': 'Ermenistan',
    'NZ': 'Yeni Zelanda',
    'ZA': 'Güney Afrika',
    'NG': 'Nijerya',
    'KE': 'Kenya',
    'MA': 'Fas',
    'DZ': 'Cezayir',
    'TN': 'Tunus',
    'CL': 'Şili',
    'CO': 'Kolombiya',
    'PE': 'Peru',
    'VE': 'Venezuela',
    'CU': 'Küba',
    'HR': 'Hırvatistan',
    'RS': 'Sırbistan',
    'AL': 'Arnavutluk',
    'BA': 'Bosna Hersek',
    'XK': 'Kosova',
    'MK': 'Kuzey Makedonya',
    'HU': 'Macaristan',
    'SK': 'Slovakya',
    'SI': 'Slovenya',
    'EE': 'Estonya',
    'LV': 'Letonya',
    'LT': 'Litvanya',
    'IS': 'İzlanda',
    'CY': 'Kıbrıs',
    'MT': 'Malta',
  };

  static String _humanCity(String code) {
    if (code.isEmpty) return '';
    // istanbul → İstanbul (ilk harf büyük)
    final cleaned = code.replaceAll('_', ' ');
    if (cleaned.isEmpty) return code;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  static String _flag(String cc) {
    if (cc.length != 2) return '🌍';
    const baseLetter = 0x41;
    const baseRegional = 0x1F1E6;
    final upper = cc.toUpperCase();
    final c1 = upper.codeUnitAt(0);
    final c2 = upper.codeUnitAt(1);
    if (c1 < baseLetter || c1 > baseLetter + 25) return '🌍';
    if (c2 < baseLetter || c2 > baseLetter + 25) return '🌍';
    return String.fromCharCodes([
      baseRegional + (c1 - baseLetter),
      baseRegional + (c2 - baseLetter),
    ]);
  }
}

// Sıralama tiebreaker'ı için doc'un en erken `when` zamanını taşıyan
// dahili kayıt yapısı.
class _RowWithWhen {
  final LeagueLeaderRow row;
  final DateTime? when;
  const _RowWithWhen(this.row, this.when);
}
