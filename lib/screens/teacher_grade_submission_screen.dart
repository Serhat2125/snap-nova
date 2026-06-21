// ═══════════════════════════════════════════════════════════════════════════
//  TeacherGradeSubmissionScreen — Açık uçlu cevapları öğretmen puanlar.
//
//  Açık uçlu sorular otomatik (kelime eşleşmesi) yerine öğretmen tarafından
//  değerlendirilir. Öğretmen her cevabı Doğru/Yanlış işaretler → submission'ın
//  notu (correct/wrong/score) yeniden hesaplanır.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);

class TeacherGradeSubmissionScreen extends StatefulWidget {
  final String classId;
  final String homeworkId;
  final String homeworkTitle;
  final HomeworkSubmissionModel submission;
  const TeacherGradeSubmissionScreen({
    super.key,
    required this.classId,
    required this.homeworkId,
    required this.homeworkTitle,
    required this.submission,
  });

  @override
  State<TeacherGradeSubmissionScreen> createState() =>
      _TeacherGradeSubmissionScreenState();
}

class _TeacherGradeSubmissionScreenState
    extends State<TeacherGradeSubmissionScreen> {
  // soru index → true (doğru) / false (yanlış) / null (henüz işaretlenmedi)
  final Map<int, bool?> _grades = {};
  late final List<SubmissionAnswer> _openAnswers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _openAnswers =
        widget.submission.answers.where((a) => a.type == 'open').toList();
    for (final a in _openAnswers) {
      _grades[a.index] = a.isCorrect; // mevcut değer (varsa)
    }
  }

  String get _studentName => widget.submission.studentDisplayName.isEmpty
      ? '@${widget.submission.studentUsername}'
      : widget.submission.studentDisplayName;

  Future<void> _save() async {
    if (_saving) return;
    final unmarked = _grades.values.where((v) => v == null).length;
    if (unmarked > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppPalette.card(ctx),
          title: Text('Eksik değerlendirme'.tr()),
          content: Text(
            '$unmarked ${'soru henüz işaretlenmedi. İşaretlenmeyenler '
                'puanlanmamış kalır. Yine de kaydedilsin mi?'.tr()}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Vazgeç'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Kaydet'.tr()),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final concrete = <int, bool>{};
    _grades.forEach((k, v) {
      if (v != null) concrete[k] = v;
    });
    if (concrete.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    final ok = await HomeworkService.gradeOpenAnswers(
      classId: widget.classId,
      homeworkId: widget.homeworkId,
      studentUid: widget.submission.studentUid,
      grades: concrete,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Değerlendirme kaydedildi.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Kaydedilemedi. Tekrar dene.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Açık Uçlu Değerlendirme'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w800, color: ink)),
            Text('$_studentName · ${widget.homeworkTitle}',
                style: GoogleFonts.poppins(fontSize: 11, color: muted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      body: SafeArea(
        child: _openAnswers.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Bu teslimde açık uçlu soru yok.'.tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 13, color: muted),
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: _openAnswers.length,
                      itemBuilder: (ctx, i) =>
                          _answerCard(context, _openAnswers[i]),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kBrand,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white),
                              )
                            : Text('Değerlendirmeyi Kaydet'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 15, fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                )),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _answerCard(BuildContext context, SubmissionAnswer a) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final grade = _grades[a.index];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Soru
          Text('${a.index + 1}. ${a.questionText}',
              style: GoogleFonts.poppins(
                fontSize: 13.5, fontWeight: FontWeight.w800, color: ink,
                height: 1.4,
              )),
          const SizedBox(height: 10),
          // Öğrenci cevabı
          Text('ÖĞRENCİNİN CEVABI'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 9.5, fontWeight: FontWeight.w800,
                color: muted, letterSpacing: 0.7,
              )),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.bg(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Text(
              a.studentAnswer.trim().isEmpty
                  ? '(boş bırakıldı)'.tr()
                  : a.studentAnswer,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: a.studentAnswer.trim().isEmpty ? muted : ink,
                height: 1.45,
                fontStyle: a.studentAnswer.trim().isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Doğru / Yanlış
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _grades[a.index] = true),
                  child: _gradeBtn('Doğru ✓'.tr(), grade == true, _kGreen,
                      context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _grades[a.index] = false),
                  child: _gradeBtn('Yanlış ✗'.tr(), grade == false, _kRed,
                      context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gradeBtn(String label, bool sel, Color color, BuildContext c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: sel ? color.withValues(alpha: 0.12) : AppPalette.bg(c),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sel ? color : AppPalette.border(c),
          width: sel ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w800,
            color: sel ? color : AppPalette.textPrimary(c),
          )),
    );
  }
}
