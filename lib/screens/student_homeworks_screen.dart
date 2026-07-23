// ═══════════════════════════════════════════════════════════════════════════
//  StudentHomeworksScreen — Öğrencinin katıldığı sınıflardan gelen ödevler.
//
//  Liste: tüm sınıfların aktif ödevleri (tarih bazlı sıralı).
//  Karta tıkla → HomeworkSolveScreen açılır → ödev çözülür → submission Firestore.
//
//  Profile veya Library'den giriş alır. Aynı zamanda push notification'dan
//  açılabilir (homework_assigned tap).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/education_models.dart';
import '../services/class_service.dart';
import '../services/runtime_translator.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import 'homework_solve_screen.dart';
import 'teacher_homework_detail_screen.dart';

class StudentHomeworksScreen extends StatefulWidget {
  const StudentHomeworksScreen({super.key});

  @override
  State<StudentHomeworksScreen> createState() => _StudentHomeworksScreenState();
}

class _StudentHomeworksScreenState extends State<StudentHomeworksScreen> {
  List<JoinedClass> _classes = [];
  // Öğretmen onayı bekleyen sınıflar — ödevleri gizli, üstte bilgi şeridi.
  List<JoinedClass> _pendingClasses = [];
  Map<String, List<HomeworkModel>> _byClass = {};
  Map<String, HomeworkSubmissionModel?> _mySubmissions = {};
  bool _loading = true;
  // Yükleme hatası (ağ/izin) — sessizce "ödev yok" göstermek yanıltıcıydı;
  // kullanıcıya hata + tekrar dene sunulur.
  bool _error = false;

  // ── Sayfa arka planı — çalışma odası fotoğrafları ─────────────────────────
  // Sağ üstteki duvar kağıdı ikonundan seçilir (1..5), hafif flu çizilir ve
  // SharedPreferences'ta kalıcıdır. null → düz tema zemini.
  static const _kBgPrefKey = 'student_hw_bg_v1';
  static const int _bgCount = 5;
  int? _bgIndex;

  // ── Düzen katmanları: filtre çipleri + arama + geçmiş arşivi ────────────
  // Kurallar: arama aktifken gruplar/arşiv düzleşir; çip+arama VE mantığıyla
  // çalışır; boş grup başlığı gizlenir.
  String? _filterSubject; // null = tüm dersler
  String? _filterClassId; // null = tüm sınıflar
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  bool _archiveOpen = false;
  /// Arama kutusu bu sayıdan çok ödev olunca görünür (azken yer israfı).
  static const int _kSearchThreshold = 15;
  /// Teslim edilmiş ve bitişi bu kadar geçmiş ödevler arşive katlanır.
  static const Duration _kArchiveAfter = Duration(days: 21);

