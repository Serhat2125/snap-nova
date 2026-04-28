import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  QuAlsarMarsScreen — Gerçekçi QuAlsar kolonisi pomodoro, 4 aşama:
//    1) Starship inişi + 3 astronot + yaşam kubbesi
//    2) Büyük sera (buğday / domates / marul / biber)
//    3) Toprak sondajı + su/oksijen üretimi
//    4) Dev anten + Dünya'ya lazer sinyali
// ═══════════════════════════════════════════════════════════════════════════════

class QuAlsarMarsScreen extends StatefulWidget {
  const QuAlsarMarsScreen({super.key});

  @override
  State<QuAlsarMarsScreen> createState() => _QuAlsarMarsScreenState();
}

enum _PhaseKind { phase1, break1, phase2, break2, phase3, break3, phase4, done }

class _QuAlsarMarsScreenState extends State<QuAlsarMarsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Mod değişkenleri (istek gereği bu isimlerle) ────────────────────────────
  bool test_mode = true;
  bool pro_mode = false;

  int get _phaseSec => pro_mode ? 25 * 60 : 5 * 60;
  int get _breakSec => pro_mode ? 5 * 60 : 1 * 60;

  // ── Sayaç durumu ───────────────────────────────────────────────────────────
  _PhaseKind _phase = _PhaseKind.phase1;
  int _timeLeft = 5 * 60;
  int _totalTime = 5 * 60;
  bool _running = false;
  bool _done = false;
  Timer? _ticker;

  // ── Sinyal kaybı ───────────────────────────────────────────────────────────
  bool _signalLost = false;
  int _signalCountdown = 7;
  Timer? _signalTimer;
  Timer? _alarmTimer;
  bool _stormCollapsed = false;

  // ── Animasyonlar ───────────────────────────────────────────────────────────
  late final AnimationController _starCtrl;      // yıldız parıltısı
  late final AnimationController _pulseCtrl;     // ışık/sinyal titreşimi
  late final AnimationController _walkCtrl;      // astronot yürüyüşü
  late final AnimationController _earthCtrl;     // dünya dönüşü
  late final AnimationController _stormCtrl;     // kum fırtınası

  late final List<_StarSpec> _stars;
  late final List<_Rock> _rocks;
  late final List<_Crater> _craters;
  late final List<_Mountain> _mountains;

  // ── Aşama ilerleme yüzdeleri (kalıcı) ──────────────────────────────────────
  double _p1 = 0, _p2 = 0, _p3 = 0, _p4 = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _timeLeft = _totalTime = _phaseSec;

    final rng = math.Random(1903);
    _stars = List.generate(140, (_) {
      final colorRoll = rng.nextDouble();
      Color c;
      if (colorRoll < 0.55) {
        c = Colors.white;
      } else if (colorRoll < 0.75) {
        c = const Color(0xFFBFD9FF);
      } else if (colorRoll < 0.9) {
        c = const Color(0xFFFFE8B0);
      } else {
        c = const Color(0xFFFFBFA0);
      }
      return _StarSpec(
        dx: rng.nextDouble(),
        dy: rng.nextDouble() * 0.52,
        size: rng.nextDouble() * 1.7 + 0.35,
        delay: rng.nextDouble(),
        opacity: rng.nextDouble() * 0.55 + 0.45,
        color: c,
        crossFlare: rng.nextDouble() > 0.93,
      );
    });

    _rocks = List.generate(34, (_) {
      return _Rock(
        dx: rng.nextDouble(),
        dy: 0.55 + rng.nextDouble() * 0.45,
        size: rng.nextDouble() * 7 + 2,
        shade: rng.nextDouble(),
        jaggedSeed: rng.nextInt(1 << 15),
      );
    });

    _craters = List.generate(6, (_) {
      return _Crater(
        dx: rng.nextDouble(),
        dy: 0.62 + rng.nextDouble() * 0.33,
        w: rng.nextDouble() * 40 + 22,
        h: rng.nextDouble() * 10 + 6,
      );
    });

    _mountains = List.generate(4, (_) {
      return _Mountain(
        cx: rng.nextDouble(),
        w: rng.nextDouble() * 0.4 + 0.25,
        h: rng.nextDouble() * 0.08 + 0.05,
        shade: rng.nextDouble(),
      );
    });

    _starCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _walkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat();
    _earthCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _stormCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _triggerSignalLoss();
    } else if (state == AppLifecycleState.resumed) {
      _recoverSignal();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _signalTimer?.cancel();
    _alarmTimer?.cancel();
    WakelockPlus.disable();
    _starCtrl.dispose();
    _pulseCtrl.dispose();
    _walkCtrl.dispose();
    _earthCtrl.dispose();
    _stormCtrl.dispose();
    super.dispose();
  }

  // ── Zamanlayıcı ────────────────────────────────────────────────────────────
  void _toggle() {
    if (_done) return;
    if (_running) {
      _pause();
    } else {
      _start();
    }
  }

  void _start() {
    if (_signalLost) return;
    setState(() => _running = true);
    WakelockPlus.enable();
    HapticFeedback.mediumImpact();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _timeLeft--;
        _updateLiveProgress();
      });
      if (_timeLeft <= 0) _advance();
    });
  }

  void _pause() {
    _ticker?.cancel();
    WakelockPlus.disable();
    setState(() => _running = false);
  }

  void _reset() {
    _ticker?.cancel();
    WakelockPlus.disable();
    setState(() {
      _running = false;
      _done = false;
      _phase = _PhaseKind.phase1;
      _timeLeft = _totalTime = _phaseSec;
      _p1 = _p2 = _p3 = _p4 = 0;
      _stormCollapsed = false;
    });
  }

  void _skip() {
    _ticker?.cancel();
    setState(() => _timeLeft = 0);
    _advance();
  }

  void _updateLiveProgress() {
    final prog = ((_totalTime - _timeLeft) / _totalTime).clamp(0.0, 1.0);
    switch (_phase) {
      case _PhaseKind.phase1:
        _p1 = prog;
        break;
      case _PhaseKind.phase2:
        _p2 = prog;
        break;
      case _PhaseKind.phase3:
        _p3 = prog;
        break;
      case _PhaseKind.phase4:
        _p4 = prog;
        break;
      default:
        break;
    }
  }

  void _advance() {
    _ticker?.cancel();
    HapticFeedback.heavyImpact();
    setState(() {
      _running = false;
      WakelockPlus.disable();
      switch (_phase) {
        case _PhaseKind.phase1:
          _p1 = 1;
          _phase = _PhaseKind.break1;
          _timeLeft = _totalTime = _breakSec;
          break;
        case _PhaseKind.break1:
          _phase = _PhaseKind.phase2;
          _timeLeft = _totalTime = _phaseSec;
          break;
        case _PhaseKind.phase2:
          _p2 = 1;
          _phase = _PhaseKind.break2;
          _timeLeft = _totalTime = _breakSec;
          break;
        case _PhaseKind.break2:
          _phase = _PhaseKind.phase3;
          _timeLeft = _totalTime = _phaseSec;
          break;
        case _PhaseKind.phase3:
          _p3 = 1;
          _phase = _PhaseKind.break3;
          _timeLeft = _totalTime = _breakSec;
          break;
        case _PhaseKind.break3:
          _phase = _PhaseKind.phase4;
          _timeLeft = _totalTime = _phaseSec;
          break;
        case _PhaseKind.phase4:
          _p4 = 1;
          _phase = _PhaseKind.done;
          _done = true;
          _showVictoryCard();
          break;
        case _PhaseKind.done:
          break;
      }
    });
  }

  void _triggerSignalLoss() {
    if (_signalLost || !_running) return;
    _pause();
    setState(() {
      _signalLost = true;
      _signalCountdown = 7;
    });
    // Alarm — sistem sesi + haptic her saniyede bir.
    _alarmTimer?.cancel();
    _alarmTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    });
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _signalTimer?.cancel();
    _signalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _signalCountdown--);
      if (_signalCountdown <= 0) {
        _signalTimer?.cancel();
        _alarmTimer?.cancel();
        _collapseFromStorm();
      }
    });
  }

  // Otomatik (app lifecycle) geri dönüş — sessizce yeniden başlat.
  void _recoverSignal() {
    if (!_signalLost) return;
    _signalTimer?.cancel();
    _alarmTimer?.cancel();
    setState(() => _signalLost = false);
  }

  // Kullanıcı "Geldim" butonuna bastı — alarm durdur, kaldığı yerden devam.
  void _imBack() {
    if (!_signalLost) return;
    _signalTimer?.cancel();
    _alarmTimer?.cancel();
    setState(() => _signalLost = false);
    _toggle(); // duraklatılmış zamanı yeniden başlat.
  }

  void _collapseFromStorm() {
    setState(() {
      _stormCollapsed = true;
      _signalLost = false;
      _running = false;
    });
  }

  void _showVictoryCard() {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      showDialog(context: context, builder: (_) => const _VictoryDialog());
    });
  }

  String _format(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  String get _phaseTitle {
    switch (_phase) {
      case _PhaseKind.phase1:
        return 'AŞAMA 1 · İNİŞ & KUBBE';
      case _PhaseKind.phase2:
        return 'AŞAMA 2 · SERA';
      case _PhaseKind.phase3:
        return 'AŞAMA 3 · YAŞAM DESTEK';
      case _PhaseKind.phase4:
        return 'AŞAMA 4 · İLETİŞİM';
      case _PhaseKind.break1:
      case _PhaseKind.break2:
      case _PhaseKind.break3:
        return 'MOLA';
      case _PhaseKind.done:
        return 'KOLONİ KURULDU';
    }
  }

  String get _phaseMessage {
    final p = _progress;
    switch (_phase) {
      case _PhaseKind.phase1:
        if (p < 0.18) return 'Starship atmosfere giriyor…';
        if (p < 0.26) return 'Belly-flop: retro-burn ateşleniyor…';
        if (p < 0.32) return 'Motorlar yakıt yakıyor, iniş dikeyleşiyor…';
        if (p < 0.40) return 'Ayaklar açılıyor, yumuşak iniş.';
        if (p < 0.55) return 'Airlock açıldı, mürettebat iniyor…';
        if (p < 0.80) return 'Astronotlar Habitat\'ı kuruyor…';
        return 'Modül basınçlandı, ışıklar yanıyor.';
      case _PhaseKind.phase2:
        if (p < 0.20) return 'Sera çelik iskeleti kuruluyor…';
        if (p < 0.45) return 'Panelli cam kaplama ekleniyor…';
        if (p < 0.70) return 'Hidroponik raflar dolduruluyor…';
        if (p < 0.90) return 'Buğday, domates, marul, biber yetişiyor!';
        return 'İlk hasat toplanıyor.';
      case _PhaseKind.phase3:
        if (p < 0.30) return 'Sondaj kulesi konumlandırıldı…';
        if (p < 0.55) return 'Buz tabakasına sondaj sürüyor…';
        if (p < 0.80) return 'Su buharı çıkıyor, jeneratörler bağlandı…';
        return 'O₂ ve H₂O stokları dolduruluyor.';
      case _PhaseKind.phase4:
        if (p < 0.30) return 'Teleskopik anten yükseliyor…';
        if (p < 0.70) return 'Çanak Dünya\'ya odaklanıyor…';
        return 'Dünya\'ya lazer sinyali gönderiliyor…';
      case _PhaseKind.break1:
        return 'Basınç eşitlendi. İlk güvenli bölge kuruldu.';
      case _PhaseKind.break2:
        return 'İlk hasat yetişti. QuAlsar artık nefes alıyor.';
      case _PhaseKind.break3:
        return 'Oksijen ve su stokları %100. Hayati risk atlatıldı.';
      case _PhaseKind.done:
        return 'BAĞLANTI KURULDU. QuAlsar Koloni Kurucusu.';
    }
  }

  double get _progress {
    if (_totalTime == 0) return 0;
    return ((_totalTime - _timeLeft) / _totalTime).clamp(0.0, 1.0);
  }

  bool get _onBreak =>
      _phase == _PhaseKind.break1 ||
      _phase == _PhaseKind.break2 ||
      _phase == _PhaseKind.break3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Uzay gradyanı (koyudan pembemsi-kırmızıya)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF03030A),
                      Color(0xFF0B0718),
                      Color(0xFF24101E),
                      Color(0xFF4C2018),
                      Color(0xFF7E3A22),
                      Color(0xFFB06040),
                    ],
                    stops: [0, 0.22, 0.42, 0.58, 0.78, 1],
                  ),
                ),
              ),
            ),

            // Samanyolu hafif bant
            Positioned.fill(
              child: CustomPaint(painter: _MilkyWayPainter()),
            ),

            // Yıldızlar
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _starCtrl,
                builder: (_, __) =>
                    CustomPaint(painter: _StarPainter(_stars, _starCtrl.value)),
              ),
            ),

            // Ay — sağ üst (solda sayaç için yer açılıyor).
            const Positioned(
              right: 24,
              top: 20,
              child: _Moon(size: 48),
            ),
            // Dünya — ayın biraz altında, sağa yakın, tam görünür.
            Positioned(
              right: 18,
              top: 78,
              child: AnimatedBuilder(
                animation: _earthCtrl,
                builder: (_, __) =>
                    _Earth(size: 66, rotation: _earthCtrl.value),
              ),
            ),

            // Uzak dağlar (sisli silüet)
            Positioned.fill(
              child: CustomPaint(
                painter: _MountainPainter(_mountains),
              ),
            ),

            // QuAlsar yüzeyi (zemin + kayalar + kraterler + kanyonlar)
            Positioned.fill(
              child: CustomPaint(
                painter: _QuAlsarSurfacePainter(
                  rocks: _rocks,
                  craters: _craters,
                ),
              ),
            ),

            // Ufuk parlaması
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.of(context).size.height * 0.50,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFFFF9670).withValues(alpha: 0.55),
                      const Color(0xFFFF9670).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Koloni inşaat katmanı
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge(
                    [_pulseCtrl, _walkCtrl, _starCtrl]),
                builder: (_, __) => CustomPaint(
                  painter: _ColonyPainter(
                    phase1: _p1,
                    phase2: _p2,
                    phase3: _p3,
                    phase4: _p4,
                    currentPhase: _phase,
                    live: _progress,
                    running: _running,
                    pulse: _pulseCtrl.value,
                    walk: _walkCtrl.value,
                    collapsed: _stormCollapsed,
                  ),
                ),
              ),
            ),

            // Kum fırtınası
            if (_stormCollapsed)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _stormCtrl,
                  builder: (_, __) => CustomPaint(
                    painter: _StormPainter(_stormCtrl.value),
                  ),
                ),
              ),

            // Ön plan içerik
            Column(
              children: [
                _buildTopBar(),
                const SizedBox(height: 4),
                _buildPhaseBadge(),
                const SizedBox(height: 8),
                _buildTimer(),
                const SizedBox(height: 6),
                _buildMessage(),
                const Spacer(),
                _buildBottomPanel(),
              ],
            ),

            if (_signalLost) _buildSignalLostOverlay(),
            if (_stormCollapsed) _buildStormOverlay(),
          ],
        ),
      ),
    );
  }

  // ── UI parçaları ──────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          _iconBtn(Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          _modeChip('TEST 5-1', test_mode && !pro_mode, () {
            if (_running) return;
            setState(() {
              test_mode = true;
              pro_mode = false;
              _timeLeft = _totalTime = _onBreak ? _breakSec : _phaseSec;
            });
          }),
          const SizedBox(width: 6),
          _modeChip('PRO 25-5', pro_mode, () {
            if (_running) return;
            setState(() {
              pro_mode = true;
              test_mode = false;
              _timeLeft = _totalTime = _onBreak ? _breakSec : _phaseSec;
            });
          }),
          const Spacer(),
          _iconBtn(Icons.refresh_rounded, onTap: _reset),
        ],
      ),
    );
  }

  Widget _buildPhaseBadge() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: const Color(0xFFFFB080).withValues(alpha: 0.55)),
      ),
      child: Text(
        _phaseTitle,
        textAlign: TextAlign.center,
        style: GoogleFonts.orbitron(
          color: const Color(0xFFFFD0B0),
          fontSize: 12,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTimer() {
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFFFF9060).withValues(alpha: 0.45),
                width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6A3C).withValues(alpha: 0.20),
                blurRadius: 10,
              ),
            ],
          ),
          child: Text(
            _format(_timeLeft),
            style: GoogleFonts.orbitron(
              color: Colors.white,
              fontSize: 22,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Text(
        _phaseMessage,
        textAlign: TextAlign.center,
        style: GoogleFonts.orbitron(
          color: Colors.white.withValues(alpha: 0.88),
          fontSize: 11.5,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _onBreak
                            ? const [Color(0xFF4AC0FF), Color(0xFF77DDFF)]
                            : const [Color(0xFFFF6A3C), Color(0xFFFFB070)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _bigBtn(
                icon: _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                label: _running ? 'DURDUR' : (_done ? 'BİTTİ' : 'BAŞLAT'),
                primary: true,
                onTap: _toggle,
              ),
              _bigBtn(
                icon: Icons.skip_next_rounded,
                label: 'ATLA',
                onTap: _skip,
              ),
              _bigBtn(
                icon: Icons.restart_alt_rounded,
                label: 'SIFIRLA',
                onTap: _reset,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalLostOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.signal_cellular_connected_no_internet_0_bar_rounded,
                size: 72, color: Colors.redAccent.shade200),
            const SizedBox(height: 14),
            Text('SİNYAL KAYBI',
                style: GoogleFonts.orbitron(
                  color: Colors.redAccent.shade100,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                )),
            const SizedBox(height: 6),
            Text('7 saniye içinde dönmezsen koloni kum altında kalır!',
                textAlign: TextAlign.center,
                style: GoogleFonts.orbitron(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11)),
            const SizedBox(height: 18),
            Text('$_signalCountdown',
                style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                )),
            const SizedBox(height: 16),
            // Geldim butonu — basınca alarm kapanır, kaldığı yerden devam.
            ElevatedButton.icon(
              onPressed: _imBack,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('GELDİM'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 26, vertical: 14),
                textStyle: GoogleFonts.orbitron(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    letterSpacing: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStormOverlay() {
    return Positioned.fill(
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cyclone_rounded,
                size: 72, color: Colors.orange.shade200),
            const SizedBox(height: 12),
            Text('KUM FIRTINASI',
                style: GoogleFonts.orbitron(
                  color: Colors.orange.shade100,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                )),
            const SizedBox(height: 8),
            Text('İnşaat durdu. Tekrar denemek ister misin?',
                textAlign: TextAlign.center,
                style: GoogleFonts.orbitron(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('YENİDEN BAŞLA'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6A3C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.18), width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _modeChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFF6A3C).withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? const Color(0xFFFFB070)
                : Colors.white.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.orbitron(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _bigBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: primary
                  ? const LinearGradient(
                      colors: [Color(0xFFFF6A3C), Color(0xFFFF9860)])
                  : null,
              color: primary ? null : Colors.black.withValues(alpha: 0.4),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22), width: 1.2),
              boxShadow: primary
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF6A3C).withValues(alpha: 0.5),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.orbitron(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Yıldız / Kaya / Krater / Dağ veri sınıfları
// ═══════════════════════════════════════════════════════════════════════════════

class _StarSpec {
  final double dx, dy, size, delay, opacity;
  final Color color;
  final bool crossFlare;
  _StarSpec({
    required this.dx,
    required this.dy,
    required this.size,
    required this.delay,
    required this.opacity,
    required this.color,
    required this.crossFlare,
  });
}

class _Rock {
  final double dx, dy, size, shade;
  final int jaggedSeed;
  _Rock({
    required this.dx,
    required this.dy,
    required this.size,
    required this.shade,
    required this.jaggedSeed,
  });
}

class _Crater {
  final double dx, dy, w, h;
  _Crater({
    required this.dx,
    required this.dy,
    required this.w,
    required this.h,
  });
}

class _Mountain {
  final double cx, w, h, shade;
  _Mountain({
    required this.cx,
    required this.w,
    required this.h,
    required this.shade,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Samanyolu bandı (çok hafif)
// ═══════════════════════════════════════════════════════════════════════════════

class _MilkyWayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * 0.55);
    final p = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          const Color(0xFFB0A8D8).withValues(alpha: 0.06),
          const Color(0xFFD0B8C8).withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, p);
  }

  @override
  bool shouldRepaint(covariant _MilkyWayPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Yıldız painter — renkli, bazılarında haç parıltısı
// ═══════════════════════════════════════════════════════════════════════════════

class _StarPainter extends CustomPainter {
  final List<_StarSpec> stars;
  final double t;
  _StarPainter(this.stars, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final s in stars) {
      final phase = (t + s.delay) % 1.0;
      final twinkle = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
      final alpha = (twinkle * s.opacity).clamp(0.0, 1.0);
      p.color = s.color.withValues(alpha: alpha);
      final pos = Offset(s.dx * size.width, s.dy * size.height);
      canvas.drawCircle(pos, s.size, p);

      if (s.crossFlare && s.size > 1.2) {
        final flareP = Paint()
          ..color = s.color.withValues(alpha: alpha * 0.55)
          ..strokeWidth = 0.7
          ..strokeCap = StrokeCap.round;
        final r = s.size * 3.5;
        canvas.drawLine(Offset(pos.dx - r, pos.dy), Offset(pos.dx + r, pos.dy),
            flareP);
        canvas.drawLine(Offset(pos.dx, pos.dy - r), Offset(pos.dx, pos.dy + r),
            flareP);
      }
    }

    // Kayan yıldız — her ~8 saniyede bir, rastgele yönde gökten geçer.
    // starCtrl 4 sn turlu → t iki turda bir meteor.
    _drawShootingStar(canvas, size, t, seed: 0);
    _drawShootingStar(canvas, size, (t + 0.5) % 1.0, seed: 1);
  }

  void _drawShootingStar(
      Canvas canvas, Size size, double phase, {required int seed}) {
    // Her turda bir meteor: phase 0..0.22 arası görünür, sonra kaybolur.
    if (phase > 0.22) return;
    final rng = math.Random(seed * 997);
    // Başlangıç noktası — üst kenarın rastgele x'inde (tur bazında)
    final cycleId = (t * 2).floor() + seed;
    final lineRng = math.Random(seed * 7331 + cycleId * 13);
    final startX = lineRng.nextDouble() * size.width * 0.8 +
        size.width * 0.1;
    final startY = lineRng.nextDouble() * size.height * 0.30;
    final angle = -math.pi / 4 + (lineRng.nextDouble() - 0.5) * 0.6;
    final speed = size.width * 0.9;
    final prog = (phase / 0.22).clamp(0.0, 1.0);
    final cx = startX + math.cos(angle) * speed * prog;
    final cy = startY + math.sin(angle) * speed * prog + speed * prog * 0.4;
    // Parlaklık fade — girişte artar, sonunda söner.
    final fade =
        math.sin(prog * math.pi).clamp(0.0, 1.0) * (rng.nextDouble() * 0.4 + 0.6);
    // Kuyruk
    final tailLen = 42.0;
    final tailEnd = Offset(
      cx - math.cos(angle) * tailLen,
      cy - math.sin(angle) * tailLen - tailLen * 0.4,
    );
    final shader = ui.Gradient.linear(
      Offset(cx, cy),
      tailEnd,
      [
        Colors.white.withValues(alpha: 0.95 * fade),
        Colors.white.withValues(alpha: 0.0),
      ],
    );
    final tailPaint = Paint()
      ..shader = shader
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), tailEnd, tailPaint);
    // Baş — parlak nokta + hafif glow
    final headPaint = Paint()
      ..color = Colors.white.withValues(alpha: fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(Offset(cx, cy), 2.0, headPaint);
    final corePaint = Paint()..color = Colors.white.withValues(alpha: fade);
    canvas.drawCircle(Offset(cx, cy), 1.1, corePaint);
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => oldDelegate.t != t;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Ay — kraterli, maria lekeli
// ═══════════════════════════════════════════════════════════════════════════════

class _Moon extends StatelessWidget {
  final double size;
  const _Moon({required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFF0D0).withValues(alpha: 0.35),
            blurRadius: 26,
          ),
        ],
      ),
      child: CustomPaint(painter: _MoonPainter()),
    );
  }
}

class _MoonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    // Temel disk
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFF6EBCE), Color(0xFFB9A78A)],
          stops: [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Maria (koyu denizler)
    final mariaP = Paint()..color = const Color(0xFF6A5A44).withValues(alpha: 0.45);
    canvas.drawCircle(c + Offset(-r * 0.25, -r * 0.15), r * 0.22, mariaP);
    canvas.drawCircle(c + Offset(r * 0.1, r * 0.2), r * 0.18, mariaP);
    canvas.drawCircle(c + Offset(r * 0.3, -r * 0.25), r * 0.12, mariaP);
    // Kraterler
    final craterLight = Paint()..color = const Color(0xFFFFF4DA).withValues(alpha: 0.5);
    final craterDark = Paint()..color = const Color(0xFF6F5B42).withValues(alpha: 0.55);
    final rng = math.Random(13);
    for (int i = 0; i < 10; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final dist = rng.nextDouble() * r * 0.82;
      final cr = rng.nextDouble() * r * 0.08 + r * 0.03;
      final pos = c + Offset(math.cos(angle) * dist, math.sin(angle) * dist);
      canvas.drawCircle(pos + Offset(cr * 0.2, cr * 0.2), cr, craterDark);
      canvas.drawCircle(pos - Offset(cr * 0.15, cr * 0.15), cr * 0.65, craterLight);
    }
    // Terminatör gölgesi (sağ alt)
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.85, 0.85),
          radius: 1.2,
          colors: [Color(0xAA1A140C), Colors.transparent],
          stops: [0.0, 0.7],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Dünya — kıtalar + bulutlar, hafif dönen
// ═══════════════════════════════════════════════════════════════════════════════

class _Earth extends StatelessWidget {
  final double size;
  final double rotation;
  const _Earth({required this.size, required this.rotation});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF60B0FF).withValues(alpha: 0.55),
            blurRadius: 30,
          ),
        ],
      ),
      child: CustomPaint(painter: _EarthPainter(rotation)),
    );
  }
}

