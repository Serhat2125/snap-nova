import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  QuAlsarNumericLoader — Sayısal (Matematik / Fizik / Kimya) soru yükleme
//  animasyonu. HTML referansından birebir Flutter'a port edilmiştir.
//
//  Kullanım:
//    if (_isLoading) const Positioned.fill(child: QuAlsarNumericLoader()),
// ═══════════════════════════════════════════════════════════════════════════════

class QuAlsarNumericLoader extends StatefulWidget {
  const QuAlsarNumericLoader({super.key});

  @override
  State<QuAlsarNumericLoader> createState() => _QuAlsarNumericLoaderState();
}

class _QuAlsarNumericLoaderState extends State<QuAlsarNumericLoader>
    with TickerProviderStateMixin {
  // Orbital halkalar
  late final AnimationController _orbit1; // 2 sn, saat yönü
  late final AnimationController _orbit2; // 1.5 sn, ters yön
  late final AnimationController _orbit3; // 1 sn, saat yönü
  late final AnimationController _glowCtrl; // logo glow

  // Tek master ticker — tüm sembollerin frame güncellemesi
  late final AnimationController _ticker;

  // Sembol akışı
  final List<_StreamSymbol> _symbols = [];
  final math.Random _rng = math.Random();
  Timer? _spawnTimer;

  // Merkez sembol
  int _centerIdx = 0;
  Timer? _centerTimer;

  // Alt yazı — 2 aşamalı basit akış: ilk 3 sn "Analiz", sonrası "Çözüm"
  bool _solving = false;
  Timer? _stageTimer;

  // Noktalar
  int _dots = 0;
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();
    _orbit1 = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _orbit2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    _orbit3 = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _ticker = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat();

    // Sembol doğum (80 ms aralık)
    _spawnTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      _spawnSymbol();
    });

    // Merkez sembol (180 ms aralık)
    _centerTimer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!mounted) return;
      setState(() {
        _centerIdx = (_centerIdx + 1) % _centerSymbols.length;
      });
    });

    // 3 sn sonra "Sorunuz Çözülüyor"a geç
    _stageTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _solving = true);
    });

    // Nokta animasyonu (300 ms aralık)
    _dotTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        _dots = (_dots + 1) % 4;
      });
    });
  }

  @override
  void dispose() {
    _spawnTimer?.cancel();
    _centerTimer?.cancel();
    _stageTimer?.cancel();
    _dotTimer?.cancel();
    _orbit1.dispose();
    _orbit2.dispose();
    _orbit3.dispose();
    _glowCtrl.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _spawnSymbol() {
    final char = _streamChars[_rng.nextInt(_streamChars.length)];
    final color = _streamColors[_rng.nextInt(_streamColors.length)];
    final angle = _rng.nextDouble() * math.pi * 2;
    final distance = 70 + _rng.nextDouble() * 20;
    final fromX = math.cos(angle) * distance;
    final fromY = math.sin(angle) * distance;
    final isLong = char.length > 3;
    final size = isLong
        ? (10 + _rng.nextDouble() * 4)
        : (14 + _rng.nextDouble() * 12);

    setState(() {
      _symbols.add(_StreamSymbol(
        text: char,
        color: color,
        fromX: fromX,
        fromY: fromY,
        size: size,
        birthMs: DateTime.now().millisecondsSinceEpoch,
      ));
      // Eski sembolleri temizle (2 sn ömür)
      final now = DateTime.now().millisecondsSinceEpoch;
      _symbols.removeWhere((s) => now - s.birthMs > 2100);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Color(0xFF1A0033), Color(0xFF000011)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // QuAlsar logo
              _buildLogo(),
              const SizedBox(height: 20),
              // Mini loader
              _buildLoader(),
              const SizedBox(height: 15),
              // Aşama metni
              _buildStageText(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Logo ────────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, __) {
        final t = _glowCtrl.value; // 0..1
        final whiteGlow = 15.0 + 10.0 * t;
        final redGlow = 30.0 + 20.0 * t;
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Qu',
                style: _logoStyle(Colors.white, [
                  Shadow(
                      color: Colors.white.withValues(alpha: 0.5 + 0.3 * t),
                      blurRadius: whiteGlow),
                  const Shadow(
                      color: Colors.black54,
                      offset: Offset(0, 2),
                      blurRadius: 6),
                ]),
              ),
              TextSpan(
                text: 'Al',
                style: _logoStyle(const Color(0xFFFF3333), [
                  const Shadow(color: Color(0xFFFF3333), blurRadius: 15),
                  Shadow(color: const Color(0xFFFF0000), blurRadius: redGlow),
                  if (t > 0.3)
                    Shadow(
                        color: const Color(0xFFFF0000),
                        blurRadius: redGlow * 1.4),
                ]),
              ),
              TextSpan(
                text: 'sar',
                style: _logoStyle(Colors.white, [
                  Shadow(
                      color: Colors.white.withValues(alpha: 0.5 + 0.3 * t),
                      blurRadius: whiteGlow),
                  const Shadow(
                      color: Colors.black54,
                      offset: Offset(0, 2),
                      blurRadius: 6),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  TextStyle _logoStyle(Color color, List<Shadow> shadows) => TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        letterSpacing: 3,
        color: color,
        fontFamily: 'Impact',
        shadows: shadows,
      );

  // ── Loader ──────────────────────────────────────────────────────────────────
  Widget _buildLoader() {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 30),
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
                width: 160,
                height: 160,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: _symbols.map((s) {
                    final life = ((now - s.birthMs) / 2000).clamp(0.0, 1.0);
                    final st = _symbolState(life);
                    final offsetX = s.fromX * st.posMul;
                    final offsetY = s.fromY * st.posMul;
                    return Positioned(
                      left: 80 + offsetX - 10,
                      top: 80 + offsetY - 10,
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
                              fontFamily: 'Cambria Math',
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
          // Orbit 1 — 160, kırmızı/pembe, saat yönü
          RotationTransition(
            turns: _orbit1,
            child: _OrbitRing(
              size: 160,
              color: const Color(0xFFFF3366),
              sides: const [_Side.top, _Side.right],
              dotAlign: Alignment.topCenter,
            ),
          ),
          // Orbit 2 — 115, cyan, ters yön
          RotationTransition(
            turns: ReverseAnimation(_orbit2),
            child: _OrbitRing(
              size: 115,
              color: const Color(0xFF00FFFF),
              sides: const [_Side.top, _Side.left],
              dotAlign: Alignment.centerRight,
            ),
          ),
          // Orbit 3 — 70, magenta, saat yönü
          RotationTransition(
            turns: _orbit3,
            child: _OrbitRing(
              size: 70,
              color: const Color(0xFFFF00FF),
              sides: const [_Side.top, _Side.bottom],
              dotAlign: Alignment.bottomCenter,
            ),
          ),
          // Merkez sembol
          _buildCenterSymbol(),
        ],
      ),
    );
  }

  Widget _buildCenterSymbol() {
    final sym = _centerSymbols[_centerIdx];
    final isLong = sym.length > 3;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      child: SizedBox(
        key: ValueKey(_centerIdx),
        width: 50,
        height: 50,
        child: Center(
          child: Text(
            sym,
            style: TextStyle(
              fontSize: isLong ? 16 : 28,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF00FFFF),
              shadows: const [
                Shadow(color: Color(0xFF00FFFF), blurRadius: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Aşama metni (iki aşama: Analiz → Çözüm) ────────────────────────────────
  Widget _buildStageText() {
    final dotStr = '.' * _dots;
    final label =
        _solving ? 'Sorunuz Çözülüyor' : 'Sorunuz Analiz Ediliyor';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: Text(
        '$label$dotStr',
        key: ValueKey(_solving),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(
              color: Colors.white.withValues(alpha: 0.4),
              blurRadius: 10,
            ),
          ],
        ),
      ),
    );
  }

  // ── Sembol yaşam eğrisi (CSS streamFlow birebir) ────────────────────────────
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

// ── Sembol modeli ─────────────────────────────────────────────────────────────
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

// ── Orbit çizimi — partial border (2 kenar renkli, diğer 2 şeffaf) ──────────
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
          // Halka (arc)
          CustomPaint(
            size: Size(size, size),
            painter: _ArcPainter(color: color, sides: sides),
          ),
          // Parlak nokta
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
    // Her kenar için ilgili çeyreği çiz (90° arc)
    for (final s in sides) {
      final start = switch (s) {
        _Side.top => -math.pi * 3 / 4, // -135°
        _Side.right => -math.pi / 4, // -45°
        _Side.bottom => math.pi / 4, // 45°
        _Side.left => math.pi * 3 / 4, // 135°
      };
      canvas.drawArc(rect, start, math.pi / 2, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.sides != sides;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Sembol & aşama sözlükleri (HTML'den birebir)
// ═══════════════════════════════════════════════════════════════════════════════

const List<String> _streamChars = [
  // Matematik
  '0','1','2','3','4','5','6','7','8','9',
  '+','−','×','÷','=','≠','≈','±','∓','·',
  '<','>','≤','≥','≪','≫',
  '∑','∏','∫','∮','∂','∇','∆','∴','∵',
  'π','φ','θ','α','β','γ','δ','ε','λ','μ','σ','ω','ψ','χ','τ','ρ','ν','ξ','κ','ι','η','ζ','Ω','Σ','Φ','Θ','Λ','Π',
  '√','∛','∜','∞','∅','∈','∉','⊂','⊃','∪','∩','⊆','⊇','∀','∃','∄',
  'x²','y³','xⁿ','2ⁿ','eˣ','log','ln','sin','cos','tan','cot','sec','csc',
  'f(x)','g(x)','lim','∫dx','dy/dx','∂/∂x',
  'ℝ','ℤ','ℕ','ℚ','ℂ','ℙ','i','ℵ',
  '3.14','2.71','1.41','½','¼','⅓','¾','⅛',
  // Fizik
  'c','ℏ','ℎ','kB','NA','R','G','g','m₀','q',
  'kg','m','s','A','K','mol','cd','Hz','N','J','W','V','Ω','T','Pa','C','F','H',
  'E⃗','B⃗','F⃗','v⃗','a⃗','p⃗','I','U','Q','Φ',
  'λ','ν','ω','ψ','Ψ','ΔE','ΔP','ΔX','Δt','⟨ψ|',
  'E=mc²','F=ma','PV=nRT','γ','β=v/c',
  'n₁','n₂','θᵢ','ΔH','ΔS','ΔG','Cv','Cp',
  'v','a','F','p','L','τ','ω','α',
  'U=IR','P=UI','W=Fd',
  // Kimya
  'H','He','Li','Be','B','C','N','O','F','Ne',
  'Na','Mg','Al','Si','P','S','Cl','Ar','K','Ca',
  'Fe','Cu','Zn','Ag','Au','Hg','Pb','U',
  'H₂O','CO₂','O₂','N₂','NH₃','CH₄','C₆H₁₂O₆','NaCl','HCl','H₂SO₄',
  'HNO₃','NaOH','CaCO₃','C₂H₅OH','CO',
  'H⁺','OH⁻','Na⁺','Cl⁻','Ca²⁺','Fe³⁺','SO₄²⁻','NO₃⁻','CO₃²⁻','NH₄⁺',
  '→','⇌','↑','↓','Δ','⇋',
  'pH','pKa','[H⁺]','mol/L','M','g/mol',
  'R-OH','R-COOH','R-NH₂','C=C','C≡C','C₆H₆',
  'ΔH°','ΔG°','Kc','Kp','Ksp',
];

const List<Color> _streamColors = [
  Color(0xFF00FFFF),
  Color(0xFFFF00FF),
  Color(0xFFFFFF00),
  Color(0xFF00FF64),
  Color(0xFFFF3366),
  Color(0xFFFF9500),
];

const List<String> _centerSymbols = [
  '∑','π','√','∫','∞','Δ','∂','±',
  'ℏ','λ','ω','Ψ','E','c','γ','Φ',
  'H₂O','CO₂','pH','NaCl','O₂','Fe','→','⇌',
];

