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

import '../services/analytics.dart';
import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/class_profile_dialog.dart';
import 'notifications_inbox_screen.dart';
import 'profile_screen.dart';
import 'teacher_class_detail_screen.dart';
import 'teacher_create_homework_screen.dart';
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
                builder: (_) => TeacherCreateHomeworkScreen(cls: cls),
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
                    const SizedBox(height: 8),
                    Text(cls.schoolName,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5, color: muted,
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
                    Text('Katılma Kodu'.tr(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w700,
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
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        decoration: BoxDecoration(
                          color: AppPalette.bg(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _kBrand.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.vpn_key_rounded,
                                size: 15, color: _kBrand),
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
                    const SizedBox(height: 8),
                    // Öğrenci sayısı — kod kutusuyla aynı genişlikte.
                    _StudentCountBadge(classId: cls.id),
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
                if (context.mounted) _editClassDialog(context);
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
  Future<void> _editClassDialog(BuildContext context) async {
    final nameCtrl = TextEditingController(text: cls.name);
    final schoolCtrl = TextEditingController(text: cls.schoolName);
    final statusCtrl = TextEditingController(text: cls.statusMessage);
    final messenger = ScaffoldMessenger.of(context);
    bool save = false;

    Widget field(BuildContext c, TextEditingController ctrl, String label,
        String hint, IconData icon, Color iconColor,
        {TextCapitalization cap = TextCapitalization.sentences,
        int maxLines = 1}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary(c))),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppPalette.bg(c),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border(c)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: ctrl,
              textCapitalization: cap,
              maxLines: maxLines,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(c)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: AppPalette.textSecondary(c).withValues(alpha: 0.5)),
                icon: Icon(icon, size: 20, color: iconColor),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border(sheetCtx),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Sınıfı düzenle'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 17, fontWeight: FontWeight.w900,
                      color: AppPalette.textPrimary(sheetCtx))),
              const SizedBox(height: 16),
              field(sheetCtx, nameCtrl, 'Sınıf adı'.tr(),
                  'örn: 10-A'.tr(), Icons.class_rounded, const Color(0xFFF59E0B),
                  cap: TextCapitalization.characters),
              const SizedBox(height: 12),
              field(sheetCtx, schoolCtrl, 'Okul / Başlık'.tr(),
                  'örn: Atatürk Lisesi'.tr(), Icons.apartment_rounded,
                  const Color(0xFF0EA5E9), cap: TextCapitalization.words),
              const SizedBox(height: 12),
              field(sheetCtx, statusCtrl, 'Durum mesajı'.tr(),
                  'örn: Bu hafta deneme sınavı var'.tr(), Icons.chat_rounded,
                  const Color(0xFF10B981), maxLines: 2),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kBrand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    save = true;
                    // Klavyeyi kapat + sheet'i ÖNCE kapat, sonra yaz.
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(sheetCtx);
                  },
                  child: Text('Kaydet'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (save) {
      final ok = await ClassService.updateClassInfo(
        cls.id,
        name: nameCtrl.text,
        schoolName: schoolCtrl.text,
        statusMessage: statusCtrl.text,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(ok ? 'Sınıf güncellendi'.tr()
            : 'Güncellenemedi, tekrar dene'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
    nameCtrl.dispose();
    schoolCtrl.dispose();
    statusCtrl.dispose();
  }

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
