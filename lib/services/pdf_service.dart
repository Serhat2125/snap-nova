import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../services/solutions_storage.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  PdfService — Çözüm kaydını PDF'e dönüştürür ve paylaşır
// ═══════════════════════════════════════════════════════════════════════════════

class PdfService {
  static Future<void> generateAndShare(SolutionRecord record) async {
    debugPrint('[PDF] generateAndShare start — id=${record.id}');
    final pdf = pw.Document();

    // ── Fontlar — built-in helvetica (internet/asset gerektirmez).
    //   Turkish-specific glyphs (ı, ğ, ş) için aşağıda transliterate ediliyor.
    final ttf     = pw.Font.helvetica();
    final ttfBold = pw.Font.helveticaBold();

    // ── Görsel yükleme ────────────────────────────────────────────────────────
    pw.MemoryImage? questionImage;
    try {
      final imgFile = File(record.imagePath);
      if (await imgFile.exists()) {
        final bytes = await imgFile.readAsBytes();
        questionImage = pw.MemoryImage(bytes);
        debugPrint('[PDF] image loaded (${bytes.length} bytes)');
      } else {
        debugPrint('[PDF] image file missing: ${record.imagePath}');
      }
    } catch (e) {
      debugPrint('[PDF] image load error: $e');
    }

    // ── Temizlenmiş + Türkçe→ASCII-güvenli metin ─────────────────────────
    final cleanText = _toLatin1Safe(_cleanForPdf(record.result));

    // ── Tarih formatı ─────────────────────────────────────────────────────────
    final dt  = record.timestamp;
    final h   = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    const months = [
      'Ocak', 'Subat', 'Mart', 'Nisan', 'Mayis', 'Haziran',
      'Temmuz', 'Agustos', 'Eylul', 'Ekim', 'Kasim', 'Aralik',
    ];
    final dateStr = '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$min';

    // ── Dinamik sayfa yüksekliği — içerik TEK uzun bir sayfada akar ────
    final pageFormat = _computePageFormat(cleanText, hasImage: questionImage != null);

    // ── PDF sayfası — soru + çözüm TEK büyük çerçevede ───────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(32, 40, 32, 36),
        header: (ctx) =>
            ctx.pageNumber == 1 ? _buildHeader(ttfBold, ttf, record, dateStr) : pw.SizedBox(),
        footer: (ctx) => _buildFooter(ttf),
        build: (ctx) => [
          pw.SizedBox(height: 10),

          // Soru + Çözüm'ü kapsayan büyük çerçeve
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              border: pw.Border.all(color: PdfColors.blueGrey300, width: 1.2),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Soru görseli
                if (questionImage != null) ...[
                  pw.Center(
                    child: pw.ClipRRect(
                      horizontalRadius: 6,
                      verticalRadius: 6,
                      child: pw.Image(questionImage,
                          height: 220, fit: pw.BoxFit.contain),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Divider(color: PdfColors.blueGrey200, thickness: 0.5, height: 10),
                  pw.SizedBox(height: 4),
                ],

                // Çözüm metni — büyük, okunaklı
                pw.Text(
                  cleanText,
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 13,
                    lineSpacing: 3,
                    color: PdfColors.grey900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // ── Kaydet ve paylaş ──────────────────────────────────────────────────────
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/qualsar_${record.id}.pdf');
      final bytes = await pdf.save();
      debugPrint('[PDF] built ${bytes.length} bytes → ${file.path}');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        text: _toLatin1Safe(
            '${record.subject} — ${record.solutionType}\nQuAlsar ile cozuldu.'),
      );
      debugPrint('[PDF] share sheet opened');
    } catch (e, st) {
      debugPrint('[PDF] build/share FAILED: $e\n$st');
      rethrow;
    }
  }

  // ── Üst bilgi ───────────────────────────────────────────────────────────────
  static pw.Widget _buildHeader(
    pw.Font bold,
    pw.Font regular,
    SolutionRecord record,
    String dateStr,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'QuAlsar',
              style: pw.TextStyle(font: bold, fontSize: 18, color: PdfColors.blueGrey800),
            ),
            pw.Text(
              dateStr,
              style: pw.TextStyle(font: regular, fontSize: 9, color: PdfColors.blueGrey500),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            _chip(bold, _toLatin1Safe(record.subject), PdfColors.blue700, PdfColors.blue50),
            pw.SizedBox(width: 6),
            _chip(bold, _toLatin1Safe(record.solutionType), PdfColors.blueGrey600, PdfColors.blueGrey50),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: PdfColors.blueGrey200, thickness: 0.5),
      ],
    );
  }

  static pw.Widget _chip(pw.Font bold, String label, PdfColor text, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(font: bold, fontSize: 8, color: text),
      ),
    );
  }

  // ── Alt bilgi ────────────────────────────────────────────────────────────────
  static pw.Widget _buildFooter(pw.Font regular) {
    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(
        'QuAlsar - AI Destekli Egitim',
        style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.blueGrey400),
      ),
    );
  }

  // ── Tek uzun sayfa için dinamik yükseklik hesabı ─────────────────────────
  //   Amaç: PDF'nin sayfa sayfa bölünmemesi, tek bir akıcı sayfa olması.
  //   Genişlik A4 sabit; yükseklik içerik kadar (minimum A4).
  static PdfPageFormat _computePageFormat(String text, {required bool hasImage}) {
    final pageWidth   = PdfPageFormat.a4.width;          // 595 pt
    const horizMargin = 32.0;
    const padding     = 14.0;
    const fontSize    = 13.0;
    const lineHeight  = fontSize + 3 + 2;                 // font + lineSpacing + leading
    const avgCharPt   = 6.1;                              // helvetica ~13pt
    final innerWidth  = pageWidth - 2 * horizMargin - 2 * padding;
    final charsPerLine = (innerWidth / avgCharPt).floor().clamp(40, 200);

    var textH = 0.0;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) { textH += lineHeight * 0.6; continue; }
      final wraps = (line.length / charsPerLine).ceil().clamp(1, 500);
      textH += wraps * lineHeight;
    }

    const headerH     = 90.0;   // başlık + chip + divider
    const footerH     = 30.0;
    const containerPd = 28.0;   // 14*2 iç padding
    const imageH      = 240.0;  // görsel + divider
    const vMargins    = 40.0 + 36.0;
    const buffer      = 90.0;   // emniyet payı (yuvarlamalar + satır sarma hatası)

    final total = headerH
        + (hasImage ? imageH : 0)
        + containerPd
        + textH
        + footerH
        + vMargins
        + buffer;

    final pageHeight = total.clamp(PdfPageFormat.a4.height, 30000.0).toDouble();
    return PdfPageFormat(pageWidth, pageHeight);
  }

  // ── LaTeX / markdown temizleyici ──────────────────────────────────────────────
  static String _cleanForPdf(String raw) {
    return raw
        .replaceAll(RegExp(r'\\\[|\\\]|\\\(|\\\)'), '')
        .replaceAll(RegExp(r'\[VIDEO:.*?\]'), '')
        .replaceAll(RegExp(r'\[WEB:.*?\]'), '')
        .replaceAll(RegExp(r'\[TEST:.*?\]'), '')
        .replaceAll(RegExp(r'\[Ders:.*?\]'), '')
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
        .replaceAllMapped(RegExp(r'\\frac\{(.+?)\}\{(.+?)\}'), (m) => '(${m[1]})/(${m[2]})')
        .replaceAll(RegExp(r'\\[a-zA-Z]+\{?'), '')
        .replaceAll(RegExp(r'\}'), '')
        .replaceAll(RegExp(r'\^'), '^')
        .replaceAll(RegExp(r'_{(.+?)}'), r'_$1')
        .replaceAll(RegExp(r'\s{3,}'), '\n\n')
        .trim();
  }

  // ── Latin-1 güvenli transliterasyon ──────────────────────────────────────
  //   Built-in helvetica PDF font'u Latin-1 destekler ama ı, ğ, Ş, İ gibi
  //   Türkçe-özgü karakterleri render edemez. Bu eşleştirme ile ASCII-safe
  //   yaparak hata/boş glyph oluşmasını engelliyoruz. ç, ö, ü, ğ'nin büyük
  //   halleri Latin-1'de var, küçük ı ve büyük İ yok — onları da çeviriyoruz.
  static const Map<String, String> _trMap = {
    'ı': 'i', 'İ': 'I',
    'ğ': 'g', 'Ğ': 'G',
    'ş': 's', 'Ş': 'S',
    'ç': 'c', 'Ç': 'C',
    'ö': 'o', 'Ö': 'O',
    'ü': 'u', 'Ü': 'U',
    '—': '-', '–': '-',
    '“': '"', '”': '"', '‘': "'", '’': "'",
    '…': '...',
    '•': '*',
    '×': 'x', '÷': '/',
    '≤': '<=', '≥': '>=',
    '≈': '~',
    '°': 'deg',
    'π': 'pi', 'α': 'alpha', 'β': 'beta', 'γ': 'gamma', 'Δ': 'Delta',
    'θ': 'theta', 'λ': 'lambda', 'μ': 'mu', 'σ': 'sigma', 'ω': 'omega',
    '∑': 'Sum', '∫': 'Int', '∞': 'inf', '√': 'sqrt',
  };

  static String _toLatin1Safe(String input) {
    final sb = StringBuffer();
    for (final ch in input.runes) {
      final s = String.fromCharCode(ch);
      if (_trMap.containsKey(s)) {
        sb.write(_trMap[s]);
      } else if (ch < 128) {
        sb.write(s);
      } else if (ch < 256) {
        // Latin-1 aralığı — helvetica destekler
        sb.write(s);
      } else {
        // Desteklenmeyen karakter — boşluk ile ikame
        sb.write(' ');
      }
    }
    return sb.toString();
  }
}
