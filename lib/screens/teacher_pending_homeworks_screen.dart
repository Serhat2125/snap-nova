// ═══════════════════════════════════════════════════════════════════════════
//  TeacherPendingHomeworksScreen — Öğretmenin BEKLEYEN ödevleri:
//    • Taslaklar (status='draft')  — atanmamış, öğrenciye görünmez
//    • Zamanlanmışlar (publishAt gelecek) — atanmış ama yayın bekliyor
//
//  Aksiyonlar: Yayınla (taslağı sınıfa at), Zamanlamayı düzenle, Sil.
//  Sınıf kartındaki "N onay bekliyor" rozetinden açılır.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_homework_preview_screen.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherPendingHomeworksScreen extends StatelessWidget {
  final String classId;
  final String className;
  const TeacherPendingHomeworksScreen({
    super.key, required this.classId, required this.className,
  });

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
            Text('Bekleyen Ödevler'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text(className,
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                )),
          ],
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<HomeworkModel>>(
          stream: HomeworkService.pendingHomeworksStream(classId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final list = snap.data ?? const <HomeworkModel>[];
            if (list.isEmpty) return _empty(context);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: list.length,
              itemBuilder: (ctx, i) =>
                  PendingHomeworkCard(hw: list[i], classId: classId),
            );
          },
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
            const Text('🗂️', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 14),
            Text('Bekleyen ödev yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 8),
            Text(
              'AI ile ödev üretip "Taslağa Kaydet" dersen veya ileri tarihe zamanlarsan burada görünür.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PendingHomeworkCard extends StatefulWidget {
  final HomeworkModel hw;
  final String classId;
  const PendingHomeworkCard({super.key, required this.hw, required this.classId});

  @override
  State<PendingHomeworkCard> createState() => PendingHomeworkCardState();
}

class PendingHomeworkCardState extends State<PendingHomeworkCard> {
  bool _busy = false;

  HomeworkModel get hw => widget.hw;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _publishNow() async {
    setState(() => _busy = true);
    final ok = await HomeworkService.publishDraft(
      classId: widget.classId,
      hwId: hw.id,
      clearPublishAt: true, // hemen yayınla
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(ok ? 'Ödev yayınlandı, öğrencilere bildirildi.'.tr()
              : 'Yayınlanamadı, tekrar dene.'.tr());
  }

  /// Tüm ödevi düzenle: başlık, sorular, şıklar, doğru cevap, zamanlama.
  Future<void> _editFull() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeacherHomeworkPreviewScreen(
        classId: widget.classId,
        title: hw.title,
        subject: hw.subject,
        topic: hw.topic,
        level: hw.level,
        types: hw.types,
        dueAt: hw.dueAt,
        publishAt: hw.publishAt,
        questions: hw.questions,
        editHwId: hw.id,
        editIsDraft: hw.isDraft,
        teacherNote: hw.teacherNote,
      ),
    ));
  }

  Future<void> _editSchedule() async {
    // Yayın tarih-saatini seç → taslaksa zamanlanmış olarak yayınla.
    final base = hw.publishAt ?? DateTime.now().add(const Duration(hours: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: base.isAfter(DateTime.now()) ? base : DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (!mounted) return;
    final when = DateTime(d.year, d.month, d.day,
        t?.hour ?? base.hour, t?.minute ?? base.minute);
    setState(() => _busy = true);
    final ok = hw.isDraft
        ? await HomeworkService.publishDraft(
            classId: widget.classId, hwId: hw.id, publishAt: when)
        : await HomeworkService.updateDraft(
            classId: widget.classId, hwId: hw.id, publishAt: when);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(ok ? 'Yayın zamanı güncellendi.'.tr() : 'Güncellenemedi.'.tr());
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppPalette.card(dctx),
        title: Text('Sil'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(dctx))),
        content: Text('"${hw.title}" silinecek. Emin misin?'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(dctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text('Sil'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final done = await HomeworkService.deleteHomework(widget.classId, hw.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) _toast('Silinemedi, tekrar dene.'.tr());
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final isDraft = hw.isDraft;
    final statusColor = isDraft
        ? const Color(0xFF7C3AED)
        : const Color(0xFF0EA5E9);
    final statusLabel = isDraft ? 'Taslak'.tr() : 'Zamanlandı'.tr();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(statusLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      color: statusColor,
                    )),
              ),
              const Spacer(),
              Text('${hw.questionCount} ${'soru'.tr()}',
                  style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(context))),
              const SizedBox(width: 4),
              // Sağ üst: kalem → tüm ödevi düzenle (başlık, sorular, şıklar…).
              SizedBox(
                width: 32, height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: _busy ? null : _editFull,
                  icon: const Icon(Icons.edit_rounded, size: 18, color: _kBrand),
                  tooltip: 'Düzenle'.tr(),
                  style: IconButton.styleFrom(
                    backgroundColor: _kBrand.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(hw.title,
              style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
              ),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${hw.subject}${hw.topic.isNotEmpty ? ' · ${hw.topic}' : ''}',
              style: GoogleFonts.poppins(
                fontSize: 11.5, color: AppPalette.textSecondary(context)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          // Zamanlama bilgisi
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 13,
                  color: AppPalette.textSecondary(context)),
              const SizedBox(width: 4),
              Text('${'Teslim'.tr()}: ${_fmt(hw.dueAt)}',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5, color: AppPalette.textSecondary(context))),
            ],
          ),
          if (hw.publishAt != null) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13,
                    color: AppPalette.textSecondary(context)),
                const SizedBox(width: 4),
                Text('${'Yayın'.tr()}: ${_fmt(hw.publishAt!)}',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, color: AppPalette.textSecondary(context))),
              ],
            ),
          ],
          const Divider(height: 18),
          // Aksiyonlar
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _publishNow,
                    child: Text('Şimdi Yayınla'.tr(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 8),
                // İleri bir tarihe zamanlama → _editSchedule gün+saat seçtirir.
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand.withValues(alpha: 0.12),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _editSchedule,
                    child: Text('Zamanlayıcı Ayarla'.tr(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: _kBrand)),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444)),
                  tooltip: 'Sil'.tr(),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFEF4444).withValues(alpha: 0.10),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
