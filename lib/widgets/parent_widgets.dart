// ═══════════════════════════════════════════════════════════════════════════
//  Parent Dashboard widget'ları — fl_chart entegre.
//
//  Bu dosyada:
//    • WeeklyStudyChart      — 7 gün × ders bazlı BarChart
//    • SubjectSuccessChart   — LineChart, ders başarı oranı zaman çizelgesi
//    • QuestionAnalyticsPie  — PieChart, doğru/yanlış/boş dağılımı
//    • PhotoQuestionCounter  — Foto-çözüm sayacı kartı
//    • AiInsightsBox         — Gemini'den anlık içgörü
//    • HorizontalSummariesScroll — son özetler yatay kaydırılabilir
//
//  Hepsi mevcut AppPalette + GoogleFonts.poppins ile tutarlı.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/education_models.dart';
import '../services/gemini_service.dart';
import '../services/locale_service.dart';
import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

// Brand palet — chartlarda kullanılacak.
const _palette = <Color>[
  Color(0xFF2563EB), // mavi
  Color(0xFFEC4899), // pembe
  Color(0xFF10B981), // yeşil
  Color(0xFFFF6A00), // turuncu
  Color(0xFF7C3AED), // mor
  Color(0xFF06B6D4), // cyan
];

// ─────────────────────────────────────────────────────────────────────────
// 1) HAFTALIK ÇALIŞMA BAR CHART
//    7 gün × ders bazlı stack — günlük toplam dakika.
// ─────────────────────────────────────────────────────────────────────────
class WeeklyStudyChart extends StatelessWidget {
  final List<StudentActivityModel> last7Days;
  const WeeklyStudyChart({super.key, required this.last7Days});

