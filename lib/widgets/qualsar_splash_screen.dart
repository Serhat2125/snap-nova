// QuAlsarSplashScreen — iki aşamalı açılış ekranı.
//
// Tasarım:
//  • Tam BEYAZ arka plan.
//  • Faz 1 (0-1300ms): "QuAlsar" harfleri tek tek FÜTÜRİSTİK kayarak
//    gelir; sıradan harf uzaktan (yatay offset + scale + opacity) süzülür,
//    kendi yerine yerleşir. Sıralı stagger 90ms ile harfler birer birer.
//    En son tüm harfler doğru yerde birleşir.
//  • Faz 2 (1300ms+): Hemen ardından altına dönen halka logosu (disk only)
//    smooth fade ile gelir.
//  • Halka altında STATUS METNİ YOK.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'qualsar_numeric_loader.dart';

class QuAlsarSplashScreen extends StatefulWidget {
  const QuAlsarSplashScreen({super.key});

  @override
  State<QuAlsarSplashScreen> createState() => _QuAlsarSplashScreenState();
}

class _QuAlsarSplashScreenState extends State<QuAlsarSplashScreen>
    with TickerProviderStateMixin {
  // Yazı intro — toplam 1300ms; harfler 0-1100 arası sırayla yerleşir.
  late final AnimationController _intro;
  // Logo fade — harf yerleşmesi biter bitmez başlar.
  late final AnimationController _loader;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..forward();

    _loader = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // %85'te (≈1100ms) logo fade başlat — harfler son pozisyonuna yaklaşırken
    // logo da pürüzsüz girer.
    _intro.addListener(() {
      if (_intro.value >= 0.85 &&
          !_loader.isAnimating &&
          _loader.value == 0.0) {
        _loader.forward();
      }
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Logo, başlığın hemen altında — büyük Expanded yerine sabit yükseklik
    // ve mainAxisAlignment center → tüm grup üst yarıda kalır, logo yukarıda.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 140),
            _SlidingTitle(intro: _intro),
            const SizedBox(height: 18),
            FadeTransition(
              opacity: _loader,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1.0).animate(
                  CurvedAnimation(
                      parent: _loader, curve: Curves.easeOutCubic),
                ),
                child: const SizedBox(
                  height: 140,
                  child: QuAlsarNumericLoader(
                    diskOnly: true,
                    variant: QuAlsarLoaderVariant.verbal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── "QuAlsar" başlığı — tek tek harfler yatay süzülerek birleşir ─────────
class _SlidingTitle extends StatelessWidget {
  final AnimationController intro;
  const _SlidingTitle({required this.intro});

  // Tasarım: Qu — siyah, Al — kırmızı (vurgu), sar — siyah.
  // ASCII karakterler: Q, u, A, l, s, a, r → 7 harf.
  static const _letters = ['Q', 'u', 'A', 'l', 's', 'a', 'r'];
  static bool _isAccent(int i) => i == 2 || i == 3; // 'A' ve 'l'

  // Her harf belirli bir yatay offset'ten süzülür — alternatifli yönler:
  // odd index sağdan, even index soldan. Bu daha "fütüristik" hareket verir.
  static const _slideOffsets = [-160, 140, -120, 120, -100, 100, -140];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: intro,
      builder: (_, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < _letters.length; i++) _buildLetter(i),
        ],
      ),
    );
  }

  Widget _buildLetter(int i) {
    // Stagger — her harf önceki başladıktan 90ms sonra başlasın.
    // Sürede 7 harf × 90ms = 630ms gecikme + 350ms süzülme = 980ms toplam.
    final start = (i * 0.075).clamp(0.0, 0.75);
    final end = (start + 0.32).clamp(0.0, 1.0);
    final t = CurvedAnimation(
      parent: intro,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );

    final dx = Tween<double>(begin: _slideOffsets[i].toDouble(), end: 0.0)
        .animate(t);
    final scale = Tween<double>(begin: 0.6, end: 1.0).animate(t);
    final opacity = Tween<double>(begin: 0, end: 1).animate(t);

    final isAccent = _isAccent(i);

    return AnimatedBuilder(
      animation: t,
      builder: (_, __) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Opacity(
            opacity: opacity.value,
            child: Transform.translate(
              offset: Offset(dx.value, 0),
              child: Transform.scale(
                scale: scale.value,
                child: Text(
                  _letters[i],
                  style: GoogleFonts.orbitron(
                    fontSize: 60,
                    fontWeight: FontWeight.w900,
                    color: isAccent
                        ? const Color(0xFFE53935)
                        : Colors.black,
                    letterSpacing: 4,
                    height: 1.0,
                    shadows: isAccent
                        ? [
                            Shadow(
                              color: const Color(0xFFE53935)
                                  .withValues(alpha: 0.30),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
