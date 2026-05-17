// LiveAnalysisScreen — QuAlsar Sesli Etkileşim (Gemini Live klonu).
//
// PERFORMANS NOTLARI (ANR çözümü için kritik):
//   • Voice level VE live transcript ValueNotifier ile yönetilir → STT'nin
//     30Hz+ callback'leri yalnızca dalga & balon widget'larını yeniden çizer,
//     tüm widget tree'yi rebuild ETMEZ.
//   • Dalga animasyonu RepaintBoundary içinde → diğer katmanlardan izole.
//   • Renkler ve dalga sabitleri const → her build'de yeni Color allocation yok.
//   • CameraController.initialize() Future.microtask ile başlar → initState
//     UI thread'ini bloklamaz; "Kamera açılıyor…" loader görünür.
//   • Painter'da sin/cos hesabı: step 8px (eski 4px) + 2 katman (eski 3) →
//     frame başına ~%50 daha az hesap.
//   • Konuşmalar toggle KAPALIYKEN UI render etmez ama _messages listesinde
//     korunur → açıldığında tüm geçmiş hazır.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../main.dart' show globalCameras, localeService;
import '../services/analytics.dart';
import '../services/gemini_service.dart';
import '../services/runtime_translator.dart';
import '../services/tts_service.dart';
import '../services/usage_quota.dart';
import '../services/voice_input_service.dart';
import '../widgets/latex_text.dart';

import '../theme/app_theme.dart';
// ─── Const renkler (build içinde Color allocation yapmamak için) ──────────
const _kBlue1 = Color(0xFF1E90FF);
const _kBlue2 = Color(0xFF00BFFF);
// Asistan cevap üretirken / konuşurken kullanılan canlı ton — kullanıcı
// "düşünme spinner'ı" yerine dalga renginin değiştiğini hemen görür.
const _kReply1 = Color(0xFF00E5FF);
const _kReply2 = Color(0xFFB5F5FF);
const _kBtnBg = Color(0xFF202024);
const _kDangerBg = Color(0xFFE83D3D);

/// Stream sırasında metni mutate edebilmek için non-final.
class _ChatMsg {
  final String role;
  String text;
  bool pending;
  final DateTime time;
  _ChatMsg({required this.role, required this.text, this.pending = false})
      : time = DateTime.now();
}

String _fmtTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

class LiveAnalysisScreen extends StatefulWidget {
  const LiveAnalysisScreen({super.key});

  @override
  State<LiveAnalysisScreen> createState() => _LiveAnalysisScreenState();
}

