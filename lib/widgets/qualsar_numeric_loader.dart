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

/// Loader sembol varyantı. Sayısal dersler için formüller/sayılar;
/// sözel dersler için harfler/kelimeler/simgeler.
enum QuAlsarLoaderVariant { numeric, verbal }

class QuAlsarNumericLoader extends StatefulWidget {
  /// İlk 3 saniyede gösterilen birincil metin.
  /// null → varsayılan "Sorunuz Analiz Ediliyor".
  final String? primaryText;

  /// 3 sn sonra geçilen ikincil metin.
  /// null → varsayılan "Sorunuz Çözülüyor".
  /// [staticLabel] true iken yok sayılır.
  final String? secondaryText;

  /// true → tek sabit metin. Aşama değişmez, sadece [primaryText] görünür.
  /// false → 3 sn sonra [primaryText] → [secondaryText] geçişi yapılır.
  final bool staticLabel;

  /// Sembol varyantı. numeric = matematik/fizik/kimya sembolleri.
  /// verbal = harfler, kelimeler, edebiyat/tarih odaklı simgeler.
  final QuAlsarLoaderVariant variant;

  /// Birikimli aşamalar. Verildiğinde [primaryText]/[secondaryText] yok sayılır.
  /// İlk satır t=0'da; her [stageInterval] kadar sonra altına bir yenisi
  /// eklenir. Mevcut aşama yanıp sönen "..." ile, tamamlananlar yeşil ✓ ile.
  final List<String>? stages;

  /// Aşamalar arasındaki gecikme (varsayılan 3 sn).
  final Duration stageInterval;

  const QuAlsarNumericLoader({
    super.key,
    this.primaryText,
    this.secondaryText,
    this.staticLabel = false,
    this.variant = QuAlsarLoaderVariant.numeric,
    this.stages,
    this.stageInterval = const Duration(seconds: 3),
  });

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

