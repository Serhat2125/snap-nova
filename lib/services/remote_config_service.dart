import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hafif uzaktan yapılandırma — Firebase Remote Config paketine ihtiyaç yok.
///
/// - Firestore'da `config/runtime` belgesinden key/value çeker.
/// - Offline çalışır: son başarılı yanıt cache'lenir.
/// - Default'lar kodda tanımlı; doküman yoksa / Firestore kapalıysa default'a düşer.
/// - **Feature flag**, A/B testi, kampanya bayrağı, deneme süresi,
///   model sıcaklığı gibi çalışma zamanı ayarları için tek kaynak.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const _tag = '🎛️ [RemoteConfig]';
  static const _prefCacheKey = 'remote_config_cache_v1';
  static const _prefTsKey = 'remote_config_ts_v1';
  static const _fetchTimeout = Duration(seconds: 6);
  static const _cacheTtl = Duration(hours: 6);

  /// Her sayfada erişilebilir default'lar. Buraya yeni bayrak eklemek
  /// **tek değişim noktası**.
  static const Map<String, Object> defaults = {
    // Genel
    'trial_entry_count': 10,
    'maintenance_mode': false,
    'min_supported_build': 1,
    // AI
    'gemini_primary_model': 'gemini-2.5-flash',
    'gemini_fallback_enabled': true,
    'openai_fallback_enabled': true,
    // Feature flags
    'feature_qualsar_mars_enabled': true,
    'feature_arena_enabled': true,
    'feature_ip_geolocation_enabled': true,
    'feature_ocr_mathpix_enabled': false, // ileride aktifleştirilecek
    // Ekonomi
    'daily_free_solve_limit': 5,
    'premium_intro_discount_pct': 50,
    // Quality of life
    'show_whatsnew_banner': false,
    'whatsnew_version': '',
    'whatsnew_title': '',
  };

  Map<String, dynamic> _values = Map.from(defaults);
  Completer<void>? _pending;

  /// Yüklenen güncel değer (default + uzaktan gelen override'lar).
  Map<String, dynamic> get values => Map.unmodifiable(_values);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _values = Map<String, dynamic>.from(defaults);
    // Cache varsa hemen uygula (hızlı açılış)
    final cached = prefs.getString(_prefCacheKey);
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          _values.addAll(map);
          if (kDebugMode) {
            debugPrint('$_tag cache uygulandı (${map.length} anahtar)');
          }
        }
      } catch (_) {}
    }
    // Arka planda tazele (başarısızsa umursama)
    unawaited(refresh());
  }

  /// Firestore'dan zorla yenile. Sonuç kullanıcı tarafından beklenmez.
  Future<void> refresh() async {
    if (_pending != null) return _pending!.future;
    final completer = Completer<void>();
    _pending = completer;
    try {
      if (Firebase.apps.isNotEmpty) {
        final firestore =
            FirebaseFirestore.instanceFor(app: Firebase.apps.first);
        final snap = await firestore
            .doc('config/runtime')
            .get()
            .timeout(_fetchTimeout);
        final data = snap.data();
        if (data != null) {
          _values = Map<String, dynamic>.from(defaults);
          _values.addAll(data);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefCacheKey, jsonEncode(data));
          await prefs.setInt(
              _prefTsKey, DateTime.now().millisecondsSinceEpoch);
          if (kDebugMode) {
            debugPrint('$_tag uzaktan ${data.length} anahtar çekildi');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('$_tag refresh başarısız: $e');
    } finally {
      if (!completer.isCompleted) completer.complete();
      _pending = null;
    }
  }

  // ── Tipli getter'lar ────────────────────────────────────────────────────
  bool getBool(String key) {
    final v = _values[key] ?? defaults[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return false;
  }

  int getInt(String key) {
    final v = _values[key] ?? defaults[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double getDouble(String key) {
    final v = _values[key] ?? defaults[key];
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  String getString(String key) {
    final v = _values[key] ?? defaults[key];
    return v?.toString() ?? '';
  }

  /// Cache hala taze mi?
  Future<bool> isCacheFresh() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_prefTsKey);
    if (ts == null) return false;
    final when = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.now().difference(when) < _cacheTtl;
  }
}
