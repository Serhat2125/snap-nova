// ═══════════════════════════════════════════════════════════════════════════
//  TeacherHomeworkResultsScreen — ÖDEV-merkezli sonuç sayfası.
//
//  Ödev Geçmişim listesinde bir ödeve basınca açılır. Öğretmen tek bakışta:
//    • Ödev künyesi (ders • konu • soru sayısı, verildi/son teslim) + Testi Gör
//    • Teslim / Bekleyen / sınıf ortalaması özet kutuları
//    • SORU ANALİZİ — sınıfın en çok yanlış yaptığı sorular (yanlış sayısına
//      göre sıralı, hata payı barı ile)
//    • Öğrenci listesi (alt alta) — doğru/yanlış/boş + yüzde; satıra dokununca
//      mevcut TeacherHomeworkDetailScreen açılır: öğrencinin işaretlediği
//      şık + gerçek cevap + soru-soru hata haritası (öğrencinin gördüğü
//      inceleme ile aynı içerik).
//
//  AI çağrısı YOK — yalnızca submissions stream'i okunur (öğrenci başına 1
//  doküman; soru-soru cevaplar zaten submission.answers içinde kayıtlı).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_homework_detail_screen.dart';
import 'teacher_homework_view_screen.dart';

const _kBrand = Color(0xFF7C3AED);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kGray = Color(0xFF94A3B8);

