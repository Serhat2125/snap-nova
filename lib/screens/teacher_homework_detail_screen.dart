// ═══════════════════════════════════════════════════════════════════════════
//  TeacherHomeworkDetailScreen — Tek ödevin öğrenci-bazlı analiz paneli.
//
//  Üstte profil + ödev künyesi (kaçıncı ödev, ad, başlangıç/bitiş tarihleri).
//  Altında Grafik | Tablo sekmesi:
//    • Grafik → doğru/yanlış/boş pasta dağılımı + yan istatistik.
//    • Tablo  → Excel benzeri istatistik tablosu + soru-soru durum.
//  Her ikisinin altında "Öğrencinin verdiği cevaplara bak" → cevap görünümü.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/education_models.dart';
import '../services/class_service.dart';
import '../services/gemini_service.dart';
import '../services/homework_service.dart';
import '../services/locale_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../widgets/teacher_help_dialog.dart';
import 'teacher_homework_view_screen.dart';

const _kBrand = Color(0xFF7C3AED);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kGray = Color(0xFF94A3B8);
const _kAmber = Color(0xFFF59E0B);

class TeacherHomeworkDetailScreen extends StatefulWidget {
  final HomeworkModel homework;
  final HomeworkSubmissionModel? submission;
  final String studentName;
  final String studentAvatar;
  final int orderNo; // kaçıncı ödev (1, 2, 3…)
  const TeacherHomeworkDetailScreen({
    super.key,
    required this.homework,
    required this.submission,
    required this.studentName,
    required this.orderNo,
    this.studentAvatar = '👤',
  });

  @override
  State<TeacherHomeworkDetailScreen> createState() =>
      _TeacherHomeworkDetailScreenState();
}

