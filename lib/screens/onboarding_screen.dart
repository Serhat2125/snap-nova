import 'dart:async';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show localeService;
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

  static const int _totalPages = 5;
  static const int _gradePageIndex = 4;

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
  static const _accentPerPage = <Color>[
    AppColors.cyan,              // Hero
    AppColors.cyan,              // Solve
    Color(0xFFA78BFA),           // Create (purple)
    Color(0xFFFF6A00),           // Compete (orange)
    Color(0xFF22C55E),           // Grade (green)
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
    if (_selectedGrade != null) {
      await prefs.setString(OnboardingScreen.gradePrefKey, _selectedGrade!);
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // LocaleInherited'a bağımlılık — setLocale sonrası ekran yeniden kurulur.
    final locale = LocaleInherited.of(context);
    final accent = _accentPerPage[_currentPage];
    final isGrade = _currentPage == _gradePageIndex;
    final isLast = _currentPage == _totalPages - 1;
    final isHero = _currentPage == 0;
    final canContinue = !isGrade || _selectedGrade != null;
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
                            localeService.tr('language_selection'),
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
                  _FeaturePage(
                    accent: _accentPerPage[1],
                    headerGraphic: _SubjectCarousel(color: _accentPerPage[1]),
                    titleKey: 'onb_solve_title',
                    subtitleKey: 'onb_solve_subtitle',
                    bulletKeys: const [
                      ('onb_solve_b1_title', 'onb_solve_b1_desc'),
                      ('onb_solve_b2_title', 'onb_solve_b2_desc'),
                      ('onb_solve_b3_title', 'onb_solve_b3_desc'),
                    ],
                  ),
                  _FeaturePage(
                    accent: _accentPerPage[2],
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
                    accent: _accentPerPage[3],
                    icon: Icons.auto_stories_rounded,
                    titleKey: 'onb_library_title',
                    subtitleKey: 'onb_library_subtitle',
                    bulletKeys: const [
                      ('onb_library_b1_title', 'onb_library_b1_desc'),
                      ('onb_library_b2_title', 'onb_library_b2_desc'),
                      ('onb_library_b3_title', 'onb_library_b3_desc'),
                    ],
                  ),
                  _GradePage(
                    accent: _accentPerPage[4],
                    selected: _selectedGrade,
                    onSelect: (g) => setState(() => _selectedGrade = g),
                  ),
                ],
              ),
            ),

            // ── Alt CTA ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: _CtaButton(
                label: _ctaLabel(),
                accent: accent,
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
    if (_currentPage == _gradePageIndex) {
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
        const quAlsarHeight = 42.0;
        const gap = 36.0;

        // Logo merkezi — ekran yüksekliğinin %38'inde (dikey ortanın belirgin
        // şekilde üstü). Yazı logonun üstünde, etiketler logonun altından.
        final centerY = constraints.maxHeight * 0.38;
        final logoTop = centerY - logoSize / 2;
        final logoBottom = centerY + logoSize / 2;
        final quAlsarTop = logoTop - gap - quAlsarHeight;
        // Ülke etiketlerinin başlayacağı y (logonun alt kenarı + küçük pay).
        final labelsMinY = logoBottom + 8;

        return Container(
          color: Colors.white,
          child: Stack(
            children: [
              // Arkaplan — logonun altından itibaren rastgele konumlarda ülke
              // bayrağı + adı (1s yaşam, hafif dönüşle).
              Positioned.fill(child: _CountryFlagStream(minY: labelsMinY)),
              // Dönen logo — ekranın üst %38'inde.
              Positioned(
                top: logoTop,
                left: 0,
                right: 0,
                child: Center(child: QuAlsarLogoMark(size: logoSize)),
              ),
              // QuAlsar yazısı — yatayda ortalı, logonun üstünde.
              Positioned(
                top: quAlsarTop,
                left: 0,
                right: 0,
                child: const Center(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 34,
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
          Text(
            localeService.tr(titleKey),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            localeService.tr(subtitleKey),
            textAlign: TextAlign.center,
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

class _GradePage extends StatelessWidget {
  final Color accent;
  final String? selected;
  final ValueChanged<String> onSelect;
  const _GradePage({
    required this.accent,
    required this.selected,
    required this.onSelect,
  });

  static const _grades = <_GradeOption>[
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
      key: 'adult',
      labelKey: 'onb_grade_adult',
      icon: Icons.person_rounded,
      color: Color(0xFF06B6D4),
    ),
    _GradeOption(
      key: 'other',
      labelKey: 'onb_grade_other',
      icon: Icons.more_horiz_rounded,
      color: Color(0xFF64748B),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _SectionIconBadge(icon: Icons.tune_rounded, color: accent),
          const SizedBox(height: 20),
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
          const SizedBox(height: 10),
          Text(
            localeService.tr('onb_grade_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.62),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: _grades.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final g = _grades[i];
                final isSelected = selected == g.key;
                return _GradeTile(
                  label: localeService.tr(g.labelKey),
                  icon: g.icon,
                  color: g.color,
                  selected: isSelected,
                  onTap: () => onSelect(g.key),
                );
              },
            ),
          ),
        ],
      ),
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

class _GradeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _GradeTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.10)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.black.withValues(alpha: 0.10),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.black
                      : Colors.black.withValues(alpha: 0.82),
                  letterSpacing: -0.1,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: color, size: 22),
          ],
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
