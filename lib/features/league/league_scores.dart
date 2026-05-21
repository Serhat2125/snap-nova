// ═══════════════════════════════════════════════════════════════════════════════
//  LeagueScores — kullanıcının Bilgi Ligi test sonuçlarının deposu.
//
//  Çift katmanlı:
//    1) Yerel cache  → SharedPreferences (offline kullanım, hızlı ortalama)
//    2) Cloud kayıt  → Firestore `league_attempts` flat collection
//                       (denormalize: location, level, grade, scope key'leri)
//
//  Auth varsa cloud'a da yazılır; yoksa sadece yerel kalır.
//  Periyot tanımları:
//    daily   → son 24 saat
//    weekly  → son 7 gün
//    monthly → son 30 gün
//    allTime → hepsi
//
//  Skor: BilgiLigiQuizScreen sonunda hesaplanan 0-1200 arası tam sayı.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/education_profile.dart';
import '../leaderboard/domain/user_location.dart';

enum LeaguePeriod { daily, weekly, monthly, allTime }

extension LeaguePeriodX on LeaguePeriod {
  Duration? get window {
    switch (this) {
      case LeaguePeriod.daily:
        return const Duration(days: 1);
      case LeaguePeriod.weekly:
        return const Duration(days: 7);
      case LeaguePeriod.monthly:
        return const Duration(days: 30);
      case LeaguePeriod.allTime:
        return null; // pencere yok
    }
  }

  /// UI etiketi — quiz badge, filtre chip, vb. Public — herhangi bir
  /// ekran tarafından kullanılabilir. (`label` adı bilgi_ligi_screen.dart
  /// içindeki özel uzantı ile çakışmasın diye `displayLabel` seçildi.)
  String get displayLabel {
    switch (this) {
      case LeaguePeriod.daily:
        return 'Günlük';
      case LeaguePeriod.weekly:
        return 'Haftalık';
      case LeaguePeriod.monthly:
        return 'Aylık';
      case LeaguePeriod.allTime:
        return 'Genel';
    }
  }
}

class LeagueAttempt {
  final String subjectKey;
  /// null ya da boş = "tüm ders" (drill-down olmadan üretilen test).
  final String? topic;
  /// Net puan (1 net = 1 puan). Ondalıklı tutulur: 7.75 net = 7.75 puan.
  final double score;
  /// Bu testin toplam çözüm süresi (saniye). Aynı puanda olan kullanıcıları
  /// ayırmak için tiebreaker olarak kullanılır — kim daha hızlıysa o üstte.
  final int durationSec;
  final DateTime when;
  /// Bu attempt'in oluşturulduğu konum (snapshot). Kullanıcı konum değiştirince
  /// eski skor doğru scope'ta kalır — yeni şehrin sıralamasına sızmaz.
  /// Eski kayıtlarda null olabilir; null durumunda güncel location kullanılır.
  final String? countryCodeSnapshot;
  final String? cityCodeSnapshot;
  /// İdempotent cloud submit için stabil client-side ID. Retry'da aynı ID
  /// kullanılır → Firestore upsert'i duplicate üretmez. Eski kayıtlarda null
  /// olabilir — fallback olarak runtime'da üretilir.
  final String? clientSubmitId;

  const LeagueAttempt({
    required this.subjectKey,
    required this.topic,
    required this.score,
    required this.durationSec,
    required this.when,
    this.countryCodeSnapshot,
    this.cityCodeSnapshot,
    this.clientSubmitId,
  });

  Map<String, dynamic> toJson() => {
        'subject': subjectKey,
        'topic': topic ?? '',
        'score': score,
        'durationSec': durationSec,
        'when': when.toIso8601String(),
        if (countryCodeSnapshot != null && countryCodeSnapshot!.isNotEmpty)
          'cc': countryCodeSnapshot,
        if (cityCodeSnapshot != null && cityCodeSnapshot!.isNotEmpty)
          'city': cityCodeSnapshot,
        if (clientSubmitId != null && clientSubmitId!.isNotEmpty)
          'csid': clientSubmitId,
      };

