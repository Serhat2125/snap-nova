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
import 'package:shared_preferences/shared_preferences.dart';

import '../models/education_models.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/parent_widgets.dart';
import 'notifications_inbox_screen.dart';
import 'onboarding_screen.dart';
import 'parent_child_homeworks_screen.dart';
import 'parent_onboarding_screen.dart';
import 'parent_weekly_report_screen.dart';

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
  String? _defaultLevel; // ParentIntro'da seçilen çocuk eğitim seviyesi

  @override
  void initState() {
    super.initState();
    _loadDefaultLevel();
  }

  Future<void> _loadDefaultLevel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lvl = (prefs.getString('parent_child_default_level') ?? '').trim();
      if (lvl.isNotEmpty && mounted) setState(() => _defaultLevel = lvl);
    } catch (_) {}
  }

  Future<void> _selectChild(LinkedChild c) async {
    setState(() {
      _selectedChild = c;
      _activity = [];
      _summaries = [];
      _baseStats = null;
      _loadingChildData = true;
    });
    await _loadChildData(c);
  }

  /// Seçili çocuğun verisini (yeniden) yükler. _selectChild ile pull-to-refresh
  /// bunu paylaşır; refresh sırasında spinner'a sıfırlamadan sessiz tazeleme.
  Future<void> _loadChildData(LinkedChild c) async {
    if (!c.isActive) {
      if (mounted) setState(() => _loadingChildData = false);
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

  /// Pull-to-refresh: seçili çocuğun verisini, içeriği boşaltmadan tazeler.
  Future<void> _refresh() async {
    final c = _selectedChild;
    if (c == null || !c.isActive) return;
    await _loadChildData(c);
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
            return RefreshIndicator(
              color: const Color(0xFF10B981),
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                        UpcomingHomeworksCard(childUid: _selectedChild!.uid),
                        const SizedBox(height: 12),
                        ParentGoalCard(
                          childUid: _selectedChild!.uid,
                          last7Days: _activity,
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
                        SubjectPerformanceTable(last7Days: _activity),
                        const SizedBox(height: 12),
                        PhotoQuestionCounter(
                          totalPhotoQuestions: _activity.fold<int>(
                              0, (s, a) => s + a.photoQuestionsSolved),
                          bySubject: _aggregatePhotoBySubject(_activity),
                        ),
                        const SizedBox(height: 12),
                        StudyPlanCard(
                          childName: _selectedChild!.displayName.isEmpty
                              ? '@${_selectedChild!.username}'
                              : _selectedChild!.displayName,
                          last7Days: _activity,
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
                        const SizedBox(height: 12),
                        ParentalControlsCard(childUid: _selectedChild!.uid),
                      ]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Foto-soru ders dağılımı. Öncelik: ActivityWriter'ın yazdığı gerçek
  /// `photoBySubject` alanı. Eski/eksik kayıtlarda bu alan boşsa, o güne ait
  /// foto-sorular en aktif derse (subjectDurations) tahminen atanır.
  Map<String, int> _aggregatePhotoBySubject(List<StudentActivityModel> acts) {
    final out = <String, int>{};
    for (final a in acts) {
      if (a.photoQuestionsSolved == 0) continue;
      if (a.photoBySubject.isNotEmpty) {
        // Gerçek ders kırılımı mevcut.
        a.photoBySubject.forEach((k, v) {
          out[k] = (out[k] ?? 0) + v;
        });
        continue;
      }
      // Geriye dönük tahmin: en çok çalışılan derse yaz.
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
            // Seçili çocuğa özel aksiyonlar (bağlı ve aktifse)
            if (_selectedChild != null && _selectedChild!.isActive) ...[
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded,
                    color: Color(0xFF10B981)),
                title: Text('Haftalık rapor (PDF)'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
                subtitle: Text('Yazdır veya e-posta ile paylaş'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11, color: AppPalette.textSecondary(context))),
                onTap: () {
                  final c = _selectedChild!;
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ParentWeeklyReportScreen(
                      childName: c.displayName.isEmpty
                          ? '@${c.username}'
                          : c.displayName,
                      activity: _activity,
                      baseStats: _baseStats ?? const {},
                    ),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.assignment_turned_in_rounded,
                    color: Color(0xFF0EA5E9)),
                title: Text('Karne ve öğretmen geri bildirimi'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
                subtitle: Text(
                    (_selectedChild!.displayName.isEmpty
                            ? '@${_selectedChild!.username}'
                            : _selectedChild!.displayName) +
                        ' • ödevler, yazılı/sözlü notları, öğretmen notları'
                            .tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11, color: AppPalette.textSecondary(context))),
                onTap: () {
                  final c = _selectedChild!;
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ParentChildHomeworksScreen(
                      childUid: c.uid,
                      childName: c.displayName.isEmpty
                          ? '@${c.username}'
                          : c.displayName,
                    ),
                  ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_off_rounded,
                    color: Color(0xFFEF4444)),
                title: Text('Bağlantıyı kaldır'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700, color: ink)),
                subtitle: Text('Bu çocuğun verilerini panelden çıkar'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11, color: AppPalette.textSecondary(context))),
                onTap: () {
                  final c = _selectedChild!;
                  Navigator.pop(ctx);
                  _confirmUnlink(c);
                },
              ),
              const Divider(height: 1),
            ],
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

  Future<void> _confirmUnlink(LinkedChild c) async {
    final name = c.displayName.isEmpty ? '@${c.username}' : c.displayName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppPalette.card(dctx),
        title: Text('Bağlantıyı kaldır'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(dctx))),
        content: Text(
          '$name ile bağlantın kaldırılacak ve verileri panelinden kaybolacak. Çocuk yeniden kod paylaşırsa tekrar bağlanabilirsin.'
              .tr(),
          style: GoogleFonts.poppins(
              fontSize: 13, color: AppPalette.textSecondary(dctx), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('Vazgeç'.tr(),
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(dctx))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text('Kaldır'.tr(),
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final success = await ParentLinkService.unlinkChild(c.uid);
    if (!mounted) return;
    if (success && _selectedChild?.uid == c.uid) {
      // Stream güncelleyecek; seçimi sıfırla ki ilk çocuğa atlasın.
      setState(() {
        _selectedChild = null;
        _activity = [];
        _summaries = [];
        _baseStats = null;
      });
    }
    messenger.showSnackBar(SnackBar(
      content: Text(success
          ? 'Bağlantı kaldırıldı'.tr()
          : 'Bağlantı kaldırılamadı, tekrar dene'.tr()),
    ));
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
            if (_defaultLevel != null && _defaultLevel!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school_rounded,
                        size: 16, color: Color(0xFF10B981)),
                    const SizedBox(width: 6),
                    Text(
                      'Seçilen seviye: '.tr() + _defaultLevel!.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: const Color(0xFF065F46),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
