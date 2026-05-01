import '../services/runtime_translator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show localeService;
import '../services/analytics.dart';
import '../services/usage_quota.dart';
import '../features/offline/domain/offline_subject_pack.dart';
import '../features/offline/providers/offline_pack_provider.dart';
import '../services/curriculum_catalog.dart';
import '../services/education_profile.dart';
import '../services/gemini_service.dart';
import '../widgets/latex_text.dart';
import '../widgets/qualsar_numeric_loader.dart';
import 'education_setup_screen.dart';
import 'test_page.dart';
import 'green_colony_screen.dart';
import 'history_screen.dart';
import 'qualsar_arena_screen.dart';
import '../widgets/study_toolbar.dart';
import 'qualsar_mars_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Kütüphane — Ders bazlı kart sistemi
//  • Her + kartı bir ders. İlk basışta ders adı + ilk konu istenir.
//  • Kart dolunca bir daha basılınca SADECE yeni konu istenir, o derse eklenir.
//  • Başka ders için başka + kartına basılır.
//  • Özet AI (Gemini) tarafından öğrencinin sınav seviyesine göre üretilir.
// ═══════════════════════════════════════════════════════════════════════════════

// Geliştirme sürecinde sınırsız — yayına alırken tekrar 15 yap.
const _monthlyLimit = 100000;
const _blue = Color(0xFF2563EB);
const _orange = Color(0xFFFF6A00);
const _indigo = Color(0xFF6366F1);
const _cardSlots = 3;

// ═══════════════════════════════════════════════════════════════════════════
//  Activity store — detaylı kayıt (tarih + saat + ders + konu + tip)
// ═══════════════════════════════════════════════════════════════════════════
class _ActivityEntry {
  final DateTime when;
  final String subject;
  final String topic;
  final String type; // 'özet' | 'soru'
  _ActivityEntry({
    required this.when,
    required this.subject,
    required this.topic,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'when': when.toIso8601String(),
        'subject': subject,
        'topic': topic,
        'type': type,
      };

  factory _ActivityEntry.fromJson(Map<String, dynamic> j) => _ActivityEntry(
        when: DateTime.parse(j['when'] as String),
        subject: j['subject'] as String,
        topic: j['topic'] as String,
        type: (j['type'] as String?) ?? 'özet',
      );
}

class _ActivityStore {
  static const _key = 'library_activity_log_v2';

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<_ActivityEntry>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.map((s) {
      try {
        return _ActivityEntry.fromJson(
            jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<_ActivityEntry>().toList();
  }

  // Mevcut hafta için günlere göre gruplayarak döner
  static Future<Map<String, List<_ActivityEntry>>> readWeekGrouped() async {
    final all = await readAll();
    final out = <String, List<_ActivityEntry>>{};
    for (final e in all) {
      final k = dayKey(e.when);
      out.putIfAbsent(k, () => []).add(e);
    }
    for (final v in out.values) {
      v.sort((a, b) => b.when.compareTo(a.when));
    }
    return out;
  }

  static Future<void> log({
    required String subject,
    required String topic,
    required String type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    final entry = _ActivityEntry(
      when: DateTime.now(),
      subject: subject,
      topic: topic,
      type: type,
    );
    list.add(jsonEncode(entry.toJson()));
    // En fazla 200 son kayıt sakla
    if (list.length > 200) list.removeRange(0, list.length - 200);
    await prefs.setStringList(_key, list);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Haftalık takvim widget'ı (Pzt-Paz, bugün indigo, aktivite ✓)
// ═══════════════════════════════════════════════════════════════════════════
class _WeeklyCalendar extends StatefulWidget {
  const _WeeklyCalendar();
  @override
  State<_WeeklyCalendar> createState() => _WeeklyCalendarState();
}

class _WeeklyCalendarState extends State<_WeeklyCalendar> {
  Map<String, List<_ActivityEntry>> _grouped = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await _ActivityStore.readWeekGrouped();
    if (!mounted) return;
    setState(() => _grouped = g);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final today = DateTime(now.year, now.month, now.day);
    final labels = [
      localeService.tr('day_mon_short'),
      localeService.tr('day_tue_short'),
      localeService.tr('day_wed_short'),
      localeService.tr('day_thu_short'),
      localeService.tr('day_fri_short'),
      localeService.tr('day_sat_short'),
      localeService.tr('day_sun_short'),
    ];

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final day = monday.add(Duration(days: i));
          final isToday = day.year == today.year &&
              day.month == today.month &&
              day.day == today.day;
          final hasActivity =
              (_grouped[_ActivityStore.dayKey(day)] ?? const []).isNotEmpty;
          return _DayCell(
            label: labels[i],
            day: day.day,
            isToday: isToday,
            hasActivity: hasActivity,
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Çalışma Takvimim — haftalık takvim + günlük detay listeleri
// ═══════════════════════════════════════════════════════════════════════════
class StudyCalendarPage extends StatefulWidget {
  const StudyCalendarPage({super.key});
  @override
  State<StudyCalendarPage> createState() => _StudyCalendarPageState();
}

class _StudyCalendarPageState extends State<StudyCalendarPage> {
  Map<String, List<_ActivityEntry>> _grouped = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await _ActivityStore.readWeekGrouped();
    if (!mounted) return;
    setState(() => _grouped = g);
  }

  /// Aktivite olan tamamlanmış geçmiş haftaların pazartesi günleri,
  /// yeniden yeniye sıralı.
  List<DateTime> _completedPastWeekMondays() {
    final mondays = <DateTime>{};
    for (final entries in _grouped.values) {
      for (final e in entries) {
        final w = e.when;
        final m = DateTime(w.year, w.month, w.day)
            .subtract(Duration(days: w.weekday - 1));
        mondays.add(m);
      }
    }
    final now = DateTime.now();
    final thisMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return mondays
        .where((m) => m.isBefore(thisMonday))
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  static const _monthShort = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  String _weekRangeLabel(DateTime monday) {
    final sunday = monday.add(const Duration(days: 6));
    if (monday.month == sunday.month) {
      return '${monday.day}-${sunday.day} ${_monthShort[monday.month - 1]}';
    }
    return '${monday.day} ${_monthShort[monday.month - 1]} - '
        '${sunday.day} ${_monthShort[sunday.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final dayNames = [
      localeService.tr('day_mon_full'),
      localeService.tr('day_tue_full'),
      localeService.tr('day_wed_full'),
      localeService.tr('day_thu_full'),
      localeService.tr('day_fri_full'),
      localeService.tr('day_sat_full'),
      localeService.tr('day_sun_full'),
    ];
    final pastMondays = _completedPastWeekMondays();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          localeService.tr('my_study_calendar'),
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Center(
            child: Text(
              'Haftalık Performansın'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Takvim çerçevesi — bu haftanın 7 günü + sağ tarafa tamamlanmış
          // geçmiş haftaların özet sekmeleri (en yeni en başta).
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
              children: [
                for (var i = 0; i < 7; i++)
                  _buildDayFrame(
                      monday.add(Duration(days: i)), dayNames[i]),
                for (final m in pastMondays)
                  _buildPastWeekCell(m),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPastWeekCell(DateTime monday) {
    final label = _weekRangeLabel(monday);
    int total = 0;
    for (var i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      total += (_grouped[_ActivityStore.dayKey(d)] ?? const []).length;
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _PastWeekPage(
            monday: monday,
            entriesByDay: _grouped,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _indigo.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _indigo.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _indigo.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Geçen Hafta'.tr(),
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: _indigo.withValues(alpha: 0.85),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: _indigo,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 22,
                        color: _indigo,
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          total > 0
                              ? '$total ${'aktivite'.tr()}'
                              : '—',
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Aç'.tr(),
                      maxLines: 1,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: _indigo,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: _indigo,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayFrame(DateTime day, String dayName) {
    final entries = _grouped[_ActivityStore.dayKey(day)] ?? const [];
    final dateText =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final isToday = day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _DayDetailPage(
            day: day,
            dayName: dayName,
            entries: entries,
          ),
        ),
      ),
      child: _buildDayFrameInner(
        day, dayName, dateText, entries, isToday),
    );
  }

  Widget _buildDayFrameInner(DateTime day, String dayName,
      String dateText, List<_ActivityEntry> entries, bool isToday) {
    // Son aktivite saati; yoksa bugün için "şimdi", değilse "—"
    final now = DateTime.now();
    String timeText;
    if (entries.isNotEmpty) {
      final last = entries.first.when;
      timeText =
          '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}';
    } else if (isToday) {
      timeText =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    } else {
      timeText = '—';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday
              ? _indigo
              : const Color(0xFFE5E7EB),
          width: isToday ? 1.6 : 1.0,
        ),
        boxShadow: isToday
            ? [
                BoxShadow(
                  color: _indigo.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık bandı: gün, saat, tarih
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _indigo.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 10, color: Colors.black),
                      const SizedBox(width: 3),
                      Text(
                        timeText,
                        maxLines: 1,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.calendar_today_rounded,
                          size: 9, color: Colors.black),
                      const SizedBox(width: 3),
                      Text(
                        dateText,
                        maxLines: 1,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Aktivite listesi (kompakt)
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        localeService.tr('no_activity_today'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: entries
                          .map((e) => _compactActivityRow(e))
                          .toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _compactActivityRow(_ActivityEntry e) {
    final isQ = e.type == 'soru';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isQ ? Icons.quiz_rounded : Icons.menu_book_rounded,
            size: 10,
            color: isQ ? _orange : _blue,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1.15,
                  ),
                ),
                Text(
                  e.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 8.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// ═════════════════════════════════════════════════════════════════════════════
//  _PastWeekPage — tamamlanmış geçmiş bir haftanın 7 günlük detay sayfası.
//  Pazartesi..Pazar grid'i; her gün hücresine basınca o günün aktivite
//  listesi (_DayDetailPage) açılır.
// ═════════════════════════════════════════════════════════════════════════════
class _PastWeekPage extends StatelessWidget {
  final DateTime monday;
  final Map<String, List<_ActivityEntry>> entriesByDay;
  const _PastWeekPage({
    required this.monday,
    required this.entriesByDay,
  });

  static const _monthShort = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  String _weekRangeLabel() {
    final sunday = monday.add(const Duration(days: 6));
    if (monday.month == sunday.month) {
      return '${monday.day}-${sunday.day} ${_monthShort[monday.month - 1]}';
    }
    return '${monday.day} ${_monthShort[monday.month - 1]} - '
        '${sunday.day} ${_monthShort[sunday.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final dayNames = [
      localeService.tr('day_mon_full'),
      localeService.tr('day_tue_full'),
      localeService.tr('day_wed_full'),
      localeService.tr('day_thu_full'),
      localeService.tr('day_fri_full'),
      localeService.tr('day_sat_full'),
      localeService.tr('day_sun_full'),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          _weekRangeLabel(),
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
              children: [
                for (var i = 0; i < 7; i++)
                  _PastWeekDayCell(
                    day: monday.add(Duration(days: i)),
                    dayName: dayNames[i],
                    entries: entriesByDay[
                            _ActivityStore.dayKey(monday.add(Duration(days: i)))] ??
                        const [],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastWeekDayCell extends StatelessWidget {
  final DateTime day;
  final String dayName;
  final List<_ActivityEntry> entries;
  const _PastWeekDayCell({
    required this.day,
    required this.dayName,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final dateText =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _DayDetailPage(
            day: day,
            dayName: dayName,
            entries: entries,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: _indigo.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 9, color: Colors.black),
                        const SizedBox(width: 3),
                        Text(
                          dateText,
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entries.isEmpty
                            ? Icons.remove_circle_outline_rounded
                            : Icons.check_circle_rounded,
                        size: 22,
                        color: entries.isEmpty
                            ? Colors.black26
                            : const Color(0xFF10B981),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          entries.isEmpty
                              ? '—'
                              : '${entries.length} ${'aktivite'.tr()}',
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  _DayDetailPage — bir güne tıklandığında açılan tam sayfa.
//  Sağ üstte renkli "Renk Seç" pill; başlık çerçevesi + dersler çerçevesi
//  ayrı ayrı renklendirilebilir. Renkler kalıcı (SharedPreferences).
// ═════════════════════════════════════════════════════════════════════════════
class _DayDetailPage extends StatefulWidget {
  final DateTime day;
  final String dayName;
  final List<_ActivityEntry> entries;
  const _DayDetailPage({
    required this.day,
    required this.dayName,
    required this.entries,
  });

  @override
  State<_DayDetailPage> createState() => _DayDetailPageState();
}

class _DayDetailPageState extends State<_DayDetailPage> {
  bool _showColorPicker = false;
  String _colorTarget = 'header'; // 'header' | 'subjects'
  Color? _headerBg;
  Color? _subjectsBg;
  Color? _pageBg;

  static const _palette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  String get _dayKey =>
      '${widget.day.year}-${widget.day.month.toString().padLeft(2, '0')}-${widget.day.day.toString().padLeft(2, '0')}';
  String get _headerKey => 'day_header_color_$_dayKey';
  String get _subjectsKey => 'day_subjects_color_$_dayKey';
  String get _pageKey => 'day_page_color_$_dayKey';

  @override
  void initState() {
    super.initState();
    _loadColors();
  }

  Future<void> _loadColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final h = prefs.getInt(_headerKey);
      final s = prefs.getInt(_subjectsKey);
      final p = prefs.getInt(_pageKey);
      if (!mounted) return;
      setState(() {
        if (h != null) _headerBg = Color(h);
        if (s != null) _subjectsBg = Color(s);
        if (p != null) _pageBg = Color(p);
      });
    } catch (_) {}
  }

  Future<void> _saveColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Future<void> set(String k, Color? c) async {
        if (c == null) {
          await prefs.remove(k);
        } else {
          await prefs.setInt(k, c.toARGB32());
        }
      }

      await set(_headerKey, _headerBg);
      await set(_subjectsKey, _subjectsBg);
      await set(_pageKey, _pageBg);
    } catch (_) {}
  }

  void _applyColor(Color c) {
    setState(() {
      switch (_colorTarget) {
        case 'header':
          _headerBg = c;
          break;
        case 'subjects':
          _subjectsBg = c;
          break;
        case 'bg':
          _pageBg = c;
          break;
      }
    });
    _saveColors();
  }

  void _applyToHeader(Color c) {
    setState(() => _headerBg = c);
    _saveColors();
  }

  void _applyToSubjects(Color c) {
    setState(() => _subjectsBg = c);
    _saveColors();
  }

  bool _isDark(Color c) {
    final l = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    return l < 0.55;
  }

  @override
  Widget build(BuildContext context) {
    final dateText = '${widget.day.day.toString().padLeft(2, '0')}'
        '.${widget.day.month.toString().padLeft(2, '0')}'
        '.${widget.day.year}';
    final pageBg = _pageBg ?? const Color(0xFFF5F6FA);
    final headerBg = _headerBg ?? Colors.white;
    final subjectsBg = _subjectsBg ?? Colors.white;
    final headerInk =
        _isDark(headerBg) ? Colors.white : Colors.black;
    final headerInkMute = _isDark(headerBg)
        ? Colors.white70
        : Colors.black54;
    final subjInk =
        _isDark(subjectsBg) ? Colors.white : Colors.black;
    final subjInkMute = _isDark(subjectsBg)
        ? Colors.white70
        : Colors.black54;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          widget.dayName,
          style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 8, horizontal: 12),
            child: GestureDetector(
              onTap: () => setState(
                  () => _showColorPicker = !_showColorPicker),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFF6A00),
                      Color(0xFFDB2777),
                      Color(0xFF7C3AED),
                      Color(0xFF2563EB),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showColorPicker
                          ? Icons.close_rounded
                          : Icons.palette_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showColorPicker
                          ? 'Kapat'.tr()
                          : 'Renk Seç'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showColorPicker) _buildColorPanel(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Başlık çerçevesi — gün + tarih
                DragTarget<Color>(
                  onAcceptWithDetails: (d) =>
                      _applyToHeader(d.data),
                  builder: (ctx, cand, _) {
                    final hovering = cand.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: headerBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: hovering
                              ? const Color(0xFFFF6A00)
                              : _indigo.withValues(alpha: 0.35),
                          width: hovering ? 2 : 1.4,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              widget.dayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: headerInk,
                                height: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.calendar_today_rounded,
                              size: 14, color: headerInkMute),
                          const SizedBox(width: 6),
                          Text(
                            dateText,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: headerInkMute,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                // Çalışılan dersler çerçevesi
                DragTarget<Color>(
                  onAcceptWithDetails: (d) =>
                      _applyToSubjects(d.data),
                  builder: (ctx, cand, _) {
                    final hovering = cand.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: subjectsBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: hovering
                              ? const Color(0xFFFF6A00)
                              : Colors.black.withValues(alpha: 0.12),
                          width: hovering ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Çalışılan Dersler'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: subjInk,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (widget.entries.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.all(12),
                              child: Center(
                                child: Text(
                                  localeService
                                      .tr('no_activity_today'),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: subjInkMute,
                                  ),
                                ),
                              ),
                            )
                          else
                            for (final e in widget.entries)
                              _entryRow(e, subjInk, subjInkMute),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryRow(_ActivityEntry e, Color ink, Color inkMute) {
    final isQ = e.type == 'soru';
    final hh = e.when.hour.toString().padLeft(2, '0');
    final mm = e.when.minute.toString().padLeft(2, '0');
    final accent = isQ ? _orange : _blue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        onTap: () => _openActivityEntry(e),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isQ ? Icons.quiz_rounded : Icons.menu_book_rounded,
                  size: 17,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.topic,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$hh:$mm',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: inkMute,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: inkMute,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            isQ
                                ? 'Sınav Soruları'.tr()
                                : 'Konu Özeti'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: inkMute),
            ],
          ),
        ),
      ),
    );
  }

  // Aktivite kartına basılınca — özet veya teste DOĞRUDAN yönlendir.
  // 'özet' → _SummaryDetailPage, 'soru' → son test denemesi
  // (tamamlandıysa TestResultPage, değilse TestPage).
  Future<void> _openActivityEntry(_ActivityEntry e) async {
    final isQ = e.type == 'soru';
    final key =
        isQ ? 'library_subjects_questions_v2' : 'library_subjects_v2';
    try {
      final prefs = await SharedPreferences.getInstance();
      final listRaw = prefs.getStringList(key) ?? const [];
      final subjects = listRaw
          .map((s) {
            try {
              return _Subject.fromJson(
                  jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<_Subject>()
          .toList();

      // Ders eşleştir — önce birebir eşleşme, sonra case-insensitive
      _Subject? subject;
      for (final s in subjects) {
        if (s.name == e.subject) {
          subject = s;
          break;
        }
      }
      if (subject == null) {
        final target = e.subject.toLowerCase();
        for (final s in subjects) {
          if (s.name.toLowerCase() == target) {
            subject = s;
            break;
          }
        }
      }

      // Konu (özet) eşleştir
      _Summary? summary;
      if (subject != null) {
        for (final sum in subject.summaries) {
          if (sum.topic == e.topic) {
            summary = sum;
            break;
          }
        }
        if (summary == null) {
          final target = e.topic.toLowerCase();
          for (final sum in subject.summaries) {
            if (sum.topic.toLowerCase() == target) {
              summary = sum;
              break;
            }
          }
        }
      }

      if (!mounted) return;

      // Kayıt bulunamadıysa kütüphaneye fallback, kullanıcı kendi bulsun.
      if (subject == null || summary == null) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AcademicPlanner(
            mode: isQ ? LibraryMode.questions : LibraryMode.summary,
          ),
        ));
        return;
      }

      if (isQ) {
        // En son oluşturulmuş test denemesi
        if (summary.tests.isEmpty) {
          // Hiç test denemesi yoksa kütüphaneye düş
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                const AcademicPlanner(mode: LibraryMode.questions),
          ));
          return;
        }
        final attempt = summary.tests.last;
        if (attempt.completed) {
          final questions = parseTestQuestions(attempt.content);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TestResultPage(
              questions: questions,
              answers: attempt.answers,
              subjectName: subject!.name,
              topic: summary!.topic,
            ),
          ));
        } else {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TestPage(
              rawContent: attempt.content,
              subjectName: subject!.name,
              topic: summary!.topic,
              initialAnswers: attempt.answers,
              timeLimit: attempt.timeLimit,
              onFinish: (answers) async {
                attempt.answers = Map<int, String?>.from(answers);
                attempt.completed = true;
                // Değişiklikleri diske yaz
                try {
                  final prefs2 =
                      await SharedPreferences.getInstance();
                  final updated = subjects
                      .map((s) => jsonEncode(s.toJson()))
                      .toList();
                  await prefs2.setStringList(key, updated);
                } catch (_) {}
              },
            ),
          ));
        }
      } else {
        // Konu özeti — detay sayfası
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SummaryDetailPage(
            summary: summary!,
            subjectName: subject!.name,
          ),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AcademicPlanner(
          mode: isQ ? LibraryMode.questions : LibraryMode.summary,
        ),
      ));
    }
  }

  Widget _buildColorPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              const SizedBox(width: 6),
              Text('Renk'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _headerBg = null;
                    _subjectsBg = null;
                    _pageBg = null;
                  });
                  _saveColors();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text('Sıfırla'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54)),
                ),
              ),
            ],
          ),
          // Hedef chip'leri — Başlık / Dersler / Arka plan. Açıklama yazısı
          // ve renk paleti "Başlık" çerçevesinin sol kenarıyla aynı hizadan
          // başlasın diye tam genişlikte ayrı satırda.
          const SizedBox(height: 8),
          _targetToggle(),
          const SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin çerçeveye bırak.'
                .tr(),
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
                height: 1.3),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _palette.length,
              itemBuilder: (_, i) =>
                  _draggableColor(_palette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetToggle() {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? _orange : Colors.black),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('header', 'Başlık'.tr()),
        const SizedBox(width: 6),
        chip('subjects', 'Dersler'.tr()),
        const SizedBox(width: 6),
        chip('bg', 'Arka plan'.tr()),
      ],
    );
  }

  Widget _draggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _dot(c)),
      child: GestureDetector(
        onTap: () => _applyColor(c),
        child: _dot(c),
      ),
    );
  }

  Widget _dot(Color c) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26, width: 1),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final String label;
  final int day;
  final bool isToday;
  final bool hasActivity;
  const _DayCell({
    required this.label,
    required this.day,
    required this.isToday,
    required this.hasActivity,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isToday ? _indigo : Colors.white;
    final fg = isToday ? Colors.white : Colors.black87;
    return Container(
      width: 50,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday
              ? _indigo
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: isToday
            ? [
                BoxShadow(
                  color: _indigo.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$day',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
          const SizedBox(height: 4),
          Icon(
            hasActivity ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 12,
            color: hasActivity
                ? (isToday ? Colors.white : const Color(0xFF22C55E))
                : (isToday
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.grey.shade300),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LibraryLanding — Kütüphanem karşılama ekranı
//  • Ortalanmış "Kütüphanem" başlığı + ikon
//  • Altında 2 eşit beyaz çerçeve: Konu Özeti / Sınav Soruları
// ═══════════════════════════════════════════════════════════════════════════════
class LibraryLanding extends StatefulWidget {
  const LibraryLanding({super.key});

  @override
  State<LibraryLanding> createState() => _LibraryLandingState();
}

class _LibraryLandingState extends State<LibraryLanding> {
  // ── Renk özelleştirme — diğer sayfalardakiyle aynı format ─────────────
  bool _showColorPicker = false;
  String _colorMode = 'frame'; // 'frame' | 'text'
  String _colorTarget = 'bg'; // 'bg' | 'cards'
  Color? _pageBgOverride;
  Color? _cardsBgOverride;
  Color? _cardsTextOverride;

  static const _libraryColorsKey = 'library_colors_v1';
  static const _libraryPalette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  @override
  void initState() {
    super.initState();
    _loadLibraryColors();
  }

  Future<void> _loadLibraryColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_libraryColorsKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        Color? read(String k) {
          final v = m[k];
          return v is num ? Color(v.toInt()) : null;
        }
        _pageBgOverride = read('bg');
        _cardsBgOverride = read('cards');
        _cardsTextOverride = read('cardsText');
      });
    } catch (_) {}
  }

  Future<void> _saveLibraryColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = <String, int>{};
      void put(String k, Color? c) {
        if (c != null) m[k] = c.toARGB32();
      }
      put('bg', _pageBgOverride);
      put('cards', _cardsBgOverride);
      put('cardsText', _cardsTextOverride);
      if (m.isEmpty) {
        await prefs.remove(_libraryColorsKey);
      } else {
        await prefs.setString(_libraryColorsKey, jsonEncode(m));
      }
    } catch (_) {}
  }

  void _applyLibraryColor(String target, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        _cardsTextOverride = c;
      } else {
        if (target == 'bg') {
          _pageBgOverride = c;
        } else {
          _cardsBgOverride = c;
        }
      }
    });
    _saveLibraryColors();
  }

  void _resetLibraryColors() {
    setState(() {
      _pageBgOverride = null;
      _cardsBgOverride = null;
      _cardsTextOverride = null;
    });
    _saveLibraryColors();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBgOverride ?? const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        foregroundColor: Colors.black87,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_library_rounded,
                color: _blue, size: 22),
            const SizedBox(width: 8),
            Text(
              localeService.tr('my_library'),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(
              child: GestureDetector(
                onTap: () => setState(
                    () => _showColorPicker = !_showColorPicker),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFF6A00),
                        Color(0xFFDB2777),
                        Color(0xFF7C3AED),
                        Color(0xFF2563EB),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showColorPicker
                            ? Icons.close_rounded
                            : Icons.palette_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _showColorPicker
                            ? localeService.tr('close')
                            : 'Renk Seç',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showColorPicker) _buildLibraryColorPanel(),
            if (_showColorPicker) const SizedBox(height: 10),
            // ── Üst satır: 2 ana sekme yatayda ───────────────────────
            // Konu Özeti | Sınav Soruları
            // Bilgi Yarışı bu satırdan ÇIKARILDI → altta tam genişlikte
            // kendi banner kartı olarak duruyor.
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.auto_stories_rounded,
                    title: localeService.tr('create_topic_summary'),
                    color: _blue,
                    compact: true,
                    customBg: _cardsBgOverride,
                    customTextColor: _cardsTextOverride,
                    onColorAccept: (c) => _applyLibraryColor('cards', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AcademicPlanner(
                            mode: LibraryMode.summary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.quiz_rounded,
                    title: localeService.tr('create_exam_questions'),
                    color: _orange,
                    compact: true,
                    customBg: _cardsBgOverride,
                    customTextColor: _cardsTextOverride,
                    onColorAccept: (c) => _applyLibraryColor('cards', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AcademicPlanner(
                            mode: LibraryMode.questions),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Bilgi Yarışı — tam genişlik banner kart ──────────────
            _LandingCard(
              icon: Icons.sports_esports_rounded,
              title: 'Bilgi Yarışı'.tr(),
              color: const Color(0xFFFFB800),
              compact: true,
              customBg: _cardsBgOverride,
              customTextColor: _cardsTextOverride,
              onColorAccept: (c) => _applyLibraryColor('cards', c),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DueloLobbyScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── 2. satır: Çözümlerim (sol) | Çalışma Takvimi (sağ) ───
            // Çözümlerim ana sayfadan TAŞINDI; Sesli Komut sekmesinin
            // ana sayfayı işgal etmesi için yer açıldı.
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.check_circle_rounded,
                    title: 'Çözümlerim'.tr(),
                    color: const Color(0xFF3B82F6),
                    customBg: _cardsBgOverride,
                    customTextColor: _cardsTextOverride,
                    onColorAccept: (c) => _applyLibraryColor('cards', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HistoryScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.calendar_month_rounded,
                    title: localeService.tr('my_study_calendar'),
                    color: _indigo,
                    customBg: _cardsBgOverride,
                    customTextColor: _cardsTextOverride,
                    onColorAccept: (c) => _applyLibraryColor('cards', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StudyCalendarPage(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── 3. satır: Pomodoro | QuAlsar Arena ───────────────────
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.timer_rounded,
                    title: 'Pomodoro Tekniği'.tr(),
                    color: const Color(0xFFE11D48),
                    customBg: _cardsBgOverride,
                    customTextColor: _cardsTextOverride,
                    onColorAccept: (c) => _applyLibraryColor('cards', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const _PomodoroTechniquePage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.stadium_rounded,
                    title: 'QuAlsar Arena',
                    color: const Color(0xFFFF5B2E),
                    customBg: _cardsBgOverride,
                    customTextColor: _cardsTextOverride,
                    onColorAccept: (c) => _applyLibraryColor('cards', c),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QuAlsarArenaScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════ Renk seçim paneli — diğer sayfalar ile aynı format ═══════════════
  Widget _buildLibraryColorPanel() {
    const orange = Color(0xFFFF6A00);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded, size: 16, color: Colors.black),
              const SizedBox(width: 6),
              Text('Renk',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
              const SizedBox(width: 10),
              Expanded(child: _libraryModeToggle(orange)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _resetLibraryColors,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text('Sıfırla',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _libraryTargetToggle(orange),
          const SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin yere bırak.',
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
                height: 1.3),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _libraryPalette.length,
              itemBuilder: (_, i) => _libraryDraggableColor(_libraryPalette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _libraryModeToggle(Color orange) {
    Widget box(String id, IconData icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? orange.withValues(alpha: 0.12)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? orange : Colors.black,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: active ? orange : Colors.black),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? orange : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', Icons.text_fields_rounded, 'Yazı'),
        const SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'),
      ],
    );
  }

  Widget _libraryTargetToggle(Color orange) {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? orange.withValues(alpha: 0.12)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? orange : Colors.black),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('bg', 'Arka plan'),
        const SizedBox(width: 6),
        chip('cards', 'Kartlar'),
      ],
    );
  }

  Widget _libraryDraggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _libraryDot(c)),
      child: GestureDetector(
        onTap: () => _applyLibraryColor(_colorTarget, c),
        child: _libraryDot(c),
      ),
    );
  }

  Widget _libraryDot(Color c) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26, width: 1),
      ),
    );
  }
}

