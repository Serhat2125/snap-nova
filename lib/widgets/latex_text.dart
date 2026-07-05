import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../services/wiki_image_service.dart';
import '../services/runtime_translator.dart';
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
  // Soru başlığında ders adı temizliği — AI prompt'a uymadığında defansif.
  // "SORU 4: Coğrafya" / "4. Coğrafya — Aşağıdakilerden..." / "4. Coğrafya:"
  // gibi başlıkları "SORU 4:" ya da "4." ile sınırla; ders adı, kategori
  // veya "—/-/:" ile sonlanan tek kelimelik takıntıyı düşür. Konu cümlesi
  // (5+ kelime) varsa elleme — sadece tek-kelimelik ders adı ekini temizle.
  const subjects = [
    'Matematik','Fizik','Kimya','Biyoloji','Coğrafya','Cografya','Tarih',
    'Edebiyat','Felsefe','Türkçe','Turkce','İngilizce','Ingilizce',
    'Geometri','Sosyal','Din','Mantık','Mantik','Almanca','Fransızca',
    'Fransizca','Sanat','Müzik','Muzik',
  ];
  final subjAlt = subjects.join('|');
  // "SORU N: <DersAdı>" → "SORU N:" (satır sonunda veya — / - / : öncesi)
  s = s.replaceAllMapped(
    RegExp(r'^(SORU\s*\d+\s*:)\s*(' + subjAlt + r')\s*([—–\-:]?)\s*$',
        multiLine: true),
    (m) => m.group(1)!,
  );
  // "SORU N: Coğrafya — Aşağıdakilerden..." → "SORU N: Aşağıdakilerden..."
  s = s.replaceAllMapped(
    RegExp(r'^(SORU\s*\d+\s*:)\s*(' + subjAlt + r')\s*[—–\-:]\s*',
        multiLine: true),
    (m) => '${m.group(1)!} ',
  );
  // "4. Coğrafya — Aşağıdakilerden..." → "4. Aşağıdakilerden..."
  s = s.replaceAllMapped(
    RegExp(r'^(\d+\.)\s*(' + subjAlt + r')\s*[—–\-:]\s*', multiLine: true),
    (m) => '${m.group(1)!} ',
  );
  // "4. Coğrafya" tek başına (satır sonu) → "4."
  s = s.replaceAllMapped(
    RegExp(r'^(\d+\.)\s*(' + subjAlt + r')\s*$', multiLine: true),
    (m) => m.group(1)!,
  );

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

// ─── Yardımcı: inline math + **bold** + ==highlight== + __underline__ ──────
//   Üç markdown markeri tek geçişte parse edilir; her segment kendi flag'lerini
//   taşır. Bold dışı düz parçalarda kalmış serseri *italic* / *** kalıntıları
//   _stripStrayAsterisks ile temizlenir (matematiğe dokunmadan).
List<InlineSpan> _inlineMath(String text, TextStyle base) {
  // 0) Üçlü asteriks'i ikiliye düşür: ***x*** → **x**. Aksi halde iç ikili
  //    eşleşince dışta tek asteriks kalır ve render'da görünür.
  var src = text.replaceAllMapped(
    RegExp(r'\*\*\*([^*\n]+?)\*\*\*'),
    (m) => '**${m.group(1)}**',
  );

  // 1) Tek pass'te tüm markerleri ayrıştır.
  //    ** → bold (group 1) | == → highlight (group 2) | __ → underline (group 3)
  final markerRe = RegExp(
    r'\*\*([^*\n]+)\*\*|==([^=\n]+)==|__([^_\n]+)__',
  );
  final segments = <_MdSeg>[];
  int last = 0;
  for (final m in markerRe.allMatches(src)) {
    if (m.start > last) {
      segments.add(_MdSeg(text: src.substring(last, m.start)));
    }
    if (m.group(1) != null) {
      segments.add(_MdSeg(text: m.group(1)!, bold: true));
    } else if (m.group(2) != null) {
      segments.add(_MdSeg(text: m.group(2)!, highlight: true));
    } else if (m.group(3) != null) {
      segments.add(_MdSeg(text: m.group(3)!, underline: true));
    }
    last = m.end;
  }
  if (last < src.length) {
    segments.add(_MdSeg(text: src.substring(last)));
  }

  // 2) Her segmentte $...$ math işle. Düz parçalarda asteriks kalıntılarını
  //    temizle (matematik bloklarının içine dokunmadan).
  final out = <InlineSpan>[];
  for (final seg in segments) {
    var segStyle = base;
    if (seg.bold) {
      segStyle = segStyle.copyWith(fontWeight: FontWeight.w800);
    }
    if (seg.underline) {
      segStyle = segStyle.copyWith(
        decoration: TextDecoration.underline,
        decorationColor: Color(0xFFEF4444), // kırmızı kalem
        decorationThickness: 2,
      );
    }
    if (seg.highlight) {
      segStyle = segStyle.copyWith(
        background: Paint()..color = Color(0xFFFEF08A), // sarı fosforlu kalem
      );
    }
    final isPlain = !seg.bold && !seg.highlight && !seg.underline;
    final segText = isPlain ? _stripStrayAsterisks(seg.text) : seg.text;
    out.addAll(_mathSpans(segText, segStyle));
  }
  return out;
}