class _EarthPainter extends CustomPainter {
  final double rot; // 0..1
  _EarthPainter(this.rot);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Atmosfer halkası
    canvas.drawCircle(
      c,
      r * 1.08,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF80C0FF).withValues(alpha: 0.0),
            const Color(0xFF80C0FF).withValues(alpha: 0.35),
          ],
          stops: const [0.78, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.08)),
    );

    // Okyanus
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.3),
          colors: [
            Color(0xFF60B8FF),
            Color(0xFF2A70D0),
            Color(0xFF0E3878),
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Kıtalar (dönüşe göre kaydır)
    canvas.save();
    final clip = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    canvas.clipPath(clip);
    final offset = rot * size.width;
    _drawContinents(canvas, size, offset);
    _drawContinents(canvas, size, offset - size.width);
    _drawContinents(canvas, size, offset - size.width * 2);
    canvas.restore();

    // Bulutlar
    canvas.save();
    canvas.clipPath(clip);
    _drawClouds(canvas, size, rot);
    canvas.restore();

    // Terminatör (gölge)
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.9, 0.8),
          radius: 1.25,
          colors: [Color(0xDD000812), Colors.transparent],
          stops: [0.0, 0.72],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Parlak highlight
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.55, -0.55),
          radius: 0.6,
          colors: [Color(0x55FFFFFF), Colors.transparent],
          stops: [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _drawContinents(Canvas canvas, Size size, double dx) {
    final w = size.width;
    final h = size.height;
    final p = Paint()..color = const Color(0xFF3FA25A);
    final pDark = Paint()..color = const Color(0xFF2F7A44);
    // Amerika (sol)
    final americas = Path()
      ..moveTo(dx + w * 0.10, h * 0.32)
      ..quadraticBezierTo(
          dx + w * 0.22, h * 0.20, dx + w * 0.25, h * 0.40)
      ..quadraticBezierTo(
          dx + w * 0.20, h * 0.50, dx + w * 0.24, h * 0.62)
      ..quadraticBezierTo(
          dx + w * 0.18, h * 0.78, dx + w * 0.13, h * 0.65)
      ..quadraticBezierTo(
          dx + w * 0.08, h * 0.50, dx + w * 0.10, h * 0.32)
      ..close();
    canvas.drawPath(americas, p);
    canvas.drawPath(americas, pDark..color = const Color(0x22000000));
    canvas.drawPath(americas, p);

    // Avrupa-Afrika (orta)
    final afroEur = Path()
      ..moveTo(dx + w * 0.42, h * 0.24)
      ..quadraticBezierTo(
          dx + w * 0.52, h * 0.22, dx + w * 0.58, h * 0.32)
      ..quadraticBezierTo(
          dx + w * 0.54, h * 0.48, dx + w * 0.50, h * 0.60)
      ..quadraticBezierTo(
          dx + w * 0.45, h * 0.72, dx + w * 0.42, h * 0.58)
      ..quadraticBezierTo(
          dx + w * 0.38, h * 0.42, dx + w * 0.42, h * 0.24)
      ..close();
    canvas.drawPath(afroEur, p);

    // Asya (sağ)
    final asia = Path()
      ..moveTo(dx + w * 0.62, h * 0.25)
      ..quadraticBezierTo(
          dx + w * 0.80, h * 0.22, dx + w * 0.86, h * 0.35)
      ..quadraticBezierTo(
          dx + w * 0.80, h * 0.48, dx + w * 0.70, h * 0.44)
      ..quadraticBezierTo(
          dx + w * 0.64, h * 0.38, dx + w * 0.62, h * 0.25)
      ..close();
    canvas.drawPath(asia, p);

    // Avustralya
    final aus = Path()
      ..addOval(Rect.fromCenter(
          center: Offset(dx + w * 0.78, h * 0.62),
          width: w * 0.14,
          height: h * 0.08));
    canvas.drawPath(aus, p);
  }

  void _drawClouds(Canvas canvas, Size size, double rot) {
    final w = size.width;
    final h = size.height;
    final base = rot * w * 1.3;
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (int k = -1; k <= 1; k++) {
      final dx = -base - k * w;
      _cloud(canvas, Offset(dx + w * 0.25, h * 0.30), w * 0.14, cloud);
      _cloud(canvas, Offset(dx + w * 0.55, h * 0.45), w * 0.18, cloud);
      _cloud(canvas, Offset(dx + w * 0.78, h * 0.28), w * 0.12, cloud);
      _cloud(canvas, Offset(dx + w * 0.35, h * 0.70), w * 0.16, cloud);
    }
  }

  void _cloud(Canvas canvas, Offset c, double r, Paint p) {
    canvas.drawCircle(c, r, p);
    canvas.drawCircle(c + Offset(r * 0.6, r * 0.1), r * 0.7, p);
    canvas.drawCircle(c + Offset(-r * 0.6, r * 0.15), r * 0.65, p);
  }

  @override
  bool shouldRepaint(covariant _EarthPainter oldDelegate) =>
      oldDelegate.rot != rot;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Uzak dağ silueti
// ═══════════════════════════════════════════════════════════════════════════════

class _MountainPainter extends CustomPainter {
  final List<_Mountain> mountains;
  _MountainPainter(this.mountains);
  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * 0.50;
    for (final m in mountains) {
      final cx = m.cx * size.width;
      final w = m.w * size.width;
      final h = size.height * m.h;
      final path = Path()
        ..moveTo(cx - w / 2, horizonY + 2)
        ..quadraticBezierTo(cx - w * 0.15, horizonY - h * 1.1, cx, horizonY - h)
        ..quadraticBezierTo(cx + w * 0.25, horizonY - h * 0.7,
            cx + w / 2, horizonY + 2)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(const Color(0xFF6A2E20), const Color(0xFF3C1810),
                  m.shade)!
              .withValues(alpha: 0.85),
      );
      // Tepe kar/toz
      final snow = Path()
        ..moveTo(cx - w * 0.1, horizonY - h * 0.85)
        ..lineTo(cx, horizonY - h)
        ..lineTo(cx + w * 0.08, horizonY - h * 0.8)
        ..close();
      canvas.drawPath(
          snow, Paint()..color = const Color(0xFFFFBFA0).withValues(alpha: 0.4));
    }
  }

  @override
  bool shouldRepaint(covariant _MountainPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  QuAlsar yüzeyi — gradyan + krater + kaya + kanyon + toz
// ═══════════════════════════════════════════════════════════════════════════════

class _QuAlsarSurfacePainter extends CustomPainter {
  final List<_Rock> rocks;
  final List<_Crater> craters;
  _QuAlsarSurfacePainter({required this.rocks, required this.craters});

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * 0.50;
    // Yüzey gradyanı (perspektifli)
    final rect = Rect.fromLTRB(0, horizonY, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFCA6F4C),
            Color(0xFFA04A2E),
            Color(0xFF6E2E1C),
            Color(0xFF3A1608),
          ],
          stops: [0.0, 0.35, 0.72, 1.0],
        ).createShader(Rect.fromLTRB(0, horizonY, size.width, size.height)),
    );

    // Hafif yüzey tonları (leke leke)
    final rng = math.Random(55);
    for (int i = 0; i < 20; i++) {
      final x = rng.nextDouble() * size.width;
      final y = horizonY + rng.nextDouble() * (size.height - horizonY);
      final r = rng.nextDouble() * 40 + 20;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = const Color(0xFF8A3A20)
              .withValues(alpha: rng.nextDouble() * 0.18),
      );
    }

    // Kraterler (uzun oval, gölgeli)
    for (final c in craters) {
      final cx = c.dx * size.width;
      final cy = horizonY + (c.dy - 0.5) / 0.5 * (size.height - horizonY);
      // Çukur gölgesi
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: c.w, height: c.h),
        Paint()..color = const Color(0xFF3A1408).withValues(alpha: 0.7),
      );
      // İç parıltı
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy - c.h * 0.2),
            width: c.w * 0.82,
            height: c.h * 0.7),
        Paint()..color = const Color(0xFFD0704A).withValues(alpha: 0.35),
      );
      // Kenarlık
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: c.w, height: c.h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF2A0C04).withValues(alpha: 0.45),
      );
    }

    // Kanyonlar — birkaç dar, yatay eğimli yarık. Gerçekçi derinlik
    // hissiyatı için koyu gölge + hafif kenar parıltısı.
    _drawCanyons(canvas, size, horizonY);

    // Kayalar
    for (final r in rocks) {
      final cx = r.dx * size.width;
      final cy = horizonY + (r.dy - 0.5) / 0.5 * (size.height - horizonY);
      _drawRock(canvas, Offset(cx, cy), r.size, r.shade, r.jaggedSeed);
    }
  }

  void _drawCanyons(Canvas canvas, Size size, double horizonY) {
    // 3 kanyon — farklı derinliklerde. Deterministik seed (55) ile üretilir,
    // tekrar render'da yerleri sabit kalır.
    final rng = math.Random(7777);
    final surfaceH = size.height - horizonY;
    for (int i = 0; i < 3; i++) {
      final baseY = horizonY + surfaceH * (0.25 + i * 0.22);
      final startX = rng.nextDouble() * size.width * 0.3;
      final endX = size.width * (0.6 + rng.nextDouble() * 0.4);
      final mid1Y = baseY + (rng.nextDouble() - 0.5) * 16;
      final mid2Y = baseY + (rng.nextDouble() - 0.5) * 20;
      // Kanyon genişliği perspektif ile artar.
      final widthNear = 18.0 + i * 6;
      final widthFar = 6.0 + i * 2;
      // Alt kenar (derin)
      final lower = Path()
        ..moveTo(startX, baseY + widthFar * 0.2)
        ..cubicTo(
          startX + (endX - startX) * 0.33,
          mid1Y + widthNear * 0.5,
          startX + (endX - startX) * 0.66,
          mid2Y + widthNear * 0.35,
          endX,
          baseY + widthFar * 0.2,
        );
      // Üst kenar (ışıklı)
      final upper = Path()
        ..moveTo(startX, baseY - widthFar * 0.1)
        ..cubicTo(
          startX + (endX - startX) * 0.33,
          mid1Y - widthNear * 0.1,
          startX + (endX - startX) * 0.66,
          mid2Y - widthNear * 0.05,
          endX,
          baseY - widthFar * 0.1,
        );
      // Kanyon iç (derin gölge) — iki eğri arasını doldur.
      final fill = Path()
        ..addPath(upper, Offset.zero)
        ..extendWithPath(
          Path()
            ..moveTo(endX, baseY + widthFar * 0.2)
            ..cubicTo(
              startX + (endX - startX) * 0.66,
              mid2Y + widthNear * 0.35,
              startX + (endX - startX) * 0.33,
              mid1Y + widthNear * 0.5,
              startX,
              baseY + widthFar * 0.2,
            ),
          Offset.zero,
        )
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A0804).withValues(alpha: 0.85),
              const Color(0xFF3A160A).withValues(alpha: 0.55),
            ],
          ).createShader(Rect.fromLTWH(
              startX, baseY - widthNear, endX - startX, widthNear * 2)),
      );
      // Üst kenar highlight — güneş tarafı.
      canvas.drawPath(
        upper,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color =
              const Color(0xFFE8976A).withValues(alpha: 0.45 - i * 0.08),
      );
      // Alt kenar koyu kontur
      canvas.drawPath(
        lower,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color =
              const Color(0xFF1A0804).withValues(alpha: 0.7),
      );
    }
  }

  void _drawRock(Canvas canvas, Offset c, double size, double shade, int seed) {
    final rng = math.Random(seed);
    final path = Path();
    final points = 7;
    for (int i = 0; i < points; i++) {
      final a = i / points * math.pi * 2;
      final rad = size * (0.75 + rng.nextDouble() * 0.4);
      final x = c.dx + math.cos(a) * rad;
      final y = c.dy + math.sin(a) * rad * 0.5;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.lerp(const Color(0xFF6E3020), const Color(0xFF3A1A10),
                shade)!,
    );
    // Üst highlight
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - size * 0.6, c.dy - size * 0.1)
        ..quadraticBezierTo(c.dx, c.dy - size * 0.35, c.dx + size * 0.6,
            c.dy - size * 0.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFE0906A).withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _QuAlsarSurfacePainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  ANA KOLONİ PAINTER — 4 aşamayı birikimli çizer
