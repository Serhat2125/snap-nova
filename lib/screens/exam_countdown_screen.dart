// ═══════════════════════════════════════════════════════════════════════════════
//  ExamCountdownScreen — Resmi sınavlara canlı geri sayım ekranı
//  • Kullanıcının ülkesini SharedPreferences'tan okur (`mini_test_country`).
//  • `exam_dates.dart` sabitinden ülkeye özel listeyi alır.
//  • Saniyede bir Timer ile UI'ı yeniler.
//  • Her kart: ad+yıl, tarih, D/H/M/S sayacı, renk değişen ilerleme çubuğu.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/exam_dates.dart';
import '../theme/app_theme.dart';
import '../main.dart' show localeService;

class ExamCountdownScreen extends StatefulWidget {
  const ExamCountdownScreen({super.key});

  @override
  State<ExamCountdownScreen> createState() => _ExamCountdownScreenState();
}

class _ExamCountdownScreenState extends State<ExamCountdownScreen> {
  Timer? _ticker;
  String _country = 'tr';
  bool _loadingCountry = true;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCountry();
    _ticker = Timer.periodic(Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadCountry() async {
    String code = 'tr';
    try {
      final prefs = await SharedPreferences.getInstance();
      final fromProfile = prefs.getString('mini_test_country');
      final fromGeo = prefs.getString('detected_country_v1') ??
          prefs.getString('ip_geo_country_v1');
      code = (fromProfile?.isNotEmpty == true)
          ? fromProfile!
          : (fromGeo?.isNotEmpty == true ? fromGeo! : 'tr');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _country = code.toLowerCase();
      _loadingCountry = false;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exams = _loadingCountry
        ? const <OfficialExam>[]
        : upcomingExamsForCountry(_country);

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined,
                color: Color(0xFFFF6A00), size: 22),
            SizedBox(width: 8),
            Text(
              localeService.tr('exam_countdowns'),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: _loadingCountry
          ? Center(child: CircularProgressIndicator())
          : exams.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  itemCount: exams.length,
                  separatorBuilder: (_, __) => SizedBox(height: 12),
                  itemBuilder: (_, i) =>
                      _ExamCountdownCard(exam: exams[i], now: _now),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded,
                size: 56, color: Colors.black38),
            SizedBox(height: 12),
            Text(
              localeService.tr('exam_countdowns_empty'),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tek bir sınav kartı ──────────────────────────────────────────────────────
class _ExamCountdownCard extends StatelessWidget {
  final OfficialExam exam;
  final DateTime now;
  const _ExamCountdownCard({required this.exam, required this.now});

  Duration get _remaining => exam.date.difference(now);

  Color get _progressColor {
    final days = _remaining.inDays;
    if (days < 30) return Color(0xFFEF4444); // kırmızı
    if (days < 100) return Color(0xFFF59E0B); // turuncu
    return Color(0xFF10B981); // yeşil
  }

  /// 0..1 arası — 365 günlük referans üzerinden ne kadar kapanmış olduğu.
  /// Sınav uzaktaysa çubuk az dolu, yaklaştıkça doluyor.
  double get _progressRatio {
    const horizon = 365;
    final daysLeft = _remaining.inDays;
    if (daysLeft <= 0) return 1.0;
    if (daysLeft >= horizon) return 0.04;
    return 1.0 - (daysLeft / horizon);
  }

  @override
  Widget build(BuildContext context) {
    final r = _remaining;
    final days = r.inDays;
    final hours = r.inHours.remainder(24);
    final minutes = r.inMinutes.remainder(60);
    final seconds = r.inSeconds.remainder(60);
    final color = _progressColor;

    return Container(
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.border(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst satır: sol = ad+yıl, sağ = tarih
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.fullTitle,
                      style: GoogleFonts.poppins(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                        height: 1.15,
                      ),
                    ),
                    if (exam.subtitle != null && exam.subtitle!.isNotEmpty) ...[
                      SizedBox(height: 3),
                      Text(
                        exam.subtitle!,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: AppPalette.textSecondary(context),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: exam.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: exam.accent.withValues(alpha: 0.4), width: 1),
                ),
                child: Text(
                  _formatDate(exam.date),
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: exam.accent,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),

          // Sayaç: D / H / M / S
          Row(
            children: [
              Expanded(
                  child:
                      _CountdownSlot(value: days, label: _label('days'))),
              SizedBox(width: 8),
              Expanded(
                  child:
                      _CountdownSlot(value: hours, label: _label('hours'))),
              SizedBox(width: 8),
              Expanded(
                  child: _CountdownSlot(
                      value: minutes, label: _label('minutes'))),
              SizedBox(width: 8),
              Expanded(
                  child: _CountdownSlot(
                      value: seconds, label: _label('seconds'))),
            ],
          ),

          SizedBox(height: 14),

          // İlerleme çubuğu — yaklaştıkça renk değişiyor.
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: Color(0xFFEEF1F4)),
                  FractionallySizedBox(
                    widthFactor: _progressRatio.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            color.withValues(alpha: 0.85),
                            color,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$days ${_label('days_left')}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                _formatTime(exam.date),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _label(String key) {
    switch (key) {
      case 'days':
        return localeService.tr('cd_days');
      case 'hours':
        return localeService.tr('cd_hours');
      case 'minutes':
        return localeService.tr('cd_minutes');
      case 'seconds':
        return localeService.tr('cd_seconds');
      case 'days_left':
        return localeService.tr('cd_days_left');
    }
    return key;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _formatDate(DateTime d) {
    return '${_two(d.day)}.${_two(d.month)}.${d.year}';
  }

  static String _formatTime(DateTime d) {
    return '${_two(d.hour)}:${_two(d.minute)}';
  }
}

class _CountdownSlot extends StatelessWidget {
  final int value;
  final String label;
  const _CountdownSlot({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final shown = value < 0 ? 0 : value;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shown.toString().padLeft(2, '0'),
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppPalette.textPrimary(context),
              height: 1,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: AppPalette.textSecondary(context),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
