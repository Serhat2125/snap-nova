import '../services/runtime_translator.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/gemini_service.dart';
import '../services/solutions_storage.dart';
import '../services/feedback_service.dart';
import '../services/image_share_service.dart';
import '../widgets/adaptive_photo.dart';
import '../widgets/latex_text.dart';
import '../widgets/study_suite_sheet.dart';
import '../main.dart' show localeService;

// ═══════════════════════════════════════════════════════════════════════════════
//  AiResultScreen
// ═══════════════════════════════════════════════════════════════════════════════

class AiResultScreen extends StatefulWidget {
  final String result;
  final String imagePath;
  final String solutionType;
  final String modelName;
  // Geçmişten açılırken mevcut kayıt ID'si ve zamanı
  final String?   existingRecordId;
  final DateTime? existingTimestamp;

  const AiResultScreen({
    super.key,
    required this.result,
    required this.imagePath,
    required this.solutionType,
    required this.modelName,
    this.existingRecordId,
    this.existingTimestamp,
  });

  @override
  State<AiResultScreen> createState() => _AiResultScreenState();
}

class _AiResultScreenState extends State<AiResultScreen> {
  late final String _mainText;

  // ── Typewriter ───────────────────────────────────────────────────────────────
  String _displayed = '';
  int    _charIdx   = 0;
  Timer? _typeTimer;
  bool   _done      = false;

  // ── Scroll ───────────────────────────────────────────────────────────────────
  final _scrollCtrl = ScrollController();

  // ── Follow-up ────────────────────────────────────────────────────────────────
  final _followCtrl  = TextEditingController();
  final _followFocus = FocusNode();
  bool   _isAsking   = false;
  final List<_QA> _qaList = [];

  // ── Geri bildirim ────────────────────────────────────────────────────────────
  bool?  _liked;              // null=cevapsız, true=👍, false=👎
  bool   _positiveGlow = false;
  bool   _isRetrying   = false;
  bool   _blurActive   = false; // arka plan flu efekti

  // ── Storage ──────────────────────────────────────────────────────────────────
  late final String   _recordId;
  late final DateTime _createdAt;
  String _aiTitle = '';

  // ── Paylaş kartı için key ─────────────────────────────────────────────────
  final GlobalKey _shareCardKey = GlobalKey();
  bool _sharing = false;

  // ── Study Suite cache (Konuyu Pekiştir) ───────────────────────────────────
  Map<String, dynamic>? _cachedStudySuite;

  @override
  void initState() {
    super.initState();
    _mainText = _stripResourceLines(widget.result);

    _createdAt = widget.existingTimestamp ?? DateTime.now();
    _recordId  = widget.existingRecordId ?? _createdAt.millisecondsSinceEpoch.toString();
    _followFocus.addListener(() => setState(() {}));
    _followCtrl.addListener(() => setState(() {}));
    if (widget.existingRecordId != null) {
      // Geçmişten açıldı — anında göster, tekrar kaydetme
      _displayed = _mainText;
      _done      = true;
      // Daha önce üretilmiş Study Suite varsa yükle
      _loadCachedStudySuite();
    } else {
      _startTypewriter();
    }
  }

  Future<void> _loadCachedStudySuite() async {
    final cached = await SolutionsStorage.loadStudySuite(_recordId);
    if (mounted && cached != null) {
      setState(() => _cachedStudySuite = cached);
    }
  }

  // ── Kaynak satırlarını metinden çıkar ────────────────────────────────────────
  static String _stripResourceLines(String full) {
    final pattern = RegExp(r'^\[(VIDEO|WEB|TEST):\s*"(.+?)"\s*\|\s*(.+?)\]\s*$');
    return full.split('\n')
        .where((line) => pattern.firstMatch(line.trim()) == null)
        .join('\n');
  }

  void _startTypewriter() {
    _typeTimer = Timer.periodic(const Duration(milliseconds: 14), (t) {
      if (_charIdx >= _mainText.length) {
        t.cancel();
        if (mounted) {
          setState(() => _done = true);
          _saveRecord();
        }
        return;
      }
      final end = (_charIdx + 3).clamp(0, _mainText.length);
      if (mounted) {
        setState(() {
          _displayed = _mainText.substring(0, end);
          _charIdx   = end;
        });
      }
    });
  }

