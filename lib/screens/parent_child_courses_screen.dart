// ═══════════════════════════════════════════════════════════════════════════
//  Ebeveyn paneli alt ekranları:
//
//  • ParentChildCoursesScreen  — "Öğretmenin Verdiği Ödevler": önce DERSLER
//    (çocuğun aldığı tüm dersler yatayda 2'li ızgara); derse basınca o
//    dersten verilen ödevler (salt-okuma karne görünümü) açılır.
//  • ParentTeacherMessagesScreen — "Öğretmen Mesajları": çocuğun tüm
//    öğretmenlerinden gelen duyurular + ebeveynle paylaşılan notlar ve
//    takdirler tek akışta, GÖNDEREN öğretmen belli.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/homework_service.dart';
import '../services/parent_link_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/parent_actions_bar.dart';
import '../widgets/teacher_help_dialog.dart';
import 'teacher_student_report_screen.dart';

const _kBrand = Color(0xFF7C3AED);
const _kGreen = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);

// ═══════════════════════════════════════════════════════════════════════════
//  ÖĞRETMENİN VERDİĞİ ÖDEVLER — ders ders
// ═══════════════════════════════════════════════════════════════════════════
class ParentChildCoursesScreen extends StatefulWidget {
  final String childUid;
  final String childName;
  /// true → çocuk bağlı değilken ÖRNEK derslerle önizleme (Firestore yok).
  final bool demo;
  const ParentChildCoursesScreen(
      {super.key,
      required this.childUid,
      required this.childName,
      this.demo = false});

  @override
  State<ParentChildCoursesScreen> createState() =>
      _ParentChildCoursesScreenState();
}

/// Demo dersler — ebeveyn akışı örnek veriyle görsün diye.
const _kDemoCourses = <(String, String, String)>[
  ('Matematik', '9-A Matematik', 'Ayşe Yılmaz'),
  ('Fizik', '9-A Fizik', 'Mehmet Demir'),
  ('Kimya', '9-A Kimya', 'Elif Kaya'),
  ('Biyoloji', '9-A Biyoloji', 'Can Öztürk'),
];

class _ParentChildCoursesScreenState extends State<ParentChildCoursesScreen> {
  late Future<List<JoinedClass>> _future;
  final _shotKey = GlobalKey();
  bool _showPalette = false;
  Color? _bg;

  /// classId → AKTİF ödev sayısı (yayınlanmış + son teslimi geçmemiş).
  final Map<String, int> _activeCounts = {};
  final Set<String> _countsRequested = {};

  /// Her sınıfın aktif ödev sayısını (bir kez) arka planda yükler.
  void _loadActiveCounts(List<JoinedClass> classes) {
    for (final c in classes) {
      if (!_countsRequested.add(c.classId)) continue;
      HomeworkService.classHomeworksStream(c.classId).first.then((hws) {
        final now = DateTime.now();
        final n = hws
            .where((h) =>
                h.isPublished &&
                h.dueAt.isAfter(now) &&
                !(h.publishAt != null && h.publishAt!.isAfter(now)))
            .length;
        if (mounted) setState(() => _activeCounts[c.classId] = n);
      }).catchError((_) {});
    }
  }

  @override
  void initState() {
    super.initState();
    _future = widget.demo
        ? Future.value(const <JoinedClass>[])
        : ClassService.joinedClassesFor(widget.childUid)
            .then((l) => l.where((c) => !c.isPending).toList());
    PageBgPrefs.load('parent_courses').then((c) {
      if (mounted && c != null) setState(() => _bg = c);
    });
  }

  void _pickBg(Color? c) {
    setState(() => _bg = c);
    PageBgPrefs.save('parent_courses', c);
  }

