import 'dart:convert';
import 'dart:io';
import '../services/error_logger.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../services/solutions_storage.dart';
import '../services/pdf_service.dart';
import '../services/runtime_translator.dart';
import '../widgets/adaptive_photo.dart';
import '../main.dart' show localeService;
import 'ai_result_screen.dart';
import 'solution_screen.dart';

import '../theme/app_theme.dart';
// ═══════════════════════════════════════════════════════════════════════════════
//  HistoryScreen — Çözümler (Modern Soft Design)
// ═══════════════════════════════════════════════════════════════════════════════

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedFilter  = 'Tümü';
  List<SolutionRecord> _records = [];
  bool _showFavoritesOnly = false;
  bool _isLoading         = false;
  String _loadingMessage  = '';
  bool _isSelecting       = false;
  final Set<String> _selectedIds = {};

  // Arama state — TextField içindeki canlı sorgu. Boş ise filtre yok.
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showSearch = false;

  // PDF üretimi sırasında set edilir — kullanıcı "İptal"e basarsa
  // tamamlanan PDF'i discard et (paylaş ekranı açma). Future iptal
  // edilemez ama UI serbest kalır.
  bool _pdfCancelled = false;

  // "Tümü" sekmesinde ders gruplarından hangisi "yanık" — yani başlığa
  // basılarak vurgulanmış. Aynı anda en fazla bir tane yanık olabilir.
  String? _litSubject;

  // ── Renk özelleştirme — diğer sayfalardakiyle aynı format ─────────────
  bool _showColorPicker = false;
  String _colorMode = 'frame'; // 'frame' | 'text'
  String _colorTarget = 'bg'; // 'bg' | 'cards'
  Color? _pageBgOverride;
  Color? _cardsBgOverride;
  Color? _cardsTextOverride;

  static const _historyColorsKey = 'history_colors_v1';
  static const _historyPalette = <Color>[
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF0F172A),
    Color(0xFFFFEFD5),
    Color(0xFFFFD1DC),
    Color(0xFFFCA5A5),
    Color(0xFFFF6A00),
    Color(0xFFC8102E),
    Color(0xFFDB2777),
    Color(0xFFFBBF24),
    Color(0xFFDCFCE7),
    Color(0xFF86EFAC),
    Color(0xFF10B981),
    Color(0xFFE0F2FE),
    Color(0xFF22D3EE),
    Color(0xFF2563EB),
    Color(0xFFE9D5FF),
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFFF5F5DC),
    Color(0xFFD4A373),
    Color(0xFF92400E),
  ];

  static const _allSubjects = [
    'Matematik', 'Fizik', 'Kimya', 'Biyoloji',
    'Coğrafya', 'Tarih', 'Edebiyat', 'Felsefe', 'İngilizce', 'Diğer',
  ];

  static const _subjectKeys = {
    'Matematik': 'subj_math', 'Fizik': 'subj_physics', 'Kimya': 'subj_chemistry',
    'Biyoloji': 'subj_biology', 'Coğrafya': 'subj_geography', 'Tarih': 'subj_history',
    'Edebiyat': 'subj_literature', 'Felsefe': 'subj_philosophy', 'İngilizce': 'subj_english',
    'Diğer': 'subj_other',
  };
  String _trSubject(String name) => localeService.tr(_subjectKeys[name] ?? name);

  @override
  void initState() {
    super.initState();
    _load();
    _loadHistoryColors();
    _searchCtrl.addListener(() {
      if (!mounted) return;
      final q = _searchCtrl.text.trim();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final records = await SolutionsStorage.loadAll();
    if (mounted) setState(() => _records = records);
  }

  Future<void> _loadHistoryColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyColorsKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        Color? read(String k) {
          final v = m[k];
          return v is num ? Color(v.toInt()) : null;
        }
        _pageBgOverride = read('bg');
        _cardsBgOverride = read('cards');
        _cardsTextOverride = read('cardsText');
      });
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'history_screen'); }
  }

  Future<void> _saveHistoryColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = <String, int>{};
      void put(String k, Color? c) {
        if (c != null) m[k] = c.toARGB32();
      }
      put('bg', _pageBgOverride);
      put('cards', _cardsBgOverride);
      put('cardsText', _cardsTextOverride);
      if (m.isEmpty) {
        await prefs.remove(_historyColorsKey);
      } else {
        await prefs.setString(_historyColorsKey, jsonEncode(m));
      }
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'history_screen'); }
  }

  void _applyHistoryColor(String target, Color c) {
    setState(() {
      if (_colorMode == 'text') {
        _cardsTextOverride = c;
      } else {
        if (target == 'bg') {
          _pageBgOverride = c;
        } else {
          _cardsBgOverride = c;
        }
      }
    });
    _saveHistoryColors();
  }

  void _resetHistoryColors() {
    setState(() {
      _pageBgOverride = null;
      _cardsBgOverride = null;
      _cardsTextOverride = null;
    });
    _saveHistoryColors();
  }

  List<String> get _orderedSubjects {
    final counts = <String, int>{};
    for (final r in _records) {
      counts[r.subject] = (counts[r.subject] ?? 0) + 1;
    }
    final subjects = List<String>.from(_allSubjects);
    subjects.sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
    return subjects;
  }

  List<SolutionRecord> get _filtered {
    var list = _showFavoritesOnly
        ? _records.where((r) => r.isFavorite).toList()
        : _records;
    if (_selectedFilter != 'Tümü') {
      list = list.where((r) => r.subject == _selectedFilter).toList();
    }
    // Arama filtresi — AI title / subject / solutionType / result / cachedQuestion
    // alanlarında case-insensitive substring.
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((r) {
        if (r.aiTitle.toLowerCase().contains(q)) return true;
        if (r.subject.toLowerCase().contains(q)) return true;
        if (r.solutionType.toLowerCase().contains(q)) return true;
        if (r.cachedQuestionText.toLowerCase().contains(q)) return true;
        // Result uzun olabilir; içinde tarama büyük metinlerde maliyetli ama
        // 100-200 kayıt boyutunda makul.
        if (r.result.toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    }
    return list;
  }

  Future<void> _delete(String id) async {
    // Önce yerel state'i güncelle — kullanıcı anında geri bildirim alır.
    if (mounted) setState(() => _records.removeWhere((r) => r.id == id));
    await SolutionsStorage.delete(id);
  }

  void _enterSelectMode() {
    setState(() { _isSelecting = true; _selectedIds.clear(); });
  }

  void _exitSelectMode() {
    setState(() { _isSelecting = false; _selectedIds.clear(); });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    // Optimistic UI: önce yerelden çıkar, sonra tek pass'te disk'e yaz.
    if (mounted) {
      setState(() {
        _records.removeWhere((r) => ids.contains(r.id));
        _isSelecting = false;
        _selectedIds.clear();
      });
    }
    // deleteMany: 50 kayıt için 50 file write yerine 1 file write.
    await SolutionsStorage.deleteMany(ids);
  }

  // Çoklu seçim banner'ından — filtrelenmiş listenin tüm id'lerini ekle.
  void _selectAllVisible() {
    final ids = _filtered.map((r) => r.id).toSet();
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(ids);
    });
  }

  // Görünür listede seçimi tersine çevir.
  void _invertSelection() {
    final visible = _filtered.map((r) => r.id).toSet();
    setState(() {
      final newSel = <String>{};
      for (final id in visible) {
        if (!_selectedIds.contains(id)) newSel.add(id);
      }
      _selectedIds
        ..clear()
        ..addAll(newSel);
    });
  }

  Future<void> _toggleFavorite(SolutionRecord rec) async {
    // Optimistic update: yerel state'de tek kaydı flip + disk'e yaz.
    // Önceki davranış (await + _load()) tüm dosyayı tekrar okuyordu.
    final idx = _records.indexWhere((r) => r.id == rec.id);
    if (idx >= 0 && mounted) {
      setState(() {
        _records[idx] = _records[idx].copyWith(
          isFavorite: !_records[idx].isFavorite,
        );
      });
    }
    await SolutionsStorage.toggleFavorite(rec.id);
  }

  void _startLoading(String msg) {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadingMessage = msg;
      _pdfCancelled = false;
    });
  }

  void _stopLoading() {
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _exportPdf(SolutionRecord rec) async {
    _startLoading(localeService.tr('creating_pdf'));
    try {
      await PdfService.generateAndShare(rec);
      // Kullanıcı iptal ettiyse paylaş ekranı yine açıldı ama loader'ı
      // kapat — bug değil, sadece bildirim.
    } catch (_) {
      if (!_pdfCancelled) {
        _showError(localeService.tr('pdf_error'));
      }
    } finally {
      _stopLoading();
    }
  }

  void _showOptions(BuildContext context, SolutionRecord rec) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              _optionTile(
                ctx: ctx,
                icon: rec.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                iconColor: Color(0xFFF59E0B),
                label: rec.isFavorite ? localeService.tr('remove_favorite') : localeService.tr('add_favorite'),
                subtitle: null,
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleFavorite(rec);
                },
              ),

              _divider(),

              _optionTile(
                ctx: ctx,
                icon: Icons.share_rounded,
                iconColor: Color(0xFF3B82F6),
                label: localeService.tr('share'),
                subtitle: null,
                onTap: () {
                  Navigator.pop(ctx);
                  _shareRecord(rec);
                },
              ),

              _divider(),

              _optionTile(
                ctx: ctx,
                icon: Icons.picture_as_pdf_rounded,
                iconColor: Color(0xFFEC4899),
                label: localeService.tr('get_pdf'),
                subtitle: null,
                onTap: () {
                  Navigator.pop(ctx);
                  _exportPdf(rec);
                },
              ),

              _divider(),

              // Resolve sadece resim dosyası mevcutsa gösterilir — yoksa
              // SolutionScreen boş açılır, bu da UX bug'ı.
              if (rec.imagePath.isNotEmpty &&
                  File(rec.imagePath).existsSync()) ...[
                _optionTile(
                  ctx: ctx,
                  icon: Icons.replay_rounded,
                  iconColor: Color(0xFF10B981),
                  label: localeService.tr('resolve'),
                  subtitle: null,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SolutionScreen(imagePath: rec.imagePath),
                      ),
                    );
                  },
                ),
                _divider(),
              ],

              _optionTile(
                ctx: ctx,
                icon: Icons.delete_rounded,
                iconColor: Color(0xFFEF4444),
                label: localeService.tr('delete'),
                subtitle: null,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, rec.id);
                },
              ),

              _divider(),

              _optionTile(
                ctx: ctx,
                icon: Icons.checklist_rounded,
                iconColor: Color(0xFF8B5CF6),
                label: localeService.tr('bulk_delete'),
                subtitle: null,
                onTap: () {
                  Navigator.pop(ctx);
                  _enterSelectMode();
                },
              ),

              SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionTile({
    required BuildContext ctx,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(label, style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 10))
          : null,
      onTap: onTap,
    );
  }

  Widget _divider() => Divider(
    color: Color(0xFFF0F0F0),
    height: 1,
    indent: 16,
    endIndent: 16,
  );

  Future<void> _shareRecord(SolutionRecord rec) async {
    final imgFile = File(rec.imagePath);
    // Paylaşılan metin: önce konu (varsa), sonra mod, sonra OCR ile çıkarılan
    // soru metni (varsa), sonra cevap. Daha anlamlı paylaşım.
    final buf = StringBuffer();
    buf.writeln('${rec.subject} — ${rec.solutionType}');
    if (rec.cachedQuestionText.isNotEmpty) {
      buf.writeln();
      buf.writeln('Soru:');
      buf.writeln(rec.cachedQuestionText);
    }
    buf.writeln();
    buf.writeln(rec.result);
    final text = buf.toString();
    try {
      if (imgFile.existsSync()) {
        await Share.shareXFiles([XFile(rec.imagePath)], text: text);
      } else {
        await Share.share(text);
      }
    } catch (_) {
      try {
        await Share.share(text);
      } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'history_screen'); }
    }
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(localeService.tr('delete'), style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 16)),
        content: Text(
          localeService.tr('confirm_delete_solution'),
          style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(localeService.tr('cancel'), style: TextStyle(color: AppPalette.textSecondary(context))),
          ),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _delete(id); },
            child: Text(localeService.tr('delete'), style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  // ── Yardım / Nasıl Kullanılır? sayfası ─────────────────────────────────
  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: AppPalette.bg(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag tutamacı
              Container(
                width: 44, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: AppPalette.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: AppPalette.textPrimary(context), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        localeService.tr('help_title'),
                        style: TextStyle(
                          color: AppPalette.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: Text(
                  localeService.tr('help_subtitle'),
                  style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 12, height: 1.45),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  children: [
                    _HelpTile(
                      icon: Icons.auto_awesome_rounded,
                      color: Color(0xFF3B82F6),
                      title: localeService.tr('help_auto_category_title'),
                      body: localeService.tr('help_auto_category_body'),
                    ),
                    _HelpTile(
                      icon: Icons.filter_list_rounded,
                      color: Color(0xFF8B5CF6),
                      title: localeService.tr('help_subject_filters_title'),
                      body: localeService.tr('help_subject_filters_body'),
                    ),
                    _HelpTile(
                      icon: Icons.image_rounded,
                      color: Color(0xFF10B981),
                      title: localeService.tr('help_full_photo_title'),
                      body: localeService.tr('help_full_photo_body'),
                    ),
                    _HelpTile(
                      icon: Icons.star_rounded,
                      color: Color(0xFFF59E0B),
                      title: localeService.tr('help_favorites_title'),
                      body: localeService.tr('help_favorites_body'),
                    ),
                    _HelpTile(
                      icon: Icons.touch_app_rounded,
                      color: Color(0xFFEC4899),
                      title: localeService.tr('help_long_press_title'),
                      body: localeService.tr('help_long_press_body'),
                    ),
                    _HelpTile(
                      icon: Icons.replay_rounded,
                      color: Color(0xFF06B6D4),
                      title: localeService.tr('help_resolve_title'),
                      body: localeService.tr('help_resolve_body'),
                    ),
                    _HelpTile(
                      icon: Icons.lock_outline_rounded,
                      color: Color(0xFF64748B),
                      title: localeService.tr('help_privacy_title'),
                      body: localeService.tr('help_privacy_body'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(color: AppPalette.textPrimary(context))),
        backgroundColor: AppPalette.card(context),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _orderedSubjects;

    return Scaffold(
      backgroundColor: _pageBgOverride ?? AppPalette.bg(context),
      body: SafeArea(
        // SelectionArea kaldırıldı — liste sayfasında metin seçimi UX
        // beklentisine ters (uzun-bas = çoklu seçim modu olmalı).
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_showSearch) _buildSearchBar(),
                // ── Başlık + Renk Seç pill (sağda) ─────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: Icon(Icons.arrow_back_rounded, color: AppPalette.textPrimary(context)),
                          onPressed: () {
                            if (_showFavoritesOnly) {
                              setState(() => _showFavoritesOnly = false);
                            } else {
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ),
                      Text(
                        _showFavoritesOnly ? localeService.tr('my_favorites') : localeService.tr('solutions'),
                        style: GoogleFonts.inter(
                          color: AppPalette.textPrimary(context),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      // Sağ üstte renkli "Renk Seç" pill — diğer sayfalardakiyle aynı.
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _showColorPicker = !_showColorPicker),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFF6A00),
                                  Color(0xFFDB2777),
                                  Color(0xFF7C3AED),
                                  Color(0xFF2563EB),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showColorPicker
                                      ? Icons.close_rounded
                                      : Icons.palette_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  _showColorPicker
                                      ? localeService.tr('close')
                                      : 'Renk Seç',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showColorPicker) _buildHistoryColorPanel(),

                SizedBox(height: 2),

                // ── Tümü pill (ortalı)  +  sağda (?) yardım + ⭐ favori ─────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: SizedBox(
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Tümü pill — ortada
                        if (!_showFavoritesOnly)
                          GestureDetector(
                            onTap: () => setState(() => _selectedFilter = 'Tümü'),
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 200),
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 26),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
            color: AppPalette.card(context),
                                borderRadius: BorderRadius.circular(50),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                '${localeService.tr('all_filter')}  •  ${_records.length}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.textPrimary(context),
                                ),
                              ),
                            ),
                          ),

                        // Sağ üst aksiyon ikonları — beyaz daire yok, sadece ikon
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Search toggle
                              GestureDetector(
                                onTap: () => setState(() {
                                  _showSearch = !_showSearch;
                                  if (!_showSearch) {
                                    _searchCtrl.clear();
                                    _searchQuery = '';
                                  }
                                }),
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox(
                                  width: 40, height: 44,
                                  child: Icon(
                                    _showSearch
                                        ? Icons.search_off_rounded
                                        : Icons.search_rounded,
                                    color: AppPalette.textPrimary(context),
                                    size: 24,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _showHelpSheet,
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox(
                                  width: 40, height: 44,
                                  child: Icon(
                                    Icons.help_outline_rounded,
                                    color: AppPalette.textPrimary(context),
                                    size: 26,
                                  ),
                                ),
                              ),
                              SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => setState(() {
                                  _showFavoritesOnly = !_showFavoritesOnly;
                                  if (_showFavoritesOnly) _selectedFilter = 'Tümü';
                                }),
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox(
                                  width: 40, height: 44,
                                  child: Icon(
                                    _showFavoritesOnly ? Icons.star_rounded : Icons.star_border_rounded,
                                    color: Colors.yellow,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (!_showFavoritesOnly) SizedBox(height: 6),

                // ── Ders filtreleri (Oval Beyaz Yapı) ─────────────────────────────────────────
                if (!_showFavoritesOnly)
                  SizedBox(
                    height: 50,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: subjects.length,
                      separatorBuilder: (_, __) => SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final f   = subjects[i];
                        final sel = _selectedFilter == f;
                        final cnt = _records.where((r) => r.subject == f).length;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedFilter = f),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
            color: AppPalette.card(context),
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: sel ? 0.10 : 0.06),
                                  blurRadius: sel ? 12 : 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_emojiFor(f), style: TextStyle(fontSize: 16)),
                                SizedBox(width: 8),
                                Text(
                                  cnt > 0 ? '${_trSubject(f)}  $cnt' : _trSubject(f),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.black : Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                if (!_showFavoritesOnly) SizedBox(height: 6),
                if (_showFavoritesOnly) SizedBox(height: 6),

                // ── Toplu seçim banner ──────────────────────────────────────
                if (_isSelecting)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Color(0xFFEF4444).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.checklist_rounded, color: Color(0xFFEF4444), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedIds.isEmpty
                                  ? localeService.tr('select_to_delete')
                                  : '${_selectedIds.length} ${localeService.tr('selected')}',
                              style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          // "Tümünü Seç" / "Ters Çevir" — görünür liste üzerinde.
                          GestureDetector(
                            onTap: _selectAllVisible,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppPalette.cardMuted(context),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Tümü'.tr(),
                                style: TextStyle(
                                  color: AppPalette.textPrimary(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 6),
                          GestureDetector(
                            onTap: _invertSelection,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppPalette.cardMuted(context),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Ters'.tr(),
                                style: TextStyle(
                                  color: AppPalette.textPrimary(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 6),
                          if (_selectedIds.isNotEmpty)
                            GestureDetector(
                              onTap: () => showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppPalette.card(context),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: Text(localeService.tr('bulk_delete'), style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 16)),
                                  content: Text(
                                    '${_selectedIds.length} ${localeService.tr('confirm_bulk_delete')}',
                                    style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 13),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localeService.tr('cancel'), style: TextStyle(color: AppPalette.textSecondary(context)))),
                                    TextButton(onPressed: () { Navigator.pop(ctx); _deleteSelected(); }, child: Text(localeService.tr('delete'), style: TextStyle(color: Color(0xFFEF4444)))),
                                  ],
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Color(0xFFEF4444).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(localeService.tr('delete'), style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          SizedBox(width: 8),
                          GestureDetector(
                            onTap: _exitSelectMode,
                            child: Icon(Icons.close_rounded, color: AppPalette.textSecondary(context), size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Liste ───────────────────────────────────────────────────
                Expanded(
                  child: _filtered.isEmpty
                      ? _emptyState()
                      : _buildGroupedList(),
                ),
              ],
            ),

            // ── Yükleme overlay ───────────────────────────────────────────
            if (_isLoading)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Stack(
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 24),
                            decoration: BoxDecoration(
                              color: AppPalette.card(context),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                    color: Color(0xFF3B82F6),
                                    strokeWidth: 2.5),
                                SizedBox(height: 16),
                                Text(
                                  _loadingMessage,
                                  style: TextStyle(
                                    color: AppPalette.textPrimary(context),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (_pdfCancelled) ...[
                                  SizedBox(height: 6),
                                  Text(
                                    'İptal ediliyor…'.tr(),
                                    style: TextStyle(
                                      color: AppPalette.textSecondary(context),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        // İptal pill — sağ üst (test page / academic planner
                        // ile tutarlı). PDF Future iptal edilemez ama UI
                        // serbest kalır; tamamlanan PDF discard işareti
                        // _pdfCancelled true olur.
                        SafeArea(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: GestureDetector(
                                onTap: _pdfCancelled
                                    ? null
                                    : () {
                                        setState(() {
                                          _pdfCancelled = true;
                                          _isLoading = false;
                                        });
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _pdfCancelled
                                        ? Color(0x33808080)
                                        : Colors.black,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.close_rounded,
                                          size: 14, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text(
                                        'İptal'.tr(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Arama satırı — başlığın hemen altında. Boş olunca filtre yok.
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded,
                size: 18, color: AppPalette.textSecondary(context)),
            SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(
                  fontSize: 13,
                  color: AppPalette.textPrimary(context),
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: 'Konu, ders veya kelime ara…'.tr(),
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
                textInputAction: TextInputAction.search,
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
                child: Icon(Icons.close_rounded,
                    size: 18, color: AppPalette.textSecondary(context)),
              ),
          ],
        ),
      ),
    );
  }

  // ── Kategoriye göre gruplanmış liste ────────────────────────────────────
  Widget _buildGroupedList() {
    // Filtre spesifik bir ders seçmişse düz liste göster.
    if (_selectedFilter != 'Tümü' || _showFavoritesOnly) {
      return ListView.separated(
        physics: BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => SizedBox(height: 12),
        itemBuilder: (_, i) => _cardFor(_filtered[i]),
      );
    }

    // "Tümü" seçiliyse: AI kategorilerine göre ExpansionTile'larla grupla.
    final Map<String, List<SolutionRecord>> groups = {};
    for (final r in _filtered) {
      groups.putIfAbsent(r.subject, () => []).add(r);
    }
    // En çok kayda sahip ders en üstte.
    final keys = groups.keys.toList()
      ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));

    return ListView(
      physics: BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        for (final subject in keys)
          _SubjectGroup(
            subject: _trSubject(subject),
            rawSubject: subject,
            emoji: _emojiFor(subject),
            records: groups[subject]!,
            cardBuilder: _cardFor,
            isLit: _litSubject == subject,
            onHeaderTap: () => setState(() {
              // Aynı sekmeye tekrar basıldığında yanık halini kaldır
              // (toggle); başkasına basılırsa onu yak, eskisini söndür.
              _litSubject = (_litSubject == subject) ? null : subject;
            }),
          ),
      ],
    );
  }

  Widget _cardFor(SolutionRecord rec) {
    final isSelected = _selectedIds.contains(rec.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _HistoryCard(
        record: rec,
        isSelecting: _isSelecting,
        isSelected: isSelected,
        customBg: _cardsBgOverride,
        customTextColor: _cardsTextOverride,
        onColorAccept: (c) => _applyHistoryColor('cards', c),
        onTap: _isSelecting
            ? () => _toggleSelection(rec.id)
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AiResultScreen(
                      result:            rec.result,
                      imagePath:         rec.imagePath,
                      solutionType:      rec.solutionType,
                      modelName:         '',
                      existingRecordId:  rec.id,
                      existingTimestamp: rec.timestamp,
                    ),
                  ),
                ).then((_) => _load()),
        onLongPress: _isSelecting
            ? () => _toggleSelection(rec.id)
            : () => _showOptions(context, rec),
      ),
    );
  }

  Widget _emptyState() {
    final isFiltered   = _selectedFilter != 'Tümü';
    final isFavorites  = _showFavoritesOnly;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFavorites ? Icons.star_border_rounded : Icons.inbox_rounded,
            size: 52,
            color: AppPalette.textSecondary(context).withValues(alpha: 0.50),
          ),
          SizedBox(height: 14),
          Text(
            isFavorites
                ? localeService.tr('empty_favorites')
                : isFiltered
                    ? localeService.tr('empty_category')
                    : localeService.tr('empty_solutions'),
            style: TextStyle(color: AppPalette.textSecondary(context), fontSize: 14),
          ),
          if (isFavorites) ...[
            SizedBox(height: 6),
            Text(
              localeService.tr('empty_favorites_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppPalette.textSecondary(context),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ] else if (!isFiltered) ...[
            SizedBox(height: 6),
            Text(
              localeService.tr('empty_solutions_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppPalette.textSecondary(context),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _emojiFor(String subject) {
    return switch (subject) {
      'Matematik' => '🧮',
      'Fizik'     => '⚛️',
      'Kimya'     => '🧪',
      'Biyoloji'  => '🧬',
      'Coğrafya'  => '🌍',
      'Tarih'     => '📜',
      'Edebiyat'  => '📚',
      'Felsefe'   => '🤔',
      'İngilizce' => '🇬🇧',
      _           => '📖',
    };
  }

  // ══════ Renk seçim paneli — diğer sayfalar ile aynı format ═══════════════
  Widget _buildHistoryColorPanel() {
    const orange = Color(0xFFFF6A00);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.textPrimary(context), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded, size: 16, color: Colors.black),
              SizedBox(width: 6),
              Text('Renk'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
              SizedBox(width: 10),
              Expanded(child: _historyModeToggle(orange)),
              SizedBox(width: 8),
              GestureDetector(
                onTap: _resetHistoryColors,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.cardMuted(context),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text('Sıfırla'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54)),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _historyTargetToggle(orange),
          SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin yere bırak.',
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
                height: 1.3),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _historyPalette.length,
              itemBuilder: (_, i) =>
                  _historyDraggableColor(_historyPalette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyModeToggle(Color orange) {
    Widget box(String id, IconData? icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? orange.withValues(alpha: 0.12)
                  : Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? orange : Colors.black,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 13, color: active ? orange : Colors.black),
                  SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? orange : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', null, 'Yazı'),
        SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'),
      ],
    );
  }

  Widget _historyTargetToggle(Color orange) {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? orange.withValues(alpha: 0.12)
                  : Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? orange : Colors.black),
            ),
          ),
        ),
      );
    }

    // Yazı modunda 'bg' (arka plan) chip'i anlamsız — yazıya etki etmez.
    // Sadece kart yazısını boyamak için 'cards' chip görünür kalır.
    final isTextMode = _colorMode == 'text';
    if (isTextMode) {
      // Text mode → cards otomatik seç (UI tek hedef gösterir).
      if (_colorTarget != 'cards') {
        // postFrame'de yap; build sırasında setState yasak.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _colorTarget != 'cards') {
            setState(() => _colorTarget = 'cards');
          }
        });
      }
      return Row(
        children: [
          chip('cards', 'Kart yazısı'),
        ],
      );
    }
    return Row(
      children: [
        chip('bg', 'Arka plan'),
        SizedBox(width: 6),
        chip('cards', 'Kartlar'),
      ],
    );
  }

  Widget _historyDraggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _historyDot(c)),
      child: GestureDetector(
        onTap: () => _applyHistoryColor(_colorTarget, c),
        child: _historyDot(c),
      ),
    );
  }

  Widget _historyDot(Color c) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border(context), width: 1),
      ),
    );
  }
}