  void _skipTypewriter() {
    _typeTimer?.cancel();
    if (mounted) {
      setState(() { _displayed = _mainText; _done = true; });
      _saveRecord();
    }
  }

  Future<void> _saveRecord() async {
    // Geçmişten açıldıysa ve Q&A eklenmemişse yeniden kaydetme
    if (widget.existingRecordId != null && _qaList.isEmpty) return;
    // Fotoğrafı kalıcı klasöre kopyala (yalnızca ilk kayıtta).
    final persistedPath = widget.existingRecordId != null
        ? widget.imagePath
        : await SolutionsStorage.persistImage(widget.imagePath);

    final subject = SolutionsStorage.detectSubjectSmart(widget.result);

    // AI başlığı yalnızca ilk kayıtta üretilir.
    if (_aiTitle.isEmpty && widget.existingRecordId == null) {
      final title = await GeminiService.generateTitle(widget.result);
      if (title.isNotEmpty) _aiTitle = title;
    }

    final record = SolutionRecord(
      id: _recordId,
      imagePath: persistedPath,
      solutionType: widget.solutionType.replaceAll('\n', ' '),
      modelName: widget.modelName.isEmpty ? 'QuAlsar' : widget.modelName,
      result: widget.result,
      qaList: _qaList
          .map((qa) => QARecord(question: qa.question, answer: qa.answer))
          .toList(),
      subject: subject,
      aiTitle: _aiTitle,
      timestamp: _createdAt,
      studySuite: _cachedStudySuite, // Konuyu Pekiştir cache — silinmesin
    );
    await SolutionsStorage.saveOrUpdate(record);
  }

