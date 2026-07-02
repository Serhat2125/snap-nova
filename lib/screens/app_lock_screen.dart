// ═══════════════════════════════════════════════════════════════════════════════
//  AppLockScreen — Uygulama açılışında PIN/biyometrik doğrulama.
//
//  AppSettingsService.appLockEnabled = true ise main.dart bu sayfayı
//  ilk açılışta gösterir; doğrulama başarılı olunca uygulama akışı devam eder.
//
//  Akış:
//    1. Sayfa açılır → varsa biyometrik dene (parmak izi / Face ID)
//    2. Biyometrik başarısızsa PIN paneli görünür
//    3. PIN girilince AppSettingsService.verifyPin() kontrolü
//    4. 5 hatalı girişte 30 saniye lockdown
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';

import '../services/app_settings_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _settings = AppSettingsService.instance;
  final _auth = LocalAuthentication();
  String _pin = '';
  String? _error;
  int _wrongCount = 0;
  Timer? _lockoutTimer;
  int _lockoutSec = 0;

  @override
  void initState() {
    super.initState();
    // Biyometrik ayarı açıksa hemen sor
    if (_settings.appLockBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    try {
      final available = await _auth.canCheckBiometrics;
      if (!available) return;
      final ok = await _auth.authenticate(
        localizedReason:
            'QuAlsar\'a giriş için kimliğini doğrula'.tr(),
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (ok && mounted) widget.onUnlocked();
    } catch (e) {
      debugPrint('[AppLock] biometric fail: $e');
    }
  }

  void _onDigit(String d) {
    if (_lockoutSec > 0) return;
    if (_pin.length >= 6) return;
    AppSettingsService.instance.hapticSelection();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length >= 4) _checkPin();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    AppSettingsService.instance.hapticSelection();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  void _checkPin() {
    if (_settings.verifyPin(_pin)) {
      AppSettingsService.instance.hapticLight();
      widget.onUnlocked();
      return;
    }
    // Doğrulamadı — yanlış, hata sayısını artır
    _wrongCount++;
    AppSettingsService.instance.hapticHeavy();
    if (_wrongCount >= 5) {
      _startLockout();
    } else {
      setState(() {
        _pin = '';
        _error = 'PIN hatalı'.tr();
      });
    }
  }

  void _startLockout() {
    setState(() {
      _lockoutSec = 30;
      _pin = '';
      _error = '5 hatalı giriş — 30 sn bekle'.tr();
    });
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_lockoutSec <= 1) {
        t.cancel();
        if (mounted) {
          setState(() {
            _lockoutSec = 0;
            _error = null;
            _wrongCount = 0;
          });
        }
      } else {
        if (mounted) setState(() => _lockoutSec--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppPalette.bg(context),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Logo + başlık
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6A00), Color(0xFFFF8A3C)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.lock_rounded,
                    color: Colors.white, size: 38),
              ),
              const SizedBox(height: 18),
              Text(
                'QuAlsar Kilidi'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _lockoutSec > 0
                    ? '${"Bekleniyor".tr()} ($_lockoutSec sn)'
                    : 'PIN ile giriş'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: AppPalette.textSecondary(context),
                ),
              ),
              const SizedBox(height: 28),
              // 6 nokta — PIN ilerlemesi
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < 6; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length
                              ? const Color(0xFFFF6A00)
                              : AppPalette.border(context),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 18,
                child: Text(
                  _error ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: const Color(0xFFEF4444),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Tuş takımı 3x4
              _buildKeypad(),
              const Spacer(),
              if (_settings.appLockBiometric)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: TextButton.icon(
                    onPressed: _tryBiometric,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: Text('Biyometrik kullan'.tr()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    Widget key(String label, {VoidCallback? onTap, Widget? child}) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 64,
          height: 64,
          child: Material(
            color: AppPalette.cardMuted(context),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: child ??
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key('1', onTap: () => _onDigit('1')),
            key('2', onTap: () => _onDigit('2')),
            key('3', onTap: () => _onDigit('3')),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key('4', onTap: () => _onDigit('4')),
            key('5', onTap: () => _onDigit('5')),
            key('6', onTap: () => _onDigit('6')),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key('7', onTap: () => _onDigit('7')),
            key('8', onTap: () => _onDigit('8')),
            key('9', onTap: () => _onDigit('9')),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 80),
            key('0', onTap: () => _onDigit('0')),
            key('',
                onTap: _onBackspace,
                child: Icon(Icons.backspace_outlined,
                    color: AppPalette.textPrimary(context))),
          ],
        ),
      ],
    );
  }
}
