// LiveBgPicker — Karşılıklı konuşma (LiveAnalysis) ekranı için WhatsApp
// tarzı arka plan seçici. 3 hedef bağımsız temalanır:
//   • Ekran arka planı  (screen)
//   • Benim balonum      (mine)
//   • Qualsar çerçevesi  (frame)
//
// Her hedef DÜZ RENK ya da DESENLİ (çizgili/noktalı/kareli/çiçekli/cyber/
// dalga) bir model olabilir. Seçim `LiveBgOption.id` ile prefs'e yazılır,
// açılışta geri yüklenir. Painter'lar note_creator_page ile aynı görsel
// dilde ama bağımsız (kopya) — o dosyanın private sınıflarına bağımlılık yok.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/runtime_translator.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Model
// ═══════════════════════════════════════════════════════════════════════════
enum LiveBgPattern {
  lined,
  dot,
  grid,
  flower,
  cyber,
  wave,
  // Kızlara hitap eden pastel/tatlı desenler
  hearts,
  stars,
  bubbles,
  confetti,
  butterfly,
  rainbow,
}

/// Tek bir arka plan seçeneği: düz renk / gradyan (+ opsiyonel desen).
class LiveBgOption {
  final String id;
  final Color bg;
  /// Opsiyonel gradyan zemin — set edilirse `bg` yerine kullanılır (desenler
  /// için daha zengin/iddialı taban). `bg` yine temsil rengi (fg hesabı için).
  final Gradient? gradient;
  final LiveBgPattern? pattern;
  const LiveBgOption({
    required this.id,
    required this.bg,
    this.gradient,
    this.pattern,
  });

  /// Bu zemin üzerinde okunur metin tonu (luminance eşiği).
  Color get fg => _isDark(bg) ? Colors.white : Colors.black87;

  static bool _isDark(Color c) =>
      (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) < 0.55;

  /// id → seçenek (prefs restore). Bulunamazsa null.
  static LiveBgOption? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final o in kLiveBgColors) {
      if (o.id == id) return o;
    }
    for (final o in kLiveWallpapers) {
      if (o.id == id) return o;
    }
    return null;
  }
}

// Renk paleti — pastel/girly tonlar + klasik doygun renkler.
const List<LiveBgOption> kLiveBgColors = [
  // ── Pastel / kızlara hitap eden yumuşak tonlar ──────────────────────────
  LiveBgOption(id: 'c_blush', bg: Color(0xFFFFD1DC)),   // pudra pembe
  LiveBgOption(id: 'c_rose', bg: Color(0xFFF9A8D4)),    // gül pembe
  LiveBgOption(id: 'c_lilac', bg: Color(0xFFDCC7FF)),   // leylak
  LiveBgOption(id: 'c_lavender', bg: Color(0xFFC4B5FD)),// lavanta
  LiveBgOption(id: 'c_peach', bg: Color(0xFFFFD8B1)),   // şeftali
  LiveBgOption(id: 'c_mint', bg: Color(0xFFB8F0D8)),    // nane
  LiveBgOption(id: 'c_babyblue', bg: Color(0xFFBAE1FF)),// bebek mavisi
  LiveBgOption(id: 'c_coral', bg: Color(0xFFFFB3A7)),   // mercan
  // ── Klasik doygun renkler ────────────────────────────────────────────────
  LiveBgOption(id: 'c_white', bg: Color(0xFFFFFFFF)),
  LiveBgOption(id: 'c_cream', bg: Color(0xFFFFF8E1)),
  LiveBgOption(id: 'c_yellow', bg: Color(0xFFFFEB3B)),
  LiveBgOption(id: 'c_amber', bg: Color(0xFFFFC107)),
  LiveBgOption(id: 'c_orange', bg: Color(0xFFFF9800)),
  LiveBgOption(id: 'c_dorange', bg: Color(0xFFFF5722)),
  LiveBgOption(id: 'c_red', bg: Color(0xFFEF4444)),
  LiveBgOption(id: 'c_pink', bg: Color(0xFFEC4899)),
  LiveBgOption(id: 'c_purple', bg: Color(0xFFA855F7)),
  LiveBgOption(id: 'c_dpurple', bg: Color(0xFF7C3AED)),
  LiveBgOption(id: 'c_blue', bg: Color(0xFF3B82F6)),
  LiveBgOption(id: 'c_cyan', bg: Color(0xFF06B6D4)),
  LiveBgOption(id: 'c_teal', bg: Color(0xFF14B8A6)),
  LiveBgOption(id: 'c_green', bg: Color(0xFF22C55E)),
  LiveBgOption(id: 'c_lime', bg: Color(0xFF84CC16)),
  LiveBgOption(id: 'c_mustard', bg: Color(0xFFEAB308)),
  LiveBgOption(id: 'c_gray', bg: Color(0xFF78716C)),
  LiveBgOption(id: 'c_black', bg: Color(0xFF000000)),
];

