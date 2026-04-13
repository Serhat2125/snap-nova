import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../main.dart' show localeService;

/// Çerçeve dışını blur + karartma, içini net bırakır.
/// Tekli kamera modunda kullanılır. Kenar kollarıyla yeniden boyutlandırılabilir.
class ScanFrameOverlay extends StatefulWidget {
  /// Kamera ekranının çerçeve rect'ini okuyabilmesi için notifier.
  final ValueNotifier<Rect>? frameNotifier;

  const ScanFrameOverlay({super.key, this.frameNotifier});

  /// Ekran boyutuna göre varsayılan çerçeve dikdörtgenini hesaplar.
  static Rect frameRect(Size screen) {
    final w  = screen.width * 0.92;
    final h  = w * 0.68;
    final dx = (screen.width  - w) / 2;
    final dy = (screen.height - h) / 2 - 130;
    return Rect.fromLTWH(dx, dy, w, h);
  }

  @override
  State<ScanFrameOverlay> createState() => _ScanFrameOverlayState();
}

class _ScanFrameOverlayState extends State<ScanFrameOverlay>
    with SingleTickerProviderStateMixin {
  static const double _minW = 100.0;
  static const double _minH =  80.0;

  late final AnimationController _pulse;
  late final Animation<double>   _glowAnim;

  Rect? _frame; // null → varsayılan frameRect kullan

  Rect _currentFrame(Size size) => _frame ?? ScanFrameOverlay.frameRect(size);

  void _notify(Rect r) => widget.frameNotifier?.value = r;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.60, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size  = Size(constraints.maxWidth, constraints.maxHeight);
        final frame = _currentFrame(size);

        // Notifier'ı bir sonraki frame'de güncelle
        WidgetsBinding.instance.addPostFrameCallback((_) => _notify(frame));

        return Stack(
          children: [
            // 1 — Animasyonlu çerçeve + blur
            AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, __) {
                final f = _currentFrame(size);
                return Stack(
                  children: [
                    ClipPath(
                      clipper: _DonutClipper(frame: f, radius: 28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                        child: Container(
                            color: Colors.black.withValues(alpha: 0.18)),
                      ),
                    ),
                    CustomPaint(
                      painter: _BorderPainter(
                        frameRect:     f,
                        cornerRadius:  28,
                        borderOpacity: _glowAnim.value,
                      ),
                      child: _CornerBrackets(frameRect: f, radius: 28),
                    ),
                    Positioned(
                      left: 16, right: 16,
                      top: f.top - 32,
                      child: Text(
                        localeService.tr('take_clear_photo'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            // 2 — Yeniden boyutlandırma kolları (animasyonsuz)
            _leftHandle(frame, size),
            _rightHandle(frame, size),
            _topHandle(frame, size),
            _bottomHandle(frame, size),
          ],
        );
      },
    );
  }

  // ── Kenar kolları ─────────────────────────────────────────────────────────────

  static const _tw = 48.0; // dokunma alanı genişlik
  static const _th = 42.0; // dokunma alanı yükseklik

  Widget _leftHandle(Rect frame, Size screen) => Positioned(
    left:   frame.left   - _tw / 2,
    top:    frame.center.dy - _th / 2,
    width:  _tw,
    height: _th,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final f = _currentFrame(screen);
        final newLeft = (f.left + d.delta.dx)
            .clamp(0.0, f.right - _minW);
        final nf = Rect.fromLTRB(newLeft, f.top, f.right, f.bottom);
        setState(() => _frame = nf);
        _notify(nf);
      },
      child: const _EdgeHandle(isHorizontal: true),
    ),
  );

  Widget _rightHandle(Rect frame, Size screen) => Positioned(
    left:   frame.right  - _tw / 2,
    top:    frame.center.dy - _th / 2,
    width:  _tw,
    height: _th,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final f = _currentFrame(screen);
        final newRight = (f.right + d.delta.dx)
            .clamp(f.left + _minW, screen.width);
        final nf = Rect.fromLTRB(f.left, f.top, newRight, f.bottom);
        setState(() => _frame = nf);
        _notify(nf);
      },
      child: const _EdgeHandle(isHorizontal: true),
    ),
  );

  Widget _topHandle(Rect frame, Size screen) => Positioned(
    left:   frame.center.dx - _th / 2,
    top:    frame.top    - _tw / 2,
    width:  _th,
    height: _tw,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final f = _currentFrame(screen);
        final newTop = (f.top + d.delta.dy)
            .clamp(0.0, f.bottom - _minH);
        final nf = Rect.fromLTRB(f.left, newTop, f.right, f.bottom);
        setState(() => _frame = nf);
        _notify(nf);
      },
      child: const _EdgeHandle(isHorizontal: false),
    ),
  );

  Widget _bottomHandle(Rect frame, Size screen) => Positioned(
    left:   frame.center.dx - _th / 2,
    top:    frame.bottom - _tw / 2,
    width:  _th,
    height: _tw,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final f = _currentFrame(screen);
        final newBottom = (f.bottom + d.delta.dy)
            .clamp(f.top + _minH, screen.height);
        final nf = Rect.fromLTRB(f.left, f.top, f.right, newBottom);
        setState(() => _frame = nf);
        _notify(nf);
      },
      child: const _EdgeHandle(isHorizontal: false),
    ),
  );
}

