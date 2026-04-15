import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../main.dart' show localeService;
import '../widgets/ai_model_card.dart';
import '../services/gemini_service.dart';
import 'ai_result_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  SolutionScreen
// ═══════════════════════════════════════════════════════════════════════════════

class SolutionScreen extends StatefulWidget {
  final String imagePath;
  final bool isMultiCapture;
  const SolutionScreen({
    super.key,
    required this.imagePath,
    this.isMultiCapture = false,
  });

  @override
  State<SolutionScreen> createState() => _SolutionScreenState();
}

class _SolutionScreenState extends State<SolutionScreen> {
  String? _selectedOption;

  final ScrollController _scrollCtrl = ScrollController();

  // ── Model seçimi ─────────────────────────────────────────────────────────────
  int? _centeredModelIdx;        // null = hiçbiri seçilmedi
  bool _modelSelected    = false; // Kullanıcı modeli tıkladı mı

  // ── API durumu ────────────────────────────────────────────────────────────────
  bool _isLoading = false;

  // ── 3 Çözüm modu ─────────────────────────────────────────────────────────────
  static const _modes = [
    _ModeOption(
      label:    'Basit Çöz',
      subtitle: '',
      icon:     Icons.bolt_rounded,
      color:    Color(0xFFF59E0B),
    ),
    _ModeOption(
      label:    'Adım Adım Çöz',
      subtitle: '',
      icon:     Icons.list_alt_rounded,
      color:    Color(0xFF3B82F6),
    ),
    _ModeOption(
      label:    'AI Öğretmen',
      subtitle: '',
      icon:     Icons.school_rounded,
      color:    Color(0xFFEC4899),
    ),
  ];

  // ── AI modelleri ─────────────────────────────────────────────────────────────

