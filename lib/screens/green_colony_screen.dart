import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  GreenColonyScreen — Mars temalı pomodoro / odak ekranı
// ═══════════════════════════════════════════════════════════════════════════════

class GreenColonyScreen extends StatefulWidget {
  const GreenColonyScreen({super.key});

  @override
  State<GreenColonyScreen> createState() => _GreenColonyScreenState();
}

class _GreenColonyScreenState extends State<GreenColonyScreen>
    with TickerProviderStateMixin {
  static const _focus = 25 * 60;
  static const _shortBreak = 5 * 60;
  static const _longBreak = 15 * 60;
  static const _totalSessions = 4;

  int _timeLeft = _focus;
  int _totalTime = _focus;
  bool _running = false;
  Timer? _ticker;
  int _session = 1;
  String _mode = 'focus';
  int _capsules = 0;
  double _o2 = 100;

  late final List<_StarSpec> _stars;
  late final AnimationController _starCtrl;
  late final AnimationController _antennaCtrl;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _stars = List.generate(60, (_) {
      return _StarSpec(
        dx: rng.nextDouble(),
        dy: rng.nextDouble() * 0.55,
        size: rng.nextDouble() * 1.6 + 0.6,
        delay: rng.nextDouble(),
        opacity: rng.nextDouble() * 0.6 + 0.4,
      );
    });
    _starCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _antennaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WakelockPlus.disable();
    _starCtrl.dispose();
    _antennaCtrl.dispose();
    super.dispose();
  }

  String get _modeLabel {
    if (_mode == 'focus') return 'ODAK';
    if (_mode == 'break') return 'MOLA';
    return 'UZUN';
  }

  String _format(int s) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(s ~/ 60)}:${two(s % 60)}';
  }

  void _toggle() {
    if (_running) {
      _ticker?.cancel();
      WakelockPlus.disable();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    WakelockPlus.enable();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _timeLeft--;
        if (_mode == 'focus') _o2 = 100;
      });
      if (_timeLeft <= 0) _completePhase();
    });
  }

  void _completePhase() {
    _ticker?.cancel();
    WakelockPlus.disable();
    setState(() {
      _running = false;
      if (_mode == 'focus') {
        _capsules++;
        if (_session >= _totalSessions) {
          _mode = 'longBreak';
          _timeLeft = _totalTime = _longBreak;
          _session = 1;
        } else {
          _mode = 'break';
          _timeLeft = _totalTime = _shortBreak;
          _session++;
        }
      } else {
        _mode = 'focus';
        _timeLeft = _totalTime = _focus;
      }
    });
  }

  void _reset() {
    _ticker?.cancel();
    WakelockPlus.disable();
    setState(() {
      _running = false;
      _session = 1;
      _mode = 'focus';
      _timeLeft = _totalTime = _focus;
      _capsules = 0;
      _o2 = 100;
    });
  }

  void _skip() {
    _ticker?.cancel();
    setState(() => _timeLeft = 0);
    _completePhase();
  }

  double get _progress {
    if (_totalTime == 0) return 0;
    return ((_totalTime - _timeLeft) / _totalTime).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Daha yumuşak kızıl tonlar
                    colors: [
                      Color(0xFF0A0820),
                      Color(0xFF241830),
                      Color(0xFF6E4538),
                      Color(0xFFA86855),
                      Color(0xFFC78A75),
                    ],
                    stops: [0, 0.25, 0.55, 0.78, 1],
                  ),
                ),
              ),
            ),
            // Yıldızlar
            Positioned.fill(
              child: CustomPaint(
                painter: _StarPainter(_stars, _starCtrl),
              ),
            ),
            // Ay — sayacın gerisinde kalmasın diye sağa kaydırıldı
            const Align(
              alignment: Alignment(0.55, -0.85),
              child: _Moon(),
            ),
            // Dünya — daha sağa
            const Align(
              alignment: Alignment(0.92, -0.78),
              child: _Earth(),
            ),
            // Mars yüzeyi
            Positioned(
              left: 0, right: 0, bottom: 0,
              height: MediaQuery.of(context).size.height * 0.36,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomCenter,
                    radius: 1.3,
                    colors: [
                      Color(0xFFD08068),
                      Color(0xFFA85540),
                      Color(0xFF6E3825),
                      Color(0xFF3A1810),
                    ],
                    stops: [0, 0.4, 0.78, 1],
                  ),
                ),
              ),
            ),
            // Ufuk parlaması
            Positioned(
              left: 0, right: 0,
              top: MediaQuery.of(context).size.height * 0.5,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFFFF9070).withValues(alpha: 0.35),
                      const Color(0xFFFF8060).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // İçerik
            Column(
              children: [
                _buildTopBar(),
                _buildHeader(),
                const SizedBox(height: 8),
                _buildTimer(),
                Expanded(child: _buildBiopod()),
                _buildBottomPanel(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Color(0xFFA8E6CF), size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Text('⬤  MARS · SEC 7',
              style: GoogleFonts.poppins(
                color: const Color(0xFFA8E6CF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              )),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Text('THE GREEN COLONY',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF00FF9D),
              letterSpacing: 2.5,
              shadows: const [
                Shadow(color: Color(0x9900FF9D), blurRadius: 12),
              ],
            )),
        const SizedBox(height: 2),
        Text('BIOPOD CONTROL',
            style: GoogleFonts.poppins(
              fontSize: 8,
              color: const Color(0xFF8BA6B8),
              letterSpacing: 3,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }

  Widget _buildTimer() {
    final warn = _o2 < 50;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          _format(_timeLeft),
          style: GoogleFonts.robotoMono(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: warn ? const Color(0xFFFF9B9B) : const Color(0xFF00FF9D),
            letterSpacing: 3,
            shadows: [
              Shadow(
                color: warn ? const Color(0xCCFF9B9B) : const Color(0xCC00FF9D),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBiopod() {
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 0, 36, 4),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Platform
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 22,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3A4555), Color(0xFF1A2030), Color(0xFF0A1018)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6), blurRadius: 12),
              ],
            ),
          ),
          // Anten + ışık
          Positioned(
            top: 0,
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _antennaCtrl,
                  builder: (_, __) {
                    final t = _antennaCtrl.value;
                    return Container(
                      width: 9, height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(const Color(0xFF00FF9D),
                            const Color(0xFF005530), t)!,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00FF9D)
                                .withValues(alpha: (1 - t) * 0.7),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Container(
                  width: 2.5, height: 18,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF00FF9D), Color(0xFF6A7585)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Kubbe
          Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 22),
            child: _buildDome(progress),
          ),
        ],
      ),
    );
  }

  Widget _buildDome(double progress) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      return ClipPath(
        clipper: _DomeClipper(),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFADDCE6).withValues(alpha: 0.15),
                const Color(0xFF87CEEB).withValues(alpha: 0.10),
                const Color(0xFF64B4C8).withValues(alpha: 0.08),
                const Color(0xFF50A0B4).withValues(alpha: 0.18),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Toprak
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.22,
                  child: AnimatedContainer(
                    duration: const Duration(seconds: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: progress > 0.3
                            ? const [
                                Color(0xFF4A3820),
                                Color(0xFF2F2010),
                                Color(0xFF1A1008),
                              ]
                            : const [
                                Color(0xFF6A4028),
                                Color(0xFF4A2810),
                                Color(0xFF2A1808),
                              ],
                      ),
                    ),
                  ),
                ),
              ),
              // Bitkiler
              Positioned(
                left: 0, right: 0, bottom: h * 0.20,
                child: _buildPlants(progress),
              ),
              // Kapı
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 38, height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF2A3040), Color(0xFF1A2030)],
                    ),
                    border: Border.all(
                        color: const Color(0xFF4A5565), width: 1.2),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20)),
                  ),
                  alignment: const Alignment(0, -0.3),
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00FF9D).withValues(alpha: 0.25),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF9D)
                              .withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Cam parlaması
              Positioned(
                top: h * 0.05,
                left: w * 0.10,
                child: Container(
                  width: w * 0.32, height: h * 0.45,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.35),
                        Colors.white.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(140),
                  ),
                ),
              ),
              // Kubbe çerçeve çizgisi (dış outline)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _DomeOutlinePainter()),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildPlants(double progress) {
    final stages = List.generate(4, (i) {
      final start = 0.05 + i * 0.18;
      return ((progress - start) / 0.4).clamp(0.0, 1.0);
    });
    return SizedBox(
      height: 70,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) => _Plant(scale: stages[i], variant: i)),
      ),
    );
  }

  Widget _buildBottomPanel() {
    final danger = _o2 < 50;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0x66000000)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('O₂ JENERATÖRÜ',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFA8E6CF),
                    fontSize: 9,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              Text('${_o2.round()}%',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFA8E6CF),
                    fontSize: 9,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
          const SizedBox(height: 3),
          Container(
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: const Color(0xFF00FF9D).withValues(alpha: 0.10),
              border: Border.all(
                  color: const Color(0xFF00FF9D).withValues(alpha: 0.25)),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (_o2 / 100).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    colors: danger
                        ? const [Color(0xFFFF9B9B), Color(0xFFFF7A8A)]
                        : const [Color(0xFF00FF9D), Color(0xFF00D4AA)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (danger
                              ? const Color(0xFFFF9B9B)
                              : const Color(0xFF00FF9D))
                          .withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _stat('Kapsül', _capsules.toString())),
              const SizedBox(width: 5),
              Expanded(child: _stat('Seans', '$_session/$_totalSessions')),
              const SizedBox(width: 5),
              Expanded(child: _stat('Mod', _modeLabel, smaller: true)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_totalSessions, (i) {
              final n = i + 1;
              final active = n == _session && _mode == 'focus';
              final done = n < _session ||
                  (n == _session && _mode != 'focus');
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? const Color(0xFF00FF9D)
                        : done
                            ? const Color(0xFF00FF9D).withValues(alpha: 0.5)
                            : Colors.transparent,
                    border: Border.all(
                        color: const Color(0xFF00FF9D)
                            .withValues(alpha: 0.4)),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00FF9D),
                              blurRadius: 5,
                            )
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _smallBtn(Icons.stop_rounded, _reset),
              const SizedBox(width: 14),
              _mainBtn(),
              const SizedBox(width: 14),
              _smallBtn(Icons.skip_next_rounded, _skip),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {bool smaller = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFF00FF9D).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label.toUpperCase(),
              style: GoogleFonts.poppins(
                color: const Color(0xFF8BA6B8),
                fontSize: 8,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 1),
          Text(value,
              style: GoogleFonts.robotoMono(
                color: const Color(0xFF00FF9D),
                fontSize: smaller ? 10 : 12,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }

  Widget _smallBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.6),
          border: Border.all(
              color: const Color(0xFF00FF9D).withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: const Color(0xFF00FF9D), size: 18),
      ),
    );
  }

  Widget _mainBtn() {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: 54, height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _running
                ? const [Color(0xFFFF9B9B), Color(0xFFEE8090)]
                : const [Color(0xFF00FF9D), Color(0xFF00D4AA)],
          ),
          boxShadow: [
            BoxShadow(
              color: (_running
                      ? const Color(0xFFFF9B9B)
                      : const Color(0xFF00FF9D))
                  .withValues(alpha: 0.5),
              blurRadius: 16,
            ),
          ],
        ),
        child: Icon(
          _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: const Color(0xFF0A0A15),
          size: 26,
        ),
      ),
    );
  }
}

