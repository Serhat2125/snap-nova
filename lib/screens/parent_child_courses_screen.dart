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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Ders kartı mini istatistikleri: aktif ödev, 24 saat alarmı, genel başarı
/// ortalaması ve tamamlanan/toplam oranı.
typedef _CourseStats = ({
  int active,
  bool urgent,
  int? avg,
  int done,
  int total,
});

class _ParentChildCoursesScreenState extends State<ParentChildCoursesScreen> {
  late Future<List<JoinedClass>> _future;
  final _shotKey = GlobalKey();
  bool _showPalette = false;
  Color? _bg;

  /// classId → kart istatistikleri (arka planda bir kez yüklenir).
  final Map<String, _CourseStats> _stats = {};
  final Set<String> _statsRequested = {};

  /// Her sınıfın ödev+teslim verisinden kart istatistiklerini çıkarır:
  /// aktif ödev sayısı, 24 saatten az kalan teslim (alarm), skor ortalaması
  /// ve tamamlanan/toplam ödev oranı.
  void _loadStats(List<JoinedClass> classes) {
    for (final c in classes) {
      if (!_statsRequested.add(c.classId)) continue;
      HomeworkService.studentReport(c.classId, widget.childUid)
          .then((entries) {
        final now = DateTime.now();
        // Öğrenciye görünür (yayınlanmış) ödevler.
        final pub = entries
            .where((e) =>
                e.homework.isPublished &&
                !(e.homework.publishAt != null &&
                    e.homework.publishAt!.isAfter(now)))
            .toList();
        final active =
            pub.where((e) => e.homework.dueAt.isAfter(now)).length;
        final urgent = pub.any((e) =>
            e.homework.dueAt.isAfter(now) &&
            e.homework.dueAt.difference(now) < const Duration(hours: 24) &&
            !(e.submission?.isSubmitted ?? false));
        final scores = <num>[
          for (final e in pub)
            if (e.submission?.scorePercent != null)
              e.submission!.scorePercent!
        ];
        final done =
            pub.where((e) => e.submission?.isSubmitted ?? false).length;
        if (!mounted) return;
        setState(() => _stats[c.classId] = (
              active: active,
              urgent: urgent,
              avg: scores.isEmpty
                  ? null
                  : (scores.reduce((a, b) => a + b) / scores.length)
                      .round(),
              done: done,
              total: pub.length,
            ));
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

  /// Ders kartındaki soldan hizalı bilgi satırı: "Etiket: değer".
  Widget _infoLine(BuildContext ctx, String label, String value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppPalette.textSecondary(ctx),
          ),
          children: [
            TextSpan(
              text: value,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color ?? AppPalette.textPrimary(ctx),
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
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
            if (!widget.demo) _loadStats(classes);
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
            // Demo kart istatistikleri (çeşitlilik görünsün diye):
            // Fizik'te 24 saat alarmı, Biyoloji'de "temiz" kart.
            const demoStats = <_CourseStats>[
              (active: 2, urgent: false, avg: 82, done: 12, total: 15),
              (active: 1, urgent: true, avg: 74, done: 8, total: 9),
              (active: 3, urgent: false, avg: 61, done: 5, total: 9),
              (active: 0, urgent: false, avg: 88, done: 9, total: 9),
            ];
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
                      // Kartta yeni satırlar var (yüzde + tamamlanan) —
                      // taşmasın diye biraz daha uzun.
                      childAspectRatio: 0.90,
                    ),
                    itemCount: courses.length,
                    itemBuilder: (ctx, i) {
                      final (subject, className, teacher) = courses[i];
                      // Kart istatistikleri — null: henüz yükleniyor.
                      final _CourseStats? st = widget.demo
                          ? demoStats[i % demoStats.length]
                          : _stats[classes[i].classId];
                      final int? active = st?.active;
                      // 4) Aktif ödevi olmayan ders → "kafamız rahat"
                      //    hissi: hafif yeşilimsi zemin + yıldız.
                      final relaxed = active == 0;
                      return Material(
                        color: relaxed
                            ? Color.alphaBlend(
                                _kGreen.withValues(alpha: 0.07),
                                AppPalette.card(ctx))
                            : AppPalette.card(ctx),
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
                              border: Border.all(
                                  color: relaxed
                                      ? _kGreen.withValues(alpha: 0.35)
                                      : AppPalette.border(ctx)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Üstte ORTALI: küçük ikon + altında ders
                                // adı. (Başarı yüzdesi kartta gösterilmez.)
                                Center(
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color:
                                          _kBrand.withValues(alpha: 0.10),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(_subjectEmoji(subject),
                                        style:
                                            const TextStyle(fontSize: 16)),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Center(
                                  child: Text(subject,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppPalette.textPrimary(ctx),
                                      )),
                                ),
                                const Spacer(),
                                // Soldan hizalı detay bloğu: öğretmen,
                                // sınıf, toplam ödev, aktif ödev.
                                if (teacher.trim().isNotEmpty)
                                  _infoLine(
                                      ctx, 'Öğretmen'.tr(), teacher,
                                      color: _kBrand),
                                _infoLine(ctx, 'Sınıf'.tr(), className),
                                _infoLine(ctx, 'Verilen ödevler'.tr(),
                                    st == null ? '…' : '${st.total}'),
                                // Aktif ödev: 24 saatten az kaldıysa ⏰
                                // turuncu; hiç yoksa ⭐ yeşil.
                                Builder(builder: (_) {
                                  final urgent = st?.urgent ?? false;
                                  final valColor = active == null
                                      ? null
                                      : urgent
                                          ? _kAmber
                                          : active > 0
                                              ? const Color(0xFF059669)
                                              : _kGreen;
                                  final v = active == null
                                      ? '…'
                                      : active > 0
                                          ? '${urgent ? '⏰ ' : ''}$active'
                                          : '⭐ ${'Yok'.tr()}';
                                  return _infoLine(
                                      ctx, 'Aktif ödev'.tr(), v,
                                      color: valColor);
                                }),
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

  /// "Çocuğuma Hatırlat" basılan ödevler (bu açılışta bir kez).
  final Set<String> _reminded = {};

  /// Sayfa başı özet: skorlu ödevlerin ortalaması + tamamlanan sayısı.
  Widget _summaryCard(
      BuildContext ctx, List<(String, String, DateTime, String, int?)> items) {
    final scores = [
      for (final it in items)
        if (it.$5 != null) it.$5!
    ];
    final avg = scores.isEmpty
        ? 0
        : (scores.reduce((a, b) => a + b) / scores.length).round();
    final done = items.where((it) => it.$4 != 'pending').length;
    final avgColor = avg >= 70 ? _kGreen : _kAmber;
    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                  )),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textSecondary(ctx),
                  )),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppPalette.card(ctx),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(ctx)),
      ),
      child: Row(
        children: [
          stat('Genel Başarı'.tr(), '%$avg', avgColor),
          Container(
              width: 1, height: 30, color: AppPalette.border(ctx)),
          stat('Tamamlanan Ödevler'.tr(), '$done/${items.length}', _kBrand),
        ],
      ),
    );
  }

  /// Kart içi küçük hap buton (AI Tavsiyesi / Çocuğuma Hatırlat).
  Widget _miniButton(BuildContext ctx,
      {required String emoji,
      required String label,
      required Color color,
      bool filled = false,
      VoidCallback? onTap}) {
    return Material(
      color: filled ? color : color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: color.withValues(alpha: filled ? 0 : 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji,
                  style: TextStyle(
                      fontSize: 12, color: filled ? Colors.white : null)),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: filled ? Colors.white : color,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  /// Ortak alt-sayfa iskeleti (analiz + AI tavsiyesi sheet'leri).
  Future<void> _openSheet(BuildContext context, Widget child) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: child,
        ),
      ),
    );
  }

  /// 1) "Ödev Analizi" — soru bazlı D/Y ızgarası + kısa AI analizi.
  ///    Demo: 20 soru, yanlışlar skora göre deterministik dağıtılır.
  void _openAnalysis(
      BuildContext context, String title, int score, String status) {
    const total = 20;
    final correct = (total * score / 100).round();
    final wrong = total - correct;
    // Yanlış soruları eşit aralıklarla dağıt (deterministik — demo).
    final wrongIdx = <int>{
      for (var k = 0; k < wrong; k++) ((k + 0.5) * total / wrong).floor()
    };
    final child = widget.childName;
    final analysis = score >= 80
        ? '$child ${'bu ödevde harika iş çıkardı; kavram sorularının tamamına doğru yanıt verdi. Yanlışları dikkatsizlik kaynaklı görünüyor — sınav öncesi kısa bir kontrol alışkanlığı yeterli.'.tr()}'
        : score >= 65
            ? '$child ${'genel olarak iyi durumda; temel kavramlar oturmuş. Yanlışlar ağırlıkla işlem/uygulama sorularında — benzer tipte 5-10 soruluk kısa tekrarlar farkı kapatır.'.tr()}'
            : '$child ${'bu konuda temel kavramlarda eksikler görünüyor; özellikle yorum gerektiren sorularda zorlanmış. Konu özetini birlikte gözden geçirip kolay sorulardan başlaması özgüvenini toparlar.'.tr()}';
    _openSheet(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    )),
              ),
              Text('%$score',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: score >= 70 ? _kGreen : _kAmber,
                  )),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '✅ $correct ${'doğru'.tr()} · ❌ $wrong ${'yanlış'.tr()}'
              '${status == 'late' ? ' · 🕒 ${'Geç teslim'.tr()}' : ''}',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
              )),
          const SizedBox(height: 12),
          // Soru ızgarası — hangi soru doğru/yanlış tek bakışta.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < total; i++)
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (wrongIdx.contains(i)
                            ? const Color(0xFFEF4444)
                            : _kGreen)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: wrongIdx.contains(i)
                            ? const Color(0xFFEF4444)
                            : _kGreen,
                        width: 1.2),
                  ),
                  child: Text('${i + 1}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: wrongIdx.contains(i)
                            ? const Color(0xFFEF4444)
                            : _kGreen,
                      )),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kBrand.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBrand.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🤖 ${'Yapay Zekâ Analizi'.tr()}',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: _kBrand,
                    )),
                const SizedBox(height: 5),
                Text(analysis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      height: 1.5,
                      color: AppPalette.textPrimary(context),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2) "AI Tavsiyesi" — geç teslim / düşük skor için veliye destek reçetesi.
  void _openAdvice(
      BuildContext context, String title, int? score, String status) {
    final child = widget.childName;
    final late_ = status == 'late';
    final advice = late_ && (score ?? 100) < 70
        ? '$child ${'bu ödevi geç teslim etti ve başarı oranı biraz düşük kaldı. Bu konudaki eksiklerini kapatması için onu motive edebilir, ödüllerini bu konuyu tekrar etmesi şartına bağlayabilirsiniz. Kızmak yerine "birlikte bakalım" yaklaşımı bu yaşta çok daha iyi çalışır.'.tr()}'
        : late_
            ? '$child ${'ödevi geç teslim etti ama başarısı iyi. Sorun bilgide değil zaman yönetiminde görünüyor — akşamları 20 dakikalık sabit bir "ödev saati" belirlemek geç teslimleri azaltır.'.tr()}'
            : '$child ${'için bu ödevin başarı oranı düşük kaldı. Konuyu anlamadığı yerleri öğretmenine sormaya teşvik edebilir, uygulamadaki konu özetini birlikte 10 dakika gözden geçirebilirsiniz. Küçük bir ilerlemeyi bile övmek motivasyonunu belirgin artırır.'.tr()}';
    _openSheet(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🤖 ${'AI Destek Reçetesi'.tr()}',
              style: GoogleFonts.poppins(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
              )),
          const SizedBox(height: 3),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppPalette.textSecondary(context),
              )),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _kBrand.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBrand.withValues(alpha: 0.25)),
            ),
            child: Text(advice,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  height: 1.55,
                  color: AppPalette.textPrimary(context),
                )),
          ),
        ],
      ),
    );
  }

  /// 3) "Çocuğuma Hatırlat" — yazışmasız teşvik; çocuğun uygulamasına tatlı
  ///    bir bildirim gider (demo: yalnız görsel onay).
  void _remind(String title) {
    if (_reminded.contains(title)) return;
    setState(() => _reminded.add(title));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(
          '🔔 ${'Hatırlatma gönderildi — çocuğuna "Ailen, yaklaşan ödevini sana hatırlatıyor, başarılar!" bildirimi gidecek.'.tr()}'),
    ));
  }

  /// Derse göre örnek konu adları — kart başında ders adı tekrar etmez
  /// (ders zaten sayfa başlığında), bunun yerine KONU gösterilir.
  static List<String> _topicsFor(String subject) {
    final k = subject.toLowerCase();
    if (k.contains('matematik') || k.contains('geometri')) {
      return ['Denklemler', 'Oran-Orantı', 'Üslü Sayılar', 'Problemler'];
    }
    if (k.contains('fizik')) {
      return ['Kuvvet ve Hareket', 'Enerji', 'Basınç', 'Optik'];
    }
    if (k.contains('kimya')) {
      return ['Maddenin Yapısı', 'Mol Kavramı', 'Karışımlar', 'Asit-Baz'];
    }
    if (k.contains('biyoloji')) {
      return ['Hücre', 'Hücre Bölünmeleri', 'Kalıtım', 'Ekosistem'];
    }
    return ['Ünite 1', 'Ünite 2', 'Ünite 3', 'Ünite 4'];
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final now = DateTime.now();
    final topics = _topicsFor(subject);
    // (başlık, konu, bitiş, durum, skor%) — durum: done | late | pending
    final items = <(String, String, DateTime, String, int?)>[
      ('Ünite Tekrarı', topics[0], now.subtract(const Duration(days: 6)),
          'done', 85),
      ('Konu Testi (20 soru)', topics[1],
          now.subtract(const Duration(days: 3)), 'done', 70),
      ('Alıştırma Ödevi', topics[2], now.subtract(const Duration(days: 1)),
          'late', 55),
      ('Haftalık Ödev', topics[3], now.add(const Duration(days: 2)),
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
            // 4) Dersin genel gidişatı tek bakışta.
            _summaryCard(context, items),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final (title, topic, due, status, score) = items[i];
                  final (label, color) = switch (status) {
                    'done' => ('✅ ${'Teslim edildi'.tr()}', _kGreen),
                    'late' => ('🕒 ${'Geç teslim'.tr()}', _kAmber),
                    _ => ('⏳ ${'Bekliyor'.tr()}', const Color(0xFF94A3B8)),
                  };
                  // AI tavsiyesi: geç teslim veya düşük başarı kartlarında.
                  final needsAdvice =
                      status == 'late' || (score != null && score < 70);
                  final reminded = _reminded.contains(title);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Material(
                    color: AppPalette.card(ctx),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      // 1) Skorlu kart → soru bazlı ödev analizi sheet'i.
                      onTap: score == null
                          ? null
                          : () => _openAnalysis(
                              ctx, '$title · $topic', score, status),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppPalette.border(ctx)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: ink,
                                      )),
                                  // Konu adı — ders adı sayfa başlığında
                                  // zaten var, kartta tekrar edilmez.
                                  Text('📌 $topic',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            AppPalette.textSecondary(ctx),
                                      )),
                                ],
                              ),
                            ),
                            if (score != null) ...[
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
                              // Analize açılabilir olduğunun işareti.
                              Icon(Icons.chevron_right_rounded,
                                  size: 18,
                                  color: AppPalette.textSecondary(ctx)),
                            ],
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
                        // 2) AI destek reçetesi — düşük skor / geç teslim.
                        if (needsAdvice) ...[
                          const SizedBox(height: 9),
                          _miniButton(
                            ctx,
                            emoji: '🤖',
                            label: 'AI Tavsiyesi'.tr(),
                            color: _kBrand,
                            onTap: () => _openAdvice(
                                ctx, '$title · $topic', score, status),
                          ),
                        ],
                        // 3) Bekleyen ödev → yazışmasız hatırlatma sinyali.
                        if (status == 'pending') ...[
                          const SizedBox(height: 9),
                          _miniButton(
                            ctx,
                            emoji: reminded ? '✓' : '🔔',
                            label: reminded
                                ? 'Hatırlatıldı'.tr()
                                : 'Çocuğuma Hatırlat'.tr(),
                            color: _kGreen,
                            filled: reminded,
                            onTap: reminded ? null : () => _remind(title),
                          ),
                        ],
                      ],
                    ),
                      ),
                    ),
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
  /// Sessiz geri bildirimde öğretmen uid'si classes/{classId}'den çözülür.
  final String classId;
  const _TeacherMsg(
      this.teacher, this.className, this.text, this.when, this.kind,
      {this.classId = ''});

  /// Mesaj başına kalıcı geri bildirim anahtarı (cihazda saklanır).
  String get ackKey =>
      '$classId|$kind|${when.millisecondsSinceEpoch}|${text.hashCode}';
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

  /// Üst filtre çipi: 'all' | 'announcement' | 'praise' | 'note'.
  String _filter = 'all';

  /// Mesaj başına gönderilmiş sessiz geri bildirim: ackKey → 'seen'|'study'.
  /// Cihazda kalıcı (SharedPreferences) — veli aynı mesaja iki kez basamaz.
  final Map<String, String> _acks = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
    PageBgPrefs.load('parent_messages').then((c) {
      if (mounted && c != null) setState(() => _bg = c);
    });
    SharedPreferences.getInstance().then((p) {
      final list =
          p.getStringList('parent_msg_acks_${widget.childUid}') ?? const [];
      if (!mounted || list.isEmpty) return;
      setState(() {
        for (final e in list) {
          final i = e.lastIndexOf('=');
          if (i > 0) _acks[e.substring(0, i)] = e.substring(i + 1);
        }
      });
    });
  }

  void _saveAcks() {
    SharedPreferences.getInstance().then((p) => p.setStringList(
        'parent_msg_acks_${widget.childUid}',
        _acks.entries.map((e) => '${e.key}=${e.value}').toList()));
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
            'announcement',
            classId: a.classId));
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
                n.isPraise ? 'praise' : 'note',
                classId: c.classId));
          }
        } catch (_) {}
      }
    } catch (_) {}
    out.sort((a, b) => b.when.compareTo(a.when));
    return out;
  }

  /// Sessiz geri bildirim: veli yazışamaz ama "gördüm" sinyali gönderebilir.
  /// Öğretmenin bildirim kutusuna parent_ack doc'u yazılır (rules: create
  /// serbest); veli tarafında seçim cihazda kalıcıdır — mesaj başına 1 kez.
  Future<void> _sendAck(_TeacherMsg m, String kind) async {
    if (_acks.containsKey(m.ackKey)) return;
    setState(() => _acks[m.ackKey] = kind);
    _saveAcks();
    var delivered = widget.demo;
    if (!widget.demo && m.classId.isNotEmpty) {
      try {
        final cls = await FirebaseFirestore.instance
            .collection('classes')
            .doc(m.classId)
            .get();
        final teacherUid = (cls.data()?['teacherUid'] ?? '').toString();
        if (teacherUid.isNotEmpty) {
          final short =
              m.text.length > 80 ? '${m.text.substring(0, 80)}…' : m.text;
          await FirebaseFirestore.instance
              .collection('notifications')
              .doc(teacherUid)
              .collection('items')
              .add({
            'type': 'parent_ack',
            'ackKind': kind,
            'className': m.className,
            'childName': widget.childName,
            'title': kind == 'study'
                ? '${widget.childName} velisi: Evde çalışacağız 🎯'
                : '${widget.childName} velisi mesajını gördü 👍',
            'body': kind == 'study'
                ? '"$short" mesajın için evde çalışacaklarını belirtti.'
                : '"$short" mesajını gördü ve onayladı.',
            'when': FieldValue.serverTimestamp(),
            'read': false,
          });
          delivered = true;
        }
      } catch (_) {/* best-effort — veli tarafındaki işaret yine kalır */}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(delivered
          ? 'Öğretmene iletildi ✅'.tr()
          : 'Kaydedildi — öğretmene şu an ulaşılamadı.'.tr()),
    ));
  }

  /// Kart altı sessiz geri bildirim butonları. Seçim yapılınca seçilen
  /// dolgulu kalır, diğeri soluklaşır; ikisi de kilitlenir.
  Widget _ackButtons(BuildContext ctx, _TeacherMsg m) {
    final chosen = _acks[m.ackKey];
    Widget btn(String kind, String emoji, String label, Color color) {
      final isChosen = chosen == kind;
      final locked = chosen != null;
      return Expanded(
        child: Opacity(
          opacity: locked && !isChosen ? 0.35 : 1,
          child: Material(
            color: isChosen ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: locked ? null : () => _sendAck(m, kind),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: color.withValues(alpha: isChosen ? 0 : 0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isChosen ? '✓' : emoji,
                        style: TextStyle(
                            fontSize: 12,
                            color: isChosen ? Colors.white : null)),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: isChosen ? Colors.white : color,
                          )),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        btn('seen', '👍', 'Okundu / Anlaşıldı'.tr(), _kGreen),
        const SizedBox(width: 8),
        btn('study', '🎯', 'Evde Çalışacağız'.tr(), _kBrand),
      ],
    );
  }

  /// Üstteki kaydırılabilir filtre çipleri (Hepsi/Duyuru/Takdir/Not).
  Widget _filterBar(BuildContext ctx) {
    const items = [
      ('all', 'Hepsi'),
      ('announcement', '📢 Duyurular'),
      ('praise', '🌟 Takdirler'),
      ('note', '⚠️ Uyarılar/Notlar'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (key, rawLabel) = items[i];
          final sel = _filter == key;
          return Material(
            color: sel ? _kBrand : AppPalette.card(ctx),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: () => setState(() => _filter = key),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: sel ? _kBrand : AppPalette.border(ctx)),
                ),
                child: Text(rawLabel.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: sel ? Colors.white : AppPalette.textPrimary(ctx),
                    )),
              ),
            ),
          );
        },
      ),
    );
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
            final shown = _filter == 'all'
                ? msgs
                : msgs.where((m) => m.kind == _filter).toList();
            return Column(
              children: [
                if (widget.demo) const _DemoBanner(),
                const SizedBox(height: 8),
                _filterBar(context),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text('Bu filtrede mesaj yok.'.tr(),
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                color: AppPalette.textSecondary(context),
                              )),
                        )
                      : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: shown.length,
              itemBuilder: (ctx, i) {
                final m = shown[i];
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
                      const SizedBox(height: 10),
                      // Sessiz geri bildirim — veli yazamaz ama öğretmene
                      // "gördüm/ilgileniyorum" sinyali gönderebilir.
                      _ackButtons(ctx, m),
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
