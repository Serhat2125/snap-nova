// ═══════════════════════════════════════════════════════════════════════════
//  TeacherStudentReportScreen — Tek öğrencinin karnesi (drill-down).
//
//  Sınıf detayındaki öğrenci satırına tıklanınca açılır. Yalnızca ÖDEV
//  verisinden (submissions) türetilir — KVKK-dostu: öğretmen öğrencinin tüm
//  uygulama davranışını değil, sadece kendi verdiği ödevlerdeki performansı
//  görür.
//
//  Bölümler:
//    • Özet: genel başarı %, ortalama çözüm süresi, tamamlama oranı
//    • Başarı trendi (zamana yayılan ödev skorları)
//    • Konu bazlı başarı (güçlü / zayıf konular)
//    • Ödev geçmişi (her ödev: skor, süre, durum, tarih)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'teacher_submission_detail_screen.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherStudentReportScreen extends StatefulWidget {
  final String classId;
  final String studentUid;
  final String studentName;
  final String studentAvatar;
  const TeacherStudentReportScreen({
    super.key,
    required this.classId,
    required this.studentUid,
    required this.studentName,
    this.studentAvatar = '👤',
  });

  @override
  State<TeacherStudentReportScreen> createState() =>
      _TeacherStudentReportScreenState();
}