// ─── Soru kartı (Modern Soft Design) ───────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final SolutionRecord record;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelecting;
  final bool isSelected;
  final Color? customBg;
  final Color? customTextColor;
  final ValueChanged<Color>? onColorAccept;

  const _HistoryCard({
    required this.record,
    required this.onTap,
    required this.onLongPress,
    this.isSelecting = false,
    this.isSelected  = false,
    this.customBg,
    this.customTextColor,
    this.onColorAccept,
  });

  static ({IconData icon, Color color, String label}) _modeInfo(String type) {
    return switch (type) {
      'Adım Adım Çöz'  => (icon: Icons.stairs_rounded,  color: Color(0xFF3B82F6), label: localeService.tr('mode_step_by_step')),
      'AI Öğretmen' || 'AI Arkadaşım' => (icon: Icons.school_rounded, color: Color(0xFF8B5CF6), label: localeService.tr('mode_ai_teacher')),
      _                => (icon: Icons.bolt_rounded,     color: Color(0xFFF59E0B), label: localeService.tr('mode_quick_solve')),
    };
  }

  @override
  Widget build(BuildContext context) {
    final mode    = _modeInfo(record.solutionType);
    final imgFile = File(record.imagePath);
    final hasImg  = imgFile.existsSync();
    final dateStr = _formatDate(record.timestamp);
    final model   = record.modelName.isEmpty ? 'QuAlsar' : record.modelName;

    final bgColor = customBg ?? Color(0xFFE9ECEF);
    final lum = 0.299 * bgColor.r + 0.587 * bgColor.g + 0.114 * bgColor.b;
    final isDark = lum < 0.55;
    final textColor =
        customTextColor ?? (isDark ? Colors.white : Colors.black);
    return DragTarget<Color>(
      onAcceptWithDetails: (d) => onColorAccept?.call(d.data),
      builder: (ctx, cand, _) => GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        // Renk değişimi anlık hissetsin diye animasyon süresi kısa.
        duration: Duration(milliseconds: 60),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Soft gri kart arka planı (varsayılan) veya kullanıcı özelleştirmesi.
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.14 : 0.06),
              blurRadius: isSelected ? 14 : 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Foto — kendi oranında TAM görünür, ince siyah çerçeve ─────
            Stack(
              children: [
                hasImg
                    ? AdaptivePhoto(
                        path: record.imagePath,
                        maxHeightFactor: 0.45,
                        borderRadius: 6,
                        background: Colors.white,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: _thumbFallback(record.subject),
                        ),
                      ),

                // Favori yıldız — sağ üst (kart içinde)
                if (record.isFavorite)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Icon(Icons.star_rounded, color: Colors.yellow, size: 22),
                  ),

                // Seçim modu onay kutusu — sağ alt
                if (isSelecting)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 180),
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: isSelected ? Color(0xFFEF4444) : Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: isSelected
                          ? Icon(Icons.check, color: Colors.white, size: 14)
                          : null,
                    ),
                  ),
              ],
            ),

            SizedBox(height: 10),

            // ── Mikro bilgi satırı — ders · yöntem · AI · saat ───────
            // Wrap kullanıyoruz; dar ekranda 4 atom tek satıra sığmazsa
            // otomatik olarak 2. satıra iner, taşma olmaz.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  _InfoAtom(
                    icon: _iconFor(record.subject),
                    label: _HistoryScreenState._subjectKeys.containsKey(record.subject)
                        ? localeService.tr(_HistoryScreenState._subjectKeys[record.subject]!)
                        : record.subject,
                    color: textColor,
                  ),
                  const _InfoDot(),
                  _InfoAtom(
                    icon: mode.icon,
                    label: mode.label,
                    color: textColor,
                  ),
                  const _InfoDot(),
                  _InfoAtom(
                    icon: Icons.smart_toy_rounded,
                    label: model,
                    color: textColor,
                  ),
                  const _InfoDot(),
                  _InfoAtom(
                    icon: Icons.schedule_rounded,
                    label: dateStr,
                    color: textColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _thumbFallback(String subject) {
    final c = _colorFor(subject);
    return Container(
      color: c.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(_iconFor(subject), color: c, size: 24),
    );
  }
}

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return localeService.tr('just_now');
  if (diff.inHours < 1) return '${diff.inMinutes}${localeService.tr('minutes_ago')}';
  if (diff.inDays < 1) return '${diff.inHours}${localeService.tr('hours_ago')}';
  if (diff.inDays == 1) return localeService.tr('yesterday');
  if (diff.inDays < 7) return '${diff.inDays} ${localeService.tr('days_ago')}';
  return '${dt.day}.${dt.month}.${dt.year}';
}

