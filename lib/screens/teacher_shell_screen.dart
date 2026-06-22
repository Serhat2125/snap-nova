// ═══════════════════════════════════════════════════════════════════════════
//  TeacherShellScreen — Öğretmen panelinin alt-bar iskeleti.
//
//  Öğrenci tarafıyla simetrik 4 sekme + ortada büyük "➕ Oluştur" butonu:
//
//    [ 🏠 Panel ]  [ 📚 Sınıflar ]  ( ➕ )  [ 📊 Analitik ]  [ 👤 Profil ]
//
//  • Panel    → karşılama + hızlı eylemler + sınıflarım şeridi (aksiyon odaklı)
//  • Sınıflar → tüm sınıfların tam listesi → detayda Öğrenciler/Ödevler/Analiz
//  • Analitik → sınıf-üstü kıyas (Faz 3'te dolar — şimdilik "yakında")
//  • Profil   → öğretmen profili + store-zorunlu metinler (ProfileScreen)
//
//  ➕ → Yeni Sınıf / AI ile Ödev / Öğrenci Davet hızlı menüsü.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/account_service.dart';
import '../services/analytics.dart';
import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'notifications_inbox_screen.dart';
import 'profile_screen.dart';
import 'teacher_analytics_class_screen.dart';
import 'teacher_class_detail_screen.dart';
import 'teacher_invite_student_screen.dart';
import 'teacher_onboarding_screen.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherShellScreen extends StatefulWidget {
  const TeacherShellScreen({super.key});

  @override
  State<TeacherShellScreen> createState() => _TeacherShellScreenState();
}

class _TeacherShellScreenState extends State<TeacherShellScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Analytics.logFeatureOpen('teacher_panel');
  }

  void _goToTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const _TeacherClassesTab(),
      const _TeacherAnalyticsTab(),
      const ProfileScreen(),
    ];
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: tabs),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        onPressed: () => _openCreateMenu(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return BottomAppBar(
      color: AppPalette.card(context),
      elevation: 8,
      shape: const CircularNotchedRectangle(),
      notchMargin: 7,
      height: 62,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            child: Row(children: [
              _navItem(0, Icons.add_circle_outline_rounded, 'Oluştur'.tr()),
              _navItem(1, Icons.class_rounded, 'Sınıflar'.tr()),
            ]),
          ),
          const SizedBox(width: 48), // ➕ FAB boşluğu (ortada)
          Expanded(
            child: Row(children: [
              _navItem(2, Icons.person_rounded, 'Profil'.tr()),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    final selected = _index == i;
    final color = selected ? _kBrand : AppPalette.textSecondary(context);
    return Expanded(
      child: InkWell(
        onTap: () => _goToTab(i),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                )),
          ],
        ),
      ),
    );
  }

  // ── ➕ Oluştur menüsü ────────────────────────────────────────────────────
  Future<void> _openCreateMenu(BuildContext context) async {
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
            _createTile(ctx, '🏫', 'Yeni Sınıf Oluştur'.tr(),
                'Sınıf kodu üret, öğrencilerinle paylaş'.tr(), () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const TeacherOnboardingScreen(),
              ));
            }),
            _createTile(ctx, '✨', 'AI ile Ödev Oluştur'.tr(),
                'Bir sınıf seç, yapay zeka soruları üretsin'.tr(), () async {
              Navigator.pop(ctx);
              final cls = await _pickClass(context);
              if (cls == null || !context.mounted) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeacherClassDetailScreen(cls: cls),
              ));
            }),
            _createTile(ctx, '👨‍🎓', 'Öğrenci Davet Et'.tr(),
                'Kullanıcı adıyla ara ve sınıfa davet et'.tr(), () async {
              Navigator.pop(ctx);
              final cls = await _pickClass(context);
              if (cls == null || !context.mounted) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeacherInviteStudentScreen(cls: cls),
              ));
            }),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _createTile(BuildContext c, String emoji, String title,
      String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 24)),
      title: Text(title,
          style: GoogleFonts.poppins(
            fontSize: 14, fontWeight: FontWeight.w800,
            color: AppPalette.textPrimary(c),
          )),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(
            fontSize: 11.5, color: AppPalette.textSecondary(c),
          )),
      onTap: onTap,
    );
  }

  /// Bir sınıf seçtirir (ödev/davet için). Sınıf yoksa uyarır.
  Future<TeacherClass?> _pickClass(BuildContext context) async {
    final classes = await ClassService.myClassesStream().first;
    if (!context.mounted) return null;
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Önce bir sınıf oluştur.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return null;
    }
    if (classes.length == 1) return classes.first;
    return showModalBottomSheet<TeacherClass>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Sınıf seç'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(ctx),
                  )),
            ),
            ...classes.map((c) => ListTile(
                  leading: const Icon(Icons.class_rounded, color: _kBrand),
                  title: Text(c.name,
                      style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary(ctx),
                      )),
                  subtitle: Text('${c.schoolName} · ${c.subject}',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5, color: AppPalette.textSecondary(ctx),
                      )),
                  onTap: () => Navigator.pop(ctx, c),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