class _LiveAnalysisScreenState extends State<LiveAnalysisScreen>
    with TickerProviderStateMixin {
  // Camera
  CameraController? _cam;
  bool _camReady = false;
  bool _camActive = false;
  bool _camOpening = false;

  // Voice — yüksek frekanslı; ValueNotifier ile ayrı render
  bool _listening = false;
  final ValueNotifier<double> _voiceLevel = ValueNotifier(0);
  final ValueNotifier<String> _liveTranscript = ValueNotifier('');
  // Voice level throttling — STT 30Hz veriyor, biz 10Hz'e indiriyoruz.
  int _lastVoiceLevelEmit = 0;

  // Conversation
  bool _thinking = false;
  bool _paused = false;
  // Yavaş bağlantı göstergesi — istek 5sn'den uzun sürerse true.
  bool _slowConnection = false;
  Timer? _slowConnTimer;
  final List<_ChatMsg> _messages = [];
  final ScrollController _chatScroll = ScrollController();

  // Typing panel
  bool _chatPanelOpen = false;
  final TextEditingController _textCtrl = TextEditingController();

  bool _showTranscript = false;

  late final AnimationController _wave;
  late final AnimationController _pulse;
  late final AnimationController _logoRot; // header logo yavaş dönüş

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: Duration(seconds: 6),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1100),
    );
    _logoRot = AnimationController(
      vsync: this,
      duration: Duration(seconds: 22), // yavaş, premium
    );
    // Servis init + animasyonları async başlat — initState bloklanmasın.
    Future.microtask(() async {
      if (!mounted) return;
      _wave.repeat();
      _pulse.repeat(reverse: true);
      _logoRot.repeat();
      // VoiceInputService callback API kaldırıldı; init yeterli.
      await VoiceInputService.init();
      await TtsService.init();
    });
  }

  // ─── Kamera ─────────────────────────────────────────────────────────────
  Future<void> _toggleCamera() async {
    if (_camOpening) return;
    if (_camActive) {
      final old = _cam;
      setState(() {
        _cam = null;
        _camReady = false;
        _camActive = false;
        // Mod değişimi: önceki moddan kalan mesajlar yeni moda taşmasın.
        _messages.clear();
        _liveTranscript.value = '';
      });
      // dispose'u arka planda yap → UI bloklanmasın.
      unawaited(Future(() async => await old?.dispose()));
      return;
    }
    // Kamera açılıyor → varsa eski sesli mod mesajlarını da temizle.
    setState(() {
      _camOpening = true;
      _messages.clear();
      _liveTranscript.value = '';
    });
    try {
      List<CameraDescription> cams = globalCameras;
      if (cams.isEmpty) {
        cams = await availableCameras();
        globalCameras = cams;
      }
      if (cams.isEmpty) {
        if (mounted) setState(() => _camOpening = false);
        _showSnack('Kamera bulunamadı'.tr());
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      // Düşük çözünürlük → bellek ve CPU tasarrufu (preview için yeterli;
      // _captureFrame() yine aynı controller'dan tam kalitede fotoğraf çeker).
      final ctrl = CameraController(
        back,
        ResolutionPreset.high, // medium → high: net görüntü için
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      if (!mounted) {
        unawaited(Future(() async => await ctrl.dispose()));
        return;
      }
      // Sürekli otofokus + otomatik exposure → görüntü her zaman net.
      try {
        await ctrl.setFocusMode(FocusMode.auto);
        await ctrl.setExposureMode(ExposureMode.auto);
      } catch (_) {/* bazı cihazlar desteklemiyor — sessizce geç */}
      setState(() {
        _cam = ctrl;
        _camReady = true;
        _camActive = true;
        _camOpening = false;
      });
    } catch (e) {
      debugPrint('[LiveAnalysis] camera init failed: $e');
      if (mounted) setState(() => _camOpening = false);
      _showSnack('Kamera açılamadı'.tr());
    }
  }

  Future<File?> _captureFrame() async {
    final ctrl = _cam;
    if (ctrl == null || !ctrl.value.isInitialized) return null;
    try {
      final XFile xf = await ctrl.takePicture();
      final raw = await xf.readAsBytes();
      // ── EDGE COMPRESSION ────────────────────────────────────────────────
      // Tam çözünürlüklü kareler 2-6 MB; Gemini içerik analizine 720p
      // çoğu zaman fazlasıyla yeterli (yazılı problem, formül, sahne).
      // Isolate (compute) → ana thread bloklanmaz, JPEG encode 50-150ms.
      // Sonuç ~80-220 KB → upload süresi 1-2 sn → bant TTS'e kalır.
      Uint8List bytes;
      try {
        bytes = await compute(_compressFrameForLive, raw);
      } catch (e) {
        // image paketi başarısızsa orijinali kullan — analiz bozulmasın.
        debugPrint('[LiveAnalysis] frame compression failed: $e');
        bytes = raw;
      }
      final dir = await getTemporaryDirectory();
      final dest =
          '${dir.path}/qa_live_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final f = File(dest);
      await f.writeAsBytes(bytes, flush: true);
      return f;
    } catch (e) {
      return null;
    }
  }

  // ─── Sesli giriş ────────────────────────────────────────────────────────
  Future<void> _startListening() async {
    if (_thinking || _listening || _paused) return;
    final ok = await VoiceInputService.requestMic();
    if (!ok) {
      _showSnack('Mikrofon izni reddedildi'.tr());
      return;
    }
    final localeId = await VoiceInputService.resolveLocaleId(
      localeService.localeCode,
    );
    await TtsService.stop();
    setState(() => _listening = true);
    _voiceLevel.value = 0;
    _liveTranscript.value = '';
    // VAD — Live mode için kısa pauseFor (2.5sn) → kullanıcı araya
    // girince hızla algılar, gereksiz bekleme yapmaz.
    final started = await VoiceInputService.start(
      localeId: localeId,
      // pauseFor 3500 ms — kullanıcı düşünüp konuşmaya başlama süresi.
      // Çok kısa olursa konuşmaya başlamadan kapanır, "algılanmadı" hatası.
      pauseFor: Duration(milliseconds: 3500),
      listenFor: Duration(seconds: 90),
      onResult: (text, isFinal) {
        if (!mounted) return;
        _liveTranscript.value = text;
        if (isFinal && text.trim().isNotEmpty) {
          _onSpeechFinished(text);
        }
      },
      onLevel: (lvl) {
        if (!mounted) return;
        // Throttle: 30Hz STT callback'lerini ~10Hz'e indir → animasyon
        // hâlâ akıcı, ama notifyListeners 3 kat azalır.
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastVoiceLevelEmit < 100) return;
        _lastVoiceLevelEmit = now;
        // Sadece anlamlı değişimde yay (smoothing).
        if ((lvl - _voiceLevel.value).abs() < 0.02) return;
        _voiceLevel.value = lvl;
      },
    );
    if (!started && mounted) {
      setState(() => _listening = false);
      _showSnack('Dinleme başlatılamadı'.tr());
    }
  }

  Future<void> _stopListening({bool sendIfText = false}) async {
    await VoiceInputService.stop();
    if (!mounted) return;
    final liveText = _liveTranscript.value;
    setState(() => _listening = false);
    _voiceLevel.value = 0;
    _liveTranscript.value = '';
    if (sendIfText) {
      if (liveText.trim().isNotEmpty) {
        _onSpeechFinished(liveText);
      } else {
        // STT durumunu da göster — debug için kritik (mic izni / locale / engine).
        final status = VoiceInputService.lastStatus;
        final err = VoiceInputService.lastError;
        final detail = err.isNotEmpty ? '[$err]' : '[$status]';
        _showSnack(
            'Konuşman algılanamadı. $detail Tekrar dene — yüksek sesle ve mikrofona yakın konuş.'
                .tr());
      }
    }
  }

  Future<void> _onSpeechFinished(String text) async {
    if (text.trim().isEmpty) return;
    if (!mounted) return;
    setState(() => _listening = false);
    _liveTranscript.value = '';
    await _sendUserMessage(text);
  }

  Future<void> _sendTypedMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    // Sohbet paneli AÇIK kalır + KLAVYE de açık kalır — kullanıcı arka
    // arkaya yazabilsin. Klavye sadece geri tuşuna basınca kapatılır.
    await _sendUserMessage(text);
  }

  Future<void> _sendUserMessage(String text) async {
    final quota = await UsageQuota.get(QuotaKind.solution);
    if (quota.isExhausted) {
      Analytics.logQuotaExhausted(QuotaKind.solution.name);
      _showSnack('Günlük çözüm sınırı doldu'.tr());
      return;
    }
    await UsageQuota.increment(QuotaKind.solution);
    Analytics.logEvent('live_analysis', params: {
      'lang': localeService.localeCode,
      'q_len': text.length,
      'has_image': _camActive ? '1' : '0',
    });

    setState(() {
      _messages.add(_ChatMsg(role: 'user', text: text));
      _messages.add(_ChatMsg(role: 'ai', text: '', pending: true));
      _thinking = true;
      _slowConnection = false;
    });
    _scrollToBottom();

    // 5sn'den uzun sürerse yavaş bağlantı bildirimi göster.
    _slowConnTimer?.cancel();
    _slowConnTimer = Timer(Duration(seconds: 5), () {
      if (mounted && _thinking) {
        setState(() => _slowConnection = true);
      }
    });

    File? frame;
    if (_camActive) frame = await _captureFrame();

    // Bağlam: son 6 mesajı (pending hariç) Gemini'a gönder → asistan
    // önceki konuşmayı hatırlar, "kafa karışıklığı" azalır.
    final history = _messages
        .where((m) => !m.pending && m != _messages.last)
        .toList();
    // Son kullanıcı mesajı zaten içeride (yeni eklenen) — onu hariç tut.
    final pendingIdx = _messages.lastIndexWhere((m) => m.pending);
    final lastUserIdx = pendingIdx > 0 ? pendingIdx - 1 : -1;
    final ctx = <({String role, String text})>[];
    for (int i = 0; i < history.length && i < lastUserIdx; i++) {
      final m = history[i];
      // Son 6 mesajı al (perf + token tasarrufu)
      if (history.length - i > 6) continue;
      ctx.add((role: m.role, text: m.text));
    }

    try {
      // Stream: chunk chunk geldikçe pending bubble'ın text'ini güncelle.
      final stream = GeminiService.chatWithImageStream(
        imagePath: frame?.path,
        userMessage: text,
        langCode: localeService.localeCode,
        previousMessages: ctx,
      );

      final buffer = StringBuffer();
      DateTime lastTick = DateTime.now();
      bool firstChunk = true;
      // STREAM-FIRST TTS — buffer içinde "ne kadarı seslendirildi" cursor'u.
      // Yeni chunk gelince bu cursor'dan sonraki tamamlanmış cümleler
      // anında TTS kuyruğuna basılır → ilk kelime gecikmesi ~0.
      int ttsCursor = 0;
      final isVoiceMode = !_chatPanelOpen;
      final langCode = localeService.localeCode;

      await for (final chunk in stream) {
        if (!mounted) return;
        buffer.write(chunk);
        // İlk chunk → pending'i kapat, slow göstergesini sil.
        if (firstChunk) {
          firstChunk = false;
          _slowConnTimer?.cancel();
          setState(() {
            _slowConnection = false;
            if (_messages.isNotEmpty && _messages.last.pending) {
              _messages.last.pending = false;
            }
          });
        }
        // STREAM-FIRST TTS: yeni tamamlanan cümle(ler)i seslendirme kuyruğuna at.
        if (isVoiceMode) {
          ttsCursor = _emitSentencesToTts(
              buffer.toString(), ttsCursor, langCode);
        }
        // Throttle: her 120ms bir setState (jank engelle).
        final now = DateTime.now();
        if (now.difference(lastTick).inMilliseconds >= 120) {
          lastTick = now;
          setState(() {
            if (_messages.isNotEmpty && _messages.last.role == 'ai') {
              _messages.last.text = buffer.toString();
            }
          });
        }
      }
      // Final flush
      if (!mounted) return;
      _slowConnTimer?.cancel();
      final raw = buffer.toString().trim();
      // Stream hiç chunk vermeden kapandı → Gemini "boş response" döndü.
      // Sessiz kalmak yerine kullanıcıya açık bir mesaj göster ki AI'nın
      // yanıt vermediğini anlasın (ağ/quota/key sorunu vb.).
      if (raw.isEmpty) {
        setState(() {
          _thinking = false;
          _slowConnection = false;
          if (_messages.isNotEmpty && _messages.last.pending) {
            _messages.removeLast();
          }
          _messages.add(_ChatMsg(
            role: 'ai',
            text:
                'Şu an cevap üretilemedi. İnternet bağlantını ve günlük çözüm sınırını kontrol et, sonra tekrar dene.'
                    .tr(),
          ));
        });
        _scrollToBottom();
        return;
      }
      final cleaned = _stripMediaSuggestions(raw);
      // _thinking bilerek henüz `false` DEĞİL — TTS hâlâ konuşuyor olabilir,
      // wave rengi "asistan cevap veriyor" tonunda kalsın.
      setState(() {
        _slowConnection = false;
        if (_messages.isNotEmpty && _messages.last.role == 'ai') {
          _messages.last.text = cleaned;
          _messages.last.pending = false;
        }
      });
      _scrollToBottom();

      if (isVoiceMode) {
        // Stream bitti — tail (terminator yoksa) cümlesini de kuyruğa at.
        _emitSentencesToTts(buffer.toString(), ttsCursor, langCode,
            force: true);
        // TTS kuyruğu boşalana kadar bekle → wave rengi & auto-relisten
        // tam bu noktadan tetiklenir.
        await TtsService.waitUntilDone();
      }
      if (!mounted) return;
      setState(() => _thinking = false);

      // KAMERA + SES SÜREKLİ DİYALOG MODU:
      // AI cevabı bittikten sonra, kamera ya da sesli mod aktifse mikrofonu
      // OTOMATİK tekrar aç. Kullanıcı manuel mic'e basmadan sohbete devam
      // eder — gerçek "asistanla konuşma" hissi.
      if (mounted &&
          !_chatPanelOpen &&
          !_paused &&
          !_listening &&
          !_thinking) {
        // Audio session'ın TTS'ten STT'ye geçişi için kısa pencere.
        await Future.delayed(const Duration(milliseconds: 250));
        if (mounted && !_listening && !_chatPanelOpen && !_paused) {
          await _startListening();
        }
      }
    } on GeminiException catch (e) {
      if (!mounted) return;
      _slowConnTimer?.cancel();
      // Hata mesajı + (varsa) ham HTTP detayı — debug için kullanıcı sebebi
      // görebilsin. Ham detay yoksa sadece userMessage gösterilir.
      final detail = e.rawError;
      final fullMsg = detail.isEmpty
          ? e.userMessage
          : '${e.userMessage}\n\nDetay: $detail';
      setState(() {
        _thinking = false;
        _slowConnection = false;
        if (_messages.isNotEmpty && _messages.last.pending) {
          _messages.removeLast();
        }
        _messages.add(_ChatMsg(role: 'ai', text: fullMsg));
      });
      _scrollToBottom();
    } catch (e, stack) {
      if (!mounted) return;
      _slowConnTimer?.cancel();
      // Yakalanmamış istisna — stack trace'in ilk satırını da göster
      // (debug yardımı). Production'da stack kırpılabilir.
      final stackHead = stack.toString().split('\n').take(2).join('\n');
      setState(() {
        _thinking = false;
        _slowConnection = false;
        if (_messages.isNotEmpty && _messages.last.pending) {
          _messages.removeLast();
        }
        _messages.add(_ChatMsg(
          role: 'ai',
          text: 'Hata: $e\n\n$stackHead',
        ));
      });
      _scrollToBottom();
    }
  }

  // ─── STREAM-FIRST TTS yardımcısı ────────────────────────────────────────
  // `full`: o ana kadar buffer'a yazılmış tüm cevap.
  // `cursor`: en son seslendirilen char index'i.
  // `force`: stream bittikten sonra tail (sentence terminator olmadan
  //          kalan parça) için true → kalan her şeyi tek cümle gibi at.
  // RETURN: yeni cursor.
  //
  // İLK SEGMENT için KLAUZ MODU: cursor == 0 ise `.!?` yanında `,;:` de
  // ayraç sayılır. Bu sayede uzun ilk cümle de orta noktasından kesilip
  // hemen seslendirilebilir → "ilk kelime" gecikmesi 1-2sn düşer. Çok kısa
  // klauzlar (< 12 char, ör. "Tabii,") yutulur, sonraki ayracı dener.
  int _emitSentencesToTts(String full, int cursor, String langCode,
      {bool force = false}) {
    if (cursor >= full.length) return cursor;
    bool clauseMode = (cursor == 0) && !force;
    const int kClauseMinChars = 12;
    int searchFrom = cursor;
    while (searchFrom < full.length) {
      final end = clauseMode
          ? _findClauseEnd(full, searchFrom)
          : _findSentenceEnd(full, searchFrom);
      if (end == -1) break;
      final raw = full.substring(cursor, end + 1);
      final clean = _stripForTtsLite(raw);
      // Klauz modunda çok kısa segmenti yutma; sonraki ayraca git.
      if (clauseMode && clean.length < kClauseMinChars) {
        searchFrom = end + 1;
        continue;
      }
      if (clean.isNotEmpty) {
        TtsService.enqueue(clean, langCode: langCode);
      }
      cursor = end + 1;
      searchFrom = cursor;
      clauseMode = false; // sonraki segmentler için tam cümle ayracı
    }
    if (force && cursor < full.length) {
      final raw = full.substring(cursor).trim();
      if (raw.isNotEmpty) {
        final clean = _stripForTtsLite(raw);
        if (clean.isNotEmpty) {
          TtsService.enqueue(clean, langCode: langCode);
        }
      }
      cursor = full.length;
    }
    return cursor;
  }

  // Cümle ayracını bul: `.`, `!`, `?` (ondalık "3.14"i ayraç sayma).
  // Newline (`\n`) de cümle sınırı sayılır — model kısa paragraflar
  // veriyorsa ilk cümleyi hızlıca patlatır.
  int _findSentenceEnd(String s, int from) {
    for (int i = from; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      // '\n'
      if (c == 0x0A) return i;
      // '.', '!', '?'
      if (c == 0x2E || c == 0x21 || c == 0x3F) {
        // Ondalık ayraç ("3.14") — sonraki karakter rakamsa atla
        if (i + 1 < s.length) {
          final n = s.codeUnitAt(i + 1);
          if (n >= 0x30 && n <= 0x39) continue;
        }
        // Son karakter veya whitespace ardından gelmeli
        if (i + 1 == s.length) return i;
        final n = s.codeUnitAt(i + 1);
        if (n == 0x20 || n == 0x0A || n == 0x09 || n == 0x0D) return i;
      }
    }
    return -1;
  }

  // Klauz ayracı: cümle ayraçları + `,`, `;`, `:`. Sadece ilk segment
  // için kullanılır — sonraki segmentler tam cümle bazlı kalsın ki
  // prosodi bozulmasın.
  int _findClauseEnd(String s, int from) {
    for (int i = from; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      // '\n'
      if (c == 0x0A) return i;
      // '.', '!', '?', ',', ';', ':'
      final isSent = c == 0x2E || c == 0x21 || c == 0x3F;
      final isClause = c == 0x2C || c == 0x3B || c == 0x3A;
      if (!isSent && !isClause) continue;
      // Ondalık ayraç ("3.14")
      if (c == 0x2E && i + 1 < s.length) {
        final n = s.codeUnitAt(i + 1);
        if (n >= 0x30 && n <= 0x39) continue;
      }
      // Sayı içinde ":" (saat 09:30) ve "," (1,5) ayraç sayma
      if ((c == 0x3A || c == 0x2C) && i > 0 && i + 1 < s.length) {
        final p = s.codeUnitAt(i - 1);
        final n = s.codeUnitAt(i + 1);
        final prevDigit = p >= 0x30 && p <= 0x39;
        final nextDigit = n >= 0x30 && n <= 0x39;
        if (prevDigit && nextDigit) continue;
      }
      if (i + 1 == s.length) return i;
      final n = s.codeUnitAt(i + 1);
      if (n == 0x20 || n == 0x0A || n == 0x09 || n == 0x0D) return i;
    }
    return -1;
  }

  // Hızlı (in-line) TTS markdown/sembol stripleme. _stripForTtsCompute
  // tam sürümü; bu hot-path'ta isolate gerekmiyor (cümle ortalama 40-120 char).
  String _stripForTtsLite(String s) {
    return s
        .replaceAll(RegExp(r'\\\([\s\S]*?\\\)'), '')
        .replaceAll(RegExp(r'\\\[[\s\S]*?\\\]'), '')
        .replaceAll('**', '')
        .replaceAll(
            RegExp(r'[🔵🟢🟡🟣🔴🟠⚪🔑🧠🧪⚡💡🎓📦🔍📐📅🧬⚖️🎯🌍📖📚⭐📌]'), '')
        .replaceAll('|', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  String _stripMediaSuggestions(String s) {
    final lines = s.split('\n');
    final out = <String>[];
    final mediaRe = RegExp(r'^\s*\[(VIDEO|WEB|TEST):', caseSensitive: false);
    for (final line in lines) {
      if (mediaRe.hasMatch(line)) continue;
      out.add(line);
    }
    final headerRe = RegExp(
      r'^\s*(İlgili\s+(Videolar|Kaynaklar)|Daha\s+Fazla|Önerilen\s+(Video|Kaynak))s?\s*:?\s*$',
      caseSensitive: false,
    );
    while (out.isNotEmpty && headerRe.hasMatch(out.last)) {
      out.removeLast();
    }
    return out.join('\n').trimRight();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(seconds: 2),
    ));
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      if (_listening) _stopListening();
      TtsService.stop();
    }
  }

  @override
  void dispose() {
    _slowConnTimer?.cancel();
    _wave.dispose();
    _pulse.dispose();
    _logoRot.dispose();
    _voiceLevel.dispose();
    _liveTranscript.dispose();
    _chatScroll.dispose();
    _textCtrl.dispose();
    _cam?.dispose();
    if (_listening) VoiceInputService.cancel();
    TtsService.stop();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════
  // BUILD — ağır hesaplama YOK; const + state-only.
  // ═════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final chatMode = _chatPanelOpen;
    final dark = AppPalette.isDark(context);
    return Scaffold(
      // Sohbet (chat panel): aydınlık modda kirli beyaz #F5F5F5; karanlık
      // modda saf siyah (blackout). Diğer mod: zaten siyah.
      backgroundColor: chatMode
          ? (dark ? Colors.black : const Color(0xFFF5F5F5))
          : Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 1. Arka plan — kamera modunda saf siyah (kamera artık centerArea
          // içinde yuvarlak kart olarak render ediliyor, full-bleed değil).
          if (!chatMode && !_camActive)
            const Positioned.fill(
              child: RepaintBoundary(child: _GalaxyBackground()),
            ),

          // 2. Dalga — kamera modunda gizli (üst+alt siyah kalsın).
          //    Sohbet veya kamera kapalı modda render edilir.
          if (!chatMode && !_camActive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.42,
              child: RepaintBoundary(
                child: _WaveLayer(
                  wave: _wave,
                  voiceLevel: _voiceLevel,
                  thinking: _thinking,
                  compact: false,
                ),
              ),
            ),

          // 4. UI çatısı
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(child: _centerArea()),
                // Sohbet açıkken input bar — klavyenin/butonların hemen
                // üstünde, WhatsApp tarzı sticky.
                if (_chatPanelOpen) _chatInputBar(Colors.black),
                _bottomBar(),
              ],
            ),
          ),

          // 5. Kamera açılırken loader
          if (_camOpening)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBar() {
    final chatMode = _chatPanelOpen;
    // Sohbet modunda: SADECE QuAlsar yazısı, ortalanmış, biraz daha büyük.
    // Yan ikonlar (pause, transkript toggle) tamamen kaldırılır.
    if (chatMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Sol üstte geri tuşu — basınca sohbet panelini kapatır,
            // kullanıcıyı kamera/ses/mesaj butonlarının olduğu sesli moda
            // döndürür.
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _chatPanelOpen = false;
                    _messages.clear();
                    _liveTranscript.value = '';
                  });
                },
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppPalette.card(context),
                    border: Border.all(
                        color: AppPalette.border(context), width: 0.6),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 20,
                      color: AppPalette.textPrimary(context)),
                ),
              ),
            ),
            RichText(
              text: TextSpan(
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                  letterSpacing: 0.5,
                ),
                children: const [
                  TextSpan(text: 'Qu'),
                  TextSpan(
                    text: 'Al',
                    style: TextStyle(color: Color(0xFFFF0000)),
                  ),
                  TextSpan(text: 'sar'),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Normal mod: pause + dönen logo + transkript toggle.
    // Üst bar arka planı her zaman saf siyah (Scaffold bg'den geliyor) —
    // kamera artık full-bleed değil, gradient'e gerek yok.
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          _topIconButton(
            icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: _togglePause,
            active: _paused,
          ),
          Spacer(),
          // Sade header: sadece QuAlsar yazısı (Al kırmızı). Ekstra
          // ikon/logo yok — pause solda, transkript toggle sağda.
          RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
              children: const [
                TextSpan(text: 'Qu'),
                TextSpan(
                  text: 'Al',
                  style: TextStyle(color: Color(0xFFFF0000)),
                ),
                TextSpan(text: 'sar'),
              ],
            ),
          ),
          Spacer(),
          _topIconButton(
            icon: _showTranscript
                ? Icons.subtitles_rounded
                : Icons.subtitles_off_outlined,
            onTap: () {
              setState(() => _showTranscript = !_showTranscript);
              if (_showTranscript) _scrollToBottom();
            },
            active: _showTranscript,
          ),
        ],
      ),
    );
  }

  Widget _topIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Color(0x2EFFFFFF) : Color(0x0FFFFFFF),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: active ? Colors.white : Color(0xD9FFFFFF),
          size: 20,
        ),
      ),
    );
  }

  Widget _centerArea() {
    final cameraOn = _camActive;
    // Kamera modu: kamera kartı her zaman görünür; transkript butonu
    // şeffaf yuvarlak paneli kameranın altında, butonların hemen üstünde
    // gösterir/gizler.
    if (cameraOn) {
      final screenH = MediaQuery.of(context).size.height;
      final cameraCard = Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              (_camReady && _cam != null)
                  ? _CameraBackground(controller: _cam!)
                  : const ColoredBox(color: Colors.black),
              // Dinleniyor göstergesi — sağ üstte, transkript kapalı olsa bile
              // mikrofonun çalıştığını kullanıcıya bildirir.
              if (_listening)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _ListeningBadge(
                      voiceLevel: _voiceLevel, pulse: _pulse),
                ),
            ],
          ),
        ),
      );
      if (!_showTranscript) {
        if (_paused) {
          return Stack(
            children: [
              cameraCard,
              Center(
                child: Text(
                  'Duraklatıldı'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        }
        return cameraCard;
      }
      // Transkript açık → şeffaf-koyu yuvarlak panel, kameranın alt
      // kenarına oturur (alt butonların hemen üstünde).
      return Stack(
        children: [
          cameraCard,
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: screenH * 0.22),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter:
                      ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.6,
                      ),
                    ),
                    child: _camTranscriptPanel(transparent: true),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!_showTranscript) {
      if (_paused) {
        return Center(
          child: Text(
            'Duraklatıldı'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white54,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      return const SizedBox.expand();
    }

    // ── Yazışma kartı renkleri ──────────────────────────────────────────
    // 3 mod var:
    //   • Sesli mod (kamera yok, chat panel yok) → BEYAZ kart, siyah yazı
    //   • Kamera modu → frosted dark over camera, beyaz yazı
    //   • Chat panel → ayrı yola gidiyor (yukarıda return), beyaz card.
    final voiceMode = !cameraOn && !_chatPanelOpen;
    final Color cardBg;
    final Color textColor;
    final Color labelColor;
    final Color dimColor;
    if (cameraOn) {
      cardBg = Colors.black.withValues(alpha: 0.30);
      textColor = Colors.white;
      labelColor = Colors.white;
      dimColor = Colors.white.withValues(alpha: 0.65);
    } else if (voiceMode) {
      cardBg = Colors.white;
      textColor = Colors.black87;
      labelColor = Colors.black87;
      dimColor = Colors.black.withValues(alpha: 0.55);
    } else {
      // Fallback (chatPanel akışı zaten yukarıda return etti) — koyu.
      cardBg = Color(0xE6000000);
      textColor = Colors.white;
      labelColor = Colors.white;
      dimColor = Colors.white.withValues(alpha: 0.65);
    }

    final screenH = MediaQuery.of(context).size.height;

    final items = <Widget>[];
    for (final m in _messages) {
      items.add(_msgBlock(m, textColor: textColor, labelColor: labelColor));
      items.add(SizedBox(height: 10));
    }
    if (_listening) {
      items.add(ValueListenableBuilder<String>(
        valueListenable: _liveTranscript,
        builder: (_, v, __) => v.isEmpty
            ? const SizedBox.shrink()
            : _liveBlock(v, textColor: textColor, labelColor: labelColor),
      ));
      items.add(SizedBox(height: 10));
    }

    Widget body;
    if (_messages.isEmpty && !_listening && !_chatPanelOpen) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Henüz konuşma yok — mikrofona bas veya yaz.'.tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: dimColor,
              height: 1.5,
            ),
          ),
        ),
      );
    } else {
      final list = (_messages.isEmpty && !_listening)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Sohbete başla — yaz veya mikrofona bas.'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: dimColor,
                  ),
                ),
              ),
            )
          : ListView(
              controller: _chatScroll,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              children: items,
            );

      // Chat panel açıkken input ARTIK kart içinde değil — kart sadece
      // mesaj listesi gösterir. Input bar dış Column'a taşındı (alt
      // butonların hemen üstünde, klavyeyle birlikte yukarı kayar).
      body = list;
    }

    // Sohbet AÇIK ise: aydınlık modda soluk beyaz (#F5F5F5) çerçeve;
    // koyu modda TAM SİYAH çerçeve. Balonlar da koyu modda siyah, yazılar
    // tam beyaz.
    if (_chatPanelOpen) {
      final dark = AppPalette.isDark(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: Container(
          decoration: BoxDecoration(
            color: dark ? Colors.black : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.10)
                  : const Color(0x14000000),
              width: 0.6,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: body,
        ),
      );
    }

    // Sesli mod (beyaz kart) → BackdropFilter atlanır; opak beyaz zeminde
    // blur etkisiz + bazı cihazlarda rendering hatası yapabiliyor.
    // Kamera/dark modda yarı saydam kart üzerinde blur uygulanır.
    final cardBorder = Border.all(
      color: voiceMode
          ? Colors.black.withValues(alpha: 0.10)
          : (cameraOn
              ? Colors.black.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.12)),
      width: 0.6,
    );
    final Widget card = voiceMode
        ? Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: cardBorder,
            ),
            clipBehavior: Clip.hardEdge,
            child: body,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.hardEdge,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: cameraOn ? 10 : 12,
                sigmaY: cameraOn ? 10 : 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: cardBorder,
                ),
                clipBehavior: Clip.hardEdge,
                child: body,
              ),
            ),
          );

    // Kamera AÇIK akışı _centerArea'nın başında ele alınıyor (early return).

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenH * 0.55),
          child: card,
        ),
      ),
    );
  }

  /// Kamera modunda alt panelde gösterilen düz transkript akışı.
  /// `transparent: true` → şeffaf-koyu zeminde beyaz/açık tonlar; aksi
  /// halde beyaz panel (siyah/gri yazı). "Sen: ..." / "AI: ..." satırları
  /// balon DEĞİL — düzenli akış.
  Widget _camTranscriptPanel({bool transparent = false}) {
    final empty = _messages.isEmpty && !_listening;
    final emptyColor = transparent
        ? Colors.white.withValues(alpha: 0.75)
        : AppPalette.textSecondary(context);
    final bodyColor = transparent
        ? Colors.white
        : AppPalette.textPrimary(context);
    final dimColor = transparent
        ? Colors.white.withValues(alpha: 0.75)
        : AppPalette.textSecondary(context);
    final senLabelColor =
        transparent ? Color(0xFF93C5FD) : Color(0xFF1E3A8A);
    final aiLabelColor =
        transparent ? Color(0xFFC4B5FD) : Color(0xFF7C3AED);
    final pendingDotColor =
        transparent ? Colors.white70 : Colors.black54;

    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'Henüz konuşma yok — mikrofona bas veya yaz.'.tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: emptyColor,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
      );
    }
    return ListView(
      controller: _chatScroll,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      children: [
        for (final m in _messages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            // Pending + boş AI mesajı için "düşünüyor" göstergesi —
            // kullanıcı stream gelene kadar AI'nın çalıştığını görsün.
            child: (m.pending && m.text.isEmpty)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${'AI'.tr()}: ',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: aiLabelColor,
                          height: 1.4,
                        ),
                      ),
                      _PendingDots(color: pendingDotColor),
                      if (_slowConnection) ...[
                        SizedBox(width: 8),
                        Text(
                          'Bağlantı kontrol ediliyor…'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: dimColor,
                          ),
                        ),
                      ],
                    ],
                  )
                : RichText(
                    text: TextSpan(
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: bodyColor,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: m.role == 'user'
                              ? '${'Sen'.tr()}: '
                              : '${'AI'.tr()}: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: m.role == 'user'
                                ? senLabelColor
                                : aiLabelColor,
                          ),
                        ),
                        TextSpan(text: m.text),
                      ],
                    ),
                  ),
          ),
        if (_listening)
          ValueListenableBuilder<String>(
            valueListenable: _liveTranscript,
            builder: (_, v, __) => v.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      'Dinleniyor…'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: dimColor,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      v,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: dimColor,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
          ),
      ],
    );
  }

  /// WhatsApp tipi mesaj balonu. Kullanıcı SAĞDA, asistan SOLDA.
  /// Sohbet modunda beyaz arka + siyah yazı, balon arkası nazik gri/mavi.
  Widget _msgBlock(_ChatMsg m,
      {required Color textColor, required Color labelColor}) {
    final isUser = m.role == 'user';
    final chatMode = _chatPanelOpen;
    final cameraOn = _camActive;
    final voiceMode = !cameraOn && !chatMode;
    // Bubble bg seçimi:
    //  • Sohbet panel: aydınlık mod → balonlar TAM BEYAZ + TAM SİYAH yazı
    //                   koyu mod    → balonlar TAM SİYAH + TAM BEYAZ yazı
    //  • Sesli mod (beyaz kart): WhatsApp tarzı açık mavi/gri palet
    //  • Kamera açık (frosted card): yarı saydam balonlar → beyaz yazı
    final dark = AppPalette.isDark(context);
    final Color bubbleBg;
    if (chatMode) {
      bubbleBg = dark ? Colors.black : Colors.white;
    } else if (voiceMode) {
      bubbleBg = isUser
          ? Color(0xFFE7F4FF)
          : Color(0xFFF1F1F2);
    } else {
      // cameraOn → frosted bubble
      bubbleBg = isUser
          ? Color(0x1AFFFFFF) // beyaz %10 (spec)
          : Color(0x14000000); // siyah %8 (kontrast için)
    }
    // Sohbet panel → tam siyah/beyaz (mod'a göre); sesli mod → black87;
    // kamera → white.
    final effectiveTextColor = chatMode
        ? (dark ? Colors.white : Colors.black)
        : (voiceMode ? Colors.black87 : textColor);
    final effectiveLabelColor = chatMode
        ? (dark ? Colors.white : Colors.black)
        : (voiceMode ? Colors.black87 : labelColor);
    final screenW = MediaQuery.of(context).size.width;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: screenW * 0.78),
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
      decoration: BoxDecoration(
        color: bubbleBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        // Koyu mod sohbet → siyah balonlar siyah panelde ayrılsın diye
        // ince beyaz çerçeve.
        border: (chatMode && dark)
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.6,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.pending)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PendingDots(color: effectiveTextColor),
                // Sohbet modunda yalnız 3 nokta yanıp söner; "Bağlantı
                // kontrol ediliyor…" yazısı sadece sesli/kamera modunda.
                if (_slowConnection && !chatMode) ...[
                  SizedBox(width: 8),
                  Text(
                    'Bağlantı kontrol ediliyor…'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: effectiveTextColor.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            )
          else
            DefaultTextStyle(
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: effectiveTextColor,
                height: 1.45,
              ),
              child: LatexText(m.text, fontSize: 14, lineHeight: 1.45),
            ),
          SizedBox(height: 3),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              _fmtTime(m.time),
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: effectiveLabelColor.withValues(alpha: 0.50),
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [bubble],
      ),
    );
  }

  /// Canlı transkript balonu — kullanıcı sağda, italik soluk.
  Widget _liveBlock(String text,
      {required Color textColor, required Color labelColor}) {
    final chatMode = _chatPanelOpen;
    final cameraOn = _camActive;
    final voiceMode = !cameraOn && !chatMode;
    // Chat panel veya Sesli mod (beyaz kart) → açık mavi balon, siyah
    // italik metin. Kamera → mavi tinted, beyaz italik.
    final bubbleBg = (chatMode || voiceMode)
        ? Color(0xFFE7F4FF).withValues(alpha: 0.55)
        : Color(0x221E90FF);
    final effectiveTextColor =
        (chatMode || voiceMode) ? Colors.black87 : textColor;
    final screenW = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: screenW * 0.78),
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
            decoration: BoxDecoration(
              color: bubbleBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(
                color: effectiveTextColor.withValues(alpha: 0.20),
                width: 0.6,
              ),
            ),
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: effectiveTextColor.withValues(alpha: 0.70),
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// WhatsApp tarzı sticky input bar — alt butonların ÜSTÜNDE, klavyenin
  /// HEMEN ÜSTÜNDE. resizeToAvoidBottomInset:true sayesinde klavye
  /// açıldığında otomatik yukarı kayar.
  Widget _chatInputBar(Color textColor) {
    // Sesli mod / chat panel "blackout" — koyu modda zemin saf siyah, beyaz
    // metin ve cursor; aydınlık modda eski açık tasarım korunur.
    final dark = AppPalette.isDark(context);
    final barBg = dark ? Colors.black : const Color(0xFFF5F5F5);
    final fieldBg = dark ? Colors.black : Colors.white;
    final ink = dark ? Colors.white : textColor;
    final divider =
        dark ? Colors.white.withValues(alpha: 0.18) : const Color(0x14000000);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          top: BorderSide(color: divider, width: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              minLines: 1,
              maxLines: 4,
              cursorColor: ink,
              style: GoogleFonts.poppins(color: ink, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'QuAlsar\'a sor…'.tr(),
                hintStyle: GoogleFonts.poppins(
                    color: ink.withValues(alpha: 0.45),
                    fontSize: 13),
                filled: true,
                fillColor: fieldBg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: divider, width: 0.6),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: divider, width: 0.6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: _kBlue1, width: 0.8),
                ),
              ),
              onSubmitted: (_) => _sendTypedMessage(),
            ),
          ),
          SizedBox(width: 8),
          GestureDetector(
            onTap: _sendTypedMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_kBlue1, _kBlue2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              // Yukarı bak: send ikon doğal sağa bakar → -90° CCW ile yukarı.
              child: Transform.rotate(
                angle: -math.pi / 2,
                child: Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final cameraOn = _camActive;
    final chatMode = _chatPanelOpen;

    // Sohbet modunda: kamera + X butonları kaldırıldı (kullanıcı isteği) —
    // sadece chatInputBar'daki gönder oku kalır. Boş alt boşluk: SafeArea
    // padding'i kadar.
    if (chatMode) {
      return SizedBox(
        height: MediaQuery.of(context).padding.bottom * 0.4,
      );
    }

    return AnimatedContainer(
      duration: Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        14 + MediaQuery.of(context).padding.bottom * 0.4,
      ),
      decoration: BoxDecoration(
        color: cameraOn ? Colors.transparent : Colors.black,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(38)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BottomCircleButton(
            icon: cameraOn
                ? Icons.videocam_rounded
                : Icons.videocam_outlined,
            onTap: () async {
              // Kamera AÇILIRKEN STT'yi geçici durdur — bazı Android cihazlarda
              // CameraController.initialize() audio session'ı kısa süre
              // kilitleyebiliyor; STT'nin sonradan temiz başlaması için.
              final wasListening = _listening;
              if (!_camActive && wasListening) {
                await _stopListening();
              }
              await _toggleCamera();
              if (_camActive && !_thinking && !_paused) {
                // Audio session'ın oturmasına izin ver, sonra dinlemeyi başlat.
                // Otomatik konuşma YOK — kullanıcı komut verene kadar AI sessiz.
                await Future.delayed(const Duration(milliseconds: 250));
                if (mounted && _camActive && !_listening) {
                  await _startListening();
                }
              }
            },
            highlight: cameraOn,
            frosted: cameraOn,
          ),
          _BottomCircleButton(
            icon: Icons.chat_bubble_outline_rounded,
            onTap: () async {
              if (!_chatPanelOpen) {
                // Sohbet açılıyor → kamerayı tamamen kapat (kaynak boşalt)
                if (_camActive) {
                  final old = _cam;
                  setState(() {
                    _cam = null;
                    _camReady = false;
                    _camActive = false;
                  });
                  unawaited(Future(() async => await old?.dispose()));
                }
              }
              setState(() {
                _chatPanelOpen = !_chatPanelOpen;
                // Mod değişimi: sohbet panel toggle'ında önceki moddan
                // (sesli/kamera) kalan mesajlar yeni moda taşmasın —
                // kullanıcı her modda sıfırdan başlamış hissetsin.
                _messages.clear();
                _liveTranscript.value = '';
                if (_chatPanelOpen) {
                  _showTranscript = true;
                  _scrollToBottom();
                } else {
                  FocusScope.of(context).unfocus();
                }
              });
            },
            highlight: _chatPanelOpen,
            frosted: cameraOn,
          ),
          _BottomMicButton(
            listening: _listening,
            pulse: _pulse,
            voiceLevel: _voiceLevel,
            frosted: cameraOn,
            lightMode: !cameraOn,
            onTap: () {
              if (_listening) {
                _stopListening(sendIfText: true);
              } else {
                _startListening();
              }
            },
          ),
          _BottomCircleButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.of(context).maybePop(),
            danger: true,
            frosted: cameraOn,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Background isolate: kamera karesi sıkıştırma — 720px max + JPEG q70.
//  Live modda gönderilen kareler analiz için yeterli, fakat upload
//  süresini 5-10× kısaltır → asistanın "ilk kelime" gecikmesi düşer.
// ═════════════════════════════════════════════════════════════════════════
Uint8List _compressFrameForLive(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return input;
  const maxSide = 720;
  img.Image resized = decoded;
  if (decoded.width > maxSide || decoded.height > maxSide) {
    if (decoded.width >= decoded.height) {
      resized = img.copyResize(decoded, width: maxSide, interpolation: img.Interpolation.linear);
    } else {
      resized = img.copyResize(decoded, height: maxSide, interpolation: img.Interpolation.linear);
    }
  }
  return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
}

// ═════════════════════════════════════════════════════════════════════════
//  Kamera arka plan
// ═════════════════════════════════════════════════════════════════════════
class _CameraBackground extends StatelessWidget {
  final CameraController controller;
  const _CameraBackground({required this.controller});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.width * controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Wave layer — ValueListenableBuilder ile sadece dalgayı yeniden çizer.
// ═════════════════════════════════════════════════════════════════════════
class _WaveLayer extends StatelessWidget {
  final AnimationController wave;
  final ValueListenable<double> voiceLevel;
  final bool thinking;
  final bool compact;
  const _WaveLayer({
    required this.wave,
    required this.voiceLevel,
    required this.thinking,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: wave,
      builder: (_, __) {
        return ValueListenableBuilder<double>(
          valueListenable: voiceLevel,
          builder: (_, lvl, ___) => CustomPaint(
            painter: _WavePainter(
              phase: wave.value * 2 * math.pi,
              level: lvl,
              thinking: thinking,
              compact: compact,
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final double phase;
  final double level;
  final bool thinking;
  final bool compact;

  _WavePainter({
    required this.phase,
    required this.level,
    required this.thinking,
    required this.compact,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Asistan cevap üretirken/konuşurken canlı cyan tona geç — kullanıcı
    // VAD final olur olmaz dalga renginin değiştiğini anında görür.
    final Color c1 = thinking ? _kReply1 : _kBlue1;
    final Color c2 = thinking ? _kReply2 : _kBlue2;

    // Galaksi zemini üzerinde dalga DAHA TRANSPARAN — alt katman olarak
    // kalır, galaksi yıldızları/sis bandı görünür kalır.
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, h),
        [
          Colors.transparent,
          c1.withValues(alpha: compact ? 0.10 : 0.12),
          c2.withValues(alpha: compact ? 0.25 : 0.32),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    final amp = compact ? 6 + 8 * level : 14 + 36 * level + (thinking ? 8 : 0);
    final layers = compact ? 1 : 2; // 3 → 2 katman: ~%33 daha az hesap
    const step = 8.0; // 4 → 8 piksel: ~%50 daha az nokta

    for (int i = 0; i < layers; i++) {
      final p = Path();
      final phaseShift = phase + i * 0.8;
      final freq = 1.6 + i * 0.4;
      final yBase = compact ? h * 0.45 : h * (0.45 + i * 0.16);

      p.moveTo(0, yBase);
      for (double x = 0; x <= w; x += step) {
        final t = x / w;
        final y = yBase +
            math.sin(t * freq * math.pi * 2 + phaseShift) * amp +
            math.sin(t * (freq + 1.3) * math.pi * 2 - phaseShift * 0.7) *
                amp *
                0.45;
        p.lineTo(x, y);
      }
      p.lineTo(w, h);
      p.lineTo(0, h);
      p.close();

      final paint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, yBase - amp),
          Offset(0, h),
          [
            c1.withValues(alpha: compact ? 0.16 : 0.10),
            c2.withValues(alpha: compact ? 0.50 : 0.38),
          ],
        );
      canvas.drawPath(p, paint);
    }

    if (compact) {
      final glowPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, h * 0.40),
          Offset(0, h * 0.60),
          [
            Colors.transparent,
            c2.withValues(alpha: 0.55),
            Colors.transparent,
          ],
          const [0.0, 0.5, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRect(Rect.fromLTWH(0, h * 0.40, w, h * 0.20), glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.phase != phase ||
      old.level != level ||
      old.thinking != thinking ||
      old.compact != compact;
}

// ═════════════════════════════════════════════════════════════════════════
//  Alt bar: dairesel buton + mic
// ═════════════════════════════════════════════════════════════════════════
class _BottomCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
  final bool danger;
  final bool frosted;
  final bool lightMode;
  const _BottomCircleButton({
    required this.icon,
    required this.onTap,
    this.highlight = false,
    this.danger = false,
    this.frosted = false,
    // ignore: unused_element_parameter
    this.lightMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (danger) {
      bg = _kDangerBg;
      fg = Colors.white;
    } else if (lightMode) {
      // Sohbet ekranı (beyaz zemin) — açık ton minimalist
      bg = Color(0xFFF5F5F5);
      fg = Colors.black87;
    } else if (highlight) {
      bg = Colors.white;
      fg = Colors.black;
    } else if (frosted) {
      bg = Color(0x33FFFFFF);
      fg = Colors.white;
    } else {
      bg = _kBtnBg;
      fg = Color(0xEAFFFFFF);
    }

    final core = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(
          color: danger
              ? Colors.transparent
              : lightMode
                  ? Color(0x14000000)
                  : frosted
                      ? Color(0x40FFFFFF)
                      : Color(0x0FFFFFFF),
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: fg, size: 26),
    );

    Widget body = core;
    if (frosted && !danger && !highlight) {
      body = ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: core,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}

/// Mic butonu — listening + level değişimine sadece kendi alanı tepki verir.
class _BottomMicButton extends StatelessWidget {
  final bool listening;
  final AnimationController pulse;
  final ValueListenable<double> voiceLevel;
  final bool frosted;
  final bool lightMode;
  final VoidCallback onTap;
  const _BottomMicButton({
    required this.listening,
    required this.pulse,
    required this.voiceLevel,
    required this.onTap,
    this.frosted = false,
    this.lightMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        height: 60,
        child: AnimatedBuilder(
          animation: pulse,
          builder: (_, child) {
            return ValueListenableBuilder<double>(
              valueListenable: voiceLevel,
              builder: (_, lvl, __) {
                final scale = listening
                    ? 1.0 + 0.05 * pulse.value + 0.10 * lvl
                    : 1.0;
                final Color bg;
                final Color fg;
                if (listening) {
                  // Listening: light mode → mavi vurgu; dark → beyaz
                  bg = lightMode ? _kBlue1 : Colors.white;
                  fg = lightMode ? Colors.white : Colors.black;
                } else if (lightMode) {
                  bg = Color(0xFFF5F5F5);
                  fg = Colors.black87;
                } else if (frosted) {
                  bg = Color(0x33FFFFFF);
                  fg = Colors.white;
                } else {
                  bg = _kBtnBg;
                  fg = Color(0xEAFFFFFF);
                }
                final core = Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bg,
                    border: Border.all(
                      color: lightMode
                          ? Color(0x14000000)
                          : frosted
                              ? Color(0x40FFFFFF)
                              : Color(0x0FFFFFFF),
                      width: 0.8,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    listening
                        ? Icons.stop_rounded
                        : Icons.mic_none_rounded,
                    color: fg,
                    size: 26,
                  ),
                );
                Widget body = core;
                if (frosted && !listening) {
                  body = ClipOval(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: core,
                    ),
                  );
                }
                return Transform.scale(scale: scale, child: body);
              },
            );
          },
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Kamera modunda "Dinleniyor…" rozeti — mikrofonun çalıştığını kullanıcıya
//  sürekli görsel olarak bildirir; ses seviyesine göre nokta nabız atar.
// ═════════════════════════════════════════════════════════════════════════
class _ListeningBadge extends StatelessWidget {
  final ValueListenable<double> voiceLevel;
  final AnimationController pulse;
  const _ListeningBadge({required this.voiceLevel, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.6,
        ),
      ),
      child: AnimatedBuilder(
        animation: pulse,
        builder: (_, __) {
          return ValueListenableBuilder<double>(
            valueListenable: voiceLevel,
            builder: (_, lvl, ___) {
              final s = 1.0 + 0.25 * pulse.value + 0.50 * lvl;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: s,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFF3B30),
                      ),
                    ),
                  ),
                  SizedBox(width: 7),
                  Text(
                    'Dinleniyor…'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Üç noktalı "düşünüyor" loader
// ═════════════════════════════════════════════════════════════════════════
class _PendingDots extends StatefulWidget {
  final Color color;
  const _PendingDots({this.color = Colors.white});
  @override
  State<_PendingDots> createState() => _PendingDotsState();
}

class _PendingDotsState extends State<_PendingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
      AnimationController(vsync: this, duration: Duration(seconds: 1))
        ..repeat();

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = ((_ac.value * 3) - i).clamp(0.0, 1.0);
            final opacity = (phase < 0.5 ? phase * 2 : (1 - phase) * 2)
                .clamp(0.25, 1.0);
            return Container(
              margin: const EdgeInsets.only(right: 6),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  _GalaxyBackground — siyah arka plan yerine kullanılan prosedürel
//  "Samanyolu" efekti. CustomPainter ile:
//    • Derin koyu lacivert/mor radyal gradient (galaksi merkezi)
//    • Rastgele yıldız noktaları (3 farklı boy + parlaklık)
//    • Yatay sis bandı (galaksi düzlemi)
//  Gerçek HD asset (assets/images/milky_way.jpg) eklendiğinde bu widget
//  Image.asset(..., fit: BoxFit.cover) ile değiştirilebilir; pubspec.yaml
//  assets bloğuna kayıt yeterli olur.
// ═════════════════════════════════════════════════════════════════════════════
class _GalaxyBackground extends StatelessWidget {
  const _GalaxyBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GalaxyPainter(),
      size: Size.infinite,
    );
  }
}

class _GalaxyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Katman 1: derin uzay — radial gradient (merkez biraz mor, kenar siyah)
    final rect = Offset.zero & size;
    final radial = Paint()
      ..shader = RadialGradient(
        center: Alignment(0, -0.2),
        radius: 1.2,
        colors: const [
          Color(0xFF1A0F2E), // koyu mor
          Color(0xFF0A0518), // çok koyu lacivert
          Color(0xFF000000), // siyah kenar
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, radial);

    // Katman 2: galaksi düzlemi — yatay yumuşak sis bandı
    final bandRect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.42),
      width: size.width * 1.2,
      height: size.height * 0.55,
    );
    final band = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Color(0xFF3B2156).withValues(alpha: 0.35),
          Color(0xFF6B4F8E).withValues(alpha: 0.15),
          Color(0xFF3B2156).withValues(alpha: 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(bandRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawRect(bandRect, band);

    // Katman 3: yıldızlar — sabit seed ile reproducible
    // 3 boy: küçük (~%80), orta (~%18), parlak (~%2)
    final rng = math.Random(42);
    final starPaint = Paint();
    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
    const starCount = 220;
    for (int i = 0; i < starCount; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final r = rng.nextDouble();
      double radius;
      double alpha;
      if (r < 0.80) {
        radius = 0.5 + rng.nextDouble() * 0.6;
        alpha = 0.35 + rng.nextDouble() * 0.30;
      } else if (r < 0.98) {
        radius = 1.0 + rng.nextDouble() * 0.8;
        alpha = 0.55 + rng.nextDouble() * 0.30;
      } else {
        radius = 1.6 + rng.nextDouble() * 1.0;
        alpha = 0.85 + rng.nextDouble() * 0.15;
      }
      // Hafif renk varyasyonu (beyaz / soğuk mavi / sıcak amber)
      final tint = rng.nextDouble();
      Color c;
      if (tint < 0.65) {
        c = Colors.white;
      } else if (tint < 0.88) {
        c = Color(0xFFB8D4FF); // soğuk mavi
      } else {
        c = Color(0xFFFFD9A6); // sıcak amber
      }
      starPaint.color = c.withValues(alpha: alpha);
      canvas.drawCircle(Offset(dx, dy), radius, starPaint);
      // En parlaklarda hafif glow
      if (radius > 1.4) {
        glowPaint.color = c.withValues(alpha: alpha * 0.45);
        canvas.drawCircle(Offset(dx, dy), radius * 2.2, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) => false;
}
