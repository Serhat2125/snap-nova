// ═══════════════════════════════════════════════════════════════════════════
//  TeacherHomeworkViewScreen — Bir ödevi salt-okunur gösterir.
//
//  İki mod:
//    • submission = null → sadece ödevin aslı (sorular + doğru cevaplar).
//    • submission != null → her soruda ÖĞRENCİNİN cevabı + doğru cevap birlikte;
//      doğru/yanlış işaretlenir. (Öğrenci karnesi → Ödevler sekmesinden gelir.)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);

class TeacherHomeworkViewScreen extends StatelessWidget {
  final HomeworkModel homework;
  /// Belirli bir öğrencinin teslimi (varsa öğrenci cevapları gösterilir).
  final HomeworkSubmissionModel? submission;
  /// AppBar alt başlığı için öğrenci adı (opsiyonel).
  final String? studentName;
  const TeacherHomeworkViewScreen({
    super.key,
    required this.homework,
    this.submission,
    this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final hasSub = submission?.isSubmitted ?? false;

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(homework.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            if (studentName != null && studentName!.trim().isNotEmpty)
              Text(studentName!,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: muted)),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ── Üst bilgi kartı ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppPalette.card(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppPalette.border(context)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${homework.subject} · ${homework.topic}',
                            style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w800,
                              color: ink)),
                        const SizedBox(height: 4),
                        Text('${homework.questionCount} ${'soru'.tr()}',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5, color: muted)),
                      ],
                    ),
                  ),
                  // Teslim edildiyse skor rozeti.
                  if (hasSub && submission?.scorePercent != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _scoreColor(submission!.scorePercent!)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                          '%${submission!.scorePercent!.toStringAsFixed(0)}',
                          style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w900,
                            color: _scoreColor(submission!.scorePercent!),
                          )),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            HomeworkAnswersList(homework: homework, submission: submission),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 70) return _kGreen;
    if (score >= 40) return _kAmber;
    return _kRed;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  HomeworkAnswersList — soru-soru cevap kartları (öğrenci cevabı + doğru
//  cevap). Hem tam ekran görüntülemede hem ödev detayında INLINE kullanılır.
//  Column döner (kendi scroll'u yok) → dıştaki ListView içine gömülebilir.
// ═══════════════════════════════════════════════════════════════════════════
class HomeworkAnswersList extends StatelessWidget {
  final HomeworkModel homework;
  final HomeworkSubmissionModel? submission;
  const HomeworkAnswersList({
    super.key, required this.homework, this.submission,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final questions = homework.questions;
    final Map<int, SubmissionAnswer> byIndex = {
      for (final a in submission?.answers ?? const <SubmissionAnswer>[])
        a.index: a,
    };
    final hasSub = submission?.isSubmitted ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (submission != null && !hasSub) ...[
          _infoBanner(context,
              'Bu öğrenci ödevi henüz teslim etmedi — yalnızca soruların '
                      'doğru cevapları gösteriliyor.'
                  .tr()),
          const SizedBox(height: 8),
        ],
        if (questions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Text('Bu ödevin soruları görüntülenemiyor.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 13, color: muted)),
          )
        else
          ...List.generate(
              questions.length,
              (i) => _questionCard(
                  context, i, questions[i],
                  hasSub ? byIndex[i] : null, ink, muted)),
      ],
    );
  }

  Widget _infoBanner(BuildContext context, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kAmber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kAmber.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: _kAmber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary(context), height: 1.35)),
            ),
          ],
        ),
      );

  Widget _questionCard(BuildContext context, int i, Map<String, dynamic> q,
      SubmissionAnswer? ans, Color ink, Color muted) {
    final type = (q['type'] ?? 'mc').toString();
    final qText = (q['q'] ?? '').toString();
    final answer = (q['answer'] ?? '').toString();
    final choices = ((q['choices'] as List?) ?? const [])
        .map((c) => c.toString())
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Soru numarası + metni + (varsa) doğru/yanlış rozeti
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: _kBrand.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: _kBrand)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(qText,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5, fontWeight: FontWeight.w700,
                      color: ink, height: 1.4)),
              ),
              if (ans != null) ...[
                const SizedBox(width: 8),
                _statusBadge(ans.isCorrect),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ..._answerArea(context, type, choices, answer, ans, ink, muted),
        ],
      ),
    );
  }

  // Soru başındaki doğru/yanlış/değerlendirilmedi rozeti.
  Widget _statusBadge(bool? isCorrect) {
    late Color c;
    late IconData icon;
    late String label;
    if (isCorrect == true) {
      c = _kGreen; icon = Icons.check_rounded; label = 'Doğru';
    } else if (isCorrect == false) {
      c = _kRed; icon = Icons.close_rounded; label = 'Yanlış';
    } else {
      c = _kAmber; icon = Icons.hourglass_empty_rounded; label = 'Bekliyor';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 3),
          Text(label.tr(),
              style: GoogleFonts.poppins(
                fontSize: 9.5, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }

  List<Widget> _answerArea(BuildContext context, String type,
      List<String> choices, String answer, SubmissionAnswer? ans,
      Color ink, Color muted) {
    final sa = (ans?.studentAnswer ?? '').trim();

    if (type == 'mc') {
      // Her şık; doğru cevap yeşil, öğrencinin (yanlış) seçimi kırmızı.
      return choices.map((c) {
        final letter = c.isNotEmpty ? c.trim()[0].toUpperCase() : '';
        final correct = letter == answer.trim().toUpperCase();
        final chosen = sa.isNotEmpty &&
            (sa.toUpperCase() == letter || sa == c);
        // Renk önceliği: doğru şık yeşil; öğrencinin yanlış seçimi kırmızı.
        final Color borderC = correct
            ? _kGreen
            : (chosen ? _kRed : AppPalette.border(context));
        final Color fillC = correct
            ? _kGreen.withValues(alpha: 0.10)
            : (chosen ? _kRed.withValues(alpha: 0.08) : AppPalette.bg(context));
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: fillC,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderC,
                width: (correct || chosen) ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(c,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: (correct || chosen)
                            ? FontWeight.w800 : FontWeight.w600,
                        color: correct ? _kGreen : (chosen ? _kRed : ink),
                      )),
                ),
                // Öğrencinin seçimi etiketi
                if (chosen && !correct) ...[
                  Text('öğrenci'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: _kRed)),
                  const SizedBox(width: 4),
                  const Icon(Icons.close_rounded, size: 16, color: _kRed),
                ] else if (correct) ...[
                  if (chosen) ...[
                    Text('öğrenci'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 9, fontWeight: FontWeight.w700,
                          color: _kGreen)),
                    const SizedBox(width: 4),
                  ],
                  const Icon(Icons.check_circle_rounded,
                      size: 16, color: _kGreen),
                ],
              ],
            ),
          ),
        );
      }).toList();
    }

    // tf / fill / open → doğru cevap + (varsa) öğrencinin cevabı.
    String correctLabel;
    String correctValue;
    if (type == 'tf') {
      correctLabel = 'Doğru cevap'.tr();
      correctValue =
          (answer.toLowerCase() == 'true') ? 'Doğru'.tr() : 'Yanlış'.tr();
    } else if (type == 'fill') {
      correctLabel = 'Doğru cevap'.tr();
      correctValue = answer.isEmpty ? '—' : answer;
    } else {
      correctLabel = 'Örnek cevap'.tr();
      correctValue = answer.isEmpty ? '—' : answer;
    }

    final widgets = <Widget>[];

    // Öğrencinin cevabı (varsa) — önce göster.
    if (ans != null) {
      final Color c = ans.isCorrect == true
          ? _kGreen
          : ans.isCorrect == false
              ? _kRed
              : _kAmber;
      String shown = sa;
      if (type == 'tf' && sa.isNotEmpty) {
        shown = (sa.toLowerCase() == 'true') ? 'Doğru'.tr() : 'Yanlış'.tr();
      }
      if (shown.isEmpty) shown = 'Boş bırakıldı'.tr();
      widgets.add(_answerBox(
          context, 'Öğrencinin cevabı'.tr(), shown, c, ink));
      widgets.add(const SizedBox(height: 6));
    }

    // Doğru / örnek cevap.
    widgets.add(_answerBox(context, correctLabel, correctValue, _kGreen, ink));
    return widgets;
  }

  Widget _answerBox(BuildContext context, String label, String value,
      Color color, Color ink) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: color, letterSpacing: 0.3)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
        ],
      ),
    );
  }
}
