// StudyToolbarOverlay — TAM REWRITE (v3).
//
// Tasarım: Yalnızca 3 buton — Renk Paleti · Kalem · X (Kapat).
// Önceki tüm mimari (Tooltip + AnimatedSwitcher + Material/InkWell + 5 buton
// kombinasyonu) silindi; yerine stock Flutter widget'ları (IconButton) ile
// minimum sade bir versiyon konuldu.
//
// Mimari:
//   Stack
//   ├─ Drawing layer (CustomPaint + GestureDetector pan)
//   ├─ Compact draggable trigger (yuvarlak buton — ilk durum)
//   ├─ 3-button vertical panel (trigger tıklanınca açılır)
//   ├─ Color panel (Renk butonu tıklanınca)
//   └─ Pen panel (Kalem butonu tıklanınca)
//
// Tüm tap handler'ları IconButton kullanır — Flutter'ın en güvenilir tap
// pattern'i, gesture arena'da çakışma yapmaz.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/error_logger.dart';
import '../services/runtime_translator.dart';
import 'note_creator_page.dart';

// ── Çizim modları ──────────────────────────────────────────────────────────
enum _DrawMode {
  off, // çizim yok
  highlight, // renkli vurgulayıcı (yatay parmak ile)
  highlightStraight, // düz yatay çizgi
  pen, // kalem çizimi
  eraser, // noktasal silme — parmağın bastığı yerdeki çizimleri siler
}

enum _PenShape { freehand, circle, square, rectangle }

// ── Sabit paletler ─────────────────────────────────────────────────────────
const List<Color> _highlightColors = [
  Color(0xFFFFEB3B), Color(0xFFFFC107), Color(0xFFFF9800), Color(0xFFFF5722),
  Color(0xFFEF4444), Color(0xFFEC4899), Color(0xFFA855F7), Color(0xFF7C3AED),
  Color(0xFF3B82F6), Color(0xFF06B6D4), Color(0xFF14B8A6), Color(0xFF22C55E),
  Color(0xFF84CC16), Color(0xFFEAB308), Color(0xFF78716C), Color(0xFF000000),
];

const List<Color> _penColors = [
  // 1. sıra — kırmızı, siyah, mavi, yeşil, turuncu, mor, pembe, kahverengi
  Color(0xFFEF4444), Color(0xFF000000), Color(0xFF3B82F6), Color(0xFF22C55E),
  Color(0xFFF59E0B), Color(0xFFA855F7), Color(0xFFEC4899), Color(0xFF92400E),
  // 2. sıra — cam göbeği, turkuaz, sarı, lime, magenta, indigo, koyu kırmızı, gri
  Color(0xFF06B6D4), Color(0xFF14B8A6), Color(0xFFEAB308), Color(0xFF84CC16),
  Color(0xFFD946EF), Color(0xFF6366F1), Color(0xFFDC2626), Color(0xFF6B7280),
];

const List<double> _penWidths = [2.0, 4.0, 7.0];

// ═══════════════════════════════════════════════════════════════════════════
//  StudyToolbarOverlay
// ═══════════════════════════════════════════════════════════════════════════
class StudyToolbarOverlay extends StatefulWidget {
  final String topicId;
  final String topicName;
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
  // ── State ───────────────────────────────────────────────────────────────
  _DrawMode _mode = _DrawMode.off;
  bool _expanded = false; // 3-button panel açık mı
  bool _colorPanelOpen = false;
  bool _penPanelOpen = false;

  Color _highlightColor = _highlightColors.first;
  Color _penColor = _penColors.first;
  double _penWidth = _penWidths[1];
  _PenShape _penShape = _PenShape.freehand;

  // Toolbar pozisyonu (sürüklenebilir)
  double? _toolbarLeft;
  double? _toolbarTop;

  // Strokes
  final List<_Stroke> _strokes = [];
  _Stroke? _current;
  bool _loaded = false;

  // Long-press ile çizim taşıma state'i.
  _Stroke? _movingStroke;
  Offset? _moveLastPos;

  // Çizim biter bitmez 3sn süreyle "uzun bas + sürükle" hint banner'ı.
  bool _showDragHint = false;
  Timer? _dragHintTimer;

