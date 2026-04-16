import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/gemini_service.dart';
import '../widgets/latex_text.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Kütüphane — Ders bazlı kart sistemi
//  • Her + kartı bir ders. İlk basışta ders adı + ilk konu istenir.
//  • Kart dolunca bir daha basılınca SADECE yeni konu istenir, o derse eklenir.
//  • Başka ders için başka + kartına basılır.
//  • Özet AI (Gemini) tarafından öğrencinin sınav seviyesine göre üretilir.
// ═══════════════════════════════════════════════════════════════════════════════

const _monthlyLimit = 15;
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
    const labels = ['Pzt', 'Sa', 'Çar', 'Per', 'Cu', 'Cmt', 'Pa'];

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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    const dayNames = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar'
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          'Çalışma Takvimim',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
        children: [
          const _WeeklyCalendar(),
          const SizedBox(height: 14),
          for (var i = 0; i < 7; i++)
            _buildDayFrame(monday.add(Duration(days: i)), dayNames[i]),
        ],
      ),
    );
  }

  Widget _buildDayFrame(DateTime day, String dayName) {
    final entries = _grouped[_ActivityStore.dayKey(day)] ?? const [];
    final dateText =
        '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _indigo.withValues(alpha: 0.10),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_note_rounded,
                      color: _indigo, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '$dayName  ·  $dateText',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _indigo,
                    ),
                  ),
                  const Spacer(),
                  if (entries.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _indigo,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${entries.length}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                child: Text(
                  'Bu gün henüz çalışma kaydı yok.',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.grey.shade500,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                child: Column(
                  children: entries
                      .map((e) => _activityRow(e))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _activityRow(_ActivityEntry e) {
    final time =
        '${e.when.hour.toString().padLeft(2, '0')}:${e.when.minute.toString().padLeft(2, '0')}';
    final isQ = e.type == 'soru';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: (isQ ? _orange : _blue).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              isQ ? Icons.quiz_rounded : Icons.menu_book_rounded,
              size: 16,
              color: isQ ? _orange : _blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '${e.subject} · ${isQ ? "soru üretildi" : "özet"}',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            time,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _indigo,
            ),
          ),
        ],
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
class LibraryLanding extends StatelessWidget {
  const LibraryLanding({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
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
              'Kütüphanem',
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
            Row(
              children: [
                Expanded(
                  child: _LandingCard(
                    icon: Icons.auto_stories_rounded,
                    title: 'Konu Özeti Oluştur',
                    color: _blue,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AcademicPlanner(
                            mode: LibraryMode.summary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LandingCard(
                    icon: Icons.quiz_rounded,
                    title: 'Sınav Soruları Oluştur',
                    color: _orange,
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
            const SizedBox(height: 12),
            _LandingCard(
              icon: Icons.calendar_month_rounded,
              title: 'Çalışma Takvimim',
              color: _indigo,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StudyCalendarPage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  const _LandingCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: color.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    height: 1.1,
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

// ── Model ──────────────────────────────────────────────────────────────────
class _Summary {
  final String id;
  final String topic;
  final String content;
  final DateTime createdAt;
  _Summary({
    required this.id,
    required this.topic,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory _Summary.fromJson(Map<String, dynamic> j) => _Summary(
        id: j['id'] as String,
        topic: j['topic'] as String,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
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

// Ders → konu placeholder ipucu
String _topicHintForSubject(String subject) {
  final s = subject.toLowerCase();
  if (s.contains('matem')) return 'Örn. Türev kuralları';
  if (s.contains('fiz')) return 'Örn. Newton kanunları';
  if (s.contains('kim')) return 'Örn. Asit-baz dengesi';
  if (s.contains('biyo')) return 'Örn. Hücre bölünmesi';
  if (s.contains('coğraf')) return 'Örn. Enlemler ve paraleller';
  if (s.contains('tar')) return 'Örn. Kurtuluş Savaşı';
  if (s.contains('edeb')) return 'Örn. Tanzimat Edebiyatı';
  if (s.contains('türk')) return 'Örn. Sözcük türleri';
  if (s.contains('feles')) return 'Örn. Bilgi felsefesi';
  if (s.contains('ingil') || s.contains('engl')) return 'Örn. Tenses';
  return 'Konuyu yazın...';
}

enum LibraryMode { summary, questions }

class AcademicPlanner extends StatefulWidget {
  final LibraryMode mode;
  const AcademicPlanner({super.key, this.mode = LibraryMode.summary});
  @override
  State<AcademicPlanner> createState() => _AcademicPlannerState();
}

class _AcademicPlannerState extends State<AcademicPlanner> {
  String get _subjectsKey => widget.mode == LibraryMode.summary
      ? 'library_subjects_v2'
      : 'library_subjects_questions_v2';
  static const _usageKey = 'topic_summary_usage';

  String get _title => widget.mode == LibraryMode.summary
      ? 'Konu Özetleri'
      : 'Sınav Soruları';
  String get _headline => widget.mode == LibraryMode.summary
      ? 'İstediğin konunun özetini oluştur'
      : 'İstediğin konu için sınav soruları oluştur';

  String _grade = '';
  int _monthUsed = 0;
  String _monthKey = '';
  List<_Subject> _subjects = [];
  bool _generating = false;

  bool _showWelcome = true;
  Timer? _welcomeTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _welcomeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showWelcome = false);
    });
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    super.dispose();
  }

  // ── Depolama ─────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final grade = prefs.getString('user_grade_level') ?? '';

    final now = DateTime.now();
    final mkey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final usageRaw = prefs.getString(_usageKey);
    var used = 0;
    if (usageRaw != null) {
      try {
        final j = jsonDecode(usageRaw) as Map<String, dynamic>;
        if (j['month'] == mkey) used = (j['count'] as num).toInt();
      } catch (_) {}
    }

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

    if (!mounted) return;
    setState(() {
      _grade = grade;
      _monthKey = mkey;
      _monthUsed = used;
      _subjects = list;
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

  // ── Yeni ders kartı oluştur (boş + slotuna basınca) ──────────────────────
  Future<void> _createNewSubject() async {
    final result = await showModalBottomSheet<_NewSubjectRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewSubjectSheet(),
    );
    if (result == null || !mounted) return;
    await _generate(
      subjectName: result.subject,
      topic: result.topic,
      newSubject: true,
    );
  }

  // Public: detail page'in çağırdığı "yeni konu ekle" akışı (page açık kalır)
  Future<bool> _generateForExistingSubject(
      _Subject subject, String topic) async {
    if (_monthUsed >= _monthlyLimit) {
      _showSnack('Bu ay kullanılabilir özet hakkınız doldu.');
      return false;
    }
    try {
      final ctx = _contextFromGrade(_grade);
      final exam = _examShort(_grade);
      final prompt = _buildPrompt(
          subject: subject.name, topic: topic, ctx: ctx, exam: exam);
      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'KonuÖzeti',
        subject: subject.name,
      );
      final summary = _Summary(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        topic: topic,
        content: _stripMarkdown(content),
        createdAt: DateTime.now(),
      );
      subject.summaries.insert(0, summary);
      _monthUsed += 1;
      await _persistSubjects();
      await _persistUsage();
      await _ActivityStore.log(
        subject: subject.name,
        topic: topic,
        type: widget.mode == LibraryMode.questions ? 'soru' : 'özet',
      );
      if (mounted) setState(() {});
      return true;
    } on GeminiException catch (e) {
      if (mounted) _showSnack(e.userMessage);
      return false;
    } catch (e) {
      if (mounted) _showSnack('Hata: $e');
      return false;
    }
  }

  // ── AI çağrısı ve özet kayıt (yeni ders kartı için) ──────────────────────
  Future<void> _generate({
    required String subjectName,
    required String topic,
    required bool newSubject,
    _Subject? existingSubject,
  }) async {
    if (_monthUsed >= _monthlyLimit) {
      _showSnack('Bu ay kullanılabilir özet hakkınız doldu.');
      return;
    }
    setState(() => _generating = true);

    try {
      final ctx = _contextFromGrade(_grade);
      final exam = _examShort(_grade);
      final prompt = _buildSummaryPrompt(
          subject: subjectName, topic: topic, ctx: ctx, exam: exam);

      final content = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'KonuÖzeti',
        subject: subjectName,
      );

      final cleanContent = _stripMarkdown(content);

      final summary = _Summary(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        topic: topic,
        content: cleanContent,
        createdAt: DateTime.now(),
      );

      if (newSubject) {
        _subjects.add(_Subject(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: subjectName,
          summaries: [summary],
        ));
      } else {
        existingSubject?.summaries.insert(0, summary);
      }
      _monthUsed += 1;
      await _persistSubjects();
      await _persistUsage();
      await _ActivityStore.log(
        subject: subjectName,
        topic: topic,
        type: widget.mode == LibraryMode.questions ? 'soru' : 'özet',
      );

      if (!mounted) return;
      setState(() => _generating = false);
      _openSummary(summary, subjectName);
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      _showSnack(e.userMessage);
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      _showSnack('Hata: $e');
    }
  }

  String _buildPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
  }) {
    if (widget.mode == LibraryMode.questions) {
      return _buildQuestionsPrompt(
          subject: subject, topic: topic, ctx: ctx, exam: exam);
    }
    return _buildSummaryPrompt(
        subject: subject, topic: topic, ctx: ctx, exam: exam);
  }

  static String _buildQuestionsPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
  }) {
    return '''
[SINAV SORULARI]
Ders: $subject
Konu: $topic
Bağlam: $ctx

GÖREVİN: Bu konu için $exam formatında 5 adet ÖZGÜN soru + kısa çözüm üret.

YAPI (her bölüm ayrı satırda):

📖 KONU ÖZETİ
[2-3 cümle ile konunun sınav açısından ne olduğunu söyle.]

📝 SORU 1 — Kolay
[Soru metni — çoktan seçmeli, şıkları satır satır:
A) ...
B) ...
C) ...
D) ...
E) ...]

🔎 ÇÖZÜM 1
[1-3 satır kısa çözüm]
Doğru cevap: [şık harfi]

📝 SORU 2 — Kolay-Orta
[aynı format]

🔎 ÇÖZÜM 2
[çözüm]
Doğru cevap: ...

📝 SORU 3 — Orta
...

🔎 ÇÖZÜM 3
...

📝 SORU 4 — Orta-Zor
...

🔎 ÇÖZÜM 4
...

📝 SORU 5 — Zor
...

🔎 ÇÖZÜM 5
...

🔑 $exam Tüyoları
[3-4 madde — bu tür sorularda dikkat edilmesi gerekenler]

KATI KURALLAR:
• ASLA markdown yıldız (**) kullanma.
• Her sorunun TAM OLARAK 5 şıkı olacak: A, B, C, D, E.
• Sayısal derslerde formülleri \$...\$ içinde LaTeX ile yaz.
• Soruların zorluğu sırayla artsın.
• [WEB:] veya [VIDEO:] kaynakları EKLEME.
• Türkçe. $exam sınav stiline uygun — kısa, net, tek doğru cevaplı.
''';
  }

  // ── Prompt builder — paylaşılan ─────────────────────────────────────────
  static String _buildSummaryPrompt({
    required String subject,
    required String topic,
    required String ctx,
    required String exam,
  }) {
    return '''
[KONU ÖZETİ]
Ders: $subject
Konu: $topic
Bağlam: $ctx

GÖREVİN: Aşağıdaki yapıyı KESİNLİKLE takip ederek ne çok uzun ne çok kısa,
profesyonel bir konu özeti üret.

YAPI (her satır ayrı, sırayla):

📖 GİRİŞ
[Konu için 2-3 cümle açıklama. Konunun ne olduğunu, neden önemli olduğunu söyle.]

1️⃣ [İlk Alt Başlık — temel kavramlar veya değerler]
[Madde madde veya kısa açıklamalı şekilde, 3-6 satır]
Örnek: [varsa somut bir örnek tek satırda]

2️⃣ [İkinci Alt Başlık — özellikler veya kurallar]
1. [Madde]
2. [Madde]
3. [Madde]
4. [Madde]
(her madde 1-2 satır)

3️⃣ [Üçüncü Alt Başlık — uygulamalar / türler / sonuçlar]
[Madde veya alt başlıklarla]

4️⃣ [Dördüncü Alt Başlık — özel/önemli noktalar]
[Detay]

(Gerekiyorsa 5️⃣, 6️⃣ ekleyebilirsin — toplam 4-6 numaralı bölüm.)

📐 FORMÜLLER (varsa)
[LaTeX formülleri \$...\$ içinde, her biri ayrı satırda — yoksa bu bölümü atla]

🎯 ÖRNEK
[1 somut örnek. Sayısal dersse hesaplı, sözel dersse durum bazlı.]

🔑 $exam için kritik bilgi
[3-5 madde, her biri tek cümle — sınavda mutlaka bilinmesi gerekenler]

⚠️ DİKKAT
[1 cümle — sık yapılan hata veya sınav tuzağı]

📺 YOUTUBE ÖNERİLERİ
[VIDEO: "Kanal Adı - Konu Başlığı" | youtube arama terimi]
[VIDEO: "Kanal Adı - Konu Başlığı" | youtube arama terimi]
[VIDEO: "Kanal Adı - Konu Başlığı" | youtube arama terimi]

🌐 WEB ÖNERİLERİ
[WEB: "Site Adı - Konu Başlığı" | google arama terimi]
[WEB: "Site Adı - Konu Başlığı" | google arama terimi]
[WEB: "Site Adı - Konu Başlığı" | google arama terimi]

KATI KURALLAR (bozarsan cevap geçersiz):
• ASLA markdown yıldız (**) kullanma.
• Konu adını başlık olarak tekrar etme — sayfanın üstünde zaten görünüyor.
• Toplam uzunluk 35-55 satır arası — verdiğim yapı dışına çıkma.
• Numaralı bölüm başlıklarında 1️⃣, 2️⃣ … emojilerini KESİNLİKLE kullan
  (1. veya (1) yazma).
• Sayısal değerleri (sayılar, oranlar, ölçüler) net ver.
• Türkçe yaz. $exam mantığına uygun, sınav odaklı pratik dil kullan.
• YouTube ve Web önerilerini TAM OLARAK 3'er adet ver.
• Önerilen kanallar Türkçe olmalı (örn. Tonguç, Hocalara Geldik, Benim Hocam,
  Khan Academy Türkçe, MEB EBA, vb.).
''';
  }

  // Markdown yıldızlarını temizle
  String _stripMarkdown(String s) {
    return s
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
        .replaceAll('###', '')
        .replaceAll('##', '')
        .replaceAll('# ', '');
  }

  Future<void> _deleteSubject(_Subject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${s.name} silinsin mi?'),
        content: Text('Bu dersin tüm ${s.summaries.length} özeti silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
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
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SummaryDetailPage(
        summary: s,
        subjectName: subjectName,
      ),
    ));
  }

  void _openSubject(_Subject s) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => _SubjectDetailPage(
            subject: s,
            onAddTopic: (topic) =>
                _generateForExistingSubject(s, topic),
            onDelete: (sum) async {
              s.summaries.removeWhere((x) => x.id == sum.id);
              await _persistSubjects();
              if (mounted) setState(() {});
            },
          ),
        ))
        .then((_) {
      if (mounted) setState(() {});
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

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final remaining = _monthlyLimit - _monthUsed;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          _title,
          style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 10, horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _orange),
              ),
              alignment: Alignment.center,
              child: Text(
                '$remaining / $_monthlyLimit',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _orange,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  child: _showWelcome
                      ? _welcomeBanner()
                      : const SizedBox(width: double.infinity, height: 0),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _headline,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (_grade.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                    child: Text(
                      'Seviye: $_grade',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildCardsRow(),
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
          if (_generating)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _orange,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Özet hazırlanıyor…',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardsRow() {
    final cells = <Widget>[];
    for (var i = 0; i < _cardSlots; i++) {
      if (i < _subjects.length) {
        cells.add(Expanded(
          child: _subjectCard(_subjects[i]),
        ));
      } else {
        cells.add(Expanded(child: _emptyCard()));
      }
      if (i < _cardSlots - 1) {
        cells.add(const SizedBox(width: 10));
      }
    }
    return Row(children: cells);
  }

  Widget _emptyCard() {
    return GestureDetector(
      onTap: _createNewSubject,
      child: AspectRatio(
        aspectRatio: 0.85,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _blue, width: 1),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add_rounded, color: _blue, size: 26),
          ),
        ),
      ),
    );
  }

  Widget _subjectCard(_Subject s) {
    return GestureDetector(
      onTap: () => _openSubject(s),
      onLongPress: () => _deleteSubject(s),
      child: AspectRatio(
        aspectRatio: 0.85,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _blue, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _blue,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 1,
                color: _blue.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  children: s.summaries.take(3).map((sum) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${sum.topic}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 9.5,
                          color: Colors.black54,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (s.summaries.length > 3)
                Text(
                  '+${s.summaries.length - 3} daha',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _blue,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDBEAFE), Color(0xFFBFDBFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kütüphanemize hoşgeldin!',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Bottom Sheet: Yeni Ders (ders + ilk konu)
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
  final _subjectCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  final _topicFocus = FocusNode();

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _topicCtrl.dispose();
    _topicFocus.dispose();
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
            Text('Ders Başlığı',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade700,
                )),
            const SizedBox(height: 6),
            TextField(
              controller: _subjectCtrl,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _topicFocus.requestFocus(),
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: _blue,
              decoration: _inputDec('Örn. Matematik'),
            ),
            const SizedBox(height: 16),
            Text('Konu Adı',
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
              decoration: _inputDec('Örn. Türev kuralları'),
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
                label: Text(
                  'Özet Oluştur',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final subject = _subjectCtrl.text.trim();
    final topic = _topicCtrl.text.trim();
    if (subject.isEmpty || topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ders başlığı ve konu adı gerekli.'),
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
            Text('Hangi konunun özetini oluşturalım?',
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
                label: Text('Özet Oluştur',
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
  final Future<bool> Function(String topic) onAddTopic;
  final Future<void> Function(_Summary sum) onDelete;
  const _SubjectDetailPage({
    required this.subject,
    required this.onAddTopic,
    required this.onDelete,
  });
  @override
  State<_SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<_SubjectDetailPage> {
  bool _generating = false;

  Future<void> _handleAddTopic() async {
    if (_generating) return;
    final topic = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewTopicSheet(subjectName: widget.subject.name),
    );
    if (topic == null || topic.trim().isEmpty || !mounted) return;
    setState(() => _generating = true);
    final ok = await widget.onAddTopic(topic.trim());
    if (!mounted) return;
    setState(() => _generating = false);
    if (ok && widget.subject.summaries.isNotEmpty) {
      // Yeni eklenen ilk sırada
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _SummaryDetailPage(
          summary: widget.subject.summaries.first,
          subjectName: widget.subject.name,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          s.name,
          style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        onPressed: _generating ? null : _handleAddTopic,
        icon: _generating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white),
              )
            : const Icon(Icons.add_rounded),
        label: Text(_generating ? 'Hazırlanıyor…' : 'Yeni Konu',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w800)),
      ),
      body: Stack(
        children: [
          s.summaries.isEmpty
              ? Center(
                  child: Text('Bu derste henüz özet yok.',
                      style: GoogleFonts.poppins(
                          color: Colors.grey.shade500)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: s.summaries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final sum = s.summaries[i];
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
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: _blue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                    Icons.bookmark_rounded,
                                    color: _blue,
                                    size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(sum.topic,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87)),
                                    const SizedBox(height: 2),
                                    Text(dateText,
                                        style: GoogleFonts.poppins(
                                            fontSize: 11.5,
                                            color: Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                    color: Colors.grey.shade500),
                                onPressed: () async {
                                  await widget.onDelete(sum);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          if (_generating)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: _orange,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Özet hazırlanıyor…',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
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
class _SummaryDetailPage extends StatelessWidget {
  final _Summary summary;
  final String subjectName;
  const _SummaryDetailPage({
    required this.summary,
    required this.subjectName,
  });

  @override
  Widget build(BuildContext context) {
    // İçerikten kaynakları ayır
    final cleaned = _stripResourceLines(summary.content);
    final videos = _extractResources(summary.content, 'VIDEO');
    final webs = _extractResources(summary.content, 'WEB');
    final sections = _splitSections(cleaned);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          summary.topic,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _blue),
            ),
            child: Text(
              subjectName,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _blue,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (sections.isEmpty)
            _card(
              header: '',
              headerColor: Colors.black87,
              body: cleaned,
            )
          else
            ...sections.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _card(
                    header: s.header,
                    headerColor: s.color,
                    body: s.body,
                  ),
                )),
          if (videos.isNotEmpty || webs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('📚', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'QuAlsar Kaynak Önerileri',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...videos.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ResourceCard(resource: r, isVideo: true),
                )),
            if (webs.isNotEmpty) const SizedBox(height: 4),
            ...webs.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ResourceCard(resource: r, isVideo: false),
                )),
          ],
        ],
      ),
    );
  }

  // [VIDEO: "title" | query] satırlarını yakala
  List<_Resource> _extractResources(String content, String tag) {
    final re = RegExp(
        r'\[' + tag + r':\s*"([^"]+)"\s*\|\s*([^\]]+)\]',
        caseSensitive: false);
    final out = <_Resource>[];
    for (final m in re.allMatches(content)) {
      out.add(_Resource(
        title: m.group(1)!.trim(),
        query: m.group(2)!.trim(),
      ));
    }
    return out.take(3).toList();
  }

  String _stripResourceLines(String content) {
    final re = RegExp(
        r'\[(VIDEO|WEB):\s*"[^"]+"\s*\|\s*[^\]]+\]\s*$',
        caseSensitive: false, multiLine: true);
    return content.replaceAll(re, '').trim();
  }

  Widget _card({
    required String header,
    required Color headerColor,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header.isNotEmpty) ...[
            Text(
              header,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: headerColor,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
          ],
          LatexText(body, fontSize: 14, lineHeight: 1.6),
        ],
      ),
    );
  }

  // Emoji başlıklarına göre böl: 📚 🔑 📐 🎯 ⚠️
  List<_Section> _splitSections(String content) {
    const markers = {
      '📚': Color(0xFF2563EB),
      '🔑': Color(0xFF059669),
      '📐': Color(0xFF7C3AED),
      '🎯': Color(0xFFEA580C),
      '⚠️': Color(0xFFDC2626),
      '💡': Color(0xFFCA8A04),
      '🔑 ': Color(0xFF059669),
    };
    final lines = content.split('\n');
    final sections = <_Section>[];
    _Section? current;
    for (final raw in lines) {
      final line = raw.trimRight();
      final trim = line.trimLeft();
      String? foundMarker;
      for (final m in markers.keys) {
        if (trim.startsWith(m)) {
          foundMarker = m;
          break;
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
      } else if (current != null) {
        current.body += '$line\n';
      } else if (line.trim().isNotEmpty) {
        // Başlık yok, sadece düz metin — tek bölüm olarak ekle
        current = _Section(
          header: '',
          color: Colors.black87,
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

// ── Kaynak modeli + kart ──────────────────────────────────────────────────
class _Resource {
  final String title;
  final String query;
  _Resource({required this.title, required this.query});

  Uri get uri {
    final q = query.trim();
    if (q.startsWith('http://') || q.startsWith('https://')) {
      return Uri.parse(q);
    }
    return Uri.parse('https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}');
  }

  Uri get youtubeUri {
    final q = query.trim();
    if (q.startsWith('http')) return Uri.parse(q);
    return Uri.parse(
        'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(q)}');
  }
}

class _ResourceCard extends StatelessWidget {
  final _Resource resource;
  final bool isVideo;
  const _ResourceCard({required this.resource, required this.isVideo});

  Future<void> _open(BuildContext context) async {
    final uri = isVideo ? resource.youtubeUri : resource.uri;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Açılamadı: $uri'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Hata: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = isVideo ? const Color(0xFFEF4444) : _blue;
    final icon = isVideo
        ? Icons.play_circle_fill_rounded
        : Icons.public_rounded;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resource.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isVideo ? 'YouTube' : 'Web',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded,
                  size: 18, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}