  @override
  Widget build(BuildContext context) {
    if (last7Days.isEmpty) {
      return _emptyBox('Henüz çalışma verisi yok.'.tr());
    }
    // Hangi dersler var?
    final subjects = <String>{};
    for (final a in last7Days) {
      subjects.addAll(a.subjectDurations.keys);
    }
    final subjectList = subjects.take(5).toList(); // max 5 ders renkli görünür

    // Y-ekseni max dakika
    double maxY = 0;
    for (final a in last7Days) {
      final dayTotal = a.subjectDurations.values.fold<int>(0, (s, v) => s + v);
      if (dayTotal > maxY) maxY = dayTotal.toDouble();
    }
    maxY = (maxY / 60.0).ceilToDouble() * 60; // saniyeye → dakikaya
    if (maxY < 30) maxY = 30;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, '📅', 'Haftalık çalışma süresi'.tr()),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppPalette.textPrimary(context),
                    tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    tooltipMargin: 6,
                    getTooltipItem: (group, _, rod, __) {
                      final mins = (rod.toY).toStringAsFixed(0);
                      return BarTooltipItem(
                        '$mins dk',
                        GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: AppPalette.bg(context),
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 30,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}',
                        style: GoogleFonts.poppins(
                          fontSize: 9.5, color: AppPalette.textSecondary(context),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= last7Days.length) return const SizedBox.shrink();
                        final dk = last7Days[idx].dateKey;
                        final dayLabel = dk.length >= 10 ? dk.substring(5) : dk;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(dayLabel,
                              style: GoogleFonts.poppins(
                                fontSize: 9, fontWeight: FontWeight.w700,
                                color: AppPalette.textSecondary(context),
                              )),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true, horizontalInterval: maxY / 4,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppPalette.border(context),
                    strokeWidth: 0.8,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(last7Days.length, (i) {
                  final act = last7Days[i];
                  double cumulative = 0;
                  final stacks = <BarChartRodStackItem>[];
                  for (int s = 0; s < subjectList.length; s++) {
                    final mins = (act.subjectDurations[subjectList[s]] ?? 0) / 60.0;
                    if (mins <= 0) continue;
                    stacks.add(BarChartRodStackItem(
                      cumulative,
                      cumulative + mins,
                      _palette[s % _palette.length],
                    ));
                    cumulative += mins;
                  }
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: cumulative,
                        width: 14,
                        borderRadius: BorderRadius.circular(4),
                        rodStackItems: stacks,
                        color: AppPalette.border(context),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Renk legendası
          Wrap(
            spacing: 12, runSpacing: 6,
            children: [
              for (int i = 0; i < subjectList.length; i++)
                _legendDot(_palette[i % _palette.length], subjectList[i]),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 2) DERS BAŞARI ZAMAN ÇİZELGESİ (LineChart)
// ─────────────────────────────────────────────────────────────────────────
class SubjectSuccessChart extends StatelessWidget {
  final List<StudentActivityModel> last7Days;
  const SubjectSuccessChart({super.key, required this.last7Days});

  @override
  Widget build(BuildContext context) {
    if (last7Days.isEmpty || last7Days.every((d) => d.successPercent == null)) {
      return _emptyBox('Henüz test verisi yok.'.tr());
    }
    final spots = <FlSpot>[];
    for (int i = 0; i < last7Days.length; i++) {
      final p = last7Days[i].successPercent;
      if (p != null) spots.add(FlSpot(i.toDouble(), p));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, '📈', 'Başarı oranı (7 gün)'.tr()),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: 0, maxY: 100,
                gridData: FlGridData(
                  show: true, drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppPalette.border(context), strokeWidth: 0.6,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 32,
                      getTitlesWidget: (v, _) {
                        if (v % 25 != 0) return const SizedBox.shrink();
                        return Text('%${v.toInt()}',
                            style: GoogleFonts.poppins(
                              fontSize: 9, color: AppPalette.textSecondary(context),
                            ));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= last7Days.length) return const SizedBox.shrink();
                        final dk = last7Days[idx].dateKey;
                        return Text(
                          dk.length >= 10 ? dk.substring(5) : dk,
                          style: GoogleFonts.poppins(
                            fontSize: 9, fontWeight: FontWeight.w700,
                            color: AppPalette.textSecondary(context),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true, curveSmoothness: 0.32,
                    color: const Color(0xFF10B981),
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 4, color: const Color(0xFF10B981),
                        strokeColor: AppPalette.card(context), strokeWidth: 2,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF10B981).withValues(alpha: 0.20),
                          const Color(0xFF10B981).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 3) PIE CHART — Doğru / Yanlış / Boş dağılımı
// ─────────────────────────────────────────────────────────────────────────
class QuestionAnalyticsPie extends StatelessWidget {
  final int correct;
  final int wrong;
  final int blank;
  const QuestionAnalyticsPie({
    super.key,
    required this.correct,
    required this.wrong,
    required this.blank,
  });

  @override
  Widget build(BuildContext context) {
    final total = correct + wrong + blank;
    if (total == 0) {
      return _emptyBox('Henüz test çözmedi.'.tr());
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, '🥧', 'Test cevap dağılımı'.tr()),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 130, height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 32,
                    sectionsSpace: 2,
                    sections: [
                      if (correct > 0)
                        PieChartSectionData(
                          value: correct.toDouble(),
                          color: const Color(0xFF10B981),
                          title: '${(correct * 100 / total).round()}%',
                          radius: 38,
                          titleStyle: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      if (wrong > 0)
                        PieChartSectionData(
                          value: wrong.toDouble(),
                          color: const Color(0xFFEF4444),
                          title: '${(wrong * 100 / total).round()}%',
                          radius: 38,
                          titleStyle: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      if (blank > 0)
                        PieChartSectionData(
                          value: blank.toDouble(),
                          color: const Color(0xFF94A3B8),
                          title: '${(blank * 100 / total).round()}%',
                          radius: 38,
                          titleStyle: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pieRow(context, const Color(0xFF10B981),
                        'Doğru'.tr(), correct),
                    const SizedBox(height: 6),
                    _pieRow(context, const Color(0xFFEF4444),
                        'Yanlış'.tr(), wrong),
                    const SizedBox(height: 6),
                    _pieRow(context, const Color(0xFF94A3B8),
                        'Boş'.tr(), blank),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Toplam: $total'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w800,
                          color: const Color(0xFF065F46),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pieRow(BuildContext c, Color color, String label, int value) {
    return Row(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary(c),
              )),
        ),
        Text('$value',
            style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(c),
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 3b) DERS BAZLI PERFORMANS TABLOSU
//     Her ders: doğru/yanlış + başarı çubuğu; genel ortalama referans çizgisi.
// ─────────────────────────────────────────────────────────────────────────
class SubjectPerformanceTable extends StatelessWidget {
  final List<StudentActivityModel> last7Days;
  const SubjectPerformanceTable({super.key, required this.last7Days});

  @override
  Widget build(BuildContext context) {
    final correct = <String, int>{};
    final wrong = <String, int>{};
    for (final a in last7Days) {
      a.subjectCorrect.forEach((k, v) => correct[k] = (correct[k] ?? 0) + v);
      a.subjectWrong.forEach((k, v) => wrong[k] = (wrong[k] ?? 0) + v);
    }
    final rows = <(String, int, int, double)>[]; // ders, doğru, yanlış, %
    final keys = {...correct.keys, ...wrong.keys};
    for (final k in keys) {
      final c = correct[k] ?? 0;
      final w = wrong[k] ?? 0;
      if (c + w == 0) continue;
      rows.add((k, c, w, c * 100.0 / (c + w)));
    }
    if (rows.isEmpty) {
      return _emptyBox('Ders bazlı test verisi yok.'.tr());
    }
    rows.sort((a, b) => b.$4.compareTo(a.$4));
    final totalC = correct.values.fold<int>(0, (s, v) => s + v);
    final totalW = wrong.values.fold<int>(0, (s, v) => s + v);
    final overall = (totalC + totalW) == 0 ? 0.0 : totalC * 100.0 / (totalC + totalW);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, '📋', 'Ders bazlı başarı'.tr()),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 13,
                  color: AppPalette.textSecondary(context)),
              const SizedBox(width: 4),
              Text('${'Genel ortalama'.tr()}: %${overall.round()}',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
                  )),
            ],
          ),
          const SizedBox(height: 12),
          ...rows.map((r) => _row(context, r.$1, r.$2, r.$3, r.$4, overall)),
        ],
      ),
    );
  }

  Widget _row(BuildContext c, String subject, int correct, int wrong,
      double pct, double overall) {
    final aboveAvg = pct >= overall;
    final barColor = pct >= 80
        ? const Color(0xFF10B981)
        : pct >= 60
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(subject,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(c),
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Icon(
                aboveAvg
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: aboveAvg
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 2),
              Text('%${pct.round()}',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w900,
                    color: barColor,
                  )),
              const SizedBox(width: 8),
              Text('$correct✓ $wrong✗',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5, fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(c),
                  )),
            ],
          ),
          const SizedBox(height: 5),
          Stack(
            children: [
              Container(
                height: 7,
                decoration: BoxDecoration(
                  color: AppPalette.border(c),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: (pct / 100).clamp(0.02, 1.0),
                child: Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Genel ortalama referans işareti
              FractionallySizedBox(
                widthFactor: (overall / 100).clamp(0.0, 1.0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 2, height: 7,
                    color: AppPalette.textSecondary(c).withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 4) FOTO-SORU SAYACI
// ─────────────────────────────────────────────────────────────────────────
class PhotoQuestionCounter extends StatelessWidget {
  final int totalPhotoQuestions;
  final Map<String, int> bySubject; // ders adı → adet
  const PhotoQuestionCounter({
    super.key,
    required this.totalPhotoQuestions,
    required this.bySubject,
  });

  @override
  Widget build(BuildContext context) {
    final entries = bySubject.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, '📸', 'Fotoğraftan çözdüğü sorular'.tr()),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6A00), Color(0xFFEC4899)],
                  ),
                ),
                alignment: Alignment.center,
                child: Text('$totalPhotoQuestions',
                    style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.w900,
                      color: Colors.white,
                    )),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Toplam soru sayısı'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppPalette.textSecondary(context),
                        )),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      Text('Henüz foto-çözüm yok.'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: AppPalette.textSecondary(context),
                          ))
                    else
                      Wrap(
                        spacing: 6, runSpacing: 4,
                        children: entries.take(4).map((e) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppPalette.bg(context),
                              border: Border.all(
                                  color: AppPalette.border(context)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('${e.key} · ${e.value}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11, fontWeight: FontWeight.w700,
                                  color: AppPalette.textPrimary(context),
                                )),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 5) AI INSIGHTS KUTUSU — Gemini'den canlı içgörü
// ─────────────────────────────────────────────────────────────────────────
class AiInsightsBox extends StatefulWidget {
  final String childName;
  final List<StudentActivityModel> last7Days;
  const AiInsightsBox({
    super.key, required this.childName, required this.last7Days,
  });

  @override
  State<AiInsightsBox> createState() => _AiInsightsBoxState();
}

class _AiInsightsBoxState extends State<AiInsightsBox> {
  String? _insight;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void didUpdateWidget(AiInsightsBox old) {
    super.didUpdateWidget(old);
    // Veri değiştiyse içgörüyü yenile (yeni gün, yeni veri).
    if (old.last7Days.length != widget.last7Days.length) _generate();
  }

  Future<void> _generate() async {
    if (widget.last7Days.isEmpty) return;
    setState(() => _loading = true);
    final subjMinutes = <String, int>{};
    final subjSuccessSum = <String, double>{};
    final subjSuccessCount = <String, int>{};
    int totalQ = 0, totalS = 0;
    for (final a in widget.last7Days) {
      a.subjectDurations.forEach((subject, secs) {
        subjMinutes[subject] = (subjMinutes[subject] ?? 0) + (secs ~/ 60);
      });
      totalQ += a.testsSolved + a.photoQuestionsSolved;
      totalS += a.summariesCreated;
      if (a.successPercent != null) {
        // Tüm dersleri aynı yüzde varsayıyoruz (basit modelde)
        for (final s in a.subjectDurations.keys) {
          subjSuccessSum[s] = (subjSuccessSum[s] ?? 0) + a.successPercent!;
          subjSuccessCount[s] = (subjSuccessCount[s] ?? 0) + 1;
        }
      }
    }
    final subjSuccess = <String, double>{};
    subjSuccessSum.forEach((k, v) {
      final n = subjSuccessCount[k] ?? 1;
      subjSuccess[k] = v / n;
    });
    try {
      final text = await GeminiService.generateParentInsight(
        childName: widget.childName,
        subjectMinutes: subjMinutes,
        subjectSuccess: subjSuccess,
        totalQuestionsSolved: totalQ,
        totalSummariesCreated: totalS,
      );
      if (!mounted) return;
      setState(() {
        _insight = text;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C3AED).withValues(alpha: 0.10),
            const Color(0xFFEC4899).withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.30), width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('AI İçgörüsü'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: const Color(0xFF581C87),
                    )),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, size: 18,
                    color: const Color(0xFF7C3AED)),
                onPressed: _loading ? null : _generate,
                tooltip: 'Yenile'.tr(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            )
          else if (_insight != null)
            Text(_insight!,
                style: GoogleFonts.poppins(
                  fontSize: 13, height: 1.55,
                  color: AppPalette.textPrimary(context),
                ))
          else
            Text(
              'İçgörü üretilemedi — çocuk biraz veri biriktirince burada görünecek.'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12, color: AppPalette.textSecondary(context),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 0) ÖĞRETMEN DUYURULARI — çocuğun sınıflarından gelen duyurular.
// ─────────────────────────────────────────────────────────────────────────
class TeacherAnnouncementsCard extends StatefulWidget {
  final String childUid;
  /// Dashboard'daki pull-to-refresh her tetiklendiğinde artan sayaç —
  /// bu widget kendi verisini sadece childUid değişince yeniliyordu, bu
  /// yüzden aşağı çekip yenilemek duyuruları hiç tazelemiyordu.
  final int refreshTick;
  const TeacherAnnouncementsCard({
    super.key,
    required this.childUid,
    this.refreshTick = 0,
  });

  @override
  State<TeacherAnnouncementsCard> createState() =>
      _TeacherAnnouncementsCardState();
}

class _TeacherAnnouncementsCardState extends State<TeacherAnnouncementsCard> {
  List<ParentAnnouncement>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TeacherAnnouncementsCard old) {
    super.didUpdateWidget(old);
    if (old.childUid != widget.childUid) {
      setState(() => _items = null);
      _load();
    } else if (old.refreshTick != widget.refreshTick) {
      _load();
    }
  }

  Future<void> _load() async {
    final list =
        await ParentLinkService.readChildAnnouncements(widget.childUid);
    if (!mounted) return;
    setState(() => _items = list);
  }

  String _rel(DateTime w) {
    final d = DateTime.now().difference(w);
    if (d.inMinutes < 60) return '${d.inMinutes} dk';
    if (d.inHours < 24) return '${d.inHours} sa';
    if (d.inDays < 7) return '${d.inDays} g';
    return '${w.day}.${w.month}.${w.year}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    // Yükleniyor ya da hiç duyuru yoksa kartı gösterme (paneli şişirme).
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final show = items.take(4).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_rounded,
                  size: 18, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Text('Öğretmen duyuruları'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: const Color(0xFF92400E),
                  )),
            ],
          ),
          const SizedBox(height: 8),
          ...show.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.message,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary(context),
                    )),
                const SizedBox(height: 2),
                Text(
                    '${a.className}'
                    '${a.teacherName.isNotEmpty ? ' · ${a.teacherName}' : ''}'
                    ' · ${_rel(a.when)}',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, color: AppPalette.textSecondary(context),
                    )),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 0z) ÖĞRETMEN NOTLARI / TEBRİKLERİ — öğretmenin "veliyle paylaş" diyerek
