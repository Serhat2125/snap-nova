// ═══════════════════════════════════════════════════════════════════════════
//  TeacherHomeworkDetailScreen — Tek ödevin öğrenci-bazlı analiz paneli.
//
//  Üstte profil + ödev künyesi (kaçıncı ödev, ad, başlangıç/bitiş tarihleri).
//  Altında Grafik | Tablo sekmesi:
//    • Grafik → doğru/yanlış/boş pasta dağılımı + yan istatistik.
//    • Tablo  → Excel benzeri istatistik tablosu + soru-soru durum.
//  Her ikisinin altında "Öğrencinin verdiği cevaplara bak" → cevap görünümü.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_homework_view_screen.dart';

const _kBrand = Color(0xFF7C3AED);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kGray = Color(0xFF94A3B8);
const _kAmber = Color(0xFFF59E0B);

class TeacherHomeworkDetailScreen extends StatefulWidget {
  final HomeworkModel homework;
  final HomeworkSubmissionModel? submission;
  final String studentName;
  final String studentAvatar;
  final int orderNo; // kaçıncı ödev (1, 2, 3…)
  const TeacherHomeworkDetailScreen({
    super.key,
    required this.homework,
    required this.submission,
    required this.studentName,
    required this.orderNo,
    this.studentAvatar = '👤',
  });

  @override
  State<TeacherHomeworkDetailScreen> createState() =>
      _TeacherHomeworkDetailScreenState();
}