// ─── Yıldızlar ───────────────────────────────────────────────────────────────

class _StarSpec {
  final double dx, dy, size, delay, opacity;
  _StarSpec({
    required this.dx,
    required this.dy,
    required this.size,
    required this.delay,
    required this.opacity,
  });
}

class _StarPainter extends CustomPainter {
  final List<_StarSpec> stars;
  final Animation<double> anim;
  _StarPainter(this.stars, this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      final t = (anim.value + s.delay) % 1.0;
      final twinkle = 0.3 + 0.7 * (1 - (2 * t - 1).abs());
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: s.opacity * twinkle);
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        s.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}

// ─── Ay ──────────────────────────────────────────────────────────────────────

class _Moon extends StatelessWidget {
  const _Moon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [
            Color(0xFFF0F0F0),
            Color(0xFFC8C8C8),
            Color(0xFF909090),
            Color(0xFF606060),
          ],
          stops: [0, 0.4, 0.75, 1],
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.white.withValues(alpha: 0.25), blurRadius: 14),
        ],
      ),
      child: CustomPaint(painter: _MoonCraters()),
    );
  }
}

class _MoonCraters extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF707070).withValues(alpha: 0.6);
    canvas.drawCircle(Offset(size.width * .35, size.height * .42), 2.5, p);
    canvas.drawCircle(Offset(size.width * .60, size.height * .30), 1.8, p);
    canvas.drawCircle(Offset(size.width * .50, size.height * .65), 2.0, p);
    canvas.drawCircle(Offset(size.width * .25, size.height * .55), 1.4, p);
  }

  @override
  bool shouldRepaint(_MoonCraters old) => false;
}