// ─── Math dışı serseri asteriks temizliği ──────────────────────────────────
//   *italic* → italic (sadece içerik), tek başına kalan * → kaldır.
//   $...$ math blokları olduğu gibi korunur.
String _stripStrayAsterisks(String text) {
  if (!text.contains('*')) return text;
  // $...$ math bloklarını koru; sadece dış parçaları temizle.
  final mathRe = RegExp(r'\$[^\$\n]*\$');
  final buf = StringBuffer();
  int idx = 0;
  for (final m in mathRe.allMatches(text)) {
    if (m.start > idx) buf.write(_cleanStarsOutsideMath(text.substring(idx, m.start)));
    buf.write(m.group(0));
    idx = m.end;
  }
  if (idx < text.length) buf.write(_cleanStarsOutsideMath(text.substring(idx)));
  return buf.toString();
}

String _cleanStarsOutsideMath(String s) {
  // *italic* → italic (içerik). Word-sınırına dikkat: 2*3 gibi math benzeri
  // kalıpları korumak için lookaround kullanıyoruz.
  var t = s.replaceAllMapped(
    RegExp(r'(?<![\w*])\*([^\*\n]+?)\*(?![\w*])'),
    (m) => m.group(1)!,
  );
  // Tek başına kalan * (eşleşmeyen, dengesiz markdown) → sil.
  t = t.replaceAll('*', '');
  return t;
}

class _MdSeg {
  final String text;
  final bool bold;
  final bool highlight;
  final bool underline;
  const _MdSeg({
    required this.text,
    this.bold = false,
    this.highlight = false,
    this.underline = false,
  });
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

  // Görsel Betimlemesi: [Görsel Betimlemesi: ... şeması ...] — placeholder
  // kart olarak render edilir; gelecekte AI görsel üretimine parse edilebilir.
  static final _reVisualDesc = RegExp(
    r'^\[\s*(?:Görsel\s*Betimlemesi|Visual\s*Description)\s*:\s*(.+?)\s*\]\s*$',
    caseSensitive: false,
  );
  // ŞEMA bloğu: [ŞEMA: <title>] ile başlar, [/ŞEMA] ile biter.
  // Aradaki satırlar Unicode/ASCII çizim olarak monospace render edilir.
  // Şapkalı Ş ve klasik S — büyük/küçük harf duyarsız.
  static final _reSchemaStart = RegExp(
    r'^\[\s*(?:ŞEMA|SEMA|SCHEMA|DIAGRAM)\s*:\s*(.+?)\s*\]\s*$',
    caseSensitive: false,
  );
  static final _reSchemaEnd = RegExp(
    r'^\[\s*/\s*(?:ŞEMA|SEMA|SCHEMA|DIAGRAM)\s*\]\s*$',
    caseSensitive: false,
  );

