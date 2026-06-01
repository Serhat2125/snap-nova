import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'lesson_3d_screen.dart';

/// 3D Eğitim Modelleri — Ders seçim ekranı.
/// Kütüphane → 3D Eğitim Modelleri kartından açılır.
/// Buradan ders seçilince ilgili dersin konu listesine gidilir.
class Edu3DSubjectsScreen extends StatelessWidget {
  const Edu3DSubjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_in_ar_rounded,
                color: Color(0xFF06B6D4), size: 22),
            const SizedBox(width: 8),
            Text(
              '3D Eğitim Modelleri',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _SubjectCard(
            icon: Icons.public_rounded,
            title: 'Coğrafya',
            color: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DCografyaScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _SubjectCard(
            icon: Icons.category_rounded,
            title: 'Geometrik Cisimler',
            color: const Color(0xFFF97316),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DGeometriScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _SubjectCard(
            icon: Icons.biotech_rounded,
            title: 'Biyoloji',
            color: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DBiyolojiScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Coğrafya dersinin 3D konu listesi.
class Edu3DCografyaScreen extends StatelessWidget {
  const Edu3DCografyaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.public_rounded,
                color: Color(0xFF0EA5E9), size: 22),
            const SizedBox(width: 8),
            Text(
              'Coğrafya',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _TopicCard(
            emoji: '🌍',
            title: 'Dünyanın Şekli ve Hareketi',
            subtitle: 'Gece-gündüz, mevsimler, Güneş sistemi',
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/dunyanin-hareketleri.html',
                  title: 'Dünyanın Şekli ve Hareketi',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🗺️',
            title: 'Yer Şekilleri ve İzohipsler',
            subtitle: 'İzohips kuralları, eğim, profil, vadi/sırt, delta, plato/ova',
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/yer-sekilleri-izohipsler.html',
                  title: 'Yer Şekilleri ve İzohipsler',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌋',
            title: 'Yerin İç Yapısı ve Levha Tektoniği',
            subtitle: 'Katmanlar, kıvrım/kırık dağlar, volkanizma, levha sınırları, depremler',
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/yerin-ic-yapisi-levha-tektonigi.html',
                  title: 'Yerin İç Yapısı ve Levha Tektoniği',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌦️',
            title: 'Atmosfer ve İklim',
            subtitle: 'Atmosfer katmanları, basınç merkezleri, Coriolis, küresel rüzgarlar',
            tint: const Color(0xFF38BDF8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/atmosfer-iklim.html',
                  title: 'Atmosfer ve İklim',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Geometrik Cisimler dersinin 3D konu listesi.
class Edu3DGeometriScreen extends StatelessWidget {
  const Edu3DGeometriScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.category_rounded,
                color: Color(0xFFF97316), size: 22),
            const SizedBox(width: 8),
            Text(
              'Geometrik Cisimler',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _TopicCard(
            emoji: '📐',
            title: 'Geometrik Cisimler ve Hesaplamalar',
            subtitle: 'Küp, prizma, silindir, koni, küre — hacim & alan',
            tint: const Color(0xFFF97316),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/geometrik-cisimler.html',
                  title: 'Geometrik Cisimler ve Hesaplamalar',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Biyoloji dersinin 3D konu listesi.
class Edu3DBiyolojiScreen extends StatelessWidget {
  const Edu3DBiyolojiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.biotech_rounded,
                color: Color(0xFF16A34A), size: 22),
            const SizedBox(width: 8),
            Text(
              'Biyoloji',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _TopicCard(
            emoji: '🧠',
            title: 'Denetleyici ve Düzenleyici Sistem',
            subtitle: 'Sinir sistemi, hormonlar, refleks',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/denetleyici-duzenleyici-sistem.html',
                  title: 'Denetleyici ve Düzenleyici Sistem',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🦴',
            title: 'Destek ve Hareket Sistemi',
            subtitle: 'Kemikler, kaslar, eklemler',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/destek-hareket-sistemi.html',
                  title: 'Destek ve Hareket Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🍽️',
            title: 'Sindirim Sistemi',
            subtitle: 'Ağız, mide, bağırsaklar, sindirim',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/sindirim-sistemi.html',
                  title: 'Sindirim Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🫀',
            title: 'Dolaşım Sistemi',
            subtitle: 'Kalp, damarlar, kan, dolaşım',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/dolasim-sistemi.html',
                  title: 'Dolaşım Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🫘',
            title: 'Boşaltım Sistemi',
            subtitle: 'Böbrek, nefron, idrar, mesane',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/bosaltim-sistemi.html',
                  title: 'Boşaltım Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🌱',
            title: 'Üreme Sistemi ve Embriyonal Gelişim',
            subtitle: 'Erkek/kadın üreme, gametler, döllenme, gebelik',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/ureme-sistemi.html',
                  title: 'Üreme Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔬',
            title: 'Hücre ve Organelleri',
            subtitle: 'Hayvan/bitki hücresi, çekirdek, mitokondri, organeller',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/hucre-organeller.html',
                  title: 'Hücre ve Organelleri',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧬',
            title: 'DNA Yapısı ve Replikasyon',
            subtitle: 'Çift sarmal, nükleotit, replikasyon, RNA, protein sentezi',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/dna-replikasyon.html',
                  title: 'DNA Yapısı ve Replikasyon',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔬',
            title: 'Mitoz ve Mayoz Bölünme',
            subtitle: 'Hücre döngüsü, mitoz/mayoz evreleri, krossing-over, gametler',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/mitoz-mayoz.html',
                  title: 'Mitoz ve Mayoz Bölünme',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌿',
            title: 'Bitki Anatomisi',
            subtitle: 'Bitkisel dokular, kök/gövde kesitleri, yaprak, stoma ve terleme',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/bitki-anatomisi.html',
                  title: 'Bitki Anatomisi',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌞',
            title: 'Fotosentez',
            subtitle: 'Kloroplast, ışık reaksiyonları, Calvin döngüsü, C3/C4/CAM',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/fotosentez.html',
                  title: 'Fotosentez',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌍',
            title: 'Ekosistem ve Besin Zinciri',
            subtitle: 'Üretici/tüketici/ayrıştırıcı, besin ağı, enerji piramidi, madde döngüleri',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/ekosistem-besin-zinciri.html',
                  title: 'Ekosistem ve Besin Zinciri',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧬',
            title: 'Kalıtım, Genotip ve Fenotip',
            subtitle: 'DNA→kromozom, Mendel yasaları, çaprazlamalar, kan grupları, X\'e bağlı kalıtım',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/kalitim-genotip-fenotip.html',
                  title: 'Kalıtım, Genotip ve Fenotip',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  const _TopicCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill,
                  color: Color(0xFFFFB627), size: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _SubjectCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppPalette.textSecondary(context)),
            ],
          ),
        ),
      ),
    );
  }
}

