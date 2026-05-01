// TtsService — Text-to-Speech sarmalayıcısı.
// AI cevaplarını sesli okuma için. flutter_tts native iOS/Android engine
// kullanır; LocaleService dil koduna göre lokalize seslendirme.

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static bool _speaking = false;

  static bool get isSpeaking => _speaking;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _tts.setStartHandler(() => _speaking = true);
      _tts.setCompletionHandler(() => _speaking = false);
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _speaking = false);
      // Doğal ve hızlı: rate 0.55 (varsayılan 0.5 biraz robotik); pitch 1.0
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.55);
      await _tts.setVolume(1.0);
      // iOS — diğer ses kanallarını dur
      await _tts.setSharedInstance(true);
    } catch (e) {
      debugPrint('[TTS] init failed: $e');
    }
  }

  /// `langCode` ('tr', 'en', 'ja') → BCP-47 ('tr-TR', 'en-US', 'ja-JP')
  static String _toBcp47(String langCode) {
    const map = {
      'tr': 'tr-TR', 'en': 'en-US', 'de': 'de-DE', 'fr': 'fr-FR',
      'es': 'es-ES', 'it': 'it-IT', 'pt': 'pt-BR', 'ja': 'ja-JP',
      'ko': 'ko-KR', 'zh': 'zh-CN', 'ru': 'ru-RU', 'ar': 'ar-SA',
      'hi': 'hi-IN', 'nl': 'nl-NL', 'pl': 'pl-PL', 'sv': 'sv-SE',
    };
    return map[langCode.toLowerCase()] ??
        '$langCode-${langCode.toUpperCase()}';
  }

  static Future<void> speak(String text, {String langCode = 'tr'}) async {
    if (!_initialized) await init();
    if (text.trim().isEmpty) return;
    try {
      await _tts.setLanguage(_toBcp47(langCode));
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TTS] speak failed: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
      _speaking = false;
    } catch (_) {}
  }

  static Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (_) {}
  }
}
