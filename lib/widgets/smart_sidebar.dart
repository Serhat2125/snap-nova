import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  SmartSidebar
//
//  Davranış:
//  • Sağ kenarda ince, oval, zarif çubuk.
//  • Çubuğa dokun → drawer ekranın sağ kenarına yapışık açılır (boşluk yok).
//    Drawer'ın üst kenarı çubuğun Y konumundadır.
//  • Drawer'da sadece başlıklar küçük çerçeveler içinde; hiyerarşik.
//  • Drawer başlığına dokun → drawer kapanır, ORTA'da preview açılır.
//  • Preview:
//      - Biraz daha küçük, ortada, kenarları oval
//      - Header'dan tutup istediğin yere sürükle
//      - Üst ve alt kenarda küçük resize grip'leri (yüksekliği değiştirir)
//      - İçeriği TAM aktif (butonlar, paneller çalışır — yeni açılmış gibi)
//      - Sağ altta Tam Ekran butonu → normal Navigator push
// ═══════════════════════════════════════════════════════════════════════════

const double _barWidth = 14;
const double _barHeight = 62;

class SidebarItem {
  final String title;
  final WidgetBuilder? pageBuilder;
  final VoidCallback? openFullscreen;
  final List<SidebarItem> children;
  final Color color;

  const SidebarItem({
    required this.title,
    this.pageBuilder,
    this.openFullscreen,
    this.children = const [],
    this.color = const Color(0xFF2563EB),
  });
}

class SmartSidebar extends StatefulWidget {
  final List<SidebarItem> items;
  const SmartSidebar({super.key, this.items = const []});

  @override
  State<SmartSidebar> createState() => _SmartSidebarState();
}

