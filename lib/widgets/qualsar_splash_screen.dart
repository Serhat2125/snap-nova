// QuAlsarSplashScreen — uygulama açılışı.
//
// Kullanıcı isteği:
//  • Uygulamaya BASILIR BASILMAZ "QuAlsar" yazısı görünsün.
//  • Yaklaşık 2 saniye sonra dönen logo (disk) altında belirsin.
//  • Uygulama tam yüklenene kadar her ikisi de ekranda kalsın.
//
// Tasarım detayları:
//  • Title kayma animasyonu KALDIRILDI — frame 0'da Text widget direkt görünür.
//    Widget tree iki kez rebuild edilse (anlık splash + sonra QuAlsarApp
//    içindeki _StartupRouter) bile yazı "kaybolup geri gelme" titremesi yapmaz.
//  • Logo görünürlüğü module-seviyesi `_appStartTime` ile takip edilir — widget
//    state'i resetlense bile, app açılışından 2sn geçtiyse logo zaten orada
//    olur. Yalnızca ilk 2sn için bir Timer.
//  • Layout MINIMUM: Center > Column(min, center). Hiçbir overflow imkansız.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'qualsar_numeric_loader.dart';

/// Uygulama process'i başladığında set edilir. Widget tree rebuild olsa bile
/// reset olmaz — splash logo'sunun "2sn sonra göründüm" durumunu korur.
final DateTime _appStartTime = DateTime.now();

/// Logo'nun ortaya çıkacağı eşik.
const Duration _logoRevealAfter = Duration(seconds: 2);

class QuAlsarSplashScreen extends StatefulWidget {
  const QuAlsarSplashScreen({super.key});

  @override
  State<QuAlsarSplashScreen> createState() => _QuAlsarSplashScreenState();
}

class _QuAlsarSplashScreenState extends State<QuAlsarSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoFade;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    _logoFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    final elapsed = DateTime.now().difference(_appStartTime);
    if (elapsed >= _logoRevealAfter) {
      // Widget tekrar mount olduğunda (örn. ikinci runApp sonrası) zaten
      // 2sn geçmişse logo'yu anında göster — fade animasyonunu replay etme.
      _logoFade.value = 1.0;
    } else {
      final remaining = _logoRevealAfter - elapsed;
      _revealTimer = Timer(remaining, () {
        if (!mounted) return;
        _logoFade.forward();
      });
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _logoFade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Material en alt katman: ErrorWidget veya başka widget'ların kırmızı
    // şeritler bırakmasına karşı beyaz zemin ve metin kontextini sağlar.
    // Align (0, -0.45): yatayda merkez, dikeyde üst yarıya doğru kaydırır —
    // başlık ve logo ekranın üst bölümünde, alt %30'da boşluk kalır.
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.45),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── QuAlsar başlığı — frame 0'da görünür, animasyonsuz ──
              // Stil: Audiowide — fütüristik ama yumuşak eğrilerle, Orbitron'a
              // göre daha karakterli ve modern. Letterspacing ile havadar.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      style: GoogleFonts.audiowide(
                        fontSize: 56,
                        fontWeight: FontWeight.w400,
                        color: Colors.black,
                        letterSpacing: 4,
                        height: 1.0,
                      ),
                      children: [
                        const TextSpan(text: 'Qu'),
                        TextSpan(
                          text: 'Al',
                          style: TextStyle(
                            color: const Color(0xFFE53935),
                            shadows: [
                              Shadow(
                                color: const Color(0xFFE53935)
                                    .withValues(alpha: 0.35),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                        ),
                        const TextSpan(text: 'sar'),
                      ],
                    ),
                  ),
                ),
              ),
              // Başlık altı küçük boşluk.
              const SizedBox(height: 14),
              // ── Alt başlık: "QuAlsar Eğitim Dünyasına Hoş Geldiniz" ──
              // FittedBox(fitWidth) + SizedBox(220): yazının genişliği TAM
              // altındaki logo diski kadar (220). Tek satır, başlangıcı/bitişi
              // logo'nun başlangıcı/bitişi ile birebir hizalı.
              SizedBox(
                width: 220,
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  child: Text(
                    'QuAlsar Eğitim Dünyasına Hoş Geldiniz',
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      letterSpacing: 0.2,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              // Alt başlık ile logo arasındaki boşluk.
              const SizedBox(height: 36),
              // ── Logo (disk) — 2 saniye sonra fade ile belirir ──
              // Önce 220×220 yer rezerve edilir; opacity 0 iken bile aynı
              // yer kaplar, böylece title konumu logo göründüğünde KAYMAZ.
              SizedBox(
                height: 220,
                width: 220,
                child: FadeTransition(
                  opacity: _logoFade,
                  child: const QuAlsarNumericLoader(
                    diskOnly: true,
                    variant: QuAlsarLoaderVariant.verbal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
