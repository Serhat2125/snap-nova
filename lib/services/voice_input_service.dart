// VoiceInputService — speech_to_text sarmalayıcısı.
// Native iOS/Android konuşma tanımayı kullanır (internet gerektirmez).
// LocaleService'in aktif diline göre konuşma tanıma yapılır (55+ dil).
//
// Kullanım:
//   await VoiceInputService.init();           // bir kez (main.dart başlangıcı)
//   if (await VoiceInputService.requestMic()) {
//     await VoiceInputService.start(
//       onResult: (text, finalResult) { ... },
//       onLevel: (level) { ... },             // amplitude 0-1 (waveform için)
//     );
//   }
//   await VoiceInputService.stop();

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputService {
  static final stt.SpeechToText _stt = stt.SpeechToText();
  static bool _initialized = false;
  static bool _available = false;

  static bool get isAvailable => _available;
  static bool get isListening => _stt.isListening;

  /// Bir kez çağrılır (main.dart). Cihaz speech engine var mı kontrol eder.
  /// Hata atmaz; başarısızsa `isAvailable` false kalır.
  static Future<bool> init() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _stt.initialize(
        onError: (e) => debugPrint('[VoiceInput] error: $e'),
        onStatus: (s) => debugPrint('[VoiceInput] status: $s'),
        debugLogging: kDebugMode,
      );
    } catch (e) {
      debugPrint('[VoiceInput] init failed: $e');
      _available = false;
    }
    return _available;
  }

  /// Mikrofon iznini ister (gerekirse). Reddedilirse false.
  static Future<bool> requestMic() async {
    if (!_initialized) await init();
    if (!_available) return false;
    return _stt.hasPermission;
  }

  /// Cihazın desteklediği locale'leri listele.
  /// Locale id örnekleri: "en_US", "tr_TR", "ja_JP".
  static Future<List<stt.LocaleName>> locales() async {
    if (!_initialized) await init();
    if (!_available) return [];
    try {
      return await _stt.locales();
    } catch (_) {
      return [];
    }
  }

  /// LocaleService kodunu (`tr`, `en`, `de`...) speech_to_text locale_id'sine
  /// (`tr_TR`, `en_US`, `de_DE`) çevir. Cihazda eşleşen locale yoksa default.
  static Future<String?> resolveLocaleId(String langCode) async {
    final list = await locales();
    if (list.isEmpty) return null;
    final lc = langCode.toLowerCase();
    // 1) Tam eşleşme: "tr_TR", "en_US"
    for (final l in list) {
      if (l.localeId.toLowerCase().startsWith('${lc}_')) return l.localeId;
    }
    // 2) Sadece dil eşleşmesi
    for (final l in list) {
      if (l.localeId.toLowerCase().startsWith(lc)) return l.localeId;
    }
    return null;
  }

  /// Dinlemeyi başlat. `onResult(text, isFinal)` her transkript güncelimde,
  /// `onLevel(0-1)` ses seviyesi (waveform animation için).
  /// `localeId` null ise cihaz default'u kullanır.
  static Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    void Function(double level)? onLevel,
    String? localeId,
    Duration listenFor = const Duration(seconds: 60),
    Duration pauseFor = const Duration(seconds: 4),
  }) async {
    if (!_initialized) await init();
    if (!_available) return false;
    try {
      await _stt.listen(
        onResult: (r) => onResult(r.recognizedWords, r.finalResult),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          onDevice: false, // online tanıma daha doğru — internet varsa
        ),
        localeId: localeId,
        listenFor: listenFor,
        pauseFor: pauseFor,
        onSoundLevelChange: onLevel == null
            ? null
            : (lvl) {
                // dB değeri (~ -2 to 10) → 0-1'e normalize
                final n = ((lvl + 2) / 12).clamp(0.0, 1.0);
                onLevel(n);
              },
      );
      return true;
    } catch (e) {
      debugPrint('[VoiceInput] start failed: $e');
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {}
  }
}
