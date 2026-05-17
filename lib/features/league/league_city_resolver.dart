// ═══════════════════════════════════════════════════════════════════════════════
//  LeagueCityResolver — Bilgi Ligi konum hiyerarşisi.
//
//  Ülke → (federasyon ise) Eyalet → Şehir
//
//  3 ayrı resolver:
//    • subdivisions(country)         → eyalet listesi (boş ise üniter ülke)
//    • citiesForState(country,state) → eyaletin şehirleri
//    • citiesForCountry(country)     → eyalet kademesiz, ülke geneli şehirler
//      (federasyon olmayan ülkeler için)
//
//  Hepsi cache'li (bellek + SharedPreferences).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import '../../services/error_logger.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/gemini_service.dart';
import '../leaderboard/data/location_catalog.dart';

/// Eyalet / federal birim kaydı (UI için).
class SubdivisionEntry {
  final String code;
  final String name;
  const SubdivisionEntry({required this.code, required this.name});
}

class LeagueCityResolver {
  /// Son city resolver hatası — UI bunu okuyup snackbar/toast gösterebilir.
  /// Başarılı çağrı sonrası boşaltılır.
  static String lastError = '';

  static const _prefixCities = 'league_cities_cache::';
  static const _prefixSubs = 'league_subs_cache::';
  static const _prefixStateCities = 'league_state_cities::';

  // Bellek cache
  static final Map<String, List<CityEntry>> _memCities = {};
  static final Map<String, List<SubdivisionEntry>> _memSubs = {};
  static final Map<String, List<CityEntry>> _memStateCities = {};

  // ── Subdivisions (eyalet listesi) ──────────────────────────────────────────
  /// Ülkenin eyaletleri. Üniter ülke için boş liste döner.
  /// Cache hit varsa anında, yoksa Gemini'ye gidip cache'ler.
  static Future<List<SubdivisionEntry>> resolveSubdivisions({
    required String countryCode,
    required String countryName,
    bool forceRefresh = false,
  }) async {
    final cc = countryCode.toUpperCase();
    if (!forceRefresh) {
      final mem = _memSubs[cc];
      if (mem != null) return mem;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefixSubs$cc');
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List;
          final subs = list
              .whereType<Map>()
              .map((m) => SubdivisionEntry(
                    code: (m['code'] ?? '').toString(),
                    name: (m['name'] ?? '').toString(),
                  ))
              .where((s) => s.code.isNotEmpty && s.name.isNotEmpty)
              .toList();
          _memSubs[cc] = subs;
          return subs;
        } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'league_city_resolver'); }
      }
    }

    try {
      final fetched = await GeminiService.fetchCountrySubdivisions(
        countryName: countryName,
        countryCode: cc,
      );
      final subs = fetched
          .map((m) => SubdivisionEntry(code: m['code']!, name: m['name']!))
          .toList();
      _memSubs[cc] = subs;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefixSubs$cc',
        jsonEncode(subs.map((s) => {'code': s.code, 'name': s.name}).toList()),
      );
      lastError = '';
      return subs;
    } catch (e) {
      // Kullanıcı UI'da bunu açıkça görebilmeli — `lastError` field okunur.
      debugPrint('[LeagueCityResolver] subdivisions fail ($cc): $e');
      lastError = 'Eyalet/il listesi şu an alınamadı. İnternet bağlantını kontrol et.';
      _memSubs[cc] = const [];
      return const [];
    }
  }

  // ── Eyaletin şehirleri ─────────────────────────────────────────────────────
  static Future<List<CityEntry>> resolveCitiesForState({
    required String countryCode,
    required String countryName,
    required String stateCode,
    required String stateName,
    bool forceRefresh = false,
  }) async {
    final key = '${countryCode.toUpperCase()}|${stateCode.toLowerCase()}';
    if (!forceRefresh) {
      final mem = _memStateCities[key];
      if (mem != null) return mem;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefixStateCities$key');
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List;
          final cities = list
              .whereType<Map>()
              .map((m) => CityEntry(
                    code: (m['code'] ?? '').toString(),
                    name: (m['name'] ?? '').toString(),
                  ))
              .where((c) => c.code.isNotEmpty && c.name.isNotEmpty)
              .toList();
          _memStateCities[key] = cities;
          return cities;
        } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'league_city_resolver'); }
      }
    }

    try {
      final fetched = await GeminiService.fetchStateCities(
        countryName: countryName,
        stateName: stateName,
      );
      final cities = fetched
          .map((m) => CityEntry(code: m['code']!, name: m['name']!))
          .toList();
      _memStateCities[key] = cities;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefixStateCities$key',
        jsonEncode(
            cities.map((c) => {'code': c.code, 'name': c.name}).toList()),
      );
      return cities;
    } catch (_) {
      return const [];
    }
  }

  // ── Üniter ülke için şehir listesi (eyalet kademesi yok) ───────────────────
  /// Federasyon değilse (Türkiye, Fransa, Japonya...) doğrudan ülke bazlı şehir.
  /// 1) Statik LocationCatalog (Türkiye 81 il vb.) ≥30 ise onu kullan.
  /// 2) Aksi halde Gemini ile çek + cache'le.
  static Future<List<CityEntry>> resolveCountryCities({
    required String countryCode,
    required String countryName,
    bool forceRefresh = false,
  }) async {
    final cc = countryCode.toUpperCase();
    if (!forceRefresh) {
      final mem = _memCities[cc];
      if (mem != null && mem.isNotEmpty) return mem;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefixCities$cc');
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List;
          final cities = list
              .whereType<Map>()
              .map((m) => CityEntry(
                    code: (m['code'] ?? '').toString(),
                    name: (m['name'] ?? '').toString(),
                  ))
              .where((c) => c.code.isNotEmpty && c.name.isNotEmpty)
              .toList();
          if (cities.isNotEmpty) {
            _memCities[cc] = cities;
            return cities;
          }
        } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'league_city_resolver'); }
      }
    }

    final staticList = LocationCatalog.findByCode(cc)?.cities ?? const [];
    if (!forceRefresh && staticList.length >= 30) {
      _memCities[cc] = staticList;
      return staticList;
    }

    try {
      final fetched = await GeminiService.fetchCountryCities(
        countryName: countryName,
        countryCode: cc,
      );
      final cities = fetched
          .map((m) => CityEntry(code: m['code']!, name: m['name']!))
          .toList();
      final result = cities.length >= staticList.length ? cities : staticList;
      if (result.isNotEmpty) {
        _memCities[cc] = result;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          '$_prefixCities$cc',
          jsonEncode(
              result.map((c) => {'code': c.code, 'name': c.name}).toList()),
        );
      }
      return result;
    } catch (_) {
      if (staticList.isNotEmpty) _memCities[cc] = staticList;
      return staticList;
    }
  }
}