// 12 desenli model — her biri FARKLI renk kimliği + gradyan taban + belirgin
// motif. Yazışma çerçevesinin İÇİNDE render edilir.
const List<LiveBgOption> kLiveBgPatterns = [
  // 1) Defter — sıcak krem, mavi çizgiler
  LiveBgOption(
    id: 'p_lined',
    bg: Color(0xFFFFFCEF),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFFDF5), Color(0xFFFFF3D6)],
    ),
    pattern: LiveBgPattern.lined,
  ),
  // 2) Kraft — bej/kahve noktalar
  LiveBgOption(
    id: 'p_dot',
    bg: Color(0xFFEFE0C9),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF4E7D3), Color(0xFFE7D3B3)],
    ),
    pattern: LiveBgPattern.dot,
  ),
  // 3) Teknik çizim — koyu mavi blueprint
  LiveBgOption(
    id: 'p_grid',
    bg: Color(0xFF1E3A8A),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
    ),
    pattern: LiveBgPattern.grid,
  ),
  // 4) Çiçek bahçesi — canlı pembe
  LiveBgOption(
    id: 'p_flower',
    bg: Color(0xFFFBAFCF),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFE0EF), Color(0xFFFAA7C9)],
    ),
    pattern: LiveBgPattern.flower,
  ),
  // 5) Cyber — neon mor/lacivert
  LiveBgOption(
    id: 'p_cyber',
    bg: Color(0xFF0A0E27),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0A0E27), Color(0xFF3B0764)],
    ),
    pattern: LiveBgPattern.cyber,
  ),
  // 6) Okyanus — turkuaz dalga
  LiveBgOption(
    id: 'p_wave',
    bg: Color(0xFF5EEAD4),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFA7F3D0), Color(0xFF22D3EE)],
    ),
    pattern: LiveBgPattern.wave,
  ),
  // ── Pastel / tatlı (kızlar için) ──────────────────────────────────────────
  // 7) Kalpler — sıcak fuşya
  LiveBgOption(
    id: 'p_hearts',
    bg: Color(0xFFFB93C5),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFD9E8), Color(0xFFF986BC)],
    ),
    pattern: LiveBgPattern.hearts,
  ),
  // 8) Galaksi — gece indigo + altın yıldız
  LiveBgOption(
    id: 'p_stars',
    bg: Color(0xFF312E81),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3730A3), Color(0xFF7C3AED)],
    ),
    pattern: LiveBgPattern.stars,
  ),
  // 9) Baloncuklar — nane/turkuaz
  LiveBgOption(
    id: 'p_bubbles',
    bg: Color(0xFF99F6E4),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFCCFBF1), Color(0xFF7DD3FC)],
    ),
    pattern: LiveBgPattern.bubbles,
  ),
  // 10) Konfeti — canlı lila taban
  LiveBgOption(
    id: 'p_confetti',
    bg: Color(0xFFDDD6FE),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEDE9FE), Color(0xFFC7B6FD)],
    ),
    pattern: LiveBgPattern.confetti,
  ),
  // 11) Kelebekler — lavanta→pembe
  LiveBgOption(
    id: 'p_butterfly',
    bg: Color(0xFFE9C7F5),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEDE9FE), Color(0xFFF9A8D4)],
    ),
    pattern: LiveBgPattern.butterfly,
  ),
  // 12) Gökkuşağı — canlı pastel şeritler
  LiveBgOption(
    id: 'p_rainbow',
    bg: Color(0xFFFDE68A),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFF7ED), Color(0xFFFFE4E6)],
    ),
    pattern: LiveBgPattern.rainbow,
  ),
];