Color _colorFor(String subject) {
  return switch (subject) {
    'Matematik' => Color(0xFF3B82F6),
    'Fizik'     => Color(0xFF8B5CF6),
    'Kimya'     => Color(0xFFEC4899),
    'Biyoloji'  => Color(0xFF10B981),
    'Coğrafya'  => Color(0xFF06B6D4),
    'Tarih'     => Color(0xFFF59E0B),
    'Edebiyat'  => Color(0xFFEF4444),
    'Felsefe'   => Color(0xFF6366F1),
    'İngilizce' => Color(0xFF14B8A6),
    _           => Color(0xFF9CA3AF),
  };
}

IconData _iconFor(String subject) {
  return switch (subject) {
    'Matematik' => Icons.calculate_rounded,
    'Fizik'     => Icons.science_rounded,
    'Kimya'     => Icons.biotech_rounded,
    'Biyoloji'  => Icons.eco_rounded,
    'Coğrafya'  => Icons.public_rounded,
    'Tarih'     => Icons.history_edu_rounded,
    'Edebiyat'  => Icons.menu_book_rounded,
    'Felsefe'   => Icons.psychology_rounded,
    'İngilizce' => Icons.language_rounded,
    _           => Icons.book_rounded,
  };
}

// ─── Kart altı mikro bilgi atomu (ikon + kısa etiket) ────────────────────────