//     yazdığı notlar + hızlı tebrik/takdirler (👏). Daha önce hiçbir ebeveyn
//     ekranı bunu okumuyordu — öğretmen tarafı "veli panelinde görünür"
//     diyordu ama gösterilmiyordu.
// ─────────────────────────────────────────────────────────────────────────
class TeacherNotesCard extends StatefulWidget {
  final String childUid;
  final int refreshTick;
  const TeacherNotesCard({
    super.key,
    required this.childUid,
    this.refreshTick = 0,
  });

  @override
  State<TeacherNotesCard> createState() => _TeacherNotesCardState();
}

class _TeacherNotesCardState extends State<TeacherNotesCard> {
  List<ParentTeacherNote>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TeacherNotesCard old) {
    super.didUpdateWidget(old);
    if (old.childUid != widget.childUid) {
      setState(() => _items = null);
      _load();
    } else if (old.refreshTick != widget.refreshTick) {
      _load();
    }
  }

  Future<void> _load() async {
    final list = await ParentLinkService.readChildNotes(widget.childUid);
    if (!mounted) return;
    setState(() => _items = list);
  }

  String _rel(DateTime w) {
    final d = DateTime.now().difference(w);
    if (d.inMinutes < 60) return '${d.inMinutes} dk';
    if (d.inHours < 24) return '${d.inHours} sa';
    if (d.inDays < 7) return '${d.inDays} g';
    return '${w.day}.${w.month}.${w.year}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final show = items.take(4).toList();
    const brand = Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, size: 18, color: brand),
              const SizedBox(width: 8),
              Text('Öğretmen notları ve tebrikleri'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: const Color(0xFF065F46),
                  )),
            ],
          ),
          const SizedBox(height: 8),
          ...show.map((n) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n.isPraise)
                  const Padding(
                    padding: EdgeInsets.only(right: 6, top: 1),
                    child: Text('👏', style: TextStyle(fontSize: 13)),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.text,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5, height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimary(context),
                          )),
                      const SizedBox(height: 2),
                      Text('${n.className} · ${_rel(n.when)}',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            color: AppPalette.textSecondary(context),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 0y) BİLGİ LİGİ BAŞARILARI — çocuğun quiz/yarışma sıralaması ve streak'i.
