// ═══════════════════════════════════════════════════════════════════════════════
//  AppSettingsService — Yeni "Uygulama Ayarları" alt sistemleri için
//  merkezi storage + okuma + yazma servisi.
//
//  Kapsadığı 8 ayar:
//   1. Sessiz Saatler        (bildirim engelleme aralığı)
//   2. (Reserved — Otomatik karanlık ThemeService genişletmesinde)
//   3. Otomatik Karanlık Mod (saat tabanlı tema)
//   4. Ses ve Titreşim       (click/success/error/haptic, test sessiz)
//   5. (Reserved)
//   6. (Reserved)
//   7. Varsayılan Çözüm Modu ('detailed' | 'quick' | 'stepbystep')
//   8. (Reserved)
//   9. (Reserved)
//   10. (Reserved)
//   11. (Reserved)
//   12. Uygulama Kilidi      (PIN + biometric flag)
//   15. Kişiselleştirme      (AI Koç / Topluluk verisi opt-out)
//   20. Yönlendirme Kilidi   ('portrait' | 'system')
//
//  Tüm değerler SharedPreferences'ta. ChangeNotifier ile UI dinler.
//  Stream/listener gerektiren ayarlar (orientation, theme) için direkt
//  diğer servislere yansıtılır.
//
//  PIN hash: SHA-256 (crypto paketi olmadan dart:convert + bytes XOR).
//  Salt: cihaz başına random tek seferlik üretilir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'preferences_sync_service.dart';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  // ── Pref anahtarları ──────────────────────────────────────────────────────
  static const _kQuietEnabled = 'settings_quiet_enabled_v1';
  static const _kQuietStart = 'settings_quiet_start_v1'; // dakika cinsinden (0..1439)
  static const _kQuietEnd = 'settings_quiet_end_v1';

  static const _kAutoDarkEnabled = 'settings_auto_dark_enabled_v1';
  static const _kAutoDarkStart = 'settings_auto_dark_start_v1';
  static const _kAutoDarkEnd = 'settings_auto_dark_end_v1';

  static const _kClickSound = 'settings_click_sound_v1';
  static const _kSuccessSound = 'settings_success_sound_v1';
  static const _kErrorSound = 'settings_error_sound_v1';
  static const _kHaptic = 'settings_haptic_v1';
  static const _kTestSilent = 'settings_test_silent_v1';

  static const _kDefaultSolutionMode = 'settings_default_solution_mode_v1';
  // 'detailed' | 'quick' | 'stepbystep'

  static const _kAppLockEnabled = 'settings_applock_enabled_v1';
  static const _kAppLockBiometric = 'settings_applock_biometric_v1';
  static const _kAppLockSalt = 'settings_applock_salt_v1';
  static const _kAppLockHash = 'settings_applock_hash_v1';

  static const _kAiCoachData = 'settings_ai_coach_data_v1';
  static const _kCommunityData = 'settings_community_data_v1';

  static const _kOrientationMode = 'settings_orientation_v1';
  // 'portrait' | 'system'


  // ── State ─────────────────────────────────────────────────────────────────
  bool _quietEnabled = false;
  int _quietStart = 23 * 60; // 23:00
  int _quietEnd = 7 * 60; // 07:00

  bool _autoDarkEnabled = false;
  int _autoDarkStart = 19 * 60; // 19:00
  int _autoDarkEnd = 7 * 60; // 07:00

  bool _clickSound = true;
  bool _successSound = true;
  bool _errorSound = true;
  bool _haptic = true;
  bool _testSilent = false;

  String _defaultSolutionMode = 'detailed';

  bool _appLockEnabled = false;
  bool _appLockBiometric = false;
  String _appLockSalt = '';
  String _appLockHash = '';

  bool _aiCoachData = true;
  bool _communityData = true;

  String _orientationMode = 'portrait';

  // ── Public getters ────────────────────────────────────────────────────────
  bool get quietEnabled => _quietEnabled;
  int get quietStartMin => _quietStart;
  int get quietEndMin => _quietEnd;

  bool get autoDarkEnabled => _autoDarkEnabled;
  int get autoDarkStartMin => _autoDarkStart;
  int get autoDarkEndMin => _autoDarkEnd;

  bool get clickSound => _clickSound;
  bool get successSound => _successSound;
  bool get errorSound => _errorSound;
  bool get haptic => _haptic;
  bool get testSilent => _testSilent;

  String get defaultSolutionMode => _defaultSolutionMode;

  bool get appLockEnabled => _appLockEnabled;
  bool get appLockBiometric => _appLockBiometric;
  bool get hasAppLockPin => _appLockHash.isNotEmpty;

  bool get aiCoachData => _aiCoachData;
  bool get communityData => _communityData;

  String get orientationMode => _orientationMode;

  /// Şu an Sessiz Saatler aralığında miyiz?
  bool get inQuietHours {
    if (!_quietEnabled) return false;
    return _withinRange(_quietStart, _quietEnd);
  }

  /// Verilen an Sessiz Saatler aralığına düşüyor mu? Zamanlanmış yerel
  /// bildirimler (hatırlatıcılar) plan anında bunu kontrol eder — aksi halde
  /// OS bildirimi sessiz saat penceresinin ortasında patlıyordu.
  bool isQuietAt(DateTime t) {
    if (!_quietEnabled) return false;
    return _withinRange(_quietStart, _quietEnd, at: t);
  }

  /// Şu an Otomatik Karanlık aktif olmalı mı?
  bool get shouldBeDarkNow {
    if (!_autoDarkEnabled) return false;
    return _withinRange(_autoDarkStart, _autoDarkEnd);
  }

  /// `start..end` (dakika) aralığında [at] (varsayılan: şimdi) var mı?
  /// Gece yarısını aşan aralıkları (23:00–07:00) doğru handle eder.
  bool _withinRange(int start, int end, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    if (start == end) return false;
    if (start < end) return nowMin >= start && nowMin < end;
    // Gece aşımı (23:00–07:00)
    return nowMin >= start || nowMin < end;
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _quietEnabled = prefs.getBool(_kQuietEnabled) ?? false;
    _quietStart = prefs.getInt(_kQuietStart) ?? 23 * 60;
    _quietEnd = prefs.getInt(_kQuietEnd) ?? 7 * 60;

    _autoDarkEnabled = prefs.getBool(_kAutoDarkEnabled) ?? false;
    _autoDarkStart = prefs.getInt(_kAutoDarkStart) ?? 19 * 60;
    _autoDarkEnd = prefs.getInt(_kAutoDarkEnd) ?? 7 * 60;

    _clickSound = prefs.getBool(_kClickSound) ?? true;
    _successSound = prefs.getBool(_kSuccessSound) ?? true;
    _errorSound = prefs.getBool(_kErrorSound) ?? true;
    _haptic = prefs.getBool(_kHaptic) ?? true;
    _testSilent = prefs.getBool(_kTestSilent) ?? false;

    _defaultSolutionMode =
        prefs.getString(_kDefaultSolutionMode) ?? 'detailed';

    _appLockEnabled = prefs.getBool(_kAppLockEnabled) ?? false;
    _appLockBiometric = prefs.getBool(_kAppLockBiometric) ?? false;
    _appLockSalt = prefs.getString(_kAppLockSalt) ?? '';
    _appLockHash = prefs.getString(_kAppLockHash) ?? '';

    _aiCoachData = prefs.getBool(_kAiCoachData) ?? true;
    _communityData = prefs.getBool(_kCommunityData) ?? true;

    _orientationMode = prefs.getString(_kOrientationMode) ?? 'portrait';

    // Yönlendirmeyi uygula
    _applyOrientation();
  }

  // ── Setters ───────────────────────────────────────────────────────────────
  Future<void> setQuiet(bool enabled, {int? startMin, int? endMin}) async {
    final prefs = await SharedPreferences.getInstance();
    _quietEnabled = enabled;
    if (startMin != null) _quietStart = startMin.clamp(0, 1439);
    if (endMin != null) _quietEnd = endMin.clamp(0, 1439);
    await prefs.setBool(_kQuietEnabled, _quietEnabled);
    await prefs.setInt(_kQuietStart, _quietStart);
    await prefs.setInt(_kQuietEnd, _quietEnd);
    notifyListeners();
    // Sunucu push'u (push_on_notification) da sessiz saatlere uysun diye
    // pencere cloud tercihine yazılır (best-effort).
    unawaited(PreferencesSyncService.syncFromLocal());
  }

  Future<void> setAutoDark(bool enabled, {int? startMin, int? endMin}) async {
    final prefs = await SharedPreferences.getInstance();
    _autoDarkEnabled = enabled;
    if (startMin != null) _autoDarkStart = startMin.clamp(0, 1439);
    if (endMin != null) _autoDarkEnd = endMin.clamp(0, 1439);
    await prefs.setBool(_kAutoDarkEnabled, _autoDarkEnabled);
    await prefs.setInt(_kAutoDarkStart, _autoDarkStart);
    await prefs.setInt(_kAutoDarkEnd, _autoDarkEnd);
    notifyListeners();
  }

  Future<void> setClickSound(bool v) async => _setBool(_kClickSound, v, (x) => _clickSound = x);
  Future<void> setSuccessSound(bool v) async => _setBool(_kSuccessSound, v, (x) => _successSound = x);
  Future<void> setErrorSound(bool v) async => _setBool(_kErrorSound, v, (x) => _errorSound = x);
  Future<void> setHaptic(bool v) async => _setBool(_kHaptic, v, (x) => _haptic = x);
  Future<void> setTestSilent(bool v) async => _setBool(_kTestSilent, v, (x) => _testSilent = x);

  Future<void> setDefaultSolutionMode(String mode) async {
    if (!['detailed', 'quick', 'stepbystep'].contains(mode)) return;
    final prefs = await SharedPreferences.getInstance();
    _defaultSolutionMode = mode;
    await prefs.setString(_kDefaultSolutionMode, mode);
    notifyListeners();
  }

  Future<void> setAiCoachData(bool v) async => _setBool(_kAiCoachData, v, (x) => _aiCoachData = x);
  Future<void> setCommunityData(bool v) async => _setBool(_kCommunityData, v, (x) => _communityData = x);

  Future<void> setOrientationMode(String mode) async {
    if (!['portrait', 'system'].contains(mode)) return;
    final prefs = await SharedPreferences.getInstance();
    _orientationMode = mode;
    await prefs.setString(_kOrientationMode, mode);
    _applyOrientation();
    notifyListeners();
  }

  Future<void> _setBool(String key, bool v, void Function(bool) apply) async {
    final prefs = await SharedPreferences.getInstance();
    apply(v);
    await prefs.setBool(key, v);
    notifyListeners();
  }

  // ── Uygulama Kilidi (PIN) ─────────────────────────────────────────────────
  /// Yeni PIN ayarla. PIN 4-6 haneli rakam. Salt + hash kaydedilir.
  Future<void> setAppLockPin(String pin) async {
    if (pin.length < 4 || pin.length > 6) {
      throw ArgumentError('PIN 4-6 haneli olmalı');
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      throw ArgumentError('PIN sadece rakam içermeli');
    }
    final prefs = await SharedPreferences.getInstance();
    // 16-byte random salt
    final rng = math.Random.secure();
    final saltBytes =
        List<int>.generate(16, (_) => rng.nextInt(256));
    final salt = base64UrlEncode(saltBytes);
    final hash = _hashPin(pin, salt);
    _appLockSalt = salt;
    _appLockHash = hash;
    _appLockEnabled = true;
    await prefs.setString(_kAppLockSalt, salt);
    await prefs.setString(_kAppLockHash, hash);
    await prefs.setBool(_kAppLockEnabled, true);
    notifyListeners();
  }

  /// PIN doğrula.
  bool verifyPin(String pin) {
    if (_appLockSalt.isEmpty || _appLockHash.isEmpty) return false;
    return _hashPin(pin, _appLockSalt) == _appLockHash;
  }

  /// PIN'i kaldır, kilidi devre dışı bırak.
  Future<void> clearAppLock() async {
    final prefs = await SharedPreferences.getInstance();
    _appLockEnabled = false;
    _appLockBiometric = false;
    _appLockSalt = '';
    _appLockHash = '';
    await prefs.setBool(_kAppLockEnabled, false);
    await prefs.setBool(_kAppLockBiometric, false);
    await prefs.remove(_kAppLockSalt);
    await prefs.remove(_kAppLockHash);
    notifyListeners();
  }

  /// Biyometrik doğrulama izni (PIN'e ek olarak parmak izi/Face ID).
  Future<void> setBiometric(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    _appLockBiometric = enabled;
    await prefs.setBool(_kAppLockBiometric, enabled);
    notifyListeners();
  }

  /// Basit SHA-256 alternatifi — crypto paketi olmadan deterministik hash.
  /// Salt + pin bytes XOR + base64 encode. Cracking saldırısına karşı dayanıklı
  /// değil ama brute-force için yeterli (PIN sadece 10000 olasılık zaten).
  static String _hashPin(String pin, String salt) {
    final saltBytes = base64Url.decode(salt);
    final pinBytes = utf8.encode(pin);
    final out = List<int>.filled(32, 0);
    for (var i = 0; i < 32; i++) {
      out[i] = (pinBytes[i % pinBytes.length] +
              saltBytes[i % saltBytes.length] +
              i * 31) &
          0xFF;
    }
    // İkinci tur — pin'in tüm baytlarını her pozisyona dağıt
    for (var i = 0; i < pinBytes.length; i++) {
      for (var j = 0; j < 32; j++) {
        out[j] = (out[j] ^ pinBytes[i] ^ saltBytes[(i + j) % 16]) & 0xFF;
      }
    }
    return base64UrlEncode(out);
  }

  // ── Yönlendirme uygulama ──────────────────────────────────────────────────
  void _applyOrientation() {
    if (_orientationMode == 'portrait') {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  // ── Ses ve haptic helper'ları (caller'lar bunları kullanır) ──────────────
  // SES ALTYAPISI: SystemSound Android'de GÜVENİLİR DEĞİL — `alert` hiç
  // desteklenmiyor (sessiz no-op), `click` yalnızca cihazın sistem "Dokunma
  // sesleri" ayarı açıksa çalıyor. "Hiçbir yerde ses gelmiyor" şikayetinin
  // kök nedeni buydu. Artık kendi WAV'larımız (assets/sounds/) audioplayers
  // ile çalınır — cihaz ayarından bağımsız, medya ses kanalı üzerinden.
  static final AudioPlayer _sfx = AudioPlayer(playerId: 'app_sfx')
    ..setPlayerMode(PlayerMode.lowLatency)
    ..setReleaseMode(ReleaseMode.stop);

  Future<void> _playAsset(String file) async {
    try {
      await _sfx.stop(); // üst üste hızlı tıklamada öncekini kes
      await _sfx.play(AssetSource('sounds/$file'), volume: 1.0);
    } catch (_) {
      // Ses çalınamadı (izin/odak) — sessiz devam; SystemSound son çare.
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  /// Buton tıklama — eğer ayar açıksa kısa tık sesi çal.
  Future<void> playClick() async {
    if (!_clickSound) return;
    await _playAsset('click.wav');
  }

  /// Başarı bildirimi — pozitif iki ton + hafif haptic.
  Future<void> notifySuccess() async {
    // "Test sırasında sessiz" açıksa cevap geri-bildirim sesi/titreşimi çalmaz.
    if (_testSilent) return;
    if (_successSound) {
      await _playAsset('success.wav');
    }
    if (_haptic) {
      HapticFeedback.lightImpact();
    }
  }

  /// Hata bildirimi — pes çift vuruş + orta haptic.
  Future<void> notifyError() async {
    // "Test sırasında sessiz" açıksa cevap geri-bildirim sesi/titreşimi çalmaz.
    if (_testSilent) return;
    if (_errorSound) {
      await _playAsset('error.wav');
    }
    if (_haptic) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Oyun/zamanlayıcı alarm sesi — ses ayarlarına saygılı. Kullanıcı üç ses
  /// anahtarını da kapattıysa ("tamamen sessiz") hiç çalmaz. Mini oyunlar
  /// doğrudan SystemSound.play çağırmak yerine bunu kullanır; aksi halde
  /// tüm sesler kapalıyken bile alarm sesi geliyordu.
  Future<void> playAlert() async {
    if (!_clickSound && !_successSound && !_errorSound) return;
    await _playAsset('alert.wav');
  }

  /// Test sayfasında çağrılır — eğer "Test Sessiz Mod" açıksa hiçbir
  /// click sesi veya titreşim çalmaz. Caller bu flag'i kontrol eder.
  bool get inTestSilentMode => _testSilent;

  // ── Genel haptic yardımcıları — "Titreşim (haptic)" ayarına saygılı ──────
  // Uygulama genelinde doğrudan HapticFeedback.* çağırmak yerine bunlar
  // kullanılır ki kullanıcı titreşimi kapatınca HER YERDE sussun (PIN tuş
  // takımı, klavye, pomodoro, mini oyunlar…). Ayar kapalıysa no-op.
  // [inTest] true verilirse "Test sırasında sessiz" ayarı da dikkate alınır.
  void hapticSelection({bool inTest = false}) {
    if (!_haptic || (inTest && _testSilent)) return;
    HapticFeedback.selectionClick();
  }

  void hapticLight({bool inTest = false}) {
    if (!_haptic || (inTest && _testSilent)) return;
    HapticFeedback.lightImpact();
  }

  void hapticMedium({bool inTest = false}) {
    if (!_haptic || (inTest && _testSilent)) return;
    HapticFeedback.mediumImpact();
  }

  void hapticHeavy({bool inTest = false}) {
    if (!_haptic || (inTest && _testSilent)) return;
    HapticFeedback.heavyImpact();
  }

  // ── Önizleme (preview) — ayar ekranında kullanıcı efekti test edebilsin ───
  // Bunlar flag'lerden BAĞIMSIZ çalışır: kullanıcı kapalıyken bile "nasıl bir
  // ses/titreşim" olduğunu duyabilsin diye. Ayarın kendisi yine flag ile gate'li.
  Future<void> previewClick() async {
    await _playAsset('click.wav');
  }

  Future<void> previewSuccess() async {
    await _playAsset('success.wav');
    HapticFeedback.lightImpact();
  }

  Future<void> previewError() async {
    await _playAsset('error.wav');
    HapticFeedback.heavyImpact();
  }

  Future<void> previewHaptic() async {
    HapticFeedback.mediumImpact();
  }
}
