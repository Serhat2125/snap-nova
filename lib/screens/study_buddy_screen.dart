import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show localeService;

// ═══════════════════════════════════════════════════════════════════════════════
//  StudyBuddyScreen — Kütüphanem > Çalışma Arkadaşım
//  • 6 sevimli robot karakter; kullanıcı birini seçer.
//  • Seçili robota birincil ve aksan renkleri uygulanabilir.
//  • Seçim + renkler SharedPreferences'ta kalıcı.
// ═══════════════════════════════════════════════════════════════════════════════

class StudyBuddyScreen extends StatefulWidget {
  const StudyBuddyScreen({super.key});

  @override
  State<StudyBuddyScreen> createState() => _StudyBuddyScreenState();
}

class _StudyBuddyScreenState extends State<StudyBuddyScreen> {
  static const _prefType = 'study_buddy_type';
  static const _prefPrimary = 'study_buddy_primary';
  static const _prefAccent = 'study_buddy_accent';

  static const _buddies = <_Buddy>[
    _Buddy('bolt', 'buddy_name_bolt', _BuddyShape.classic),
    _Buddy('nova', 'buddy_name_nova', _BuddyShape.owl),
    _Buddy('mia', 'buddy_name_mia', _BuddyShape.cat),
    _Buddy('bob', 'buddy_name_bob', _BuddyShape.bear),
    _Buddy('astro', 'buddy_name_astro', _BuddyShape.space),
    _Buddy('pixel', 'buddy_name_pixel', _BuddyShape.mini),
  ];

  static const _palette = <Color>[
    Color(0xFF7C3AED), // mor
    Color(0xFF2563EB), // mavi
    Color(0xFF0891B2), // teal
    Color(0xFF10B981), // yeşil
    Color(0xFFF59E0B), // amber
    Color(0xFFFF6A00), // turuncu
    Color(0xFFE11D48), // kırmızı
    Color(0xFFEC4899), // pembe
    Color(0xFF111827), // siyah
  ];

