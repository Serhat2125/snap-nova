import 'dart:io';
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
    final pdf = pw.Document();

    // ── Yerleşik fontlar ──────────────────────────────────────────────────────
    final ttf     = pw.Font.helvetica();
    final ttfBold = pw.Font.helveticaBold();

    // ── Görsel yükleme ────────────────────────────────────────────────────────
    pw.MemoryImage? questionImage;
    try {
      final imgFile = File(record.imagePath);
      if (await imgFile.exists()) {
        final bytes = await imgFile.readAsBytes();
        questionImage = pw.MemoryImage(bytes);
      }
    } catch (_) {}

    // ── Temizlenmiş metin ─────────────────────────────────────────────────────
    final cleanText = _cleanForPdf(record.result);

    // ── Tarih formatı ─────────────────────────────────────────────────────────
    final dt  = record.timestamp;
    final h   = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    const months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    final dateStr = '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$min';

    // ── PDF sayfası ───────────────────────────────────────────────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 48, 36, 40),
        header: (ctx) => _buildHeader(ttfBold, ttf, record, dateStr),
        footer: (ctx) => _buildFooter(ttf, ctx),
        build: (ctx) => [
          pw.SizedBox(height: 16),

          // Soru görseli
          if (questionImage != null) ...[
            pw.Center(
              child: pw.ClipRRect(
                horizontalRadius: 8,
                verticalRadius: 8,
                child: pw.Image(questionImage, height: 200, fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 20),
          ],

          // Çözüm başlığı
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.5),
            ),
            child: pw.Text(
              'ÇÖZÜM',
              style: pw.TextStyle(font: ttfBold, fontSize: 11, color: PdfColors.blueGrey700),
            ),
          ),
          pw.SizedBox(height: 12),

          // Çözüm metni
          pw.Text(
            cleanText,
            style: pw.TextStyle(font: ttf, fontSize: 10.5, lineSpacing: 2, color: PdfColors.grey900),
          ),
        ],
      ),
    );

    // ── Kaydet ve paylaş ──────────────────────────────────────────────────────
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/aurasnap_${record.id}.pdf');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: '${record.subject} — ${record.solutionType}\nAuraSnap ile çözüldü.',
    );
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
              'AuraSnap',
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
            _chip(bold, record.subject, PdfColors.blue700, PdfColors.blue50),
            pw.SizedBox(width: 6),
            _chip(bold, record.solutionType, PdfColors.blueGrey600, PdfColors.blueGrey50),
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
  static pw.Widget _buildFooter(pw.Font regular, pw.Context ctx) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'AuraSnap — AI Destekli Eğitim',
          style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.blueGrey400),
        ),
        pw.Text(
          '${ctx.pageNumber} / ${ctx.pagesCount}',
          style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.blueGrey400),
        ),
      ],
    );
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
}
