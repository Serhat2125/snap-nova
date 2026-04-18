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

    // Soru sayfasında OCR metni DEĞİL, kullanıcının fotoğrafı gösterilir.
    // OCR çağrısı tamamen kaldırıldı — hem tekrar yazım hem de 3-15 sn bekleme yok.
    final pages = _buildPages(record.imagePath, cleanText);
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
      // Flutter'ın tüm sayfaları render etmesine izin ver — iki frame yeterli,
      // 300 ms sabit beklemesi kaldırıldı (gereksizdi, çoğunlukla hazır oluyor).
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;

      // Tüm sayfaları PARALEL yakalamayı dene.
      // Her sayfa aynı UI thread'ini kullandığı için tamamen eşzamanlı değil
      // ama Future.wait dosya yazma I/O'sunu üst üste bindiriyor → net kazanç.
      final files = await Future.wait(List.generate(keys.length, (i) async {
        final bytes = await _capturePng(keys[i]);
        final f = File(
            '${dir.path}/aurasnap_${ts}_${(i + 1).toString().padLeft(2, '0')}.png');
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
  //  Not: questionImagePath, soru sayfasında gösterilecek fotoğrafın yolu.
  static List<_PageContent> _buildPages(
      String questionImagePath, String solution) {
    // Çok kısa ise tek sayfa — foto + çözüm beraber.
    if (solution.length < 900) {
      return [
        _PageContent(
          pageNumber: 1,
          totalPages: 1,
          questionImagePath: questionImagePath,
          solutionText: solution,
          showHeader: true,
          showFooter: true,
        ),
      ];
    }

    final solutionChunks = _splitByParagraph(solution, charsPerPage: 750);

    final total = solutionChunks.length + 1; // +1 soru sayfası için
    final pages = <_PageContent>[
      // Sayfa 1 — SORU FOTOĞRAFI + tam başlık (logo + chips), footer YOK
      _PageContent(
        pageNumber: 1,
        totalPages: total,
        questionImagePath: questionImagePath,
        solutionText: null,
        showHeader: true,
        showFooter: false,
      ),
    ];
    for (var i = 0; i < solutionChunks.length; i++) {
      final isLast = i == solutionChunks.length - 1;
      pages.add(_PageContent(
        pageNumber: i + 2,
        totalPages: total,
        questionImagePath: null,
        solutionText: solutionChunks[i],
        isSolutionContinuation: i > 0,
        // Ara sayfalar başlıksız; sadece SON sayfada footer görünür.
        showHeader: false,
        showFooter: isLast,
      ));
    }
    return pages;
  }

  // Metni \n\n sınırında parçalayıp her sayfanın ~charsPerPage altında kalmasını
  // hedefleyerek gruplar. Tek bir paragraf çok uzunsa o kendi sayfasında kalır.
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
    final pattern = RegExp(r'^\[(VIDEO|WEB|TEST):\s*"(.+?)"\s*\|\s*(.+?)\]\s*$');
    return full
        .split('\n')
        .where((line) => pattern.firstMatch(line.trim()) == null)
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
                          'AuraSnap',
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
                      child: _questionImage(record.imagePath, maxH: 720),
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
  final String? questionImagePath; // Soru sayfasında gösterilecek fotoğraf
  final String? solutionText;
  final bool isSolutionContinuation;
  final bool showHeader; // Logo + AuraSnap + chip'ler
  final bool showFooter; // "AuraSnap ile çözüldü" satırı
  const _PageContent({
    required this.pageNumber,
    required this.totalPages,
    this.questionImagePath,
    this.solutionText,
    this.isSolutionContinuation = false,
    this.showHeader = false,
    this.showFooter = false,
  });
}

// ─── TEK SAYFA KARTI ─────────────────────────────────────────────────────────

class _PageCard extends StatelessWidget {
  final SolutionRecord record;
  final _PageContent content;
  const _PageCard({required this.record, required this.content});

  @override
  Widget build(BuildContext context) {
    // Header varsa üstte 110 padding, yoksa çok az — sayfa numarası kadar boşluk
    final topPad = content.showHeader ? 110.0 : 18.0;
    return Container(
      width: ImageShareService._cardWidth,
      color: const Color(0xFFF5F6F8),
      padding: EdgeInsets.fromLTRB(12, topPad, 12, 40),
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
                  Text(
                    'AuraSnap',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
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

          // Sayfa indicator (birden fazla sayfa varsa HER sayfada göster)
          if (content.totalPages > 1) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      'Sayfa ${content.pageNumber} / ${content.totalPages}',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Sayfa numarası kadar az boşluk
            const SizedBox(height: 12),
          ],

          // İçerik çerçevesi — overflow taşmasın diye hardEdge clip
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
                if (content.questionImagePath != null) ...[
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(content.questionImagePath!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        height: 400,
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: Text(
                          'Fotoğraf açılamadı',
                          style: GoogleFonts.poppins(
                            color: Colors.black54,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // SORU + ÇÖZÜM aynı sayfadaysa ayraç
                if (content.questionImagePath != null && content.solutionText != null) ...[
                  const SizedBox(height: 54),
                  Container(height: 3, color: Colors.black12),
                  const SizedBox(height: 40),
                ],

                // ÇÖZÜM bölümü (varsa)
                if (content.solutionText != null) ...[
                  if (content.isSolutionContinuation)
                    // Devam sayfası — küçük metin, üstte, ikon yok
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Çözüm (devam)',
                        style: GoogleFonts.poppins(
                          color: Colors.black87,
                          fontSize: 45,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else ...[
                    // İlk çözüm sayfası — büyük başlık
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
                    'AuraSnap ile saniyeler içinde çözüldü',
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

// ─── Paylaşılan yardımcı — soru görseli, yoksa placeholder ───────────────────
Widget _questionImage(String path, {required double maxH}) {
  final f = File(path);
  if (f.existsSync()) {
    return Image.file(
      f,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _imagePlaceholder(maxH),
    );
  }
  return _imagePlaceholder(maxH);
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
