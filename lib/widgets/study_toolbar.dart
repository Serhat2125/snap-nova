// StudyToolbarOverlay — özet sayfasının sol kenarında dikey çalışma araç çubuğu.
// 5 ikon: Not Al · Sarı Vurgulayıcı · Kırmızı Kalem · Silgi · Kapat
// Aktif modda ekranın üstüne çizim katmanı (CustomPainter) bindirir;
// kullanıcı parmağıyla çizer, çizimler topicId bazlı kalıcı saklanır.
//
// Kullanım:
//   Stack(children: [
//     YourPageBody(...),
//     StudyToolbarOverlay(topicId: '...', topicName: '...'),
//   ])

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'note_creator_page.dart';

enum _DrawMode { off, highlight, pen, multiHighlight, multiHighlightStraight, eraser }

/// Çoklu renkli vurgulayıcının renk paleti — 16 renk, 2 sıra × 8 sütun.
const List<Color> _multiHighlightColors = [
  Color(0xFFFFEB3B), // sarı
  Color(0xFFFFC107), // amber
  Color(0xFFFF9800), // turuncu
  Color(0xFFFF5722), // koyu turuncu
  Color(0xFFEF4444), // kırmızı
  Color(0xFFEC4899), // pembe
  Color(0xFFA855F7), // mor
  Color(0xFF7C3AED), // koyu mor
  Color(0xFF3B82F6), // mavi
  Color(0xFF06B6D4), // cam göbeği
  Color(0xFF14B8A6), // turkuaz
  Color(0xFF22C55E), // yeşil
  Color(0xFF84CC16), // lime
  Color(0xFFEAB308), // hardal
  Color(0xFF78716C), // gri
  Color(0xFF000000), // siyah
];

class StudyToolbarOverlay extends StatefulWidget {
  final String topicId;
  final String topicName;
  /// Sticky highlights için parent scrollable'ın controller'ı.
  /// Stack içinde overlay scrollable'ın sibling'i olduğunda
  /// Scrollable.maybeOf(context) null döner — controller'ı doğrudan
  /// inject etmek gerek.
  final ScrollController? scrollController;
  const StudyToolbarOverlay({
    super.key,
    required this.topicId,
    required this.topicName,
    this.scrollController,
  });

  @override
  State<StudyToolbarOverlay> createState() => _StudyToolbarOverlayState();
}

class _StudyToolbarOverlayState extends State<StudyToolbarOverlay> {
  _DrawMode _mode = _DrawMode.off;
  final List<_Stroke> _strokes = [];
  _Stroke? _current;
  bool _loaded = false;
  // Sticky highlights — strokes content-space'te (scrollOffset eklenmiş)
  // saklanır. Render sırasında canvas -scrollOffset translate edilir →
  // çizimler içerikle birlikte hareket eder.
  double _scrollOffset = 0;
  ScrollPosition? _scrollPosition;
  // Collapse/expand state — kullanıcı tek yuvarlak butona basınca
  // 6 ikonlu panel açılır; X'e basınca tekrar collapse olur.
  bool _expanded = false;
  // Çoklu renkli vurgulayıcı: butona basılınca yana 5 renk + silgi paneli açılır.
  bool _colorPickerOpen = false;
  Color _multiHighlightColor = _multiHighlightColors.first;

  // ── Draggable toolbar pozisyonu ────────────────────────────────────────
  // Kullanıcı toolbar'ı sürükleyince offset güncellenir, position
  // SharedPreferences ile topicId bazlı saklanır.
  // _toolbarLeft/Top null iken default konum (sol, ekranın %22'si).
  double? _toolbarLeft;
  double? _toolbarTop;

  String get _strokeKey => 'strokes_${widget.topicId}';
  String get _posKey => 'toolbar_pos_${widget.topicId}';

  @override
  void initState() {
    super.initState();
    _loadStrokes();
    _loadToolbarPos();
    _attachToController();
  }

