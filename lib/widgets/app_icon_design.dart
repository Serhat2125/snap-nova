// QuAlsar uygulama logosu — telefonun launcher'ında görünen icon.
//
// Tasarım çizgisi:
//  • Arka plan beyaz, modern flat/vector estetiği.
//  • Merkezde Quasar enerji çekirdeği — 3 ince halka (gri/kırmızı/mavi)
//    + iç küçük küre. Halkalar gap'li → dönüş hissi statik.
//  • Sol kanat: açık kitap simgesi → sözel/dil becerileri.
//  • Sağ kanat: atom simgesi (kırmızı çekirdek) → sayısal/bilim.
//    Kırmızı çekirdek "Al" harflerinin rengini tekrar ederek bütünlük kurar.
//  • Alt: "Qu**Al**sar" metni — Qu ve sar koyu gri, Al canlı kırmızı.
//
// İki varyant:
//  • full: kanatlar + alt metin dahil (iOS + dış launcher.png).
//  • centerOnly: yalnızca merkez halkalar + küre — Android adaptive icon
//    foreground'unun safe area'sına (merkez %66) sığması için.
//
// Renderer dosyası: tool/generate_app_icon.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';

enum AppIconVariant { full, centerOnly }

class AppIconDesign extends StatelessWidget {
  final AppIconVariant variant;
  final double size;

  const AppIconDesign({
    super.key,
    this.variant = AppIconVariant.full,
    this.size = 1024,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AppIconPainter(variant: variant),
      ),
    );
  }
}

class _AppIconPainter extends CustomPainter {
  final AppIconVariant variant;
  _AppIconPainter({required this.variant});

  // Palette
  static const _bgColor = Colors.white;
  static const _textDark = Color(0xFF1A1F2E);
  static const _accentRed = Color(0xFFE53935);
  static const _ringDark = Color(0xFF1A1F2E);
  static const _ringRed = Color(0xFFE53935);
  static const _ringBlue = Color(0xFF0277BD);

  @override
  void paint(Canvas c, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // ── Arka plan: temiz beyaz ─────────────────────────────────────────────
    c.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = _bgColor,
    );

    final isFull = variant == AppIconVariant.full;
    // Full varyantta merkez biraz yukarda — alt metin yer açsın diye.
    final centerY = isFull ? h * 0.40 : h * 0.50;
    final ringMax = isFull ? w * 0.20 : w * 0.34;
    final stroke = w * 0.014;

    // ── Halkalar (3 katman, gap'li → dönüş hissi) ──────────────────────────
    _drawRing(c, Offset(cx, centerY), ringMax,
        stroke: stroke,
        color: _ringDark,
        startDeg: -120,
        sweepDeg: 240);
    _drawRing(c, Offset(cx, centerY), ringMax * 0.72,
        stroke: stroke,
        color: _ringRed,
        startDeg: 60,
        sweepDeg: 240);
    _drawRing(c, Offset(cx, centerY), ringMax * 0.45,
        stroke: stroke,
        color: _ringBlue,
        startDeg: -60,
        sweepDeg: 240);

    // Halka uçlarındaki noktalar — partikül vurgu
    _drawDot(c, Offset(cx, centerY), ringMax, -120, _ringDark);
    _drawDot(c, Offset(cx, centerY), ringMax * 0.72, 60, _ringRed);
    _drawDot(c, Offset(cx, centerY), ringMax * 0.45, -60, _ringBlue);

    // ── Merkez küre (Quasar core) ──────────────────────────────────────────
    _drawCore(c, Offset(cx, centerY), ringMax * 0.18);

