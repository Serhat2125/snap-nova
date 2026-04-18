import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../theme/app_theme.dart';
import 'media_cards.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  LatexText — AI yanıtlarını LaTeX destekli, stilize şekilde render eder.
//
//  Desteklenen sözdizimi (tercih edilen + eski):
//    \( ... \)  → Satır içi (inline) LaTeX  ★ yeni standart
//    \[ ... \]  → Bağımsız (block / display) LaTeX  ★ yeni standart
//    $...$      → Satır içi (eski, geriye uyum)
//    $$...$$    → Bağımsız (eski, geriye uyum)
//
//  Otomatik vurgulanan etiketler:
//    "N. Adım:"    → gradient badge + cyan
//    "Sonuç:"      → yeşil
//    "Püf Nokta:"  → amber
//    "BÖLÜM N —"   → mor + sol çizgi
//    "→"           → cyan
//    "SORU N:"     → cyan
//    Formül: / Kural: / Gerekçe: / Tespit: / vb. → cyan
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Giriş normalizasyonu: \( \) \[ \] → $ $ / $$ $$ ──────────────────────────
// AI dolar işareti kullanmak zorunda kalmasın diye \( ... \) ve \[ ... \]
// sözdizimlerini kabul ediyoruz; burada mevcut akışa uygun biçime çeviriyoruz.
String _normalizeLatex(String input) {
  var s = input;
  // \[ formula \]  →  $$formula$$   (çok satırlı olabilir)
  s = s.replaceAllMapped(
    RegExp(r'\\\[([\s\S]*?)\\\]'),
    (m) => '\$\$${m.group(1)!.trim()}\$\$',
  );
  // \( formula \)  →  $formula$
  s = s.replaceAllMapped(
    RegExp(r'\\\(([\s\S]*?)\\\)'),
    (m) => '\$${m.group(1)!.trim()}\$',
  );
  return s;
}

// ─── Yardımcı: inline $...$ parçacıklarını InlineSpan listesine çevirir ───────

List<InlineSpan> _inlineMath(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  // Sadece tek $...$ → block $$$...$$$ ile karışmasın
  final re = RegExp(r'(?<!\$)\$(?!\$)([^$\n]+?)(?<!\$)\$(?!\$)');
  int last = 0;

  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: base));
    }
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Math.tex(
          m.group(1)!.trim(),
          textStyle: base.copyWith(letterSpacing: 0),
          onErrorFallback: (_) =>
              Text(m.group(0)!, style: base.copyWith(color: Colors.black54)),
        ),
      ),
    ));
    last = m.end;
  }

  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: base));
  }
  return spans;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Ana widget
// ═══════════════════════════════════════════════════════════════════════════════

class LatexText extends StatelessWidget {
  final String text;
  final double fontSize;
  final double lineHeight;

  const LatexText(
    this.text, {
    super.key,
    this.fontSize = 15,
    this.lineHeight = 1.75,
  });

  // ── Regex sabitleri ─────────────────────────────────────────────────────────
  static final _reStep    = RegExp(r'^(\d+)\. Adım:');
  static final _reSonuc   = RegExp(r'^(Sonuç:)');
  static final _reSoru    = RegExp(r'^(SORU \d+:)');
  static final _reArrow   = RegExp(r'^(→)');
  static final _reBolum   = RegExp(r'^(BÖLÜM \d+\s*[—\-])');
  static final _reDers    = RegExp(r'^\[Ders:\s*(.+?)\]');
  static final _reVideo   = RegExp(r'^\[VIDEO:\s*"(.+?)"\s*\|\s*(.+?)\]\s*$');
  static final _reWeb     = RegExp(r'^\[WEB:\s*"(.+?)"\s*\|\s*(.+?)\]\s*$');
  static final _reTest    = RegExp(r'^\[TEST:\s*"(.+?)"\s*\|\s*(.+?)\]\s*$');
  static final _reSpecial = RegExp(
    r'^(Kural\s*:|Gerekçe\s*:|İşlem\s*:|Tespit\s*:|Formül\s*:|Hesap\s*:|'
    r'Cevap\s*:|Düşünce Zinciri\s*:|Düşünce\s*:|Ara Kontrol\s*:|Doğrulama\s*:|'
    r'Verilenlerin Analizi\s*:|Verilenler\s*:|Kavram\s*:|Uygula\s*:|'
    r'Hesapla\s*:|Yorumla\s*:|Açıkla\s*:|Püf Nokta\s*:|'
    r'Yaklaşım\s*:|Alternatif\s*:|Soru\s*:|İpucu\s*:)',
  );
  static final _rePuf = RegExp(r'^(Püf Nokta\s*:)');