// ── Gradyan duvar kağıtları (desensiz, WhatsApp mesh/holografik tarzı) ───────
// Çok renkli akışkan gradyanlar — her biri benzersiz renk kimliği.
const List<LiveBgOption> kLiveGradientWalls = [
  LiveBgOption(
    id: 'w_holo',
    bg: Color(0xFFC084FC),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFA5B4FC), Color(0xFFF0ABFC), Color(0xFF93C5FD)],
    ),
  ),
  LiveBgOption(
    id: 'w_sunset',
    bg: Color(0xFFFB7185),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFEC89A), Color(0xFFFB7185), Color(0xFF9333EA)],
    ),
  ),
  LiveBgOption(
    id: 'w_ocean',
    bg: Color(0xFF38BDF8),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF67E8F9), Color(0xFF3B82F6), Color(0xFF312E81)],
    ),
  ),
  LiveBgOption(
    id: 'w_aurora',
    bg: Color(0xFF34D399),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6EE7B7), Color(0xFF22D3EE), Color(0xFF818CF8)],
    ),
  ),
  LiveBgOption(
    id: 'w_peach',
    bg: Color(0xFFFDA4AF),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFED7AA), Color(0xFFFDA4AF)],
    ),
  ),
  LiveBgOption(
    id: 'w_lavender',
    bg: Color(0xFFC4B5FD),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFDDD6FE), Color(0xFFF5D0FE)],
    ),
  ),
  LiveBgOption(
    id: 'w_night',
    bg: Color(0xFF1E293B),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF334155), Color(0xFF0F172A)],
    ),
  ),
  LiveBgOption(
    id: 'w_candy',
    bg: Color(0xFFF9A8D4),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFBCFE8), Color(0xFFDDD6FE), Color(0xFFA7F3D0)],
    ),
  ),
  LiveBgOption(
    id: 'w_gold',
    bg: Color(0xFFFBBF24),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFDE68A), Color(0xFFFBBF24), Color(0xFFF472B6)],
    ),
  ),
  LiveBgOption(
    id: 'w_forest',
    bg: Color(0xFF10B981),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6EE7B7), Color(0xFF059669), Color(0xFF065F46)],
    ),
  ),
  LiveBgOption(
    id: 'w_rose',
    bg: Color(0xFFF472B6),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFECDD3), Color(0xFFF472B6), Color(0xFFBE185D)],
    ),
  ),
  LiveBgOption(
    id: 'w_sky',
    bg: Color(0xFF60A5FA),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFBAE6FD), Color(0xFF60A5FA)],
    ),
  ),
];

// Tüm duvar kağıtları — gradyanlar + desenler (≥15 benzersiz).
final List<LiveBgOption> kLiveWallpapers = [
  ...kLiveGradientWalls,
  ...kLiveBgPatterns,
];

// ═══════════════════════════════════════════════════════════════════════════
//  Hazır temalar — duvar kağıdı + balon rengi birlikte (WhatsApp "Temalar").
// ═══════════════════════════════════════════════════════════════════════════
class LiveTheme {
  final String id;
  final String name;
  final LiveBgOption? wall;   // duvar kağıdı (çerçeve); null = sade
  final LiveBgOption? bubble; // sohbet balonu rengi; null = varsayılan
  const LiveTheme({
    required this.id,
    required this.name,
    this.wall,
    this.bubble,
  });
}

LiveTheme _mkTheme(String id, String name, String? wallId, String? bubId) =>
    LiveTheme(
      id: id,
      name: name,
      wall: LiveBgOption.byId(wallId),
      bubble: LiveBgOption.byId(bubId),
    );

