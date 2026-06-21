// ═══════════════════════════════════════════════════════════════════════════
//  TeacherSubmissionDetailScreen — Bir öğrencinin TEK bir ödevdeki teslim
//  detayı (drill-down'ın en alt seviyesi).
//
//  Öğrenci karnesindeki ödev satırına tıklanınca açılır. Gösterdiği:
//    • Ödev başlığı + ders·konu + veriliş/bitiş tarihi
//    • Doğru / Yanlış / Boş sayısı
//    • Bu sette geçirdiği aktif (ekran önü) ve pasif (dışarıda) zaman
//    • AI'nin bu performans için ürettiği kısa yorum (cache'li)
//    • Soru-soru öğrencinin cevapları
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherSubmissionDetailScreen extends StatefulWidget {
  final String classId;
  final HomeworkModel homework;
  final HomeworkSubmissionModel submission;
  final String studentName;
  const TeacherSubmissionDetailScreen({
    super.key,
    required this.classId,
    required this.homework,
    required this.submission,
    required this.studentName,
  });

  @override
  State<TeacherSubmissionDetailScreen> createState() =>
      _TeacherSubmissionDetailScreenState();
}

class _TeacherSubmissionDetailScreenState
    extends State<TeacherSubmissionDetailScreen> {
  String? _comment;
  bool _loadingComment = false;

  int get _correct => widget.submission.correct ?? 0;
  int get _wrong => widget.submission.wrong ?? 0;
  int get _blank {
    final b = widget.homework.questionCount - _correct - _wrong;
    return b < 0 ? 0 : b;
  }

  @override
  void initState() {
    super.initState();
    _comment = widget.submission.aiComment;
    if (widget.submission.isSubmitted &&
        (_comment == null || _comment!.trim().isEmpty)) {
      _loadComment();
    }
  }

  Future<void> _loadComment() async {
    setState(() => _loadingComment = true);
    final hw = widget.homework;
    final c = await HomeworkService.ensureSubmissionComment(
      classId: widget.classId,
      homeworkId: hw.id,
      studentUid: widget.submission.studentUid,
      studentName: widget.studentName,
      homeworkTitle: hw.title,
      subject: hw.subject,
      topic: hw.topic,
      correct: _correct,
      wrong: _wrong,
      blank: _blank,
      active: widget.submission.activeTime,
      passive: widget.submission.passiveTime,
      cached: widget.submission.aiComment,
    );
    if (!mounted) return;
    setState(() {
      _comment = c;
      _loadingComment = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final hw = widget.homework;
    final sub = widget.submission;
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Ödev Detayı'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            // ── Başlık + tarihler ─────────────────────────────────────
            Text(hw.title,
                style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w900, color: ink,
                  height: 1.3,
                )),
            const SizedBox(height: 4),
            Text('${hw.subject} · ${hw.topic}',
                style: GoogleFonts.poppins(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondary(context),
                )),
            const SizedBox(height: 10),
            Row(
              children: [
                _dateChip(context, Icons.event_available_rounded,
                    'Verildi'.tr(), _fmtDate(hw.assignedAt)),
                const SizedBox(width: 8),
                _dateChip(context, Icons.event_busy_rounded,
                    'Bitiş'.tr(), _fmtDate(hw.dueAt)),
              ],
            ),
            const SizedBox(height: 20),

            if (!sub.isSubmitted)
              _notSubmitted(context)
            else ...[
              // ── Doğru / Yanlış / Boş ────────────────────────────────
              Row(
                children: [
                  _statCard(context, '✅', 'Doğru'.tr(), '$_correct',
                      const Color(0xFF10B981)),
                  const SizedBox(width: 10),
                  _statCard(context, '❌', 'Yanlış'.tr(), '$_wrong',
                      const Color(0xFFEF4444)),
                  const SizedBox(width: 10),
                  _statCard(context, '⬜', 'Boş'.tr(), '$_blank',
                      const Color(0xFF94A3B8)),
                ],
              ),
              const SizedBox(height: 12),
              // ── Aktif / Pasif zaman ─────────────────────────────────
              Row(
                children: [
                  _timeCard(context, Icons.bolt_rounded, 'Aktif Süre'.tr(),
                      _fmtDur(sub.activeTime), const Color(0xFF7C3AED)),
                  const SizedBox(width: 10),
                  _timeCard(context, Icons.pause_circle_outline_rounded,
                      'Pasif Süre'.tr(), _fmtDur(sub.passiveTime),
                      const Color(0xFFF59E0B)),
                ],
              ),
              const SizedBox(height: 22),

              // ── AI yorumu ───────────────────────────────────────────
              _aiCommentCard(context),
              const SizedBox(height: 22),

              // ── Soru-soru cevaplar ──────────────────────────────────
              if (sub.answers.isNotEmpty) ...[
                Text('CEVAPLAR'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      color: AppPalette.textSecondary(context),
                      letterSpacing: 0.8,
                    )),
                const SizedBox(height: 10),
                ...sub.answers.map((a) => _answerRow(context, a)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _aiCommentCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _kBrand.withValues(alpha: 0.10),
          const Color(0xFFEC4899).withValues(alpha: 0.08),
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBrand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text('AI Değerlendirmesi'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w800,
                    color: _kBrand,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingComment)
            Row(
              children: [
                const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Performans yorumu hazırlanıyor…'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: AppPalette.textSecondary(context),
                    )),
              ],
            )
          else if (_comment != null && _comment!.trim().isNotEmpty)
            Text(_comment!,
                style: GoogleFonts.poppins(
                  fontSize: 13.5, height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: AppPalette.textPrimary(context),
                ))
          else
            Row(
              children: [
                Expanded(
                  child: Text('Yorum oluşturulamadı.'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: AppPalette.textSecondary(context),
                      )),
                ),
                TextButton(
                  onPressed: _loadComment,
                  child: Text('Tekrar dene'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12.5, fontWeight: FontWeight.w700,
                        color: _kBrand,
                      )),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _answerRow(BuildContext context, SubmissionAnswer a) {
    final (color, icon) = a.isCorrect == true
        ? (const Color(0xFF10B981), Icons.check_circle_rounded)
        : a.isCorrect == false
            ? (const Color(0xFFEF4444), Icons.cancel_rounded)
            : (const Color(0xFFF59E0B), Icons.hourglass_top_rounded);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.index + 1}. ${a.questionText}',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(context), height: 1.35,
                    )),
                const SizedBox(height: 3),
                Text(
                  a.studentAnswer.trim().isEmpty
                      ? '(boş)'.tr()
                      : a.studentAnswer,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(BuildContext c, String emoji, String label, String value,
      Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppPalette.card(c),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(c)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.poppins(
                  fontSize: 22, fontWeight: FontWeight.w900, color: color,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondary(c),
                )),
          ],
        ),
      ),
    );
  }

  Widget _timeCard(BuildContext c, IconData icon, String label, String value,
      Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppPalette.card(c),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(c)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w900,
                      color: AppPalette.textPrimary(c),
                    )),
                Text(label,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, fontWeight: FontWeight.w600,
                      color: AppPalette.textSecondary(c),
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(
      BuildContext c, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppPalette.card(c),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border(c)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppPalette.textSecondary(c)),
          const SizedBox(width: 6),
          Text('$label: ',
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(c),
              )),
          Text(value,
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(c),
              )),
        ],
      ),
    );
  }

  Widget _notSubmitted(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        children: [
          const Text('⏳', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 10),
          Text('Henüz teslim edilmedi'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
              )),
          const SizedBox(height: 6),
          Text('Öğrenci bu ödevi tamamlayınca detaylar burada görünecek.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5, color: AppPalette.textSecondary(context),
                height: 1.4,
              )),
        ],
      ),
    );
  }

  String _fmtDur(Duration? d) {
    if (d == null) return '—';
    if (d.inMinutes < 1) return '${d.inSeconds} sn';
    if (d.inHours < 1) return '${d.inMinutes} dk';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '$h sa' : '$h sa $m dk';
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} $hh:$mm';
  }
}
