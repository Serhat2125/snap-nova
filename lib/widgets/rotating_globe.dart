// ═══════════════════════════════════════════════════════════════════════════════
//  RotatingGlobe — gerçek NASA Blue Marble dokusuyla TAM TUR dönen 3D dünya.
//
//  • Küre, shaders/globe.frag fragment shader'ı ile çizilir: eşdikdörtgen
//    doku ortografik projeksiyonla küreye sarılır → kıtalar/okyanuslar
//    orijinal yerinde. Limb kararması + atmosfer halesi shader'da.
//  • Bayraklar: her ülkenin (lat, lon) merkezi shader'la AYNI projeksiyonla
//    ekrana taşınır; ön yarım kürede kalanlar küçük emoji bayrak olarak
//    ülkenin tam üstünde görünür, küreyle birlikte döner.
//  • [paused] true iken animasyon durur (ör. üstte tam ekran panel açıkken)
//    — boşa GPU/pil harcanmaz. Uygulama arka plandayken de durur.
//  • Shader/doku yüklenene kadar [fallback] gösterilir (görsel sıçrama yok).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RotatingGlobe extends StatefulWidget {
  final double height;
  /// Yüklenene kadar gösterilecek widget (ör. statik dünya görseli).
  final Widget? fallback;
  /// true → dönüş durur (üstte overlay varken pil yakmasın).
  final bool paused;
  /// Tam tur süresi.
  final Duration period;
  /// Kullanıcının ülkesi (ISO-2) — bu bayrak küme nöbetine GİRMEZ, ülke ön
  /// yüzdeyken HER ZAMAN görünür (kullanıcı kendi bayrağını hep görsün).
  final String? pinnedCountry;

  const RotatingGlobe({
    super.key,
    this.height = 180,
    this.fallback,
    this.paused = false,
    this.period = const Duration(seconds: 22),
    this.pinnedCountry,
  });

  @override
  State<RotatingGlobe> createState() => _RotatingGlobeState();
}

/// Shader programı + NASA dokusu — RotatingGlobe ve CountryZoomGlobe
/// paylaşır; bir kez yüklenir.
class _GlobeAssets {
  static ui.FragmentProgram? program;
  static ui.Image? texture;
  static Future<bool> ensure() async {
    try {
      program ??= await ui.FragmentProgram.fromAsset('shaders/globe.frag');
      if (texture == null) {
        final data =
            await rootBundle.load('assets/library_icons/earth_equirect.jpg');
        final codec =
            await ui.instantiateImageCodec(data.buffer.asUint8List());
        texture = (await codec.getNextFrame()).image;
      }
      return true;
    } catch (e) {
      debugPrint('[Globe] asset yüklenemedi: $e');
      return false;
    }
  }
}

