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
import 'package:path_provider/path_provider.dart';
import '../main.dart' show globalCameras, localeService;
import '../services/analytics.dart';
import '../services/gemini_service.dart';
import '../services/runtime_translator.dart';
import '../services/tts_service.dart';
import '../services/usage_quota.dart';
import '../services/voice_input_service.dart';
import '../widgets/latex_text.dart';

// ─── Const renkler (build içinde Color allocation yapmamak için) ──────────
const _kBlue1 = Color(0xFF1E90FF);
const _kBlue2 = Color(0xFF00BFFF);
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
      duration: const Duration(seconds: 6),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _logoRot = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22), // yavaş, premium
    );
    // Servis init + animasyonları async başlat — initState bloklanmasın.
    Future.microtask(() async {
      if (!mounted) return;
      _wave.repeat();
      _pulse.repeat(reverse: true);
      _logoRot.repeat();
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
      });
      // dispose'u arka planda yap → UI bloklanmasın.
      unawaited(Future(() async => await old?.dispose()));
      return;
    }
    setState(() => _camOpening = true);
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
      final dir = await getTemporaryDirectory();
      final dest =
          '${dir.path}/qa_live_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final f = File(dest);
      await f.writeAsBytes(await xf.readAsBytes(), flush: true);
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
      pauseFor: const Duration(milliseconds: 2500),
      listenFor: const Duration(seconds: 90),
      onResult: (text, isFinal) {
        if (!mounted) return;
        _liveTranscript.value = text;
        if (isFinal && text.trim().isNotEmpty) {
          _onSpeechFinished(text);
        }
      },
      onLevel: (lvl) {
        if (!mounted) return;
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
    if (sendIfText && liveText.trim().isNotEmpty) {
      _onSpeechFinished(liveText);
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
    setState(() => _chatPanelOpen = false);
    FocusScope.of(context).unfocus();
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
    _slowConnTimer = Timer(const Duration(seconds: 5), () {
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
      final cleaned = _stripMediaSuggestions(buffer.toString());
      setState(() {
        _thinking = false;
        _slowConnection = false;
        if (_messages.isNotEmpty && _messages.last.role == 'ai') {
          _messages.last.text = cleaned;
          _messages.last.pending = false;
        }
      });
      _scrollToBottom();

      // TTS — TÜM cevabı oku, kesme yok. Strip arka planda.
      final ttsRaw = await compute(_stripForTtsCompute, cleaned);
      await TtsService.speak(ttsRaw, langCode: localeService.localeCode);
    } on GeminiException catch (e) {
      if (!mounted) return;
      _slowConnTimer?.cancel();
      setState(() {
        _thinking = false;
        _slowConnection = false;
        if (_messages.isNotEmpty && _messages.last.pending) {
          _messages.removeLast();
        }
        _messages.add(_ChatMsg(role: 'ai', text: e.userMessage));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _slowConnTimer?.cancel();
      setState(() {
        _thinking = false;
        _slowConnection = false;
        if (_messages.isNotEmpty && _messages.last.pending) {
          _messages.removeLast();
        }
        _messages.add(_ChatMsg(role: 'ai', text: e.toString()));
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
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
      duration: const Duration(seconds: 2),
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
    return Scaffold(
      // Sohbet: dış kirli beyaz #F5F5F5, içerideki çerçeve parlak beyaz.
      // Diğer mod: siyah (kamera/dalga arka plan).
      backgroundColor: chatMode ? const Color(0xFFF5F5F5) : Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 1. Kamera arka plan — sohbet açıkken HİÇ render etme.
          if (!chatMode && _camActive && _camReady && _cam != null)
            Positioned.fill(
              child: RepaintBoundary(
                child: _CameraBackground(controller: _cam!),
              ),
            )
          else if (!chatMode)
            const Positioned.fill(child: ColoredBox(color: Colors.black)),

          // 2. Karartma — sadece kamera açık + sohbet kapalı.
          if (!chatMode && _camActive)
            const Positioned.fill(
              child: ColoredBox(color: Color(0x26000000)),
            ),

          // 3. Dalga — sohbet açıkken render etme (CPU tasarrufu).
          if (!chatMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _camActive
                  ? 110
                  : MediaQuery.of(context).size.height * 0.42,
              child: RepaintBoundary(
                child: _WaveLayer(
                  wave: _wave,
                  voiceLevel: _voiceLevel,
                  thinking: _thinking,
                  compact: _camActive,
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: Color(0xFFFFB800), size: 20),
            const SizedBox(width: 8),
            RichText(
              text: TextSpan(
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
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
    // Kamera açıkken header'a hafif karartma → metinler okunaklı.
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: _camActive
          ? const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000)],
              ),
            )
          : null,
      child: Row(
        children: [
          _topIconButton(
            icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: _togglePause,
            active: _paused,
          ),
          const Spacer(),
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
          const Spacer(),
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
          color: active ? const Color(0x2EFFFFFF) : const Color(0x0FFFFFFF),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: active ? Colors.white : const Color(0xD9FFFFFF),
          size: 20,
        ),
      ),
    );
  }

  Widget _centerArea() {
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
    // Otomatik kontrast: zemin AÇIK ise yazı SİYAH, KOYU ise yazı BEYAZ.
    // whiteMode = sohbet panel veya kamera açık (her ikisinde de zemin
    // beyaz/açık). Aksi halde dark transparent kart → beyaz yazı.
    final cameraOn = _camActive;
    final whiteMode = _chatPanelOpen || cameraOn;
    final cardBg = whiteMode
        ? (cameraOn
            ? Colors.white.withValues(alpha: 0.70) // kamera arkası görünür
            : Colors.white) // sohbet panel
        // Kamera kapalı: derin siyah (eskiden 0.50 → çok soluk → 0.90)
        : const Color(0xE6000000);
    final textColor = whiteMode ? Colors.black : Colors.white;
    final labelColor = whiteMode ? Colors.black : Colors.white;
    final dimColor = whiteMode
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.65);

    final screenH = MediaQuery.of(context).size.height;

    final items = <Widget>[];
    for (final m in _messages) {
      items.add(_msgBlock(m, textColor: textColor, labelColor: labelColor));
      items.add(const SizedBox(height: 10));
    }
    if (_listening) {
      items.add(ValueListenableBuilder<String>(
        valueListenable: _liveTranscript,
        builder: (_, v, __) => v.isEmpty
            ? const SizedBox.shrink()
            : _liveBlock(v, textColor: textColor, labelColor: labelColor),
      ));
      items.add(const SizedBox(height: 10));
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

    // Sohbet AÇIK ise: dış #F5F5F5 + iç çerçeve parlak beyaz card.
    if (_chatPanelOpen) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x14000000), width: 0.6),
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

    // Frosted card — kamera AÇIKKEN white 70% + blur(10), KAPALIYKEN dark
    // transparent + blur(12). Her iki durumda da BackdropFilter uygulanır
    // çünkü yarı saydam zemin arkasını gösterir.
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      // İç içeriğin köşeleri taşmasın diye hardEdge clip
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
            border: Border.all(
              color: cameraOn
                  ? Colors.black.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.12),
              width: 0.6,
            ),
          ),
          // ListView içindeki yazılar kart sınırı dışına çıkmasın
          clipBehavior: Clip.hardEdge,
          child: body,
        ),
      ),
    );

    // Kamera AÇIK: kart EKRAN ALT YARISINDA (header'ın altında değil,
    // ortada/aşağıda). Üst yarı boş kalır → kamera görünür.
    // Kamera KAPALI: kart üst yarıda (dalga arkasında).
    if (cameraOn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          children: [
            const Spacer(flex: 1), // üst yarı boş — kamera görünür
            SizedBox(
              height: screenH * 0.45, // alt yarı yazışma alanı
              child: card,
            ),
          ],
        ),
      );
    }

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

  /// WhatsApp tipi mesaj balonu. Kullanıcı SAĞDA, asistan SOLDA.
  /// Sohbet modunda beyaz arka + siyah yazı, balon arkası nazik gri/mavi.
  Widget _msgBlock(_ChatMsg m,
      {required Color textColor, required Color labelColor}) {
    final isUser = m.role == 'user';
    final chatMode = _chatPanelOpen;
    final cameraOn = _camActive;
    // Bubble bg seçimi:
    //  • Sohbet panel: WhatsApp palette (kullanıcı mavi, AI gri)
    //  • Kamera açık (frosted card): kullanıcı rgba(255,255,255,0.10),
    //                                AI siyah-soluk (rgba(0,0,0,0.04))
    //  • Kamera kapalı dark: yarı saydam balonlar
    final Color bubbleBg;
    if (chatMode) {
      bubbleBg = isUser
          ? const Color(0xFFE7F4FF)
          : const Color(0xFFF1F1F2);
    } else if (cameraOn) {
      bubbleBg = isUser
          ? const Color(0x1AFFFFFF) // beyaz %10 (spec)
          : const Color(0x14000000); // siyah %8 (kontrast için)
    } else {
      bubbleBg = isUser
          ? const Color(0x331E90FF)
          : const Color(0x1AFFFFFF);
    }
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.pending)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PendingDots(color: textColor),
                if (_slowConnection) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Bağlantı kontrol ediliyor…'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: textColor.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            )
          else
            DefaultTextStyle(
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: textColor,
                height: 1.45,
              ),
              child: LatexText(m.text, fontSize: 14, lineHeight: 1.45),
            ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              _fmtTime(m.time),
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
                color: textColor.withValues(alpha: 0.50),
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
    final bubbleBg = chatMode
        ? const Color(0xFFE7F4FF).withValues(alpha: 0.55)
        : const Color(0x221E90FF);
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
                color: textColor.withValues(alpha: 0.20),
                width: 0.6,
              ),
            ),
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: textColor.withValues(alpha: 0.70),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5), // dış zeminle aynı, çerçeve hissi yumuşak
        border: Border(
          top: BorderSide(color: Color(0x14000000), width: 0.6),
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
              style: GoogleFonts.poppins(color: textColor, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'QuAlsar\'a sor…'.tr(),
                hintStyle: GoogleFonts.poppins(
                    color: textColor.withValues(alpha: 0.45),
                    fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                      color: Color(0x14000000), width: 0.6),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                      color: Color(0x14000000), width: 0.6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: _kBlue1, width: 0.8),
                ),
              ),
              onSubmitted: (_) => _sendTypedMessage(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendTypedMessage,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_kBlue1, _kBlue2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              // 14:00 yönüne çevir: send ikon doğal sağ (3 yönü) → -30° CCW
              child: Transform.rotate(
                angle: -math.pi / 6,
                child: const Icon(Icons.send_rounded,
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

    // Sohbet modunda: SİYAH BAR YOK, 3 buton bağımsız dairesel.
    if (chatMode) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          8,
          18,
          10 + MediaQuery.of(context).padding.bottom * 0.4,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _BottomCircleButton(
              icon: Icons.videocam_outlined,
              onTap: () async {
                setState(() => _chatPanelOpen = false);
                FocusScope.of(context).unfocus();
                await _toggleCamera();
                if (_camActive && !_listening && !_thinking && !_paused) {
                  await _startListening();
                }
              },
              lightMode: true,
            ),
            _BottomMicButton(
              listening: _listening,
              pulse: _pulse,
              voiceLevel: _voiceLevel,
              lightMode: true,
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
            ),
          ],
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
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
              await _toggleCamera();
              if (_camActive && !_listening && !_thinking && !_paused) {
                await _startListening();
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
//  Background isolate: TTS metni stripleme — ana thread'i bloklamasın.
// ═════════════════════════════════════════════════════════════════════════
String _stripForTtsCompute(String s) {
  return s
      .replaceAll(RegExp(r'\\\([\s\S]*?\\\)'), '')
      .replaceAll(RegExp(r'\\\[[\s\S]*?\\\]'), '')
      .replaceAll(RegExp(r'\*\*'), '')
      .replaceAll(
          RegExp(r'[🔵🟢🟡🟣🔴🟠⚪🔑🧠🧪⚡💡🎓📦🔍📐📅🧬⚖️🎯🌍📖📚⭐📌]'), '')
      .replaceAll(RegExp(r'\|[-:\s|]+\|'), '')
      .replaceAll('|', ' ');
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

    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, h),
        [
          Colors.transparent,
          _kBlue1.withValues(alpha: compact ? 0.18 : 0.20),
          _kBlue2.withValues(alpha: compact ? 0.45 : 0.55),
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
            _kBlue1.withValues(alpha: compact ? 0.28 : 0.18),
            _kBlue2.withValues(alpha: compact ? 0.85 : 0.65),
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
            _kBlue2.withValues(alpha: 0.55),
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
      bg = const Color(0xFFF5F5F5);
      fg = Colors.black87;
    } else if (highlight) {
      bg = Colors.white;
      fg = Colors.black;
    } else if (frosted) {
      bg = const Color(0x33FFFFFF);
      fg = Colors.white;
    } else {
      bg = _kBtnBg;
      fg = const Color(0xEAFFFFFF);
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
                  ? const Color(0x14000000)
                  : frosted
                      ? const Color(0x40FFFFFF)
                      : const Color(0x0FFFFFFF),
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
                  bg = const Color(0xFFF5F5F5);
                  fg = Colors.black87;
                } else if (frosted) {
                  bg = const Color(0x33FFFFFF);
                  fg = Colors.white;
                } else {
                  bg = _kBtnBg;
                  fg = const Color(0xEAFFFFFF);
                }
                final core = Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bg,
                    border: Border.all(
                      color: lightMode
                          ? const Color(0x14000000)
                          : frosted
                              ? const Color(0x40FFFFFF)
                              : const Color(0x0FFFFFFF),
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
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
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
