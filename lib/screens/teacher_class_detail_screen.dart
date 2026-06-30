// ═══════════════════════════════════════════════════════════════════════════
//  TeacherClassDetailScreen — Bir sınıfın öğretmen detay sayfası.
//
//  - Sınıf bilgisi başlık
//  - Sınıf kodu (kopyalanabilir)
//  - Öğrenci listesi (canlı stream)
//  - Sınıfı sil / paylaş
//
//  İçerik dağıtımı için ileride "Konu Özeti / Test gönder" butonu eklenir.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/class_service.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import '../utils/safe_dismiss.dart';
import '../widgets/class_profile_dialog.dart';
import '../widgets/teacher_help_dialog.dart';
import 'teacher_class_resources_screen.dart';
import 'teacher_student_report_screen.dart';

const _kBrand = Color(0xFF7C3AED);

// ═══════════════════════════════════════════════════════════════════════════
//  DEMO VERİSİ — Öğretmen paneli boşken nasıl görüneceğini göstermek için.
//  "Demo Açık" sekmesi seçilince grid + Özet tablosu bu sahte (ödevini yapmış)
//  öğrencilerle dolar. Gerçek öğrenci verisine hiç dokunmaz; sadece UI önizleme.
// ═══════════════════════════════════════════════════════════════════════════
final DateTime _demoJoined = DateTime(2026, 3, 1);

class _DemoRow {
  final String name;
  final String username;
  final String avatar;
  final int total, correct, wrong, empty;
  const _DemoRow(this.name, this.username, this.avatar,
      this.total, this.correct, this.wrong, this.empty);
}

const List<_DemoRow> _demoRows = [
  _DemoRow('Ahmet Yılmaz', 'ahmety', '🦊', 50, 47, 2, 1),
  _DemoRow('Zeynep Kaya', 'zeynepk', '🐱', 50, 45, 3, 2),
  _DemoRow('Mehmet Demir', 'mehmetd', '🐼', 50, 42, 6, 2),
  _DemoRow('Elif Şahin', 'elifs', '🦉', 50, 40, 8, 2),
  _DemoRow('Can Öztürk', 'cano', '🐯', 50, 37, 10, 3),
  _DemoRow('Ayşe Çelik', 'aysec', '🐰', 50, 34, 12, 4),
  _DemoRow('Mert Aydın', 'merta', '🦁', 50, 31, 14, 5),
  _DemoRow('Selin Arslan', 'selina', '🐨', 50, 28, 16, 6),
  _DemoRow('Burak Doğan', 'burakd', '🐺', 50, 25, 18, 7),
  _DemoRow('Deniz Yıldız', 'denizy', '🦄', 50, 21, 22, 7),
  _DemoRow('Ece Korkmaz', 'ecek', '🐸', 50, 18, 25, 7),
  _DemoRow('Kaan Aksoy', 'kaana', '🐵', 50, 14, 28, 8),
];

List<ClassStudent> get _demoStudents => [
      for (var i = 0; i < _demoRows.length; i++)
        ClassStudent(
          uid: 'demo_$i',
          username: _demoRows[i].username,
          displayName: _demoRows[i].name,
          avatar: _demoRows[i].avatar,
          joinedAt: _demoJoined,
        ),
    ];

List<StudentGradeSummary> get _demoSummaries => [
      for (var i = 0; i < _demoRows.length; i++)
        StudentGradeSummary(
          uid: 'demo_$i',
          name: _demoRows[i].name,
          totalQuestions: _demoRows[i].total,
          correct: _demoRows[i].correct,
          wrong: _demoRows[i].wrong,
          empty: _demoRows[i].empty,
        ),
    ];

class TeacherClassDetailScreen extends StatefulWidget {
  final TeacherClass cls;
  const TeacherClassDetailScreen({super.key, required this.cls});

  @override
  State<TeacherClassDetailScreen> createState() => _TeacherClassDetailScreenState();
}

class _TeacherClassDetailScreenState extends State<TeacherClassDetailScreen> {
  TeacherClass get cls => widget.cls;
  String? _nameOverride; // yeniden adlandırma sonrası başlık güncellemesi
  bool _demo = false; // demo önizleme (app bar'daki "Demo" menüsünden kontrol)

  @override
  void initState() {
    super.initState();
    // Auto-reminder timer başlat — 30 dakikada bir checkPendingReminders.
    // EVENT: teacher dashboard opened → start business logic.
    HomeworkService.startReminderTimer();
  }

