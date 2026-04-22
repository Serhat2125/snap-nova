import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'geolocation_service.dart';
import 'locale_service.dart';

/// **Tek kaynak doğruluk** — "Bu kullanıcı hangi ülkede?"
///
/// Öncelik sırası:
///   1. `mini_test_country` — kullanıcının EducationSetup'ta seçtiği ülke.
///   2. `ip_geo_country_v1` — IP geolocation sonucu (GeolocationService).
///   3. `detected_country_v1` — cihaz locale segmenti (LocaleService).
///   4. `null` — hiçbir sinyal yok; UI default'a (TR) düşer.
///
/// Bu katman sayesinde UI kodu her yerde aynı fonksiyonu çağırır, sinyal
/// çatışmaları tek noktada çözülür.
class CountryResolver {
  CountryResolver._();
  static final CountryResolver instance = CountryResolver._();

  static const _tag = '🎯 [CountryResolver]';
  String? _cached;

  /// Mevcut en iyi tahminimiz. Senkron, hızlı — cache'den okur.
  String? get current => _cached;

  /// Tüm sinyalleri merge eder. `init()` uygulama açılışında bir kez
  /// çağrılır, değişiklikler için `refresh()` kullanılır.
  Future<String?> init({LocaleService? locale}) async {
    await _compute(locale: locale);
    return _cached;
  }

  /// IP geolocation'ı tetikler (ilk çalıştırmada) ve sonra tekrar merge eder.
  /// Kullanıcı ağ değişikliğinden sonra veya manuel refresh'te çağırabilir.
  Future<String?> refresh({
    LocaleService? locale,
    bool forceIpRefresh = false,
  }) async {
    // IP tarafı cache'li; sadece ilk çağrıda veya zorlamada ağa gider.
    await GeolocationService.resolve(forceRefresh: forceIpRefresh);
    await _compute(locale: locale);
    return _cached;
  }

  Future<void> _compute({LocaleService? locale}) async {
    final prefs = await SharedPreferences.getInstance();
    // 1) Manuel seçim
    final manual = prefs.getString('mini_test_country');
    if (manual != null && manual.isNotEmpty) {
      _cached = manual;
      _log('kullanıcı seçimi → $manual');
      return;
    }
    // 2) IP geolocation
    final ip = prefs.getString('ip_geo_country_v1');
    if (ip != null && ip.isNotEmpty) {
      _cached = ip;
      _log('IP geo → $ip');
      return;
    }
    // 3) Cihaz locale
    final deviceCountry =
        locale?.detectedCountry ?? prefs.getString('detected_country_v1');
    if (deviceCountry != null && deviceCountry.isNotEmpty) {
      _cached = deviceCountry;
      _log('cihaz locale → $deviceCountry');
      return;
    }
    // 4) Hiçbir sinyal yok
    _cached = null;
    _log('ülke belirsiz — null');
  }

  static void _log(String msg) {
    if (kDebugMode) debugPrint('$_tag $msg');
  }
}