//  SEKME 2 — SINIFLAR (tam liste)
// ═══════════════════════════════════════════════════════════════════════════
class _TeacherClassesTab extends StatelessWidget {
  const _TeacherClassesTab();

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 6),
          child: Row(
            children: [
              const Text('👨‍🏫', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Sınıflarım'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w900, color: ink,
                    )),
              ),
              IconButton(
                icon: Icon(Icons.notifications_rounded,
                    color: AppPalette.textSecondary(context)),
                tooltip: 'Bildirimler'.tr(),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NotificationsInboxScreen(),
                )),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<TeacherClass>>(
            stream: ClassService.myClassesStream(),
            builder: (context, snap) {
              if (snap.hasError) return _empty(context, ink);
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final classes = snap.data ?? const <TeacherClass>[];
              if (classes.isEmpty) return _empty(context, ink);
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
                itemCount: classes.length,
                itemBuilder: (ctx, i) => TeacherClassCard(cls: classes[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, Color ink) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👨‍🏫', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('Henüz sınıf yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w900, color: ink,
                )),
            const SizedBox(height: 8),
            Text('Sağ alttaki ➕ ile ilk sınıfını oluştur.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13, color: AppPalette.textSecondary(context),
                  height: 1.45,
                )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Paylaşılan sınıf kartı (Panel + Sınıflar sekmesi) — canlı öğrenci sayısı +
//  kopyalanabilir kod + detaya geçiş.
// ═══════════════════════════════════════════════════════════════════════════
class TeacherClassCard extends StatelessWidget {
  final TeacherClass cls;
  const TeacherClassCard({super.key, required this.cls});

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeacherClassDetailScreen(cls: cls),
        )),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _kBrand.withValues(alpha: 0.12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.class_rounded,
                        color: _kBrand, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cls.name,
                            style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${cls.schoolName} · ${cls.subject}',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5, color: muted,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  _StudentCountBadge(classId: cls.id),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Katılma kodu'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: muted, letterSpacing: 0.3,
                        )),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                            ClipboardData(text: cls.shortCode));
                        messenger.showSnackBar(SnackBar(
                          content: Text('Sınıf kodu kopyalandı'.tr()),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: AppPalette.bg(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _kBrand.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🔑', style: TextStyle(fontSize: 15)),
                            const SizedBox(width: 8),
                            Text(cls.shortCode,
                                style: GoogleFonts.poppins(
                                  fontSize: 15, fontWeight: FontWeight.w900,
                                  color: ink, letterSpacing: 1.5,
                                )),
                            const SizedBox(width: 8),
                            const Icon(Icons.copy_rounded,
                                size: 16, color: _kBrand),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sınıftaki canlı öğrenci sayısı rozeti.
class _StudentCountBadge extends StatelessWidget {
  final String classId;
  const _StudentCountBadge({required this.classId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClassStudent>>(
      stream: ClassService.studentsStream(classId),
      builder: (context, snap) {
        final n = snap.data?.length ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _kBrand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_alt_rounded, size: 13, color: _kBrand),
              const SizedBox(width: 4),
              Text('$n',
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w800, color: _kBrand,
                  )),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SEKME 3 — ANALİTİK (Faz 3'te dolacak)
// ═══════════════════════════════════════════════════════════════════════════
class _TeacherAnalyticsTab extends StatelessWidget {
  const _TeacherAnalyticsTab();

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Text('Analitik'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w900, color: ink,
                  )),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Builder(builder: (context) {
            final branch = AccountService.instance.teacherBranch;
            final txt = (branch != null && branch.trim().isNotEmpty)
                ? '${'Branşın'.tr()}: $branch · '
                    '${'bir sınıf seç ve performansı gör'.tr()}'
                : 'Bir sınıf seç, öğrencilerin ödev performansını gör.'.tr();
            return Text(txt,
                style: GoogleFonts.poppins(
                  fontSize: 12.5, color: AppPalette.textSecondary(context),
                ));
          }),
        ),
        Expanded(
          child: StreamBuilder<List<TeacherClass>>(
            stream: ClassService.myClassesStream(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final classes = snap.data ?? const <TeacherClass>[];
              if (classes.isEmpty) return _empty(context, ink);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                ),
                itemCount: classes.length,
                itemBuilder: (ctx, i) => _classTile(context, classes[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _classTile(BuildContext context, TeacherClass cls) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeacherAnalyticsClassScreen(cls: cls),
        )),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _kBrand.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.class_rounded,
                    color: _kBrand, size: 22),
              ),
              const Spacer(),
              Text(cls.name,
                  style: GoogleFonts.poppins(
                    fontSize: 15.5, fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(context),
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(cls.subject,
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(context),
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.people_alt_rounded, size: 14,
                      color: AppPalette.textSecondary(context)),
                  const SizedBox(width: 4),
                  Text('${cls.studentCount} ${'öğrenci'.tr()}',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w700,
                        color: AppPalette.textSecondary(context),
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, Color ink) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏫', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('Henüz sınıf yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w900, color: ink,
                )),
            const SizedBox(height: 8),
            Text('Önce bir sınıf oluştur, sonra öğrenci performansını '
                'buradan izle.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13, color: AppPalette.textSecondary(context),
                  height: 1.45,
                )),
          ],
        ),
      ),
    );
  }
}