class _TeacherHomeworkDetailScreenState
    extends State<TeacherHomeworkDetailScreen> {
  int _tab = 0; // 0 = Grafik, 1 = Tablo
  bool _qExpanded = true; // "Soru bazında" tablosu açık/kapalı

  HomeworkModel get hw => widget.homework;
  HomeworkSubmissionModel? get sub => widget.submission;
  bool get submitted => sub?.isSubmitted ?? false;

  // ── Doğru / yanlış / boş / bekliyor sayıları ───────────────────────────
  ({int total, int correct, int wrong, int empty, int pending, double pct})
      get _stats {
    int correct = 0, wrong = 0, empty = 0, pending = 0;
    final answers = sub?.answers ?? const <SubmissionAnswer>[];
    if (answers.isNotEmpty) {
      for (final a in answers) {
        final blank = a.studentAnswer.trim().isEmpty;
        if (blank) {
          empty++;
        } else if (a.isCorrect == true) {
          correct++;
        } else if (a.isCorrect == false) {
          wrong++;
        } else {
          pending++;
        }
      }
    } else {
      correct = sub?.correct ?? 0;
      wrong = sub?.wrong ?? 0;
    }
    // Toplam soru: ödevin soru sayısı, yoksa cevap sayısı, o da yoksa
    // sayımların toplamı (asla 0'a bölünme olmasın).
    final qCount =
        hw.questionCount > 0 ? hw.questionCount : answers.length;
    final total = qCount > 0 ? qCount : (correct + wrong + empty + pending);
    // Cevaplanmayan/eksik kalan soruları boş say (slice'lar toplamı = total).
    final counted = correct + wrong + empty + pending;
    if (total > counted) empty += total - counted;
    // Başarı oranı TOPLAM sorulan soru üzerinden (boş/yanlış da paydada).
    final pct = total > 0 ? correct * 100 / total : 0.0;
    return (
      total: total,
      correct: correct,
      wrong: wrong,
      empty: empty,
      pending: pending,
      pct: pct
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
        title: Text('${widget.orderNo}. ${'Ödev'.tr()}',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _profileHeader(context),
            const SizedBox(height: 12),
            _homeworkMeta(context),
            const SizedBox(height: 16),
            _tabBar(context),
            const SizedBox(height: 14),
            if (!submitted)
              _notSubmitted(context)
            else ...[
              _tab == 0 ? _graphSection(context) : _tableSection(context),
              const SizedBox(height: 16),
              _answersButton(context),
            ],
          ],
        ),
      ),
    );
  }

  // ── Profil (en üstte) ──────────────────────────────────────────────────
  Widget _profileHeader(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Row(
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrand.withValues(alpha: 0.12),
          ),
          alignment: Alignment.center,
          child: Text(widget.studentAvatar,
              style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(widget.studentName,
              style: GoogleFonts.poppins(
                fontSize: 17, fontWeight: FontWeight.w900, color: ink,
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // ── Ödev künyesi ───────────────────────────────────────────────────────
  //  Sol: konu → ödev adı → ödev no.  Sağ üst (küçük): başlangıç → bitiş → soru.
  Widget _homeworkMeta(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SOL: konu / ödev adı / ödev no
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${hw.subject} · ${hw.topic}',
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w700,
                        color: muted),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(hw.title,
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: ink, height: 1.2),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${widget.orderNo}. ${'Ödev'.tr()}',
                      style: GoogleFonts.poppins(
                          fontSize: 10.5, fontWeight: FontWeight.w800,
                          color: _kBrand)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // SAĞ ÜST: küçük başlangıç / bitiş / soru sayısı
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _rightInfo(context, '🟢', 'Başlangıç'.tr(),
                  _fmtDate(hw.assignedAt)),
              const SizedBox(height: 6),
              _rightInfo(context, '🔴', 'Bitiş'.tr(), _fmtDate(hw.dueAt)),
              const SizedBox(height: 6),
              _rightInfo(context, '❓', 'Soru'.tr(), '${_stats.total}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rightInfo(
      BuildContext context, String emoji, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$emoji $label',
            style: GoogleFonts.poppins(
                fontSize: 8.5, fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context))),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context))),
      ],
    );
  }

  // ── Grafik | Tablo sekme çubuğu ────────────────────────────────────────
  Widget _tabBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          _tabBtn(context, 0, Icons.pie_chart_rounded, 'Grafik'.tr()),
          _tabBtn(context, 1, Icons.table_chart_rounded, 'Tablo'.tr()),
        ],
      ),
    );
  }

  Widget _tabBtn(BuildContext context, int i, IconData icon, String label) {
    final sel = _tab == i;
    final muted = AppPalette.textSecondary(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? _kBrand : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: sel ? Colors.white : muted),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: sel ? Colors.white : muted,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ── GRAFİK: pasta + yan istatistik ─────────────────────────────────────
  Widget _graphSection(BuildContext context) {
    final s = _stats;
    return Container(
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
              const Text('🥧', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text('Cevap Dağılımı'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Pasta (daire)
              SizedBox(
                width: 132, height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(PieChartData(
                      centerSpaceRadius: 34,
                      sectionsSpace: 2,
                      sections: [
                        if (s.correct > 0)
                          _slice(s.correct, s.total, _kGreen),
                        if (s.wrong > 0) _slice(s.wrong, s.total, _kRed),
                        if (s.empty > 0) _slice(s.empty, s.total, _kGray),
                        if (s.pending > 0) _slice(s.pending, s.total, _kAmber),
                      ],
                    )),
                    // Merkez: toplam başarı
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('%${s.pct.toStringAsFixed(0)}',
                            style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.w900,
                              color: _scoreColor(s.pct))),
                        Text('başarı'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 8.5,
                              color: AppPalette.textSecondary(context))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Yan istatistik — tablo içinde
              Expanded(
                child: Table(
                  border: TableBorder.all(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(),
                    1: FixedColumnWidth(44),
                  },
                  children: [
                    _statRow(context, '📋 ${'Soru'.tr()}',
                        s.total, const Color(0xFF6366F1)),
                    _statRow(context, '✅ ${'Doğru'.tr()}', s.correct, _kGreen),
                    _statRow(context, '❌ ${'Yanlış'.tr()}', s.wrong, _kRed),
                    _statRow(context, '⬜ ${'Boş'.tr()}', s.empty, _kGray),
                    if (s.pending > 0)
                      _statRow(context, '⏳ ${'Bekliyor'.tr()}',
                          s.pending, _kAmber),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Toplam başarı şeridi
          _successBar(context, s.pct),
        ],
      ),
    );
  }

  PieChartSectionData _slice(int v, int total, Color c) => PieChartSectionData(
        value: v.toDouble(),
        color: c,
        title: total > 0 ? '${(v * 100 / total).round()}%' : '',
        radius: 32,
        titleStyle: GoogleFonts.poppins(
            fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.white),
      );

  TableRow _statRow(BuildContext context, String label, int value, Color c) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11.5, fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Text('$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w900, color: c)),
        ),
      ],
    );
  }

  Widget _successBar(BuildContext context, double pct) {
    final c = _scoreColor(pct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('🎯 ${'Toplam Başarı'.tr()}',
                style: GoogleFonts.poppins(
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context))),
            const Spacer(),
            Text('%${pct.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w900, color: c)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppPalette.border(context),
            valueColor: AlwaysStoppedAnimation(c),
          ),
        ),
      ],
    );
  }

  // ── TABLO: Excel benzeri istatistik ────────────────────────────────────
  Widget _tableSection(BuildContext context) {
    final s = _stats;
    final ink = AppPalette.textPrimary(context);
    return Container(
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
              const Text('📊', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text('Ödev İstatistikleri'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
            ],
          ),
          const SizedBox(height: 12),
          // Özet tablo (Excel benzeri)
          Table(
            border: TableBorder.all(
              color: AppPalette.border(context),
              borderRadius: BorderRadius.circular(10),
            ),
            children: [
              TableRow(
                decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: 0.10)),
                children: [
                  _th(context, '✅ ${'Doğru'.tr()}'),
                  _th(context, '❌ ${'Yanlış'.tr()}'),
                  _th(context, '⬜ ${'Boş'.tr()}'),
                  _th(context, '🎯 ${'Başarı'.tr()}'),
                ],
              ),
              TableRow(
                children: [
                  _td(context, '${s.correct}', _kGreen),
                  _td(context, '${s.wrong}', _kRed),
                  _td(context, '${s.empty}', _kGray),
                  _td(context, '%${s.pct.toStringAsFixed(0)}',
                      _scoreColor(s.pct)),
                ],
              ),
            ],
          ),
          if (s.pending > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('⏳', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text('${'Değerlendirilmeyi bekleyen'.tr()}: ${s.pending}',
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: _kAmber)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          // Soru-soru durum tablosu — açılır/kapanır başlık
          InkWell(
            onTap: () => setState(() => _qExpanded = !_qExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                      _qExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 20, color: _kBrand),
                  const SizedBox(width: 4),
                  Text('Soru bazında'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(context))),
                ],
              ),
            ),
          ),
          if (_qExpanded) ...[
            const SizedBox(height: 8),
            if ((sub?.answers ?? const []).isNotEmpty)
              Table(
                border: TableBorder.all(
                  color: AppPalette.border(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                columnWidths: const {
                  0: FixedColumnWidth(70),
                  1: FlexColumnWidth(),
                  2: FixedColumnWidth(90),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                        color: _kBrand.withValues(alpha: 0.10)),
                    children: [
                      _th(context, 'Soru\nnumarası'.tr()),
                      _th(context, 'Tür'.tr()),
                      _th(context, 'Durum'.tr()),
                    ],
                  ),
                  ...sub!.answers.asMap().entries.map((e) {
                    final a = e.value;
                    return TableRow(
                      children: [
                        _td(context, '${e.key + 1}', ink),
                        _td(context, _typeLabel(a.type),
                            AppPalette.textSecondary(context), bold: false),
                        _statusCell(context, a),
                      ],
                    );
                  }),
                ],
              )
            else
              Text('Soru-soru detay yok.'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppPalette.textSecondary(context))),
          ],
        ],
      ),
    );
  }

  Widget _th(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Text(t,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context))),
      );

  Widget _td(BuildContext context, String t, Color color,
          {bool bold = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Text(t,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                color: color)),
      );

  Widget _statusCell(BuildContext context, SubmissionAnswer a) {
    String label;
    Color c;
    if (a.studentAnswer.trim().isEmpty) {
      label = '⬜ ${'Boş'.tr()}'; c = _kGray;
    } else if (a.isCorrect == true) {
      label = '✅ ${'Doğru'.tr()}'; c = _kGreen;
    } else if (a.isCorrect == false) {
      label = '❌ ${'Yanlış'.tr()}'; c = _kRed;
    } else {
      label = '⏳ ${'Bekliyor'.tr()}'; c = _kAmber;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      child: Text(label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
    );
  }

  // ── "Öğrencinin verdiği cevaplara bak" ─────────────────────────────────
  Widget _answersButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TeacherHomeworkViewScreen(
            homework: hw,
            submission: sub,
            studentName: widget.studentName,
          ),
        )),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.fact_check_rounded, size: 19),
        label: Text('Öğrencinin verdiği cevaplara bak'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 13.5, fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
    );
  }

  Widget _notSubmitted(BuildContext context) {
    final muted = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        children: [
          const Text('📭', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Bu ödev henüz teslim edilmedi.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context))),
          const SizedBox(height: 6),
          Text('Öğrenci ödevi tamamlayınca grafik ve istatistikler '
                  'burada görünür.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: muted, height: 1.4)),
        ],
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 70) return _kGreen;
    if (score >= 40) return _kAmber;
    return _kRed;
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'mc': return 'Çoktan seçmeli'.tr();
      case 'tf': return 'Doğru/Yanlış'.tr();
      case 'fill': return 'Boşluk'.tr();
      default: return 'Açık uçlu'.tr();
    }
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Oca','Şub','Mar','Nis','May','Haz',
      'Tem','Ağu','Eyl','Eki','Kas','Ara',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
