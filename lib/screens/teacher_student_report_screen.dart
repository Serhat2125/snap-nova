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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/account_service.dart';
import '../services/class_service.dart';
import '../services/grading_config.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../utils/safe_dismiss.dart';
import '../theme/app_theme.dart';
import '../widgets/teacher_help_dialog.dart';
import 'teacher_homework_detail_screen.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherStudentReportScreen extends StatefulWidget {
  final String classId;
  final String studentUid;
  final String studentName;
  final String studentAvatar;
  // Ebeveyn görünümü: salt-okuma (AI yorumu üretimi/yazımı devre dışı).
  final bool readOnly;
  const TeacherStudentReportScreen({
    super.key,
    required this.classId,
    required this.studentUid,
    required this.studentName,
    this.studentAvatar = '👤',
    this.readOnly = false,
  });

  @override
  State<TeacherStudentReportScreen> createState() =>
      _TeacherStudentReportScreenState();
}

class _TeacherStudentReportScreenState
    extends State<TeacherStudentReportScreen> {
  late Future<List<StudentReportEntry>> _future;
  int _tab = 0; // 0 = Ödevler, 1 = Notlar, 2 = Yazılılar

  // Yazılılar sayfasında "basılı tut" ipucu balonu (ilk 5 ziyaret, 2 sn).
  static const String _coachKey = 'grades_longpress_coach_count';
  static const int _coachMaxShows = 5;
  bool _coachVisible = false;
  bool _coachTriedThisOpen = false;
  Timer? _coachTimer;

  // Dönem çerçevesinde notların kapatıldığı dönemler (varsayılan: açık).
  final Set<int> _collapsedTerms = {};

  /// Öğretmenin seçtiği müfredata göre aktif not konfigürasyonu (skala,
  /// kategoriler, hesaplama türü, geçme sınırı…).
  /// Öncelik: SINIFIN müfredatı (öğretmenin seçtiği) → ebeveyn/öğrenci de aynı
  /// skalada görür. Yoksa görüntüleyenin kendi seçimi → generic.
  String? _classGradingCountry;
  String? _classGradingProfile;
  CurriculumConfig get _cfg => GradingConfigService.forCountry(
      (_classGradingCountry != null && _classGradingCountry!.isNotEmpty)
          ? _classGradingCountry
          : AccountService.instance.gradingCountry,
      profileId: (_classGradingProfile != null && _classGradingProfile!.isNotEmpty)
          ? _classGradingProfile
          : AccountService.instance.gradingProfile);

  List<GradeEntry> _entries(List<StudentGrade> gs) => gs
      .map((g) => GradeEntry(
            score: g.score,
            weightPercent: g.weight,
            categoryKey: g.type,
            term: g.term,
          ))
      .toList();

  // Sürüklenebilir "Sınav notu ekle" butonunun konumu (null = varsayılan).
  Offset? _gradeFabPos;

  @override
  void initState() {
    super.initState();
    _future = HomeworkService.studentReport(widget.classId, widget.studentUid);
    // Sınıfın müfredat ülkesini çek (gerekirse sahibi öğretmense geriye doldur)
    // → notlar öğretmen/ebeveyn/öğrencide AYNI skalada gösterilir.
    ClassService.gradingCountryForClass(widget.classId).then((cc) {
      if (mounted && cc.isNotEmpty) {
        setState(() => _classGradingCountry = cc);
      }
    });
    ClassService.gradingProfileForClass(widget.classId).then((pid) {
      if (mounted && pid.isNotEmpty) {
        setState(() => _classGradingProfile = pid);
      }
    });
  }

  @override
  void dispose() {
    _coachTimer?.cancel();
    super.dispose();
  }

  /// Sağ üstteki "?" → aktif sekmeye göre kısa "nasıl kullanılır" rehberi.
  Future<void> _showHelp() async {
    final (title, items) = switch (_tab) {
      1 => (
          'Notlar — nasıl kullanılır?',
          [
            TeacherHelpItem('📝',
                '“Yeni not ekle” ile öğrenci hakkında gözlem/öneri yaz.'),
            TeacherHelpItem('👪',
                '“Ebeveynle paylaş” açıksa not velinin panelinde görünür; kapalıysa sadece sana özeldir.'),
            TeacherHelpItem('👏',
                '“Takdir” ile hazır olumlu geri bildirim gönderebilirsin.'),
            TeacherHelpItem('✏️',
                'Bir nota dokunarak düzenleyebilir veya silebilirsin.'),
          ],
        ),
      2 => (
          'Yazılılar — nasıl kullanılır?',
          [
            TeacherHelpItem('➕',
                'Her dönem çerçevesindeki “Not ekle” ile yazılı/sözlü not girersin; çerçevenin dönemi hazır gelir.'),
            TeacherHelpItem('🗂️',
                'Her dönem kendi çerçevesindedir; “Notları göster/gizle” ile aç-kapat.'),
            TeacherHelpItem('🎯',
                'Not eklerken “Yüzdelik Katkısı”, o notun dönem ağırlığıdır.'),
            TeacherHelpItem('🔢',
                '“Verilen” girdiğin nottur; “Katkı” o notun ortalamaya gerçek payıdır — bir dönemdeki katkıların toplamı Ortalama’ya eşittir.'),
            TeacherHelpItem('✋', 'Bir nota uzun basarak düzenle veya sil.'),
          ],
        ),
      _ => (
          'Ödevler — nasıl kullanılır?',
          [
            TeacherHelpItem('📊',
                'Öğrencinin verdiğin ödevlerdeki performansı: skor, süre, durum.'),
            TeacherHelpItem('📈',
                'Başarı trendi ve konu bazlı güçlü/zayıf alanlar burada görünür.'),
            TeacherHelpItem('👇',
                'Bir ödeve dokunarak ayrıntılı sonucu açabilirsin.'),
          ],
        ),
    };
    await showTeacherHelpDialog(context, title: title, items: items);
  }

  /// AppBar'daki "Ekle" → güncel notları çekip not ekleme sayfasını açar.
  Future<void> _openAddGrade() async {
    final grades = await ClassService.gradesStream(
            widget.classId, widget.studentUid)
        .first;
    if (!mounted) return;
    await _addGradeDialog(context, grades);
  }

  /// Notlar varsa, ilk 5 ziyarette "basılı tut" ipucunu 2 sn göster.
  Future<void> _maybeShowGradesCoach() async {
    if (_coachTriedThisOpen || widget.readOnly) return;
    _coachTriedThisOpen = true;
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_coachKey) ?? 0;
    if (count >= _coachMaxShows) return;
    await prefs.setInt(_coachKey, count + 1);
    if (!mounted) return;
    setState(() => _coachVisible = true);
    _coachTimer?.cancel();
    _coachTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _coachVisible = false);
    });
  }

  /// Risk değerlendirmesi: son ödevleri kaçırma + düşük ortalama.
  /// entries yeni→eski sıralı. Risk yoksa null döner.
  String? _riskMessage(List<StudentReportEntry> entries) {
    if (entries.isEmpty) return null;
    final recent = entries.take(3).toList();
    final missed = recent.where((e) => !e.isDone).length;
    final doneScores = entries
        .where((e) => e.isDone)
        .map((e) => e.submission?.scorePercent)
        .whereType<double>()
        .toList();
    final avg = doneScores.isEmpty
        ? null
        : doneScores.reduce((a, b) => a + b) / doneScores.length;
    if (recent.length >= 2 && missed >= 2) {
      return 'Son $missed ödevi teslim etmedi.'.tr();
    }
    if (avg != null && avg < 50) {
      return 'Ödev ortalaması düşük (%${avg.toStringAsFixed(0)}).'.tr();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        actions: [
          // Sağ üstte, geri oku hizasında "nasıl kullanılır?" yardımı.
          IconButton(
            icon: Icon(Icons.help_outline_rounded,
                color: AppPalette.textPrimary(context)),
            tooltip: 'Nasıl kullanılır?'.tr(),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: SafeArea(
        child: _tab == 0
            ? _reportTab(context)
            : _tab == 1
                ? _notesTab(context)
                : _gradesTab(context),
      ),
      bottomNavigationBar: _bottomBar(context),
    );
  }

  Widget _reportTab(BuildContext context) {
    return FutureBuilder<List<StudentReportEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? const <StudentReportEntry>[];
        return _buildBody(context, entries);
      },
    );
  }

  // ── Alt sekme barı: Ödevler | Öğrenim ──────────────────────────────────
  Widget _bottomBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        border: Border(
            top: BorderSide(color: AppPalette.border(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              _navItem(context, 0, Icons.assignment_rounded, 'Ödevler'.tr()),
              _navItem(context, 1, Icons.menu_book_rounded, 'Notlar'.tr()),
              _navItem(context, 2, Icons.grading_rounded, 'Yazılılar'.tr()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
      BuildContext context, int index, IconData icon, String label) {
    final sel = _tab == index;
    final muted = AppPalette.textSecondary(context);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _tab = index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: sel ? _kBrand : muted),
                const SizedBox(height: 3),
                Text(label,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? _kBrand : muted,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Öğrenim sekmesi: öğretmenin öğrenci hakkındaki notları ─────────────
  Widget _notesTab(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return StreamBuilder<List<StudentNote>>(
      // Ebeveyn yalnızca paylaşılan notları görür.
      stream: ClassService.notesStream(widget.classId, widget.studentUid,
          onlyShared: widget.readOnly),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final notes = snap.data!;
        return Column(
          children: [
            // Başlık + takdir + "Yeni not ekle"
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kBrand.withValues(alpha: 0.12),
                    ),
                    alignment: Alignment.center,
                    child: Text(widget.studentAvatar,
                        style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.studentName,
                            style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w900,
                              color: ink,
                            )),
                        Text(
                            widget.readOnly
                                ? 'Öğretmenin paylaştığı notlar'.tr()
                                : 'Öğrenci hakkındaki notların'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11.5, color: muted,
                            )),
                      ],
                    ),
                  ),
                  if (!widget.readOnly) ...[
                    // Takdir gönder (👏)
                    _iconBox(
                      icon: Icons.emoji_events_rounded,
                      color: const Color(0xFFF59E0B),
                      tooltip: 'Takdir gönder'.tr(),
                      onTap: () => _praiseDialog(context),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _editNoteDialog(context, null),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kBrand,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Yeni Not'.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 12.5, fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: notes.isEmpty
                  ? _notesEmpty(context, muted)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        _sectionLabel(context,
                            widget.readOnly
                                ? 'ÖĞRETMENDEN'.tr()
                                : 'NOTLARIM'.tr()),
                        const SizedBox(height: 10),
                        ...notes.map((n) => _noteCard(context, n)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _iconBox({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 38, height: 38,
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }

  Widget _noteCard(BuildContext context, StudentNote n) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final praise = n.isPraise;
    final accent = praise ? const Color(0xFFF59E0B) : _kBrand;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: praise
            ? const Color(0xFFF59E0B).withValues(alpha: 0.07)
            : AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: praise
                ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                : AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst satır: tür/tarih + paylaşım rozeti + düzelt
          Row(
            children: [
              if (praise) ...[
                const Text('👏', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text('Takdir'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, fontWeight: FontWeight.w800,
                      color: accent)),
                const SizedBox(width: 8),
              ],
              Icon(Icons.calendar_today_rounded, size: 11, color: muted),
              const SizedBox(width: 4),
              Text(_fmtDate(n.createdAt),
                  style: GoogleFonts.poppins(fontSize: 10.5, color: muted)),
              const Spacer(),
              // Veli görüyor rozeti (öğretmen tarafında bilgi)
              if (!widget.readOnly && n.sharedWithParent) ...[
                Icon(Icons.family_restroom_rounded,
                    size: 12, color: const Color(0xFF10B981)),
                const SizedBox(width: 3),
                Text('Veli görüyor'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 9.5, fontWeight: FontWeight.w700,
                      color: const Color(0xFF10B981))),
              ],
              // Takdir düzenlenmez; normal notlar düzeltilebilir.
              if (!widget.readOnly && !praise) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _editNoteDialog(context, n),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_rounded,
                            size: 14, color: _kBrand),
                        const SizedBox(width: 3),
                        Text('Notu düzelt'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 10.5, fontWeight: FontWeight.w700,
                              color: _kBrand,
                            )),
                      ],
                    ),
                  ),
                ),
              ],
              // Takdiri silme (öğretmen) — yanlışlıkla silmeye karşı onaylı.
              if (!widget.readOnly && praise)
                InkWell(
                  onTap: () => _confirmDeletePraise(context, n),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 15, color: _kBrand),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(n.text,
              style: GoogleFonts.poppins(
                fontSize: 13.5, color: ink, height: 1.45,
              )),
        ],
      ),
    );
  }

  Widget _notesEmpty(BuildContext c, Color muted) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📒', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                widget.readOnly
                    ? 'Öğretmen henüz not eklemedi.'.tr()
                    : 'Henüz not yok — "Yeni Not" ile bu öğrenci hakkındaki '
                        'gözlemlerini yazabilirsin.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: muted, height: 1.4),
              ),
            ],
          ),
        ),
      );

  Future<void> _confirmDeletePraise(
      BuildContext context, StudentNote n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Takdiri sil'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Text('Bu takdir silinsin mi?'.tr(),
            style: GoogleFonts.poppins(
                color: AppPalette.textSecondary(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ClassService.deleteNote(
          widget.classId, widget.studentUid, n.id);
    }
  }

  /// Not ekleme/düzenleme alt sayfası. [existing] null → yeni not.
  Future<void> _editNoteDialog(
      BuildContext context, StudentNote? existing) async {
    final ctrl = TextEditingController(text: existing?.text ?? '');
    bool shared = existing?.sharedWithParent ?? false;
    // Klavye açıkken (autofocus) sheet kapanırken _dependents.isEmpty kırmızı
    // ekranını önlemek için TÜM kapatma yolları (kaydet/sil/geri/aşağı kaydır)
    // tek bir klavye-güvenli close() üzerinden gider (PopScope ile yakalanır).
    bool dismissing = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final ink = AppPalette.textPrimary(sheetCtx);
          final muted = AppPalette.textSecondary(sheetCtx);
          // Klavye-güvenli kapatma: önce odağı bırak, kapanış animasyonunu
          // bekle, sonra (canPop=true ile) pop et. Mid-animation pop = çökme.
          Future<void> close() async {
            FocusManager.instance.primaryFocus?.unfocus();
            await Future<void>.delayed(const Duration(milliseconds: 320));
            if (!sheetCtx.mounted) return;
            dismissing = true;
            setSheet(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetCtx.mounted) Navigator.of(sheetCtx).maybePop();
            });
          }

          return PopScope(
            canPop: dismissing,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) close();
            },
            child: Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 16,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border(sheetCtx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(existing == null ? 'Yeni Not'.tr() : 'Notu Düzelt'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 17, fontWeight: FontWeight.w900,
                            color: ink)),
                    const Spacer(),
                    if (existing != null)
                      IconButton(
                        onPressed: () async {
                          await close();
                          await ClassService.deleteNote(
                              widget.classId, widget.studentUid, existing.id);
                        },
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444)),
                        tooltip: 'Sil'.tr(),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.bg(sheetCtx),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppPalette.border(sheetCtx)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 8,
                    minLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5, color: ink, height: 1.45),
                    decoration: InputDecoration(
                      hintText: 'Gözlemlerini, gelişimini ve önerilerini '
                          'buraya yazabilirsin…'.tr(),
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 13, color: muted.withValues(alpha: 0.5),
                          height: 1.45),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Ebeveynle paylaş anahtarı
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.bg(sheetCtx),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppPalette.border(sheetCtx)),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.family_restroom_rounded,
                          size: 18, color: Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ebeveynle paylaş'.tr(),
                                style: GoogleFonts.poppins(
                                    fontSize: 13, fontWeight: FontWeight.w700,
                                    color: ink)),
                            Text('Açıksa bu not velinin panelinde görünür.'.tr(),
                                style: GoogleFonts.poppins(
                                    fontSize: 10.5, color: muted)),
                          ],
                        ),
                      ),
                      Switch(
                        value: shared,
                        activeThumbColor: const Color(0xFF10B981),
                        onChanged: (v) => setSheet(() => shared = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final text = ctrl.text.trim();
                      // Klavye-güvenli kapat (geri/aşağı/kaydet hepsi aynı yol).
                      await close();
                      if (text.isEmpty) return;
                      if (existing == null) {
                        await ClassService.addNote(widget.classId,
                            widget.studentUid, text,
                            sharedWithParent: shared);
                      } else {
                        await ClassService.updateNote(widget.classId,
                            widget.studentUid, existing.id, text,
                            sharedWithParent: shared);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: Text('Kaydet'.tr(),
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
        },
      ),
    );
    ctrl.dispose();
  }

  /// Takdir/hızlı geri bildirim — hazır ifadelerden seç ya da kendin yaz.
  /// Takdir notları her zaman ebeveynle paylaşılır (👏).
  Future<void> _praiseDialog(BuildContext context) async {
    const presets = [
      '👏 Bu hafta çok çalıştı',
      '⭐ Ödevlerini eksiksiz yaptı',
      '🙋 Derse katılımı harika',
      '📈 Belirgin gelişme gösterdi',
      '🤝 Arkadaşlarına yardımcı oldu',
      '🎯 Hedeflerine odaklandı',
    ];
    final messenger = ScaffoldMessenger.of(context);
    final customCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final ink = AppPalette.textPrimary(sheetCtx);
        final muted = AppPalette.textSecondary(sheetCtx);
        Future<void> send(String text) async {
          if (text.trim().isEmpty) return;
          // Odağı bırak → IME teardown'u bitince sheet'i güvenle kapat.
          await safeDismiss(sheetCtx);
          messenger.showSnackBar(SnackBar(
            content: Text('Takdir gönderildi 👏'.tr()),
            behavior: SnackBarBehavior.floating,
          ));
          await ClassService.addNote(
              widget.classId, widget.studentUid, text.trim(),
              kind: 'praise');
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 16,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border(sheetCtx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('👏', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text('Takdir gönder'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 17, fontWeight: FontWeight.w900,
                            color: ink)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Veliye anında bildirilir.'.tr(),
                    style: GoogleFonts.poppins(fontSize: 11.5, color: muted)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: presets.map((p) {
                    return GestureDetector(
                      onTap: () => send(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Text(p.tr(),
                            style: GoogleFonts.poppins(
                                fontSize: 12.5, fontWeight: FontWeight.w700,
                                color: ink)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('Kendin yaz'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: muted)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.bg(sheetCtx),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppPalette.border(sheetCtx)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    controller: customCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.poppins(
                        fontSize: 13.5, color: ink),
                    decoration: InputDecoration(
                      hintText: 'Örn: Sınav sonucu çok başarılıydı 🎉'.tr(),
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: muted.withValues(alpha: 0.5)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => send(customCtrl.text),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text('Takdiri Gönder'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 13.5, fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    customCtrl.dispose();
  }

  // ── Yazılılar sekmesi: yazılı/sözlü notları ────────────────────────────
  Widget _gradesTab(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return StreamBuilder<List<StudentGrade>>(
      stream: ClassService.gradesStream(widget.classId, widget.studentUid),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final grades = snap.data!;
        // Not varsa ipucu balonunu (ilk 5 ziyaret) tetikle.
        if (grades.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _maybeShowGradesCoach());
        }
        return LayoutBuilder(builder: (context, c) {
        return Stack(
          children: [
            Column(
          children: [
            // Başlık + ekle butonu
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kBrand.withValues(alpha: 0.12),
                    ),
                    alignment: Alignment.center,
                    child: Text(widget.studentAvatar,
                        style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.studentName,
                            style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w900,
                              color: ink,
                            )),
                        Text('Yazılı & sözlü notları'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11.5, color: muted,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: grades.isEmpty
                  ? _gradesEmpty(context, muted)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: _gradeSummaries(context, grades),
                    ),
            ),
          ],
            ),
            _coachBalloon(context),
            if (grades.isNotEmpty && !widget.readOnly)
              _draggableAddGrade(c),
          ],
        );
        });
      },
    );
  }

  /// Sürüklenebilir "Sınav notu ekle" butonu — öğretmen istediği yere taşır.
  Widget _draggableAddGrade(BoxConstraints c) {
    const w = 188.0, h = 46.0;
    final def = Offset(c.maxWidth - w - 16, c.maxHeight - h - 18);
    final pos = _gradeFabPos ?? def;
    double clampX(double x) => x.clamp(8.0, math.max(8.0, c.maxWidth - w - 8));
    double clampY(double y) => y.clamp(8.0, math.max(8.0, c.maxHeight - h - 8));
    return Positioned(
      left: clampX(pos.dx),
      top: clampY(pos.dy),
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          final cur = _gradeFabPos ?? def;
          _gradeFabPos =
              Offset(clampX(cur.dx + d.delta.dx), clampY(cur.dy + d.delta.dy));
        }),
        onTap: _openAddGrade,
        child: Material(
          elevation: 6,
          shadowColor: _kBrand.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
          color: _kBrand,
          child: Container(
            width: w, height: h,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.drag_indicator_rounded,
                    size: 16, color: Colors.white70),
                const SizedBox(width: 4),
                const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('Sınav notu ekle'.tr(),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Basılı tut" ipucu balonu — notların ortasında belirir, 2 sn sonra solar.
  Widget _coachBalloon(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _coachVisible ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: _coachVisible ? 1 : 0.9,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 36),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: _kBrand,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 20, offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.touch_app_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'İpucu: Bir notu düzenlemek ya da silmek için üzerine basılı tut.'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12.5, height: 1.4,
                          fontWeight: FontWeight.w700, color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Dönem sonu sonucu — aktif müfredatın hesaplama modeline göre
  /// (aritmetik / kategori-ağırlıklı / not-ağırlıklı / puan toplamı).
  double _termResult(List<StudentGrade> gs) =>
      GradeCalculator.termResult(_cfg, _entries(gs));

  /// Bir notun döneme yaklaşık katkısı (toplamları = dönem sonucu).
  /// Modele göre: aritmetik → eşit pay; not-ağırlıklı → ağırlık payı;
  /// kategori-ağırlıklı → kategori ağırlığı ÷ kategori not adedi.
  double _contribution(StudentGrade g, List<StudentGrade> all) {
    final term = all.where((x) => x.term == g.term).toList();
    if (term.isEmpty) return 0;

    if (_cfg.calc == CalcModel.weighted &&
        _cfg.weightMode == WeightMode.perCategory) {
      double wTotal = 0;
      for (final cat in _cfg.categories) {
        if (term.any((x) => x.type == cat.key) && cat.defaultWeight > 0) {
          wTotal += cat.defaultWeight;
        }
      }
      final cat = _cfg.categoryByKey(g.type);
      final inCat = term.where((x) => x.type == g.type).length;
      if (wTotal <= 0 || inCat == 0 || cat.defaultWeight <= 0) {
        return g.score / term.length;
      }
      return g.score * (cat.defaultWeight / wTotal) / inCat;
    }

    if (_cfg.calc == CalcModel.weighted &&
        _cfg.weightMode == WeightMode.perNote) {
      final nonZero = term.where((x) => x.weight > 0).toList();
      if (nonZero.isEmpty) return g.score / term.length;
      final avgW =
          nonZero.fold<int>(0, (s, x) => s + x.weight) / nonZero.length;
      double totalW = 0;
      for (final x in term) {
        totalW += x.weight > 0 ? x.weight.toDouble() : avgW;
      }
      final effW = g.weight > 0 ? g.weight.toDouble() : avgW;
      return totalW > 0 ? g.score * effW / totalW : 0;
    }

    // Aritmetik / puan toplamı → eşit pay.
    return g.score / term.length;
  }

  /// Not değerine göre renk (skala yönünü dikkate alır).
  Color _gradeColor(double score) {
    final r = GradeCalculator.successRatio(_cfg, score);
    if (r >= 0.80) return const Color(0xFF10B981);
    if (r >= 0.50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  /// Notun okunur etiketi (kategori adı + sıra), müfredata göre.
  String _gradeLabel(StudentGrade g) {
    final cat = _cfg.categoryByKey(g.type);
    final name = cat.label.tr();
    return cat.orderable ? '${g.order}. $name' : name;
  }

  /// Skoru giriş alanında gösterilecek metne çevirir (tam sayıda .0 olmaz).
  String _scoreInputText(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Her DÖNEM için ayrı çerçeve (özet + altında açılır not listesi). 2. dönem
  /// notu girilince ikinci çerçeve otomatik eklenir.
  List<Widget> _gradeSummaries(
      BuildContext context, List<StudentGrade> grades) {
    final terms = <int, List<StudentGrade>>{};
    for (final g in grades) {
      terms.putIfAbsent(g.term, () => []).add(g);
    }
    final sorted = terms.keys.toList()..sort();
    return [
      for (final t in sorted)
        _gradeSummary(context, t, terms[t]!, grades),
    ];
  }

  // Tek dönem çerçevesi: dönem etiketi + Ortalama/Sınav/Geçer + sağ altta
  // aç/kapa düğmesi ve içeride o dönemin yazılı/sözlü not detayları.
  Widget _gradeSummary(BuildContext context, int term,
      List<StudentGrade> grades, List<StudentGrade> allGrades) {
    final avg = _termResult(grades);
    final passed =
        grades.where((g) => GradeCalculator.isPass(_cfg, g.score)).length;
    final open = !_collapsedTerms.contains(term); // varsayılan: açık
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sol üstte dönem etiketi (rozet).
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: _kBrand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$term. ${'Dönem'.tr()}',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: _kBrand,
                  )),
            ),
          ),
          Row(
            children: [
              _miniStat(context, '📊', 'Ortalama'.tr(),
                  GradeCalculator.displayResult(_cfg, avg), _gradeColor(avg)),
              _miniDivider(context),
              _miniStat(context, '📝', 'Sınav'.tr(),
                  '${grades.length}', const Color(0xFF6366F1)),
              _miniDivider(context),
              _miniStat(context, '✅', 'Geçer'.tr(),
                  '$passed/${grades.length}', const Color(0xFF10B981)),
            ],
          ),
          const SizedBox(height: 10),
          // Sağ altta "Notları göster/gizle". ("Sınav notu ekle" sürüklenebilir
          // yüzen butona taşındı.)
          Align(
            alignment: Alignment.centerRight,
            child: _termPill(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              open ? 'Notları gizle'.tr() : 'Notları göster'.tr(),
              () => setState(() {
                if (open) {
                  _collapsedTerms.add(term);
                } else {
                  _collapsedTerms.remove(term);
                }
              }),
              iconRight: true,
            ),
          ),
          // İçeride o dönemin yazılı/sözlü notları (açıldıkça kayar).
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      children: [
                        for (final g in grades)
                          _gradeRow(context, g, allGrades),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Dönem çerçevesinin alt satırındaki hap-düğme ("Not ekle" / "Notları …").
  Widget _termPill(IconData icon, String label, VoidCallback onTap,
      {bool iconRight = false}) {
    final text = Text(label,
        style: GoogleFonts.poppins(
            fontSize: 11.5, fontWeight: FontWeight.w800, color: _kBrand));
    final ic = Icon(icon, size: 16, color: _kBrand);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _kBrand.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kBrand.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconRight
              ? [text, const SizedBox(width: 4), ic]
              : [ic, const SizedBox(width: 4), text],
        ),
      ),
    );
  }

  Widget _miniStat(BuildContext c, String emoji, String label, String value,
      Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 3),
          Text(value,
              style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w900, color: color,
              )),
          Text(label,
              style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(c),
              )),
        ],
      ),
    );
  }

  Widget _miniDivider(BuildContext c) => Container(
        width: 1, height: 34,
        color: AppPalette.border(c),
      );

  Widget _gradeRow(
      BuildContext context, StudentGrade g, List<StudentGrade> allGrades) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final color = _gradeColor(g.score);
    final passed = GradeCalculator.isPass(_cfg, g.score);
    // Döneme GERÇEK katkı: not × etkinAğırlık ÷ Σ(etkinAğırlık). Bir dönemdeki
    // katkıların toplamı tam olarak ağırlıklı ortalamayı verir.
    final contribution = _contribution(g, allGrades);
    String fmtNum(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return GestureDetector(
      onLongPress: widget.readOnly
          ? null
          : () => _gradeActionMenu(context, g, allGrades),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(_gradeLabel(g),
                            style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      // Başarı durumu rozeti
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (passed
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444))
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          passed ? 'Geçer'.tr() : 'Kaldı'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 9.5, fontWeight: FontWeight.w800,
                            color: passed
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 11, color: muted),
                      const SizedBox(width: 4),
                      Text(_fmtDate(g.date),
                          style: GoogleFonts.poppins(
                            fontSize: 11, color: muted,
                          )),
                      if (_cfg.showPercentageSelector && g.weight > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.percent_rounded, size: 11, color: _kBrand),
                        const SizedBox(width: 2),
                        Text('${'Etki'.tr()} %${g.weight}',
                            style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: _kBrand,
                            )),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Sağ: yüzde kullanılıyorsa "Verilen" + "Katkı"; kullanılmıyorsa
            // (TR gibi) yalnızca verilen not (tek kutu).
            if (_cfg.showPercentageSelector)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 52,
                          child: Text('Verilen'.tr(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 8.5, fontWeight: FontWeight.w700,
                                  color: muted))),
                      const SizedBox(width: 6),
                      SizedBox(width: 52,
                          child: Text('Katkı'.tr(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 8.5, fontWeight: FontWeight.w700,
                                  color: muted))),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _scoreMiniBox(
                          GradeCalculator.displayScore(_cfg, g.score), color),
                      const SizedBox(width: 6),
                      _scoreMiniBox(fmtNum(contribution), _kBrand),
                    ],
                  ),
                ],
              )
            else
              _scoreMiniBox(
                  GradeCalculator.displayScore(_cfg, g.score), color),
          ],
        ),
      ),
    );
  }

  /// Karttaki küçük puan kutusu — "Verilen" ve "Katkı" değerleri için.
  Widget _scoreMiniBox(String value, Color fg) => Container(
        width: 52, height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withValues(alpha: 0.30)),
        ),
        child: Text(value,
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w900, color: fg, height: 1,
            )),
      );

  /// Tek çerçeve içindeki açılır-menü değer alanı (kenarlıksız, ok ikonlu).
  Widget _menuValue(BuildContext c, Color ink, bool open, String value,
          VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(value,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: ink)),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 18, color: _kBrand),
              ],
            ),
          ),
        ),
      );

  /// Çerçeve içi dikey ayraç.
  Widget _vsep(BuildContext c) =>
      Container(width: 1, height: 26, color: AppPalette.border(c));

  Widget _gradesEmpty(BuildContext c, Color muted) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📝', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                widget.readOnly
                    ? 'Henüz yazılı/sözlü notu girilmedi.'.tr()
                    : 'Henüz not yok — "Sınav notu ekle" ile ilk yazılı/sözlü notunu gir.'
                        .tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: muted, height: 1.4),
              ),
              if (!widget.readOnly) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _openAddGrade,
                  style: FilledButton.styleFrom(
                    backgroundColor: _kBrand,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Sınav notu ekle'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      );

  /// Girilen nota uzun basınca: Düzenle / Sil menüsü.
  Future<void> _gradeActionMenu(
      BuildContext context, StudentGrade g, List<StudentGrade> allGrades) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(
                      g.isOral
                          ? Icons.record_voice_over_rounded
                          : Icons.edit_note_rounded,
                      size: 20,
                      color: g.isOral
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF6366F1)),
                  const SizedBox(width: 10),
                  Text('${_gradeLabel(g)} · '
                      '${GradeCalculator.displayScore(_cfg, g.score)}',
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(ctx))),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: _kBrand),
              title: Text('Notu düzenle'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(ctx))),
              onTap: () {
                Navigator.pop(ctx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _addGradeDialog(this.context, allGrades, edit: g);
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444)),
              title: Text('Notu sil'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: const Color(0xFFEF4444))),
              onTap: () {
                Navigator.pop(ctx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _confirmDeleteGrade(this.context, g);
                });
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteGrade(
      BuildContext context, StudentGrade g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        title: Text('Notu sil'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(ctx))),
        content: Text('${_gradeLabel(g)} '
            '(${GradeCalculator.displayScore(_cfg, g.score)}) silinsin mi?'.tr(),
            style: GoogleFonts.poppins(
                color: AppPalette.textSecondary(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ClassService.deleteGrade(
          widget.classId, widget.studentUid, g.id);
    }
  }

  // Yazılı/sözlü notu ekleme/düzenleme alt sayfası. [edit] null → yeni not.
  Future<void> _addGradeDialog(
      BuildContext context, List<StudentGrade> existing,
      {StudentGrade? edit, int? initialTerm}) async {
    final cfg = _cfg;
    // Seçili kategori anahtarı (müfredat kategorilerinden). Düzenlemede mevcut
    // tür config'de yoksa ilk kategoriye düşülür.
    String categoryKey = (edit != null &&
            cfg.categories.any((c) => c.key == edit.type))
        ? edit.type
        : cfg.categories.first.key;
    int term = edit?.term ?? initialTerm ?? 1;
    // Aynı kategori+dönem için bir sonraki sıra numarasını öner.
    int nextOrder(String catKey, int t) {
      final same = existing
          .where((g) => g.type == catKey && g.term == t && g.id != edit?.id);
      if (same.isEmpty) return 1;
      return same.map((g) => g.order).reduce((a, b) => a > b ? a : b) + 1;
    }

    int order = edit?.order ?? nextOrder(categoryKey, term);
    // Harf/GPA müfredatında not, harf seçimiyle girilir (sayısal yerine).
    final letterInput = cfg.letterMap != null &&
        (cfg.display == DisplayType.letter || cfg.display == DisplayType.gpa);
    double? letterScore = (letterInput && edit != null) ? edit.score : null;
    final scoreCtrl = TextEditingController(
        text: (edit != null && !letterInput) ? _scoreInputText(edit.score) : '');
    // Döneme etkisi (ağırlık %). Yeni notta varsayılan 30; düzenlemede mevcut.
    int weight = (edit != null && edit.weight > 0) ? edit.weight : 30;
    DateTime date = edit?.date ?? DateTime.now();
    // Açık olan açılır-menü: 'none' | 'term' | 'type' | 'order'.
    String openMenu = 'none';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Panel arka planı soluk beyaz; içindeki alanlar/sekmeler beyaz.
      backgroundColor: const Color(0xFFF3F4F6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final ink = AppPalette.textPrimary(sheetCtx);
          final muted = AppPalette.textSecondary(sheetCtx);

          // Açılan menüdeki tek seçenek satırı (alt alta).
          Widget optionTile(
              String label, bool selected, VoidCallback onSelect) {
            return GestureDetector(
              onTap: () => setSheet(() {
                onSelect();
                openMenu = 'none';
              }),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 11),
                decoration: BoxDecoration(
                  color: selected
                      ? _kBrand.withValues(alpha: 0.12)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color:
                          selected ? _kBrand : AppPalette.border(sheetCtx),
                      width: selected ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    if (selected)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.check_rounded,
                            size: 15, color: _kBrand),
                      ),
                    // Uzun kategori adları dar sütuna sığsın → sarmalı + ellipsis.
                    Expanded(
                      child: Text(label,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: selected ? _kBrand : ink,
                          )),
                    ),
                  ],
                ),
              ),
            );
          }

          // Açık menünün seçenekleri.
          List<Widget> openOptions() {
            switch (openMenu) {
              case 'term':
                return [
                  optionTile('1. ${'Dönem'.tr()}', term == 1,
                      () { term = 1; order = nextOrder(categoryKey, 1); }),
                  optionTile('2. ${'Dönem'.tr()}', term == 2,
                      () { term = 2; order = nextOrder(categoryKey, 2); }),
                ];
              case 'type':
                return [
                  for (final c in cfg.categories)
                    optionTile('${c.emoji} ${c.label.tr()}',
                        categoryKey == c.key,
                        () { categoryKey = c.key; order = nextOrder(c.key, term); }),
                ];
              case 'order':
                final tw = cfg.categoryByKey(categoryKey).label.tr();
                return [
                  for (int n = 1; n <= 4; n++)
                    optionTile('$n. $tw', order == n, () => order = n),
                ];
              default:
                return const [];
            }
          }

          final selCat = cfg.categoryByKey(categoryKey);
          final typeWord = selCat.label.tr();

          // Listede olmayan bir yüzdeyi (ör. %15) elle girer.
          Future<void> pickCustomWeight() async {
            final ctrl = TextEditingController(
                text: const [30, 40, 50, 60].contains(weight) ? '' : '$weight');
            final v = await showDialog<int>(
              context: sheetCtx,
              builder: (dCtx) => AlertDialog(
                backgroundColor: AppPalette.card(dCtx),
                title: Text('Özel yüzde'.tr(),
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(dCtx))),
                content: TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: '1–100', suffixText: '%'),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: Text('Vazgeç'.tr())),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _kBrand),
                    onPressed: () {
                      final n = int.tryParse(ctrl.text.trim());
                      if (n != null && n >= 1 && n <= 100) {
                        Navigator.pop(dCtx, n);
                      }
                    },
                    child: Text('Tamam'.tr(),
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            if (v != null) setSheet(() => weight = v);
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 30,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppPalette.border(sheetCtx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Başlık + sağ üstte küçük tarih kutusu.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          edit != null
                              ? 'Notu Düzenle'.tr()
                              : 'Öğrenci notuna gir'.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 17, fontWeight: FontWeight.w900,
                              color: ink)),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: sheetCtx,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setSheet(() => date = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppPalette.border(sheetCtx)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                size: 15, color: Color(0xFF06B6D4)),
                            const SizedBox(width: 6),
                            Text(
                              '${date.day.toString().padLeft(2, '0')}.'
                              '${date.month.toString().padLeft(2, '0')}.'
                              '${date.year % 100}',
                              style: GoogleFonts.poppins(
                                  fontSize: 12.5, fontWeight: FontWeight.w800,
                                  color: ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Üç alan TEK çerçeve içinde (beyaz zemin), aralarında ayraç.
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppPalette.border(sheetCtx)),
                  ),
                  child: Row(
                    children: [
                      _menuValue(sheetCtx, ink, openMenu == 'term',
                          '$term. ${'Dönem'.tr()}',
                          () => setSheet(() =>
                              openMenu = openMenu == 'term' ? 'none' : 'term')),
                      _vsep(sheetCtx),
                      _menuValue(sheetCtx, ink, openMenu == 'type',
                          '${selCat.emoji} ${selCat.label.tr()}',
                          () => setSheet(() =>
                              openMenu = openMenu == 'type' ? 'none' : 'type')),
                      _vsep(sheetCtx),
                      _menuValue(sheetCtx, ink, openMenu == 'order',
                          '$order. $typeWord',
                          () => setSheet(() => openMenu =
                              openMenu == 'order' ? 'none' : 'order')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Alt form. Açılan menü bunun ÜZERİNDE (overlay) açılır:
                // başlık satırı yukarı kaymaz, içerik aşağı itilmez, arka
                // plan flulanır. (Stack'in son çocuğu = overlay.)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Menü açıkken alt form alanına min yükseklik ver → açılan
                    // seçenekler sayfaya sığar, panel yukarı doğru büyür.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight: openMenu == 'none' ? 0 : 260),
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                // Not alanı (+ müfredat izin veriyorsa yüzdelik katkı).
                Builder(builder: (_) {
                  // Harf/GPA: sayısal alan yerine harf seçim ızgarası.
                  final Widget scoreField = letterInput
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${'Not'.tr()} (${'Harf'.tr()})',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                    color: muted)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6, runSpacing: 6,
                              children: [
                                for (final e in cfg.letterMap!.entries)
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        setSheet(() => letterScore = e.value),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: letterScore == e.value
                                            ? _kBrand.withValues(alpha: 0.12)
                                            : Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: letterScore == e.value
                                              ? _kBrand
                                              : AppPalette.border(sheetCtx),
                                          width:
                                              letterScore == e.value ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Text(e.key,
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: letterScore == e.value
                                                ? _kBrand
                                                : ink,
                                          )),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${'Not'.tr()} (${GradeCalculator.scaleLabel(cfg)})',
                          style: GoogleFonts.poppins(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: muted)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppPalette.border(sheetCtx)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: TextField(
                          controller: scoreCtrl,
                          keyboardType: TextInputType.numberWithOptions(
                              decimal: cfg.decimals > 0),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w800,
                              color: ink),
                          decoration: InputDecoration(
                            hintText: '—',
                            hintStyle: GoogleFonts.poppins(color: muted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  );
                  if (!cfg.showPercentageSelector) return scoreField;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 96, child: scoreField),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Yüzdelik Katkısı'.tr(),
                                style: GoogleFonts.poppins(
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                    color: muted)),
                            const SizedBox(height: 8),
                            Container(
                              height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppPalette.border(sheetCtx)),
                              ),
                              child: Row(
                                children: [
                                  for (final w in const [30, 40, 50, 60])
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () =>
                                            setSheet(() => weight = w),
                                        child: Center(
                                          child: Text('%$w',
                                              style: GoogleFonts.poppins(
                                                fontSize: 13.5,
                                                fontWeight: weight == w
                                                    ? FontWeight.w900
                                                    : FontWeight.w600,
                                                color: weight == w
                                                    ? _kBrand
                                                    : muted,
                                              )),
                                        ),
                                      ),
                                    ),
                                  Container(
                                      width: 1, height: 24,
                                      color: AppPalette.border(sheetCtx)),
                                  // "Özel" — listede olmayan yüzde girişi.
                                  Builder(builder: (_) {
                                    final isCustom = !const [30, 40, 50, 60]
                                        .contains(weight);
                                    return Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: pickCustomWeight,
                                        child: Center(
                                          child: isCustom
                                              ? Text('%$weight',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 13.5,
                                                    fontWeight:
                                                        FontWeight.w900,
                                                    color: _kBrand,
                                                  ))
                                              : Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.tune_rounded,
                                                        size: 13,
                                                        color: muted),
                                                    const SizedBox(width: 3),
                                                    Text('Özel'.tr(),
                                                        style: GoogleFonts
                                                            .poppins(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: muted,
                                                        )),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
                if (cfg.showPercentageSelector) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Yüzdelik katkı, bu notun dönem ortalamasındaki ağırlığıdır. Notlar ağırlıklarına göre hesaplanır; toplam 100 olmasa da oranlanır.'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 10.5, height: 1.4,
                        color: muted.withValues(alpha: 0.85)),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      // Harf modunda seçilen harfin puanı; sayısal modda alan.
                      final score = letterInput
                          ? letterScore
                          : double.tryParse(
                              scoreCtrl.text.trim().replaceAll(',', '.'));
                      if (score == null ||
                          !GradeCalculator.isScoreValid(cfg, score)) {
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                            content: Text(letterInput
                                ? 'Bir harf seç.'.tr()
                                : '${'Geçerli bir not gir.'.tr()} '
                                    '(${GradeCalculator.scaleLabel(cfg)})')));
                        return;
                      }
                      final g = StudentGrade(
                        id: edit?.id ?? '',
                        type: categoryKey,
                        order: order,
                        term: term,
                        score: score,
                        weight: cfg.showPercentageSelector ? weight : 0,
                        date: date,
                      );
                      // Odağı bırak → IME teardown'u bitince sheet'i kapat;
                      // sonra yaz (alttaki StreamBuilder güvenle yenilenir).
                      await safeDismiss(sheetCtx);
                      if (edit != null) {
                        await ClassService.updateGrade(
                            widget.classId, widget.studentUid, g);
                      } else {
                        await ClassService.addGrade(
                            widget.classId, widget.studentUid, g);
                      }
                    },
                    child: Text('Kaydet'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
                      ],
                    ),
                    ),
                    // ── Açılan menü overlay'i ──────────────────────────────
                    // Arka planı (alt formu) flulayan dokunma-ile-kapanan
                    // perde + basılan sütunun hizasında üstte açılan seçenekler.
                    if (openMenu != 'none') ...[
                      Positioned.fill(
                        child: ClipRect(
                          child: BackdropFilter(
                            filter:
                                ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setSheet(() => openMenu = 'none'),
                              child: Container(
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6, left: 0, right: 0,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: openMenu == 'term'
                                    ? Column(children: openOptions())
                                    : const SizedBox()),
                            const SizedBox(width: 1),
                            Expanded(
                                child: openMenu == 'type'
                                    ? Column(children: openOptions())
                                    : const SizedBox()),
                            const SizedBox(width: 1),
                            Expanded(
                                child: openMenu == 'order'
                                    ? Column(children: openOptions())
                                    : const SizedBox()),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
    scoreCtrl.dispose();
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  Widget _buildBody(BuildContext context, List<StudentReportEntry> entries) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);

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

        // ── Risk uyarısı ──────────────────────────────────────────────
        if (_riskMessage(entries) != null) ...[
          _banner(context,
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFEF4444),
              title: 'Dikkat'.tr(),
              text: _riskMessage(entries)!),
          const SizedBox(height: 16),
        ],

        if (entries.isEmpty)
          _emptyState(context, muted)
        else ...[
          // ── Ödevler (2'li grid, çerçeve içinde) ─────────────────────
          Row(
            children: [
              const Text('📚', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text('Ödevler'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 22, fontWeight: FontWeight.w900,
                    color: ink, letterSpacing: -0.3,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          ..._homeworkGrid(context, entries),
        ],
      ],
    );
  }

  /// Ödevleri yatayda 2'li çerçeveler halinde dizer.
  List<Widget> _homeworkGrid(
      BuildContext context, List<StudentReportEntry> entries) {
    // Kronolojik sıra numarası (1 = en eski).
    final ordered = [...entries]
      ..sort((a, b) =>
          a.homework.assignedAt.compareTo(b.homework.assignedAt));
    final orderOf = <String, int>{};
    for (var i = 0; i < ordered.length; i++) {
      orderOf[ordered[i].homework.id] = i + 1;
    }
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 2) {
      final left = entries[i];
      final right = (i + 1 < entries.length) ? entries[i + 1] : null;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: _homeworkCard(
                      context, left, orderOf[left.homework.id] ?? 0)),
              const SizedBox(width: 10),
              Expanded(
                child: right == null
                    ? const SizedBox()
                    : _homeworkCard(
                        context, right, orderOf[right.homework.id] ?? 0),
              ),
            ],
          ),
        ),
      ));
    }
    return rows;
  }

  Widget _homeworkCard(
      BuildContext context, StudentReportEntry e, int orderNo) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final hw = e.homework;
    final score = e.submission?.scorePercent;
    final done = e.isDone;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TeacherHomeworkDetailScreen(
          homework: hw,
          submission: e.submission,
          studentName: widget.studentName,
          studentAvatar: widget.studentAvatar,
          orderNo: orderNo,
        ),
      )),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üstte: ödev adı (sol) + sağ üstte numara (sayı üstte, "Ödev" altta)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(hw.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5, fontWeight: FontWeight.w800, color: ink,
                        height: 1.2),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('$orderNo.',
                        style: GoogleFonts.poppins(
                          fontSize: 17, fontWeight: FontWeight.w900,
                          color: _kBrand, height: 1.0)),
                    Text('Ödev'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 8.5, fontWeight: FontWeight.w700,
                          color: _kBrand, height: 1.1)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('🟢', style: TextStyle(fontSize: 10)),
                const SizedBox(width: 4),
                Text(_fmtDateShort(hw.assignedAt),
                    style: GoogleFonts.poppins(fontSize: 10, color: muted)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Text('🔴', style: TextStyle(fontSize: 10)),
                const SizedBox(width: 4),
                Text(_fmtDateShort(hw.dueAt),
                    style: GoogleFonts.poppins(fontSize: 10, color: muted)),
              ],
            ),
            const SizedBox(height: 10),
            // Durum / skor şeridi
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: (done ? _scoreColor(score) : const Color(0xFF94A3B8))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(done ? Icons.check_circle_rounded
                          : Icons.hourglass_empty_rounded,
                      size: 13,
                      color: done
                          ? _scoreColor(score)
                          : const Color(0xFF94A3B8)),
                  const SizedBox(width: 5),
                  Text(
                      done
                          ? '%${(score ?? 0).toStringAsFixed(0)} ${'başarı'.tr()}'
                          : 'Teslim edilmedi'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10.5, fontWeight: FontWeight.w800,
                        color: done
                            ? _scoreColor(score)
                            : const Color(0xFF94A3B8),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDateShort(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm';
  }

  // ── Yardımcılar ───────────────────────────────────────────────────────
  // Üst bilgi/uyarı şeridi (duyuru, risk).
  Widget _banner(BuildContext context,
      {required IconData icon,
      required Color color,
      required String title,
      required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, fontWeight: FontWeight.w800,
                      color: color, letterSpacing: 0.3)),
                const SizedBox(height: 1),
                Text(text,
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary(context), height: 1.35)),
              ],
            ),
          ),
        ],
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

}