class TeacherHomeworkResultsScreen extends StatelessWidget {
  final HomeworkModel homework;
  final String className;
  final int orderNo; // kaçıncı ödev (1, 2, 3…)
  const TeacherHomeworkResultsScreen({
    super.key,
    required this.homework,
    required this.className,
    required this.orderNo,
  });

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

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
            Text('$orderNo. ${'Ödev Sonuçları'.tr()}',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text(className,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 11, color: muted)),
          ],
        ),
        actions: [
          // Testin kendisi (sorular + doğru cevaplar) — salt-okunur görünüm.
          IconButton(
            tooltip: 'Testi Gör'.tr(),
            icon: const Icon(Icons.menu_book_rounded, color: _kBrand),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeacherHomeworkViewScreen(homework: homework))),
          ),
        ],
      ),
      body: StreamBuilder<List<HomeworkSubmissionModel>>(
        stream: HomeworkService.submissionsStream(homework.classId, homework.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _kBrand));
          }
          final subs = snap.data ?? const <HomeworkSubmissionModel>[];
          // Teslim edenler önce (yüksek skor üstte), bekleyenler sonda.
          final sorted = [...subs]..sort((a, b) {
              if (a.isSubmitted != b.isSubmitted) return a.isSubmitted ? -1 : 1;
              return (b.scorePercent ?? -1).compareTo(a.scorePercent ?? -1);
            });
          final submitted = sorted.where((s) => s.isSubmitted).toList();
          final pendingCount = sorted.length - submitted.length;
          final avg = submitted.isEmpty
              ? null
              : submitted.fold<double>(0, (t, s) => t + (s.scorePercent ?? 0)) /
                  submitted.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _headerCard(context, ink, muted),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statBox(context, '✅', '${submitted.length}', 'Teslim'.tr(),
                      _kGreen),
                  const SizedBox(width: 8),
                  _statBox(context, '⏳', '$pendingCount', 'Bekliyor'.tr(),
                      _kAmber),
                  const SizedBox(width: 8),
                  _statBox(
                      context,
                      '📊',
                      avg == null ? '—' : '%${avg.round()}',
                      'Ortalama'.tr(),
                      _kBrand),
                ],
              ),
              if (submitted.isNotEmpty) ...[
                const SizedBox(height: 14),
                _questionAnalysis(context, ink, muted, submitted),
              ],
              const SizedBox(height: 14),
              Text('Öğrenciler'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, fontWeight: FontWeight.w900, color: ink)),
              const SizedBox(height: 8),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('Henüz teslim eden olmadı.'.tr(),
                        style:
                            GoogleFonts.poppins(fontSize: 12.5, color: muted)),
                  ),
                )
              else
                for (final s in sorted) _studentRow(context, ink, muted, s),
            ],
          );
        },
      ),
    );
  }

  // ── Ödev künyesi ─────────────────────────────────────────────────────────
  Widget _headerCard(BuildContext context, Color ink, Color muted) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(homework.title,
              style: GoogleFonts.poppins(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 4),
          Text(
              '${homework.subject} • ${homework.topic} • '
              '${homework.questionCount} ${'soru'.tr()}',
              style: GoogleFonts.poppins(fontSize: 11.5, color: muted)),
          const SizedBox(height: 2),
          Text(
              '${'Verildi'.tr()}: ${_fmtDate(homework.assignedAt)}'
              ' • ${'Son teslim'.tr()}: ${_fmtDate(homework.dueAt)}',
              style: GoogleFonts.poppins(fontSize: 10.5, color: muted)),
        ],
      ),
    );
  }

  Widget _statBox(
      BuildContext c, String emoji, String val, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            Text(val,
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w900, color: color)),
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(c))),
          ],
        ),
      ),
    );
  }

  // ── Soru analizi — sınıfın takıldığı sorular ─────────────────────────────
  Widget _questionAnalysis(BuildContext context, Color ink, Color muted,
      List<HomeworkSubmissionModel> submitted) {
    // Soru index'i → (yanlış, doğru) sayısı. answers dizisinden toplanır.
    final wrongCount = <int, int>{};
    final rightCount = <int, int>{};
    for (final s in submitted) {
      for (final a in s.answers) {
        if (a.isCorrect == false) {
          wrongCount[a.index] = (wrongCount[a.index] ?? 0) + 1;
        } else if (a.isCorrect == true) {
          rightCount[a.index] = (rightCount[a.index] ?? 0) + 1;
        }
      }
    }
    final troubled = wrongCount.keys.toList()
      ..sort((a, b) => wrongCount[b]!.compareTo(wrongCount[a]!));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔍 ${'Soru Analizi'.tr()}',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 2),
          Text('Sınıfın en çok yanlış yaptığı sorular üstte.'.tr(),
              style: GoogleFonts.poppins(fontSize: 10.5, color: muted)),
          const SizedBox(height: 10),
          if (troubled.isEmpty)
            Text('🎉 ${'Teslim edilen ödevlerde yanlış cevap yok.'.tr()}',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600, color: _kGreen))
          else
            for (final qi in troubled) _questionRow(context, ink, muted, qi,
                wrongCount[qi]!, rightCount[qi] ?? 0, submitted.length),
        ],
      ),
    );
  }

  Widget _questionRow(BuildContext context, Color ink, Color muted, int index,
      int wrong, int right, int total) {
    final qText = index < homework.questions.length
        ? (homework.questions[index]['q'] ?? '').toString()
        : '';
    final ratio = total == 0 ? 0.0 : wrong / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text('${index + 1}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w900,
                        color: _kRed)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(qText.isEmpty ? '${'Soru'.tr()} ${index + 1}' : qText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: ink)),
              ),
              const SizedBox(width: 8),
              Text('✗$wrong  ✓$right',
                  style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w800, color: muted)),
            ],
          ),
          const SizedBox(height: 4),
          // Hata payı barı — yanlış yapan öğrenci oranı.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: _kGreen.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(_kRed),
            ),
          ),
        ],
      ),
    );
  }

  // ── Öğrenci satırı ───────────────────────────────────────────────────────
  Widget _studentRow(BuildContext context, Color ink, Color muted,
      HomeworkSubmissionModel s) {
    final name = s.studentDisplayName.trim().isEmpty
        ? '@${s.studentUsername}'
        : s.studentDisplayName;
    final correct = s.correct ?? 0;
    final wrong = s.wrong ?? 0;
    final blank = s.isSubmitted
        ? (homework.questionCount - correct - wrong).clamp(0, 999)
        : 0;
    final late = s.status == 'late';
    final statusColor =
        s.isSubmitted ? (late ? _kAmber : _kGreen) : _kGray;
    final statusLabel = s.isSubmitted
        ? (late ? 'Gecikmeli'.tr() : 'Teslim'.tr())
        : 'Bekliyor'.tr();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TeacherHomeworkDetailScreen(
                    homework: homework,
                    submission: s,
                    studentName: name,
                    orderNo: orderNo,
                  ))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                      name.replaceAll('@', '').isEmpty
                          ? '👤'
                          : name.replaceAll('@', '')[0].toUpperCase(),
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: _kBrand)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: ink)),
                      const SizedBox(height: 2),
                      s.isSubmitted
                          ? Text(
                              '✓$correct  ✗$wrong'
                              '${blank > 0 ? '  −$blank ${'boş'.tr()}' : ''}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: muted))
                          : Text('Henüz çözmedi'.tr(),
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (s.isSubmitted && s.scorePercent != null)
                  Text('%${s.scorePercent!.round()}',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _scoreColor(s.scorePercent!))),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(statusLabel,
                      style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor)),
                ),
                Icon(Icons.chevron_right_rounded, color: muted, size: 20),
              ],
            ),
          ),
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
