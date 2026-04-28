import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show localeService;
import '../services/auth_service.dart';
import '../services/country_resolver.dart';
import '../services/education_profile.dart';
import '../services/gemini_service.dart';
import '../services/locale_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/qualsar_logo_mark.dart';
import 'camera_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  QuAlsar Onboarding — 4 tanıtım + 1 giriş (seviye seçimi)
//  Tüm metinler localeService.tr() üzerinden — cihaz diline göre otomatik.
//  1. Hero: marka tanıtımı
//  2. Her soruyu çöz (fotoğraftan çözüm, her ders)
//  3. Kendi kütüphaneni oluştur (özet + sınav soruları)
//  4. Sahneye çık yarış (arena, 1v1, ülke/dünya)
//  5. Seviye seçimi + "Öğrenmeye Başla" (giriş)
// ═════════════════════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// İlk açılış kontrolü için SharedPreferences anahtarı.
  static const String prefKey = 'onboarding_done_v2';

  /// Seçilen eğitim seviyesi (opsiyonel, gelecekte kişiselleştirme için).
  static const String gradePrefKey = 'user_grade_level';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  String? _selectedGrade;
  /// Multi-select: kullanıcı birden fazla seviye seçmiş olabilir.
  /// Her giriş: 'level:grade' veya 'level:faculty:grade'.
  List<String> _selectedProfiles = [];

  static const int _totalPages = 7;
  static const int _gradePageIndex = 2;
  static const int _authPageIndex = 1;

  @override
  void initState() {
    super.initState();
    // RuntimeTranslator çeviriler arka planda cache'e eklendikçe notify eder;
    // bu sayede gecikmeli gelen yeni dil metinleri tüm onboarding'de hemen
    // yansır (subject carousel, açılan maddeler, vb. dahil).
    RuntimeTranslator.instance.addListener(_onTranslationsUpdated);
  }

  void _onTranslationsUpdated() {
    if (mounted) setState(() {});
  }

  // Her sayfanın kendi vurgu rengi — kartlar ve ikonlar aynı paletten beslenir.
  // Sıra: Hero → Auth → Grade → Solve → Create → Library → Compete
  static const _accentPerPage = <Color>[
    AppColors.cyan,              // 0 Hero
    Color(0xFF2563EB),           // 1 Auth (deep blue)
    Color(0xFF22C55E),           // 2 Grade (green)
    AppColors.cyan,              // 3 Solve
    Color(0xFFA78BFA),           // 4 Create (purple)
    Color(0xFFEC4899),           // 5 Library (pink)
    Color(0xFFFF6A00),           // 6 Compete (orange)
  ];

  @override
  void dispose() {
    RuntimeTranslator.instance.removeListener(_onTranslationsUpdated);
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (_currentPage < _totalPages - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    } else {
      await _finish();
    }
  }

  Future<void> _goBack() async {
    if (_currentPage == 0) return;
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen.prefKey, true);

    // Multi-select: çoklu profil varsa onu kullan; yoksa tek seçimi kullan
    // (geriye dönük uyumluluk).
    final List<String> rawProfiles = _selectedProfiles.isNotEmpty
        ? _selectedProfiles
        : (_selectedGrade != null ? [_selectedGrade!] : <String>[]);

    if (rawProfiles.isNotEmpty) {
      // Eski "tek profil" pref'i — primary = ilk seçim.
      final primary = rawProfiles.first;
      await prefs.setString(OnboardingScreen.gradePrefKey, primary);

      // EduProfile pref'leri (eski single-profile API) — primary'yi yaz.
      final parts = primary.split(':');
      if (parts.isNotEmpty) {
        final eduLevel = _mapOnbLevelToEduProfile(parts[0]);
        await prefs.setString('mini_test_level', eduLevel);
        if (parts.length == 2) {
          await prefs.setString('mini_test_grade', parts[1]);
          await prefs.remove('mini_test_faculty');
        } else if (parts.length >= 3) {
          await prefs.setString('mini_test_faculty', parts[1]);
          await prefs.setString('mini_test_grade', parts.sublist(2).join(':'));
        }
      }

      // Yeni multi-profile pref: tüm profillerin JSON listesi.
      // Riverpod userProfilesProvider bu pref'i okur.
      final country = prefs.getString('mini_test_country') ?? 'tr';
      final List<Map<String, dynamic>> profilesJson = [];
      for (final raw in rawProfiles) {
        final p = raw.split(':');
        if (p.isEmpty) continue;
        final level = _mapOnbLevelToEduProfile(p[0]);
        String grade;
        String? faculty;
        if (p.length == 2) {
          grade = p[1];
          faculty = null;
        } else {
          faculty = p[1];
          grade = p.sublist(2).join(':');
        }
        profilesJson.add({
          'country': country,
          'level': level,
          'grade': grade,
          'faculty': faculty,
          'track': null,
          'addedAt': DateTime.now().toIso8601String(),
        });
      }
      await prefs.setString(
          'mini_test_profiles_v1', jsonEncode(profilesJson));

      // Eski cache'i tazele.
      await EduProfile.load();
      // Tüm profiller için arka planda AI müfredatlarını çek.
      for (final raw in rawProfiles) {
        final p = raw.split(':');
        if (p.isEmpty) continue;
        final level = _mapOnbLevelToEduProfile(p[0]);
        final isFaculty = p.length >= 3;
        final temp = EduProfile(
          country: country,
          level: level,
          grade: isFaculty ? p.sublist(2).join(':') : p[1],
          faculty: isFaculty ? p[1] : null,
        );
        unawaited(_prefetchAiCurriculum(temp));
      }
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  /// Profil seçildikten sonra AI'dan o profile özel ders listesini çek
  /// ve cache'le — kütüphane / arena bir sonraki yüklemede bunu gösterir.
  static Future<void> _prefetchAiCurriculum(EduProfile p) async {
    try {
      final subjects = await GeminiService.fetchProfileSubjects(p);
      if (subjects.isNotEmpty) {
        await EduProfile.saveAiSubjectCache(p, subjects);
      }
    } catch (_) {
      // Sessizce başarısız ol — fallback olarak hardcoded liste kullanılır.
    }
  }

  /// Onboarding'in level anahtarlarını EduProfile şemasına eşler.
  /// EduProfile farklı kelimeler kullanıyor (uni_prep → exam_prep,
  /// master → masters, phd → doctorate); bu fonksiyon farkı kapatır.
  static String _mapOnbLevelToEduProfile(String raw) {
    switch (raw) {
      case 'uni_prep':
      case 'post_uni_exam':
      case 'lgs_prep': // hepsi sınav slotunda — fark grade alanında
        return 'exam_prep';
      case 'master':
        return 'masters';
      case 'phd':
        return 'doctorate';
      case 'personal':
        return 'other';
      default:
        return raw; // primary, middle, high, university olduğu gibi geçer.
    }
  }

  @override
  Widget build(BuildContext context) {
    // LocaleInherited'a bağımlılık — setLocale sonrası ekran yeniden kurulur.
    final locale = LocaleInherited.of(context);
    final accent = _accentPerPage[_currentPage];
    final isGrade = _currentPage == _gradePageIndex;
    final isAuth  = _currentPage == _authPageIndex;
    final isLast = _currentPage == _totalPages - 1;
    final isHero = _currentPage == 0;
    final canContinue = (!isGrade ||
            _selectedProfiles.isNotEmpty ||
            _selectedGrade != null) &&
        (!isAuth || AuthService.isSignedIn);
    // Tüm onboarding beyaz zeminde — üst bar öğeleri koyu renkli.
    const onBg = Color(0xFF4B5563);
    final inactiveTrack = Colors.black.withValues(alpha: 0.10);
    final currentLang = LocaleService.languages.firstWhere(
      (l) => l.$4 == locale.localeCode,
      orElse: () => LocaleService.languages[1],
    );
    final currentFlag = currentLang.$1;

    return Scaffold(
      // Hero → pür beyaz; feature/grade sayfaları → soluk beyaz, böylece
      // beyaz kartlar ve çerçeveler bu zemin üzerinde öne çıkar.
      backgroundColor: isHero ? Colors.white : const Color(0xFFF2F3F5),
      body: SafeArea(
        child: Column(
          children: [
            // ── Üst bar: geri + progress + atla, altında dil chip'i ───────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: _currentPage > 0
                            ? IconButton(
                                icon: Icon(Icons.arrow_back_rounded,
                                    color: onBg, size: 22),
                                onPressed: _goBack,
                              )
                            : null,
                      ),
                      Expanded(
                        child: _ProgressBar(
                          current: _currentPage,
                          total: _totalPages,
                          color: accent,
                          inactiveColor: inactiveTrack,
                        ),
                      ),
                    ],
                  ),
                  if (isHero) ...[
                    const SizedBox(height: 8),
                    // Dil chip'i — yalnızca ilk (hero) sayfada, üstünde seçili
                    // dildeki "Dil Seçimi" etiketi ile sağa hizalı.
                    Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            localeService.tr('onb_lang_pick'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: onBg,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _LanguageChip(
                            flag: currentFlag,
                            isHero: isHero,
                            onBg: onBg,
                            onTap: () => _openLanguagePicker(locale),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Sayfalar ────────────────────────────────────────────────
            Expanded(
              // Locale değiştiğinde PageView komple yeniden kurulur —
              // böylece içerideki tüm state'ler (carousel, bullet) silinip
              // yeni dilde taze çizilir. Kaçak "eski dil" kalamaz.
              child: PageView(
                key: ValueKey('onb_pages_${locale.localeCode}'),
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  const _HeroPage(),
                  _AuthPage(
                    accent: _accentPerPage[1],
                    onAuthenticated: () async {
                      if (!mounted) return;
                      setState(() {});
                      await Future<void>.delayed(
                          const Duration(milliseconds: 350));
                      if (mounted && _currentPage == _authPageIndex) {
                        await _goNext();
                      }
                    },
                  ),
                  _GradePage(
                    accent: _accentPerPage[2],
                    selected: _selectedGrade,
                    onSelect: (g) => setState(() => _selectedGrade = g),
                    onProfilesChanged: (list) =>
                        setState(() => _selectedProfiles = list),
                  ),
                  _FeaturePage(
                    accent: _accentPerPage[3],
                    headerGraphic: _SubjectCarousel(color: _accentPerPage[3]),
                    titleKey: 'onb_solve_title',
                    subtitleKey: 'onb_solve_subtitle',
                    bulletKeys: const [
                      ('onb_solve_b1_title', 'onb_solve_b1_desc'),
                      ('onb_solve_b2_title', 'onb_solve_b2_desc'),
                      ('onb_solve_b3_title', 'onb_solve_b3_desc'),
                    ],
                  ),
                  _FeaturePage(
                    accent: _accentPerPage[4],
                    icon: Icons.psychology_rounded,
                    titleKey: 'onb_create_title',
                    subtitleKey: 'onb_create_subtitle',
                    bulletKeys: const [
                      ('onb_create_b1_title', 'onb_create_b1_desc'),
                      ('onb_create_b2_title', 'onb_create_b2_desc'),
                      ('onb_create_b3_title', 'onb_create_b3_desc'),
                    ],
                  ),
                  _FeaturePage(
                    accent: _accentPerPage[5],
                    icon: Icons.auto_stories_rounded,
                    titleKey: 'onb_library_title',
                    subtitleKey: 'onb_library_subtitle',
                    bulletKeys: const [
                      ('onb_library_b1_title', 'onb_library_b1_desc'),
                      ('onb_library_b2_title', 'onb_library_b2_desc'),
                      ('onb_library_b3_title', 'onb_library_b3_desc'),
                    ],
                  ),
                  _FeaturePage(
                    accent: _accentPerPage[6],
                    headerGraphic: _CompeteGlobeHeader(color: _accentPerPage[6]),
                    titleKey: 'onb_compete_title',
                    subtitleKey: 'onb_compete_subtitle',
                    bulletKeys: const [
                      ('onb_compete_b1_title', 'onb_compete_b1_desc'),
                      ('onb_compete_b2_title', 'onb_compete_b2_desc'),
                      ('onb_compete_b3_title', 'onb_compete_b3_desc'),
                    ],
                  ),
                ],
              ),
            ),

            // ── Alt CTA ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: _CtaButton(
                label: _ctaLabel(),
                // Son sayfa ("Ülkende ve Dünyada Yarış") → yeşil "Öğrenmeye
                // Başla". Diğer sayfalarda sayfaya özel accent kalır.
                accent: isLast ? const Color(0xFF22C55E) : accent,
                enabled: canContinue,
                onTap: () async {
                  if (!canContinue) return;
                  if (isLast) {
                    await _finish();
                  } else {
                    await _goNext();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ctaLabel() {
    if (_currentPage == 0) return localeService.tr('onb_get_started');
    // Eğitim seviyesi sayfası: "Kaydet ve Devam Et" — kullanıcı seçimini
    // saklayıp sonraki tanıtım sayfalarına devam eder.
    if (_currentPage == _gradePageIndex) {
      return localeService.tr('onb_save_continue');
    }
    // Son sayfa (Ülkende ve Dünyada Yarış): "Öğrenmeye Başla" — uygulamaya
    // gerçek giriş.
    if (_currentPage == _totalPages - 1) {
      return localeService.tr('onb_finish_cta');
    }
    return localeService.tr('onb_continue');
  }

  Future<void> _openLanguagePicker(LocaleService locale) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _LanguagePickerSheet(currentCode: locale.localeCode),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Dil seçici (üst bar chip + bottom sheet)
// ═════════════════════════════════════════════════════════════════════════════

class _LanguageChip extends StatelessWidget {
  final String flag;
  final bool isHero;
  final Color onBg;
  final VoidCallback onTap;
  const _LanguageChip({
    required this.flag,
    required this.isHero,
    required this.onBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isHero
        ? Colors.black.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.06);
    final border = isHero
        ? Colors.black.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.16);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 72,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(flag, style: const TextStyle(fontSize: 20, height: 1.0)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, color: onBg, size: 18),
          ],
        ),
      ),
    );
  }
}

// Dünya genelinde konuşucu sayısına göre sıralama (yaklaşık, 2024).
// Küçük sayı = daha kalabalık. Dil picker'da sıralama için kullanılır.
const Map<String, int> _languageSpeakerRank = {
  'en': 1, 'zh': 2, 'hi': 3, 'es': 4, 'ar': 5, 'fr': 6, 'pt': 7,
  'bn': 8, 'ru': 9, 'ur': 10, 'id': 11, 'de': 12, 'ja': 13,
  // ~125M konuşucu — Pencapça ve Marathi burada
  'pa': 14, 'ko': 15,
  'vi': 16, 'ta': 17, 'mr': 18,
  'fa': 19, 'te': 20, 'it': 21, 'sw': 22,
  // ~80M — Hausa burada
  'ha': 23, 'th': 24,
  'pl': 25, 'ms': 26, 'uk': 27, 'uz': 28, 'am': 29, 'my': 30, 'tl': 31,
  'ne': 32, 'ro': 33, 'nl': 34, 'az': 35, 'si': 36, 'km': 37, 'hu': 38,
  'el': 39, 'cs': 40, 'kk': 41, 'sr': 42, 'sv': 43, 'bg': 44, 'he': 45,
  'af': 46, 'fi': 47, 'no': 48, 'da': 49, 'sk': 50, 'hr': 51, 'mn': 52,
  'lo': 53, 'lt': 54, 'ka': 55, 'lv': 56, 'et': 57,
};

class _LanguagePickerSheet extends StatefulWidget {
  final String currentCode;
  const _LanguagePickerSheet({required this.currentCode});

  @override
  State<_LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectLanguage(
    BuildContext sheetCtx,
    LocaleService locale,
    String code,
  ) async {
    // Anında dil değişimi — statik harita (critical + generated) tüm UI'ı
    // garantiliyor. Gemini'yi beklemek yok; setLocaleChangeHook preloadAll'u
    // arka planda koşturmaya devam eder (yeni anahtarlar için fallback).
    await locale.setLocale(code);
    if (!sheetCtx.mounted) return;
    Navigator.of(sheetCtx).pop();
  }

  @override
  Widget build(BuildContext context) {
    final locale = LocaleInherited.of(context);
    final all = LocaleService.languages;
    final q = _query.toLowerCase().trim();
    final filtered = q.isEmpty
        ? all
        : all.where((l) {
            final (_, name, eng, code, _) = l;
            return name.toLowerCase().contains(q) ||
                eng.toLowerCase().contains(q) ||
                code.toLowerCase().contains(q);
          }).toList();
    // Sıralama: Türkçe sabit tepede (deneme aşamasında); sonra dünya
    // genelinde en çok konuşulan diller — en kalabalık ülkelerin dilleri önde.
    final sorted = List<(String, String, String, String, String)>.from(filtered)
      ..sort((a, b) {
        int rank(String c) {
          if (c == 'tr') return -1; // deneme: Türkçe her zaman tepede
          return _languageSpeakerRank[c] ?? 999;
        }

        return rank(a.$4).compareTo(rank(b.$4));
      });

    // Seçili dil için vurgu rengi — turuncu.
    const accent = Color(0xFFFF6A00);
    const textMain = Colors.black;
    // Sheet arkaplanı — hafif soluk (off-white), kartların saf beyazı
    // belirgin görünsün diye kontrast oluşturur.
    const sheetBg = Color(0xFFEFEFF2);
    final textMuted = Colors.black.withValues(alpha: 0.55);
    final subtleBorder = Colors.black.withValues(alpha: 0.08);

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: sheetBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: _buildSheetBody(
          scrollCtrl: scrollCtrl,
          locale: locale,
          all: all,
          sorted: sorted,
          accent: accent,
          textMain: textMain,
          textMuted: textMuted,
          subtleBorder: subtleBorder,
        ),
      ),
    );
  }

  Widget _buildSheetBody({
    required ScrollController scrollCtrl,
    required LocaleService locale,
    required List<(String, String, String, String, String)> all,
    required List<(String, String, String, String, String)> sorted,
    required Color accent,
    required Color textMain,
    required Color textMuted,
    required Color subtleBorder,
  }) {
    return Column(
          children: [
            // ── Tutamaç ─────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ── Başlık ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.language_rounded,
                      color: accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      localeService.tr('language_options'),
                      style: TextStyle(
                        color: textMain,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${all.length}',
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // ── Arama ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: subtleBorder),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: textMain, fontSize: 14),
                  cursorColor: accent,
                  decoration: InputDecoration(
                    hintText: localeService.tr('search_language'),
                    hintStyle: TextStyle(
                      color: Colors.black.withValues(alpha: 0.35),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.black.withValues(alpha: 0.45),
                      size: 20,
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.black.withValues(alpha: 0.45),
                              size: 18,
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            // ── Liste ──────────────────────────────────────────────
            Expanded(
              child: sorted.isEmpty
                  ? Center(
                      child: Text(
                        localeService.tr('no_results'),
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      itemCount: sorted.length,
                      itemBuilder: (_, i) {
                        final (flag, name, eng, code, _) = sorted[i];
                        final isSel = code == locale.localeCode;
                        return Builder(
                          builder: (itemCtx) => GestureDetector(
                            onTap: () => _selectLanguage(itemCtx, locale, code),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSel ? accent : subtleBorder,
                                  width: isSel ? 1.6 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(flag,
                                      style: const TextStyle(fontSize: 22)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            color: isSel ? accent : textMain,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          eng,
                                          style: TextStyle(
                                            color: textMuted,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSel)
                                    Icon(Icons.check_circle_rounded,
                                        color: accent, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sayfa 1 — Hero (marka tanıtımı)
// ═════════════════════════════════════════════════════════════════════════════

class _HeroPage extends StatelessWidget {
  const _HeroPage();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Logo boyutu — ekran genişliğinin %58'i, 180-260 px arası sınırlı.
        final logo = constraints.maxWidth * 0.58;
        final logoSize = logo.clamp(180.0, 260.0);
        const quAlsarHeight = 56.0;
        const welcomeHeight = 22.0;
        // Hoşgeldin yazısı QuAlsar'a yakın (hemen altında); logoya nispeten
        // daha büyük boşlukla.
        const gapTitleToWelcome = 4.0;
        const gapWelcomeToLogo = 30.0;
        const totalGap = gapTitleToWelcome + welcomeHeight + gapWelcomeToLogo;

        // Logo merkezi yukarıda — büyütülen başlık + sıkı dizilim için.
        final centerY = constraints.maxHeight * 0.40;
        final logoTop = centerY - logoSize / 2;
        final logoBottom = centerY + logoSize / 2;
        // QuAlsar yazısı: logo üstünde, hoşgeldin satırı arada.
        final quAlsarTop = logoTop - totalGap - quAlsarHeight;
        final welcomeTop = quAlsarTop + quAlsarHeight + gapTitleToWelcome;
        // Ülke etiketlerinin başlayacağı y (logonun alt kenarı + küçük pay).
        final labelsMinY = logoBottom + 8;

        return Container(
          color: Colors.white,
          child: Stack(
            children: [
              // Arkaplan — logonun altından itibaren rastgele konumlarda ülke
              // bayrağı + adı (1s yaşam, hafif dönüşle).
              Positioned.fill(child: _CountryFlagStream(minY: labelsMinY)),
              // Dönen logo — ekranın merkezine yakın.
              Positioned(
                top: logoTop,
                left: 0,
                right: 0,
                child: Center(child: QuAlsarLogoMark(size: logoSize)),
              ),
              // QuAlsar yazısı — yukarı çekildi.
              Positioned(
                top: quAlsarTop,
                left: 0,
                right: 0,
                child: const Center(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.2,
                      ),
                      children: [
                        TextSpan(
                          text: 'Qu',
                          style: TextStyle(color: Colors.black),
                        ),
                        TextSpan(
                          text: 'Al',
                          style: TextStyle(color: Color(0xFFD81B1B)),
                        ),
                        TextSpan(
                          text: 'sar',
                          style: TextStyle(color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Hoşgeldin satırı — QuAlsar yazısının hemen altında.
              Positioned(
                top: welcomeTop,
                left: 16,
                right: 16,
                child: SizedBox(
                  height: welcomeHeight,
                  child: Center(
                    child: Text(
                      localeService.tr('onb_hero_welcome'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.72),
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Arkaplan ülke akışı — rastgele konumlarda 1 saniye yaşayan bayrak + ad.
//  Logo merkez dairesi arkada olduğunda etiketler dönen logonun arkasına denk
//  gelirse logonun opak fonu onları gizler — sorun yok.
// ═════════════════════════════════════════════════════════════════════════════

class _CountryFlagStream extends StatefulWidget {
  /// Etiketlerin yerleştirileceği en üst y (genelde logonun alt kenarı).
  final double minY;
  const _CountryFlagStream({required this.minY});

  @override
  State<_CountryFlagStream> createState() => _CountryFlagStreamState();
}

class _CountryFlagStreamState extends State<_CountryFlagStream>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final List<_FlagItem> _items = [];
  int _countryIdx = 0;
  int _nextBatchAt = 0;

  // Yatayda 3 etiketli grup 3000 ms'de alttan yukarı çıkıp söner.
  // Her 1000 ms'de yeni bir grup doğar → ekranda aynı anda 3 grup görünür:
  //   biri altta yeni, biri ortada, biri yukarda sönüyor. İlk grup tam
  //   kaybolurken bir sonraki tam alttan taze olarak belirir.
  static const int _lifeMs = 3000;
  static const int _spawnIntervalMs = 1000;

  // 3 şerit — yatay konumları (ekran genişliğinin yüzdeleri).
  // Birbirine yakın, yüzde 25 aralıklı.
  static const _lanes = <double>[0.25, 0.50, 0.75];

  @override
  void initState() {
    super.initState();
    // AnimatedBuilder bu controller'a bağlı olduğu için her karede yeniden
    // çizer — setState'e ihtiyaç yok. Kare atlama/kasma riski düşer.
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _maybeSpawnBatch(int now) {
    if (now < _nextBatchAt) return;
    for (int lane = 0; lane < 3; lane++) {
      final c = _countries[(_countryIdx + lane) % _countries.length];
      _items.add(_FlagItem(
        code: c.$1,
        name: c.$2,
        lane: lane,
        birthMs: now,
      ));
    }
    _countryIdx = (_countryIdx + 3) % _countries.length;
    _nextBatchAt = now + _spawnIntervalMs;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return AnimatedBuilder(
          animation: _ticker,
          builder: (_, __) {
            final now = DateTime.now().millisecondsSinceEpoch;
            _maybeSpawnBatch(now);
            _items.removeWhere((e) => now - e.birthMs > _lifeMs);
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (final item in _items)
                  _buildItem(item, now, constraints),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildItem(_FlagItem item, int now, BoxConstraints c) {
    final life = (now - item.birthMs) / _lifeMs;
    if (life >= 1.0) return const SizedBox.shrink();
    final minY = widget.minY.clamp(0.0, c.maxHeight - 24);
    final startY = c.maxHeight - 24.0;
    final endY = minY;
    final top = startY + (endY - startY) * life;
    double opacity;
    if (life < 0.12) {
      opacity = life / 0.12;
    } else if (life < 0.70) {
      opacity = 1.0;
    } else {
      // Logoya yaklaşırken (son %30 içinde) kaybolsun.
      opacity = (1.0 - life) / 0.30;
    }
    final laneX = _lanes[item.lane] * c.maxWidth;
    return Positioned(
      left: laneX,
      top: top,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CountryFlag.fromCountryCode(
                  item.code,
                  theme: const ImageTheme(
                    width: 18,
                    height: 12,
                    shape: RoundedRectangle(2),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlagItem {
  final String code; // ISO 3166-1 alpha-2 (bayrak SVG anahtarı)
  final String name; // Ülkenin kendi dilindeki adı
  final int lane; // 0=sol, 1=orta, 2=sağ
  final int birthMs;
  _FlagItem({
    required this.code,
    required this.name,
    required this.lane,
    required this.birthMs,
  });
}

// En kalabalık ülkeler önce — yaklaşık nüfus sırasına göre (2024 verisi).
// Her giriş: (ISO alpha-2 kod, ülkenin kendi dilindeki adı).
const List<(String, String)> _countries = [
  ('IN', 'भारत'),
  ('CN', '中国'),
  ('US', 'United States'),
  ('ID', 'Indonesia'),
  ('PK', 'پاکستان'),
  ('NG', 'Nigeria'),
  ('BR', 'Brasil'),
  ('BD', 'বাংলাদেশ'),
  ('RU', 'Россия'),
  ('MX', 'México'),
  ('JP', '日本'),
  ('ET', 'ኢትዮጵያ'),
  ('PH', 'Pilipinas'),
  ('EG', 'مصر'),
  ('VN', 'Việt Nam'),
  ('IR', 'ایران'),
  ('TR', 'Türkiye'),
  ('DE', 'Deutschland'),
  ('TH', 'ไทย'),
  ('GB', 'United Kingdom'),
  ('FR', 'France'),
  ('ZA', 'South Africa'),
  ('IT', 'Italia'),
  ('KE', 'Kenya'),
  ('KR', '대한민국'),
  ('CO', 'Colombia'),
  ('ES', 'España'),
  ('AR', 'Argentina'),
  ('DZ', 'الجزائر'),
  ('IQ', 'العراق'),
  ('UA', 'Україна'),
  ('CA', 'Canada'),
  ('PL', 'Polska'),
  ('MA', 'المغرب'),
  ('UZ', 'Oʻzbekiston'),
  ('SA', 'السعودية'),
  ('PE', 'Perú'),
  ('MY', 'Malaysia'),
  ('GH', 'Ghana'),
  ('VE', 'Venezuela'),
  ('AU', 'Australia'),
  ('KZ', 'Қазақстан'),
  ('RO', 'România'),
  ('CL', 'Chile'),
  ('NL', 'Nederland'),
  ('SN', 'Sénégal'),
  ('TN', 'تونس'),
  ('BE', 'België'),
  ('CU', 'Cuba'),
  ('CZ', 'Česko'),
  ('JO', 'الأردن'),
  ('HU', 'Magyarország'),
  ('GR', 'Ελλάδα'),
  ('SE', 'Sverige'),
  ('PT', 'Portugal'),
  ('AZ', 'Azərbaycan'),
  ('AE', 'الإمارات'),
  ('AT', 'Österreich'),
  ('IL', 'ישראל'),
  ('CH', 'Schweiz'),
  ('SG', 'Singapore'),
  ('DK', 'Danmark'),
  ('FI', 'Suomi'),
  ('NO', 'Norge'),
  ('IE', 'Éire'),
  ('NZ', 'Aotearoa'),
  ('LB', 'لبنان'),
  ('KW', 'الكويت'),
  ('GE', 'საქართველო'),
  ('AM', 'Հայաստան'),
  ('QA', 'قطر'),
];

// ═════════════════════════════════════════════════════════════════════════════
//  Sayfa 2-4 — Özellik tanıtımı (3 madde + büyük ikon)
// ═════════════════════════════════════════════════════════════════════════════

class _FeaturePage extends StatelessWidget {
  final Color accent;
  final IconData? icon;
  // Opsiyonel — sağlanırsa _SectionIconBadge yerine bu widget gösterilir.
  final Widget? headerGraphic;
  final String titleKey;
  final String subtitleKey;
  // (titleKey, descKey?) — descKey null ise sadece başlık gösterilir (tıklanamaz).
  // descKey varsa kart tıklanabilir — açılıp kapanır.
  final List<(String, String?)> bulletKeys;

  const _FeaturePage({
    required this.accent,
    this.icon,
    this.headerGraphic,
    required this.titleKey,
    required this.subtitleKey,
    required this.bulletKeys,
  }) : assert(icon != null || headerGraphic != null);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Üst boşluk yok → logo ve yazısı üst bar'ın hemen altında dursun.
          headerGraphic ?? _SectionIconBadge(icon: icon!, color: accent),
          // Başlık ve altı carousel/ikona yakın dursun — daha yukarıda.
          const SizedBox(height: 20),
          // FittedBox: uzun çevirilerde başlığı tek satıra sığdırmak için
          // otomatik küçültür; kısa başlıklar 34'te kalır.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              localeService.tr(titleKey),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            localeService.tr(subtitleKey),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          // Her madde kendi beyaz kartı — başlığa basınca açıklama açılıp
          // kapanır. Uzun çevirilerde kaydırılabilir olarak kalır; sayfa
          // alt bar'a taşmaz.
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  for (int i = 0; i < bulletKeys.length; i++) ...[
                    _ExpandableBullet(
                      number: i + 1,
                      title: localeService.tr(bulletKeys[i].$1),
                      description: bulletKeys[i].$2 != null
                          ? localeService.tr(bulletKeys[i].$2!)
                          : null,
                      color: accent,
                    ),
                    if (i != bulletKeys.length - 1)
                      const SizedBox(height: 10),
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

// Tıklanabilir/açılıp kapanabilir bullet kartı. description null ise
// tıklanmaz, sadece başlık gösterilir.
class _ExpandableBullet extends StatefulWidget {
  final int number;
  final String title;
  final String? description;
  final Color color;
  const _ExpandableBullet({
    required this.number,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  State<_ExpandableBullet> createState() => _ExpandableBulletState();
}

class _ExpandableBulletState extends State<_ExpandableBullet> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final hasDesc = widget.description != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasDesc ? () => setState(() => _open = !_open) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _open
                ? widget.color.withValues(alpha: 0.45)
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Siyah dolu daire, içindeki rakam beyaz.
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.black,
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
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                if (hasDesc)
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: Colors.black.withValues(alpha: 0.55),
                      size: 22,
                    ),
                  ),
              ],
            ),
            // Açıklama — açıkken görünür; sekmenin içine sığması için küçük.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: (hasDesc && _open)
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(44, 8, 8, 2),
                      child: Text(
                        widget.description!,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.black.withValues(alpha: 0.72),
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

// ═════════════════════════════════════════════════════════════════════════════
//  Sayfa 5 — Seviye seçimi (giriş)
// ═════════════════════════════════════════════════════════════════════════════

class _GradePage extends StatefulWidget {
  final Color accent;
  final String? selected;
  final ValueChanged<String> onSelect;
  /// Multi-select: tüm eklenen profil string'lerinin tam listesi.
  /// Format her profil: 'level:grade' veya 'level:faculty:grade'.
  final ValueChanged<List<String>>? onProfilesChanged;
  const _GradePage({
    required this.accent,
    required this.selected,
    required this.onSelect,
    this.onProfilesChanged,
  });

  @override
  State<_GradePage> createState() => _GradePageState();
}

class _GradePageState extends State<_GradePage> {
  String? _level;
  String? _classKey;
  bool _levelOpen = true;
  bool _classOpen = false;
  /// Eklenen profillerin string biçiminde listesi. Her giriş: 'level:grade'
  /// veya 'level:faculty:grade'. Kullanıcı "+ Başka seviye ekle" ile birden
  /// fazla profil ekleyebilir (örn. "Lise 11" + "YKS hazırlığı").
  final List<String> _picked = [];
  // Cihazın otomatik tespit edilen ülkesi (mini_test_country pref) — sınav
  // listelerini ülkeye göre filtrelemek için. initState'te yüklenir.
  String _country = 'tr';

  /// Uyumluluk hatası — sayfa ortasında kırmızı uyarı olarak gösterilir.
  /// Snackbar yerine kullanılır; daha belirgin geri bildirim sağlar.
  String? _errorMessage;
  Timer? _errorTimer;

  void _showIncompatibilityError(String msg) {
    _errorTimer?.cancel();
    setState(() => _errorMessage = msg);
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _errorMessage = null);
    });
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final code = p.getString('mini_test_country');
      if (code != null && code.isNotEmpty) {
        setState(() => _country = code);
      }
    });
  }

  // Eğitim düzeyleri (üst sekme)
  static const _levels = <_GradeOption>[
    _GradeOption(
      key: 'primary',
      labelKey: 'onb_grade_primary',
      icon: Icons.backpack_rounded,
      color: Color(0xFF22C55E),
    ),
    _GradeOption(
      key: 'middle',
      labelKey: 'onb_grade_middle',
      icon: Icons.school_rounded,
      color: Color(0xFF3B82F6),
    ),
    _GradeOption(
      key: 'lgs_prep',
      labelKey: 'onb_grade_lgs_prep',
      icon: Icons.trending_up_rounded,
      color: Color(0xFF14B8A6),
    ),
    _GradeOption(
      key: 'high',
      labelKey: 'onb_grade_high',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFFA78BFA),
    ),
    _GradeOption(
      key: 'uni_prep',
      labelKey: 'onb_grade_uni_prep',
      icon: Icons.emoji_events_rounded,
      color: Color(0xFFF59E0B),
    ),
    _GradeOption(
      key: 'university',
      labelKey: 'onb_grade_university',
      icon: Icons.workspace_premium_rounded,
      color: Color(0xFFEC4899),
    ),
    _GradeOption(
      key: 'post_uni_exam',
      labelKey: 'onb_grade_post_uni_exam',
      icon: Icons.assignment_turned_in_rounded,
      color: Color(0xFFD946EF),
    ),
    _GradeOption(
      key: 'master',
      labelKey: 'onb_grade_master',
      icon: Icons.school_outlined,
      color: Color(0xFF8B5CF6),
    ),
    _GradeOption(
      key: 'phd',
      labelKey: 'onb_grade_phd',
      icon: Icons.workspace_premium_outlined,
      color: Color(0xFF06B6D4),
    ),
    _GradeOption(
      key: 'personal',
      labelKey: 'onb_grade_personal',
      icon: Icons.person_rounded,
      color: Color(0xFF64748B),
    ),
  ];

  // Bölüm gerektirmeyen seviyeler için sabit sınıf listesi.
  static const Map<String, List<String>> _classMap = {
    'primary':  ['1. Sınıf', '2. Sınıf', '3. Sınıf', '4. Sınıf'],
    'middle':   ['5. Sınıf', '6. Sınıf', '7. Sınıf', '8. Sınıf'],
    // Liseye Geçiş — sadece LGS hazırlığı için ayrı seviye.
    'lgs_prep': ['LGS (Liselere Geçiş Sınavı)'],
    'high':     ['9. Sınıf', '10. Sınıf', '11. Sınıf', '12. Sınıf'],
    // Sınava hazırlık — ortaokul + lise sonrası Türkiye sınavları.
    'uni_prep': [
      'LGS (Liselere Geçiş Sınavı)',
      'YKS (Yükseköğretim Kurumları Sınavı)',
      'MSÜ (Milli Savunma Üniversitesi Sınavı)',
      'KPSS Ortaöğretim',
      'DGS (Dikey Geçiş Sınavı)',
      'YDS / YÖKDİL',
      'PMYO (Polis Meslek Yüksekokulu Sınavı)',
    ],
    // Üniversite sonrası sınavlar — KPSS Lisans, ALES, TUS vb.
    'post_uni_exam': [
      'ALES',
      'KPSS Lisans',
      'YDS / YÖKDİL',
      'KPSS ÖABT',
      'TUS / DUS / EUS',
      'Hâkimlik ve Savcılık Sınavları',
      'Kaymakamlık Sınavı',
      'Sayıştay Denetçi Yardımcılığı Sınavı',
      'SMMM Sınavları',
      'İSG Sınavı',
    ],
    'personal': [],
  };

  // ─── Ülkeye göre sınav listeleri ────────────────────────────────────────
  // Anahtar: '<ülke>_<seviye>'. Ülkesi haritada yoksa international fallback.
  // Sınav adları o ülkenin kendi diliyle (endonim) — yerel öğrenci tanır.
  static const Map<String, List<String>> _examsByCountry = {
    // 🇹🇷 Türkiye
    'tr_uni_prep': [
      'LGS (Liselere Geçiş Sınavı)',
      'YKS (Yükseköğretim Kurumları Sınavı)',
      'MSÜ (Milli Savunma Üniversitesi Sınavı)',
      'KPSS Ortaöğretim',
      'DGS (Dikey Geçiş Sınavı)',
      'YDS / YÖKDİL',
      'PMYO (Polis Meslek Yüksekokulu Sınavı)',
    ],
    'tr_post_uni_exam': [
      'ALES',
      'KPSS Lisans',
      'YDS / YÖKDİL',
      'KPSS ÖABT',
      'TUS / DUS / EUS',
      'Hâkimlik ve Savcılık Sınavları',
      'Kaymakamlık Sınavı',
      'Sayıştay Denetçi Yardımcılığı Sınavı',
      'SMMM Sınavları',
      'İSG Sınavı',
    ],

    // 🇩🇪 Almanya
    'de_uni_prep': [
      'Abitur',
      'Fachhochschulreife',
      'TMS (Test für medizinische Studiengänge)',
      'TestAS (Studierfähigkeitstest)',
      'TestDaF / DSH (Deutsch)',
      'IELTS / TOEFL',
    ],
    'de_post_uni_exam': [
      'Erstes Staatsexamen (Jura / Medizin / Lehramt)',
      'Zweites Staatsexamen',
      'Steuerberaterprüfung',
      'Wirtschaftsprüfer-Examen',
      'Fachanwaltsprüfung',
      'Habilitation',
      'GMAT / GRE',
    ],

    // 🇺🇸 USA
    'us_uni_prep': [
      'SAT',
      'ACT',
      'PSAT',
      'AP Exams',
      'TOEFL / IELTS',
      'CLT',
    ],
    'us_post_uni_exam': [
      'GRE',
      'GMAT',
      'LSAT',
      'MCAT',
      'USMLE',
      'NCLEX (Nursing)',
      'Bar Exam',
      'CPA',
      'CFA',
    ],

    // 🇬🇧 UK
    'uk_uni_prep': [
      'A-Levels',
      'GCSE',
      'BMAT',
      'UCAT',
      'LNAT',
      'TSA (Oxford / Cambridge)',
      'IELTS / TOEFL',
    ],
    'uk_post_uni_exam': [
      'SQE (Solicitors Qualifying Exam)',
      'GMC PLAB',
      'ACCA',
      'CIMA',
      'CFA UK',
      'GMAT / GRE',
    ],

    // 🇫🇷 Fransa
    'fr_uni_prep': [
      'Baccalauréat',
      'Parcoursup',
      'Concours Sciences Po',
      'Concours ENS',
      'TCF / DELF / DALF (Français)',
      'IELTS / TOEFL',
    ],
    'fr_post_uni_exam': [
      'CAPES (Enseignement)',
      'Agrégation',
      'ENM (Magistrature)',
      'INSP (ex-ENA, Administration)',
      'Concours administratifs',
      'DSCG / DEC (Comptabilité)',
      'GMAT / GRE',
    ],

    // 🇯🇵 Japonya
    'jp_uni_prep': [
      '大学入学共通テスト (Daigaku Nyuugaku Kyoutsuu)',
      '個別大学入試',
      'EJU (Examination for Japanese University Admission)',
      'JLPT (日本語能力試験)',
      'TOEIC / TOEFL',
    ],
    'jp_post_uni_exam': [
      '司法試験 (Bar Exam)',
      '医師国家試験 (Medical Doctor)',
      '公認会計士 (CPA)',
      '国家公務員試験 (National Civil Servant)',
      '弁理士試験 (Patent Attorney)',
      'GMAT / GRE',
    ],

    // 🇮🇳 Hindistan
    'in_uni_prep': [
      'JEE Main',
      'JEE Advanced',
      'NEET (Medical)',
      'CUET',
      'BITSAT',
      'KVPY',
      'CLAT (Law)',
      'IELTS / TOEFL',
    ],
    'in_post_uni_exam': [
      'UPSC Civil Services',
      'GATE',
      'CAT (MBA)',
      'NEET PG',
      'AIIMS PG',
      'CA (Chartered Accountant)',
      'CS (Company Secretary)',
      'GRE / GMAT',
    ],

    // 🇧🇷 Brezilya
    'br_uni_prep': ['ENEM', 'Vestibular FUVEST', 'Vestibular UNICAMP', 'ITA', 'IME', 'Concurso Militar'],
    'br_post_uni_exam': ['OAB (Direito)', 'Concurso Magistratura', 'Residência Médica', 'CFA Brasil', 'Concurso Público (Federal)'],

    // 🇷🇺 Rusya
    'ru_uni_prep': ['ЕГЭ (Единый госэкзамен)', 'ОГЭ (Основной госэкзамен)', 'Олимпиады РСОШ', 'TORFL'],
    'ru_post_uni_exam': ['Аспирантура (вступительные)', 'Адвокатский экзамен', 'Квалификационный экзамен врачей', 'GMAT / GRE'],

    // 🇨🇳 Çin
    'cn_uni_prep': ['高考 Gaokao', '艺考 Yikao', 'HSK (汉语水平考试)', 'IELTS / TOEFL'],
    'cn_post_uni_exam': ['考研 Kaoyan (研究生入学)', '司法考试 Sifa', '注册会计师 CICPA', '公务员考试', 'GMAT / GRE'],

    // 🇰🇷 Kore
    'kr_uni_prep': ['수능 (Suneung / CSAT)', '논술', '실기시험', 'TOEIC / TOEFL'],
    'kr_post_uni_exam': ['변호사시험 (Bar)', '의사국가시험', '공인회계사 (KICPA)', '국가공무원 5급', 'GMAT / GRE'],

    // 🇮🇹 İtalya
    'it_uni_prep': ['Esame di Maturità', 'TOLC (Test Online)', 'Test Medicina', 'IMAT', 'IELTS / TOEFL'],
    'it_post_uni_exam': ['Esame di Stato Avvocato', 'Esame di Stato Medicina', 'Concorso Magistratura', 'Dottorato (concorso)', 'GMAT'],

    // 🇪🇸 İspanya
    'es_uni_prep': ['EBAU / Selectividad', 'EvAU', 'DELE (Español)', 'IELTS / TOEFL'],
    'es_post_uni_exam': ['MIR (Médicos)', 'FIR (Farmacéuticos)', 'EIR (Enfermería)', 'Oposiciones (Profesorado)', 'GMAT / GRE'],

    // 🇨🇦 Kanada
    'ca_uni_prep': ['SAT', 'ACT', 'IB Diploma', 'Provincial Exams', 'IELTS / TOEFL'],
    'ca_post_uni_exam': ['LSAT', 'MCAT', 'GRE', 'GMAT', 'CPA Canada', 'Bar Admission'],

    // 🇦🇺 Avustralya
    'au_uni_prep': ['ATAR', 'STAT', 'UCAT ANZ', 'IELTS / TOEFL', 'IB Diploma'],
    'au_post_uni_exam': ['GAMSAT', 'LAT', 'AMC (Medical)', 'CPA Australia', 'GMAT / GRE'],

    // 🇳🇱 Hollanda
    'nl_uni_prep': ['VWO Eindexamen', 'HAVO Eindexamen', 'CITO', 'IELTS / TOEFL'],
    'nl_post_uni_exam': ['BIG-toets (Medisch)', 'Beroepsopleiding Advocatuur', 'NBA (Accountancy)', 'GMAT / GRE'],

    // 🇵🇱 Polonya
    'pl_uni_prep': ['Matura', 'Egzamin ósmoklasisty', 'IELTS / TOEFL'],
    'pl_post_uni_exam': ['LEK (Lekarski Egzamin)', 'Egzamin Adwokacki / Radcowski', 'Aplikacja sędziowska', 'CFA / GMAT'],

    // 🇲🇽 Meksika
    'mx_uni_prep': ['EXANI-II', 'COMIPEMS', 'Examen UNAM', 'Examen IPN', 'TOEFL / IELTS'],
    'mx_post_uni_exam': ['EGEL (CENEVAL)', 'ENARM (Médico)', 'Examen de Oposición', 'GMAT / GRE'],

    // 🇦🇷 Arjantin
    'ar_uni_prep': ['CBC (Curso de Ingreso UBA)', 'Examen de Ingreso', 'TOEFL / IELTS'],
    'ar_post_uni_exam': ['Examen de Residencia Médica', 'Concurso Magistratura', 'GMAT / GRE'],

    // 🇮🇩 Endonezya
    'id_uni_prep': ['UTBK-SNBT', 'SNBP', 'Mandiri', 'IELTS / TOEFL'],
    'id_post_uni_exam': ['UKMPPD (Dokter)', 'PPDS (Spesialis)', 'CPNS', 'Tes ASN', 'GMAT'],

    // 🇹🇭 Tayland
    'th_uni_prep': ['TGAT', 'TPAT', 'A-Level Tayland', 'GAT/PAT'],
    'th_post_uni_exam': ['ใบประกอบวิชาชีพแพทย์', 'ผู้พิพากษา (Judges Exam)', 'GMAT / GRE'],

    // 🇻🇳 Vietnam
    'vn_uni_prep': ['Kỳ thi tốt nghiệp THPT', 'Kỳ thi Đánh giá năng lực', 'IELTS / TOEFL'],
    'vn_post_uni_exam': ['Thi công chức', 'Thi luật sư', 'CCQT chứng khoán', 'GMAT / GRE'],

    // 🇪🇬 Mısır
    'eg_uni_prep': ['الثانوية العامة', 'IGCSE / IB', 'STEP / SAT', 'TOEFL / IELTS'],
    'eg_post_uni_exam': ['امتحان النيابة العامة', 'الزمالة المصرية للأطباء', 'GMAT / GRE'],

    // 🇸🇦 Suudi Arabistan
    'sa_uni_prep': ['قياس (Qiyas QIYAS)', 'GAT (القدرات العامة)', 'تحصيلي (Tahsili)', 'STEP', 'IELTS / TOEFL'],
    'sa_post_uni_exam': ['الامتياز الطبي', 'هيئة المحامين', 'SOCPA (محاسبة)', 'GMAT / GRE'],

    // 🇮🇷 İran
    'ir_uni_prep': ['کنکور سراسری (Konkur)', 'آزمون استعداد تحصیلی'],
    'ir_post_uni_exam': ['آزمون دکتری', 'آزمون وکالت', 'آزمون پزشکی', 'GMAT / GRE'],

    // 🇵🇰 Pakistan
    'pk_uni_prep': ['MDCAT', 'ECAT', 'NTS NAT', 'SAT', 'IELTS / TOEFL'],
    'pk_post_uni_exam': ['CSS (Civil Services)', 'PMS', 'FCPS', 'CA Pakistan', 'GMAT / GRE'],

    // 🇧🇩 Bangladeş
    'bd_uni_prep': ['HSC', 'University Admission Test (DU/BUET)', 'Medical Admission', 'IELTS / TOEFL'],
    'bd_post_uni_exam': ['BCS Exam', 'Bar Council Exam', 'CA Bangladesh', 'GMAT / GRE'],

    // 🇳🇬 Nijerya
    'ng_uni_prep': ['JAMB UTME', 'WAEC SSCE', 'NECO', 'Post-UTME', 'IELTS / TOEFL'],
    'ng_post_uni_exam': ['Bar Part II (Law School)', 'NYSC', 'ICAN', 'GMAT / GRE'],

    // 🇿🇦 Güney Afrika
    'za_uni_prep': ['NSC / Matric', 'NBT', 'IELTS / TOEFL'],
    'za_post_uni_exam': ['Bar Exam (LPA)', 'HPCSA Board', 'SAICA Board (CA)', 'GMAT / GRE'],

    // 🇵🇭 Filipinler
    'ph_uni_prep': ['UPCAT', 'ACET', 'DLSUCET', 'USTET', 'TOEFL / IELTS'],
    'ph_post_uni_exam': ['Bar Examination', 'Physician Licensure', 'CPA Board', 'GMAT / GRE'],

    // 🇲🇾 Malezya
    'my_uni_prep': ['SPM', 'STPM', 'Matrikulasi', 'MUET', 'IELTS / TOEFL'],
    'my_post_uni_exam': ['CLP (Common Law)', 'Medical Qualifying Exam', 'MIA (Accountants)', 'GMAT / GRE'],

    // 🇸🇬 Singapur
    'sg_uni_prep': ['GCE A-Level', 'GCE O-Level', 'IB Diploma', 'BMAT', 'IELTS / TOEFL'],
    'sg_post_uni_exam': ['Singapore Bar Exam', 'MLE (Medicine)', 'CA Singapore', 'GMAT / GRE'],

    // 🇺🇦 Ukrayna
    'ua_uni_prep': ['НМТ (NMT)', 'ЗНО', 'IELTS / TOEFL'],
    'ua_post_uni_exam': ['Адвокатський іспит', 'Лікарський іспит', 'GMAT / GRE'],

    // 🇬🇷 Yunanistan
    'gr_uni_prep': ['Πανελλαδικές Εξετάσεις', 'IELTS / TOEFL', 'IB Diploma'],
    'gr_post_uni_exam': ['Εξετάσεις Δικηγορίας', 'ΕΣΔΥ Ιατρών', 'GMAT / GRE'],

    // 🇵🇹 Portekiz
    'pt_uni_prep': ['Exames Nacionais 12.º', 'CNA', 'IELTS / TOEFL'],
    'pt_post_uni_exam': ['Exame da Ordem dos Advogados', 'Internato Médico', 'OCC (Contabilistas)', 'GMAT'],

    // 🇸🇪 İsveç
    'se_uni_prep': ['Högskoleprovet', 'Slutbetyg', 'IELTS / TOEFL'],
    'se_post_uni_exam': ['Allmäntjänstgöring (AT-Läkare)', 'Advokatexamen', 'GMAT / GRE'],

    // 🇳🇴 Norveç
    'no_uni_prep': ['Generell studiekompetanse', 'Forkurs', 'IELTS / TOEFL'],
    'no_post_uni_exam': ['Turnustjeneste (lege)', 'Advokateksamen', 'GMAT / GRE'],

    // 🇩🇰 Danimarka
    'dk_uni_prep': ['Studentereksamen', 'HF-eksamen', 'KOT', 'IELTS / TOEFL'],
    'dk_post_uni_exam': ['Klinisk basisuddannelse', 'Advokatfuldmægtigeksamen', 'GMAT / GRE'],

    // 🇫🇮 Finlandiya
    'fi_uni_prep': ['Ylioppilastutkinto', 'Pääsykoe (Üniv. giriş)', 'IELTS / TOEFL'],
    'fi_post_uni_exam': ['Lääkärin laillistaminen', 'Asianajajakoe', 'GMAT / GRE'],

    // 🇨🇿 Çekya
    'cz_uni_prep': ['Maturita', 'NSZ Scio', 'IELTS / TOEFL'],
    'cz_post_uni_exam': ['Advokátní zkouška', 'Atestační zkouška (Lékaři)', 'GMAT'],

    // 🇭🇺 Macaristan
    'hu_uni_prep': ['Érettségi', 'Felvételi', 'IELTS / TOEFL'],
    'hu_post_uni_exam': ['Szakvizsga (Orvosi)', 'Jogi szakvizsga', 'GMAT / GRE'],

    // 🇷🇴 Romanya
    'ro_uni_prep': ['Bacalaureat', 'Admiterea la facultate', 'IELTS / TOEFL'],
    'ro_post_uni_exam': ['Examen Definitivat (Profesori)', 'Examen Rezidențiat', 'Examen INM (Magistratură)', 'GMAT'],

    // 🇮🇱 İsrail
    'il_uni_prep': ['בגרות (Bagrut)', 'פסיכומטרי (Psychometric)', 'IELTS / TOEFL'],
    'il_post_uni_exam': ['בחינת לשכת עורכי הדין', 'בחינת רישוי לרופאים', 'GMAT / GRE'],

    // 🇹🇼 Tayvan
    'tw_uni_prep': ['學測 GSAT', '指考/分科測驗', 'TOEIC / TOEFL'],
    'tw_post_uni_exam': ['律師高考', '醫師國考', '會計師考試', 'GMAT / GRE'],

    // 🇭🇰 Hong Kong
    'hk_uni_prep': ['HKDSE', 'IB Diploma', 'GCE A-Level', 'IELTS / TOEFL'],
    'hk_post_uni_exam': ['PCLL', 'Hong Kong Bar', 'HKICPA', 'GMAT / GRE'],

    // 🇦🇪 BAE
    'ae_uni_prep': ['EmSAT', 'IELTS / TOEFL', 'SAT', 'Tawjihiya'],
    'ae_post_uni_exam': ['DHA / MOH Licensing', 'Bar (UAE)', 'GMAT / GRE'],

    // 🇲🇦 Fas
    'ma_uni_prep': ['Baccalauréat marocain', 'Concours Médecine', 'Concours Ingénieurs', 'TCF / DELF'],
    'ma_post_uni_exam': ['Concours Magistrature', 'Examen Avocats', 'Internat Médecine', 'GMAT'],

    // 🇩🇿 Cezayir
    'dz_uni_prep': ['Baccalauréat algérien', 'Concours Médecine', 'TCF'],
    'dz_post_uni_exam': ['Concours Résidanat', 'Examen Magistrature', 'CAPA', 'GMAT'],

    // 🇰🇪 Kenya
    'ke_uni_prep': ['KCSE', 'KCPE', 'IELTS / TOEFL', 'SAT'],
    'ke_post_uni_exam': ['Kenya Bar (KSL)', 'CPA Kenya', 'GMAT / GRE'],

    // 🇰🇿 Kazakistan
    'kz_uni_prep': ['ҰБТ (UNT)', 'KAZTEST', 'IELTS / TOEFL'],
    'kz_post_uni_exam': ['Аттестация врачей', 'Адвокатский экзамен', 'GMAT / GRE'],

    // 🇺🇿 Özbekistan
    'uz_uni_prep': ['DTM (Davlat test)', 'IELTS / TOEFL'],
    'uz_post_uni_exam': ['Advokatlik imtihoni', 'Tabobat sertifikati', 'GMAT'],

    // ───────── LATİN AMERİKA ─────────
    'co_uni_prep': ['ICFES Saber 11', 'Saber Pro', 'Examen Universidad Nacional', 'IELTS / TOEFL'],
    'co_post_uni_exam': ['Examen del Estado (Médicos)', 'Examen Notarial', 'GMAT / GRE'],
    'cl_uni_prep': ['PAES (Prueba de Acceso)', 'PSU', 'TOEFL / IELTS'],
    'cl_post_uni_exam': ['EUNACOM (Médicos)', 'Examen de Grado', 'GMAT / GRE'],
    'pe_uni_prep': ['Examen de Admisión UNI / SAN MARCOS', 'CEPRE', 'IELTS / TOEFL'],
    'pe_post_uni_exam': ['ENAM (Médicos)', 'Examen Colegiatura', 'GMAT / GRE'],
    'ec_uni_prep': ['EAES', 'Examen de Admisión', 'IELTS / TOEFL'],
    'ec_post_uni_exam': ['Examen Habilitante (Médicos)', 'Examen Abogados', 'GMAT'],
    'bo_uni_prep': ['Examen de Suficiencia Académica', 'PSA', 'IELTS / TOEFL'],
    'bo_post_uni_exam': ['Examen de Egreso', 'Colegiatura Médica', 'GMAT'],
    've_uni_prep': ['Prueba de Aptitud Académica', 'OPSU', 'IELTS / TOEFL'],
    've_post_uni_exam': ['Examen de Habilitación Médica', 'Examen Notarial', 'GMAT'],
    'uy_uni_prep': ['Bachillerato', 'Examen de Ingreso UDELAR', 'IELTS / TOEFL'],
    'uy_post_uni_exam': ['Reválida Médica', 'Examen Notarial', 'GMAT'],
    'pa_uni_prep': ['Bachillerato', 'PCC (Prueba Capacidades)', 'IELTS / TOEFL'],
    'pa_post_uni_exam': ['Examen de Idoneidad Médica', 'Examen Notarial', 'GMAT'],
    'cr_uni_prep': ['Bachillerato por Madurez', 'PAA UCR', 'IELTS / TOEFL'],
    'cr_post_uni_exam': ['Examen Colegiatura Médica', 'Examen Notarial', 'GMAT'],
    'gt_uni_prep': ['Graduación / Bachillerato', 'Pruebas USAC', 'IELTS / TOEFL'],
    'gt_post_uni_exam': ['Examen Privado', 'Colegiatura Médica', 'GMAT'],
    'hn_uni_prep': ['PAA Bachillerato', 'PAEM', 'IELTS / TOEFL'],
    'hn_post_uni_exam': ['Examen de Tesis', 'Colegio Médico Examen', 'GMAT'],
    'sv_uni_prep': ['PAES', 'AVANZO', 'IELTS / TOEFL'],
    'sv_post_uni_exam': ['Examen Privado', 'Colegio Médico Examen', 'GMAT'],
    'ni_uni_prep': ['Bachillerato Nacional', 'Examen de Admisión UNAN', 'IELTS / TOEFL'],
    'ni_post_uni_exam': ['Examen de Servicio Social Médico', 'Reválida', 'GMAT'],
    'do_uni_prep': ['Pruebas Nacionales', 'POMA UASD', 'IELTS / TOEFL'],
    'do_post_uni_exam': ['Examen de Pasantía Médica', 'CONESCYT', 'GMAT / GRE'],
    'cu_uni_prep': ['Examen de Ingreso a la Educación Superior', 'Examen Estatal'],
    'cu_post_uni_exam': ['Examen Estatal Médico', 'Especialidades', 'GMAT'],
    'jm_uni_prep': ['CSEC', 'CAPE', 'IELTS / TOEFL'],
    'jm_post_uni_exam': ['Caribbean Bar Exam', 'CMB Medical', 'GMAT / GRE'],

    // ───────── BALKAN / DOĞU AVRUPA ─────────
    'bg_uni_prep': ['ДЗИ (Държавни зрелостни)', 'Кандидат-студентски изпит', 'IELTS / TOEFL'],
    'bg_post_uni_exam': ['Изпит за адвокат', 'Държавен изпит по медицина', 'GMAT / GRE'],
    'rs_uni_prep': ['Velika matura', 'Prijemni ispit', 'IELTS / TOEFL'],
    'rs_post_uni_exam': ['Pravosudni ispit', 'Lekarski stručni ispit', 'GMAT'],
    'hr_uni_prep': ['Državna matura', 'IELTS / TOEFL'],
    'hr_post_uni_exam': ['Pravosudni ispit', 'Stručni ispit liječnika', 'GMAT'],
    'ba_uni_prep': ['Mala matura', 'Velika matura', 'IELTS / TOEFL'],
    'ba_post_uni_exam': ['Pravosudni ispit', 'Lekarski ispit', 'GMAT'],
    'xk_uni_prep': ['Matura Shtetërore', 'Provimi pranues', 'IELTS / TOEFL'],
    'xk_post_uni_exam': ['Provimi i Jurispudencës', 'Specializimi mjekësor', 'GMAT'],
    'mk_uni_prep': ['Државна матура', 'Матура / Matura', 'IELTS / TOEFL'],
    'mk_post_uni_exam': ['Правосуден испит', 'Лекарски испит', 'GMAT'],
    'al_uni_prep': ['Matura Shtetërore', 'IELTS / TOEFL'],
    'al_post_uni_exam': ['Provimi i Jurispudencës', 'Provimi i Mjekut', 'GMAT'],
    'me_uni_prep': ['Matura', 'Prijemni ispit', 'IELTS / TOEFL'],
    'me_post_uni_exam': ['Pravosudni ispit', 'Stručni ispit', 'GMAT'],
    'si_uni_prep': ['Splošna matura', 'Poklicna matura', 'IELTS / TOEFL'],
    'si_post_uni_exam': ['Pravniški državni izpit', 'Strokovni izpit zdravnikov', 'GMAT'],
    'sk_uni_prep': ['Maturita', 'Prijímacie skúšky', 'IELTS / TOEFL'],
    'sk_post_uni_exam': ['Advokátska skúška', 'Atestácia lekárov', 'GMAT'],
    'by_uni_prep': ['ЦТ (Централизованное тестирование)', 'IELTS / TOEFL'],
    'by_post_uni_exam': ['Адвокатский экзамен', 'Атестация врачей', 'GMAT'],
    'md_uni_prep': ['Bacalaureat', 'IELTS / TOEFL'],
    'md_post_uni_exam': ['Examen de Licență Avocat', 'Rezidențiat Medical', 'GMAT'],
    'ge_uni_prep': ['ერთიანი ეროვნული გამოცდები (Erovnuli)', 'IELTS / TOEFL'],
    'ge_post_uni_exam': ['ადვოკატის საკვალიფიკაციო გამოცდა', 'სარეზიდენტო', 'GMAT'],
    'am_uni_prep': ['Միասնական ընդունելության քննություններ', 'IELTS / TOEFL'],
    'am_post_uni_exam': ['Փաստաբանի որակավորման քննություն', 'Բժշկական լիցենզիա', 'GMAT'],
    'az_uni_prep': ['Buraxılış İmtahanı', 'TQDK / DİM', 'IELTS / TOEFL'],
    'az_post_uni_exam': ['Vəkillik imtahanı', 'Həkimlik sertifikatı', 'GMAT'],

    // ───────── BALTIK / İSKANDİNAV ─────────
    'ee_uni_prep': ['Riigieksamid', 'IELTS / TOEFL'],
    'ee_post_uni_exam': ['Advokaadieksam', 'Arsti pädevuseksam', 'GMAT'],
    'lv_uni_prep': ['Centralizētie eksāmeni', 'IELTS / TOEFL'],
    'lv_post_uni_exam': ['Advokāta eksāmens', 'Ārsta sertifikācija', 'GMAT'],
    'lt_uni_prep': ['Brandos egzaminas', 'IELTS / TOEFL'],
    'lt_post_uni_exam': ['Advokato kvalifikacinis', 'Gydytojo licencijavimas', 'GMAT'],
    'is_uni_prep': ['Stúdentspróf', 'IELTS / TOEFL'],
    'is_post_uni_exam': ['Lögmannspróf', 'Lækningaleyfi', 'GMAT'],

    // ───────── BATI AVRUPA ─────────
    'ie_uni_prep': ['Leaving Certificate', 'HPAT', 'IELTS / TOEFL'],
    'ie_post_uni_exam': ['Bar Exam (King\'s Inns)', 'Solicitor (Law Society)', 'GMAT / GRE'],
    'be_uni_prep': ['CESS / Diplôme d\'humanité', 'TOSS', 'Bac', 'IELTS / TOEFL'],
    'be_post_uni_exam': ['Examen d\'avocat', 'Examen de spécialisation médicale', 'GMAT'],
    'at_uni_prep': ['Matura / Reifeprüfung', 'MedAT', 'IELTS / TOEFL'],
    'at_post_uni_exam': ['Rechtsanwaltsprüfung', 'Arzt für Allgemeinmedizin', 'GMAT'],
    'ch_uni_prep': ['Matura / Maturité / Maturità', 'EMS (Eignungstest Medizin)', 'IELTS / TOEFL'],
    'ch_post_uni_exam': ['Anwaltsprüfung', 'Eidg. Facharztprüfung', 'GMAT'],
    'lu_uni_prep': ['Diplôme de fin d\'études secondaires (Bac)', 'IELTS / TOEFL'],
    'lu_post_uni_exam': ['Examen Barreau', 'Examen Médecin', 'GMAT'],
    'mc_uni_prep': ['Baccalauréat français', 'IELTS / TOEFL'],
    'mc_post_uni_exam': ['CRFPA (Avocats)', 'Internat Médical', 'GMAT'],
    'mt_uni_prep': ['MATSEC', 'IELTS / TOEFL'],
    'mt_post_uni_exam': ['Bar Exam Malta', 'Medical Council Exam', 'GMAT'],
    'cy_uni_prep': ['Παγκύπριες Εξετάσεις', 'IELTS / TOEFL'],
    'cy_post_uni_exam': ['Cyprus Bar', 'Cyprus Medical Council', 'GMAT'],

    // ───────── ORTA DOĞU ─────────
    'iq_uni_prep': ['الامتحان الوزاري (Baccalaureate)', 'IELTS / TOEFL'],
    'iq_post_uni_exam': ['نقابة المحامين العراقية', 'البورد العراقي للأطباء', 'GMAT'],
    'jo_uni_prep': ['التوجيهي (Tawjihi)', 'IELTS / TOEFL'],
    'jo_post_uni_exam': ['نقابة المحامين الأردنيين', 'البورد الأردني الطبي', 'GMAT'],
    'lb_uni_prep': ['Brevet libanais', 'Baccalauréat libanais', 'TOEFL / IELTS'],
    'lb_post_uni_exam': ['نقابة المحامين', 'الكولوكيوم الطبي', 'GMAT'],
    'sy_uni_prep': ['الشهادة الثانوية (Bakaloria)', 'IELTS / TOEFL'],
    'sy_post_uni_exam': ['نقابة المحامين السوريين', 'البورد الطبي السوري', 'GMAT'],
    'om_uni_prep': ['دبلوم التعليم العام', 'EmSAT / IELTS', 'TOEFL'],
    'om_post_uni_exam': ['نقابة المحامين العمانية', 'OMSB Medical Board', 'GMAT'],
    'qa_uni_prep': ['الثانوية العامة (Sanawiya)', 'IGCSE', 'IELTS / TOEFL'],
    'qa_post_uni_exam': ['QCHP Medical', 'Qatar Bar Exam', 'GMAT / GRE'],
    'bh_uni_prep': ['الثانوية العامة', 'IELTS / TOEFL'],
    'bh_post_uni_exam': ['NHRA Medical', 'Bar Exam Bahrain', 'GMAT'],
    'kw_uni_prep': ['الثانوية العامة', 'IELTS / TOEFL'],
    'kw_post_uni_exam': ['نقابة المحامين الكويتية', 'KIMS Medical Board', 'GMAT'],
    'ye_uni_prep': ['الثانوية العامة', 'IELTS / TOEFL'],
    'ye_post_uni_exam': ['نقابة المحامين اليمنية', 'البورد اليمني للأطباء', 'GMAT'],
    'ps_uni_prep': ['التوجيهي الفلسطيني', 'IELTS / TOEFL'],
    'ps_post_uni_exam': ['نقابة المحامين الفلسطينيين', 'المجلس الطبي الفلسطيني', 'GMAT'],

    // ───────── KUZEY AFRİKA ─────────
    'ly_uni_prep': ['الشهادة الثانوية العامة الليبية', 'IELTS / TOEFL'],
    'ly_post_uni_exam': ['نقابة المحامين الليبية', 'الكلية الطبية الليبية', 'GMAT'],
    'sd_uni_prep': ['الشهادة السودانية للتعليم الثانوي', 'IELTS / TOEFL'],
    'sd_post_uni_exam': ['نقابة المحامين السودانيين', 'البورد السوداني الطبي', 'GMAT'],
    'tn_uni_prep': ['Baccalauréat tunisien', 'IELTS / TOEFL'],
    'tn_post_uni_exam': ['CAPA (Avocats)', 'Concours Résidanat Médical', 'GMAT'],

    // ───────── SUB-SAHARA AFRİKA ─────────
    'gh_uni_prep': ['WASSCE', 'BECE', 'TOEFL / IELTS'],
    'gh_post_uni_exam': ['Ghana Bar Examination', 'Ghana Medical and Dental Council', 'GMAT / GRE'],
    'et_uni_prep': ['Ethiopian Higher Education Entrance Exam (EHEECE)', 'IELTS / TOEFL'],
    'et_post_uni_exam': ['Ethiopian Bar Exam', 'EMA Medical Licensing', 'GMAT'],
    'tz_uni_prep': ['CSEE (Form 4)', 'ACSEE (Form 6)', 'TOEFL / IELTS'],
    'tz_post_uni_exam': ['Tanganyika Law Society', 'Medical Council of Tanganyika', 'GMAT'],
    'ug_uni_prep': ['UCE (O Level)', 'UACE (A Level)', 'TOEFL / IELTS'],
    'ug_post_uni_exam': ['Uganda Law Council', 'Uganda Medical Council', 'GMAT'],
    'zm_uni_prep': ['Grade 12 Examinations', 'TOEFL / IELTS'],
    'zm_post_uni_exam': ['Zambia Bar Exam', 'HPCZ Medical', 'GMAT'],
    'zw_uni_prep': ['ZIMSEC O Level', 'ZIMSEC A Level', 'TOEFL / IELTS'],
    'zw_post_uni_exam': ['Council for Legal Education', 'MDPC Zimbabwe', 'GMAT'],
    'mz_uni_prep': ['Exame Final 12.ª Classe', 'IELTS / TOEFL'],
    'mz_post_uni_exam': ['Ordem dos Advogados', 'Ordem Médica', 'GMAT'],
    'mg_uni_prep': ['Baccalauréat malgache', 'IELTS / TOEFL'],
    'mg_post_uni_exam': ['Ordre des Avocats', 'Ordre des Médecins', 'GMAT'],
    'ao_uni_prep': ['Exame Final 12.ª Classe', 'TOEFL / IELTS'],
    'ao_post_uni_exam': ['Ordem dos Advogados', 'Ordem Médica de Angola', 'GMAT'],
    'cd_uni_prep': ['Examen d\'État', 'Bac d\'État', 'IELTS / TOEFL'],
    'cd_post_uni_exam': ['Barreau RDC', 'Conseil Médical', 'GMAT'],
    'cm_uni_prep': ['Probatoire', 'Baccalauréat', 'GCE A/O Level', 'IELTS / TOEFL'],
    'cm_post_uni_exam': ['CAPA', 'Internat Médical', 'GMAT'],

    // ───────── GÜNEY ASYA ─────────
    'np_uni_prep': ['SEE (Class 10)', 'NEB Class 12', 'CMAT', 'IELTS / TOEFL'],
    'np_post_uni_exam': ['Nepal Bar Council', 'NMC Medical Licensing', 'GMAT / GRE'],
    'lk_uni_prep': ['GCE A-Level Sri Lanka', 'GCE O-Level Sri Lanka', 'IELTS / TOEFL'],
    'lk_post_uni_exam': ['Sri Lanka Bar Examination', 'SLMC Medical', 'GMAT'],
    'mm_uni_prep': ['Matriculation Examination', 'University Entrance', 'IELTS / TOEFL'],
    'mm_post_uni_exam': ['Myanmar Bar Council', 'MMC Medical', 'GMAT'],

    // ───────── ORTA ASYA / DOĞU ASYA ─────────
    'tj_uni_prep': ['ТТМТ (Markazi Test)', 'IELTS / TOEFL'],
    'tj_post_uni_exam': ['Tahsili Vakolat', 'Tabobat sertifikati', 'GMAT'],
    'tm_uni_prep': ['Yokarry okuw mekdebiniň giriş synaglary', 'IELTS / TOEFL'],
    'tm_post_uni_exam': ['Adwokat sertifikaty', 'Lukman sertifikaty', 'GMAT'],
    'kg_uni_prep': ['ОРТ (Общереспубликанское тестирование)', 'IELTS / TOEFL'],
    'kg_post_uni_exam': ['Адвокатский экзамен', 'Аттестация врачей', 'GMAT'],
    'mn_uni_prep': ['ЭЕШ (Элсэлтийн ерөнхий шалгалт)', 'IELTS / TOEFL'],
    'mn_post_uni_exam': ['Хуульчийн шалгалт', 'Эмчийн зөвшөөрөл', 'GMAT'],
    'kp_uni_prep': ['대학입학시험 (DPRK Üniv. Giriş)', 'TOEFL / IELTS'],
    'kp_post_uni_exam': ['변호사시험', '의사면허', 'GMAT'],

    // ───────── GÜNEY-DOĞU ASYA ─────────
    'la_uni_prep': ['ການສອບເສັງມັດທະຍົມຕອນປາຍ', 'IELTS / TOEFL'],
    'la_post_uni_exam': ['Lao Bar Council', 'Lao Medical Council', 'GMAT'],
    'kh_uni_prep': ['Bac II Cambodia', 'IELTS / TOEFL'],
    'kh_post_uni_exam': ['Cambodia Bar Examination', 'Cambodia Medical Council', 'GMAT'],

    // ───────── PASİFİK ─────────
    'nz_uni_prep': ['NCEA Level 3', 'University Entrance', 'IELTS / TOEFL'],
    'nz_post_uni_exam': ['Bar Practising Certificate', 'NZREX (Medical)', 'GMAT'],

    // ───────── DİĞER ─────────
    'af_uni_prep': ['کانکور (Kankor)', 'IELTS / TOEFL'],
    'af_post_uni_exam': ['Stage Vakil', 'Sehat Mubaraka Medical', 'GMAT'],

    // 🌐 International — diğer tüm ülkeler için yaygın uluslararası sınavlar
    'international_uni_prep': [
      'SAT',
      'ACT',
      'IELTS',
      'TOEFL',
      'IB Diploma',
    ],
    'international_post_uni_exam': [
      'GRE',
      'GMAT',
      'IELTS Academic',
      'TOEFL',
      'CFA',
      'PMP',
    ],
  };

  // Bölüm seçimi gerektiren seviyeler.
  static bool _needsDept(String level) =>
      level == 'university' || level == 'master' || level == 'phd';

  // Lisans (Üniversite) için bölüm bazlı eğitim süresi (yıl).
  // Türkiye'deki yaygın programlara göre.
  static const Map<String, int> _bachelorYears = {
    'Tıp': 6,
    'Diş Hekimliği': 5,
    'Eczacılık': 5,
    'Veterinerlik': 5,
    'İnşaat Mühendisliği': 5,
  };
  static const int _bachelorDefaultYears = 4;
  // Yüksek Lisans: tezli max 3 yıl (tez uzatması dahil).
  static const int _masterYears = 3;
  // Doktora: ortalama 4-6 yıl, tez süresiyle 6'ya kadar.
  static const int _phdYears = 6;

  int _yearsFor(String level, String? dept) {
    if (level == 'master') return _masterYears;
    if (level == 'phd') return _phdYears;
    // university:
    if (dept == null) return _bachelorDefaultYears;
    return _bachelorYears[dept] ?? _bachelorDefaultYears;
  }

  List<String> _classesFor(String level, String? dept) {
    if (_needsDept(level)) {
      final n = _yearsFor(level, dept);
      return List.generate(n, (i) => '${i + 1}. Sınıf');
    }
    // Sınav hazırlık seviyeleri ülkeye göre değişir.
    if (level == 'uni_prep' || level == 'post_uni_exam') {
      final byCountry = _examsByCountry['${_country}_$level'];
      if (byCountry != null) return byCountry;
      // Detaylı katalog yoksa international sınavlar.
      return _examsByCountry['international_$level'] ?? const [];
    }
    return _classMap[level] ?? const [];
  }

  // En yaygın olanlar başta — alfabetik değil, popülerlik sırası.
  static const _departments = <String>[
    'Tıp', 'Hukuk', 'Bilgisayar Mühendisliği', 'Endüstri Mühendisliği',
    'Elektrik-Elektronik Mühendisliği', 'Makine Mühendisliği',
    'İnşaat Mühendisliği', 'Yazılım Mühendisliği', 'İşletme', 'İktisat',
    'Psikoloji', 'Mimarlık', 'Eczacılık', 'Diş Hekimliği', 'Veterinerlik',
    'Hemşirelik', 'Fizyoterapi ve Rehabilitasyon', 'Beslenme ve Diyetetik',
    'Sınıf Öğretmenliği', 'Matematik Öğretmenliği', 'Fen Bilgisi Öğretmenliği',
    'İngilizce Öğretmenliği', 'Türkçe Öğretmenliği',
    'Rehberlik ve Psikolojik Danışmanlık',
    'Endüstri Tasarımı', 'Grafik Tasarım', 'İç Mimarlık',
    'Türk Dili ve Edebiyatı', 'İngiliz Dili ve Edebiyatı',
    'Tarih', 'Coğrafya', 'Felsefe', 'Sosyoloji', 'Antropoloji', 'Arkeoloji',
    'Siyaset Bilimi', 'Uluslararası İlişkiler', 'Halkla İlişkiler',
    'İletişim', 'Gazetecilik', 'Reklamcılık', 'Radyo Televizyon ve Sinema',
    'Bankacılık ve Finans', 'Muhasebe ve Finans', 'Maliye',
    'Pazarlama', 'Lojistik Yönetimi', 'Uluslararası Ticaret',
    'Yönetim Bilişim Sistemleri',
    'Matematik', 'Fizik', 'Kimya', 'Biyoloji', 'İstatistik',
    'Moleküler Biyoloji ve Genetik', 'Biyokimya',
    'Kimya Mühendisliği', 'Çevre Mühendisliği', 'Biyomedikal Mühendisliği',
    'Gıda Mühendisliği', 'Tekstil Mühendisliği', 'Petrol Mühendisliği',
    'Maden Mühendisliği', 'Jeoloji Mühendisliği', 'Harita Mühendisliği',
    'Uzay Mühendisliği', 'Havacılık ve Uzay Mühendisliği',
    'Mekatronik Mühendisliği', 'Yapay Zeka Mühendisliği',
    'Veri Bilimi', 'Yazılım Geliştirme',
    'Pilotluk', 'Hava Trafik Kontrol',
    'Turizm İşletmeciliği', 'Gastronomi ve Mutfak Sanatları',
    'Spor Bilimleri', 'Beden Eğitimi ve Spor Öğretmenliği',
    'Müzik', 'Resim', 'Heykel', 'Tiyatro', 'Sinema ve Televizyon',
    'Sanat Tarihi',
    'Sosyal Hizmet', 'Çocuk Gelişimi', 'Okul Öncesi Öğretmenliği',
    'Özel Eğitim Öğretmenliği',
    'Tarih Öğretmenliği', 'Coğrafya Öğretmenliği',
    'Fizik Öğretmenliği', 'Kimya Öğretmenliği', 'Biyoloji Öğretmenliği',
    'İlahiyat', 'İslami İlimler',
    'Dil ve Konuşma Terapisi', 'Odyoloji', 'Ebelik',
    'Acil Yardım ve Afet Yönetimi',
    'Diğer',
  ];

  String? _dept;
  bool _deptOpen = false;

  String _labelFor(String key) {
    final g = _levels.firstWhere((e) => e.key == key, orElse: () => _levels.first);
    return localeService.tr(g.labelKey);
  }

  void _pickLevel(String key) {
    final needsDept = _needsDept(key);
    final classes = _classesFor(key, null);
    setState(() {
      _level = key;
      _classKey = null;
      _dept = null;
      _levelOpen = false;
      // Üniversite/Yüksek Lisans/Doktora ise bölüm sekmesi açılır,
      // sınıf sekmesi kapalı kalır (bölüm seçildikten sonra açılır).
      _deptOpen = needsDept;
      _classOpen = !needsDept && classes.isNotEmpty;
    });
    if (!needsDept && classes.isEmpty) {
      // Hiç alt katman yok — direkt seçimi onayla.
      widget.onSelect(key);
    }
  }

  void _pickDept(String d) {
    setState(() {
      _dept = d;
      _deptOpen = false;
      _classOpen = true;
    });
  }

  /// En fazla seçilebilecek profil sayısı — örn. "Lise 12" + "YKS hazırlık".
  /// Daha fazlası genelde anlamlı değil, AI maliyeti de artar.
  static const int _maxProfiles = 2;

  /// İki profil birlikte seçilebilir mi? Uyumsuzsa sebep döner, uyumluysa null.
  /// Kurallar:
  ///   • Aynı eğitim seviyesinden iki sınıf birlikte seçilemez.
  ///   • İki çalışma seviyesi birlikte seçilemez (ör. İlkokul + Lise).
  ///   • İki sınav birlikte seçilemez.
  ///   • Çalışma seviyesi + uygun sınav: sadece SON sınıflar (Lise 12 + YKS,
  ///     Ortaokul 8 + LGS, Üniversite herhangi sınıf + post-uni sınav).
  ///   • Ara sınıflar (Lise 9-11, Ortaokul 5-7, İlkokul tüm sınıflar) ek
  ///     seçim yapamaz.
  String? _incompatibilityReason(String existing, String candidate) {
    if (existing == candidate) return 'Bu seçim zaten ekli.';
    final ea = _parseProfile(existing);
    final eb = _parseProfile(candidate);
    bool isExamLevel(String l) =>
        l == 'uni_prep' || l == 'post_uni_exam' || l == 'lgs_prep';
    final isExamA = isExamLevel(ea.level);
    final isExamB = isExamLevel(eb.level);
    // İki sınav
    if (isExamA && isExamB) {
      return 'Aynı anda iki sınav birden seçilemez.';
    }
    // İki çalışma seviyesi
    if (!isExamA && !isExamB) {
      return 'İki farklı eğitim seviyesi birlikte seçilemez.';
    }
    // Birisi çalışma seviyesi, biri sınav — uyumluluk kontrolü
    final study = isExamA ? eb : ea;
    final exam = isExamA ? ea : eb;
    final examShort = exam.grade.split(' (').first.trim().toUpperCase();
    // Soyut "son sınıf" kontrolü — _classMap'in son elemanı.
    // Bu sayede tüm ülkeler için aynı şekilde çalışır:
    // TR ortaokul son: '8. Sınıf' · DE: '8. Sınıf' (aynı format) · vb.
    bool isFinalGrade(String levelKey, String grade) {
      final list = _classMap[levelKey];
      if (list == null || list.isEmpty) return false;
      return grade == list.last;
    }
    // İlkokul → hiçbir sınav uyumlu değil
    if (study.level == 'primary') {
      return 'İlkokul seviyesi için sınav hazırlığı seçilemez.';
    }
    // Ortaokul: sadece SON sınıf + Liseye Geçiş (lgs_prep)
    if (study.level == 'middle') {
      if (!isFinalGrade('middle', study.grade)) {
        return '${study.grade} öğrencisi henüz sınav seçemez. Son sınıfta Liseye Geçiş hazırlığı açılır.';
      }
      // Sadece lgs_prep veya LGS adıyla başlayan sınav (TR LGS, diğer
      // ülkelerin "transition" sınavı isimleri farklı olabilir → label'a
      // göre değil level'a göre kontrol)
      if (exam.level != 'lgs_prep' && !examShort.startsWith('LGS')) {
        return 'Son sınıf ortaokul öğrencisi sadece Liseye Geçiş hazırlığı seçebilir.';
      }
      return null;
    }
    // Lise: sadece SON sınıf + uni_prep (üniversite hazırlık sınavları)
    if (study.level == 'high') {
      if (!isFinalGrade('high', study.grade)) {
        return '${study.grade} öğrencisi henüz sınav seçemez. Son sınıfta üniversite sınavı hazırlığı açılır.';
      }
      if (exam.level != 'uni_prep') {
        return 'Lise son sınıf öğrencisi sadece üniversite hazırlık sınavları seçebilir (ALES/KPSS Lisans/TUS değil).';
      }
      return null;
    }
    // Sınava hazırlık seviyeleri kendi başına seçilir; çalışma seviyesi
    // değiller. Buraya düşmemeli.
    if (study.level == 'uni_prep' ||
        study.level == 'post_uni_exam' ||
        study.level == 'lgs_prep') {
      return 'Bu kombinasyon desteklenmiyor.';
    }
    // Üniversite (her sınıf) + post_uni_exam (1 tane)
    if (study.level == 'university') {
      if (exam.level != 'post_uni_exam') {
        return 'Üniversite öğrencisi sadece üniversite sonrası sınavları seçebilir.';
      }
      return null;
    }
    // Y. Lisans / Doktora — yine sadece post_uni_exam
    if (study.level == 'masters' || study.level == 'doctorate') {
      if (exam.level != 'post_uni_exam') {
        return 'Bu seviyede sadece üniversite sonrası sınavlar uygundur.';
      }
      return null;
    }
    return null;
  }

  /// Bu level seçilebilir mi? (Daha önce eklenen profillerle uyumlu mu?)
  /// Ders sıralaması üst→alt geçişi engeller — örn. üniversite öğrencisi
  /// LGS / YKS seçemez, lise 12 öğrencisi LGS seçemez.
  bool _isLevelKeySelectable(String candidateLevel) {
    if (_picked.isEmpty) return true;
    bool isExam(String l) =>
        l == 'uni_prep' || l == 'post_uni_exam' || l == 'lgs_prep';
    // Şu anda lobi'de sadece TEK profil olabilir (max 2, ikincisi şu anda
    // seçiliyor); ilk profili referans al.
    final ex = _parseProfile(_picked.first);
    final exIsExam = isExam(ex.level);
    final candIsExam = isExam(candidateLevel);
    // İki çalışma seviyesi
    if (!exIsExam && !candIsExam) return false;
    // İki sınav
    if (exIsExam && candIsExam) return false;
    // study + exam — uyumlu eşleşmeleri tanımla
    if (!exIsExam) {
      // Mevcut study → izinli sınav level'i
      switch (ex.level) {
        case 'primary':
          return false; // ilkokul için sınav yok
        case 'middle':
          return candidateLevel == 'lgs_prep';
        case 'high':
          return candidateLevel == 'uni_prep';
        case 'university':
        case 'masters':
        case 'doctorate':
          return candidateLevel == 'post_uni_exam';
        default:
          return false;
      }
    }
    // Mevcut exam → izinli study level'i
    switch (ex.level) {
      case 'lgs_prep':
        return candidateLevel == 'middle';
      case 'uni_prep':
        return candidateLevel == 'high';
      case 'post_uni_exam':
        return candidateLevel == 'university' ||
            candidateLevel == 'masters' ||
            candidateLevel == 'doctorate';
    }
    return false;
  }

  /// Bu sınıf/sınav opsiyonu seçilebilir mi? (Alt sınıflar engellenir.)
  bool _isClassSelectable(String level, String classOption) {
    if (_picked.isEmpty) return true;
    final base = _dept == null
        ? '$level:$classOption'
        : '$level:${_dept!}:$classOption';
    if (_picked.contains(base)) return true;
    for (final ex in _picked) {
      if (_incompatibilityReason(ex, base) != null) return false;
    }
    return true;
  }

  /// "level:grade" veya "level:dept:grade" → bileşenler
  ({String level, String grade, String? dept}) _parseProfile(String raw) {
    final parts = raw.split(':');
    if (parts.length >= 3) {
      return (
        level: parts[0],
        grade: parts.sublist(2).join(':'),
        dept: parts[1],
      );
    }
    return (
      level: parts.isNotEmpty ? parts[0] : '',
      grade: parts.length > 1 ? parts[1] : '',
      dept: null,
    );
  }

  void _pickClass(String c) {
    final base = _dept == null
        ? '${_level!}:$c'
        : '${_level!}:${_dept!}:$c';
    final alreadyPicked = _picked.contains(base);
    // Limit kontrolü: yeni eklenecekse ve liste doluysa engelle.
    if (!alreadyPicked && _picked.length >= _maxProfiles) {
      _showIncompatibilityError(
        'En fazla $_maxProfiles seviye seçebilirsin. Birini kaldırıp yeniden dene.',
      );
      setState(() {
        _classKey = c;
        _classOpen = false;
      });
      return;
    }
    // Uyumluluk kontrolü — diğer profilllerle birlikte seçilebilir mi?
    if (!alreadyPicked && _picked.isNotEmpty) {
      for (final ex in _picked) {
        final reason = _incompatibilityReason(ex, base);
        if (reason != null) {
          _showIncompatibilityError(reason);
          setState(() {
            _classKey = c;
            _classOpen = false;
          });
          return;
        }
      }
    }
    setState(() {
      _classKey = c;
      _classOpen = false;
      if (!alreadyPicked) {
        _picked.add(base);
      }
    });
    widget.onSelect(base);
    widget.onProfilesChanged?.call(List.of(_picked));
  }

  /// Eklenen bir profili kaldır.
  void _removePicked(String raw) {
    setState(() => _picked.remove(raw));
    if (_picked.isNotEmpty) {
      widget.onSelect(_picked.last);
    }
    widget.onProfilesChanged?.call(List.of(_picked));
  }

  /// "+ Başka seviye ekle" — picker'ı sıfırlayıp yeni seçim için aç.
  void _resetForAnother() {
    setState(() {
      _level = null;
      _classKey = null;
      _dept = null;
      _levelOpen = true;
      _deptOpen = false;
      _classOpen = false;
    });
  }

  /// Eklenen profil string'inden insan-okur etiket üret.
  String _chipLabelFor(String raw) {
    final parts = raw.split(':');
    String levelLabel(String key) {
      for (final l in _levels) {
        if (l.key == key) return localeService.tr(l.labelKey);
      }
      return key;
    }
    if (parts.length == 2) {
      return '${levelLabel(parts[0])} · ${parts[1]}';
    } else if (parts.length >= 3) {
      return '${levelLabel(parts[0])} · ${parts[1]} · ${parts.sublist(2).join(":")}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final classes = _level == null
        ? const <String>[]
        : _classesFor(_level!, _dept);
    final hasClasses = classes.isNotEmpty;
    final needsDept = _level != null && _needsDept(_level!);
    // Sınıf sekmesi enable: sınıf listesi var VE (bölüm gerekmiyorsa direkt /
    // bölüm gerekiyorsa bölüm seçilmiş olmalı).
    final classEnabled = hasClasses && (!needsDept || _dept != null);
    return Stack(
      children: [
        Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _SectionIconBadge(icon: Icons.tune_rounded, color: widget.accent),
          const SizedBox(height: 16),
          Text(
            localeService.tr('onb_grade_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localeService.tr('onb_grade_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.62),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              // Üstte 20px boşluk: Positioned(top:-16) etiketleri kırpmasın.
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                children: [
                  // ── Multi-select: eklenen profillerin chip listesi ────────
                  if (_picked.isNotEmpty) ...[
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final raw in _picked)
                          _PickedProfileChip(
                            label: _chipLabelFor(raw),
                            color: widget.accent,
                            onRemove: () => _removePicked(raw),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Yeni seviye eklemek için picker'ı sıfırla.
                    Center(
                      child: GestureDetector(
                        onTap: _resetForAnother,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                              color: widget.accent.withValues(alpha: 0.45),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded,
                                  size: 16, color: widget.accent),
                              const SizedBox(width: 4),
                              Text(
                                localeService.tr('onb_add_more_level'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: widget.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  // ── Sekme 1: Eğitim Düzeyi ───────────────────────────────
                  _ExpandableSelect(
                    accent: widget.accent,
                    title: localeService.tr('onb_level_section'),
                    selectedLabel: _level == null
                        ? localeService.tr('onb_pick_level_hint')
                        : _labelFor(_level!),
                    selectedColor: _level == null
                        ? null
                        : _levels.firstWhere((e) => e.key == _level).color,
                    selectedIcon: _level == null
                        ? null
                        : _levels.firstWhere((e) => e.key == _level).icon,
                    isOpen: _levelOpen,
                    enabled: true,
                    onToggle: () => setState(() => _levelOpen = !_levelOpen),
                    children: [
                      for (final g in _levels)
                        _SelectRow(
                          icon: g.icon,
                          color: g.color,
                          label: localeService.tr(g.labelKey),
                          selected: _level == g.key,
                          // Daha önce profil eklendiyse, bu seviyenin
                          // SEÇİLMİŞ olanlarla uyumlu olup olmadığını kontrol
                          // et — uyumsuzsa kilitli (gri + 🔒) göster.
                          enabled: _picked.isEmpty ||
                              _isLevelKeySelectable(g.key),
                          onTap: () => _pickLevel(g.key),
                        ),
                    ],
                  ),
                  // Tab'lar arası boşluk: 28px — etiketin (top:-16) açıklığı +
                  // göze rahat ayrım.
                  const SizedBox(height: 28),
                  // ── (Üniv/Y.Lis/Doktora) Sekme: Bölüm — arama destekli ───
                  if (needsDept) ...[
                    _DeptExpandable(
                      accent: widget.accent,
                      title: localeService.tr('onb_dept_section'),
                      selectedDept: _dept,
                      placeholder: localeService.tr('onb_pick_one'),
                      isOpen: _deptOpen,
                      onToggle: () =>
                          setState(() => _deptOpen = !_deptOpen),
                      departments: _departments,
                      onPick: _pickDept,
                    ),
                    const SizedBox(height: 28),
                  ],
                  // ── Sekme: Sınıf / (sınav hazırlık seviyelerinde) Sınav  ──
                  _ExpandableSelect(
                    accent: widget.accent,
                    title: (_level == 'uni_prep' || _level == 'lgs_prep')
                        ? localeService.tr('onb_exam_prep_section')
                        : (_level == 'post_uni_exam'
                            ? localeService.tr('onb_post_uni_exam_section')
                            : localeService.tr('onb_class_section')),
                    selectedLabel: _classKey ??
                        (classEnabled
                            ? ((_level == 'uni_prep' ||
                                    _level == 'post_uni_exam' ||
                                    _level == 'lgs_prep')
                                ? localeService.tr('onb_pick_exam_hint')
                                : localeService.tr('onb_pick_class_hint'))
                            : (_level == null
                                ? localeService.tr('onb_pick_level_first')
                                : (needsDept && _dept == null
                                    ? localeService.tr('onb_pick_dept_first')
                                    : localeService.tr('onb_no_class_needed')))),
                    selectedColor: null,
                    // Sınıf/sınav seçildiğinde seviyenin ikonunu kullan —
                    // ilkokul → backpack, lise → kitap, üniversite → mezar
                    // şapkası vb. (akademik / çocuksu uyumu).
                    selectedIcon: (_classKey != null && _level != null)
                        ? _levels
                            .firstWhere((e) => e.key == _level)
                            .icon
                        : null,
                    isOpen: _classOpen && classEnabled,
                    enabled: classEnabled,
                    onToggle: () {
                      if (!classEnabled) return;
                      setState(() => _classOpen = !_classOpen);
                    },
                    children: [
                      for (final c in classes)
                        _SelectRow(
                          icon: Icons.class_outlined,
                          color: widget.accent,
                          label: c,
                          selected: _classKey == c,
                          // Mevcut profillerle uyumsuz sınıf/sınav → kilitli.
                          // Örn. Lise 12 + YKS seçili → "9/10/11. Sınıf" pasif.
                          enabled: _level == null ||
                              _isClassSelectable(_level!, c),
                          onTap: () => _pickClass(c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
        ),
        // Sayfanın TAM ORTASINDA — uyumsuzluk uyarısı (kırmızı, belirgin).
        if (_errorMessage != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: 1,
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFDC2626),
                        width: 1.6,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Color(0xFFDC2626), size: 22),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Bölüm seçici — arama destekli ──────────────────────────────────────────
// ── Eklenen profil chip'i (multi-select onboarding) ────────────────────────
class _PickedProfileChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onRemove;
  const _PickedProfileChip({
    required this.label,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 16, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeptExpandable extends StatefulWidget {
  final Color accent;
  final String title;
  final String? selectedDept;
  final String placeholder;
  final bool isOpen;
  final VoidCallback onToggle;
  final List<String> departments;
  final ValueChanged<String> onPick;

  const _DeptExpandable({
    required this.accent,
    required this.title,
    required this.selectedDept,
    required this.placeholder,
    required this.isOpen,
    required this.onToggle,
    required this.departments,
    required this.onPick,
  });

  @override
  State<_DeptExpandable> createState() => _DeptExpandableState();
}

class _DeptExpandableState extends State<_DeptExpandable> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _norm(String s) =>
      s.toLowerCase()
       .replaceAll('ı', 'i')
       .replaceAll('İ', 'i')
       .replaceAll('ş', 's')
       .replaceAll('ç', 'c')
       .replaceAll('ğ', 'g')
       .replaceAll('ü', 'u')
       .replaceAll('ö', 'o');

  @override
  Widget build(BuildContext context) {
    final query = _norm(_search.text.trim());
    final filtered = query.isEmpty
        ? widget.departments
        : widget.departments
            .where((d) => _norm(d).contains(query))
            .toList();

    return Stack(
      clipBehavior: Clip.none,
      children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isOpen
                ? widget.accent.withValues(alpha: 0.55)
                : Colors.black.withValues(alpha: 0.12),
            width: widget.isOpen ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık satırı — sadece seçili değer; "Bölüm" etiketi çerçeve üstünde.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onToggle,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 16),
                  child: Row(
                    children: [
                      if (widget.selectedDept != null) ...[
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.school_rounded,
                            size: 18,
                            color: widget.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          widget.selectedDept ?? widget.placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: widget.selectedDept != null
                                ? widget.accent
                                : Colors.black,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: widget.isOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // İçerik: arama + liste
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !widget.isOpen
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    child: Column(
                      children: [
                        Container(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.06),
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            cursorColor: Colors.black,
                            cursorWidth: 2.2,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                            decoration: InputDecoration(
                              hintText: localeService
                                  .tr('onb_dept_search_hint'),
                              hintStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.black38,
                              ),
                              prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: Colors.black45),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: Colors.black45),
                                      onPressed: () {
                                        _search.clear();
                                        setState(() {});
                                      },
                                    ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 10),
                              filled: true,
                              fillColor: const Color(0xFFF6F7F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxHeight: 280),
                          child: filtered.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 22),
                                  child: Text(
                                    localeService
                                        .tr('onb_dept_no_results'),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const ClampingScrollPhysics(),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) => _SelectRow(
                                    icon: Icons.school_outlined,
                                    color: widget.accent,
                                    label: filtered[i],
                                    selected:
                                        widget.selectedDept == filtered[i],
                                    onTap: () =>
                                        widget.onPick(filtered[i]),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      ),
      // Çerçeve üstündeki etiket — sayfa zemini renkli yama çizgiyi keser.
      Positioned(
        top: -10,
        left: 14,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            color: const Color(0xFFF2F3F5),
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
      ],
    );
  }
}

class _GradeOption {
  final String key;
  final String labelKey;
  final IconData icon;
  final Color color;
  const _GradeOption({
    required this.key,
    required this.labelKey,
    required this.icon,
    required this.color,
  });
}

// ── Açılır/kapanır seçim kartı ──────────────────────────────────────────────
class _ExpandableSelect extends StatelessWidget {
  final Color accent;
  final String title;
  final String selectedLabel;
  final Color? selectedColor;
  /// Seçim yapılmışsa label'ın SOLUNDA gösterilecek ikon. null ise yok.
  final IconData? selectedIcon;
  final bool isOpen;
  final bool enabled;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _ExpandableSelect({
    required this.accent,
    required this.title,
    required this.selectedLabel,
    required this.selectedColor,
    required this.isOpen,
    required this.enabled,
    required this.onToggle,
    required this.children,
    this.selectedIcon,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isOpen
        ? accent.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.12);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: double.infinity,
          // Clip — InkWell splash'ı yuvarlatılmış kenarın dışına taşmasın
          // (etiket alanına sızmasın).
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFF6F7F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: isOpen ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık satırı — artık küçük etiket DEĞİL, sadece seçili değer.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: enabled ? onToggle : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                    child: Row(
                      children: [
                        if (selectedIcon != null) ...[
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: (selectedColor ?? accent)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              selectedIcon,
                              size: 18,
                              color: enabled
                                  ? (selectedColor ?? accent)
                                  : Colors.black26,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            selectedLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: enabled
                                  ? (selectedColor ?? Colors.black)
                                  : Colors.black38,
                            ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: isOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 22,
                            color: enabled
                                ? Colors.black54
                                : Colors.black26,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          // Liste
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !isOpen
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Column(
                      children: [
                        Container(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.06),
                          margin:
                              const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        const SizedBox(height: 6),
                        for (final c in children) c,
                      ],
                    ),
                  ),
          ),
        ],
      ),
        ),
        // Çerçeve sınırının üstünde, dışarıda — kart içine taşmaz, böylece
        // sekmeye basıldığında InkWell highlight'ı etiketi etkilemez.
        Positioned(
          top: -18,
          left: 14,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              // Sayfa zemini ile aynı renk → border çizgisinin üstüne oturur.
              color: const Color(0xFFF2F3F5),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: enabled
                      ? Colors.black.withValues(alpha: 0.7)
                      : Colors.black26,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Liste satırı (her seçenek) ─────────────────────────────────────────────
class _SelectRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  const _SelectRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final fadedColor = color.withValues(alpha: 0.30);
    final iconColor = enabled ? color : fadedColor;
    final textColor =
        enabled ? (selected ? color : Colors.black87) : Colors.black26;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (enabled ? color : fadedColor)
                      .withValues(alpha: 0.14),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              if (!enabled)
                const Icon(Icons.lock_outline_rounded,
                    color: Colors.black26, size: 16)
              else if (selected)
                Icon(Icons.check_circle_rounded, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Ortak bileşenler
// ═════════════════════════════════════════════════════════════════════════════

class _ProgressBar extends StatelessWidget {
  final int current;
  final int total;
  final Color color;
  final Color inactiveColor;
  const _ProgressBar({
    required this.current,
    required this.total,
    required this.color,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final done = i <= current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              height: 4,
              decoration: BoxDecoration(
                color: done ? color : inactiveColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SectionIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _SectionIconBadge({required this.icon, required this.color});

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

// ═════════════════════════════════════════════════════════════════════════════
//  _SubjectCarousel — "Her Soruyu Çöz" başlık grafiği.
//  Sağ üstte küçük QuAlsar logosu (center kelime gizli) + üstünde "QuAlsar"
//  (Al kırmızı). Alt satırda 3 SABİT beyaz pill çerçeve. Her döngü:
//    1) Pill içinde (icon + ders adı) belirir (fade-in)
//    2) ~2 sn sabit durur
//    3) Ders ADI pill'den çıkıp logoya süzülerek küçülüp kaybolur;
//       metin pill sınırını aşar aşmaz IKON da kaybolur (pill boşalır)
//    4) Sonraki ders aynı pill'in içine belirir
//  12 ders × 4 grup, pill çerçeveleri hiç hareket etmez.
// ═════════════════════════════════════════════════════════════════════════════

class _CarouselSubject {
  final String key;
  final IconData icon;
  const _CarouselSubject(this.key, this.icon);
}

class _SubjectCarousel extends StatefulWidget {
  final Color color;
  const _SubjectCarousel({required this.color});

  @override
  State<_SubjectCarousel> createState() => _SubjectCarouselState();
}

class _SubjectCarouselState extends State<_SubjectCarousel>
    with SingleTickerProviderStateMixin {
  static const _subjects = <_CarouselSubject>[
    _CarouselSubject('subject_math', Icons.calculate_rounded),
    _CarouselSubject('subject_physics', Icons.bolt_rounded),
    _CarouselSubject('subject_chemistry', Icons.science_rounded),
    _CarouselSubject('subject_biology', Icons.biotech_rounded),
    _CarouselSubject('subject_english', Icons.translate_rounded),
    _CarouselSubject('subject_geography', Icons.public_rounded),
    _CarouselSubject('subject_history', Icons.account_balance_rounded),
    _CarouselSubject('subject_literature', Icons.menu_book_rounded),
    _CarouselSubject('subject_computer', Icons.computer_rounded),
    _CarouselSubject('subject_economics', Icons.trending_up_rounded),
    _CarouselSubject('subject_philosophy', Icons.psychology_alt_rounded),
    _CarouselSubject('subject_art', Icons.palette_rounded),
  ];

  late final AnimationController _ctrl;
  int _groupIdx = 0;

  // Döngü 2500 ms:
  //   0 – flyStart (1500 ms) → mevcut grup pill içinde sabit
  //   flyStart – 1 (1000 ms) → mevcut grup yazısı logoya DOĞRUSAL hızda uçar,
  //     AYNI ANDA sıradaki grup pill içinde fade-in olur (paralel).
  static const int _cycleMs = 2500;
  static const double _flyStart = 0.60; // 1500 ms

  // Header ölçüleri.
  static const double _headerW = 300;
  static const double _headerH = 178;
  static const double _logoSize = 68;
  static const double _pillW = 94;
  static const double _pillH = 60;
  static const double _pillY = 116;
  static const double _gap = 7.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _cycleMs),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _groupIdx = (_groupIdx + 1) % 4);
          _ctrl.forward(from: 0);
        }
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Logo merkezi — yatayda ortalı ("QuAlsar" altında).
    const logoCX = _headerW / 2; // 150
    const logoCY = 18 + 4 + _logoSize / 2; // 56
    // 3 pill yerleşimi — yatayda ortalı.
    const rowW = _pillW * 3 + _gap * 2; // 296
    const rowStart = (_headerW - rowW) / 2; // 2

    return SizedBox(
      width: _headerW,
      height: _headerH,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          // Uçuş fazının 0..1 ilerlemesi (DOĞRUSAL — hız sabit).
          final flyT = t < _flyStart ? 0.0 : (t - _flyStart) / (1 - _flyStart);

          // Mevcut grup: 0..flyStart tam görünür; flyStart..1 logoya uçar.
          // İkon pill sınırını geçer geçmez hızla kaybolur.
          double curIconOpacity;
          double curTextOpacity;
          if (flyT == 0) {
            curIconOpacity = 1.0;
            curTextOpacity = 1.0;
          } else {
            curIconOpacity = flyT < 0.15
                ? 1.0
                : flyT < 0.30
                    ? 1.0 - (flyT - 0.15) / 0.15
                    : 0.0;
            curTextOpacity = flyT < 0.75 ? 1.0 : (1.0 - flyT) / 0.25;
          }
          // Sıradaki grup: flyT == 0 iken gizli; sonrasında 0→1 linear fade-in.
          final nextOpacity = flyT;
          // Uçuş konumu ve ölçeği — DOĞRUSAL.
          final textScale = 1.0 - flyT * 0.85;

          final curGroup =
              _subjects.sublist(_groupIdx * 3, _groupIdx * 3 + 3);
          final nextIdx = (_groupIdx + 1) % 4;
          final nextGroup = _subjects.sublist(nextIdx * 3, nextIdx * 3 + 3);

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 3 SABİT pill çerçevesi.
              for (int i = 0; i < 3; i++)
                Positioned(
                  left: rowStart + i * (_pillW + _gap),
                  top: _pillY,
                  child: _PillFrame(color: widget.color),
                ),
              // Sıradaki grup — fly fazında pill içinde ALTTAN fade-in.
              for (int i = 0; i < 3; i++)
                Positioned(
                  left: rowStart + i * (_pillW + _gap),
                  top: _pillY + 8,
                  width: _pillW,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: nextOpacity.clamp(0.0, 1.0),
                      child: Center(
                        child: Icon(
                          nextGroup[i].icon,
                          color: widget.color,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              for (int i = 0; i < 3; i++)
                Positioned(
                  left: rowStart + i * (_pillW + _gap),
                  top: _pillY + _pillH / 2 + 4,
                  width: _pillW,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: nextOpacity.clamp(0.0, 1.0),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            localeService.tr(nextGroup[i].key),
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Mevcut grubun ikonları — pill içinde, uçuş başladıkça kaybolur.
              for (int i = 0; i < 3; i++)
                Positioned(
                  left: rowStart + i * (_pillW + _gap),
                  top: _pillY + 8,
                  width: _pillW,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: curIconOpacity.clamp(0.0, 1.0),
                      child: Center(
                        child: Icon(
                          curGroup[i].icon,
                          color: widget.color,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              // Mevcut grubun yazıları — doğrusal hızla logoya uçar.
              for (int i = 0; i < 3; i++)
                _buildFlyingText(
                  subject: curGroup[i],
                  slotX: rowStart + i * (_pillW + _gap),
                  curvedFly: flyT,
                  opacity: curTextOpacity,
                  scale: textScale,
                  logoCX: logoCX,
                  logoCY: logoCY,
                ),
              // QuAlsar yazısı + dönen logo — yatayda ortalı, en üstte.
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                            height: 1.0,
                          ),
                          children: [
                            TextSpan(
                                text: 'Qu',
                                style: TextStyle(color: Colors.black)),
                            TextSpan(
                                text: 'Al',
                                style: TextStyle(color: Color(0xFFD81B1B))),
                            TextSpan(
                                text: 'sar',
                                style: TextStyle(color: Colors.black)),
                          ],
                        ),
                      ),
                      SizedBox(height: 4),
                      QuAlsarLogoMark(
                        size: _logoSize,
                        showCenterWord: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFlyingText({
    required _CarouselSubject subject,
    required double slotX,
    required double curvedFly,
    required double opacity,
    required double scale,
    required double logoCX,
    required double logoCY,
  }) {
    // Metnin pill içindeki başlangıç merkezi (icon altı).
    final textStartX = slotX + _pillW / 2;
    final textStartY = _pillY + _pillH / 2 + 10;
    final dx = (logoCX - textStartX) * curvedFly;
    final dy = (logoCY - textStartY) * curvedFly;
    return Positioned(
      left: slotX,
      top: _pillY + _pillH / 2 + 4,
      width: _pillW,
      child: IgnorePointer(
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    localeService.tr(subject.key),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillFrame extends StatelessWidget {
  final Color color;
  const _PillFrame({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _SubjectCarouselState._pillW,
      height: _SubjectCarouselState._pillH,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black,
          width: 0.8,
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  final String label;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;
  const _CtaButton({
    required this.label,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final darker = Color.lerp(accent, Colors.black, 0.35)!;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.4,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent, darker],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.30),
                      blurRadius: 22,
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _CompeteGlobeHeader — "Ülkende ve Dünyada Yarış" sayfasının başlık grafiği.
//  Merkez: kupa. Etrafında dönen yörünge yok; bunun yerine soldan ve sağdan
//  aynı anda iki kart (bayrak + ülke + hayali kullanıcı adı) kayarak gelir,
//  ~2 saniye durur, fade ile çıkar; yerine başka ikili gelir.
// ═══════════════════════════════════════════════════════════════════════════════
class _CompeteGlobeHeader extends StatefulWidget {
  final Color color;
  const _CompeteGlobeHeader({required this.color});

  @override
  State<_CompeteGlobeHeader> createState() => _CompeteGlobeHeaderState();
}

class _CompeteGlobeHeaderState extends State<_CompeteGlobeHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle;

  // Hayali kullanıcı + ülke havuzu — bazı ülkelerde birden fazla kullanıcı var,
  // böylece "aynı ülke içi yarış" da gösterilebiliyor (kullanıcı kendi ülkesinde
  // de yarışabilir).
  static const _users = <_RivalUser>[
    _RivalUser('🇹🇷', 'Türkiye', 'Mert Y.'),
    _RivalUser('🇹🇷', 'Türkiye', 'Ayşe K.'),
    _RivalUser('🇹🇷', 'Türkiye', 'Zeynep B.'),
    _RivalUser('🇺🇸', 'USA', 'Emma R.'),
    _RivalUser('🇺🇸', 'USA', 'Jake T.'),
    _RivalUser('🇩🇪', 'Almanya', 'Lukas M.'),
    _RivalUser('🇩🇪', 'Almanya', 'Anna F.'),
    _RivalUser('🇯🇵', 'Japonya', 'Yuki S.'),
    _RivalUser('🇯🇵', 'Japonya', 'Hiro T.'),
    _RivalUser('🇫🇷', 'Fransa', 'Léa D.'),
    _RivalUser('🇧🇷', 'Brezilya', 'João P.'),
    _RivalUser('🇮🇳', 'Hindistan', 'Riya P.'),
    _RivalUser('🇪🇸', 'İspanya', 'Sofia G.'),
    _RivalUser('🇮🇹', 'İtalya', 'Luca B.'),
    _RivalUser('🇰🇷', 'Kore', 'Min Lee'),
    _RivalUser('🇲🇽', 'Meksika', 'Diego R.'),
    _RivalUser('🇨🇦', 'Kanada', 'Liam J.'),
    _RivalUser('🇦🇺', 'Avustralya', 'Charlotte W.'),
    _RivalUser('🇳🇱', 'Hollanda', 'Sven V.'),
    _RivalUser('🇸🇪', 'İsveç', 'Astrid L.'),
    _RivalUser('🇵🇱', 'Polonya', 'Kasia N.'),
  ];

  // Yarışılan ders + konu havuzu — her döngüde iki kullanıcı AYNI konuda yarışır.
  static const _matches = <_MatchTopic>[
    _MatchTopic('Matematik', 'Türev'),
    _MatchTopic('Fizik', 'Newton Yasaları'),
    _MatchTopic('Kimya', 'Asit-Baz'),
    _MatchTopic('Biyoloji', 'Hücre'),
    _MatchTopic('Tarih', 'Lozan'),
    _MatchTopic('Coğrafya', 'İklim'),
    _MatchTopic('Matematik', 'İntegral'),
    _MatchTopic('Türkçe', 'Paragraf'),
    _MatchTopic('Fizik', 'Elektrik'),
    _MatchTopic('Geometri', 'Üçgen'),
    _MatchTopic('İngilizce', 'Tenses'),
    _MatchTopic('Edebiyat', 'Roman'),
  ];

  int _leftIdx = 0;
  int _rightIdx = 3; // Türkiye → USA (farklı ülke)
  int _matchIdx = 0;
  int _cycleCount = 0;
  final math.Random _rng = math.Random();

  // Bir döngü ~2.4 sn: 0.30 sn giriş + 1.80 sn duruş + 0.30 sn çıkış.
  static const _cycleMs = 2400;

  @override
  void initState() {
    super.initState();
    _cycle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _cycleMs),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() {
            _pickNextPair();
            _matchIdx = (_matchIdx + 1) % _matches.length;
          });
          _cycle.forward(from: 0);
        }
      });
    _cycle.forward();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  // Sıradaki rakip ikilisini seç. Her 3 döngüden 1'inde aynı ülke içi
  // yarış (kişi kendi ülkesinde de yarışabilir); diğerlerinde dünya çapı.
  void _pickNextPair() {
    _cycleCount++;
    final wantSameCountry = _cycleCount % 3 == 0;
    if (wantSameCountry) {
      final groups = <String, List<int>>{};
      for (var i = 0; i < _users.length; i++) {
        groups.putIfAbsent(_users[i].country, () => []).add(i);
      }
      final multi = groups.values.where((g) => g.length >= 2).toList();
      if (multi.isNotEmpty) {
        final group = multi[_rng.nextInt(multi.length)];
        _leftIdx = group[_rng.nextInt(group.length)];
        do {
          _rightIdx = group[_rng.nextInt(group.length)];
        } while (_rightIdx == _leftIdx);
        return;
      }
    }
    // Dünya çapı: farklı ülkeden iki kişi.
    _leftIdx = _rng.nextInt(_users.length);
    do {
      _rightIdx = _rng.nextInt(_users.length);
    } while (_rightIdx == _leftIdx ||
        _users[_rightIdx].country == _users[_leftIdx].country);
  }

  // Animasyon fazı: 0..0.125 giriş, 0.125..0.875 duruş, 0.875..1 çıkış.
  ({double slide, double opacity}) _phase(double t) {
    if (t < 0.125) {
      final p = t / 0.125;
      return (slide: Curves.easeOutCubic.transform(p), opacity: p);
    }
    if (t > 0.875) {
      final p = (t - 0.875) / 0.125;
      return (slide: 1 - Curves.easeInCubic.transform(p) * 0.4, opacity: 1 - p);
    }
    return (slide: 1.0, opacity: 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          // Kupa ekran genişliğinin %20'si — küçük (dar telefonda da çakışma olmaz).
          final cupSize = (w * 0.20).clamp(56.0, 76.0);
          // Kupa ile pill arası en az 10 px boşluk; pill kenardan 4 px içeride.
          const edgePad = 4.0;
          const minGap = 10.0;
          final pillW = ((w - cupSize) / 2 - minGap - edgePad).clamp(80.0, 140.0);

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Dış parlama (kupa ile orantılı)
              Container(
                width: cupSize * 2.4,
                height: cupSize * 2.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.color.withValues(alpha: 0.18),
                      widget.color.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
              // Soldan/sağdan kayan kullanıcı kartları
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _cycle,
                  builder: (_, __) {
                    final p = _phase(_cycle.value);
                    final off = (1 - p.slide) * (pillW + 40);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: edgePad - off,
                          top: 50,
                          child: Opacity(
                            opacity: p.opacity,
                            child: _RivalPill(
                              user: _users[_leftIdx],
                              match: _matches[_matchIdx],
                              width: pillW,
                            ),
                          ),
                        ),
                        Positioned(
                          right: edgePad - off,
                          top: 50,
                          child: Opacity(
                            opacity: p.opacity,
                            child: _RivalPill(
                              user: _users[_rightIdx],
                              match: _matches[_matchIdx],
                              width: pillW,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // Merkez kupa (pill'lerin önünde)
              Container(
                width: cupSize,
                height: cupSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color,
                      widget.color.withValues(alpha: 0.75),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: Colors.white,
                  size: cupSize * 0.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RivalUser {
  final String flag;
  final String country;
  final String user;
  const _RivalUser(this.flag, this.country, this.user);
}

class _MatchTopic {
  final String subject;
  final String topic;
  const _MatchTopic(this.subject, this.topic);
}

class _RivalPill extends StatelessWidget {
  final _RivalUser user;
  final _MatchTopic match;
  final double width;
  const _RivalPill({
    required this.user,
    required this.match,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bayrak + ülke (üst satır)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  user.country,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Kullanıcı adı
          Text(
            user.user,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.62),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          // Ayraç çizgi
          Container(
            width: 24,
            height: 1,
            color: Colors.black.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 5),
          // Ders adı (iki kullanıcı için AYNI — yarışılan ortak konu)
          Text(
            match.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFFEAB308),
              height: 1.1,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 2),
          // Yarışılan konu (iki kullanıcı için AYNI)
          Text(
            match.topic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.55),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _AuthPage — Hero ile Çöz arasında: hesap oluşturma / giriş.
//  Sağlayıcılar: Google · Apple · Facebook · E-posta · Misafir.
//  Backend: AuthService (mock). Üretimde firebase_auth + ilgili paketler
//  bağlandığında bu UI değişmeden çalışır.
// ═══════════════════════════════════════════════════════════════════════════════
class _AuthPage extends StatefulWidget {
  final Color accent;
  final VoidCallback onAuthenticated;
  const _AuthPage({required this.accent, required this.onAuthenticated});

  @override
  State<_AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<_AuthPage> {
  bool _busy = false;
  String? _activeProvider;

  Future<void> _run(String tag, Future<AppUser> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _activeProvider = tag;
    });
    try {
      await fn();
      if (!mounted) return;
      widget.onAuthenticated();
    } on AuthException catch (e) {
      if (!mounted) return;
      // Kullanıcı iptal etti → sessizce dön (snackbar gösterme).
      if (e.code == 'cancelled') return;
      // Yapılandırma hatası → AlertDialog ile net mesaj.
      if (e.code == 'firebase-not-configured' || e.code == 'no-app') {
        await _showFriendlyError(
          title: 'Yapılandırma eksik',
          body: e.message,
        );
        return;
      }
      _snack(e.message);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      if (raw.contains('[core/no-app]') || raw.contains('No Firebase App')) {
        await _showFriendlyError(
          title: 'Firebase yapılandırılmamış',
          body:
              'Bu giriş yöntemi için Firebase başlatılamıyor. '
              'Terminalde "flutterfire configure" çalıştırıp uygulamayı '
              'yeniden başlat.',
        );
        return;
      }
      _snack(localeService.tr('auth_error_generic'));
      debugPrint('[Auth] $tag error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _activeProvider = null;
        });
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _showFriendlyError({
    required String title,
    required String body,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          body,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Tamam',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEmailSheet() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: _EmailSignUpSheet(accent: widget.accent),
      ),
    );
    if (ok == true && mounted) widget.onAuthenticated();
  }

  Future<void> _openPhoneSheet() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: _PhoneAuthSheet(accent: widget.accent),
      ),
    );
    if (ok == true && mounted) widget.onAuthenticated();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.current;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.accent,
                  widget.accent.withValues(alpha: 0.72),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.32),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.account_circle_rounded,
              color: Colors.white,
              size: 52,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            localeService.tr('auth_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localeService.tr('auth_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.62),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          if (user != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF22C55E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF22C55E), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          localeService.tr('auth_signed_in'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF166534),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email ?? user.name ?? user.provider.id,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await AuthService.signOut();
                      if (mounted) setState(() {});
                    },
                    child: Text(
                      localeService.tr('auth_sign_out'),
                      style: const TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _AuthBigButton(
            label: localeService.tr('auth_with_google'),
            background: Colors.white,
            foreground: Colors.black,
            border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
            iconBuilder: (_) => const _GoogleGlyph(size: 22),
            busy: _busy && _activeProvider == 'google',
            onTap: () => _run('google', () => AuthService.signInWithGoogle()),
          ),
          const SizedBox(height: 10),
          _AuthBigButton(
            label: localeService.tr('auth_with_apple'),
            background: Colors.white,
            foreground: Colors.black,
            border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
            iconBuilder: (_) => const Icon(
              Icons.apple,
              color: Colors.black,
              size: 24,
            ),
            busy: _busy && _activeProvider == 'apple',
            onTap: () => _run('apple', () => AuthService.signInWithApple()),
          ),
          const SizedBox(height: 10),
          _AuthBigButton(
            label: localeService.tr('auth_with_phone'),
            background: Colors.white,
            foreground: Colors.black,
            border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
            iconBuilder: (_) => const Icon(
              Icons.phone_iphone_rounded,
              color: Color(0xFF22C55E),
              size: 24,
            ),
            busy: false,
            onTap: _openPhoneSheet,
          ),
          const SizedBox(height: 14),
          _OrDivider(label: localeService.tr('auth_or')),
          const SizedBox(height: 14),
          _AuthBigButton(
            label: localeService.tr('auth_with_email'),
            background: const Color(0xFFF6F7F9),
            foreground: Colors.black,
            border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            iconBuilder: (_) => Icon(
              Icons.alternate_email_rounded,
              color: widget.accent,
              size: 24,
            ),
            busy: false,
            onTap: _openEmailSheet,
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run('guest', () => AuthService.continueAsGuest()),
            child: Text(
              localeService.tr('auth_continue_guest'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black.withValues(alpha: 0.62),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            localeService.tr('auth_terms_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.black.withValues(alpha: 0.42),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBigButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final Widget Function(BuildContext) iconBuilder;
  final bool busy;
  final BoxBorder? border;
  final VoidCallback? onTap;

  const _AuthBigButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.iconBuilder,
    required this.busy,
    required this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: foreground,
                          ),
                        )
                      : iconBuilder(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                    letterSpacing: 0.1,
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

class _OrDivider extends StatelessWidget {
  final String label;
  const _OrDivider({required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(height: 1, color: Colors.black.withValues(alpha: 0.10)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.45),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: Container(height: 1, color: Colors.black.withValues(alpha: 0.10)),
        ),
      ],
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  final double size;
  const _GoogleGlyph({required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Color(0xFF4285F4),
            Color(0xFF34A853),
            Color(0xFFFBBC05),
            Color(0xFFEA4335),
            Color(0xFF4285F4),
          ],
        ),
      ),
      child: Container(
        width: size - 4,
        height: size - 4,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: Text(
          'G',
          style: TextStyle(
            fontSize: size * 0.62,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF4285F4),
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _EmailSignUpSheet extends StatefulWidget {
  final Color accent;
  const _EmailSignUpSheet({required this.accent});

  @override
  State<_EmailSignUpSheet> createState() => _EmailSignUpSheetState();
}

class _EmailSignUpSheetState extends State<_EmailSignUpSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _isLogin = false;
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isLogin) {
        await AuthService.signInWithEmail(
          email: _email.text,
          password: _pass.text,
        );
      } else {
        await AuthService.signUpWithEmail(
          name: _name.text,
          email: _email.text,
          password: _pass.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = localeService.tr('auth_error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Colors.black38,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, size: 18, color: Colors.black54),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        filled: true,
        fillColor: const Color(0xFFF6F7F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isLogin
                ? localeService.tr('auth_email_login_title')
                : localeService.tr('auth_email_signup_title'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 14),
          if (!_isLogin) ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              cursorColor: widget.accent,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
              decoration: _dec(
                localeService.tr('auth_name_hint'),
                Icons.person_rounded,
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            cursorColor: widget.accent,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            decoration: _dec(
              localeService.tr('auth_email_hint'),
              Icons.alternate_email_rounded,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pass,
            obscureText: _obscure,
            cursorColor: widget.accent,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            decoration: _dec(
              localeService.tr('auth_password_hint'),
              Icons.lock_rounded,
            ).copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: Colors.black54,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: widget.accent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _busy ? null : _submit,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isLogin
                                ? localeService.tr('auth_sign_in')
                                : localeService.tr('auth_sign_up'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _isLogin = !_isLogin),
            child: Text(
              _isLogin
                  ? localeService.tr('auth_no_account')
                  : localeService.tr('auth_have_account'),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _PhoneAuthSheet — telefon + OTP doğrulama (iki adım)
//  Adım 1: numara gir → Kod Gönder
//  Adım 2: 6 haneli OTP kodu gir → Doğrula (otomatik tetiklenir)
// ═══════════════════════════════════════════════════════════════════════════════
class _PhoneAuthSheet extends StatefulWidget {
  final Color accent;
  const _PhoneAuthSheet({required this.accent});

  @override
  State<_PhoneAuthSheet> createState() => _PhoneAuthSheetState();
}

class _PhoneAuthSheetState extends State<_PhoneAuthSheet> {
  // Cihaz/lokasyon ülkesinden ülke kodu tablosu — yaygın ülkeler.
  static const Map<String, String> _dialCodes = {
    'tr': '+90', 'us': '+1', 'ca': '+1',
    'gb': '+44', 'uk': '+44', 'ie': '+353',
    'de': '+49', 'fr': '+33', 'it': '+39', 'es': '+34',
    'pt': '+351', 'nl': '+31', 'be': '+32', 'lu': '+352',
    'at': '+43', 'ch': '+41', 'pl': '+48', 'cz': '+420',
    'sk': '+421', 'hu': '+36', 'ro': '+40', 'bg': '+359',
    'gr': '+30', 'hr': '+385', 'rs': '+381', 'ba': '+387',
    'al': '+355', 'mk': '+389', 'si': '+386', 'me': '+382',
    'se': '+46', 'no': '+47', 'dk': '+45', 'fi': '+358',
    'is': '+354', 'ee': '+372', 'lv': '+371', 'lt': '+370',
    'ru': '+7', 'ua': '+380', 'by': '+375', 'md': '+373',
    'kz': '+7', 'uz': '+998', 'az': '+994', 'ge': '+995',
    'am': '+374', 'tj': '+992', 'kg': '+996', 'tm': '+993',
    'jp': '+81', 'kr': '+82', 'cn': '+86', 'tw': '+886',
    'hk': '+852', 'mo': '+853', 'sg': '+65', 'my': '+60',
    'th': '+66', 'vn': '+84', 'id': '+62', 'ph': '+63',
    'la': '+856', 'kh': '+855', 'mm': '+95', 'mn': '+976',
    'in': '+91', 'pk': '+92', 'bd': '+880', 'lk': '+94',
    'np': '+977', 'bt': '+975', 'mv': '+960', 'af': '+93',
    'au': '+61', 'nz': '+64', 'fj': '+679',
    'br': '+55', 'mx': '+52', 'ar': '+54', 'cl': '+56',
    'co': '+57', 'pe': '+51', 'uy': '+598', 'py': '+595',
    've': '+58', 'bo': '+591', 'ec': '+593', 'cu': '+53',
    'do': '+1', 'pr': '+1', 'cr': '+506', 'pa': '+507',
    'gt': '+502', 'sv': '+503', 'hn': '+504', 'ni': '+505',
    'sa': '+966', 'ae': '+971', 'qa': '+974', 'kw': '+965',
    'bh': '+973', 'om': '+968', 'jo': '+962', 'lb': '+961',
    'sy': '+963', 'iq': '+964', 'ye': '+967', 'ps': '+970',
    'il': '+972', 'ir': '+98',
    'eg': '+20', 'ma': '+212', 'dz': '+213', 'tn': '+216',
    'ly': '+218', 'sd': '+249', 'so': '+252', 'et': '+251',
    'ke': '+254', 'tz': '+255', 'ug': '+256', 'rw': '+250',
    'ng': '+234', 'gh': '+233', 'sn': '+221', 'ci': '+225',
    'cm': '+237', 'za': '+27', 'zm': '+260', 'zw': '+263',
    'mg': '+261', 'mu': '+230',
  };

  String _dialFor(String? cc) {
    final code = cc?.toLowerCase().trim();
    if (code == null || code.isEmpty) return '+90';
    return _dialCodes[code] ?? '+90';
  }

  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  String? _sessionId;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    // 1) Cihaz/lokasyon ülkesine göre uluslararası kodu otomatik koy.
    //    CountryResolver: önce manuel seçim → IP geo → cihaz locale → null.
    final detected = CountryResolver.instance.current;
    final dial = _dialFor(detected);
    _phone.text = '$dial ';
    // İmleç ülke kodunun SONUNDA — kullanıcı doğrudan kalan rakamı yazsın.
    _phone.selection = TextSelection.collapsed(offset: _phone.text.length);

    // 2) Sheet animasyonu bitince odakla → klavye açılsın, imleç yanıp sönsün.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _phoneFocus.requestFocus();
      // Bazı platformlar focus alındığında metni "select-all" yapabilir;
      // 50 ms sonra imleci yine sona koyuyoruz ki ülke kodu silinmesin.
      Future<void>.delayed(const Duration(milliseconds: 60), () {
        if (!mounted) return;
        _phone.selection =
            TextSelection.collapsed(offset: _phone.text.length);
      });
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() => _resendIn = 30);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendIn <= 0) {
        t.cancel();
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _requestCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await AuthService.requestPhoneCode(_phone.text);
      if (!mounted) return;
      setState(() => _sessionId = id);
      _startResendTimer();
      // Kod alanı görünür hale gelir gelmez ona odaklan.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Yapılandırma hatası → ham kod yerine kullanıcıya net dialog.
      if (e.code == 'firebase-not-configured' || e.code == 'no-app') {
        await _showFriendlyError(
          title: 'Telefon doğrulama hazır değil',
          body:
              'Firebase yapılandırması tamamlanmadığı için şu an SMS '
              'gönderilemiyor. Geliştirici terminalde '
              '"flutterfire configure" komutunu çalıştırıp uygulamayı '
              'yeniden başlatmalı.\n\nDilersen e-posta veya misafir '
              'olarak devam edebilirsin.',
        );
        return;
      }
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final raw = e.toString();
      // Firebase'in [core/no-app] hatası — yapılandırma yapılmadığında çıkar.
      if (raw.contains('[core/no-app]') ||
          raw.contains('No Firebase App')) {
        await _showFriendlyError(
          title: 'Telefon doğrulama hazır değil',
          body:
              'Firebase başlatılamadığı için SMS gönderilemiyor. '
              'Geliştirici "flutterfire configure" komutunu çalıştırıp '
              'uygulamayı yeniden başlatmalı.',
        );
        return;
      }
      setState(() => _error = localeService.tr('auth_error_generic'));
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _showFriendlyError({
    required String title,
    required String body,
  }) async {
    if (!mounted) return;
    // Sheet üzerinden görünür olsun diye SnackBar yerine Dialog kullanıyoruz.
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          body,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Tamam',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verify() async {
    if (_sessionId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.verifyPhoneCode(
        sessionId: _sessionId!,
        code: _code.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = localeService.tr('auth_error_generic'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Colors.black38,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, size: 18, color: Colors.black54),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        filled: true,
        fillColor: const Color(0xFFF6F7F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final hasSession = _sessionId != null;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasSession
                ? localeService.tr('auth_phone_code_title')
                : localeService.tr('auth_phone_title'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasSession
                ? localeService
                    .tr('auth_phone_code_hint')
                    .replaceFirst('%s', _phone.text.trim())
                : localeService.tr('auth_phone_hint_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withValues(alpha: 0.62),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (!hasSession)
            TextField(
              controller: _phone,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              cursorColor: widget.accent,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
              decoration: _dec(
                localeService.tr('auth_phone_field_hint'),
                Icons.phone_iphone_rounded,
              ),
              onSubmitted: (_) => _busy ? null : _requestCode(),
            )
          else
            TextField(
              controller: _code,
              focusNode: _codeFocus,
              keyboardType: TextInputType.number,
              cursorColor: widget.accent,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
                color: Colors.black,
              ),
              decoration: _dec(
                '••••••',
                Icons.lock_clock_rounded,
              ).copyWith(counterText: ''),
              onChanged: (v) {
                if (v.length == 6 && !_busy) _verify();
              },
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: widget.accent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _busy
                    ? null
                    : (hasSession ? _verify : _requestCode),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            hasSession
                                ? localeService.tr('auth_phone_verify')
                                : localeService.tr('auth_phone_send_code'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (hasSession) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: (_busy || _resendIn > 0) ? null : _requestCode,
              child: Text(
                _resendIn > 0
                    ? localeService
                        .tr('auth_phone_resend_in')
                        .replaceFirst('%d', '$_resendIn')
                    : localeService.tr('auth_phone_resend'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _resendIn > 0
                      ? Colors.black38
                      : Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 2),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _sessionId = null;
                        _code.clear();
                        _error = null;
                        _resendIn = 0;
                      });
                      _resendTimer?.cancel();
                    },
              child: Text(
                localeService.tr('auth_phone_change_number'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