  /// Ders adına göre kart emojisi.
  static String _subjectEmoji(String s) {
    final k = s.toLowerCase();
    if (k.contains('matematik') || k.contains('geometri')) return '📐';
    if (k.contains('fizik')) return '🔭';
    if (k.contains('kimya')) return '🧪';
    if (k.contains('biyoloji')) return '🧬';
    if (k.contains('türkçe') || k.contains('edebiyat')) return '📖';
    if (k.contains('tarih') || k.contains('inkılap')) return '🏛️';
    if (k.contains('coğrafya')) return '🌍';
    if (k.contains('ingilizce') || k.contains('dil')) return '🗣️';
    if (k.contains('fen')) return '🔬';
    if (k.contains('sosyal')) return '🧭';
    if (k.contains('din')) return '🕌';
    if (k.contains('müzik')) return '🎵';
    if (k.contains('beden') || k.contains('spor')) return '⚽';
    return '📘';
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final bg = _bg ?? AppPalette.bg(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Öğretmenin Verdiği Ödevler'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text(widget.childName,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(context))),
          ],
        ),
        actions: [
          ParentActionsPill(
            shotKey: _shotKey,
            shareText:
                '${widget.childName} — ${'Öğretmenin Verdiği Ödevler'.tr()} 📚',
            paletteOpen: _showPalette,
            onPaletteToggle: () =>
                setState(() => _showPalette = !_showPalette),
            helpTitle: 'Bu sayfa nasıl çalışır?',
            helpItems: const [
              TeacherHelpItem('📚',
                  'Dersler, çocuğunun katıldığı sınıflardan otomatik gelir.'),
              TeacherHelpItem('👆',
                  'Bir derse dokun → o dersten verilen tüm ödevler, teslim durumu ve puanlarla açılır.'),
              TeacherHelpItem('✈️',
                  'Paylaş ile bu ekranın görüntüsünü WhatsApp vb. üzerinden gönderebilirsin.'),
              TeacherHelpItem('🎨',
                  'Renk paletiyle sayfanın arka plan rengini kişiselleştirebilirsin.'),
            ],
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _shotKey,
        child: ColoredBox(
          color: bg,
          child: SafeArea(
        child: Column(
          children: [
            if (_showPalette) PageBgPaletteStrip(onPick: _pickBg),
            Expanded(
              child: FutureBuilder<List<JoinedClass>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final classes = snap.data ?? const <JoinedClass>[];
            if (!widget.demo) _loadActiveCounts(classes);
            // Demo: örnek dersler; gerçek modda boşsa bilgilendir.
            final courses = widget.demo
                ? _kDemoCourses
                : classes
                    .map((c) => (
                          c.subject.trim().isEmpty ? c.className : c.subject,
                          c.className,
                          c.teacherDisplayName,
                        ))
                    .toList();
            // Demo aktif ödev sayıları (çeşitlilik görünsün diye).
            const demoCounts = [2, 1, 3, 0];
            if (courses.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Çocuğun henüz bir derse (sınıfa) katılmamış — '
                    'katıldığında dersleri burada görünür.'.tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppPalette.textSecondary(context),
                        height: 1.45),
                  ),
                ),
              );
            }
            return Column(
              children: [
                if (widget.demo) const _DemoBanner(),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.02,
                    ),
                    itemCount: courses.length,
                    itemBuilder: (ctx, i) {
                      final (subject, className, teacher) = courses[i];
                      // Aktif ödev sayısı: verilmiş + süresi geçmemiş.
                      // null → henüz yükleniyor.
                      final int? active = widget.demo
                          ? demoCounts[i % demoCounts.length]
                          : _activeCounts[classes[i].classId];
                      return Material(
                        color: AppPalette.card(ctx),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () {
                            if (widget.demo) {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => _DemoCourseHomeworksScreen(
                                      subject: subject,
                                      className: className,
                                      teacher: teacher,
                                      childName: widget.childName)));
                              return;
                            }
                            final c = classes[i];
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TeacherStudentReportScreen(
                                  classId: c.classId,
                                  studentUid: widget.childUid,
                                  studentName: widget.childName,
                                  readOnly: true,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: AppPalette.border(ctx)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // İkon + SAĞINDA ders adı.
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color:
                                            _kBrand.withValues(alpha: 0.10),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(_subjectEmoji(subject),
                                          style: const TextStyle(
                                              fontSize: 20)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(subject,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color:
                                                AppPalette.textPrimary(ctx),
                                          )),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                // Aktif ödev sayısı — verilmiş + süresi
                                // geçmemiş ödevler.
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (active != null && active > 0
                                            ? const Color(0xFF10B981)
                                            : AppPalette
                                                .textSecondary(ctx))
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                      active == null
                                          ? '…'
                                          : active > 0
                                              ? '📝 $active ${'aktif ödev'.tr()}'
                                              : 'Aktif ödev yok'.tr(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: active != null && active > 0
                                            ? const Color(0xFF059669)
                                            : AppPalette
                                                .textSecondary(ctx),
                                      )),
                                ),
                                const SizedBox(height: 6),
                                if (teacher.trim().isNotEmpty)
                                  Text('👨‍🏫 $teacher',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: _kBrand,
                                      )),
                                Text(className,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: AppPalette.textSecondary(ctx),
                                    )),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

/// Demo ekranların üstündeki amber bilgi şeridi.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kAmber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_rounded, size: 16, color: _kAmber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Demo önizleme — örnek veriler. Çocuğunu bağlayınca gerçek '
              'dersler ve ödevler burada görünür.'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// DEMO: bir dersten verilen ödevler — teslim durumu/skor rozetleriyle,
/// gerçek karne akışının nasıl görüneceğini gösterir.
class _DemoCourseHomeworksScreen extends StatefulWidget {
  final String subject;
  final String className;
  final String teacher;
  final String childName;
  const _DemoCourseHomeworksScreen({
    required this.subject,
    required this.className,
    required this.teacher,
    required this.childName,
  });

  @override
  State<_DemoCourseHomeworksScreen> createState() =>
      _DemoCourseHomeworksScreenState();
}

class _DemoCourseHomeworksScreenState
    extends State<_DemoCourseHomeworksScreen> {
  final _shotKey = GlobalKey();
  bool _showPalette = false;
  Color? _bg;

  @override
  void initState() {
    super.initState();
    PageBgPrefs.load('parent_course_homeworks').then((c) {
      if (mounted && c != null) setState(() => _bg = c);
    });
  }

  void _pickBg(Color? c) {
    setState(() => _bg = c);
    PageBgPrefs.save('parent_course_homeworks', c);
  }

  String get subject => widget.subject;
  String get className => widget.className;
  String get teacher => widget.teacher;

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final now = DateTime.now();
    // (başlık, bitiş, durum, skor%) — durum: done | late | pending
    final items = <(String, DateTime, String, int?)>[
      ('$subject — Ünite Tekrarı', now.subtract(const Duration(days: 6)),
          'done', 85),
      ('$subject — Konu Testi (20 soru)',
          now.subtract(const Duration(days: 3)), 'done', 70),
      ('$subject — Alıştırma Ödevi', now.subtract(const Duration(days: 1)),
          'late', 55),
      ('$subject — Haftalık Ödev', now.add(const Duration(days: 2)),
          'pending', null),
    ];
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final bg = _bg ?? AppPalette.bg(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subject,
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text('$className · 👨‍🏫 $teacher',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(context))),
          ],
        ),
        actions: [
          ParentActionsPill(
            shotKey: _shotKey,
            shareText: '${widget.childName} — $subject ${'ödevleri'.tr()} 📚',
            paletteOpen: _showPalette,
            onPaletteToggle: () =>
                setState(() => _showPalette = !_showPalette),
            helpTitle: 'Bu sayfa nasıl çalışır?',
            helpItems: const [
              TeacherHelpItem('📋',
                  'Bu derste öğretmenin verdiği tüm ödevler; teslim durumu ve puan rozetleriyle.'),
              TeacherHelpItem('🏷️',
                  '✅ Teslim edildi · 🕒 Geç teslim · ⏳ Bekliyor — bitiş tarihi her kartın altında.'),
              TeacherHelpItem('✈️',
                  'Paylaş ile ekranı gönderebilir, 🎨 ile sayfa rengini değiştirebilirsin.'),
            ],
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _shotKey,
        child: ColoredBox(
          color: bg,
          child: SafeArea(
        child: Column(
          children: [
            if (_showPalette) PageBgPaletteStrip(onPick: _pickBg),
            const _DemoBanner(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final (title, due, status, score) = items[i];
                  final (label, color) = switch (status) {
                    'done' => ('✅ ${'Teslim edildi'.tr()}', _kGreen),
                    'late' => ('🕒 ${'Geç teslim'.tr()}', _kAmber),
                    _ => ('⏳ ${'Bekliyor'.tr()}', const Color(0xFF94A3B8)),
                  };
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppPalette.card(ctx),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppPalette.border(ctx)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  )),
                            ),
                            if (score != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (score >= 70 ? _kGreen : _kAmber)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('%$score',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color:
                                          score >= 70 ? _kGreen : _kAmber,
                                    )),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(label,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  )),
                            ),
                            const Spacer(),
                            Text('${'Bitiş'.tr()}: ${fmt(due)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  color: AppPalette.textSecondary(ctx),
                                )),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  ÖĞRETMEN MESAJLARI
// ═══════════════════════════════════════════════════════════════════════════
class _TeacherMsg {
  final String teacher;
  final String className;
  final String text;
  final DateTime when;
  final String kind; // 'announcement' | 'praise' | 'note'
  const _TeacherMsg(
      this.teacher, this.className, this.text, this.when, this.kind);
}

class ParentTeacherMessagesScreen extends StatefulWidget {
  final String childUid;
  final String childName;
  /// true → örnek mesajlarla önizleme (Firestore yok).
  final bool demo;
  const ParentTeacherMessagesScreen(
      {super.key,
      required this.childUid,
      required this.childName,
      this.demo = false});

  @override
  State<ParentTeacherMessagesScreen> createState() =>
      _ParentTeacherMessagesScreenState();
}

class _ParentTeacherMessagesScreenState
    extends State<ParentTeacherMessagesScreen> {
  late Future<List<_TeacherMsg>> _future;
  final _shotKey = GlobalKey();
  bool _showPalette = false;
  Color? _bg;

  @override
  void initState() {
    super.initState();
    _future = _load();
    PageBgPrefs.load('parent_messages').then((c) {
      if (mounted && c != null) setState(() => _bg = c);
    });
  }

  void _pickBg(Color? c) {
    setState(() => _bg = c);
    PageBgPrefs.save('parent_messages', c);
  }

  Future<List<_TeacherMsg>> _load() async {
    final out = <_TeacherMsg>[];
    if (widget.demo) {
      final now = DateTime.now();
      return [
        _TeacherMsg(
            'Ayşe Yılmaz',
            '9-A Matematik',
            'Yarınki derste 2. ünite tekrarı yapacağız — ödev sorularını '
                'çözerek gelin lütfen.',
            now.subtract(const Duration(hours: 3)),
            'announcement'),
        _TeacherMsg(
            'Mehmet Demir',
            '9-A Fizik',
            'Bu haftaki ödevini eksiksiz ve zamanında teslim etti, '
            'tebrikler! 🌟',
            now.subtract(const Duration(days: 1)),
            'praise'),
        _TeacherMsg(
            'Elif Kaya',
            '9-A Kimya',
            'Mol kavramında biraz zorlanıyor; evde kısa tekrarlar iyi '
            'gelecektir.',
            now.subtract(const Duration(days: 2)),
            'note'),
        _TeacherMsg(
            'Ayşe Yılmaz',
            '9-A Matematik',
            'Deneme sınavı Cuma günü — konu eksiklerini bu hafta '
            'kapatmaya çalışıyoruz.',
            now.subtract(const Duration(days: 4)),
            'announcement'),
      ];
    }
    // 1) Sınıf duyuruları (gönderen öğretmen adı payload'da).
    try {
      final anns =
          await ParentLinkService.readChildAnnouncements(widget.childUid);
      for (final a in anns) {
        out.add(_TeacherMsg(
            a.teacherName.trim().isEmpty ? 'Öğretmen' : a.teacherName,
            a.className,
            a.message,
            a.when,
            'announcement'));
      }
    } catch (_) {}
    // 2) Ebeveynle paylaşılan öğretmen notları/takdirleri (sınıf sınıf).
    try {
      final classes = await ClassService.joinedClassesFor(widget.childUid);
      for (final c in classes) {
        if (c.isPending) continue;
        try {
          final notes = await ClassService.notesStream(
                  c.classId, widget.childUid,
                  onlyShared: true)
              .first;
          for (final n in notes) {
            out.add(_TeacherMsg(
                c.teacherDisplayName.trim().isEmpty
                    ? 'Öğretmen'
                    : c.teacherDisplayName,
                c.className,
                n.text,
                n.createdAt,
                n.isPraise ? 'praise' : 'note'));
          }
        } catch (_) {}
      }
    } catch (_) {}
    out.sort((a, b) => b.when.compareTo(a.when));
    return out;
  }

  (String, Color) _kindChip(String kind) {
    switch (kind) {
      case 'announcement':
        return ('📢 ${'Duyuru'.tr()}', _kAmber);
      case 'praise':
        return ('👏 ${'Takdir'.tr()}', _kGreen);
      default:
        return ('📝 ${'Not'.tr()}', const Color(0xFF0EA5E9));
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final bg = _bg ?? AppPalette.bg(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Öğretmen Mesajları'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            Text(widget.childName,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppPalette.textSecondary(context))),
          ],
        ),
        actions: [
          ParentActionsPill(
            shotKey: _shotKey,
            shareText:
                '${widget.childName} — ${'Öğretmen Mesajları'.tr()} 📬',
            paletteOpen: _showPalette,
            onPaletteToggle: () =>
                setState(() => _showPalette = !_showPalette),
            helpTitle: 'Bu sayfa nasıl çalışır?',
            helpItems: const [
              TeacherHelpItem('📬',
                  'Çocuğunun TÜM öğretmenlerinden gelen mesajlar tek akışta, en yeni üstte.'),
              TeacherHelpItem('👨‍🏫',
                  'Her kartta gönderen öğretmen, sınıf ve tarih açıkça görünür.'),
              TeacherHelpItem('🏷️',
                  'Rozetler: 📢 Duyuru (sınıfa), 👏 Takdir (hızlı geri bildirim), 📝 Not (ebeveynle paylaşılan gözlem).'),
              TeacherHelpItem('✈️',
                  'Paylaş ile ekranı gönderebilir, 🎨 ile sayfa rengini değiştirebilirsin.'),
            ],
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _shotKey,
        child: ColoredBox(
          color: bg,
          child: SafeArea(
        child: Column(
          children: [
            if (_showPalette) PageBgPaletteStrip(onPick: _pickBg),
            Expanded(
              child: FutureBuilder<List<_TeacherMsg>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final msgs = snap.data ?? const <_TeacherMsg>[];
            if (msgs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Henüz öğretmen mesajı yok — öğretmenler duyuru '
                    'yayınladığında ya da not paylaştığında burada görünür.'
                        .tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppPalette.textSecondary(context),
                        height: 1.45),
                  ),
                ),
              );
            }
            return Column(
              children: [
                if (widget.demo) const _DemoBanner(),
                Expanded(
                  child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: msgs.length,
              itemBuilder: (ctx, i) {
                final m = msgs[i];
                final (chipLabel, chipColor) = _kindChip(m.kind);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: AppPalette.card(ctx),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppPalette.border(ctx)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: chipColor.withValues(alpha: 0.12),
                            ),
                            alignment: Alignment.center,
                            child: const Text('👨‍🏫',
                                style: TextStyle(fontSize: 17)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.teacher,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: ink,
                                    )),
                                Text(m.className,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: AppPalette.textSecondary(ctx),
                                    )),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: chipColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(chipLabel,
                                style: GoogleFonts.poppins(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: chipColor,
                                )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(m.text,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: ink,
                            height: 1.45,
                          )),
                      const SizedBox(height: 6),
                      Text(_fmt(m.when),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: AppPalette.textSecondary(ctx),
                          )),
                    ],
                  ),
                );
              },
                  ),
                ),
              ],
            );
          },
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}
