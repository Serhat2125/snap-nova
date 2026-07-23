// ═══════════════════════════════════════════════════════════════════════════
//  TeacherShellScreen — Öğretmen panelinin alt-bar iskeleti.
//
//  2 sekme + ortada büyük "➕ Oluştur" FAB'ı (ayrı "Oluştur"/"Analitik" YOK):
//
//    [ 📚 Sınıflar ]  ( ➕ )  [ 👤 Profil ]
//
//  • Sınıflar → tüm sınıfların tam listesi → detayda Öğrenciler/Ödevler/Analiz
//  • Profil   → öğretmen profili + store-zorunlu metinler (ProfileScreen)
//
//  ➕ → Yeni Sınıf / AI ile Ödev / Öğrenci Davet hızlı menüsü (merkez FAB).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/education_models.dart';
import '../services/account_service.dart';
import '../services/analytics.dart';
import '../services/class_service.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/class_profile_dialog.dart';
import 'notifications_inbox_screen.dart';
import 'profile_screen.dart';
import 'teacher_announcement_screen.dart';
import 'teacher_class_detail_screen.dart';
import 'teacher_create_homework_screen.dart';
import 'teacher_curriculum_select_screen.dart';
import 'teacher_invite_student_screen.dart';
import 'teacher_all_pending_screen.dart';
import 'teacher_material_screen.dart';
import 'teacher_onboarding_screen.dart';
import 'teacher_pending_homeworks_screen.dart';

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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _ensureCurriculumSelected());
  }

  /// Öğretmen henüz not sistemini (müfredatını) seçmediyse ilk açılışta seçtirir.
  Future<void> _ensureCurriculumSelected() async {
    if (!mounted) return;
    final acc = AccountService.instance;
    if (!acc.isTeacher || acc.gradingCountry != null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const TeacherCurriculumSelectScreen(),
    ));
    if (mounted) setState(() {});
  }

  void _goToTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const _TeacherClassesTab(),
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
        onPressed: () {
          // Profil sekmesindeyken ➕ → önce Sınıflar sekmesine geç; menü
          // kapanınca öğretmen kendini profilde değil sınıflarında bulur.
          if (_index != 0) setState(() => _index = 0);
          _openCreateMenu(context);
        },
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
      // İki sekme ➕ FAB'ın iki yanında simetrik: solda Sınıflar, sağda Profil,
      // ortada ➕. "Oluştur" ayrı sekme değil; oluşturma ortadaki FAB.
      child: Row(
        children: [
          _navItem(0, Icons.class_rounded, 'Sınıflar'.tr()),
          const SizedBox(width: 48), // ➕ FAB boşluğu (tam ortada)
          _navItem(1, Icons.person_rounded, 'Profil'.tr()),
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

  // ── ➕ Oluştur menüsü — + hizasında yukarı açılan kompakt kartlar ───────
  Future<void> _openCreateMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => GestureDetector(
        // Kart DIŞINDA kalan şeffaf alanlar da sheet'in parçası — oralara
        // dokununca da menü hemen kapansın (yalnız üstteki barrier değil).
        behavior: HitTestBehavior.translucent,
        onTap: () => Navigator.pop(ctx),
        child: SafeArea(
        child: Padding(
          // Ortadaki ➕ FAB + alt bar üstünde, hizasında yukarı açılır.
          padding: const EdgeInsets.only(bottom: 78, left: 16, right: 16),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: GestureDetector(
                onTap: () {/* kartın kendisine dokunuş menüyü kapatmasın */},
                child: Container(
                // Tüm seçenekleri saran tek dış çerçeve.
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                decoration: BoxDecoration(
                  color: AppPalette.card(ctx),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: _kBrand.withValues(alpha: 0.30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18, offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  _createChip(ctx, '🏫', 'Yeni Sınıf Oluştur'.tr(), () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TeacherOnboardingScreen()));
                  }),
                  _createChip(ctx, '✨', 'AI ile Ödev Oluştur'.tr(), () async {
                    Navigator.pop(ctx);
                    final picked = await _pickClassesForHomework(context);
                    if (picked == null ||
                        picked.isEmpty ||
                        !context.mounted) {
                      return;
                    }
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          TeacherCreateHomeworkScreen(classes: picked)));
                  }),
                  _createChip(ctx, '👨‍🎓', 'Öğrenci Davet Et'.tr(), () async {
                    Navigator.pop(ctx);
                    final cls = await _pickClass(context);
                    if (cls == null || !context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TeacherInviteStudentScreen(cls: cls)));
                  }),
                  _createChip(ctx, '📢', 'Duyuru Yayınla'.tr(), () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TeacherAnnouncementScreen()));
                  }),
                  _createChip(ctx, '📎', 'Kaynak Paylaş'.tr(), () async {
                    Navigator.pop(ctx);
                    final cls = await _pickClass(context);
                    if (cls == null || !context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TeacherMaterialScreen(cls: cls)));
                  }),
                  ],
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

  // Kompakt oval kart — küçük ikon + başlık (kendi çerçevesi + gölgesi).
  Widget _createChip(BuildContext c, String emoji, String title,
      VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppPalette.bg(c),
        elevation: 0,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _kBrand.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 15)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(c),
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
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
      backgroundColor: const Color(0xFFF3F4F6), // solgun beyaz arka plan
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Sınıf seç'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  )),
              const SizedBox(height: 14),
              // Her sınıf — tam beyaz çerçeve, ortalı, profil fotolu, ikonsuz.
              ...classes.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, c),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ClassAvatar(photoB64: c.photoB64, size: 38),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(c.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF111827),
                                    )),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  /// AI Ödev için ÇOKLU sınıf seçtirir (ortada, dar, "Devam Et" onaylı).
  /// Boş/iptal → null. Tek sınıf varsa onu döndürür (seçim ekranı gereksiz).
  Future<List<TeacherClass>?> _pickClassesForHomework(
      BuildContext context) async {
    final classes = await ClassService.myClassesStream().first;
    if (!context.mounted) return null;
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Önce bir sınıf oluştur.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return null;
    }
    if (classes.length == 1) return [classes.first];

    final selected = <String>{};
    const green = Color(0xFF16A34A);
    return showDialog<List<TeacherClass>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFF3F4F6),
        // Dar (yatay 34px boşluk) + merkezden %20 aşağıda konumlan.
        alignment: const Alignment(0, 0.2),
        insetPadding: const EdgeInsets.symmetric(horizontal: 34, vertical: 24),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22)),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            final hasSel = selected.isNotEmpty;
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Sınıf seç'.tr(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: const Color(0xFF111827),
                      )),
                  const SizedBox(height: 4),
                  Text('Birden fazla sınıf seçebilirsin'.tr(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w500,
                        color: const Color(0xFF9CA3AF),
                      )),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final c in classes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setLocal(() {
                                    if (!selected.add(c.id)) {
                                      selected.remove(c.id);
                                    }
                                  }),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: selected.contains(c.id)
                                            ? green
                                            : const Color(0xFFE5E7EB),
                                        width: selected.contains(c.id)
                                            ? 1.6 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ClassAvatar(
                                            photoB64: c.photoB64, size: 38),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(c.name,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    const Color(0xFF111827),
                                              )),
                                        ),
                                        Icon(
                                          selected.contains(c.id)
                                              ? Icons.check_circle_rounded
                                              : Icons
                                                  .radio_button_unchecked,
                                          color: selected.contains(c.id)
                                              ? green
                                              : const Color(0xFFD1D5DB),
                                          size: 22,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: hasSel
                          ? () => Navigator.pop(
                              ctx,
                              classes
                                  .where((c) => selected.contains(c.id))
                                  .toList())
                          : null,
                      child: Text('Devam Et'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: hasSel
                                ? Colors.white
                                : const Color(0xFF9CA3AF),
                          )),
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
                itemCount: classes.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) return _TeacherHomeHeader(classCount: classes.length);
                  return TeacherClassCard(cls: classes[i - 1]);
                },
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
        onLongPress: () => _showManageMenu(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── SOL: profil avatarı + sağında sınıf adı; altında okul + durum ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Avatara basınca fotoğraf + durum mesajı çerçevesi açılır.
                        GestureDetector(
                          onTap: () => showClassProfileDialog(context, cls),
                          child: ClassAvatar(photoB64: cls.photoB64, size: 44),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(cls.name,
                              style: GoogleFonts.poppins(
                                fontSize: 16, fontWeight: FontWeight.w800,
                                color: ink,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(cls.schoolName,
                        style: GoogleFonts.poppins(
                          fontSize: 10.5,
                          color: muted.withValues(alpha: 0.7),
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (cls.statusMessage.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('💬 ${cls.statusMessage.trim()}',
                            style: GoogleFonts.poppins(
                              fontSize: 11, fontStyle: FontStyle.italic,
                              color: _kBrand,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    _PendingHomeworkBadge(cls: cls),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // ── SAĞ: Katılma kodu etiketi + kod kutusu + öğrenci sayısı.
              //    IntrinsicWidth + stretch → üçü de AYNI genişlikte (kutuya
              //    göre), başlangıç ve bitiş hizaları aynı. ──
              IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Kompakt katılma kodu chip'i (dokun → kopyala).
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
                        padding:
                            const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: _kBrand.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _kBrand.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.vpn_key_rounded,
                                size: 12, color: _kBrand),
                            const SizedBox(width: 5),
                            Text(cls.shortCode,
                                style: GoogleFonts.poppins(
                                  fontSize: 12.5, fontWeight: FontWeight.w900,
                                  color: ink, letterSpacing: 1.0,
                                )),
                            const SizedBox(width: 5),
                            Icon(Icons.copy_rounded,
                                size: 12,
                                color: _kBrand.withValues(alpha: 0.7)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StudentCountBadge(classId: cls.id),
                    const SizedBox(height: 6),
                    _ActiveHomeworkBadge(classId: cls.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Uzun bas → yönet menüsü (adı değiştir / sil) ───────────────────────
  Future<void> _showManageMenu(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.card(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Text(cls.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(ctx),
                  )),
            ),
            Divider(height: 1, color: AppPalette.border(ctx)),
            _menuRow(ctx, Icons.edit_rounded, 'Sınıfı düzenle'.tr(),
                _kBrand, () {
              Navigator.pop(ctx);
              // Menü kapanışı bitmeden dialog açmak unmount çakışması
              // (_dependents.isEmpty) yaratıyor — bir sonraki frame'e ertele.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) showEditClassSheet(context, cls);
              });
            }),
            Divider(height: 1, color: AppPalette.border(ctx)),
            _menuRow(ctx, Icons.delete_outline_rounded, 'Sınıfı sil'.tr(),
                const Color(0xFFEF4444), () {
              Navigator.pop(ctx);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) _confirmDelete(context);
              });
            }),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _menuRow(BuildContext ctx, IconData icon, String label, Color color,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w700, color: color,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  /// Sınıfı düzenle — ad, okul/başlık ve durum mesajı tek formda.
  Future<void> _confirmDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Sınıfı sil'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(ctx))),
            ),
          ],
        ),
        content: Text(
          '"${cls.name}" sınıfını silersen tüm sınıf verileri ve içindeki '
                  'her şey (öğrenciler, ödevler, yazılı/sözlü notları ve '
                  'sonuçlar) kalıcı olarak silinir. Bu işlem geri alınamaz.'
              .tr(),
          style: GoogleFonts.poppins(
              fontSize: 13, height: 1.45,
              color: AppPalette.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Kalıcı Olarak Sil'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ClassService.deleteClass(cls.id, cls.code);
    messenger.showSnackBar(SnackBar(
      content: Text(done ? 'Sınıf silindi'.tr()
          : 'Silinemedi, tekrar dene'.tr()),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

/// Sınıftaki canlı öğrenci sayısı rozeti.
/// Öğretmene her girişte değişen kısa, sıcak/etkileyici karşılama cümleleri.
/// (Apostrof içerenler çift tırnakla yazıldı — kaçış gerekmesin.)
const _teacherGreetings = <String>[
  // İlham veren & duygusal
  "Bugün bir öğrencinin geleceğine dokunacaksın ✨",
  "İyi ki varsınız — emeğiniz çoğalıyor 🌱",
  "Bir öğretmen, bin umut demektir 💫",
  "Bugün de ilham olmaya hazır mısın? 🚀",
  "Öğrettiğin her şey bir tohum 🌳",
  "Sabrın ve emeğin meyvesini veriyor 🍎",
  "Sınıfının yıldızı sensin ⭐",
  "Küçük bir söz, büyük bir iz bırakır 🖋️",
  "Bugün harika bir ders günü olacak ☀️",
  "Geleceği yetiştiriyorsun, ne güzel 💚",
  "Bilgiyi paylaştıkça çoğalan tek hazine 📚",
  "Emeğin fark yaratıyor, görülüyorsun 👏",
  "Bir gülümseme, bir öğrenciye yeter 😊",
  "Sen anlattıkça dünya biraz daha aydınlanıyor 🌍",
  "Bugün bir çocuğun kahramanı olmaya hazır mısın? 🦸‍♂️",
  "Dünyayı değiştirecek o çocuk bugün senin sınıfında oturuyor olabilir 🚀",
  "Tarih kitapları liderleri yazar, liderleri ise sen yetiştirirsin 📚",
  "Bugün ekeceğin bir bilgi tohumu, yarın koca bir çınar olacak 🌱",
  "Tebeşir tozu kokusu, geleceğin parfümüdür 🌬️",
  "Bir çocuğun zihnini açmak, evrenin en güzel sanatıdır 🎨",
  "Gelecek, senin sınıfının kapısından içeri giriyor 🚪",
  "Bugün yine birilerinin hayatında 'unutulmaz öğretmen' olacaksın 💖",
  "Sadece ders anlatmıyorsun; hayal kurmayı öğretiyorsun 🌌",
  "Işığınla sadece sınıfı değil, dünyayı aydınlatıyorsun 💡",
  "Bir çocuğun 'Anladım!' derken parlayan gözlerinden güzel manzara yoktur 👀✨",
  "Senin sabrın, bir çocuğun en büyük şansıdır 🙏",
  "Bugün sınıfına sadece bilgini değil, kalbini de götürüyorsun ❤️",
  "Geleceğin mimarı bugün iş başında 🏗️",
  "Bir kelimenle bir çocuğun tüm dünyasını değiştirebilirsin 🗣️",
  // Esprili
  "Bugün o arka sıradaki gizemli enerjiyi çözme günü! 🕵️‍♂️",
  "Sakin ol ve derin bir nefes al... Bugün kimse kalemini unutmayacak (umarız!) ✏️",
  "Yapay zeka bile senin kadar sabırlı olmayı beceremedi 🤖",
  "Sınıfın enerjisi yüksek olabilir ama kahvenin enerjisi daha yüksek ☕",
  "Bugün 'Hocam bu sınavda çıkacak mı?' sorusuna en cool cevapsın 😎",
  "Zilin sesiyle canlanan o enerjiyi sadece bir öğretmen yönetebilir 🔔",
  "Tüm sınıfın dikkatini aynı anda toplayan gerçek bir sihirbazsın 🪄",
  "Bugün ödevini unutan sevimli yalancıları gülümseyerek karşılama günü 😺",
  "Yapay zeka soru üretir ama o soruyu sevdirme sanatı sana ait 🧠",
  "Sınıftaki tatlı uğultuyu sevgiye dönüştüren gizli güç sensin 🎶",
  "Bugün tahtaya kalkmak istemeyenlerin bile kalbini kazanacaksın 🎯",
  "Öğretmenler odasındaki ilk yudum çay kadar huzurlu bir gün dileriz 🫖",
  "Bugün sınıfın 'en popüler' insanı olmaya hazır mısın? 📣",
  // Kısa & güçlü
  "Enerjini topla, sınıfın seni bekliyor 🔋",
  "Fikirler seninle filizlenir 💭",
  "Bugün yine harikalar yaratacaksın 🪄",
  "Eğitim ordusunun en güçlü neferine selam olsun 🫡",
  "Yürüdüğün yolda arkanda koca bir gelecek bırakıyorsun 👣",
  "Bilginin en tatlı hali senin sesinde saklı 🗣️🎵",
  "Bugün bir hayalin temelini atacaksın 🧱",
  "Sınıfın ritmi senin elinde 🥁",
  "Küçük adımları büyük başarılara dönüştüren sensin 🏃‍♂️",
  "Bugün yine bir çocuğun 'başardım' deme sebebi olacaksın 🏆",
  // Vizyon
  "Sen ders anlatırken zaman durur, gelecek başlar ⏳",
  "Bir sınıfı yönetmek, bir ülkenin geleceğini yönetmektir 🗺️",
  "Kitapların ötesinde bir şeysin; sen canlı bir ilham kaynağısın 📖",
  "Yarınların parlak olmasının sebebi bugün senin kürsüde olman 🌟",
  "Her başarılı insanın arkasında senin gibi bir öğretmenin izi vardır 👣",
  "Bugün sınıfa giren her çocuk, seninle biraz daha büyüyecek 🪴",
  "Sorulara cevap olmaya, karanlığa ışık tutmaya geldin 🕯️",
  "Bilgi denizinde öğrencilerine rehberlik eden güvenilir kaptansın 🧭",
  "Seninle öğrenmek, her çocuk için bir ayrıcalıktır 💎",
  "Dünya, senin gibi öğretmenlerin omuzlarında yükseliyor 🌐",
  // İlham veren (2. parti)
  "Bugün bir çocuğun kendine inanmasına sebep olabilirsin ✨",
  "Her ders, geleceğe yazılmış yeni bir mektuptur 💌",
  "Sınıfındaki sessiz çocuk bile büyük bir hikâye taşıyor 📖",
  "Bir öğrencinin hayatında iz bırakmak, yıllar sonra süren bir mucizedir 🌈",
  "Bugün anlattığın bir konu, bir ömrün yönünü değiştirebilir 🧭",
  "En büyük yatırımlar bazen bir sınıfta yapılır 💰",
  "Her soru, yeni bir keşfin kapısını aralar 🚪",
  "Öğrenciler unutabilir ama hissettirdiklerini hatırlar ❤️",
  "Bilgi verirken umut da veriyorsun 🌱",
  "Bir çocuğun potansiyelini görmek gerçek süper güçtür ⚡",
  // Duygusal (2. parti)
  "Bir gün öğrencilerin seni anlatırken yüzleri gülümseyecek 😊",
  "Bazı kahramanlar pelerin değil, öğretmen önlüğü giyer 🦸",
  "Sınıfta kurulan güven, hayat boyu taşınan bir hazinedir 💎",
  "Bugün söylediğin güzel bir söz yıllarca hatırlanabilir 🌹",
  "Çocukların kalbine dokunmak dünyanın en değerli işlerindendir 🤲",
  "Her öğrencinin içinde keşfedilmeyi bekleyen bir yıldız vardır ⭐",
  "Sen sadece ders vermiyorsun, cesaret de veriyorsun 💪",
  "Bir öğrencinin başarısında emeğinin izi vardır 👣",
  "En güzel eserlerin insan yetiştirmektir 🎨",
  "Bazı meslekler iş yapar, sen gelecek inşa ediyorsun 🏗️",
  // Vizyoner (2. parti)
  "Bir ülkenin yarını bugün senin sınıfında oturuyor 🇹🇷",
  "Tek bir öğrenciye ilham vermek, nesillere etki etmektir 🌍",
  "Geleceğin bilim insanları, sanatçıları ve liderleri sana emanet 🔬",
  "Bir çocuğun hayaline ortak olmak dünyayı değiştirmektir 🌎",
  "Bugün attığın adımlar yarının başarı hikâyelerini yazacak 📚",
  "Her ders, insanlığın geleceğine yapılan bir katkıdır 🌐",
  "Senin sınıfın küçük görünebilir ama etkisi sınırsızdır ♾️",
  "Büyük değişimler çoğu zaman bir sınıfta başlar 🚀",
  "Yarınların mimarları bugün seni dinliyor 🎯",
  "Bir toplumun gücü, öğretmenlerinin gücü kadardır 🏛️",
  // Esprili (2. parti)
  "Bugün yine 'Hocam bu konu önemli mi?' sorusuna hazırlan 😅",
  "Kahven hazırsa hiçbir şey imkânsız değil ☕",
  "Bugün tahtaya yazdıklarının yarısını silsen bile efsanesin 😎",
  "Öğrencilerin internetten hızlı olabilir ama tecrübenden değil 🚄",
  "Bugün en az üç kez 'Sessiz olalım arkadaşlar' deme hakkın var 🔊",
  "Sınıf yönetimi bazen ileri seviye strateji oyunudur 🎮",
  "Bugün kalemini unutanlar yaratıcı bahanelerle geliyor olabilir ✏️",
  "Bir öğretmenin bakışı bazen bin kelimeden güçlüdür 👀",
  "Sınıfın enerjisi yükselirse sakin kal, sen kaptansın 🚢",
  "Öğretmenlik: Aynı anda psikolog, rehber, lider ve dedektif olmak 🕵️",
  // Uzun & etkileyici
  "Bugün de ilham olmaya hazır mısın? Sınıfına gireceğin o an, birilerinin gününü ve belki geleceğini değiştirecek 🚀",
  "Yıllar sonra bir öğrencin bugünü hatırlayacak ve 'O gün öğretmenim bana inanmıştı' diyecek — o günü bugün yazıyorsun 💛",
  "Anlattığın konu unutulabilir ama sınıfına kattığın güven, cesaret ve merak bir ömür boyu taşınır 🌟",
  "Kimi gün yorulur, kimi gün tükendiğini hissedersin; ama unutma, senin 'sıradan' bir dersin bile bir çocuğun en iyi anısı olabilir ☀️",
  "Bir sınıf dolusu farklı hayal, farklı hikâye ve farklı potansiyel seni bekliyor — hepsinin ortak noktası sensin 🧩",
  "Bugün soracağın tek bir güzel soru, bir öğrencinin zihninde yıllarca sürecek bir merak ateşi yakabilir 🔥",
];
// Sıralı gösterim: son gösterilen indeks (bellek) + prefs ilk yükleme bayrağı.
// Her girişte sıradaki cümle gösterilir; uygulama kapansa da kaldığı yerden devam.
int _greetSeq = -1;
bool _greetLoaded = false;

/// Öğretmen ana ekranı üst kartı: karşılama + günün özeti + istatistik
/// rozetleri (Sınıf / Öğrenci / Bu hafta ödev). Bekleyen sayısı tıklanınca
/// tüm sınıfların bekleyen ödevleri tek listede açılır.
class _TeacherHomeHeader extends StatefulWidget {
  final int classCount;
  const _TeacherHomeHeader({required this.classCount});

  @override
  State<_TeacherHomeHeader> createState() => _TeacherHomeHeaderState();
}

class _TeacherHomeHeaderState extends State<_TeacherHomeHeader> {
  ({String name, int classes, int students, int weekHomeworks, int pending})?
      _sum;
  String _greeting = '';

  @override
  void initState() {
    super.initState();
    // İlk kare boş kalmasın: bilinen son indeksi göster, sonra sıradakine geç.
    _greeting = (_greetSeq >= 0 && _greetSeq < _teacherGreetings.length)
        ? _teacherGreetings[_greetSeq]
        : _teacherGreetings[0];
    _advanceGreeting();
    _load();
  }

  /// Karşılama cümlesini SIRAYLA ilerletir (kalıcı). Her girişte sıradaki;
  /// uygulama kapanıp açılsa da prefs'teki indeksten devam eder.
  Future<void> _advanceGreeting() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!_greetLoaded) {
        _greetSeq = p.getInt('teacher_greet_seq') ?? -1;
        _greetLoaded = true;
      }
      _greetSeq = (_greetSeq + 1) % _teacherGreetings.length;
      await p.setInt('teacher_greet_seq', _greetSeq);
    } catch (_) {
      _greetSeq = (_greetSeq + 1) % _teacherGreetings.length;
    }
    if (mounted) setState(() => _greeting = _teacherGreetings[_greetSeq]);
  }

  Future<void> _load() async {
    final s = await HomeworkService.teacherHomeSummary();
    if (mounted) setState(() => _sum = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _sum;
    final pending = s?.pending ?? 0;
    return Column(
      children: [
        // ── ŞIK karşılama çerçevesi — "Sınıflarım"ın hemen altında ──
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            // Solda KOYU yeşil → sağa doğru açılan yeşil (kullanıcı isteği).
            gradient: const LinearGradient(
              colors: [Color(0xFF064E3B), Color(0xFF059669), Color(0xFF34D399)],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.35),
                blurRadius: 16, offset: const Offset(0, 6),
              ),
            ],
          ),
          // Logo/ikon YOK — cümle tüm karta yayılır.
          child: Text(_greeting.tr(),
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  height: 1.35, color: Colors.white)),
        ),
        // ── Günün özeti + istatistik rozetleri (ayrı sade kart) ──
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: pending > 0
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const TeacherAllPendingScreen()))
                    : null,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        pending > 0
                            ? '${'Kontrol bekleyen'.tr()} $pending ${'ödev var'.tr()}'
                            : 'Bugün her şey güncel 🎉'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: pending > 0
                                ? const Color(0xFFDC2626)
                                : AppPalette.textSecondary(context)),
                      ),
                    ),
                    if (pending > 0) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 14, color: Color(0xFFDC2626)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _stat(context, '🏫', '${widget.classCount}', 'Sınıf'.tr()),
                  const SizedBox(width: 8),
                  _stat(context, '👥', s == null ? '–' : '${s.students}',
                      'Öğrenci'.tr()),
                  const SizedBox(width: 8),
                  _stat(context, '📝', s == null ? '–' : '${s.weekHomeworks}',
                      'Bu hafta'.tr()),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(BuildContext c, String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppPalette.card(c).withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border(c)),
        ),
        child: Column(
          children: [
            Text('$emoji $value',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(c))),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 9.5, fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(c))),
          ],
        ),
      ),
    );
  }
}