  @override
  Widget build(BuildContext context) {
    final lines = _normalizeLatex(text).split('\n');
    final gap   = (fontSize * (lineHeight - 1.0) * 0.45).clamp(1.0, 10.0);
    final children = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      if (i > 0) children.add(SizedBox(height: gap));
      final w = _buildLine(lines[i]);
      if (w != null) children.add(w);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // ── Satır ayırt edici ───────────────────────────────────────────────────────
  Widget? _buildLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return const SizedBox(height: 3);

    final base = TextStyle(
      color: Colors.black,
      fontSize: fontSize,
      height: lineHeight,
      letterSpacing: 0.1,
    );

    // 1. [Ders: X] etiketi — çözüm kartında gizli (kullanıcı istedi)
    if (_reDers.firstMatch(trimmed) != null) {
      return const SizedBox.shrink();
    }

    // 2. [VIDEO: "title" | query] — YouTube kartı
    final vm = _reVideo.firstMatch(trimmed);
    if (vm != null) {
      return VideoCard(title: vm.group(1)!.trim(), query: vm.group(2)!.trim());
    }

    // 3. [WEB: "title" | query] — Web/kaynak kartı
    final wm = _reWeb.firstMatch(trimmed);
    if (wm != null) {
      return WebCard(title: wm.group(1)!.trim(), query: wm.group(2)!.trim());
    }

    // 4. [TEST: "title" | query] — Test platform kartı
    final tm = _reTest.firstMatch(trimmed);
    if (tm != null) {
      return TestCard(title: tm.group(1)!.trim(), query: tm.group(2)!.trim());
    }

    // 5. Block math $$...$$
    if (trimmed.startsWith(r'$$') &&
        trimmed.endsWith(r'$$') &&
        trimmed.length > 4) {
      final formula = trimmed.substring(2, trimmed.length - 2).trim();
      return _BlockMath(formula: formula, fontSize: fontSize);
    }

    // 6. BÖLÜM N — başlığı
    final bm = _reBolum.firstMatch(line);
    if (bm != null) {
      return _SectionRow(
        label: bm.group(1)!,
        rest: line.substring(bm.end).trim(),
        fontSize: fontSize,
        lineHeight: lineHeight,
      );
    }

    // 7. Numaralı adım "N. Adım:"
    final sm = _reStep.firstMatch(line);
    if (sm != null) {
      return _StepRow(
        num: int.tryParse(sm.group(1)!) ?? 0,
        rest: line.substring(sm.end),
        fontSize: fontSize,
        lineHeight: lineHeight,
        base: base,
      );
    }

    // 4. Sonuç:
    final som = _reSonuc.firstMatch(line);
    if (som != null) {
      return _LabelRow(
        label: som.group(1)!,
        rest: line.substring(som.end),
        color: const Color(0xFF22C55E),
        bold: true,
        fontSize: fontSize,
        base: base,
      );
    }

    // 5. SORU N:
    final sqm = _reSoru.firstMatch(line);
    if (sqm != null) {
      return _LabelRow(
        label: sqm.group(1)!,
        rest: line.substring(sqm.end),
        color: AppColors.cyan,
        bold: true,
        fontSize: fontSize,
        base: base,
      );
    }

    // 6. → ok işareti
    final am = _reArrow.firstMatch(line);
    if (am != null) {
      return _LabelRow(
        label: '→',
        rest: line.substring(am.end),
        color: AppColors.cyan,
        bold: true,
        fontSize: fontSize,
        base: base,
      );
    }

    // 7. Özel etiket (Formül:, Gerekçe:, Püf Nokta: vb.)
    final pm = _rePuf.firstMatch(line);
    if (pm != null) {
      return _LabelRow(
        label: pm.group(1)!,
        rest: line.substring(pm.end),
        color: const Color(0xFFF59E0B),
        bold: true,
        fontSize: fontSize,
        base: base,
      );
    }

    final sp = _reSpecial.firstMatch(line);
    if (sp != null) {
      return _LabelRow(
        label: sp.group(1)!,
        rest: line.substring(sp.end),
        color: AppColors.cyan,
        bold: true,
        fontSize: fontSize,
        base: base,
      );
    }

    // 8. Normal satır (inline LaTeX olabilir)
    return RichText(
      text: TextSpan(style: base, children: _inlineMath(line, base)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Alt widget'lar
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Block Math: $$formula$$ ──────────────────────────────────────────────────
class _BlockMath extends StatelessWidget {
  final String formula;
  final double fontSize;
  const _BlockMath({required this.formula, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        // Beyaza yakın, çok hafif gri-mavi tint — formüller için ayırıcı.
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Center(
        child: Math.tex(
          formula,
          textStyle: TextStyle(color: Colors.black, fontSize: fontSize + 2),
          onErrorFallback: (_) => Text(
            '\$\$$formula\$\$',
            style: TextStyle(
              color: Colors.black54,
              fontSize: fontSize - 1,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bölüm başlığı: BÖLÜM N — ────────────────────────────────────────────────
class _SectionRow extends StatelessWidget {
  final String label, rest;
  final double fontSize, lineHeight;
  const _SectionRow({
    required this.label,
    required this.rest,
    required this.fontSize,
    required this.lineHeight,
  });

  static const _color = Color(0xFFA855F7);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: fontSize + 6,
            decoration: BoxDecoration(
              color: _color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: fontSize + 0.5,
                  fontWeight: FontWeight.w800,
                  height: lineHeight,
                  letterSpacing: 0.1,
                ),
                children: [
                  TextSpan(text: label, style: const TextStyle(color: _color)),
                  if (rest.isNotEmpty)
                    TextSpan(
                      text: ' $rest',
                      style: const TextStyle(
                          color: Colors.black),
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

// ─── Numaralı adım: gradient badge + Adım: ───────────────────────────────────
class _StepRow extends StatelessWidget {
  final int num;
  final String rest;
  final double fontSize, lineHeight;
  final TextStyle base;
  const _StepRow({
    required this.num,
    required this.rest,
    required this.fontSize,
    required this.lineHeight,
    required this.base,
  });

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF22C55E);
    // Arka plan beyaz — sadece "N. Adım:" etiketi yeşil olacak.
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: RichText(
        text: TextSpan(
          style: base,
          children: [
            TextSpan(
              text: '$num. Adım: ',
              style: base.copyWith(
                color: green,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
            ..._inlineMath(rest, base.copyWith(color: Colors.black)),
          ],
        ),
      ),
    );
  }
}

// ─── Genel etiketli satır: Sonuç:, →, Formül: vb. ────────────────────────────
class _LabelRow extends StatelessWidget {
  final String label, rest;
  final Color color;
  final bool bold;
  final double fontSize;
  final TextStyle base;

  const _LabelRow({
    required this.label,
    required this.rest,
    required this.color,
    required this.bold,
    required this.fontSize,
    required this.base,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: base,
        children: [
          TextSpan(
            text: label,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          ..._inlineMath(rest, base),
        ],
      ),
    );
  }
}
