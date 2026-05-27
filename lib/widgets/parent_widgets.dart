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

import '../models/education_models.dart';
import '../services/gemini_service.dart';
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
