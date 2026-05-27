// ═══════════════════════════════════════════════════════════════════════════
//  ParentDashboardScreen — Ebeveynin ana ekranı (genişletilmiş).
//
//  Yapı:
//    1. Bağlı çocuklar şeridi (üstte avatar listesi, çocuk seç)
//    2. Seçili çocuğun analitiği:
//       • AcademicSummaryCard (haftalık özet + streak + odak dakika)
//       • WeeklyStudyChart (BarChart)
//       • SubjectSuccessChart (LineChart)
//       • QuestionAnalyticsPie (PieChart)
//       • PhotoQuestionCounter (foto-soru sayacı)
//       • HorizontalSummariesScroll (son özetler)
//       • AiInsightsBox (Gemini analiz)
//    3. + Çocuk ekle butonu (FAB)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/parent_widgets.dart';
import 'notifications_inbox_screen.dart';
import 'onboarding_screen.dart';
import 'parent_onboarding_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  LinkedChild? _selectedChild;
  List<StudentActivityModel> _activity = [];
  List<Map<String, dynamic>> _summaries = [];
  Map<String, dynamic>? _baseStats;
  bool _loadingChildData = false;

  Future<void> _selectChild(LinkedChild c) async {
    setState(() {
      _selectedChild = c;
      _activity = [];
      _summaries = [];
      _baseStats = null;
      _loadingChildData = true;
    });
    if (!c.isActive) {
      setState(() => _loadingChildData = false);
      return;
    }
    try {
      final results = await Future.wait([
        ParentLinkService.readChild7DayActivity(c.uid),
        ParentLinkService.readChildRecentSummaries(c.uid),
        ParentLinkService.readChildStats(c.uid),
      ]);
      if (!mounted) return;
      setState(() {
        _activity = (results[0] as List<Map<String, dynamic>>)
            .map(StudentActivityModel.fromJson).toList();
        _summaries = results[1] as List<Map<String, dynamic>>;
        _baseStats = results[2] as Map<String, dynamic>;
        _loadingChildData = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingChildData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
              ),
              alignment: Alignment.center,
              child: const Text('👨‍👩‍👧', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 10),
            Text('Ebeveyn Paneli'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w800, color: ink,
                )),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_rounded, color: ink),
            tooltip: 'Bildirimler'.tr(),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const NotificationsInboxScreen(),
            )),
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: ink),
            tooltip: 'Menü'.tr(),
            onPressed: () => _showSettingsSheet(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ParentOnboardingScreen(),
        )),
        icon: const Icon(Icons.person_add_rounded, size: 20),
        label: Text('Çocuk Ekle'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w800,
            )),
      ),
      body: SafeArea(
        child: StreamBuilder<List<LinkedChild>>(
          stream: ParentLinkService.linkedChildrenStream(),
          builder: (context, snap) {
            // Hata ya da veri yokken empty CTA — spinner'a takılmasın.
            if (snap.hasError) return _buildEmpty(context);
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final children = snap.data ?? const <LinkedChild>[];
            if (children.isEmpty) return _buildEmpty(context);
            // İlk açılışta veya seçili çocuk silindiyse ilk çocuğa atla
            if (_selectedChild == null ||
                !children.any((c) => c.uid == _selectedChild!.uid)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _selectChild(children.first);
              });
            }
            return CustomScrollView(
              slivers: [
                // Çocuk seçici şerit
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 86,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      itemCount: children.length,
                      itemBuilder: (ctx, i) {
                        final c = children[i];
                        final sel = c.uid == _selectedChild?.uid;
                        return GestureDetector(
                          onTap: () => _selectChild(c),
                          child: Container(
                            width: 70,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: sel
                                  ? const Color(0xFF10B981)
                                      .withValues(alpha: 0.10)
                                  : AppPalette.card(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFF10B981)
                                    : AppPalette.border(context),
                                width: sel ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(c.avatar,
                                    style: const TextStyle(fontSize: 28)),
                                const SizedBox(height: 2),
                                Text(c.username,
                                    style: GoogleFonts.poppins(
                                      fontSize: 10, fontWeight: FontWeight.w700,
                                      color: sel
                                          ? const Color(0xFF065F46)
                                          : AppPalette.textSecondary(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                if (c.isPending)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text('Bekliyor'.tr(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFFB45309),
                                        )),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Seçili çocuk içeriği
                if (_selectedChild == null)
                  SliverFillRemaining(
                    child: Center(
                      child: Text('Çocuk seç'.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: AppPalette.textSecondary(context))),
                    ),
                  )
                else if (_selectedChild!.isPending)
                  SliverToBoxAdapter(child: _pendingNotice(context))
                else if (_loadingChildData)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        _AcademicSummaryCard(
                          child: _selectedChild!,
                          activity: _activity,
                          baseStats: _baseStats ?? const {},
                        ),
                        const SizedBox(height: 12),
                        WeeklyStudyChart(last7Days: _activity),
                        const SizedBox(height: 12),
                        SubjectSuccessChart(last7Days: _activity),
                        const SizedBox(height: 12),
                        QuestionAnalyticsPie(
                          correct: _activity.fold<int>(
                              0, (s, a) => s + a.correctAnswers),
                          wrong: _activity.fold<int>(
                              0, (s, a) => s + a.wrongAnswers),
                          blank: _activity.fold<int>(
                              0, (s, a) => s + a.blankAnswers),
                        ),
                        const SizedBox(height: 12),
                        PhotoQuestionCounter(
                          totalPhotoQuestions: _activity.fold<int>(
                              0, (s, a) => s + a.photoQuestionsSolved),
                          bySubject: _aggregatePhotoBySubject(_activity),
                        ),
                        const SizedBox(height: 12),
                        HorizontalSummariesScroll(summaries: _summaries),
                        const SizedBox(height: 12),
                        AiInsightsBox(
                          childName: _selectedChild!.displayName.isEmpty
                              ? '@${_selectedChild!.username}'
                              : _selectedChild!.displayName,
                          last7Days: _activity,
                        ),
                      ]),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Activity verisinde foto-soru ders dağılımı yoksa subjectDurations'tan
  /// kabaca türetilebilir; gerçek subjectBySubject alanı varsa onu kullan.
  Map<String, int> _aggregatePhotoBySubject(List<StudentActivityModel> acts) {
    final out = <String, int>{};
    for (final a in acts) {
      // En aktif derslere göre dağıt — foto-soru ders bazlı veri yoksa
      // tahminen subjectDurations en yüksek olana yaz.
      if (a.photoQuestionsSolved == 0) continue;
      String? topSubject;
      int topSecs = 0;
      a.subjectDurations.forEach((k, v) {
        if (v > topSecs) { topSecs = v; topSubject = k; }
      });
      if (topSubject != null) {
        out[topSubject!] = (out[topSubject!] ?? 0) + a.photoQuestionsSolved;
      }
    }
    return out;
  }

  Widget _pendingNotice(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFBBF24).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            const Text('⏳', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text('Çocuğun onayı bekleniyor'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: const Color(0xFF92400E),
                )),
            const SizedBox(height: 6),
            Text(
              'Çocuğun uygulamayı açıp profil sekmesinden ebeveyn isteğini onaylaması gerekiyor. Onayladığında istatistikleri burada görünür.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12, color: AppPalette.textSecondary(c),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettingsSheet(BuildContext context) async {
    final ink = AppPalette.textPrimary(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_rounded,
                  color: Color(0xFF10B981)),
              title: Text('Yeni çocuk ekle'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ParentOnboardingScreen(),
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded,
                  color: Color(0xFF7C3AED)),
              title: Text('Hesap tipini değiştir'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
              subtitle: Text('Öğrenci veya öğretmen moduna geç'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(context))),
              onTap: () async {
                Navigator.pop(ctx);
                await AccountService.instance.setType(AccountType.student);
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => OnboardingScreen()),
                  (r) => false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: Color(0xFFEF4444)),
              title: Text('Çıkış yap'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: const Color(0xFFEF4444))),
              onTap: () async {
                Navigator.pop(ctx);
                await AuthService.signOut();
                await AccountService.instance.clear();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => OnboardingScreen()),
                  (r) => false,
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF10B981).withValues(alpha: 0.10),
              ),
              alignment: Alignment.center,
              child: const Text('👨‍👩‍👧', style: TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 18),
            Text('Henüz çocuk bağlı değil'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 8),
            Text(
              'Sağ alttaki + butonuna basıp çocuğunun kullanıcı adını ekleyebilirsin.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(context),
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 1. Academic Summary Card (kombine üst kart) ──────────────────────
class _AcademicSummaryCard extends StatelessWidget {
  final LinkedChild child;
  final List<StudentActivityModel> activity;
  final Map<String, dynamic> baseStats;
  const _AcademicSummaryCard({
    required this.child, required this.activity, required this.baseStats,
  });

  @override
  Widget build(BuildContext context) {
    final totalMins = activity.fold<int>(
      0, (s, a) => s + (a.focusSeconds ~/ 60));
    final hours = (totalMins / 60).toStringAsFixed(1);
    final streak = (baseStats['streakDays'] ?? 0) as int;
    final summaryCount = activity.fold<int>(0, (s, a) => s + a.summariesCreated);
    final testCount = activity.fold<int>(0, (s, a) => s + a.testsSolved);
    final photoCount = activity.fold<int>(0, (s, a) => s + a.photoQuestionsSolved);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.30),
            blurRadius: 16, offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(child.avatar, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.displayName.isEmpty
                          ? '@${child.username}'
                          : child.displayName,
                      style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    Text('Son 7 gün özeti'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.white.withValues(alpha: 0.85),
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat('⏱️', '$hours sa', 'Odak'.tr()),
              _miniStat('🔥', '$streak g', 'Streak'.tr()),
              _miniStat('📚', '$summaryCount', 'Özet'.tr()),
              _miniStat('📐', '$testCount', 'Test'.tr()),
              _miniStat('📸', '$photoCount', 'Foto'.tr()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String emoji, String val, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 1),
            Text(val,
                style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
