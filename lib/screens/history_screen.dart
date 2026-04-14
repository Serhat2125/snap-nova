import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../services/solutions_storage.dart';
import '../services/pdf_service.dart';
import '../main.dart' show localeService;
import 'ai_result_screen.dart';
import 'solution_screen.dart';

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
  }

  Future<void> _load() async {
    final records = await SolutionsStorage.loadAll();
    if (mounted) setState(() => _records = records);
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
    return list;
  }

  Future<void> _delete(String id) async {
    await SolutionsStorage.delete(id);
    if (mounted) setState(() => _records.removeWhere((r) => r.id == id));
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
    for (final id in ids) {
      await SolutionsStorage.delete(id);
    }
    if (mounted) {
      setState(() {
        _records.removeWhere((r) => ids.contains(r.id));
        _isSelecting = false;
        _selectedIds.clear();
      });
    }
  }

  Future<void> _toggleFavorite(SolutionRecord rec) async {
    await SolutionsStorage.toggleFavorite(rec.id);
    await _load();
  }

  void _startLoading(String msg) =>
      setState(() { _isLoading = true; _loadingMessage = msg; });

  void _stopLoading() =>
      setState(() => _isLoading = false);

  Future<void> _exportPdf(SolutionRecord rec) async {
    _startLoading(localeService.tr('creating_pdf'));
    try {
      await PdfService.generateAndShare(rec);
    } catch (_) {
      _showError(localeService.tr('pdf_error'));
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
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
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              _optionTile(
                ctx: ctx,
                icon: rec.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                iconColor: const Color(0xFFF59E0B),
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
                iconColor: const Color(0xFF3B82F6),
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
                iconColor: const Color(0xFFEC4899),
                label: localeService.tr('get_pdf'),
                subtitle: null,
                onTap: () {
                  Navigator.pop(ctx);
                  _exportPdf(rec);
                },
              ),

              _divider(),

              _optionTile(
                ctx: ctx,
                icon: Icons.replay_rounded,
                iconColor: const Color(0xFF10B981),
                label: localeService.tr('resolve'),
                subtitle: null,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SolutionScreen(imagePath: rec.imagePath),
                    ),
                  );
                },
              ),

              _divider(),

              _optionTile(
                ctx: ctx,
                icon: Icons.delete_rounded,
                iconColor: const Color(0xFFEF4444),
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
                iconColor: const Color(0xFF8B5CF6),
                label: localeService.tr('bulk_delete'),
                subtitle: null,
                onTap: () {
                  Navigator.pop(ctx);
                  _enterSelectMode();
                },
              ),

              const SizedBox(height: 4),
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
      title: Text(label, style: const TextStyle(color: Color(0xFF333333), fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10))
          : null,
      onTap: onTap,
    );
  }

  Widget _divider() => Divider(
    color: const Color(0xFFF0F0F0),
    height: 1,
    indent: 16,
    endIndent: 16,
  );

  Future<void> _shareRecord(SolutionRecord rec) async {
    final imgFile = File(rec.imagePath);
    final text = '${rec.subject} — ${rec.solutionType}\n\n${rec.result}';
    try {
      if (imgFile.existsSync()) {
        await Share.shareXFiles([XFile(rec.imagePath)], text: text);
      } else {
        await Share.share(text);
      }
    } catch (_) {
      try {
        await Share.share(text);
      } catch (_) {}
    }
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(localeService.tr('delete'), style: const TextStyle(color: Color(0xFF333333), fontSize: 16)),
        content: Text(
          localeService.tr('confirm_delete_solution'),
          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(localeService.tr('cancel'), style: const TextStyle(color: Color(0xFF9CA3AF))),
          ),
          TextButton(
            onPressed: () { Navigator.pop(ctx); _delete(id); },
            child: Text(localeService.tr('delete'), style: const TextStyle(color: Color(0xFFEF4444))),
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
          decoration: const BoxDecoration(
            color: Color(0xFFF7F7F9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag tutamacı
              Container(
                width: 44, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        localeService.tr('help_title'),
                        style: const TextStyle(
                          color: Colors.black,
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
                  style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.45),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  children: [
                    _HelpTile(
                      icon: Icons.auto_awesome_rounded,
                      color: const Color(0xFF3B82F6),
                      title: localeService.tr('help_auto_category_title'),
                      body: localeService.tr('help_auto_category_body'),
                    ),
                    _HelpTile(
                      icon: Icons.filter_list_rounded,
                      color: const Color(0xFF8B5CF6),
                      title: localeService.tr('help_subject_filters_title'),
                      body: localeService.tr('help_subject_filters_body'),
                    ),
                    _HelpTile(
                      icon: Icons.image_rounded,
                      color: const Color(0xFF10B981),
                      title: localeService.tr('help_full_photo_title'),
                      body: localeService.tr('help_full_photo_body'),
                    ),
                    _HelpTile(
                      icon: Icons.star_rounded,
                      color: const Color(0xFFF59E0B),
                      title: localeService.tr('help_favorites_title'),
                      body: localeService.tr('help_favorites_body'),
                    ),
                    _HelpTile(
                      icon: Icons.touch_app_rounded,
                      color: const Color(0xFFEC4899),
                      title: localeService.tr('help_long_press_title'),
                      body: localeService.tr('help_long_press_body'),
                    ),
                    _HelpTile(
                      icon: Icons.replay_rounded,
                      color: const Color(0xFF06B6D4),
                      title: localeService.tr('help_resolve_title'),
                      body: localeService.tr('help_resolve_body'),
                    ),
                    _HelpTile(
                      icon: Icons.lock_outline_rounded,
                      color: const Color(0xFF64748B),
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
        content: Text(msg, style: const TextStyle(color: Color(0xFF333333))),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _orderedSubjects;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: SelectionArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Başlık ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 20, 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF333333)),
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
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

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
                              duration: const Duration(milliseconds: 200),
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 26),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(50),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                '${localeService.tr('all_filter')}  •  ${_records.length}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
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
                              GestureDetector(
                                onTap: _showHelpSheet,
                                behavior: HitTestBehavior.opaque,
                                child: const SizedBox(
                                  width: 40, height: 44,
                                  child: Icon(
                                    Icons.help_outline_rounded,
                                    color: Colors.black,
                                    size: 26,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
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

                if (!_showFavoritesOnly) const SizedBox(height: 16),

                // ── Ders filtreleri (Oval Beyaz Yapı) ─────────────────────────────────────────
                if (!_showFavoritesOnly)
                  SizedBox(
                    height: 50,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: subjects.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) {
                        final f   = subjects[i];
                        final sel = _selectedFilter == f;
                        final cnt = _records.where((r) => r.subject == f).length;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedFilter = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: sel ? 0.10 : 0.06),
                                  blurRadius: sel ? 12 : 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_emojiFor(f), style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Text(
                                  cnt > 0 ? '${_trSubject(f)}  $cnt' : _trSubject(f),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.black : const Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                if (!_showFavoritesOnly) const SizedBox(height: 14),
                if (_showFavoritesOnly) const SizedBox(height: 14),

                // ── Toplu seçim banner ──────────────────────────────────────
                if (_isSelecting)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.checklist_rounded, color: Color(0xFFEF4444), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedIds.isEmpty
                                  ? localeService.tr('select_to_delete')
                                  : '${_selectedIds.length} ${localeService.tr('selected')}',
                              style: const TextStyle(color: Color(0xFF333333), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (_selectedIds.isNotEmpty)
                            GestureDetector(
                              onTap: () => showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  title: Text(localeService.tr('bulk_delete'), style: const TextStyle(color: Color(0xFF333333), fontSize: 16)),
                                  content: Text(
                                    '${_selectedIds.length} ${localeService.tr('confirm_bulk_delete')}',
                                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(localeService.tr('cancel'), style: const TextStyle(color: Color(0xFF9CA3AF)))),
                                    TextButton(onPressed: () { Navigator.pop(ctx); _deleteSelected(); }, child: Text(localeService.tr('delete'), style: const TextStyle(color: Color(0xFFEF4444)))),
                                  ],
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(localeService.tr('delete'), style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _exitSelectMode,
                            child: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF), size: 18),
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
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
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
                            const CircularProgressIndicator(color: Color(0xFF3B82F6), strokeWidth: 2.5),
                            const SizedBox(height: 16),
                            Text(
                              _loadingMessage,
                              style: const TextStyle(color: Color(0xFF333333), fontSize: 13, fontWeight: FontWeight.w500),
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
    );
  }

  // ── Kategoriye göre gruplanmış liste ────────────────────────────────────
  Widget _buildGroupedList() {
    // Filtre spesifik bir ders seçmişse düz liste göster.
    if (_selectedFilter != 'Tümü' || _showFavoritesOnly) {
      return ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
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
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        for (final subject in keys)
          _SubjectGroup(
            subject: subject,
            emoji: _emojiFor(subject),
            records: groups[subject]!,
            cardBuilder: _cardFor,
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
            color: const Color(0xFF9CA3AF).withValues(alpha: 0.50),
          ),
          const SizedBox(height: 14),
          Text(
            isFavorites
                ? localeService.tr('empty_favorites')
                : isFiltered
                    ? localeService.tr('empty_category')
                    : localeService.tr('empty_solutions'),
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
          ),
          if (isFavorites) ...[
            const SizedBox(height: 6),
            Text(
              localeService.tr('empty_favorites_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ] else if (!isFiltered) ...[
            const SizedBox(height: 6),
            Text(
              localeService.tr('empty_solutions_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
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
      'Matematik' => '🔢',
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
}

// ─── Soru kartı (Modern Soft Design) ───────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final SolutionRecord record;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelecting;
  final bool isSelected;

  const _HistoryCard({
    required this.record,
    required this.onTap,
    required this.onLongPress,
    this.isSelecting = false,
    this.isSelected  = false,
  });

  static ({IconData icon, Color color, String label}) _modeInfo(String type) {
    return switch (type) {
      'Adım Adım Çöz'  => (icon: Icons.stairs_rounded,  color: const Color(0xFF3B82F6), label: localeService.tr('mode_step_by_step')),
      'AI Öğretmen'    => (icon: Icons.school_rounded,   color: const Color(0xFF8B5CF6), label: localeService.tr('mode_ai_teacher')),
      _                => (icon: Icons.bolt_rounded,     color: const Color(0xFFF59E0B), label: localeService.tr('mode_quick_solve')),
    };
  }

  @override
  Widget build(BuildContext context) {
    final mode    = _modeInfo(record.solutionType);
    final imgFile = File(record.imagePath);
    final hasImg  = imgFile.existsSync();
    final dateStr = _formatDate(record.timestamp);
    final model   = record.modelName.isEmpty ? 'SnapNova' : record.modelName;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Soft gri kart arka planı
          color: const Color(0xFFE9ECEF),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.14 : 0.06),
              blurRadius: isSelected ? 14 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tam boy foto — kalın siyah oval çerçeve ─────────────
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: hasImg
                          ? Image.file(
                              imgFile,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _thumbFallback(record.subject),
                            )
                          : _thumbFallback(record.subject),
                    ),
                  ),
                ),

                // Favori yıldız — sağ üst (kart içinde)
                if (record.isFavorite)
                  const Positioned(
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
                      duration: const Duration(milliseconds: 180),
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFEF4444) : Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : null,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // ── Mikro bilgi satırı — ders · yöntem · AI · saat ───────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  _InfoAtom(
                    icon: _iconFor(record.subject),
                    label: _HistoryScreenState._subjectKeys.containsKey(record.subject)
                        ? localeService.tr(_HistoryScreenState._subjectKeys[record.subject]!)
                        : record.subject,
                    color: Colors.black,
                  ),
                  const _InfoDot(),
                  _InfoAtom(
                    icon: mode.icon,
                    label: mode.label,
                    color: Colors.black,
                  ),
                  const _InfoDot(),
                  _InfoAtom(
                    icon: Icons.smart_toy_rounded,
                    label: model,
                    color: Colors.black,
                  ),
                  const _InfoDot(),
                  _InfoAtom(
                    icon: Icons.schedule_rounded,
                    label: dateStr,
                    color: Colors.black,
                  ),
                ],
              ),
            ),
          ],
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
    'Matematik' => const Color(0xFF3B82F6),
    'Fizik'     => const Color(0xFF8B5CF6),
    'Kimya'     => const Color(0xFFEC4899),
    'Biyoloji'  => const Color(0xFF10B981),
    'Coğrafya'  => const Color(0xFF06B6D4),
    'Tarih'     => const Color(0xFFF59E0B),
    'Edebiyat'  => const Color(0xFFEF4444),
    'Felsefe'   => const Color(0xFF6366F1),
    'İngilizce' => const Color(0xFF14B8A6),
    _           => const Color(0xFF9CA3AF),
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
          const SizedBox(width: 3),
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
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─── Kategoriye göre açılır grup ─────────────────────────────────────────────

class _SubjectGroup extends StatelessWidget {
  final String subject;
  final String emoji;
  final List<SolutionRecord> records;
  final Widget Function(SolutionRecord) cardBuilder;

  const _SubjectGroup({
    required this.subject,
    required this.emoji,
    required this.records,
    required this.cardBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(subject);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: Colors.black,
          collapsedIconColor: Colors.black54,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          title: Text(
            _HistoryScreenState._subjectKeys.containsKey(subject)
                ? localeService.tr(_HistoryScreenState._subjectKeys[subject]!)
                : subject,
            style: GoogleFonts.inter(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '${records.length} ${localeService.tr('solution_count')}',
              style: GoogleFonts.inter(
                color: Colors.black38,
                fontSize: 10,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.black54,
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
