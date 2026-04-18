import 'dart:io';
import 'package:flutter/material.dart';
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
import 'history_screen.dart';
import 'academic_planner.dart';
import 'calculator_screen.dart';
import 'profile_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CameraScreen
// ═══════════════════════════════════════════════════════════════════════════════

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing   = false;
  bool _isFlashOn     = false;
  bool _isMultiCapture = false;
  int  _navIndex      = 1;
  String? _errorMsg;

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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _frameNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
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
      try { cams = await availableCameras(); globalCameras = cams; } catch (_) {}
    }
    if (cams.isEmpty) {
      if (mounted) setState(() => _errorMsg = localeService.tr('camera_not_found'));
      return;
    }

    final camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    final ctrl = CameraController(
      camera, ResolutionPreset.high, enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await ctrl.initialize();
      if (!mounted) return;
      _controller = ctrl;
      try {
        _minZoom = await ctrl.getMinZoomLevel();
        _maxZoom = await ctrl.getMaxZoomLevel();
        _currentZoom = _minZoom;
      } catch (_) {}
      setState(() { _isInitialized = true; _errorMsg = null; });
    } on CameraException catch (e) {
      if (mounted) setState(() => _errorMsg = e.description ?? localeService.tr('camera_error'));
    }
  }

  // ── Fotoğraf çek ─────────────────────────────────────────────────────────────

  Future<void> _onCapture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);

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
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _isCapturing = false);
        _showSnack(e.description ?? localeService.tr('photo_failed'));
      }
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
    await Permission.photos.request();
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
    } catch (_) {}
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
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 380),
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
                MaterialPageRoute(builder: (_) => const CalculatorScreen()),
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
                child: const Icon(
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
    if (_isInitialized && _controller != null) return CameraPreview(_controller!);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: _errorMsg != null
            ? _ErrorView(message: _errorMsg!, onRetry: _initCamera)
            : const CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2),
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
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _BottomIconBtn(
                      icon: Icons.photo_library_rounded,
                      label: localeService.tr('gallery'),
                      color: const Color(0xFF22C55E),
                      onTap: _openGallery,
                    ),
                    const SizedBox(width: 28),
                    CaptureButton(onPressed: _onCapture, isCapturing: _isCapturing),
                    const SizedBox(width: 28),
                    _BottomIconBtn(
                      icon: _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      label: _isFlashOn ? localeService.tr('flash_on') : 'Flash',
                      color: _isFlashOn ? Colors.amber : Colors.white70,
                      onTap: _toggleFlash,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Nav bar — beyaz arka plan ──────────────────────────────────
          Container(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: CameraBottomNav(
                  selectedIndex: _navIndex,
                  onItemSelected: (i) {
                    if (i == 1) return; // Tara — zaten kameradayız
                    setState(() => _navIndex = i);
                    Widget child;
                    switch (i) {
                      case 0: child = const HistoryScreen(); break;
                      case 2: child = const LibraryLanding(); break;
                      case 3: child = const ProfileScreen(); break;
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
          duration: const Duration(milliseconds: 200),
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

class _BottomIconBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;

  const _BottomIconBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.85), fontWeight: FontWeight.w500),
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
    Widget newChild;
    switch (i) {
      case 0: newChild = const HistoryScreen(); break;
      case 2: newChild = const LibraryLanding(); break;
      case 3: newChild = const ProfileScreen(); break;
      default: return;
    }
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => _NavShell(selectedIndex: i, child: newChild),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 180),
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
          child: Container(
            color: Colors.white,
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
        const Icon(Icons.no_photography_outlined, color: AppColors.textMuted, size: 52),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextButton(onPressed: onRetry, child: Text(localeService.tr('try_again'), style: const TextStyle(color: AppColors.cyan))),
      ],
    );
  }
}
