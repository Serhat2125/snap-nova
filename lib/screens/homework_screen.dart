import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../main.dart' show localeService;
import '../services/gemini_service.dart';
import '../widgets/latex_text.dart';
import 'solution_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Model
// ═══════════════════════════════════════════════════════════════════════════════

class HomeworkRecord {
  final String   id;
  final String   title;
  final String   subject;
  final DateTime dueDate;
  final bool     isDone;
  final DateTime createdAt;
  final String?  aiSolution;    // null → henüz AI çözümü yok
  final String?  solutionType;  // 'Hızlı Çözüm' | 'Adım Adım Çöz' | 'AI Öğretmen'

  const HomeworkRecord({
    required this.id,
    required this.title,
    required this.subject,
    required this.dueDate,
    this.isDone      = false,
    required this.createdAt,
    this.aiSolution,
    this.solutionType,
  });

  bool get isSolved => aiSolution != null;

  HomeworkRecord copyWith({bool? isDone, String? aiSolution, String? solutionType}) =>
      HomeworkRecord(
        id: id, title: title, subject: subject,
        dueDate: dueDate, createdAt: createdAt,
        isDone:       isDone       ?? this.isDone,
        aiSolution:   aiSolution   ?? this.aiSolution,
        solutionType: solutionType ?? this.solutionType,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'subject': subject,
        'dueDate': dueDate.toIso8601String(),
        'isDone': isDone,
        'createdAt': createdAt.toIso8601String(),
        'aiSolution': aiSolution,
        'solutionType': solutionType,
      };

