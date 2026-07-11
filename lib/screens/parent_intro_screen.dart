// ═══════════════════════════════════════════════════════════════════════════
//  ParentIntroScreen — Ebeveyn hesap tipi seçildikten sonra gösterilen 2
//  slaytlı tanıtım akışı. Son slayttan ParentShellScreen'e geçer.
//
//  Tasarım: öğrenci onboarding'indeki _FeaturePage düzeninin birebir karşılığı
//  (dairesel ikon rozeti + büyük başlık + alt yazı + açılır kartlar).
//  Eski 3. slayt (çocuğun eğitim seviyesi seçimi) KALDIRILDI — ebeveyn için
//  bağlayıcı değildi; seviye çocuğun kendi profilinden gelir.
//
//  Slaytlar:
//   1) Ebeveyn Paneliniz (neler görürsünüz)
//   2) Üç Adımda Bağlanın (kod üret → kodu gir → panel hazır)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'parent_shell_screen.dart';

const _kGreen = Color(0xFF10B981);

class ParentIntroScreen extends StatefulWidget {
  const ParentIntroScreen({super.key});

  @override
  State<ParentIntroScreen> createState() => _ParentIntroScreenState();
}

class _ParentIntroScreenState extends State<ParentIntroScreen> {
  final _pc = PageController();
  int _page = 0;

  static const _totalPages = 2;

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
    try {
      final prefs = await SharedPreferences.getInstance();
      // Intro'yu tamamladığını işaretle — yoksa kullanıcı slayt 1'de
      // uygulamayı kapatırsa _HomeRouter bir daha bu ekranı hiç göstermez
      // (AccountType.parent zaten kalıcı yazılmıştı) ve "çocuk nasıl
      // eklenir" anlatan tek yer bir daha asla görünmezdi.
      await prefs.setBool('parent_intro_completed', true);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ParentShellScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 18),
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _ParentFeaturePage(
                    icon: Icons.family_restroom_rounded,
                    title: 'Ebeveyn Paneliniz'.tr(),
                    subtitle:
                        'Çocuğunuzun çalışmasını ve gelişimini tek ekrandan izleyin.'
                            .tr(),
                    bullets: [
                      (
                        'Canlı takip'.tr(),
                        'Çocuğunuzun günlük çalışma süresini ve hangi derse ne kadar odaklandığını anlık görürsünüz.'
                            .tr(),
                        Icons.timer_rounded,
                      ),
                      (
                        'Başarı analizi'.tr(),
                        'Ders ve konu bazlı doğru/yanlış dağılımı, zaman içindeki gelişim grafikleri ve yapay zekânın haftalık yorumu.'
                            .tr(),
                        Icons.insights_rounded,
                      ),
                      (
                        'Ödev takibi'.tr(),
                        'Öğretmenin verdiği ödevleri, teslim durumlarını ve sonuçları panelinizden izlersiniz.'
                            .tr(),
                        Icons.assignment_turned_in_rounded,
                      ),
                      (
                        'Güvenli veri'.tr(),
                        'Yalnızca özet veriler görüntülenir; çocuğunuzun sohbetleri ve özel notları gizli kalır.'
                            .tr(),
                        Icons.verified_user_rounded,
                      ),
                    ],
                  ),
                  _ParentFeaturePage(
                    icon: Icons.link_rounded,
                    title: 'Üç Adımda Bağlanın'.tr(),
                    subtitle:
                        'Panele girdiğinizde ➕ butonuyla çocuğunuzu hemen ekleyebilirsiniz.'
                            .tr(),
                    bullets: [
                      (
                        'Çocuğunuz kod oluşturur'.tr(),
                        'Çocuğunuz kendi profilindeki "Ebeveyn Bağla" ekranından QR kod veya bağlantı kodu üretir.'
                            .tr(),
                        null,
                      ),
                      (
                        'Kodu girin veya QR okutun'.tr(),
                        'Panelinizden kodu yazın ya da kamerayla QR kodu okutun; bağlantı saniyeler içinde kurulur.'
                            .tr(),
                        null,
                      ),
                      (
                        'Panel hazır'.tr(),
                        'Çalışma süreleri, başarı grafikleri ve ödev durumu otomatik olarak panelinize gelir.'
                            .tr(),
                        null,
                      ),
                    ],
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
                      fontSize: 16,
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
//  _ParentFeaturePage — öğrenci onboarding'indeki _FeaturePage düzeninin
//  ebeveyn kopyası: dairesel ikon rozeti + büyük başlık + alt yazı +
//  açılır kartlar.
// ═══════════════════════════════════════════════════════════════════════════
class _ParentFeaturePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  /// (başlık, açıklama, opsiyonel satır ikonu) — ikon null ise numara rozeti.
  final List<(String, String, IconData?)> bullets;

  const _ParentFeaturePage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _IconBadge(icon: icon, color: _kGreen),
          const SizedBox(height: 20),
          // Uzun çevirilerde başlığı tek satıra sığdırmak için otomatik küçült.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: AppPalette.textPrimary(context),
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
              color: AppPalette.textPrimary(context),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  for (int i = 0; i < bullets.length; i++) ...[
                    _ExpandableFeatureCard(
                      number: i + 1,
                      icon: bullets[i].$3,
                      title: bullets[i].$1,
                      description: bullets[i].$2,
                    ),
                    if (i != bullets.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Dairesel ikon rozeti — onboarding'deki _SectionIconBadge ile aynı görünüm.
class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 22,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 34),
    );
  }
}

// Tıklanınca açılıp kapanan madde kartı — onboarding'deki _ExpandableBullet
// düzeni; solda numara rozeti ya da (verildiyse) yeşil zeminli ikon.
class _ExpandableFeatureCard extends StatefulWidget {
  final int number;
  final IconData? icon;
  final String title;
  final String description;
  const _ExpandableFeatureCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  State<_ExpandableFeatureCard> createState() => _ExpandableFeatureCardState();
}

class _ExpandableFeatureCardState extends State<_ExpandableFeatureCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _open
                ? _kGreen.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.08),
            width: _open ? 1.2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.icon != null)
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _kGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Icon(widget.icon, color: _kGreen, size: 18),
                  )
                else
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppPalette.textPrimary(context),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${widget.number}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.title,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppPalette.textPrimary(context),
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: AppPalette.textSecondary(context),
                    size: 22,
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(44, 8, 8, 2),
                      child: Text(
                        widget.description,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppPalette.textPrimary(context)
                              .withValues(alpha: 0.72),
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                          letterSpacing: -0.05,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
