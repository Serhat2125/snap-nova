import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/gemini_service.dart';
import '../services/solutions_storage.dart';
import '../services/feedback_service.dart';
import '../widgets/latex_text.dart';
import '../widgets/study_suite_sheet.dart';

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
    } else {
      _startTypewriter();
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
      modelName: widget.modelName.isEmpty ? 'SnapNova' : widget.modelName,
      result: widget.result,
      qaList: _qaList
          .map((qa) => QARecord(question: qa.question, answer: qa.answer))
          .toList(),
      subject: subject,
      aiTitle: _aiTitle,
      timestamp: _createdAt,
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
      _showSnack('Bir hata oluştu, tekrar dene.');
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
        child: Stack(
          children: [
            Column(
              children: [
            _buildTopBar(),

            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPhotoCard(),
                    const SizedBox(height: 16),

                    // "Çözüm" başlığı — siyah, geniş harf aralığı
                    const SizedBox(
                      width: double.infinity,
                      child: Text(
                        'Çözüm',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

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
                      const SizedBox(height: 14),
                      _buildFeedbackCard(),
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

  // ── Fotoğraf kartı ─ belirgin çerçeve ────────────────────────────────────────

  Widget _buildPhotoCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.black,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: double.infinity,
          height: 250,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 5.0,
            clipBehavior: Clip.none,
            child: Image.file(
              File(widget.imagePath),
              width: double.infinity,
              height: 250,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: double.infinity,
                height: 250,
                color: AppColors.surface,
                child: const Icon(Icons.image_not_supported_outlined,
                    color: AppColors.textMuted, size: 36),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Çözüm kartı ─ adım etiketleri renkli ────────────────────────────────────

  Widget _buildSolutionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LatexText(_displayed),
          if (!_done) ...[
            const SizedBox(height: 6),
            const _BlinkingCursor(),
          ],
        ],
      ),
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fast_forward_rounded,
                  color: AppColors.textMuted, size: 13),
              SizedBox(width: 5),
              Text('Tamamını Göster',
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
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: Color(0xFF22C55E), size: 13),
            const SizedBox(width: 5),
            const Text(
              'Çözüm tamamlandı',
              style: TextStyle(
                  color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
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
                color: Colors.black, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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
      'İşlem hatası var',
      'Yanlış cevap verdi',
      'Anlatım karmaşık',
      'Yanlış konu algılandı',
      'Çözüm eksik kaldı',
      'Çok yavaş yanıt verdi',
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
          // ── Tüm sheet alanı çerçeveli ───────────────────────────────────────
          decoration: BoxDecoration(
            color: const Color(0xFF0D1520),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: AppColors.cyan.withValues(alpha: 0.35),
              width: 1.4,
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
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Center(
                child: Text(
                  'Neyi Geliştirelim?',
                  style: TextStyle(
                    color: Colors.white,
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
                    color: Colors.white.withValues(alpha: 0.40),
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
                        color: sel
                            ? AppColors.cyan.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: sel
                              ? AppColors.cyan.withValues(alpha: 0.75)
                              : Colors.white.withValues(alpha: 0.10),
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
                                color: sel ? AppColors.cyan : Colors.white.withValues(alpha: 0.28),
                                width: 1.4,
                              ),
                            ),
                            child: sel
                                ? const Icon(Icons.check, color: Colors.black, size: 10)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: sel ? Colors.white : Colors.white.withValues(alpha: 0.65),
                                fontSize: 11.5,
                                fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
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

              // ── Gönder butonu — mavi ──────────────────────────────────────
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
                    color: AppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.55),
                      width: 1.3,
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Geri Bildirim Gönder',
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_fix_high_rounded,
                    color: AppColors.cyan, size: 26),
              ),
              const SizedBox(height: 16),
              const Text(
                'Geri bildirimin için teşekkürler!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Bu soruyu senin için AI Öğretmen modunda tekrar çözmemi ister misin?',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
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
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Evet, AI Öğretmen ile çöz',
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

              // Hayır → kapat
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Center(
                    child: Text(
                      'Hayır, teşekkürler',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 13,
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
        'AI Öğretmen',
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AiResultScreen(
            result: result,
            imagePath: widget.imagePath,
            solutionType: 'AI Öğretmen',
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
      _showSnack('Bir hata oluştu, tekrar dene.');
    }
  }

  // ── Geri bildirim kartı ──────────────────────────────────────────────────────

  Widget _buildFeedbackCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _positiveGlow
              ? const Color(0xFF22C55E)
              : Colors.black,
          width: 2.0,
        ),
        boxShadow: _positiveGlow
            ? [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: _isRetrying
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      color: AppColors.cyan, strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'AI Öğretmen hazırlanıyor…',
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
                        ? '✨ Harika! Başarılar dileriz.'
                        : 'Bu çözüm sana yardımcı oldu mu?',
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
                  label: 'Evet',
                  selected: _liked == true,
                  activeColor: const Color(0xFF22C55E),
                  onTap: _onPositiveTapped,
                ),
                const SizedBox(width: 5),
                _FeedbackButton(
                  emoji: '👎',
                  label: 'Hayır',
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
    return GestureDetector(
      onTap: () => StudySuiteSheet.show(
        context,
        solution: widget.result,
        subject:  subject,
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
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 10),
            const Text(
              'Bu soruyla ilgili konuyu pekiştir',
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
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
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              'Başka Soru Tara',
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
        // Dış kabuk — beyaz arka plan
        color: Colors.white,
        border: Border(
          top: BorderSide(
              color: Colors.black.withValues(alpha: 0.10), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Input alanı — beyaza yakın hafif gri ton farkı
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6), // beyazdan hafif koyu ton
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
                  hintText: 'Aklına ne takıldıysa sor',
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