  // Pedagojik özet kutuları — çok satırlı bloklar (başlık + sonraki maddeler):
  //   "⭐ Aklında Kalsın"  → konunun özü / en kritik maddeler (yeşil kart)
  //   "🎯 Kendini Sına"    → aktif hatırlama / mini öz-test (mor kart)
  // Başlık satırından sonra gelen madde/metin satırları boş satıra veya bir
  // sonraki bloğa/başlığa kadar kart içinde toplanır.
  // "⭐ Aklında Kalsın" (yeni) + legacy "⭐ Özet" / "⭐ Özet — 5 Bilgi"
  // (eski cache'ler) — hepsi aynı yeşil "özün özü" kartına düşer. Başlıktan
  // sonraki "— N Bilgi" gibi alt açıklama tüketilir.
  static final _reKeyTakeStart = RegExp(
    // "Özet" sonrası harf gelirse (Özetle, Özetlersek) EŞLEŞME — yalnız
    // gerçek "⭐ Özet"/"⭐ Aklında Kalsın" başlığı kutuya düşsün.
    r'^⭐\s*(?:AKLINDA\s*KALSIN|Aklında\s*Kalsın|(?:ÖZET|Özet)(?![a-zçğıöşü]))'
    r'(?:\s*[—\-][^\n:]*)?\s*:?\s*(.*)$',
    caseSensitive: false,
  );
  static final _reSelfTestStart = RegExp(
    r'^🎯\s*(?:KENDİNİ\s*SINA|Kendini\s*Sına)\s*:?\s*(.*)$',
    caseSensitive: false,
  );

  static bool _isSchemaStart(String line) =>
      _reSchemaStart.hasMatch(line.trim());

  /// Pedagojik blok (⭐/🎯) başlangıcı mı? Tip döner: 'key' | 'test' | null.
  static String? _pedagogyKind(String line) {
    final t = line.trim();
    if (_reKeyTakeStart.hasMatch(t)) return 'key';
    if (_reSelfTestStart.hasMatch(t)) return 'test';
    return null;
  }

  /// Pedagojik bloğun gövde sonunu bul: boş satır, yeni blok/başlık veya
  /// dosya sonu. (Kutu içeriği yalnızca ardışık madde/metin satırlarıdır.)
  static int _findPedagogyEnd(List<String> lines, int start) {
    int i = start + 1;
    while (i < lines.length) {
      final t = lines[i].trim();
      if (t.isEmpty) break;
      // Yeni bir blok/başlık başlıyorsa dur.
      if (_pedagogyKind(t) != null) break;
      if (_isSchemaStart(t) || _reSchemaEnd.hasMatch(t)) break;
      if (t.startsWith('#') || _reSubHead.hasMatch(t)) break;
      if (t.startsWith('|') && t.endsWith('|')) break;
      i++;
    }
    return i; // [start, i) blok gövdesi (exclusive)
  }

  static int _findSchemaEnd(List<String> lines, int start) {
    for (int i = start + 1; i < lines.length; i++) {
      if (_reSchemaEnd.hasMatch(lines[i].trim())) return i;
    }
    // Bitiş etiketi yoksa dosyanın sonuna kadar al — kullanıcı taşınmadan
    // yarı kalmış bir özet hâlâ görünür.
    return lines.length - 1;
  }
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
      // ŞEMA bloğu: [ŞEMA: title] ... [/ŞEMA] — AI tarafından üretilen
      // Unicode/ASCII diyagram. Monospace çerçeveli kart olarak render.
      if (_isSchemaStart(lines[i])) {
        final end = _findSchemaEnd(lines, i);
        final titleMatch = _reSchemaStart.firstMatch(lines[i].trim());
        final title = titleMatch?.group(1)?.trim() ?? '';
        // Body: i+1 ile end-1 arasındaki satırlar (start ve end etiketleri hariç).
        final body = (end > i + 1)
            ? lines.sublist(i + 1, end).join('\n')
            : '';
        if (children.isNotEmpty) children.add(SizedBox(height: gap * 2));
        children.add(_SchemaBlock(
          title: title,
          body: body,
          fontSize: fontSize,
        ));
        if (end + 1 < lines.length) children.add(SizedBox(height: gap * 2));
        i = end + 1; // [/ŞEMA] satırını da atla
        continue;
      }
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
      // Pedagojik kutu: "⭐ Aklında Kalsın" / "🎯 Kendini Sına" — başlık +
      // sonraki madde satırlarını renkli kart içinde topla.
      final pedKind = _pedagogyKind(lines[i]);
      if (pedKind != null) {
        final headMatch = (pedKind == 'key'
                ? _reKeyTakeStart
                : _reSelfTestStart)
            .firstMatch(lines[i].trim());
        final inlineRest = headMatch?.group(1)?.trim() ?? '';
        final end = _findPedagogyEnd(lines, i);
        final bodyLines = <String>[];
        if (inlineRest.isNotEmpty) bodyLines.add(inlineRest);
        if (end > i + 1) bodyLines.addAll(lines.sublist(i + 1, end));
        final body = bodyLines.join('\n').trim();
        if (body.isNotEmpty) {
          if (children.isNotEmpty) children.add(SizedBox(height: gap * 2));
          children.add(_PedagogyBox(
            kind: pedKind,
            body: body,
            fontSize: fontSize,
            lineHeight: lineHeight,
          ));
          if (end < lines.length) children.add(SizedBox(height: gap * 2));
          i = end;
          continue;
        }
      }
      if (i > 0 && children.isNotEmpty) children.add(SizedBox(height: gap));
      final w = _buildLine(lines[i], context);
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
  Widget? _buildLine(String line, BuildContext context) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return SizedBox(height: 3);