// ─── Kenar kolu görsel ────────────────────────────────────────────────────────

class _EdgeHandle extends StatelessWidget {
  final bool isHorizontal;
  const _EdgeHandle({required this.isHorizontal});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: isHorizontal
            ? const EdgeInsets.symmetric(horizontal: 3, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: AppColors.cyan.withValues(alpha: 0.70), width: 1.1),
        ),
        child: Icon(
          isHorizontal ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded,
          color: AppColors.cyan,
          size: 13,
        ),
      ),
    );
  }
}

// ─── Donut Clipper ────────────────────────────────────────────────────────────

class _DonutClipper extends CustomClipper<Path> {
  final Rect   frame;
  final double radius;
  const _DonutClipper({required this.frame, required this.radius});

  @override
  Path getClip(Size size) => Path()
    ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
    ..addRRect(RRect.fromRectAndRadius(frame, Radius.circular(radius)))
    ..fillType = PathFillType.evenOdd;

  @override
  bool shouldReclip(covariant _DonutClipper old) =>
      old.frame != frame || old.radius != radius;
}

// ─── Border Painter ───────────────────────────────────────────────────────────

class _BorderPainter extends CustomPainter {
  final Rect   frameRect;
  final double cornerRadius;
  final double borderOpacity;
  const _BorderPainter({
    required this.frameRect,
    required this.cornerRadius,
    required this.borderOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rRect = RRect.fromRectAndRadius(
        frameRect, Radius.circular(cornerRadius));
    canvas.drawRRect(rRect, Paint()
      ..color       = AppColors.cyan.withValues(alpha: borderOpacity * 0.10)
      ..strokeWidth = 8
      ..style       = PaintingStyle.stroke
      ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawRRect(rRect, Paint()
      ..color       = AppColors.cyan.withValues(alpha: borderOpacity * 0.70)
      ..strokeWidth = 1.8
      ..style       = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_BorderPainter old) =>
      old.borderOpacity != borderOpacity || old.frameRect != frameRect;
}

// ─── Corner Brackets ──────────────────────────────────────────────────────────

class _CornerBrackets extends StatelessWidget {
  final Rect   frameRect;
  final double radius;
  const _CornerBrackets({required this.frameRect, required this.radius});

  @override
  Widget build(BuildContext context) {
    // Kendi Stack'ımız içinde Positioned kullanıyoruz — parent CustomPaint
    // olduğu için Positioned'ı direkt dönemeyiz (StackParentData hatası).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: frameRect.left, top: frameRect.top,
          width: frameRect.width, height: frameRect.height,
          child: CustomPaint(
            painter: _BracketPainter(
                bracketLength: 20, bracketWidth: 2.2, radius: radius),
          ),
        ),
      ],
    );
  }
}

class _BracketPainter extends CustomPainter {
  final double bracketLength;
  final double bracketWidth;
  final double radius;
  const _BracketPainter({
    required this.bracketLength,
    required this.bracketWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color       = AppColors.cyan.withValues(alpha: 0.15)
      ..strokeWidth = bracketWidth + 3
      ..strokeCap   = StrokeCap.round
      ..style       = PaintingStyle.stroke
      ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 3);
    final solid = Paint()
      ..color       = AppColors.cyan
      ..strokeWidth = bracketWidth
      ..strokeCap   = StrokeCap.round
      ..style       = PaintingStyle.stroke;

    for (final p in _buildPaths(size)) {
      canvas.drawPath(p, glow);
      canvas.drawPath(p, solid);
    }
  }

  List<Path> _buildPaths(Size size) {
    final w = size.width;
    final h = size.height;
    final r = radius;
    final l = bracketLength;
    return [
      Path()..moveTo(0, r + l)..lineTo(0, r)
            ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
            ..lineTo(r + l, 0),
      Path()..moveTo(w - r - l, 0)..lineTo(w - r, 0)
            ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
            ..lineTo(w, r + l),
      Path()..moveTo(0, h - r - l)..lineTo(0, h - r)
            ..arcToPoint(Offset(r, h), radius: Radius.circular(r), clockwise: false)
            ..lineTo(r + l, h),
      Path()..moveTo(w - r - l, h)..lineTo(w - r, h)
            ..arcToPoint(Offset(w, h - r), radius: Radius.circular(r), clockwise: false)
            ..lineTo(w, h - r - l),
    ];
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}
