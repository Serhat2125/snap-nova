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
import 'error_logger.dart';

class VoiceInputService {
  static final stt.SpeechToText _stt = stt.SpeechToText();
  static bool _initialized = false;
  static bool _available = false;

  /// STT durum bilgisi — son hata veya status mesajı (debug için).
  /// "Konuşma algılanmadı" hatasında sebebi anlamak için kullanıcıya gösterilebilir.
  ///
  /// 30Hz callback'lerden gelen güncellemelerin son user-facing hatayı
  /// silmemesi için lastError SADECE "permanent" hata kodları tutar
  /// (no_match, network, etc.). Geçici/bilgi mesajları lastStatus'a gider.
  static String lastStatus = 'init bekleniyor';
  static String lastError = '';

  /// Permanent error kodları — kullanıcıya gösterilmeye değer.
  static const _permanentErrors = {
    'error_no_match',
    'error_speech_timeout',
    'error_network',
    'error_network_timeout',
    'error_audio',
    'error_server',
    'error_busy',
    'error_insufficient_permissions',
    'error_too_many_requests',
  };

  static bool get isAvailable => _available;
  static bool get isListening => _stt.isListening;

  /// Bir kez çağrılır (main.dart). Cihaz speech engine var mı kontrol eder.
  /// Hata atmaz; başarısızsa `isAvailable` false kalır.
  ///
  /// NOT: audio_session ile manuel session config kaldırıldı — speech_to_text
  /// paketi kendi iç AVAudioSession yönetimini yapıyor, override etmek bazı
  /// cihazlarda "konuşma algılanamadı" hatasına sebep oluyordu.
  static Future<bool> init() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _stt.initialize(
        onError: (e) {
          // Sadece permanent error kodlarını lastError'a yaz; transient
          // callback'ler son user-facing hatayı silmesin.
          final code = e.errorMsg;
          if (_permanentErrors.contains(code) || e.permanent) {
            lastError = code;
          }
          debugPrint('[VoiceInput] error: $e');
        },
        onStatus: (s) {
          lastStatus = s;
          debugPrint('[VoiceInput] status: $s');
        },
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
  /// (`tr_TR`, `en_US`, `de_DE`) çevir. Cihazda eşleşen locale yoksa
  /// fallback chain: en_US → en_* → systemLocale → ilk locale.
  /// Bu sayede sesli komut hiçbir cihazda "locale not found" ile boş kalmaz.
  static Future<String?> resolveLocaleId(String langCode) async {
    final list = await locales();
    if (list.isEmpty) return null;
    final lc = langCode.toLowerCase();
    // 1) Tam eşleşme: "tr_TR", "en_US"
    for (final l in list) {
      if (l.localeId.toLowerCase().startsWith('${lc}_')) return l.localeId;
    }
    // 2) Sadece dil eşleşmesi (örn. "tr" → "tr-tr")
    for (final l in list) {
      if (l.localeId.toLowerCase().startsWith(lc)) return l.localeId;
    }
    // 3) Cihaz sistem locale'i (speech_to_text varsa döner)
    try {
      final sys = await _stt.systemLocale();
      if (sys != null && sys.localeId.isNotEmpty) return sys.localeId;
    } catch (_) {/* yok say */}
    // 4) en_US fallback
    for (final l in list) {
      if (l.localeId.toLowerCase().startsWith('en_us') ||
          l.localeId.toLowerCase().startsWith('en-us')) {
        return l.localeId;
      }
    }
    // 5) Herhangi bir İngilizce
    for (final l in list) {
      if (l.localeId.toLowerCase().startsWith('en')) return l.localeId;
    }
    // 6) Son çare: ilk locale
    return list.first.localeId;
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
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'voice_input_service'); }
  }

  static Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'voice_input_service'); }
  }
}