// ─── Dünya ───────────────────────────────────────────────────────────────────

class _Earth extends StatelessWidget {
  const _Earth();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70, height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.4, -0.5),
          colors: [
            Color(0xFF6AB4FF),
            Color(0xFF3A7FC8),
            Color(0xFF1A4D8A),
            Color(0xFF0A1D3D),
          ],
          stops: [0, 0.35, 0.65, 1],
        ),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF4A9EFF).withValues(alpha: 0.35),
              blurRadius: 25),
        ],
      ),
      child: ClipOval(child: CustomPaint(painter: _EarthDetails())),
    );
  }
}

class _EarthDetails extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .30, h * .42), width: w * .35, height: h * .22),
      Paint()..color = const Color(0xFF2D7A3D),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .65, h * .55), width: w * .30, height: h * .20),
      Paint()..color = const Color(0xFF3A8A4D),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .45, h * .75), width: w * .22, height: h * .15),
      Paint()..color = const Color(0xFF4AAE5D),
    );
    // Bulutlar
    final c1 = Paint()..color = Colors.white.withValues(alpha: 0.45);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .48, h * .35), width: w * .55, height: h * .14),
      c1,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .40, h * .60), width: w * .38, height: h * .11),
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_EarthDetails old) => false;
}

// ─── Bitki ───────────────────────────────────────────────────────────────────