  Future<void> _sendFollowUp() async {
    final q = _followCtrl.text.trim();
    if (q.isEmpty || _isAsking) return;
    _followFocus.unfocus();
    setState(() => _isAsking = true);

    try {
      final answer = await GeminiService.askFollowUp(
        previousSolution: widget.result,
        userQuestion: q,
      );
      if (!mounted) return;
      final qa = _QA(question: q, answer: answer);
      setState(() {
        _qaList.add(qa);
        _followCtrl.clear();
      });
      _saveRecord(); // Q&A eklendikten sonra güncelle
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = qa.key.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            alignment: 0.0, // öğeyi görünür alanın üstüne hizala
          );
        }
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      _showSnack(e.userMessage.replaceAll('\n', ' '));
    } catch (_) {
      if (!mounted) return;
      _showSnack(localeService.tr('error_retry'));
    } finally {
      if (mounted) setState(() => _isAsking = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.surfaceElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _scrollCtrl.dispose();
    _followCtrl.dispose();
    _followFocus.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SelectionArea(
        child: Stack(
          children: [
            Column(
              children: [
            _buildTopBar(),

            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(6, 18, 6, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhotoCard(),
                    const SizedBox(height: 26),

                    _buildSolutionCard(),

                    if (!_done) ...[
                      const SizedBox(height: 12),
                      _buildSkipButton(),
                    ] else ...[
                      const SizedBox(height: 10),
                      _buildDoneRow(),
                    ],

                    for (final qa in _qaList) ...[
                      const SizedBox(height: 16),
                      _buildQACard(qa),
                    ],

                    if (_done) ...[
                      const SizedBox(height: 24),
                      _buildStudySuiteButton(),
                      const SizedBox(height: 12),
                      _buildScanAgainButton(),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            _buildStickyInput(),
              ],
            ),

            // ── Blur overlay — sheet/dialog açıkken arka planı flu yapar ──────
            if (_blurActive)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.40),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  // ── Üst bar ───────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.black12, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 1.2),
              ),
              child: Text(
                widget.solutionType.replaceAll('\n', ' '),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _done
                ? const Icon(Icons.check_circle_rounded,
                    key: ValueKey('done'),
                    color: Color(0xFF22C55E), size: 20)
                : const _PulseDot(key: ValueKey('pulse')),
          ),
        ],
      ),
    );
  }

  // ── Paylaş: önizleme sheet'i (artık PDF paylaşımıyla değiştirildi) ────────
  // ignore: unused_element
  void _openSharePreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: RepaintBoundary(
                      key: _shareCardKey,
                      child: _buildShareCard(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(sheetCtx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.close_rounded),
                        label: Text(
                          'İptal',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: StatefulBuilder(
                        builder: (ctx, setLocal) => FilledButton.icon(
                          onPressed: _sharing
                              ? null
                              : () async {
                                  setLocal(() => _sharing = true);
                                  await _shareAsImage();
                                  if (ctx.mounted) {
                                    setLocal(() => _sharing = false);
                                  }
                                  if (sheetCtx.mounted) {
                                    Navigator.pop(sheetCtx);
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6A00),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: _sharing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.share_rounded),
                          label: Text(
                            _sharing ? 'Hazırlanıyor…'.tr() : 'Paylaş'.tr(),
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Paylaşılacak kart görseli ─────────────────────────────────────────────
  Widget _buildShareCard() {
    final preview = _mainText.length > 520
        ? '${_mainText.substring(0, 520)}…'
        : _mainText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7EE), Color(0xFFFFE7D0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFFFB380), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8A3D), Color(0xFFFF6A00)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.auto_awesome_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                'QuAlsar',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1F2937),
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFF6A00)),
                ),
                child: Text(
                  widget.solutionType.replaceAll('\n', ' '),
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFFF6A00),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.imagePath.isNotEmpty && File(widget.imagePath).existsSync())
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(widget.imagePath),
                  width: double.infinity,
                  height: 140,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFE2C7)),
            ),
            child: Text(
              preview,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                height: 1.55,
                color: const Color(0xFF1F2937),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  size: 14, color: Color(0xFFFF6A00)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'QuAlsar ile saniyeler içinde çözüldü',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFF6A00),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Kartı görsele çevir ve paylaş ─────────────────────────────────────────
  Future<void> _shareAsImage() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _shareCardKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Kart bulunamadı');
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) throw Exception('Görsel oluşturulamadı');
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/qualsar_cozum_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: localeService.tr('share_invite_text'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${localeService.tr('share_failed')}: $e')),
      );
    }
  }

  // ── Fotoğraf kartı ─ ince çerçeve, üstte ders etiketi ──────────────────────

  Widget _buildPhotoCard() {
    final subject = SolutionsStorage.detectSubjectSmart(widget.result);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Fotoğraf artık sabit 250 px DEĞİL — kendi oranına göre uzar/kısar,
        // dikey/yatay tüm görseller TAM gözükür (BoxFit.contain).
        AdaptivePhoto(
          path: widget.imagePath,
          maxHeightFactor: 0.55,
          borderRadius: 14,
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.55),
            width: 0.6,
          ),
          background: AppColors.surface,
        ),
        _frameLabel(top: -7, left: 14, text: subject.toUpperCase()),
        _frameLabel(
          bottom: -7,
          right: 14,
          text: _shortStamp(),
          muted: true,
        ),
      ],
    );
  }

  String _shortStamp() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = _createdAt;
    return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  // Çerçeve üstünde/altında "kesik" etkili küçük etiket.
  Widget _frameLabel({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required String text,
    bool muted = false,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        color: const Color(0xFFF0F2F5),
        child: Text(
          text,
          style: TextStyle(
            color: muted ? Colors.black54 : Colors.black,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  // ── Çözüm kartı ─ ince çerçeve, üstte etiket ───────────────────────────────

  Widget _buildSolutionCard() {
    final subject = SolutionsStorage.detectSubjectSmart(widget.result);
    final modelLabel = widget.modelName.isEmpty ? 'QuAlsar' : widget.modelName;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: _done
              ? const EdgeInsets.fromLTRB(14, 16, 14, 0)
              : const EdgeInsets.fromLTRB(14, 16, 14, 16),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.55),
              width: 0.6,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LatexText(_displayed),
              if (!_done) ...[
                const SizedBox(height: 6),
                const _BlinkingCursor(),
              ] else ...[
                const SizedBox(height: 14),
                _buildFeedbackCard(),
              ],
            ],
          ),
        ),
        _frameLabel(
          top: -7,
          left: 14,
          text: '${localeService.tr('solution').toUpperCase()} · ${subject.toUpperCase()}',
        ),
        _frameLabel(
          bottom: -7,
          right: 14,
          text: modelLabel.toUpperCase(),
          muted: true,
        ),
      ],
    );
  }

  Widget _buildSkipButton() {
    return Center(
      child: GestureDetector(
        onTap: _skipTypewriter,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.cyan.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fast_forward_rounded,
                  color: AppColors.textMuted, size: 13),
              const SizedBox(width: 5),
              Text(localeService.tr('show_all'),
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoneRow() {
    // Tek geniş "Arkadaşına Gönder" sekmesi — yatayda tam genişlik.
    return GestureDetector(
      onTap: _sharing ? null : _shareSolutionAsPdf,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_sharing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppColors.cyan,
                  strokeWidth: 2,
                ),
              )
            else ...[
              Flexible(
                child: Text(
                  localeService.tr('share_with_friend'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Transform.rotate(
                // +x yönü — saat 2 civarı: -45° (−π/4)
                angle: -math.pi / 4,
                child: const Icon(Icons.send_rounded,
                    color: Color(0xFF0070FF), size: 22),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Çift görsel (preview + tam çözüm) olarak paylaş
  Future<void> _shareSolutionAsPdf() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Defans: storage'da bu id için güncel bir kayıt varsa onu kullan.
      // Aksi halde widget'tan kur. Bu, widget.imagePath'in eski temp dosyaya
      // işaret ettiği durumlarda yanlış fotoğraf paylaşılmasını engeller.
      SolutionRecord? record;
      try {
        final all = await SolutionsStorage.loadAll();
        record = all.firstWhere(
          (r) => r.id == _recordId,
          orElse: () => SolutionRecord(
            id: '',
            imagePath: '',
            solutionType: '',
            result: '',
            qaList: const [],
            subject: '',
            timestamp: _createdAt,
          ),
        );
        if (record.id.isEmpty) record = null;
      } catch (_) {
        record = null;
      }

      record ??= SolutionRecord(
        id: _recordId,
        imagePath: widget.imagePath,
        solutionType: widget.solutionType.replaceAll('\n', ' '),
        modelName: widget.modelName.isEmpty ? 'QuAlsar' : widget.modelName,
        result: widget.result,
        qaList: _qaList
            .map((qa) => QARecord(question: qa.question, answer: qa.answer))
            .toList(),
        subject: SolutionsStorage.detectSubjectSmart(widget.result),
        aiTitle: _aiTitle,
        timestamp: _createdAt,
      );

      debugPrint('[Share] record id=${record.id} '
          'img=${record.imagePath.split('/').last} '
          'resultLen=${record.result.length}');

      if (!mounted) return;
      await ImageShareService.shareDouble(
        context: context,
        record: record,
      );
    } catch (e, st) {
      debugPrint('[AiResultScreen] image share error: $e\n$st');
      if (mounted) {
        _showSnack('Görsel paylaşılamadı: ${e.toString().replaceAll('\n', ' ')}');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Q&A kartı ─────────────────────────────────────────────────────────────────

  Widget _buildQACard(_QA qa) {
    return Column(
      key: qa.key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kullanıcı sorusu (sağda)
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00E5FF), Color(0xFF0070FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Text(
              qa.question,
              style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // AI cevabı (solda) — adım etiketleri renkli
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(
                color: Colors.black.withValues(alpha: 0.55), width: 0.6),
          ),
          child: LatexText(qa.answer, fontSize: 13, lineHeight: 1.65),
        ),
      ],
    );
  }

  // ── Olumlu geri bildirim ─────────────────────────────────────────────────────

  void _onPositiveTapped() {
    if (_liked == true) return;
    setState(() { _liked = true; _positiveGlow = true; });
    FeedbackService.saveFeedback(
      isPositive: true,
      solutionMode: widget.solutionType,
      questionSummary: widget.result,
    );
    // Parlama animasyonunu 800ms sonra kapat
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _positiveGlow = false);
    });
  }

  // ── Olumsuz geri bildirim + BottomSheet ──────────────────────────────────────

  void _onNegativeTapped() {
    if (_liked == false) return;
    setState(() => _liked = false);
    _showNegativeFeedbackSheet();
  }

  void _showNegativeFeedbackSheet() {
    final reasons = [
      localeService.tr('fb_calculation_error'),
      localeService.tr('fb_wrong_answer'),
      localeService.tr('fb_complex'),
      localeService.tr('fb_wrong_topic'),
      localeService.tr('fb_incomplete'),
      localeService.tr('fb_slow'),
    ];
    final selected = <String>{};

    // Arka planı flu yap
    setState(() => _blurActive = true);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,  // container'ın border'ı görünsün
      barrierColor: Colors.transparent,      // blur overlay biz yönetiyoruz
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          // ── Tüm sheet alanı beyaz, siyah ince çerçeve ───────────────────
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.12),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Tutamaç çubuğu
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Center(
                child: Text(
                  localeService.tr('what_to_improve'),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Center(
                child: Text(
                  'Geri bildirimin sistemi daha iyi hale getirecek.',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.55),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Neden seçenekleri — 2 sütun grid ─────────────────────────
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.6,
                children: reasons.map((r) {
                  final sel = selected.contains(r);
                  return GestureDetector(
                    onTap: () => setSheet(() =>
                        sel ? selected.remove(r) : selected.add(r)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        // İç çerçeve de beyaz; seçiliyken hafif cyan tint
                        color: sel
                            ? AppColors.cyan.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel
                              ? AppColors.cyan.withValues(alpha: 0.75)
                              : Colors.black.withValues(alpha: 0.18),
                          width: sel ? 1.6 : 1.0,
                        ),
                        boxShadow: sel
                            ? [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.15), blurRadius: 10)]
                            : [],
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 16, height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sel ? AppColors.cyan : Colors.transparent,
                              border: Border.all(
                                color: sel ? AppColors.cyan : Colors.black.withValues(alpha: 0.35),
                                width: 1.4,
                              ),
                            ),
                            child: sel
                                ? const Icon(Icons.check, color: Colors.white, size: 10)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 11.5,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 10),

              // ── Gönder butonu — beyaz arka plan, cyan kenar ───────────
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  FeedbackService.saveFeedback(
                    isPositive: false,
                    solutionMode: widget.solutionType,
                    questionSummary: widget.result,
                    userReason: selected.isNotEmpty ? selected.join(', ') : null,
                  );
                  if (!mounted) return;
                  _showRetryDialog(selected.isNotEmpty ? selected.join(', ') : null);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.70),
                      width: 1.4,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      localeService.tr('send_feedback'),
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _blurActive = false);
    });
  }

  // ── Yeniden çözüm teklifi diyalogu ───────────────────────────────────────────

  void _showRetryDialog(String? reason) {
    // Dialog açılırken arka planı flu tut
    if (mounted) setState(() => _blurActive = true);

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, _, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 10 * anim.value,
            sigmaY: 10 * anim.value,
          ),
          child: FadeTransition(
            opacity:
                CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOut),
              ),
              child: child,
            ),
          ),
        );
      },
      pageBuilder: (ctx, _, __) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Colors.black.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: const Icon(Icons.auto_fix_high_rounded,
                    color: AppColors.cyan, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                localeService.tr('feedback_thanks'),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                localeService.tr('ai_teacher_offer'),
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Evet → AI Öğretmen
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _retryWithAITeacher();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.cyan, Color(0xFF0070FF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.30),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.school_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        localeService.tr('yes_ai_teacher'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Hayır → kapat (beyaz arka plan, siyah kenar, siyah yazı)
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.black.withValues(alpha: 0.30),
                        width: 1.0),
                  ),
                  child: Center(
                    child: Text(
                      localeService.tr('no_thanks'),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _blurActive = false);
    });
  }

  // ── AI Öğretmen yeniden çözüm ────────────────────────────────────────────────

  Future<void> _retryWithAITeacher() async {
    setState(() => _isRetrying = true);

    try {
      final result = await GeminiService.analyzeImage(
        widget.imagePath,
        localeService.tr('ai_teacher'),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AiResultScreen(
            result: result,
            imagePath: widget.imagePath,
            solutionType: localeService.tr('ai_teacher'),
            modelName: widget.modelName,
          ),
        ),
      );
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() => _isRetrying = false);
      _showSnack(e.userMessage.replaceAll('\n', ' '));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRetrying = false);
      _showSnack(localeService.tr('error_retry'));
    }
  }

  // ── Geri bildirim kartı ──────────────────────────────────────────────────────

  Widget _buildFeedbackCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        color: _positiveGlow
            ? const Color(0xFF22C55E).withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: _isRetrying
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      color: AppColors.cyan, strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    localeService.tr('ai_teacher_loading'),
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : Row(
              // Yazı ve sekmeler tek satırda yan yana
              children: [
                Expanded(
                  child: Text(
                    _liked == true
                        ? localeService.tr('great_success')
                        : localeService.tr('was_helpful'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _liked == true
                          ? const Color(0xFF22C55E)
                          : Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _FeedbackButton(
                  emoji: '👍',
                  label: localeService.tr('yes'),
                  selected: _liked == true,
                  activeColor: const Color(0xFF22C55E),
                  onTap: _onPositiveTapped,
                ),
                const SizedBox(width: 5),
                _FeedbackButton(
                  emoji: '👎',
                  label: localeService.tr('no'),
                  selected: _liked == false,
                  activeColor: const Color(0xFFEF4444),
                  onTap: _onNegativeTapped,
                ),
              ],
            ),
    );
  }

  // ── "Bu soruyla ilgili konuyu pekiştir" — Study Suite açıcı ─────────────────

  Widget _buildStudySuiteButton() {
    final subject = SolutionsStorage.detectSubject(widget.result);
    final hasCache = _cachedStudySuite != null;
    final label = localeService.tr(
        hasCache ? 'continue_studying' : 'reinforce_this_topic');
    return GestureDetector(
      onTap: () => StudySuiteSheet.show(
        context,
        solution: widget.result,
        subject:  subject,
        cached: _cachedStudySuite,
        onFetched: (json) {
          if (mounted) setState(() => _cachedStudySuite = json);
          SolutionsStorage.saveStudySuite(_recordId, json);
        },
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.black,
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF0070FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                hasCache
                    ? Icons.bookmark_rounded
                    : Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, color: Colors.black, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Başka soru tara butonu ────────────────────────────────────────────────────

  Widget _buildScanAgainButton() {
    return GestureDetector(
      onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.cyan, Color(0xFF0070FF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.cyan.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              localeService.tr('scan_another'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sabit soru alanı ─ cyan ok + çerçeve ────────────────────────────────────

  Widget _buildStickyInput() {
    final focused  = _followFocus.hasFocus;
    final hasText  = _followCtrl.text.trim().isNotEmpty;
    final inactive = _isAsking || !hasText;

    return Container(
      decoration: BoxDecoration(
        // Dış kabuk — soluk beyaz
        color: const Color(0xFFF5F5F5),
        border: Border(
          top: BorderSide(
              color: Colors.black.withValues(alpha: 0.10), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Input alanı — saf beyaz
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: focused
                      ? Colors.black
                      : Colors.black.withValues(alpha: 0.14),
                  width: focused ? 1.5 : 1.0,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                        )
                      ]
                    : [],
              ),
              child: TextField(
                controller: _followCtrl,
                focusNode: _followFocus,
                maxLines: 4,
                minLines: 1,
                style: const TextStyle(color: Colors.black, fontSize: 13),
                decoration: InputDecoration(
                  hintText: localeService.tr('ask_anything'),
                  hintStyle: TextStyle(
                    color: Colors.black.withValues(alpha: 0.38),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendFollowUp(),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Gönder butonu — her zaman cyan tonlu
          GestureDetector(
            onTap: _sendFollowUp,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: inactive
                    ? null
                    : const LinearGradient(
                        colors: [AppColors.cyan, Color(0xFF0070FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: inactive ? Colors.white : null,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: inactive
                      ? Colors.black.withValues(alpha: 0.20)
                      : Colors.transparent,
                ),
                boxShadow: inactive
                    ? []
                    : [
                        BoxShadow(
                          color: AppColors.cyan.withValues(alpha: 0.35),
                          blurRadius: 12,
                        ),
                      ],
              ),
              child: _isAsking
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: AppColors.cyan,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      color: hasText
                          ? Colors.white
                          : Colors.black.withValues(alpha: 0.45),
                      size: 22,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Geri bildirim butonu ─────────────────────────────────────────────────────

class _FeedbackButton extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  const _FeedbackButton({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: selected ? activeColor : Colors.black,
            width: selected ? 1.4 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.18),
                    blurRadius: 6,
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? activeColor : Colors.black,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Veri modeli ──────────────────────────────────────────────────────────────

class _QA {
  final String question;
  final String answer;
  final GlobalKey key;
  _QA({required this.question, required this.answer}) : key = GlobalKey();
}


// ─── Animasyonlar ─────────────────────────────────────────────────────────────

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 530))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2,
        height: 16,
        decoration: BoxDecoration(
          color: AppColors.cyan,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({super.key});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cyan.withValues(alpha: 0.5 + 0.5 * _ctrl.value),
          boxShadow: [
            BoxShadow(
              color: AppColors.cyan.withValues(alpha: 0.4 * _ctrl.value),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