  @override
  void initState() {
    super.initState();
    _loadBgPref();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBgPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_kBgPrefKey);
      if (mounted && v != null && v >= 1 && v <= _bgCount) {
        setState(() => _bgIndex = v);
      }
    } catch (_) {/* okunamazsa düz zeminle devam */}
  }

  Future<void> _saveBgPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_bgIndex == null) {
        await prefs.remove(_kBgPrefKey);
      } else {
        await prefs.setInt(_kBgPrefKey, _bgIndex!);
      }
    } catch (_) {}
  }

  /// Arka plan seçim sayfası — 5 çalışma odası fotoğrafı + "arka plan yok".
  Future<void> _pickBackground() async {
    final ink = AppPalette.textPrimary(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppPalette.bg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.border(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Arka Plan Seç'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 4),
            Text('Beğendiğin çalışma odası bu sayfanın arka planı olur.'.tr(),
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppPalette.textSecondary(ctx))),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
              children: [
                for (int i = 1; i <= _bgCount; i++)
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset('assets/library_icons/hw_bg_$i.jpg',
                              fit: BoxFit.cover),
                          if (_bgIndex == i)
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: const Color(0xFF22C55E),
                                    width: 3),
                              ),
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF22C55E), size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                // Arka planı kaldır — düz tema zemini.
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppPalette.cardMuted(ctx),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _bgIndex == null
                              ? const Color(0xFF22C55E)
                              : AppPalette.border(ctx),
                          width: _bgIndex == null ? 3 : 1),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hide_image_outlined,
                            size: 24,
                            color: AppPalette.textSecondary(ctx)),
                        const SizedBox(height: 6),
                        Text('Arka plan yok'.tr(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.textSecondary(ctx))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _bgIndex = picked == 0 ? null : picked);
    _saveBgPref();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      // Tüm sınıfları al
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid == null) {
        setState(() => _loading = false);
        return;
      }
      // joined classes
      final joinedSnap = await FirebaseFirestore.instance
          .collection('users').doc(myUid)
          .collection('joined_classes').get();
      final rawClasses = joinedSnap.docs
          .map((d) => JoinedClass.fromMap(d.id, d.data())).toList();
      // Üyelik durumunu CANLI üyelik dökümanından doğrula: öğretmen onayı
      // bekleyen (pending) sınıfların ödevleri gizlenir; üyeliği silinmiş
      // (reddedilmiş/çıkarılmış) sınıflar hiç listelenmez.
      final classes = <JoinedClass>[];
      final pending = <JoinedClass>[];
      await Future.wait(rawClasses.map((c) async {
        try {
          final member = await FirebaseFirestore.instance
              .collection('classes').doc(c.classId)
              .collection('students').doc(myUid).get();
          if (!member.exists) return;
          final st = (member.data()?['status'] ?? 'active').toString();
          if (st == 'pending') {
            pending.add(c.withStatus('pending'));
          } else {
            classes.add(c.withStatus(st));
          }
        } catch (_) {
          classes.add(c); // okuma hatasında sınıfı KORU
        }
      }));
      _classes = classes;
      _pendingClasses = pending;
      // Her sınıfın aktif ödevleri + benim teslimlerim — sınıflar arası ve
      // teslim okumaları PARALEL (eski seri N+1 akış 3 sınıf × 20 ödevde
      // 60+ ardışık istek yapıp sayfayı saniyelerce bekletiyordu).
      final byClass = <String, List<HomeworkModel>>{};
      final subs = <String, HomeworkSubmissionModel?>{};
      await Future.wait(classes.map((c) async {
        final hwSnap = await FirebaseFirestore.instance
            .collection('classes').doc(c.classId)
            .collection('homeworks')
            .orderBy('dueAt', descending: false)
            .limit(50).get();
        // Yayın zamanı gelmemiş (zamanlanmış) ödevler öğrencide gizli kalır.
        final hws = hwSnap.docs
            .map(HomeworkModel.fromDoc)
            .where((hw) => hw.isPublished)
            .toList();
        byClass[c.classId] = hws;
        await Future.wait(hws.map((hw) async {
          final subSnap = await FirebaseFirestore.instance
              .collection('classes').doc(c.classId)
              .collection('homeworks').doc(hw.id)
              .collection('submissions').doc(myUid).get();
          if (subSnap.exists) {
            subs[hw.id] = HomeworkSubmissionModel.fromMap(subSnap.data()!);
          }
        }));
      }));
      _byClass = byClass;
      _mySubmissions = subs;
    } catch (_) {
      _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final allHws = <(JoinedClass, HomeworkModel)>[];
    for (final c in _classes) {
      for (final hw in (_byClass[c.classId] ?? const <HomeworkModel>[])) {
        allHws.add((c, hw));
      }
    }
    // Bitiş tarihine göre sırala — en yakın bitenler önce
    allHws.sort((a, b) => a.$2.dueAt.compareTo(b.$2.dueAt));

    // ── Çip verileri (eldeki ödevlerden otomatik türetilir) ────────────────
    final chipSubjects = allHws
        .map((e) => e.$2.subject.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final chipClasses = _classes
        .where((c) => (_byClass[c.classId] ?? const []).isNotEmpty)
        .toList();

    // ── Filtre + arama (VE mantığı) ────────────────────────────────────────
    final q = _search.trim().toLowerCase();
    bool matches((JoinedClass, HomeworkModel) e) {
      if (_filterSubject != null &&
          e.$2.subject.trim() != _filterSubject) {
        return false;
      }
      if (_filterClassId != null && e.$1.classId != _filterClassId) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = '${e.$2.title} ${e.$2.topic} ${e.$2.subject} '
                '${e.$1.className} ${e.$1.teacherDisplayName}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }

    final filtered = allHws.where(matches).toList();
    // Gruplar: Yapılacaklar (bitişe göre artan) / Teslim edilenler (yeni→eski)
    // / Geçmiş arşivi (teslim edilmiş + bitişi 3 haftadan eski).
    final now = DateTime.now();
    final todo = filtered
        .where((e) => !(_mySubmissions[e.$2.id]?.isSubmitted ?? false))
        .toList();
    final doneAll = filtered
        .where((e) => _mySubmissions[e.$2.id]?.isSubmitted ?? false)
        .toList()
      ..sort((a, b) => b.$2.dueAt.compareTo(a.$2.dueAt));
    final archiveCut = now.subtract(_kArchiveAfter);
    final archived =
        doneAll.where((e) => e.$2.dueAt.isBefore(archiveCut)).toList();
    final done =
        doneAll.where((e) => !e.$2.dueAt.isBefore(archiveCut)).toList();
    final searching = q.isNotEmpty;

    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Sınıf Ödevlerim'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
        actions: [
          // Arka plan seçici — çalışma odası fotoğrafları.
          IconButton(
            icon: Icon(Icons.wallpaper_rounded, color: ink),
            tooltip: 'Arka Plan Seç'.tr(),
            onPressed: _pickBackground,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: ink),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Seçili çalışma odası — hafif FLU + tema uyumlu okunabilirlik
            // perdesi (yazılar/kartlar fotoğrafın üstünde net kalır).
            if (_bgIndex != null) ...[
              Positioned.fill(
                child: ImageFiltered(
                  // Çok flu bulundu → hafifletildi (2.5 → 1.0); oda net
                  // seçilebiliyor, yazılar yine okunaklı.
                  imageFilter: ImageFilter.blur(sigmaX: 1.0, sigmaY: 1.0),
                  child: Image.asset(
                    'assets/library_icons/hw_bg_$_bgIndex.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned.fill(
                child: ColoredBox(
                  color: AppPalette.bg(context).withValues(alpha: 0.28),
                ),
              ),
            ],
            _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Onay bekleyen sınıflar — ödevler öğretmen onayına kadar gizli.
                  for (final c in _pendingClasses)
                    _buildPendingBanner(context, c),
                  // Arama kutusu — yalnızca liste kalabalıklaşınca görünür.
                  if (allHws.length > _kSearchThreshold)
                    _buildSearchBar(context),
                  // Ders + sınıf filtre çipleri (birden çok seçenek varsa).
                  if (allHws.isNotEmpty &&
                      (chipSubjects.length > 1 || chipClasses.length > 1))
                    _buildFilterChips(context, chipSubjects, chipClasses),
                  Expanded(child: RefreshIndicator(
                onRefresh: _load,
                child: allHws.isEmpty || filtered.isEmpty
                    // Boş/hata/sonuçsuz durumda da aşağı çekilebilsin diye
                    // kaydırılabilir sarmalayıcı.
                    ? LayoutBuilder(
                        builder: (ctx, cons) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: cons.maxHeight,
                            child: _error
                                ? _buildError(context)
                                : allHws.isEmpty
                                    ? _buildEmpty(context)
                                    : _buildNoResults(context),
                          ),
                        ),
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          if (searching)
                            // Arama aktif → düz sonuç listesi (grup/arşiv yok;
                            // sonuç arşiv içinde "gizli kalmasın").
                            for (final e in filtered)
                              _hwCardFor(context, e, allHws, ink, muted)
                          else ...[
                            if (todo.isNotEmpty) ...[
                              _sectionHeader(context, '📌', 'Yapılacaklar'.tr(),
                                  todo.length, const Color(0xFFF59E0B)),
                              for (final e in todo)
                                _hwCardFor(context, e, allHws, ink, muted),
                            ],
                            if (done.isNotEmpty) ...[
                              _sectionHeader(context, '✅',
                                  'Teslim edilenler'.tr(), done.length,
                                  const Color(0xFF10B981)),
                              for (final e in done)
                                _hwCardFor(context, e, allHws, ink, muted),
                            ],
                            if (archived.isNotEmpty) ...[
                              _archiveHeader(context, archived.length),
                              if (_archiveOpen)
                                for (final e in archived)
                                  _hwCardFor(context, e, allHws, ink, muted),
                            ],
                          ],
                        ],
                      ),
              )),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Kart + sınıf içi sıra numarası (analiz ekranı başlığı için).
  Widget _hwCardFor(
      BuildContext context,
      (JoinedClass, HomeworkModel) e,
      List<(JoinedClass, HomeworkModel)> allHws,
      Color ink,
      Color muted) {
    final (cls, hw) = e;
    final sameClass = allHws
        .where((x) => x.$1.classId == cls.classId)
        .map((x) => x.$2)
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final orderNo = sameClass.indexWhere((h) => h.id == hw.id) + 1;
    return _buildHwCard(
        context, cls, hw, _mySubmissions[hw.id], ink, muted, orderNo);
  }

  /// Grup başlığı: emoji + ad + adet rozeti.
  Widget _sectionHeader(BuildContext context, String emoji, String title,
      int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 7),
          Text(title,
              style: GoogleFonts.poppins(
                fontSize: 13.5, fontWeight: FontWeight.w900,
                color: AppPalette.textPrimary(context),
              )),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count',
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w800, color: color,
                )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(color: AppPalette.border(context), height: 1),
          ),
        ],
      ),
    );
  }

  /// Geçmiş ödevler — katlanabilir arşiv başlığı.
  Widget _archiveHeader(BuildContext context, int count) {
    final muted = AppPalette.textSecondary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _archiveOpen = !_archiveOpen),
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppPalette.card(context).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 17, color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${'Geçmiş ödevler'.tr()} ($count)',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    )),
              ),
              Icon(
                _archiveOpen
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 20, color: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Arama kutusu — başlık/konu/ders/sınıf/öğretmen adında arar.
  Widget _buildSearchBar(BuildContext context) {
    final muted = AppPalette.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _search = v),
          style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(context)),
          decoration: InputDecoration(
            hintText: 'Ödev, konu, ders veya öğretmen ara…'.tr(),
            hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: muted),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: muted),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: muted),
                    onPressed: () => setState(() {
                      _searchCtrl.clear();
                      _search = '';
                    }),
                  ),
            border: InputBorder.none,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          ),
        ),
      ),
    );
  }

  /// Ders + sınıf filtre çipleri — "Tümü" + otomatik türetilen seçenekler.
  Widget _buildFilterChips(BuildContext context, List<String> subjects,
      List<JoinedClass> classes) {
    Widget chip(String label, bool selected, VoidCallback onTap,
        {String? emoji}) {
      const brand = Color(0xFF7C3AED);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? brand.withValues(alpha: 0.14)
                  : AppPalette.card(context),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? brand : AppPalette.border(context),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Text(
              emoji == null ? label : '$emoji $label',
              style: GoogleFonts.poppins(
                fontSize: 11.5, fontWeight: FontWeight.w800,
                color: selected ? brand : AppPalette.textPrimary(context),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        children: [
          chip('Tümü'.tr(), _filterSubject == null && _filterClassId == null,
              () => setState(() {
                    _filterSubject = null;
                    _filterClassId = null;
                  })),
          // Sınıf çipleri — etikette sınıf adı DEĞİL, sınıfın DERSİ yazar
          // (öğrenci zaten tek fiziksel sınıfta; ayrım derse göre anlamlı).
          // Aynı dersten iki sınıf varsa yanına sınıf adı eklenir.
          if (classes.length > 1)
            for (final c in classes)
              chip(_classChipLabel(c, classes),
                  _filterClassId == c.classId,
                  () => setState(() => _filterClassId =
                      _filterClassId == c.classId ? null : c.classId),
                  emoji: '📘'),
          // Ödev konusu bazlı ders çipleri — sınıf çipiyle aynı adı taşıyan
          // ders atlanır (ikiz çip olmasın).
          if (subjects.length > 1)
            for (final s in subjects)
              if (!classes.any((c) => c.subject.trim() == s))
                chip(s, _filterSubject == s,
                    () => setState(() =>
                        _filterSubject = _filterSubject == s ? null : s),
                    emoji: '📚'),
        ],
      ),
    );
  }

  /// Sınıf çipi etiketi: sınıfın dersi; ders boşsa sınıf adı. Aynı dersten
  /// birden çok sınıf varsa "Fizik (10/A)" biçiminde ayrıştırılır.
  String _classChipLabel(JoinedClass c, List<JoinedClass> all) {
    final subj = c.subject.trim();
    if (subj.isEmpty) return c.className;
    final dup = all.where((x) => x.subject.trim() == subj).length > 1;
    return dup ? '$subj (${c.className})' : subj;
  }

  /// Filtre/arama sonuç vermedi — temizleme kısayollu boş durum.
  Widget _buildNoResults(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔎', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text('Sonuç bulunamadı'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 15, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 6),
            Text('Filtreyi veya aramayı değiştirip tekrar dene.'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: AppPalette.textSecondary(context),
                )),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() {
                _filterSubject = null;
                _filterClassId = null;
                _searchCtrl.clear();
                _search = '';
              }),
              child: Text('Filtreleri temizle'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  /// Öğretmen onayı bekleyen sınıf için bilgi şeridi.
  Widget _buildPendingBanner(BuildContext context, JoinedClass c) {
    const amber = Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '"${c.className}" ${'sınıfı için öğretmen onayı bekleniyor. '
                  'Onaylanınca ödevleri burada göreceksin.'.tr()}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHwCard(BuildContext context, JoinedClass cls, HomeworkModel hw,
      HomeworkSubmissionModel? sub, Color ink, Color muted,
      [int orderNo = 1]) {
    // Status badge
    Color statusColor; String statusLabel;
    if (sub?.isSubmitted ?? false) {
      statusColor = const Color(0xFF10B981); statusLabel = 'Teslim edildi'.tr();
    } else if (sub?.status == 'in_progress') {
      statusColor = const Color(0xFF06B6D4); statusLabel = 'Devam ediyor'.tr();
    } else if (hw.isOverdue) {
      statusColor = const Color(0xFFEF4444); statusLabel = 'Süresi geçti'.tr();
    } else {
      statusColor = const Color(0xFFFBBF24); statusLabel = 'Bekliyor'.tr();
    }
    final remaining = hw.timeRemaining;
    // Sayı .tr() DIŞINDA — interpolasyonlu anahtar sözlükte hiç eşleşmez,
    // metin tüm dillerde Türkçe kalıyordu.
    final remainingStr = remaining.isNegative
        ? 'Süre doldu'.tr()
        : remaining.inDays > 0
            ? '${remaining.inDays} ${'gün kaldı'.tr()}'
            : remaining.inHours > 0
                ? '${remaining.inHours} ${'saat kaldı'.tr()}'
                : '${remaining.inMinutes} ${'dakika kaldı'.tr()}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          // TESLİM EDİLMİŞ ödev:
          //  • Öğretmen cevap anahtarını PAYLAŞMADIYSA → yalnız "Ödev Teslim
          //    Edildi" onay sayfası (skor/grafik/soru-cevap GÖRÜNMEZ —
          //    değerlendirme açıklanana dek öğrenciye kapalı).
          //  • Paylaştıysa → öğretmenin gördüğü analiz ekranının aynısı
          //    (grafik/tablo, künye, süre, AI analizi). readOnly: sınıf
          //    ortalaması sorgusu ve öğretmen aksiyonları atlanır.
          if (sub?.isSubmitted ?? false) {
            final answersOpen =
                hw.answersShared || (sub?.answersShared ?? false);
            if (!answersOpen) {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => HomeworkSolveScreen(
                  classId: cls.classId, homework: hw, submission: sub,
                ),
              ));
              _load();
              return;
            }
            final me = UserProfileService.instance;
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TeacherHomeworkDetailScreen(
                homework: hw,
                submission: sub,
                studentName: me.displayNameOrUsername,
                studentAvatar: me.avatar,
                studentAvatarData: me.avatarData,
                orderNo: orderNo,
                readOnly: true,
              ),
            ));
            _load();
            return;
          }
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HomeworkSolveScreen(
              classId: cls.classId, homework: hw, submission: sub,
            ),
          ));
          _load(); // dönünce yenile
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (sub?.isSubmitted ?? false)
                  ? const Color(0xFF10B981).withValues(alpha: 0.30)
                  : AppPalette.border(context),
              width: (sub?.isSubmitted ?? false) ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(statusLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w800,
                          color: statusColor,
                        )),
                  ),
                  const Spacer(),
                  Text(remainingStr,
                      style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        // Son 24 saat ve teslim edilmedi → acil vurgusu.
                        color: hw.isOverdue
                            ? const Color(0xFFEF4444)
                            : (!(sub?.isSubmitted ?? false) &&
                                    !remaining.isNegative &&
                                    remaining.inHours < 24)
                                ? const Color(0xFFF97316)
                                : muted,
                      )),
                ],
              ),
              const SizedBox(height: 8),
              Text(hw.title,
                  style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w800, color: ink,
                  ),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${cls.className} · ${hw.subject} · ${hw.topic}',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5, color: muted,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.help_outline_rounded, size: 14, color: muted),
                  const SizedBox(width: 4),
                  Text('${hw.questionCount} ${'soru'.tr()}',
                      style: GoogleFonts.poppins(
                        fontSize: 11, color: muted,
                      )),
                  const SizedBox(width: 12),
                  // Skor, öğretmen cevap anahtarını paylaşana kadar GİZLİ —
                  // değerlendirme açıklanmadan öğrenci yüzde görmesin.
                  if (sub?.scorePercent != null &&
                      (hw.answersShared ||
                          (sub?.answersShared ?? false))) ...[
                    Icon(Icons.star_rounded, size: 14,
                        color: const Color(0xFFFBBF24)),
                    const SizedBox(width: 4),
                    Text('%${sub!.scorePercent!.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309),
                        )),
                  ],
                  // Öğretmen cevap anahtarını paylaştıysa — sınıf geneli
                  // ya da yalnız bu öğrenciye — (ve teslim edilmişse)
                  // karta rozet; dokununca çözümler görülür.
                  if ((hw.answersShared || (sub?.answersShared ?? false)) &&
                      (sub?.isSubmitted ?? false)) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.key_rounded,
                        size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 3),
                    Text('Cevaplar paylaşıldı'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 10.5, fontWeight: FontWeight.w800,
                          color: const Color(0xFFB45309),
                        )),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Yükleme hatası — "ödev yok" ile karışmasın; tekrar dene butonlu.
  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📡', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Ödevler yüklenemedi'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 6),
            Text(
              'İnternet bağlantını kontrol edip tekrar dene.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED)),
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('Tekrar Dene'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Henüz ödev yok'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimary(context),
                )),
            const SizedBox(height: 6),
            Text(
              'Sınıfa katıldığın öğretmenler ödev gönderince burada görünür.'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppPalette.textSecondary(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