  @override
  void dispose() {
    // EVENT: teacher leaves the class detail → keep timer running.
    // (Dashboard kapansa da reminder akışı çalışsın diye stop ETMİYORUZ.
    //  Sadece app kapandığında timer otomatik ölür.)
    super.dispose();
  }

  /// ⋮ Sınıf menüsü — kompakt, dar, her seçenek kendi çerçevesinde + tek
  /// dış çerçeve içinde (alt-ortada açılır).
  Future<void> _showClassMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                decoration: BoxDecoration(
                  color: AppPalette.card(ctx),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: _kBrand.withValues(alpha: 0.30)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18, offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _menuChip(ctx, Icons.vpn_key_rounded, _kBrand,
                        'Davet kodunu kopyala'.tr(), () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                          ClipboardData(text: cls.shortCode));
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(SnackBar(
                        content: Text('Sınıf kodu kopyalandı'.tr()),
                        behavior: SnackBarBehavior.floating));
                    }),
                    _menuChip(ctx, Icons.edit_rounded,
                        const Color(0xFF0EA5E9), 'Sınıfı düzenle'.tr(),
                        () async {
                      Navigator.pop(ctx);
                      final newName = await showEditClassSheet(context, cls);
                      if (newName != null && mounted) {
                        setState(() => _nameOverride = newName);
                      }
                    }),
                    _menuChip(ctx, Icons.folder_shared_rounded,
                        const Color(0xFF10B981), 'Paylaşılan Kaynaklar'.tr(),
                        () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              TeacherClassResourcesScreen(cls: cls)));
                    }),
                    _menuChip(ctx, Icons.help_outline_rounded,
                        const Color(0xFF7C3AED), 'Nasıl kullanılır?'.tr(),
                        () { Navigator.pop(ctx); _showHelp(context); }),
                    _menuChip(ctx, Icons.delete_outline_rounded,
                        const Color(0xFFEF4444), 'Sınıfı sil'.tr(),
                        () { Navigator.pop(ctx); _confirmDelete(); },
                        danger: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Kompakt menü kartı — küçük ikon + başlık, kendi oval çerçevesi.
  Widget _menuChip(BuildContext c, IconData icon, Color color, String title,
      VoidCallback onTap, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppPalette.bg(c),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: color.withValues(alpha: danger ? 0.40 : 0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: danger ? color : AppPalette.textPrimary(c))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _confirmDelete() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppPalette.card(dctx),
        title: Text('Sınıfı sil'.tr(),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(dctx))),
        content: Text(
            'Bu sınıfı silersen sınıftaki tüm geçmiş veriler ve kişiler silinir. Yine de silmek istiyor musun?'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppPalette.textSecondary(dctx),
                height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('Şimdilik kalsın'.tr(),
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(dctx)))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text('Sil'.tr(),
                style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ClassService.deleteClass(cls.id, cls.code);
    if (!mounted) return;
    if (done) {
      navigator.pop(); // detay ekranını kapat — liste stream'le güncellenir
      messenger.showSnackBar(SnackBar(
        content: Text('Sınıf silindi'.tr()),
        behavior: SnackBarBehavior.floating));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('Silinemedi, tekrar dene'.tr()),
        behavior: SnackBarBehavior.floating));
    }
  }

  /// "?" yardım paneli — bu sayfanın nasıl çalıştığını anlatır.
  void _showHelp(BuildContext context) {
    showTeacherHelpDialog(
      context,
      title: 'Bu sayfa nasıl çalışır?',
      items: const [
        TeacherHelpItem('👤', 'Öğrenci profilleri',
            'Sınıf koduyla katılan öğrenciler burada listelenir. Avatarı, adı ve @kullanıcı adı görünür.'),
        TeacherHelpItem('📊', 'Öğrenciye dokun → karne',
            'Bir öğrenciye dokununca o öğrencinin yaptığı ödevler, doğru/yanlış dağılımı ve gelişim grafikleri açılır.'),
        TeacherHelpItem('✏️', 'Uzun bas → ad değiştir',
            'Bir öğrenciye uzun basınca sınıfta görünen adını (gerçek adı ya da bir lakap) sen belirleyebilirsin.'),
        TeacherHelpItem('➕', 'Öğrenci davet et',
            '"Öğrenci Ara & Davet Et" ile kullanıcı adından arayıp sınıfa davet gönderebilirsin. Öğrenciler ayrıca sınıf koduyla da katılır.'),
        TeacherHelpItem('📝', 'Ödev vermek için',
            'Ödev oluşturmak için ana paneldeki ortadaki ➕ butonuna bas → "AI ile Ödev Oluştur" → bu sınıfı seç.'),
      ],
    );
  }

  /// App bar'da 3 noktanın hemen solunda "Demo" düğmesi. Basınca hemen altında
  /// alt alta iki küçük seçenek açılır: "Demoyu aç" / "Demoyu kapat".
  Widget _demoMenuButton(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Demo'.tr(),
      offset: const Offset(0, 46),
      color: AppPalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) => setState(() => _demo = v),
      itemBuilder: (ctx) => [
        PopupMenuItem<bool>(
          value: true,
          height: 40,
          child: Row(children: [
            const Icon(Icons.visibility_rounded, size: 17, color: _kBrand),
            const SizedBox(width: 8),
            Text('Demoyu aç'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(ctx))),
          ]),
        ),
        PopupMenuItem<bool>(
          value: false,
          height: 40,
          child: Row(children: [
            Icon(Icons.visibility_off_rounded,
                size: 17, color: AppPalette.textSecondary(ctx)),
            const SizedBox(width: 8),
            Text('Demoyu kapat'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(ctx))),
          ]),
        ),
      ],
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 9),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _demo ? _kBrand : _kBrand.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: _kBrand.withValues(alpha: _demo ? 1.0 : 0.40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Demo'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 12.5, fontWeight: FontWeight.w800,
                    color: _demo ? Colors.white : _kBrand)),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded,
                size: 18, color: _demo ? Colors.white : _kBrand),
          ],
        ),
      ),
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
        title: Text(_nameOverride ?? cls.name,
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
        actions: [
          _demoMenuButton(context),
          IconButton(
            icon: Icon(Icons.menu_rounded, color: ink),
            tooltip: 'Sınıf menüsü'.tr(),
            onPressed: () => _showClassMenu(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Üst kart: kod + bilgi ───────────────────────────────
            // Yalnızca öğrenci profilleri listelenir (kod kartı + Ödev/Analiz
            // sekmeleri kaldırıldı). Kod, sınıf listesindeki kartta ve üstteki
            // paylaş ikonunda mevcut. Bir öğrenciye basınca rapor açılır.
            Expanded(child: _StudentsView(cls: cls, demo: _demo)),
          ],
        ),
      ),
    );
  }
}

