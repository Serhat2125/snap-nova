// ═══════════════════════════════════════════════════════════════════════════
//  TeacherClassDetailScreen — Bir sınıfın öğretmen detay sayfası.
//
//  - Sınıf bilgisi başlık
//  - Sınıf kodu (kopyalanabilir)
//  - Öğrenci listesi (canlı stream)
//  - Sınıfı sil / paylaş
//
//  İçerik dağıtımı için ileride "Konu Özeti / Test gönder" butonu eklenir.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/education_models.dart';
import '../services/class_service.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/teacher_widgets.dart';

class TeacherClassDetailScreen extends StatefulWidget {
  final TeacherClass cls;
  const TeacherClassDetailScreen({super.key, required this.cls});

  @override
  State<TeacherClassDetailScreen> createState() => _TeacherClassDetailScreenState();
}

class _TeacherClassDetailScreenState extends State<TeacherClassDetailScreen> {
  TeacherClass get cls => widget.cls;

  @override
  void initState() {
    super.initState();
    // Auto-reminder timer başlat — 30 dakikada bir checkPendingReminders.
    // EVENT: teacher dashboard opened → start business logic.
    HomeworkService.startReminderTimer();
  }

  @override
  void dispose() {
    // EVENT: teacher leaves the class detail → keep timer running.
    // (Dashboard kapansa da reminder akışı çalışsın diye stop ETMİYORUZ.
    //  Sadece app kapandığında timer otomatik ölür.)
    super.dispose();
  }

  Future<void> _shareCode(BuildContext context) async {
    final msg =
        'QuAlsar Sınıf Daveti\n\n'
        '${cls.name} · ${cls.subject}\n'
        '${cls.schoolName}\n\n'
        'Sınıfa katılmak için QuAlsar uygulamasına bu kodu gir:\n'
        '🔑 ${cls.code}';
    try {
      await Share.share(msg, subject: 'QuAlsar sınıf daveti');
    } catch (_) {}
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Sınıfı sil?'.tr()),
        content: Text(
          'Bu işlem geri alınamaz. Sınıftaki öğrenciler bağlantılarını kaybeder.'
              .tr(),
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
            child: Text('Sil'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final success = await ClassService.deleteClass(cls.id, cls.code);
    if (!context.mounted) return;
    if (success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text(cls.name,
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
        actions: [
          IconButton(
            icon: Icon(Icons.share_rounded, color: ink),
            tooltip: 'Sınıf kodunu paylaş'.tr(),
            onPressed: () => _shareCode(context),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: const Color(0xFFEF4444)),
            tooltip: 'Sınıfı sil'.tr(),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Üst kart: kod + bilgi ───────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.30),
                    blurRadius: 14, offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${cls.schoolName} · ${cls.subject} · ${cls.level}',
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: cls.code));
                      if (!context.mounted) return;
                      messenger.showSnackBar(SnackBar(
                        content: Text('Sınıf kodu kopyalandı'.tr()),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('SINIF KODU'.tr(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white.withValues(alpha: 0.85),
                                      letterSpacing: 1.0,
                                    )),
                                const SizedBox(height: 2),
                                Text(cls.code,
                                    style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 1.5,
                                    )),
                              ],
                            ),
                          ),
                          const Icon(Icons.copy_rounded,
                              color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Öğrencilerin bu kodla sınıfa katılır.'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            // İki sekme: Öğrenciler + Ödevler
            Expanded(child: _TabbedContent(cls: cls)),
          ],
        ),
      ),
    );
  }
}

class _TabbedContent extends StatefulWidget {
  final TeacherClass cls;
  const _TabbedContent({required this.cls});
  @override
  State<_TabbedContent> createState() => _TabbedContentState();
}

class _TabbedContentState extends State<_TabbedContent> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Column(
      children: [
        TabBar(
          controller: _tab,
          labelColor: const Color(0xFF7C3AED),
          unselectedLabelColor: muted,
          indicatorColor: const Color(0xFF7C3AED),
          indicatorWeight: 2.5,
          labelStyle: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: 'Öğrenciler'.tr()),
            Tab(text: 'Ödevler'.tr()),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _studentsTab(context, ink, muted),
              _homeworkTab(context, ink, muted),
            ],
          ),
        ),
      ],
    );
  }

  Widget _studentsTab(BuildContext context, Color ink, Color muted) {
    return StreamBuilder<List<ClassStudent>>(
      stream: ClassService.studentsStream(widget.cls.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final students = snap.data!;
        if (students.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Henüz öğrenci yok — kodu paylaş, öğrenciler katıldıkça burada görünecek.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: muted, height: 1.45),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: students.length,
          itemBuilder: (ctx, i) {
                      final s = students[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                        decoration: BoxDecoration(
                          color: AppPalette.card(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppPalette.border(context)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF7C3AED)
                                    .withValues(alpha: 0.10),
                              ),
                              alignment: Alignment.center,
                              child: Text(s.avatar,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.displayName.isEmpty
                                        ? '@${s.username}'
                                        : s.displayName,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14, fontWeight: FontWeight.w700,
                                      color: ink,
                                    ),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                  Text('@${s.username}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11, color: muted,
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
  }

  Widget _homeworkTab(BuildContext context, Color ink, Color muted) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        // AI Homework Generator widget (yeni ödev üretim arayüzü)
        AiHomeworkGeneratorWidget(cls: widget.cls),
        const SizedBox(height: 14),
        // Aktif/eski ödevler — submission durumları ile
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.assignment_rounded, color: muted, size: 18),
              const SizedBox(width: 6),
              Text('SINIFIN ÖDEVLERİ'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: muted, letterSpacing: 1.0,
                  )),
            ],
          ),
        ),
        StreamBuilder<List<HomeworkModel>>(
          stream: HomeworkService.classHomeworksStream(widget.cls.id),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final hws = snap.data!;
            if (hws.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('Henüz ödev gönderilmedi.'.tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, color: muted,
                    )),
              );
            }
            return Column(
              children: hws.map((hw) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StudentPerformanceList(
                  classId: widget.cls.id, homework: hw,
                ),
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}
