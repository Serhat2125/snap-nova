// ═══════════════════════════════════════════════════════════════════════════════
//  LeagueScores — kullanıcının Bilgi Ligi test sonuçlarının deposu.
//
//  Çift katmanlı:
//    1) Yerel cache  → SharedPreferences (offline kullanım, hızlı ortalama)
//    2) Cloud kayıt  → `submitLeagueAttempt` Cloud Function'ı üzerinden.
//       İstemci Firestore'a DOĞRUDAN YAZMAZ (rules kapalı) — fonksiyon
//       rate limit, sunucu saati kovası, idempotens ve attempt↔totals
//       atomikliğini garanti eder. Başarısız gönderimler yerel OUTBOX'a
//       girer, sonraki açılışta flushOutbox() ile tekrar denenir.
//
//  Periyot tanımları — liderlik tablosuyla AYNI takvim kovaları (UTC):
//    daily   → bugünün UTC günü        (d:YYYY-MM-DD)
//    weekly  → bu ISO haftası          (w:YYYY-Wnn)
//    monthly → bu takvim ayı           (m:YYYY-MM)
//    allTime → hepsi                   (all)
//
//  Skor: 1 net = 1 puan (test başına max 10).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/education_profile.dart';
import '../../services/runtime_translator.dart';
import '../../services/user_profile_service.dart';
import '../../screens/academic_planner.dart' show logActivitySession;
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
  /// Bu attempt'in oluşturulduğu konum (snapshot). Attempt GEÇMİŞİ konum
  /// değişse de kazanıldığı yerde kalır. TOPLAMLAR (league_totals) ise
  /// BİLİNÇLİ olarak kullanıcının SON konumunu izler: kullanıcı şehir/sınıf
  /// değiştirip yeni test çözünce birikmiş toplamı ve sıralaması yeni
  /// kapsama taşınır (bkz. league_submit.ts totals merge yazımı).
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
    // Sunucu saat farkını da ilk erişimde yükle (kova hesapları için).
    await _loadServerOffset();
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

      // "Çalışma Takvimim"e de yaz — lig quizleri takvimde görünsün.
      if (withSnapshot.durationSec > 0) {
        unawaited(logActivitySession(
          subject: withSnapshot.subjectKey.isEmpty
              ? 'Bilgi Ligi'
              : withSnapshot.subjectKey,
          topic: withSnapshot.topic ?? '',
          type: 'lig',
          durationSec: withSnapshot.durationSec,
        ));
      }

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

      // 2) Cloud — submitLeagueAttempt Cloud Function'ı (tek yazım yolu).
      // GLOBAL-FIRST GÜVENLİK AĞI: Kullanıcı konum SEÇMEMİŞSE bile skor
      // buluta gitmeli — ülke kodu EduProfile.country'den türetilir, şehir
      // boş kalır (şehir sıralamasına girmez ama ülke+dünya sıralamasında
      // görünür).
      if (profile == null) return;
      final countryCode = effectiveCountryCode(profile, location);
      if (countryCode.isEmpty) return;

      final resolvedName = (displayName ?? '').trim().isEmpty
          ? (FirebaseAuth.instance.currentUser?.displayName ?? '')
          : displayName!.trim();

      final payload = <String, dynamic>{
        'clientSubmitId': clientSubmitId,
        'subjectKey': withSnapshot.subjectKey,
        'topic': withSnapshot.topic ?? '',
        'score': withSnapshot.score,
        'durationSec': withSnapshot.durationSec,
        'whenMs': withSnapshot.when.toUtc().millisecondsSinceEpoch,
        'countryCode': countryCode,
        // Şehir slug'ı savunmalı normalize: farklı kaynaklardan (Gemini
        // resolver, eski kayıt) gelen "Istanbul"/"istanbul " varyantları
        // aynı şehir havuzunda toplansın. CF tarafı da aynı normalizasyonu
        // uygular; okuma tarafı LeagueLeaderboardService'te normalize edilir.
        'cityCode': (location?.cityCode ?? '').trim().toLowerCase(),
        'level': profile.level,
        'grade': profile.grade,
        'displayName': resolvedName,
        'avatar': avatar ?? '',
      };

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        // Auth henüz yok — puanı DÜŞÜRME (eskiden sessizce kayboluyordu:
        // "ilk test puanım toplanmadı" şikayetinin kök nedeni). Outbox'a
        // al; giriş sonrası flushOutbox() aynı clientSubmitId ile güvenle
        // gönderir (CF idempotent, çift sayım yok).
        await _enqueueOutbox(payload);
        return;
      }

      final sent = await _submitToCloud(payload);
      if (!sent) {
        // Retry edilebilir hata → outbox'a al; sonraki açılışta
        // flushOutbox() clientSubmitId sayesinde güvenle tekrar dener.
        await _enqueueOutbox(payload);
      }
    });
  }

  // ── Cloud gönderim + outbox ────────────────────────────────────────────────

  static HttpsCallable get _submitCallable =>
      FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'submitLeagueAttempt',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );

  /// Tek bir gönderimi Cloud Function'a iletir.
  /// true  → işlendi (veya kalıcı olarak reddedildi — retry ANLAMSIZ).
  /// false → geçici hata (ağ/timeout/rate) — outbox'ta bekletilmeli.
  static Future<bool> _submitToCloud(Map<String, dynamic> payload) async {
    try {
      final res = await _submitCallable.call<Map<dynamic, dynamic>>(payload);
      final data = res.data;
      final serverNowMs = (data['serverNowMs'] as num?)?.toInt();
      if (serverNowMs != null) {
        await _storeServerOffset(serverNowMs);
      }
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[LeagueScores] cloud submit fail (${e.code}): ${e.message}');
      // Kalıcı retler: aynı payload asla geçmez → outbox'ı doldurma.
      const permanent = {
        'invalid-argument',
        'permission-denied',
        'failed-precondition',
      };
      return permanent.contains(e.code);
    } catch (e) {
      debugPrint('[LeagueScores] cloud submit fail: $e');
      return false; // ağ / timeout → retry
    }
  }

  static const _outboxKey = 'bilgi_ligi_outbox_v1';
  static const _outboxMaxTries = 20;

  static Future<void> _enqueueOutbox(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_outboxKey);
      final list = <Map<String, dynamic>>[];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) list.add(e.cast<String, dynamic>());
          }
        }
      }
      list.add({'payload': payload, 'tries': 0});
      await prefs.setString(_outboxKey, jsonEncode(list));
      debugPrint('[LeagueScores] outbox +1 (bekleyen: ${list.length})');
    } catch (e) {
      debugPrint('[LeagueScores] outbox yazılamadı: $e');
    }
  }

  /// Bekleyen cloud gönderimlerini tekrar dener. Bilgi Ligi ekranı açılışında
  /// çağrılır; idempotent (clientSubmitId) olduğu için çift sayım riski yok.
  /// Skor GÖNDERİMİNDE ve sıralama OKUMASINDA kullanılan ülke kodu — tek
  /// formül: konum seçiliyse onun kodu, değilse eğitim profili ülkesi
  /// (upper-case). bilgi_ligi_screen._effectiveLocation da BUNU kullanır;
  /// iki taraf ayrışırsa "puan buluta yazılıyor ama kullanıcı sıralamada
  /// görünmüyor" hatası geri gelir (2026-07-08'de yaşandı). Tutarlılık
  /// league_location_consistency_test.dart ile sabitlenmiştir.
  static String effectiveCountryCode(
      EduProfile? profile, UserLocation? location) {
    final loc = (location?.countryCode ?? '').trim();
    final cc = loc.isNotEmpty
        ? loc.toUpperCase()
        : (profile?.country ?? '').trim().toUpperCase();
    // Eğitim profili 'uk' kodunu, LocationCatalog ISO 'GB' kodunu kullanıyor;
    // normalize edilmezse aynı ülke iki ayrı liderlik havuzuna bölünüyordu.
    // CF tarafı (league_submit.ts) da aynı normalizasyonu uygular.
    return cc == 'UK' ? 'GB' : cc;
  }

  static Future<void> flushOutbox() {
    return _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_outboxKey);
      if (raw == null || raw.isEmpty) return;
      List<dynamic> decoded;
      try {
        decoded = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        await prefs.remove(_outboxKey);
        return;
      }
      if (decoded.isEmpty) {
        await prefs.remove(_outboxKey);
        return;
      }
      if (FirebaseAuth.instance.currentUser == null) return;

      final remaining = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();
        final payload = (m['payload'] as Map?)?.cast<String, dynamic>();
        final tries = (m['tries'] as num?)?.toInt() ?? 0;
        if (payload == null || tries >= _outboxMaxTries) continue;
        final ok = await _submitToCloud(payload);
        if (!ok) {
          remaining.add({'payload': payload, 'tries': tries + 1});
        }
      }
      if (remaining.isEmpty) {
        await prefs.remove(_outboxKey);
      } else {
        await prefs.setString(_outboxKey, jsonEncode(remaining));
      }
    });
  }

  /// TEK SEFERLİK ONARIM — soru sayısı seçimi (5/10/15/20) eklendiğinde
  /// sunucu tek-test tavanı hâlâ 10 puandı; 10 üzeri netler invalid-argument
  /// ile KALICI reddedilip outbox'a bile girmeden kayboluyordu (puan yerelde
  /// görünüyor ama şehir/ülke/dünya sıralamasına hiç yazılmıyordu). Tavan
  /// 20'ye çıkarıldı; bu rutin yerel kayıtlardaki 10 üzeri puanlı attempt'leri
  /// outbox'a koyar — flushOutbox idempotent gönderir (CF clientSubmitId ile
  /// dedupe eder, çift sayım imkânsız). Başarıyla tarandıktan sonra pref
  /// bayrağıyla bir daha çalışmaz.
  static const _capRepairKey = 'bilgi_ligi_cap10_repair_done_v1';
  static Future<void> repairCapRejectedScores({
    EduProfile? profile,
    UserLocation? location,
    String? displayName,
  }) {
    return _serialize(() async {
      if (profile == null) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_capRepairKey) ?? false) return;
      final fallbackCc = effectiveCountryCode(profile, location);
      final list = await loadAll();
      final resolvedName = (displayName ?? '').trim().isEmpty
          ? (FirebaseAuth.instance.currentUser?.displayName ?? '')
          : displayName!.trim();
      var queued = 0;
      for (final a in list) {
        // Eski tavanın (10.01) altındakiler zaten kabul edilmişti.
        if (a.score <= 10.01) continue;
        final csid = a.clientSubmitId;
        if (csid == null || csid.isEmpty) continue;
        final cc = (a.countryCodeSnapshot ?? '').isNotEmpty
            ? a.countryCodeSnapshot!
            : fallbackCc;
        if (cc.isEmpty) continue;
        await _enqueueOutbox({
          'clientSubmitId': csid,
          'subjectKey': a.subjectKey,
          'topic': a.topic ?? '',
          'score': a.score,
          'durationSec': a.durationSec,
          'whenMs': a.when.toUtc().millisecondsSinceEpoch,
          'countryCode': cc,
          'cityCode': a.cityCodeSnapshot ?? location?.cityCode ?? '',
          'level': profile.level,
          'grade': profile.grade,
          'displayName': resolvedName,
          'avatar': '',
        });
        queued++;
      }
      if (queued > 0) {
        debugPrint('[LeagueScores] tavan onarımı: $queued kayıt outbox\'a alındı');
      }
      await prefs.setBool(_capRepairKey, true);
    });
  }

  /// Liderlik adı/avatarını geriye dönük senkronize eder (anonim mod
  /// açıldı/kapandı veya profil adı değişti). Fire-and-forget kullanım için
  /// güvenli — hata yutulur, bir sonraki gönderimde zaten güncellenir.
  static Future<void> syncDisplayName(String displayName,
      {String avatar = ''}) async {
    final name = displayName.trim();
    if (name.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'bilgi_ligi_synced_name_v1';
      if (prefs.getString(key) == name) return; // değişmemiş → çağrı yok
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
            'updateLeagueDisplayName',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<dynamic, dynamic>>(
              {'displayName': name, 'avatar': avatar});
      await prefs.setString(key, name);
    } catch (e) {
      debugPrint('[LeagueScores] name sync fail: $e');
    }
  }

  // ── Sunucu saati düzeltmesi ────────────────────────────────────────────────
  // Takvim kovaları sunucu saatine göre işler; cihaz saati yanlışsa
  // kullanıcı yanlış (çoğu zaman boş) kovaya bakar. Her başarılı cloud
  // gönderiminde sunucu zamanı alınır ve fark saklanır; bucketFor() bu
  // düzeltilmiş zamanı kullanır.
  static Duration _serverOffset = Duration.zero;
  static bool _offsetLoaded = false;
  static const _offsetPrefKey = 'bilgi_ligi_server_offset_ms_v1';

  static Future<void> _storeServerOffset(int serverNowMs) async {
    final offset = Duration(
        milliseconds:
            serverNowMs - DateTime.now().toUtc().millisecondsSinceEpoch);
    _serverOffset = offset;
    _offsetLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_offsetPrefKey, offset.inMilliseconds);
    } catch (_) {/* kalıcı yazım başarısız → bellek içi değer yeter */}
  }

  static Future<void> _loadServerOffset() async {
    if (_offsetLoaded) return;
    _offsetLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_offsetPrefKey);
      if (ms != null) _serverOffset = Duration(milliseconds: ms);
    } catch (_) {/* offset yok → cihaz saati */}
  }

  /// Sunucu-düzeltmeli "şimdi" — kova hesapları bunu kullanır.
  static DateTime correctedNow() => DateTime.now().add(_serverOffset);

  // ── Takvim kovası yardımcıları (UTC — tüm dünyada aynı lig günü) ──────────
  static String dayBucket(DateTime t) {
    final u = t.toUtc();
    return 'd:${u.year}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
  }

  static String weekBucket(DateTime t) {
    final u = t.toUtc();
    // ISO-8601 hafta numarası.
    final thursday = u.add(Duration(days: 4 - (u.weekday == 7 ? 7 : u.weekday)));
    final firstDay = DateTime.utc(thursday.year, 1, 1);
    final week = ((thursday.difference(firstDay).inDays) / 7).floor() + 1;
    return 'w:${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  static String monthBucket(DateTime t) {
    final u = t.toUtc();
    return 'm:${u.year}-${u.month.toString().padLeft(2, '0')}';
  }

  /// Periyot → güncel kova anahtarı (leaderboard sorgusu bunu kullanır).
  /// `now` verilmezse SUNUCU-düzeltmeli saat kullanılır — cihaz saati
  /// yanlış olsa bile kullanıcı doğru (aktif) kovaya bakar.
  static String bucketFor(LeaguePeriod period, [DateTime? now]) {
    final t = now ?? correctedNow();
    switch (period) {
      case LeaguePeriod.daily:
        return dayBucket(t);
      case LeaguePeriod.weekly:
        return weekBucket(t);
      case LeaguePeriod.monthly:
        return monthBucket(t);
      case LeaguePeriod.allTime:
        return 'all';
    }
  }

  /// Doc id'de kullanılamayan '/' karakterini değiştir.
  /// (Cloud Function tarafındaki `san()` ile birebir aynı olmalı.)
  static String _san(String s) => s.replaceAll('/', '⁄');

  /// Deterministik league_totals doküman id'si (uid_bucket_mode) —
  /// Cloud Function tarafındaki yazımla birebir. myCloudTotal ve
  /// LeagueLeaderboardService.fetchNeighbors aynı id'yi kullanır.
  static String totalsDocId({
    required String uid,
    required String modeKey,
    required LeaguePeriod period,
  }) =>
      _san('${uid}_${bucketFor(period)}_$modeKey');

  /// Kullanıcının KENDİ toplamını buluttan okur — "Senin Sıran" kartının
  /// liderlik tablosuyla aynı kaynağı göstermesi için. Doc id deterministik
  /// (uid_bucket_mode) olduğundan tek doküman okuması, sorgu yok.
  /// null → bulutta kayıt yok (offline veya bu kovada hiç oynamadı).
  static Future<({double score, int attempts, int durationSec})?>
      myCloudTotal({
    required String modeKey,
    required LeaguePeriod period,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return null;
      final id = totalsDocId(uid: uid, modeKey: modeKey, period: period);
      final doc = await FirebaseFirestore.instance
          .collection('league_totals')
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 8));
      final m = doc.data();
      if (m == null) return null;
      return (
        score: (m['score'] as num?)?.toDouble() ?? 0.0,
        attempts: (m['attempts'] as num?)?.toInt() ?? 0,
        durationSec: (m['durationSec'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('[LeagueScores] myCloudTotal fail: $e');
      return null;
    }
  }

  // ── Bilgi Ligi ekranı DIŞINDAN skor gönderimi (ör. Arena Sınav Modu) ──────
  /// Kayıtlı lig konumu + anonim-ad tercihi + görünen adı kendisi çözer ve
  /// add() ile aynı yoldan (yerel kayıt + cloud/outbox) gönderir. Prefs
  /// anahtarları bilgi_ligi_screen'dekilerle birebir aynıdır.
  static Future<void> submitQuizResult({
    required EduProfile profile,
    required String subjectKey,
    String? topic,
    required double score,
    required int durationSec,
  }) async {
    UserLocation? location;
    bool anonymous = false;
    String profileName = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      anonymous = prefs.getBool('bilgi_ligi_anonymous_mode') ?? false;
      profileName = (prefs.getString('profile_name') ?? '').trim();
      final raw = prefs.getString('world_ranking_location_v1');
      if (raw != null && raw.isNotEmpty) {
        location =
            UserLocation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[LeagueScores] submitQuizResult prefs fail: $e');
    }
    final user = FirebaseAuth.instance.currentUser;
    final displayName = anonymous
        ? (() {
            final u = user?.uid ?? '';
            return u.length >= 5
                ? '${'Öğrenci'.tr()} #${u.substring(0, 5)}'
                : 'Anonim'.tr();
          })()
        : (UserProfileService.instance.username.isNotEmpty
            ? UserProfileService.instance.username
            : (profileName.isNotEmpty ? profileName : user?.displayName));
    await add(
      LeagueAttempt(
        subjectKey: subjectKey,
        topic: topic,
        score: score,
        durationSec: durationSec,
        when: correctedNow(),
        countryCodeSnapshot: location?.countryCode,
        cityCodeSnapshot: location?.cityCode,
      ),
      profile: profile,
      location: location,
      displayName: displayName,
      avatar: '',
    );
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

  /// Periyot filtresi liderlik tablosuyla AYNI takvim kovasını kullanır
  /// (UTC gün / ISO hafta / takvim ayı). Eskiden "son 24 saat" gibi kayan
  /// pencereydi — "Senin Sıran" kartındaki puan tablodakinden farklı
  /// çıkabiliyordu.
  static List<LeagueAttempt> _filtered(
    List<LeagueAttempt> source, {
    String? subjectKey,
    String? topic,
    bool topicNullMeansAny = true,
    required LeaguePeriod period,
  }) {
    final bucket =
        period == LeaguePeriod.allTime ? null : bucketFor(period);
    return source.where((a) {
      if (subjectKey != null && a.subjectKey != subjectKey) return false;
      if (topic != null) {
        if (a.topic != topic) return false;
      } else if (!topicNullMeansAny) {
        if (a.topic != null && a.topic!.isNotEmpty) return false;
      }
      if (bucket != null && _bucketOf(period, a.when) != bucket) return false;
      return true;
    }).toList();
  }

  /// Bir attempt'in verilen periyot türündeki kova anahtarı.
  static String _bucketOf(LeaguePeriod period, DateTime when) {
    switch (period) {
      case LeaguePeriod.daily:
        return dayBucket(when);
      case LeaguePeriod.weekly:
        return weekBucket(when);
      case LeaguePeriod.monthly:
        return monthBucket(when);
      case LeaguePeriod.allTime:
        return 'all';
    }
  }

  /// Aktif kovada (bugün/bu hafta/bu ay) kaç deneme var?
  /// `subjectKey`/`topic` verilirse o derse/konuya daraltılır.
  /// Kullanım: günlük ücretsiz hak kontrolü + tekrar-çözme tespiti.
  static Future<int> attemptsInBucket({
    String? subjectKey,
    String? topic,
    required LeaguePeriod period,
  }) async {
    final list = await loadAll();
    return _filtered(
      list,
      subjectKey: subjectKey,
      topic: topic,
      period: period,
    ).length;
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