class _RotatingGlobeState extends State<RotatingGlobe>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  late final AnimationController _spin;
  // Bayrak nöbetleşe gösterimi için duvar saati — kümelerdeki 5 sn'lik
  // slotlar bundan hesaplanır. paused iken durur.
  final Stopwatch _clock = Stopwatch();
  bool _ready = false;

  // Parmakla döndürme: sürükleme sırasında otomatik dönüş durur, ofset
  // toplam dönüşe eklenir; bırakınca kaldığı yerden otomatik döner.
  double _dragOffset = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _spin = AnimationController(vsync: this, duration: widget.period);
    _load();
  }

  Future<void> _load() async {
    final ok = await _GlobeAssets.ensure();
    // Shader/doku yüklenemezse (eski cihaz vb.) fallback'te kal.
    if (!ok || !mounted) return;
    setState(() => _ready = true);
    _syncSpin();
  }

  void _syncSpin() {
    if (!_ready) return;
    final shouldRun = !widget.paused && !_dragging;
    if (shouldRun && !_spin.isAnimating) {
      _spin.repeat();
      _clock.start();
    } else if (!shouldRun && _spin.isAnimating) {
      _spin.stop();
      if (widget.paused) _clock.stop();
    }
  }

  @override
  void didUpdateWidget(RotatingGlobe old) {
    super.didUpdateWidget(old);
    if (old.paused != widget.paused) _syncSpin();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncSpin();
    } else {
      _spin.stop();
      _clock.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready ||
        _GlobeAssets.program == null ||
        _GlobeAssets.texture == null) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: widget.fallback ?? const ColoredBox(color: Color(0xFF0B1B2B)),
      );
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      // Yatay sürükleme küreyi elle döndürür (dikey kaydırma sayfada,
      // tek dokunuş üstteki kartın onTap'ında kalır — çakışma yok).
      child: GestureDetector(
        onHorizontalDragStart: (_) {
          _dragging = true;
          _syncSpin();
        },
        onHorizontalDragUpdate: (d) {
          final r = widget.height / 2 - 2.0;
          setState(() => _dragOffset -= d.delta.dx / r);
        },
        onHorizontalDragEnd: (_) {
          _dragging = false;
          _syncSpin();
        },
        onHorizontalDragCancel: () {
          _dragging = false;
          _syncSpin();
        },
        child: AnimatedBuilder(
          animation: _spin,
          builder: (_, __) => CustomPaint(
            painter: _GlobePainter(
              program: _GlobeAssets.program!,
              texture: _GlobeAssets.texture!,
              rotation: _spin.value * 2 * math.pi + _dragOffset,
              timeSec: _clock.elapsedMilliseconds / 1000.0,
              pinnedCountry: widget.pinnedCountry,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobePainter extends CustomPainter {
  final ui.FragmentProgram program;
  final ui.Image texture;
  final double rotation;
  final double timeSec;
  final String? pinnedCountry;
  _GlobePainter({
    required this.program,
    required this.texture,
    required this.rotation,
    required this.timeSec,
    this.pinnedCountry,
  });

  /// Bayraklar nöbetleşe: yan yana ülkeler tek kümede toplanır; kümede aynı
  /// anda TEK bayrak görünür, [_slotSeconds] sonra sıradaki komşuya geçer.
  /// Böylece sıkışık bölgelerde (Avrupa, Karayipler) bayraklar üst üste
  /// binmez, hangi bayrağın nereye ait olduğu net okunur.
  static const double _slotSeconds = 5.0;

  /// Küme eşiği — iki ülke merkezi arasındaki açı bunun altındaysa komşu
  /// sayılır (~7° ≈ 780 km).
  static const double _clusterCosThreshold = 0.9925; // cos(7°)

  // index listeleri — _flagAnchors'a göre bir kez hesaplanır.
  static List<List<int>>? _clusters;
  static List<List<int>> _buildClusters() {
    final n = _flagAnchors.length;
    // Birim küre vektörleri
    final vx = List<double>.filled(n, 0);
    final vy = List<double>.filled(n, 0);
    final vz = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final lat = _flagAnchors[i].$2 * math.pi / 180;
      final lon = _flagAnchors[i].$3 * math.pi / 180;
      vx[i] = math.cos(lat) * math.cos(lon);
      vy[i] = math.cos(lat) * math.sin(lon);
      vz[i] = math.sin(lat);
    }
    // Greedy kümeleme: mevcut kümelerden birinin HERHANGİ bir üyesine
    // yeterince yakınsa o kümeye katıl, değilse yeni küme aç.
    final clusters = <List<int>>[];
    for (int i = 0; i < n; i++) {
      List<int>? home;
      for (final c in clusters) {
        for (final j in c) {
          final dot = vx[i] * vx[j] + vy[i] * vy[j] + vz[i] * vz[j];
          if (dot >= _clusterCosThreshold) {
            home = c;
            break;
          }
        }
        if (home != null) break;
      }
      (home ?? (clusters..add(<int>[])).last).add(i);
    }
    return clusters;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform sırası: uSize(w,h), uLat0, uLon0, uZoom.
    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, 0.0) // ekvator merkezli
      ..setFloat(3, rotation)
      ..setFloat(4, 1.0) // tam küre
      ..setImageSampler(0, texture);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);

    // ── Bayraklar — shader'la aynı ortografik projeksiyon ──────────────────
    // Kümede aynı anda TEK bayrak: 5 sn'de bir sıradaki komşuya geçer.
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 2.0;
    final clusters = _clusters ??= _buildClusters();
    final slot = (timeSec / _slotSeconds).floor();
    // Slot başında yumuşak büyüme (0 → 1, ilk ~0.35 sn).
    final tIn = ((timeSec % _slotSeconds) / 0.35).clamp(0.0, 1.0);
    // Kullanıcının ülkesi nöbete girmez — ön yüzdeyken HEP görünür.
    final pinned = (pinnedCountry ?? '').toLowerCase();

    // (index, z, ekran) hesabı — tek yerden.
    (int, double, Offset)? project(int i) {
      final f = _flagAnchors[i];
      final lat = f.$2 * math.pi / 180;
      final lon = f.$3 * math.pi / 180;
      final d = lon - rotation;
      final cosLat = math.cos(lat);
      final x = cosLat * math.sin(d);
      final z = cosLat * math.cos(d);
      final y = math.sin(lat);
      if (z <= 0.18) return null; // arka yüz / kenar
      return (i, z, c + Offset(x * r, -y * r));
    }

    void drawFlag((int, double, Offset) p, double scale) {
      final fs = (8.0 + 4.0 * p.$2).roundToDouble();
      final tp = _flagPainter(_flagAnchors[p.$1].$1, fs);
      canvas.save();
      canvas.translate(p.$3.dx, p.$3.dy);
      canvas.scale(scale);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    for (final cluster in clusters) {
      // Önce ÖN YÜZDE görünen üyeleri bul (arka yarıdakiler zaten çizilmez).
      final visible = <(int, double, Offset)>[];
      for (final i in cluster) {
        final p = project(i);
        if (p == null) continue;
        // Sabitlenmiş ülke: hemen çiz, nöbet listesine katma.
        if (_flagAnchors[i].$1 == pinned) {
          drawFlag(p, 1.0);
          continue;
        }
        visible.add(p);
      }
      if (visible.isEmpty) continue;
      // Tek üyeli küme (izole ülke) hep görünür; çok üyelide sıradaki seçilir.
      final pick = visible.length == 1
          ? visible.first
          : visible[slot % visible.length];
      drawFlag(pick, visible.length == 1 ? 1.0 : tIn);
    }
  }

  // TextPainter cache — ~195 bayrağı HER KAREDE yeniden layout etmek CPU
  // yakar (ısınma!). (ülke, punto) başına bir kez layout edilir, sonra
  // sadece paint edilir.
  static final Map<String, TextPainter> _tpCache = {};
  static TextPainter _flagPainter(String cc, double fs) {
    return _tpCache.putIfAbsent('$cc|$fs', () {
      final tp = TextPainter(
        text: TextSpan(text: _flagEmoji(cc), style: TextStyle(fontSize: fs)),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    });
  }

  @override
  bool shouldRepaint(_GlobePainter old) =>
      old.rotation != rotation ||
      old.timeSec != timeSec ||
      old.pinnedCountry != pinnedCountry ||
      old.texture != texture;
}

/// Ülke bayrağı çapaları — (ISO-2, lat, lon), ülkenin kara merkezine yakın.
/// TÜM BM üyeleri (~195): uygulamayı indiren HER kullanıcı kendi bayrağını
/// kürede kendi ülkesinin üstünde görür (GLOBAL-FIRST).
const List<(String, double, double)> _flagAnchors = [
  // ── Avrupa ──
  ('tr', 39.0, 35.0), ('de', 51.0, 10.0), ('fr', 46.5, 2.5),
  ('gb', 53.5, -2.0), ('es', 40.0, -3.7), ('it', 42.5, 12.5),
  ('gr', 39.0, 22.0), ('pl', 52.0, 19.0), ('ua', 49.0, 32.0),
  ('se', 62.0, 15.0), ('no', 61.0, 9.0), ('fi', 64.0, 26.0),
  ('dk', 56.0, 10.0), ('is', 65.0, -18.5), ('ie', 53.2, -8.0),
  ('pt', 39.5, -8.0), ('nl', 52.2, 5.5), ('be', 50.6, 4.5),
  ('lu', 49.8, 6.1), ('ch', 46.8, 8.2), ('at', 47.5, 14.5),
  ('cz', 49.8, 15.5), ('sk', 48.7, 19.5), ('hu', 47.0, 19.5),
  ('ro', 46.0, 25.0), ('bg', 42.7, 25.3), ('rs', 44.0, 21.0),
  ('hr', 45.1, 15.2), ('ba', 44.0, 17.8), ('si', 46.1, 14.8),
  ('me', 42.7, 19.3), ('mk', 41.6, 21.7), ('al', 41.0, 20.0),
  ('xk', 42.6, 20.9), ('by', 53.7, 28.0), ('lt', 55.3, 23.9),
  ('lv', 57.0, 25.0), ('ee', 58.7, 25.0), ('md', 47.2, 28.5),
  ('cy', 35.0, 33.0), ('mt', 35.9, 14.4), ('ad', 42.5, 1.5),
  ('mc', 43.73, 7.42), ('li', 47.15, 9.55), ('sm', 43.94, 12.45),
  ('va', 41.9, 12.45), ('ru', 58.0, 62.0),
  // ── Asya ──
  ('kz', 48.0, 68.0), ('az', 40.4, 47.5), ('am', 40.2, 45.0),
  ('ge', 42.0, 43.5), ('ir', 32.5, 53.5), ('iq', 33.0, 43.7),
  ('sy', 35.0, 38.5), ('lb', 33.9, 35.9), ('il', 31.4, 35.0),
  ('ps', 31.9, 35.2), ('jo', 31.2, 36.5), ('sa', 24.0, 45.0),
  ('ye', 15.6, 47.5), ('om', 21.0, 57.0), ('ae', 24.0, 54.0),
  ('qa', 25.3, 51.2), ('bh', 26.0, 50.55), ('kw', 29.3, 47.6),
  ('af', 33.9, 67.7), ('pk', 30.0, 70.0), ('in', 21.0, 78.5),
  ('np', 28.4, 84.1), ('bt', 27.5, 90.4), ('bd', 23.7, 90.3),
  ('lk', 7.9, 80.8), ('mv', 3.2, 73.2), ('mm', 19.8, 96.1),
  ('th', 15.5, 101.0), ('la', 18.0, 103.8), ('kh', 12.5, 105.0),
  ('vn', 16.0, 107.5), ('my', 4.2, 101.9), ('sg', 1.35, 103.8),
  ('bn', 4.5, 114.7), ('id', -2.0, 118.0), ('tl', -8.8, 125.9),
  ('ph', 12.5, 122.5), ('cn', 35.0, 103.0), ('mn', 46.9, 103.8),
  ('kp', 40.0, 127.0), ('kr', 36.3, 128.0), ('jp', 36.5, 138.5),
  ('uz', 41.4, 64.6), ('tm', 39.0, 59.5), ('tj', 38.9, 71.3),
  ('kg', 41.2, 74.8),
  // ── Afrika ──
  ('eg', 26.5, 30.0), ('ly', 27.0, 17.3), ('tn', 34.1, 9.6),
  ('dz', 28.0, 2.6), ('ma', 31.5, -6.5), ('mr', 20.3, -10.3),
  ('ml', 17.3, -4.0), ('ne', 17.6, 8.1), ('td', 15.4, 18.7),
  ('sd', 15.6, 30.2), ('ss', 7.3, 30.3), ('er', 15.2, 39.0),
  ('dj', 11.7, 42.6), ('et', 8.6, 39.6), ('so', 5.2, 46.2),
  ('ke', 0.5, 38.0), ('ug', 1.3, 32.4), ('rw', -2.0, 29.9),
  ('bi', -3.4, 29.9), ('tz', -6.4, 34.9), ('cd', -2.9, 23.6),
  ('cg', -0.7, 15.6), ('ga', -0.6, 11.6), ('gq', 1.6, 10.5),
  ('cm', 5.7, 12.7), ('cf', 6.6, 20.9), ('ng', 9.0, 8.0),
  ('bj', 9.6, 2.3), ('tg', 8.5, 1.0), ('gh', 7.9, -1.2),
  ('ci', 7.6, -5.5), ('lr', 6.4, -9.4), ('sl', 8.5, -11.8),
  ('gn', 10.4, -10.9), ('gw', 12.0, -14.9), ('sn', 14.4, -14.5),
  ('gm', 13.4, -15.4), ('bf', 12.2, -1.7), ('cv', 15.1, -23.6),
  ('st', 0.2, 6.6), ('ao', -12.3, 17.5), ('zm', -13.5, 27.8),
  ('mw', -13.2, 34.3), ('mz', -17.3, 35.5), ('zw', -19.0, 29.9),
  ('bw', -22.3, 24.7), ('na', -22.1, 17.2), ('za', -29.0, 24.0),
  ('ls', -29.6, 28.2), ('sz', -26.5, 31.5), ('mg', -19.4, 46.7),
  ('km', -11.9, 43.9), ('mu', -20.3, 57.6), ('sc', -4.7, 55.5),
  // ── Amerika ──
  ('us', 39.0, -98.5), ('ca', 56.0, -106.0), ('mx', 23.5, -102.5),
  ('gt', 15.7, -90.4), ('bz', 17.2, -88.7), ('sv', 13.7, -88.9),
  ('hn', 14.8, -86.6), ('ni', 12.9, -85.2), ('cr', 9.9, -84.2),
  ('pa', 8.5, -80.1), ('cu', 21.5, -79.5), ('jm', 18.1, -77.3),
  ('ht', 19.0, -72.7), ('do', 18.9, -70.5), ('bs', 24.7, -77.9),
  ('bb', 13.2, -59.5), ('tt', 10.5, -61.3), ('gd', 12.1, -61.7),
  ('vc', 13.2, -61.2), ('lc', 13.9, -61.0), ('dm', 15.4, -61.35),
  ('ag', 17.1, -61.8), ('kn', 17.3, -62.7), ('co', 4.0, -73.0),
  ('ve', 7.1, -66.2), ('gy', 4.8, -58.9), ('sr', 4.1, -55.9),
  ('ec', -1.4, -78.4), ('pe', -9.5, -75.0), ('br', -10.0, -52.0),
  ('bo', -16.7, -64.7), ('py', -23.2, -58.4), ('cl', -35.0, -71.0),
  ('ar', -34.5, -64.5), ('uy', -32.8, -56.0),
  // ── Okyanusya ──
  ('au', -25.0, 134.0), ('nz', -42.5, 172.5), ('pg', -6.5, 144.3),
  ('fj', -17.8, 178.0), ('sb', -9.6, 160.2), ('vu', -16.0, 167.0),
  ('ws', -13.8, -172.1), ('to', -21.2, -175.2), ('ki', 1.4, 173.0),
  ('tv', -8.0, 178.0), ('nr', -0.5, 166.9), ('mh', 7.1, 171.2),
  ('fm', 6.9, 158.2), ('pw', 7.5, 134.6),
];

String _flagEmoji(String cc) {
  const base = 0x1F1E6;
  final up = cc.toUpperCase();
  return String.fromCharCodes(
      [base + up.codeUnitAt(0) - 0x41, base + up.codeUnitAt(1) - 0x41]);
}

/// Dışa açık yardımcılar — Ülke Çapında kartı bunları kullanır.
String flagEmojiFor(String cc) => _flagEmoji(cc);

/// Ülkenin kara merkezi (lat, lon) — bilinmiyorsa null.
(double, double)? countryAnchor(String cc) {
  final lc = cc.toLowerCase();
  for (final f in _flagAnchors) {
    if (f.$1 == lc) return (f.$2, f.$3);
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CountryZoomGlobe — AYNI orijinal küre (aynı shader + NASA dokusu), ama
//  kullanıcının ülkesine yakınlaşmış ve SABİT. Ülkenin sınırları (veri
//  varsa) parlak çizgiyle kürenin üstüne çizilir; sınır verisi yoksa ülke
//  merkezinde bayrak + halka işareti gösterilir. Animasyon yok → maliyet 0.
// ═══════════════════════════════════════════════════════════════════════════════
class CountryZoomGlobe extends StatefulWidget {
  final double height;
  final double centerLat; // derece
  final double centerLon; // derece
  /// Ülke sınır poligonları — [poligon][nokta][lon, lat] (derece).
  final List<List<List<double>>>? borders;
  /// Sınır verisi yoksa merkezde gösterilecek bayrak (ISO-2).
  final String? flagCc;
  final Widget? fallback;
  const CountryZoomGlobe({
    super.key,
    this.height = 180,
    required this.centerLat,
    required this.centerLon,
    this.borders,
    this.flagCc,
    this.fallback,
  });

  @override
  State<CountryZoomGlobe> createState() => _CountryZoomGlobeState();
}

class _CountryZoomGlobeState extends State<CountryZoomGlobe> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _GlobeAssets.ensure().then((ok) {
      if (mounted && ok) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready ||
        _GlobeAssets.program == null ||
        _GlobeAssets.texture == null) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: widget.fallback ?? const ColoredBox(color: Color(0xFF0B1B2B)),
      );
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ZoomGlobePainter(
          program: _GlobeAssets.program!,
          texture: _GlobeAssets.texture!,
          centerLat: widget.centerLat * math.pi / 180,
          centerLon: widget.centerLon * math.pi / 180,
          borders: widget.borders,
          flagCc: widget.flagCc,
        ),
      ),
    );
  }
}

class _ZoomGlobePainter extends CustomPainter {
  final ui.FragmentProgram program;
  final ui.Image texture;
  final double centerLat; // radyan
  final double centerLon; // radyan
  final List<List<List<double>>>? borders;
  final String? flagCc;
  _ZoomGlobePainter({
    required this.program,
    required this.texture,
    required this.centerLat,
    required this.centerLon,
    this.borders,
    this.flagCc,
  });

  /// (lat,lon) derece → birim küre ortografik (x, y, z) — merkez centerLat/Lon.
  (double, double, double) _project(double latDeg, double lonDeg) {
    final lat = latDeg * math.pi / 180;
    final lon = lonDeg * math.pi / 180;
    final dLon = lon - centerLon;
    final x = math.cos(lat) * math.sin(dLon);
    final y = math.cos(centerLat) * math.sin(lat) -
        math.sin(centerLat) * math.cos(lat) * math.cos(dLon);
    final z = math.sin(centerLat) * math.sin(lat) +
        math.cos(centerLat) * math.cos(lat) * math.cos(dLon);
    return (x, y, z);
  }

  /// Sınır verisine göre yakınlaşma — ülke kartın ~%72'sini dolduracak
  /// şekilde; veri yoksa sabit 2.6.
  double _fitZoom() {
    final b = borders;
    if (b == null || b.isEmpty) return 2.6;
    double maxR = 0;
    for (final poly in b) {
      for (final p in poly) {
        final v = _project(p[1], p[0]);
        if (v.$3 <= 0) continue;
        final r = math.sqrt(v.$1 * v.$1 + v.$2 * v.$2);
        if (r > maxR) maxR = r;
      }
    }
    if (maxR <= 0.001) return 2.6;
    return (0.72 / maxR).clamp(1.15, 7.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final zoom = _fitZoom();
    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, centerLat)
      ..setFloat(3, centerLon)
      ..setFloat(4, zoom)
      ..setImageSampler(0, texture);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);

    final c = Offset(size.width / 2, size.height / 2);
    final scale = (math.min(size.width, size.height) / 2 - 2.0) * zoom;

    // ── Ülke sınırları — parlak kontur + yumuşak dış ışıma ──────────────────
    final b = borders;
    if (b != null && b.isNotEmpty) {
      final path = Path();
      for (final poly in b) {
        bool started = false;
        for (final p in poly) {
          final v = _project(p[1], p[0]);
          if (v.$3 <= 0) continue; // arka yüz (zoom'da pratikte olmaz)
          final o = c + Offset(v.$1 * scale, -v.$2 * scale);
          if (!started) {
            path.moveTo(o.dx, o.dy);
            started = true;
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        if (started) path.close();
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..color = const Color(0xFFFFD54F).withValues(alpha: 0.65)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.95),
      );
    } else if (flagCc != null) {
      // Sınır verisi yok → merkezde bayrak + ince halka işareti.
      canvas.drawCircle(
        c,
        16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.85),
      );
      final tp = TextPainter(
        text: TextSpan(
            text: _flagEmoji(flagCc!), style: const TextStyle(fontSize: 16)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_ZoomGlobePainter old) =>
      old.centerLat != centerLat ||
      old.centerLon != centerLon ||
      old.borders != borders ||
      old.flagCc != flagCc ||
      old.texture != texture;
}