  factory HomeworkRecord.fromJson(Map<String, dynamic> j) => HomeworkRecord(
        id:           j['id']           as String,
        title:        j['title']        as String,
        subject:      j['subject']      as String,
        dueDate:      DateTime.parse(j['dueDate']   as String),
        isDone:       j['isDone']       as bool? ?? false,
        createdAt:    DateTime.parse(j['createdAt'] as String),
        aiSolution:   j['aiSolution']   as String?,
        solutionType: j['solutionType'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Storage
// ═══════════════════════════════════════════════════════════════════════════════

class _HWStorage {
  static const _f = 'snap_nova_homework.json';
  static Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$_f');

  static Future<List<HomeworkRecord>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      return (jsonDecode(await f.readAsString()) as List)
          .map((e) => HomeworkRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) { return []; }
  }

  static Future<void> save(List<HomeworkRecord> r) async =>
      (await _file()).writeAsString(jsonEncode(r.map((x) => x.toJson()).toList()));
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Yardımcılar
// ═══════════════════════════════════════════════════════════════════════════════

const _subjects = [
  'Matematik','Fizik','Kimya','Biyoloji',
  'Coğrafya','Tarih','Edebiyat','Felsefe','İngilizce','Diğer',
];

IconData _iconFor(String s) => switch (s) {
  'Fizik'     => Icons.bolt_rounded,
  'Kimya'     => Icons.science_rounded,
  'Biyoloji'  => Icons.biotech_rounded,
  'Coğrafya'  => Icons.public_rounded,
  'Tarih'     => Icons.account_balance_rounded,
  'Edebiyat'  => Icons.menu_book_rounded,
  'Felsefe'   => Icons.psychology_rounded,
  'İngilizce' => Icons.translate_rounded,
  'Diğer'     => Icons.help_outline_rounded,
  _           => Icons.functions_rounded,
};

Color _colorFor(String s) => switch (s) {
  'Fizik'     => const Color(0xFFF59E0B),
  'Kimya'     => const Color(0xFF10B981),
  'Biyoloji'  => const Color(0xFF8B5CF6),
  'Coğrafya'  => const Color(0xFF06B6D4),
  'Tarih'     => const Color(0xFFEF4444),
  'Edebiyat'  => const Color(0xFFF97316),
  'Felsefe'   => const Color(0xFFA855F7),
  'İngilizce' => const Color(0xFF22C55E),
  'Diğer'     => const Color(0xFF6B7280),
  _           => const Color(0xFF3B82F6),
};

({Color color, String label, IconData icon}) _urgency(DateTime due, bool isDone) {
  if (isDone) return (color: const Color(0xFF34D399), label: localeService.tr('completed'), icon: Icons.check_circle_rounded);
  final d = due.difference(DateTime.now());
  if (d.isNegative)  return (color: const Color(0xFFEF4444), label: localeService.tr('overdue'),   icon: Icons.warning_rounded);
  if (d.inHours < 24) return (color: const Color(0xFFF97316), label: localeService.tr('today'),    icon: Icons.timer_rounded);
  if (d.inDays == 1)  return (color: const Color(0xFFF59E0B), label: localeService.tr('tomorrow'), icon: Icons.schedule_rounded);
  if (d.inDays <= 7)  return (color: const Color(0xFF60A5FA), label: '${d.inDays} ${localeService.tr("days")}', icon: Icons.event_rounded);
  return                     (color: const Color(0xFF6B7280), label: _fd(due),           icon: Icons.calendar_today_rounded);
}

String _fd(DateTime d) {
  const m = ['Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'];
  return '${d.day} ${m[d.month-1]}';
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Ana Ekran
// ═══════════════════════════════════════════════════════════════════════════════

class HomeworkScreen extends StatefulWidget {
  const HomeworkScreen({super.key});
  @override State<HomeworkScreen> createState() => _HomeworkScreenState();
}

class _HomeworkScreenState extends State<HomeworkScreen>
    with SingleTickerProviderStateMixin {

  List<HomeworkRecord> _records = [];
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    _load();
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    final r = await _HWStorage.load();
    if (mounted) setState(() => _records = r);
  }

  Future<void> _update(HomeworkRecord rec) async {
    final i = _records.indexWhere((r) => r.id == rec.id);
    if (i < 0) { _records.insert(0, rec); } else { _records[i] = rec; }
    await _HWStorage.save(_records);
    if (mounted) setState(() {});
  }

  Future<void> _delete(String id) async {
    _records.removeWhere((r) => r.id == id);
    await _HWStorage.save(_records);
    if (mounted) setState(() {});
  }

  List<HomeworkRecord> get _filtered => switch (_tab.index) {
    0 => (_records.where((r) => !r.isDone).toList()
          ..sort((a,b) => a.dueDate.compareTo(b.dueDate))),
    1 => (_records.where((r) => r.isSolved && !r.isDone).toList()
          ..sort((a,b) => a.dueDate.compareTo(b.dueDate))),
    _ => (_records.where((r) => r.isDone).toList()
          ..sort((a,b) => b.createdAt.compareTo(a.createdAt))),
  };

  int get _pending => _records.where((r) => !r.isDone).length;
  int get _solved  => _records.where((r) => r.isSolved && !r.isDone).length;
  int get _done    => _records.where((r) => r.isDone).length;

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [

          // ── Başlık ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
            child: Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localeService.tr('my_homework'), style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    _pending == 0 ? localeService.tr('all_homework_done')
                                  : '$_pending ${localeService.tr("pending")} • $_solved ${localeService.tr("ai_solved")}',
                    style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              )),
              // Ekle
              GestureDetector(
                onTap: () => _showAddSheet(),
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C2D4), Color(0xFF6B21F2)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.30), blurRadius: 12)],
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 14),

          // ── İstatistikler ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _stat(localeService.tr('pending'), _pending, Icons.hourglass_top_rounded, const Color(0xFF60A5FA)),
              const SizedBox(width: 8),
              _stat(localeService.tr('ai_solved'), _solved, Icons.auto_awesome_rounded, AppColors.cyan),
              const SizedBox(width: 8),
              _stat(localeService.tr('ok'), _done, Icons.check_circle_rounded, const Color(0xFF34D399)),
            ]),
          ),

          const SizedBox(height: 14),

          // ── Tab bar ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1526),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF00C2D4), Color(0xFF6B21F2)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500),
                tabs: const [Tab(text: 'Bekleyen'), Tab(text: 'AI Çözümlü'), Tab(text: 'Tamam')],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Liste ────────────────────────────────────────────────────────
          Expanded(
            child: list.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    physics: const BouncingScrollPhysics(),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _HWCard(
                      record: list[i],
                      onToggleDone: () => _update(list[i].copyWith(isDone: !list[i].isDone)),
                      onDelete: () => _delete(list[i].id),
                      onSolveWithAI: () => _openSolveSheet(list[i]),
                      onViewSolution: () => _openSolution(list[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  // ── Alt metotlar ─────────────────────────────────────────────────────────────

  Widget _stat(String label, int count, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$count', style: GoogleFonts.inter(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1)),
          Text(label, style: GoogleFonts.inter(
            color: color.withValues(alpha: 0.80), fontSize: 9, fontWeight: FontWeight.w600)),
        ]),
      ]),
    ),
  );

  Widget _empty() {
    const msgs = [
      'Bekleyen ödev yok.\nEklemek için + butonuna bas.',
      'Henüz AI ile çözülmüş ödev yok.\nBir ödevi seç ve "AI ile Çöz" butonuna bas.',
      'Tamamlanan ödev yok.\nÖdev tamamladıkça burada görünür.',
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.menu_book_rounded, size: 52,
              color: const Color(0xFF34D399).withValues(alpha: 0.30)),
          const SizedBox(height: 16),
          Text(msgs[_tab.index],
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13, height: 1.6)),
        ]),
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSheet(
        onSave: (rec) async { await _update(rec); },
        onSolveWithCamera: (rec) async {
          await _update(rec);
          if (!mounted) return;
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => SolutionScreen(imagePath: '')));
        },
      ),
    );
  }

  void _openSolveSheet(HomeworkRecord rec) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SolveSheet(
        record: rec,
        onSolved: (updated) async { await _update(updated); },
      ),
    );
  }

  void _openSolution(HomeworkRecord rec) {
    if (rec.aiSolution == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SolutionView(record: rec),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Ödev Kartı
// ═══════════════════════════════════════════════════════════════════════════════

class _HWCard extends StatelessWidget {
  final HomeworkRecord record;
  final VoidCallback onToggleDone;
  final VoidCallback onDelete;
  final VoidCallback onSolveWithAI;
  final VoidCallback onViewSolution;

  const _HWCard({
    required this.record,
    required this.onToggleDone,
    required this.onDelete,
    required this.onSolveWithAI,
    required this.onViewSolution,
  });

  @override
  Widget build(BuildContext context) {
    final sc  = _colorFor(record.subject);
    final urg = _urgency(record.dueDate, record.isDone);

    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
        ),
        child: const Icon(Icons.delete_rounded, color: Color(0xFFEF4444), size: 22),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0D1520),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
          ),
          title: const Text('Ödevi Sil', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: Text('"${record.title}" silinsin mi?',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal', style: TextStyle(color: AppColors.textSecondary))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sil', style: TextStyle(color: Color(0xFFEF4444)))),
          ],
        ),
      ) ?? false,
      onDismissed: (_) => onDelete(),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1526),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: record.isDone
                ? const Color(0xFF34D399).withValues(alpha: 0.20)
                : record.isSolved
                    ? AppColors.cyan.withValues(alpha: 0.28)
                    : urg.color.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [BoxShadow(
            color: (record.isSolved ? AppColors.cyan : urg.color).withValues(alpha: 0.06),
            blurRadius: 12,
          )],
        ),
        child: Column(children: [
          // ── Ana satır ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Checkbox
              GestureDetector(
                onTap: onToggleDone,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24, height: 24,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: record.isDone
                        ? const Color(0xFF34D399).withValues(alpha: 0.18)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: record.isDone ? const Color(0xFF34D399) : Colors.white.withValues(alpha: 0.22),
                      width: 1.8,
                    ),
                  ),
                  child: record.isDone
                      ? const Icon(Icons.check_rounded, color: Color(0xFF34D399), size: 14)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              // Ders ikonu
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sc.withValues(alpha: 0.28)),
                ),
                child: Icon(_iconFor(record.subject), color: sc, size: 17),
              ),
              const SizedBox(width: 10),
              // Başlık + ders adı
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(record.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: record.isDone
                        ? Colors.white.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.92),
                    fontSize: 13, fontWeight: FontWeight.w600,
                    decoration: record.isDone ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white.withValues(alpha: 0.25),
                  )),
                const SizedBox(height: 3),
                Row(children: [
                  Text(record.subject, style: GoogleFonts.inter(
                    color: sc.withValues(alpha: 0.80), fontSize: 10, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  // Aciliyet rozeti
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: urg.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: urg.color.withValues(alpha: 0.30)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(urg.icon, color: urg.color, size: 10),
                      const SizedBox(width: 3),
                      Text(urg.label, style: GoogleFonts.inter(
                        color: urg.color, fontSize: 9, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
              ])),
              const SizedBox(width: 6),
              // AI rozeti (çözüldüyse)
              if (record.isSolved)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome_rounded, color: AppColors.cyan, size: 10),
                    const SizedBox(width: 3),
                    Text('AI', style: GoogleFonts.inter(
                      color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w800)),
                  ]),
                ),
            ]),
          ),

          // ── Alt aksiyon butonu ────────────────────────────────────────────
          if (!record.isDone)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: record.isSolved
                  ? GestureDetector(
                      onTap: onViewSolution,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.30)),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.visibility_rounded, color: AppColors.cyan, size: 14),
                          const SizedBox(width: 6),
                          Text('AI Çözümünü Gör', style: GoogleFonts.inter(
                            color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    )
                  : GestureDetector(
                      onTap: onSolveWithAI,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            const Color(0xFF00C2D4).withValues(alpha: 0.15),
                            const Color(0xFF6B21F2).withValues(alpha: 0.15),
                          ]),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.auto_awesome_rounded, color: AppColors.cyan, size: 14),
                          const SizedBox(width: 6),
                          Text('AI ile Çöz', style: GoogleFonts.inter(
                            color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
            ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Ödev Ekleme Sheet'i
// ═══════════════════════════════════════════════════════════════════════════════

class _AddSheet extends StatefulWidget {
  final Future<void> Function(HomeworkRecord) onSave;
  final Future<void> Function(HomeworkRecord) onSolveWithCamera;
  const _AddSheet({required this.onSave, required this.onSolveWithCamera});
  @override State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _ctrl = TextEditingController();
  String   _subject  = 'Matematik';
  DateTime _due      = DateTime.now().add(const Duration(days: 1));

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  HomeworkRecord _build() => HomeworkRecord(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    title: _ctrl.text.trim(),
    subject: _subject,
    dueDate: _due,
    createdAt: DateTime.now(),
  );

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.cyan, surface: Color(0xFF0D1526))),
        child: child!,
      ),
    );
    if (p != null) setState(() => _due = p);
  }

  @override
  Widget build(BuildContext context) {
    final urg = _urgency(_due, false);
    final valid = _ctrl.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1526),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.22)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Tutaç
          Center(child: Container(
            width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
          )),

          Text('Ödev Ekle', style: GoogleFonts.inter(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),

          // Başlık
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Ödev veya soru yaz…',
              hintStyle: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.28), fontSize: 13),
              filled: true, fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.cyan, width: 1.4)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),

          // Ders seçimi
          Text('Ders', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SizedBox(height: 34, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _subjects.length,
            separatorBuilder: (_, __) => const SizedBox(width: 5),
            itemBuilder: (_, i) {
              final s = _subjects[i]; final sel = s == _subject; final c = _colorFor(s);
              return GestureDetector(
                onTap: () => setState(() => _subject = s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? c.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: sel ? c.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.09),
                      width: sel ? 1.3 : 1.0,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_iconFor(s), color: sel ? c : Colors.white.withValues(alpha: 0.35), size: 11),
                    const SizedBox(width: 4),
                    Text(s, style: GoogleFonts.inter(
                      color: sel ? c : Colors.white.withValues(alpha: 0.45),
                      fontSize: 10, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
              );
            },
          )),
          const SizedBox(height: 12),

          // Teslim tarihi
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: urg.color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: urg.color.withValues(alpha: 0.30)),
              ),
              child: Row(children: [
                Icon(urg.icon, color: urg.color, size: 15),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${_due.day} ${['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'][_due.month-1]} ${_due.year}',
                  style: GoogleFonts.inter(color: urg.color, fontSize: 12, fontWeight: FontWeight.w600))),
                Icon(Icons.edit_calendar_rounded, color: urg.color.withValues(alpha: 0.55), size: 14),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Aksiyon butonları ────────────────────────────────────────────
          Text('Nasıl Devam Etmek İstersin?', style: GoogleFonts.inter(
            color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          Row(children: [
            // Sadece kaydet
            Expanded(child: GestureDetector(
              onTap: valid ? () async {
                await widget.onSave(_build());
                if (mounted) Navigator.pop(context);
              } : null,
              child: _actionBtn(
                icon: Icons.bookmark_add_rounded,
                label: 'Kaydet',
                sub: 'Hatırlatıcı',
                color: const Color(0xFF6B7280),
                active: valid,
              ),
            )),
            const SizedBox(width: 8),
            // AI ile çöz
            Expanded(child: GestureDetector(
              onTap: valid ? () async {
                final rec = _build();
                await widget.onSave(rec);
                if (mounted) {
                  Navigator.pop(context);
                  // AI çözüm sheet'i ana ekrandan açılır
                  await Future.delayed(const Duration(milliseconds: 300));
                }
              } : null,
              child: _actionBtn(
                icon: Icons.auto_awesome_rounded,
                label: 'Yaz & Çöz',
                sub: 'AI ile anında çöz',
                color: AppColors.cyan,
                active: valid,
                gradient: true,
              ),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required String sub,
    required Color color,
    required bool active,
    bool gradient = false,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: active ? 1.0 : 0.35,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: gradient && active
              ? const LinearGradient(colors: [Color(0xFF00C2D4), Color(0xFF6B21F2)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: gradient ? null : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: gradient ? null : Border.all(color: color.withValues(alpha: 0.30)),
          boxShadow: gradient && active ? [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.22), blurRadius: 10)] : [],
        ),
        child: Column(children: [
          Icon(icon, color: gradient ? Colors.white : color, size: 20),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(
            color: gradient ? Colors.white : color, fontSize: 12, fontWeight: FontWeight.w800)),
          Text(sub, style: GoogleFonts.inter(
            color: (gradient ? Colors.white : color).withValues(alpha: 0.65), fontSize: 9)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  AI Çözüm Sheet'i
// ═══════════════════════════════════════════════════════════════════════════════

class _SolveSheet extends StatefulWidget {
  final HomeworkRecord record;
  final Future<void> Function(HomeworkRecord) onSolved;
  const _SolveSheet({required this.record, required this.onSolved});
  @override State<_SolveSheet> createState() => _SolveSheetState();
}

class _SolveSheetState extends State<_SolveSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.record.title);
  String  _mode    = 'Hızlı Çözüm';
  String? _result;
  bool    _loading = false;
  String? _error;

  static const _modes = [
    (label: 'Hızlı Çözüm',   icon: Icons.bolt_rounded,     color: Color(0xFFF59E0B)),
    (label: 'Adım Adım Çöz', icon: Icons.list_alt_rounded,  color: Color(0xFF3B82F6)),
    (label: 'AI Öğretmen',   icon: Icons.school_rounded,    color: Color(0xFFEC4899)),
  ];

  Future<void> _solve() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _error = null; _result = null; });
    try {
      final r = await GeminiService.solveHomework(
        question: q, solutionType: _mode, subject: widget.record.subject);
      if (!mounted) return;
      final updated = widget.record.copyWith(aiSolution: r, solutionType: _mode);
      await widget.onSolved(updated);
      setState(() { _result = r; _loading = false; });
    } on GeminiException catch (e) {
      if (mounted) setState(() { _error = e.userMessage; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sc = _colorFor(widget.record.subject);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1526),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.22)),
        ),
        child: Column(children: [
          // Tutaç + başlık
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(children: [
              Center(child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: sc.withValues(alpha: 0.28)),
                  ),
                  child: Icon(_iconFor(widget.record.subject), color: sc, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('AI ile Çöz', style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                  Text(widget.record.subject, style: GoogleFonts.inter(
                    color: sc.withValues(alpha: 0.80), fontSize: 10, fontWeight: FontWeight.w600)),
                ])),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.40), size: 20),
                ),
              ]),
            ]),
          ),

          Expanded(
            child: _result != null
                // ── Çözüm görünümü ──────────────────────────────────────────
                ? ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // Başarı rozeti
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34D399).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.30)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 16),
                          const SizedBox(width: 8),
                          Text('AI çözümü hazır!', style: GoogleFonts.inter(
                            color: const Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text(_mode, style: GoogleFonts.inter(
                            color: const Color(0xFF34D399).withValues(alpha: 0.65), fontSize: 10)),
                        ]),
                      ),
                      LatexText(_result!),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00C2D4), Color(0xFF6B21F2)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(child: Text('Tamam', style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800))),
                        ),
                      ),
                    ],
                  )
                // ── Soru + mod seçimi ────────────────────────────────────────
                : ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // Soru alanı
                      Text('Soru', style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _ctrl,
                        maxLines: 4,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Ödevi buraya yaz veya düzenle…',
                          hintStyle: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.28), fontSize: 13),
                          filled: true, fillColor: Colors.white.withValues(alpha: 0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.cyan, width: 1.4)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Çözüm tipi
                      Text('Çözüm Yöntemi', style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(children: _modes.map((m) {
                        final sel = _mode == m.label;
                        return Expanded(child: Padding(
                          padding: EdgeInsets.only(right: m.label == _modes.last.label ? 0 : 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _mode = m.label),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: sel ? m.color.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sel ? m.color.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.09),
                                  width: sel ? 1.4 : 1.0,
                                ),
                              ),
                              child: Column(children: [
                                Icon(m.icon, color: sel ? m.color : Colors.white.withValues(alpha: 0.35), size: 18),
                                const SizedBox(height: 4),
                                Text(m.label, textAlign: TextAlign.center, maxLines: 2,
                                  style: GoogleFonts.inter(
                                    color: sel ? m.color : Colors.white.withValues(alpha: 0.45),
                                    fontSize: 9, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                    height: 1.3)),
                              ]),
                            ),
                          ),
                        ));
                      }).toList()),
                      const SizedBox(height: 16),

                      // Hata
                      if (_error != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.30)),
                          ),
                          child: Text(_error!, style: GoogleFonts.inter(
                            color: const Color(0xFFEF4444), fontSize: 11)),
                        ),

                      // Çöz butonu
                      GestureDetector(
                        onTap: _loading ? null : _solve,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00C2D4), Color(0xFF6B21F2)],
                              begin: Alignment.centerLeft, end: Alignment.centerRight),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.25), blurRadius: 12)],
                          ),
                          child: Center(child: _loading
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Text('AI ile Çöz', style: GoogleFonts.inter(
                                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                                ])),
                        ),
                      ),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  AI Çözüm Görüntüleme