  String _selectedId = 'bolt';
  Color _primary = const Color(0xFF7C3AED);
  Color _accent = const Color(0xFFFFC857);
  bool _editingAccent = false; // false = birincil renk seçiliyor

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedId = prefs.getString(_prefType) ?? 'bolt';
      final p = prefs.getInt(_prefPrimary);
      if (p != null) _primary = Color(p);
      final a = prefs.getInt(_prefAccent);
      if (a != null) _accent = Color(a);
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefType, _selectedId);
    await prefs.setInt(_prefPrimary, _primary.toARGB32());
    await prefs.setInt(_prefAccent, _accent.toARGB32());
  }

  void _selectBuddy(String id) {
    setState(() => _selectedId = id);
    _save();
  }

  void _applyColor(Color c) {
    setState(() {
      if (_editingAccent) {
        _accent = c;
      } else {
        _primary = c;
      }
    });
    _save();
  }

  _Buddy get _current =>
      _buddies.firstWhere((b) => b.id == _selectedId, orElse: () => _buddies.first);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          localeService.tr('my_study_buddy'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Büyük önizleme: seçili robot ────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: _primary.withValues(alpha: 0.15),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _BuddyAvatar(
                    shape: _current.shape,
                    primary: _primary,
                    accent: _accent,
                    size: 150,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    localeService.tr(_current.nameKey),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            // ── 6 robot grid ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.85,
                ),
                itemCount: _buddies.length,
                itemBuilder: (_, i) {
                  final b = _buddies[i];
                  final sel = b.id == _selectedId;
                  return GestureDetector(
                    onTap: () => _selectBuddy(b.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? _primary : Colors.black.withValues(alpha: 0.10),
                          width: sel ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _BuddyAvatar(
                              shape: b.shape,
                              primary: sel
                                  ? _primary
                                  : Colors.black.withValues(alpha: 0.65),
                              accent: sel
                                  ? _accent
                                  : Colors.black.withValues(alpha: 0.35),
                              size: 70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            localeService.tr(b.nameKey),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: sel ? _primary : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // ── Renk modu toggle ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _targetChip(
                    label: localeService.tr('primary_color'),
                    active: !_editingAccent,
                    onTap: () => setState(() => _editingAccent = false),
                  ),
                  const SizedBox(width: 8),
                  _targetChip(
                    label: localeService.tr('accent_color'),
                    active: _editingAccent,
                    onTap: () => setState(() => _editingAccent = true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ── Renk paleti ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _palette)
                    GestureDetector(
                      onTap: () => _applyColor(c),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (_editingAccent ? _accent : _primary)
                                        .toARGB32() ==
                                    c.toARGB32()
                                ? Colors.black
                                : Colors.black.withValues(alpha: 0.15),
                            width: (_editingAccent ? _accent : _primary)
                                        .toARGB32() ==
                                    c.toARGB32()
                                ? 2.5
                                : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? _primary.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? _primary : Colors.black.withValues(alpha: 0.12),
              width: active ? 1.6 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? _primary : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Veri modelleri ──────────────────────────────────────────────────────────

class _Buddy {
  final String id;
  final String nameKey;
  final _BuddyShape shape;
  const _Buddy(this.id, this.nameKey, this.shape);
}

enum _BuddyShape { classic, owl, cat, bear, space, mini }

// ─── Robot avatar — CustomPaint ile ─────────────────────────────────────────

class _BuddyAvatar extends StatelessWidget {
  final _BuddyShape shape;
  final Color primary;
  final Color accent;
  final double size;
  const _BuddyAvatar({
    required this.shape,
    required this.primary,
    required this.accent,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BuddyPainter(shape: shape, primary: primary, accent: accent),
      ),
    );
  }
}

class _BuddyPainter extends CustomPainter {
  final _BuddyShape shape;
  final Color primary;
  final Color accent;
  _BuddyPainter({required this.shape, required this.primary, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    switch (shape) {
      case _BuddyShape.classic:
        _paintClassic(canvas, size);
        break;
      case _BuddyShape.owl:
        _paintOwl(canvas, size);
        break;
      case _BuddyShape.cat:
        _paintCat(canvas, size);
        break;
      case _BuddyShape.bear:
        _paintBear(canvas, size);
        break;
      case _BuddyShape.space:
        _paintSpace(canvas, size);
        break;
      case _BuddyShape.mini:
        _paintMini(canvas, size);
        break;
    }
  }

  // Ortak araçlar
  Paint _body() => Paint()..color = primary..style = PaintingStyle.fill;
  Paint _accent() => Paint()..color = accent..style = PaintingStyle.fill;
  Paint _outline([double w = 120]) => Paint()
    ..color = Colors.black.withValues(alpha: 0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * 0.012;
  Paint _white() => Paint()..color = Colors.white..style = PaintingStyle.fill;

  void _eyes(Canvas canvas, Size size,
      {double dy = 0.48, double radius = 0.07}) {
    final w = size.width;
    final r = w * radius;
    final eyeY = size.height * dy;
    final leftX = w * 0.38;
    final rightX = w * 0.62;
    canvas.drawCircle(Offset(leftX, eyeY), r, _white());
    canvas.drawCircle(Offset(rightX, eyeY), r, _white());
    // Pupils
    final pupil = Paint()..color = Colors.black;
    canvas.drawCircle(Offset(leftX, eyeY), r * 0.55, pupil);
    canvas.drawCircle(Offset(rightX, eyeY), r * 0.55, pupil);
    // Shine
    final shine = Paint()..color = Colors.white;
    canvas.drawCircle(
        Offset(leftX + r * 0.25, eyeY - r * 0.25), r * 0.22, shine);
    canvas.drawCircle(
        Offset(rightX + r * 0.25, eyeY - r * 0.25), r * 0.22, shine);
  }

  void _smile(Canvas canvas, Size size) {
    final w = size.width;
    final rect = Rect.fromCenter(
      center: Offset(w * 0.5, size.height * 0.66),
      width: w * 0.22,
      height: w * 0.12,
    );
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0.2, 3.14 - 0.4, false, p);
  }

  // 1. Classic robot — yuvarlatılmış kare kafa + anten
  void _paintClassic(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Antenna
    final antBase = Offset(w * 0.5, h * 0.18);
    canvas.drawLine(antBase, Offset(w * 0.5, h * 0.08),
        Paint()
          ..color = primary
          ..strokeWidth = w * 0.025
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(Offset(w * 0.5, h * 0.06), w * 0.05, _accent());
    // Head
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.15, h * 0.18, w * 0.7, h * 0.68),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(rect, _body());
    canvas.drawRRect(rect, _outline(w));
    // Visor strip
    final visor = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, h * 0.36, w * 0.56, h * 0.22),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(visor,
        Paint()..color = Colors.black.withValues(alpha: 0.85));
    _eyes(canvas, size, dy: 0.47, radius: 0.065);
    _smile(canvas, size);
  }

  // 2. Owl Bot — baykuş kulakları
  void _paintOwl(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Ear tufts
    final leftEar = Path()
      ..moveTo(w * 0.22, h * 0.22)
      ..lineTo(w * 0.30, h * 0.06)
      ..lineTo(w * 0.40, h * 0.22)
      ..close();
    final rightEar = Path()
      ..moveTo(w * 0.60, h * 0.22)
      ..lineTo(w * 0.70, h * 0.06)
      ..lineTo(w * 0.78, h * 0.22)
      ..close();
    canvas.drawPath(leftEar, _body());
    canvas.drawPath(rightEar, _body());
    canvas.drawPath(leftEar, _outline(w));
    canvas.drawPath(rightEar, _outline(w));
    // Body (circle)
    canvas.drawCircle(
        Offset(w * 0.5, h * 0.55), w * 0.38, _body());
    canvas.drawCircle(Offset(w * 0.5, h * 0.55), w * 0.38, _outline(w));
    // Big round eyes (goggles)
    final eyeY = h * 0.48;
    canvas.drawCircle(Offset(w * 0.37, eyeY), w * 0.13, _accent());
    canvas.drawCircle(Offset(w * 0.63, eyeY), w * 0.13, _accent());
    canvas.drawCircle(Offset(w * 0.37, eyeY), w * 0.08, _white());
    canvas.drawCircle(Offset(w * 0.63, eyeY), w * 0.08, _white());
    final pupil = Paint()..color = Colors.black;
    canvas.drawCircle(Offset(w * 0.37, eyeY), w * 0.04, pupil);
    canvas.drawCircle(Offset(w * 0.63, eyeY), w * 0.04, pupil);
    // Beak
    final beak = Path()
      ..moveTo(w * 0.5, h * 0.60)
      ..lineTo(w * 0.44, h * 0.68)
      ..lineTo(w * 0.56, h * 0.68)
      ..close();
    canvas.drawPath(beak, _accent());
  }

  // 3. Cat Bot — kedi kulakları
  void _paintCat(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Ears
    final leftEar = Path()
      ..moveTo(w * 0.22, h * 0.30)
      ..lineTo(w * 0.28, h * 0.06)
      ..lineTo(w * 0.42, h * 0.25)
      ..close();
    final rightEar = Path()
      ..moveTo(w * 0.58, h * 0.25)
      ..lineTo(w * 0.72, h * 0.06)
      ..lineTo(w * 0.78, h * 0.30)
      ..close();
    canvas.drawPath(leftEar, _body());
    canvas.drawPath(rightEar, _body());
    canvas.drawPath(leftEar, _outline(w));
    canvas.drawPath(rightEar, _outline(w));
    // Head (rounded square)
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.22, w * 0.64, h * 0.66),
      Radius.circular(w * 0.22),
    );
    canvas.drawRRect(rect, _body());
    canvas.drawRRect(rect, _outline(w));
    _eyes(canvas, size, dy: 0.50, radius: 0.075);
    // Nose
    final nose = Path()
      ..moveTo(w * 0.47, h * 0.62)
      ..lineTo(w * 0.53, h * 0.62)
      ..lineTo(w * 0.5, h * 0.67)
      ..close();
    canvas.drawPath(nose, _accent());
    // Whiskers
    final wp = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..strokeWidth = w * 0.012;
    canvas.drawLine(
        Offset(w * 0.22, h * 0.66), Offset(w * 0.40, h * 0.68), wp);
    canvas.drawLine(
        Offset(w * 0.60, h * 0.68), Offset(w * 0.78, h * 0.66), wp);
  }

  // 4. Bear Bot — ayı kulakları (yan yuvarlak)
  void _paintBear(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Ears
    canvas.drawCircle(Offset(w * 0.24, h * 0.26), w * 0.11, _body());
    canvas.drawCircle(Offset(w * 0.76, h * 0.26), w * 0.11, _body());
    canvas.drawCircle(Offset(w * 0.24, h * 0.26), w * 0.11, _outline(w));
    canvas.drawCircle(Offset(w * 0.76, h * 0.26), w * 0.11, _outline(w));
    // Inner ears
    canvas.drawCircle(Offset(w * 0.24, h * 0.26), w * 0.06, _accent());
    canvas.drawCircle(Offset(w * 0.76, h * 0.26), w * 0.06, _accent());
    // Head
    canvas.drawCircle(Offset(w * 0.5, h * 0.55), w * 0.36, _body());
    canvas.drawCircle(Offset(w * 0.5, h * 0.55), w * 0.36, _outline(w));
    // Snout
    final snout = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.66),
        width: w * 0.30,
        height: h * 0.20,
      ),
      Radius.circular(w * 0.1),
    );
    canvas.drawRRect(snout, _accent());
    _eyes(canvas, size, dy: 0.50, radius: 0.055);
    // Nose
    canvas.drawCircle(Offset(w * 0.5, h * 0.62), w * 0.035, Paint()..color = Colors.black);
    // Mouth
    final m = Paint()
      ..color = Colors.black
      ..strokeWidth = w * 0.015
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.5, h * 0.66), Offset(w * 0.5, h * 0.70), m);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(w * 0.45, h * 0.72), width: w * 0.10, height: h * 0.04),
        0,
        3.14,
        false,
        m);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(w * 0.55, h * 0.72), width: w * 0.10, height: h * 0.04),
        0,
        3.14,
        false,
        m);
  }

  // 5. Space Bot — astronot kasket
  void _paintSpace(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Helmet outer
    canvas.drawCircle(Offset(w * 0.5, h * 0.52), w * 0.42, _body());
    canvas.drawCircle(Offset(w * 0.5, h * 0.52), w * 0.42, _outline(w));
    // Visor (dark glass)
    final visor = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.52),
        width: w * 0.52,
        height: h * 0.30,
      ),
      Radius.circular(w * 0.15),
    );
    canvas.drawRRect(visor,
        Paint()..color = Colors.black.withValues(alpha: 0.88));
    // Reflection on visor
    final refl = Path()
      ..moveTo(w * 0.28, h * 0.48)
      ..lineTo(w * 0.40, h * 0.42)
      ..lineTo(w * 0.42, h * 0.56)
      ..lineTo(w * 0.30, h * 0.62)
      ..close();
    canvas.drawPath(refl, Paint()..color = accent.withValues(alpha: 0.6));
    // Side antennas
    final ant = Paint()
      ..color = primary
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.14, h * 0.45), Offset(w * 0.06, h * 0.32), ant);
    canvas.drawLine(Offset(w * 0.86, h * 0.45), Offset(w * 0.94, h * 0.32), ant);
    canvas.drawCircle(Offset(w * 0.06, h * 0.30), w * 0.045, _accent());
    canvas.drawCircle(Offset(w * 0.94, h * 0.30), w * 0.045, _accent());
  }

  // 6. Mini Bot — küçük yuvarlak beden, kalpli LED
  void _paintMini(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Body (rounded rectangle)
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, h * 0.20, w * 0.56, h * 0.60),
      Radius.circular(w * 0.22),
    );
    canvas.drawRRect(rect, _body());
    canvas.drawRRect(rect, _outline(w));
    _eyes(canvas, size, dy: 0.42, radius: 0.06);
    // Heart LED
    final heart = Path();
    final cx = w * 0.5;
    final cy = h * 0.66;
    final s = w * 0.08;
    heart.moveTo(cx, cy + s * 0.7);
    heart.cubicTo(cx - s * 1.3, cy - s * 0.2, cx - s * 0.3, cy - s,
        cx, cy - s * 0.2);
    heart.cubicTo(cx + s * 0.3, cy - s, cx + s * 1.3, cy - s * 0.2,
        cx, cy + s * 0.7);
    canvas.drawPath(heart, _accent());
    // Chest screws
    final screw = Paint()..color = Colors.black.withValues(alpha: 0.7);
    canvas.drawCircle(Offset(w * 0.28, h * 0.76), w * 0.02, screw);
    canvas.drawCircle(Offset(w * 0.72, h * 0.76), w * 0.02, screw);
    // Feet
    canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.30, h * 0.84, w * 0.14, h * 0.10),
          Radius.circular(w * 0.04),
        ),
        _body());
    canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.56, h * 0.84, w * 0.14, h * 0.10),
          Radius.circular(w * 0.04),
        ),
        _body());
  }

  @override
  bool shouldRepaint(covariant _BuddyPainter old) {
    return old.shape != shape || old.primary != primary || old.accent != accent;
  }
}