//     Daha önce ebeveyn panelinde Bilgi Ligi'ye dair HİÇBİR gösterim yoktu.
// ─────────────────────────────────────────────────────────────────────────
class LeagueStatsCard extends StatefulWidget {
  final String childUid;
  final int refreshTick;
  const LeagueStatsCard({
    super.key,
    required this.childUid,
    this.refreshTick = 0,
  });

  @override
  State<LeagueStatsCard> createState() => _LeagueStatsCardState();
}

class _LeagueStatsCardState extends State<LeagueStatsCard> {
  ParentLeagueStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LeagueStatsCard old) {
    super.didUpdateWidget(old);
    if (old.childUid != widget.childUid || old.refreshTick != widget.refreshTick) {
      _load();
    }
  }

  Future<void> _load() async {
    final s = await ParentLinkService.readChildLeagueStats(widget.childUid);
    if (!mounted) return;
    setState(() => _stats = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    if (s == null || !s.hasData) return const SizedBox.shrink();
    const brand = Color(0xFF7C3AED);
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w800, color: brand,
                  )),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 10, color: AppPalette.textSecondary(context),
                  )),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, size: 18, color: brand),
              const SizedBox(width: 8),
              Text('Bilgi Ligi başarıları'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w800, color: brand,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat('${s.attempts}', 'Test'.tr()),
              stat(s.averageScore.toStringAsFixed(1), 'Ort. Puan'.tr()),
              stat(s.bestScore.toStringAsFixed(1), 'En İyi'.tr()),
              stat('${s.streakDays} 🔥', 'Gün Streak'.tr()),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 0a-2) BİLGİ LABİRENTİ RAPORU — oyunun içindeki "Veli Raporu" bölümünün
//       birebir alanları; öğrenci cihazı Firestore'a yazar, burada okunur.
// ─────────────────────────────────────────────────────────────────────────
class LabyrinthReportCard extends StatefulWidget {
  final String childUid;
  final int refreshTick;
  const LabyrinthReportCard({
    super.key,
    required this.childUid,
    this.refreshTick = 0,
  });

  @override
  State<LabyrinthReportCard> createState() => _LabyrinthReportCardState();
}