class _LandingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  final Color? customBg;
  final Color? customTextColor;
  final ValueChanged<Color>? onColorAccept;
  /// 3'lü yatay sıralama için kompakt mod — kart yüksekliği + içerik küçülür.
  final bool compact;
  const _LandingCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.customBg,
    this.customTextColor,
    this.onColorAccept,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasSub = subtitle != null && subtitle!.isNotEmpty;
    final bgColor = customBg ?? Colors.white;
    final lum = 0.299 * bgColor.r + 0.587 * bgColor.g + 0.114 * bgColor.b;
    final isDark = lum < 0.55;
    final titleColor =
        customTextColor ?? (isDark ? Colors.white : Colors.black);
    final subtitleColor = customTextColor ??
        (isDark ? Colors.white70 : Colors.black54);

    final cardHeight = compact ? 102.0 : 128.0;
    final iconBox = compact ? 38.0 : (hasSub ? 40.0 : 48.0);
    final iconSize = compact ? 20.0 : (hasSub ? 22.0 : 26.0);
    final titleFs = compact ? 11.0 : (hasSub ? 12.5 : 13.0);

    return DragTarget<Color>(
      onAcceptWithDetails: (d) => onColorAccept?.call(d.data),
      builder: (ctx, cand, _) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: cardHeight,
          padding: EdgeInsets.symmetric(
              horizontal: 8, vertical: hasSub ? 10 : (compact ? 10 : 14)),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: cand.isNotEmpty
                ? Border.all(color: const Color(0xFFFF6A00), width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(compact ? 11 : (hasSub ? 12 : 14)),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: iconSize),
              ),
              SizedBox(height: compact ? 8 : (hasSub ? 6 : 10)),
              Text(
                title,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: titleFs,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                  height: 1.15,
                ),
              ),
              if (hasSub && !compact) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Model ──────────────────────────────────────────────────────────────────
// Konu başına 3 adet test hakkı. Her _TestAttempt bir testi temsil eder:
// JSON içeriği + kullanıcının seçimleri + tamamlanma durumu.
class _TestAttempt {
  final String id;
  final String content;
  Map<int, String?> answers;
  bool completed;
  final DateTime createdAt;
  // Soru başına saniye. 0 = süresiz (relax). 90 = normal, 45 = race.
  final int timeLimit;
  // Seçilen zorluk — UI'da rozet olarak gösterilebilir.
  final String difficulty;

  _TestAttempt({
    required this.id,
    required this.content,
    required this.answers,
    required this.completed,
    required this.createdAt,
    this.timeLimit = 0,
    this.difficulty = 'medium',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'answers': answers
            .map((k, v) => MapEntry(k.toString(), v)),
        'completed': completed,
        'createdAt': createdAt.toIso8601String(),
        'timeLimit': timeLimit,
        'difficulty': difficulty,
      };

  factory _TestAttempt.fromJson(Map<String, dynamic> j) {
    final raw = (j['answers'] as Map?) ?? const {};
    final parsed = <int, String?>{};
    raw.forEach((k, v) {
      final key = int.tryParse(k.toString());
      if (key != null) parsed[key] = v?.toString();
    });
    return _TestAttempt(
      id: (j['id'] ?? DateTime.now().millisecondsSinceEpoch.toString())
          .toString(),
      content: (j['content'] ?? '').toString(),
      answers: parsed,
      completed: (j['completed'] as bool?) ?? false,
      createdAt:
          DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      timeLimit: (j['timeLimit'] as num?)?.toInt() ?? 0,
      difficulty: (j['difficulty'] ?? 'medium').toString(),
    );
  }
}

// Test oluşturma sihirbazının son adımındaki yapılandırma.
class _TestConfig {
  int count = 10;
  String difficulty = 'medium'; // 'easy' | 'medium' | 'hard'
  String timeMode = 'relax'; // 'relax' | 'normal' | 'race'

  int get timeLimitSeconds {
    switch (timeMode) {
      case 'normal':
        return 90;
      case 'race':
        return 45;
      default:
        return 0;
    }
  }
}

class _Summary {
  final String id;
  final String topic;
  // Streaming akışı sırasında parça parça doldurulduğu için `content`
  // mutable. Stream tamamlandığında nihai metin atanır + persist edilir.
  String content;
  final DateTime createdAt;
  // Questions mode için test denemeleri (max 3). Summary mode boş kalır.
  List<_TestAttempt> tests;
  _Summary({
    required this.id,
    required this.topic,
    required this.content,
    required this.createdAt,
    List<_TestAttempt>? tests,
  }) : tests = tests ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'tests': tests.map((t) => t.toJson()).toList(),
      };