// ═══════════════════════════════════════════════════════════════════════════════

class _ColonyPainter extends CustomPainter {
  final double phase1, phase2, phase3, phase4;
  final _PhaseKind currentPhase;
  final double live;
  final bool running;
  final double pulse;
  final double walk;
  final bool collapsed;

  _ColonyPainter({
    required this.phase1,
    required this.phase2,
    required this.phase3,
    required this.phase4,
    required this.currentPhase,
    required this.live,
    required this.running,
    required this.pulse,
    required this.walk,
    required this.collapsed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final groundY = size.height * 0.70;

    // Aşama 1 — Starship + astronotlar + habitat
    if (phase1 > 0 || currentPhase == _PhaseKind.phase1) {
      _drawPhase1(canvas, size, groundY);
    }
    // Aşama 2 — Büyük sera
    if (phase2 > 0 || currentPhase == _PhaseKind.phase2) {
      _drawPhase2Greenhouse(canvas, size, groundY);
    }
    // Aşama 3 — Sondaj + yaşam destek
    if (phase3 > 0 || currentPhase == _PhaseKind.phase3) {
      _drawPhase3Drill(canvas, size, groundY);
    }
    // Aşama 4 — Dev anten
    if (phase4 > 0 || currentPhase == _PhaseKind.phase4) {
      _drawPhase4Antenna(canvas, size, groundY);
    }
  }

  // ── AŞAMA 1 ────────────────────────────────────────────────────────────────
  void _drawPhase1(Canvas canvas, Size size, double groundY) {
    final p =
        (currentPhase == _PhaseKind.phase1 ? live : phase1).clamp(0.0, 1.0);
    final cx = size.width * 0.32;

    // İniş profili:
    // 0-0.12  : yüksekte yatay yaklaşım (belly-flop), gövde eğimli
    // 0.12-0.25: flip + retro-burn, dikeyleşir, hız düşer
    // 0.25-0.38: son 10 metre, dev alev, toz kalkar
    // 0.38-0.42: iniş — gövde yerde, alev söner
    // 0.42-0.55: hatch açılır, astronot 1 çıkar
    // 0.55-0.65: astronot 2 çıkar
    // 0.65-0.75: astronot 3 çıkar
    // 0.75-1.0 : habitat dome yükselir
    final landed = p >= 0.38;
    final craftRestY = groundY - 82;

    double craftX = cx;
    double craftY;
    double tilt; // radyan

    if (p < 0.12) {
      // yüksekten gelir, belly-flop (yatayımsı)
      final t = p / 0.12;
      craftY = -40 + t * (groundY - 260);
      craftX = cx - 90 + t * 80;
      tilt = -1.1 + t * 0.4; // -63°'den -40° civarına
    } else if (p < 0.25) {
      // flip + retro-burn
      final t = (p - 0.12) / 0.13;
      craftY = (groundY - 260) + t * 100;
      craftX = cx - 10 + t * 8;
      tilt = -0.7 * (1 - t); // yavaşça dikeye
    } else if (p < 0.38) {
      // son iniş
      final t = (p - 0.25) / 0.13;
      // Yumuşayan iniş (quadratic ease out)
      final eased = 1 - (1 - t) * (1 - t);
      craftY = (groundY - 160) + eased * 78;
      craftX = cx;
      tilt = 0;
    } else {
      craftX = cx;
      craftY = craftRestY;
      tilt = 0;
    }

    // Toz bulutu (son iniş + sonrası)
    if (p > 0.25 && p < 0.55) {
      final dustT = ((p - 0.25) / 0.20).clamp(0.0, 1.0);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFD8906A).withValues(alpha: 0.75 * (1 - dustT * 0.4)),
            Colors.transparent,
          ],
        ).createShader(
            Rect.fromCircle(center: Offset(cx, groundY), radius: 90));
      canvas.drawCircle(Offset(cx, groundY + 6), 90, paint);
    }

    // Alev (inişte yoğun, sonrası söner)
    if (p < 0.38) {
      double intensity;
      if (p < 0.12) {
        intensity = 0.35;
      } else if (p < 0.25) {
        intensity = 0.5 + (p - 0.12) / 0.13 * 0.5;
      } else {
        intensity = 1.0;
      }
      _drawFlames(canvas, craftX, craftY, tilt, intensity);
    }

    // Starship gövdesi
    _drawStarship(canvas, craftX, craftY, tilt, landed);

    // İniz izi (yerde izleri)
    if (p > 0.42) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, groundY + 2), width: 64, height: 8),
        Paint()..color = const Color(0xFF4A1A0C).withValues(alpha: 0.55),
      );
    }

    // Astronotlar — sırayla çıkar
    final astroCount = p < 0.55 ? 0 : (p < 0.65 ? 1 : (p < 0.75 ? 2 : 3));
    for (int i = 0; i < astroCount; i++) {
      final baseT = [0.55, 0.65, 0.75][i];
      final exitT = ((p - baseT) / 0.10).clamp(0.0, 1.0);
      // Astronot hatch'tan çıkar, sağa yürür
      final startX = cx + 14;
      final targetX = cx + 70 + i * 22;
      final ax = startX + (targetX - startX) * exitT;
      final bob = math.sin((walk + i * 0.33) * math.pi * 2) * 1.2;
      _drawAstronaut(
        canvas,
        Offset(ax, groundY + bob),
        walk + i * 0.33,
        legs: exitT > 0.1,
      );
    }

    // Habitat dome — 75%+
    if (p > 0.75) {
      final domeT = ((p - 0.75) / 0.25).clamp(0.0, 1.0);
      _drawHabitat(canvas, size, groundY, cx + 140, domeT);
    }
  }

  void _drawFlames(Canvas canvas, double cx, double cy, double tilt,
      double intensity) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(tilt);
    // Alt alev
    final w = 18.0 * intensity;
    final h = 40.0 * intensity;
    final baseY = 48.0;
    final flamePath = Path()
      ..moveTo(-w, baseY)
      ..quadraticBezierTo(-w * 0.6, baseY + h * 0.4, 0, baseY + h)
      ..quadraticBezierTo(w * 0.6, baseY + h * 0.4, w, baseY)
      ..close();
    canvas.drawPath(
      flamePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFE070).withValues(alpha: 0.95),
            const Color(0xFFFF7A30).withValues(alpha: 0.8),
            const Color(0xFFFF3010).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(-w, baseY, w * 2, h)),
    );
    // Sıcak merkez
    canvas.drawPath(
      Path()
        ..moveTo(-w * 0.5, baseY)
        ..quadraticBezierTo(-w * 0.3, baseY + h * 0.35, 0, baseY + h * 0.75)
        ..quadraticBezierTo(w * 0.3, baseY + h * 0.35, w * 0.5, baseY)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.85 * intensity),
    );
    canvas.restore();
  }

  void _drawStarship(Canvas canvas, double cx, double cy, double tilt,
      bool landed) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(tilt);

    // Boyutlar
    final bodyW = 28.0;
    final bodyH = 96.0;
    final noseH = 22.0;

    // Gölge / ışık için gradyan
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFFB8C0C8),
          const Color(0xFFF2F4F6),
          const Color(0xFF909898),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCenter(
          center: Offset(0, -bodyH / 2),
          width: bodyW,
          height: bodyH));

    // Burun konisi
    final nose = Path()
      ..moveTo(-bodyW / 2, -bodyH + 2)
      ..quadraticBezierTo(0, -bodyH - noseH, bodyW / 2, -bodyH + 2)
      ..close();
    canvas.drawPath(nose, bodyPaint);

    // Gövde (uzun silindir)
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(-bodyW / 2, -bodyH, bodyW, bodyH),
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      ),
      bodyPaint,
    );

    // Siyah ısı kalkanı şeridi (sol yüz)
    canvas.drawRect(
      Rect.fromLTWH(-bodyW / 2, -bodyH + 6, 4, bodyH - 10),
      Paint()..color = const Color(0xFF20242A),
    );

    // Panel çizgileri
    final lineP = Paint()
      ..color = const Color(0xFF707880).withValues(alpha: 0.7)
      ..strokeWidth = 0.5;
    for (int i = 1; i < 5; i++) {
      final y = -bodyH + i * (bodyH / 5);
      canvas.drawLine(
          Offset(-bodyW / 2 + 1, y), Offset(bodyW / 2 - 1, y), lineP);
    }

    // Üst kanatçıklar (forward flaps)
    final flapTopP = Paint()..color = const Color(0xFF606A74);
    final flapTopL = Path()
      ..moveTo(-bodyW / 2, -bodyH + 8)
      ..lineTo(-bodyW / 2 - 10, -bodyH + 14)
      ..lineTo(-bodyW / 2 - 8, -bodyH + 26)
      ..lineTo(-bodyW / 2, -bodyH + 20)
      ..close();
    final flapTopR = Path()
      ..moveTo(bodyW / 2, -bodyH + 8)
      ..lineTo(bodyW / 2 + 10, -bodyH + 14)
      ..lineTo(bodyW / 2 + 8, -bodyH + 26)
      ..lineTo(bodyW / 2, -bodyH + 20)
      ..close();
    canvas.drawPath(flapTopL, flapTopP);
    canvas.drawPath(flapTopR, flapTopP);

    // Alt kanatçıklar (aft flaps) - daha büyük
    final flapBtmL = Path()
      ..moveTo(-bodyW / 2, -22)
      ..lineTo(-bodyW / 2 - 18, -6)
      ..lineTo(-bodyW / 2 - 14, 8)
      ..lineTo(-bodyW / 2, -2)
      ..close();
    final flapBtmR = Path()
      ..moveTo(bodyW / 2, -22)
      ..lineTo(bodyW / 2 + 18, -6)
      ..lineTo(bodyW / 2 + 14, 8)
      ..lineTo(bodyW / 2, -2)
      ..close();
    canvas.drawPath(flapBtmL, flapTopP);
    canvas.drawPath(flapBtmR, flapTopP);

    // Pencere sırası
    final winP = Paint()..color = const Color(0xFF8AD8FF);
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(0, -bodyH + 30 + i * 10), 1.6, winP);
    }
    // Kapı (hatch)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, -14), width: 8, height: 14),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF2E343C),
    );

    // Motor çanı (taban)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-bodyW / 2 + 2, 0, bodyW - 4, 10),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF2A2E34),
    );
    canvas.drawLine(Offset(-8, 4), Offset(-8, 10),
        Paint()..color = const Color(0xFF8E969E));
    canvas.drawLine(Offset(0, 4), Offset(0, 10),
        Paint()..color = const Color(0xFF8E969E));
    canvas.drawLine(Offset(8, 4), Offset(8, 10),
        Paint()..color = const Color(0xFF8E969E));

    // Landing legs (indiğinde açılır)
    if (landed) {
      final legP = Paint()
        ..color = const Color(0xFF4A5058)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(-bodyW / 2 + 2, 4), Offset(-bodyW / 2 - 6, 14),
          legP);
      canvas.drawLine(Offset(bodyW / 2 - 2, 4), Offset(bodyW / 2 + 6, 14),
          legP);
      canvas.drawLine(Offset(0, 10), Offset(0, 16), legP);
      // Ayak pedleri
      canvas.drawCircle(Offset(-bodyW / 2 - 6, 14), 2.4,
          Paint()..color = const Color(0xFF30363E));
      canvas.drawCircle(Offset(bodyW / 2 + 6, 14), 2.4,
          Paint()..color = const Color(0xFF30363E));
    }

    // "QUALSAR" logosu
    final tp = TextPainter(
      text: TextSpan(
        text: 'QUALSAR',
        style: GoogleFonts.orbitron(
          color: const Color(0xFF303840),
          fontSize: 5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(0, -bodyH + 52);
    canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();

    canvas.restore();
  }

  void _drawAstronaut(Canvas canvas, Offset ground, double t, {bool legs = true}) {
    // Gövde ölçüleri (küçük)
    final x = ground.dx;
    final y = ground.dy; // ayakların yere değdiği nokta
    // Beyaz skafander gövdesi
    final suit = Paint()..color = const Color(0xFFF2F6FA);
    final suitShade = Paint()..color = const Color(0xFFD0D8E0);
    // Bacaklar (yürüme animasyonu)
    final legP = Paint()
      ..color = const Color(0xFFF2F6FA)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    if (legs) {
      final swing = math.sin(t * math.pi * 2) * 2.4;
      canvas.drawLine(Offset(x, y - 8), Offset(x - 2 + swing, y), legP);
      canvas.drawLine(Offset(x, y - 8), Offset(x + 2 - swing, y), legP);
    } else {
      canvas.drawLine(Offset(x, y - 8), Offset(x - 1.5, y), legP);
      canvas.drawLine(Offset(x, y - 8), Offset(x + 1.5, y), legP);
    }
    // Torso
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y - 12), width: 7, height: 9),
        const Radius.circular(2),
      ),
      suit,
    );
    // Sırt çantası (PLSS)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x - 4.5, y - 13), width: 3.5, height: 8),
        const Radius.circular(1.5),
      ),
      suitShade,
    );
    // Kollar
    final armSwing = math.sin(t * math.pi * 2 + math.pi) * 1.5;
    canvas.drawLine(Offset(x - 3, y - 14), Offset(x - 5 + armSwing, y - 8),
        legP..strokeWidth = 2);
    canvas.drawLine(Offset(x + 3, y - 14), Offset(x + 5 - armSwing, y - 8),
        legP..strokeWidth = 2);
    // Kask (yuvarlak)
    canvas.drawCircle(Offset(x, y - 20), 4.2, suit);
    // Vizör
    final visor = Rect.fromCenter(
        center: Offset(x, y - 20), width: 6.6, height: 4.5);
    canvas.drawOval(
      visor,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF2A3A60), Color(0xFF80D0FF)],
        ).createShader(visor),
    );
    // Kask yansıması
    canvas.drawCircle(Offset(x - 1.4, y - 20.8), 0.8,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
    // Anten
    canvas.drawLine(Offset(x + 2.5, y - 23.5), Offset(x + 3.6, y - 25.6),
        Paint()
          ..color = const Color(0xFF606A74)
          ..strokeWidth = 0.8);
  }

  void _drawHabitat(Canvas canvas, Size size, double groundY, double cx,
      double progress) {
    final maxR = 50.0;
    final r = maxR * progress;
    final rect = Rect.fromCenter(
      center: Offset(cx, groundY - r * 0.6),
      width: r * 2,
      height: r * 1.25,
    );
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, groundY));
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.5),
          colors: [
            const Color(0xFFE8EEF6).withValues(alpha: 0.85),
            const Color(0xFF7098C0).withValues(alpha: 0.45),
          ],
        ).createShader(rect),
    );
    // Çerçeve
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.restore();
    // Taban
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - r, groundY - 4, r * 2, 6),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF3A4048),
    );
    // Kapı
    if (progress > 0.5) {
      canvas.drawRect(
        Rect.fromLTWH(cx - 5, groundY - 14, 10, 14),
        Paint()..color = const Color(0xFF20242A),
      );
    }
    if (progress >= 1) {
      final lp = Paint()
        ..color =
            Color.lerp(const Color(0xFFFFD060), Colors.white, pulse * 0.4)!
                .withValues(alpha: 0.85);
      canvas.drawCircle(Offset(cx - r * 0.4, groundY - r * 0.35), 2.6, lp);
      canvas.drawCircle(Offset(cx + r * 0.4, groundY - r * 0.35), 2.6, lp);
      canvas.drawCircle(Offset(cx, groundY - r * 0.85), 2.6, lp);
    }
  }

  // ── AŞAMA 2: BÜYÜK SERA ────────────────────────────────────────────────────
  void _drawPhase2Greenhouse(Canvas canvas, Size size, double groundY) {
    final p =
        (currentPhase == _PhaseKind.phase2 ? live : phase2).clamp(0.0, 1.0);
    final cxL = size.width * 0.50;
    final cxR = size.width * 0.82;
    final baseY = groundY - 2;
    final greenhouseW = (cxR - cxL).abs();
    final greenhouseH = 84.0;
    final top = baseY - greenhouseH;

    // 0-0.20: çelik iskelet
    final skeletonT = (p / 0.20).clamp(0.0, 1.0);
    final frameP = Paint()
      ..color = const Color(0xFF808890)
      ..strokeWidth = 1.6;
    // Yan direkler
    canvas.drawLine(Offset(cxL, baseY), Offset(cxL, baseY - greenhouseH * skeletonT),
        frameP);
    canvas.drawLine(Offset(cxR, baseY),
        Offset(cxR, baseY - greenhouseH * skeletonT), frameP);
    // Tavan kemeri
    if (skeletonT > 0.5) {
      final arcT = ((skeletonT - 0.5) / 0.5).clamp(0.0, 1.0);
      final mid = Offset((cxL + cxR) / 2, top - 14 * arcT);
      final path = Path()
        ..moveTo(cxL, top + greenhouseH - greenhouseH * skeletonT)
        ..quadraticBezierTo(mid.dx, mid.dy, cxR, top);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = const Color(0xFF808890));
    }
    // Çapraz destekler
    if (skeletonT > 0.8) {
      for (int i = 1; i < 4; i++) {
        final x = cxL + i * (greenhouseW / 4);
        canvas.drawLine(Offset(x, baseY), Offset(x, top + 4),
            frameP..strokeWidth = 1);
      }
    }

    // 0.20-0.45: cam kaplama
    if (p > 0.20) {
      final glassT = ((p - 0.20) / 0.25).clamp(0.0, 1.0);
      final rect = Rect.fromLTWH(cxL, top, greenhouseW, greenhouseH);
      canvas.save();
      canvas.clipRect(rect);
      // Kemer üstlü cam gövde
      final path = Path()
        ..moveTo(cxL, baseY)
        ..lineTo(cxL, top + 10)
        ..quadraticBezierTo((cxL + cxR) / 2, top - 14, cxR, top + 10)
        ..lineTo(cxR, baseY)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color =
              const Color(0xFFBFE4F0).withValues(alpha: 0.35 * glassT),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.55 * glassT),
      );
      // Cam panel çizgileri
      for (int i = 1; i < 5; i++) {
        final x = cxL + i * (greenhouseW / 5);
        canvas.drawLine(
          Offset(x, baseY),
          Offset(x, top + 4),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3 * glassT)
            ..strokeWidth = 0.8,
        );
      }
      canvas.restore();
    }

    // 0.45-0.70: hidroponik raflar (3 kat)
    if (p > 0.45) {
      final rackT = ((p - 0.45) / 0.25).clamp(0.0, 1.0);
      final rackP = Paint()..color = const Color(0xFF4A5058);
      final soilP = Paint()..color = const Color(0xFF3E2010);
      for (int i = 0; i < 3; i++) {
        final y = baseY - 18 - i * 20;
        final widthT = rackT;
        final w = greenhouseW * 0.82 * widthT;
        final xStart = cxL + (greenhouseW - w) / 2;
        // Raf tablası
        canvas.drawRect(Rect.fromLTWH(xStart, y, w, 3), rackP);
        // Toprak
        canvas.drawRect(Rect.fromLTWH(xStart + 2, y - 3, w - 4, 3), soilP);
      }
      // LED ışık çubukları
      if (rackT > 0.6) {
        for (int i = 0; i < 3; i++) {
          final y = baseY - 18 - i * 20 - 16;
          canvas.drawRect(
            Rect.fromLTWH(cxL + 6, y, greenhouseW - 12, 1.5),
            Paint()
              ..color =
                  const Color(0xFFFFE0B0).withValues(alpha: 0.65 + 0.3 * pulse),
          );
        }
      }
    }

    // 0.60-1.0: bitkiler çeşit çeşit yetişir
    if (p > 0.60) {
      final plantT = ((p - 0.60) / 0.40).clamp(0.0, 1.0);
      // 3 raf × 5 bitki = 15 bitki, her raf farklı ürün
      _drawRackPlants(canvas, cxL, cxR, baseY - 21, plantT, _CropKind.wheat);
      _drawRackPlants(canvas, cxL, cxR, baseY - 41, plantT, _CropKind.tomato);
      _drawRackPlants(canvas, cxL, cxR, baseY - 61, plantT, _CropKind.lettuce);
    }
  }

  void _drawRackPlants(Canvas canvas, double xL, double xR, double topOfSoil,
      double t, _CropKind kind) {
    final count = 7;
    final w = xR - xL;
    for (int i = 0; i < count; i++) {
      final x = xL + (i + 0.5) * (w / count);
      final stagger = i * 0.06;
      final g = ((t - stagger) / (1 - stagger)).clamp(0.0, 1.0);
      if (g <= 0) continue;
      switch (kind) {
        case _CropKind.wheat:
          _drawWheat(canvas, x, topOfSoil, g);
          break;
        case _CropKind.tomato:
          _drawTomato(canvas, x, topOfSoil, g);
          break;
        case _CropKind.lettuce:
          _drawLettuce(canvas, x, topOfSoil, g);
          break;
      }
    }
  }

  void _drawWheat(Canvas canvas, double x, double baseY, double g) {
    final h = 16 * g;
    // Sap
    canvas.drawLine(
      Offset(x, baseY),
      Offset(x, baseY - h),
      Paint()
        ..color = const Color(0xFFC0A050)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round,
    );
    // Başak (sarıya dönüyor)
    if (g > 0.5) {
      final ear = Paint()..color = const Color(0xFFE6B860);
      for (int k = 0; k < 4; k++) {
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x + (k.isEven ? -1.2 : 1.2), baseY - h + 2 + k * 1.6),
              width: 2.2,
              height: 1.3),
          ear,
        );
      }
    }
  }

  void _drawTomato(Canvas canvas, double x, double baseY, double g) {
    final h = 14 * g;
    canvas.drawLine(
      Offset(x, baseY),
      Offset(x, baseY - h),
      Paint()
        ..color = const Color(0xFF2E7B3A)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    // Yapraklar
    if (g > 0.35) {
      final leaf = Paint()..color = const Color(0xFF3FA050);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x - 3, baseY - h * 0.4), width: 4, height: 2.4),
          leaf);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x + 3, baseY - h * 0.65), width: 4, height: 2.4),
          leaf);
    }
    // Domates (kırmızı)
    if (g > 0.75) {
      final tomP = Paint()..color = const Color(0xFFE04030);
      canvas.drawCircle(Offset(x - 2, baseY - h * 0.55), 1.6, tomP);
      canvas.drawCircle(Offset(x + 2.5, baseY - h * 0.8), 1.8, tomP);
    }
  }

  void _drawLettuce(Canvas canvas, double x, double baseY, double g) {
    final r = 5.5 * g;
    // Kıvrım kıvrım marul
    final leaf = Paint()..color = const Color(0xFF70C078);
    final leafShade = Paint()..color = const Color(0xFF4E8A54);
    canvas.drawCircle(Offset(x, baseY - 2), r, leafShade);
    canvas.drawCircle(Offset(x - r * 0.3, baseY - r * 0.5), r * 0.7, leaf);
    canvas.drawCircle(Offset(x + r * 0.3, baseY - r * 0.6), r * 0.7, leaf);
    canvas.drawCircle(Offset(x, baseY - r * 0.9), r * 0.55, leaf);
  }

  // ── AŞAMA 3: SONDAJ + YAŞAM DESTEK ─────────────────────────────────────────
  void _drawPhase3Drill(Canvas canvas, Size size, double groundY) {
    final p =
        (currentPhase == _PhaseKind.phase3 ? live : phase3).clamp(0.0, 1.0);
    final cx = size.width * 0.15;

    // 0-0.30: kule yükselir
    final riseT = (p / 0.30).clamp(0.0, 1.0);
    final towerH = 78.0 * riseT;
    final towerTopY = groundY - towerH;

    // Kafes kule (3 dikey + diyagonaller)
    final bar = Paint()
      ..color = const Color(0xFF9A9A9E)
      ..strokeWidth = 1.8;
    canvas.drawLine(Offset(cx - 8, groundY), Offset(cx - 8, towerTopY), bar);
    canvas.drawLine(Offset(cx + 8, groundY), Offset(cx + 8, towerTopY), bar);
    canvas.drawLine(Offset(cx, groundY), Offset(cx, towerTopY - 8), bar);
    // Diyagonaller
    final diagSteps = (towerH / 14).floor();
    for (int i = 0; i < diagSteps; i++) {
      final y1 = groundY - i * 14.0;
      final y2 = groundY - (i + 1) * 14.0;
      canvas.drawLine(Offset(cx - 8, y1), Offset(cx + 8, y2),
          bar..strokeWidth = 0.8);
      canvas.drawLine(Offset(cx + 8, y1), Offset(cx - 8, y2),
          bar..strokeWidth = 0.8);
    }

    if (riseT >= 1) {
      // Kule üstü motor bloğu
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, towerTopY - 10), width: 24, height: 14),
        Paint()..color = const Color(0xFFB07850),
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, towerTopY - 10), width: 24, height: 14),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF5E3820),
      );
    }

    // 0.30-0.55: matkap döner, zemine saplanır
    if (p > 0.30) {
      final drillT = ((p - 0.30) / 0.25).clamp(0.0, 1.0);
      final drillLen = 18.0 + 12.0 * drillT;
      // Matkap çubuğu
      canvas.drawLine(
        Offset(cx, groundY - 3),
        Offset(cx, groundY + drillLen),
        Paint()
          ..color = const Color(0xFF707880)
          ..strokeWidth = 2.6,
      );
      // Titreşim (zemine girerken)
      if (running && currentPhase == _PhaseKind.phase3 && drillT < 1) {
        final j = math.sin(pulse * math.pi * 8) * 1.2;
        canvas.drawLine(
          Offset(cx + j, groundY + drillLen),
          Offset(cx + j, groundY + drillLen + 6),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.45)
            ..strokeWidth = 2,
        );
      }
      // Toprak yığını (delme sonucu)
      if (drillT > 0.3) {
        final moundP = Paint()..color = const Color(0xFF6E3520);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx - 14, groundY + 2), width: 14, height: 4),
          moundP,
        );
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx + 14, groundY + 2), width: 14, height: 4),
          moundP,
        );
      }
    }

    // 0.55-0.80: su buharı
    if (p > 0.55) {
      final steamT = ((p - 0.55) / 0.25).clamp(0.0, 1.0);
      for (int i = 0; i < 4; i++) {
        final offset = (pulse + i * 0.25) % 1.0;
        canvas.drawCircle(
          Offset(cx + math.sin(offset * math.pi * 2) * 4,
              groundY - towerH - 6 - offset * 36),
          4 + offset * 7,
          Paint()
            ..color = Colors.white
                .withValues(alpha: 0.5 * steamT * (1 - offset)),
        );
      }
    }

    // 0.70-1.0: O2 ve H2O tankları kuruyor (kulenin sağına)
    if (p > 0.65) {
      final tankT = ((p - 0.65) / 0.35).clamp(0.0, 1.0);
      final tx = cx + 32;
      _drawTank(canvas, tx, groundY, 'O₂', const Color(0xFF4AD0FF), tankT);
      _drawTank(
          canvas, tx + 22, groundY, 'H₂O', const Color(0xFF70C8FF), tankT);
      // Boru bağlantısı
      if (tankT > 0.5) {
        canvas.drawLine(
          Offset(cx, groundY - 10),
          Offset(tx, groundY - 12),
          Paint()
            ..color = const Color(0xFF606870)
            ..strokeWidth = 1.4,
        );
      }
    }
  }

  void _drawTank(Canvas canvas, double cx, double groundY, String label,
      Color color, double fill) {
    final w = 18.0, h = 44.0;
    final rect = Rect.fromLTWH(cx - w / 2, groundY - h, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = const Color(0xFF2A2E36),
    );
    final fillH = h * fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - w / 2 + 2, groundY - fillH, w - 4, fillH - 2),
        const Radius.circular(3),
      ),
      Paint()..color = color.withValues(alpha: 0.85),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: GoogleFonts.orbitron(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, groundY - h - 11));
  }

  // ── AŞAMA 4: ANTEN + LAZER ─────────────────────────────────────────────────
  void _drawPhase4Antenna(Canvas canvas, Size size, double groundY) {
    final p =
        (currentPhase == _PhaseKind.phase4 ? live : phase4).clamp(0.0, 1.0);
    final cx = size.width * 0.88;

    // Tepe
    final hillPath = Path()
      ..moveTo(cx - 44, groundY)
      ..quadraticBezierTo(cx - 10, groundY - 28, cx, groundY - 26)
      ..quadraticBezierTo(cx + 18, groundY - 24, cx + 44, groundY)
      ..close();
    canvas.drawPath(
      hillPath,
      Paint()..color = const Color(0xFF5A2818),
    );
    // Tepe highlight
    canvas.drawPath(
      Path()
        ..moveTo(cx - 20, groundY - 18)
        ..quadraticBezierTo(cx - 5, groundY - 28, cx + 5, groundY - 25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFC07050).withValues(alpha: 0.6),
    );

    final rise = (p / 0.70).clamp(0.0, 1.0);
    final h = 130.0 * rise;
    final topY = groundY - 26 - h;

    // Direk
    canvas.drawLine(
      Offset(cx, groundY - 26),
      Offset(cx, topY),
      Paint()
        ..color = const Color(0xFFC0C4C8)
        ..strokeWidth = 3,
    );
    // Destek telleri
    if (rise > 0.3) {
      final wireP = Paint()
        ..color = const Color(0xFF808890).withValues(alpha: 0.6)
        ..strokeWidth = 0.7;
      canvas.drawLine(Offset(cx, topY + 20), Offset(cx - 20, groundY - 26), wireP);
      canvas.drawLine(Offset(cx, topY + 20), Offset(cx + 20, groundY - 26), wireP);
    }
    // Çanak
    if (rise > 0.3) {
      final dishR = 12 * ((rise - 0.3) / 0.7).clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx, topY), width: dishR * 2.2, height: dishR * 2.2),
        math.pi * 1.1,
        math.pi * 0.8,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..color = const Color(0xFFE0E4E8),
      );
      canvas.drawCircle(Offset(cx, topY), 2.4,
          Paint()..color = const Color(0xFFFFB070));
    }

    // Lazer sinyal
    if (p > 0.7) {
      final beamProg = ((p - 0.7) / 0.3).clamp(0.0, 1.0);
      final beamEnd = Offset(size.width * 0.75, 44); // Dünya'ya yakın
      final start = Offset(cx, topY);
      final alpha = (0.4 + 0.6 * pulse) * beamProg;
      canvas.drawLine(
        start,
        Offset.lerp(start, beamEnd, beamProg)!,
        Paint()
          ..color = const Color(0xFF80E0FF).withValues(alpha: alpha)
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        start,
        Offset.lerp(start, beamEnd, beamProg)!,
        Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.65)
          ..strokeWidth = 0.8
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ColonyPainter oldDelegate) => true;
}

