import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/solutions_storage.dart';
import '../services/gemini_service.dart';
import '../widgets/latex_text.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  SolutionDetailScreen — Geçmişten çözüm detayı + takip sorusu
// ═══════════════════════════════════════════════════════════════════════════════

class SolutionDetailScreen extends StatefulWidget {
  final SolutionRecord record;
  const SolutionDetailScreen({super.key, required this.record});

  @override
  State<SolutionDetailScreen> createState() => _SolutionDetailScreenState();
}

class _SolutionDetailScreenState extends State<SolutionDetailScreen> {
  late List<QARecord> _qaList;
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _qaList = List<QARecord>.from(widget.record.qaList);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Takip sorusu gönder ───────────────────────────────────────────────────
  Future<void> _sendQuestion() async {
    final q = _inputCtrl.text.trim();
    if (q.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _inputCtrl.clear();
    });
    _scrollToBottom();

    try {
      final answer = await GeminiService.askFollowUp(
        previousSolution: widget.record.result,
        userQuestion: q,
      );
      final qa = QARecord(question: q, answer: answer);
      setState(() => _qaList.add(qa));

      // Kaydet
      final updated = SolutionRecord(
        id:           widget.record.id,
        imagePath:    widget.record.imagePath,
        result:       widget.record.result,
        solutionType: widget.record.solutionType,
        subject:      widget.record.subject,
        timestamp:    widget.record.timestamp,
        qaList:       _qaList,
      );
      await SolutionsStorage.saveOrUpdate(updated);

      _scrollToBottom(delayed: true);
    } on GeminiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage,
              style: const TextStyle(fontSize: 13)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Beklenmedik bir hata oluştu.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom({bool delayed = false}) {
    Future.delayed(Duration(milliseconds: delayed ? 350 : 80), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final color = _colorFor(widget.record.subject);
    final icon  = _iconFor(widget.record.subject);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, color, icon),

            // ── Kaydırılabilir içerik ──────────────────────────────────────
            Expanded(
              child: ListView(
                controller: _scrollCtrl,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  _buildPhotoCard(),
                  const SizedBox(height: 16),

                  const Text(
                    'Çözüm',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  _buildSolutionCard(),

                  if (_qaList.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Sorular & Cevaplar',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final qa in _qaList) ...[
                      _buildQACard(context, qa),
                      const SizedBox(height: 12),
                    ],
                  ],

                  // Yazıyor göstergesi için boşluk
                  if (_sending) ...[
                    const SizedBox(height: 12),
                    _buildTypingIndicator(),
                  ],

                  const SizedBox(height: 8),
                ],
              ),
            ),

            // ── Sohbet giriş kutusu ────────────────────────────────────────
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Üst bar ──────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppColors.cyan.withValues(alpha: 0.10), width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cyan),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.30)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 13),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${widget.record.subject}  •  ${widget.record.solutionType}',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF22C55E), size: 20),
        ],
      ),
    );
  }

  // ── Fotoğraf ──────────────────────────────────────────────────────────────────
  Widget _buildPhotoCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.cyan.withValues(alpha: 0.65),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.22),
            blurRadius: 20,
            spreadRadius: 3,
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
              File(widget.record.imagePath),
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

  // ── Çözüm kartı ───────────────────────────────────────────────────────────────
  Widget _buildSolutionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.cyan.withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LatexText(widget.record.result),
    );
  }

  // ── Q&A balonu ────────────────────────────────────────────────────────────────
  Widget _buildQACard(BuildContext context, QARecord qa) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border:
                Border.all(color: AppColors.cyan.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
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

  // ── Yazıyor göstergesi ────────────────────────────────────────────────────────
  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(delay: 0),
            const SizedBox(width: 4),
            _Dot(delay: 200),
            const SizedBox(width: 4),
            _Dot(delay: 400),
          ],
        ),
      ),
    );
  }

  // ── Giriş kutusu ─────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).viewInsets.bottom + 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.cyan.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _inputCtrl,
        builder: (_, val, __) {
          final hasText = val.text.trim().isNotEmpty;
          return Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Aklına ne takıldıysa sor',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: AppColors.cyan.withValues(alpha: 0.38)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: AppColors.cyan.withValues(alpha: 0.38)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: AppColors.cyan.withValues(alpha: 0.70),
                          width: 1.4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sending ? null : _sendQuestion,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: hasText && !_sending
                        ? AppColors.cyan.withValues(alpha: 0.18)
                        : Colors.transparent,
                    border: Border.all(
                      color: hasText && !_sending
                          ? AppColors.cyan.withValues(alpha: 0.70)
                          : AppColors.cyan.withValues(alpha: 0.30),
                      width: 1.3,
                    ),
                  ),
                  child: _sending
                      ? Padding(
                          padding: const EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.cyan.withValues(alpha: 0.70),
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward_rounded,
                          color: hasText
                              ? AppColors.cyan
                              : AppColors.cyan.withValues(alpha: 0.40),
                          size: 20,
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Dot animasyonu ───────────────────────────────────────────────────────────

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.cyan,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ─── Yardımcılar ──────────────────────────────────────────────────────────────

IconData _iconFor(String subject) => switch (subject) {
      'Fizik'     => Icons.bolt_rounded,
      'Kimya'     => Icons.science_rounded,
      'Biyoloji'  => Icons.biotech_rounded,
      'Coğrafya'  => Icons.public_rounded,
      'Tarih'     => Icons.account_balance_rounded,
      'Edebiyat'  => Icons.menu_book_rounded,
      'Felsefe'   => Icons.psychology_rounded,
      'İngilizce' => Icons.translate_rounded,
      'Diğer'     => Icons.help_outline_rounded,
      _           => Icons.functions_rounded,
    };

Color _colorFor(String subject) => switch (subject) {
      'Fizik'     => const Color(0xFFF59E0B),
      'Kimya'     => const Color(0xFF10B981),
      'Biyoloji'  => const Color(0xFF8B5CF6),
      'Coğrafya'  => const Color(0xFF06B6D4),
      'Tarih'     => const Color(0xFFEF4444),
      'Edebiyat'  => const Color(0xFFF97316),
      'Felsefe'   => const Color(0xFFA855F7),
      'İngilizce' => const Color(0xFF22C55E),
      'Diğer'     => const Color(0xFF6B7280),
      _           => const Color(0xFF3B82F6),
    };