  Future<void> _loadToolbarPos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_posKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _toolbarLeft = (m['left'] as num?)?.toDouble();
        _toolbarTop = (m['top'] as num?)?.toDouble();
      });
    } catch (_) {}
  }

  Future<void> _saveToolbarPos() async {
    if (_toolbarLeft == null || _toolbarTop == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _posKey,
      jsonEncode({'left': _toolbarLeft, 'top': _toolbarTop}),
    );
  }

  @override
  void didUpdateWidget(StudyToolbarOverlay old) {
    super.didUpdateWidget(old);
    if (old.scrollController != widget.scrollController) {
      _detachFromController();
      _attachToController();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fallback: controller injecte edilmediyse ata yakın Scrollable'ı bul.
    if (widget.scrollController != null) return;
    final newPos = Scrollable.maybeOf(context)?.position;
    if (newPos != _scrollPosition) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = newPos;
      _scrollPosition?.addListener(_onScroll);
      if (newPos != null) {
        _scrollOffset = newPos.pixels;
      }
    }
  }

  void _attachToController() {
    final c = widget.scrollController;
    if (c == null) return;
    c.addListener(_onControllerScroll);
    if (c.hasClients) {
      _scrollOffset = c.offset;
    }
  }

  void _detachFromController() {
    widget.scrollController?.removeListener(_onControllerScroll);
  }

  void _onControllerScroll() {
    final c = widget.scrollController;
    if (c == null || !c.hasClients) return;
    setState(() => _scrollOffset = c.offset);
  }

  void _onScroll() {
    final pos = _scrollPosition;
    if (pos == null) return;
    setState(() => _scrollOffset = pos.pixels);
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    _detachFromController();
    super.dispose();
  }

  Future<void> _loadStrokes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_strokeKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _strokes.addAll(list
            .map((e) => _Stroke.fromJson(e as Map<String, dynamic>))
            .toList());
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  Future<void> _persistStrokes() async {
    final prefs = await SharedPreferences.getInstance();
    if (_strokes.isEmpty) {
      await prefs.remove(_strokeKey);
    } else {
      final raw =
          jsonEncode(_strokes.map((s) => s.toJson()).toList());
      await prefs.setString(_strokeKey, raw);
    }
  }

  /// Ekran koordinatını içerik koordinatına çevir (sticky highlights için).
  Offset _toContent(Offset screen) =>
      Offset(screen.dx, screen.dy + _scrollOffset);

  void _onPanStart(DragStartDetails d) {
    if (_mode == _DrawMode.off) return;
    // Silgi modunda yeni stroke oluşturma — sadece dokunulan yerdeki strokes
    // silinir (yarıçap içinde).
    if (_mode == _DrawMode.eraser) {
      _eraseNear(d.localPosition);
      return;
    }
    Color strokeColor;
    double strokeWidth;
    switch (_mode) {
      case _DrawMode.highlight:
        strokeColor = const Color(0xFFFFEB3B).withValues(alpha: 0.30);
        strokeWidth = 16;
        break;
      case _DrawMode.pen:
        strokeColor = const Color(0xFFEF4444).withValues(alpha: 0.95);
        strokeWidth = 4;
        break;
      case _DrawMode.multiHighlight:
      case _DrawMode.multiHighlightStraight:
        strokeColor = _multiHighlightColor.withValues(alpha: 0.40);
        strokeWidth = 22;
        break;
      case _DrawMode.eraser:
      case _DrawMode.off:
        return;
    }
    setState(() {
      _current = _Stroke(
        color: strokeColor,
        width: strokeWidth,
        // Content-space'te sakla → scroll ile birlikte hareket eder.
        points: [_toContent(d.localPosition)],
      );
    });
  }

  /// Verilen ekran noktasına YAKIN stroke'ları sil (silgi modu).
  /// Önce ekran koordinatını content-space'e çevirir.
  void _eraseNear(Offset screenPoint) {
    const radius = 22.0;
    final radiusSq = radius * radius;
    final point = _toContent(screenPoint);
    bool removed = false;
    setState(() {
      _strokes.removeWhere((s) {
        for (final p in s.points) {
          final dx = p.dx - point.dx;
          final dy = p.dy - point.dy;
          if (dx * dx + dy * dy <= radiusSq) {
            removed = true;
            return true;
          }
        }
        return false;
      });
    });
    if (removed) _persistStrokes();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    // Silgi modunda dokunulan yerdeki stroke'ları siler (drag boyunca devam).
    if (_mode == _DrawMode.eraser) {
      _eraseNear(d.localPosition);
      return;
    }
    if (_current == null) return;
    final contentPt = _toContent(d.localPosition);
    // Düz çizgi modunda Y'yi başlangıç noktasına kilitle — yatay düz çizgi.
    final pt = _mode == _DrawMode.multiHighlightStraight
        ? Offset(contentPt.dx, _current!.points.first.dy)
        : contentPt;
    setState(() => _current!.points.add(pt));
  }

  void _onPanEnd(DragEndDetails _) {
    if (_current == null) return;
    setState(() {
      _strokes.add(_current!);
      _current = null;
    });
    _persistStrokes();
  }

  Future<void> _eraseAll() async {
    setState(() {
      _strokes.clear();
      _current = null;
    });
    await _persistStrokes();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final drawing = _mode != _DrawMode.off;
    return Stack(
      children: [
        // Çizim katmanı — YATAY drag = vurgulama, DİKEY drag = scroll için
        // parent'a bırakılır. Cümleler yatay olduğu için bu doğal hisseder:
        //   • Sağa-sola sürükle → renkli vurgu
        //   • Yukarı-aşağı sürükle → sayfa scroll
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !drawing,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onPanStart,
              onHorizontalDragUpdate: _onPanUpdate,
              onHorizontalDragEnd: _onPanEnd,
              child: CustomPaint(
                size: Size.infinite,
                painter: _StrokePainter(
                  strokes: _strokes,
                  current: _current,
                  scrollOffset: _scrollOffset,
                ),
              ),
            ),
          ),
        ),
        // Toolbar — sürüklenebilir. Default sol-orta; kullanıcı sürükleyince
        // _toolbarLeft/Top güncellenir + persist edilir.
        // Collapsed iken tek yuvarlak buton, expanded iken 6 ikonlu panel.
        () {
          final screen = MediaQuery.of(context).size;
          final left = _toolbarLeft ?? 8;
          final top = _toolbarTop ?? screen.height * 0.22;
          return Positioned(
            left: left,
            top: top,
            child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _expanded
                ? Row(
                    key: const ValueKey('expanded'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ToolbarPanel(
                        mode: _mode,
                        multiActive: _mode == _DrawMode.multiHighlight ||
                            _mode == _DrawMode.multiHighlightStraight,
                        multiOpen: _colorPickerOpen,
                        onOpenNotePage: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NoteCreatorPage(
                              topicId: widget.topicId,
                              topicName: widget.topicName,
                            ),
                          ),
                        ),
                        onMultiHighlight: () => setState(() {
                          _colorPickerOpen = !_colorPickerOpen;
                        }),
                        onHighlight: () =>
                            setState(() => _mode = _DrawMode.highlight),
                        onPen: () =>
                            setState(() => _mode = _DrawMode.pen),
                        onErase: _eraseAll,
                        onClose: () => setState(() {
                          _mode = _DrawMode.off;
                          _expanded = false;
                          _colorPickerOpen = false;
                        }),
                      ),
                      // Yan sub-panel: 5 renk yatay + silgi alt
                      if (_colorPickerOpen) ...[
                        const SizedBox(width: 8),
                        // Multi-color pen toolbar'da 2. sıra (Not Sayfası altında).
                        // Yaklaşık offset: 1 buton yüksekliği + divider ≈ 50px.
                        Padding(
                          padding: const EdgeInsets.only(top: 50),
                          child: _ColorSubPanel(
                            colors: _multiHighlightColors,
                            selected: _multiHighlightColor,
                            eraserActive: _mode == _DrawMode.eraser,
                            onSelect: (c, straight) => setState(() {
                              _multiHighlightColor = c;
                              _mode = straight
                                  ? _DrawMode.multiHighlightStraight
                                  : _DrawMode.multiHighlight;
                              _colorPickerOpen = false;
                              // Toolbar tamamen kapanır → ekran temiz; kullanıcı
                              // seçtiği renkle cümleyi vurgulayabilir.
                              _expanded = false;
                            }),
                            onErase: () => setState(() {
                              // Silgi MODU aktif — hepsini silmez, parmakla
                              // dokunulan yerdeki strokes silinir.
                              _mode = _DrawMode.eraser;
                              _colorPickerOpen = false;
                            }),
                          ),
                        ),
                      ],
                    ],
                  )
                : _CollapsedButton(
                    key: const ValueKey('collapsed'),
                    onTap: () => setState(() => _expanded = true),
                    onDrag: (dx, dy) {
                      // Drag delta'sını mevcut konuma ekle.
                      // Ekran sınırlarına clamp et — buton hep görünür kalsın.
                      const buttonSize = 50.0;
                      final maxLeft = screen.width - buttonSize - 4;
                      final maxTop = screen.height -
                          buttonSize -
                          MediaQuery.of(context).padding.bottom -
                          16;
                      setState(() {
                        _toolbarLeft = ((_toolbarLeft ?? left) + dx)
                            .clamp(4.0, maxLeft);
                        _toolbarTop = ((_toolbarTop ?? top) + dy)
                            .clamp(MediaQuery.of(context).padding.top + 4,
                                maxTop);
                      });
                    },
                    onDragEnd: _saveToolbarPos,
                  ),
          ),
        );
        }(),
      ],
    );
  }
}

