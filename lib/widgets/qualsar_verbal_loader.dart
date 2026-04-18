import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  QuAlsarVerbalLoader — Sözel (Türkçe / Edebiyat / Tarih / Felsefe / Dil)
//  yükleme animasyonu. HTML referansından birebir Flutter'a port edilmiştir.
//
//  Tema: siyah arka plan + gri tonlu yörüngeler + dünya dillerinden harfler.
// ═══════════════════════════════════════════════════════════════════════════════

class QuAlsarVerbalLoader extends StatefulWidget {
  const QuAlsarVerbalLoader({super.key});

  @override
  State<QuAlsarVerbalLoader> createState() => _QuAlsarVerbalLoaderState();
}

class _QuAlsarVerbalLoaderState extends State<QuAlsarVerbalLoader>
    with TickerProviderStateMixin {
  late final AnimationController _orbit1;
  late final AnimationController _orbit2;
  late final AnimationController _orbit3;
  late final AnimationController _glowCtrl;
  late final AnimationController _ticker;

  final List<_StreamLetter> _letters = [];
  final math.Random _rng = math.Random();
  Timer? _spawnTimer;

  int _centerIdx = 0;
  Timer? _centerTimer;

  // 2 aşamalı basit akış: ilk 3 sn "Analiz", sonrası "Çözüm"
  bool _solving = false;
  Timer? _stageTimer;

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

    // Sözelde 75 ms doğum aralığı (sayısalda 80 ms)
    _spawnTimer = Timer.periodic(const Duration(milliseconds: 75), (_) {
      if (!mounted) return;
      _spawnLetter();
    });

    // Merkez harf 200 ms aralık
    _centerTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        _centerIdx = (_centerIdx + 1) % _centerLetters.length;
      });
    });

    _stageTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _solving = true);
    });

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

  void _spawnLetter() {
    final char = _streamChars[_rng.nextInt(_streamChars.length)];
    final color = _streamColors[_rng.nextInt(_streamColors.length)];
    final angle = _rng.nextDouble() * math.pi * 2;
    final distance = 80 + _rng.nextDouble() * 20;
    final fromX = math.cos(angle) * distance;
    final fromY = math.sin(angle) * distance;
    final size = 14 + _rng.nextDouble() * 14;
    final italic = _rng.nextBool();

    setState(() {
      _letters.add(_StreamLetter(
        text: char,
        color: color,
        fromX: fromX,
        fromY: fromY,
        size: size,
        italic: italic,
        birthMs: DateTime.now().millisecondsSinceEpoch,
      ));
      final now = DateTime.now().millisecondsSinceEpoch;
      _letters.removeWhere((s) => now - s.birthMs > 2100);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Color(0xFF0A0A0A), Color(0xFF000000)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLogo(),
              const SizedBox(height: 20),
              _buildLoader(),
              const SizedBox(height: 15),
              _buildStageText(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, __) {
        final t = _glowCtrl.value;
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

  Widget _buildLoader() {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.8), blurRadius: 30),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.hardEdge,
        children: [
          // Akan harfler
          AnimatedBuilder(
            animation: _ticker,
            builder: (_, __) {
              final now = DateTime.now().millisecondsSinceEpoch;
              return SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: _letters.map((s) {
                    final life = ((now - s.birthMs) / 2000).clamp(0.0, 1.0);
                    final st = _letterState(life);
                    final offsetX = s.fromX * st.posMul;
                    final offsetY = s.fromY * st.posMul;
                    return Positioned(
                      left: 90 + offsetX - 10,
                      top: 90 + offsetY - 10,
                      child: Transform.rotate(
                        angle: st.rotation,
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
                                fontStyle: s.italic
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                fontFamily: 'Noto Sans',
                                shadows: [
                                  Shadow(color: s.color, blurRadius: 8),
                                ],
                              ),
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
          // Orbit 1 — 180 px, açık gri
          RotationTransition(
            turns: _orbit1,
            child: _OrbitRing(
              size: 180,
              color: const Color(0xFFB8B8C8),
              sides: const [_Side.top, _Side.right],
              dotAlign: Alignment.topCenter,
            ),
          ),
          // Orbit 2 — 130 px, beyazımsı gri (ters)
          RotationTransition(
            turns: ReverseAnimation(_orbit2),
            child: _OrbitRing(
              size: 130,
              color: const Color(0xFFD0D0DC),
              sides: const [_Side.top, _Side.left],
              dotAlign: Alignment.centerRight,
            ),
          ),
          // Orbit 3 — 80 px, orta gri
          RotationTransition(
            turns: _orbit3,
            child: _OrbitRing(
              size: 80,
              color: const Color(0xFFA0A0B0),
              sides: const [_Side.top, _Side.bottom],
              dotAlign: Alignment.bottomCenter,
            ),
          ),
          _buildCenterLetter(),
        ],
      ),
    );
  }

  Widget _buildCenterLetter() {
    final letter = _centerLetters[_centerIdx];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      child: SizedBox(
        key: ValueKey(_centerIdx),
        width: 50,
        height: 50,
        child: Center(
          child: Text(
            letter,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'Noto Sans',
              shadows: [
                Shadow(color: Color(0xE6FFFFFF), blurRadius: 20),
                Shadow(color: Color(0x4DFFFFFF), blurRadius: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
                color: Colors.white.withValues(alpha: 0.4), blurRadius: 10),
          ],
        ),
      ),
    );
  }

  // Harf yaşam eğrisi — CSS letterStreamFlow birebir (rotasyon dahil)
  _LetterState _letterState(double life) {
    if (life < 0.2) {
      final t = life / 0.2;
      return _LetterState(
        opacity: _lerp(0.0, 1.0, t),
        scale: _lerp(0.3, 0.8, t),
        posMul: _lerp(1.0, 0.7, t),
        rotation: _lerp(0.0, math.pi / 2, t),
      );
    } else if (life < 0.8) {
      final t = (life - 0.2) / 0.6;
      return _LetterState(
        opacity: 1.0,
        scale: _lerp(0.8, 1.0, t),
        posMul: _lerp(0.7, 0.15, t),
        rotation: _lerp(math.pi / 2, math.pi * 1.5, t),
      );
    } else {
      final t = (life - 0.8) / 0.2;
      return _LetterState(
        opacity: _lerp(1.0, 0.0, t),
        scale: _lerp(1.0, 0.3, t),
        posMul: _lerp(0.15, 0.0, t),
        rotation: _lerp(math.pi * 1.5, math.pi * 2, t),
      );
    }
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

// ── Modeller ──────────────────────────────────────────────────────────────────
class _StreamLetter {
  final String text;
  final Color color;
  final double fromX, fromY, size;
  final bool italic;
  final int birthMs;
  _StreamLetter({
    required this.text,
    required this.color,
    required this.fromX,
    required this.fromY,
    required this.size,
    required this.italic,
    required this.birthMs,
  });
}

class _LetterState {
  final double opacity, scale, posMul, rotation;
  _LetterState({
    required this.opacity,
    required this.scale,
    required this.posMul,
    required this.rotation,
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
                boxShadow: [BoxShadow(color: color, blurRadius: 15)],
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

// ═══════════════════════════════════════════════════════════════════════════════
//  Harf havuzu — 13 dil + semboller (HTML'den birebir)
// ═══════════════════════════════════════════════════════════════════════════════

const List<String> _streamChars = [
  // Latin / Türkçe
  'A','B','C','Ç','D','E','F','G','Ğ','H','I','İ','Ö','Ş','Ü',
  'a','e','i','o','u','ç','ğ','ş','ı',
  // Çince (Hanzi)
  '爱','家','人','心','天','地','水','火','山','月','日','風','花','雪','夢','光','美','道',
  '漢','字','書','文','學','言','語','話','聞','見',
  // Japonca (Hiragana + Katakana)
  'あ','い','う','え','お','か','き','く','け','こ','さ','し','す','せ','そ',
  'た','ち','つ','て','と','な','に','ぬ','ね','の','は','ひ','ふ','へ','ほ',
  'ア','イ','ウ','エ','オ','カ','キ','ク','ケ','コ','サ','シ','ス','セ','ソ',
  // Arapça
  'ا','ب','ت','ث','ج','ح','خ','د','ذ','ر','ز','س','ش','ص','ض',
  'ط','ظ','ع','غ','ف','ق','ك','ل','م','ن','ه','و','ي',
  'سلام','حب','نور',
  // Korece (Hangul)
  '가','나','다','라','마','바','사','아','자','차','카','타','파','하',
  '한','국','말','글','사랑','빛','꿈','달',
  // Rusça (Kiril)
  'А','Б','В','Г','Д','Е','Ж','З','И','Й','К','Л','М','Н','О','П','Р','С','Т','У','Ф',
  'Х','Ц','Ч','Ш','Щ','Ъ','Ы','Ь','Э','Ю','Я',
  'мир','дом',
  // Yunanca
  'Α','Β','Γ','Δ','Ε','Ζ','Η','Θ','Ι','Κ','Λ','Μ','Ν','Ξ','Ο','Π','Ρ','Σ','Τ','Υ','Φ','Χ','Ψ','Ω',
  'α','β','γ','δ','ε','ζ','η','θ','λ','μ','ξ','π','σ','φ','ψ','ω',
  // İbranice
  'א','ב','ג','ד','ה','ו','ז','ח','ט','י','כ','ל','מ','נ','ס','ע','פ','צ','ק','ר','ש','ת',
  'שלום','אהבה',
  // Runik
  'ᚠ','ᚢ','ᚦ','ᚨ','ᚱ','ᚷ','ᚹ','ᚺ','ᚾ','ᛁ','ᛃ','ᛇ','ᛈ','ᛉ','ᛊ','ᛏ','ᛒ','ᛖ','ᛗ','ᛚ','ᛜ','ᛞ','ᛟ',
  // Mısır hiyeroglifleri
  '𓀀','𓀁','𓁐','𓂀','𓃒','𓅓','𓆣','𓇯','𓈗','𓊖','𓋹','𓏏','𓐍',
  // Tayca
  'ก','ข','ค','ง','จ','ช','ด','ต','น','บ','ป','ผ','พ','ม','ย','ร','ล','ว','ส','ห',
  // Hintçe (Devanagari)
  'अ','आ','इ','उ','ए','क','ख','ग','घ','च','ज','ट','ड','त','द','न','प','ब','म','य','र','ल','व','स','ह',
  'नमस्ते','प्रेम','शांति',
  // Ermenice
  'Ա','Բ','Գ','Դ','Ե','Զ','Է','Ը','Թ','Ժ','Ի','Լ','Խ','Ծ','Կ','Հ','Ձ','Ղ','Ճ','Մ','Յ','Ն','Շ','Ո',
  // Gürcüce
  'ა','ბ','გ','დ','ე','ვ','ზ','თ','ი','კ','ლ','მ','ნ','ო','პ','ჟ','რ','ს','ტ','უ',
  // Semboller ve noktalama
  '?','!','.',',',';',':','"','«','»','—','…','§','¶','†','‡','※','☯','☮','✦','✧','♪','♫',
];

const List<Color> _streamColors = [
  Color(0xFFFFFFFF),
  Color(0xFFE8E8F0),
  Color(0xFFC8C8D4),
  Color(0xFFB0B0BC),
  Color(0xFFD8D8E0),
  Color(0xFFA8A8B8),
  Color(0xFFF0F0F5),
];

const List<String> _centerLetters = [
  'A','Z','爱','あ','ا','한','Я','Ω','ש','अ',
  'ᚠ','𓀀','ก','Ա','ა','?','!','Ö','Ü','Ç',
  '言','の','ب','빛','λ','ב','स','道','א','φ',
];

