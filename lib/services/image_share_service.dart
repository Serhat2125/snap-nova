import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/latex_text.dart';
import 'solutions_storage.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ImageShareService — Çoklu sayfa görsel paylaşım.
//
//  Soru + çözüm, telefon oranına (yaklaşık 1080×1600) yakın sayfalara bölünüp
//  her sayfa ayrı PNG olarak üretilir. WhatsApp'ta galeri şeklinde gösterilir.
//
//  Sayfa 1: SORU (OCR metni)
//  Sayfa 2..N: ÇÖZÜM — paragraf sınırlarında bölünmüş
//
//  Kısa çözüm ise (<1100 karakter) SORU + ÇÖZÜM tek sayfa olur.
// ═══════════════════════════════════════════════════════════════════════════════

class ImageShareService {
  static const double _cardWidth = 1080;
  static const double _storyHeight = 1920; // 9:16 story oranı
  static const double _pixelRatio = 2.0;

  static Future<void> shareDouble({
    required BuildContext context,
    required SolutionRecord record,
  }) async {
    final overlayState = Overlay.of(context, rootOverlay: true);
    final mq = MediaQuery.of(context);

    final cleanText = _cleanResourceLines(record.result);

    // ── Soru görselini ÖNDEN belleğe al ve cache'le ─────────────────────────
    //   Image.file asenkron yükleniyor; offscreen overlay sadece 2 frame
    //   bekliyor. Eğer dosya çözümü o anda tamamlanmazsa fotoğraf 0×0
    //   yakalanıyor → alıcıya soru görünmüyor. precacheImage ile decoder'ı
    //   önceden çalıştırıp `Image(image: ...)` ilk frame'de senkron çiziliyor.
    ImageProvider? questionImg;
    try {
      final f = File(record.imagePath);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        if (bytes.isNotEmpty) {
          questionImg = MemoryImage(bytes);
          if (context.mounted) {
            await precacheImage(questionImg, context);
          }
          debugPrint('[ImgShare] question image precached: ${bytes.length}B');
        }
      } else {
        debugPrint('[ImgShare] question image MISSING: ${record.imagePath}');
      }
    } catch (e) {
      debugPrint('[ImgShare] question image preload failed: $e');
      questionImg = null;
    }

    final pages = _buildPages(questionImg, cleanText);
    debugPrint('[ImgShare] ${pages.length} sayfa oluşturulacak');

    final keys = List.generate(pages.length, (_) => GlobalKey());

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -99999,
        top: 0,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: mq,
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < pages.length; i++) ...[
                    RepaintBoundary(
                      key: keys[i],
                      child: _PageCard(record: record, content: pages[i]),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlayState.insert(entry);

    try {
      // 3 frame bekle — precache yapılmış olsa da layout/paint zincirinin
      // tüm sayfalar için tamamlanması garantilensin.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;

      final files = await Future.wait(List.generate(keys.length, (i) async {
        final bytes = await _capturePng(keys[i]);
        final f = File(
            '${dir.path}/qualsar_${ts}_${(i + 1).toString().padLeft(2, '0')}.png');
        await f.writeAsBytes(bytes);
        debugPrint('[ImgShare] sayfa ${i + 1}/${keys.length} = ${bytes.length}b');
        return XFile(f.path, mimeType: 'image/png');
      }));

      entry.remove();

      await Share.shareXFiles(
        files,
        text: 'QuAlsar ile çözdüm, sen de dene!',
      );
    } catch (e, st) {
      debugPrint('[ImgShare] failed: $e\n$st');
      try {
        entry.remove();
      } catch (_) {}
      rethrow;
    }
  }

  // ── Sayfa bölme ─────────────────────────────────────────────────────────────
  //  Çözüm metni ekran-boyu sayfalara bölünür; her sayfa kendi PNG'i olarak
  //  paylaşılır. Sayfa içi padding minimum tutuldu → görsel olarak bitişik
  //  hissi verir.
  //  Kısa çözüm (~900 karakter altı) → tek sayfa: foto + çözüm + footer.
  //  Uzun çözüm → sayfa 1 = foto, sayfa 2+ = çözüm parçaları.
  static List<_PageContent> _buildPages(
      ImageProvider? questionImg, String solution) {
    if (solution.length < 900) {
      return [
        _PageContent(
          pageNumber: 1,
          totalPages: 1,
          questionImage: questionImg,
          solutionText: solution,
          showHeader: true,
          showFooter: true,
        ),
      ];
    }

    final chunks = _splitByParagraph(solution, charsPerPage: 700);
    final total = chunks.length + 1; // +1 soru sayfası
    final pages = <_PageContent>[
      _PageContent(
        pageNumber: 1,
        totalPages: total,
        questionImage: questionImg,
        solutionText: null,
        showHeader: true,
        showFooter: false,
      ),
    ];
    for (var i = 0; i < chunks.length; i++) {
      pages.add(_PageContent(
        pageNumber: i + 2,
        totalPages: total,
        questionImage: null,
        solutionText: chunks[i],
        showHeader: false,
        showFooter: i == chunks.length - 1,
        // Sadece İLK çözüm sayfası "ÇÖZÜM" başlığını gösterir;
        // sonrakiler düz devam metni (başlıksız).
        isSolutionContinuation: i > 0,
      ));
    }
    return pages;
  }

  // Metni \n\n sınırında parçalayıp her sayfanın ~charsPerPage altında
  // kalmasını hedefleyerek gruplar.
  static List<String> _splitByParagraph(String text,
      {required int charsPerPage}) {
    final blocks = text
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
    if (blocks.isEmpty) return [text];

    final pages = <StringBuffer>[];
    var cur = StringBuffer();
    for (final block in blocks) {
      if (cur.isNotEmpty && (cur.length + 2 + block.length) > charsPerPage) {
        pages.add(cur);
        cur = StringBuffer();
      }
      if (cur.isNotEmpty) cur.write('\n\n');
      cur.write(block);
    }
    if (cur.isNotEmpty) pages.add(cur);
    return pages.map((p) => p.toString()).toList();
  }

  static Future<Uint8List> _capturePng(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw Exception('Render sınırı bulunamadı — kart oluşturulamadı');
    }
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('PNG byte dönüşümü başarısız');
    }
    return byteData.buffer.asUint8List();
  }

  static String _cleanResourceLines(String full) {
    final resPattern = RegExp(r'^\[(VIDEO|WEB|TEST):\s*"(.+?)"\s*\|\s*(.+?)\]\s*$');
    // Gemini CONTINUATION MODE bazen "Çözüm (devam)", "Çözüm devam",
    // "(devam)" gibi satırlar bastırabiliyor — bunları süpür.
    final contPattern = RegExp(
        r'^(?:\*{0,2})\s*(?:çözüm\s*\(?devam(?:ı)?\)?|\(?\s*devam(?:ı)?\s*\)?)\s*[:：]?\s*(?:\*{0,2})\s*$',
        caseSensitive: false);
    return full
        .split('\n')
        .where((line) {
          final t = line.trim();
          return resPattern.firstMatch(t) == null &&
              contPattern.firstMatch(t) == null;
        })
        .join('\n');
  }
}