class _LabyrinthReportCardState extends State<LabyrinthReportCard> {
  ParentLabyrinthReport? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LabyrinthReportCard old) {
    super.didUpdateWidget(old);
    if (old.childUid != widget.childUid ||
        old.refreshTick != widget.refreshTick) {
      _load();
    }
  }

  Future<void> _load() async {
    final r =
        await ParentLinkService.readChildLabyrinthReport(widget.childUid);
    if (!mounted) return;
    setState(() => _report = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    if (r == null || !r.hasData) return const SizedBox.shrink();
    const brand = Color(0xFF00897B);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppPalette.textSecondary(context),
                    )),
              ),
              Text(value,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                  )),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.explore_rounded, size: 18, color: brand),
              const SizedBox(width: 8),
              Text('Bilgi Labirenti raporu'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w800, color: brand,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          row('Tamamlanan ada'.tr(), '${r.islands}'),
          row('Doğruluk oranı'.tr(), '%${r.acc}'),
          row('Gün serisi'.tr(), '${r.dayStreak} ${"gün".tr()}'),
          row('En güçlü ders'.tr(),
              r.bestPct >= 0 ? '${r.best} (%${r.bestPct})' : r.best),
          row('Gelişmesi gereken'.tr(),
              r.worstPct <= 100 ? '${r.worst} (%${r.worstPct})' : r.worst),
          row('Aralıklı tekrarla pekişen'.tr(),
              '${r.consolidated} ${"soru".tr()}'),
          row('Genel hazırlık'.tr(), r.readiness),
          const SizedBox(height: 6),
          Text(
              'Bu rapor öğrencinin oyun içi performansından otomatik oluşturulur.'
                  .tr(),
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppPalette.textSecondary(context),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 0a) YAKLAŞAN ÖDEVLER — son tarihe göre sıralı; teslim durumu rozetli.
// ─────────────────────────────────────────────────────────────────────────
class UpcomingHomeworksCard extends StatefulWidget {
  final String childUid;
  /// Dashboard'daki pull-to-refresh her tetiklendiğinde artan sayaç —
  /// bu widget kendi verisini sadece childUid değişince yeniliyordu, bu
  /// yüzden aşağı çekip yenilemek yaklaşan ödevleri hiç tazelemiyordu.
  final int refreshTick;
  const UpcomingHomeworksCard({
    super.key,
    required this.childUid,
    this.refreshTick = 0,
  });

  @override
  State<UpcomingHomeworksCard> createState() => _UpcomingHomeworksCardState();
}

class _UpcomingHomeworksCardState extends State<UpcomingHomeworksCard> {
  List<ParentUpcomingHomework>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(UpcomingHomeworksCard old) {
    super.didUpdateWidget(old);
    if (old.childUid != widget.childUid) {
      setState(() => _items = null);
      _load();
    } else if (old.refreshTick != widget.refreshTick) {
      _load();
    }
  }

  Future<void> _load() async {
    final list =
        await ParentLinkService.readChildUpcomingHomeworks(widget.childUid);
    if (!mounted) return;
    setState(() => _items = list);
  }

  String _dueLabel(DateTime due) {
    final now = DateTime.now();
    final diff = due.difference(now);
    if (diff.isNegative) {
      final d = now.difference(due);
      if (d.inDays >= 1) return '${d.inDays} ${'gün gecikti'.tr()}';
      if (d.inHours >= 1) return '${d.inHours} ${'saat gecikti'.tr()}';
      return 'Süresi doldu'.tr();
    }
    if (diff.inDays >= 1) return '${diff.inDays} ${'gün kaldı'.tr()}';
    if (diff.inHours >= 1) return '${diff.inHours} ${'saat kaldı'.tr()}';
    return '${diff.inMinutes} ${'dk kaldı'.tr()}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    // Yükleniyor: yer tutucu gösterme — sessizce gizli.
    if (items == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: _cardDecoration(context),
        child: Row(
          children: [
            _sectionHeader(context, '🗓️', 'Yaklaşan ödevler'.tr()),
            const Spacer(),
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final show = items.take(5).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, '🗓️', 'Yaklaşan ödevler'.tr()),
          const SizedBox(height: 10),
          ...show.map((h) => _row(context, h)),
        ],
      ),
    );
  }

  Widget _row(BuildContext c, ParentUpcomingHomework h) {
    final overdue = h.isOverdue && !h.submitted;
    final statusColor = h.submitted
        ? const Color(0xFF10B981)
        : overdue
            ? const Color(0xFFEF4444)
            : const Color(0xFF0EA5E9);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.title.isEmpty ? h.subject : h.title,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(c),
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                    '${h.subject.isEmpty ? h.className : h.subject} · ${_dueLabel(h.dueAt)}',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, color: AppPalette.textSecondary(c),
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              h.submitted
                  ? 'Teslim edildi'.tr()
                  : overdue
                      ? 'Gecikti'.tr()
                      : 'Bekliyor'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 9.5, fontWeight: FontWeight.w800, color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 0b) VELİ HEDEFİ — haftalık odak saati + başarı hedefi, ilerleme çubukları.
//     Hedefler SharedPreferences'ta çocuk uid bazlı saklanır (veli-yerel).
// ─────────────────────────────────────────────────────────────────────────
class ParentGoalCard extends StatefulWidget {
  final String childUid;
  final List<StudentActivityModel> last7Days;
  const ParentGoalCard({
    super.key, required this.childUid, required this.last7Days,
  });

  @override
  State<ParentGoalCard> createState() => _ParentGoalCardState();
}

class _ParentGoalCardState extends State<ParentGoalCard> {
  double? _goalHours;   // haftalık hedef odak saati
  int? _goalSuccess;    // hedef başarı yüzdesi
  bool _loaded = false;

  String get _kHours => 'parent_goal_hours_${widget.childUid}';
  String get _kSuccess => 'parent_goal_success_${widget.childUid}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final h = p.getDouble(_kHours);
      final s = p.getInt(_kSuccess);
      if (mounted) {
        setState(() { _goalHours = h; _goalSuccess = s; _loaded = true; });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save(double hours, int success) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kHours, hours);
      await p.setInt(_kSuccess, success);
    } catch (_) {}
    if (mounted) setState(() { _goalHours = hours; _goalSuccess = success; });
  }

  double get _currentHours {
    final mins = widget.last7Days.fold<int>(0, (s, a) => s + a.focusMinutes);
    return mins / 60.0;
  }

  int get _currentSuccess {
    int c = 0, w = 0;
    for (final a in widget.last7Days) {
      c += a.correctAnswers;
      w += a.wrongAnswers;
    }
    if (c + w == 0) return 0;
    return (c * 100 / (c + w)).round();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final hasGoal = _goalHours != null && _goalSuccess != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionHeader(context, '🎯', 'Haftalık hedef'.tr())),
              TextButton(
                onPressed: _openEditor,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(hasGoal ? 'Düzenle'.tr() : 'Hedef koy'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: const Color(0xFF10B981),
                    )),
              ),
            ],
          ),
          if (!hasGoal) ...[
            const SizedBox(height: 4),
            Text(
              'Çocuğun için haftalık çalışma süresi ve başarı hedefi belirle; ilerlemesini buradan takip et.'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12, height: 1.4,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            _goalBar(context, '⏱️', 'Odak süresi'.tr(),
                _currentHours, _goalHours!,
                '${_currentHours.toStringAsFixed(1)}/${_goalHours!.toStringAsFixed(0)} sa'),
            const SizedBox(height: 12),
            _goalBar(context, '📊', 'Başarı'.tr(),
                _currentSuccess.toDouble(), _goalSuccess!.toDouble(),
                '%$_currentSuccess/%$_goalSuccess'),
          ],
        ],
      ),
    );
  }

  Widget _goalBar(BuildContext c, String emoji, String label,
      double current, double goal, String valueText) {
    final ratio = goal <= 0 ? 0.0 : (current / goal).clamp(0.0, 1.0);
    final reached = current >= goal;
    final color = reached ? const Color(0xFF10B981) : const Color(0xFF0EA5E9);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(c),
                  )),
            ),
            if (reached)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.check_circle_rounded,
                    size: 14, color: Color(0xFF10B981)),
              ),
            Text(valueText,
                style: GoogleFonts.poppins(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: color,
                )),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: AppPalette.border(c),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor() async {
    double hours = _goalHours ?? 5;
    int success = _goalSuccess ?? 70;
    final result = await showModalBottomSheet<(double, int)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppPalette.border(ctx),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Haftalık hedef belirle'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimary(ctx),
                  )),
              const SizedBox(height: 16),
              Text('${'Odak süresi'.tr()}: ${hours.toStringAsFixed(0)} ${'saat/hafta'.tr()}',
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(ctx),
                  )),
              Slider(
                value: hours, min: 1, max: 40, divisions: 39,
                activeColor: const Color(0xFF10B981),
                label: hours.toStringAsFixed(0),
                onChanged: (v) => setM(() => hours = v),
              ),
              const SizedBox(height: 4),
              Text('${'Başarı hedefi'.tr()}: %${success.toString()}',
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(ctx),
                  )),
              Slider(
                value: success.toDouble(), min: 30, max: 100, divisions: 14,
                activeColor: const Color(0xFF10B981),
                label: '%$success',
                onChanged: (v) => setM(() => success = v.round()),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, (hours, success)),
                  child: Text('Kaydet'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: Colors.white,
                      )),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
    if (result != null) await _save(result.$1, result.$2);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 5b) ZAYIF/GÜÇLÜ DERS + AI HAFTALIK ÇALIŞMA PLANI
