import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/error_logger.dart';
import '../services/runtime_translator.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/capture_button.dart';
import '../widgets/scan_frame_overlay.dart';
import '../widgets/bottom_nav_bar.dart';
import 'solution_screen.dart';
import 'live_analysis_screen.dart';
import 'academic_planner.dart';
import 'calculator_screen.dart';
import 'profile_screen.dart';
import 'qualsar_arena_screen.dart' show arenaRouteObserver;

// ═══════════════════════════════════════════════════════════════════════════════
//  CameraScreen
// ═══════════════════════════════════════════════════════════════════════════════

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, RouteAware {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing   = false;
  bool _isFlashOn     = false;
  bool _isMultiCapture = false;
  int  _navIndex      = 1;
  String? _errorMsg;

  // Ortam ışığı algılama — GÖREV DÖNGÜLÜ örnekleme (ısınma düzeltmesi):
  // 4 sn'de bir stream kısaca açılır, İLK kare ile parlaklık ölçülür ve
  // hemen kapatılır. Eskiden stream SÜREKLİ açıktı → plugin saniyede ~30
  // YUV karesi kopyalayıp Dart'a taşıyordu (1'ini kullansak bile) →
  // kesintisiz CPU yükü telefonun ısınmasının ana nedenlerindendi.
  bool _isLowLight     = false;
  bool _lightStreaming = false;
  bool _lightDisabled  = false; // cihaz stream'i desteklemiyorsa kapat
  Timer? _lightTimer;

  // Dinamik çerçeve rect — ScanFrameOverlay'den beslenir
  final ValueNotifier<Rect> _frameNotifier = ValueNotifier(Rect.zero);

  // Pinch-to-zoom (sadece Çoklu modda)
  double _currentZoom = 1.0;
  double _baseZoom    = 1.0;
  double _minZoom     = 1.0;
  double _maxZoom     = 1.0;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rota takibi: kameranın üstüne sayfa açılınca donanımı bırak
    // (ISINMA düzeltmesi — önizleme arkada çalışmaya devam ediyordu).
    final route = ModalRoute.of(context);
    if (route is PageRoute) arenaRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    arenaRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _lightTimer?.cancel();
    _controller?.dispose();
    _frameNotifier.dispose();
    super.dispose();
  }

  /// Kamerayı tamamen bırak — üstüne sayfa açıldığında ya da uygulama
  /// arka plana geçtiğinde. Önizleme hattı + ışık örnekleme durur; cihaz
  /// ısınmaz, pil yanmaz. Geri dönüşte `_initCamera` yeniden kurar.
  void _pauseCamera() {
    _lightTimer?.cancel();
    _lightTimer = null;
    // Controller'ı dispose et VE referansı temizle — yoksa bir sonraki
    // build CameraPreview'i disposed instance'a çağırır → crash.
    final old = _controller;
    _controller = null;
    _lightStreaming = false;
    if (mounted) setState(() => _isInitialized = false);
    old?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _pauseCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  // RouteAware — bu sayfanın üstüne başka sayfa açıldı / geri dönüldü.
  @override
  void didPushNext() => _pauseCamera();

  @override
  void didPopNext() {
    if (_controller == null) _initCamera();
  }

  // ── Kamera başlatma ──────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _errorMsg = 'Kamera izni gerekiyor.');
      return;
    }

    List<CameraDescription> cams = globalCameras;
    if (cams.isEmpty) {
      try { cams = await availableCameras(); globalCameras = cams; } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'camera_screen'); }
    }
    if (cams.isEmpty) {
      if (mounted) setState(() => _errorMsg = localeService.tr('camera_not_found'));
      return;
    }

    final camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    // imageFormatGroup verme — varsayılan platform formatı (Android: yuv420,
    // iOS: bgra8888) preview stream'i için gerekli. takePicture() zaten
    // her iki platformda JPEG döner.
    //
    // KADEMELİ PRESET: bazı cihazların kamera HAL'i yüksek çözünürlükte
    // preview + still kombinasyonunu DESTEKLEMEZ ve CameraX
    // "No supported surface combination" fırlatır (ör. 1280x720
    // PRIV+JPEG reddi). high başarısızsa medium, o da olmazsa low ile
    // yeniden denenir — kamera hemen her cihazda açılır. Ham exception
    // metni ASLA ekrana basılmaz; kullanıcıya kısa Türkçe mesaj gösterilir.
    CameraController? ctrl;
    CameraException? lastErr;
    for (final preset in const [
      ResolutionPreset.high,
      ResolutionPreset.medium,
      ResolutionPreset.low,
    ]) {
      final candidate =
          CameraController(camera, preset, enableAudio: false);
      try {
        await candidate.initialize();
        ctrl = candidate;
        break;
      } on CameraException catch (e, st) {
        lastErr = e;
        ErrorLogger.instance
            .capture(e, st, context: 'camera_init_${preset.name}');
        try {
          await candidate.dispose();
        } catch (_) {/* yok say */}
      }
    }
    if (ctrl == null) {
      debugPrint('[Camera] tüm presetler başarısız: ${lastErr?.description}');
      if (mounted) {
        setState(() => _errorMsg =
            'Kamera bu cihazda başlatılamadı. Uygulamayı kapatıp açmayı dene; '
                    'sorun sürerse Galeri\'den fotoğraf seçebilirsin.'
                .tr());
      }
      return;
    }

    if (!mounted) {
      try {
        await ctrl.dispose();
      } catch (_) {/* yok say */}
      return;
    }
    _controller = ctrl;
    try {
      _minZoom = await ctrl.getMinZoomLevel();
      _maxZoom = await ctrl.getMaxZoomLevel();
      _currentZoom = _minZoom;
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'camera_screen'); }
    if (!mounted) return;
    setState(() { _isInitialized = true; _errorMsg = null; });
    _startLightStream();
  }

  // ── Ortam ışığı algılama — GÖREV DÖNGÜLÜ ─────────────────────────────────
  // 4 sn'de bir stream kısaca açılır, İLK kare ile parlaklık ölçülür
  // (Android'de Y, iOS'ta B kanalı — ikisi de parlaklıkla iyi korele) ve
  // stream hemen kapatılır. Histerezis geçişi kararlı tutar.
  static const _lightPeriod = Duration(seconds: 4);

  void _startLightStream() {
    if (_lightDisabled || _lightTimer != null) return;
    _sampleLightOnce();
    _lightTimer = Timer.periodic(_lightPeriod, (_) => _sampleLightOnce());
  }

  Future<void> _stopLightStream() async {
    _lightTimer?.cancel();
    _lightTimer = null;
    if (!_lightStreaming || _controller == null) {
      _lightStreaming = false;
      return;
    }
    try { await _controller!.stopImageStream(); } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'camera_screen'); }
    _lightStreaming = false;
  }

  Future<void> _sampleLightOnce() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (_lightStreaming || _isCapturing) return;
    try {
      _lightStreaming = true;
      await ctrl.startImageStream(_onPreviewFrame);
    } catch (_) {
      // Bazı cihazlar stream + takePicture çakışması nedeniyle başlatamaz —
      // özellik sessizce kapanır, ikon sabit kalır; timer da durdurulur.
      _lightStreaming = false;
      _lightDisabled = true;
      _lightTimer?.cancel();
      _lightTimer = null;
    }
  }

  void _onPreviewFrame(CameraImage image) {
    // Görev döngüsü: İLK kare yeter — stream hemen kapatılır, kalan kareler
    // yok sayılır (re-entrancy guard'ı _lightStreaming).
    if (!_lightStreaming) return;
    _lightStreaming = false;
    final ctrl = _controller;
    if (ctrl != null) {
      unawaited(ctrl.stopImageStream().catchError((_) {}));
    }
    if (!mounted) return;

    final bytes = image.planes.isEmpty ? null : image.planes.first.bytes;
    if (bytes == null || bytes.isEmpty) return;
    int sum = 0, cnt = 0;
    // Seyrek örnekleme — CPU yükü sıfıra yakın
    for (int i = 0; i < bytes.length; i += 256) {
      sum += bytes[i];
      cnt++;
    }
    if (cnt == 0) return;
    final avg = sum / cnt;

    // Histerezis — girişte 55'in altı, çıkışta 75 üstü (0..255)
    bool? next;
    if (!_isLowLight && avg < 55) {
      next = true;
    } else if (_isLowLight && avg > 75) {
      next = false;
    }
    if (next != null && next != _isLowLight) {
      setState(() => _isLowLight = next!);
    }
  }

  // ── Fotoğraf çek ─────────────────────────────────────────────────────────────

  Future<void> _onCapture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);

    // Bazı cihazlarda aktif image stream takePicture ile çakışıyor — durdur.
    await _stopLightStream();

    try {
      final file = await _controller!.takePicture();
      var path = file.path;

      // Tekli modda çerçeveyi kırp — AI sadece çerçeve içini görsün
      if (!_isMultiCapture && mounted) {
        final screen = MediaQuery.of(context).size;
        final frame = _frameNotifier.value.isEmpty
            ? ScanFrameOverlay.frameRect(screen)
            : _frameNotifier.value;
        final cropped = await _cropToFrame(path, screen, frame);
        if (cropped != null) path = cropped;
      }

      if (!mounted) return;
      setState(() => _isCapturing = false);

      await Navigator.push(
        context,
        _slideUp(SolutionScreen(imagePath: path, isMultiCapture: _isMultiCapture)),
      );
      // Kullanıcı geri döndü — ışık akışını yeniden başlat
      if (mounted) _startLightStream();
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _isCapturing = false);
        _showSnack(e.description ?? localeService.tr('photo_failed'));
      }
      if (mounted) _startLightStream();
    }
  }

  // ── Çerçeveye göre kırp ──────────────────────────────────────────────────
  // CameraPreview AspectRatio ile gösterilir → ekranla aspect farkı varsa
  // letterbox (üst/alt siyah) veya pillarbox olur. Kırparken gerçek preview
  // dikdörtgenini hesaplayıp ona göre normalize ediyoruz.
  Future<String?> _cropToFrame(
      String srcPath, Size screen, Rect frame) async {
    try {
      final bytes = await File(srcPath).readAsBytes();
      var im = img.decodeImage(bytes);
      if (im == null) return null;
      // EXIF rotasyonunu uygula (fiziksel olarak döndür)
      im = img.bakeOrientation(im);

      final imgW = im.width.toDouble();
      final imgH = im.height.toDouble();
      if (imgW <= 0 || imgH <= 0) return null;

      final imgAspect = imgW / imgH;
      final screenAspect = screen.width / screen.height;

      // Preview'ın ekrandaki dikdörtgeni (letterbox/pillarbox hesabı)
      double pLeft, pTop, pW, pH;
      if (imgAspect > screenAspect) {
        // Image daha geniş → üst/alt boşluk
        pW = screen.width;
        pH = pW / imgAspect;
        pLeft = 0;
        pTop = (screen.height - pH) / 2;
      } else {
        // Image daha dar → sol/sağ boşluk
        pH = screen.height;
        pW = pH * imgAspect;
        pTop = 0;
        pLeft = (screen.width - pW) / 2;
      }

      // Çerçeveyi preview'a clamp'le
      final clampedLeft = frame.left.clamp(pLeft, pLeft + pW);
      final clampedTop = frame.top.clamp(pTop, pTop + pH);
      final clampedRight = frame.right.clamp(pLeft, pLeft + pW);
      final clampedBottom = frame.bottom.clamp(pTop, pTop + pH);
      final cw = clampedRight - clampedLeft;
      final ch = clampedBottom - clampedTop;
      if (cw <= 0 || ch <= 0) return null;

      // Preview koordinatlarını 0..1 normalize et
      final xN = (clampedLeft - pLeft) / pW;
      final yN = (clampedTop - pTop) / pH;
      final wN = cw / pW;
      final hN = ch / pH;

      // Gerçek image piksellerine uygula
      final sx = (xN * imgW).round().clamp(0, im.width - 1);
      final sy = (yN * imgH).round().clamp(0, im.height - 1);
      final sw = (wN * imgW).round().clamp(1, im.width - sx);
      final sh = (hN * imgH).round().clamp(1, im.height - sy);

      final cropped = img.copyCrop(im, x: sx, y: sy, width: sw, height: sh);
      final encoded = img.encodeJpg(cropped, quality: 90);

      final dir = await getTemporaryDirectory();
      final out = File(
          '${dir.path}/snap_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(encoded);
      return out.path;
    } catch (_) {
      return null;
    }
  }

  // ── Galeri ───────────────────────────────────────────────────────────────────

  Future<void> _openGallery() async {
    // İzin istenmez: Android 13+ sistem Photo Picker'ı, eski sürümlerde
    // sistem seçici izinsiz çalışır (Play Fotoğraf/Video İzinleri Politikası).
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file != null && mounted) {
      await Navigator.push(context, _slideUp(SolutionScreen(imagePath: file.path)));
    }
  }

  // ── Flash ────────────────────────────────────────────────────────────────────

  Future<void> _toggleFlash() async {
    if (_controller == null || !_isInitialized) return;
    final next = !_isFlashOn;
    setState(() => _isFlashOn = next);
    try {
      await _controller!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'camera_screen'); }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Route<void> _slideUp(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, __) => page,
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween<Offset>(begin: Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: Duration(milliseconds: 380),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onScaleStart:  (d) { _baseZoom = _currentZoom; },
            onScaleUpdate: (d) {
              if (!_isMultiCapture || d.pointerCount < 2) return;
              final z = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
              _controller?.setZoomLevel(z);
              _currentZoom = z;
            },
            child: _buildPreview(),
          ),
          if (!_isMultiCapture)
            Positioned.fill(
              child: ScanFrameOverlay(frameNotifier: _frameNotifier),
            ),
          // ── Hesap Makinesi Butonu (Sağ Üst) ─────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CalculatorScreen()),
              ),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.15),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.calculate_rounded,
                  color: AppColors.cyan,
                  size: 24,
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomPanel()),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    // Defensif: _isInitialized ile _controller arasında race condition olabilir
    // (dispose sonrası setState gecikmesi). value.isInitialized kontrolü
    // disposed/uninitalized durumda CameraPreview'i çağırmamamızı garanti eder.
    final c = _controller;
    if (_isInitialized && c != null && c.value.isInitialized) {
      return CameraPreview(c);
    }
    return ColoredBox(
      color: AppPalette.textPrimary(context),
      child: Center(
        child: _errorMsg != null
            ? _ErrorView(message: _errorMsg!, onRetry: _initCamera)
            : CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2),
      ),
    );
  }

  // ── Alt panel ────────────────────────────────────────────────────────────────

  Widget _buildBottomPanel() {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Kontroller — kamera üzerinde şeffaf ────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: _buildCaptureTabBar()),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _BottomIconBtn(
                      icon: Icons.photo_library_rounded,
                      label: localeService.tr('gallery'),
                      color: Color(0xFF22C55E),
                      onTap: _openGallery,
                    ),
                    SizedBox(width: 28),
                    CaptureButton(onPressed: _onCapture, isCapturing: _isCapturing),
                    SizedBox(width: 28),
                    _BottomIconBtn(
                      icon: _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      label: _isFlashOn ? localeService.tr('flash_on') : 'Flash',
                      color: _isFlashOn
                          ? Colors.amber
                          : (_isLowLight ? Colors.amber : Colors.white70),
                      onTap: _toggleFlash,
                      pulse: !_isFlashOn && _isLowLight,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Nav bar — pill dışı açık temada soluk beyaz ────────────────
          Container(
            color: AppPalette.isDark(context)
                ? AppPalette.bg(context)
                : const Color(0xFFF6F7FA),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: CameraBottomNav(
                  selectedIndex: _navIndex,
                  onItemSelected: (i) {
                    if (i == 1) return; // Tara — zaten kameradayız
                    setState(() => _navIndex = i);
                    // LiveAnalysisScreen alt sekmeler OLMADAN açılır —
                    // tam ekran Gemini-style multimodal deneyim için.
                    if (i == 0) {
                      Navigator.push(
                        context,
                        _slideUp(LiveAnalysisScreen()),
                      ).then((_) => setState(() => _navIndex = 1));
                      return;
                    }
                    Widget child;
                    switch (i) {
                      case 2: child = LibraryLanding(); break;
                      case 3: child = ProfileScreen(); break;
                      default: return;
                    }
                    Navigator.push(
                      context,
                      _slideUp(_NavShell(selectedIndex: i, child: child)),
                    ).then((_) => setState(() => _navIndex = 1));
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tekli / Çoklu sekme ───────────────────────────────────────────────────

  Widget _buildCaptureTabBar() {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _tabBtn(label: localeService.tr('multi_mode'), selected:  _isMultiCapture, onTap: () => setState(() => _isMultiCapture = true)),
          _tabBtn(label: localeService.tr('single_mode'), selected: !_isMultiCapture, onTap: () {
            // Tekli moda geçince zoom sıfırla
            if (_currentZoom != _minZoom) {
              _controller?.setZoomLevel(_minZoom);
              _currentZoom = _minZoom;
            }
            setState(() => _isMultiCapture = false);
          }),
        ],
      ),
    );
  }

  Widget _tabBtn({required String label, required bool selected, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.85) : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white.withValues(alpha: 0.50),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Alt ikon butonu ──────────────────────────────────────────────────────────

class _BottomIconBtn extends StatefulWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  final bool     pulse;

  const _BottomIconBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.pulse = false,
  });

  @override
  State<_BottomIconBtn> createState() => _BottomIconBtnState();
}