// ─── 1) STORY KARTI (1080×1920 — 9:16 Instagram/WhatsApp story) ────────────
// (Şu an kullanılmıyor, ileride ikinci paylaşım seçeneğine hazır duruyor.)

// ignore: unused_element
class _PreviewCard extends StatelessWidget {
  final SolutionRecord record;
  const _PreviewCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ImageShareService._cardWidth,
      height: ImageShareService._storyHeight,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0B0D14),
            Color(0xFF111524),
            Color(0xFF0B0D14),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Sol üst cyan glow
          Positioned(
            top: -180,
            left: -180,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00E5FF).withValues(alpha: 0.28),
                    const Color(0xFF00E5FF).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // Sağ alt turuncu glow
          Positioned(
            bottom: -200,
            right: -200,
            child: Container(
              width: 560,
              height: 560,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF6A00).withValues(alpha: 0.22),
                    const Color(0xFFFF6A00).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),

          // İçerik
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 110, 72, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── MARKA ────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                            blurRadius: 30,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 40),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'QuAlsar',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        Text(
                          _dateStr(record.timestamp),
                          style: GoogleFonts.poppins(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 44),

                // ── DERS + YÖNTEM ────────────────────────────────────
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _chip(record.subject, const Color(0xFF00E5FF)),
                    _chip(record.solutionType, const Color(0xFFFF6A00)),
                  ],
                ),
                const SizedBox(height: 40),

                // ── SORU FOTOĞRAFI ───────────────────────────────────
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.20),
                        blurRadius: 50,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 520,
                        maxHeight: 720,
                      ),
                      child: File(record.imagePath).existsSync()
                          ? Image.file(File(record.imagePath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  _imagePlaceholder(560))
                          : _imagePlaceholder(560),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // ── ÇÖZÜM ÖZETİ ──────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'ÇÖZÜM ÖZETİ',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _solutionSnippet(record.result),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 22,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── ALT: CTA + ROZET ─────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tam çözüm\nsonraki görselde →',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'ÇÖZÜLDÜ',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _dateStr(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }

  // Çözüm metninden story'e uygun kısa ve temiz özet çıkar.
  //   — LaTeX, markdown, kaynak etiketleri temizlenir
  //   — "Sonuç:" varsa odakta tutulur
  String _solutionSnippet(String raw) {
    var t = raw
        .replaceAll(RegExp(r'\[(VIDEO|WEB|TEST):.*?\]'), '')
        .replaceAll(RegExp(r'\[Ders:.*?\]'), '')
        .replaceAll(RegExp(r'\$\$(.+?)\$\$', dotAll: true), (' '))
        .replaceAll(RegExp(r'\$([^\$\n]+?)\$'), ' ')
        .replaceAll(RegExp(r'\\frac\{(.+?)\}\{(.+?)\}'), ' ')
        .replaceAll(RegExp(r'\\[a-zA-Z]+\{?'), ' ')
        .replaceAll(RegExp(r'[\{\}]'), ' ')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // "Sonuç:" varsa öncelikle onu göster
    final resultMatch =
        RegExp(r'Sonu[cç]:\s*([^\n]+)', caseSensitive: false).firstMatch(t);
    final resultLine = resultMatch?.group(0)?.trim() ?? '';

    // İlk cümleleri al — fazla uzun olanı kırp
    final firstPart = t.length > 300 ? '${t.substring(0, 300)}…' : t;

    if (resultLine.isNotEmpty && !firstPart.contains(resultLine)) {
      return '$firstPart\n\n$resultLine';
    }
    return firstPart;
  }
}

