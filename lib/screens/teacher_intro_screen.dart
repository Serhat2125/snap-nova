// ═══════════════════════════════════════════════════════════════════════════
//  TeacherIntroScreen — Öğretmen seviye/müfredat sayfasından sonra gösterilen
//  2 slaytlı tanıtım. Son slayttan "Panelime Git" ile TeacherShellScreen'e
//  geçer. Sınıf oluşturma burada SORULMAZ — öğretmen panelde ➕ ile açar.
//
//  Slaytlar:
//   1) Avantajlar (AI ödev üretici, performans paneli, hatırlatma, paylaşım)
//   2) 3 adımda sınıfını çalıştır (sınıf kodu + ödev gönder + izle)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_shell_screen.dart';

class TeacherIntroScreen extends StatefulWidget {
  const TeacherIntroScreen({super.key});

  @override
  State<TeacherIntroScreen> createState() => _TeacherIntroScreenState();
}

class _TeacherIntroScreenState extends State<TeacherIntroScreen> {
  final _pc = PageController();
  int _page = 0;
  bool _saving = false;

  static const _totalPages = 2;
  static const _kPurple = Color(0xFF7C3AED);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _totalPages - 1) {
      await _pc.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    // Sınıf oluşturma burada SORULMUYOR — öğretmen panele girince ortadaki
    // ➕ ile istediği zaman sınıf açar (tanıtım sade kalsın).
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TeacherShellScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // İlerleme şeridi
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: List.generate(_totalPages, (i) {
                  final active = i <= _page;
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: EdgeInsets.only(
                          right: i == _totalPages - 1 ? 0 : 6),
                      height: 4,
                      decoration: BoxDecoration(
                        color: active
                            ? _kPurple
                            : _kPurple.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _AdvantagesSlide(ink: ink),
                  _CapabilitiesSlide(ink: ink),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : _next,
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white,
                          ),
                        )
                      : Text(
                          _page == _totalPages - 1
                              ? 'Panelime Git'.tr()
                              : 'Devam Et'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
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

// ═══════════════════════════════════════════════════════════════════════════
//  Slayt 1: Avantajlar
// ═══════════════════════════════════════════════════════════════════════════
class _AdvantagesSlide extends StatelessWidget {
  final Color ink;
  const _AdvantagesSlide({required this.ink});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 92, height: 92,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
              ),
            ),
            alignment: Alignment.center,
            child: const Text('👨‍🏫', style: TextStyle(fontSize: 44)),
          ),
          const SizedBox(height: 22),
          Text('Sınıfını dijitalde yönet'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: ink,
                height: 1.2,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 10),
          Text(
            'Öğretmen panelinde sınıf oluşturur, AI ile dakikalar içinde ödev hazırlar, öğrencilerin ilerlemesini canlı izlersin.'
                .tr(),
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: AppPalette.textSecondary(context),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          _row(context, '🤖', 'AI ödev üretici'.tr(),
              'Konu seç, sayı belirle, anında 10–30 soru hazır.'.tr()),
          _row(context, '📈', 'Performans paneli'.tr(),
              'Sınıf ortalaması, en zayıf konular, bireysel ilerleme.'.tr()),
          _row(context, '📨', 'Otomatik hatırlatma'.tr(),
              'Teslim saatine 2 saat kala bekleyen öğrencilere ping.'.tr()),
          _row(context, '📚', 'İçerik paylaşımı'.tr(),
              'Özet veya test üret, sınıf koduyla anında dağıt.'.tr()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String emoji, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    )),
                const SizedBox(height: 2),
                Text(desc,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppPalette.textSecondary(context),
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Slayt 2: Ne yapabilirsin
// ═══════════════════════════════════════════════════════════════════════════
class _CapabilitiesSlide extends StatelessWidget {
  final Color ink;
  const _CapabilitiesSlide({required this.ink});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 92, height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.class_rounded,
                color: Color(0xFF7C3AED), size: 48),
          ),
          const SizedBox(height: 22),
          Text('3 adımda sınıfını çalıştır'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: ink,
                height: 1.2,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 10),
          Text(
            'Sınıf oluşturur oluşturmaz öğrencilerinle paylaşacağın bir kod alırsın (SINIF-XXXXX). Öğrenciler kodla katılır.'
                .tr(),
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: AppPalette.textSecondary(context),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          _step(context, 1, 'Sınıf oluştur'.tr(),
              'Ad + okul + ders. SINIF-XXXXX kodu otomatik üretilir.'.tr()),
          _step(context, 2, 'Kodu paylaş'.tr(),
              'WhatsApp, e-posta veya tahtada göster — öğrenci kodu yazıp katılır.'.tr()),
          _step(context, 3, 'Ödev gönder ve izle'.tr(),
              'AI ile soru üret, teslim tarihi belirle, performansı canlı gör.'.tr()),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    color: Color(0xFF7C3AED), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AI ödev üretici tipik bir 20 soruluk testi 30 saniyede hazırlar — kıyaslayıcı raporla teslim sonrası performansı görürsün.'
                        .tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary(context),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, int n, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFF7C3AED),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text('$n',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    )),
                const SizedBox(height: 2),
                Text(desc,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppPalette.textSecondary(context),
                      height: 1.45,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