  factory LeagueAttempt.fromJson(Map<String, dynamic> j) => LeagueAttempt(
        subjectKey: (j['subject'] ?? '').toString(),
        topic: () {
          final t = (j['topic'] ?? '').toString();
          return t.isEmpty ? null : t;
        }(),
        score: (j['score'] as num?)?.toDouble() ?? 0.0,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
        when: DateTime.tryParse((j['when'] ?? '').toString()) ?? DateTime.now(),
        countryCodeSnapshot: () {
          final v = (j['cc'] ?? '').toString();
          return v.isEmpty ? null : v;
        }(),
        cityCodeSnapshot: () {
          final v = (j['city'] ?? '').toString();
          return v.isEmpty ? null : v;
        }(),
        clientSubmitId: () {
          final v = (j['csid'] ?? '').toString();
          return v.isEmpty ? null : v;
        }(),
      );
}

class LeagueScoreSummary {
  final double? average;  // null = veri yok
  final double? best;     // null = veri yok
  final double total;     // toplam puan (sıralama için kullanılan ana metrik)
  final int attempts;     // periyot içindeki deneme sayısı
  const LeagueScoreSummary({
    required this.average,
    required this.best,
    required this.total,
    required this.attempts,
  });

  bool get hasData => attempts > 0;
}

class LeagueScores {
  static const _key = 'bilgi_ligi_attempts_v1';
  /// Yedek key — primary key parse fail olursa fallback olarak okunur.
  /// add() her yazma'da hem primary hem backup'a yazar (atomik değil ama
  /// rolling backup mantığı: 99% durumda biri sağlam kalır).
  static const _backupKey = 'bilgi_ligi_attempts_backup_v1';

  // Bellek içi cache — bootstrap sonrası bir kez SharedPref'ten okunur,
  // sonraki erişimler senkron çalışır.
  static List<LeagueAttempt>? _cache;

