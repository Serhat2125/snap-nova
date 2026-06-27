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

import '../services/class_service.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
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

  @override
  void initState() {
    super.initState();
    _future = HomeworkService.studentReport(widget.classId, widget.studentUid);
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
                    Text(existing == null ? 'Yeni Not'.tr() : 'Notu Düzelt'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 17, fontWeight: FontWeight.w900,
                            color: ink)),
                    const Spacer(),
                    if (existing != null)
                      IconButton(
                        onPressed: () async {
                          Navigator.pop(sheetCtx);
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
                      // Klavyeyi kapat + sheet'i ÖNCE kapat, sonra yaz
                      // (_dependents.isEmpty çökmesini önler).
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(sheetCtx);
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
          // Klavyeyi kapat + sheet'i ÖNCE kapat, sonra yaz.
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.pop(sheetCtx);
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
        return Column(
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
                  if (!widget.readOnly)
                    FilledButton.icon(
                      onPressed: () => _addGradeDialog(context, grades),
                      style: FilledButton.styleFrom(
                        backgroundColor: _kBrand,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Ekle'.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 12.5, fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                ],
              ),
            ),
            if (grades.isNotEmpty) _gradeSummary(context, grades),
            Expanded(
              child: grades.isEmpty
                  ? _gradesEmpty(context, muted)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: _buildGradeGroups(context, grades),
                    ),
            ),
          ],
        );
      },
    );
  }

  // Dönem ortalaması özet şeridi.
  Widget _gradeSummary(BuildContext context, List<StudentGrade> grades) {
    final avg = grades.map((g) => g.score).reduce((a, b) => a + b) /
        grades.length;
    final passed = grades.where((g) => g.score >= 50).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          _miniStat(context, '📊', 'Ortalama'.tr(),
              avg.toStringAsFixed(0), _scoreColor(avg)),
          _miniDivider(context),
          _miniStat(context, '📝', 'Sınav'.tr(),
              '${grades.length}', const Color(0xFF6366F1)),
          _miniDivider(context),
          _miniStat(context, '✅', 'Geçer'.tr(),
              '$passed/${grades.length}', const Color(0xFF10B981)),
        ],
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

  // Notları döneme göre gruplar; her grup başlıklı.
  List<Widget> _buildGradeGroups(
      BuildContext context, List<StudentGrade> grades) {
    final terms = <int, List<StudentGrade>>{};
    for (final g in grades) {
      terms.putIfAbsent(g.term, () => []).add(g);
    }
    final sortedTerms = terms.keys.toList()..sort();
    final out = <Widget>[];
    for (final t in sortedTerms) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: _sectionLabel(context, '$t. DÖNEM'.tr()),
      ));
      out.addAll(terms[t]!.map((g) => _gradeRow(context, g, grades)));
    }
    return out;
  }

  Widget _gradeRow(
      BuildContext context, StudentGrade g, List<StudentGrade> allGrades) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final color = _scoreColor(g.score.toDouble());
    // Canlı, türüne göre ikon ve renk.
    final typeColor =
        g.isOral ? const Color(0xFFF59E0B) : const Color(0xFF6366F1);
    final typeIcon =
        g.isOral ? Icons.record_voice_over_rounded : Icons.edit_note_rounded;
    final passed = g.score >= 50;
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
            // Tür ikonu (renkli kutu)
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(typeIcon, size: 22, color: typeColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(g.label.tr(),
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
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Not (büyük, renkli)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${g.score}',
                    style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.w900, color: color,
                      height: 1,
                    )),
                Text('/100',
                    style: GoogleFonts.poppins(
                      fontSize: 9.5, fontWeight: FontWeight.w600, color: muted,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
                    : 'Henüz not yok — "Ekle" ile ilk yazılı/sözlü notunu gir.'
                        .tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: muted, height: 1.4),
              ),
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
                  Text('${g.label.tr()} · ${g.score}',
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
        content: Text('${g.label.tr()} (${g.score}) silinsin mi?'.tr(),
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
      {StudentGrade? edit}) async {
    bool isOral = edit?.isOral ?? false;
    int term = edit?.term ?? 1;
    // Aynı tür+dönem için bir sonraki sıra numarasını öner.
    int nextOrder(bool oral, int t) {
      final same = existing
          .where((g) => g.isOral == oral && g.term == t && g.id != edit?.id);
      if (same.isEmpty) return 1;
      return same.map((g) => g.order).reduce((a, b) => a > b ? a : b) + 1;
    }

    int order = edit?.order ?? nextOrder(false, 1);
    final scoreCtrl =
        TextEditingController(text: edit != null ? '${edit.score}' : '');
    DateTime date = edit?.date ?? DateTime.now();

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
          Widget chip(String label, bool selected, VoidCallback onTap,
              Color c) {
            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? c.withValues(alpha: 0.14) : AppPalette.bg(sheetCtx),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: selected ? c : AppPalette.border(sheetCtx),
                      width: selected ? 1.5 : 1),
                ),
                child: Text(label,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? c : muted,
                    )),
              ),
            );
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
                Text(edit != null ? 'Notu Düzenle'.tr() : 'Not Ekle'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 17, fontWeight: FontWeight.w900, color: ink)),
                const SizedBox(height: 16),
                // Tür
                Text('Tür'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: muted)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    chip('📝 ${'Yazılı'.tr()}', !isOral, () {
                      setSheet(() {
                        isOral = false;
                        order = nextOrder(false, term);
                      });
                    }, const Color(0xFF6366F1)),
                    const SizedBox(width: 10),
                    chip('🗣️ ${'Sözlü'.tr()}', isOral, () {
                      setSheet(() {
                        isOral = true;
                        order = nextOrder(true, term);
                      });
                    }, const Color(0xFFF59E0B)),
                  ],
                ),
                const SizedBox(height: 16),
                // Dönem
                Text('Dönem'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: muted)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    chip('1. ${'Dönem'.tr()}', term == 1, () {
                      setSheet(() {
                        term = 1;
                        order = nextOrder(isOral, 1);
                      });
                    }, _kBrand),
                    const SizedBox(width: 10),
                    chip('2. ${'Dönem'.tr()}', term == 2, () {
                      setSheet(() {
                        term = 2;
                        order = nextOrder(isOral, 2);
                      });
                    }, _kBrand),
                  ],
                ),
                const SizedBox(height: 16),
                // Sıra + Not + Tarih
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sıra'.tr(),
                              style: GoogleFonts.poppins(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: muted)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _stepBtn(Icons.remove_rounded, () {
                                if (order > 1) setSheet(() => order--);
                              }),
                              Expanded(
                                child: Text('$order',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: ink)),
                              ),
                              _stepBtn(Icons.add_rounded,
                                  () => setSheet(() => order++)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Not (0-100)'.tr(),
                              style: GoogleFonts.poppins(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: muted)),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: AppPalette.bg(sheetCtx),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppPalette.border(sheetCtx)),
                            ),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: TextField(
                              controller: scoreCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 16, fontWeight: FontWeight.w800,
                                  color: ink),
                              decoration: InputDecoration(
                                hintText: '—',
                                hintStyle:
                                    GoogleFonts.poppins(color: muted),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Tarih
                Text('Tarih'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: muted)),
                const SizedBox(height: 8),
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
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: AppPalette.bg(sheetCtx),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppPalette.border(sheetCtx)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded,
                            size: 18, color: Color(0xFF06B6D4)),
                        const SizedBox(width: 10),
                        Text(_fmtDate(date),
                            style: GoogleFonts.poppins(
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: ink)),
                      ],
                    ),
                  ),
                ),
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
                      final score = int.tryParse(scoreCtrl.text.trim());
                      if (score == null || score < 0 || score > 100) {
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                            content:
                                Text('0-100 arası geçerli bir not gir.'.tr())));
                        return;
                      }
                      final g = StudentGrade(
                        id: edit?.id ?? '',
                        type: isOral ? 'sozlu' : 'yazili',
                        order: order,
                        term: term,
                        score: score,
                        date: date,
                      );
                      // Klavyeyi kapat + sheet'i ÖNCE kapat, sonra yaz.
                      // (Kaydederken sheet açıkken alttaki StreamBuilder'ın
                      //  yeniden kurulması _dependents.isEmpty çökmesi yapıyor.)
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(sheetCtx);
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
          );
        },
      ),
    );
    scoreCtrl.dispose();
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34, height: 40,
          decoration: BoxDecoration(
            color: _kBrand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: _kBrand),
        ),
      );

  String _fmtDate(DateTime d) {
    const months = [
      'Oca','Şub','Mar','Nis','May','Haz',
      'Tem','Ağu','Eyl','Eki','Kas','Ara',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
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
    const months = [
      'Oca','Şub','Mar','Nis','May','Haz',
      'Tem','Ağu','Eyl','Eki','Kas','Ara',
    ];
    return '${d.day} ${months[d.month - 1]}';
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