//     subjectCorrect/subjectWrong'tan ders başarısı; Gemini ile plan.
// ─────────────────────────────────────────────────────────────────────────
class StudyPlanCard extends StatefulWidget {
  final String childName;
  final List<StudentActivityModel> last7Days;
  const StudyPlanCard({
    super.key, required this.childName, required this.last7Days,
  });

  @override
  State<StudyPlanCard> createState() => _StudyPlanCardState();
}

class _StudyPlanCardState extends State<StudyPlanCard> {
  List<String>? _plan;
  bool _loading = false;

  /// Ders → başarı yüzdesi (yeterli veri olan dersler).
  Map<String, double> _subjectSuccess() {
    final correct = <String, int>{};
    final wrong = <String, int>{};
    for (final a in widget.last7Days) {
      a.subjectCorrect.forEach((k, v) => correct[k] = (correct[k] ?? 0) + v);
      a.subjectWrong.forEach((k, v) => wrong[k] = (wrong[k] ?? 0) + v);
    }
    final out = <String, double>{};
    final keys = {...correct.keys, ...wrong.keys};
    for (final k in keys) {
      final c = correct[k] ?? 0;
      final w = wrong[k] ?? 0;
      final tot = c + w;
      if (tot < 3) continue; // istatistiksel olarak anlamsız
      out[k] = c * 100.0 / tot;
    }
    return out;
  }

