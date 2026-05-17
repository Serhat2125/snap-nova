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
        q = q.where(
          'scopeWorld',
          isEqualTo: '${profile.level}|${profile.grade}',
        );
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

    // 4) Periyot filter + uid başına TOPLAM puan (Bilgi Ligi sıralaması
    //    "toplam puan" üzerinden — her test puanı kullanıcının toplamına eklenir).
    final cutoff = period.window == null
        ? null
        : DateTime.now().subtract(period.window!);
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    final totalsScore = <String, double>{};
    final totalsDuration = <String, int>{};
    // Tiebreaker: aynı (score, duration) durumunda EN ESKİ aktivite üstte
    // (daha önce ulaşan kazanır). uid başına en erken `when` saklanır.
    final earliestWhen = <String, DateTime>{};
    final infos = <String, Map<String, dynamic>>{};

    for (final doc in snap.docs) {
      final m = doc.data();
      final uid = (m['uid'] ?? '').toString();
      if (uid.isEmpty) continue;
      final score = (m['score'] as num?)?.toDouble() ?? 0.0;
      final dur = (m['durationSec'] as num?)?.toInt() ?? 0;
      final whenTs = m['when'];
      DateTime? when;
      if (whenTs is Timestamp) when = whenTs.toDate();
      if (cutoff != null && (when == null || when.isBefore(cutoff))) continue;

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
      // Sıralama: skor DESC, eşitlikte daha az süre, eşitlikte daha erken `when`.
      ..sort((a, b) {
        final cmpScore = b.row.score.compareTo(a.row.score);
        if (cmpScore != 0) return cmpScore;
        final cmpDur = a.row.durationSec.compareTo(b.row.durationSec);
        if (cmpDur != 0) return cmpDur;
        // Tiebreaker: önce gelen kazanır.
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

  /// Sadece kendi skor pozisyonunu çek (ayrı query, hızlı tekil bilgi için).
  static Future<int?> myRank({
    required EduProfile profile,
    required UserLocation location,
    required LeagueScope scope,
    required LeagueMode mode,
    required LeaguePeriod period,
    String? subjectKey,
    String? topic,
  }) async {
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
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return null;
    for (int i = 0; i < all.length; i++) {
      if (all[i].uid == myUid) return i + 1;
    }
    return null;
  }

  static String _formatLocation(LeagueScope scope, Map<String, dynamic> doc) {
    switch (scope) {
      case LeagueScope.city:
        return _humanCity((doc['cityCode'] ?? '').toString());
      case LeagueScope.country:
        return _humanCity((doc['cityCode'] ?? '').toString());
      case LeagueScope.world:
        final cc = (doc['countryCode'] ?? '').toString().toUpperCase();
        final name = _countryNameTr[cc] ?? cc;
        return '${_flag(cc)} $name';
    }
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
