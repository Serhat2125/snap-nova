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
import '../services/error_logger.dart';
import '../services/runtime_translator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'note_creator_page.dart';

enum _DrawMode { off, highlight, pen, multiHighlight, multiHighlightStraight, eraser }

/// Kalem çizim şekli — kullanıcı renk/kalınlık seçtikten sonra hangi şekilde
/// çizeceğini belirler. `freehand` = elle/serbest çizim (parmak izi),
/// diğerleri rubber-band: start ve end point ile şekil.
enum _PenShape { freehand, circle, square, rectangle }

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

/// Kalem renk paleti — 8 koyu/canlı renk, çizim için ideal opasite.
const List<Color> _penColors = [
  Color(0xFFEF4444), // kırmızı
  Color(0xFF000000), // siyah
  Color(0xFF3B82F6), // mavi
  Color(0xFF22C55E), // yeşil
  Color(0xFFF59E0B), // turuncu
  Color(0xFFA855F7), // mor
  Color(0xFFEC4899), // pembe
  Color(0xFF92400E), // kahverengi
];

/// Kalem kalınlık seçenekleri — ince, orta, kalın.
const List<double> _penWidths = [2.0, 4.0, 7.0];

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
  // Kalem: kullanıcı seçtiği renk + kalınlık + şekil. Butona basınca yana panel
  // açılır; "Çizmeye Başla" sonrası şekil seçim sheet'i (alt) gelir.
  bool _penPickerOpen = false;
  Color _penColor = _penColors.first;
  double _penWidth = _penWidths[1]; // orta = 4.0
  _PenShape _penShape = _PenShape.freehand;

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
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'study_toolbar'); }
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
      } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'study_toolbar'); }
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
        // Kullanıcı seçimi — renk + kalınlık yan panelden gelir.
        strokeColor = _penColor.withValues(alpha: 0.95);
        strokeWidth = _penWidth;
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
        // Kalem modunda kullanıcı seçtiği şekli kaydet; diğer modlar
        // her zaman freehand (highlighter).
        shape: _mode == _DrawMode.pen ? _penShape : _PenShape.freehand,
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
    // Şekil modlarında (circle/square/rectangle) sadece 2 nokta tut —
    // ilk = anchor, ikinci = güncel mouse/parmak pozisyonu (rubber-band).
    final isShape = _current!.shape != _PenShape.freehand;
    if (isShape) {
      setState(() {
        if (_current!.points.length < 2) {
          _current!.points.add(contentPt);
        } else {
          _current!.points[1] = contentPt;
        }
      });
      return;
    }
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

  /// Kalem rengi + kalınlığı seçildikten sonra "Nasıl çizmek istersin?"
  /// alt sheet'i açar — 4 seçenek: Yuvarlak / Kare / Dikdörtgen / Düz (elle).
  Future<_PenShape?> _askPenShape(BuildContext ctx) {
    return showModalBottomSheet<_PenShape>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
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
                    color: _penColor,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Nasıl çizmek istersin?'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    )),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PenShapeCard(
                    label: 'Yuvarlak'.tr(),
                    color: _penColor,
                    width: _penWidth,
                    shape: _PenShape.circle,
                    onTap: () => Navigator.of(sheetCtx).pop(_PenShape.circle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PenShapeCard(
                    label: 'Kare'.tr(),
                    color: _penColor,
                    width: _penWidth,
                    shape: _PenShape.square,
                    onTap: () => Navigator.of(sheetCtx).pop(_PenShape.square),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _PenShapeCard(
                    label: 'Dikdörtgen'.tr(),
                    color: _penColor,
                    width: _penWidth,
                    shape: _PenShape.rectangle,
                    onTap: () =>
                        Navigator.of(sheetCtx).pop(_PenShape.rectangle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PenShapeCard(
                    label: 'Düz'.tr(),
                    color: _penColor,
                    width: _penWidth,
                    shape: _PenShape.freehand,
                    onTap: () =>
                        Navigator.of(sheetCtx).pop(_PenShape.freehand),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    // Renk vurgu modunda küçük üst gösterge: kullanıcıya modu hatırlatır + çıkış butonu.
    final colorActive = _mode == _DrawMode.multiHighlight ||
        _mode == _DrawMode.multiHighlightStraight ||
        _mode == _DrawMode.pen;
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
                        penOpen: _penPickerOpen,
                        penColor: _penColor,
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
                          if (_colorPickerOpen) _penPickerOpen = false;
                        }),
                        onHighlight: () =>
                            setState(() => _mode = _DrawMode.highlight),
                        onPen: () => setState(() {
                          _penPickerOpen = !_penPickerOpen;
                          if (_penPickerOpen) _colorPickerOpen = false;
                        }),
                        onErase: _eraseAll,
                        onClose: () => setState(() {
                          _mode = _DrawMode.off;
                          _expanded = false;
                          _colorPickerOpen = false;
                          _penPickerOpen = false;
                        }),
                      ),
                      // Yan sub-panel: highlighter veya kalem renk/kalınlık seçici
                      if (_colorPickerOpen) ...[
                        const SizedBox(width: 8),
                        // Multi-color highlighter toolbar'da 2. sıra (Not Sayfası altında).
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
                      // Kalem sub-paneli — 8 renk + 3 kalınlık
                      if (_penPickerOpen) ...[
                        const SizedBox(width: 8),
                        // Pen panel — kalem butonu 3. sırada (≈ 100px offset).
                        Padding(
                          padding: const EdgeInsets.only(top: 100),
                          child: _PenSubPanel(
                            colors: _penColors,
                            widths: _penWidths,
                            selectedColor: _penColor,
                            selectedWidth: _penWidth,
                            onPick: (c, w) async {
                              // Renk + kalınlık seçildi; alt sheet ile şekil sor.
                              setState(() {
                                _penColor = c;
                                _penWidth = w;
                                _penPickerOpen = false;
                                _expanded = false;
                              });
                              final picked = await _askPenShape(context);
                              if (picked == null || !mounted) return;
                              setState(() {
                                _penShape = picked;
                                _mode = _DrawMode.pen;
                              });
                            },
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
        // ── Sol üst renk modu göstergesi ──────────────────────────────
        // Kullanıcı renk + çizim şekli seçtikten sonra toolbar kapanır;
        // bu küçük tab modu hatırlatır + X ile çıkış sağlar.
        if (colorActive)
          Positioned(
            left: 12,
            top: MediaQuery.of(context).padding.top + 8,
            child: _ColorModeBadge(
              color: _mode == _DrawMode.pen ? _penColor : _multiHighlightColor,
              onClose: () => setState(() => _mode = _DrawMode.off),
            ),
          ),
      ],
    );
  }
}

// ─── Sol üst renk modu göstergesi ──────────────────────────────────────────
// Küçük yatay tab: renk dot + "Renk seç, cümleni vurgula" + X.
class _ColorModeBadge extends StatelessWidget {
  final Color color;
  final VoidCallback onClose;
  const _ColorModeBadge({required this.color, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Renk dot
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: Colors.white, width: 1.4),
              ),
            ),
            const SizedBox(width: 8),
            // Metin
            Text(
              'Renk seç, cümleni vurgula',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            // X butonu — renk modundan çıkar
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
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
  final bool penOpen;
  final Color penColor;
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
    required this.penOpen,
    required this.penColor,
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
            tooltip: 'Kalem (Renk + Kalınlık)',
            // Seçili kalem rengini buton üzerinde göster — kullanıcı geçerli
            // rengi anında görür.
            color: penColor,
            active: mode == _DrawMode.pen || penOpen,
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
                Text('Çizim Şekli'.tr(),
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
  /// Çizim şekli — freehand (varsayılan) veya geometric (circle/square/rect).
  _PenShape shape;
  _Stroke({
    required this.color,
    required this.width,
    required this.points,
    this.shape = _PenShape.freehand,
  });

  Map<String, dynamic> toJson() => {
        // ignore: deprecated_member_use
        'c': color.value,
        'w': width,
        'p': points.map((o) => [o.dx, o.dy]).toList(),
        's': shape.index,
      };

  factory _Stroke.fromJson(Map<String, dynamic> j) => _Stroke(
        color: Color((j['c'] as num).toInt()),
        width: (j['w'] as num).toDouble(),
        points: (j['p'] as List)
            .map((e) => Offset(
                (e[0] as num).toDouble(), (e[1] as num).toDouble()))
            .toList(),
        shape: j['s'] != null
            ? _PenShape.values[(j['s'] as num).toInt()
                .clamp(0, _PenShape.values.length - 1)]
            : _PenShape.freehand,
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
      if (s.points.isEmpty) return;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      // Geometric shape — start + end (rubber-band).
      if (s.shape != _PenShape.freehand && s.points.length >= 2) {
        final a = s.points.first;
        final b = s.points.last;
        switch (s.shape) {
          case _PenShape.circle:
            // Oval: a ve b ile tanımlanan dikdörtgenin içine sığar.
            final rect = Rect.fromPoints(a, b);
            canvas.drawOval(rect, paint);
            return;
          case _PenShape.square:
            // En büyük kenar tarafından belirlenen kare; a köşe, b yön.
            final dx = b.dx - a.dx;
            final dy = b.dy - a.dy;
            final side = (dx.abs() > dy.abs() ? dx.abs() : dy.abs());
            final sx = dx >= 0 ? a.dx : a.dx - side;
            final sy = dy >= 0 ? a.dy : a.dy - side;
            canvas.drawRect(
                Rect.fromLTWH(sx, sy, side, side), paint);
            return;
          case _PenShape.rectangle:
            canvas.drawRect(Rect.fromPoints(a, b), paint);
            return;
          case _PenShape.freehand:
            break;
        }
      }
      // Freehand veya tek nokta
      if (s.points.length < 2) {
        if (s.points.length == 1) {
          canvas.drawCircle(s.points.first, s.width / 2,
              Paint()..color = s.color);
        }
        return;
      }
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

// ─── Kalem Sub-Paneli ─────────────────────────────────────────────────────
// 8 renk + 3 kalınlık (ince/orta/kalın). Renk ve kalınlık birlikte seçilir,
// onPick callback'i ile mode pen olarak aktive olur.
class _PenSubPanel extends StatefulWidget {
  final List<Color> colors;
  final List<double> widths;
  final Color selectedColor;
  final double selectedWidth;
  final void Function(Color color, double width) onPick;

  const _PenSubPanel({
    required this.colors,
    required this.widths,
    required this.selectedColor,
    required this.selectedWidth,
    required this.onPick,
  });

  @override
  State<_PenSubPanel> createState() => _PenSubPanelState();
}

class _PenSubPanelState extends State<_PenSubPanel> {
  late Color _tmpColor;
  late double _tmpWidth;

  @override
  void initState() {
    super.initState();
    _tmpColor = widget.selectedColor;
    _tmpWidth = widget.selectedWidth;
  }

  @override
  Widget build(BuildContext context) {
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
          // İpucu
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
            child: Text(
              'Renk ve kalınlık seç',
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.70),
                letterSpacing: 0.2,
              ),
            ),
          ),
          // 8 renk yan yana (yatay scroll)
          SizedBox(
            width: 220,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final c in widget.colors) ...[
                  _ColorDot(
                    color: c,
                    active: c.toARGB32() == _tmpColor.toARGB32(),
                    onTap: () => setState(() => _tmpColor = c),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // İnce / orta / kalın — yatay 3 buton
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int i = 0; i < widget.widths.length; i++)
                _PenWidthBtn(
                  width: widget.widths[i],
                  color: _tmpColor,
                  active: widget.widths[i] == _tmpWidth,
                  label: ['İnce', 'Orta', 'Kalın'][i],
                  onTap: () => setState(() => _tmpWidth = widget.widths[i]),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Onay butonu — seçimi uygula
          GestureDetector(
            onTap: () => widget.onPick(_tmpColor, _tmpWidth),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_tmpColor, _tmpColor.withValues(alpha: 0.75)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                'Çizmeye Başla',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PenWidthBtn extends StatelessWidget {
  final double width;
  final Color color;
  final bool active;
  final String label;
  final VoidCallback onTap;
  const _PenWidthBtn({
    required this.width,
    required this.color,
    required this.active,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? color : Colors.white.withValues(alpha: 0.10),
            width: active ? 1.6 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Çizgi önizleme — seçili kalınlık ve renk
            Container(
              height: width,
              width: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(width / 2),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: active ? color : Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Kalem Şekil Kartı (alt sheet içinde) ─────────────────────────────────
// Her kart bir şekli önizler + ada sahip + tıklanınca Navigator.pop ile döner.
class _PenShapeCard extends StatelessWidget {
  final String label;
  final Color color;
  final double width;
  final _PenShape shape;
  final VoidCallback onTap;
  const _PenShapeCard({
    required this.label,
    required this.color,
    required this.width,
    required this.shape,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Şekil önizleme — küçük canvas
            SizedBox(
              width: 60,
              height: 40,
              child: CustomPaint(
                painter: _PenShapePreview(
                  shape: shape,
                  color: color,
                  width: width,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PenShapePreview extends CustomPainter {
  final _PenShape shape;
  final Color color;
  final double width;
  _PenShapePreview(
      {required this.shape, required this.color, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.7,
        height: size.height * 0.6);
    switch (shape) {
      case _PenShape.circle:
        canvas.drawOval(rect, paint);
        break;
      case _PenShape.square:
        final side = rect.height;
        final square = Rect.fromCenter(
            center: rect.center, width: side, height: side);
        canvas.drawRect(square, paint);
        break;
      case _PenShape.rectangle:
        canvas.drawRect(rect, paint);
        break;
      case _PenShape.freehand:
        // Dalgalı serbest çizgi — elle çizimi temsil eder.
        final path = Path()..moveTo(rect.left, rect.center.dy);
        final step = rect.width / 6;
        for (int i = 0; i < 6; i++) {
          final x1 = rect.left + step * (i + 0.5);
          final y1 = rect.center.dy + (i % 2 == 0 ? -8.0 : 8.0);
          final x2 = rect.left + step * (i + 1);
          final y2 = rect.center.dy;
          path.quadraticBezierTo(x1, y1, x2, y2);
        }
        canvas.drawPath(path, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(_PenShapePreview old) =>
      old.shape != shape || old.color != color || old.width != width;
}