  Map<String, int> _subjectMinutes() {
    final out = <String, int>{};
    for (final a in widget.last7Days) {
      a.subjectDurations.forEach((k, v) => out[k] = (out[k] ?? 0) + (v ~/ 60));
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void didUpdateWidget(StudyPlanCard old) {
    super.didUpdateWidget(old);
    if (old.last7Days.length != widget.last7Days.length) _generate();
  }

  Future<void> _generate() async {
    final success = _subjectSuccess();
    if (success.isEmpty) {
      setState(() => _plan = const []);
      return;
    }
    final weak = success.entries.where((e) => e.value < 60).map((e) => e.key).toList()
      ..sort((a, b) => (success[a] ?? 0).compareTo(success[b] ?? 0));
    setState(() => _loading = true);
    try {
      final plan = await GeminiService.generateParentStudyPlan(
        childName: widget.childName,
        subjectMinutes: _subjectMinutes(),
        subjectSuccess: success,
        weakSubjects: weak,
        langCode: LocaleService.global?.localeCode ?? 'tr',
      );
      if (!mounted) return;
      setState(() { _plan = plan; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final success = _subjectSuccess();
    if (success.isEmpty) {
      return _emptyBox('Plan için biraz test verisi gerekiyor.'.tr());
    }
    final weak = success.entries.where((e) => e.value < 60).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final strong = success.entries.where((e) => e.value >= 80).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionHeader(context, '🎯',
                    'Haftalık çalışma planı'.tr()),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18,
                    color: Color(0xFF10B981)),
                onPressed: _loading ? null : _generate,
                tooltip: 'Yenile'.tr(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Zayıf / güçlü ders rozetleri
          if (weak.isNotEmpty) ...[
            _subjectChips(context, 'Geliştirilecek'.tr(),
                const Color(0xFFEF4444), weak),
            const SizedBox(height: 8),
          ],
          if (strong.isNotEmpty) ...[
            _subjectChips(context, 'Güçlü'.tr(),
                const Color(0xFF10B981), strong),
            const SizedBox(height: 10),
          ],
          const Divider(height: 18),
          // AI plan listesi
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            )
          else if (_plan != null && _plan!.isNotEmpty)
            ...List.generate(_plan!.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text('${i + 1}',
                        style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w900,
                          color: const Color(0xFF065F46),
                        )),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_plan![i],
                        style: GoogleFonts.poppins(
                          fontSize: 12.5, height: 1.45,
                          color: AppPalette.textPrimary(context),
                        )),
                  ),
                ],
              ),
            ))
          else
            Text('Plan üretilemedi — tekrar dene.'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12, color: AppPalette.textSecondary(context),
                )),
        ],
      ),
    );
  }

  Widget _subjectChips(BuildContext c, String label, Color color,
      List<MapEntry<String, double>> entries) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(label,
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800, color: color,
              )),
        ),
        Expanded(
          child: Wrap(
            spacing: 6, runSpacing: 4,
            children: entries.take(4).map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: 0.30)),
              ),
              child: Text('${e.key} · %${e.value.round()}',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: color,
                  )),
            )).toList(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 7) EBEVEYN KONTROLÜ — günlük süre limiti + sessiz saatler.
//    Parent-yerel (SharedPreferences) + Firestore'a yazılır. Çocuk app
//    tarafında uygulanması (kullanımı engelleme) ayrı bir adımdır.
// ─────────────────────────────────────────────────────────────────────────
class ParentalControlsCard extends StatefulWidget {
  final String childUid;
  const ParentalControlsCard({super.key, required this.childUid});

  @override
  State<ParentalControlsCard> createState() => _ParentalControlsCardState();
}

class _ParentalControlsCardState extends State<ParentalControlsCard> {
  bool _timeLimit = false;
  int _dailyMins = 120;
  bool _quiet = false;
  int _quietStart = 21 * 60; // 21:00
  int _quietEnd = 7 * 60;    // 07:00
  bool _loaded = false;