class _TeacherStudentReportScreenState
    extends State<TeacherStudentReportScreen> {
  late Future<List<StudentReportEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = HomeworkService.studentReport(widget.classId, widget.studentUid);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Öğrenci Karnesi'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ),
      body: SafeArea(
        child: FutureBuilder<List<StudentReportEntry>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snap.data ?? const <StudentReportEntry>[];
            return _buildBody(context, entries);
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<StudentReportEntry> entries) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);

    final done = entries.where((e) => e.isDone).toList();
    final scores = done
        .map((e) => e.submission?.scorePercent)
        .whereType<double>()
        .toList();
    final avgScore = scores.isEmpty
        ? null
        : scores.reduce((a, b) => a + b) / scores.length;
    final durations = done
        .map((e) => e.submission?.solveDuration)
        .whereType<Duration>()
        .toList();
    final avgDuration = durations.isEmpty
        ? null
        : Duration(
            seconds: durations
                    .map((d) => d.inSeconds)
                    .reduce((a, b) => a + b) ~/
                durations.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        // ── Öğrenci başlığı ───────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kBrand.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: Text(widget.studentAvatar,
                  style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.studentName,
                  style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w900, color: ink,
                  )),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Özet kartları ─────────────────────────────────────────────
        Row(
          children: [
            _statCard(context, '🎯', 'Genel Başarı'.tr(),
                avgScore == null ? '—' : '%${avgScore.toStringAsFixed(0)}',
                _scoreColor(avgScore)),
            const SizedBox(width: 10),
            _statCard(context, '⏱️', 'Ort. Süre'.tr(),
                avgDuration == null ? '—' : _fmtDuration(avgDuration),
                const Color(0xFF06B6D4)),
            const SizedBox(width: 10),
            _statCard(context, '✅', 'Tamamlama'.tr(),
                '${done.length}/${entries.length}',
                const Color(0xFF10B981)),
          ],
        ),
        const SizedBox(height: 22),

        if (entries.isEmpty)
          _emptyState(context, muted)
        else ...[
          // ── Başarı trendi ───────────────────────────────────────────
          _sectionLabel(context, 'BAŞARI TRENDİ'.tr()),
          const SizedBox(height: 10),
          _TrendChart(
            // eski → yeni: trend soldan sağa zaman akışı
            entries: done.reversed.toList(),
          ),
          const SizedBox(height: 22),

          // ── Konu bazlı başarı ───────────────────────────────────────
          _sectionLabel(context, 'KONU BAZLI BAŞARI'.tr()),
          const SizedBox(height: 10),
          ..._buildTopicBars(context, done),
          const SizedBox(height: 22),

          // ── Ödev geçmişi ────────────────────────────────────────────
          _sectionLabel(context, 'ÖDEV GEÇMİŞİ'.tr()),
          const SizedBox(height: 10),
          ...entries.map((e) => _historyRow(context, e)),
        ],
      ],
    );
  }

  // ── Konu bazlı başarı barları ─────────────────────────────────────────
  List<Widget> _buildTopicBars(
      BuildContext context, List<StudentReportEntry> done) {
    if (done.isEmpty) {
      return [
        Text('Henüz teslim edilen ödev yok.'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 12.5, color: AppPalette.textSecondary(context),
            )),
      ];
    }
    final Map<String, List<double>> byTopic = {};
    for (final e in done) {
      final key = '${e.homework.subject} · ${e.homework.topic}';
      final s = e.submission?.scorePercent;
      if (s != null) byTopic.putIfAbsent(key, () => []).add(s);
    }
    final rows = byTopic.entries
        .map((m) => (
              label: m.key,
              avg: m.value.reduce((a, b) => a + b) / m.value.length,
            ))
        .toList()
      ..sort((a, b) => a.avg.compareTo(b.avg)); // zayıf → güçlü

    return rows.map((r) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.label,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5, fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary(context),
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text('%${r.avg.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: _scoreColor(r.avg),
                    )),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (r.avg / 100).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: AppPalette.border(context),
                valueColor: AlwaysStoppedAnimation(_scoreColor(r.avg)),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _historyRow(BuildContext context, StudentReportEntry e) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final sub = e.submission;
    final (statusColor, statusLabel) = _statusOf(sub?.status);
    final hw = e.homework;
    final tappable = sub != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tappable
            ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TeacherSubmissionDetailScreen(
                    classId: widget.classId,
                    homework: hw,
                    submission: sub,
                    studentName: widget.studentName,
                  ),
                ))
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(hw.title,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(statusLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w800,
                          color: statusColor,
                        )),
                  ),
                  if (tappable) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: muted),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text('${hw.subject} · ${hw.topic}',
                        style: GoogleFonts.poppins(fontSize: 11, color: muted),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (sub?.solveDuration != null) ...[
                    Icon(Icons.timer_outlined, size: 12, color: muted),
                    const SizedBox(width: 2),
                    Text(_fmtDuration(sub!.solveDuration!),
                        style:
                            GoogleFonts.poppins(fontSize: 10.5, color: muted)),
                    const SizedBox(width: 8),
                  ],
                  if (sub?.scorePercent != null)
                    Text('%${sub!.scorePercent!.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5, fontWeight: FontWeight.w800,
                          color: _scoreColor(sub.scorePercent!),
                        )),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${'Verildi'.tr()}: ${_fmtDate(hw.assignedAt)}  ·  '
                '${'Bitiş'.tr()}: ${_fmtDate(hw.dueAt)}',
                style: GoogleFonts.poppins(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  // ── Yardımcılar ───────────────────────────────────────────────────────
  Widget _statCard(BuildContext c, String emoji, String label, String value,
      Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppPalette.card(c),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(c)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(value,
                style: GoogleFonts.poppins(
                  fontSize: 17, fontWeight: FontWeight.w900, color: color,
                )),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondary(c),
                )),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext c, String t) => Text(t,
      style: GoogleFonts.poppins(
        fontSize: 11, fontWeight: FontWeight.w800,
        color: AppPalette.textSecondary(c), letterSpacing: 0.8,
      ));

  Widget _emptyState(BuildContext c, Color muted) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Text('📋', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text('Bu öğrenciye henüz ödev atanmadı.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13, color: muted, height: 1.4,
                )),
          ],
        ),
      );

  Color _scoreColor(double? score) {
    if (score == null) return const Color(0xFF94A3B8);
    if (score >= 70) return const Color(0xFF10B981);
    if (score >= 40) return const Color(0xFFFBBF24);
    return const Color(0xFFEF4444);
  }

  (Color, String) _statusOf(String? status) {
    switch (status) {
      case 'submitted': return (const Color(0xFF10B981), 'Teslim'.tr());
      case 'late': return (const Color(0xFFFB923C), 'Geç'.tr());
      case 'in_progress': return (const Color(0xFF06B6D4), 'Çözüyor'.tr());
      case 'pending': return (const Color(0xFF94A3B8), 'Bekliyor'.tr());
      default: return (const Color(0xFF94A3B8), 'Atanmadı'.tr());
    }
  }

  String _fmtDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}sn';
    if (d.inHours < 1) return '${d.inMinutes}dk';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}s' : '${h}s ${m}dk';
  }
}

// ── Basit başarı trend grafiği (bağımlılıksız bar chart) ───────────────────
class _TrendChart extends StatelessWidget {
  /// Eski → yeni sıralı, teslim edilmiş ödevler.
  final List<StudentReportEntry> entries;
  const _TrendChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final points = entries
        .map((e) => e.submission?.scorePercent)
        .whereType<double>()
        .toList();
    if (points.length < 2) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Text(
          'Trend için en az 2 teslim edilmiş ödev gerekir.'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 12.5, color: AppPalette.textSecondary(context),
          ),
        ),
      );
    }
    return Container(
      height: 130,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((p) {
          final color = p >= 70
              ? const Color(0xFF10B981)
              : p >= 40
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFFEF4444);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('%${p.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                        fontSize: 8.5, fontWeight: FontWeight.w700,
                        color: AppPalette.textSecondary(context),
                      )),
                  const SizedBox(height: 3),
                  Container(
                    height: (p / 100 * 80).clamp(4.0, 80.0),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
