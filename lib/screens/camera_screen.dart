import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
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
import 'homework_screen.dart';
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
      String path = file.path;

      if (!_isMultiCapture && mounted) {
        final screen = MediaQuery.of(context).size;
        path = await _cropToFrame(path, screen);
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

  // ── Kırpma ───────────────────────────────────────────────────────────────────

  Future<String> _cropToFrame(String srcPath, Size screen) async {
    ui.Image? srcImage;
    ui.Image? cropped;
    try {
      final bytes = await File(srcPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1024);
      final srcFrame = await codec.getNextFrame();
      srcImage = srcFrame.image;

      final frame = _frameNotifier.value.isEmpty
          ? ScanFrameOverlay.frameRect(screen)
          : _frameNotifier.value;
      final scaleX = srcImage.width  / screen.width;
      final scaleY = srcImage.height / screen.height;

      final srcRect = Rect.fromLTWH(
        frame.left * scaleX, frame.top * scaleY,
        frame.width * scaleX, frame.height * scaleY,
      );
      final dstRect = Rect.fromLTWH(0, 0, srcRect.width, srcRect.height);

      final recorder = ui.PictureRecorder();
      final canvas   = ui.Canvas(recorder);
      canvas.drawImageRect(srcImage, srcRect, dstRect, ui.Paint());
      final picture  = recorder.endRecording();

      srcImage.dispose();
      srcImage = null;

      cropped = await picture.toImage(
        srcRect.width.round().clamp(1, 4096),
        srcRect.height.round().clamp(1, 4096),
      );
      final bd = await cropped.toByteData(format: ui.ImageByteFormat.png);
      cropped.dispose();
      cropped = null;

      if (bd == null) return srcPath;
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/snap_${DateTime.now().millisecondsSinceEpoch}.png');
      await out.writeAsBytes(bd.buffer.asUint8List());
      return out.path;
    } catch (_) {
      return srcPath;
    } finally {
      srcImage?.dispose();
      cropped?.dispose();
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
                      label: 'Galeri',
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

          // ── Nav bar — sadece bu alan siyah ─────────────────────────────
          Container(
            color: Colors.black,
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
                      case 2: child = const HomeworkScreen(); break;
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
      case 2: newChild = const HomeworkScreen(); break;
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
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.96),
                  Colors.black.withValues(alpha: 0.80),
                  Colors.transparent,
                ],
                stops: const [0, 0.80, 1],
              ),
            ),
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
        TextButton(onPressed: onRetry, child: const Text('Tekrar Dene', style: TextStyle(color: AppColors.cyan))),
      ],
    );
  }
}
