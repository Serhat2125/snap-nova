import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  QuAlsarLogoMark — Marka işareti.
//  Matematik + kimya + fizik sembolleri ile 5 dilde (EN, ZH, HI, JA, AR)
//  tanınmış harfler aynı havuzda akar. Soru hazırlanırken kullanılan loader
//  ile aynı görsel dili paylaşır.
// ═══════════════════════════════════════════════════════════════════════════════

class QuAlsarLogoMark extends StatefulWidget {
  final double size;
  /// Merkezdeki dönen ders adı (Matematik → 数学 → ...) gösterilsin mi?
  /// false ise sadece 3 halka + etrafındaki formül/sembol akışı görünür.
  final bool showCenterWord;
  const QuAlsarLogoMark({
    super.key,
    this.size = 200,
    this.showCenterWord = true,
  });

  @override
  State<QuAlsarLogoMark> createState() => _QuAlsarLogoMarkState();
}

class _QuAlsarLogoMarkState extends State<QuAlsarLogoMark>
    with TickerProviderStateMixin {
  late final AnimationController _orbit1;
  late final AnimationController _orbit2;
  late final AnimationController _orbit3;
  late final AnimationController _ticker;

  final List<_StreamSymbol> _symbols = [];
  final math.Random _rng = math.Random();
  Timer? _spawnTimer;
  int _centerIdx = 0;
  Timer? _centerTimer;

  // Orbit renkleri — iç 2 halka her tam dönüşte sıradaki renge geçer.
  // Dış halka sabit kırmızı, renk değişimi yok.
  int _color2Idx = 2;
  int _color3Idx = 4;
  double _prev2 = 0, _prev3 = 0;

  @override
  void initState() {
    super.initState();
    _orbit1 = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _orbit2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..addListener(_onOrbit2Tick)
      ..repeat();
    _orbit3 = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_onOrbit3Tick)
      ..repeat();
    _ticker = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();

    // Sembol akışı — setState yok; AnimatedBuilder(_ticker) her karede
    // yeniden çizdiği için mutasyon yeterli (kare atlama önler).
    _spawnTimer = Timer.periodic(const Duration(milliseconds: 220), (_) {
      if (!mounted) return;
      _spawnSymbol();
    });

    // Merkez kelime akışı — sadece showCenterWord=true ise çalışır.
    if (widget.showCenterWord) {
      _centerTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
        if (!mounted) return;
        setState(() {
          _centerIdx = (_centerIdx + 1) % _centerSymbols.length;
        });
      });
    }
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _centerTimer?.cancel();
    _orbit1.dispose();
    _orbit2.dispose();
    _orbit3.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _onOrbit2Tick() {
    if (_orbit2.value < _prev2) {
      setState(() => _color2Idx = (_color2Idx + 1) % _orbitPalette.length);
    }
    _prev2 = _orbit2.value;
  }

  void _onOrbit3Tick() {
    if (_orbit3.value < _prev3) {
      setState(() => _color3Idx = (_color3Idx + 1) % _orbitPalette.length);
    }
    _prev3 = _orbit3.value;
  }

  void _spawnSymbol() {
    final char = _streamChars[_rng.nextInt(_streamChars.length)];
    final color = _streamColors[_rng.nextInt(_streamColors.length)];
    final angle = _rng.nextDouble() * math.pi * 2;
    final distance = widget.size * 0.44 + _rng.nextDouble() * widget.size * 0.12;
    final fromX = math.cos(angle) * distance;
    final fromY = math.sin(angle) * distance;
    final isLong = char.length > 3;
    final scaleRef = widget.size / 200.0;
    final size = isLong
        ? (11 + _rng.nextDouble() * 5) * scaleRef
        : (14 + _rng.nextDouble() * 12) * scaleRef;

    // setState yok — AnimatedBuilder(_ticker) zaten her karede yeniden
    // çiziyor; liste mutasyonu bir sonraki karede görünür.
    _symbols.add(_StreamSymbol(
      text: char,
      color: color,
      fromX: fromX,
      fromY: fromY,
      size: size,
      birthMs: DateTime.now().millisecondsSinceEpoch,
    ));
    final now = DateTime.now().millisecondsSinceEpoch;
    _symbols.removeWhere((s) => now - s.birthMs > 2100);
  }

  @override
  Widget build(BuildContext context) {
    final disc = widget.size;
    final mid = disc / 2;
    return Container(
      width: disc,
      height: disc,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0E0E10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
            blurRadius: 34,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        children: [
          // Akan semboller
          AnimatedBuilder(
            animation: _ticker,
            builder: (_, __) {
              final now = DateTime.now().millisecondsSinceEpoch;
              return SizedBox(
                width: disc,
                height: disc,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: _symbols.map((s) {
                    final life = ((now - s.birthMs) / 2000).clamp(0.0, 1.0);
                    final st = _symbolState(life);
                    final offsetX = s.fromX * st.posMul;
                    final offsetY = s.fromY * st.posMul;
                    return Positioned(
                      left: mid + offsetX - 10,
                      top: mid + offsetY - 10,
                      child: Transform.scale(
                        scale: st.scale,
                        child: Opacity(
                          opacity: st.opacity,
                          child: Text(
                            s.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: s.color,
                              fontSize: s.size,
                              fontWeight: FontWeight.bold,
                              // Sistem yazı tipi — CJK/Devanagari/Arabic için
                              // cihazın fallback fontu devreye girsin.
                              shadows: [
                                Shadow(color: s.color, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          // Orbit 1 — dış halka (sabit kırmızı).
          RotationTransition(
            turns: _orbit1,
            child: _OrbitRing(
              size: disc,
              color: const Color(0xFFE11D2E),
              sides: const [_Side.top, _Side.right],
              dotAlign: Alignment.topCenter,
            ),
          ),
          // Orbit 2 — orta halka (ters yön)
          RotationTransition(
            turns: ReverseAnimation(_orbit2),
            child: _OrbitRing(
              size: disc * 0.72,
              color: _orbitPalette[_color2Idx],
              sides: const [_Side.top, _Side.left],
              dotAlign: Alignment.centerRight,
            ),
          ),
          // Orbit 3 — iç halka
          RotationTransition(
            turns: _orbit3,
            child: _OrbitRing(
              size: disc * 0.44,
              color: _orbitPalette[_color3Idx],
              sides: const [_Side.top, _Side.bottom],
              dotAlign: Alignment.bottomCenter,
            ),
          ),
          // Merkez kelime — 10 dilde ders adları (opsiyonel)
          if (widget.showCenterWord)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween(begin: 0.85, end: 1.0).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOut),
                  ),
                  child: child,
                ),
              ),
              child: SizedBox(
                key: ValueKey(_centerIdx),
                width: disc * 0.70,
                height: disc * 0.34,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _centerSymbols[_centerIdx],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: disc * 0.15,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF00FFFF),
                          letterSpacing: -0.2,
                          shadows: const [
                            Shadow(color: Color(0xFF00FFFF), blurRadius: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  _SymbolState _symbolState(double life) {
    if (life < 0.2) {
      final t = life / 0.2;
      return _SymbolState(
        opacity: _lerp(0.0, 1.0, t),
        scale: _lerp(0.3, 0.8, t),
        posMul: _lerp(1.0, 0.7, t),
      );
    } else if (life < 0.8) {
      final t = (life - 0.2) / 0.6;
      return _SymbolState(
        opacity: 1.0,
        scale: _lerp(0.8, 1.0, t),
        posMul: _lerp(0.7, 0.15, t),
      );
    } else {
      final t = (life - 0.8) / 0.2;
      return _SymbolState(
        opacity: _lerp(1.0, 0.0, t),
        scale: _lerp(1.0, 0.3, t),
        posMul: _lerp(0.15, 0.0, t),
      );
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _StreamSymbol {
  final String text;
  final Color color;
  final double fromX, fromY, size;
  final int birthMs;
  _StreamSymbol({
    required this.text,
    required this.color,
    required this.fromX,
    required this.fromY,
    required this.size,
    required this.birthMs,
  });
}

class _SymbolState {
  final double opacity, scale, posMul;
  _SymbolState({
    required this.opacity,
    required this.scale,
    required this.posMul,
  });
}

enum _Side { top, right, bottom, left }

class _OrbitRing extends StatelessWidget {
  final double size;
  final Color color;
  final List<_Side> sides;
  final Alignment dotAlign;
  const _OrbitRing({
    required this.size,
    required this.color,
    required this.sides,
    required this.dotAlign,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _ArcPainter(color: color, sides: sides),
          ),
          Align(
            alignment: dotAlign,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color, blurRadius: 15),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final Color color;
  final List<_Side> sides;
  _ArcPainter({required this.color, required this.sides});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    for (final s in sides) {
      final start = switch (s) {
        _Side.top => -math.pi * 3 / 4,
        _Side.right => -math.pi / 4,
        _Side.bottom => math.pi / 4,
        _Side.left => math.pi * 3 / 4,
      };
      canvas.drawArc(rect, start, math.pi / 2, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.sides != sides;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Sembol havuzları — stream çevrede sembol/formül, merkez ders adları 10 dilde
// ═══════════════════════════════════════════════════════════════════════════

// Çevrede akan — yalnızca matematik/fizik/kimya sembol ve formülleri.
// Kelimeler merkeze taşındı — iç içe geçmesin.
const List<String> _streamChars = [
  // ─── Matematik ───
  '0', '1', '2', '3', '7', '9',
  'π', '∑', '∫', '√', '∞', 'Δ', '∂', '±', '≈', '≠',
  'x²', 'y³', 'eˣ', 'θ', 'λ', 'ω', 'φ', 'α', 'β',
  'f(x)', 'dy/dx', 'log', 'sin', 'cos', 'tan',
  'ℝ', 'ℤ', 'ℕ', 'ℚ',
  // ─── Fizik ───
  'E=mc²', 'F=ma', 'PV=nRT', 'U=IR',
  'c', 'ℏ', 'ν', 'γ', 'v⃗', 'p⃗', 'a⃗',
  'kg', 'm/s', 'Hz', 'J', 'W', 'V', 'Ω',
  'ΔE', 'ΔS', 'Ψ', 'Φ',
  // ─── Kimya ───
  'Fe', 'Au', 'Cu', 'Na',
  'H₂O', 'CO₂', 'O₂', 'NaCl', 'NH₃', 'CH₄', 'HCl',
  'pH', '→', '⇌', 'H⁺', 'OH⁻',
];

const List<Color> _streamColors = [
  Color(0xFF00FFFF),
  Color(0xFFFF00FF),
  Color(0xFFFFFF00),
  Color(0xFF00FF64),
  Color(0xFFFF3366),
  Color(0xFFFF9500),
];

// Her tam dönüşte orbit halkalarının geçeceği renk döngüsü.
const List<Color> _orbitPalette = [
  Color(0xFFFF3366), // kırmızı
  Color(0xFF00FFFF), // cyan
  Color(0xFFFF00FF), // magenta
  Color(0xFFFFFF00), // sarı
  Color(0xFF00FF64), // yeşil
  Color(0xFFFF9500), // turuncu
  Color(0xFF7C4DFF), // mor
];

// Merkezde akış — 6 ders × 10 dil. Her ders 10 dilde peş peşe gösterilir;
// ardından bir sonraki derse geçilir. Sıralı, sabit ritim.
// Diller: TR, ZH (Çince), HI (Hintçe), ES, FR, AR, BN (Bengalce), PT, RU, UR.
const List<String> _centerSymbols = [
  // ─── Matematik ───
  'Matematik',   // tr
  '数学',         // zh
  'गणित',        // hi
  'Matemáticas', // es
  'Maths',       // fr
  'رياضيات',    // ar
  'গণিত',        // bn
  'Matemática',  // pt
  'Математика',  // ru
  'ریاضی',       // ur

  // ─── Fizik ───
  'Fizik',
  '物理',
  'भौतिकी',
  'Física',
  'Physique',
  'فيزياء',
  'পদার্থ',
  'Física',
  'Физика',
  'فزکس',

  // ─── Kimya ───
  'Kimya',
  '化学',
  'रसायन',
  'Química',
  'Chimie',
  'كيمياء',
  'রসায়ন',
  'Química',
  'Химия',
  'کیمیا',

  // ─── Tarih ───
  'Tarih',
  '历史',
  'इतिहास',
  'Historia',
  'Histoire',
  'تاريخ',
  'ইতিহাস',
  'História',
  'История',
  'تاریخ',

  // ─── Coğrafya ───
  'Coğrafya',
  '地理',
  'भूगोल',
  'Geografía',
  'Géographie',
  'جغرافيا',
  'ভূগোল',
  'Geografia',
  'География',
  'جغرافیہ',

  // ─── Felsefe ───
  'Felsefe',
  '哲学',
  'दर्शन',
  'Filosofía',
  'Philosophie',
  'فلسفة',
  'দর্শন',
  'Filosofia',
  'Философия',
  'فلسفہ',
];