// ─── Collapsed yuvarlak buton — tek tıklamayla expand olur ─────────────────
// Aynı zamanda sürüklenebilir: pan ile ekranın istediği yerine taşınır.
// onTap ve onDrag aynı GestureDetector'da: kısa basışta tap, hareket olunca
// drag tetiklenir (Flutter otomatik ayırt eder).
class _CollapsedButton extends StatelessWidget {
  final VoidCallback onTap;
  final void Function(double dx, double dy)? onDrag;
  final VoidCallback? onDragEnd;
  const _CollapsedButton({
    super.key,
    required this.onTap,
    this.onDrag,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: onDrag == null
          ? null
          : (d) => onDrag!(d.delta.dx, d.delta.dy),
      onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.40),
              blurRadius: 16,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.menu_book_rounded,
            color: Colors.white, size: 24),
      ),
    );
  }
}

// ─── Toolbar paneli ──────────────────────────────────────────────────────────
class _ToolbarPanel extends StatelessWidget {
  final _DrawMode mode;
  final bool multiActive;
  final bool multiOpen;
  final VoidCallback onOpenNotePage;
  final VoidCallback onMultiHighlight;
  final VoidCallback onHighlight;
  final VoidCallback onPen;
  final VoidCallback onErase;
  final VoidCallback onClose;

