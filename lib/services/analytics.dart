// Analytics / Crashlytics ince sarmalayıcı.
// Firebase paketleri yoksa ya da init başarısızsa sessizce no-op çalışır;
// app asla bu yüzden crash etmemeli.
//
// Kullanım:
//   await Analytics.init();
//   Analytics.logEvent('test_completed', params: {'subject': 'math', 'score': 4});
//   Analytics.recordError(error, stack, fatal: false);
//
// pubspec.yaml:
//   firebase_analytics: ^11.3.0
//   firebase_crashlytics: ^4.1.0
//
// Çağrı sırasında firebase_core init'i tamamlanmış olmalı (main.dart'ta yapıldı).

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class Analytics {
  static FirebaseAnalytics? _analytics;
  static FirebaseCrashlytics? _crashlytics;
  static bool _initialized = false;

  /// main.dart'ta `Firebase.initializeApp` BAŞARILI OLDUKTAN SONRA çağır.
  /// Hata atmaz; init başarısızsa tüm metodlar no-op'a düşer.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      _analytics = FirebaseAnalytics.instance;
      _crashlytics = FirebaseCrashlytics.instance;
      // Debug build'lerde Crashlytics raporlarını kapat (gürültüyü önler).
      await _crashlytics!.setCrashlyticsCollectionEnabled(!kDebugMode);
      _initialized = true;
    } catch (e) {
      debugPrint('[Analytics] init failed: $e — devre dışı');
      _analytics = null;
      _crashlytics = null;
    }
  }

  /// Olay logla (event tracking). Failures sessizdir.
  static Future<void> logEvent(
    String name, {
    Map<String, Object>? params,
  }) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('[Analytics] logEvent($name) failed: $e');
    }
  }

  /// Kullanıcı ID'si ata (giriş sonrası).
  static Future<void> setUserId(String? id) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.setUserId(id: id);
      _crashlytics?.setUserIdentifier(id ?? 'anonymous');
    } catch (_) {}
  }

  /// Profil özelliği ata (örn. country, level).
  static Future<void> setUserProperty(String name, String? value) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.setUserProperty(name: name, value: value);
    } catch (_) {}
  }

  /// Ekran görüntüleme.
  static Future<void> logScreenView(String screenName) async {
    await logEvent('screen_view', params: {'screen_name': screenName});
  }

  /// Hata kaydet — non-fatal default. `fatal=true` Crashlytics'te crash olarak görünür.
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) async {
    final c = _crashlytics;
    if (c == null) {
      debugPrint('[Analytics] recordError (no-op): $error');
      return;
    }
    try {
      await c.recordError(error, stack, fatal: fatal, reason: reason);
    } catch (e) {
      debugPrint('[Analytics] recordError failed: $e');
    }
  }

  /// Flutter framework hatalarını yakala (FlutterError.onError'a bağlanır).
  static void registerFlutterErrorHandler() {
    final c = _crashlytics;
    if (c == null) return;
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      c.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      c.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Quota dolduğunda — strategic event.
  static void logQuotaExhausted(String quotaKind) =>
      logEvent('quota_exhausted', params: {'kind': quotaKind});

  /// Premium funnel olayları.
  static void logPaywallShown(String trigger) =>
      logEvent('paywall_shown', params: {'trigger': trigger});
  static void logPurchaseCompleted(String tier) =>
      logEvent('purchase_completed', params: {'tier': tier});
}