  // Scroll tracking (sticky highlights)
  double _scrollOffset = 0;
  ScrollPosition? _scrollPosition;

  String get _strokeKey => 'strokes_${widget.topicId}';
  String get _posKey => 'toolbar_pos_${widget.topicId}';

  // ── Lifecycle ───────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadStrokes();
    _loadPos();
    _attachToController();
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
    if (widget.scrollController != null) return;
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _scrollPosition) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = pos;
      _scrollPosition?.addListener(_onScroll);
      if (pos != null) _scrollOffset = pos.pixels;
    }
  }

  void _attachToController() {
    final c = widget.scrollController;
    if (c == null) return;
    c.addListener(_onControllerScroll);
    if (c.hasClients) _scrollOffset = c.offset;
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
    _dragHintTimer?.cancel();
    super.dispose();
  }

  // ── Persistence ─────────────────────────────────────────────────────────
  Future<void> _loadStrokes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_strokeKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _strokes.addAll(list
            .map((e) => _Stroke.fromJson(e as Map<String, dynamic>))
            .toList());
      } catch (e, st) {
        ErrorLogger.instance.capture(e, st, context: 'study_toolbar');
      }
    }
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  Future<void> _persistStrokes() async {
    final prefs = await SharedPreferences.getInstance();
    if (_strokes.isEmpty) {
      await prefs.remove(_strokeKey);
    } else {
      await prefs.setString(
        _strokeKey,
        jsonEncode(_strokes.map((s) => s.toJson()).toList()),
      );
    }
  }

  Future<void> _loadPos() async {
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
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'study_toolbar_pos');
    }
  }

  Future<void> _savePos() async {
    if (_toolbarLeft == null || _toolbarTop == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _posKey,
      jsonEncode({'left': _toolbarLeft, 'top': _toolbarTop}),
    );
  }

  // ── Drawing handlers ────────────────────────────────────────────────────
  Offset _toContent(Offset screen) =>
      Offset(screen.dx, screen.dy + _scrollOffset);

  void _onPanStart(DragStartDetails d) {
    if (_mode == _DrawMode.off) return;
    Color color;
    double width;
    switch (_mode) {
      case _DrawMode.highlight:
      case _DrawMode.highlightStraight:
        color = _highlightColor.withValues(alpha: 0.40);
        width = 22;
        break;
      case _DrawMode.pen:
        color = _penColor.withValues(alpha: 0.95);
        width = _penWidth;
        break;
      case _DrawMode.eraser:
      case _DrawMode.off:
        return; // _onPanStart silgi modunda çağrılmaz; emniyetli early-return
    }
    setState(() {
      _current = _Stroke(
        color: color,
        width: width,
        points: [_toContent(d.localPosition)],
        shape: _mode == _DrawMode.pen ? _penShape : _PenShape.freehand,
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_current == null) return;
    final pt = _toContent(d.localPosition);
    final isShape = _current!.shape != _PenShape.freehand;
    if (isShape) {
      setState(() {
        if (_current!.points.length < 2) {
          _current!.points.add(pt);
        } else {
          _current!.points[1] = pt;
        }
      });
      return;
    }
    final p = _mode == _DrawMode.highlightStraight
        ? Offset(pt.dx, _current!.points.first.dy)
        : pt;
    setState(() => _current!.points.add(p));
  }

  void _onPanEnd(DragEndDetails _) {
    if (_current == null) return;
    setState(() {
      _strokes.add(_current!);
      _current = null;
      // Çizim bitti → 3sn boyunca hint banner'ı göster (kullanıcı
      // uzun-bas-taşı özelliğini keşfetsin).
      _showDragHint = true;
    });
    _dragHintTimer?.cancel();
    _dragHintTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showDragHint = false);
    });
    _persistStrokes();
  }

  // ── Long-press ile mevcut çizimi taşıma ────────────────────────────────
  // Kullanıcı bir şeklin/vurgunun ÜZERİNE basılı tutar (~500ms), sonra
  // parmağını kaydırır → şekil parmakla beraber hareket eder, bırakınca
  // yeni konumda kalır. Yatay scroll/normal çizim ile çakışmaz çünkü
  // long-press recognizer arenada ayrı kategori.

  void _onMoveStart(LongPressStartDetails d) {
    final pt = _toContent(d.localPosition);
    final hit = _findStrokeAt(pt);
    if (hit == null) return;
    setState(() {
      _movingStroke = hit;
      _moveLastPos = pt;
    });
  }

  void _onMoveUpdate(LongPressMoveUpdateDetails d) {
    final m = _movingStroke;
    final last = _moveLastPos;
    if (m == null || last == null) return;
    final pt = _toContent(d.localPosition);
    final delta = pt - last;
    if (delta == Offset.zero) return;
    setState(() {
      m.points = m.points.map((p) => p + delta).toList();
      _moveLastPos = pt;
    });
  }

  void _onMoveEnd(LongPressEndDetails _) {
    if (_movingStroke == null) return;
    _persistStrokes();
    setState(() {
      _movingStroke = null;
      _moveLastPos = null;
    });
  }

  /// Verilen NOKTAYA en yakın çizimi bul; bulamazsa null.
  /// Strokes ters sırada test edilir → üstteki (en son çizilen) öncelikli.
  /// Bounding-box + 20px tampon ile esnek hit.
  _Stroke? _findStrokeAt(Offset pt) {
    const padding = 20.0;
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final s = _strokes[i];
      final rect = _strokeBBox(s);
      if (rect.inflate(padding).contains(pt)) return s;
    }
    return null;
  }

  Rect _strokeBBox(_Stroke s) {
    if (s.points.isEmpty) return Rect.zero;
    double minX = s.points.first.dx, maxX = minX;
    double minY = s.points.first.dy, maxY = minY;
    for (final p in s.points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final screen = MediaQuery.of(context).size;
    final padTop = MediaQuery.of(context).padding.top;
    final drawing = _mode != _DrawMode.off;
    final left = _toolbarLeft ?? 8;
    final top = _toolbarTop ?? screen.height * 0.25;

    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── 1. Çizim katmanı ────────────────────────────────────────────
          // KRİTİK: drawing modu KAPALIYKEN IgnorePointer ile katman
          // tamamen şeffaf — sayfa scroll'u serbest.
          // SİLGİ modunda: onPan (her yön) — parmağı kaydırınca sürekli sil.
          // ÇİZİM modunda: onHorizontalDrag — yalnız yatay, vertical scroll'u
          // bozmaz (kullanıcı zaten drawing modunda olduğu için aktif).
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !drawing,
              child: _mode == _DrawMode.eraser
                  ? GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (d) => _eraseAt(d.localPosition),
                      onPanUpdate: (d) => _eraseAt(d.localPosition),
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _StrokePainter(
                          strokes: _strokes,
                          current: _current,
                          scrollOffset: _scrollOffset,
                          highlight: _movingStroke,
                        ),
                      ),
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: _onPanStart,
                      onHorizontalDragUpdate: _onPanUpdate,
                      onHorizontalDragEnd: _onPanEnd,
                      onLongPressStart: _onMoveStart,
                      onLongPressMoveUpdate: _onMoveUpdate,
                      onLongPressEnd: _onMoveEnd,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _StrokePainter(
                          strokes: _strokes,
                          current: _current,
                          scrollOffset: _scrollOffset,
                          highlight: _movingStroke,
                        ),
                      ),
                    ),
            ),
          ),
          // Drawing modu KAPALIYKEN paint katmanı (sadece görsel, hit'siz).
          if (!drawing)
            Positioned.fill(
              child: IgnorePointer(
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

          // ── 2. Toolbar (collapsed/expanded) ─────────────────────────────
          Positioned(
            left: left,
            top: top,
            child: _expanded
                ? _ExpandedToolbar(
                    penColor: _penColor,
                    colorActive: _colorPanelOpen ||
                        _mode == _DrawMode.highlight ||
                        _mode == _DrawMode.highlightStraight,
                    penActive: _penPanelOpen || _mode == _DrawMode.pen,
                    onNote: _onNoteTap,
                    onColor: _onColorTap,
                    onPen: _onPenTap,
                    onErase: _onEraseTap,
                    onClose: _onCloseTap,
                  )
                : _CollapsedTrigger(
                    eraseActive: _mode == _DrawMode.eraser,
                    onTap: () {
                      debugPrint('[toolbar] Collapsed → Expanded');
                      setState(() => _expanded = true);
                    },
                    onDrag: (dx, dy) {
                      const btn = 50.0;
                      final maxLeft = screen.width - btn - 4;
                      final maxTop = screen.height -
                          btn -
                          MediaQuery.of(context).padding.bottom -
                          16;
                      setState(() {
                        _toolbarLeft =
                            ((_toolbarLeft ?? left) + dx).clamp(4.0, maxLeft);
                        _toolbarTop = ((_toolbarTop ?? top) + dy)
                            .clamp(padTop + 4, maxTop);
                      });
                    },
                    onDragEnd: _savePos,
                  ),
          ),

          // ── 3. Renk paneli (sağ üst) ────────────────────────────────────
          // Y konumu: sticky section header (~36px) altında kalsın → 50px.
          // Aksi takdirde özet sayfasındaki "şu anda hangi bölümde" pill ile
          // panel çakışıyor.
          if (_colorPanelOpen)
            Positioned(
              right: 8,
              top: padTop + 50,
              child: _ColorPanel(
                selected: _highlightColor,
                onPick: (c, straight) {
                  debugPrint('[toolbar] Renk seçildi: $c, straight=$straight');
                  setState(() {
                    _highlightColor = c;
                    _mode = straight
                        ? _DrawMode.highlightStraight
                        : _DrawMode.highlight;
                    // Panel açık kalır; kullanıcı renk değiştirmek isteyebilir
                  });
                },
                onClose: () {
                  debugPrint('[toolbar] Renk paneli X tıklandı');
                  setState(() {
                    _colorPanelOpen = false;
                    if (_mode == _DrawMode.highlight ||
                        _mode == _DrawMode.highlightStraight) {
                      _mode = _DrawMode.off;
                    }
                  });
                },
              ),
            ),

          // ── 4. Kalem paneli (yatayda tam: left+right) ───────────────────
          // Y konumu: sticky section header (~36px) altında kalsın → 50px.
          if (_penPanelOpen)
            Positioned(
              left: 8,
              right: 8,
              top: padTop + 50,
              child: _PenPanel(
                selectedColor: _penColor,
                selectedWidth: _penWidth,
                onStart: (c, w, shape) {
                  debugPrint('[toolbar] Kalem başla: $c, $w, $shape');
                  setState(() {
                    _penColor = c;
                    _penWidth = w;
                    _penShape = shape;
                    _mode = _DrawMode.pen;
                  });
                },
                onClose: () {
                  debugPrint('[toolbar] Kalem paneli X tıklandı');
                  setState(() {
                    _penPanelOpen = false;
                    if (_mode == _DrawMode.pen) _mode = _DrawMode.off;
                  });
                },
              ),
            ),

          // ── 5. Sürükle ipucu banner'ı — çizimden sonra 3sn gösterilir ──
          // Kullanıcıya uzun-bas-taşı özelliğini hatırlatır. Sticky header
          // altında kalsın → 54px (panellerden 4px sonra ki üst üste binmesin).
          if (_showDragHint)
            Positioned(
              top: padTop + 54,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _showDragHint ? 1 : 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.pan_tool_rounded,
                            size: 14,
                            color: Color(0xFFFBBF24),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Şekli taşımak için uzun bas + sürükle'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.2,
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
    );
  }

  // ── Button callbacks ────────────────────────────────────────────────────
  // KULLANICI DAVRANIŞI: Not/Renk/Kalem butonuna basıldığında alt sekme açılır
  // ve expanded toolbar OTOMATIK kapanır → yalnız floating trigger görünür kalır.
  // Sub-panel'in kendi X'iyle kapatılması da net olur; üstte 5'li toolbar artık
  // ekranı tıkamaz.
  void _onNoteTap() {
    debugPrint('[toolbar] Not Sayfası butonu tıklandı');
    setState(() => _expanded = false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteCreatorPage(
          topicId: widget.topicId,
          topicName: widget.topicName,
        ),
      ),
    );
  }

  void _onColorTap() {
    debugPrint('[toolbar] Renk butonu tıklandı');
    setState(() {
      _colorPanelOpen = !_colorPanelOpen;
      if (_colorPanelOpen) {
        _penPanelOpen = false;
        _expanded = false; // toolbar kapansın, panel görünür kalsın
      }
    });
  }

  void _onPenTap() {
    debugPrint('[toolbar] Kalem butonu tıklandı');
    setState(() {
      _penPanelOpen = !_penPanelOpen;
      if (_penPanelOpen) {
        _colorPanelOpen = false;
        _expanded = false;
      }
    });
  }

  void _onEraseTap() {
    debugPrint('[toolbar] Silgi butonu tıklandı (noktasal silme moduna geç)');
    setState(() {
      // Toggle: zaten silgi modundaysa kapat, değilse aç.
      _mode = _mode == _DrawMode.eraser ? _DrawMode.off : _DrawMode.eraser;
      _colorPanelOpen = false;
      _penPanelOpen = false;
      _expanded = false; // floating trigger'a düş — kullanıcı silmeye odaklansın
    });
  }

  /// Parmak konumuna [radius] içinde değen tüm çizimleri sil.
  /// Drag boyunca tekrar tekrar çağrılır.
  /// - Freehand çizim (vurgu + serbest kalem): nokta yakınlığı.
  /// - Pen şekilleri (yuvarlak/kare/dikdörtgen): şeklin BOUNDING BOX'ına
  ///   parmak değdiğinde silinir — şeklin ortasına basınca da çalışır.
  void _eraseAt(Offset screenPt) {
    const radius = 24.0;
    final radiusSq = radius * radius;
    final pt = _toContent(screenPt);
    bool removed = false;
    _strokes.removeWhere((s) {
      // Şekil-tabanlı (2 anchor point): bounding box hit test.
      if (s.shape != _PenShape.freehand && s.points.length >= 2) {
        final a = s.points.first;
        final b = s.points.last;
        final rect = Rect.fromPoints(a, b).inflate(radius);
        if (rect.contains(pt)) {
          removed = true;
          return true;
        }
        return false;
      }
      // Freehand / vurgu: nokta yakınlığı.
      for (final p in s.points) {
        final dx = p.dx - pt.dx;
        final dy = p.dy - pt.dy;
        if (dx * dx + dy * dy <= radiusSq) {
          removed = true;
          return true;
        }
      }
      return false;
    });
    if (removed) {
      setState(() {});
      _persistStrokes();
    }
  }

  void _onCloseTap() {
    debugPrint('[toolbar] X butonu tıklandı');
    setState(() {
      _mode = _DrawMode.off;
      _expanded = false;
      _colorPanelOpen = false;
      _penPanelOpen = false;
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _CollapsedTrigger — tek yuvarlak buton, sürüklenebilir
// ═══════════════════════════════════════════════════════════════════════════
class _CollapsedTrigger extends StatelessWidget {
  final VoidCallback onTap;
  final void Function(double dx, double dy) onDrag;
  final VoidCallback onDragEnd;
  /// Silgi modu aktifken trigger ikon ve rengini değiştir — kullanıcı
  /// hangi modda olduğunu net görsün.
  final bool eraseActive;

  const _CollapsedTrigger({
    required this.onTap,
    required this.onDrag,
    required this.onDragEnd,
    this.eraseActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = eraseActive
        ? const LinearGradient(
            colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final shadowColor = eraseActive
        ? const Color(0xFF3B82F6)
        : const Color(0xFF7C3AED);
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (d) => onDrag(d.delta.dx, d.delta.dy),
      onPanEnd: (_) => onDragEnd(),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.40),
              blurRadius: 16,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          eraseActive
              ? Icons.cleaning_services_rounded
              : Icons.edit_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _ExpandedToolbar — 3 buton dikey (Renk · Kalem · X)
//  IconButton kullanır — Flutter'ın en güvenilir tap pattern'i.
// ═══════════════════════════════════════════════════════════════════════════
class _ExpandedToolbar extends StatelessWidget {
  final Color penColor;
  final bool colorActive;
  final bool penActive;
  final VoidCallback onNote;
  final VoidCallback onColor;
  final VoidCallback onPen;
  final VoidCallback onErase;
  final VoidCallback onClose;

  const _ExpandedToolbar({
    required this.penColor,
    required this.colorActive,
    required this.penActive,
    required this.onNote,
    required this.onColor,
    required this.onPen,
    required this.onErase,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // Material wrapper: IconButton'un ripple efekti için gerekli.
      // Type.transparency: Material kendi yüzey rengini eklemez, alttaki
      // siyah Container görünür kalır.
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
          children: [
            // ── Not Sayfası butonu (en üstte) ──────────────────────────
            IconButton(
              onPressed: onNote,
              icon: const Icon(
                Icons.menu_book_rounded,
                color: Color(0xFFA855F7),
              ),
              tooltip: 'Not Sayfası'.tr(),
              splashRadius: 22,
              iconSize: 22,
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            _div(),
            // ── Renk paleti butonu ─────────────────────────────────────
            IconButton(
              onPressed: onColor,
              icon: Icon(
                Icons.palette_rounded,
                color: colorActive
                    ? const Color(0xFFEC4899)
                    : const Color(0xFFEC4899).withValues(alpha: 0.85),
              ),
              tooltip: 'Renk Paleti'.tr(),
              splashRadius: 22,
              iconSize: 22,
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            _div(),
            // ── Kalem butonu ───────────────────────────────────────────
            IconButton(
              onPressed: onPen,
              icon: Icon(
                Icons.create_rounded,
                color: penColor,
              ),
              tooltip: 'Kalem'.tr(),
              splashRadius: 22,
              iconSize: 22,
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            _div(),
            // ── Silgi (tümünü sil) butonu ──────────────────────────────
            IconButton(
              onPressed: onErase,
              icon: const Icon(
                Icons.cleaning_services_rounded,
                color: Color(0xFF60A5FA),
              ),
              tooltip: 'Tümünü Sil'.tr(),
              splashRadius: 22,
              iconSize: 22,
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            _div(),
            // ── X (kapat) butonu ───────────────────────────────────────
            IconButton(
              onPressed: onClose,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
              ),
              tooltip: 'Kapat'.tr(),
              splashRadius: 22,
              iconSize: 22,
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
    );
  }

  Widget _div() => Container(
        width: 22,
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: Colors.white.withValues(alpha: 0.10),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  _ColorPanel — 16 renk (4x4 wrap) + Düz/Serbest mod butonları + X
// ═══════════════════════════════════════════════════════════════════════════
class _ColorPanel extends StatefulWidget {
  final Color selected;
  final void Function(Color color, bool straight) onPick;
  final VoidCallback onClose;
  const _ColorPanel({
    required this.selected,
    required this.onPick,
    required this.onClose,
  });

  @override
  State<_ColorPanel> createState() => _ColorPanelState();
}

class _ColorPanelState extends State<_ColorPanel> {
  late Color _tmp;

  @override
  void initState() {
    super.initState();
    _tmp = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    // 16 renk → 2 yatay sıra × 8 sütun. Her dot 28px + 4px spacing.
    final row1 = _highlightColors.take(8).toList();
    final row2 = _highlightColors.skip(8).take(8).toList();
    // KRİTİK: Sabit width — Expanded kullanma! Positioned parent unbounded
    // constraint veriyor; Expanded içeride patlıyordu (Renk paneli açılmama
    // sebebi). 28×8 + 4×7 = 252 dots + 4 padL + 28 X + 4 padR ≈ 288.
    const double w = 296;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: w,
        // Üst padding 6 → 4: yönerge yazısıyla çerçeve üstü arasında bolşuk
        // çok az olsun. Alt padding 10 → 6: thin mod butonlarıyla daha kompakt.
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
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
            // Yönerge + X aynı satırda — dikeyde tasarruf, çerçeve üstüyle
            // metin arası neredeyse hiç bolşuk yok.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Bir renk seç, satırı parmağınla kaydır'.tr(),
                      maxLines: 2,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.82),
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 13),
                    splashRadius: 12,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 2 sıra × 8 sütun renk
            _rowOfDots(row1),
            const SizedBox(height: 6),
            _rowOfDots(row2),
            const SizedBox(height: 6),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 6),
            // İnce mod butonları — Serbest / Düz Çizgi (tek satır, kompakt)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: (w - 14 - 8) / 2,
                    child: _modeBtn(
                        'Serbest', Icons.gesture_rounded, false)),
                const SizedBox(width: 8),
                SizedBox(
                  width: (w - 14 - 8) / 2,
                  child: _modeBtn(
                      'Düz Çizgi', Icons.horizontal_rule_rounded, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowOfDots(List<Color> colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < colors.length; i++) ...[
          _dot(colors[i], colors[i].toARGB32() == _tmp.toARGB32(),
              () => setState(() => _tmp = colors[i])),
          if (i < colors.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _dot(Color c, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          border: Border.all(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.25),
            width: active ? 2.4 : 1.2,
          ),
          boxShadow: active
              ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)]
              : null,
        ),
      ),
    );
  }

  Widget _modeBtn(String label, IconData icon, bool straight) {
    // Yatay layout — Column yerine Row. Yükseklik ~38 → ~26 px,
    // panel toplamı azalır, arka plandaki not içeriği daha çok görünür.
    return InkWell(
      onTap: () => widget.onPick(_tmp, straight),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: _tmp.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _tmp.withValues(alpha: 0.55), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _tmp, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _PenPanel — 8 renk + 3 kalınlık + Çizmeye Başla + X
// ═══════════════════════════════════════════════════════════════════════════
class _PenPanel extends StatefulWidget {
  final Color selectedColor;
  final double selectedWidth;
  final void Function(Color color, double width, _PenShape shape) onStart;
  final VoidCallback onClose;
  const _PenPanel({
    required this.selectedColor,
    required this.selectedWidth,
    required this.onStart,
    required this.onClose,
  });

  @override
  State<_PenPanel> createState() => _PenPanelState();
}

class _PenPanelState extends State<_PenPanel> {
  late Color _tmpColor;
  late double _tmpWidth;
  // "Çizmeye Başla"'ya basıldığında inline 3 şekil tab'ı açılır.
  bool _showShapeTabs = false;

  @override
  void initState() {
    super.initState();
    _tmpColor = widget.selectedColor;
    _tmpWidth = widget.selectedWidth;
  }

  @override
  Widget build(BuildContext context) {
    // 16 renk → 2 sıra × 8 sütun.
    final row1 = _penColors.take(8).toList();
    final row2 = _penColors.skip(8).take(8).toList();
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
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
            // X sağ üstte
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 14),
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
            // ┌─────────────────────┬──────────────┐
            // │  16 renk (2×8)      │ İnce         │
            // │                     │ Orta         │
            // │                     │ Kalın        │
            // └─────────────────────┴──────────────┘
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // SOL: 16 renk 2 sıra × 8 sütun (Expanded ile esnek)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _penRowOfDots(row1),
                      const SizedBox(height: 6),
                      _penRowOfDots(row2),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Dikey ayırıcı
                Container(
                  width: 1,
                  height: 78,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                const SizedBox(width: 8),
                // SAĞ: 3 kalınlık dikey (İnce > Orta > Kalın)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _wBtn(_penWidths[0], 'İnce'),
                    const SizedBox(height: 4),
                    _wBtn(_penWidths[1], 'Orta'),
                    const SizedBox(height: 4),
                    _wBtn(_penWidths[2], 'Kalın'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
                height: 1, color: Colors.white.withValues(alpha: 0.12)),
            const SizedBox(height: 8),
            // Çizmeye Başla — tam genişlik. Tıklayınca aşağıda 3 şekil tab'ı açılır.
            InkWell(
              onTap: () =>
                  setState(() => _showShapeTabs = !_showShapeTabs),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_tmpColor, _tmpColor.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Çizmeye Başla'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _showShapeTabs
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            // ── 3 ince şekil tab'ı (Yuvarlak / Dikdörtgen / Serbest) ──
            // "Çizmeye Başla"'ya basıldığında inline expand olur.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: _showShapeTabs
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _shapeTab(_PenShape.circle, 'Yuvarlak',
                                Icons.circle_outlined),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _shapeTab(_PenShape.rectangle, 'Dikdörtgen',
                                Icons.crop_din_rounded),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _shapeTab(_PenShape.freehand, 'Serbest',
                                Icons.gesture_rounded),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// İnce, zarif şekil tab'ı — tıklayınca o şekilde çizim modunu aktive eder.
  Widget _shapeTab(_PenShape shape, String label, IconData icon) {
    return InkWell(
      onTap: () => widget.onStart(_tmpColor, _tmpWidth, shape),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _tmpColor.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: _tmpColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _penRowOfDots(List<Color> colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < colors.length; i++) ...[
          _penDot(colors[i]),
          if (i < colors.length - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }

  Widget _penDot(Color c) {
    final active = c.toARGB32() == _tmpColor.toARGB32();
    // Dot 28 → 22: 8 dots + 7 spacing'ler ile thickness column'a yer kalsın.
    return InkWell(
      onTap: () => setState(() => _tmpColor = c),
      customBorder: const CircleBorder(),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c,
          border: Border.all(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.25),
            width: active ? 2.2 : 1.0,
          ),
          boxShadow: active
              ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }

  Widget _wBtn(double w, String label) {
    final active = w == _tmpWidth;
    final previewHeight = w <= 2 ? 3.0 : (w <= 4 ? 6.0 : 11.0);
    // 70 → 62: thickness column daha kompakt, sol kolona ekstra alan kalır.
    return InkWell(
      onTap: () => setState(() => _tmpWidth = w),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: active
              ? _tmpColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? _tmpColor : Colors.white.withValues(alpha: 0.10),
            width: active ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              child: Text(
                label.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: active ? _tmpColor : Colors.white70,
                ),
              ),
            ),
            const SizedBox(width: 3),
            // Kalınlık önizleme — yatay bar (16 → genişlik 16)
            Container(
              height: previewHeight,
              width: 16,
              decoration: BoxDecoration(
                color: _tmpColor,
                borderRadius: BorderRadius.circular(previewHeight / 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Stroke model + painter
// ═══════════════════════════════════════════════════════════════════════════
class _Stroke {
  Color color;
  double width;
  List<Offset> points;
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
            ? _PenShape.values[
                (j['s'] as num).toInt().clamp(0, _PenShape.values.length - 1)]
            : _PenShape.freehand,
      );
}

class _StrokePainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? current;
  final double scrollOffset;
  /// Long-press ile taşınmakta olan çizim — etrafına kesik çerçeve çizilir.
  final _Stroke? highlight;
  _StrokePainter({
    required this.strokes,
    this.current,
    this.scrollOffset = 0,
    this.highlight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(0, -scrollOffset);
    void draw(_Stroke s) {
      if (s.points.isEmpty) return;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.shape != _PenShape.freehand && s.points.length >= 2) {
        final a = s.points.first;
        final b = s.points.last;
        switch (s.shape) {
          case _PenShape.circle:
            canvas.drawOval(Rect.fromPoints(a, b), paint);
            return;
          case _PenShape.square:
            final dx = b.dx - a.dx;
            final dy = b.dy - a.dy;
            final side = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
            final sx = dx >= 0 ? a.dx : a.dx - side;
            final sy = dy >= 0 ? a.dy : a.dy - side;
            canvas.drawRect(Rect.fromLTWH(sx, sy, side, side), paint);
            return;
          case _PenShape.rectangle:
            canvas.drawRect(Rect.fromPoints(a, b), paint);
            return;
          case _PenShape.freehand:
            break;
        }
      }
      if (s.points.length < 2) {
        if (s.points.length == 1) {
          canvas.drawCircle(
              s.points.first, s.width / 2, Paint()..color = s.color);
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
      draw(s);
    }
    if (current != null) draw(current!);

    // Taşınan çizimi belirginleştir — bounding-box etrafına kesik kontur.
    final h = highlight;
    if (h != null && h.points.isNotEmpty) {
      double minX = h.points.first.dx, maxX = minX;
      double minY = h.points.first.dy, maxY = minY;
      for (final p in h.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      final rect = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(8);
      final dashPaint = Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.85)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        dashPaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}
