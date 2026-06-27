// ═══════════════════════════════════════════════════════════════════════════
//  TeacherIntroScreen — Öğretmen hesap tipi seçildikten sonra gösterilen 3
//  slaytlı tanıtım akışı. Onboarding'in 2. sayfasında Auth tamamlanır
//  tamamlanmaz pushAndRemoveUntil ile buraya gelinir. Son slayttan
//  TeacherShellScreen'e geçer (opsiyonel olarak ilk sınıf oluşturur).
//
//  Slaytlar:
//   1) Avantajlar (öğretmen panelinin neyi mümkün kıldığı)
//   2) Ne yapabilirsin (sınıf oluştur, AI ödev üret, ilerlemeyi izle)
//   3) Sınıf seviyesi + ders + okul adı (opsiyonel — atla mümkün)
//
//  3. slaytta okul adı/ders verirsen "Panelime Git" basınca arka planda
//  ilk sınıf otomatik oluşturulur ve sınıf kodu hazır gelir; boş geçersen
//  sadece dashboard'a düşürür (FAB'dan sınıf eklersin).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/class_service.dart';
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

  // Slayt 3 alanları
  String? _selectedLevel; // İlkokul / Ortaokul / Lise / Üniversite
  String _subject = 'Matematik';
  final _classNameCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();

  static const _totalPages = 3;
  static const _kPurple = Color(0xFF7C3AED);

  static const _subjects = [
    'Matematik','Fizik','Kimya','Biyoloji','Geometri',
    'Tarih','Coğrafya','Edebiyat','Türkçe','İngilizce',
    'Felsefe','Din Kültürü','Genel',
  ];

  @override
  void dispose() {
    _pc.dispose();
    _classNameCtrl.dispose();
    _schoolCtrl.dispose();
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

    // Seçilen varsayılanları cache'le (dashboard'da öneri olarak kullanılır)
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedLevel != null && _selectedLevel!.isNotEmpty) {
        await prefs.setString('teacher_default_level', _selectedLevel!);
      }
      await prefs.setString('teacher_default_subject', _subject);
      if (_schoolCtrl.text.trim().isNotEmpty) {
        await prefs.setString('teacher_school_name', _schoolCtrl.text.trim());
      }
    } catch (_) {}

    // Eğer öğretmen sınıf adı + okul adı girdiyse arka planda ilk sınıfı
    // oluştur — dashboard'a düşünce kod hazır karşılar. Hata olsa bile
    // akışı bloklamaz (dashboard FAB ile manuel oluşturma alternatifi var).
    final name = _classNameCtrl.text.trim();
    final school = _schoolCtrl.text.trim();
    if (name.isNotEmpty && school.isNotEmpty) {
      try {
        await ClassService.createClass(
          name: name,
          schoolName: school,
          subject: _subject,
          level: _selectedLevel ?? 'Lise',
        );
      } catch (_) {/* sessizce devam */}
    }
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
                  _ClassSetupSlide(
                    ink: ink,
                    selectedLevel: _selectedLevel,
                    subject: _subject,
                    classNameCtrl: _classNameCtrl,
                    schoolCtrl: _schoolCtrl,
                    subjects: _subjects,
                    onLevelSelect: (v) =>
                        setState(() => _selectedLevel = v),
                    onSubjectSelect: (v) => setState(() => _subject = v),
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
          _row(context, '🤖', 'AI ödev üretici',
              'Konu seç, sayı belirle, anında 10–30 soru hazır.'),
          _row(context, '📈', 'Performans paneli',
              'Sınıf ortalaması, en zayıf konular, bireysel ilerleme.'),
          _row(context, '📨', 'Otomatik hatırlatma',
              'Teslim saatine 2 saat kala bekleyen öğrencilere ping.'),
          _row(context, '📚', 'İçerik paylaşımı',
              'Özet veya test üret, sınıf koduyla anında dağıt.'),
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
          _step(context, 1, 'Sınıf oluştur',
              'Ad + okul + ders. SINIF-XXXXX kodu otomatik üretilir.'),
          _step(context, 2, 'Kodu paylaş',
              'WhatsApp, e-posta veya tahtada göster — öğrenci kodu yazıp katılır.'),
          _step(context, 3, 'Ödev gönder ve izle',
              'AI ile soru üret, teslim tarihi belirle, performansı canlı gör.'),
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
//  Slayt 3: İlk sınıf kurulumu (opsiyonel)
// ═══════════════════════════════════════════════════════════════════════════
class _ClassSetupSlide extends StatelessWidget {
  final Color ink;
  final String? selectedLevel;
  final String subject;
  final List<String> subjects;
  final TextEditingController classNameCtrl;
  final TextEditingController schoolCtrl;
  final ValueChanged<String> onLevelSelect;
  final ValueChanged<String> onSubjectSelect;

  const _ClassSetupSlide({
    required this.ink,
    required this.selectedLevel,
    required this.subject,
    required this.subjects,
    required this.classNameCtrl,
    required this.schoolCtrl,
    required this.onLevelSelect,
    required this.onSubjectSelect,
  });

  static const _levels = <(String, IconData)>[
    ('İlkokul', Icons.backpack_rounded),
    ('Ortaokul', Icons.school_rounded),
    ('Lise', Icons.menu_book_rounded),
    ('Üniversite', Icons.workspace_premium_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76, height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add_circle_outline_rounded,
                color: Color(0xFF7C3AED), size: 40),
          ),
          const SizedBox(height: 18),
          Text('İlk sınıfını kuralım'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: ink,
                letterSpacing: -0.3,
              )),
          const SizedBox(height: 6),
          Text(
            'İstersen sınıf bilgilerini şimdi gir, kod hazır karşılasın. Atlarsan dashboard\'dan FAB ile eklersin.'
                .tr(),
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: AppPalette.textSecondary(context),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),

          // Eğitim seviyesi
          Text('Eğitim seviyesi'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
              )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _levels.map((e) {
              final sel = selectedLevel == e.$1;
              return InkWell(
                onTap: () => onLevelSelect(e.$1),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFF7C3AED)
                        : AppPalette.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel
                          ? const Color(0xFF7C3AED)
                          : AppPalette.border(context),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(e.$2,
                          size: 16,
                          color: sel
                              ? Colors.white
                              : const Color(0xFF7C3AED)),
                      const SizedBox(width: 6),
                      Text(e.$1.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: sel
                                ? Colors.white
                                : AppPalette.textPrimary(context),
                          )),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Sınıf adı
          _label(context, 'Sınıf adı (örn: 10-A)'.tr()),
          _field(context, classNameCtrl, 'Sınıf adı'.tr(),
              Icons.class_rounded),
          const SizedBox(height: 12),

          // Okul adı
          _label(context, 'Okul adı'.tr()),
          _field(context, schoolCtrl, 'Okul adı'.tr(),
              Icons.school_rounded),
          const SizedBox(height: 12),

          // Ders
          _label(context, 'Ders'.tr()),
          Container(
            decoration: BoxDecoration(
              color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border(context)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: subject,
                isExpanded: true,
                icon: Icon(Icons.expand_more_rounded,
                    color: AppPalette.textSecondary(context)),
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                ),
                items: subjects.map((o) => DropdownMenuItem(
                  value: o, child: Text(o.tr()))).toList(),
                onChanged: (v) { if (v != null) onSubjectSelect(v); },
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Tüm alanlar zorunlu değil — sadece sınıf adı + okul adı dolarsa sınıf otomatik oluşturulur.'
                  .tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppPalette.textSecondary(context),
                fontStyle: FontStyle.italic,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppPalette.textPrimary(context),
          )),
    );
  }

  Widget _field(BuildContext context, TextEditingController c,
      String hint, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: c,
        style: GoogleFonts.poppins(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppPalette.textPrimary(context),
        ),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          prefixIcon: Icon(icon,
              size: 18, color: AppPalette.textSecondary(context)),
        ),
      ),
    );
  }
}
