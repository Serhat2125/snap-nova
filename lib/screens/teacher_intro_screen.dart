// ═══════════════════════════════════════════════════════════════════════════
//  TeacherIntroScreen — Öğretmen seviye/müfredat sayfasından sonra gösterilen
//  2 slaytlı tanıtım. Son slayttan "Panelime Git" ile TeacherShellScreen'e
//  geçer. Sınıf oluşturma burada SORULMAZ — öğretmen panelde ➕ ile açar.
//
//  Tasarım: öğrenci onboarding'indeki _FeaturePage düzeninin birebir karşılığı
//  (dairesel ikon rozeti + büyük başlık + alt yazı + numaralı açılır kartlar).
//  İçerik panelin GERÇEK yeteneklerini anlatır: sınıf yönetimi, AI ödev,
//  performans analizi, duyuru/kaynak paylaşımı.
//
//  Slaytlar:
//   1) Öğretmen Paneliniz (yetenekler)
//   2) Üç Adımda Başlayın (sınıf kodu + ödev gönder + izle)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_shell_screen.dart';

const _kPurple = Color(0xFF7C3AED);

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
            const SizedBox(height: 18),
            Expanded(
              child: PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _TeacherFeaturePage(
                    icon: Icons.space_dashboard_rounded,
                    title: 'Öğretmen Paneliniz'.tr(),
                    subtitle:
                        'Sınıflarınızı tek merkezden yönetin: ödev, takip, analiz ve iletişim.'
                            .tr(),
                    bullets: [
                      (
                        'Sınıf yönetimi'.tr(),
                        'Sınıflarınızı oluşturun; her sınıf için benzersiz bir katılım kodu otomatik üretilir. Öğrencileriniz bu kodla saniyeler içinde sınıfınıza katılır.'
                            .tr(),
                        Icons.class_rounded,
                      ),
                      (
                        'Yapay zekâ destekli ödev'.tr(),
                        'Konuyu ve soru sayısını belirleyin; müfredatınıza uygun ödev dakikalar içinde hazırlanır. Teslim tarihini belirleyip tek dokunuşla sınıfınıza gönderin.'
                            .tr(),
                        Icons.auto_awesome_rounded,
                      ),
                      (
                        'Performans analizi'.tr(),
                        'Sınıf ortalamasını, konu bazlı başarıyı ve her öğrencinin bireysel ilerlemesini canlı raporlarla takip edin.'
                            .tr(),
                        Icons.insights_rounded,
                      ),
                      (
                        'Duyuru ve kaynak paylaşımı'.tr(),
                        'Sınıflarınıza duyuru yayınlayın; ders notlarını, dokümanları ve bağlantıları güvenle paylaşın.'
                            .tr(),
                        Icons.campaign_rounded,
                      ),
                    ],
                  ),
                  _TeacherFeaturePage(
                    icon: Icons.rocket_launch_rounded,
                    title: 'Üç Adımda Başlayın'.tr(),
                    subtitle:
                        'Panele girdiğinizde ➕ butonuyla ilk sınıfınızı hemen oluşturabilirsiniz.'
                            .tr(),
                    bullets: [
                      (
                        'Sınıfınızı oluşturun'.tr(),
                        'Sınıf adını, okulu ve dersi girin; SINIF-XXXXX biçimindeki katılım kodunuz otomatik hazırlanır.'
                            .tr(),
                        null,
                      ),
                      (
                        'Kodu öğrencilerinizle paylaşın'.tr(),
                        'Kodu mesajla iletin ya da tahtaya yazın; öğrenciler kodu girerek sınıfa katılır. Dilerseniz öğrencileri panelden tek tek de davet edebilirsiniz.'
                            .tr(),
                        null,
                      ),
                      (
                        'Ödev gönderin, gelişimi izleyin'.tr(),
                        'Yapay zekâ ile ödevinizi üretin, teslim tarihini belirleyin; sonuçları ve sınıf analizini panelinizden anlık takip edin.'
                            .tr(),
                        null,
                      ),
                    ],
                  ),
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
//  _TeacherFeaturePage — öğrenci onboarding'indeki _FeaturePage düzeninin
//  öğretmen kopyası: dairesel ikon rozeti + büyük başlık + alt yazı +
//  numaralı açılır kartlar.
// ═══════════════════════════════════════════════════════════════════════════
class _TeacherFeaturePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  /// (başlık, açıklama, opsiyonel satır ikonu) — ikon null ise numara rozeti.
  final List<(String, String, IconData?)> bullets;

  const _TeacherFeaturePage({
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
          _IconBadge(icon: icon, color: _kPurple),
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
// düzeni; solda numara rozeti ya da (verildiyse) mor zeminli ikon.
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
                ? _kPurple.withValues(alpha: 0.45)
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
                      color: _kPurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Icon(widget.icon, color: _kPurple, size: 18),
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
