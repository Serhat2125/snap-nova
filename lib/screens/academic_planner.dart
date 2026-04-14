import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show localeService;
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Data Models
// ═══════════════════════════════════════════════════════════════════════════════

class ExamRecord {
  final String id;
  final String title;
  final String subject;
  final DateTime date;
  final TimeOfDay time;
  final bool hasAlarm;

  ExamRecord({
    required this.id,
    required this.title,
    required this.subject,
    required this.date,
    required this.time,
    this.hasAlarm = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subject,
        'date': date.toIso8601String(),
        'timeHour': time.hour,
        'timeMinute': time.minute,
        'hasAlarm': hasAlarm,
      };

  factory ExamRecord.fromJson(Map<String, dynamic> j) => ExamRecord(
        id: j['id'] as String,
        title: j['title'] as String,
        subject: j['subject'] as String,
        date: DateTime.parse(j['date'] as String),
        time: TimeOfDay(
          hour: j['timeHour'] as int,
          minute: j['timeMinute'] as int,
        ),
        hasAlarm: j['hasAlarm'] as bool? ?? false,
      );
}

class LessonRecord {
  final String id;
  final String subject;
  final int dayOfWeek; // 1=Mon .. 7=Sun
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  LessonRecord({
    required this.id,
    required this.subject,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'dayOfWeek': dayOfWeek,
        'startHour': startTime.hour,
        'startMinute': startTime.minute,
        'endHour': endTime.hour,
        'endMinute': endTime.minute,
      };

  factory LessonRecord.fromJson(Map<String, dynamic> j) => LessonRecord(
        id: j['id'] as String,
        subject: j['subject'] as String,
        dayOfWeek: j['dayOfWeek'] as int,
        startTime: TimeOfDay(
          hour: j['startHour'] as int,
          minute: j['startMinute'] as int,
        ),
        endTime: TimeOfDay(
          hour: j['endHour'] as int,
          minute: j['endMinute'] as int,
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Subject helpers
// ═══════════════════════════════════════════════════════════════════════════════

class _SubjectInfo {
  final String key;
  final IconData icon;
  final Color color;
  _SubjectInfo(this.key, this.icon, this.color);
}

final List<_SubjectInfo> _subjects = [
  _SubjectInfo('subj_math', Icons.calculate_rounded, const Color(0xFF3B82F6)),
  _SubjectInfo('subj_physics', Icons.science_rounded, const Color(0xFF8B5CF6)),
  _SubjectInfo('subj_chemistry', Icons.biotech_rounded, const Color(0xFF10B981)),
  _SubjectInfo('subj_biology', Icons.eco_rounded, const Color(0xFF22C55E)),
  _SubjectInfo('subj_geography', Icons.public_rounded, const Color(0xFFF59E0B)),
  _SubjectInfo('subj_history', Icons.menu_book_rounded, const Color(0xFFEF4444)),
  _SubjectInfo('subj_literature', Icons.auto_stories_rounded, const Color(0xFFEC4899)),
  _SubjectInfo('subj_philosophy', Icons.psychology_rounded, const Color(0xFF6366F1)),
];

// ═══════════════════════════════════════════════════════════════════════════════
//  AcademicPlanner Widget
// ═══════════════════════════════════════════════════════════════════════════════

class AcademicPlanner extends StatefulWidget {
  const AcademicPlanner({super.key});

  @override
  State<AcademicPlanner> createState() => _AcademicPlannerState();
}

class _AcademicPlannerState extends State<AcademicPlanner> {
  // ── State ──────────────────────────────────────────────────────────────────
  List<ExamRecord> _exams = [];
  List<LessonRecord> _lessons = [];
  int _selectedDayOffset = 0; // 0 = today
  Timer? _countdownTimer;
  Duration _countdown = Duration.zero;

  // Pomodoro
  Timer? _pomodoroTimer;
  int _pomodoroSeconds = 25 * 60;
  bool _pomodoroRunning = false;

  // Keys for SharedPreferences
  static const _examsKey = 'academic_planner_exams';
  static const _lessonsKey = 'academic_planner_lessons';

  // Day-name translation keys
  static const _dayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateCountdown(),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pomodoroTimer?.cancel();
    super.dispose();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final examsJson = prefs.getString(_examsKey);
    final lessonsJson = prefs.getString(_lessonsKey);
    setState(() {
      if (examsJson != null) {
        final list = jsonDecode(examsJson) as List;
        _exams = list.map((e) => ExamRecord.fromJson(e as Map<String, dynamic>)).toList();
      }
      if (lessonsJson != null) {
        final list = jsonDecode(lessonsJson) as List;
        _lessons = list.map((e) => LessonRecord.fromJson(e as Map<String, dynamic>)).toList();
      }
    });
    _updateCountdown();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_examsKey, jsonEncode(_exams.map((e) => e.toJson()).toList()));
    await prefs.setString(_lessonsKey, jsonEncode(_lessons.map((e) => e.toJson()).toList()));
  }

  // ── Countdown logic ────────────────────────────────────────────────────────

  void _updateCountdown() {
    if (_exams.isEmpty) {
      if (mounted) setState(() => _countdown = Duration.zero);
      return;
    }
    final now = DateTime.now();
    final futureExams = _exams.where((e) {
      final examDt = DateTime(e.date.year, e.date.month, e.date.day, e.time.hour, e.time.minute);
      return examDt.isAfter(now);
    }).toList()
      ..sort((a, b) {
        final aDt = DateTime(a.date.year, a.date.month, a.date.day, a.time.hour, a.time.minute);
        final bDt = DateTime(b.date.year, b.date.month, b.date.day, b.time.hour, b.time.minute);
        return aDt.compareTo(bDt);
      });

    if (futureExams.isEmpty) {
      if (mounted) setState(() => _countdown = Duration.zero);
      return;
    }
    final next = futureExams.first;
    final examDt = DateTime(next.date.year, next.date.month, next.date.day, next.time.hour, next.time.minute);
    if (mounted) {
      setState(() => _countdown = examDt.difference(now));
    }
  }

  ExamRecord? get _nextExam {
    final now = DateTime.now();
    final futureExams = _exams.where((e) {
      final examDt = DateTime(e.date.year, e.date.month, e.date.day, e.time.hour, e.time.minute);
      return examDt.isAfter(now);
    }).toList()
      ..sort((a, b) {
        final aDt = DateTime(a.date.year, a.date.month, a.date.day, a.time.hour, a.time.minute);
        final bDt = DateTime(b.date.year, b.date.month, b.date.day, b.time.hour, b.time.minute);
        return aDt.compareTo(bDt);
      });
    return futureExams.isNotEmpty ? futureExams.first : null;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _tr(String key) => localeService.tr(key);

  DateTime get _selectedDate => DateTime.now().add(Duration(days: _selectedDayOffset));

  List<dynamic> _eventsForDay(DateTime day) {
    final List<dynamic> events = [];
    // Exams on this day
    for (final e in _exams) {
      if (e.date.year == day.year && e.date.month == day.month && e.date.day == day.day) {
        events.add(e);
      }
    }
    // Lessons on this weekday
    final wd = day.weekday; // 1=Mon
    for (final l in _lessons) {
      if (l.dayOfWeek == wd) {
        events.add(l);
      }
    }
    return events;
  }

  String _subjectName(String subjectKey) => _tr(subjectKey);

  int _solutionCountForSubject(String subjectKey) {
    // Placeholder — in a real app this would query saved solutions
    return 0;
  }

  void _deleteEvent(dynamic event) {
    setState(() {
      if (event is ExamRecord) {
        _exams.removeWhere((e) => e.id == event.id);
      } else if (event is LessonRecord) {
        _lessons.removeWhere((l) => l.id == event.id);
      }
    });
    _saveData();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text(
          _tr('academic_planner'),
          style: GoogleFonts.poppins(
            color: const Color(0xFF1E293B),
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF3B82F6),
        onPressed: _showAddMenu,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildExamCountdownBanner(),
            const SizedBox(height: 16),
            _buildWeeklyCalendar(),
            const SizedBox(height: 16),
            _buildDayEvents(),
            const SizedBox(height: 20),
            _buildModeSectionTitle(),
            const SizedBox(height: 10),
            _buildModeCards(),
            const SizedBox(height: 20),
            _buildSubjectFoldersTitle(),
            const SizedBox(height: 10),
            _buildSubjectFoldersGrid(),
            const SizedBox(height: 20),
            _buildPomodoroButton(),
            const SizedBox(height: 80), // FAB clearance
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  //  1. Exam Countdown Banner
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildExamCountdownBanner() {
    final next = _nextExam;
    final days = _countdown.inDays;
    final hours = _countdown.inHours % 24;
    final minutes = _countdown.inMinutes % 60;
    final seconds = _countdown.inSeconds % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: next != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📚 ${_tr('exam_countdown')}',
                  style: GoogleFonts.poppins(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  next.title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _countdownChip('$days', _tr('days_left')),
                    const SizedBox(width: 8),
                    _countdownChip('$hours', _tr('hours_left')),
                    const SizedBox(width: 8),
                    _countdownChip('$minutes', _tr('minutes_left')),
                    const SizedBox(width: 8),
                    _countdownChip('$seconds', _tr('seconds_left')),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('no_upcoming_exams'),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _tr('keep_studying'),
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _countdownChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  //  2. Weekly Calendar
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildWeeklyCalendar() {
    final today = DateTime.now();
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = today.add(Duration(days: i));
          final dayKey = _dayKeys[(day.weekday - 1) % 7];
          final isSelected = _selectedDayOffset == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedDayOffset = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 58,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF3B82F6) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _tr(dayKey),
                    style: GoogleFonts.poppins(
                      color: isSelected ? Colors.white70 : const Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${day.day}',
                    style: GoogleFonts.poppins(
                      color: isSelected ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Day events list ────────────────────────────────────────────────────────

  Widget _buildDayEvents() {
    final events = _eventsForDay(_selectedDate);
    if (events.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Center(
          child: Text(
            _tr('no_events_today'),
            style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      children: events.map((e) {
        if (e is ExamRecord) return _examEventTile(e);
        if (e is LessonRecord) return _lessonEventTile(e);
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  Widget _examEventTile(ExamRecord exam) {
    final timeStr =
        '${exam.time.hour.toString().padLeft(2, '0')}:${exam.time.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.quiz_rounded, color: Color(0xFFEF4444), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_tr('exam_label')}: ${exam.title}',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${_subjectName(exam.subject)} • $timeStr',
                  style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
          if (exam.hasAlarm)
            const Icon(Icons.alarm_on_rounded, color: Color(0xFFF59E0B), size: 20),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
            onPressed: () => _deleteEvent(exam),
            tooltip: _tr('delete_event'),
          ),
        ],
      ),
    );
  }

  Widget _lessonEventTile(LessonRecord lesson) {
    final start =
        '${lesson.startTime.hour.toString().padLeft(2, '0')}:${lesson.startTime.minute.toString().padLeft(2, '0')}';
    final end =
        '${lesson.endTime.hour.toString().padLeft(2, '0')}:${lesson.endTime.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.class_rounded, color: Color(0xFF3B82F6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_tr('lesson_label')}: ${_subjectName(lesson.subject)}',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '$start – $end',
                  style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
            onPressed: () => _deleteEvent(lesson),
            tooltip: _tr('delete_event'),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  //  3. Mode Selection Cards
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildModeSectionTitle() {
    return Text(
      '🧠 ${_tr('quick_solve')}',
      style: GoogleFonts.poppins(
        color: const Color(0xFF1E293B),
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    );
  }

  Widget _buildModeCards() {
    final modes = [
      (_tr('step_by_step'), Icons.format_list_numbered_rounded, const Color(0xFF3B82F6)),
      (_tr('quick_solve'), Icons.flash_on_rounded, const Color(0xFFF59E0B)),
      (_tr('ai_teacher_mode'), Icons.smart_toy_rounded, AppColors.cyan),
    ];

    return Row(
      children: modes.map((m) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: m.$3.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(m.$2, color: m.$3, size: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  m.$1,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  //  4. Subject Folders
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildSubjectFoldersTitle() {
    return Text(
      '📂 ${_tr('my_folders')}',
      style: GoogleFonts.poppins(
        color: const Color(0xFF1E293B),
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    );
  }

  Widget _buildSubjectFoldersGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _subjects.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.65,
      ),
      itemBuilder: (context, i) {
        final s = _subjects[i];
        final count = _solutionCountForSubject(s.key);
        return GestureDetector(
          onTap: () => _showFolderSheet(s),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: s.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(s.icon, color: s.color, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  _subjectName(s.key),
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$count ${_tr('folder_solutions')}',
                  style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFolderSheet(_SubjectInfo s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Icon(s.icon, color: s.color, size: 36),
              const SizedBox(height: 8),
              Text(
                _subjectName(s.key),
                style: GoogleFonts.poppins(
                  color: const Color(0xFF1E293B),
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Text(
                    _tr('no_saved_solutions'),
                    style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  //  5. Pomodoro Focus Button
  // ═════════════════════════════════════════════════════════════════════════════

  Widget _buildPomodoroButton() {
    return Center(
      child: GestureDetector(
        onTap: _showPomodoroSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎯', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                _tr('focus_mode'),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPomodoroSheet() {
    _pomodoroSeconds = 25 * 60;
    _pomodoroRunning = false;
    _pomodoroTimer?.cancel();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final min = _pomodoroSeconds ~/ 60;
            final sec = _pomodoroSeconds % 60;
            final display = '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
            final isComplete = _pomodoroSeconds <= 0;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _tr('pomodoro_title'),
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF1E293B),
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (isComplete) ...[
                    const Text('🎉', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      _tr('focus_complete'),
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tr('great_focus'),
                      style: GoogleFonts.poppins(color: const Color(0xFF94A3B8), fontSize: 14),
                    ),
                  ] else ...[
                    Text(
                      display,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF3B82F6),
                        fontWeight: FontWeight.w800,
                        fontSize: 56,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Start / Pause
                      _pomodoroActionBtn(
                        label: _pomodoroRunning ? _tr('pause_timer') : _tr('start_timer'),
                        icon: _pomodoroRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: const Color(0xFF3B82F6),
                        onTap: () {
                          if (_pomodoroRunning) {
                            _pomodoroTimer?.cancel();
                            _pomodoroRunning = false;
                          } else {
                            _pomodoroRunning = true;
                            _pomodoroTimer = Timer.periodic(
                              const Duration(seconds: 1),
                              (_) {
                                if (_pomodoroSeconds > 0) {
                                  _pomodoroSeconds--;
                                  setSheetState(() {});
                                } else {
                                  _pomodoroTimer?.cancel();
                                  _pomodoroRunning = false;
                                  setSheetState(() {});
                                }
                              },
                            );
                          }
                          setSheetState(() {});
                        },
                      ),
                      const SizedBox(width: 16),
                      // Reset
                      _pomodoroActionBtn(
                        label: _tr('reset_timer'),
                        icon: Icons.refresh_rounded,
                        color: const Color(0xFFF59E0B),
                        onTap: () {
                          _pomodoroTimer?.cancel();
                          _pomodoroRunning = false;
                          _pomodoroSeconds = 25 * 60;
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _pomodoroTimer?.cancel();
      _pomodoroRunning = false;
    });
  }

  Widget _pomodoroActionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  //  FAB — Add Exam / Lesson
  // ═════════════════════════════════════════════════════════════════════════════

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              _addMenuTile(
                icon: Icons.quiz_rounded,
                color: const Color(0xFFEF4444),
                label: _tr('add_exam'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddExamSheet();
                },
              ),
              const SizedBox(height: 10),
              _addMenuTile(
                icon: Icons.class_rounded,
                color: const Color(0xFF3B82F6),
                label: _tr('add_lesson'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddLessonSheet();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _addMenuTile({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: const Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  // ── Add Exam Sheet ─────────────────────────────────────────────────────────

  void _showAddExamSheet() {
    String title = '';
    String selectedSubject = _subjects.first.key;
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);
    bool alarm = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          _tr('add_exam'),
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF1E293B),
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Title
                      Text(
                        _tr('exam_title'),
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        onChanged: (v) => title = v,
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFF0F2F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Subject
                      Text(
                        _tr('select_subject'),
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: selectedSubject,
                            items: _subjects
                                .map((s) => DropdownMenuItem(
                                      value: s.key,
                                      child: Text(
                                        _subjectName(s.key),
                                        style: GoogleFonts.poppins(fontSize: 14),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setSheetState(() => selectedSubject = v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Date
                      Row(
                        children: [
                          Expanded(
                            child: _sheetPickerTile(
                              label: _tr('select_date'),
                              value:
                                  '${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}',
                              icon: Icons.calendar_today_rounded,
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: selectedDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (d != null) setSheetState(() => selectedDate = d);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _sheetPickerTile(
                              label: _tr('select_time'),
                              value:
                                  '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                              icon: Icons.access_time_rounded,
                              onTap: () async {
                                final t = await showTimePicker(context: ctx, initialTime: selectedTime);
                                if (t != null) setSheetState(() => selectedTime = t);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Alarm toggle
                      Row(
                        children: [
                          const Icon(Icons.alarm_rounded, color: Color(0xFFF59E0B), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _tr('alarm_set'),
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF1E293B),
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: alarm,
                            activeThumbColor: const Color(0xFF3B82F6),
                            onChanged: (v) => setSheetState(() => alarm = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            if (title.trim().isEmpty) return;
                            final exam = ExamRecord(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              title: title.trim(),
                              subject: selectedSubject,
                              date: selectedDate,
                              time: selectedTime,
                              hasAlarm: alarm,
                            );
                            setState(() => _exams.add(exam));
                            _saveData();
                            _updateCountdown();
                            Navigator.pop(ctx);
                            if (alarm) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_tr('alarm_set')),
                                  backgroundColor: const Color(0xFF3B82F6),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _tr('add_exam'),
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Add Lesson Sheet ───────────────────────────────────────────────────────

  void _showAddLessonSheet() {
    String selectedSubject = _subjects.first.key;
    int selectedDay = DateTime.now().weekday; // 1=Mon
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 0);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          _tr('add_lesson'),
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF1E293B),
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Subject
                      Text(
                        _tr('select_subject'),
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: selectedSubject,
                            items: _subjects
                                .map((s) => DropdownMenuItem(
                                      value: s.key,
                                      child: Text(
                                        _subjectName(s.key),
                                        style: GoogleFonts.poppins(fontSize: 14),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setSheetState(() => selectedSubject = v);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Day of week
                      Text(
                        _tr('select_date'),
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: List.generate(7, (i) {
                          final dayNum = i + 1;
                          final isSelected = selectedDay == dayNum;
                          return GestureDetector(
                            onTap: () => setSheetState(() => selectedDay = dayNum),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFFF0F2F5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _tr(_dayKeys[i]),
                                style: GoogleFonts.poppins(
                                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      // Times
                      Row(
                        children: [
                          Expanded(
                            child: _sheetPickerTile(
                              label: _tr('start_time'),
                              value:
                                  '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
                              icon: Icons.access_time_rounded,
                              onTap: () async {
                                final t = await showTimePicker(context: ctx, initialTime: startTime);
                                if (t != null) setSheetState(() => startTime = t);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _sheetPickerTile(
                              label: _tr('end_time'),
                              value:
                                  '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                              icon: Icons.access_time_rounded,
                              onTap: () async {
                                final t = await showTimePicker(context: ctx, initialTime: endTime);
                                if (t != null) setSheetState(() => endTime = t);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            final lesson = LessonRecord(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              subject: selectedSubject,
                              dayOfWeek: selectedDay,
                              startTime: startTime,
                              endTime: endTime,
                            );
                            setState(() => _lessons.add(lesson));
                            _saveData();
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _tr('add_lesson'),
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Shared picker tile widget ──────────────────────────────────────────────

  Widget _sheetPickerTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF3B82F6), size: 18),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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
