// ═══════════════════════════════════════════════════════════════════════════
//  ParentalControlGate — Uygulama-geneli ebeveyn kontrolü kilidi.
//
//  MaterialApp.builder Stack'ine overlay olarak eklenir. Öğrenci hesabında:
//    • Ön planda geçen süreyi sayar → günlük limit aşılınca tam-ekran kilit.
//    • Sessiz saat aralığında tam-ekran kilit (saat geçince otomatik kalkar).
//  Öğretmen/ebeveyn hesabında hiçbir şey yapmaz (servis zaten no-op döner).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/parental_controls_service.dart';
import '../services/runtime_translator.dart';

class ParentalControlGate extends StatefulWidget {
  const ParentalControlGate({super.key});

  @override
  State<ParentalControlGate> createState() => _ParentalControlGateState();
}

class _ParentalControlGateState extends State<ParentalControlGate>
    with WidgetsBindingObserver {
  static const _tick = Duration(seconds: 20);
  Timer? _timer;
  bool _foreground = true;
  LockReason _lock = LockReason.none;
  int _usedMinutes = 0;
  int _sinceRefresh = 0; // sn — periyodik Firestore yenilemesi için

  final _svc = ParentalControlsService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _svc.addListener(_onSvc);
    _init();
  }

  Future<void> _init() async {
    await _svc.refresh();
    await _evaluate();
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  void _onSvc() {
    if (mounted) _evaluate();
  }

  Future<void> _onTick() async {
    if (_foreground) {
      await _svc.addUsageSeconds(_tick.inSeconds);
      _sinceRefresh += _tick.inSeconds;
      // ~5 dakikada bir ebeveyn değişikliklerini çek.
      if (_sinceRefresh >= 300) {
        _sinceRefresh = 0;
        await _svc.refresh(); // listener _evaluate tetikler
      }
    }
    await _evaluate();
  }

  Future<void> _evaluate() async {
    final used = await _svc.usedMinutesToday();
    final lock = _svc.lockFor(used);
    if (!mounted) return;
    if (lock != _lock || used != _usedMinutes) {
      setState(() {
        _lock = lock;
        _usedMinutes = used;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _sinceRefresh = 0;
      _svc.refresh(); // öne gelince güncel ayar + kilit
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _svc.removeListener(_onSvc);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lock == LockReason.none) return const SizedBox.shrink();
    return _LockScreen(reason: _lock, svc: _svc);
  }
}

class _LockScreen extends StatelessWidget {
  final LockReason reason;
  final ParentalControlsService svc;
  const _LockScreen({required this.reason, required this.svc});

  @override
  Widget build(BuildContext context) {
    final isQuiet = reason == LockReason.quietHours;
    final emoji = isQuiet ? '🌙' : '⏰';
    final title = isQuiet ? 'Sessiz saatler'.tr() : 'Günlük süre doldu'.tr();
    final desc = isQuiet
        ? '${'Şu an çalışma dışı saatlerdesin'.tr()} (${svc.quietRangeLabel}). '
            '${'Bu süre bitince uygulama tekrar açılır.'.tr()}'
        : '${'Bugünkü kullanım süren doldu'.tr()} '
            '(${svc.dailyLimitMinutes} ${'dk'.tr()}). '
            '${'Yarın yeniden başlayabilirsin.'.tr()}';
    // Tam ekran, opak, dokunuşları yutar (arkadaki UI'a erişilemez).
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0B1220),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    alignment: Alignment.center,
                    child: Text(emoji, style: const TextStyle(fontSize: 46)),
                  ),
                  const SizedBox(height: 24),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.w900,
                        color: Colors.white,
                      )),
                  const SizedBox(height: 12),
                  Text(desc,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14, height: 1.55,
                        color: Colors.white.withValues(alpha: 0.75),
                      )),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.family_restroom_rounded,
                            size: 16, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text('Ebeveyn kontrolü etkin'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: Colors.white70,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