  factory _Summary.fromJson(Map<String, dynamic> j) {
    final rawTests = (j['tests'] as List?) ?? const [];
    final tests = rawTests
        .whereType<Map>()
        .map((e) => _TestAttempt.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return _Summary(
      id: j['id'] as String,
      topic: j['topic'] as String,
      content: j['content'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      tests: tests,
    );
  }
}

class _Subject {
  final String id;
  String name;
  List<_Summary> summaries;
  _Subject({required this.id, required this.name, required this.summaries});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'summaries': summaries.map((s) => s.toJson()).toList(),
      };

  factory _Subject.fromJson(Map<String, dynamic> j) => _Subject(
        id: j['id'] as String,
        name: j['name'] as String,
        summaries: ((j['summaries'] as List?) ?? [])
            .map((e) => _Summary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// Seviye → kısaltma (sınav tipi)
String _examShort(String grade) {
  switch (grade) {
    case 'LGS Hazırlık': return 'LGS';
    case 'TYT Hazırlık': return 'TYT';
    case 'AYT Hazırlık': return 'AYT';
    case 'KPSS Hazırlık': return 'KPSS';
    case 'Lise 9-10':    return 'TYT';
    default:             return 'Sınav';
  }
}

// Seviye → bağlam metni
String _contextFromGrade(String grade) {
  switch (grade) {
    case 'LGS Hazırlık':
      return 'Öğrenci LGS (8. sınıf merkezî sınav) için hazırlanıyor.';
    case 'TYT Hazırlık':
      return 'Öğrenci TYT (YKS Temel Yeterlilik Testi) için hazırlanıyor.';
    case 'AYT Hazırlık':
      return 'Öğrenci AYT (YKS Alan Yeterlilik Testi) için hazırlanıyor.';
    case 'KPSS Hazırlık':
      return 'Öğrenci KPSS için hazırlanıyor.';
    case 'Lise 9-10':
      return 'Lise 9-10 öğrencisi, TYT mantığında çalışıyor.';
    case 'Ortaokul':
      return 'Ortaokul düzeyinde, basit dille anlat.';
    case 'İlkokul':
      return 'İlkokul düzeyinde çok basit anlat.';
    case 'Üniversite':
      return 'Üniversite düzeyinde akademik anlat.';
    default:
      return 'Lise/TYT düzeyinde anlat.';
  }
}

// Ders → konu placeholder ipucu (locale-aware)
String _topicHintForSubject(String subject) {
  final s = subject.toLowerCase();
  if (s.contains('matem') || s.contains('math')) return localeService.tr('topic_hint_math');
  if (s.contains('fiz') || s.contains('phys')) return localeService.tr('topic_hint_physics');
  if (s.contains('kim') || s.contains('chem')) return localeService.tr('topic_hint_chemistry');
  if (s.contains('biyo') || s.contains('bio')) return localeService.tr('topic_hint_biology');
  if (s.contains('coğraf') || s.contains('geo')) return localeService.tr('topic_hint_geography');
  if (s.contains('tar') || s.contains('hist')) return localeService.tr('topic_hint_history');
  if (s.contains('edeb') || s.contains('lit')) return localeService.tr('topic_hint_literature');
  if (s.contains('türk') || s.contains('gram')) return localeService.tr('topic_hint_grammar');
  if (s.contains('feles') || s.contains('phil')) return localeService.tr('topic_hint_philosophy');
  if (s.contains('ingil') || s.contains('engl')) return localeService.tr('topic_hint_english');
  return localeService.tr('topic_hint_generic');
}

enum LibraryMode { summary, questions }

class AcademicPlanner extends StatefulWidget {
  final LibraryMode mode;
  // İlk açılışta otomatik açılması istenen ders+konu. Test sonuç sayfasındaki
  // "Kısa bir tekrar" butonu kullanır: özet varsa direkt açılır; yoksa o
  // konuda özet üretim akışı tetiklenir.
  final String? autoOpenSubject;
  final String? autoOpenTopic;
  const AcademicPlanner({
    super.key,
    this.mode = LibraryMode.summary,
    this.autoOpenSubject,
    this.autoOpenTopic,
  });
  @override
  State<AcademicPlanner> createState() => _AcademicPlannerState();
}

class _AcademicPlannerState extends State<AcademicPlanner> {
  String get _subjectsKey => widget.mode == LibraryMode.summary
      ? 'library_subjects_v2'
      : 'library_subjects_questions_v2';
  static const _usageKey = 'topic_summary_usage';

  // _title artık AppBar'da kullanılmıyor (başlık kaldırıldı). Diğer
  // ekranlarda tekrar gerekirse buradan üretilebilir.
  // ignore: unused_element
  String get _title => widget.mode == LibraryMode.summary
      ? localeService.tr('topic_summaries')
      : localeService.tr('exam_questions');
  String get _headline => widget.mode == LibraryMode.summary
      ? localeService.tr('create_summary_hint')
      : 'İstediğin konudan test oluştur'.tr();

  String _grade = '';
  int _monthUsed = 0;
  String _monthKey = '';
  List<_Subject> _subjects = [];
  bool _generating = false;
  // Loader stage list için aktif üretim bilgisi (ders + konu).
  String _generatingSubject = '';
  String _generatingTopic = '';

  // "Diğer Dersler" overlay sheet — modal değil, böylece arka plandaki
  // ilk 8 ders kareleri tıklanabilir/sürüklenebilir kalır.
  bool _showOtherSheet = false;
  // Bir ders sürüklenirken sheet'i şeffaflaştırmak için.
  bool _draggingFromSheet = false;

  // Renk özelleştirme — kullanıcı AppBar'daki palet butonundan açar.
  // İki mod: 'frame' (arka plan/çerçeve/ders kareleri zeminleri) ·
  // 'text' (başlık ve ders kartlarındaki yazı rengi).
  // Üç hedef: 'bg' (sayfa arka planı) · 'frame' (dersleri çevreleyen dış
  // çerçeve / başlık) · 'subjects' (ders kareleri). Renk tek dokunuşla
  // uygulanabilir ya da sürükleyip bırakılabilir.
  bool _showColorPicker = false;
  String _colorMode = 'frame'; // 'frame' | 'text'
  String _colorTarget = 'bg'; // 'bg' | 'frame' | 'subjects'
  Color? _pageBgOverride;
  Color? _frameOverride;
  Color? _frameTextOverride;
  // Manuel eklenen dersler için ayrı çerçeve rengi (drag-drop ile uygulanır)
  Color? _customFrameOverride;
  final Map<String, Color> _subjectTileColors = {};
  final Map<String, Color> _subjectTileTextColors = {};
  static const _planColorPalette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  // SharedPreferences anahtarları — kayıt mode bazlı (özet/test ayrı renk
  // seti). Anahtar adında mode.name kullanıyoruz.
  String get _bgColorKey =>
      'planner_bg_color_${widget.mode.name}';
  String get _frameColorKey =>
      'planner_frame_color_${widget.mode.name}';
  String get _frameTextColorKey =>
      'planner_frame_text_color_${widget.mode.name}';
  String get _tileColorsKey =>
      'planner_tile_colors_${widget.mode.name}';
  String get _tileTextColorsKey =>
      'planner_tile_text_colors_${widget.mode.name}';
  String get _subjectOrderKey =>
      'planner_subject_order_${widget.mode.name}';
  String get _summaryCardColorsKey =>
      'planner_summary_card_colors_${widget.mode.name}';
  String get _customFrameColorKey =>
      'planner_custom_frame_color_${widget.mode.name}';

  // Alt kartların (oluşturulmuş özet/test ders kartları) ayrı renk map'i.
  final Map<String, Color> _summaryCardColors = {};

  Future<void> _loadSummaryCardColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_summaryCardColorsKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _summaryCardColors.clear();
      m.forEach((k, v) {
        if (v is num) _summaryCardColors[k] = Color(v.toInt());
      });
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveSummaryCardColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_summaryCardColors.isEmpty) {
        await prefs.remove(_summaryCardColorsKey);
      } else {
        await prefs.setString(
            _summaryCardColorsKey,
            jsonEncode(_summaryCardColors
                .map((k, v) => MapEntry(k, v.toARGB32()))));
      }
    } catch (_) {}
  }

  void _applyColorToSummaryCard(String subjectId, Color c) {
    setState(() => _summaryCardColors[subjectId] = c);
    _saveSummaryCardColors();
  }

  Future<void> _loadCustomSubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_customSubjectsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final loaded = <EduSubject>[];
      for (final m in list) {
        final key = (m['key'] as String?) ?? '';
        final name = (m['name'] as String?) ?? '';
        final emoji = (m['emoji'] as String?) ?? '📚';
        final colorVal = m['color'];
        if (key.isEmpty || name.isEmpty) continue;
        final color = colorVal is num ? Color(colorVal.toInt()) : _blue;
        loaded.add(EduSubject(key, emoji, name, color));
      }
      if (!mounted) return;
      setState(() => _customSubjects = loaded);
    } catch (_) {}
  }

  Future<void> _saveCustomSubjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _customSubjects
          .map((s) => {
                'key': s.key,
                'name': s.name,
                'emoji': s.emoji,
                'color': s.color.toARGB32(),
              })
          .toList();
      await prefs.setString(_customSubjectsKey, jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _loadSubjectOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_subjectOrderKey);
      if (raw == null || raw.isEmpty) return;
      // _inlineEduSubjects yüklendiyse buna göre yeniden sırala.
      if (_inlineEduSubjects.isEmpty) return;
      final byKey = {for (final s in _inlineEduSubjects) s.key: s};
      final reordered = <EduSubject>[];
      for (final k in raw) {
        final s = byKey.remove(k);
        if (s != null) reordered.add(s);
      }
      // raw'da olmayan yeni dersler sona eklenir.
      reordered.addAll(byKey.values);
      if (!mounted) return;
      setState(() => _inlineEduSubjects = reordered);
    } catch (_) {}
  }

  Future<void> _saveSubjectOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _subjectOrderKey,
        _inlineEduSubjects.map((s) => s.key).toList(),
      );
    } catch (_) {}
  }

  // İki dersin yerini değiştir + kaydet. Drag bitince sheet'i de kapat.
  void _swapSubjects(String draggedKey, String targetKey) {
    if (draggedKey == targetKey) return;
    final list = List<EduSubject>.from(_inlineEduSubjects);
    final from = list.indexWhere((s) => s.key == draggedKey);
    final to = list.indexWhere((s) => s.key == targetKey);
    if (from < 0 || to < 0) return;
    final tmp = list[from];
    list[from] = list[to];
    list[to] = tmp;
    setState(() {
      _inlineEduSubjects = list;
      _draggingFromSheet = false;
    });
    _saveSubjectOrder();
  }

  Future<void> _loadColorPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bgInt = prefs.getInt(_bgColorKey);
      final frameInt = prefs.getInt(_frameColorKey);
      final frameTextInt = prefs.getInt(_frameTextColorKey);
      final customFrameInt = prefs.getInt(_customFrameColorKey);
      final tilesRaw = prefs.getString(_tileColorsKey);
      final tilesTextRaw = prefs.getString(_tileTextColorsKey);
      if (!mounted) return;
      setState(() {
        if (bgInt != null) _pageBgOverride = Color(bgInt);
        if (frameInt != null) _frameOverride = Color(frameInt);
        if (frameTextInt != null) _frameTextOverride = Color(frameTextInt);
        if (customFrameInt != null) _customFrameOverride = Color(customFrameInt);
        if (tilesRaw != null && tilesRaw.isNotEmpty) {
          try {
            final m = jsonDecode(tilesRaw) as Map<String, dynamic>;
            _subjectTileColors.clear();
            m.forEach((k, v) {
              if (v is num) _subjectTileColors[k] = Color(v.toInt());
            });
          } catch (_) {}
        }
        if (tilesTextRaw != null && tilesTextRaw.isNotEmpty) {
          try {
            final m = jsonDecode(tilesTextRaw) as Map<String, dynamic>;
            _subjectTileTextColors.clear();
            m.forEach((k, v) {
              if (v is num) _subjectTileTextColors[k] = Color(v.toInt());
            });
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  Future<void> _saveColorPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_pageBgOverride == null) {
        await prefs.remove(_bgColorKey);
      } else {
        await prefs.setInt(_bgColorKey, _pageBgOverride!.toARGB32());
      }
      if (_frameOverride == null) {
        await prefs.remove(_frameColorKey);
      } else {
        await prefs.setInt(_frameColorKey, _frameOverride!.toARGB32());
      }
      if (_frameTextOverride == null) {
        await prefs.remove(_frameTextColorKey);
      } else {
        await prefs.setInt(
            _frameTextColorKey, _frameTextOverride!.toARGB32());
      }
      if (_customFrameOverride == null) {
        await prefs.remove(_customFrameColorKey);
      } else {
        await prefs.setInt(
            _customFrameColorKey, _customFrameOverride!.toARGB32());
      }
      if (_subjectTileColors.isEmpty) {
        await prefs.remove(_tileColorsKey);
      } else {
        final json = jsonEncode(_subjectTileColors
            .map((k, v) => MapEntry(k, v.toARGB32())));
        await prefs.setString(_tileColorsKey, json);
      }
      if (_subjectTileTextColors.isEmpty) {
        await prefs.remove(_tileTextColorsKey);
      } else {
        final json = jsonEncode(_subjectTileTextColors
            .map((k, v) => MapEntry(k, v.toARGB32())));
        await prefs.setString(_tileTextColorsKey, json);
      }
    } catch (_) {}
  }

  void _applyColorTo(String target, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        // Yazı modu — renk metne uygulanır.
        if (target == 'subjects') {
          for (final s in _inlineEduSubjects) {
            _subjectTileTextColors[s.key] = c;
          }
        } else {
          // 'bg' ya da 'frame' → çerçeve başlık yazısı.
          _frameTextOverride = c;
        }
      } else {
        // Çerçeve modu — zemine uygulanır (mevcut davranış).
        if (target == 'bg') {
          _pageBgOverride = c;
        } else if (target == 'frame') {
          _frameOverride = c;
        } else {
          for (final s in _inlineEduSubjects) {
            _subjectTileColors[s.key] = c;
          }
        }
      }
    });
    _saveColorPrefs();
  }

  void _applyColorToTile(String subjectKey, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        _subjectTileTextColors[subjectKey] = c;
      } else {
        _subjectTileColors[subjectKey] = c;
      }
    });
    _saveColorPrefs();
  }

  Widget _buildColorPickerPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst satır: sol "Renk" başlığı · ortada Yazı/Çerçeve mod seçici ·
          // sağda Sıfırla. Target chips bir alttaki satırda.
          Row(
            children: [
              const Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              const SizedBox(width: 6),
              Text(
                'Renk'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.black),
              ),
              const SizedBox(width: 10),
              Expanded(child: _modeToggle()),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _pageBgOverride = null;
                    _frameOverride = null;
                    _frameTextOverride = null;
                    _customFrameOverride = null;
                    _subjectTileColors.clear();
                    _subjectTileTextColors.clear();
                    _summaryCardColors.clear();
                  });
                  _saveColorPrefs();
                  _saveSummaryCardColors();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    'Sıfırla'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.black54),
                  ),
                ),
              ),
            ],
          ),
          // Hedef chip'leri — "Arka plan / Çerçeve / Ders alanı". Tam
          // genişlikte tek satır; altındaki açıklama yazısı ve renk paleti
          // "Arka plan" çerçevesinin sol kenarı ile aynı hizadan başlar.
          const SizedBox(height: 8),
          _targetToggle(),
          const SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin kareye veya arka plana bırak.'
                .tr(),
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
                height: 1.3),
          ),
          const SizedBox(height: 8),
          // Çift sıra, yatay kaydırılabilir · her renk Draggable.
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _planColorPalette.length,
              itemBuilder: (_, i) =>
                  _draggableColor(_planColorPalette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetToggle() {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? _orange : Colors.black),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('bg', 'Arka plan'.tr()),
        const SizedBox(width: 6),
        chip('frame', 'Çerçeve'.tr()),
        const SizedBox(width: 6),
        chip('subjects', 'Ders alanı'.tr()),
      ],
    );
  }

  // Yazı / Çerçeve mod seçici — Renk başlığının altında iki küçük kutu.
  Widget _modeToggle() {
    Widget box(String id, IconData icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 13,
                    color: active ? _orange : Colors.black),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? _orange : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', Icons.text_fields_rounded, 'Yazı'.tr()),
        const SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'.tr()),
      ],
    );
  }

  Widget _draggableColor(Color c) {
    final selected = (_colorMode == 'frame') &&
        ((_colorTarget == 'bg' && _pageBgOverride == c) ||
            (_colorTarget == 'frame' && _frameOverride == c));
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: _colorDot(c, faded: true, selected: false),
      child: GestureDetector(
        onTap: () => _applyColorTo(_colorTarget, c),
        child: _colorDot(c, selected: selected),
      ),
    );
  }

  Widget _colorDot(Color c,
      {bool faded = false, bool selected = false}) {
    return Opacity(
      opacity: faded ? 0.3 : 1.0,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _orange : Colors.black26,
            width: selected ? 2.4 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded,
                size: 16, color: _orange)
            : null,
      ),
    );
  }

  // Inline ders ekle paneli (sürekli açık, modal yok)
  EduProfile? _inlineProfile;
  List<EduSubject> _inlineEduSubjects = [];

  // Kullanıcının kendi eklediği kalıcı dersler — modlar arası paylaşılır
  // (özet ve test sayfasında aynı liste görünür).
  static const _customSubjectsKey = 'planner_custom_subjects_v1';
  List<EduSubject> _customSubjects = [];



  @override
  void initState() {
    super.initState();
    _load();
    _loadColorPrefs();
    _loadSummaryCardColors();
    _loadCustomSubjects();
    // Inline panel profili hemen yükle
    EduProfile.load().then((p) async {
      if (!mounted) return;
      // AI cache pref'ten yükle (uygulama yeniden başlatıldıysa olabilir).
      await EduProfile.loadAiSubjectCache();
      if (!mounted) return;
      setState(() {
        _inlineProfile = p;
        _inlineEduSubjects = _subjectsForProfileAllTracks(p);
      });
      // Varsayılan sıra: çekirdek dersler kullanım azalan + seçmeliler sona.
      // Kullanıcı manuel sürükle-bırak yapmışsa _loadSubjectOrder bunu ezer.
      await _applyDefaultUsageOrder();
      _loadSubjectOrder();
      // Cache yoksa AI'dan profile özel ders listesi çek + güncelle.
      if (p != null && EduProfile.aiCachedSubjects(p) == null) {
        unawaited(_fetchAiCurriculum(p));
      }
    });
  }

  Future<void> _applyDefaultUsageOrder() async {
    final usage = await SubjectUsageStats.load();
    if (!mounted) return;
    setState(() {
      _inlineEduSubjects =
          orderSubjectsByUsage(_inlineEduSubjects, usage);
    });
  }

  /// AI'dan o profilin müfredatını çek + cache'le + UI'yi yenile.
  /// `fetchProfileCurriculum` ders + konuları beraber döndürür → 131 ülkenin
  /// her biri için (static catalog'a bakmaksızın) ülke-spesifik müfredat üretir.
  Future<void> _fetchAiCurriculum(EduProfile p) async {
    try {
      final result = await GeminiService.fetchProfileCurriculum(p);
      if (result.subjects.isEmpty) return;
      await EduProfile.saveAiSubjectCache(p, result.subjects);
      if (result.topicsBySubject.isNotEmpty) {
        await EduProfile.saveAiTopicsCache(p, result.topicsBySubject);
      }
      if (!mounted) return;
      setState(() {
        _inlineEduSubjects = _subjectsForProfileAllTracks(p);
      });
      await _applyDefaultUsageOrder();
      _loadSubjectOrder();
    } catch (_) {
      // Sessizce başarısız — kullanıcı static fallback listesini görür.
    }
  }

  /// subjectsForProfile'ı tüm track varyasyonları üzerinde UNION'lar.
  /// Kullanıcı profilinde "Eşit Ağırlık" seçse bile diğer alanlardaki
  /// dersler de grid'te görünür — hepsi tıklanabilir.
  List<EduSubject> _subjectsForProfileAllTracks(EduProfile? p) {
    if (p == null) return [];
    final seen = <String>{};
    final all = <EduSubject>[];
    void addList(List<EduSubject> list) {
      for (final s in list) {
        if (seen.add(s.key)) all.add(s);
      }
    }
    addList(subjectsForProfile(p));
    if (p.level == 'high') {
      const knownTracks = <String>[
        'sayisal', 'esit_agirlik', 'sozel', 'dil',
        'science', 'commerce', 'arts',
        'ipa', 'ips',
      ];
      for (final t in knownTracks) {
        if (p.track == t) continue;
        addList(subjectsForProfile(EduProfile(
          country: p.country,
          level: p.level,
          grade: p.grade,
          track: t,
          faculty: p.faculty,
        )));
      }
    }
    return all;
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Depolama ─────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final grade = prefs.getString('user_grade_level') ?? '';

    final now = DateTime.now();
    final mkey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    // Geliştirme sürecinde aylık kota sıfırlanıyor: tüm cihazlarda bir kez
    // sıfıra çekmek için sayaç yok sayılır. Yayına alırken bu bloğu kaldır.
    var used = 0;
    await prefs.setString(
      _usageKey,
      jsonEncode({'month': mkey, 'count': 0}),
    );

    final listRaw = prefs.getStringList(_subjectsKey) ?? [];
    final list = listRaw
        .map((s) {
          try {
            return _Subject.fromJson(
                jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<_Subject>()
        .toList();

    // Eski kayıtları yeni modele taşı: Questions mode'da tests boşsa
    // ama content doluysa, content'i ilk deneme olarak kabul et.
    if (widget.mode == LibraryMode.questions) {
      for (final subj in list) {
        for (final sum in subj.summaries) {
          if (sum.tests.isEmpty && sum.content.isNotEmpty) {
            sum.tests.add(_TestAttempt(
              id: '${sum.id}_legacy',
              content: sum.content,
              answers: {},
              completed: false,
              createdAt: sum.createdAt,
            ));
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _grade = grade;
      _monthKey = mkey;
      _monthUsed = used;
      _subjects = list;
    });
    // Test sonuç sayfasından "Kısa bir tekrar" ile açıldıysa hedef konuyu
    // otomatik aç (varsa özetini, yoksa üretim akışını).
    _maybeAutoOpen();
  }

  bool _autoOpenHandled = false;

  void _maybeAutoOpen() {
    if (_autoOpenHandled) return;
    final s = widget.autoOpenSubject;
    final t = widget.autoOpenTopic;
    if (s == null || s.trim().isEmpty || t == null || t.trim().isEmpty) {
      return;
    }
    _autoOpenHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _Subject? subjectRef;
      final target = _normSubjectName(s);
      for (final sb in _subjects) {
        if (_normSubjectName(sb.name) == target) {
          subjectRef = sb;
          break;
        }
      }
      _Summary? summary;
      if (subjectRef != null) {
        for (final sum in subjectRef.summaries) {
          if (sum.topic.toLowerCase() == t.trim().toLowerCase()) {
            summary = sum;
            break;
          }
        }
      }
      if (summary != null) {
        _openSummary(summary, subjectRef!.name);
      } else {
        await _runGenerateWithSetup(subjectName: s, topic: t);
      }
    });
  }

  Future<void> _persistUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _usageKey,
      jsonEncode({'month': _monthKey, 'count': _monthUsed}),
    );
  }

  Future<void> _persistSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _subjectsKey,
      _subjects.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }





  // Public: detail page'in çağırdığı "yeni konu ekle" akışı (page açık kalır)
  Future<bool> _generateForExistingSubject(
      _Subject subject, String topic,
      {_TestConfig? config}) async {
    if (_monthUsed >= _monthlyLimit) {
      _showSnack(localeService.tr('monthly_limit_reached'));
      return false;
    }
    final isQuestions = widget.mode == LibraryMode.questions;
    final cfg = config ?? _TestConfig();

    // Questions mode: aynı konu varsa 3 hakkını kontrol et + attempt ekle.
    _Summary? existingSummary;
    if (isQuestions) {
      for (final s in subject.summaries) {
        if (s.topic.toLowerCase() == topic.toLowerCase()) {
          existingSummary = s;
          break;
        }
      }
      if (existingSummary != null && existingSummary.tests.length >= 3) {
        _showSnack(
            'Bu konu için 3 test hakkın da bitti. Başka bir konu dene.'.tr());
        return false;
      }
    }

    try {
      final profile = await EduProfile.load();
      final baseCtx = _contextFromGrade(_grade);
      final profileCtx = educationContext(profile);
      final ctx = profileCtx.isEmpty ? baseCtx : '$baseCtx\n$profileCtx';
      final exam = _examShort(_grade);
      final prompt = _buildPrompt(
        subject: subject.name,
        topic: topic,
        ctx: ctx,
        exam: exam,
        count: cfg.count,
        difficulty: cfg.difficulty,
      );
      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: isQuestions ? 'TestSorulari' : 'KonuÖzeti',
        subject: subject.name,
      );
      final cleanContent = isQuestions ? content : _stripMarkdown(content);

      if (isQuestions && existingSummary != null) {
        existingSummary.tests.add(_TestAttempt(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: cleanContent,
          answers: {},
          completed: false,
          createdAt: DateTime.now(),
          timeLimit: cfg.timeLimitSeconds,
          difficulty: cfg.difficulty,
        ));
      } else {
        final summary = _Summary(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          topic: topic,
          content: cleanContent,
          createdAt: DateTime.now(),
          tests: isQuestions
              ? [
                  _TestAttempt(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    content: cleanContent,
                    answers: {},
                    completed: false,
                    createdAt: DateTime.now(),
                    timeLimit: cfg.timeLimitSeconds,
                    difficulty: cfg.difficulty,
                  ),
                ]
              : null,
        );
        subject.summaries.insert(0, summary);
      }
      _monthUsed += 1;
      await _persistSubjects();
      await _persistUsage();
      await _ActivityStore.log(
        subject: subject.name,
        topic: topic,
        type: isQuestions ? 'soru' : 'özet',
      );
      if (mounted) setState(() {});
      return true;
    } on GeminiException catch (e) {
      if (mounted) _showSnack(e.userMessage);
      return false;
    } catch (e) {
      if (mounted) _showSnack('${localeService.tr('error_label')}: $e');
      return false;
    }
  }

  // Questions mode — var olan _Summary'e yeni bir test hakkı ekler.
  // 3 hak dolunca engellenir. Tamamlandığında TestPage'i açar.
  // Loader state'i _SubjectDetailPage kendi yönetir; burada sadece veri işi.
  Future<void> _generateAttemptForSummary(
      _Subject subject, _Summary summary,
      {_TestConfig? config}) async {
    if (widget.mode != LibraryMode.questions) return;
    if (_monthUsed >= _monthlyLimit) {
      _showSnack(localeService.tr('monthly_limit_reached'));
      return;
    }
    if (summary.tests.length >= 3) {
      _showSnack(
          'Bu konu için 3 test hakkın da bitti. Başka bir konu dene.'.tr());
      return;
    }
    final cfg = config ?? _TestConfig();
    try {
      final profile = await EduProfile.load();
      final baseCtx = _contextFromGrade(_grade);
      final profileCtx = educationContext(profile);
      final ctx = profileCtx.isEmpty ? baseCtx : '$baseCtx\n$profileCtx';
      final exam = _examShort(_grade);
      final prompt = _buildQuestionsPrompt(
        subject: subject.name,
        topic: summary.topic,
        ctx: ctx,
        exam: exam,
        count: cfg.count,
        difficulty: cfg.difficulty,
      );
      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'TestSorulari',
        subject: subject.name,
      );
      final attempt = _TestAttempt(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        answers: {},
        completed: false,
        createdAt: DateTime.now(),
        timeLimit: cfg.timeLimitSeconds,
        difficulty: cfg.difficulty,
      );
      summary.tests.add(attempt);
      _monthUsed += 1;
      await _persistSubjects();
      await _persistUsage();
      await _ActivityStore.log(
        subject: subject.name,
        topic: summary.topic,
        type: 'soru',
      );
      if (!mounted) return;
      setState(() {});
      _openTestAttempt(summary, attempt, subject.name);
    } on GeminiException catch (e) {
      if (mounted) _showSnack(e.userMessage);
    } catch (e) {
      if (mounted) _showSnack('${localeService.tr('error_label')}: $e');
    }
  }

  // Questions mode — önce _TestSetupPage aç, sonra _generate.
  // Summary mode — setup'a gerek yok, doğrudan üret.
  Future<void> _runGenerateWithSetup({
    required String subjectName,
    required String topic,
  }) async {
    if (widget.mode != LibraryMode.questions) {
      await _generate(
          subjectName: subjectName, topic: topic, newSubject: true);
      return;
    }
    // Var olan konu için sonraki attempt index'ini bul; 3 dolduysa engelle.
    int nextIdx = 0;
    for (final s in _subjects) {
      if (s.name.toLowerCase() == subjectName.toLowerCase()) {
        for (final sum in s.summaries) {
          if (sum.topic.toLowerCase() == topic.toLowerCase()) {
            nextIdx = sum.tests.length;
            break;
          }
        }
        break;
      }
    }
    if (nextIdx >= 3) {
      _showSnack(
          'Bu konu için 3 test hakkın da bitti. Başka bir konu dene.'.tr());
      return;
    }
    // Küçük zorluk seçici dialog — arka plan flu + 3 kutu + Tamam butonu.
    final cfg = await _showDifficultyDialog();
    if (cfg == null) return;
    await _generate(
      subjectName: subjectName,
      topic: topic,
      newSubject: true,
      config: cfg,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Zorluk seçici dialog — Kolay · Orta · Zor + Tamam butonu.
  //  Arka plan BackdropFilter ile fludur. Kullanıcı bir zorluğa basınca
  //  seçili olur; "Tamam"a basınca _TestConfig döner.
  // ══════════════════════════════════════════════════════════════════════════
  Future<_TestConfig?> _showDifficultyDialog() {
    return showGeneralDialog<_TestConfig>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.2),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, a1, a2) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: const _DifficultyPickerDialog(),
      ),
    );
  }

  // ── AI çağrısı ve özet kayıt (yeni ders kartı için) ──────────────────────
  Future<void> _generate({
    required String subjectName,
    required String topic,
    required bool newSubject,
    _Subject? existingSubject,
    _TestConfig? config,
  }) async {
    final isQuestions = widget.mode == LibraryMode.questions;
    final cfg = config ?? _TestConfig();

    // Subject ref'i ÖNCE bul — sonraki check'lerin (per-subject limit, varolan
    // summary lookup) buna ihtiyacı var. Türkçe karakterlere dayanıklı normalize.
    _Subject? subjectRef = existingSubject;
    if (subjectRef == null || subjectRef.id.isEmpty) {
      final target = _normSubjectName(subjectName);
      for (final s in _subjects) {
        if (_normSubjectName(s.name) == target) {
          subjectRef = s;
          break;
        }
      }
    }

    // ── LIMIT KADEMELERİ ────────────────────────────────────────────────
    // 1) Yeni quota sistemi (UsageQuota): günlük + aylık global sınır.
    //    Hem konu özeti (200/ay) hem test (300/ay) ayrı sayaçlar tutar.
    //    Eski `_monthUsed` ve per-subject 4/ay limitleri KALDIRILDI —
    //    UsageQuota tek doğru kaynak. (Önceden 3 katman çakışıyordu;
    //    kullanıcı 4+ özet üretince "oluşturulamıyor" oluyordu.)
    final kind = isQuestions ? QuotaKind.testQuestions : QuotaKind.topicSummary;
    final quota = await UsageQuota.get(kind);
    if (quota.isExhausted) {
      Analytics.logQuotaExhausted(kind.name);
      _showSnack(quota.isDailyExhausted
          ? 'Günlük AI sınırına ulaştın (${quota.dailyLimit}). '
              'Yarın tekrar dene veya Premium\'a geç.'
          : 'Aylık AI sınırına ulaştın (${quota.monthlyLimit}). '
              'Ay başında sıfırlanır.');
      return;
    }
    // ── /LIMIT ───────────────────────────────────────────────────────────
    _Summary? existingSummary;
    if (isQuestions && subjectRef != null && subjectRef.id.isNotEmpty) {
      for (final s in subjectRef.summaries) {
        if (s.topic.toLowerCase() == topic.toLowerCase()) {
          existingSummary = s;
          break;
        }
      }
    }
    if (isQuestions &&
        existingSummary != null &&
        existingSummary.tests.length >= 3) {
      _showSnack(
          'Bu konu için 3 test hakkın da bitti. Başka bir konu dene.'.tr());
      return;
    }

    // Tüm pre-check'ler geçti — şimdi quota counter'ı artır + Analytics event.
    // Daha önce burada quota erkenden artırılıyordu; engellenen op'larda boşa
    // sayaç tüketiyordu (kullanıcı limite çabuk takılıyordu).
    await UsageQuota.increment(kind);
    Analytics.logEvent(
      isQuestions ? 'test_questions_generated' : 'topic_summary_generated',
      params: {
        'subject': subjectName,
        'topic': topic,
      },
    );

    // KonuÖzeti modunda STREAMING kullanılır — sayfa anında açılır,
    // AI yazdıkça içerik dolar. TestSorulari modunda JSON full yanıt
    // bekleyen klasik akış.
    final profile = await EduProfile.load();
    final baseCtx = _contextFromGrade(_grade);
    final profileCtx = educationContext(profile);
    final ctx = profileCtx.isEmpty ? baseCtx : '$baseCtx\n$profileCtx';
    final exam = _examShort(_grade);
    final prompt = isQuestions
        ? _buildQuestionsPrompt(
            subject: subjectName,
            topic: topic,
            ctx: ctx,
            exam: exam,
            count: cfg.count,
            difficulty: cfg.difficulty,
          )
        : _buildSummaryPrompt(
            subject: subjectName, topic: topic, ctx: ctx, exam: exam);

    if (!isQuestions) {
      // ── STREAMING AKIŞI (KonuÖzeti) ─────────────────────────────────
      // 1) Boş özet oluştur, _subjects'e ekle, persist et.
      // 2) Sayfayı HEMEN aç + stream'i ona ver.
      // 3) Stream bitince summary.content güncellenir + persist edilir
      //    (onStreamComplete callback'iyle).
      final summary = _Summary(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        topic: topic,
        content: '',
        createdAt: DateTime.now(),
      );
      if (subjectRef != null && subjectRef.id.isNotEmpty) {
        subjectRef.summaries.insert(0, summary);
      } else {
        _subjects.add(_Subject(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: subjectName,
          summaries: [summary],
        ));
      }
      _monthUsed += 1;
      await _persistSubjects();
      await _persistUsage();
      await _ActivityStore.log(
        subject: subjectName,
        topic: topic,
        type: 'özet',
      );

      if (!mounted) return;
      setState(() {});

      final stream = GeminiService.solveHomeworkStream(
        question: prompt,
        solutionType: 'KonuÖzeti',
        subject: subjectName,
      );

      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _SummaryDetailPage(
          summary: summary,
          subjectName: subjectName,
          stream: stream,
          onStreamComplete: (finalContent) async {
            summary.content = _stripMarkdown(finalContent);
            await _persistSubjects();
            if (mounted) setState(() {});
          },
        ),
      )).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    // ── KLASİK AKIŞ (TestSorulari) — JSON tam yanıt gerekir ──────────
    setState(() {
      _generating = true;
      _generatingSubject = subjectName;
      _generatingTopic = topic;
    });
    try {
      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'TestSorulari',
        subject: subjectName,
      );

      // AI yanıtı boş veya çok kısa geldiyse — kaydetme, hata göster + retry
      if (content.trim().length < 40) {
        if (!mounted) return;
        setState(() => _generating = false);
        _showRetrySnack(
          'AI yanıt veremedi. Tekrar denemek ister misin?',
          () => _generate(
            subjectName: subjectName,
            topic: topic,
            newSubject: newSubject,
            existingSubject: existingSubject,
            config: config,
          ),
        );
        return;
      }

      final cleanContent = content;

      // Bu noktaya yalnız TestSorulari modunda ulaşılır (KonuÖzeti yukarıda
      // streaming akışıyla erken return etti).
      final _Summary targetSummary;
      final _TestAttempt createdAttempt;

      if (existingSummary != null) {
        createdAttempt = _TestAttempt(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: cleanContent,
          answers: {},
          completed: false,
          createdAt: DateTime.now(),
          timeLimit: cfg.timeLimitSeconds,
          difficulty: cfg.difficulty,
        );
        existingSummary.tests.add(createdAttempt);
        targetSummary = existingSummary;
      } else {
        final summary = _Summary(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          topic: topic,
          content: cleanContent,
          createdAt: DateTime.now(),
        );
        createdAttempt = _TestAttempt(
          id: summary.id,
          content: cleanContent,
          answers: {},
          completed: false,
          createdAt: summary.createdAt,
          timeLimit: cfg.timeLimitSeconds,
          difficulty: cfg.difficulty,
        );
        summary.tests.add(createdAttempt);
        if (subjectRef != null && subjectRef.id.isNotEmpty) {
          subjectRef.summaries.insert(0, summary);
        } else {
          _subjects.add(_Subject(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: subjectName,
            summaries: [summary],
          ));
        }
        targetSummary = summary;
      }

      _monthUsed += 1;
      await _persistSubjects();
      await _persistUsage();
      await _ActivityStore.log(
        subject: subjectName,
        topic: topic,
        type: 'soru',
      );

      if (!mounted) return;
      setState(() => _generating = false);
      _openTestAttempt(targetSummary, createdAttempt, subjectName);
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      _showRetrySnack(
        e.userMessage,
        () => _generate(
          subjectName: subjectName,
          topic: topic,
          newSubject: newSubject,
          existingSubject: existingSubject,
          config: config,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      _showRetrySnack(
        '${localeService.tr('error_label')}: $e',
        () => _generate(
          subjectName: subjectName,
          topic: topic,
          newSubject: newSubject,
          existingSubject: existingSubject,
          config: config,
        ),
      );
    }
  }

  String _buildPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
    int count = 10,
    String difficulty = 'medium',
  }) {
    if (widget.mode == LibraryMode.questions) {
      return _buildQuestionsPrompt(
        subject: subject,
        topic: topic,
        ctx: ctx,
        exam: exam,
        count: count,
        difficulty: difficulty,
      );
    }
    return _buildSummaryPrompt(
        subject: subject, topic: topic, ctx: ctx, exam: exam);
  }

  static String _buildQuestionsPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
    int count = 10,
    String difficulty = 'medium',
  }) {
    final layer = _subjectLayer(subject);
    final isNumeric = layer == 'numeric';
    final isVerbal = layer == 'verbal';
    final layerLine = isNumeric
        ? '• Katman 1 (Sayısal): "sol" alanında formül + sembol/birim + işlem '
            'basamakları (algoritma) sırasıyla yer alsın. Biyoloji ise genetik '
            'çaprazlama (Aa × Aa) ve biyokimyasal formüller (\\( C_6H_{12}O_6 \\)) '
            'kusursuz gösterilsin.'
        : isVerbal
            ? '• Katman 2 (Sözel): "sol" alanında akıcı bir profesör dili kullan; '
                'tarihte kesin yıl/antlaşma, edebiyatta yazar-eser-dönem bağı, '
                'felsefede argüman→sentez şeması bulunsun. LaTeX kullanma.'
            : '• Konu sayısalsa formül+birim, sözelse kronolojik/kavramsal bağ '
                'biçiminde "sol" alanını kur.';
    final diffLine = () {
      switch (difficulty) {
        case 'easy':
          return '• "d" alanı: tüm sorular "easy". Sorular temel seviyede, '
              'tanım ve basit uygulama odaklı.';
        case 'hard':
          return '• "d" alanı: tüm sorular "hard". Sorular zorlayıcı — çok '
              'adımlı, kavramsal derinlik, istisnalar ve tuzak şıklar içersin.';
        case 'medium':
        default:
          return '• "d" alanı: tüm sorular "medium". Tipik sınav zorluğunda, '
              'dengeli.';
      }
    }();
    return '''
[TEST — $count SORU · JSON]
Ders: $subject
Konu: $topic
Bağlam: $ctx
Zorluk: $difficulty
Katman: ${isNumeric ? 'SAYISAL (formül + sembol + birim)' : isVerbal ? 'SÖZEL (anlatı + kronoloji + bağlam)' : 'KARMA'}

GÖREVİN: Bu konu için $exam stiline uygun TAM OLARAK $count soru üret.
Tüm sorular $difficulty zorluk seviyesinde olsun.
QuAlsar Akademik İçerik Protokolü'nü uygula:
$layerLine
SADECE geçerli bir JSON array döndür — başka hiçbir metin, açıklama,
markdown fence (```json), emoji başlık yok.

Format (array, $count eleman):
[
  {
    "q": "soru metni — ÇOK kısa ve net, en fazla 1 kısa cümle",
    "opts": {"A": "...", "B": "...", "C": "...", "D": "...", "E": "..."},
    "ans": "B",
    "hint": "tek cümle yol gösterici ipucu — cevabı VERME, sadece yöntem/ilke",
    "sol": "2-3 cümle çözüm. Formüller LaTeX: \\\\( ... \\\\) veya \\\\[ ... \\\\].",
    "d": "$difficulty"
  },
  ...
]

ZORUNLU KURALLAR:
• TAM $count soru, ne eksik ne fazla.
• "opts" her zaman 5 şık: A, B, C, D, E.
• "ans" şık harfi: "A" | "B" | "C" | "D" | "E".
• Soru metni (q) ÇOK KISA — ideal 1 kısa cümle, maksimum 15 kelime.
  Uzun anlatım, hikâye, gereksiz detay EKLEME.
• "hint" tek cümle — kullanıcıya "nereden başlamalı" diye yol göster.
  Cevabı açıkça söyleme; sadece yöntem veya anahtar kavram ver.
• "sol" 2-3 cümle — sorunun çözüm mantığını kısa ver.
$diffLine
• ÇELDİRİCİLER (ÖSYM/LGS mantığı): Yanlış şıklar RASTGELE büyük sayı değil,
  öğrencinin GERÇEKTEN yapabileceği hatalar olmalı:
   – işaret hatası (artıyı eksiyle karıştırma)
   – birim/ondalık karışıklığı
   – formülün yanlış uygulanması (örn. yarıçap yerine çap, çevre yerine alan)
   – paydanın sıfır olduğu özel durumu atlama
   – eksik koşul (ör. \\( x \\neq 0 \\)) görmemek
   – sık yapılan kavramsal karıştırma
  En az 2 çeldirici bu tipte olmalı; yalnız bir doğru cevap.
• Dolar işareti (\$) kullanma — LaTeX için \\\\( ... \\\\) ve \\\\[ ... \\\\].
• Markdown yıldız (**) veya başlık (#) YAZMA.
• Emoji başlık (📝 📖 🔑) EKLEME.
• "Sonuç:" / "Püf Nokta:" yazma.
• Türkçe. $exam stiline uygun, tek doğru cevaplı.
• Çıktın tek başına geçerli bir JSON array olmalı — baştan sondan fazla
  whitespace, açıklama, backtick fence YOK.
''';
  }

  // ── Ders adı normalizasyonu — aynı ders altında özet birleştirme ────────
  // "Coğrafya" / "coğrafya" / "  COĞRAFYA  " / "Cografya" gibi varyasyonlar
  // tek kart altında birleşsin diye eşleştirme normalize anahtarla yapılır.
  static String _normSubjectName(String s) {
    var t = s.trim().toLowerCase();
    // Türkçe ve yaygın aksanlı karakterleri ASCII karşılığına indir
    const map = {
      'ç': 'c', 'ğ': 'g', 'ı': 'i', 'i̇': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
      'â': 'a', 'î': 'i', 'û': 'u', 'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o',
      'ú': 'u', 'ñ': 'n', 'ä': 'a', 'ë': 'e', 'ï': 'i',
    };
    map.forEach((k, v) => t = t.replaceAll(k, v));
    // Birden fazla boşluk → tek boşluk
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  // ── QuAlsar Akademik İçerik Protokolü — ders katmanı tespiti ───────────
  // Sayısal: Matematik, Geometri, Fizik, Kimya, Biyoloji
  // Sözel:   Tarih, Coğrafya, Edebiyat, Felsefe, Türkçe, Sanat Tarihi,
  //          Din Kültürü, Mantık (+ İngilizce/Yabancı Dil)
  static String _subjectLayer(String subject) {
    final s = subject.toLowerCase();
    bool any(List<String> ks) => ks.any(s.contains);
    if (any([
      'matematik', 'math', 'geometri', 'geometry',
      'fizik', 'physics', 'kimya', 'chem',
      'biyoloji', 'biology',
      '数学', '物理', '化学', '生物', '几何',
    ])) {
      return 'numeric';
    }
    if (any([
      'tarih', 'history', 'coğraf', 'cografya', 'geograph',
      'edebiyat', 'literature', 'türk dili', 'türkçe', 'turkish',
      'felsefe', 'philosoph', 'sanat tarihi', 'art history',
      'din kült', 'religion', 'mantık', 'logic',
      'ingiliz', 'english', 'yabancı dil',
      '历史', '地理', '文学', '哲学',
    ])) {
      return 'verbal';
    }
    return 'mixed';
  }

  // ── Prompt builder — paylaşılan ─────────────────────────────────────────
  static String _buildSummaryPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
  }) {
    final layer = _subjectLayer(subject);
    final isNumeric = layer == 'numeric';
    final isVerbal = layer == 'verbal';

    // ─── KATMAN 1 — SAYISAL: Mantık, Sembol ve Formül Disiplini ─────────────
    final numericProtocol = '''
[QUALSAR — AKADEMİK DERİNLİK PROTOKOLÜ · KATMAN 1: SAYISAL BRANŞ]
Bu dersin EN YETKİN UZMANI gibi yaz: profesyonel, akıcı, otoriter.
Hedef: YKS derecesi yapacak öğrencinin başka kaynağa ihtiyaç duymayacağı
"Nihai Özet". Anlatım mimarisi:
  • ATOMİK ANALİZ: Konuyu en küçük yapı taşına kadar parçala
    (örn. çarpanlara ayırma basamakları, kuvvet bileşenleri, mol-kütle dönüşümü).
  • MANTIK TEMELİ: "Neden?" sorusuna bilimsel yanıt.
  • GÖRSELLEŞTİRİLMİŞ FORMÜLLER: Her formül belirgin ve açıklamalı; her
    sembolün anlamı + BİRİMİ açıkça verilsin.
    Örn: \\( F = m \\cdot a \\)  →  F: kuvvet (N), m: kütle (kg), a: ivme (m/s²).
  • HÜCRELİ ANLATIM: Her formül/kuralın HEMEN ALTINDA "🧪 Uygulama Örneği"
    ile mini bir soru çöz; çözüm adım adım (algoritmik) gösterilsin.
  • TAMLIK İLKESİ: Sadece ana bilgi DEĞİL — istisnalar (örn. \\( 0! = 1 \\)),
    pozitif/negatif bölenler, uç durumlar, sınavda hata yaptıran ince
    detaylar kapsansın. Sembol galerisi: \\( \\sum, \\int, \\Delta, \\Omega, \\nabla \\) bağlamında.
  • BİYOLOJİK SEMBOLİZM: Genetik çaprazlama (Aa × Aa → 1 AA : 2 Aa : 1 aa)
    ve biyokimyasal formüller (\\( C_6H_{12}O_6 \\), \\( CO_2 \\), \\( H_2O \\)) kusursuz.
''';

    // ─── KATMAN 2 — SÖZEL: Anlatı, Akıcılık, Derinlik ─────────────────────
    final verbalProtocol = '''
[QUALSAR — AKADEMİK DERİNLİK PROTOKOLÜ · KATMAN 2: SÖZEL BRANŞ]
Bu dersin EN YETKİN UZMANI/profesörü gibi yaz: hitabet gücüyle, akıcı,
büyüleyici. Hedef: YKS derecesi yapacak öğrencinin başka kaynağa ihtiyaç
duymayacağı "Nihai Özet". Anlatım mimarisi:
  • HİYERARŞİK YAPI: Ana başlıklar → alt başlıklar → maddeler; konuyu
    mantıksal sıraya diz, karmaşayı önle.
  • SEBEP-SONUÇ DETAYI: Olayları kuru ezber DEĞİL, "dönemin ruhu"yla
    sebep→sonuç zincirine yedirerek anlat — ANA BAŞLIKLARIN İÇİNDE.
  • ENTELEKTÜEL DERİNLİK: Felsefede kavramsal analiz, edebiyatta sanatsal
    yorum, tarihte dönemsel analiz — profesyonel dilde harmanlı.
  • LaTeX KULLANMA — düz, akıcı Türkçe paragraf/maddeler.
''';

    final protocolBlock = isNumeric
        ? numericProtocol
        : isVerbal
            ? verbalProtocol
            : '''
[QUALSAR — AKADEMİK DERİNLİK PROTOKOLÜ · KARMA BRANŞ]
Konu sayısal işlem gerektiriyorsa Katman 1 (atomik analiz, görselleştirilmiş
formüller, hücreli anlatım, tamlık ilkesi) kurallarını; kavramsal/anlatı
ağırlıklıysa Katman 2 (hiyerarşi + sebep-sonuç + derinlik) kurallarını
uygula. "Nihai Özet" hedefini koru.
''';

    // Ortak format zenginlikleri — her iki katman için geçerli
    const richFormatBlock = '''
ZENGİN FORMAT (gerektiğinde KULLAN):
  • TABLO: Karşılaştırma/sınıflandırma gerektiren bilgiler için sade
    Markdown tablosu (örn. asit/baz, dönem akımları, formül-birim eşleşmesi).
  • ÖNEMLİ BİLGİ KUTUSU: Tuzak/istisna/uzman içgörüsü varsa
    "💡 Önemli Bilgi: …" satırı ekle (UI bunu vurgulu kutuda gösterir).
  • AKIŞ ŞEMASI: Karmaşık süreçleri (Fotosentez, Fransız İhtilali aşamaları,
    glikoliz vb.) → ok'lu maddelerle göster:  Adım 1 → Adım 2 → Adım 3.
  • GÖRSEL/ŞEKİL/GRAFİK ANLATIMI: Konuda bir şekil, diyagram, grafik,
    moleküler yapı, devre, harita ya da haritalanması gereken kavramsal
    şema varsa, bunu MUTLAKA betimle: hangi eksende ne, hangi parça ne
    işe yarar, hangi etiket nereye düşer — öğrenci görseli zihninde
    canlandırabilsin. Yalnız "şu grafikte görülür" deyip geçme; tüm
    parçaları açıkla.
  • FORMÜL DETAYI: Bir formül veriliyorsa her sembolün anlamı + birimi
    + tipik değer aralığı + ne durumda kullanılır mutlaka belirtilsin.
''';

    final formulasBlock = isNumeric
        ? '''
📐 FORMÜL KARTI GALERİSİ + 🧪 UYGULAMA ÖRNEĞİ

Her formül için ZORUNLU "FORMÜL KARTI" yapısı (bu yapıyı bozma):

🟢 **FORMÜL ADI** (örn: Newton'un 2. Yasası)
\\[ F = m \\cdot a \\]
📌 **Sembol Çözümü:**
| Sembol | Tanım | Birim | Tipik Değer |
|--------|-------|-------|-------------|
| F      | Kuvvet | N (Newton) | 1–10⁵ |
| m      | Kütle | kg | nesne kütlesi |
| a      | İvme | m/s² | g=9.81 (yer) |

🧠 **Şöyle Düşün:** Bir cisme ne kadar kuvvet uygularsan o kadar hızlanır;
   ama ağırsa daha az hızlanır. F doğru orantılı m'le, ters orantılı bu nedenle
   a = F/m olarak da yazılabilir.

🧪 **Uygulama Örneği:**
   2 kg bir cisme 10 N kuvvet uygulanırsa ivmesi nedir?
   ▸ Adım 1: F = 10 N, m = 2 kg → \\( a = F/m \\)
   ▸ Adım 2: \\( a = 10\\,\\mathrm{N} / 2\\,\\mathrm{kg} \\)
   ▸ Adım 3: \\( a = 5\\,\\mathrm{m/s^2} \\) ✓ (birim doğrulaması)

⚡ **Kısa Yol:** F=ma'da m sabitse F ile a doğru orantılı; F→2F olursa a→2a.
🔴 **Tuzak:** Sürtünme varsa "net kuvvet" hesaba kat: \\( F_{net} = F - F_s \\).

═══════════════════════════════════════

KURAL — Bu KART YAPISINI bozmadan en az 3 anahtar formül ver:
  • LaTeX ZORUNLU: \\( ... \\) veya \\[ ... \\]
  • Her sembol için **TABLO** (sembol/tanım/birim/tipik değer)
  • 🧠 Şöyle Düşün satırı (sezgisel mantık — 1-2 cümle)
  • 🧪 Uygulama Örneği (numaralı 2-4 adım, birim takibi)
  • ⚡ Kısa Yol veya 🔴 Tuzak (en az birini ver)
  • Türetilebilir formülde 1-2 adım türetim göster
  • Birim/boyut analizi en az 1 formülde açıkça yapılır

ÖZEL DURUMLAR:
  • Genetik: Aa × Aa → tablo ile (Punnett karesi: 1 AA | 2 Aa | 1 aa)
  • Biyokimya: \\( C_6H_{12}O_6 + 6O_2 \\to 6CO_2 + 6H_2O \\) tam denklemi
  • TAMLIK: istisnalar (\\( 0! = 1 \\)), uç durumlar (n=0, payda=0)
    mutlaka 🔴 veya ⚪ marker'ı ile vurgulanır
  • Ondalık virgül (3{,}14), bilim notasyonu LaTeX içinde
'''
        : isVerbal
            ? '''
DETAY VE SEBEP-SONUÇ AKIŞI (formüller yerine, ana başlık içinde)
Sözel branş — kuru ezber YERİNE detaylı bağlam ver:
  • Sebep → Sonuç zinciri (yıllarla, en az 4-6 ok'lu adım) — ana başlığın
    gövdesinde, AYRI BÖLÜM AÇMA.
  • Karmaşık süreçler için akış şeması mantığı:
      Adım 1 → Adım 2 → Adım 3 → Sonuç
    (örn. Fransız İhtilali aşamaları, Tanzimat süreci, fotosentez evreleri).
  • Felsefe ise: Argüman → Karşı argüman → Sentez.
  • Karşılaştırma/sınıflandırma için sade Markdown TABLO kullan
    (örn. dönem-akım-temsilci-eser; antlaşma-yıl-taraflar).
  • Görselle anlatılması daha verimli olan kavram (harita, kronolojik
    çizgi, kavramsal şema) varsa METİNLE betimle: ne nereye düşer,
    hangi öge neyi temsil eder.
  • LaTeX kullanma; düz metin maddeler.
'''
            : '''
📐 FORMÜLLER / DETAY (varsa)
Konu sayısalsa "🧪 Uygulama Örneği" ile hücreli anlat; sözelse sebep→sonuç
zinciri ver. Karşılaştırma için Markdown tablo serbest. Şekil/diyagram
varsa metinle betimle.
''';

    return '''
[KONU ÖZETİ — DERSHANE KİTABI TARZI]
Ders: $subject
Konu: $topic
Bağlam: $ctx

[AKADEMİK EDİTÖR — KATI FORMAT PROTOKOLÜ]
Sen bir akademik editörsün. Aşağıdaki 4 kural HARFİ HARFİNE uygulanır;
herhangi biri ihlal edilirse çıktı GEÇERSİZDİR.

1) GÖRSEL TEMİZLİK — HAM MARKDOWN YASAK:
   • Asla satır başında çıplak "#", "##", "###" yazma. Başlıkları sadece bu
     promptta tanımlı YAPI (📖, 📚, ▸ 1., 🟢 vb.) ile ver.
     Yanlış: "### Tanım"  /  Doğru: "📖 Tanım"
   • "**" sadece **anahtar terimleri** vurgulamak için kullan; süs olarak
     paragrafta serpiştirme. UI bold render eder; ancak fazla * → kirli görünür.
   • Tek "*" YASAK (italik render edilmiyor → metinde yıldız kalıyor).
     Vurgulamak istediğin kelime varsa **çift yıldız** kullan veya hiç kullanma.
   • "—" tek tireyle veya boşluksuz "-" KULLANMA; uzun tire (–) ya da
     "—" olarak boşluklu yaz: "Sembol — Tanım".
   • Satır başlarında "* maddeler" değil "• maddeler" kullan (kural format).

2) GELİŞMİŞ FORMÜL YAPISI — LATEX ZORUNLU:
   • Tüm matematiksel/fiziksel/kimyasal formüller LaTeX içinde verilir.
   • SATIR İÇİ formül: \\( ... \\)  → "ivme \\( a = F/m \\) olarak yazılır"
   • BAĞIMSIZ formül: \\[ ... \\]  → her zaman AYRI bir satırda, önce/sonra
     boş satır bırakılarak. Birden fazla denklem aynı satıra YAZILMAZ.
   • Birim/sayı LaTeX dışında değil İÇİNDE: \\( a = 5\\,\\mathrm{m/s^2} \\)
   • Düz metin "E = mc^2" YASAK — \\( E = mc^2 \\) ya da \\[ E = mc^2 \\] olur.
   • Kimyasal denklemler de LaTeX: \\( C_6H_{12}O_6 + 6O_2 \\to 6CO_2 + 6H_2O \\)

3) MANTIKSAL ÇÖZÜMLEME — ADIM 1 / ADIM 2 / ADIM 3 ZORUNLU:
   • Bir problem ya da çıkarım anlatırken sadece sonucu verme — **adımlandır**:
       Adım 1: [verilen / başlangıç durumu]
       Adım 2: [hangi yasa/kural/formül uygulandı + neden]
       Adım 3: [hesaplama veya çıkarım]
       Sonuç: [birim doğrulamasıyla birlikte]
   • Her adımda "neden" sorusunu da cevapla: "Newton'un 2. yasasını uyguluyoruz
     çünkü cisme net kuvvet etki ediyor." → bağlam olmadan adım atlama.
   • En az 1 örnek problem her sayısal konuda Adım 1-2-3 yapısıyla çözülür.
   • Sözel konularda "neden → nasıl → sonuç" zinciri aynı zorunluluk taşır.

4) ÇIKTI HEDEFİ — DERS KİTABI KALİTESİ:
   • Çıktı bir ders kitabı sayfasıdır: temiz, hiyerarşik, formülleri teknik
     olarak hatasız.
   • Boyut/birim hatası YASAK (\\( F = ma \\) için F→N, m→kg, a→m/s²).
   • Ondalık ayraç olarak Türkçe virgül LaTeX içinde "{,}" yazılır:
     \\( \\pi \\approx 3{,}14 \\). Düz metinde "3.14" değil "3,14".
   • Hiçbir bölümü "vb. detaylar..." gibi yarım bırakma; bilgi MUTLAKA
     somut sayı/yıl/isim/formülle desteklenir.

$protocolBlock
$richFormatBlock
GÖREVİN: Konuyu standart bir DERSHANE KİTABINDAKİ gibi işle. Önce kısa
tanım, ardından konuyu mantıksal ana başlıklara böl ve her ana başlığın
altında alt başlıkları/maddeleri ver — tıpkı bir ders kitabının
"konu işlenişi" sayfası gibi. Hedef: "Nihai Özet" kalitesi.

⚠️ ÇIKTI ZORUNLU OLARAK 4 BÖLÜMÜN HEPSİNİ İÇERİR (sırayla):
   1) 📖 Tanım
   2) 📚 Konu İşlenişi   ← ana başlıklar + alt maddeler (asla atlama)
   3) ${isNumeric ? '📐 Formül Galerisi + 🧪 Uygulama Örneği' : isVerbal ? '(Konu İşlenişi içine yedirilen detaylı sebep-sonuç akışı yeterli)' : '📐 Formül / Akış (varsa)'}
   4) ⭐ Özet — 5 Bilgi
HERHANGİ BİR BÖLÜM EKSİK OLURSA cevap GEÇERSİZDİR — özellikle "Konu
İşlenişi" sadece tanımdan sonra durup BİTİRME, mutlaka ana başlıklarla
devam et.

İlk satır "📖 Tanım" başlığı olmalıdır; öncesinde HİÇBİR selamlama
("Harika!", "Tabii ki", "Hemen başlayalım", "Bu konuyu inceleyelim") YOK.
Tanım satırından sonra DOĞRUDAN "📚 Konu İşlenişi" gelir, ardından diğer
bölümler — TÜM bölümler tamamlanana dek bitirme.

ÖZEL ÇERÇEVE YOK — "⚠️ KRİTİK UYARI / 🔬 QuAlsar Notu" diye AYRI bir bölüm
açma. Tuzak/istisna/uzman içgörüsü gerekiyorsa Konu İşlenişi içinde
"💡 Önemli Bilgi: ..." satırı olarak inline yedir (UI bunu kutuda gösterir).

YAPI (aşağıdaki başlıkları BİREBİR kullan — sırayla):

📖 Tanım
[TEK kısa cümle. Süsleme YOK, dolambaç YOK.]

📚 Konu İşlenişi
[Konunun doğal mantığına göre ${isNumeric ? '4-6' : '5-7'} ANA BAŞLIK belirle ve
 her ana başlığın altında ${isNumeric ? '4-7' : '5-8'} alt madde ver.
 Yapı, ders kitaplarındaki bir ünitenin DETAYLI işlenişi gibidir —
 yüzeysel kalmaz, ezberlenecek anahtar bilgileri spesifik isimler /
 yıllar / formüller / örneklerle besler.

   ▸ 1. {Konuyla uyumlu emoji} Başlık Adı
     • {emoji} **Anahtar Terim** — açıklama (tek cümle, somut bilgi)
     • {emoji} **Bir başka kavram** — yıl, isim, sayı veya formül içeren cümle
     • ...

   ▸ 2. {emoji} Başlık Adı
     • ...

 BAŞLIK FORMAT KURALLARI:
 • ANA BAŞLIK: "▸ N. {emoji} Başlık Adı" — N=1,2,3...; başlık önünde
   konuya uygun TEK emoji + Title Case başlık (sadece kelime başları
   büyük, TÜMÜ BÜYÜK YAZMA YASAK).
   Doğru: "▸ 1. 📍 Matematiksel ve Özel Konum"
          "▸ 2. ⛰️ Yeryüzü Şekilleri"
          "▸ 3. ⚔️ Savaşın Tarafları"
   Yanlış: "▸ 1. MATEMATIKSEL KONUM" / "▸ 1. matematiksel konum"
 • ALT MADDE: 2 boşluk girinti + "• {emoji} **Anahtar terim** — açıklama"
   - Anahtar terim **çift yıldız** ile (UI bold render eder).
   - Açıklamada SOMUT bilgi: yıl, sayı, isim, yer, formül, birim.
   - Tek cümle (8-22 kelime arası — yüzeysel değil, dolu olsun).

 ZENGİNLEŞTİRİCİ ÖGELER — TEMBELLİK YASAK, gerektiğinde MUTLAKA kullan:

 ▶ TABLO (KARŞILAŞTIRMA/SINIFLAMA İÇİN ZORUNLU):
   • Aşağıdaki durumlarda MUTLAKA Markdown tablosu kullan:
     - 2+ kavramın özelliklerini karşılaştırırken (Asit vs Baz, mitoz vs mayoz)
     - Sınıflandırma yaparken (canlı sınıflandırması, akım/dönem/temsilciler)
     - Formül-birim-değer eşleşmeleri (her satır: sembol | tanım | birim)
     - Tarihsel olaylar (yıl | olay | sonuç sütunları)
     - Bileşik özellikleri (renk, çözünürlük, pH vb.)
   • 2-4 sütun, 3-8 satır. İlk sütun KALIN (anahtar).
   • Tablo başlığı çok değerli olduğunda 1 cümle bağlam ver, sonra tablo.

 ▶ RENK KODLU SEKSİYON ROZETLERİ (her ana başlıkta TEK rozet):
   🔵 = TANIM/KAVRAM      — yeni bilgi tanıtımı
   🟢 = FORMÜL/KURAL       — sayısal ilişki, fizik yasası
   🟡 = ÖRNEK/UYGULAMA     — somut örnek, problem
   🟣 = TARİH/AKIM         — kronoloji, dönemsel bilgi
   🔴 = TUZAK/UYARI        — sınavda hata yaptıran ince nokta
   🟠 = SEBEP-SONUÇ        — neden→nasıl→sonuç zinciri
   ⚪ = İSTİSNA/UÇ DURUM   — kuralın geçersiz olduğu hâl
   Örn: "▸ 3. 🟢 Newton'un 2. Yasası" — F=ma'yı işliyorsa 🟢
        "▸ 4. 🔴 Sınav Tuzakları" — sık yapılan hatalar 🔴

 ▶ PEDAGOJİK İÇGÖRÜ MARKER'LARI (inline, paragraf ortasında):
   💡 Önemli Bilgi: ...     → vurgulu kutu (uzman içgörüsü)
   🎓 Püf Nokta: ...         → öğrencinin atlayacağı kritik detay
   ⚡ Kısa Yol: ...          → sınavda zaman kazandıran shortcut
   📦 Hatırlatma: ...        → mavi çerçeveli inline not
   🧠 Şöyle Düşün: ...       → mantık temelini sezgisel açıklama
   🔍 Dikkat: ...            → çeldirici / yanıltıcı seçenek uyarısı
   Hepsi tek satır + bir tane "..." içerikle. Birden fazla marker'ı
   üst üste KULLANMA — bilgi seyreltme yapar.

 ▶ ŞEKİL/GRAFİK/DİYAGRAM BETİMLEMESİ:
   Konuda diyagram, grafik, harita, moleküler yapı, devre vb. kavramsal
   şema varsa, parça parça METİNLE betimle:
     • Eksenler (x: zaman, y: hız)
     • Etiketler (her noktada ne yazıyor)
     • Renkli alanlar (mavi: katı, yeşil: gaz)
     • Hangi parça ne işe yarar
   Sadece "şu grafikte görülür" deyip GEÇME.

 ▶ AKIŞ ŞEMASI (süreç/aşama için):
   "Adım 1 → Adım 2 → Adım 3 → Sonuç" oklu zincir.
   Karmaşık süreçlerde dallanma:
     Reaktif → [hız belirleyen] → Aktif kompleks → Ürün
                                     ↓
                                 [yan ürün]

 ${isNumeric ? 'SAYISAL ÖZEL: Her ana başlıkta mümkünse 1 formül kutusu \\\\[ ... \\\\] '
        've altında "🧪 Uygulama Örneği:" ile 2-4 adımlık mini çözüm. Sembol+birim eksiksiz.' : ''}
 ${isVerbal ? 'SÖZEL ÖZEL: Tarih kronolojik akış (yıl→yıl); edebiyat dönem→akım→'
        'temsilci→eser→özellik silsilesi; felsefe kavram→argüman→eleştiri. '
        'Her ana başlıkta en az 1 spesifik tarih/yer/isim geçsin.' : ''}
 ${!isNumeric && !isVerbal ? 'KARMA: yapıyı konuya göre seç.' : ''}

 KAPSAM: Yüzeysel listeleme YASAK. Bir öğrenci bu özeti okuduğunda
 KONUYU TAMAMEN öğrenmiş olmalı; başka kaynağa ihtiyaç DUYMAMALI.]

$formulasBlock

⭐ Özet — 5 Bilgi
[Konunun en önemli 5 bilgisini DOĞRUDAN bilgi cümlesi olarak ver.
 META YORUM YASAK: "bunu bilmen önemli", "sınavda işine yarar",
 "akılda tut" gibi cümleler yazma. Sadece bilgi.

 Format — her satır başında BİLGİ TÜRÜNE GÖRE ikon, sonra DOĞRUDAN bilgi:
   🔑 = anahtar tanım/kavram
   📐 = formül/sayısal değer
   📅 = tarih/kronoloji
   🧬 = bilimsel olgu/yasa
   ⚖️ = ilke/kural
   🎯 = sınav-kritik bilgi
   🌍 = bağlam/yer/coğrafya

 Örnekler (her madde tek cümle, 8-20 kelime):
   📐 **Pisagor:** \\( a^2 + b^2 = c^2 \\), dik üçgenin hipotenüs ilişkisi.
   🧬 **DNA** çift sarmal yapıdadır; iki zincir antiparalel uzanır.
   📅 **Lozan Antlaşması** 24 Temmuz 1923'te imzalandı, 18 maddedir.
   ⚖️ **Newton'un 3. Yasası:** her etkiye eşit ve zıt bir tepki vardır.
   🎯 **YKS Tuzağı:** Mol kavramında Avogadro sayısı 6,022×10²³ — bunu unutma.

 ${isNumeric ? 'Sayısal: formül / sayısal değer / sembol + birim; mümkünse LaTeX kutu.' : ''}
 ${isVerbal ? 'Sözel: yıl / yazar-eser / kavram-tanım / sebep-sonuç çekirdeği.' : ''}
 TAM 5 madde, ne eksik ne fazla. İkonlar ÇEŞİTLİ olsun — hepsi 🔑 olmasın.
 Bu son bölümdür — sonrasına hiçbir şey yazma; "📌 Özetle" gibi kapanış
 paragrafı, "Sonuç:" başlığı, ek yorum YOK.]

═══════════════════════════════════════════════════════
KATI KURALLAR (bozarsan cevap geçersiz):
• ÇIKTI "📖 Tanım" satırıyla BAŞLAR. Öncesinde tek kelime selamlama,
  "Harika", "Tabii", "Hemen başlayalım", "Bu konuya bakalım" YASAK.
• "📚 Konu İşlenişi" bölümünde ana başlık → alt madde hiyerarşisi ZORUNLU.
• ⭐ Özet bölümünde "bunu bilmen önemli", "sınavda çıkar", "akılda tut" gibi
  meta yorum YASAK — sadece doğrudan bilgi cümleleri.
• Markdown bold (**metin**) SERBEST — UI bold render eder; sadece
  anahtar terimleri vurgulamak için kullan, paragraf süslemesi YOK.
• Markdown italic tek yıldız (*metin*) KULLANMA.
• Markdown başlık işareti (#) kullanma; tablo Markdown'u serbest.
• DOLAR işareti (\$) çıktıda HİÇ olmayacak.
  LaTeX için SADECE \\( ... \\) ve \\[ ... \\] kullan.
• Konu adını başlık olarak tekrar etme.
• "⚠️ KRİTİK UYARI / 🔬 QuAlsar Notu" diye AYRI BAŞLIK AÇMA — yasak.
  Tuzak/istisna/içgörü için sadece inline "💡 Önemli Bilgi: …" kullan.
• ⭐ Özet — 5 Bilgi bölümü ZORUNLU — tam 5 madde, 🔑 başlı; çıktının
  son bölümüdür, sonrasına hiçbir şey yazma.
• "📌 Özetle" / kapanış paragrafı / "Sonuç:" YASAK — ekleme.
• Toplam uzunluk ${isVerbal ? '70-110' : '60-95'} satır — derinlikli Nihai Özet, dolgu yok.
• Türkçe yaz. $exam mantığına uygun, ders kitabı işlenişine sadık.
• YouTube/Web/kaynak önerisi EKLEME. [VIDEO:] ve [WEB:] yok.
${isNumeric ? '• Her sayısal tanımda sembol + BİRİM birlikte verilsin (boyut analizi).' : ''}
${isVerbal ? '• Tarihte yıl, edebiyatta yazar/eser/dönem, felsefede filozof/akım adı eksiksiz.' : ''}
''';
  }

  // Markdown yıldızlarını temizle + giriş paragrafını kırp
  String _stripMarkdown(String s) {
    // **bold** KORUNUR (UI inline bold render eder).
    // Sadece tek-yıldız italic ve markdown başlıkları temizlenir.
    var out = s.replaceAllMapped(
      RegExp(r'(?<![\\\w*])\*([^*\n]+)\*(?!\w|\*)'),
      (m) => m.group(1) ?? '',
    );
    out = out
        .replaceAll('###', '')
        .replaceAll('##', '')
        .replaceAll('# ', '');
    // AI giriş cümlesi yazmışsa "📖 Tanım" / "📚" gibi ilk başlık satırından
    // önceki giriş paragrafını kırp.
    final firstHeader = RegExp(
      r'(📖[^\n]*|📚[^\n]*|🎯[^\n]*|📐[^\n]*|🌊[^\n]*|⭐[^\n]*|📌[^\n]*)',
    );
    final m = firstHeader.firstMatch(out);
    if (m != null && m.start > 0) {
      out = out.substring(m.start);
    }
    return out.trimLeft();
  }

  Future<void> _deleteSubject(_Subject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${s.name} — ${localeService.tr('delete_subject_confirm')}'),
        content: Text(localeService.tr('delete_subject_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(localeService.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(localeService.tr('delete'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _subjects.removeWhere((x) => x.id == s.id));
      await _persistSubjects();
    }
  }

  void _openSummary(_Summary s, String subjectName) {
    // Summary mode → özet detayı. Questions mode burada çağrılmaz;
    // o akışta ya _openTestAttempt ya da _openCompletedAttempt kullanılır.
    if (widget.mode == LibraryMode.questions) {
      // Geriye dönük uyumluluk: eski kod yolu. İlk tamamlanmamış attempt'i aç.
      final attempt = s.tests.firstWhere(
        (t) => !t.completed,
        orElse: () => s.tests.isNotEmpty
            ? s.tests.first
            : _TestAttempt(
                id: s.id,
                content: s.content,
                answers: {},
                completed: false,
                createdAt: s.createdAt,
              ),
      );
      if (attempt.completed) {
        _openCompletedAttempt(s, attempt, subjectName);
      } else {
        _openTestAttempt(s, attempt, subjectName);
      }
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _SummaryDetailPage(
          summary: s,
          subjectName: subjectName,
        ),
      ));
    }
  }

  // Yeni ya da devam ettirilen bir test açar. Bitince answers + completed
  // alanlarını saklar.
  void _openTestAttempt(
      _Summary summary, _TestAttempt attempt, String subjectName) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TestPage(
        rawContent: attempt.content,
        subjectName: subjectName,
        topic: summary.topic,
        initialAnswers: attempt.answers,
        timeLimit: attempt.timeLimit,
        onFinish: (answers) async {
          attempt.answers = Map<int, String?>.from(answers);
          attempt.completed = true;
          await _persistSubjects();
          if (mounted) setState(() {});
        },
      ),
    )).then((_) {
      if (mounted) setState(() {});
    });
  }

  // Tamamlanmış bir testin sonuç + çözüm ekranını açar.
  void _openCompletedAttempt(
      _Summary summary, _TestAttempt attempt, String subjectName) {
    final questions = parseTestQuestions(attempt.content);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TestResultPage(
        questions: questions,
        answers: attempt.answers,
        subjectName: subjectName,
        topic: summary.topic,
      ),
    ));
  }

  void _openSubject(_Subject s) {
    Navigator.of(context)
        .push<String>(MaterialPageRoute(
          builder: (_) => _SubjectDetailPage(
            subject: s,
            mode: widget.mode,
            // Planner'da bu ders kartı renklendirilmişse, açılan sayfa da
            // aynı zemin rengiyle başlasın — kayıtlı renk kalıcı kabul edilir.
            pageBg: _summaryCardColors[s.id],
            onAddTopic: (topic) =>
                _generateForExistingSubject(s, topic),
            onDelete: (sum) async {
              s.summaries.removeWhere((x) => x.id == sum.id);
              await _persistSubjects();
              if (mounted) setState(() {});
            },
            onAddAttempt: (summary, cfg) =>
                _generateAttemptForSummary(s, summary, config: cfg),
            onOpenAttempt: (summary, attempt) {
              if (attempt.completed) {
                _openCompletedAttempt(summary, attempt, s.name);
              } else {
                _openTestAttempt(summary, attempt, s.name);
              }
            },
          ),
        ))
        .then((result) {
      if (!mounted) return;
      setState(() {});
      // FAB'e basıldıysa `_openSubjectTopics` sinyali gelir → bu dersin
      // konular dialogunu aç (yeni konu seçmek için).
      if (result == '_openSubjectTopics') {
        final edu = _inlineEduSubjects.firstWhere(
          (e) => e.name.toLowerCase() == s.name.toLowerCase(),
          orElse: () => EduSubject(s.id, '📚', s.name, _blue),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openSubjectTopicsDialog(edu: edu);
        });
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // Hata mesajı + Tekrar Dene aksiyonu olan snack — AI çağrıları için.
  // En fazla 5 saniye ekranda kalır, sonra otomatik kaybolur.
  void _showRetrySnack(String msg, VoidCallback onRetry) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: 'Tekrar Dene'.tr(),
        textColor: const Color(0xFFFFB74D),
        onPressed: onRetry,
      ),
    ));
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Root Stack: loader çıkınca AppBar + sayfayı komple kapatsın.
    // Arka plan varsayılanı — kullanıcı palet üzerinden override edebilir.
    final pageBg = _pageBgOverride ?? const Color(0xFFDDE1E9);
    return Stack(
      children: [
        Scaffold(
          backgroundColor: pageBg,
          appBar: AppBar(
            backgroundColor: pageBg,
            elevation: 0,
            foregroundColor: Colors.black,
            // Sayfa başlığı kaldırıldı; sadece sağdaki Renk Seç + (?) kalır.
            titleSpacing: 0,
            title: const SizedBox.shrink(),
            actions: [
              // Renkli "🎨 Renk Seç" pill — sağ üstte belirgin.
              Padding(
                padding: const EdgeInsets.only(
                    top: 8, bottom: 8, left: 12, right: 6),
                child: GestureDetector(
                  onTap: () => setState(
                      () => _showColorPicker = !_showColorPicker),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF6A00), // turuncu
                          Color(0xFFDB2777), // pembe
                          Color(0xFF7C3AED), // mor
                          Color(0xFF2563EB), // mavi
                        ],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showColorPicker
                              ? Icons.close_rounded
                              : Icons.palette_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showColorPicker
                              ? 'Kapat'.tr()
                              : 'Renk Seç'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Sayfa rehberi (?) — Renk Seç pill'inin sağında, aynı hizada.
              Padding(
                padding: const EdgeInsets.only(
                    top: 8, bottom: 8, left: 0, right: 12),
                child: Center(child: _buildHelpButton()),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_showColorPicker) _buildColorPickerPanel(),
              Expanded(
                child: DragTarget<Color>(
                  onAcceptWithDetails: (d) =>
                      setState(() => _pageBgOverride = d.data),
                  builder: (ctx, cand, rej) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: _buildInlineAddPanel(),
                ),
                if (_subjects.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildCardsRow(),
                  ),
                const SizedBox(height: 22),
              ],
            ),
                  ),
                ),
              ),
              ],
            ),
          ),
        // "Diğer Dersler" overlay sheet — modal değil, üstteki ders
        // grid'i tıklanabilir kalır (sürükle-bırak için).
        if (_showOtherSheet) _buildOtherSheetOverlay(),
        // Loader her şeyin üstünde — AppBar + body'yi tamamen kaplar
        if (_generating)
          Positioned.fill(
            child: Material(
              color: Colors.white,
              child: QuAlsarNumericLoader(
                stages: buildGenStages(
                  subject: _generatingSubject,
                  topic: _generatingTopic,
                  isQuestions: widget.mode == LibraryMode.questions,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCardsRow() {
    // Her dersin kendi mini "sayfası" var — başlığın altında o dersin TÜM
    // konu özetleri/testleri listelenir. Sayfalar 3 sütunda Wrap ile dizilir;
    // 4+ ders olduğunda alt satıra (soldan başlayarak) sarar.
    final shown = _subjects.where((s) => s.summaries.isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const cols = _cardSlots; // 3
        const spacing = 10.0;
        final cellWidth =
            (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final s in shown)
              SizedBox(
                width: cellWidth,
                child: _subjectPageTile(s),
              ),
          ],
        );
      },
    );
  }

  // Bir dersin "sayfası" — başlık + alt alta tüm konu özetleri (testler).
  // Çerçeve SABİT BOYUT: yatay 3 / dikey 5 oran (aspectRatio = 0.6) — kaç
  // konu olursa olsun tüm sayfalar aynı görünür; içerik fazlaysa konu
  // listesi tile içinde dikey kaydırılır.
  Widget _subjectPageTile(_Subject s) {
    final isQuestions = widget.mode == LibraryMode.questions;
    final custom = _summaryCardColors[s.id];
    final bg = custom ?? Colors.white;
    final lum = (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b);
    final isDark = lum < 0.55;
    final ink = isDark ? Colors.white : Colors.black;
    final inkMute = isDark ? Colors.white70 : Colors.black54;
    final divider = isDark ? Colors.white24 : Colors.black12;
    return DragTarget<Color>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) =>
          _applyColorToSummaryCard(s.id, d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        return AspectRatio(
          aspectRatio: 3 / 5, // yatay 3 : dikey 5
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hovering ? _orange : Colors.black12,
                width: hovering ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            // TÜM tile tıklanabilir — header'a, divider'a, boş alana
            // basılınca dersin liste detay sayfası açılır. Konu satırları
            // kendi InkWell'lerini taşıdığı için inner tap onlara gider.
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openSubject(s),
                onLongPress: () => _deleteSubject(s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: ink,
                                height: 1.1,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 16,
                              color: ink.withValues(alpha: 0.55)),
                        ],
                      ),
                    ),
                    Container(height: 1, color: divider),
                    // ── Konu özetleri listesi — kalan alanı doldurur, fazla
                    //    içerik kaydırılabilir. Tile her zaman aynı boyut.
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        physics: const ClampingScrollPhysics(),
                        children: [
                          for (final sum in s.summaries)
                            _topicSummaryRow(
                                s, sum, isQuestions, ink, inkMute),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Tek bir konu satırı — özet adına bas → o özet açılır
  // (test modunda son denemeyi açar). Uzun bas → o özeti sil.
  Widget _topicSummaryRow(
    _Subject s,
    _Summary sum,
    bool isQuestions,
    Color ink,
    Color inkMute,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (isQuestions) {
            // Son attempt'ı aç — _openSummary mantığı zaten bu fallback'i yapıyor
            _openSummary(sum, s.name);
          } else {
            _openSummary(sum, s.name);
          }
        },
        onLongPress: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(sum.topic,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
              content: Text(
                isQuestions
                    ? 'Bu test setini silmek ister misin?'.tr()
                    : 'Bu özeti silmek ister misin?'.tr(),
                style: GoogleFonts.poppins(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('İptal'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text('Sil'.tr(),
                      style: const TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (ok != true || !mounted) return;
          setState(() {
            s.summaries.removeWhere((x) => x.id == sum.id);
          });
          await _persistSubjects();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 4),
                child: Text(
                  '•',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  sum.topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: inkMute,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══ Sayfa rehberi (?) — Renk Seç pill'inin altında küçük yuvarlak buton.
  //   Basınca sayfanın nasıl çalıştığını anlatan dialog açılır.
  Widget _buildHelpButton() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _showHelpDialog,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: const Icon(
            Icons.question_mark_rounded,
            size: 16,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    final isQuestions = widget.mode == LibraryMode.questions;
    final pageLabel = isQuestions
        ? 'Sınav Soruları'.tr()
        : 'Konu Özetleri'.tr();
    final outputWord = isQuestions ? 'test sorularını' : 'özetini';
    final limitLine = isQuestions
        ? 'Her dersin her konusu için en fazla 3 test hakkın var. 3. denemen bittikten sonra aynı konudan yeni test üretemezsin; başka bir konu seçebilirsin.'
        : 'Bir ay içinde aynı dersten en fazla 4 konu özeti çıkarabilirsin. Limit dolduğunda bekle, yeni ay başında sayaç sıfırlanır. İstediğin kadar farklı dersle çalışabilirsin — toplam ders sayısı sınırsız.';
    final steps = <(String, String, String)>[
      (
        '1',
        'Ders seç'.tr(),
        'Üstteki çerçevede tüm derslerin listelenir. Bir derse basarak o dersin müfredat konuları açılır. İstediğin dersten ${outputWord.replaceAll('ını', 'ı')} çıkarabilirsin — ders sayısı limitsiz.'
            .tr(),
      ),
      (
        '2',
        'Dersleri sıralarken sürükle-bırak'.tr(),
        'Bir derse PARMAĞINI BASILI TUT, sürükleyip başka bir dersin üzerine bırak — iki dersin yeri yer değiştirir. Sıralaman cihazına kayıtlı kalır.'
            .tr(),
      ),
      (
        '3',
        'Konu seç veya kendin yaz'.tr(),
        'Açılan ekranda müfredat konuları listelenir. Bir konuya basınca AI o konunun ${isQuestions ? "test sorularını" : "özetini"} oluşturur. Konu listede yoksa, alttaki "Yeni Konu Ekle" alanına başlığı yazıp Kaydet\'e bas — kendi konunun $outputWord aynı kalitede üretilir.'
            .tr(),
      ),
      (
        '4',
        '${isQuestions ? "Test" : "Özet"} kütüphanen — her dersin kendi sayfası'.tr(),
        '${isQuestions ? "Test soruları" : "Özet"} oluşturduğun her ders, sayfanın altında KENDİ MİNİ SAYFASINI alır. Sayfalar 3\'lü grid hâlinde dizilir; 4. dersi eklediğinde yeni satıra (soldan başlayarak) sarar. Her sayfada ders adının altında o derse ait TÜM ${isQuestions ? "test denemeleri" : "konu özetleri"} alt alta listelenir. Bir konuya basınca doğrudan o ${isQuestions ? "test denemesine" : "özete"} gidersin; ders başlığına basarsan tüm liste detayını açan ders sayfasına ulaşırsın.'
            .tr(),
      ),
      (
        '5',
        'Aylık limit'.tr(),
        limitLine.tr(),
      ),
      (
        '6',
        'Renk Seç paleti — sayfayı kişiselleştir'.tr(),
        'Sağ üstteki renkli "Renk Seç" pill\'ine bas — palet açılır. 3 hedef arasından seç (Arka plan / Çerçeve / Ders alanı) ve modu belirle (Yazı rengi mi, Çerçeve/zemin rengi mi). Sonra paletten bir rengi PARMAĞINLA SÜRÜKLEYİP istediğin alana bırak — anında uygulanır. Tek bir ders sayfasına ya da manuel ders çerçevesine renk sürükleyerek özel renk de verebilirsin.'
            .tr(),
      ),
      (
        '7',
        'Uzun basma kısayolları'.tr(),
        'Bir ders sayfasının BAŞLIĞINA uzun bas → o dersi tamamen silebilirsin. Sayfa içindeki bir ${isQuestions ? "test" : "özet"} satırına uzun bas → o ${isQuestions ? "testi" : "özeti"} silme onayı çıkar. Kendi eklediğin özel bir derse (üstteki ders ızgarasında) uzun bas → dersi listeden kaldırabilirsin.'
            .tr(),
      ),
      if (!isQuestions)
        (
          '8',
          'Özet ekranını da renklendirebilirsin'.tr(),
          'Bir özete girince, içerideki ekran da kendi renk paletine sahip — başlık çerçevesi, kart zemini ve yazı rengini bağımsız değiştirebilirsin. Her özet kendi ayarlarını saklar.'
              .tr(),
        ),
    ];
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      child: const Icon(
                        Icons.question_mark_rounded,
                        size: 18,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$pageLabel — ${'Bu sayfa nasıl çalışır?'.tr()}',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(ctx).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded,
                              size: 18, color: Colors.black54),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: Colors.black12),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < steps.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _helpStep(steps[i].$1, steps[i].$2, steps[i].$3),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Anladım'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _helpStep(String n, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black,
          ),
          child: Text(
            n,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _unusedQuestionsSubjectSection(_Subject subject) {
    final customBg = _summaryCardColors[subject.id];
    final bg = customBg ?? Colors.white;
    final lum = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    final ink = lum < 0.55 ? Colors.white : Colors.black;
    final allAttempts = <_AttemptRef>[];
    for (final sum in subject.summaries) {
      for (var i = 0; i < sum.tests.length; i++) {
        allAttempts.add(_AttemptRef(
          summary: sum,
          attempt: sum.tests[i],
          attemptIndex: i + 1,
        ));
      }
    }
    allAttempts.sort((a, b) =>
        b.attempt.createdAt.compareTo(a.attempt.createdAt));
    return DragTarget<Color>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) =>
          _applyColorToSummaryCard(subject.id, d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hovering ? _orange : Colors.black,
              width: hovering ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık — ders ismi
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subject.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: ink,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                  Text(
                    '${allAttempts.length} ${'test'.tr()}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ink.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(height: 1, color: ink.withValues(alpha: 0.2)),
              const SizedBox(height: 8),
              for (final ref in allAttempts)
                _unusedTestAttemptRow(subject, ref, ink),
            ],
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _unusedTestAttemptRow(
      _Subject subject, _AttemptRef ref, Color ink) {
    final attempt = ref.attempt;
    final completed = attempt.completed;
    // Skor hesabı — tamamlandıysa parse et.
    String statusText;
    Color statusColor;
    if (completed) {
      try {
        final questions = parseTestQuestions(attempt.content);
        if (questions.isEmpty) {
          statusText = 'Tamamlandı'.tr();
          statusColor = const Color(0xFF10B981);
        } else {
          var correct = 0;
          for (var i = 0; i < questions.length; i++) {
            final userAns = attempt.answers[i];
            if (userAns != null &&
                userAns.toUpperCase() == questions[i].ans) {
              correct++;
            }
          }
          final pct = (correct / questions.length * 100).round();
          statusText = '%$pct';
          statusColor = pct >= 70
              ? const Color(0xFF10B981)
              : pct >= 40
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFDC2626);
        }
      } catch (_) {
        statusText = 'Tamamlandı'.tr();
        statusColor = const Color(0xFF10B981);
      }
    } else {
      // Cevap var mı? Varsa "Devam et", yoksa "Başla"
      if (attempt.answers.isNotEmpty) {
        statusText = 'Devam et'.tr();
        statusColor = _orange;
      } else {
        statusText = 'Başla'.tr();
        statusColor = _blue;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: () {
          if (completed) {
            _openCompletedAttempt(ref.summary, attempt, subject.name);
          } else {
            _openTestAttempt(ref.summary, attempt, subject.name);
          }
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: ink.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ink.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.quiz_rounded,
                    size: 16, color: _orange),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.summary.topic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${ref.attemptIndex}. ${'Deneme'.tr()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: ink.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: ink.withValues(alpha: 0.55)),
            ],
          ),
        ),
      ),
    );
  }


  // Loader için aşama listesi — konuyu cümleye yedirir, 3 satır birikimli.
  // Test ve özet için ayrı şablon; konu boşsa "Bu konu" fallback'i.
  static List<String> buildGenStages({
    required String subject,
    required String topic,
    required bool isQuestions,
  }) {
    final t = topic.trim().isEmpty ? 'Konu' : topic.trim();
    if (isQuestions) {
      return [
        '$t analiz ediliyor',
        '$t için sorular hazırlanıyor',
        'Neredeyse hazır',
      ];
    }
    return [
      '$t analiz ediliyor',
      '$t konusu özetleniyor',
      'Neredeyse hazır',
    ];
  }

  // Her kelimenin baş harfini büyütür. Türkçe "i" → "İ", "ı" → "I" özel
  // dönüşümü doğru çalışsın diye küçük "i"yi açıkça ele alır.
  String _toTitleCase(String s) {
    return s.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return w;
      final first = w[0];
      String upper;
      if (first == 'i') {
        upper = 'İ';
      } else if (first == 'ı') {
        upper = 'I';
      } else {
        upper = first.toUpperCase();
      }
      return '$upper${w.substring(1)}';
    }).join(' ');
  }

  Widget _buildInlineAddPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ═══ Çerçevenin ÜSTÜ — yalnız başlık pill'i (Title Case, siyah).
        //    Eğitim seviyesi ve hak sayacı kaldırıldı; başlık tam genişlikte
        //    görünür, kırpılmaz.
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.black, width: 1.2),
            ),
            child: Text(
              _toTitleCase(_headline),
              maxLines: 2,
              softWrap: true,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                height: 1.2,
              ),
            ),
          ),
        ),
        // ═══ Çerçeve — yalnız ders kareleri (iç başlık kaldırıldı) ═══
        DragTarget<Color>(
          onWillAcceptWithDetails: (_) =>
              _colorTarget == 'frame' || _showColorPicker,
          onAcceptWithDetails: (d) => _applyColorTo('frame', d.data),
          builder: (ctx, cand, _) {
            final hovering = cand.isNotEmpty;
            return Container(
              decoration: BoxDecoration(
                color: _frameOverride ?? Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: hovering ? _orange : Colors.black,
                  width: hovering ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: _buildInlineSubjectGrid(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInlineSubjectGrid() {
    if (_inlineEduSubjects.isEmpty) {
      // Profile yoksa "Yükleniyor…" yerine kullanıcıyı yönlendir — eğitim
      // profili olmadan müfredat üretilemiyor.
      final hasProfile = _inlineProfile != null;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasProfile)
              Text('Yükleniyor…'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade600))
            else ...[
              const Icon(Icons.school_rounded,
                  size: 28, color: Colors.black54),
              const SizedBox(height: 8),
              Text(
                'Eğitim profilini ayarla'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Konu özeti üretmek için önce sınıf/seviye/alanını seçmen gerekir.'
                    .tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.black54,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EducationSetupScreen(
                      trialEntryNumber: 1,
                      onSaved: () => Navigator.of(context).maybePop(),
                    ),
                  ));
                  // Profil set edildikten sonra inline grid'i yeniden yükle
                  final p = await EduProfile.load();
                  if (!mounted) return;
                  setState(() {
                    _inlineProfile = p;
                    _inlineEduSubjects = _subjectsForProfileAllTracks(p);
                  });
                  _loadSubjectOrder();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Profili Aç'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }
    // İlk 12 ders burada (3x4 ızgara); kalanlar alt "Diğer Dersler" sheet'inde
    final visible = _inlineEduSubjects.take(12).toList();
    // "Diğer Dersler" sheet'ine geçiş koşulu: ister müfredat 13+, ister
    // manuel ders 5+ olsun.
    final hasMore = _inlineEduSubjects.length > 12 || _customSubjects.length > 4;
    // Kullanıcının eklediği özel dersler her zaman görünür (en sonda).
    // Manuel ders çerçevesinde sadece ilk 4 görünür; fazlası "Diğer
    // Dersler" sheet'inde listelenir.
    final customVisible = _customSubjects.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Ders ızgarası — TAM 12 hücre (3 satır × 4) — son satırda yalnız
        //    1 hücre kalmasın diye "+ Yeni Ders Ekle" grid'in DIŞINA alındı.
        GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final s in visible) _subjectGridTile(s),
          ],
        ),
        // ── "Yeni Ders Ekle" — tam genişlikte buton, grid altında.
        const SizedBox(height: 10),
        _wideAddSubjectButton(),
        if (customVisible.isNotEmpty) ...[
          const SizedBox(height: 12),
          _customSubjectsFrame(customVisible),
        ],
        if (hasMore) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _openOtherSubjectsSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📚', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Text(
                    'Diğer Dersler'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Tam genişlikte "+ Yeni Ders Ekle" butonu — grid'in altında.
  /// `_addSubjectTile()` (kare grid hücresi) kaldırıldı; yerine bu kullanılır.
  Widget _wideAddSubjectButton() {
    return GestureDetector(
      onTap: _openAddCustomSubjectDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: _orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _orange.withValues(alpha: 0.55), width: 1.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: _orange),
            const SizedBox(width: 6),
            Text(
              'Yeni Ders Ekle'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subjectGridTile(EduSubject s) {
    final custom = _subjectTileColors[s.key];
    final bgColor = custom ?? Colors.white;
    final lum = (0.299 * bgColor.r +
        0.587 * bgColor.g +
        0.114 * bgColor.b);
    final isDark = lum < 0.55;
    final customText = _subjectTileTextColors[s.key];
    final fg = customText ?? (isDark ? Colors.white : Colors.black);

    Widget tile(bool hovering) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          // Çerçeve çizgisi yok — yalnızca hover/drag'de turuncu vurgu.
          // Normal durumda hafif gölgeyle zeminden ayrışır.
          border: hovering
              ? Border.all(color: _orange, width: 2.4)
              : null,
          boxShadow: hovering
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(s.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 3),
            // Uzun ders adlarında otomatik küçülerek kart içine sığar
            // (örn. "Elektrik-Elektronik Mühendisliği"). Kısa adlar 10pt'te kalır.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Üç katmanlı: dış DragTarget<String> (ders swap), iç DragTarget<Color>
    // (renk uygula), en içte LongPressDraggable<String> (basılı tut sürükle).
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != s.key,
      onAcceptWithDetails: (d) => _swapSubjects(d.data, s.key),
      builder: (ctx, swapCand, _) {
        return DragTarget<Color>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (d) => _applyColorToTile(s.key, d.data),
          builder: (ctx2, colorCand, _) {
            final hovering = swapCand.isNotEmpty || colorCand.isNotEmpty;
            return LongPressDraggable<String>(
              data: s.key,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: tile(false),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: tile(false),
              ),
              child: GestureDetector(
                onTap: _showColorPicker
                    ? null
                    : () => _openSubjectTopicsDialog(edu: s),
                child: tile(hovering),
              ),
            );
          },
        );
      },
    );
  }

  /// Kullanıcının eklediği özel ders kartı.
  /// Tıklandığında o dersin konuları (statik/AI) gösterilir.
  /// Uzun basıldığında silinir.
  Widget _customSubjectGridTile(EduSubject s) {
    final custom = _subjectTileColors[s.key];
    final bgColor = custom ?? Colors.white;
    final lum =
        (0.299 * bgColor.r + 0.587 * bgColor.g + 0.114 * bgColor.b);
    final isDark = lum < 0.55;
    final customText = _subjectTileTextColors[s.key];
    final fg = customText ?? (isDark ? Colors.white : Colors.black);
    return GestureDetector(
      onTap: _showColorPicker
          ? null
          : () => _openSubjectTopicsDialog(edu: s),
      onLongPress: () => _confirmDeleteCustomSubject(s),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(s.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 3),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Manuel olarak eklenen ders kareleri için ayrı, fütüristik & renklendirilebilir
  /// çerçeve. `DragTarget<Color>` — kullanıcı paletten istediği rengi sürükleyip
  /// buraya bırakırsa çerçeve zemini o renge boyanır.
  Widget _customSubjectsFrame(List<EduSubject> customs) {
    return DragTarget<Color>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) {
        setState(() => _customFrameOverride = d.data);
        _saveColorPrefs();
      },
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        final hasOverride = _customFrameOverride != null;
        // Override yoksa fütüristik gradient kenarlık; varsa düz ince siyah
        // kenarlık + override zemini.
        final innerBg = _customFrameOverride ?? Colors.white;
        final lum = 0.299 * innerBg.r + 0.587 * innerBg.g + 0.114 * innerBg.b;
        final isDark = lum < 0.55;
        final labelColor = isDark ? Colors.white : Colors.black87;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED)
                    .withValues(alpha: hovering ? 0.30 : 0.14),
                blurRadius: hovering ? 18 : 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF22D3EE).withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(1.3),
              decoration: BoxDecoration(
                gradient: hasOverride
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFF6A00),
                          Color(0xFFDB2777),
                          Color(0xFF7C3AED),
                          Color(0xFF22D3EE),
                        ],
                      ),
                color: hasOverride ? Colors.black : null,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(14.7),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 6),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 12, color: labelColor),
                          const SizedBox(width: 4),
                          Text(
                            'Eklediğin Dersler'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: labelColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.0,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (final s in customs) _customSubjectGridTile(s),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// "+ Yeni Ders Ekle" karesi — grid'in en sonunda durur.
  // _addSubjectTile() kaldırıldı — artık _wideAddSubjectButton tam genişlikte
  // grid altında gösteriliyor. Kullanıcı "+ Yeni Ders Ekle"'ye basınca aynı
  // _openAddCustomSubjectDialog akışı çalışır.

  Future<void> _openAddCustomSubjectDialog() async {
    final result = await showModalBottomSheet<_NewCustomSubjectResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCustomSubjectSheet(
        existingNames: [
          ..._inlineEduSubjects.map((s) => s.name),
          ..._customSubjects.map((s) => s.name),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final exists = [
      ..._inlineEduSubjects,
      ..._customSubjects,
    ].any((s) => s.name.toLowerCase() == result.name.toLowerCase());
    if (exists) {
      _showSnack('Bu ders zaten listede.'.tr());
      return;
    }
    final key = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _customSubjects.add(EduSubject(key, result.emoji, result.name, _blue));
    });
    await _saveCustomSubjects();
  }

  Future<void> _confirmDeleteCustomSubject(EduSubject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.emoji} ${s.name}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
        content: Text(
          'Bu dersi listeden kaldırmak ister misin?'.tr(),
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('İptal'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Sil'.tr(),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _customSubjects.removeWhere((x) => x.key == s.key);
    });
    _saveCustomSubjects();
  }

  /// 8'in üstündeki müfredat dersleri + 4'ün üstündeki manuel dersleri
  /// listeleyen bottom sheet.
  Future<void> _openOtherSubjectsSheet() async {
    final overflowCurr = _inlineEduSubjects.skip(8).toList();
    final overflowCustom = _customSubjects.skip(4).toList();
    if (overflowCurr.isEmpty && overflowCustom.isEmpty) return;
    setState(() => _showOtherSheet = true);
  }

  void _closeOtherSheet() {
    if (_showOtherSheet) {
      setState(() {
        _showOtherSheet = false;
        _draggingFromSheet = false;
      });
    }
  }

  // Overlay sheet — modal değil, arka plandaki top-8 grid tıklanabilir kalır.
  Widget _buildOtherSheetOverlay() {
    // Müfredat dersleri 9+ ve manuel dersler 5+ aynı sheet'te toplanır.
    final overflowCurr = _inlineEduSubjects.skip(8).toList();
    final overflowCustom = _customSubjects.skip(4).toList();
    final overflow = [...overflowCurr, ...overflowCustom];
    if (overflow.isEmpty) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    final sheetHeight = mq.size.height * 0.55;
    return Stack(
      children: [
        // Sürükleme aktifken hafif şeffaf — kullanıcı arkayı görsün.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedOpacity(
            opacity: _draggingFromSheet ? 0.30 : 1.0,
            duration: const Duration(milliseconds: 180),
            // Material sarmalı: Text widget'larındaki sarı debug
            // alt çizgilerini önler (Material context sağlar).
            child: Material(
              type: MaterialType.transparency,
              child: Container(
              height: sheetHeight,
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFA),
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 30),
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _closeOtherSheet,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(
                                color: Colors.black12),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Başlık + ipucu pill
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Diğer Dersler'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      // Sağ üstte küçük, çerçevesiz, soluk (flu) ipucu —
                      // iki satıra sığacak kadar dar.
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 130),
                        child: Opacity(
                          opacity: 0.85,
                          child: Text(
                            'Derslere basılı tut,\nsürükle, yerini değiştir'
                                .tr(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.0,
                      children: [
                        for (final s in overflow)
                          _OverflowSubjectTile(
                            subject: s,
                            bgColor: _subjectTileColors[s.key],
                            textColor: _subjectTileTextColors[s.key],
                            onTap: () {
                              _closeOtherSheet();
                              _openSubjectTopicsDialog(edu: s);
                            },
                            onDragStarted: () {
                              setState(() =>
                                  _draggingFromSheet = true);
                            },
                            onDragEnd: () {
                              setState(() =>
                                  _draggingFromSheet = false);
                            },
                            onAcceptSwap: (draggedKey) =>
                                _swapSubjects(draggedKey, s.key),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  Ders seçim modali — sol: konu sekmeleri, sağ: özet durumu, alt: yeni
  //  konu ekleme. `edu` ile seçilir (grid) veya `customName` (kendim yazayım).
  // ═════════════════════════════════════════════════════════════════════════
  /// Profil'in country+level+grade kombinasyonu için TÜM track'lerden
  /// subjectKey veya subjectName ile eşleşen dersin konularını UNION'la topla.
  /// Bu sayede kullanıcı hangi alanı seçmiş olursa olsun, hangi derse tıklarsa
  /// o dersin tüm konuları gösterilir.
  List<String> _topicsForSubjectAllTracks({
    required EduProfile? profile,
    String? subjectKey,
    required String subjectName,
  }) {
    bool matches(CurriculumSubject c) {
      final sName = subjectName.toLowerCase();
      final cName = c.displayName.toLowerCase();
      if (subjectKey != null && c.key == subjectKey) return true;
      if (cName == sName) return true;
      return cName.contains(sName) || sName.contains(cName);
    }

    final seen = <String>{};
    final collected = <String>[];

    void addFrom(EduProfile p) {
      for (final c in curriculumFor(p)) {
        if (!matches(c)) continue;
        for (final t in c.topics) {
          final k = t.trim().toLowerCase();
          if (k.isEmpty) continue;
          if (seen.add(k)) collected.add(t);
        }
      }
    }

    if (profile != null) {
      addFrom(profile);
      // Tüm bilinen track varyasyonlarını da tara
      const knownTracks = <String>[
        'sayisal', 'esit_agirlik', 'sozel', 'dil',
        'lixue', 'wenxue',
        'jayeon', 'insa',
        'ipa', 'ips',
        'science', 'commerce', 'arts',
        'stem', 'abm', 'humss',
        'sciences', 'humanities',
      ];
      for (final t in knownTracks) {
        if (profile.track == t) continue;
        addFrom(EduProfile(
          country: profile.country,
          level: profile.level,
          grade: profile.grade,
          track: t,
          faculty: profile.faculty,
        ));
      }
      // Track'siz genel fallback
      addFrom(EduProfile(
        country: profile.country,
        level: profile.level,
        grade: profile.grade,
        track: null,
        faculty: profile.faculty,
      ));
    } else {
      addFrom(EduProfile(
        country: 'international',
        level: 'high',
        grade: '11',
      ));
    }
    return collected;
  }

  Future<void> _openSubjectTopicsDialog({
    EduSubject? edu,
    String? customName,
    String? customEmoji,
  }) async {
    final subjectName = edu?.name ?? customName ?? '';
    final subjectEmoji = edu?.emoji ?? customEmoji ?? '📚';
    final subjectColor = edu?.color ?? _blue;
    if (subjectName.isEmpty) return;

    // Curriculum'dan bu dersin konuları (ülke+sınıf+alan'a göre)
    // Dersi ülke+sınıf için TÜM alan (track) varyasyonlarından topla,
    // böylece profil 'eşit ağırlık' seçili olsa bile matematik/fizik/
    // biyoloji vb. hangi ders tıklandıysa o dersin konuları çıkar.
    var topics = _topicsForSubjectAllTracks(
      profile: _inlineProfile,
      subjectKey: edu?.key,
      subjectName: subjectName,
    );

    // Statik müfredat bu ders için konu vermediyse (örn. AI-generated bir
    // bölüm dersi: Anatomi, Arkeoloji, Veri Bilimi vb.) → önce offline pack
    // cache'i, sonra AI'ya canlı sor; konuları doldur.
    if (topics.isEmpty && _inlineProfile != null && edu != null) {
      final cached = await OfflineDownloadController.readPack(
        profile: _inlineProfile!,
        subjectKey: edu.key,
      );
      if (cached != null && cached.topics.isNotEmpty) {
        topics = cached.topics.map((t) => t.name).toList();
      } else {
        // Yükleme overlay'i — dialog açıkken AI'dan getirebilirdik ama
        // dialog daha açılmadığından küçük bir snackbar yeterli.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text('Konular hazırlanıyor…'),
                ],
              ),
              duration: const Duration(seconds: 30),
            ),
          );
        }
        try {
          final pairs = await GeminiService.fetchSubjectTopicPack(
            subjectName: subjectName,
            profile: _inlineProfile!,
          );
          topics = pairs
              .map((m) => m['name'] ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          // Pack'i cache'le → bir sonraki açılış anında olsun.
          if (pairs.isNotEmpty) {
            // OfflineDownloadController'ın savePack helper'ı yok; doğrudan
            // SharedPreferences üzerinden offline pack key'ine yaz.
            final pack = OfflineSubjectPack(
              subjectKey: edu.key,
              subjectName: subjectName,
              emoji: edu.emoji,
              topics: pairs
                  .map((p) => OfflineTopic(
                        name: p['name'] ?? '',
                        summary: p['summary'] ?? '',
                      ))
                  .toList(),
              cachedAt: DateTime.now(),
            );
            try {
              final prefs = await SharedPreferences.getInstance();
              final p = _inlineProfile!;
              final key = 'offline_pack_v1::'
                  '${p.country}_${p.level}_${p.grade}_'
                  '${p.faculty ?? ""}_${p.track ?? ""}::${edu.key}';
              await prefs.setString(key, pack.encode());
            } catch (_) {}
          }
        } catch (_) {
          // Sessizce başarısız → kullanıcı kendi konusunu yazabilir.
        }
        if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _SubjectTopicsDialog(
        subjectName: subjectName,
        subjectEmoji: subjectEmoji,
        subjectColor: subjectColor,
        profileLabel: _inlineProfile?.displayLabel() ?? '',
        curriculumTopics: topics,
        mode: widget.mode,
        getExistingSubject: () {
          final target = _normSubjectName(subjectName);
          return _subjects.firstWhere(
            (x) => _normSubjectName(x.name) == target,
            orElse: () => _Subject(
              id: '',
              name: subjectName,
              summaries: [],
            ),
          );
        },
        onGenerateTopic: (topic) async {
          Navigator.of(ctx).pop();
          await _runGenerateWithSetup(subjectName: subjectName, topic: topic);
        },
        onOpenExistingSummary: (summary) {
          Navigator.of(ctx).pop();
          _openSummary(summary, subjectName);
        },
        onAddCustomTopic: (topic) async {
          Navigator.of(ctx).pop();
          await _runGenerateWithSetup(subjectName: subjectName, topic: topic);
        },
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
//  _AddCustomSubjectSheet — "Yeni Ders Ekle" modal sheet'i.
//  Controller lifecycle bu sheet'in State'ine bağlı (parent rebuild olsa
//  da dialog güvenli kalır). Klavye safe-aware (viewInsets).
// ═══════════════════════════════════════════════════════════════════════════
class _NewCustomSubjectResult {
  final String name;
  final String emoji;
  const _NewCustomSubjectResult({required this.name, required this.emoji});
}

class _AddCustomSubjectSheet extends StatefulWidget {
  final List<String> existingNames;
  const _AddCustomSubjectSheet({required this.existingNames});

  @override
  State<_AddCustomSubjectSheet> createState() =>
      _AddCustomSubjectSheetState();
}

class _AddCustomSubjectSheetState extends State<_AddCustomSubjectSheet> {
  final _nameCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final emoji = _emojiCtrl.text.trim().isEmpty
        ? '📚'
        : _emojiCtrl.text.trim();
    Navigator.of(context).pop(
      _NewCustomSubjectResult(name: name, emoji: emoji),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Yeni Ders Ekle'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                cursorColor: Colors.black,
                decoration: _inputDec('Ders adı'.tr()),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emojiCtrl,
                maxLength: 4,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                cursorColor: Colors.black,
                decoration: _inputDec('Emoji (opsiyonel, örn. 🧠)'.tr())
                    .copyWith(counterText: ''),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'İptal'.tr(),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _submit,
                    child: Text(
                      'Ekle'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Bottom Sheet: Yeni Ders (ders + ilk konu) — eski tasarım, geriye uyum.
// ═══════════════════════════════════════════════════════════════════════════
class _NewSubjectRequest {
  final String subject;
  final String topic;
  _NewSubjectRequest(this.subject, this.topic);
}

class _NewSubjectSheet extends StatefulWidget {
  const _NewSubjectSheet();
  @override
  State<_NewSubjectSheet> createState() => _NewSubjectSheetState();
}

class _NewSubjectSheetState extends State<_NewSubjectSheet> {
  final _topicCtrl = TextEditingController();
  final _topicFocus = FocusNode();
  EduProfile? _profile;
  List<EduSubject> _subjects = [];
  EduSubject? _selectedSubject;
  bool _customMode = false;
  final _customSubjectCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final p = await EduProfile.load();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _subjects = subjectsForProfile(p);
    });
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    _topicFocus.dispose();
    _customSubjectCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Eğitim profili bandı
              if (_profile != null) _profileBanner(),
              if (_profile != null) const SizedBox(height: 14),
              // Ders seçimi
              Row(
                children: [
                  Text('DERS SEÇ'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.08,
                      )),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _customMode = !_customMode),
                    icon: Icon(_customMode ? Icons.grid_view_rounded : Icons.edit_rounded,
                        size: 14, color: _orange),
                    label: Text(
                      _customMode ? 'Listeden seç' : 'Kendim yazayım',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _orange,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_customMode)
                TextField(
                  controller: _customSubjectCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _topicFocus.requestFocus(),
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: _blue,
                  decoration: _inputDec(localeService.tr('subject_title_hint')),
                )
              else
                _buildSubjectGrid(),
              const SizedBox(height: 18),
              // Konu adı
              Text(localeService.tr('topic_name'),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                  )),
              const SizedBox(height: 6),
              TextField(
                controller: _topicCtrl,
                focusNode: _topicFocus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: _blue,
                decoration: _inputDec(localeService.tr('topic_name_hint')),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    localeService.tr('create_summary_btn'),
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Text('🎓'.tr(), style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _profile!.displayLabel(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _blue,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectGrid() {
    if (_subjects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('Yükleniyor…'.tr(),
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.0,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final s in _subjects)
          GestureDetector(
            onTap: () => setState(() => _selectedSubject = s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _selectedSubject?.key == s.key
                    ? s.color.withValues(alpha: 0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedSubject?.key == s.key ? s.color : Colors.grey.shade300,
                  width: _selectedSubject?.key == s.key ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(s.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 4),
                  // Uzun ders adı taşmasın — FittedBox ile auto-shrink.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 90),
                        child: Text(
                          s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _selectedSubject?.key == s.key
                                ? s.color
                                : Colors.black87,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _submit() {
    final subject = _customMode
        ? _customSubjectCtrl.text.trim()
        : (_selectedSubject?.name ?? '');
    final topic = _topicCtrl.text.trim();
    if (subject.isEmpty || topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          _customMode
              ? localeService.tr('subject_topic_required')
              : 'Lütfen bir ders seç ve konu adı yaz',
        ),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    Navigator.pop(context, _NewSubjectRequest(subject, topic));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Bottom Sheet: Mevcut derse yeni konu
// ═══════════════════════════════════════════════════════════════════════════
class _NewTopicSheet extends StatefulWidget {
  final String subjectName;
  const _NewTopicSheet({required this.subjectName});
  @override
  State<_NewTopicSheet> createState() => _NewTopicSheetState();
}

class _NewTopicSheetState extends State<_NewTopicSheet> {
  final _topicCtrl = TextEditingController();

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.menu_book_rounded, color: _blue, size: 20),
                const SizedBox(width: 8),
                Text(widget.subjectName,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _blue,
                    )),
              ],
            ),
            const SizedBox(height: 14),
            Text(localeService.tr('which_topic_summary'),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                )),
            const SizedBox(height: 8),
            TextField(
              controller: _topicCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: _blue,
              decoration:
                  _inputDec(_topicHintForSubject(widget.subjectName)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(localeService.tr('create_summary_btn'),
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final t = _topicCtrl.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }
}

InputDecoration _inputDec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
        fontSize: 14,
        color: Colors.grey.shade400,
      ),
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );

// ═══════════════════════════════════════════════════════════════════════════
//  Ders detay sayfası (içinde konu özetleri listesi + yeni konu ekle)
// ═══════════════════════════════════════════════════════════════════════════
class _SubjectDetailPage extends StatefulWidget {
  final _Subject subject;
  final LibraryMode mode;
  final Future<bool> Function(String topic) onAddTopic;
  final Future<void> Function(_Summary sum) onDelete;
  // Questions mode — boş slot: yeni attempt üret. Çağıran tarafta loader
  // durumu yok; burası kendi loader'ını gösterir. Config, önce setup page'de
  // seçilip buraya aktarılır.
  final Future<void> Function(_Summary summary, _TestConfig cfg)? onAddAttempt;
  // Questions mode — dolu slot: tamamlanmışsa sonuç, değilse devam.
  final void Function(_Summary summary, _TestAttempt attempt)? onOpenAttempt;
  // Planner'da ders kartına uygulanan renk — buradaki sayfanın da arka
  // planına yansır. null → varsayılan açık gri zemin.
  final Color? pageBg;
  const _SubjectDetailPage({
    required this.subject,
    required this.mode,
    required this.onAddTopic,
    required this.onDelete,
    this.onAddAttempt,
    this.onOpenAttempt,
    this.pageBg,
  });
  @override
  State<_SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<_SubjectDetailPage> {
  bool _generating = false;
  String _generatingTopic = '';

  /// Konu satırına basılı tutunca: [Yeniden Oluştur] + [Sil] seçenekleri.
  Future<void> _showTopicActions(_Summary sum) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Text(
                sum.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: Colors.black),
              InkWell(
                onTap: () => Navigator.of(ctx).pop('regen'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.refresh_rounded, size: 20,
                          color: Colors.black),
                      const SizedBox(width: 10),
                      Text(
                        'Yeniden Oluştur'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 1, color: Colors.black),
              InkWell(
                onTap: () => Navigator.of(ctx).pop('delete'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delete_outline_rounded, size: 20,
                          color: Color(0xFFDC2626)),
                      const SizedBox(width: 10),
                      Text(
                        'Sil'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'delete') {
      await widget.onDelete(sum);
      if (mounted) setState(() {});
    } else if (action == 'regen') {
      final topic = sum.topic;
      // Önce mevcut özeti sil, sonra aynı konu için yeniden oluştur
      await widget.onDelete(sum);
      if (!mounted) return;
      setState(() {
        _generating = true;
        _generatingTopic = topic;
      });
      await widget.onAddTopic(topic);
      if (!mounted) return;
      setState(() => _generating = false);
    }
  }

  // Summary mode — eski düzen.
  Widget _summaryRow(_Subject s, _Summary sum) {
    final d = sum.createdAt;
    final dateText =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _SummaryDetailPage(
              summary: sum,
              subjectName: s.name,
            ),
          ));
        },
        onLongPress: () => _showTopicActions(sum),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Row(
            children: [
              const Text('📖', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sum.topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.black)),
                    const SizedBox(height: 2),
                    Text(dateText,
                        style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }

  // Questions mode — konu + sağda 3 küçük test slot'u.
  // Dolu slot turuncu (tamamlanmışsa ✓ ikonlu), boş slot soluk.
  // Dolu slot → sonuç / devam. Boş slot → yeni test üret. 3 bitince kapalı.
  Widget _questionsRow(_Subject s, _Summary sum) {
    final slots = <Widget>[];
    for (int i = 0; i < 3; i++) {
      final attempt = i < sum.tests.length ? sum.tests[i] : null;
      slots.add(Expanded(child: _testSlot(s, sum, i, attempt)));
      if (i < 2) slots.add(const SizedBox(width: 6));
    }
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: () => _showTopicActions(sum),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Row(
            children: [
              const Text('📖', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              // Sol: konu adı
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sum.topic,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${sum.tests.length}/3 ${'test'.tr()}',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Sağ: 3 slot
              Expanded(
                flex: 5,
                child: Row(children: slots),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _testSlot(
      _Subject subject, _Summary summary, int index, _TestAttempt? attempt) {
    final filled = attempt != null;
    final completed = attempt?.completed ?? false;
    // Renkler: dolu=turuncu, boş=soluk.
    final bg = filled
        ? _orange.withValues(alpha: completed ? 1.0 : 0.75)
        : const Color(0xFFEFF1F6);
    final fg = filled ? Colors.white : Colors.black38;
    final borderColor = filled
        ? _orange
        : Colors.black.withValues(alpha: 0.18);
    final label = '${index + 1}. ${'Test'.tr()}';
    return AspectRatio(
      aspectRatio: 1.0,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            if (filled) {
              widget.onOpenAttempt?.call(summary, attempt);
            } else {
              // Yalnızca sıradaki boş slot oluşturabilir;
              // ileri slotlar önceki boşsa pasif.
              if (index != summary.tests.length) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      'Önce ${summary.tests.length + 1}. testi oluştur.'.tr()),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
                return;
              }
              if (widget.onAddAttempt == null) return;
              // Önce kullanıcıya son ayarlar sayfası.
              final cfg = await Navigator.of(context).push<_TestConfig>(
                MaterialPageRoute(
                  builder: (_) => _TestSetupPage(
                    subjectName: subject.name,
                    topic: summary.topic,
                    attemptIndex: summary.tests.length,
                  ),
                ),
              );
              if (cfg == null) return;
              setState(() {
                _generating = true;
                _generatingTopic = summary.topic;
              });
              await widget.onAddAttempt!(summary, cfg);
              if (!mounted) return;
              setState(() => _generating = false);
            }
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  filled
                      ? (completed
                          ? Icons.check_circle_rounded
                          : Icons.play_arrow_rounded)
                      : Icons.add_rounded,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: fg,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final isQuestions = widget.mode == LibraryMode.questions;
    final fabLabel = isQuestions
        ? 'Yeni Test Soruları'.tr()
        : 'Yeni Konu Özeti'.tr();
    // Sayfa zemini — planner'da ders kartına atanmış renk varsa onu kullan,
    // yoksa nötr açık gri. Kart arka planının koyu/açık olmasına göre
    // başlık ve geri ikonu rengi otomatik ayarlanır.
    final pageBg = widget.pageBg ?? const Color(0xFFE8EAEF);
    final lum = (0.299 * pageBg.r + 0.587 * pageBg.g + 0.114 * pageBg.b);
    final isDark = lum < 0.55;
    final fg = isDark ? Colors.white : Colors.black;
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: fg,
        iconTheme: IconThemeData(color: fg),
        title: Text(
          s.name,
          style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w800, color: fg),
        ),
      ),
      // Sağ alt: yeni özet/soru için bu dersin konular sayfasını açan buton.
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () {
          // _LibraryPage'e sinyali gönder → o, konular dialogunu açar.
          Navigator.of(context).pop('_openSubjectTopics');
        },
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text(
          fabLabel,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Stack(
        children: [
          s.summaries.isEmpty
              ? Center(
                  child: Text(localeService.tr('no_summary_yet'),
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade500)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: s.summaries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final sum = s.summaries[i];
                    if (widget.mode == LibraryMode.questions) {
                      return _questionsRow(s, sum);
                    }
                    return _summaryRow(s, sum);
                  },
                ),
          if (_generating)
            Positioned.fill(
              child: QuAlsarNumericLoader(
                stages: _AcademicPlannerState.buildGenStages(
                  subject: widget.subject.name,
                  topic: _generatingTopic,
                  isQuestions: widget.mode == LibraryMode.questions,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Özet Detay Sayfası (çerçeveli, temiz, profesyonel)
// ═══════════════════════════════════════════════════════════════════════════
class _SummaryDetailPage extends StatefulWidget {
  final _Summary summary;
  final String subjectName;
  // Streaming desteği — null değilse sayfa boş açılır, AI yazdıkça
  // içerik gelir; stream bitince onStreamComplete çağrılır (persist için).
  final Stream<String>? stream;
  final Future<void> Function(String finalContent)? onStreamComplete;
  const _SummaryDetailPage({
    required this.summary,
    required this.subjectName,
    this.stream,
    this.onStreamComplete,
  });

  @override
  State<_SummaryDetailPage> createState() => _SummaryDetailPageState();
}

class _SummaryDetailPageState extends State<_SummaryDetailPage> {
  // ── Renk özelleştirme state'i — Konu Özetleri / Bilgi Yarışı ile aynı ──
  // 3 hedef: 'bg' (sayfa arka planı) · 'title' (üst başlık çerçevesi) ·
  // 'cards' (alt başlık kartları + en önemli 5 bilgi kartı).
  // 2 mod: 'frame' (zemin) · 'text' (yazı rengi).
  bool _showColorPicker = false;
  String _colorMode = 'frame'; // 'frame' | 'text'
  String _colorTarget = 'bg'; // 'bg' | 'title' | 'cards'
  Color? _pageBgOverride;
  Color? _titleBgOverride;
  Color? _cardsBgOverride;
  Color? _titleTextOverride;
  Color? _cardsTextOverride;

  static const _palette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  // Her özet kendi renk setine sahip — SharedPreferences anahtarı özet id'si.
  String get _prefKey => 'summary_colors_${widget.summary.id}';

  // ── Streaming state ─────────────────────────────────────────────────────
  // _streamedContent: stream geldikçe büyür. Stream bittiğinde
  // widget.summary.content güncellenir + onStreamComplete persist eder.
  String? _streamedContent;
  bool _streaming = false;
  bool _streamFailed = false;
  /// Stream başarısız olunca kullanıcıya gösterilecek nedeni içerir.
  /// noInternet/serverTimeout/safety/etc spesifik mesajları üstlenir.
  String? _streamFailMessage;
  StreamSubscription<String>? _streamSub;

  /// StudyToolbarOverlay sticky highlights için — ListView ile overlay
  /// Stack'te sibling olduğundan Scrollable.maybeOf(context) bulamıyor.
  /// Controller'ı parent'ta tutup overlay'e inject ediyoruz.
  final ScrollController _scrollController = ScrollController();

  // ── Parse cache — sayfa açılışını anında yapmak için ───────────────────
  // _clean() + _splitSections() pahalı; her build'de tekrar koşmasın.
  // Ham içerik değişmediyse cache kullan, sadece içerik değişince yenile.
  String? _cachedRaw;
  String _cachedCleaned = '';
  List<_Section> _cachedNormalSections = const [];
  _Section? _cachedKeyFacts;

  void _ensureParsed(String raw) {
    if (raw == _cachedRaw) return;
    _cachedRaw = raw;
    _cachedCleaned = _clean(raw);
    final sections = _splitSections(_cachedCleaned);
    final normal = <_Section>[];
    _Section? key;
    for (final s in sections) {
      // "📌 Özetle" kapanış paragrafı kaldırıldı — geçmişte üretilmiş
      // özetlerde bu bölüm varsa render'da gizle.
      if (_isClosingHeader(s.header)) continue;
      if (_isKeyFactsHeader(s.header)) {
        key = s;
      } else {
        normal.add(s);
      }
    }
    _cachedNormalSections = normal;
    _cachedKeyFacts = key;
  }

  bool _isClosingHeader(String h) {
    final t = h.toLowerCase();
    return t.contains('📌') || t.contains('özetle');
  }

  @override
  void initState() {
    super.initState();
    _loadColors();
    _attachStreamIfAny();
    // Heavy parse'ı ilk frame'den SONRA yap — sayfa transition'ı anında
    // açılsın, içerik bir tick sonra dolsun. Boş cache ile ilk build hızlı.
    if (widget.stream == null && widget.summary.content.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureParsed(widget.summary.content);
        setState(() {});
      });
    }
  }

  void _attachStreamIfAny() {
    final s = widget.stream;
    if (s == null) return;
    setState(() {
      _streaming = true;
      _streamedContent = '';
    });
    _streamSub = s.listen(
      (acc) {
        if (!mounted) return;
        setState(() => _streamedContent = acc);
      },
      onError: (e) async {
        if (!mounted) return;
        // Stream hata verse bile o ana kadar gelmiş kısmi içeriği KAYDET —
        // kullanıcı yarıda kalmış özeti görsün, ileride uzun-bas → "Yeniden
        // Oluştur" ile tamamlayabilsin.
        final partial = _streamedContent ?? '';
        // Hata tipinden anlamlı kullanıcı mesajı çıkar.
        String msg;
        if (e is GeminiException) {
          msg = e.userMessage;
        } else {
          msg = 'AI yanıt veremedi — özeti tekrar oluşturmak için satıra uzun bas.';
        }
        setState(() {
          _streaming = false;
          _streamFailed = true;
          _streamFailMessage = msg;
          if (partial.isNotEmpty) {
            widget.summary.content = partial;
          }
        });
        if (partial.isNotEmpty) {
          try {
            await widget.onStreamComplete?.call(partial);
          } catch (_) {}
        }
      },
      onDone: () async {
        if (!mounted) return;
        final finalContent = _streamedContent ?? '';
        setState(() {
          _streaming = false;
          widget.summary.content = finalContent;
        });
        try {
          await widget.onStreamComplete?.call(finalContent);
        } catch (_) {}
      },
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        Color? read(String k) {
          final v = m[k];
          return v is num ? Color(v.toInt()) : null;
        }

        _pageBgOverride = read('bg');
        _titleBgOverride = read('title');
        _cardsBgOverride = read('cards');
        _titleTextOverride = read('titleText');
        _cardsTextOverride = read('cardsText');
      });
    } catch (_) {}
  }

  Future<void> _saveColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = <String, int>{};
      void put(String k, Color? c) {
        if (c != null) m[k] = c.toARGB32();
      }

      put('bg', _pageBgOverride);
      put('title', _titleBgOverride);
      put('cards', _cardsBgOverride);
      put('titleText', _titleTextOverride);
      put('cardsText', _cardsTextOverride);
      if (m.isEmpty) {
        await prefs.remove(_prefKey);
      } else {
        await prefs.setString(_prefKey, jsonEncode(m));
      }
    } catch (_) {}
  }

  void _applyColorTo(String target, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        if (target == 'title') {
          _titleTextOverride = c;
        } else if (target == 'cards') {
          _cardsTextOverride = c;
        } else {
          // 'bg' Yazı modunda — başlık + kart yazılarını birlikte ayarla.
          _titleTextOverride = c;
          _cardsTextOverride = c;
        }
      } else {
        if (target == 'bg') {
          _pageBgOverride = c;
        } else if (target == 'title') {
          _titleBgOverride = c;
        } else {
          _cardsBgOverride = c;
        }
      }
    });
    _saveColors();
  }

  void _resetColors() {
    setState(() {
      _pageBgOverride = null;
      _titleBgOverride = null;
      _cardsBgOverride = null;
      _titleTextOverride = null;
      _cardsTextOverride = null;
    });
    _saveColors();
  }

  bool _isDark(Color c) {
    final l = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
    return l < 0.55;
  }

  // Üst başlık kartı — ders adı + konu adı; renk paletinden 'title' hedefi.
  Widget _buildTitleCard() {
    return DragTarget<Color>(
      onAcceptWithDetails: (d) => _applyColorTo('title', d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        final bg = _titleBgOverride ?? const Color(0xFFFAFAFA);
        final ink = _titleTextOverride ??
            (_isDark(bg) ? Colors.white : Colors.black);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? const Color(0xFFFF6A00) : Colors.black,
              width: hovering ? 2 : 1,
            ),
          ),
          child: RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: widget.subjectName,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    letterSpacing: 0.1,
                  ),
                ),
                TextSpan(
                  text: ' / ',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ink.withValues(alpha: 0.5),
                  ),
                ),
                TextSpan(
                  text: widget.summary.topic,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ink.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Sağ alt FAB — "Test Sorularını Çöz" ─────────────────────────────
  // Tıklanınca: questions kütüphanesinden bu konunun testi varsa direkt aç,
  // yoksa AcademicPlanner(questions, autoOpen) ile yönlendir.
  Widget _testQuestionsFab() {
    // Küçük, kompakt pill — uzun extended FAB yerine.
    return GestureDetector(
      onTap: _onTestQuestionsTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6A00),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6A00).withValues(alpha: 0.40),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.quiz_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text('Test Çöz'.tr(),
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Future<void> _onTestQuestionsTap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('library_subjects_questions_v2') ?? const [];
    final subjects = raw
        .map((s) {
          try {
            return _Subject.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<_Subject>()
        .toList();
    final subjTarget = widget.subjectName.toLowerCase().trim();
    final topicTarget = widget.summary.topic.toLowerCase().trim();
    _Subject? subject;
    for (final s in subjects) {
      if (s.name.toLowerCase().trim() == subjTarget) {
        subject = s;
        break;
      }
    }
    if (!mounted) return;

    // Eğer dersin altında test varsa: önce konu listesi sheet'i göster
    // (aktif konu vurgulu). Boşsa direkt eski akışa düş.
    if (subject != null && subject.summaries.isNotEmpty) {
      final picked = await _showTopicPickerSheet(subject, topicTarget);
      if (picked == null) return; // kullanıcı kapattı
      if (!mounted) return;
      await _navigateToTest(subject, picked);
      return;
    }

    _Summary? summary;
    if (subject != null) {
      for (final sum in subject.summaries) {
        if (sum.topic.toLowerCase().trim() == topicTarget) {
          summary = sum;
          break;
        }
      }
    }
    // Test varsa: direkt en son denemeyi aç (tamamlanmışsa sonuç, değilse devam)
    if (summary != null && summary.tests.isNotEmpty) {
      final attempt = summary.tests.last;
      if (attempt.completed) {
        final qs = parseTestQuestions(attempt.content);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TestResultPage(
            questions: qs,
            answers: attempt.answers,
            subjectName: subject!.name,
            topic: summary!.topic,
          ),
        ));
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TestPage(
            rawContent: attempt.content,
            subjectName: subject!.name,
            topic: summary!.topic,
            initialAnswers: attempt.answers,
            timeLimit: attempt.timeLimit,
            onFinish: (answers) async {
              attempt.answers = Map<int, String?>.from(answers);
              attempt.completed = true;
            },
          ),
        ));
      }
      return;
    }
    // Test YOK: AcademicPlanner(questions) aç + autoOpen sinyali ile o
    // konunun üzerine git. Açılan sayfada konu vurgulanır (snackbar
    // ile yönlendirme + autoOpen mevcut akışı tetikler).
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AcademicPlanner(
        mode: LibraryMode.questions,
        autoOpenSubject: widget.subjectName,
        autoOpenTopic: widget.summary.topic,
      ),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${widget.summary.topic}" için test henüz yok — '
            'üretmek için konuyu seç ↓'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  /// Test FAB tıklanınca açılan sheet — dersin altındaki tüm konular
  /// listelenir. Aktif konu (üzerinde olduğun özet) turuncu çerçeveyle
  /// vurgulanır. Tıklayınca o konunun testine gidilir.
  Future<_Summary?> _showTopicPickerSheet(
      _Subject subject, String activeTopicLower) async {
    return showModalBottomSheet<_Summary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _TestTopicPicker(
          subject: subject,
          activeTopicLower: activeTopicLower,
        );
      },
    );
  }

  Future<void> _navigateToTest(_Subject subject, _Summary summary) async {
    if (summary.tests.isNotEmpty) {
      final attempt = summary.tests.last;
      if (attempt.completed) {
        final qs = parseTestQuestions(attempt.content);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TestResultPage(
            questions: qs,
            answers: attempt.answers,
            subjectName: subject.name,
            topic: summary.topic,
          ),
        ));
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TestPage(
            rawContent: attempt.content,
            subjectName: subject.name,
            topic: summary.topic,
            initialAnswers: attempt.answers,
            timeLimit: attempt.timeLimit,
            onFinish: (answers) async {
              attempt.answers = Map<int, String?>.from(answers);
              attempt.completed = true;
            },
          ),
        ));
      }
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AcademicPlanner(
        mode: LibraryMode.questions,
        autoOpenSubject: subject.name,
        autoOpenTopic: summary.topic,
      ),
    ));
  }

  // Sayfa açılır açılmaz görünen ince şerit — AI yazıyor / başarısız oldu.
  Widget _buildStreamingBanner() {
    final isFail = _streamFailed;
    final color = isFail
        ? const Color(0xFFEF4444)
        : const Color(0xFF7C3AED);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(
        children: [
          if (!isFail)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF7C3AED),
              ),
            )
          else
            const Icon(Icons.error_outline_rounded,
                size: 16, color: Color(0xFFEF4444)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isFail
                  ? (_streamFailMessage ??
                      'AI yanıt veremedi — özeti tekrar oluşturmak için satıra uzun bas.')
                  : 'AI özeti yazıyor… içerik geldikçe ekrana akacak.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Streaming aktifse o anki birikmiş içeriği göster; bittiğinde
    // widget.summary.content nihai metni içeriyor.
    final raw = _streamedContent ?? widget.summary.content;
    // Streaming durumunda her chunk için parse et (cache'li, idempotent).
    // Non-streaming durumda parse zaten initState'in postFrameCallback'inde
    // arkaplanda yapılıyor; ilk build skeleton döner → sayfa anında açılır.
    if (widget.stream != null) {
      _ensureParsed(raw);
    }
    final cleaned = _cachedCleaned;
    final keyFactsSection = _cachedKeyFacts;
    final normalSections = _cachedNormalSections;
    // Cache henüz dolmadıysa (postFrame öncesi) hafif skeleton döndür —
    // sayfa transition'ı pürüzsüz başlar, içerik bir tick sonra dolar.
    final notParsedYet =
        _cachedRaw == null && raw.isNotEmpty && widget.stream == null;

    final pageBg = _pageBgOverride ?? const Color(0xFFFAFAFA);

    // Streaming başladığında ama henüz anlamlı içerik gelmediğinde —
    // QuAlsar küresi + 3 birikimli aşama (analiz / özetleniyor / hazır).
    // İlk gerçek tokenlar gelene kadar gösterilir; sonrası içeriğe geçer.
    if (widget.stream != null && _streaming && cleaned.trim().length < 40) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: QuAlsarNumericLoader(
          stages: _AcademicPlannerState.buildGenStages(
            subject: widget.subjectName,
            topic: widget.summary.topic,
            isQuestions: false,
          ),
        ),
      );
    }

    if (notParsedYet) {
      return Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: pageBg,
          elevation: 0,
          foregroundColor: Colors.black,
          titleSpacing: 0,
          title: const SizedBox.shrink(),
        ),
        body: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      // ── Sağ alt FAB: "Test Sorularını Çöz" ─────────────────────────
      // Stream bittikten sonra (özet hazırsa) görünür; yoksa gizli.
      floatingActionButton: (widget.stream == null || !_streaming)
          ? _testQuestionsFab()
          : null,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: Colors.black,
        titleSpacing: 0,
        title: const SizedBox.shrink(),
        actions: [
          // Renkli "Renk Seç" pill — diğer sayfalardaki ile aynı.
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: GestureDetector(
              onTap: () => setState(
                  () => _showColorPicker = !_showColorPicker),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFF6A00),
                      Color(0xFFDB2777),
                      Color(0xFF7C3AED),
                      Color(0xFF2563EB),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showColorPicker
                          ? Icons.close_rounded
                          : Icons.palette_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showColorPicker
                          ? 'Kapat'.tr()
                          : 'Renk Seç'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // Klavye açıldığında layout otomatik kaysın (TextField sheet için kritik).
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Asıl içerik (sayfa)
          Column(children: [
          if (_showColorPicker) _buildColorPickerPanel(),
          // Streaming şeridi sadece HATA durumunda gösterilir; üretim
          // sırasında "AI özeti yazıyor…" yazısı kaldırıldı.
          if (_streamFailed) _buildStreamingBanner(),
          Expanded(
            child: DragTarget<Color>(
              onAcceptWithDetails: (d) {
                if (_colorMode == 'text') return;
                setState(() => _pageBgOverride = d.data);
                _saveColors();
              },
              builder: (ctx, cand, _) {
                // Lazy section render — sadece ekrandaki kart inşa edilir.
                // LaTeX widget'ları off-screen kartlarda compile edilmediği
                // için sayfa anında açılır, scrollda parça parça dolar.
                final hasFallback =
                    normalSections.isEmpty && keyFactsSection == null;
                final sectionCount = hasFallback ? 1 : normalSections.length;
                final keyOffset = keyFactsSection != null ? 1 : 0;
                // [0]=title, [1]=spacer14, [2..2+sectionCount-1]=sections,
                // [last-1]=spacer6 (keyFacts varsa), [last]=keyFacts
                final total =
                    2 + sectionCount + (keyOffset == 0 ? 0 : 2);
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: total,
                  cacheExtent: 600,
                  itemBuilder: (ctx, i) {
                    if (i == 0) return _buildTitleCard();
                    if (i == 1) return const SizedBox(height: 14);
                    final sIdx = i - 2;
                    if (sIdx < sectionCount) {
                      if (hasFallback) {
                        return RepaintBoundary(
                          child: _wrappedCard(
                            child: _card(
                                header: '',
                                headerColor: Colors.black,
                                body: cleaned),
                          ),
                        );
                      }
                      final s = normalSections[sIdx];
                      return RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _wrappedCard(
                            child: _card(
                              header: s.header,
                              headerColor: s.color,
                              body: s.body,
                            ),
                          ),
                        ),
                      );
                    }
                    if (keyFactsSection != null) {
                      if (sIdx == sectionCount) {
                        return const SizedBox(height: 6);
                      }
                      return RepaintBoundary(
                        child: _wrappedCard(
                          child: _keyFactsCard(keyFactsSection),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ),
          ]),
          // Çalışma araç çubuğu — sol kenar; not + vurgulayıcı + kalem +
          // silgi + kapat. Çizimler topicId bazlı kalıcı saklanır.
          StudyToolbarOverlay(
            topicId: 'note_${widget.summary.id}',
            topicName: widget.summary.topic,
            scrollController: _scrollController,
          ),
        ],
      ),
    );
  }

  // Kart'ı DragTarget<Color> ile sar — hedef 'cards'.
  Widget _wrappedCard({required Widget child}) {
    return DragTarget<Color>(
      onAcceptWithDetails: (d) => _applyColorTo('cards', d.data),
      builder: (ctx, cand, _) => child,
    );
  }

  // ═════ İçerik temizleyici ═════
  String _clean(String content) {
    var out = content;
    // İlk başlık satırından önceki giriş paragrafını ("Harika...", "Tabii ki",
    // "Hemen başlayalım" vb.) kırp — özet doğrudan başlıkla başlasın.
    final firstHeader = RegExp(
      r'(📖[^\n]*|📚[^\n]*|🎯[^\n]*|📐[^\n]*|🌊[^\n]*|⭐[^\n]*)',
    );
    final fm = firstHeader.firstMatch(out);
    if (fm != null && fm.start > 0) {
      out = out.substring(fm.start);
    }
    // YouTube / Web satırları
    out = out.replaceAll(
      RegExp(r'\[(VIDEO|WEB):\s*"[^"]+"\s*\|\s*[^\]]+\]\s*$',
          caseSensitive: false, multiLine: true),
      '',
    );
    // Markdown bold (**...**) KORUNUR — LatexText inline bold render eder.
    // Tek yıldızlı italik (*...*) → metin (UI italic'i render etmiyor).
    out = out.replaceAllMapped(
      RegExp(r'(?<![\\\w*])\*([^*\n]+)\*(?!\w|\*)'),
      (m) => m.group(1) ?? '',
    );
    // İçi boş **...** → tamamen sil (AI bazen "** **" gibi süs bırakıyor)
    out = out.replaceAll(RegExp(r'\*\*\s*\*\*'), '');
    // Satır sonunda kalan tek "*" / "**" artıkları
    out = out.replaceAll(RegExp(r'\s\*+\s*$', multiLine: true), '');
    // Markdown başlık işaretleri ### ## # (satır başı + satır içi setext)
    out = out.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    // Setext başlık altçizgileri (=== veya ---) — başlık değil normal metin sandı
    out = out.replaceAll(
        RegExp(r'^[=\-]{3,}\s*$', multiLine: true), '');
    // Tek başına yıldız artıkları ("* metin" → "• metin")
    out = out.replaceAllMapped(
      RegExp(r'^\s*\*\s+', multiLine: true),
      (_) => '• ',
    );
    // Çift dolar kullanımları → LaTeX \[ \]
    out = out.replaceAllMapped(
      RegExp(r'\$\$([^\$\n]+)\$\$'),
      (m) => '\\[${m.group(1)}\\]',
    );
    // Tekli $...$ → \( ... \)
    out = out.replaceAllMapped(
      RegExp(r'\$([^\$\n]+)\$'),
      (m) => '\\(${m.group(1)}\\)',
    );
    // Serbest kalan yalnız dolar işaretleri — temizle
    out = out.replaceAll(RegExp(r'\s*\$\s*'), ' ');
    // Alt başlık içinde "1." "2." vs numara başı geçerse → "▸"
    // (AI bazen kurala uymaz; UI tarafında güvenceye al)
    out = out.replaceAllMapped(
      RegExp(r'^\s*(\d+)[\.\)]\s+', multiLine: true),
      (_) => '▸ ',
    );
    // "Sonuç:", "Püf Nokta:", "İpucu:" — özet modunda yasaklı etiketler.
    // Yine de çıkarsa temizlenir (defansif).
    out = out.replaceAll(
      RegExp(r'^\s*(Sonuç|Sonuc|Püf Nokta|Puf Nokta|İpucu|Ipucu|Tip|Conclusion|Key Tip|Pro Tip)\s*[:：].*$',
          multiLine: true, caseSensitive: false),
      '',
    );
    // Triple newline → double
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  bool _isKeyFactsHeader(String h) {
    final t = h.toLowerCase();
    return t.contains('⭐') ||
        t.contains('en önemli 5') ||
        t.contains('en onemli 5') ||
        t.contains('top 5') ||
        t.contains('5 key') ||
        t.contains('5 temel');
  }

  // ═════ Normal alt başlık kartı — arka plan ve yazı renkleri state'ten ═════
  //   Header bandı hafif farklı ton (gri-mavi) — gövdeden görsel olarak ayrılır.
  Widget _card({
    required String header,
    required Color headerColor,
    required String body,
  }) {
    final bg = _cardsBgOverride ?? Colors.white;
    final ink = _cardsTextOverride ??
        (_isDark(bg) ? Colors.white : Colors.black);
    final headerBg = _cardsBgOverride == null
        ? const Color(0xFFF3F6FB)
        : bg;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              decoration: BoxDecoration(
                color: headerBg,
                border: Border(
                  bottom: BorderSide(
                    color: ink.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                header,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: ink),
              child: LatexText(body, fontSize: 14, lineHeight: 1.65),
            ),
          ),
        ],
      ),
    );
  }

  // ═════ ⭐ En Önemli 5 Bilgi — vurgulu, farklı renk kartı ═════
  Widget _keyFactsCard(_Section s) {
    final bg = _cardsBgOverride ?? const Color(0xFFFFFAE8);
    final ink = _cardsTextOverride ??
        (_isDark(bg) ? Colors.white : Colors.black);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'En Önemli 5 Bilgi'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: ink.withValues(alpha: 0.25)),
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: TextStyle(color: ink),
            child: LatexText(s.body, fontSize: 14, lineHeight: 1.7),
          ),
        ],
      ),
    );
  }

  // ══════════════════ Renk seçim paneli — diğer sayfalar ile aynı ═══════════
  Widget _buildColorPickerPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              const SizedBox(width: 6),
              Text('Renk'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
              const SizedBox(width: 10),
              Expanded(child: _modeToggle()),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _resetColors,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text('Sıfırla'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _targetToggle(),
          const SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin yere bırak.'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
                height: 1.3),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _palette.length,
              itemBuilder: (_, i) => _draggableColor(_palette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeToggle() {
    Widget box(String id, IconData icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 13,
                    color: active ? _orange : Colors.black),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? _orange : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', Icons.text_fields_rounded, 'Yazı'.tr()),
        const SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'.tr()),
      ],
    );
  }

  Widget _targetToggle() {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? _orange.withValues(alpha: 0.12)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? _orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? _orange : Colors.black),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('bg', 'Arka plan'.tr()),
        const SizedBox(width: 6),
        chip('title', 'Başlık'.tr()),
        const SizedBox(width: 6),
        chip('cards', 'Kartlar'.tr()),
      ],
    );
  }

  Widget _draggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _dot(c)),
      child: GestureDetector(
        onTap: () => _applyColorTo(_colorTarget, c),
        child: _dot(c),
      ),
    );
  }

  Widget _dot(Color c) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26, width: 1),
      ),
    );
  }

  // Emoji başlıklarına göre böl: 📚 🔑 📐 🎯 ⚠️ ⭐
  List<_Section> _splitSections(String content) {
    const markers = {
      '📖': Color(0xFF0F766E), // Tanım — teal
      '📚': Color(0xFF2563EB),
      '🔑': Color(0xFF059669),
      '📐': Color(0xFF7C3AED),
      '🌊': Color(0xFF0EA5E9),
      '🎯': Color(0xFFEA580C),
      '⚠️': Color(0xFFDC2626),
      '💡': Color(0xFFCA8A04),
      '⭐': Color(0xFFCA8A04),
      '📌': Color(0xFF334155), // Özetle kapanış — slate
      '1️⃣': Color(0xFF2563EB),
      '2️⃣': Color(0xFF059669),
      '3️⃣': Color(0xFF7C3AED),
      '4️⃣': Color(0xFFEA580C),
      '5️⃣': Color(0xFFDC2626),
      '6️⃣': Color(0xFF0891B2),
    };
    final lines = content.split('\n');
    final sections = <_Section>[];
    _Section? current;
    // ⭐ "EN ÖNEMLİ 5 BİLGİ" section'ı başlayınca — sonraki satırlar marker
    // (🔑 vs.) olsa bile yeni section açma; hepsi bu vurgulu kartın body'si.
    bool inKeyFactsBlock = false;
    for (final raw in lines) {
      final line = raw.trimRight();
      final trim = line.trimLeft();
      String? foundMarker;
      if (!inKeyFactsBlock) {
        for (final m in markers.keys) {
          if (trim.startsWith(m)) {
            foundMarker = m;
            break;
          }
        }
      }
      if (foundMarker != null) {
        if (current != null) {
          current.body = current.body.trim();
          if (current.body.isNotEmpty || current.header.isNotEmpty) {
            sections.add(current);
          }
        }
        current = _Section(
          header: trim,
          color: markers[foundMarker]!,
          body: '',
        );
        if (foundMarker == '⭐') inKeyFactsBlock = true;
      } else if (current != null) {
        current.body += '$line\n';
      } else if (line.trim().isNotEmpty) {
        current = _Section(
          header: '',
          color: Colors.black,
          body: '$line\n',
        );
      }
    }
    if (current != null) {
      current.body = current.body.trim();
      if (current.body.isNotEmpty || current.header.isNotEmpty) {
        sections.add(current);
      }
    }
    return sections;
  }
}

