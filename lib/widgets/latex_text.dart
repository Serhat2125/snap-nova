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
  // AI bazen çift escape'lenmiş yazıyor: \\( ... \\) → tek escape'e indir.
  s = s.replaceAll(r'\\(', r'\(').replaceAll(r'\\)', r'\)');
  s = s.replaceAll(r'\\[', r'\[').replaceAll(r'\\]', r'\]');
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
  // AI bazen Türkçe karakteri LaTeX içinde "\text{...}" olmadan koyuyor —
  // flutter_math_fork bunu silebiliyor. \mathrm{...} dışındaki Türkçe
  // ifadelerde \text{} sarması yapma; AI prompt'u bunu kontrol ediyor.
  return s;
}

// ─── Yardımcı: inline $...$ + **bold** parçacıklarını InlineSpan'e çevirir.
//   Önce metni **...** ile bölüp her parçada $...$ math'ı işliyoruz.
List<InlineSpan> _inlineMath(String text, TextStyle base) {
  // 1) İlk geçiş: **bold** segmentlerini ayır.
  final boldRe = RegExp(r'\*\*([^*\n]+)\*\*');
  final segments = <_MdSeg>[];
  int last = 0;
  for (final m in boldRe.allMatches(text)) {
    if (m.start > last) {
      segments.add(_MdSeg(text.substring(last, m.start), false));
    }
    segments.add(_MdSeg(m.group(1)!, true));
    last = m.end;
  }
  if (last < text.length) {
    segments.add(_MdSeg(text.substring(last), false));
  }

  // 2) Her segmentte $...$ math işle.
  final out = <InlineSpan>[];
  for (final seg in segments) {
    final segStyle = seg.bold
        ? base.copyWith(fontWeight: FontWeight.w800)
        : base;
    out.addAll(_mathSpans(seg.text, segStyle));
  }
  return out;
}

class _MdSeg {
  final String text;
  final bool bold;
  const _MdSeg(this.text, this.bold);
}