class _BottomIconBtnState extends State<_BottomIconBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkCtrl;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 700),
    );
    _syncAnim();
  }

  @override
  void didUpdateWidget(_BottomIconBtn old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse) _syncAnim();
  }

  void _syncAnim() {
    if (widget.pulse) {
      _blinkCtrl.repeat(reverse: true);
    } else {
      _blinkCtrl.stop();
      _blinkCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _blinkCtrl,
            builder: (_, __) {
              final t = Curves.easeInOut.transform(_blinkCtrl.value);
              final iconOpacity = widget.pulse ? (1.0 - 0.70 * t) : 1.0;
              final glow = widget.pulse ? (0.55 * (1 - t)) : 0.0;
              return Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.pulse
                        ? widget.color.withValues(alpha: 0.45 + 0.35 * (1 - t))
                        : AppColors.border,
                  ),
                  boxShadow: widget.pulse
                      ? [
                          BoxShadow(
                            color: widget.color.withValues(alpha: glow),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Opacity(
                  opacity: iconOpacity,
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
              );
            },
          ),
          SizedBox(height: 5),
          Text(
            widget.label,
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: 9, color: widget.color.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ─── NavShell — sekme ekranlarını alt nav ile sararlar ───────────────────────

class _NavShell extends StatelessWidget {
  final int selectedIndex;
  final Widget child;

  const _NavShell({required this.selectedIndex, required this.child});

  void _onTabSelected(BuildContext context, int i) {
    if (i == 1) {
      // Tara — kameraya dön
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    if (i == selectedIndex) return;
    // LiveAnalysisScreen alt sekmeler olmadan tam ekran açılır.
    if (i == 0) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => LiveAnalysisScreen(),
          transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
          transitionDuration: Duration(milliseconds: 180),
        ),
      );
      return;
    }
    Widget newChild;
    switch (i) {
      case 2: newChild = LibraryLanding(); break;
      case 3: newChild = ProfileScreen(); break;
      default: return;
    }
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _NavShell(selectedIndex: i, child: newChild),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        transitionDuration: Duration(milliseconds: 180),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 0, right: 0, bottom: 0,
          // Pill'in DIŞINDA kalan şerit: açık temada soluk beyaz
          // (pill'in saf beyazından bir tık kırık — kullanıcı isteği).
          child: Container(
            color: AppPalette.isDark(context)
                ? AppPalette.card(context)
                : const Color(0xFFF6F7FA),
            child: SafeArea(
              top: false,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: CameraBottomNav(
                    selectedIndex: selectedIndex,
                    onItemSelected: (i) => _onTabSelected(context, i),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Hata görünümü ────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.no_photography_outlined, color: AppColors.textMuted, size: 52),
        SizedBox(height: 12),
        Text(message, style: TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
        SizedBox(height: 20),
        TextButton(onPressed: onRetry, child: Text(localeService.tr('try_again'), style: TextStyle(color: AppColors.cyan))),
      ],
    );
  }
}