    final base = TextStyle(
      color: AppPalette.textPrimary(context),
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
        accent: Color(0xFF0EA5E9), // sky blue
        icon: '📦',
        fontSize: fontSize,
      );
    }

    // 6.3 Inline 💡 Önemli Bilgi: ... (legacy ⚠️ Kritik Uyarı / 🔬 QuAlsar
    // Notu da aynı kutuda render edilir — tek tip "Önemli Bilgi" görünümü).
    final note = _reInlineNote.firstMatch(trimmed);
    if (note != null) {
      return _BoxedCallout(
        label: 'Önemli Bilgi'.tr(),
        body: note.group(1)!.trim(),
        accent: Color(0xFFD97706), // amber-600
        icon: '💡',
        fontSize: fontSize,
      );
    }

    // 6.4 [Görsel Betimlemesi: ...] — Wikipedia'dan görsel çekip kart olarak
    // render eder. Format: "Konu Adı — kısa açıklama" (— ayraç). "—" yoksa
    // tüm metin hem arama sorgusu hem caption olarak kullanılır.
    final visual = _reVisualDesc.firstMatch(trimmed);
    if (visual != null) {
      return _VisualImageCard(
        description: visual.group(1)!.trim(),
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
        color: Color(0xFF22C55E),
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
        color: Color(0xFFF59E0B),
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
        color: Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context), width: 1),
      ),
      child: Center(
        child: Math.tex(
          formula,
          textStyle: TextStyle(color: AppPalette.textPrimary(context), fontSize: fontSize + 2),
          onErrorFallback: (_) => Text(
            '\$\$$formula\$\$',
            style: TextStyle(
              color: AppPalette.textSecondary(context),
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
    final cleanRest = _stripStrayAsterisks(rest);
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
          SizedBox(width: 8),
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
                  TextSpan(text: label, style: TextStyle(color: _color)),
                  if (cleanRest.isNotEmpty)
                    TextSpan(
                      text: ' $cleanRest',
                      style: TextStyle(
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
    // Alt başlık — ana başlık çerçevesinden ayrışsın diye renkli accent.
    // **Başlık** gibi markdown asteriksleri → temizle (zaten bold render).
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        _stripStrayAsterisks(title),
        style: TextStyle(
          color: Color(0xFF2563EB),
          fontWeight: FontWeight.w800,
          fontSize: fontSize + 1,
          height: 1.25,
          letterSpacing: 0.1,
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
    // Bullet karakteri (•) kaldırıldı — sade satır olarak render et.
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 1, bottom: 1),
      child: RichText(
        text: TextSpan(style: base, children: _inlineMath(rest, base)),
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
          SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: fontSize - 0.5,
                  height: 1.35,
                  color: AppPalette.textPrimary(context),
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
//  Pedagojik kutu — çok satırlı: "⭐ Aklında Kalsın" (özün özü, yeşil) ve
//  "🎯 Kendini Sına" (aktif hatırlama/öz-test, mor). Başlık şeridi + gövde
//  (gövde iç içe LatexText ile → madde/LaTeX/tablo render'ı korunur).
// ═══════════════════════════════════════════════════════════════════════════════
class _PedagogyBox extends StatelessWidget {
  final String kind; // 'key' | 'test'
  final String body;
  final double fontSize;
  final double lineHeight;
  const _PedagogyBox({
    required this.kind,
    required this.body,
    required this.fontSize,
    required this.lineHeight,
  });

  @override
  Widget build(BuildContext context) {
    final isKey = kind == 'key';
    final accent = isKey ? const Color(0xFF059669) : const Color(0xFF7C3AED);
    final icon = isKey ? '⭐' : '🎯';
    final title = isKey ? 'Aklında Kalsın'.tr() : 'Kendini Sına'.tr();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.40), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık şeridi
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Text(icon, style: TextStyle(fontSize: fontSize + 1)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: fontSize + 0.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          // Gövde — iç içe LatexText ile madde/LaTeX/tablo render'ı korunur.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: LatexText(
              body,
              fontSize: fontSize - 0.5,
              lineHeight: lineHeight,
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
  static List<String> _parseRow(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((e) => e.trim()).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (lines.length < 2) return const SizedBox.shrink();
    // Buton tablonun DIŞINDA, hemen üstünde sağa yaslı; çerçeveler örtüşmez.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, right: 2),
          child: Align(
            alignment: Alignment.centerRight,
            child: _FullscreenTableButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => _FullscreenTablePage(
                      lines: lines,
                      fontSize: fontSize,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _buildTableContent(context, fullscreen: false),
      ],
    );
  }

  Widget _buildTableContent(BuildContext context,
      {required bool fullscreen}) {
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

    final isDark = AppPalette.isDark(context);
    const accent = Color(0xFF7C3AED);
    // Karanlık modda "negatif film" tablo: zemin saf siyah, ızgara/yazı beyaz.
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.85)
        : Colors.black.withValues(alpha: 0.18);
    final cellBg = isDark ? Colors.black : Colors.white;
    final cellBgAlt = isDark ? Colors.black : const Color(0xFFF8FAFC);

    Widget cell(String content, {required bool isHeader}) {
      final base = TextStyle(
        fontSize: fontSize - 1,
        height: 1.4,
        color: isHeader
            ? Colors.white
            : (isDark ? Colors.white : Colors.black87),
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

    final tableWidget = Table(
      defaultColumnWidth: IntrinsicColumnWidth(),
      border: TableBorder.symmetric(
        inside: BorderSide(color: borderColor, width: 0.6),
        outside: BorderSide(color: borderColor, width: 0.8),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(color: isDark ? Colors.black : accent),
          children: [
            for (final h in normalize(header)) cell(h, isHeader: true),
          ],
        ),
        for (var r = 0; r < dataRows.length; r++)
          TableRow(
            decoration: BoxDecoration(
              color: r.isOdd ? cellBgAlt : cellBg,
            ),
            children: [
              for (final c in normalize(dataRows[r]))
                cell(c, isHeader: false),
            ],
          ),
      ],
    );

    final scrollable = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 40,
        ),
        child: tableWidget,
      ),
    );

    // Fullscreen modunda: dikey scroll da gerekir; container görünümü kalkar
    // (sayfanın AppBar/padding'i çerçeve görevi görür).
    if (fullscreen) {
      return SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: scrollable,
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
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: scrollable,
    );
  }
}

// ─── Tam Ekran butonu — tablonun sağ üst köşesinde küçük cyan pill ───────────
class _FullscreenTableButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FullscreenTableButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
                color: Colors.black.withValues(alpha: 0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_full_rounded,
                  size: 13, color: Colors.black),
              SizedBox(width: 5),
              Text(
                'Tabloyu Tam Ekran Yap'.tr(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tam ekran tablo sayfası — açılırken yatay, kapanırken dikey moda dön. ──
class _FullscreenTablePage extends StatefulWidget {
  final List<String> lines;
  final double fontSize;
  const _FullscreenTablePage({
    required this.lines,
    required this.fontSize,
  });

  @override
  State<_FullscreenTablePage> createState() => _FullscreenTablePageState();
}

class _FullscreenTablePageState extends State<_FullscreenTablePage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Uygulamanın varsayılan moduna geri dön (main.dart portraitUp).
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<void> _close() async {
    // Önce orientation'ı tetikleyip sonra pop — geri dönüşte rebuild
    // kararsızlığı oluşmasın diye.
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final block = _TableBlock(lines: widget.lines, fontSize: widget.fontSize);
    return Scaffold(
      backgroundColor: AppPalette.card(context),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
              child: block._buildTableContent(context, fullscreen: true),
            ),
            // Kapat (X) — sağ üst.
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _close,
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Görsel kartı: Wikipedia API'sinden konuyla ilgili thumbnail çekip
// üstte resim, altta açıklama metnini gösterir. Hata/yokluk durumunda
// metin-only placeholder'a düşer (mor accent + 🖼️ ikon).
class _VisualImageCard extends StatefulWidget {
  final String description;
  final double fontSize;
  const _VisualImageCard({
    required this.description,
    required this.fontSize,
  });

  @override
  State<_VisualImageCard> createState() => _VisualImageCardState();
}

class _VisualImageCardState extends State<_VisualImageCard> {
  static const _accent = Color(0xFF7C3AED);
  String? _url;
  bool _loading = true;

  String get _query {
    // "Konu Adı — açıklama" formatında ise sadece konu adı arama sorgusu.
    // Yoksa ilk birkaç anlamlı kelimeyi sorgu yap, açıklama ise tamamı.
    final desc = widget.description;
    final dashIdx = desc.indexOf(RegExp(r'[—–-]'));
    if (dashIdx > 0 && dashIdx < 80) {
      return desc.substring(0, dashIdx).trim();
    }
    final words = desc.split(RegExp(r'\s+'));
    if (words.length <= 6) return desc;
    return words.take(6).join(' ');
  }

  String get _caption {
    final desc = widget.description;
    final dashIdx = desc.indexOf(RegExp(r'[—–-]'));
    if (dashIdx > 0 && dashIdx < 80) {
      return desc.substring(dashIdx + 1).trim();
    }
    return desc;
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final lang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final useLang = lang.isEmpty ? 'tr' : lang;
    final url = await WikiImageService.fetchImageUrl(_query, lang: useLang);
    if (!mounted) return;
    setState(() {
      _url = url;
      _loading = false;
    });
  }

  // Wikipedia eşleşmesi yoksa veya yüklerken hata olursa: diyagram çerçevesi.
  // Köşe parantezleri + merkez ikon + konu adı + "Diyagram Çerçevesi" etiketi
  // → kullanıcı boş kart yerine teknik bir placeholder görür.
  Widget _buildDiagramFrame() {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(
              color: _accent.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 4 köşe parantezi — diyagram çerçevesi havası
          for (int i = 0; i < 4; i++)
            Positioned(
              top: i < 2 ? 8 : null,
              bottom: i >= 2 ? 8 : null,
              left: i.isEven ? 10 : null,
              right: i.isOdd ? 10 : null,
              child: SizedBox(
                width: 14,
                height: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: i < 2
                          ? BorderSide(
                              color: _accent.withValues(alpha: 0.7),
                              width: 2)
                          : BorderSide.none,
                      bottom: i >= 2
                          ? BorderSide(
                              color: _accent.withValues(alpha: 0.7),
                              width: 2)
                          : BorderSide.none,
                      left: i.isEven
                          ? BorderSide(
                              color: _accent.withValues(alpha: 0.7),
                              width: 2)
                          : BorderSide.none,
                      right: i.isOdd
                          ? BorderSide(
                              color: _accent.withValues(alpha: 0.7),
                              width: 2)
                          : BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          // Merkez içerik
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schema_rounded,
                size: 30,
                color: _accent,
              ),
              SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  _query,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.fontSize - 1,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Diyagram Çerçevesi',
                style: TextStyle(
                  fontSize: widget.fontSize - 4,
                  fontStyle: FontStyle.italic,
                  color: _accent.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.30), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst kısım: görsel veya yükleniyor / yok placeholder.
          if (_loading)
            Container(
              height: 70,
              color: _accent.withValues(alpha: 0.04),
              alignment: Alignment.center,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: _accent,
                ),
              ),
            )
          else if (_url != null)
            // BoxFit.contain → görsel kırpılmaz, numaralı diyagramların
            // tüm parçaları görünür. maxHeight 280'e çıkarıldı ki dikey
            // diyagramlar da rahat sığsın. Yumuşak gri zemin letterbox'ı
            // ders kitabı stilinde gösterir.
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 140,
                maxHeight: 280,
              ),
              child: Container(
                width: double.infinity,
                color: Color(0xFFF8FAFC),
                alignment: Alignment.center,
                child: Image.network(
                _url!,
                fit: BoxFit.contain,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _buildDiagramFrame(),
                loadingBuilder: (_, child, prog) {
                  if (prog == null) return child;
                  return Container(
                    height: 120,
                    color: _accent.withValues(alpha: 0.04),
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: _accent,
                        value: prog.expectedTotalBytes == null
                            ? null
                            : prog.cumulativeBytesLoaded /
                                prog.expectedTotalBytes!,
                      ),
                    ),
                  );
                },
                ),
              ),
            )
          else
            // Wikipedia'dan görsel çekilemedi → Diyagram Çerçevesi placeholder.
            // AI'ın yazdığı caption teknik bir diyagram tarifi olarak görünür.
            _buildDiagramFrame(),
          // Alt kısım: açıklama metni + 🖼️ ikon, kaynak notu.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🖼️', style: TextStyle(fontSize: 14)),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _caption,
                        style: TextStyle(
                          fontSize: widget.fontSize - 1,
                          color: AppPalette.textPrimary(context),
                          height: 1.4,
                        ),
                      ),
                      if (_url != null) ...[
                        SizedBox(height: 4),
                        Text(
                          'Görsel: Wikipedia',
                          style: TextStyle(
                            fontSize: widget.fontSize - 4,
                            color: AppPalette.textSecondary(context),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
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

// ═══════════════════════════════════════════════════════════════════════════════
//  _SchemaBlock — AI tarafından Unicode/ASCII art ile çizilmiş diyagram.
//  Monospace font ile satır satır render, ders kitabı tarzı çerçevede.
// ═══════════════════════════════════════════════════════════════════════════════
class _SchemaBlock extends StatelessWidget {
  final String title;
  final String body;
  final double fontSize;
  const _SchemaBlock({
    required this.title,
    required this.body,
    required this.fontSize,
  });

  static TextStyle _monoStyle(double size) => TextStyle(
        fontSize: size,
        height: 1.25,
        fontFamily: 'Courier',
        fontFamilyFallback: const [
          'monospace',
          'Roboto Mono',
          'Menlo',
          'Consolas',
        ],
        color: Colors.black,
        letterSpacing: 0,
      );

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _SchemaFullscreenPage(title: title, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7C3AED);
    // Tablo gibi: Tam Ekran butonu çerçevenin DIŞINDA, sağ üstte.
    // Çerçeve içindeki eski fullscreen ikonu kaldırıldı.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, right: 2, top: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: _FullscreenSchemaButton(
              onTap: () => _openFullscreen(context),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: accent.withValues(alpha: 0.35), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst başlık şeridi: sadece ikon + konu adı (fullscreen ikonu yok).
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  border: Border(
                    bottom: BorderSide(
                      color: accent.withValues(alpha: 0.30),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schema_rounded, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title.isEmpty ? 'Şema' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fontSize - 1,
                          fontWeight: FontWeight.w800,
                          color: accent,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Body — monospace çizim. Yatay scroll uzun şemalar için.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Text(body, style: _monoStyle(fontSize - 1)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Tam Ekran butonu — diyagramın üstünde, tablo butonunun ikizi ───────────
class _FullscreenSchemaButton extends StatelessWidget {
  final VoidCallback onTap;
  const _FullscreenSchemaButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
                color: Colors.black.withValues(alpha: 0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_full_rounded,
                  size: 13, color: Colors.black),
              const SizedBox(width: 5),
              Text(
                'Diyagramı Tam Ekran Yap'.tr(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _SchemaFullscreenPage — Diyagramı tam ekran açar; iki yönde scroll + pinch zoom.
// ═══════════════════════════════════════════════════════════════════════════════
class _SchemaFullscreenPage extends StatefulWidget {
  final String title;
  final String body;
  const _SchemaFullscreenPage({required this.title, required this.body});

  @override
  State<_SchemaFullscreenPage> createState() => _SchemaFullscreenPageState();
}

class _SchemaFullscreenPageState extends State<_SchemaFullscreenPage> {
  @override
  void initState() {
    super.initState();
    // Tablo gibi: landscape moda zorla → diyagramı yatay göster.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<void> _close() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7C3AED);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Diyagram — pinch zoom + iki yönlü scroll
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
              child: InteractiveViewer(
                constrained: false,
                minScale: 0.5,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(80),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    widget.body,
                    style: _SchemaBlock._monoStyle(14),
                  ),
                ),
              ),
            ),
            // Başlık şeridi — sol üst
            Positioned(
              top: 8,
              left: 8,
              right: 56,
              child: Text(
                widget.title.isEmpty ? 'Şema' : widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: accent,
                  fontSize: 14,
                ),
              ),
            ),
            // Kapat (X) — sağ üst
            Positioned(
              top: 4,
              right: 8,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _close,
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