/// Sınıf kartında "N onay bekliyor" rozeti. Taslak + zamanlanmış (yayını
/// gelecek) ödevleri sayar; dokununca Bekleyen Ödevler ekranını açar.
class _PendingHomeworkBadge extends StatelessWidget {
  final TeacherClass cls;
  const _PendingHomeworkBadge({required this.cls});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HomeworkModel>>(
      stream: HomeworkService.pendingHomeworksStream(cls.id),
      builder: (context, snap) {
        final list = snap.data ?? const <HomeworkModel>[];
        if (list.isEmpty) return const SizedBox.shrink();
        final drafts = list.where((h) => h.isDraft).length;
        final scheduled = list.length - drafts;
        final label = drafts > 0 && scheduled > 0
            ? '${list.length} ${'bekleyen'.tr()}'
            : drafts > 0
                ? '$drafts ${'onay bekliyor'.tr()}'
                : '$scheduled ${'zamanlandı'.tr()}';
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TeacherPendingHomeworksScreen(
                classId: cls.id, className: cls.name),
            )),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pending_actions_rounded,
                      size: 13, color: Color(0xFFEF4444)),
                  const SizedBox(width: 5),
                  // Başka dilde uzayınca taşmasın → esnet + kısalt.
                  Flexible(
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 10.5, fontWeight: FontWeight.w800,
                          color: const Color(0xFFDC2626),
                        )),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StudentCountBadge extends StatelessWidget {
  final String classId;
  const _StudentCountBadge({required this.classId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: ClassService.studentCountStream(classId),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _kBrand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.people_alt_rounded, size: 13, color: _kBrand),
              const SizedBox(width: 4),
              Text('$n ${'öğrenci'.tr()}',
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

/// Sınıftaki yayında (aktif) ödev sayısı rozeti — kart üzerinde canlı bilgi.
class _ActiveHomeworkBadge extends StatelessWidget {
  final String classId;
  const _ActiveHomeworkBadge({required this.classId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: HomeworkService.activeHomeworkCountStream(classId),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        const c = Color(0xFF0EA5E9);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.assignment_rounded, size: 13, color: c),
              const SizedBox(width: 4),
              Text('$n ${'aktif ödev'.tr()}',
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w800, color: c,
                  )),
            ],
          ),
        );
      },
    );
  }
}
