// ═══════════════════════════════════════════════════════════════════════════
//  ParentIntroScreen — Ebeveyn hesap tipi seçildikten sonra gösterilen 3
//  slaytlı tanıtım akışı. Onboarding'in 2. sayfasında Auth tamamlanır
//  tamamlanmaz pushAndRemoveUntil ile buraya gelinir. Son slayttan
//  ParentDashboardScreen'e geçer.
//
//  Slaytlar:
//   1) Faydalar (neler göreceksin)
//   2) Ne yapabilirsin (çocuk bağla, içgörü al, ödevleri takip et)
//   3) Çocuğunun eğitim seviyesi (opsiyonel — atla mümkün)
//
//  Eğitim seviyesi seçimi ebeveyn için bağlayıcı değil (çocuk kendi
//  profilinden günceller). Sadece ebeveyn dashboard'unda gösterilecek
//  varsayılan müfredatı belirler.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'parent_dashboard_screen.dart';

class ParentIntroScreen extends StatefulWidget {
  const ParentIntroScreen({super.key});

  @override
  State<ParentIntroScreen> createState() => _ParentIntroScreenState();
}

class _ParentIntroScreenState extends State<ParentIntroScreen> {
  final _pc = PageController();
  int _page = 0;
  String? _selectedLevel; // İlkokul / Ortaokul / Lise / Üniversite

  static const _totalPages = 3;
  static const _kGreen = Color(0xFF10B981);

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
    if (_selectedLevel != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('parent_child_default_level', _selectedLevel!);
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
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
            // ── İlerleme şeridi ──────────────────────────────────────
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
                            ? _kGreen
                            : _kGreen.withValues(alpha: 0.18),
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
                  _BenefitsSlide(ink: ink),
                  _CapabilitiesSlide(ink: ink),
                  _LevelSlide(
                    ink: ink,
                    selected: _selectedLevel,
                    onSelect: (v) => setState(() => _selectedLevel = v),
                  ),
                ],
              ),
            ),
            // ── Devam butonu ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _next,
                  child: Text(
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
//  Slayt 1: Faydalar
// ═══════════════════════════════════════════════════════════════════════════
class _BenefitsSlide extends StatelessWidget {
  final Color ink;
  const _BenefitsSlide({required this.ink});

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
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
            ),
            alignment: Alignment.center,
            child: const Text('👨‍👩‍👧', style: TextStyle(fontSize: 44)),
          ),
          const SizedBox(height: 22),
          Text('Çocuğunun yolculuğunda yanında ol'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: ink,
                height: 1.2,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 10),
          Text(
            'Ebeveyn panelinde çocuğun nasıl çalıştığını, neyi anladığını ve nerede takıldığını sezgisel grafiklerle görürsün.'
                .tr(),
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: AppPalette.textSecondary(context),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          _benefitRow(context, '⏱️', 'Günlük çalışma süresi'.tr(),
              'Hangi derste ne kadar odaklandı?'.tr()),
          _benefitRow(context, '📊', 'Ders bazlı başarı'.tr(),
              'Konu konu doğru/yanlış dağılımı, zaman içinde gelişim.'.tr()),
          _benefitRow(context, '📸', 'Fotoğraf soru sayısı'.tr(),
              'Kaç soru yöneltti, hangileri pratiğe döndü?'.tr()),
          _benefitRow(context, '🧠', 'AI içgörü'.tr(),
              'Yapay zeka çocuğun haftalık performansını yorumlar.'.tr()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _benefitRow(BuildContext context, String emoji, String title,
      String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
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
                Text(title.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    )),
                const SizedBox(height: 2),
                Text(desc.tr(),
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
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.link_rounded,
                color: Color(0xFF10B981), size: 48),
          ),
          const SizedBox(height: 22),
          Text('Tek dokunuşla çocuğuna bağlan'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: ink,
                height: 1.2,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 10),
          Text(
            'Çocuğun uygulamayı kullanıyorsa profilinden ebeveyn bağlantı kodunu paylaşır, paneline yazarsın — sonrası otomatik.'
                .tr(),
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: AppPalette.textSecondary(context),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          _step(context, 1,
              'Çocuk profilinden kodu üretir'.tr(),
              'Çocuğun "Profil → Ebeveyn Bağla" ekranından 6 haneli kod oluşturur.'.tr()),
          _step(context, 2,
              'Sen panelinden kodu girersin'.tr(),
              'Ebeveyn Paneli → "Çocuk Ekle" → kodu yapıştır.'.tr()),
          _step(context, 3,
              'Bağlantı kurulur, panel açılır'.tr(),
              'Tüm aktiviteler, ödevler, AI içgörüler senin için hazır.'.tr()),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.20),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.privacy_tip_rounded,
                    color: Color(0xFF10B981), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'KVKK uyumlu: yalnızca özet veriler görüntülenir, sohbet ve özel notlar korunur.'
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
              color: Color(0xFF10B981),
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
                Text(title.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    )),
                const SizedBox(height: 2),
                Text(desc.tr(),
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

// ═══════════════════════════════════════════════════════════════════════════
//  Slayt 3: Çocuğun eğitim seviyesi
// ═══════════════════════════════════════════════════════════════════════════
class _LevelSlide extends StatelessWidget {
  final Color ink;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _LevelSlide({
    required this.ink,
    required this.selected,
    required this.onSelect,
  });

  static const _levels = <(String, String, IconData)>[
    ('İlkokul', '6–10 yaş', Icons.backpack_rounded),
    ('Ortaokul', '11–13 yaş', Icons.school_rounded),
    ('Lise', '14–17 yaş', Icons.menu_book_rounded),
    ('Üniversite', '18+', Icons.workspace_premium_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 84, height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.school_outlined,
                color: Color(0xFF10B981), size: 42),
          ),
          const SizedBox(height: 22),
          Text('Çocuğunun eğitim seviyesi'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: ink,
                height: 1.2,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 8),
          Text(
            'Panelde gösterilecek varsayılan müfredatı belirler. Sonra değiştirebilirsin.'
                .tr(),
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppPalette.textSecondary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ..._levels.map((e) => _option(context, e.$1, e.$2, e.$3)),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => onSelect(''),
              child: Text(
                selected == '' || selected == null
                    ? 'Bilmiyorum / Sonra seç'.tr()
                    : 'Seçimi temizle'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary(context),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _option(BuildContext context, String title, String subtitle,
      IconData icon) {
    final isSel = selected == title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(title),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSel
                    ? const Color(0xFF10B981)
                    : AppPalette.border(context),
                width: isSel ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: const Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textPrimary(context),
                          )),
                      Text(subtitle.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: AppPalette.textSecondary(context),
                          )),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSel
                        ? const Color(0xFF10B981)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSel
                          ? const Color(0xFF10B981)
                          : AppPalette.border(context),
                      width: 1.8,
                    ),
                  ),
                  child: isSel
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
