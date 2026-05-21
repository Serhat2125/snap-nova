import '../services/error_logger.dart';
import '../services/runtime_translator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../main.dart' show localeService;
import '../services/analytics.dart';
import '../services/usage_quota.dart';
import '../widgets/adaptive_photo.dart';
import '../widgets/ai_model_card.dart';
import '../widgets/qualsar_loading_widget.dart';
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
  // 'numeric' | 'verbal' — hızlı sınıflandırıcıdan paralel gelir; null → henüz belirsiz
  String? _subjectKind;

  // ── 3 Çözüm modu ─────────────────────────────────────────────────────────────
  List<_ModeOption> get _modes => [
    _ModeOption(
      label: 'Basit Çöz'.tr(),
      subtitle: 'Basit ve pratik çözer'.tr(),
      icon: Icons.diamond_rounded,
      color: Color(0xFFF59E0B),
      // Parlayan karat: diamond + sağ üst köşesinde küçük sparkle.
      iconBuilder: (c) => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.diamond_rounded, color: c, size: 22),
          Positioned(
            top: -2,
            right: -2,
            child: Icon(Icons.auto_awesome_rounded,
                color: c.withValues(alpha: 0.85), size: 8),
          ),
        ],
      ),
    ),
    _ModeOption(
      label: 'Adım Adım Çöz'.tr(),
      subtitle: 'Detaylı adım adım çözer'.tr(),
      icon: Icons.pets_rounded,
      color: Color(0xFF3B82F6),
      // 4 panda ayak izi — aynı yatay hizada, izler yatay (yan yatık) baksın.
      // Transform.rotate ile paw 90° yatık → yürüyüş yönünde uzanmış izler.
      iconBuilder: (c) => SizedBox(
        width: 40,
        height: 22,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(4, (_) {
            return Transform.rotate(
              angle: math.pi / 2, // 90° → yatay
              child: Icon(Icons.pets_rounded, color: c, size: 9),
            );
          }),
        ),
      ),
    ),
    _ModeOption(
      label: 'AI Arkadaşım'.tr(),
      subtitle: 'Bir arkadaş gibi çözer'.tr(),
      icon: Icons.smart_toy_rounded,
      color: Color(0xFFEC4899),
      // Detaylı robot — anten + kafa + LED gözler + ağız.
      iconBuilder: (c) => SizedBox(
        width: 26,
        height: 26,
        child: CustomPaint(painter: _RobotPainter(c)),
      ),
    ),
  ];

  // ── AI modelleri ─────────────────────────────────────────────────────────────

  static final _models = [
    AiModel(
      name: 'QuAlsar',
      subtitle: 'Hızlı ve genel çözüm'.tr(),
      badge: localeService.tr('recommended'),
      accentColor: AppColors.cyan,
      logo: ShaderMask(
        shaderCallback: (b) => LinearGradient(
          colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(b),
        child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
      ),
    ),
    AiModel(
      name: 'ChatGPT',
      subtitle: 'Detaylı ve mantıklı çözüm'.tr(),
      badge: 'Yakında',
      accentColor: Color(0xFF10A37F),
      logo: Padding(
        padding: EdgeInsets.all(2),
        child: CustomPaint(painter: _OpenAiKnotPainter()),
      ),
    ),
    AiModel(
      name: 'Gemini',
      subtitle: 'Hızlı analiz ve alternatif çözüm'.tr(),
      badge: 'Aktif',
      accentColor: Color(0xFF4796E3),
      logo: Padding(
        padding: EdgeInsets.all(2),
        child: CustomPaint(painter: _GeminiStarPainter()),
      ),
    ),
    AiModel(
      name: 'Grok',
      subtitle: 'Anlık ve yaratıcı çözüm'.tr(),
      badge: 'Yakında',
      accentColor: Color(0xFF1D1D1D),
      logo: Padding(
        padding: EdgeInsets.all(2),
        child: CustomPaint(painter: _GrokXPainter()),
      ),
    ),
    AiModel(
      name: 'Deepseek',
      subtitle: 'Derin analiz ve akıl yürütme'.tr(),
      badge: 'Aktif',
      accentColor: Color(0xFF4B8BF5),
      logo: Padding(
        padding: EdgeInsets.all(1),
        child: CustomPaint(
            painter: _DeepseekWhalePainter(color: Color(0xFF4B8BF5))),
      ),
    ),
    AiModel(
      name: 'Claude',
      subtitle: 'Derin açıklama ve mantık yürütme'.tr(),
      badge: 'Yakında',
      accentColor: Color(0xFFD97706),
      logo: Padding(
        padding: EdgeInsets.all(2),
        child: CustomPaint(
            painter: _ClaudeBurstPainter(color: Color(0xFFD97706))),
      ),
    ),
  ];

  // ── Renk özelleştirme — ai_result_screen ile ortak prefs anahtarı ────────
  // Burada değiştirilen renkler çözüm ekranına da geçer (aynı prefs).
  static const _resultColorsKey = 'ai_result_colors_v1';
  static const _resultPalette = <Color>[
    Color(0xFFFFFFFF), Color(0xFF000000),
    Color(0xFFEF4444), Color(0xFFF97316), Color(0xFFF59E0B),
    Color(0xFF22C55E), Color(0xFF10B981), Color(0xFF14B8A6),
    Color(0xFF06B6D4), Color(0xFF0EA5E9), Color(0xFF3B82F6),
    Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFD946EF),
    Color(0xFFEC4899), Color(0xFFF43F5E),
    Color(0xFFFEF3C7), Color(0xFFFCE7F3), Color(0xFFE0F2FE),
    Color(0xFFDCFCE7), Color(0xFF1F2937),
  ];
  bool _showColorPicker = false;
  String _colorMode   = 'frame'; // frame | text
  String _colorTarget = 'bg';    // bg | photo | cards
  final ValueNotifier<Color?> _pageBgN    = ValueNotifier(null);
  final ValueNotifier<Color?> _photoBgN   = ValueNotifier(null);
  final ValueNotifier<Color?> _cardsBgN   = ValueNotifier(null);
  final ValueNotifier<Color?> _cardsTextN = ValueNotifier(null);

  // ── Yeniden kırpma (re-crop) ──────────────────────────────────────────────
  // Normalize edilmiş 0..1 koordinatlarda kullanıcının seçtiği alan.
  // Başlangıç: tüm görsel — kullanıcı dokunmazsa orijinal yollanır.
  final ValueNotifier<Rect> _cropRectN =
      ValueNotifier(const Rect.fromLTRB(0, 0, 1, 1));

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadResultColors();
  }

  @override
  void dispose() {
    // Loading sırasında back/leave olursa AI çağrısının sonucunu yutmak
    // için cancel flag set edelim. Stream HTTP isteği zaten arka planda
    // tamamlanır (cancel edemiyoruz) ama navigator.push çağrısı yapılmaz,
    // setState atılmaz, kullanıcı maliyet/UX sorunu yaşamaz.
    _cancelled = true;
    _slowConnTimer?.cancel();
    _scrollCtrl.dispose();
    _pageBgN.dispose();
    _photoBgN.dispose();
    _cardsBgN.dispose();
    _cardsTextN.dispose();
    _cropRectN.dispose();
    super.dispose();
  }

  // ─── Stream cancel + slow connection state ─────────────────────────────
  bool _cancelled = false;
  Timer? _slowConnTimer;
  bool _slowConnection = false;

  /// Kullanıcı kırpma çerçevesini daralttıysa yeni bir temp JPG yarat ve
  /// onun yolunu döndür; daraltılmamışsa orijinal yolu döndür.
  /// Hata durumunda (decode/IO) sessizce orijinal yola düş — analiz akışı
  /// kesilmesin.
  /// Eski recrop_*.jpg temp dosyalarını sil — birikim disk doluşturmasın.
  /// Sadece 1 günden eski olanları sil (aktif çözümler korunur).
  static Future<void> _cleanOldRecropTemps() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!await dir.exists()) return;
      final cutoff =
          DateTime.now().subtract(const Duration(hours: 24));
      await for (final ent in dir.list()) {
        if (ent is File &&
            ent.path.contains('recrop_') &&
            ent.path.endsWith('.jpg')) {
          try {
            final stat = await ent.stat();
            if (stat.modified.isBefore(cutoff)) {
              await ent.delete();
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[Solution] recrop cleanup fail: $e');
    }
  }

  Future<String> _applyCropIfNeeded() async {
    // Her _solve çağrısında arka planda eski temp dosyaları temizle.
    unawaited(_cleanOldRecropTemps());
    final r = _cropRectN.value;
    // Tam alan ya da neredeyse tam (1 px tolerans) → kırpma yok.
    const eps = 0.005;
    final isFull = r.left <= eps &&
        r.top <= eps &&
        r.right >= 1 - eps &&
        r.bottom >= 1 - eps;
    if (isFull) return widget.imagePath;
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      var im = img.decodeImage(bytes);
      if (im == null) return widget.imagePath;
      im = img.bakeOrientation(im);
      final sx = (r.left * im.width).round().clamp(0, im.width - 1);
      final sy = (r.top * im.height).round().clamp(0, im.height - 1);
      final sw =
          (r.width * im.width).round().clamp(1, im.width - sx);
      final sh =
          (r.height * im.height).round().clamp(1, im.height - sy);
      final cropped =
          img.copyCrop(im, x: sx, y: sy, width: sw, height: sh);
      final encoded = img.encodeJpg(cropped, quality: 92);
      final dir = await getTemporaryDirectory();
      final out = File(
          '${dir.path}/recrop_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(encoded);
      return out.path;
    } catch (_) {
      return widget.imagePath;
    }
  }

  Future<void> _loadResultColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_resultColorsKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;
      Color? read(String k) {
        final v = m[k];
        return v is num ? Color(v.toInt()) : null;
      }
      _pageBgN.value    = read('bg');
      _photoBgN.value   = read('photo');
      _cardsBgN.value   = read('cards');
      _cardsTextN.value = read('cardsText');
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'solution_screen'); }
  }

  Future<void> _saveResultColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = <String, int>{};
      void put(String k, Color? c) {
        if (c != null) m[k] = c.toARGB32();
      }
      put('bg',        _pageBgN.value);
      put('photo',     _photoBgN.value);
      put('cards',     _cardsBgN.value);
      put('cardsText', _cardsTextN.value);
      if (m.isEmpty) {
        await prefs.remove(_resultColorsKey);
      } else {
        await prefs.setString(_resultColorsKey, jsonEncode(m));
      }
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'solution_screen'); }
  }

  void _applyResultColor(String target, Color c) {
    if (_colorMode == 'text') {
      _cardsTextN.value = c;
    } else if (target == 'bg') {
      _pageBgN.value = c;
    } else if (target == 'photo') {
      _photoBgN.value = c;
    } else {
      _cardsBgN.value = c;
    }
    _saveResultColors();
  }

  void _resetResultColors() {
    _pageBgN.value    = null;
    _photoBgN.value   = null;
    _cardsBgN.value   = null;
    _cardsTextN.value = null;
    _saveResultColors();
  }

  // ── Geri git ─────────────────────────────────────────────────────────────────

  Future<void> _deleteAndGoBack() async {
    try {
      final f = File(widget.imagePath);
      if (await f.exists()) await f.delete();
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'solution_screen'); }
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
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: Duration(seconds: 2),
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
          content: Text('${model.name} ${localeService.tr('coming_soon_suffix')}'),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    // Quota kontrolü — fotoğraf çözümü = Solution kategorisi.
    // Free tier: 100/gün, 1500/ay. Aşılırsa snackbar + Analytics event.
    final quota = await UsageQuota.get(QuotaKind.solution);
    if (quota.isExhausted) {
      Analytics.logQuotaExhausted(QuotaKind.solution.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(quota.isDailyExhausted
              ? 'Günlük çözüm sınırına ulaştın (${quota.dailyLimit}). Yarın tekrar dene veya Premium\'a geç.'
              : 'Aylık çözüm sınırına ulaştın (${quota.monthlyLimit}). Ay başında sıfırlanır.'),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      return;
    }
    await UsageQuota.increment(QuotaKind.solution);
    Analytics.logEvent('solution_started', params: {
      'model': model.name,
      'option': _selectedOption ?? 'unknown',
    });

    _cancelled = false;
    _slowConnection = false;
    setState(() {
      _isLoading = true;
      _subjectKind = null;
    });
    // 5sn'i geçerse "Bağlantı kontrol ediliyor…" göster
    _slowConnTimer?.cancel();
    _slowConnTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoading && !_cancelled) {
        setState(() => _slowConnection = true);
      }
    });

    // Not: Daha önce `classifySubjectQuick` paralel çağrısı yapılıyordu —
    // her çözüm için 2 Gemini API isteği (sınıflandırıcı + çözüm) oluyordu
    // ve free-tier kotayı çabuk doldurup "kota aşıldı" hatası veriyordu.
    // Sınıflandırıcı yalnızca hangi loader animasyonunun (numeric/verbal)
    // gösterileceğini seçiyordu (kozmetik). Asıl çözümü etkilemediği için
    // kapatıldı — tek API isteğiyle doğrudan çözüme geçilir, varsayılan
    // sayısal loader çalışır.

    // Sonuç değişkenleri finally dışına taşındı — finally her zaman çalışır
    String? result;
    GeminiException? geminiError;

    // Kullanıcı kırpma çerçevesini daraltmışsa görseli o alana göre yeniden
    // kırpıp temp dosya yarat; AI'a yalnızca seçilmiş bölge gider.
    final pathForAI = await _applyCropIfNeeded();

    try {
      if (model.name == 'Deepseek') {
        result = await GeminiService.analyzeImageWithDeepseek(
          pathForAI,
          _selectedOption!,
          isMulti: widget.isMultiCapture,
        );
      } else {
        result = await GeminiService.analyzeImage(
          pathForAI,
          _selectedOption!,
          isMulti: widget.isMultiCapture,
        );
      }
    } on GeminiException catch (e) {
      geminiError = e;
    } on SocketException {
      geminiError = GeminiException.noInternet();
    } on TimeoutException {
      geminiError = GeminiException.serverTimeout();
    } on HandshakeException {
      // TLS handshake — proxy/cert sorunu, internet yok kabul et.
      geminiError = GeminiException.noInternet();
    } catch (e) {
      geminiError = GeminiException.unknown(e.toString());
    } finally {
      // _isLoading'i her koşulda sıfırla — UI asla kilitlenmesin
      _slowConnTimer?.cancel();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _slowConnection = false;
        });
      }
    }

    if (!mounted || _cancelled) return;

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
              begin: Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
          transitionDuration: Duration(milliseconds: 380),
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
        child: _FuturisticErrorDialog(
          exception: e,
          // Network/timeout/empty/unknown hatalarında tek tıkla yeniden dene.
          // Quota ve safety hatalarında retry mantıklı değil (gizlenir).
          onRetry: () => _solve(),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color?>(
      valueListenable: _pageBgN,
      builder: (_, pageBg, body) => Scaffold(
        backgroundColor: pageBg ?? AppPalette.bg(context),
        body: body,
      ),
      child: SelectionArea(
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
                    physics: BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPhotoCard(),
                        SizedBox(height: 22),

                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 8),
                            decoration: BoxDecoration(
            color: AppPalette.card(context),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              'Nasıl Çözelim?',
                              style: GoogleFonts.inter(
                                color: AppPalette.textPrimary(context),
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 14),

                        _buildModeButtons(),
                        SizedBox(height: 22),

                        Center(
                          child: Text(
                            'Hangisiyle çözmek istersin?',
                            style: GoogleFonts.inter(
                              color: AppPalette.textPrimary(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        SizedBox(height: 16),

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
                icon: Icon(Icons.arrow_back_rounded, color: AppColors.cyan),
                onPressed: () => Navigator.pop(context),
              ),
            ),

          // ── 3 — Yükleme overlay (birleşik standart loader) ───────────────
          // Tüm modüller (özet/çözüm/test) aynı görsel kimliği kullanır;
          // QuAlsarLoadingWidget içte stages + mavi tik + motivasyon yönetir.
          // Konu fotoğraftan gelmediği için topic=''; "Sorunuz analiz
          // ediliyor" fallback'ine düşer.
          if (_isLoading)
            Positioned.fill(
              child: Stack(
                children: [
                  QuAlsarLoadingWidget(
                    type: QuAlsarLoadingType.solution,
                    domain: _subjectKind == 'verbal'
                        ? SubjectDomain.verbal
                        : SubjectDomain.numeric,
                  ),
                  if (_slowConnection)
                    Positioned(
                      bottom: 80,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFFFB200)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Bağlantı yavaş, kontrol ediliyor…'.tr(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  // ── Üst bar: geri + "Renk Seç" pill (en sağda, diğer sayfalardaki ile aynı)
  Widget _buildBackRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 12, bottom: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: AppColors.cyan),
            onPressed: () => Navigator.pop(context),
          ),
          Spacer(),
          GestureDetector(
            onTap: () =>
                setState(() => _showColorPicker = !_showColorPicker),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF6A00),
                    Color(0xFFDB2777),
                    Color(0xFF7C3AED),
                    Color(0xFF2563EB),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showColorPicker
                        ? Icons.close_rounded
                        : Icons.palette_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  SizedBox(width: 5),
                  Text(
                    _showColorPicker
                        ? 'Kapat'.tr()
                        : 'Renk Seç'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fotoğraf kartı ────────────────────────────────────────────────────────────

  Widget _buildPhotoCard() {
    // Çerçeve artık sabit 4:3 DEĞİL — fotoğrafın gerçek en-boy oranına göre
    // uzar/kısalır, böylece dikey/yatay her görsel TAM gözükür (BoxFit.contain).
    // En fazla ekranın %55'i kadar yer kaplar.
    // Üzerinde ayarlanabilir bir kırpma çerçevesi var; "Alanı Belirle" altyazısı
    // kullanıcıya kenarlardan tutup daraltıp/genişletebileceğini hatırlatır.
    return Column(
      children: [
        // Talimat şeridi: "Alanı Belirle"
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.crop_free_rounded,
                  size: 14, color: AppColors.cyan),
              SizedBox(width: 6),
              Text(
                'Alanı Belirle'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(width: 6),
              Text(
                'Kenarlardan tutarak daralt'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        Stack(
          children: [
            ValueListenableBuilder<Color?>(
              valueListenable: _photoBgN,
              builder: (_, photoBg, __) => AdaptivePhoto(
                path: widget.imagePath,
                maxHeightFactor: 0.55,
                borderRadius: 14,
                border: Border.all(color: AppPalette.textPrimary(context), width: 3),
                background: photoBg ?? AppPalette.bg(context),
                overlay: _PhotoCropOverlay(rectN: _cropRectN),
              ),
            ),
            // Sağ üst: kapat (X) — fotoğrafın içinde
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
                  child: Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
            // Renk paneli — palette butonuna basıldığında doğrudan fotoğrafın
            // ÜZERİNE overlay olarak gelir.
            if (_showColorPicker)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _buildResultColorPanel(),
                ),
              ),
          ],
        ),
      ],
    );
  }


  // ── 3 mod butonu — her biri kendi oval beyaz çerçevesinde ─────────────────
  //   Çerçeve hafif yuvarlak (10 px radius). İç tam beyaz; dış sayfa zemini
  //   biraz daha soluk beyaz. Her kart: yuvarlak ikon + başlık + alt-açıklama.
  Widget _buildModeButtons() {
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _modes.map((mode) {
          final sel = _selectedOption == mode.label;
          final c = mode.color;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedOption = mode.label),
              behavior: HitTestBehavior.opaque,
              child: AnimatedOpacity(
                opacity: _selectedOption != null && !sel ? 0.45 : 1.0,
                duration: Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Saf beyaz zemin
                        color: AppPalette.card(context),
                        border: Border.all(
                          color: sel ? c : Color(0xFFD0D0D0),
                          width: sel ? 2.4 : 1.0,
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color: c.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  spreadRadius: 2,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.04),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                      ),
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            mode.iconBuilder?.call(c) ??
                                Icon(mode.icon, color: c, size: 22),
                            SizedBox(height: 3),
                            Text(
                              mode.label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: sel ? c : Colors.black,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              mode.subtitle,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: Colors.black
                                    .withValues(alpha: 0.55),
                                fontSize: 8.2,
                                fontWeight: FontWeight.w500,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
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

  // ══════ Renk seçim paneli — fotoğraf üzerinde overlay ═══════════════════
  Widget _buildResultColorPanel() {
    final orange = Color(0xFFFF6A00);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.textPrimary(context), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              SizedBox(width: 6),
              Text('Renk'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
              SizedBox(width: 10),
              Expanded(child: _resultModeToggle(orange)),
              SizedBox(width: 8),
              GestureDetector(
                onTap: _resetResultColors,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.cardMuted(context),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text('Sıfırla'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.black54)),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _resultTargetToggle(orange),
          SizedBox(height: 6),
          Text(
            'Renge bas ya da sürükleyip istediğin yere bırak.'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
                height: 1.3),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _resultPalette.length,
              itemBuilder: (_, i) =>
                  _resultDraggableColor(_resultPalette[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultModeToggle(Color orange) {
    Widget box(String id, IconData icon, String label) {
      final active = _colorMode == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorMode = id),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 140),
            padding:
                const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: active
                  ? orange.withValues(alpha: 0.12)
                  : Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? orange : Colors.black,
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 13, color: active ? orange : Colors.black),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? orange : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        box('text', Icons.text_fields_rounded, 'Yazı'.tr()),
        SizedBox(width: 8),
        box('frame', Icons.crop_square_rounded, 'Çerçeve'.tr()),
      ],
    );
  }

  Widget _resultTargetToggle(Color orange) {
    Widget chip(String id, String label) {
      final active = _colorTarget == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _colorTarget = id),
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? orange.withValues(alpha: 0.12)
                  : Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? orange : Colors.black12,
                width: active ? 1.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: active ? orange : Colors.black),
            ),
          ),
        ),
      );
    }

    // 'photo' hedefi kaldırıldı — bu sayfada fotoğrafa renk uygulanmıyor.
    return Row(
      children: [
        chip('bg', 'Arka plan'.tr()),
        SizedBox(width: 6),
        chip('cards', 'Kartlar'.tr()),
      ],
    );
  }

  Widget _resultDraggableColor(Color c) {
    return Draggable<Color>(
      data: c,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _resultDot(c)),
      child: GestureDetector(
        onTap: () => _applyResultColor(_colorTarget, c),
        child: _resultDot(c),
      ),
    );
  }

  Widget _resultDot(Color c) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border(context), width: 1),
      ),
    );
  }

  // ── AI Model Grid — 2 sütun, 3 sol 3 sağ ────────────────────────────────────

  Widget _buildModelWheel() {
    final modeChosen = _selectedOption != null;
    return AnimatedOpacity(
      duration: Duration(milliseconds: 250),
      opacity: modeChosen ? 1.0 : 0.35,
      child: IgnorePointer(
        ignoring: !modeChosen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GridView.count(
            // 3 sütun — yatayda 3 altıgen sığar; yaklaşık %50 küçük.
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            // Daha da daraltıldı — yatay-dominant, dikey kompakt.
            childAspectRatio: 1.35,
            children: _models.asMap().entries.map((e) {
              final idx      = e.key;
              final model    = e.value;
              final sel      = idx == _centeredModelIdx;
              final c        = model.accentColor;
              final isActive = model.badge == localeService.tr('recommended');
              final fillColor = sel ? c.withValues(alpha: 0.10) : Colors.white;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _centeredModelIdx = idx;
                    _modelSelected    = false;
                  });
                  _onSolveButtonTap();
                },
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: sel
                        ? [BoxShadow(
                            color: c.withValues(alpha: 0.25),
                            blurRadius: 10,
                            spreadRadius: 0.5)]
                        : [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: Offset(0, 1))],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: model.logo,
                      ),
                      SizedBox(height: 2),
                      Text(
                        model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: AppPalette.textPrimary(context),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        model.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: AppPalette.textSecondary(context),
                          fontSize: 7,
                          fontWeight: FontWeight.w500,
                          height: 1.05,
                        ),
                      ),
                      SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: (isActive ? c : Color(0xFF9CA3AF))
                              .withValues(alpha: sel ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: (isActive ? c : Color(0xFF9CA3AF))
                                .withValues(alpha: sel ? 0.50 : 0.30),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          model.badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppPalette.textPrimary(context),
                            fontSize: 6.5,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
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
        duration: Duration(milliseconds: 260),
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
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 0, offset: Offset(0, 3))]
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
            SizedBox(width: 12),
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
        vsync: this, duration: Duration(milliseconds: 1600))
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
              SizedBox(height: 28),
              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFFAA44FF)],
                ).createShader(b),
                child: Text(
                  'Sorunuz Analiz Ediliyor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              SizedBox(height: 8),
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
                  ? Color(0xFF00E5FF)
                  : Color(0xFFAA44FF))
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
            Color(0xFF00E5FF).withValues(alpha: 0.9),
            Color(0xFF00E5FF).withValues(alpha: 0.0),
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
  /// Retry mümkün hata türleri için callback. null verilirse retry butonu gizli.
  final VoidCallback? onRetry;
  const _FuturisticErrorDialog({required this.exception, this.onRetry});

  /// Hata tipi retry yapılabilir mi? (network, timeout, empty response, vs.)
  bool get _canRetry =>
      exception.type == GeminiErrorType.noInternet ||
      exception.type == GeminiErrorType.serverTimeout ||
      exception.type == GeminiErrorType.emptyResponse ||
      exception.type == GeminiErrorType.unknown;

  IconData get _icon => switch (exception.type) {
        GeminiErrorType.noInternet    => Icons.wifi_off_rounded,
        GeminiErrorType.blurryImage   => Icons.blur_on_rounded,
        GeminiErrorType.emptyResponse => Icons.refresh_rounded,
        GeminiErrorType.safetyBlocked => Icons.shield_outlined,
        GeminiErrorType.quotaExceeded => Icons.hourglass_empty_rounded,
        GeminiErrorType.imageTooLarge => Icons.photo_size_select_large_rounded,
        GeminiErrorType.invalidKey    => Icons.vpn_key_off_rounded,
        GeminiErrorType.serverTimeout => Icons.timer_off_rounded,
        GeminiErrorType.unknown       => Icons.refresh_rounded,
      };

  Color get _color => switch (exception.type) {
        GeminiErrorType.noInternet    => Color(0xFFEF4444),
        GeminiErrorType.blurryImage   => Color(0xFFF59E0B),
        GeminiErrorType.emptyResponse => Color(0xFFF59E0B),
        GeminiErrorType.safetyBlocked => Color(0xFFEF4444),
        GeminiErrorType.quotaExceeded => Color(0xFF8B5CF6),
        GeminiErrorType.imageTooLarge => Color(0xFFEF4444),
        GeminiErrorType.invalidKey    => Color(0xFF8B5CF6),
        GeminiErrorType.serverTimeout => Color(0xFFF59E0B),
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
        color: Color(0xFF0A0818),
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
          SizedBox(height: 18),
          // Mesaj
          Text(
            exception.userMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
          // Ham hata — debug için geçici
          if (exception.rawError.isNotEmpty) ...[
            SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppPalette.textSecondary(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                rawTrimmed,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          SizedBox(height: 24),
          // Retry + Kapat butonları (retry sadece uygun hata türlerinde)
          if (_canRetry && onRetry != null) ...[
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                onRetry!();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [c, c.withValues(alpha: 0.78)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Tekrar Dene',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
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
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  /// Opsiyonel custom widget — null ise [icon] kullanılır.
  /// Color parametresi mode renginde geçer (icon tint için).
  final Widget Function(Color color)? iconBuilder;
  const _ModeOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.iconBuilder,
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
      ..shader = LinearGradient(
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

// ─── OpenAI / ChatGPT — siyah hexafoil knot (6-fold rotational symmetry) ────
class _OpenAiKnotPainter extends CustomPainter {
  const _OpenAiKnotPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    // 3 örtüşen oval — 0°, 60°, 120° dönmeyle 6-fold simetri oluşturur.
    for (int i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(i * math.pi / 3);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: size.width * 0.78,
        height: size.height * 0.36,
      );
      canvas.drawOval(rect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _OpenAiKnotPainter oldDelegate) => false;
}

// ─── Grok / xAI — sert-italik X ─────────────────────────────────────────────
class _GrokXPainter extends CustomPainter {
  const _GrokXPainter();
  Color get color => Colors.black;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18
      ..strokeCap = StrokeCap.square;
    final m = size.width * 0.16;
    // Hafif italik için üst-noktalar sağa kayık
    final lean = size.width * 0.05;
    canvas.drawLine(
      Offset(m + lean, m),
      Offset(size.width - m - lean, size.height - m),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - m + lean, m),
      Offset(m - lean, size.height - m),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GrokXPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─── Deepseek — stilize edilmiş yunus/balina silüeti ────────────────────────
class _DeepseekWhalePainter extends CustomPainter {
  final Color color;
  const _DeepseekWhalePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.fill;

    // Gövde: curved teardrop facing right
    final body = Path()
      ..moveTo(w * 0.08, h * 0.56)
      ..cubicTo(
          w * 0.10, h * 0.35,
          w * 0.40, h * 0.28,
          w * 0.62, h * 0.36)
      ..cubicTo(
          w * 0.85, h * 0.42,
          w * 0.95, h * 0.50,
          w * 0.96, h * 0.58)
      // Kuyruk üst kanat
      ..lineTo(w * 0.86, h * 0.40)
      ..lineTo(w * 0.94, h * 0.62)
      // Kuyruk alt kanat
      ..lineTo(w * 0.86, h * 0.78)
      ..lineTo(w * 0.92, h * 0.62)
      ..cubicTo(
          w * 0.78, h * 0.78,
          w * 0.40, h * 0.82,
          w * 0.18, h * 0.74)
      ..cubicTo(
          w * 0.06, h * 0.68,
          w * 0.04, h * 0.62,
          w * 0.08, h * 0.56)
      ..close();
    canvas.drawPath(body, paint);

    // Göz noktası (beyaz)
    canvas.drawCircle(
      Offset(w * 0.26, h * 0.50),
      w * 0.045,
      Paint()..color = Colors.white..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _DeepseekWhalePainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─── Claude / Anthropic — turuncu sunburst (4-noktalı asterisk) ────────────
class _ClaudeBurstPainter extends CustomPainter {
  final Color color;
  const _ClaudeBurstPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.42;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.fill;

    // 4 sivri uçlu yıldız (sunburst): her ucu ince elmas
    for (int i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final path = Path()
        ..moveTo(0, -r)
        ..lineTo(r * 0.18, 0)
        ..lineTo(0, r * 0.18)
        ..lineTo(-r * 0.18, 0)
        ..close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }

    // Diyagonal ince ışınlar (45°, 135°, ...)
    final raysPaint = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final angle = math.pi / 4 + i * math.pi / 2;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + r * 0.65 * math.cos(angle),
            cy + r * 0.65 * math.sin(angle)),
        raysPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClaudeBurstPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─── Detaylı Robot ikonu (CustomPainter) ──────────────────────────────────────
// Anten (top) + ışıklı bulb + rounded kafa + 2 LED göz + ağız.
// 26x26 alanda mükemmel oturur, vector — her boyuta scale olur.
class _RobotPainter extends CustomPainter {
  final Color color;
  const _RobotPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Antenna çizgisi (top center)
    canvas.drawLine(
      Offset(w / 2, h * 0.16),
      Offset(w / 2, h * 0.27),
      stroke,
    );
    // Antenna bulb — küçük dolu daire + dış glow halkası (parlama)
    final glow = Paint()
      ..color = color.withValues(alpha: 0.30)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(w / 2, h * 0.12), w * 0.12, glow);
    canvas.drawCircle(Offset(w / 2, h * 0.12), w * 0.07, fill);

    // Kafa — rounded rectangle stroke
    final headRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.16, h * 0.30, w * 0.84, h * 0.84),
      Radius.circular(w * 0.16),
    );
    canvas.drawRRect(headRect, stroke);

    // 2 LED göz — büyük dolu daireler (ışık ver)
    canvas.drawCircle(Offset(w * 0.37, h * 0.52), w * 0.085, fill);
    canvas.drawCircle(Offset(w * 0.63, h * 0.52), w * 0.085, fill);

    // Göz parıltısı (highlight) — sağ üst köşelerde küçük beyaz nokta
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.80)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(Offset(w * 0.395, h * 0.50), w * 0.022, highlight);
    canvas.drawCircle(Offset(w * 0.655, h * 0.50), w * 0.022, highlight);

    // Ağız — yatay küçük çizgi (smile/neutral)
    canvas.drawLine(
      Offset(w * 0.40, h * 0.72),
      Offset(w * 0.60, h * 0.72),
      stroke,
    );

    // Kulaklar — yan taraftan minik oval çıkıntılar (anten soketleri)
    final earL = Rect.fromCenter(
      center: Offset(w * 0.14, h * 0.55),
      width: w * 0.07,
      height: h * 0.16,
    );
    final earR = Rect.fromCenter(
      center: Offset(w * 0.86, h * 0.55),
      width: w * 0.07,
      height: h * 0.16,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(earL, Radius.circular(w * 0.04)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(earR, Radius.circular(w * 0.04)),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RobotPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  _PhotoCropOverlay — Fotoğraf üzerinde ayarlanabilir kırpma çerçevesi.
//  • Çerçevenin DIŞI hafif karartılır (donut clipper); içi tam görünür.
//  • 4 kenarda dokunma kolu — yatay/dikey ok ikonu ile.
//  • Çerçeve değiştikçe parent'a normalize edilmiş Rect (0..1) yollar.
//  • Başlangıç: tam alan; kullanıcı daraltıp/genişletebilir.
// ═══════════════════════════════════════════════════════════════════════════════
class _PhotoCropOverlay extends StatefulWidget {
  final ValueNotifier<Rect> rectN;
  const _PhotoCropOverlay({required this.rectN});

  @override
  State<_PhotoCropOverlay> createState() => _PhotoCropOverlayState();
}

class _PhotoCropOverlayState extends State<_PhotoCropOverlay> {
  // Çerçeve pixel-cinsinden — LayoutBuilder size'ı baz alır.
  Rect? _frame;
  Size? _lastSize;

  // Min boyut (piksel cinsinden) — çok küçülmesin.
  static const double _minW = 60;
  static const double _minH = 60;

  Rect _initial(Size s) =>
      Rect.fromLTRB(0, 0, s.width, s.height);

  Rect _currentFrame(Size s) {
    if (_frame == null || _lastSize != s) {
      // Notifier'da kayıtlı normalize rect → pixel'e çevir.
      final n = widget.rectN.value;
      _frame = Rect.fromLTRB(
        n.left * s.width,
        n.top * s.height,
        n.right * s.width,
        n.bottom * s.height,
      );
      _lastSize = s;
    }
    return _frame!;
  }

  void _commit(Rect f, Size s) {
    setState(() {
      _frame = f;
      _lastSize = s;
    });
    widget.rectN.value = Rect.fromLTRB(
      (f.left / s.width).clamp(0.0, 1.0),
      (f.top / s.height).clamp(0.0, 1.0),
      (f.right / s.width).clamp(0.0, 1.0),
      (f.bottom / s.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        // İlk çağrıda full alan
        if (_frame == null) {
          _frame = _initial(size);
          _lastSize = size;
        }
        final frame = _currentFrame(size);
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Dış karartma — çerçeve içi şeffaf
            IgnorePointer(
              child: ClipPath(
                clipper: _CropDonutClipper(frame: frame, radius: 6),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.32),
                ),
              ),
            ),
            // Cyan çerçeve kenarlığı
            Positioned(
              left: frame.left,
              top: frame.top,
              width: frame.width,
              height: frame.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.85),
                      width: 1.6,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            // Köşe parantezleri (CustomPaint)
            Positioned(
              left: frame.left,
              top: frame.top,
              width: frame.width,
              height: frame.height,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CropBracketPainter(),
                ),
              ),
            ),
            // 4 kenar kolu
            _edge(
              frame,
              size,
              Axis.horizontal,
              isStart: true,
            ),
            _edge(
              frame,
              size,
              Axis.horizontal,
              isStart: false,
            ),
            _edge(
              frame,
              size,
              Axis.vertical,
              isStart: true,
            ),
            _edge(
              frame,
              size,
              Axis.vertical,
              isStart: false,
            ),
          ],
        );
      },
    );
  }

  // axis = horizontal → sol/sağ; vertical → üst/alt.
  Widget _edge(Rect f, Size s, Axis axis,
      {required bool isStart}) {
    const tw = 44.0;
    const th = 36.0;
    final isHorizontal = axis == Axis.horizontal;
    final left = isHorizontal
        ? (isStart ? f.left - tw / 2 : f.right - tw / 2)
        : f.center.dx - th / 2;
    final top = isHorizontal
        ? f.center.dy - th / 2
        : (isStart ? f.top - tw / 2 : f.bottom - tw / 2);
    final w = isHorizontal ? tw : th;
    final h = isHorizontal ? th : tw;
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          var nf = f;
          if (axis == Axis.horizontal) {
            if (isStart) {
              final newLeft = (f.left + d.delta.dx)
                  .clamp(0.0, f.right - _minW);
              nf = Rect.fromLTRB(newLeft, f.top, f.right, f.bottom);
            } else {
              final newRight = (f.right + d.delta.dx)
                  .clamp(f.left + _minW, s.width);
              nf = Rect.fromLTRB(f.left, f.top, newRight, f.bottom);
            }
          } else {
            if (isStart) {
              final newTop = (f.top + d.delta.dy)
                  .clamp(0.0, f.bottom - _minH);
              nf = Rect.fromLTRB(f.left, newTop, f.right, f.bottom);
            } else {
              final newBottom = (f.bottom + d.delta.dy)
                  .clamp(f.top + _minH, s.height);
              nf = Rect.fromLTRB(f.left, f.top, f.right, newBottom);
            }
          }
          _commit(nf, s);
        },
        child: Center(
          child: Container(
            padding: isHorizontal
                ? const EdgeInsets.symmetric(horizontal: 4, vertical: 3)
                : const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AppColors.cyan.withValues(alpha: 0.7),
                width: 1.1,
              ),
            ),
            child: Icon(
              isHorizontal
                  ? Icons.swap_horiz_rounded
                  : Icons.swap_vert_rounded,
              color: AppColors.cyan,
              size: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _CropDonutClipper extends CustomClipper<Path> {
  final Rect frame;
  final double radius;
  const _CropDonutClipper({required this.frame, required this.radius});

  @override
  Path getClip(Size size) => Path()
    ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
    ..addRRect(RRect.fromRectAndRadius(frame, Radius.circular(radius)))
    ..fillType = PathFillType.evenOdd;

  @override
  bool shouldReclip(covariant _CropDonutClipper old) =>
      old.frame != frame || old.radius != radius;
}

class _CropBracketPainter extends CustomPainter {
  const _CropBracketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.cyan
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const l = 14.0;
    final w = size.width;
    final h = size.height;
    // Sol üst
    canvas.drawLine(Offset(0, 0), Offset(l, 0), p);
    canvas.drawLine(Offset(0, 0), Offset(0, l), p);
    // Sağ üst
    canvas.drawLine(Offset(w - l, 0), Offset(w, 0), p);
    canvas.drawLine(Offset(w, 0), Offset(w, l), p);
    // Sol alt
    canvas.drawLine(Offset(0, h - l), Offset(0, h), p);
    canvas.drawLine(Offset(0, h), Offset(l, h), p);
    // Sağ alt
    canvas.drawLine(Offset(w - l, h), Offset(w, h), p);
    canvas.drawLine(Offset(w, h - l), Offset(w, h), p);
  }

  @override
  bool shouldRepaint(covariant _CropBracketPainter old) => false;
}