  const _ToolbarPanel({
    required this.mode,
    required this.multiActive,
    required this.multiOpen,
    required this.onOpenNotePage,
    required this.onMultiHighlight,
    required this.onHighlight,
    required this.onPen,
    required this.onErase,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // En üstte — büyük not editörü sayfası
          _ToolBtn(
            icon: Icons.menu_book_rounded,
            tooltip: 'Not Sayfası Oluştur',
            color: const Color(0xFFA855F7),
            onTap: onOpenNotePage,
          ),
          _Divider(),
          // YENİ: Çoklu Renkli Vurgulayıcı — basınca yana 5 renk + silgi açılır
          _ToolBtn(
            icon: Icons.palette_rounded,
            tooltip: 'Çoklu Renkli Vurgulayıcı',
            color: const Color(0xFFEC4899),
            active: multiActive || multiOpen,
            onTap: onMultiHighlight,
          ),
          _Divider(),
          // Sarı vurgulayıcı kaldırıldı — çoklu renkli vurgulayıcıda zaten
          // sarı seçeneği var, çift fonksiyona gerek yok.
          _ToolBtn(
            icon: Icons.create_rounded,
            tooltip: 'Kırmızı Kalem',
            color: const Color(0xFFEF4444),
            active: mode == _DrawMode.pen,
            onTap: onPen,
          ),
          _Divider(),
          _ToolBtn(
            icon: Icons.cleaning_services_rounded,
            tooltip: 'Tümünü Sil',
            color: const Color(0xFF60A5FA),
            onTap: onErase,
          ),
          _Divider(),
          _ToolBtn(
            icon: Icons.close_rounded,
            tooltip: 'Araçları Kapat',
            color: Colors.white,
            active: mode == _DrawMode.off,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: active
                ? Border.all(color: color, width: 1.6)
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.white.withValues(alpha: 0.10),
    );
  }
}

// ─── Çoklu Renk Sub-Paneli ──────────────────────────────────────────────────
// 16 renk, 2 sıra × 8 sütun, yatay scrollable. Renge basınca otomatik kapanır,
// "stroke mode" diyalog'u açılır (Serbest / Düz Çizgi). Altta silgi.
class _ColorSubPanel extends StatelessWidget {
  final List<Color> colors;
  final Color selected;
  /// `(color, straight)` — straight=true → düz çizgi modu, false → serbest.
  final void Function(Color color, bool straight) onSelect;
  final VoidCallback onErase;
  final bool eraserActive;
  const _ColorSubPanel({
    required this.colors,
    required this.selected,
    required this.onSelect,
    required this.onErase,
    this.eraserActive = false,
  });