// ═══════════════════════════════════════════════════════════════════════════════

class _SolutionView extends StatelessWidget {
  final HomeworkRecord record;
  const _SolutionView({required this.record});

  @override
  Widget build(BuildContext context) {
    final sc  = _colorFor(record.subject);
    final urg = _urgency(record.dueDate, record.isDone);

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1526),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.22)),
        ),
        child: Column(children: [
          // Başlık
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(children: [
              Center(child: Container(
                width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: sc.withValues(alpha: 0.28))),
                  child: Icon(_iconFor(record.subject), color: sc, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(record.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  Row(children: [
                    Text(record.subject, style: GoogleFonts.inter(
                      color: sc.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: urg.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: urg.color.withValues(alpha: 0.28))),
                      child: Text(urg.label, style: GoogleFonts.inter(
                        color: urg.color, fontSize: 8, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ])),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.40), size: 20),
                ),
              ]),
            ]),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
          // Çözüm içeriği
          Expanded(child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              if (record.solutionType != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cyan.withValues(alpha: 0.22)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.auto_awesome_rounded, color: AppColors.cyan, size: 13),
                      const SizedBox(width: 6),
                      Text('${record.solutionType} • AI Çözümü', style: GoogleFonts.inter(
                        color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              LatexText(record.aiSolution ?? ''),
            ],
          )),
        ]),
      ),
    );
  }
}
