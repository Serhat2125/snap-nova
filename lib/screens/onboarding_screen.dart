import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'camera_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  QuAlsar Onboarding — QandA / Solvely tarzı, 5 aşamalı akış
//  1. Hero hoş geldin + sosyal kanıt
//  2. Fotoğraftan çöz (animasyonlu soru demo)
//  3. Her derste (ders grid)
//  4. Sınıf seçimi (soft segmentation)
//  5. Bildirim izni priming
// ═════════════════════════════════════════════════════════════════════════════

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// İlk açılış kontrolü için SharedPreferences anahtarı.
  static const String prefKey = 'onboarding_done_v2';

  /// Seçilen sınıf/seviye bilgisi (isteğe bağlı, gelecekte kullanılabilir)
  static const String gradePrefKey = 'user_grade_level';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  String? _selectedGrade;
  final _inviteCodeCtrl = TextEditingController();

  static const int _totalPages = 6;

  @override
  void dispose() {
    _pageController.dispose();
    _inviteCodeCtrl.dispose();
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
    final code = _inviteCodeCtrl.text.trim();
    if (code.length == 8 &&
        int.tryParse(code) != null &&
        prefs.getString('redeemed_invite_code') == null) {
      await prefs.setString('redeemed_invite_code', code);
      // Daveti kabul eden kullanıcıya anında 1 hafta ücretsiz premium
      final until = DateTime.now().add(const Duration(days: 7));
      await prefs.setBool('is_premium', true);
      await prefs.setString('premium_until', until.toIso8601String());
      await prefs.setString('premium_source', 'invite_redeem');
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
  }

  Future<void> _askNotifications() async {
    await Permission.notification.request();
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _totalPages - 1;
    final isGrade = _currentPage == 3;
    final canContinue = !isGrade || _selectedGrade != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Üst bar: geri + progress + atla
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: _currentPage > 0
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back_rounded,
                                color: AppColors.textSecondary, size: 22),
                            onPressed: _goBack,
                          )
                        : null,
                  ),
                  Expanded(
                    child: _ProgressBar(
                        current: _currentPage, total: _totalPages),
                  ),
                  SizedBox(
                    width: 60,
                    child: isLast
                        ? null
                        : TextButton(
                            onPressed: _finish,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Atla',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            // Sayfalar
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  const _HeroPage(),
                  const _SnapDemoPage(),
                  const _SubjectsPage(),
                  _GradePage(
                    selected: _selectedGrade,
                    onSelect: (g) => setState(() => _selectedGrade = g),
                  ),
                  _InviteCodePage(controller: _inviteCodeCtrl),
                  const _NotificationPage(),
                ],
              ),
            ),
            // Alt buton
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: _CtaButton(
                label: _ctaLabel(),
                enabled: canContinue,
                onTap: () async {
                  if (!canContinue) return;
                  if (_currentPage == _totalPages - 1) {
                    await _askNotifications();
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
    switch (_currentPage) {
      case 0:
        return 'Başlayalım';
      case 3:
        return _selectedGrade == null ? 'Bir seçenek seç' : 'Devam Et';
      case 4:
        return 'Devam Et';
      case 5:
        return 'Bildirimleri Aç & Başla';
      default:
        return 'Devam';
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sayfa 5 — Davet kodu (opsiyonel)
// ═════════════════════════════════════════════════════════════════════════════

class _InviteCodePage extends StatelessWidget {
  final TextEditingController controller;
  const _InviteCodePage({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text('🎁', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text(
            'Davet kodun var mı?',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Bir arkadaşın seni davet ettiyse 8 haneli kodunu gir. '
            'Kod girmek zorunlu değil — atlayabilirsin.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFE5E7EB),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 8,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: '––––––––',
                counterText: '',
                hintStyle: TextStyle(
                  color: Color(0xFFCBD5E1),
                  letterSpacing: 6,
                  fontWeight: FontWeight.w900,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Seni davet eden arkadaşın, 3 arkadaşını tamamladığında 1 ay premium kazanır.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sayfa 1 — Hero hoş geldin
// ═════════════════════════════════════════════════════════════════════════════

class _HeroPage extends StatelessWidget {
  const _HeroPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // Glow logo
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.cyan.withValues(alpha: 0.35),
                  AppColors.cyan.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.5),
                      width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.35),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF0070FF)],
                  ).createShader(r),
                  child: const Icon(Icons.auto_awesome_rounded,
                      size: 46, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
          // Marka adı
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              colors: [AppColors.cyan, Color(0xFF0070FF)],
            ).createShader(r),
            child: const Text(
              'QuAlsar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Her soru, saniyeler içinde çözüm.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          // Sosyal kanıt
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: List.generate(
                      5,
                      (_) => const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 1),
                            child: Icon(Icons.star_rounded,
                                color: Color(0xFFFFC107), size: 20),
                          )),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 1,
                  height: 22,
                  color: AppColors.border,
                ),
                const SizedBox(width: 12),
                const Text(
                  '10M+ öğrenci',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sayfa 2 — Fotoğraftan çöz (animasyonlu demo)
// ═════════════════════════════════════════════════════════════════════════════

class _SnapDemoPage extends StatelessWidget {
  const _SnapDemoPage();

  static const _questions = [
    {
      'subject': 'Matematik',
      'question': 'x² + 5x + 6 = 0 denkleminin köklerini bulunuz.',
      'solution': 'x² + 5x + 6 = (x+2)(x+3) = 0\nx = -2  veya  x = -3',
      'explanation': 'Çarpanlarına ayırma ile kökler -2 ve -3 bulunur.',
    },
    {
      'subject': 'Fizik',
      'question': '10 kg kütleli cisme 50 N kuvvet. İvme kaçtır?',
      'solution': 'F = m·a  →  a = F/m = 50/10 = 5 m/s²',
      'explanation': 'Newton\'un 2. yasası.',
    },
    {
      'subject': 'Kimya',
      'question': 'H₂ + O₂ → H₂O tepkimesini denkleştiriniz.',
      'solution': '2H₂ + O₂ → 2H₂O',
      'explanation': '4 H ve 2 O atomu korunur.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _SectionIconBadge(
            icon: Icons.camera_alt_rounded,
            color: AppColors.cyan,
          ),
          const SizedBox(height: 20),
          const Text(
            'Fotoğrafla Çöz',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sorunun fotoğrafını çek, saniyeler içinde\nadım adım çözümünü al.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.20)),
              ),
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: _questions.length,
                separatorBuilder: (_, __) => Divider(
                  color: Colors.white.withValues(alpha: 0.07),
                  height: 1,
                ),
                itemBuilder: (_, i) => _AnimatedQuestion(q: _questions[i]),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sayfa 3 — Ders grid
// ═════════════════════════════════════════════════════════════════════════════

class _SubjectsPage extends StatelessWidget {
  const _SubjectsPage();

  static const _subjects = [
    {'icon': Icons.calculate,      'name': 'Matematik',   'color': Color(0xFF00E5FF)},
    {'icon': Icons.science,        'name': 'Fizik',        'color': Color(0xFF3B82F6)},
    {'icon': Icons.biotech,        'name': 'Kimya',        'color': Color(0xFF14B8A6)},
    {'icon': Icons.eco,            'name': 'Biyoloji',     'color': Color(0xFF22C55E)},
    {'icon': Icons.library_books,  'name': 'Edebiyat',     'color': Color(0xFF6366F1)},
    {'icon': Icons.history,        'name': 'Tarih',        'color': Color(0xFFF59E0B)},
    {'icon': Icons.map,            'name': 'Coğrafya',     'color': Color(0xFFEF4444)},
    {'icon': Icons.language,       'name': 'Dil Bilgisi',  'color': Color(0xFFF97316)},
    {'icon': Icons.psychology,     'name': 'Psikoloji',    'color': Color(0xFFA78BFA)},
    {'icon': Icons.trending_up,    'name': 'Ekonomi',      'color': Color(0xFFEC4899)},
    {'icon': Icons.code,           'name': 'Algoritma',    'color': Color(0xFF64748B)},
    {'icon': Icons.menu_book,      'name': 'Felsefe',      'color': Color(0xFFD97706)},
    {'icon': Icons.restaurant,     'name': 'Beslenme',     'color': Color(0xFF84CC16)},
    {'icon': Icons.public,         'name': 'Sosyoloji',    'color': Color(0xFF06B6D4)},
    {'icon': Icons.gavel,          'name': 'Hukuk',        'color': Color(0xFF7C3AED)},
    {'icon': Icons.auto_stories,   'name': 'Geometri',     'color': Color(0xFFC026D3)},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _SectionIconBadge(
            icon: Icons.apps_rounded,
            color: const Color(0xFF7C9CFF),
          ),
          const SizedBox(height: 20),
          const Text(
            'Her Derste Yanındayız',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Matematikten edebiyata, fizikten hukuka —\nher konuda yapay zekâ çözümün.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.18)),
              ),
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 3.2,
                  crossAxisSpacing: 8,
                ),
                itemCount: _subjects.length,
                itemBuilder: (_, i) {
                  final s = _subjects[i];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Row(children: [
                          Icon(s['icon'] as IconData,
                              color: s['color'] as Color, size: 17),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s['name'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white
                                    .withValues(alpha: 0.88),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.07),
                        height: 1,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sayfa 4 — Sınıf seçimi (soft segmentation)
// ═════════════════════════════════════════════════════════════════════════════

class _GradePage extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _GradePage({required this.selected, required this.onSelect});

  static const _grades = [
    {'label': 'İlkokul', 'icon': Icons.backpack_rounded, 'color': Color(0xFF22C55E)},
    {'label': 'Ortaokul', 'icon': Icons.school_rounded, 'color': Color(0xFF3B82F6)},
    {'label': 'Lise', 'icon': Icons.auto_stories_rounded, 'color': Color(0xFFA78BFA)},
    {'label': 'Üniversite', 'icon': Icons.workspace_premium_rounded, 'color': Color(0xFFEC4899)},
    {'label': 'Sınava Hazırlanıyorum', 'icon': Icons.emoji_events_rounded, 'color': Color(0xFFF59E0B)},
    {'label': 'Diğer', 'icon': Icons.more_horiz_rounded, 'color': Color(0xFF64748B)},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _SectionIconBadge(
            icon: Icons.person_rounded,
            color: const Color(0xFFA78BFA),
          ),
          const SizedBox(height: 20),
          const Text(
            'Seni Daha İyi Tanıyalım',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hangi seviyedesin? İçeriği sana göre\nkişiselleştirelim.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: _grades.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final g = _grades[i];
                final label = g['label'] as String;
                final isSelected = selected == label;
                final color = g['color'] as Color;
                return _GradeTile(
                  label: label,
                  icon: g['icon'] as IconData,
                  color: color,
                  selected: isSelected,
                  onTap: () => onSelect(label),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? color
                : AppColors.border.withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textPrimary,
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
//  Sayfa 5 — Bildirim izni priming
// ═════════════════════════════════════════════════════════════════════════════

class _NotificationPage extends StatelessWidget {
  const _NotificationPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // Büyük bildirim ikonu
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFC107).withValues(alpha: 0.3),
                  const Color(0xFFFFC107).withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(
                      color:
                          const Color(0xFFFFC107).withValues(alpha: 0.5),
                      width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFFFFC107).withValues(alpha: 0.3),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  size: 40,
                  color: Color(0xFFFFC107),
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
          const Text(
            'Çalışma Hedefini Kaçırma',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Bildirimleri aç — günlük hedeflerin,\nhatırlatıcıların ve önemli güncellemelerin\nhep senin yanında olsun.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary.withValues(alpha: 0.9),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          _BulletList(items: const [
            'Günlük çalışma hatırlatıcısı',
            'Çözüm tamamlandığında uyarı',
            'Yeni özellikler ve ipuçları',
          ]),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.cyan, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Ortak bileşenler
// ═════════════════════════════════════════════════════════════════════════════

class _ProgressBar extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressBar({required this.current, required this.total});

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
                color: done
                    ? AppColors.cyan
                    : Colors.white.withValues(alpha: 0.14),
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
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 18,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}

class _CtaButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _CtaButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.cyan, Color(0xFF0070FF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: enabled
                ? [
                    BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.28),
                        blurRadius: 20),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedQuestion extends StatefulWidget {
  final Map<String, String> q;
  const _AnimatedQuestion({required this.q});

  @override
  State<_AnimatedQuestion> createState() => _AnimatedQuestionState();
}

class _AnimatedQuestionState extends State<_AnimatedQuestion> {
  String _solution = '';
  String _explanation = '';
  Timer? _timer;
  int _si = 0;
  int _ei = 0;
  bool _solutionDone = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 22), (_) {
      if (!mounted) return;
      final sol = widget.q['solution']!;
      final exp = widget.q['explanation']!;
      if (_si < sol.length) {
        setState(() => _solution = sol.substring(0, ++_si));
      } else if (!_solutionDone) {
        setState(() => _solutionDone = true);
      } else if (_ei < exp.length) {
        setState(() => _explanation = exp.substring(0, ++_ei));
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          widget.q['subject']!,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.cyan,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.q['question']!,
          style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        if (_solution.isNotEmpty)
          Text(
            _solution,
            style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.65),
                height: 1.4),
          ),
        if (_explanation.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _explanation,
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.40),
                height: 1.4),
          ),
        ],
      ]),
    );
  }
}
