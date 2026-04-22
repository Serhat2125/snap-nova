import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcının bulunduğu ülkeyi **IP** üzerinden tespit eder.
///
/// - İlk çağrıda ücretsiz `ipapi.co/json/` uç noktasına gider; bu başarısız
///   olursa `geojs.io` yedeğine düşer. Hiçbir API anahtarı gerekmez.
/// - Sonuç 24 saat boyunca `SharedPreferences` içinde cachelenir.
/// - Çağrı **hiçbir zaman** UI'ı bloke etmez (timeout 4 sn, tek seferlik).
///
/// Döndürülen ülke kodu ISO 3166-1 alpha-2 (küçük harf: `tr`, `us`, `de`…).
class GeolocationService {
  static const _tag = '🌐 [GeolocationService]';
  static const _prefCountryKey = 'ip_geo_country_v1';
  static const _prefTimestampKey = 'ip_geo_ts_v1';
  static const _prefExtraKey = 'ip_geo_extra_v1';
  static const _cacheTtl = Duration(hours: 24);
  static const _httpTimeout = Duration(seconds: 4);

  /// Cache + uzaktan çözümleme. Önce cache'e bakar; süresi dolmuşsa
  /// arka planda tazeler ama cache varsa hemen döner.
  static Future<GeoInfo?> resolve({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = _readCache(prefs);
      if (cached != null && !cached.isExpired) {
        return cached;
      }
    }

    final fresh = await _fetchFromNetwork();
    if (fresh != null) {
      await _writeCache(prefs, fresh);
      return fresh;
    }

    // Ağ başarısız — eski cache'i döndür (stale-while-offline)
    return _readCache(prefs);
  }

  static GeoInfo? _readCache(SharedPreferences prefs) {
    final country = prefs.getString(_prefCountryKey);
    final ts = prefs.getInt(_prefTimestampKey);
    if (country == null || ts == null) return null;
    final ts2 = DateTime.fromMillisecondsSinceEpoch(ts);
    final extraRaw = prefs.getString(_prefExtraKey);
    Map<String, dynamic>? extra;
    if (extraRaw != null) {
      try {
        extra = jsonDecode(extraRaw) as Map<String, dynamic>;
      } catch (_) {}
    }
    return GeoInfo(
      country: country,
      timestamp: ts2,
      extra: extra ?? const {},
    );
  }

  static Future<void> _writeCache(
    SharedPreferences prefs,
    GeoInfo info,
  ) async {
    await prefs.setString(_prefCountryKey, info.country);
    await prefs.setInt(
      _prefTimestampKey,
      info.timestamp.millisecondsSinceEpoch,
    );
    await prefs.setString(_prefExtraKey, jsonEncode(info.extra));
  }

  /// Uzaktan çözümleme. Sırayla her endpoint'i dener.
  static Future<GeoInfo?> _fetchFromNetwork() async {
    for (final resolver in _resolvers) {
      try {
        final result = await resolver().timeout(_httpTimeout);
        if (result != null && result.country.isNotEmpty) {
          _log('Ülke tespit edildi → ${result.country} '
              '(${result.extra['source']})');
          return result;
        }
      } catch (e) {
        _log('Endpoint başarısız: $e');
      }
    }
    _log('Hiçbir endpoint yanıt vermedi.');
    return null;
  }

  static final List<Future<GeoInfo?> Function()> _resolvers = [
    _fetchIpapi,
    _fetchGeojs,
    _fetchIpwho,
  ];

  // ── ipapi.co/json/ ─────────────────────────────────────────────────────────
  static Future<GeoInfo?> _fetchIpapi() async {
    final resp = await http.get(Uri.parse('https://ipapi.co/json/'));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['country_code'] as String?)?.toLowerCase();
    if (code == null || code.isEmpty) return null;
    return GeoInfo(
      country: code,
      timestamp: DateTime.now(),
      extra: {
        'source': 'ipapi',
        'ip': j['ip'],
        'city': j['city'],
        'region': j['region'],
        'timezone': j['timezone'],
        'currency': j['currency'],
        'languages': j['languages'],
      },
    );
  }

  // ── get.geojs.io — yedek ─────────────────────────────────────────────────
  static Future<GeoInfo?> _fetchGeojs() async {
    final resp =
        await http.get(Uri.parse('https://get.geojs.io/v1/ip/country.json'));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = (j['country'] as String?)?.toLowerCase();
    if (code == null || code.isEmpty) return null;
    return GeoInfo(
      country: code,
      timestamp: DateTime.now(),
      extra: {'source': 'geojs', 'ip': j['ip']},
    );
  }

  // ── ipwho.is — ikinci yedek ──────────────────────────────────────────────
  static Future<GeoInfo?> _fetchIpwho() async {
    final resp = await http.get(Uri.parse('https://ipwho.is/?fields=country_code,ip,city,region,timezone'));
    if (resp.statusCode != 200) return null;
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    if (j['success'] == false) return null;
    final code = (j['country_code'] as String?)?.toLowerCase();
    if (code == null || code.isEmpty) return null;
    return GeoInfo(
      country: code,
      timestamp: DateTime.now(),
      extra: {
        'source': 'ipwho',
        'ip': j['ip'],
        'city': j['city'],
        'region': j['region'],
        'timezone': j['timezone'],
      },
    );
  }

  static void _log(String msg) {
    if (kDebugMode) debugPrint('$_tag $msg');
  }
}

class GeoInfo {
  final String country; // ISO 3166 alpha-2, küçük harf
  final DateTime timestamp;
  final Map<String, dynamic> extra;

  const GeoInfo({
    required this.country,
    required this.timestamp,
    this.extra = const {},
  });

  bool get isExpired =>
      DateTime.now().difference(timestamp) >
      GeolocationService._cacheTtl;
}