  // Birikimli stage list — her [stageInterval] kadar sonra yeni satır eklenir.
  int _stageIdx = 0;
  Timer? _stageRevealTimer;

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
        _centerIdx = (_centerIdx + 1) % _centerPool.length;
      });
    });

    // 3 sn sonra ikincil metne geç — sadece staticLabel false ve stages
    // verilmediğinde (stages varken bu mod yok sayılır).
    if (!widget.staticLabel && widget.stages == null) {
      _stageTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _solving = true);
      });
    }

    // Stages verildiyse her interval'de bir yeni satır aç.
    if (widget.stages != null && widget.stages!.length > 1) {
      _stageRevealTimer = Timer.periodic(widget.stageInterval, (t) {
        if (!mounted) return;
        if (_stageIdx + 1 < widget.stages!.length) {
          setState(() => _stageIdx++);
        } else {
          t.cancel();
        }
      });
    }

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
    _stageRevealTimer?.cancel();
    _dotTimer?.cancel();
    _orbit1.dispose();
    _orbit2.dispose();
    _orbit3.dispose();
    _glowCtrl.dispose();
    _ticker.dispose();
    super.dispose();
  }

  List<String> get _chars => widget.variant == QuAlsarLoaderVariant.verbal
      ? _verbalStreamChars
      : _streamChars;
  List<String> get _centerPool =>
      widget.variant == QuAlsarLoaderVariant.verbal
          ? _verbalCenterSymbols
          : _centerSymbols;

  void _spawnSymbol() {
    final char = _chars[_rng.nextInt(_chars.length)];
    final color = _streamColors[_rng.nextInt(_streamColors.length)];
    final angle = _rng.nextDouble() * math.pi * 2;
    final distance = 88 + _rng.nextDouble() * 25;
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
    // Arka plan saf beyaz. Dönen disk ekranın tam ortasında, QuAlsar logosu
    // biraz daha aşağıda (önceki üst SafeArea 72 → şimdi ~%20 aşağı).
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Stack(
          children: [
            // QuAlsar logosu — ekranın üst kısmında
            Align(
              alignment: const Alignment(0, -0.85),
              child: _buildLogo(),
            ),
            // Dönen disk — merkezin biraz üstünde
            Align(
              alignment: const Alignment(0, -0.18),
              child: _buildLoader(),
            ),
            // Durum metni — spinner'ın altında
            Align(
              alignment: const Alignment(0, 0.28),
              child: _buildStageText(),
            ),
          ],
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
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Qu',
                style: _logoStyle(Colors.black, [
                  Shadow(
                      color: Colors.black.withValues(alpha: 0.15 + 0.15 * t),
                      blurRadius: whiteGlow),
                ]),
              ),
              TextSpan(
                text: 'Al',
                // "Al" net — hiç blur yok, sadece saf kırmızı
                style: _logoStyle(const Color(0xFFFF0000), const []),
              ),
              TextSpan(
                text: 'sar',
                style: _logoStyle(Colors.black, [
                  Shadow(
                      color: Colors.black.withValues(alpha: 0.15 + 0.15 * t),
                      blurRadius: whiteGlow),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  TextStyle _logoStyle(Color color, List<Shadow> shadows) => TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w900,
        letterSpacing: 3,
        color: color,
        fontFamily: 'Impact',
        shadows: shadows,
      );

  // ── Loader ──────────────────────────────────────────────────────────────────
  Widget _buildLoader() {
    const disc = 200.0; // önceki 160 → biraz daha büyük
    const mid = disc / 2;
    return Container(
      width: disc,
      height: disc,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0E0E10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 28,
              offset: const Offset(0, 8)),
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
          // Orbit 1 — disc, kırmızı/pembe, saat yönü
          RotationTransition(
            turns: _orbit1,
            child: _OrbitRing(
              size: disc,
              color: const Color(0xFFFF3366),
              sides: const [_Side.top, _Side.right],
              dotAlign: Alignment.topCenter,
            ),
          ),
          // Orbit 2 — 145, cyan, ters yön
          RotationTransition(
            turns: ReverseAnimation(_orbit2),
            child: _OrbitRing(
              size: 145,
              color: const Color(0xFF00FFFF),
              sides: const [_Side.top, _Side.left],
              dotAlign: Alignment.centerRight,
            ),
          ),
          // Orbit 3 — 88, magenta, saat yönü
          RotationTransition(
            turns: _orbit3,
            child: _OrbitRing(
              size: 88,
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
    final sym = _centerPool[_centerIdx];
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

  // ── Aşama metni — iki mod ──────────────────────────────────────────────────
  //   • stages verildi: birikimli liste, her satır 3 sn arayla altta belirir.
  //   • stages null: klasik 2-aşama (analiz → çözüm) tek satır.
  Widget _buildStageText() {
    if (widget.stages != null && widget.stages!.isNotEmpty) {
      return _buildStagesColumn();
    }
    final dotStr = '.' * _dots;
    final primary = widget.primaryText ?? 'Sorunuz Analiz Ediliyor';
    final secondary = widget.secondaryText ?? 'Sorunuz Çözülüyor';
    final label = (widget.staticLabel || !_solving) ? primary : secondary;
    const textStyle = TextStyle(
      color: Colors.black,
      fontSize: 15,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: Row(
        key: ValueKey(_solving),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: textStyle),
          SizedBox(
            width: 18,
            child: Text(
              dotStr,
              style: textStyle,
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStagesColumn() {
    final stages = widget.stages!;
    final dotStr = '.' * _dots;
    const activeStyle = TextStyle(
      color: Colors.black,
      fontSize: 14,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );
    const doneStyle = TextStyle(
      color: Colors.black54,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i <= _stageIdx && i < stages.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Row(
                key: ValueKey('stage_$i'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i < _stageIdx)
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Color(0xFF10B981),
                    )
                  else
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFC8102E),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      stages[i],
                      style: i < _stageIdx ? doneStyle : activeStyle,
                    ),
                  ),
                  if (i == _stageIdx)
                    SizedBox(
                      width: 18,
                      child: Text(
                        dotStr,
                        style: activeStyle,
                        textAlign: TextAlign.left,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
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

// ═══════════════════════════════════════════════════════════════════════════════
//  QuAlsarStaticBadge — küçük, sabit (animasyonsuz) logo rozeti.
//  "Konuyu Pekiştir" gibi başlık satırlarında dönen loader'ın durağan bir
//  özeti olarak kullanılır. Disk + 3 farklı yarıçaplı arc + merkez sembol.
// ═══════════════════════════════════════════════════════════════════════════════
class QuAlsarStaticBadge extends StatelessWidget {
  final double size;
  final QuAlsarLoaderVariant variant;
  const QuAlsarStaticBadge({
    super.key,
    this.size = 52,
    this.variant = QuAlsarLoaderVariant.numeric,
  });

  @override
  Widget build(BuildContext context) {
    final center = variant == QuAlsarLoaderVariant.verbal ? 'A' : 'Σ';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0E0E10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _StaticBadgePainter(),
        child: Center(
          child: Text(
            center,
            style: TextStyle(
              fontSize: size * 0.32,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF00FFFF),
              shadows: const [
                Shadow(color: Color(0xFF00FFFF), blurRadius: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaticBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final center = Offset(w / 2, w / 2);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..style = PaintingStyle.fill;

    // Dış halka — pembe/kırmızı, sağ üst yarısı
    const pink = Color(0xFFFF3366);
    arc.color = pink;
    final rOuter = w / 2 - 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: rOuter),
      -math.pi * 3 / 4,
      math.pi,
      false,
      arc,
    );
    dot.color = pink;
    canvas.drawCircle(Offset(center.dx, center.dy - rOuter), w * 0.055, dot);

    // Orta halka — cyan, sol üst yarısı
    const cyan = Color(0xFF00FFFF);
    arc.color = cyan;
    final rMid = w * 0.36;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: rMid),
      math.pi / 4,
      math.pi,
      false,
      arc,
    );
    dot.color = cyan;
    canvas.drawCircle(Offset(center.dx + rMid, center.dy), w * 0.05, dot);

    // İç halka — magenta, alt yarısı
    const magenta = Color(0xFFFF00FF);
    arc.color = magenta;
    final rIn = w * 0.22;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: rIn),
      -math.pi / 4,
      math.pi,
      false,
      arc,
    );
    dot.color = magenta;
    canvas.drawCircle(Offset(center.dx, center.dy + rIn), w * 0.045, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

// ═════════════════════════════════════════════════════════════════════════════
//  Sözel varyant — edebiyat, tarih, coğrafya, felsefe, yabancı dil için
//  harfler, kelimeler, noktalama, sembol ve tarihsel referanslar.
// ═════════════════════════════════════════════════════════════════════════════

const List<String> _verbalStreamChars = [
  // Türk alfabesi (büyük)
  'A','B','C','Ç','D','E','F','G','Ğ','H','I','İ','J','K','L',
  'M','N','O','Ö','P','R','S','Ş','T','U','Ü','V','Y','Z',
  // Latin alfabesi (küçük) — bol görünsün
  'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z',
  // Noktalama & tipografi
  '.', ',', ';', ':', '!', '?', '«', '»', '"', '\'', '—', '…', '¶', '§', '&',
  // Edebiyat / söylem sembolleri
  '“', '”', '‘', '’', '©', '™',
  // Sık kelimeler — Türkçe
  'Şiir','Roman','Öykü','Dram','Destan','Masal','Efsane',
  'Dize','Mısra','Kafiye','Uyak','Redif','İmge','İstiare',
  'Özne','Yüklem','Nesne','Tümleç','Fiil','İsim','Sıfat','Zamir',
  'Tarih','Savaş','Barış','Antlaşma','Devlet','İmparator','Sultan',
  'Çağ','Dönem','Devir','Asır','Yüzyıl',
  'Kıta','Ülke','Şehir','Başkent','Nehir','Dağ','Okyanus','Deniz',
  'İklim','Ekvator','Kuzey','Güney','Doğu','Batı',
  'Felsefe','Mantık','Ahlak','Varlık','Bilgi','Sanat',
  // Tarihsel yıllar
  'M.Ö.','M.S.','1453','1492','1789','1923','1945','1969',
  // İngilizce — yabancı dil
  'The','And','Of','To','In','Is','Was','Be','Have','That',
  'word','verb','noun','tense','past','future',
  // Fransızca / diğer kısa
  'Le','La','Les','Je','Tu','Il','Nous','Vous','Le Monde',
  'Der','Die','Das','Ich','Du','Wir',
  // Ünlü isimler (klasik)
  'Atatürk','Fatih','Süleyman','Mevlana','Yunus','Karacaoğlan',
  'Shakespeare','Dante','Goethe','Dostoyevski','Tolstoy','Homer',
  'Sokrates','Platon','Aristo','Kant','Nietzsche',
];

const List<String> _verbalCenterSymbols = [
  'A','B','Ç','E','İ','M','N','S','Z',
  '«','»','…','¶','§',
  'Şiir','Tarih','Roman','Kıta','Çağ','Fiil','Dize',
  'The','Le','Der','Я',
  '1453','1923','M.Ö.',
  '✍️','📜','📖','🗺️',
];