List<InlineSpan> _mathSpans(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'(?<!\$)\$(?!\$)([^$\n]+?)(?<!\$)\$(?!\$)');
  int last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: style));
    }
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Math.tex(
          m.group(1)!.trim(),
          textStyle: style.copyWith(letterSpacing: 0),
          onErrorFallback: (_) =>
              Text(m.group(0)!, style: style.copyWith(color: Colors.black54)),
        ),
      ),
    ));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: style));
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
  // Dershane tarzı alt başlık: "▸ 1. Başlık Adı" — _SubHeadingRow ile
  // mavi accent renk + bold + Title Case rendering.
  static final _reSubHead = RegExp(r'^▸\s*(\d+)\.?\s+(.+)');
  // Çerçeveli inline not: "📦 NOT: ..." veya "📦 NOT KUTUSU: ..."
  static final _reBoxNote = RegExp(
    r'^📦\s*(NOT(?:\s*KUTUSU)?|NOTE)\s*:\s*(.+)',
    caseSensitive: false,
  );
  // Önemli Bilgi inline kutusu — yeni format (💡 Önemli Bilgi) +
  // legacy format (⚠️ KRİTİK UYARI / 🔬 QuAlsar Notu). Hepsi tek tip
  // "💡 ÖNEMLİ BİLGİ" kutusunda render edilir.
  static final _reInlineNote = RegExp(
    r'^(?:💡\s*ÖNEMLİ\s*BİLGİ|💡\s*Önemli\s*Bilgi|📌\s*ÖNEMLİ\s*BİLGİ|'
    r'⚠️\s*(?:KRİTİK\s*UYARI|UYARI)|🔬\s*(?:QuAlsar\s*Notu|Not))\s*:\s*(.+)',
    caseSensitive: false,
  );
  // Bullet satırı: "• ..." — hanging indent (devam satırı ilk metnin
  // başlangıç hizasına gelir, bullet'ın ALTINA değil).
  static final _reBullet = RegExp(r'^(•)\s+(.+)');
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

    int i = 0;
    while (i < lines.length) {
      // Markdown tablosu: header satırı (| ... |) + separator (|---|---|)
      // ardışık ise bir _TableBlock olarak render et.
      if (_isTableStart(lines, i)) {
        final end = _findTableEnd(lines, i);
        if (children.isNotEmpty) children.add(SizedBox(height: gap * 2));
        children.add(_TableBlock(
          lines: lines.sublist(i, end),
          fontSize: fontSize,
        ));
        if (end < lines.length) children.add(SizedBox(height: gap * 2));
        i = end;
        continue;
      }
      if (i > 0 && children.isNotEmpty) children.add(SizedBox(height: gap));
      final w = _buildLine(lines[i]);
      if (w != null) children.add(w);
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// `lines[i]` "| col | col |" header'ı ve `lines[i+1]` "|---|---|"
  /// separator'ı mı? Tablo başlangıcı algıla.
  static bool _isTableStart(List<String> lines, int i) {
    if (i + 1 >= lines.length) return false;
    final header = lines[i].trim();
    final sep = lines[i + 1].trim();
    if (!header.startsWith('|') || !header.endsWith('|')) return false;
    if (!sep.startsWith('|') || !sep.endsWith('|')) return false;
    // Separator yalnız "-", ":", "|", whitespace içerir.
    return RegExp(r'^[\|\-\:\s]+$').hasMatch(sep) && sep.contains('-');
  }

  /// Tablonun sonunu bul (boş satıra veya non-table satıra kadar).
  static int _findTableEnd(List<String> lines, int start) {
    int i = start + 2; // header + separator atla
    while (i < lines.length) {
      final t = lines[i].trim();
      if (t.isEmpty) break;
      if (!t.startsWith('|') || !t.endsWith('|')) break;
      i++;
    }
    return i;
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

    // 6.1 Dershane alt başlığı: "▸ N. Başlık Adı"
    final shm = _reSubHead.firstMatch(trimmed);
    if (shm != null) {
      return _SubHeadingRow(
        number: shm.group(1)!,
        title: shm.group(2)!.trim(),
        fontSize: fontSize,
      );
    }

    // 6.2 Çerçeveli inline not: "📦 NOT: ..."
    final bxm = _reBoxNote.firstMatch(trimmed);
    if (bxm != null) {
      return _BoxedCallout(
        label: bxm.group(1)!.toUpperCase(),
        body: bxm.group(2)!.trim(),
        accent: const Color(0xFF0EA5E9), // sky blue
        icon: '📦',
        fontSize: fontSize,
      );
    }

    // 6.3 Inline 💡 Önemli Bilgi: ... (legacy ⚠️ Kritik Uyarı / 🔬 QuAlsar
    // Notu da aynı kutuda render edilir — tek tip "Önemli Bilgi" görünümü).
    final note = _reInlineNote.firstMatch(trimmed);
    if (note != null) {
      return _BoxedCallout(
        label: 'Önemli Bilgi',
        body: note.group(1)!.trim(),
        accent: const Color(0xFFD97706), // amber-600
        icon: '💡',
        fontSize: fontSize,
      );
    }

    // 6.5 Bullet satırı "• …" — hanging indent.
    final bul = _reBullet.firstMatch(trimmed);
    if (bul != null) {
      return _BulletRow(
        bullet: bul.group(1)!,
        rest: bul.group(2)!,
        fontSize: fontSize,
        lineHeight: lineHeight,
        base: base,
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

// ─── Dershane alt başlığı: "▸ N. Başlık Adı" ─────────────────────────────────
//   Mavi accent renk + büyük font + kalın; sol tarafta dik renk şeridi.
class _SubHeadingRow extends StatelessWidget {
  final String number;
  final String title;
  final double fontSize;
  const _SubHeadingRow({
    required this.number,
    required this.title,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2563EB);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
        decoration: BoxDecoration(
          // Alt başlık zemini — kart zemininden hafif farklı bir ton
          // (görsel hiyerarşi için yumuşak gri-mavi tint).
          color: const Color(0xFFF3F6FB),
          borderRadius: BorderRadius.circular(8),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Sol dikey renk şeridi — başlığı görsel olarak vurgular.
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  number,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: fontSize - 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                    fontSize: fontSize + 1,
                    height: 1.25,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bullet satırı: "• …" — hanging indent (devam satırı bullet altına
//    DEĞİL, ilk metnin başlangıç hizasına gelir).
class _BulletRow extends StatelessWidget {
  final String bullet;
  final String rest;
  final double fontSize, lineHeight;
  final TextStyle base;
  const _BulletRow({
    required this.bullet,
    required this.rest,
    required this.fontSize,
    required this.lineHeight,
    required this.base,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 1, bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sabit kutu — sağındaki metin Expanded olduğundan wrap olunca
          // devam satırı bunun ALTINA gelmez, metnin başlangıç hizasına gelir.
          SizedBox(
            width: fontSize * 0.95,
            child: Text(
              bullet,
              style: base.copyWith(
                color: const Color(0xFF6B7280),
                fontWeight: FontWeight.w900,
                height: lineHeight,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: RichText(
              text: TextSpan(style: base, children: _inlineMath(rest, base)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Çerçeveli inline not: "📦 NOT", "💡 Önemli Bilgi"
//   Renk kart içinde önemli bilgileri vurgular. Yarı şeffaf zemin + ince
//   kenarlık + sol şerit + bold etiket.
class _BoxedCallout extends StatelessWidget {
  final String label;
  final String body;
  final Color accent;
  final String icon;
  final double fontSize;
  const _BoxedCallout({
    required this.label,
    required this.body,
    required this.accent,
    required this.icon,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: TextStyle(fontSize: fontSize)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: fontSize - 0.5,
                  height: 1.35,
                  color: Colors.black,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.15,
                    ),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Markdown tablosu — | col | col | + |---|---| ardışıklığını yakalar.
//  Hücreler de inline math + bold destekler (_inlineMath helper'ını kullanır).
// ═══════════════════════════════════════════════════════════════════════════════
class _TableBlock extends StatelessWidget {
  final List<String> lines;
  final double fontSize;
  const _TableBlock({required this.lines, required this.fontSize});

  /// "| a | b | c |" → ['a', 'b', 'c']
  List<String> _parseRow(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((e) => e.trim()).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (lines.length < 2) return const SizedBox.shrink();
    final header = _parseRow(lines[0]);
    final dataRows = lines.skip(2).map(_parseRow).toList();
    final colCount = header.length;
    if (colCount == 0) return const SizedBox.shrink();

    List<String> normalize(List<String> row) {
      if (row.length == colCount) return row;
      if (row.length < colCount) {
        return [...row, for (var i = 0; i < colCount - row.length; i++) ''];
      }
      return row.sublist(0, colCount);
    }

    const accent = Color(0xFF7C3AED);
    final borderColor = Colors.black.withValues(alpha: 0.18);
    const stripeColor = Color(0xFFF8FAFC);

    Widget cell(String content, {required bool isHeader}) {
      final base = TextStyle(
        fontSize: fontSize - 1,
        height: 1.4,
        color: isHeader ? Colors.white : Colors.black87,
        fontWeight: isHeader ? FontWeight.w800 : FontWeight.w500,
        letterSpacing: 0.05,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text.rich(
          TextSpan(children: _inlineMath(content, base)),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 40,
          ),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.symmetric(
              inside: BorderSide(color: borderColor, width: 0.6),
            ),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: accent),
                children: [
                  for (final h in normalize(header)) cell(h, isHeader: true),
                ],
              ),
              for (var r = 0; r < dataRows.length; r++)
                TableRow(
                  decoration: BoxDecoration(
                    color: r.isOdd ? stripeColor : Colors.white,
                  ),
                  children: [
                    for (final c in normalize(dataRows[r]))
                      cell(c, isHeader: false),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