class _SmartSidebarState extends State<SmartSidebar>
    with TickerProviderStateMixin {
  bool _drawerOpen = false;
  SidebarItem? _previewItem;
  double _edgeY = 250;

  // Preview konum/boyut
  Offset _previewOffset = Offset.zero;
  double _previewWidth = 0;
  double _previewHeight = 0;

  late final AnimationController _drawerCtrl;
  late final AnimationController _previewCtrl;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _previewCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    _previewCtrl.dispose();
    super.dispose();
  }

  void _toggleDrawer() {
    setState(() {
      _drawerOpen = !_drawerOpen;
    });
    _drawerOpen ? _drawerCtrl.forward(from: 0) : _drawerCtrl.reverse();
  }

  void _openPreview(SidebarItem item, Size screen) {
    // Her yeni preview açılışında boyut ve konum merkeze dönsün
    _previewWidth = (screen.width * 0.78).clamp(260.0, 440.0);
    _previewHeight = (screen.height * 0.55).clamp(320.0, 560.0);
    _previewOffset = Offset.zero;
    setState(() {
      _previewItem = item;
      _drawerOpen = false;
    });
    _drawerCtrl.reverse();
    _previewCtrl.forward(from: 0);
  }

  void _closePreview() {
    _previewCtrl.reverse();
    setState(() => _previewItem = null);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final padTop = MediaQuery.of(context).padding.top;
    final clampedY = _edgeY.
    clamp(padTop + 20, screen.height - _barHeight - 20);

    return Stack(
      children: [
        // 1. Preview penceresi — BACKDROP YOK; arka plan tam etkileşimli kalır.
        //    Preview sadece X butonuyla kapanır.
        if (_previewItem != null) _buildPreview(screen),

        // 2. Drawer — kenara yapışık
        if (_drawerOpen) _buildDrawer(screen, clampedY),

        // 3. Edge bar — her zaman en üstte
        _buildEdgeBar(screen, padTop, clampedY),
      ],
    );
  }

  // ── Edge bar (oval, zarif, küçük) ────────────────────────────────────────
  Widget _buildEdgeBar(Size screen, double padTop, double clampedY) {
    return Positioned(
      right: 0,
      top: clampedY,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleDrawer,
        onVerticalDragUpdate: (d) {
          setState(() => _edgeY += d.delta.dy);
        },
        onHorizontalDragEnd: (d) {
          if (!_drawerOpen && (d.primaryVelocity ?? 0) < -120) {
            _toggleDrawer();
          }
        },
        child: Container(
          width: _barWidth,
          height: _barHeight,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              bottomLeft: Radius.circular(14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(-1, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  // ── Drawer (kenara yapışık, oval) ────────────────────────────────────────
  Widget _buildDrawer(Size screen, double topY) {
    final w = (screen.width / 3.4).clamp(170.0, 290.0);
    final h = screen.height - topY - 12;
    return AnimatedBuilder(
      animation: _drawerCtrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_drawerCtrl.value);
        final off = (1 - t) * w;
        return Positioned(
          right: -off,
          top: topY,
          width: w,
          height: h,
          child: child!,
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(26),
            bottomLeft: Radius.circular(26),
          ),
          child: Container(
            color: const Color(0xFFE5E7EB), // açık gri arka plan
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 10, 14, 14),
              children: widget.items
                  .map((it) => _buildNode(it, 0, screen))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNode(SidebarItem item, int depth, Size screen) {
    final isLeaf = item.children.isEmpty;
    final fontSize = depth == 0 ? 12.5 : (depth == 1 ? 11.5 : 10.5);
    final fontWeight = depth == 0
        ? FontWeight.w800
        : (depth == 1 ? FontWeight.w600 : FontWeight.w500);
    final color = depth == 0
        ? Colors.black87
        : (depth == 1 ? Colors.grey.shade800 : Colors.grey.shade600);
    final indent = depth * 8.0;

    if (isLeaf) {
      return Padding(
        padding: EdgeInsets.fromLTRB(indent, 3, 0, 3),
        child: _frameTile(
          title: item.title,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          accent: item.color,
          onTap: () => _openPreview(item, screen),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 3, 0, 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _frameTile(
            title: item.title,
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
            accent: item.color,
            onTap: () => _openPreview(item, screen),
            showExpand: true,
          ),
          ...item.children.map((c) => _buildNode(c, depth + 1, screen)),
        ],
      ),
    );
  }

  Widget _frameTile({
    required String title,
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    required Color accent,
    required VoidCallback onTap,
    bool showExpand = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    color: color,
                    height: 1.2,
                  ),
                ),
              ),
              if (showExpand)
                Icon(Icons.unfold_more_rounded,
                    size: 11, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  // ── Preview penceresi (sürüklenebilir, resize'lanabilir) ─────────────────
  Widget _buildPreview(Size screen) {
    final item = _previewItem!;

    // Konum: ekran merkezi + offset
    final centerX = (screen.width - _previewWidth) / 2 + _previewOffset.dx;
    final centerY = (screen.height - _previewHeight) / 2 + _previewOffset.dy;

    // Ekran dışına taşmasın
    final left = centerX.clamp(-_previewWidth * 0.3,
        screen.width - _previewWidth * 0.7);
    final top = centerY.clamp(
        MediaQuery.of(context).padding.top,
        screen.height - _previewHeight + 80);

    return Positioned(
      left: left,
      top: top,
      width: _previewWidth,
      height: _previewHeight,
      child: AnimatedBuilder(
        animation: _previewCtrl,
        builder: (_, child) {
          final v = Curves.easeOutBack
              .transform(_previewCtrl.value.clamp(0.0, 1.0));
          return Transform.scale(
            scale: 0.92 + 0.08 * v,
            child: Opacity(opacity: _previewCtrl.value, child: child),
          );
        },
        child: Material(
          elevation: 20,
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _topResizeGrip(screen),
              _previewHeader(item),
              Expanded(
                child: ClipRect(
                  child: item.pageBuilder != null
                      ? Builder(builder: item.pageBuilder!)
                      : Center(
                          child: Text(
                            'İçerik yok',
                            style: GoogleFonts.poppins(
                                color: Colors.grey.shade500),
                          ),
                        ),
                ),
              ),
              _bottomBar(item),
              _bottomResizeGrip(screen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewHeader(SidebarItem item) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        setState(() => _previewOffset += d.delta);
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.fromLTRB(12, 0, 2, 0),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ),
            GestureDetector(
              onTap: _closePreview,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.close_rounded,
                    size: 16, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Üst kenarda küçük resize grip — dikey sürükleme yüksekliği değiştirir
  Widget _topResizeGrip(Size screen) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        setState(() {
          // Drag UP (negatif dy) → büyüt, DOWN → küçült
          _previewHeight =
              (_previewHeight - d.delta.dy).clamp(240.0, screen.height - 80);
          _previewOffset = Offset(_previewOffset.dx,
              _previewOffset.dy + d.delta.dy / 2);
        });
      },
      child: Container(
        height: 12,
        alignment: Alignment.center,
        child: Container(
          width: 30,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _bottomResizeGrip(Size screen) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        setState(() {
          _previewHeight =
              (_previewHeight + d.delta.dy).clamp(240.0, screen.height - 80);
          _previewOffset = Offset(_previewOffset.dx,
              _previewOffset.dy + d.delta.dy / 2);
        });
      },
      child: Container(
        height: 12,
        alignment: Alignment.center,
        child: Container(
          width: 30,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(SidebarItem item) {
    if (item.openFullscreen == null) return const SizedBox.shrink();
    return Container(
      height: 26,
      padding: const EdgeInsets.only(right: 6),
      alignment: Alignment.centerRight,
      color: Colors.white,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final cb = item.openFullscreen!;
          _closePreview();
          cb();
        },
        child: Container(
          width: 26,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(Icons.open_in_full_rounded,
              size: 12, color: item.color),
        ),
      ),
    );
  }
}
