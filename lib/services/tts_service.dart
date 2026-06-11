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
import 'package:shared_preferences/shared_preferences.dart';

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

  // ── Konuşma hızı (kullanıcı tunable) ───────────────────────────────────
  // Default 0.58 ≈ 155 WPM doğal konuşma. Özet sayfası 0.5x/1x/1.5x/2x
  // çarpanlarıyla bu değeri ölçekler (0.29 / 0.58 / 0.87 / 1.16).
  static const double _defaultRate = 0.58;
  static double _rate = _defaultRate;
  static const String _kRatePrefKey = 'tts_speech_rate';
  static double get currentRate => _rate;

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

      // Persisted hızı yükle — kullanıcı önceki oturumda değiştirdiyse korunur.
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getDouble(_kRatePrefKey);
        if (saved != null) _rate = saved.clamp(0.15, 1.50);
      } catch (_) {}

      // ── İnsansı KADIN tonlama ───────────────────────────────────────────
      //   pitch 1.08  → kadın sesine yakın, doğal-canlı (robotik düz değil)
      //   rate  _rate → varsayılan 0.58 ~155 WPM; kullanıcı hızı SharedPrefs'te
      //   volume 1.0  → tam ses
      await _tts.setPitch(1.08);
      await _tts.setSpeechRate(_rate);
      await _tts.setVolume(1.0);

      // tr-TR KADIN + en doğal (network/enhanced) sesi seç.
      await _applyPreferredVoice();

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

  // ── Sesli okumadan emoji/simge/ikon temizliği ──────────────────────────
  // Ekran/etiket emojileri ("🧠", "•", "→", "⚡") sesli anlatımda OKUNMAZ.
  static final RegExp _symRe = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{27BF}\u{2B00}-\u{2BFF}'
    r'\u{2600}-\u{26FF}\u{25A0}-\u{25FF}\u{2022}\u{2023}\u{25CF}\u{25CB}'
    r'\u{FE00}-\u{FE0F}\u{200D}]',
    unicode: true,
  );
  static String _sanitize(String t) =>
      t.replaceAll(_symRe, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// tr-TR için KADIN + en doğal (network/enhanced) sesi seçer.
  /// Cihazda kadın ses yoksa pitch 1.08 zaten kadınsı tona yaklaştırır.
  static Future<void> _applyPreferredVoice() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return;
      final tr = voices.whereType<Map>().where((v) {
        final loc = (v['locale'] ?? v['language'] ?? '').toString().toLowerCase();
        return loc.startsWith('tr');
      }).toList();
      if (tr.isEmpty) return;
      final femaleRe = RegExp(
        r'female|kad[ıi]n|yelda|filiz|seda|elif|aylin|meltem|nazli',
        caseSensitive: false,
      );
      final netRe =
          RegExp(r'network|enhanced|premium|neural', caseSensitive: false);
      Map? best;
      int bestScore = -1;
      for (final v in tr) {
        final name = (v['name'] ?? '').toString();
        final gender = (v['gender'] ?? '').toString().toLowerCase();
        int score = 0;
        if (gender == 'female' || femaleRe.hasMatch(name)) score += 4;
        if (netRe.hasMatch(name)) score += 2;
        if (score > bestScore) {
          bestScore = score;
          best = v;
        }
      }
      if (best != null) {
        await _tts.setVoice({
          'name': (best['name'] ?? '').toString(),
          'locale':
              (best['locale'] ?? best['language'] ?? 'tr-TR').toString(),
        });
      }
    } catch (_) {}
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
    final clean = _sanitize(text);
    if (clean.isEmpty) return;
    _wantStop = false;
    try {
      await _tts.setVolume(1.0); // warmup koruması
      await _tts.setLanguage(_toBcp47(langCode));
      speakingNotifier.value = true;
      await _tts.speak(clean);
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
    final s = _sanitize(sentence);
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

  /// Konuşma hızını ayarlar (kalıcı). Aralık 0.15–1.50 ile clamp edilir.
  /// 0.58 doğal konuşma (~155 WPM); 0.29 yavaş öğrenme, 1.16 hızlı tekrar.
  /// Aktif konuşma varsa bir sonraki cümlede hız değişir.
  static Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.15, 1.50);
    try {
      if (_initialized) await _tts.setSpeechRate(_rate);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kRatePrefKey, _rate);
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'tts_service');
    }
  }
}