final List<LiveTheme> kLiveThemes = [
  const LiveTheme(id: 't_default', name: 'Varsayılan'),
  _mkTheme('t_holo', 'Holografik', 'w_holo', 'c_dpurple'),
  _mkTheme('t_sunset', 'Gün Batımı', 'w_sunset', 'c_coral'),
  _mkTheme('t_ocean', 'Okyanus', 'w_ocean', 'c_blue'),
  _mkTheme('t_candy', 'Şeker', 'w_candy', 'c_purple'),
  _mkTheme('t_hearts', 'Kalpler', 'p_hearts', 'c_rose'),
  _mkTheme('t_galaxy', 'Galaksi', 'p_stars', 'c_lavender'),
  _mkTheme('t_flower', 'Çiçek', 'p_flower', 'c_purple'),
  _mkTheme('t_butterfly', 'Kelebek', 'p_butterfly', 'c_dpurple'),
  _mkTheme('t_rose', 'Gül', 'w_rose', 'c_rose'),
  _mkTheme('t_forest', 'Orman', 'w_forest', 'c_teal'),
  _mkTheme('t_confetti', 'Konfeti', 'p_confetti', 'c_purple'),
  _mkTheme('t_night', 'Gece', 'w_night', 'c_babyblue'),
];

// ═══════════════════════════════════════════════════════════════════════════
//  Zemin widget'ı — renk + opsiyonel desen, altına child.
// ═══════════════════════════════════════════════════════════════════════════
class LiveBgSurface extends StatelessWidget {
  final LiveBgOption option;
  final Widget? child;
  final BorderRadius? radius;
  const LiveBgSurface({
    super.key,
    required this.option,
    this.child,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    Widget stack = Stack(
      fit: StackFit.expand,
      children: [
        if (option.gradient != null)
          DecoratedBox(decoration: BoxDecoration(gradient: option.gradient))
        else
          ColoredBox(color: option.bg),
        if (option.pattern != null)
          CustomPaint(painter: _painterFor(option.pattern!)),
        if (child != null) child!,
      ],
    );
    if (radius != null) {
      return ClipRRect(borderRadius: radius!, child: stack);
    }
    return stack;
  }
}

CustomPainter _painterFor(LiveBgPattern p) {
  switch (p) {
    case LiveBgPattern.lined:
      return _LinedPainter();
    case LiveBgPattern.dot:
      return _DotPainter();
    case LiveBgPattern.grid:
      return _GridPainter();
    case LiveBgPattern.flower:
      return _FlowerPainter();
    case LiveBgPattern.cyber:
      return _CyberPainter();
    case LiveBgPattern.wave:
      return _WavePainter();
    case LiveBgPattern.hearts:
      return _HeartsPainter();
    case LiveBgPattern.stars:
      return _StarsPainter();
    case LiveBgPattern.bubbles:
      return _BubblesPainter();
    case LiveBgPattern.confetti:
      return _ConfettiPainter();
    case LiveBgPattern.butterfly:
      return _ButterflyPainter();
    case LiveBgPattern.rainbow:
      return _RainbowPainter();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Seçici sayfa (bottom sheet) — 3 hedef sekmesi + renk + desen.
// ═══════════════════════════════════════════════════════════════════════════
/// [target] 0=Arka plan, 1=Benim, 2=Qualsar çerçevesi.
/// [option] null → varsayılana dön.
typedef LiveBgChanged = void Function(int target, LiveBgOption? option);

Future<void> showLiveBgPicker(
  BuildContext context, {
  required List<LiveBgOption?> current, // [screen, mine, frame]
  required LiveBgChanged onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _LiveBgSheet(current: current, onChanged: onChanged),
  );
}

class _LiveBgSheet extends StatefulWidget {
  final List<LiveBgOption?> current;
  final LiveBgChanged onChanged;
  const _LiveBgSheet({required this.current, required this.onChanged});

  @override
  State<_LiveBgSheet> createState() => _LiveBgSheetState();
}

class _LiveBgSheetState extends State<_LiveBgSheet> {
  // Aktif seçimler: duvar kağıdı (çerçeve) + iki balon rengi.
  LiveBgOption? _wall;    // widget.current[2] (frame)
  LiveBgOption? _bubble;  // widget.current[1] (benim balonum)
  LiveBgOption? _qualsar; // widget.current[3] (Qualsar balonu)
  int _bubbleTab = 0;     // 0 = Benim, 1 = Qualsar

  @override
  void initState() {
    super.initState();
    _wall = widget.current.length > 2 ? widget.current[2] : null;
    _bubble = widget.current.length > 1 ? widget.current[1] : null;
    _qualsar = widget.current.length > 3 ? widget.current[3] : null;
  }

  void _applyTheme(LiveTheme t) {
    setState(() {
      _wall = t.wall;
      _bubble = t.bubble;
    });
    widget.onChanged(2, t.wall); // duvar kağıdı → çerçeve
    widget.onChanged(1, t.bubble); // benim balonum
    widget.onChanged(0, null); // ekran arka planını sıfırla
  }

  void _pickWall(LiveBgOption? o) {
    setState(() => _wall = o);
    widget.onChanged(2, o);
  }

  // Aktif balon sekmesine (Benim / Qualsar) göre uygular.
  void _pickBubbleActive(LiveBgOption? o) {
    if (_bubbleTab == 0) {
      setState(() => _bubble = o);
      widget.onChanged(1, o);
    } else {
      setState(() => _qualsar = o);
      widget.onChanged(3, o);
    }
  }

  void _resetAll() {
    setState(() {
      _wall = null;
      _bubble = null;
      _qualsar = null;
    });
    widget.onChanged(0, null);
    widget.onChanged(1, null);
    widget.onChanged(2, null);
    widget.onChanged(3, null);
  }

  bool _themeSelected(LiveTheme t) =>
      _wall?.id == t.wall?.id && _bubble?.id == t.bubble?.id;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: Color(0xF0111122),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.wallpaper_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Sohbet teması'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const Spacer(),
                TextButton(
                  onPressed: _resetAll,
                  child: Text('Sıfırla'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white60)),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Hem duvar kağıdı hem balon birlikte değişir.'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 14),
            // ── Temalar — hazır önizleme kartları ────────────────────────────
            _sectionLabel('Temalar'.tr()),
            const SizedBox(height: 10),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: kLiveThemes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final t = kLiveThemes[i];
                  return _ThemeCard(
                    theme: t,
                    active: _themeSelected(t),
                    onTap: () => _applyTheme(t),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            // ── Özelleştir: Duvar kağıdı ─────────────────────────────────────
            _customLabel(Icons.image_rounded, 'Duvar kağıdı'.tr()),
            const SizedBox(height: 10),
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: kLiveWallpapers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final o = kLiveWallpapers[i];
                  return _PatternThumb(
                    option: o,
                    active: _wall?.id == o.id,
                    onTap: () => _pickWall(o),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            // ── Özelleştir: Sohbet balonu (Benim / Qualsar) ──────────────────
            _customLabel(Icons.chat_bubble_rounded, 'Sohbet balonu'.tr()),
            const SizedBox(height: 10),
            // Hangi balon? Benim ↔ Qualsar alt sekmesi.
            Row(
              children: [
                for (int i = 0; i < 2; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == 0 ? 8 : 0),
                    child: GestureDetector(
                      onTap: () => setState(() => _bubbleTab = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: _bubbleTab == i
                              ? const Color(0xFF7C3AED)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          i == 0 ? 'Benim'.tr() : 'Qualsar'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color:
                                _bubbleTab == i ? Colors.white : Colors.white60,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ColorRows(
              selId: (_bubbleTab == 0 ? _bubble : _qualsar)?.id,
              onPick: _pickBubbleActive,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String s) => Text(
        s,
        style: GoogleFonts.poppins(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.white54,
          letterSpacing: 0.4,
        ),
      );

  Widget _customLabel(IconData icon, String s) => Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Text(s,
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      );
}

// ── Tema önizleme kartı — mini sohbet mockup (duvar kağıdı + 2 balon) ────────
class _ThemeCard extends StatelessWidget {
  final LiveTheme theme;
  final bool active;
  final VoidCallback onTap;
  const _ThemeCard(
      {required this.theme, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Duvar kağıdı zemin — null ise sade açık gri (WhatsApp varsayılanı gibi).
    const plain = LiveBgOption(id: 'w_plain', bg: Color(0xFFE8E6DC));
    final wall = theme.wall ?? plain;
    final bubbleColor = theme.bubble?.bg ?? const Color(0xFFC7F5D0);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                width: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? const Color(0xFFFFB800)
                        : Colors.white.withValues(alpha: 0.25),
                    width: active ? 2.6 : 1.2,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFB800)
                                .withValues(alpha: 0.45),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      LiveBgSurface(option: wall),
                      // Gelen balon (beyaz, sol üst)
                      Positioned(
                        left: 10,
                        top: 16,
                        child: _miniBubble(Colors.white, 46),
                      ),
                      // Giden balon (tema rengi, sağ alt)
                      Positioned(
                        right: 10,
                        bottom: 16,
                        child: _miniBubble(bubbleColor, 40),
                      ),
                      if (active)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF111122),
                            ),
                            child: const Icon(Icons.check_rounded,
                                size: 13, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              theme.name.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBubble(Color c, double w) => Container(
        width: w,
        height: 16,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 3,
                offset: const Offset(0, 1)),
          ],
        ),
      );
}

/// Renk paleti — 2 yatay sıra, sağa-sola kaydırmalı tek çerçeve.
/// Üst sıra ilk yarı, alt sıra ikinci yarı; birlikte kayar (sütunlar hizalı).
class _ColorRows extends StatelessWidget {
  final String? selId;
  final ValueChanged<LiveBgOption?> onPick;
  const _ColorRows({required this.selId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final half = (kLiveBgColors.length / 2).ceil();
    final top = kLiveBgColors.sublist(0, half);
    final bottom = kLiveBgColors.sublist(half);
    Widget rowFor(List<LiveBgOption> list) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in list)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _ColorSwatch(
                  option: o,
                  active: selId == o.id,
                  onTap: () => onPick(o),
                ),
              ),
          ],
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          rowFor(top),
          const SizedBox(height: 10),
          rowFor(bottom),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final LiveBgOption option;
  final bool active;
  final VoidCallback onTap;
  const _ColorSwatch(
      {required this.option, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: option.bg,
          border: Border.all(
            color: active
                ? const Color(0xFFFFB800)
                : Colors.white.withValues(alpha: 0.30),
            width: active ? 2.6 : 1.2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.55),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _PatternThumb extends StatelessWidget {
  final LiveBgOption option;
  final bool active;
  final VoidCallback onTap;
  const _PatternThumb(
      {required this.option, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? const Color(0xFFFFB800)
                : Colors.white.withValues(alpha: 0.30),
            width: active ? 2.6 : 1.2,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.45),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: LiveBgSurface(
          option: option,
          radius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Painter'lar — gradyan tabanlar üzerinde YÜKSEK KONTRAST + kalın motif.
// ═══════════════════════════════════════════════════════════════════════════
class _LinedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Defter: mavi yatay çizgiler + kırmızı sol margin.
    final line = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.70)
      ..strokeWidth = 1.0;
    const sp = 26.0;
    for (double y = 22; y < size.height; y += sp) {
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), line);
    }
    final margin = Paint()
      ..color = const Color(0xFFF87171).withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(size.width * 0.14, 0),
        Offset(size.width * 0.14, size.height), margin);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF92400E).withValues(alpha: 0.42);
    const sp = 22.0;
    for (double y = sp; y < size.height; y += sp) {
      for (double x = sp; x < size.width; x += sp) {
        canvas.drawCircle(Offset(x, y), 2.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Blueprint: beyaz ince grid + parlak vurgu hatları.
    final thin = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 0.7;
    final bold = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    const sp = 22.0;
    int c = 0;
    for (double x = 0; x < size.width; x += sp) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          c % 4 == 0 ? bold : thin);
      c++;
    }
    int r = 0;
    for (double y = 0; y < size.height; y += sp) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          r % 4 == 0 ? bold : thin);
      r++;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _FlowerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final petalPaint = Paint()..color = Colors.white.withValues(alpha: 0.55);
    final centerPaint =
        Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.75);
    const sp = 54.0;
    int row = 0;
    for (double y = 28; y < size.height; y += sp) {
      final off = row.isEven ? 0.0 : sp / 2;
      for (double x = 28 + off; x < size.width; x += sp) {
        for (int i = 0; i < 6; i++) {
          final angle = (i * math.pi * 2) / 6;
          final px = x + math.cos(angle) * 8;
          final py = y + math.sin(angle) * 8;
          canvas.drawCircle(Offset(px, py), 5.5, petalPaint);
        }
        canvas.drawCircle(Offset(x, y), 3.5, centerPaint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CyberPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF22D3EE).withValues(alpha: 0.32)
      ..strokeWidth = 0.8;
    final glowPaint = Paint()
      ..color = const Color(0xFFE879F9).withValues(alpha: 0.28)
      ..strokeWidth = 1.6;
    const sp = 34.0;
    for (double x = 0; x < size.width; x += sp) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += sp) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Kavşak parlamaları
    final node = Paint()..color = const Color(0xFF67E8F9).withValues(alpha: 0.5);
    for (double y = 0; y < size.height; y += sp * 2) {
      for (double x = 0; x < size.width; x += sp * 2) {
        canvas.drawCircle(Offset(x, y), 1.8, node);
      }
    }
    for (double y = sp * 3; y < size.height; y += sp * 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), glowPaint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    const sp = 34.0;
    for (double baseY = 18; baseY < size.height; baseY += sp) {
      final path = Path()..moveTo(0, baseY);
      for (double x = 0; x < size.width; x += 4) {
        final y = baseY + math.sin(x / 16) * 7;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Pastel / kızlara hitap eden desenler
// ═══════════════════════════════════════════════════════════════════════════

// Küçük bir kalp çizer (merkez cx,cy; s ~ yarı genişlik).
void _drawHeart(Canvas canvas, double cx, double cy, double s, Paint paint) {
  final path = Path();
  path.moveTo(cx, cy + s * 0.55);
  path.cubicTo(cx - s * 1.4, cy - s * 0.4, cx - s * 0.5, cy - s * 1.1, cx,
      cy - s * 0.35);
  path.cubicTo(cx + s * 0.5, cy - s * 1.1, cx + s * 1.4, cy - s * 0.4, cx,
      cy + s * 0.55);
  path.close();
  canvas.drawPath(path, paint);
}

class _HeartsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white.withValues(alpha: 0.60);
    final deep = Paint()..color = const Color(0xFFDB2777).withValues(alpha: 0.45);
    const sp = 46.0;
    int row = 0;
    for (double y = 22; y < size.height; y += sp) {
      final off = (row.isEven) ? 0.0 : sp / 2;
      for (double x = 20 + off; x < size.width; x += sp) {
        _drawHeart(canvas, x, y, 9, row.isEven ? white : deep);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// 5 köşeli yıldız path'i.
Path _starPath(double cx, double cy, double r) {
  final path = Path();
  for (int i = 0; i < 5; i++) {
    final outer = (i * 4 * math.pi / 5) - math.pi / 2;
    final inner = outer + 2 * math.pi / 5;
    final ox = cx + math.cos(outer) * r;
    final oy = cy + math.sin(outer) * r;
    final ix = cx + math.cos(inner) * r * 0.42;
    final iy = cy + math.sin(inner) * r * 0.42;
    if (i == 0) {
      path.moveTo(ox, oy);
    } else {
      path.lineTo(ox, oy);
    }
    path.lineTo(ix, iy);
  }
  path.close();
  return path;
}

class _StarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Galaksi: altın büyük yıldızlar + beyaz küçük parıltılar.
    final gold = Paint()..color = const Color(0xFFFCD34D).withValues(alpha: 0.85);
    final white = Paint()..color = Colors.white.withValues(alpha: 0.55);
    const sp = 50.0;
    int i = 0;
    for (double y = 26; y < size.height; y += sp) {
      final off = (y ~/ sp).isEven ? 0.0 : sp / 2;
      for (double x = 24 + off; x < size.width; x += sp) {
        final big = (i % 3 == 0);
        if (big) {
          canvas.drawPath(_starPath(x, y, 9), gold);
        } else {
          canvas.drawPath(_starPath(x, y, 4.5), white);
          canvas.drawCircle(Offset(x + sp * 0.28, y - sp * 0.18), 1.2, white);
        }
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _BubblesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.22);
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    const sp = 46.0;
    int i = 0;
    for (double y = 18; y < size.height; y += sp) {
      final off = (y ~/ sp).isEven ? 0.0 : sp / 2;
      for (double x = 18 + off; x < size.width; x += sp) {
        final r = 7.0 + (i % 3) * 3.5;
        canvas.drawCircle(Offset(x, y), r, fill);
        canvas.drawCircle(Offset(x, y), r, ring);
        // parıltı noktası
        canvas.drawCircle(Offset(x - r * 0.35, y - r * 0.35), 1.4,
            Paint()..color = Colors.white.withValues(alpha: 0.7));
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _ConfettiPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const colors = [
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF3B82F6),
    ];
    const sp = 36.0;
    int i = 0;
    for (double y = 14; y < size.height; y += sp) {
      final off = (y ~/ sp).isEven ? 0.0 : sp / 2;
      for (double x = 14 + off; x < size.width; x += sp) {
        final c = colors[i % colors.length];
        final paint = Paint()..color = c.withValues(alpha: 0.65);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate((i % 5) * 0.5);
        // eğik konfeti çubuğu (daha büyük/belirgin)
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-5.5, -2.2, 11, 4.4),
            const Radius.circular(2.2),
          ),
          paint,
        );
        canvas.restore();
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _ButterflyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const wingColors = [
      Color(0xFFDB2777),
      Color(0xFF7C3AED),
      Colors.white,
    ];
    const sp = 60.0;
    int i = 0;
    for (double y = 32; y < size.height; y += sp) {
      final off = (y ~/ sp).isEven ? 0.0 : sp / 2;
      for (double x = 30 + off; x < size.width; x += sp) {
        final c = wingColors[i % wingColors.length];
        final wing = Paint()..color = c.withValues(alpha: 0.45);
        final body = Paint()
          ..color = const Color(0xFF4C1D95).withValues(alpha: 0.55);
        // 4 kanat (2 üst büyük, 2 alt küçük)
        canvas.drawOval(
            Rect.fromCircle(center: Offset(x - 5, y - 3), radius: 5.5), wing);
        canvas.drawOval(
            Rect.fromCircle(center: Offset(x + 5, y - 3), radius: 5.5), wing);
        canvas.drawOval(
            Rect.fromCircle(center: Offset(x - 4, y + 4), radius: 4), wing);
        canvas.drawOval(
            Rect.fromCircle(center: Offset(x + 4, y + 4), radius: 4), wing);
        // gövde
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 1.8, height: 12),
            const Radius.circular(1),
          ),
          body,
        );
        i++;
      }
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _RainbowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Canlı pastel gökkuşağı — belirgin çapraz şeritler.
    const bands = [
      Color(0xFFFB7185), // pembe
      Color(0xFFFB923C), // turuncu
      Color(0xFFFACC15), // sarı
      Color(0xFF4ADE80), // yeşil
      Color(0xFF38BDF8), // mavi
      Color(0xFFA78BFA), // mor
    ];
    const bandW = 24.0;
    // Sol üstten sağ alta doğru çapraz akan şeritler.
    final diag = size.width + size.height;
    int i = 0;
    for (double d = -size.height; d < diag; d += bandW) {
      final c = bands[i % bands.length];
      final paint = Paint()
        ..color = c.withValues(alpha: 0.50)
        ..strokeWidth = bandW * 0.72
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
      i++;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