  String _k(String s) => 'pc_${s}_${widget.childUid}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _timeLimit = p.getBool(_k('time_enabled')) ?? false;
      _dailyMins = p.getInt(_k('daily')) ?? 120;
      _quiet = p.getBool(_k('quiet_enabled')) ?? false;
      _quietStart = p.getInt(_k('quiet_start')) ?? 21 * 60;
      _quietEnd = p.getInt(_k('quiet_end')) ?? 7 * 60;
    } catch (_) {}
    // Yerel cache SADECE bu cihazda daha önce kaydedilmişse doğru — başka
    // bir cihazdan (veya başka ebeveyn olarak) girildiyse Firestore'daki
    // KENDİ kayıtlı ayarım asıl kaynak. Onu çekip cache'in üzerine yaz.
    try {
      final cloud = await ParentLinkService.readParentalControls(widget.childUid);
      if (cloud != null) {
        _timeLimit = (cloud['timeLimitEnabled'] ?? _timeLimit) == true;
        _dailyMins = (cloud['dailyLimitMinutes'] ?? _dailyMins) as int;
        _quiet = (cloud['quietHoursEnabled'] ?? _quiet) == true;
        _quietStart = (cloud['quietStartMinutes'] ?? _quietStart) as int;
        _quietEnd = (cloud['quietEndMinutes'] ?? _quietEnd) as int;
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_k('time_enabled'), _timeLimit);
      await p.setInt(_k('daily'), _dailyMins);
      await p.setBool(_k('quiet_enabled'), _quiet);
      await p.setInt(_k('quiet_start'), _quietStart);
      await p.setInt(_k('quiet_end'), _quietEnd);
    } catch (_) {}
    // Çocuk app'in okuyabilmesi için Firestore'a da yaz (best-effort).
    ParentLinkService.saveParentalControls(
      widget.childUid,
      timeLimitEnabled: _timeLimit,
      dailyLimitMinutes: _dailyMins,
      quietHoursEnabled: _quiet,
      quietStartMinutes: _quietStart,
      quietEndMinutes: _quietEnd,
    );
  }

  String _fmt(int mins) {
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime(bool isStart) async {
    final cur = isStart ? _quietStart : _quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (picked == null) return;
    setState(() {
      final v = picked.hour * 60 + picked.minute;
      if (isStart) { _quietStart = v; } else { _quietEnd = v; }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, '🛡️', 'Ebeveyn kontrolü'.tr()),
          const SizedBox(height: 8),
          // Günlük süre limiti
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeThumbColor: const Color(0xFF10B981),
            value: _timeLimit,
            onChanged: (v) { setState(() => _timeLimit = v); _save(); },
            title: Text('Günlük süre limiti'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                )),
            subtitle: Text(
                _timeLimit
                    ? '${'Günlük'.tr()}: ${_dailyMins ~/ 60} sa ${_dailyMins % 60} dk'
                    : 'Kapalı'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 11, color: AppPalette.textSecondary(context),
                )),
          ),
          if (_timeLimit)
            Slider(
              value: _dailyMins.toDouble(), min: 30, max: 240, divisions: 14,
              activeColor: const Color(0xFF10B981),
              label: '${_dailyMins ~/ 60}sa ${_dailyMins % 60}dk',
              onChanged: (v) => setState(() => _dailyMins = v.round()),
              onChangeEnd: (_) => _save(),
            ),
          const Divider(height: 14),
          // Sessiz saatler
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeThumbColor: const Color(0xFF10B981),
            value: _quiet,
            onChanged: (v) { setState(() => _quiet = v); _save(); },
            title: Text('Sessiz saatler'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                )),
            subtitle: Text(
                _quiet
                    ? '${_fmt(_quietStart)} – ${_fmt(_quietEnd)} ${'arası kapalı'.tr()}'
                    : 'Kapalı'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 11, color: AppPalette.textSecondary(context),
                )),
          ),
          if (_quiet)
            Row(
              children: [
                Expanded(
                  child: _timeBtn(context, 'Başlangıç'.tr(),
                      _fmt(_quietStart), () => _pickTime(true)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _timeBtn(context, 'Bitiş'.tr(),
                      _fmt(_quietEnd), () => _pickTime(false)),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 13,
                  color: AppPalette.textSecondary(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Limitler çocuğun cihazında uygulanır; etkin olması için çocuğun uygulamayı güncellemesi gerekir.'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 10, height: 1.4,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeBtn(BuildContext c, String label, String value, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: AppPalette.bg(c),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppPalette.border(c)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 10, color: AppPalette.textSecondary(c),
                  )),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(c),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 6) YATAY ÖZET LİSTESİ — son AI özetler
// ─────────────────────────────────────────────────────────────────────────
class HorizontalSummariesScroll extends StatelessWidget {
  /// Her item: {topic, subject, createdAt, length?}
  final List<Map<String, dynamic>> summaries;
  const HorizontalSummariesScroll({super.key, required this.summaries});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, '📚',
              'Son hazırlanan konu özetleri'.tr()),
          const SizedBox(height: 10),
          if (summaries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Henüz özet oluşturmadı.'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12, color: AppPalette.textSecondary(context),
                  )),
            )
          else
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: summaries.length,
                itemBuilder: (ctx, i) {
                  final m = summaries[i];
                  final color = _palette[i % _palette.length];
                  return Container(
                    width: 160,
                    margin: EdgeInsets.only(right: 10, left: i == 0 ? 0 : 0),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withValues(alpha: 0.28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['subject'] ?? ''}',
                            style: GoogleFonts.poppins(
                              fontSize: 10.5, fontWeight: FontWeight.w800,
                              color: color, letterSpacing: 0.6,
                            )),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text('${m['topic'] ?? ''}',
                              style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w700,
                                color: AppPalette.textPrimary(context),
                                height: 1.3,
                              ),
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                        ),
                        Text(_formatRelativeTime(m['createdAt']),
                            style: GoogleFonts.poppins(
                              fontSize: 10, color: AppPalette.textSecondary(context),
                            )),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _formatRelativeTime(dynamic ts) {
  if (ts == null) return '';
  DateTime? when;
  if (ts is Timestamp) when = ts.toDate();
  if (ts is int) when = DateTime.fromMillisecondsSinceEpoch(ts);
  if (when == null) return '';
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 60) return '${diff.inMinutes}dk';
  if (diff.inHours < 24) return '${diff.inHours}s';
  return '${diff.inDays}g';
}

// ─── Yardımcı widget'lar ────────────────────────────────────────────────
BoxDecoration _cardDecoration(BuildContext c) => BoxDecoration(
      color: AppPalette.card(c),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppPalette.border(c)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10, offset: const Offset(0, 3),
        ),
      ],
    );

Widget _sectionHeader(BuildContext c, String emoji, String label) {
  return Row(
    children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 8),
      Text(label,
          style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w800,
            color: AppPalette.textPrimary(c),
            letterSpacing: 0.1,
          )),
    ],
  );
}

Widget _legendDot(Color color, String label) {
  return Builder(builder: (c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label,
          style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: AppPalette.textSecondary(c),
          )),
    ],
  ));
}

Widget _emptyBox(String label) {
  return Builder(builder: (c) => Container(
    padding: const EdgeInsets.fromLTRB(14, 28, 14, 28),
    decoration: _cardDecoration(c),
    alignment: Alignment.center,
    child: Text(label,
        style: GoogleFonts.poppins(
          fontSize: 12, color: AppPalette.textSecondary(c),
        )),
  ));
}