  // Concurrent add() çağrıları arasında race condition kapansın. SharedPref
  // read-modify-write tek sıralı kuyrukta. SolutionsStorage/_ActivityStore
  // pattern ile aynı.
  static Future<void> _writeLock = Future.value();
  static Future<T> _serialize<T>(Future<T> Function() task) {
    final prev = _writeLock;
    final c = Completer<T>();
    _writeLock = prev.then((_) async {
      try {
        c.complete(await task());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  // Tek bir entry parse — partial recovery için. Bozuk satır null döner.
  static LeagueAttempt? _parseOne(dynamic raw) {
    try {
      if (raw is! Map) return null;
      return LeagueAttempt.fromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static List<LeagueAttempt> _parseList(String raw) {
    final out = <LeagueAttempt>[];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        for (final item in list) {
          final p = _parseOne(item);
          if (p != null) out.add(p);
        }
      }
    } catch (e) {
      debugPrint('[LeagueScores] JSON parse fail: $e');
    }
    return out;
  }

  static Future<List<LeagueAttempt>> loadAll() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      final parsed = _parseList(raw);
      if (parsed.isNotEmpty) {
        _cache = parsed;
        return _cache!;
      }
      // Primary key boş geldi veya tamamen bozuk → backup'ı dene.
      debugPrint('[LeagueScores] primary key bozuk; backup deneniyor');
    }
    final backup = prefs.getString(_backupKey);
    if (backup != null && backup.isNotEmpty) {
      final parsed = _parseList(backup);
      _cache = parsed;
      if (parsed.isNotEmpty) {
        debugPrint('[LeagueScores] backup\'tan ${parsed.length} kayıt kurtarıldı');
      }
      return _cache!;
    }
    _cache = <LeagueAttempt>[];
    return _cache!;
  }

  /// Yerele yaz + (mümkünse) cloud'a yaz.
  /// `profile` ve `location` cloud yazımı için gereklidir; yoksa sadece yerel.
  /// `displayName` / `avatar` opsiyonel — null ise FirebaseAuth'tan alınır.
  static Future<void> add(
    LeagueAttempt attempt, {
    EduProfile? profile,
    UserLocation? location,
    String? displayName,
    String? avatar,
  }) {
    return _serialize(() async {
      // Attempt'e cityCode snapshot + clientSubmitId yoksa bu noktada üret.
      // Idempotent cloud upsert için kararlı bir ID gerekli.
      final clientSubmitId = attempt.clientSubmitId ?? _newClientSubmitId();
      final withSnapshot = LeagueAttempt(
        subjectKey: attempt.subjectKey,
        topic: attempt.topic,
        score: attempt.score,
        durationSec: attempt.durationSec,
        when: attempt.when,
        countryCodeSnapshot:
            attempt.countryCodeSnapshot ?? location?.countryCode,
        cityCodeSnapshot: attempt.cityCodeSnapshot ?? location?.cityCode,
        clientSubmitId: clientSubmitId,
      );

      // 1) Yerel cache + pref + backup
      final list = await loadAll();
      list.add(withSnapshot);
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
      try {
        await prefs.setString(_key, encoded);
        // Backup write — primary corrupt olursa kurtarma için.
        await prefs.setString(_backupKey, encoded);
      } catch (e) {
        debugPrint('[LeagueScores] local write fail: $e');
      }

      // 2) Cloud (auth + profile + location varsa) — idempotent doc id.
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) return;
        if (profile == null || location == null) return;
        if (location.countryCode.isEmpty || location.cityCode.isEmpty) return;

        final scopeWorld = '${profile.level}|${profile.grade}';
        final scopeCountry =
            '${location.countryCode}|${profile.level}|${profile.grade}';
        final scopeCity =
            '${location.countryCode}|${location.cityCode}|${profile.level}|${profile.grade}';

        // Doc id = "<uid>_<clientSubmitId>" → retry'da aynı doc, duplicate yok.
        final docId = '${uid}_$clientSubmitId';
        final ref = FirebaseFirestore.instance
            .collection('league_attempts')
            .doc(docId);
        await ref.set({
          'uid': uid,
          'clientSubmitId': clientSubmitId,
          'displayName': (displayName ?? '').trim().isEmpty
              ? (FirebaseAuth.instance.currentUser?.displayName ?? '')
              : displayName!.trim(),
          'avatar': avatar ?? '',
          'countryCode': location.countryCode,
          'cityCode': location.cityCode,
          'level': profile.level,
          'grade': profile.grade,
          'scopeWorld': scopeWorld,
          'scopeCountry': scopeCountry,
          'scopeCity': scopeCity,
          'subjectKey': attempt.subjectKey,
          'topic': attempt.topic ?? '',
          'hasTopic': attempt.topic != null && attempt.topic!.isNotEmpty,
          'score': attempt.score,
          'durationSec': attempt.durationSec,
          // Tiebreaker: aynı (score, duration) olanlar için kronolojik sıra.
          'when': Timestamp.fromDate(attempt.when),
          // Server-side enforcement için ek timestamp — istemci saatine
          // güvenmeden weekly/monthly pencerelerini doğrulamak için.
          'serverWhen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 12));
      } catch (e) {
        // Cloud hatası yutulur — yerel kayıt zaten var, kullanıcıyı bloklamayız.
        debugPrint('[LeagueScores] cloud submit fail: $e');
      }
    });
  }

  /// Yeni clientSubmitId üret — timestamp + 8-haneli rastgele.
  static String _newClientSubmitId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rng = math.Random.secure();
    final tail = rng.nextInt(0x7fffffff).toRadixString(36).padLeft(6, '0');
    return '${now.toRadixString(36)}_$tail';
  }

  /// Eski sürümlerde tutulan basit "subject|topic → score" map'inden, varsa
  /// çek ve yeni sisteme tek tek migrate et. Sadece ilk açılışta gerekir.
  static Future<void> migrateLegacyIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('bilgi_ligi_scores_v1');
    if (raw == null || raw.isEmpty) return;
    final list = await loadAll();
    if (list.isNotEmpty) {
      // Zaten yeni format kullanılıyor; eski key'i temizle.
      await prefs.remove('bilgi_ligi_scores_v1');
      return;
    }
    final migrated = <LeagueAttempt>[];
    for (final part in raw.split(';')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq < 0) continue;
      final k = part.substring(0, eq);
      final v = int.tryParse(part.substring(eq + 1));
      if (v == null) continue;
      final pipe = k.indexOf('|');
      final subj = pipe < 0 ? k : k.substring(0, pipe);
      final topic = pipe < 0 ? '' : k.substring(pipe + 1);
      migrated.add(LeagueAttempt(
        subjectKey: subj,
        topic: topic.isEmpty ? null : topic,
        score: v.toDouble(),
        durationSec: 0, // eski kayıtlarda süre yoktu
        when: DateTime.now().subtract(const Duration(days: 1)),
      ));
    }
    if (migrated.isNotEmpty) {
      _cache = migrated;
      final encoded =
          jsonEncode(migrated.map((e) => e.toJson()).toList());
      await prefs.setString(_key, encoded);
    }
    await prefs.remove('bilgi_ligi_scores_v1');
  }

  // ── Filtreleme yardımcıları ─────────────────────────────────────────────────

  static List<LeagueAttempt> _filtered(
    List<LeagueAttempt> source, {
    String? subjectKey,
    String? topic,
    bool topicNullMeansAny = true,
    required LeaguePeriod period,
  }) {
    final win = period.window;
    final cutoff = win == null ? null : DateTime.now().subtract(win);
    return source.where((a) {
      if (subjectKey != null && a.subjectKey != subjectKey) return false;
      if (topic != null) {
        if (a.topic != topic) return false;
      } else if (!topicNullMeansAny) {
        if (a.topic != null && a.topic!.isNotEmpty) return false;
      }
      if (cutoff != null && a.when.isBefore(cutoff)) return false;
      return true;
    }).toList();
  }

  static LeagueScoreSummary _summarize(List<LeagueAttempt> attempts) {
    if (attempts.isEmpty) {
      return const LeagueScoreSummary(
          average: null, best: null, total: 0.0, attempts: 0);
    }
    double total = 0;
    double best = -1;
    for (final a in attempts) {
      total += a.score;
      if (a.score > best) best = a.score;
    }
    return LeagueScoreSummary(
      average: total / attempts.length,
      best: best,
      total: total,
      attempts: attempts.length,
    );
  }

  // ── Sorgu API'si ────────────────────────────────────────────────────────────

  /// Üst üste quiz çözülen gün sayısı (streak).
  /// Bugün quiz çözülmediyse dünden geri başlar (dünden başlayarak ardışık
  /// günler sayılır). Hiç attempt yoksa 0 döner.
  ///
  /// Mantık:
  ///   - Tüm attempt'lerin tarihlerini güne yuvarla, eşsiz gün seti yap.
  ///   - Bugünden geriye doğru git: hangi günde aktivite varsa +1, ilk
  ///     boş günde dur. Bugün yoksa dün'den başla (1 günlük tolerans).
  static Future<int> currentStreak() async {
    final list = await loadAll();
    if (list.isEmpty) return 0;
    final days = <DateTime>{};
    for (final a in list) {
      final d = DateTime(a.when.year, a.when.month, a.when.day);
      days.add(d);
    }
    final today = DateTime.now();
    DateTime cursor = DateTime(today.year, today.month, today.day);
    // Bugün boşsa dünden başla — günlük streak'i sıfıra düşürmemek için
    // 1 gün tolerans.
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(cursor)) return 0;
    }
    int streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Belirli bir konu için (ders + konu eşleşmeli) skor özeti.
  static Future<LeagueScoreSummary> forTopic({
    required String subjectKey,
    required String topic,
    required LeaguePeriod period,
  }) async {
    final list = await loadAll();
    final filtered = _filtered(
      list,
      subjectKey: subjectKey,
      topic: topic,
      period: period,
    );
    return _summarize(filtered);
  }

  /// Belirli bir ders için (tüm konular dâhil) skor ortalaması.
  static Future<LeagueScoreSummary> forSubject({
    required String subjectKey,
    required LeaguePeriod period,
  }) async {
    final list = await loadAll();
    final filtered = _filtered(
      list,
      subjectKey: subjectKey,
      topic: null,
      topicNullMeansAny: true,
      period: period,
    );
    return _summarize(filtered);
  }

  /// Tüm derslerin / tüm konuların ortalaması.
  static Future<LeagueScoreSummary> overall({
    required LeaguePeriod period,
  }) async {
    final list = await loadAll();
    final filtered = _filtered(list, period: period);
    return _summarize(filtered);
  }
}