class _Plant extends StatelessWidget {
  final double scale;
  final int variant;
  const _Plant({required this.scale, required this.variant});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38, height: 70,
      child: scale <= 0
          ? const SizedBox.shrink()
          : AnimatedScale(
              scale: scale.clamp(0.05, 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutBack,
              alignment: Alignment.bottomCenter,
              child: CustomPaint(painter: _PlantPainter(variant)),
            ),
    );
  }
}

class _PlantPainter extends CustomPainter {
  final int variant;
  _PlantPainter(this.variant);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final stem = Paint()
      ..color = const Color(0xFF2D5016)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w / 2, h), Offset(w / 2, h * 0.4), stem);

    const colors = [
      Color(0xFF4ADE80),
      Color(0xFF22C55E),
      Color(0xFF16A34A),
    ];
    for (int i = 0; i < 3; i++) {
      final paint = Paint()..color = colors[i];
      final y = h * (0.7 - i * 0.15);
      final dx = (i.isEven ? -1.0 : 1.0) * w * 0.20;
      canvas.save();
      canvas.translate(w / 2 + dx, y);
      canvas.rotate((i.isEven ? -1 : 1) * 0.5);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 16, height: 8),
        paint,
      );
      canvas.restore();
    }

    if (variant == 1) {
      canvas.drawCircle(Offset(w / 2, h * 0.30), 7,
          Paint()..color = const Color(0xFFA7F3D0));
      canvas.drawCircle(Offset(w / 2, h * 0.30), 4,
          Paint()..color = const Color(0xFF6EE7B7));
    } else if (variant == 2) {
      canvas.drawCircle(Offset(w / 2 - 6, h * 0.30), 3,
          Paint()..color = const Color(0xFFFF69B4));
      canvas.drawCircle(Offset(w / 2 + 6, h * 0.30), 3,
          Paint()..color = const Color(0xFFC084FC));
      canvas.drawCircle(Offset(w / 2, h * 0.26), 4,
          Paint()..color = const Color(0xFFF472B6));
    } else if (variant == 3) {
      canvas.drawCircle(Offset(w / 2, h * 0.32), 6,
          Paint()..color = const Color(0xFFFBBF24));
      canvas.drawCircle(Offset(w / 2, h * 0.32), 2.5,
          Paint()..color = const Color(0xFFF59E0B));
    }
  }

  @override
  bool shouldRepaint(_PlantPainter old) => false;
}

// ─── Kubbe (cam kapsül) ──────────────────────────────────────────────────────

class _DomeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final p = Path();
    p.moveTo(0, h - 12);
    p.lineTo(0, h * 0.55);
    // Sol üst yumuşak yay
    p.cubicTo(0, h * 0.18, w * 0.25, 0, w * 0.5, 0);
    // Sağ üst yay
    p.cubicTo(w * 0.75, 0, w, h * 0.18, w, h * 0.55);
    p.lineTo(w, h - 12);
    p.quadraticBezierTo(w, h, w - 12, h);
    p.lineTo(12, h);
    p.quadraticBezierTo(0, h, 0, h - 12);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

class _DomeOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path();
    path.moveTo(0, h - 12);
    path.lineTo(0, h * 0.55);
    path.cubicTo(0, h * 0.18, w * 0.25, 0, w * 0.5, 0);
    path.cubicTo(w * 0.75, 0, w, h * 0.18, w, h * 0.55);
    path.lineTo(w, h - 12);
    path.quadraticBezierTo(w, h, w - 12, h);
    path.lineTo(12, h);
    path.quadraticBezierTo(0, h, 0, h - 12);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFADDCE6).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Orta dikey çizgi
    canvas.drawLine(
      Offset(w / 2, 4), Offset(w / 2, h - 4),
      Paint()
        ..color = const Color(0xFFADDCE6).withValues(alpha: 0.25)
        ..strokeWidth = 1.2,
    );
    // Orta yatay çizgi
    canvas.drawLine(
      Offset(8, h * 0.42), Offset(w - 8, h * 0.42),
      Paint()
        ..color = const Color(0xFFADDCE6).withValues(alpha: 0.25)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_DomeOutlinePainter old) => false;
}