class _Section {
  String header;
  Color color;
  String body;
  _Section({required this.header, required this.color, required this.body});
}

// ══════════════════════════════════════════════════════════════════════════
//  Zorluk Seçici Dialog — Kolay · Orta · Zor. Kullanıcı bir kutuya basarak
//  seçer, sağ altta "Tamam" ile _TestConfig döner.
// ══════════════════════════════════════════════════════════════════════════
class _DifficultyPickerDialog extends StatefulWidget {
  const _DifficultyPickerDialog();

  @override
  State<_DifficultyPickerDialog> createState() =>
      _DifficultyPickerDialogState();
}

class _DifficultyPickerDialogState extends State<_DifficultyPickerDialog> {
  String? _selected; // null | 'easy' | 'medium' | 'hard'

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Zorluk Seç'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF3F4F6),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 15, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Test zorluğunu seç ve Tamam\'a bas.'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _difficultyBox(
                      id: 'easy',
                      emoji: '🌱',
                      label: 'Kolay'.tr(),
                      accent: const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _difficultyBox(
                      id: 'medium',
                      emoji: '⚖️',
                      label: 'Orta'.tr(),
                      accent: const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _difficultyBox(
                      id: 'hard',
                      emoji: '🔥',
                      label: 'Zor'.tr(),
                      accent: const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tamam butonu — sadece bir zorluk seçiliyse aktif.
              GestureDetector(
                onTap: _selected == null
                    ? null
                    : () {
                        final cfg = _TestConfig()..difficulty = _selected!;
                        Navigator.of(context).pop(cfg);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: _selected == null
                        ? const Color(0xFFE5E7EB)
                        : Colors.black,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Tamam'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _selected == null
                          ? Colors.black38
                          : Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _difficultyBox({
    required String id,
    required String emoji,
    required String label,
    required Color accent,
  }) {
    final active = _selected == id;
    return GestureDetector(
      onTap: () => setState(() => _selected = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? accent : Colors.black,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: active ? accent : Colors.black,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sınav Soruları sayfasında — bir dersin altındaki her test için
// özet + test denemesi + sırası (1./2./3. deneme) ikilisi.
class _AttemptRef {
  final _Summary summary;
  final _TestAttempt attempt;
  final int attemptIndex; // 1-based
  _AttemptRef({
    required this.summary,
    required this.attempt,
    required this.attemptIndex,
  });
}


// ═══════════════════════════════════════════════════════════════════════════════
//  _SubjectTopicsDialog — ders seçildiğinde açılan küçük modal.
//  Sol sütun: curriculum konuları (oval pill, ince siyah border)
//  Sağ sütun: "Konu Özeti" (varsa) / "Oluştur" rozeti
//  Alt: yeni konu ekle input + kaydet (eklenince ikon görünür)
// ═══════════════════════════════════════════════════════════════════════════════

class _SubjectTopicsDialog extends StatefulWidget {
  final String subjectName;
  final String subjectEmoji;
  final Color subjectColor;
  final String profileLabel;
  final List<String> curriculumTopics;
  final LibraryMode mode; // summary → "Konu Özeti", questions → "Soru Seti"
  final _Subject Function() getExistingSubject;
  final Future<void> Function(String topic) onGenerateTopic;
  final void Function(_Summary summary) onOpenExistingSummary;
  final Future<void> Function(String topic) onAddCustomTopic;

  const _SubjectTopicsDialog({
    required this.subjectName,
    required this.subjectEmoji,
    required this.subjectColor,
    required this.profileLabel,
    required this.curriculumTopics,
    required this.mode,
    required this.getExistingSubject,
    required this.onGenerateTopic,
    required this.onOpenExistingSummary,
    required this.onAddCustomTopic,
  });

  // Sağ sekme etiketleri — mod'a göre
  String get _existingLabel =>
      mode == LibraryMode.questions ? 'Test Soruları' : 'Konu Özeti';
  String get _createLabel =>
      mode == LibraryMode.questions ? 'Test Oluştur' : 'Özet Oluştur';

  @override
  State<_SubjectTopicsDialog> createState() => _SubjectTopicsDialogState();
}

class _SubjectTopicsDialogState extends State<_SubjectTopicsDialog> {
  final _newTopicCtrl = TextEditingController();
  final Set<String> _savedCustomTopics = {};

  @override
  void dispose() {
    _newTopicCtrl.dispose();
    super.dispose();
  }

  _Summary? _summaryForTopic(String topic) {
    final subj = widget.getExistingSubject();
    for (final s in subj.summaries) {
      if (s.topic.toLowerCase() == topic.toLowerCase()) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.getExistingSubject();
    final existingTopics = existing.summaries.map((s) => s.topic).toList();
    final extras = existingTopics
        .where((t) => !widget.curriculumTopics
            .any((c) => c.toLowerCase() == t.toLowerCase()))
        .toList();
    final allTopics = [...widget.curriculumTopics, ...extras];

    return Dialog(
      // Dialog iç zemini SOLUK beyaz — konu kartları (saf beyaz) öne çıksın
      backgroundColor: const Color(0xFFE8EAEF),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ═══ Ders başlığı — merkezde, büyük ═══
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.subjectEmoji,
                            style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.subjectName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 14),
              // Ders başlığı altında ince ayırıcı — yumuşak ton
              Container(height: 1, color: Colors.black.withValues(alpha: 0.08)),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (allTopics.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Bu ders için henüz müfredat konuları yüklenmemiş. Aşağıdan kendi konunu ekleyebilirsin.'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        )
                      else
                        for (final topic in allTopics) _topicRow(topic),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Yeni Konu Ekle'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                  letterSpacing: 0.08,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          textSelectionTheme: TextSelectionThemeData(
                            cursorColor: Colors.black,
                            selectionColor:
                                Colors.black.withValues(alpha: 0.25),
                            selectionHandleColor: Colors.black,
                          ),
                        ),
                        child: TextField(
                          controller: _newTopicCtrl,
                          textCapitalization: TextCapitalization.sentences,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                          cursorColor: Colors.black,
                          decoration: InputDecoration(
                            hintText: 'Konu başlığı…'.tr(),
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.black38,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final t = _newTopicCtrl.text.trim();
                      if (t.isEmpty) return;
                      setState(() {
                        _savedCustomTopics.add(t);
                        _newTopicCtrl.clear();
                      });
                      await widget.onAddCustomTopic(t);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Kaydet'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
            // ═══ Kapat butonu — Dialog kartının SAĞ ÜSTÜNDE (çerçevesiz) ═══
            Positioned(
              right: 10,
              top: 10,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: Colors.black),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topicRow(String topic) {
    final existing = _summaryForTopic(topic);
    final hasSummary = existing != null;
    final hasIcon = hasSummary || _savedCustomTopics.contains(topic);
    final isQuestions = widget.mode == LibraryMode.questions;
    // Questions mode'da sağdaki butonun davranışı:
    //   • testCount < 3  → her tıklama yeni test üretir (eski sonuca gitmez)
    //   • testCount == 3 → buton kilitli, dokununca uyarı snackbar'ı
    final testCount =
        isQuestions && existing != null ? existing.tests.length : 0;
    final limitReached = isQuestions && testCount >= 3;

    final IconData actionIcon;
    final String actionLabel;
    final Color actionBg;
    final Color actionFg;
    if (isQuestions) {
      if (limitReached) {
        actionIcon = Icons.lock_rounded;
        actionLabel = '${'Limit'.tr()} · 3/3';
        actionBg = const Color(0xFFE5E7EB);
        actionFg = Colors.black54;
      } else if (testCount > 0) {
        actionIcon = Icons.add_rounded;
        actionLabel = '${'Yeni Test'.tr()} · $testCount/3';
        actionBg = const Color(0xFFEFF1F6);
        actionFg = Colors.black;
      } else {
        actionIcon = Icons.auto_awesome_rounded;
        actionLabel = widget._createLabel.tr();
        actionBg = const Color(0xFFEFF1F6);
        actionFg = Colors.black;
      }
    } else {
      actionIcon = hasSummary
          ? Icons.auto_stories_rounded
          : Icons.auto_awesome_rounded;
      actionLabel =
          hasSummary ? widget._existingLabel.tr() : widget._createLabel.tr();
      actionBg = const Color(0xFFEFF1F6);
      actionFg = Colors.black;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('•',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.black,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                topic,
                maxLines: 3,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  height: 1.3,
                ),
              ),
            ),
            if (hasIcon) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle_rounded,
                  size: 14, color: Colors.black),
            ],
            const SizedBox(width: 10),
            Material(
              color: actionBg,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  if (limitReached) {
                    // Limit dolu — diyaloğu kapat, planner sayfasında
                    // (3 slot'un göründüğü konu satırının olduğu sayfa)
                    // uyarı snackbar'ı göster.
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(context).pop();
                    messenger.showSnackBar(SnackBar(
                      content: Text(
                        'Bu konudan zaten 3 test oluşturdun. Aynı konu için en fazla 3 test oluşturabilirsin.'
                            .tr(),
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                    return;
                  }
                  if (isQuestions) {
                    widget.onGenerateTopic(topic);
                  } else if (hasSummary) {
                    widget.onOpenExistingSummary(existing);
                  } else {
                    widget.onGenerateTopic(topic);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(actionIcon, size: 13, color: actionFg),
                      const SizedBox(width: 5),
                      Text(
                        actionLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: actionFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Test Setup Page — sınav için "Son Ayarlar" (QuAlsar Arena stilinde).
//  Soru sayısı · Zorluk · Süre Modu. Onaylayınca _TestConfig döner.
// ═══════════════════════════════════════════════════════════════════════════════

class _TestSetupPage extends StatefulWidget {
  final String subjectName;
  final String topic;
  final int attemptIndex; // 0..2 — 1./2./3. test
  const _TestSetupPage({
    required this.subjectName,
    required this.topic,
    required this.attemptIndex,
  });

  @override
  State<_TestSetupPage> createState() => _TestSetupPageState();
}

class _TestSetupPageState extends State<_TestSetupPage> {
  final _cfg = _TestConfig();

  @override
  Widget build(BuildContext context) {
    const pageBg = Color(0xFFE8EAEF);
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          '${widget.attemptIndex + 1}. ${'Test'.tr()}',
          style:
              GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Son Ayarlar'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.subjectName} · ${widget.topic}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _TestPillGroup(
                      label: '📊 SORU SAYISI'.tr(),
                      options: const [
                        _TestPillOpt('5', '⚡', '5 Soru', '~5 dk'),
                        _TestPillOpt('10', '📝', '10 Soru', '~10 dk'),
                        _TestPillOpt('15', '📚', '15 Soru', '~15 dk'),
                      ],
                      selected: '${_cfg.count}',
                      onSelect: (v) =>
                          setState(() => _cfg.count = int.parse(v)),
                    ),
                    _TestPillGroup(
                      label: '⚡ ZORLUK SEVİYESİ'.tr(),
                      options: const [
                        _TestPillOpt('easy', '🟢', 'Kolay', 'Temel',
                            tone: Color(0xFF059669),
                            toneBg: Color(0xFFECFDF5)),
                        _TestPillOpt('medium', '🟡', 'Orta', 'Dengeli',
                            tone: Color(0xFFD97706),
                            toneBg: Color(0xFFFFFBEB)),
                        _TestPillOpt('hard', '🔴', 'Zor', 'Zorlayıcı',
                            tone: Color(0xFFDC2626),
                            toneBg: Color(0xFFFEF2F2)),
                      ],
                      selected: _cfg.difficulty,
                      onSelect: (v) =>
                          setState(() => _cfg.difficulty = v),
                    ),
                    _TestPillGroup(
                      label: '⏱️ SÜRE MODU'.tr(),
                      options: const [
                        _TestPillOpt('relax', '🧘', 'Rahat', 'Süre yok'),
                        _TestPillOpt(
                            'normal', '⏲️', 'Normal', '90 sn/soru'),
                        _TestPillOpt('race', '🔥', 'Yarış', '45 sn/soru'),
                      ],
                      selected: _cfg.timeMode,
                      onSelect: (v) =>
                          setState(() => _cfg.timeMode = v),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(_cfg),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: _orange.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🚀', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(
                        'Testi Oluştur'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestPillOpt {
  final String value;
  final String emoji;
  final String title;
  final String hint;
  final Color? tone;
  final Color? toneBg;
  const _TestPillOpt(this.value, this.emoji, this.title, this.hint,
      {this.tone, this.toneBg});
}

class _TestPillGroup extends StatelessWidget {
  final String label;
  final List<_TestPillOpt> options;
  final String selected;
  final ValueChanged<String> onSelect;
  const _TestPillGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black54,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelect(options[i].value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected == options[i].value
                            ? (options[i].toneBg ?? Colors.white)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == options[i].value
                              ? (options[i].tone ?? Colors.black)
                              : Colors.black12,
                          width: selected == options[i].value ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(options[i].emoji,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(
                            options[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            options[i].hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Pomodoro Tekniği — iki alt başlığı barındıran kapsayıcı sayfa:
//    • Yeşil Koloni (mola zamanı mini oyun)
//    • QuAlsar · Mars Protokolü (derin odak pomodoro)
//  İlk tıklamada kısa açıklama modalı çıkar, "Tamam" ile kapanır; tekrar
//  girişlerde gösterilmez (SharedPreferences bayrağı).
// ═══════════════════════════════════════════════════════════════════════════════

// Diğer Dersler sheet'indeki ders tile'ı — uzun basışta drag başlar,
// onDragStarted ile parent sheet'i kapatır. Ayrıca DragTarget<String>
// olduğu için, sheet içindeki başka bir ders üstüne bırakılınca onAcceptSwap
// tetiklenir (sheet içi yer değiştirme).
class _OverflowSubjectTile extends StatelessWidget {
  final EduSubject subject;
  final Color? bgColor;
  final Color? textColor;
  final VoidCallback onTap;
  final VoidCallback onDragStarted;
  final VoidCallback? onDragEnd;
  final ValueChanged<String>? onAcceptSwap;
  const _OverflowSubjectTile({
    required this.subject,
    required this.onTap,
    required this.onDragStarted,
    this.bgColor,
    this.textColor,
    this.onDragEnd,
    this.onAcceptSwap,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != subject.key,
      onAcceptWithDetails: (d) => onAcceptSwap?.call(d.data),
      builder: (ctx, cand, _) {
        final hovering = cand.isNotEmpty;
        final bg = bgColor ?? Colors.white;
        final lum = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
        final autoFg = lum < 0.55 ? Colors.white : Colors.black;
        final fg = textColor ?? autoFg;
        final tile = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering ? const Color(0xFFFF6A00) : Colors.black,
              width: hovering ? 2.4 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(subject.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 3),
              Text(
                subject.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.15,
                ),
              ),
            ],
          ),
        );
        return LongPressDraggable<String>(
          data: subject.key,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnd?.call(),
          onDraggableCanceled: (_, __) => onDragEnd?.call(),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 72, height: 72, child: tile),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: GestureDetector(onTap: onTap, child: tile),
        );
      },
    );
  }
}

class _PomodoroTechniquePage extends StatelessWidget {
  const _PomodoroTechniquePage();

  static const _colonyPrefKey = 'pomodoro_intro_colony_seen_v1';
  static const _marsPrefKey = 'pomodoro_intro_mars_seen_v1';

  Future<void> _openWithIntro(
    BuildContext context, {
    required String prefKey,
    required String title,
    required String emoji,
    required String intro,
    required Widget Function() pageBuilder,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(prefKey) ?? false;
    if (!context.mounted) return;
    if (!seen) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (ctx) => _IntroDialog(
          title: title,
          emoji: emoji,
          body: intro,
        ),
      );
      await prefs.setBool(prefKey, true);
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => pageBuilder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_rounded,
                color: Color(0xFFE11D48), size: 22),
            const SizedBox(width: 8),
            Text(
              'Pomodoro Tekniği'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Odaklanmış çalışma ritmi — 25 dk çalış, 5 dk dinlen. Aşağıdan iki farklı pomodoro modunu seçebilirsin.'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            _LandingCard(
              icon: Icons.eco_rounded,
              title: 'Yeşil Koloni'.tr(),
              color: const Color(0xFF00B070),
              onTap: () => _openWithIntro(
                context,
                prefKey: _colonyPrefKey,
                title: 'Yeşil Koloni'.tr(),
                emoji: '🌱',
                intro: 'Pomodoro boyunca küçük bir ada geliştiriyorsun. '
                        'Her tamamlanan 25 dakikalık odak seansı için '
                        'bir tohum ekilir; molada sulamazsan bitki solar. '
                        'Kesintisiz odaklanmak kolonini büyütür, dikkat '
                        'dağılınca tohumların bir kısmı kaybolur. '
                        'Hedef: haftalar içinde bu adayı ormana çevirmek.'
                    .tr(),
                pageBuilder: () => const GreenColonyScreen(),
              ),
            ),
            const SizedBox(height: 12),
            _LandingCard(
              icon: Icons.rocket_launch_rounded,
              title: 'QuAlsar · Mars Protokolü'.tr(),
              color: const Color(0xFFFF6A3C),
              onTap: () => _openWithIntro(
                context,
                prefKey: _marsPrefKey,
                title: 'QuAlsar · Mars Protokolü'.tr(),
                emoji: '🚀',
                intro: 'Bu mod derin odak için tasarlandı. 25 dakikalık '
                        'bir "görev fazı" başlatırsın; görev boyunca roket '
                        'Mars\'a doğru ilerler. Telefonu kilitler veya '
                        'uygulamadan çıkarsan görev başarısız olur. '
                        'Başarılı her seans QuAlsar Point kazandırır ve '
                        'seni sıralamada yukarı taşır. Toplam biriken '
                        'görevlerle rozetler açılır.'
                    .tr(),
                pageBuilder: () => const QuAlsarMarsScreen(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroDialog extends StatelessWidget {
  final String title;
  final String emoji;
  final String body;
  const _IntroDialog({
    required this.title,
    required this.emoji,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Colors.black, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.black),
            const SizedBox(height: 14),
            Text(
              body,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                  child: Text(
                    'Tamam'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
//  Test Topic Picker — Test FAB tıklanınca açılan sheet
//  Aktif konu turuncu border + dolgu ile vurgulanır (active_topic_color).
// ═════════════════════════════════════════════════════════════════════════
class _TestTopicPicker extends StatelessWidget {
  final _Subject subject;
  final String activeTopicLower;
  const _TestTopicPicker({
    required this.subject,
    required this.activeTopicLower,
  });

  static const _activeColor = Color(0xFFFF6A00);

  @override
  Widget build(BuildContext context) {
    final summaries = subject.summaries;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    const Icon(Icons.quiz_rounded,
                        color: _activeColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${subject.name} — Test Konuları',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    Text('${summaries.length}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        )),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  itemCount: summaries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = summaries[i];
                    final isActive =
                        s.topic.toLowerCase().trim() == activeTopicLower;
                    final hasTest = s.tests.isNotEmpty;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop(s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? _activeColor.withValues(alpha: 0.10)
                                : const Color(0xFFF7F7F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive
                                  ? _activeColor
                                  : Colors.transparent,
                              width: isActive ? 2 : 0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isActive
                                      ? _activeColor
                                      : Colors.black12,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  isActive
                                      ? Icons.location_on_rounded
                                      : (hasTest
                                          ? Icons.task_alt_rounded
                                          : Icons.add_rounded),
                                  color: isActive
                                      ? Colors.white
                                      : Colors.black54,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.topic,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: isActive
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                        color: isActive
                                            ? _activeColor
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isActive
                                          ? 'Şu anki konu'
                                          : (hasTest
                                              ? 'Test mevcut'
                                              : 'Test oluştur'),
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isActive
                                            ? _activeColor.withValues(
                                                alpha: 0.85)
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: isActive
                                      ? _activeColor
                                      : Colors.black38),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