enum _CropKind { wheat, tomato, lettuce }

// ═══════════════════════════════════════════════════════════════════════════════
//  Kum fırtınası
// ═══════════════════════════════════════════════════════════════════════════════

class _StormPainter extends CustomPainter {
  final double t;
  _StormPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFA09080).withValues(alpha: 0.78),
          const Color(0xFF806858).withValues(alpha: 0.88),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (int i = 0; i < 36; i++) {
      final y = (size.height * (i / 36) + t * size.height) % size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 8), line);
    }
  }

  @override
  bool shouldRepaint(covariant _StormPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Zafer diyaloğu
// ═══════════════════════════════════════════════════════════════════════════════

class _VictoryDialog extends StatelessWidget {
  const _VictoryDialog();
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E0A22), Color(0xFF6E2A20)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFB070), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6A3C).withValues(alpha: 0.4),
              blurRadius: 26,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.military_tech_rounded,
                size: 58, color: Colors.orange.shade200),
            const SizedBox(height: 10),
            Text('BAĞLANTI KURULDU',
                style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                )),
            const SizedBox(height: 8),
            Text('QuAlsar Koloni Kurucusu',
                style: GoogleFonts.orbitron(
                  color: Colors.orange.shade100,
                  fontSize: 12,
                  letterSpacing: 1.4,
                )),
            const SizedBox(height: 12),
            Text(
              '4 aşamalı QuAlsar Protokolü\'nü tamamladın.\nDünya ile iletişim kuruldu.',
              textAlign: TextAlign.center,
              style: GoogleFonts.orbitron(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6A3C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 10),
              ),
              child: const Text('DEVAM'),
            ),
          ],
        ),
      ),
    );
  }
}
