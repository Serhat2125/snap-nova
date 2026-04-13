import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'camera_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage == 0) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeInOutCubic,
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CameraScreen()),
      );
    }
  }

  void _back() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentPage = i),
        physics: const BouncingScrollPhysics(),
        children: [
          _Page1(onNext: _next),
          _Page2(onNext: _next, onBack: _back),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Sayfa 1 — Logo + animasyonlu soru listesi
// ═══════════════════════════════════════════════════════════════════════════════

class _Page1 extends StatelessWidget {
  final VoidCallback onNext;
  const _Page1({required this.onNext});

  static const _questions = [
    {
      'subject': 'Matematik',
      'question': 'x² + 5x + 6 = 0 denkleminin köklerini bulunuz.',
      'solution': 'x² + 5x + 6 = (x+2)(x+3) = 0\nx = -2  veya  x = -3',
      'explanation': 'Çarpanlarına ayırma yöntemi ile kökler -2 ve -3 bulunur.',
    },
    {
      'subject': 'Fizik',
      'question': '10 kg kütleli cisme 50 N kuvvet. İvme kaçtır?',
      'solution': 'F = m·a  →  a = F/m = 50/10 = 5 m/s²',
      'explanation': 'Newton\'un 2. yasası: kuvvet arttıkça ivme artar.',
    },
    {
      'subject': 'Kimya',
      'question': 'H₂ + O₂ → H₂O tepkimesini denkleştiriniz.',
      'solution': 'Adım 1: 2H₂O yaz  →  Adım 2: 2H₂ ekle\nSonuç: 2H₂ + O₂ → 2H₂O',
      'explanation': 'Her iki tarafta 4 H ve 2 O atomu korunur.',
    },
    {
      'subject': 'Biyoloji',
      'question': 'Fotosentezin temel denklemini yazınız.',
      'solution': '6CO₂ + 6H₂O → C₆H₁₂O₆ + 6O₂',
      'explanation': 'Işık enerjisiyle karbondioksit ve su glikoza dönüşür.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // ── Logo ──────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        colors: [AppColors.cyan, Color(0xFF0070FF)],
                      ).createShader(r),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 42),
                    ),
                    const SizedBox(width: 10),
                    ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        colors: [AppColors.cyan, Color(0xFF0070FF)],
                      ).createShader(r),
                      child: const Text(
                        'SnapNova',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),
                Text(
                  'Her soruyu anında çözer.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.50),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Soru listesi ──────────────────────────────────────
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.22)),
                    ),
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: _questions.length,
                      separatorBuilder: (_, __) => Divider(
                        color: Colors.white.withValues(alpha: 0.07),
                        height: 1,
                        thickness: 1,
                      ),
                      itemBuilder: (_, i) =>
                          _AnimatedQuestion(q: _questions[i]),
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                _ActionButton(label: 'Başla', onTap: onNext),
                const SizedBox(height: 16),
                _PageDots(current: 0, total: 2),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Sayfa 2 — Ders grid
// ═══════════════════════════════════════════════════════════════════════════════

class _Page2 extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  const _Page2({required this.onNext, required this.onBack});

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
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Back
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.cyan, size: 22),
                    onPressed: onBack,
                  ),
                ),

                // Header card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        ShaderMask(
                          shaderCallback: (r) => const LinearGradient(
                            colors: [AppColors.cyan, Color(0xFF0070FF)],
                          ).createShader(r),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 8),
                        ShaderMask(
                          shaderCallback: (r) => const LinearGradient(
                            colors: [AppColors.cyan, Color(0xFF0070FF)],
                          ).createShader(r),
                          child: const Text(
                            'SnapNova',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      const Text(
                        'Her derste, her konuda istediğini sor.\nSnapNova anında çözsün.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Grid
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(24),
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
                        mainAxisSpacing: 0,
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
                              thickness: 1,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                _ActionButton(label: 'Hemen Başla', onTap: onNext),
                const SizedBox(height: 16),
                _PageDots(current: 1, total: 2),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Ortak bileşenler
// ═══════════════════════════════════════════════════════════════════════════════

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
        setState(() {
          _solution = sol.substring(0, ++_si);
        });
      } else if (!_solutionDone) {
        setState(() => _solutionDone = true);
      } else if (_ei < exp.length) {
        setState(() {
          _explanation = exp.substring(0, ++_ei);
        });
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

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.cyan, Color(0xFF0070FF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: AppColors.cyan.withValues(alpha: 0.28),
                blurRadius: 20)
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int current;
  final int total;
  const _PageDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 4,
          width: active ? 28 : 10,
          decoration: BoxDecoration(
            color: active ? AppColors.cyan : Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }),
    );
  }
}