  static final _models = [
    AiModel(
      name: 'QuAlsar',
      subtitle: 'Hızlı ve genel çözüm',
      badge: localeService.tr('recommended'),
      accentColor: AppColors.cyan,
      logo: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(b),
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
      ),
    ),
    AiModel(
      name: 'ChatGPT',
      subtitle: 'Detaylı ve mantıklı çözüm',
      badge: 'Yakında',
      accentColor: Color(0xFF10A37F),
      logo: const Center(
        child: Text('GPT', style: TextStyle(color: Color(0xFF10A37F), fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      ),
    ),
    AiModel(
      name: 'Gemini',
      subtitle: 'Hızlı analiz ve alternatif çözüm',
      badge: 'Aktif',
      accentColor: Color(0xFF4796E3),
      logo: Padding(
        padding: EdgeInsets.all(4),
        child: CustomPaint(painter: _GeminiStarPainter()),
      ),
    ),
    AiModel(
      name: 'Grok',
      subtitle: 'Anlık ve yaratıcı çözüm',
      badge: 'Yakında',
      accentColor: Color(0xFF9CA3AF),
      logo: const Center(
        child: Text('G', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, height: 1.0)),
      ),
    ),
    AiModel(
      name: 'Deepseek',
      subtitle: 'Derin analiz ve akıl yürütme',
      badge: 'Aktif',
      accentColor: Color(0xFF4B8BF5),
      logo: const Center(
        child: Text('DS', style: TextStyle(color: Color(0xFF4B8BF5), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      ),
    ),
    AiModel(
      name: 'Claude',
      subtitle: 'Derin açıklama ve mantık yürütme',
      badge: 'Yakında',
      accentColor: Color(0xFFD97706),
      logo: const Center(
        child: Text('C', style: TextStyle(color: Color(0xFFD97706), fontSize: 26, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, height: 1.0)),
      ),
    ),
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Geri git ─────────────────────────────────────────────────────────────────

  Future<void> _deleteAndGoBack() async {
    try {
      final f = File(widget.imagePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  // ── Buton tıklama yöneticisi ─────────────────────────────────────────────────

  void _onSolveButtonTap() {
    if (_isLoading) return;
    if (_selectedOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localeService.tr('select_method_first'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    _solve();
  }

  // ── Çözüme başla ─────────────────────────────────────────────────────────────

  Future<void> _solve() async {
    if (_selectedOption == null || _isLoading || _centeredModelIdx == null) return;
    final model = _models[_centeredModelIdx!];

    // QuAlsar, Gemini ve Deepseek aktif — diğerleri yakında
    if (model.name != 'QuAlsar' &&
        model.name != 'Gemini' &&
        model.name != 'Deepseek') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${model.name} yakında geliyor! 🚀'),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Sonuç değişkenleri finally dışına taşındı — finally her zaman çalışır
    String? result;
    GeminiException? geminiError;

    try {
      if (model.name == 'Deepseek') {
        result = await GeminiService.analyzeImageWithDeepseek(
          widget.imagePath,
          _selectedOption!,
          isMulti: widget.isMultiCapture,
        );
      } else {
        result = await GeminiService.analyzeImage(
          widget.imagePath,
          _selectedOption!,
          isMulti: widget.isMultiCapture,
        );
      }
    } on GeminiException catch (e) {
      geminiError = e;
    } catch (e) {
      geminiError = GeminiException.unknown(e.toString());
    } finally {
      // _isLoading'i her koşulda sıfırla — UI asla kilitlenmesin
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;

    if (geminiError != null) {
      _showErrorDialog(geminiError);
      return;
    }

    if (result != null) {
      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, a, __) => AiResultScreen(
            result: result!,
            imagePath: widget.imagePath,
            solutionType: _selectedOption!,
            modelName: model.name,
          ),
          transitionsBuilder: (_, a, __, child) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 380),
        ),
      );
    }
  }

  void _showErrorDialog(GeminiException e) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: _FuturisticErrorDialog(exception: e),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SelectionArea(
      child: Stack(
        children: [
          // ── 1 — Ana içerik ──────────────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBackRow(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPhotoCard(),
                        const SizedBox(height: 8),

                        Center(
                          child: Text(
                            'Nasıl Çözelim?',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF1A1A2E),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        _buildModeButtons(),
                        const SizedBox(height: 8),

                        Center(
                          child: Text(
                            'Hangisiyle çözmek istersin?',
                            style: GoogleFonts.inter(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        _buildModelWheel(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 2 — Çözüme Başla overlay ─────────────────────────────────────────
          if (_modelSelected && _selectedOption != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _modelSelected = false),
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    alignment: Alignment(0, 0.45),
                    child: GestureDetector(
                      onTap: () {}, // önce propagation'ı kes
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildSolveButton(),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Overlay açıkken geri butonu — overlay'in üstünde kalır ──────────
          if (_modelSelected && _selectedOption != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cyan),
                onPressed: () => Navigator.pop(context),
              ),
            ),

          // ── 3 — Aura yükleme overlay ────────────────────────────────────────
          if (_isLoading) const Positioned.fill(child: _AuraLoadingOverlay()),
        ],
      ),
      ),
    );
  }

  // ── Geri butonu ───────────────────────────────────────────────────────────────

  Widget _buildBackRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, bottom: 4),
      child: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cyan),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }

  // ── Fotoğraf kartı ────────────────────────────────────────────────────────────

  Widget _buildPhotoCard() {
    // Sabit 4:3 çerçeve — siyah border (radius 14) ve antiAlias clip
    return Stack(
      children: [
        Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black, width: 3),
          ),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.file(
              File(widget.imagePath),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFF0F2F5),
                child: const Icon(Icons.image_not_supported_outlined,
                    color: Colors.black26, size: 36),
              ),
            ),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: GestureDetector(
            onTap: _deleteAndGoBack,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30), width: 1),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  // ── 3 mod butonu — yan yana, seçilince büyür + parlar ───────────────────────

  Widget _buildModeButtons() {
    // Dış çerçeve yok — her buton kendi border'ıyla serbest duruyor.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _modes.asMap().entries.map((e) {
            final i    = e.key;
            final mode = e.value;
            final sel  = _selectedOption == mode.label;
            final c    = mode.color;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left:  i == 0 ? 0 : 6,
                  right: i == _modes.length - 1 ? 0 : 6,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedOption = mode.label),
                  child: AnimatedOpacity(
                    opacity: _selectedOption != null && !sel ? 0.45 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      decoration: BoxDecoration(
                        color: sel
                            ? c.withValues(alpha: 0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel
                              ? c.withValues(alpha: 0.75)
                              : Colors.black,
                          width: 1.5,
                        ),
                        boxShadow: sel
                            ? [BoxShadow(color: c.withValues(alpha: 0.30), blurRadius: 16, spreadRadius: 1)]
                            : [],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(mode.icon, color: c, size: 20),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              mode.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: Colors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
      ),
    );
  }

  // ── AI Model Grid — 2 sütun, 3 sol 3 sağ ────────────────────────────────────

  Widget _buildModelWheel() {
    final modeChosen = _selectedOption != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: modeChosen ? 1.0 : 0.35,
      child: IgnorePointer(
        ignoring: !modeChosen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 2.2,
            children: _models.asMap().entries.map((e) {
            final idx      = e.key;
            final model    = e.value;
            final sel      = idx == _centeredModelIdx;
            final c        = model.accentColor;
            final isActive = model.badge == localeService.tr('recommended');
            return GestureDetector(
              onTap: () {
                setState(() {
                  _centeredModelIdx = idx;
                  _modelSelected    = false;
                });
                _onSolveButtonTap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                decoration: BoxDecoration(
                  color: sel ? c.withValues(alpha: 0.10) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: sel ? c.withValues(alpha: 0.65) : Colors.black,
                    width: 1.5,
                  ),
                  boxShadow: sel
                      ? [BoxShadow(color: c.withValues(alpha: 0.22), blurRadius: 10)]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo + isim — aynı hizada
                    Row(
                      children: [
                        SizedBox(
                          width: 22, height: 22,
                          child: model.logo,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            model.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      model.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.black54,
                        fontSize: 8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: (isActive ? c : const Color(0xFF9CA3AF)).withValues(alpha: sel ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: (isActive ? c : const Color(0xFF9CA3AF)).withValues(alpha: sel ? 0.45 : 0.25),
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        model.badge,
                        style: GoogleFonts.inter(
                          color: Colors.black,
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Çözüme Başla butonu ───────────────────────────────────────────────────────

  Widget _buildSolveButton() {
    final model    = _models[_centeredModelIdx ?? 0];
    final isActive = model.name == 'QuAlsar' ||
        model.name == 'Gemini' ||
        model.name == 'Deepseek';
    final color    = model.accentColor;

    return GestureDetector(
      onTap: _onSolveButtonTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: [color.withValues(alpha: 0.72), color.withValues(alpha: 0.50)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isActive ? null : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? null
              : Border.all(color: color.withValues(alpha: 0.45)),
          boxShadow: isActive
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 0, offset: const Offset(0, 3))]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 18, color: isActive ? Colors.white : color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isActive ? 'Çözüme Başla' : '${model.name} — Yakında',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${model.name}  •  $_selectedOption',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.80), size: 20),
          ],
        ),
      ),
    );
  }

}


// ═══════════════════════════════════════════════════════════════════════════════
//  Aura yükleme animasyonu overlay
// ═══════════════════════════════════════════════════════════════════════════════

class _AuraLoadingOverlay extends StatefulWidget {
  const _AuraLoadingOverlay();

  @override
  State<_AuraLoadingOverlay> createState() => _AuraLoadingOverlayState();
}

class _AuraLoadingOverlayState extends State<_AuraLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        color: Colors.black.withValues(alpha: 0.68),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => CustomPaint(
                    painter: _AuraPainter(progress: _ctrl.value),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFFAA44FF)],
                ).createShader(b),
                child: const Text(
                  'Sorunuz Analiz Ediliyor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Yapay zeka sorunuzu inceliyor',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.38),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuraPainter extends CustomPainter {
  final double progress;
  const _AuraPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // 3 yayılan halka — farklı faz
    for (int i = 0; i < 3; i++) {
      final phase = (progress + i / 3.0) % 1.0;
      final radius = phase * maxR;
      final alpha = (1.0 - phase).clamp(0.0, 1.0);
      final isEven = i.isEven;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = (isEven
                  ? const Color(0xFF00E5FF)
                  : const Color(0xFFAA44FF))
              .withValues(alpha: alpha * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    // Merkez parlama
    canvas.drawCircle(
      center,
      26,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF00E5FF).withValues(alpha: 0.9),
            const Color(0xFF00E5FF).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 26)),
    );

    // İç beyaz nokta
    canvas.drawCircle(
      center,
      10,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    // Rotate eden ışın
    final angle = progress * 2 * math.pi;
    final beamPaint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center,
      Offset(
        center.dx + math.cos(angle) * 40,
        center.dy + math.sin(angle) * 40,
      ),
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(_AuraPainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Fütüristik hata dialog
// ═══════════════════════════════════════════════════════════════════════════════

class _FuturisticErrorDialog extends StatelessWidget {
  final GeminiException exception;
  const _FuturisticErrorDialog({required this.exception});

  IconData get _icon => switch (exception.type) {
        GeminiErrorType.noInternet    => Icons.wifi_off_rounded,
        GeminiErrorType.blurryImage   => Icons.blur_on_rounded,
        GeminiErrorType.quotaExceeded => Icons.hourglass_empty_rounded,
        GeminiErrorType.imageTooLarge => Icons.photo_size_select_large_rounded,
        GeminiErrorType.invalidKey    => Icons.vpn_key_off_rounded,
        GeminiErrorType.serverTimeout => Icons.timer_off_rounded,
        GeminiErrorType.unknown       => Icons.refresh_rounded,
      };

  Color get _color => switch (exception.type) {
        GeminiErrorType.noInternet    => const Color(0xFFEF4444),
        GeminiErrorType.blurryImage   => const Color(0xFFF59E0B),
        GeminiErrorType.quotaExceeded => const Color(0xFF8B5CF6),
        GeminiErrorType.imageTooLarge => const Color(0xFFEF4444),
        GeminiErrorType.invalidKey    => const Color(0xFF8B5CF6),
        GeminiErrorType.serverTimeout => const Color(0xFFF59E0B),
        GeminiErrorType.unknown       => AppColors.cyan,
      };

  @override
  Widget build(BuildContext context) {
    final c = _color;
    final maxH = MediaQuery.of(context).size.height * 0.75;
    final rawTrimmed = exception.rawError.length > 400
        ? '${exception.rawError.substring(0, 400)}…'
        : exception.rawError;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0818),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.withValues(alpha: 0.50), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: 0.18),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // İkon
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: c.withValues(alpha: 0.38)),
              boxShadow: [
                BoxShadow(
                  color: c.withValues(alpha: 0.14),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Icon(_icon, color: c, size: 32),
          ),
          const SizedBox(height: 18),
          // Mesaj
          Text(
            exception.userMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
          // Ham hata — debug için geçici
          if (exception.rawError.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                rawTrimmed,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Kapat butonu
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.withValues(alpha: 0.42)),
              ),
              alignment: Alignment.center,
              child: Text(
                'Tamam',
                style: TextStyle(
                  color: c,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
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

// ─── Sabit veri modeli ────────────────────────────────────────────────────────

class _ModeOption {
  final String   label;
  final String   subtitle;
  final IconData icon;
  final Color    color;
  const _ModeOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ─── Gemini 4-köşeli yıldız ikonu ────────────────────────────────────────────
// İçbükey kenarlı 4-köşeli kıvılcım — Google'un blue → purple → pink degradesiyle.
class _GeminiStarPainter extends CustomPainter {
  const _GeminiStarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = math.min(size.width, size.height) / 2;
    final k  = r * 0.30; // içbükeyliği belirleyen kontrol mesafesi

    final path = Path()
      ..moveTo(cx, cy - r)
      ..cubicTo(cx + k, cy - k, cx + k, cy - k, cx + r, cy)
      ..cubicTo(cx + k, cy + k, cx + k, cy + k, cx, cy + r)
      ..cubicTo(cx - k, cy + k, cx - k, cy + k, cx - r, cy)
      ..cubicTo(cx - k, cy - k, cx - k, cy - k, cx, cy - r)
      ..close();

    final paint = Paint()
      ..isAntiAlias = true
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF4796E3),
          Color(0xFF9168C0),
          Color(0xFFBB4287),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GeminiStarPainter oldDelegate) => false;
}