    // ── Yan kanatlar ve alt metin (sadece full) ────────────────────────────
    if (isFull) {
      final wingSize = w * 0.085;
      _drawBook(c, Offset(w * 0.14, centerY), wingSize);
      _drawAtom(c, Offset(w * 0.86, centerY), wingSize);

      _drawBrandText(c, cx, h * 0.78, w * 0.13);
    }
  }

  // ── Halka çizimi ────────────────────────────────────────────────────────
  void _drawRing(Canvas c, Offset center, double r,
      {required double stroke,
      required Color color,
      required double startDeg,
      required double sweepDeg}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    final rect = Rect.fromCircle(center: center, radius: r);
    final start = startDeg * math.pi / 180;
    final sweep = sweepDeg * math.pi / 180;
    c.drawArc(rect, start, sweep, false, paint);
  }

  void _drawDot(
      Canvas c, Offset center, double r, double angleDeg, Color color) {
    final ang = angleDeg * math.pi / 180;
    final pos = Offset(
      center.dx + r * math.cos(ang),
      center.dy + r * math.sin(ang),
    );
    c.drawCircle(pos, r * 0.07, Paint()..color = color);
  }

  // ── Quasar çekirdeği — gradient küre + kırmızı kor ─────────────────────
  void _drawCore(Canvas c, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sphere = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [
          Color(0xFFFFFFFF),
          _accentRed.withValues(alpha: 0.95),
          _ringDark,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    c.drawCircle(center, radius, sphere);
  }

  // ── Sol kanat: açık kitap simgesi ──────────────────────────────────────
  void _drawBook(Canvas c, Offset center, double size) {
    final stroke = size * 0.10;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = _textDark;

    final left = center.dx - size;
    final right = center.dx + size;
    final top = center.dy - size * 0.7;
    final bottom = center.dy + size * 0.7;
    final mid = center.dx;

    // Sol sayfa — yumuşak kavisli kapak
    final leftPath = Path()
      ..moveTo(left, top + size * 0.15)
      ..quadraticBezierTo(left, top, left + size * 0.25, top)
      ..lineTo(mid, top + size * 0.18)
      ..lineTo(mid, bottom)
      ..lineTo(left + size * 0.05, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - size * 0.15)
      ..close();
    c.drawPath(leftPath,
        Paint()..color = _textDark.withValues(alpha: 0.08));
    c.drawPath(leftPath, paint);

    // Sağ sayfa — simetrik
    final rightPath = Path()
      ..moveTo(right, top + size * 0.15)
      ..quadraticBezierTo(right, top, right - size * 0.25, top)
      ..lineTo(mid, top + size * 0.18)
      ..lineTo(mid, bottom)
      ..lineTo(right - size * 0.05, bottom)
      ..quadraticBezierTo(right, bottom, right, bottom - size * 0.15)
      ..close();
    c.drawPath(rightPath,
        Paint()..color = _textDark.withValues(alpha: 0.08));
    c.drawPath(rightPath, paint);

    // Sayfa çizgileri (incecik) — sadeliğe ek
    final lineP = Paint()
      ..color = _textDark.withValues(alpha: 0.45)
      ..strokeWidth = stroke * 0.45
      ..strokeCap = StrokeCap.round;
    for (int i = 1; i <= 2; i++) {
      final y = top + size * (0.35 + i * 0.18);
      c.drawLine(
          Offset(left + size * 0.18, y), Offset(mid - size * 0.10, y), lineP);
      c.drawLine(
          Offset(mid + size * 0.10, y), Offset(right - size * 0.18, y), lineP);
    }
  }

  // ── Sağ kanat: atom — 3 elips + kırmızı çekirdek ───────────────────────
  void _drawAtom(Canvas c, Offset center, double size) {
    final stroke = size * 0.075;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = _textDark;

    final rectV = Rect.fromCenter(
      center: center,
      width: size * 1.95,
      height: size * 0.75,
    );

    // 3 elliptik yörünge — 60° aralıklarla rotated
    for (int i = 0; i < 3; i++) {
      final ang = i * math.pi / 3;
      c.save();
      c.translate(center.dx, center.dy);
      c.rotate(ang);
      c.translate(-center.dx, -center.dy);
      c.drawOval(rectV, paint);
      c.restore();
    }

    // Çekirdek — kırmızı (Al harflerinin rengi: tasarım bütünlüğü)
    c.drawCircle(center, size * 0.22, Paint()..color = _accentRed);
    // İç parlama
    c.drawCircle(
      center.translate(-size * 0.06, -size * 0.06),
      size * 0.08,
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  // ── Alt marka metni: "Qu" + "Al" (kırmızı) + "sar" ─────────────────────
  void _drawBrandText(Canvas c, double cx, double y, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Qu',
            style: TextStyle(
              color: _textDark,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          TextSpan(
            text: 'Al',
            style: TextStyle(
              color: _accentRed,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          TextSpan(
            text: 'sar',
            style: TextStyle(
              color: _textDark,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    tp.layout();
    tp.paint(c, Offset(cx - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _AppIconPainter old) =>
      old.variant != variant;
}
