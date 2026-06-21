// ═══════════════════════════════════════════════════════════════════════════
//  TeacherAnalyticsClassScreen — Analiz sekmesinde bir sınıfa tıklayınca
//  açılan öğrenci listesi (drill-down 2. seviye).
//
//  Sınıftaki tüm öğrenciler listelenir; bir isme tıklayınca o öğrencinin
//  karnesi (TeacherStudentReportScreen) açılır → oradan ödev → teslim detayı.
//
//  Demo modu: ⋮ menüden "Demo veri ekle" → sınıfa gerçekçi öğrenci + ödev +
//  teslim yazılır (önizleme için). "Demo veriyi temizle" geri alır.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/demo_seed_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_student_report_screen.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherAnalyticsClassScreen extends StatefulWidget {
  final TeacherClass cls;
  const TeacherAnalyticsClassScreen({super.key, required this.cls});

  @override
  State<TeacherAnalyticsClassScreen> createState() =>
      _TeacherAnalyticsClassScreenState();
}

class _TeacherAnalyticsClassScreenState
    extends State<TeacherAnalyticsClassScreen> {
  bool _busy = false;

  TeacherClass get cls => widget.cls;

  Future<void> _seed() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await DemoSeedService.seedClass(
      classId: cls.id,
      teacherUid: cls.teacherUid,
      subject: cls.subject,
      level: cls.level,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(ok
        ? 'Demo öğrenci ve ödevler eklendi.'.tr()
        : 'Demo verisi eklenemedi.'.tr());
  }

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await DemoSeedService.clearDemo(cls.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(ok ? 'Demo verisi temizlendi.'.tr() : 'Temizlenemedi.'.tr());
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cls.name,
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text('${'Öğrenciler'.tr()} · ${cls.subject}',
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                )),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy,
            icon: Icon(Icons.more_vert_rounded,
                color: AppPalette.textSecondary(context)),
            onSelected: (v) {
              if (v == 'seed') _seed();
              if (v == 'clear') _clear();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'seed',
                child: Row(children: [
                  const Text('🧪', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Text('Demo veri ekle'.tr(),
                      style: GoogleFonts.poppins(fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(children: [
                  const Icon(Icons.delete_outline_rounded,
                      size: 17, color: Color(0xFFEF4444)),
                  const SizedBox(width: 8),
                  Text('Demo veriyi temizle'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: const Color(0xFFEF4444))),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            StreamBuilder<List<ClassStudent>>(
              stream: ClassService.studentsStream(cls.id),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final students = snap.data ?? const <ClassStudent>[];
                if (students.isEmpty) return _empty(context);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.70,
                  ),
                  itemCount: students.length,
                  itemBuilder: (ctx, i) => _studentTile(context, students[i]),
                );
              },
            ),
            if (_busy)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.04),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Dikey öğrenci kartı — çerçeve içinde: üstte profil, altında ad-soyad,
  // altında kullanıcı adı. Grid'de yatayda 4'lü dizilir.
  Widget _studentTile(BuildContext context, ClassStudent s) {
    final name = s.displayName.trim().isNotEmpty
        ? s.displayName
        : (s.username.trim().isNotEmpty ? s.username : 'Öğrenci'.tr());
    final avatar = s.avatar.trim().isEmpty ? '👤' : s.avatar;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeacherStudentReportScreen(
            classId: cls.id,
            studentUid: s.uid,
            studentName: name,
            studentAvatar: avatar,
          ),
        )),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBrand.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Text(avatar, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(height: 8),
              Text(name,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: AppPalette.textPrimary(context),
                  ),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              if (s.username.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('@${s.username}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 9.5,
                      color: AppPalette.textSecondary(context),
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👥', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('Bu sınıfta henüz öğrenci yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 8),
            Text('Öğrenci davet et — ya da nasıl göründüğünü görmek için '
                'demo veri ekle.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13, color: AppPalette.textSecondary(context),
                  height: 1.4,
                )),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kBrand,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _busy ? null : _seed,
              icon: const Text('🧪', style: TextStyle(fontSize: 15)),
              label: Text('Demo veri ekle'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13.5, fontWeight: FontWeight.w800,
                    color: Colors.white,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
