// TtsService — Text-to-Speech sarmalayıcısı.
//
// AI cevaplarını sesli okuma için. flutter_tts native iOS/Android engine
// kullanır; LocaleService dil koduna göre lokalize seslendirme.
//
// MİMARİ — STREAM-FIRST (Gemini Live klonu):
//   • `enqueue(sentence)` — gelen cümleyi kuyruğa ekler ve worker konuşmaya
//     başlamamışsa tetikler. LLM stream'i chunk yazarken arayan kod
//     cümleyi algılar algılamaz buraya basar; ilk cümle ekrana düşmeden
//     önce sesli yanıt başlayabilir. (Latency: tüm cevabı bekleme süresi → 0.)
//   • Native engine ile `awaitSpeakCompletion(true)`: `await speak()` cümle
//     bitince döner → worker döngüsü doğal kuyruğa dönüşür.
//   • `waitUntilDone()` — caller "TTS bitti mi" sorusunu blocking biçimde
//     sorabilir (auto-relisten, vb.).
//   • `speakingNotifier` — UI dalga rengi / state için reactive sinyal.
//
// PROSODI:
//   • rate 0.58  → insan konuşma hızı ≈ 150-160 WPM (önceki 0.52 ~120 WPM,
//     hantal hissediyordu).
//   • pitch 1.02 → robotik düz değil, çok hafifçe canlı.
//   • Cümle bazlı parça çağrısı → engine kelime arası boşluğu otomatik
//     sıkıştırır; eski "tüm metni ver" yaklaşımındaki yapay nefes azalır.
//
// BARGE-IN:
//   • `stop()` kuyruğu siler + native speech'i durdurur — kullanıcı mic'e
//     basınca asistan anında susar.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'error_logger.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;
  static bool _speaking = false;
  static bool _wantStop = false;
  // Pre-warm sırasında handler'lar UI'a sinyal vermesin (false speaking).
  static bool _prewarming = false;

  // ── Sentence queue (stream-first mimari) ────────────────────────────────
  static final List<String> _sentenceQueue = [];
  static bool _queueRunning = false;
  static String _currentLang = 'tr-TR';

  /// UI dalga rengi vb. için reactive sinyal — başla/dur değişimlerinde
  /// listener'ları tetikler. `isSpeaking` getter polling içindir.
  static final ValueNotifier<bool> speakingNotifier = ValueNotifier(false);

  static bool get isSpeaking => _speaking || _sentenceQueue.isNotEmpty;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _tts.setStartHandler(() {
        if (_prewarming) return;
        _speaking = true;
        if (!speakingNotifier.value) speakingNotifier.value = true;
      });
      _tts.setCompletionHandler(() {
        if (_prewarming) return;
        _speaking = false;
        // Kuyruk boşsa UI'a "asistan sustu" sinyali yolla.
        if (_sentenceQueue.isEmpty && speakingNotifier.value) {
          speakingNotifier.value = false;
        }
      });
      _tts.setCancelHandler(() {
        if (_prewarming) return;
        _speaking = false;
        if (speakingNotifier.value) speakingNotifier.value = false;
      });
      _tts.setErrorHandler((_) {
        if (_prewarming) return;
        _speaking = false;
        if (_sentenceQueue.isEmpty && speakingNotifier.value) {
          speakingNotifier.value = false;
        }
      });

      // ── İnsansı tonlama ─────────────────────────────────────────────────
      //   pitch 1.02  → düz robotik değil, çok hafifçe canlı
      //   rate  0.58  → ~155 WPM doğal konuşma; cümleler arası engine zaten
      //                 nefes verir, ekstra delay eklemiyoruz.
      //   volume 1.0  → tam ses
      await _tts.setPitch(1.02);
      await _tts.setSpeechRate(0.58);
      await _tts.setVolume(1.0);

      // KRİTİK: `await speak(...)` cümle bitene kadar bloklasın → worker
      // döngüsü doğrudan kuyruk gibi davranır, manuel completer şart değil.
      await _tts.awaitSpeakCompletion(true);

      // iOS — diğer ses kanallarını paylaş
      await _tts.setSharedInstance(true);

      // PRE-WARM: Android TTS engine cold-start 200-400ms. İlk gerçek
      // cümleden önce sessizce ısıtırsak kullanıcı gecikmeyi hissetmez.
      // volume=0 + boşluk speak → handler'lar prewarming flag ile UI'a
      // sinyal vermez, ses çıkmaz, engine kuyruğu hazır kalır.
      unawaited(_prewarm());
    } catch (e) {
      debugPrint('[TTS] init failed: $e');
    }
  }

  static Future<void> _prewarm() async {
    _prewarming = true;
    try {
      await _tts.setVolume(0.0);
      await _tts.setLanguage(_currentLang);
      // awaitSpeakCompletion(true) sayesinde await speak() cümle bitince döner.
      await _tts.speak(' ');
    } catch (e) {
      debugPrint('[TTS] prewarm failed: $e');
    } finally {
      try {
        await _tts.setVolume(1.0);
      } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'tts_service'); }
      _prewarming = false;
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

  /// Tek-shot konuşma — kısa metinler için.
  static Future<void> speak(String text, {String langCode = 'tr'}) async {
    if (!_initialized) await init();
    if (text.trim().isEmpty) return;
    _wantStop = false;
    try {
      await _tts.setVolume(1.0); // warmup koruması
      await _tts.setLanguage(_toBcp47(langCode));
      speakingNotifier.value = true;
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TTS] speak failed: $e');
    }
  }

  /// Stream-first ana API. LLM chunk'ları içinden cümle algılayan kod
  /// bu fonksiyonu çağırır — kuyruğa ekler ve worker yoksa başlatır.
  ///
  /// İlk çağrı: engine init + setLanguage; ardından kuyruk çalıştırıcı
  /// async olarak başlar. Asistanın "ilk kelime" gecikmesi ~0.
  static void enqueue(String sentence, {String langCode = 'tr'}) {
    final s = sentence.trim();
    if (s.isEmpty) return;
    _currentLang = _toBcp47(langCode);
    _wantStop = false;
    _sentenceQueue.add(s);
    // UI hemen "asistan cevaba başlıyor" sinyalini almalı — speak
    // start handler tetiklenmeden önce wave renk değişsin.
    if (!speakingNotifier.value) speakingNotifier.value = true;
    if (!_queueRunning) {
      _queueRunning = true;
      // Fire-and-forget worker
      // ignore: discarded_futures
      _runQueue();
    }
  }

  static Future<void> _runQueue() async {
    if (!_initialized) await init();
    try {
      // Warmup volume 0'da bırakmış olabilir — her gerçek konuşmadan
      // önce volume'u 1.0'a sabitle.
      await _tts.setVolume(1.0);
      await _tts.setLanguage(_currentLang);
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'tts_service'); }
    while (_sentenceQueue.isNotEmpty) {
      if (_wantStop) break;
      final s = _sentenceQueue.removeAt(0);
      try {
        // awaitSpeakCompletion(true) sayesinde speak() cümle bitene kadar
        // bekler. Doğal cümle akışı için bu yeterli.
        await _tts.speak(s);
      } catch (e) {
        debugPrint('[TTS] queue speak failed: $e');
        break;
      }
    }
    _queueRunning = false;
    _speaking = false;
    if (speakingNotifier.value) speakingNotifier.value = false;
  }

  /// Cümle bazlı streaming — tek seferde uzun metni cümlelere bölüp sıraya
  /// koyar. (LLM chunk akışı kullanılmıyorsa — fallback.)
  static Future<void> speakStreaming(String text,
      {String langCode = 'tr'}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    for (final sentence in _splitSentences(clean)) {
      if (_wantStop) break;
      if (sentence.isEmpty) continue;
      enqueue(sentence, langCode: langCode);
    }
    await waitUntilDone();
  }

  /// TTS kuyruğu boşalana ve son cümle bitene kadar bekle.
  /// Auto-relisten ve "mod kapanışı" gibi senaryolar için.
  static Future<void> waitUntilDone() async {
    // 80ms polling — wave/UI için "asistan sustu" tepkisi insan algı eşiğinin
    // (~100ms) altında kalır.
    while (!_wantStop && (_speaking || _sentenceQueue.isNotEmpty)) {
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  /// Metni doğal cümlelere böl. "." "!" "?" sonlarını ayraç sayar;
  /// kısaltmaları kabaca atlar (çok kısa parçayı yutar).
  static Iterable<String> _splitSentences(String text) sync* {
    final regex = RegExp(r'([^.!?]+[.!?]+|\S[^.!?]*$)', multiLine: true);
    for (final m in regex.allMatches(text)) {
      final s = m.group(0)?.trim() ?? '';
      if (s.isEmpty) continue;
      if (s.length < 4 && (s.endsWith('.') || s.endsWith('!'))) continue;
      yield s;
    }
  }

  /// Konuşmayı anında kes (barge-in). Worker döngüsü de durur.
  static Future<void> stop() async {
    _wantStop = true;
    _sentenceQueue.clear();
    try {
      await _tts.stop();
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'tts_service'); }
    _speaking = false;
    if (speakingNotifier.value) speakingNotifier.value = false;
  }

  static Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'tts_service'); }
  }
}