class _InfoAtom extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;

  const _InfoAtom({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoDot extends StatelessWidget {
  const _InfoDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3, height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppPalette.textSecondary(context),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─── Kategoriye göre açılır grup ─────────────────────────────────────────────

class _SubjectGroup extends StatelessWidget {
  final String subject;
  // Renk + çeviri anahtarı eşlemeleri için ham (çevrilmemiş) ders adı
  // — "subject" UI'da görünen çevrilmiş etikettir.
  final String rawSubject;
  final String emoji;
  final List<SolutionRecord> records;
  final Widget Function(SolutionRecord) cardBuilder;
  // Bu grup şu anda "yanık" — başlığa basılarak vurgulanmış mı.
  // Yanıkken: ders rengi belirgin çerçeve + glow gölgesi + soft tinted bg.
  final bool isLit;
  // Başlığa (leading + title alanı) tek dokunuşla yanık-söndür toggle.
  final VoidCallback? onHeaderTap;

  const _SubjectGroup({
    required this.subject,
    required this.rawSubject,
    required this.emoji,
    required this.records,
    required this.cardBuilder,
    this.isLit = false,
    this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(rawSubject);
    return AnimatedContainer(
      duration: Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        // Yanık iken hafifçe ders renginin tonu çıksın.
        color: isLit
            ? Color.alphaBlend(color.withValues(alpha: 0.06), Colors.white)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        // Yanık → ders rengiyle 1.6 px belirgin çerçeve. Söndük → çerçevesiz.
        border: isLit
            ? Border.all(color: color, width: 1.6)
            : null,
        boxShadow: [
          BoxShadow(
            color: isLit
                ? color.withValues(alpha: 0.32)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: isLit ? 18 : 10,
            spreadRadius: isLit ? 0.5 : 0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.only(bottom: 10),
          iconColor: isLit ? color : Colors.black,
          collapsedIconColor: Colors.black54,
          // Açma/kapamada da yanık halini güncelle — kullanıcı başlığa
          // bastığında ExpansionTile genişler, bu callback ile aynı anda
          // yanık state'i toggle eder.
          onExpansionChanged: (_) => onHeaderTap?.call(),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isLit ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: TextStyle(fontSize: 16)),
          ),
          title: Text(
            _HistoryScreenState._subjectKeys.containsKey(rawSubject)
                ? localeService.tr(_HistoryScreenState._subjectKeys[rawSubject]!)
                : subject,
            style: GoogleFonts.inter(
              color: isLit ? color : Colors.black87,
              fontSize: 12.5,
              fontWeight: isLit ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '${records.length} ${localeService.tr('solution_count')}',
              style: GoogleFonts.inter(
                color: AppPalette.textSecondary(context),
                fontSize: 9.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          children: [
            for (final r in records) cardBuilder(r),
          ],
        ),
      ),
    );
  }
}

// ─── Yardım kartı satırı ──────────────────────────────────────────────────────

class _HelpTile extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   body;

  const _HelpTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppPalette.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: AppPalette.textSecondary(context),
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
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