// ─── SAYFA MODELİ ────────────────────────────────────────────────────────────

class _PageContent {
  final int pageNumber;
  final int totalPages;
  // ÖNCEDEN belleğe alınmış (precached) görsel — Image.file lazy
  // load'ından kaynaklanan "fotoğraf çıkmıyor" sorununu önler.
  final ImageProvider? questionImage;
  final String? solutionText;
  final bool showHeader; // Logo + QuAlsar + chip'ler
  final bool showFooter; // "QuAlsar ile çözüldü" satırı
  // True ise: çözümün devam sayfası — "ÇÖZÜM" başlığı YAZILMAZ.
  final bool isSolutionContinuation;
  const _PageContent({
    required this.pageNumber,
    required this.totalPages,
    this.questionImage,
    this.solutionText,
    this.showHeader = false,
    this.showFooter = false,
    this.isSolutionContinuation = false,
  });
}

// ─── TEK SAYFA KARTI ─────────────────────────────────────────────────────────

class _PageCard extends StatelessWidget {
  final SolutionRecord record;
  final _PageContent content;
  const _PageCard({required this.record, required this.content});

  @override
  Widget build(BuildContext context) {
    // Sayfalar arası bitişik hissi — üst/alt padding minimuma çekildi.
    // Header sayfası biraz daha pay ister; içerik sayfaları sıkışık.
    final topPad = content.showHeader ? 36.0 : 8.0;
    final bottomPad = content.showFooter ? 18.0 : 8.0;
    return Container(
      width: ImageShareService._cardWidth,
      color: const Color(0xFFF5F6F8),
      padding: EdgeInsets.fromLTRB(12, topPad, 12, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık bandı — logo + ders + yöntem (YALNIZCA showHeader=true ise)
          if (content.showHeader) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Center(
                      child: Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 48),
                    ),
                  ),
                  const SizedBox(width: 28),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Qu',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: 'Al',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFFF0000),
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: 'sar',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _miniChip(record.subject, const Color(0xFF0070FF)),
                  const SizedBox(width: 18),
                  _miniChip(record.solutionType, const Color(0xFFFF6A00)),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],

          // İçerik çerçevesi — overflow taşmasın diye hardEdge clip
          // (sayfa numarası göstergesi kaldırıldı)
          Container(
            padding: const EdgeInsets.all(30),
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black, width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SORU bölümü — artık OCR metni değil, fotoğraf
                if (content.questionImage != null) ...[
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0070FF),
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      const SizedBox(width: 30),
                      Text(
                        'SORU',
                        style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 66,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 9,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  // Soru görseli — precached ImageProvider; senkron çizilir.
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.12),
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 520,
                          maxHeight: 900,
                        ),
                        child: Image(
                          image: content.questionImage!,
                          fit: BoxFit.contain,
                          width: double.infinity,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              _imagePlaceholder(560),
                        ),
                      ),
                    ),
                  ),
                ],

                // SORU + ÇÖZÜM aynı sayfadaysa ayraç
                if (content.questionImage != null && content.solutionText != null) ...[
                  const SizedBox(height: 54),
                  Container(height: 3, color: Colors.black12),
                  const SizedBox(height: 40),
                ],

                // ÇÖZÜM bölümü — başlık SADECE ilk çözüm sayfasında.
                if (content.solutionText != null) ...[
                  if (!content.isSolutionContinuation) ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF22C55E), size: 72),
                        const SizedBox(width: 30),
                        Text(
                          'ÇÖZÜM',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 66,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 9,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 42),
                  ],
                  LatexText(content.solutionText!, fontSize: 38, lineHeight: 1.5),
                ],
              ],
            ),
          ),

          // Footer YALNIZCA son sayfada (showFooter=true)
          if (content.showFooter) ...[
            const SizedBox(height: 40),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded,
                      color: const Color(0xFFFF6A00), size: 40),
                  const SizedBox(width: 14),
                  Text(
                    'QuAlsar ile saniyeler içinde çözüldü',
                    style: GoogleFonts.poppins(
                      color: Colors.black54,
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 2),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Widget _imagePlaceholder(double h) {
  return Container(
    height: h,
    color: Colors.grey.shade200,
    child: const Center(
      child: Icon(Icons.image_not_supported_outlined,
          color: Colors.black26, size: 64),
    ),
  );
}