class _StudentsView extends StatefulWidget {
  final TeacherClass cls;
  final bool demo; // app bar "Demo" menüsünden kontrol edilen önizleme durumu
  const _StudentsView({required this.cls, required this.demo});
  @override
  State<_StudentsView> createState() => _StudentsViewState();
}

class _StudentsViewState extends State<_StudentsView> {
  int _view = 0; // 0 = Öğrenciler (grid), 1 = Özet (tablo)
  Future<List<StudentGradeSummary>>? _summaryFuture;
  String? _selectedHwId; // null = tüm ödevler
  String? _sortKey; // null = varsayılan başarı sırası; 'name'/'correct'/...
  bool _sortAsc = false;
  String _selectedHwTitle = '';
  Offset? _fabPos; // Sürüklenebilir Özet butonunun konumu

  // Özet görünümünde pill genişler (Öğrenciler + Ödevler birlikte).
  double get _fabW => _view == 1 ? 300.0 : 150.0;
  static const double _fabH = 46;

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Column(
      children: [
        if (widget.demo) _demoBanner(context),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            // Varsayılan konum: sağ alt köşe.
            final pos = _fabPos ??
                Offset(c.maxWidth - _fabW - 16, c.maxHeight - _fabH - 24);
            return Stack(
              children: [
                Positioned.fill(
                  child: _view == 0
                      ? _studentsTab(context, ink, muted)
                      : _summaryTab(context, ink, muted),
                ),
                Positioned(
                  // Güvenli sınır: dar/sıfır constraint'te clamp atmasın.
                  left: pos.dx
                      .clamp(8.0, math.max(8.0, c.maxWidth - _fabW - 8)),
                  top: pos.dy
                      .clamp(8.0, math.max(8.0, c.maxHeight - _fabH - 8)),
                  child: _draggableTab(context, c),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  // ── Demo açıkken gösterilen ince bilgi banner'ı (aç/kapa app bar'da) ──
  Widget _demoBanner(BuildContext context) {
    const brand = Color(0xFF7C3AED);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Text(
        '🎬 ${'Demo görünümü — gerçek öğrenciler sınıfa katıldığında paneliniz aynen böyle dolacak. Bu öğrenciler örnektir.'.tr()}',
        style: GoogleFonts.poppins(
          fontSize: 10.5,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: brand,
        ),
      ),
    );
  }

  // ── Sürüklenebilir sekme: öğretmen istediği yere taşıyabilir ───────────
  //  Grid'de: [⠿ 📊 Özet].  Özet'te: [⠿ 👥 Öğrenciler | 📋 Ödevler ▾].
  Widget _draggableTab(BuildContext context, BoxConstraints c) {
    const brand = Color(0xFF7C3AED);
    final summary = _view == 1;
    return GestureDetector(
      // Sürükle → konumu güncelle (ekran sınırları içinde).
      onPanUpdate: (d) {
        setState(() {
          final cur = _fabPos ??
              Offset(c.maxWidth - _fabW - 16, c.maxHeight - _fabH - 24);
          _fabPos = Offset(
            (cur.dx + d.delta.dx)
                .clamp(8.0, math.max(8.0, c.maxWidth - _fabW - 8)),
            (cur.dy + d.delta.dy)
                .clamp(8.0, math.max(8.0, c.maxHeight - _fabH - 8)),
          );
        });
      },
      child: Material(
        elevation: 6,
        shadowColor: brand.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        color: brand,
        child: Container(
          width: _fabW, height: _fabH,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.drag_indicator_rounded,
                  size: 16, color: Colors.white70),
              const SizedBox(width: 4),
              // Sol: görünüm geçişi (Özet ↔ Öğrenciler)
              Flexible(
                child: InkWell(
                  onTap: () => setState(() {
                    _view = summary ? 0 : 1;
                    if (!summary) {
                      _summaryFuture = HomeworkService.classGradeSummary(
                          widget.cls.id, homeworkId: _selectedHwId);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(summary ? '👥' : '📊',
                            style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                              summary ? 'Öğrenciler'.tr() : 'Özet'.tr(),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Özet görünümünde: ayraç + Ödevler seçici
              if (summary) ...[
                Container(width: 1, height: 22, color: Colors.white30),
                InkWell(
                  onTap: _pickHomework,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.assignment_rounded,
                            size: 15, color: Colors.white),
                        const SizedBox(width: 5),
                        Text('Ödevler'.tr(),
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        const Icon(Icons.expand_more_rounded,
                            size: 16, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Özet sekmesi: tüm öğrencilerin Excel benzeri sonuç tablosu ─────────
  Widget _summaryTab(BuildContext context, Color ink, Color muted) {
    // Demo açıkken gerçek veriyi sorgulamadan sahte özetler gösterilir.
    if (widget.demo) {
      return _summaryBody(context, ink, _demoSummaries, 'Sınıf Özeti'.tr());
    }
    _summaryFuture ??= HomeworkService.classGradeSummary(
        widget.cls.id, homeworkId: _selectedHwId);
    return FutureBuilder<List<StudentGradeSummary>>(
      future: _summaryFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final rows = snap.data ?? const <StudentGradeSummary>[];
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Henüz sonuç yok — öğrenciler ödev teslim ettikçe '
                  'özet burada görünecek.'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: muted, height: 1.45)),
            ),
          );
        }
        return _summaryBody(context, ink, rows,
            _selectedHwId == null ? 'Sınıf Özeti'.tr() : _selectedHwTitle);
      },
    );
  }

  /// Özet gövdesi — başlık + "Tam ekran yap" + Excel tablosu. Hem gerçek hem
  /// demo veriyle çağrılır.
  Widget _summaryBody(BuildContext context, Color ink,
      List<StudentGradeSummary> rows, String title) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık + sağda "Tam ekran yap" (tablo hizasında)
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w900, color: ink)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      _FullscreenSummaryScreen(title: title, rows: rows),
                )),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kBrand.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBrand, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fullscreen_rounded,
                          size: 11, color: _kBrand),
                      const SizedBox(width: 3),
                      Text('Tam ekran yap'.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: _kBrand)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Donuk sütunlu tablo: # + isim sabit, kalan sütunlar kayar.
          _excelTable(context, rows),
        ],
      ),
    );
  }

  static const double _rowH = 46;
  static const double _headH = 42;

  /// Donuk-sütunlu özet tablosu: SOL (# + Öğrenci) sabit; SAĞ (Soru/Doğru/
  /// Yanlış/Boş/Başarı) yatay kaydırılabilir. Dikey kaydırma ikisini birlikte
  /// taşır (ortak satır yükseklikleri sayesinde hizalı kalır).
  Widget _excelTable(BuildContext context, List<StudentGradeSummary> rows) {
    const green = Color(0xFF10B981);
    const red = Color(0xFFEF4444);
    const gray = Color(0xFF94A3B8);
    final medals = <int, String>{0: '🥇', 1: '🥈', 2: '🥉'};

    // #2 Sıralama: başlığa basınca yerel sıralama. null = servis sırası (başarı).
    final sorted = [...rows];
    if (_sortKey != null) {
      int cmp(StudentGradeSummary a, StudentGradeSummary b) {
        switch (_sortKey) {
          case 'name':
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          case 'total': return a.totalQuestions.compareTo(b.totalQuestions);
          case 'correct': return a.correct.compareTo(b.correct);
          case 'wrong': return a.wrong.compareTo(b.wrong);
          case 'empty': return a.empty.compareTo(b.empty);
          case 'pct': return a.pct.compareTo(b.pct);
          default: return 0;
        }
      }
      sorted.sort((a, b) => _sortAsc ? cmp(a, b) : cmp(b, a));
    }
    // Madalya yalnız varsayılan başarı sırasında anlamlı; özel sıralamada sıra no.
    final showMedals = _sortKey == null;

    // SOL sabit kısım: # + Öğrenci (satır tıklanınca rapora geçer)
    final frozen = Table(
      border: TableBorder.all(color: AppPalette.border(context)),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {0: FixedColumnWidth(40), 1: FixedColumnWidth(124)},
      children: [
        TableRow(
          decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12)),
          children: [
            _tcell(context, '#', null, header: true),
            _hcell(context, 'Öğrenci'.tr(), 'name', left: true),
          ],
        ),
        for (var i = 0; i < sorted.length; i++)
          TableRow(children: [
            _tcell(context, showMedals ? (medals[i] ?? '${i + 1}') : '${i + 1}',
                AppPalette.textPrimary(context),
                onTap: () => _openStudentReport(sorted[i])),
            _tcell(context, sorted[i].name, AppPalette.textPrimary(context),
                left: true, onTap: () => _openStudentReport(sorted[i])),
          ]),
      ],
    );

    // SAĞ kayan kısım: sayısal sütunlar (başlıklar sıralanabilir)
    final scroll = Table(
      border: TableBorder.all(color: AppPalette.border(context)),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: FixedColumnWidth(56),
        1: FixedColumnWidth(58),
        2: FixedColumnWidth(58),
        3: FixedColumnWidth(50),
        4: FixedColumnWidth(64),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.12)),
          children: [
            _hcell(context, 'Soru'.tr(), 'total'),
            _hcell(context, 'Doğru'.tr(), 'correct'),
            _hcell(context, 'Yanlış'.tr(), 'wrong'),
            _hcell(context, 'Boş'.tr(), 'empty'),
            _hcell(context, 'Başarı'.tr(), 'pct'),
          ],
        ),
        for (final r in sorted)
          TableRow(children: [
            _tcell(context, '${r.totalQuestions}', const Color(0xFF6366F1),
                onTap: () => _openStudentReport(r)),
            _tcell(context, '${r.correct}', green,
                onTap: () => _openStudentReport(r)),
            _tcell(context, '${r.wrong}', red,
                onTap: () => _openStudentReport(r)),
            _tcell(context, '${r.empty}', gray,
                onTap: () => _openStudentReport(r)),
            _tcell(context, '%${r.pct.toStringAsFixed(0)}', _scoreColor(r.pct),
                onTap: () => _openStudentReport(r)),
          ]),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        frozen,
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: scroll,
          ),
        ),
      ],
    );
  }

  /// Sabit yükseklikli hücre — sol ve sağ tabloların satırları hizalı kalsın.
  /// [onTap] verilirse satır tıklanabilir (öğrenci raporuna geçiş).
  Widget _tcell(BuildContext context, String t, Color? color,
      {bool left = false, bool header = false, VoidCallback? onTap}) {
    final cell = SizedBox(
      height: header ? _headH : _rowH,
      child: Align(
        alignment: left ? Alignment.centerLeft : Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(t,
              textAlign: left ? TextAlign.left : TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: header ? 11 : 12.5,
                  fontWeight: FontWeight.w800,
                  color: color ?? AppPalette.textPrimary(context))),
        ),
      ),
    );
    if (onTap == null) return cell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque, onTap: onTap, child: cell);
  }

  /// Tıklanabilir başlık hücresi — sütuna göre sıralar; aktifse ↑/↓ gösterir.
  Widget _hcell(BuildContext context, String label, String key,
      {bool left = false}) {
    final active = _sortKey == key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (_sortKey == key) {
          _sortAsc = !_sortAsc;
        } else {
          _sortKey = key;
          _sortAsc = false; // ilk dokunuşta büyükten küçüğe
        }
      }),
      child: SizedBox(
        height: _headH,
        child: Align(
          alignment: left ? Alignment.centerLeft : Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment:
                  left ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w800,
                          color: active
                              ? _kBrand
                              : AppPalette.textPrimary(context))),
                ),
                Icon(
                  active
                      ? (_sortAsc
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded)
                      : Icons.unfold_more_rounded,
                  size: 12,
                  color: active
                      ? _kBrand
                      : AppPalette.textSecondary(context).withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tablo satırından öğrenci raporuna geçiş (demo öğrencide uyarı).
  void _openStudentReport(StudentGradeSummary r) {
    if (r.uid.startsWith('demo_')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
            'Bu bir demo öğrencidir. Gerçek öğrenci katıldığında karnesi açılır.'
                .tr())));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeacherStudentReportScreen(
        classId: widget.cls.id,
        studentUid: r.uid,
        studentName: r.name,
        studentAvatar: '👤',
      ),
    ));
  }

  Color _scoreColor(double score) {
    if (score >= 70) return const Color(0xFF10B981);
    if (score >= 40) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  // Ödev seçici — "Tümü" + verilen ödevler (en son en üstte).
  Future<void> _pickHomework() async {
    final hws = await HomeworkService.classHomeworks(widget.cls.id);
    if (!mounted) return;
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
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
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.border(ctx),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Text('Ödev seç'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w900,
                          color: AppPalette.textPrimary(ctx))),
                ],
              ),
            ),
            // Tümü
            _hwOption(ctx, null, '📚 ${'Tüm ödevler'.tr()}', null,
                selected: _selectedHwId == null),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: hws.length,
                itemBuilder: (c, i) {
                  final hw = hws[i];
                  // hws yeni→eski; kronolojik numara = toplam - i.
                  final no = hws.length - i;
                  return _hwOption(ctx, hw.id, '$no. ${'Ödev'.tr()} · ${hw.title}',
                      fmt(hw.assignedAt),
                      selected: _selectedHwId == hw.id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hwOption(BuildContext ctx, String? id, String title, String? date,
      {required bool selected}) {
    const brand = Color(0xFF7C3AED);
    return ListTile(
      dense: true,
      leading: Icon(
          id == null ? Icons.dashboard_rounded : Icons.assignment_rounded,
          color: selected ? brand : AppPalette.textSecondary(ctx)),
      title: Text(title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              color: selected ? brand : AppPalette.textPrimary(ctx))),
      subtitle: date == null
          ? null
          : Text('🟢 $date',
              style: GoogleFonts.poppins(
                  fontSize: 10.5, color: AppPalette.textSecondary(ctx))),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: brand, size: 20)
          : null,
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          _selectedHwId = id;
          _selectedHwTitle = id == null ? '' : title;
          _summaryFuture = HomeworkService.classGradeSummary(
              widget.cls.id, homeworkId: id);
        });
      },
    );
  }

  Widget _studentsTab(BuildContext context, Color ink, Color muted) {
    // Demo açıkken canlı stream yerine sahte öğrenci grid'i gösterilir.
    if (widget.demo) {
      return _studentsGrid(context, ink, muted, _demoStudents, true);
    }
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ClassStudent>>(
            stream: ClassService.studentsStream(widget.cls.id),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Öğrenciler yüklenemedi. İnternet bağlantını '
                        'kontrol et.'.tr(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: muted, height: 1.45)),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2));
              }
              final students = snap.data!;
              if (students.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Henüz öğrenci yok — kodu paylaş, öğrenciler katıldıkça burada görünecek.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: muted, height: 1.45),
              ),
            ),
          );
        }
                return _studentsGrid(context, ink, muted, students, false);
              },
            ),
          ),
        ],
      );
  }

  /// Öğrenci grid'i — gerçek (canlı) ve demo öğrenciler için ortak.
  /// [isDemo] true ise: karta dokununca boş karne yerine kısa bilgi gösterilir
  /// ve uzun bas (ad değiştir) devre dışı kalır.
  Widget _studentsGrid(BuildContext context, Color ink, Color muted,
      List<ClassStudent> students, bool isDemo) {
    return GridView.builder(
      // Daha dar yatay boşluk + küçük sütun aralığı → kartlar genişler.
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 4,
        childAspectRatio: 0.82,
      ),
      itemCount: students.length,
      itemBuilder: (ctx, i) {
        final s = students[i];
        return GestureDetector(
          onLongPress: isDemo ? null : () => _editStudentName(context, s),
          onTap: isDemo
              ? () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                        'Bu bir demo öğrencidir. Gerçek öğrenci katıldığında dokununca karnesi açılır.'
                            .tr()),
                  ))
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TeacherStudentReportScreen(
                        classId: widget.cls.id,
                        studentUid: s.uid,
                        studentName: s.displayLabel,
                        studentAvatar: s.avatar,
                      ),
                    ),
                  ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
                  ),
                  alignment: Alignment.center,
                  child:
                      Text(s.avatar, style: const TextStyle(fontSize: 21)),
                ),
                const SizedBox(height: 6),
                Text(
                  s.displayLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: ink, height: 1.1,
                  ),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
                Text('@${s.username}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 9.5, color: muted,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Öğretmen bir öğrenciye uzun basınca: sınıftaki görünen adını (gerçek ad
  /// veya lakap) belirlediği alt sayfa. Boş bırakıp kaydederse öğrenci yeniden
  /// kendi adı/kullanıcı adıyla görünür.
  Future<void> _editStudentName(BuildContext context, ClassStudent s) async {
    final ctrl = TextEditingController(text: s.teacherAlias);
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    // Sheet bir AKSİYON döndürür ('remove'); çıkar-onayı sheet TAMAMEN
    // kapandıktan SONRA açılır. Böylece autofocus TextField unmount'u ile
    // dialog açılışı çakışmaz (_dependents.isEmpty kırmızı ekranı).
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Future<void> save(String value) async {
              if (saving) return;
              saving = true;
              final messenger = ScaffoldMessenger.of(context);
              // Odağı bırak → IME teardown'u bitince sheet'i güvenle kapat.
              await safeDismiss(sheetCtx);
              final ok = await ClassService.setStudentAlias(
                  widget.cls.id, s.uid, value);
              messenger.showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Öğrencinin görünen adı güncellendi'.tr()
                    : 'Ad güncellenemedi, tekrar dene'.tr()),
              ));
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppPalette.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
                        ),
                        alignment: Alignment.center,
                        child: Text(s.avatar,
                            style: const TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Görünen adı belirle'.tr(),
                                style: GoogleFonts.poppins(
                                  fontSize: 16, fontWeight: FontWeight.w800,
                                  color: ink,
                                )),
                            Text('@${s.username}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12, color: muted,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Bu öğrencinin sınıf listesinde nasıl görüneceğini sen belirle — gerçek adını yazabilir ya da bir lakap verebilirsin.'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, color: muted, height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: save,
                    style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700, color: ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Örn. Ahmet Yılmaz veya Kaptan'.tr(),
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: muted.withValues(alpha: 0.6)),
                      filled: true,
                      fillColor: AppPalette.bg(context),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppPalette.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppPalette.border(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFF7C3AED), width: 1.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (s.teacherAlias.trim().isNotEmpty)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving ? null : () => save(''),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: muted,
                              side: BorderSide(color: AppPalette.border(context)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('Sıfırla'.tr(),
                                style: GoogleFonts.poppins(
                                    fontSize: 13, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      if (s.teacherAlias.trim().isNotEmpty)
                        const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              saving ? null : () => save(ctrl.text),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: saving
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text('Kaydet'.tr(),
                                  style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(height: 1, color: AppPalette.border(context)),
                  const SizedBox(height: 4),
                  // ── Öğrenciyi sınıftan çıkar ──────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              // Sheet'i 'remove' aksiyonuyla GÜVENLE kapat;
                              // çıkar-onayı await tamamlanınca (sheet tamamen
                              // kapandıktan sonra) açılır.
                              await safeDismiss(sheetCtx, 'remove');
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.person_remove_rounded, size: 18),
                      label: Text('Bu öğrenciyi sınıftan çıkar'.tr(),
                          style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    ctrl.dispose();
    // Sheet tamamen kapandı; "çıkar" istendiyse onay dialog'u ŞİMDİ açılır.
    if (action == 'remove' && mounted) {
      await _confirmRemoveStudent(s);
    }
  }

  /// Öğrenciyi sınıftan çıkarma onayı — onaylanırsa tüm verisi silinir.
  /// Kararlı State context'i kullanır (StreamBuilder/LayoutBuilder context
  /// churn'ünden etkilenmez).
  Future<void> _confirmRemoveStudent(ClassStudent s) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Öğrenciyi çıkar'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(ctx))),
            ),
          ],
        ),
        content: Text(
          '"${s.displayLabel}" adlı öğrenciyi sınıftan çıkarırsan bu '
                  'öğrencinin tüm ödev verileri, yazılı/sözlü notları ve '
                  'sınıftaki kişisel bilgileri kalıcı olarak silinir. '
                  'Bu işlem geri alınamaz.'
              .tr(),
          style: GoogleFonts.poppins(
              fontSize: 13, height: 1.45,
              color: AppPalette.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Yine de Çıkar'.tr(),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ClassService.removeStudent(widget.cls.id, s.uid);
    messenger.showSnackBar(SnackBar(
      content: Text(done
          ? 'Öğrenci sınıftan çıkarıldı'.tr()
          : 'Çıkarılamadı, tekrar dene'.tr()),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _FullscreenSummaryScreen — Özet tablosunu YATAY tam ekran gösterir.
//  Tüm öğrencilerin adı + soru/doğru/yanlış/boş + başarı oranı tek ekranda.
// ═══════════════════════════════════════════════════════════════════════════
class _FullscreenSummaryScreen extends StatefulWidget {
  final String title;
  final List<StudentGradeSummary> rows;
  const _FullscreenSummaryScreen({required this.title, required this.rows});

  @override
  State<_FullscreenSummaryScreen> createState() =>
      _FullscreenSummaryScreenState();
}

class _FullscreenSummaryScreenState extends State<_FullscreenSummaryScreen> {
  @override
  void initState() {
    super.initState();
    // Yatay moda zorla.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Dikey moda geri dön.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  Color _scoreColor(double s) {
    if (s >= 70) return const Color(0xFF10B981);
    if (s >= 40) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    const brand = Color(0xFF7C3AED);
    const green = Color(0xFF10B981);
    const red = Color(0xFFEF4444);
    const gray = Color(0xFF94A3B8);

    Widget hCell(String t, {bool left = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Text(t,
              textAlign: left ? TextAlign.left : TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
        );
    Widget cell(String t, Color c,
            {bool left = false, bool bold = true}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Text(t,
              textAlign: left ? TextAlign.left : TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: c)),
        );

    final tableRows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: brand.withValues(alpha: 0.12)),
        children: [
          hCell('#'),
          hCell('Öğrenci'.tr(), left: true),
          hCell('Soru'.tr()),
          hCell('Doğru'.tr()),
          hCell('Yanlış'.tr()),
          hCell('Boş'.tr()),
          hCell('Başarı'.tr()),
        ],
      ),
    ];
    for (var i = 0; i < widget.rows.length; i++) {
      final r = widget.rows[i];
      final medal =
          i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}';
      tableRows.add(TableRow(
        children: [
          cell(medal, ink),
          cell(r.name, ink, left: true),
          cell('${r.totalQuestions}', const Color(0xFF6366F1)),
          cell('${r.correct}', green),
          cell('${r.wrong}', red),
          cell('${r.empty}', gray),
          cell('%${r.pct.toStringAsFixed(0)}', _scoreColor(r.pct)),
        ],
      ));
    }

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Row(
          children: [
            const Text('📊', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w900, color: ink)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.fullscreen_exit_rounded, color: ink),
            tooltip: 'Kapat'.tr(),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Table(
            border: TableBorder.all(
              color: AppPalette.border(context),
              borderRadius: BorderRadius.circular(12),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            // Yatay tam ekran: ad esnek, sayılar sabit → ekranı doldurur.
            columnWidths: const {
              0: FixedColumnWidth(54),
              1: FlexColumnWidth(),
              2: FixedColumnWidth(80),
              3: FixedColumnWidth(80),
              4: FixedColumnWidth(80),
              5: FixedColumnWidth(70),
              6: FixedColumnWidth(90),
            },
            children: tableRows,
          ),
        ),
      ),
    );
  }
}