  Future<void> _askStrokeMode(BuildContext ctx, Color picked) async {
    final straight = await showModalBottomSheet<bool>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (dialogCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xF0111122),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: picked,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Çizim Şekli',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StrokeModeCard(
                    title: 'Serbest',
                    subtitle: 'Parmağı takip eder',
                    icon: Icons.gesture_rounded,
                    color: picked,
                    onTap: () => Navigator.of(dialogCtx).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StrokeModeCard(
                    title: 'Düz Çizgi',
                    subtitle: 'Yatay düz devam eder',
                    icon: Icons.horizontal_rule_rounded,
                    color: picked,
                    onTap: () => Navigator.of(dialogCtx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (straight != null && ctx.mounted) {
      onSelect(picked, straight);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 16 renk → 2 sıra × 8 sütun.
    final firstRow = colors.take(8).toList();
    final secondRow = colors.skip(8).take(8).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst ipucu — kullanıcıya ne yapacağını anlatır.
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
            child: Text(
              'Bir renk seç, cümleni vurgula',
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.70),
                letterSpacing: 0.2,
              ),
            ),
          ),
          // 2 sıra × yatay scroll
          SizedBox(
            width: 220,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                children: [
                  Row(children: [
                    for (final c in firstRow) ...[
                      _ColorDot(
                        color: c,
                        active: c.toARGB32() == selected.toARGB32(),
                        onTap: () => _askStrokeMode(context, c),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (final c in secondRow) ...[
                      _ColorDot(
                        color: c,
                        active: c.toARGB32() == selected.toARGB32(),
                        onTap: () => _askStrokeMode(context, c),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onErase,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF60A5FA).withValues(
                    alpha: eraserActive ? 0.30 : 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF60A5FA)
                        .withValues(alpha: eraserActive ? 0.90 : 0.40),
                    width: eraserActive ? 1.8 : 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cleaning_services_rounded,
                      color: Color(0xFF60A5FA), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    eraserActive ? 'Silgi (Aktif)' : 'Silgi',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF60A5FA)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokeModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StrokeModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.50), width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: Colors.white60,
                    height: 1.3)),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _ColorDot(
      {required this.color, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.25),
            width: active ? 2.5 : 1.2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 10,
                    spreadRadius: 1.5,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

// ─── Stroke modeli + painter ────────────────────────────────────────────────
class _Stroke {
  Color color;
  double width;
  List<Offset> points;
  _Stroke({
    required this.color,
    required this.width,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        // ignore: deprecated_member_use
        'c': color.value,
        'w': width,
        'p': points.map((o) => [o.dx, o.dy]).toList(),
      };

  factory _Stroke.fromJson(Map<String, dynamic> j) => _Stroke(
        color: Color((j['c'] as num).toInt()),
        width: (j['w'] as num).toDouble(),
        points: (j['p'] as List)
            .map((e) => Offset(
                (e[0] as num).toDouble(), (e[1] as num).toDouble()))
            .toList(),
      );
}

class _StrokePainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? current;
  /// Aktif scroll offset — strokes content-space'te saklanıyor; render
  /// sırasında canvas -scrollOffset translate edilir → çizimler içerik
  /// scroll'una göre senkron hareket eder (sticky highlights).
  final double scrollOffset;
  _StrokePainter({
    required this.strokes,
    this.current,
    this.scrollOffset = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(0, -scrollOffset);
    void drawStroke(_Stroke s) {
      if (s.points.length < 2) {
        if (s.points.length == 1) {
          canvas.drawCircle(s.points.first, s.width / 2,
              Paint()..color = s.color);
        }
        return;
      }
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (var i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    for (final s in strokes) {
      drawStroke(s);
    }
    if (current != null) drawStroke(current!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

// google_fonts placeholder — _u referansı build sırasında değişebilecek
// gelecek başlık/etiket için tutuluyor. Şu anda toolbar sadece ikon.
// ignore: unused_element
final _ = GoogleFonts.poppins;