class _TeacherHomeworkDetailScreenState
    extends State<TeacherHomeworkDetailScreen> {
  int _tab = 0; // 0 = Grafik, 1 = Tablo
  bool _qExpanded = true; // "Soru bazında" tablosu açık/kapalı
  bool _answersExpanded = false; // "Öğrencinin cevapları" inline panel açık/kapalı
  final GlobalKey _shotKey = GlobalKey(); // ekran görüntüsü (ebeveyne gönder)
  double? _classAvg; // #4 bu ödev için sınıf ortalaması (%)

  @override
  void initState() {
    super.initState();
    _loadClassAverage();
  }

  /// #4 — Bu ödev için sınıf ortalamasını (teslim eden öğrenciler) hesaplar.
  Future<void> _loadClassAverage() async {
    try {
      final rows = await HomeworkService.classGradeSummary(
          hw.classId, homeworkId: hw.id);
      final submittedRows =
          rows.where((r) => r.totalQuestions > 0).toList();
      if (submittedRows.isEmpty) return;
      final avg = submittedRows.fold<double>(0, (s, r) => s + r.pct) /
          submittedRows.length;
      if (mounted) setState(() => _classAvg = avg);
    } catch (_) {}
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// O an ekranda olan grafik+verileri PNG olarak yakalar ve paylaşım
  /// sayfasını açar (WhatsApp/Telegram vb. ile ebeveyne gönderilebilir).
  Future<void> _shareScreenshot() async {
    try {
      // Mevcut çerçeve bitmeden toImage() çağrılırsa hata verir — bir frame bekle.
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      final boundary =
          _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) {
        _snack('Ekran henüz hazır değil, tekrar dene.'.tr());
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        _snack('Görüntü oluşturulamadı.'.tr());
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/odev_raporu_${widget.orderNo}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      final name = widget.studentName.trim();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${name.isEmpty ? '' : '$name — '}'
            '${'Ödev raporu'.tr()} (${widget.orderNo}. ${'Ödev'.tr()}) 📊',
      );
    } catch (e) {
      _snack('${'Paylaşım başarısız'.tr()}: $e');
    }
  }

  HomeworkModel get hw => widget.homework;
  HomeworkSubmissionModel? get sub => widget.submission;
  bool get submitted => sub?.isSubmitted ?? false;

  // ── Doğru / yanlış / boş / bekliyor sayıları ───────────────────────────
  ({int total, int correct, int wrong, int empty, int pending, double pct})
      get _stats {
    int correct = 0, wrong = 0, empty = 0, pending = 0;
    final answers = sub?.answers ?? const <SubmissionAnswer>[];
    if (answers.isNotEmpty) {
      for (final a in answers) {
        final blank = a.studentAnswer.trim().isEmpty;
        if (blank) {
          empty++;
        } else if (a.isCorrect == true) {
          correct++;
        } else if (a.isCorrect == false) {
          wrong++;
        } else {
          pending++;
        }
      }
    } else {
      correct = sub?.correct ?? 0;
      wrong = sub?.wrong ?? 0;
    }
    // Toplam soru: ödevin soru sayısı, yoksa cevap sayısı, o da yoksa
    // sayımların toplamı (asla 0'a bölünme olmasın).
    final qCount =
        hw.questionCount > 0 ? hw.questionCount : answers.length;
    final total = qCount > 0 ? qCount : (correct + wrong + empty + pending);
    // Cevaplanmayan/eksik kalan soruları boş say (slice'lar toplamı = total).
    final counted = correct + wrong + empty + pending;
    if (total > counted) empty += total - counted;
    // Başarı oranı TOPLAM sorulan soru üzerinden (boş/yanlış da paydada).
    final pct = total > 0 ? correct * 100 / total : 0.0;
    return (
      total: total,
      correct: correct,
      wrong: wrong,
      empty: empty,
      pending: pending,
      pct: pct
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('${widget.orderNo}. ${'Ödev'.tr()}',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
        actions: [
          // Gönder (ebeveyne paylaş) — çerçeve içinde, WhatsApp yeşili.
          _appBarBox(
            context,
            Transform.rotate(
              angle: -math.pi / 4,
              child: const Icon(Icons.send_rounded,
                  color: Color(0xFF25D366), size: 20),
            ),
            'Ebeveyne gönder'.tr(),
            _shareScreenshot,
          ),
          // Bu sayfa nasıl çalışır? — sadece "?" ikonu, küçük çerçeve.
          _appBarBox(
            context,
            Icon(Icons.help_outline_rounded,
                size: 20, color: AppPalette.textPrimary(context)),
            'Bu sayfa nasıl çalışır?'.tr(),
            _showHelp,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RepaintBoundary(
        key: _shotKey,
        child: ColoredBox(
          color: AppPalette.bg(context),
          child: SafeArea(
            child: Column(
              children: [
            // SABİT başlık: profil + ödev (sayfa kaydırılsa da sabit kalır).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  _profileHeader(context),
                  const SizedBox(height: 12),
                  _homeworkMeta(context),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                'Öğrenci verilerini nasıl görmek istersin?'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
              ),
            ),
            _tabBar(context),
            const SizedBox(height: 14),
            if (!submitted)
              _notSubmitted(context)
            else ...[
              _tab == 0 ? _graphSection(context) : _tableSection(context),
              const SizedBox(height: 12),
              // #1 AI özet yorum (öğrenci cevaplarının analizi).
              _AiHomeworkInsight(
                studentName: widget.studentName,
                homework: hw,
                submission: sub,
                stats: _stats,
              ),
              const SizedBox(height: 12),
              _answersButton(context),
              if (_answersExpanded) ...[
                const SizedBox(height: 12),
                HomeworkAnswersList(homework: hw, submission: sub),
              ],
              // #5a Veliye/öğrenciye not gönder.
              const SizedBox(height: 10),
              _sendNoteButton(context),
            ],
                ],
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// AppBar'da çerçeveli küçük ikon-buton (gönder / "?" yardım).
  Widget _appBarBox(BuildContext context, Widget icon, String tooltip,
      VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppPalette.border(context)),
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }

  /// "?" → bu sayfa nasıl çalışır kısa rehberi.
  Future<void> _showHelp() async {
    await showTeacherHelpDialog(
      context,
      title: 'Bu sayfa nasıl çalışır?',
      items: const [
        TeacherHelpItem('📊',
            '“Grafik” sekmesi doğru/yanlış/boş dağılımını; “Tablo” sekmesi sayısal istatistikleri gösterir.'),
        TeacherHelpItem('🔎',
            'Tabloda “Soruları detaylı göster” ile her sorunun durumunu (doğru/yanlış/boş) açabilirsin.'),
        TeacherHelpItem('🤖',
            '“AI yorumu” öğrencinin cevaplarını analiz edip güçlü/zayıf yönleri özetler.'),
        TeacherHelpItem('📨',
            'Sağ üstteki gönder ikonuyla ekranı ebeveyne (WhatsApp vb.) iletebilirsin.'),
        TeacherHelpItem('✍️',
            '“Veliye/öğrenciye not gönder” ile kısa bir geri bildirim yazabilirsin.'),
        TeacherHelpItem('📌',
            'Üstteki öğrenci ve ödev bilgisi, sayfa kaydırılsa da sabit kalır.'),
      ],
    );
  }

  // ── #5a Veliye/öğrenciye not gönder butonu + dialog ───────────────────
  Widget _sendNoteButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openNoteDialog,
        style: OutlinedButton.styleFrom(
          foregroundColor: _kGreen,
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: const BorderSide(color: _kGreen, width: 1.3),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.rate_review_rounded, size: 18),
        label: Text('Veliye/öğrenciye not gönder'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Future<void> _openNoteDialog() async {
    final studentUid = sub?.studentUid ?? '';
    if (studentUid.isEmpty) {
      _snack('Öğrenci bilgisi bulunamadı.'.tr());
      return;
    }
    final ctrl = TextEditingController();
    const quick = [
      'Harika iş, tebrik ederim! 🌟',
      'Güzel ilerleme, böyle devam! 👏',
      'Eksik konulara biraz daha çalışalım.',
    ];
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 14, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
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
                    borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text('Not gönder'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w900,
                      color: AppPalette.textPrimary(ctx))),
              const SizedBox(height: 4),
              Text('${widget.studentName} • ${'veli panelinde de görünür'.tr()}',
                  style: GoogleFonts.poppins(
                      fontSize: 11.5, color: AppPalette.textSecondary(ctx))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: quick.map((q) => GestureDetector(
                  onTap: () => setM(() => ctrl.text = q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kGreen.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: _kGreen.withValues(alpha: 0.30)),
                    ),
                    child: Text(q,
                        style: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: const Color(0xFF065F46))),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                maxLength: 300,
                style: GoogleFonts.poppins(
                    fontSize: 13.5, color: AppPalette.textPrimary(ctx)),
                decoration: InputDecoration(
                  hintText: 'Notunu yaz…'.tr(),
                  hintStyle: GoogleFonts.poppins(
                      fontSize: 13, color: AppPalette.textSecondary(ctx)),
                  filled: true,
                  fillColor: AppPalette.bg(ctx),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppPalette.border(ctx)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppPalette.border(ctx)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kGreen, width: 1.5),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kGreen,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (ctrl.text.trim().isEmpty) return;
                    final ok = await ClassService.addNote(
                        hw.classId, studentUid, ctrl.text.trim(),
                        kind: 'praise');
                    if (ctx.mounted) Navigator.pop(ctx, ok);
                  },
                  child: Text('Gönder'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (sent == true) {
      _snack('Not gönderildi.'.tr());
    } else if (sent == false) {
      _snack('Not gönderilemedi, tekrar dene.'.tr());
    }
  }

  // ── #3 Harcanan süre (dk) — activeMs ya da başlangıç→teslim farkı ─────
  int? _spentMinutes() {
    final s = sub;
    if (s == null) return null;
    if (s.activeMs != null && s.activeMs! > 0) {
      return (s.activeMs! / 60000).round();
    }
    if (s.startedAt != null && s.submittedAt != null) {
      final d = s.submittedAt!.difference(s.startedAt!).inMinutes;
      if (d > 0) return d;
    }
    return null;
  }

  // ── #2 Durum etiketi (label + renk) ───────────────────────────────────
  (String, Color) _statusInfo() {
    if (!submitted) {
      return hw.isOverdue
          ? ('Süresi Geçti'.tr(), _kRed)
          : ('Bekliyor'.tr(), _kAmber);
    }
    // Teslim edildi — açık uçlu sorular hâlâ puanlanmayı bekliyorsa "Kontrol bekliyor".
    return _stats.pending > 0
        ? ('Kontrol bekliyor'.tr(), const Color(0xFF3B82F6))
        : ('Tamamlandı'.tr(), _kGreen);
  }

  Widget _statusBadge(BuildContext context) {
    final (label, color) = _statusInfo();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
    );
  }

  // ── Profil (en üstte) ──────────────────────────────────────────────────
  Widget _profileHeader(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    return Row(
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kBrand.withValues(alpha: 0.12),
          ),
          alignment: Alignment.center,
          child: Text(widget.studentAvatar,
              style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(widget.studentName,
              style: GoogleFonts.poppins(
                fontSize: 17, fontWeight: FontWeight.w900, color: ink,
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // ── Ödev künyesi ───────────────────────────────────────────────────────
  //  Sol: konu → ödev adı → ödev no.  Sağ üst (küçük): başlangıç → bitiş → soru.
  Widget _homeworkMeta(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SOL: konu / ödev adı / ödev no
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${hw.subject} · ${hw.topic}',
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w700,
                        color: muted),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(hw.title,
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w900,
                        color: ink, height: 1.2),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                // Ödev no + #2 durum etiketi yan yana.
                Wrap(
                  spacing: 6, runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kBrand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${widget.orderNo}. ${'Ödev'.tr()}',
                          style: GoogleFonts.poppins(
                              fontSize: 10.5, fontWeight: FontWeight.w800,
                              color: _kBrand)),
                    ),
                    _statusBadge(context),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // SAĞ ÜST: küçük başlangıç / bitiş / soru / #3 harcanan süre
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _rightInfo(context, '🟢', 'Başlangıç'.tr(),
                  _fmtDate(hw.assignedAt)),
              const SizedBox(height: 6),
              _rightInfo(context, '🔴', 'Bitiş'.tr(), _fmtDate(hw.dueAt)),
              const SizedBox(height: 6),
              _rightInfo(context, '❓', 'Soru'.tr(), '${_stats.total}'),
              if (_spentMinutes() != null) ...[
                const SizedBox(height: 6),
                _rightInfo(context, '⏱️', 'Harcanan süre'.tr(),
                    '${_spentMinutes()} ${'dk'.tr()}'),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _rightInfo(
      BuildContext context, String emoji, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$emoji $label',
            style: GoogleFonts.poppins(
                fontSize: 8.5, fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context))),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context))),
      ],
    );
  }

  // ── Grafik | Tablo sekme çubuğu ────────────────────────────────────────
  Widget _tabBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          _tabBtn(context, 0, Icons.pie_chart_rounded, 'Grafik'.tr()),
          _tabBtn(context, 1, Icons.table_chart_rounded, 'Tablo'.tr()),
        ],
      ),
    );
  }

  Widget _tabBtn(BuildContext context, int i, IconData icon, String label) {
    final sel = _tab == i;
    final muted = AppPalette.textSecondary(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? _kBrand : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: sel ? Colors.white : muted),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: sel ? Colors.white : muted,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ── GRAFİK: pasta + yan istatistik ─────────────────────────────────────
  Widget _graphSection(BuildContext context) {
    final s = _stats;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🥧', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text('Cevap Dağılımı'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Pasta (daire)
              SizedBox(
                width: 132, height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(PieChartData(
                      centerSpaceRadius: 34,
                      sectionsSpace: 2,
                      sections: [
                        if (s.correct > 0)
                          _slice(s.correct, s.total, _kGreen),
                        if (s.wrong > 0) _slice(s.wrong, s.total, _kRed),
                        if (s.empty > 0) _slice(s.empty, s.total, _kGray),
                        if (s.pending > 0) _slice(s.pending, s.total, _kAmber),
                      ],
                    )),
                    // Merkez: toplam başarı
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('%${s.pct.toStringAsFixed(0)}',
                            style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.w900,
                              color: _scoreColor(s.pct))),
                        Text('başarı'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 8.5,
                              color: AppPalette.textSecondary(context))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Yan istatistik — tablo içinde
              Expanded(
                child: Table(
                  border: TableBorder.all(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(),
                    1: FixedColumnWidth(44),
                  },
                  children: [
                    _statRow(context, '📋 ${'Soru'.tr()}',
                        s.total, const Color(0xFF6366F1)),
                    _statRow(context, '✅ ${'Doğru'.tr()}', s.correct, _kGreen),
                    _statRow(context, '❌ ${'Yanlış'.tr()}', s.wrong, _kRed),
                    _statRow(context, '⬜ ${'Boş'.tr()}', s.empty, _kGray),
                    if (s.pending > 0)
                      _statRow(context, '⏳ ${'Bekliyor'.tr()}',
                          s.pending, _kAmber),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Toplam başarı şeridi
          _successBar(context, s.pct),
          // #4 Sınıf ortalamasıyla kıyas — küçük gri metin.
          if (_classAvg != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Row(
                children: [
                  Icon(Icons.groups_rounded, size: 13,
                      color: AppPalette.textSecondary(context)),
                  const SizedBox(width: 4),
                  Text(
                    '${'Sınıf ortalaması'.tr()}: %${_classAvg!.toStringAsFixed(0)}',
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: AppPalette.textSecondary(context)),
                  ),
                  const SizedBox(width: 6),
                  // Öğrenci ortalamanın üstünde mi altında mı?
                  Icon(
                    s.pct >= _classAvg!
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 13,
                    color: s.pct >= _classAvg! ? _kGreen : _kRed,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  PieChartSectionData _slice(int v, int total, Color c) => PieChartSectionData(
        value: v.toDouble(),
        color: c,
        title: total > 0 ? '${(v * 100 / total).round()}%' : '',
        radius: 32,
        titleStyle: GoogleFonts.poppins(
            fontSize: 10.5, fontWeight: FontWeight.w900, color: Colors.white),
      );

  TableRow _statRow(BuildContext context, String label, int value, Color c) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11.5, fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Text('$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w900, color: c)),
        ),
      ],
    );
  }

  Widget _successBar(BuildContext context, double pct) {
    final c = _scoreColor(pct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('🎯 ${'Toplam Başarı'.tr()}',
                style: GoogleFonts.poppins(
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context))),
            const Spacer(),
            Text('%${pct.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w900, color: c)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppPalette.border(context),
            valueColor: AlwaysStoppedAnimation(c),
          ),
        ),
      ],
    );
  }

  // ── TABLO: Excel benzeri istatistik ────────────────────────────────────
  Widget _tableSection(BuildContext context) {
    final s = _stats;
    final ink = AppPalette.textPrimary(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text('Ödev İstatistikleri'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
              const Spacer(),
              // Sağda: soruları detaylı göster (açılır/kapanır).
              InkWell(
                onTap: () => setState(() => _qExpanded = !_qExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Soruları detaylı göster'.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 12, fontWeight: FontWeight.w800,
                              color: _kBrand)),
                      const SizedBox(width: 2),
                      Icon(
                          _qExpanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_right_rounded,
                          size: 18, color: _kBrand),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Özet tablo (Excel benzeri)
          Table(
            border: TableBorder.all(
              color: AppPalette.border(context),
              borderRadius: BorderRadius.circular(10),
            ),
            children: [
              TableRow(
                decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: 0.10)),
                children: [
                  _th(context, '✅ ${'Doğru'.tr()}'),
                  _th(context, '❌ ${'Yanlış'.tr()}'),
                  _th(context, '⬜ ${'Boş'.tr()}'),
                  _th(context, '🎯 ${'Başarı'.tr()}'),
                ],
              ),
              TableRow(
                children: [
                  _td(context, '${s.correct}', _kGreen),
                  _td(context, '${s.wrong}', _kRed),
                  _td(context, '${s.empty}', _kGray),
                  _td(context, '%${s.pct.toStringAsFixed(0)}',
                      _scoreColor(s.pct)),
                ],
              ),
            ],
          ),
          if (s.pending > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('⏳', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text('${'Değerlendirilmeyi bekleyen'.tr()}: ${s.pending}',
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: _kAmber)),
              ],
            ),
          ],
          // Soru-soru durum tablosu (üstteki "Soruları detaylı göster" ile aç).
          if (_qExpanded) ...[
            const SizedBox(height: 16),
            if ((sub?.answers ?? const []).isNotEmpty)
              Table(
                border: TableBorder.all(
                  color: AppPalette.border(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                columnWidths: const {
                  0: FixedColumnWidth(46),
                  1: FlexColumnWidth(),
                  2: FixedColumnWidth(90),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                        color: _kBrand.withValues(alpha: 0.10)),
                    children: [
                      _th(context, 'No'.tr()),
                      _th(context, 'Tür'.tr()),
                      _th(context, 'Durum'.tr()),
                    ],
                  ),
                  ...sub!.answers.asMap().entries.map((e) {
                    final a = e.value;
                    return TableRow(
                      children: [
                        _td(context, '${e.key + 1}', ink),
                        _td(context, _typeLabel(a.type),
                            AppPalette.textSecondary(context), bold: false),
                        _statusCell(context, a),
                      ],
                    );
                  }),
                ],
              )
            else
              Text('Soru-soru detay yok.'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppPalette.textSecondary(context))),
          ],
        ],
      ),
    );
  }

  Widget _th(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Text(t,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context))),
      );

  Widget _td(BuildContext context, String t, Color color,
          {bool bold = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: Text(t,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                color: color)),
      );

  Widget _statusCell(BuildContext context, SubmissionAnswer a) {
    String label;
    Color c;
    if (a.studentAnswer.trim().isEmpty) {
      label = '⬜ ${'Boş'.tr()}'; c = _kGray;
    } else if (a.isCorrect == true) {
      label = '✅ ${'Doğru'.tr()}'; c = _kGreen;
    } else if (a.isCorrect == false) {
      label = '❌ ${'Yanlış'.tr()}'; c = _kRed;
    } else {
      label = '⏳ ${'Bekliyor'.tr()}'; c = _kAmber;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      child: Text(label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
    );
  }

  // ── "Öğrencinin verdiği cevaplara bak" ─────────────────────────────────
  Widget _answersButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        // Yeni sayfaya gitme — aynı sayfada inline aç/kapat.
        onPressed: () =>
            setState(() => _answersExpanded = !_answersExpanded),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(
            _answersExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.fact_check_rounded,
            size: 19),
        label: Text(
            _answersExpanded
                ? 'Cevapları gizle'.tr()
                : 'Öğrencinin verdiği cevaplara bak'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 13.5, fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
    );
  }

  Widget _notSubmitted(BuildContext context) {
    final muted = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        children: [
          const Text('📭', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Bu ödev henüz teslim edilmedi.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context))),
          const SizedBox(height: 6),
          Text('Öğrenci ödevi tamamlayınca grafik ve istatistikler '
                  'burada görünür.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: muted, height: 1.4)),
        ],
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 70) return _kGreen;
    if (score >= 40) return _kAmber;
    return _kRed;
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'mc': return 'Çoktan seçmeli'.tr();
      case 'tf': return 'Doğru/Yanlış'.tr();
      case 'fill': return 'Boşluk'.tr();
      default: return 'Açık uçlu'.tr();
    }
  }

  String _fmtDate(DateTime d) {
    // Dile-nötr sayısal tarih (GG.AA.YYYY) → her müfredat dilinde doğru,
    // çeviri gerektirmez, taşmaz.
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _AiHomeworkInsight — Öğrenci ödev cevaplarının AI ile tek-cümlelik analizi.
//  Yalnız teslim edilmiş ödevde; Gemini'den içgörü çeker, hata/boşta gizlenir.
// ═══════════════════════════════════════════════════════════════════════════
class _AiHomeworkInsight extends StatefulWidget {
  final String studentName;
  final HomeworkModel homework;
  final HomeworkSubmissionModel? submission;
  final ({int total, int correct, int wrong, int empty, int pending, double pct})
      stats;
  const _AiHomeworkInsight({
    required this.studentName,
    required this.homework,
    required this.submission,
    required this.stats,
  });

  @override
  State<_AiHomeworkInsight> createState() => _AiHomeworkInsightState();
}

class _AiHomeworkInsightState extends State<_AiHomeworkInsight> {
  String? _text;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  List<Map<String, dynamic>> _answers() {
    final out = <Map<String, dynamic>>[];
    for (final a in widget.submission?.answers ?? const <SubmissionAnswer>[]) {
      out.add({
        'q': a.questionText,
        'studentAnswer': a.studentAnswer,
        'status': a.isCorrect == true
            ? 'doğru'
            : a.isCorrect == false
                ? 'yanlış'
                : 'değerlendirilmedi',
      });
    }
    return out;
  }

  Future<void> _generate() async {
    final answers = _answers();
    if (answers.isEmpty) return;
    setState(() => _loading = true);
    try {
      final s = widget.stats;
      final t = await GeminiService.analyzeStudentHomework(
        studentName: widget.studentName,
        subject: widget.homework.subject,
        topic: widget.homework.topic,
        answers: answers,
        correct: s.correct,
        wrong: s.wrong,
        empty: s.empty,
        total: s.total,
        pct: s.pct,
        langCode: LocaleService.global?.localeCode ?? 'tr',
      );
      if (!mounted) return;
      setState(() { _text = t; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_answers().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF7C3AED).withValues(alpha: 0.10),
          const Color(0xFF06B6D4).withValues(alpha: 0.10),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30, height: 30,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)]),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.auto_awesome_rounded,
                size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Analizi'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w800,
                        color: const Color(0xFF6D28D9))),
                const SizedBox(height: 4),
                if (_loading)
                  Text('Analiz ediliyor…'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppPalette.textSecondary(context)))
                else if (_text != null)
                  Text(_text!,
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, height: 1.45,
                          color: AppPalette.textPrimary(context)))
                else
                  Text('Analiz üretilemedi.'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppPalette.textSecondary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
