import '../services/error_logger.dart';
import '../services/runtime_translator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jovial_svg/jovial_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../main.dart' show localeService;
import '../services/analytics.dart';
import '../services/app_settings_service.dart';
import '../services/usage_quota.dart';
import '../widgets/adaptive_photo.dart';
import '../widgets/ai_model_card.dart';
import '../widgets/qualsar_loading_widget.dart';
import '../services/gemini_service.dart';
// Sadece AiProvider enum'u — bu dosyadaki yerel `AiModel` ile çakışmasın diye
// `show` ile sınırlı import.
import '../services/ai_provider_service.dart' show AiProvider;
import 'ai_result_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Marka logoları — orijinal vektör çizimleri (24×24 viewBox, Simple Icons
//  path verisi). jovial_svg ile bir kez parse edilir, cache'ten servis edilir.
// ═══════════════════════════════════════════════════════════════════════════════

const String _openAiSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#FFFFFF" d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.8956zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"/></svg>';

// Gemini yıldızı — orijinal mavi→mor degrade.
const String _geminiSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<defs><linearGradient id="gg" x1="0" y1="24" x2="24" y2="0" gradientUnits="userSpaceOnUse">'
    '<stop offset="0" stop-color="#4285F4"/><stop offset="0.55" stop-color="#9B72CB"/><stop offset="1" stop-color="#D96570"/>'
    '</linearGradient></defs>'
    '<path fill="url(#gg)" d="M11.04 19.32Q12 21.51 12 24q0-2.49.93-4.68.96-2.19 2.58-3.81t3.81-2.55Q21.51 12 24 12q-2.49 0-4.68-.93a12.3 12.3 0 0 1-3.81-2.58 12.3 12.3 0 0 1-2.58-3.81Q12 2.49 12 0q0 2.49-.96 4.68-.93 2.19-2.55 3.81a12.3 12.3 0 0 1-3.81 2.58Q2.49 12 0 12q2.49 0 4.68.96 2.19.93 3.81 2.55t2.55 3.81"/></svg>';

const String _grokSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#FFFFFF" d="m3.005 8.858 8.783 12.544h3.904L6.908 8.858zM6.905 15.825 3 21.402h3.907l1.951-2.788zM16.585 2l-6.75 9.64 1.953 2.79L20.492 2zM17.292 7.965v13.437h3.2V3.395z"/></svg>';

const String _deepseekSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#4D6BFE" d="M23.748 4.651c-.254-.124-.364.113-.512.233-.051.04-.094.09-.137.137-.372.397-.806.657-1.373.626-.829-.046-1.537.214-2.163.848-.133-.782-.575-1.248-1.247-1.548-.352-.155-.708-.311-.955-.65-.172-.24-.219-.509-.305-.774-.055-.16-.11-.323-.293-.35-.2-.031-.278.136-.356.276-.313.572-.434 1.202-.422 1.84.027 1.436.633 2.58 1.838 3.393.137.094.172.187.129.323-.082.28-.18.553-.266.833-.055.179-.137.218-.328.14a5.5 5.5 0 0 1-1.737-1.179c-.857-.828-1.631-1.743-2.597-2.46a12 12 0 0 0-.689-.47c-.985-.957.13-1.743.387-1.836.27-.098.094-.433-.778-.428-.872.003-1.67.295-2.687.685a3 3 0 0 1-.465.136 9.6 9.6 0 0 0-2.883-.101c-1.885.21-3.39 1.1-4.497 2.622C.082 8.776-.231 10.854.152 13.02c.403 2.284 1.568 4.175 3.36 5.653 1.857 1.533 3.997 2.284 6.438 2.14 1.482-.085 3.132-.284 4.994-1.86.47.234.962.328 1.78.398.629.058 1.235-.031 1.705-.129.735-.155.684-.836.418-.961-2.155-1.004-1.682-.595-2.112-.926 1.095-1.295 2.768-3.598 3.284-6.733.05-.346.115-.834.108-1.114-.004-.171.035-.238.23-.257a4.2 4.2 0 0 0 1.545-.475c1.397-.763 1.96-2.016 2.093-3.517.02-.23-.004-.467-.247-.588M11.58 18.168c-2.088-1.642-3.101-2.183-3.52-2.16-.39.024-.32.472-.234.763.09.288.207.487.371.74.114.167.192.416-.113.603-.673.416-1.842-.14-1.897-.168-1.361-.801-2.5-1.86-3.301-3.306-.775-1.393-1.225-2.888-1.299-4.482-.02-.385.094-.522.477-.592a4.7 4.7 0 0 1 1.53-.038c2.131.311 3.946 1.264 5.467 2.774.868.86 1.525 1.887 2.202 2.89.72 1.066 1.494 2.082 2.48 2.915.348.291.626.513.892.677-.802.09-2.14.109-3.055-.615zm1.001-6.44a.306.306 0 0 1 .415-.287.3.3 0 0 1 .113.074.3.3 0 0 1 .086.214c0 .17-.136.307-.308.307a.303.303 0 0 1-.306-.307m3.11 1.596c-.2.081-.4.151-.591.16a1.25 1.25 0 0 1-.798-.254c-.274-.23-.47-.358-.551-.758a1.7 1.7 0 0 1 .015-.588c.07-.327-.007-.537-.238-.727-.188-.156-.426-.199-.689-.199a.6.6 0 0 1-.254-.078.253.253 0 0 1-.114-.358 1 1 0 0 1 .192-.21c.356-.202.767-.136 1.146.016.352.144.618.408 1.001.782.392.451.462.576.685.915.176.264.336.536.446.848.066.194-.02.353-.25.45"/></svg>';

const String _claudeSvg =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#D97757" d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"/></svg>';

// Parse edilen ScalableImage cache'i — her SVG bir kez derlenir.
final Map<String, ScalableImage> _brandSiCache = {};

/// Marka glifini gerçek uygulama ikonu görünümünde render eder:
/// kendi marka zemini üzerinde yuvarlatılmış kare rozet.
/// Açık zeminli rozetlere (beyaz/krem) ince gri kenarlık eklenir.
Widget _brandLogo(String key, String svg,
    {required Color bg, bool lightBg = false, double pad = 4}) {
  final si = _brandSiCache.putIfAbsent(
      key, () => ScalableImage.fromSvgString(svg));
  return Container(
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(7),
      border: lightBg
          ? Border.all(color: const Color(0xFFE5E7EB), width: 0.8)
          : null,
    ),
    padding: EdgeInsets.all(pad),
    child: ScalableImageWidget(si: si),
  );
}

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
      // Uygulamanın kendi orijinal logosu — diğer rozetlerle aynı köşe.
      logo: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset('assets/app_icon.png', fit: BoxFit.cover),
      ),
    ),
    AiModel(
      name: 'ChatGPT',
      subtitle: 'Detaylı ve mantıklı çözüm'.tr(),
      badge: 'Aktif',
      accentColor: Color(0xFF10A37F),
      // Güncel ChatGPT uygulama ikonu: siyah zemin üzerinde beyaz düğüm.
      logo: _brandLogo('openai', _openAiSvg, bg: Color(0xFF000000)),
    ),
    AiModel(
      name: 'Gemini',
      subtitle: 'Hızlı analiz ve alternatif çözüm'.tr(),
      badge: 'Aktif',
      accentColor: Color(0xFF4796E3),
      // Gemini ikonu: beyaz zeminde mavi→mor degrade yıldız.
      logo: _brandLogo('gemini', _geminiSvg,
          bg: Colors.white, lightBg: true),
    ),
    AiModel(
      name: 'Grok',
      subtitle: 'Anlık ve yaratıcı çözüm'.tr(),
      badge: 'Aktif',
      accentColor: Color(0xFF1D1D1D),
      // Grok (xAI) uygulama ikonu: siyah zeminde beyaz işaret.
      logo: _brandLogo('grok', _grokSvg, bg: Color(0xFF000000)),
    ),
    AiModel(
      name: 'Deepseek',
      subtitle: 'Derin analiz ve akıl yürütme'.tr(),
      badge: 'Aktif',
      accentColor: Color(0xFF4D6BFE),
      // DeepSeek ikonu: beyaz zeminde mavi balina.
      logo: _brandLogo('deepseek', _deepseekSvg,
          bg: Colors.white, lightBg: true),
    ),
    AiModel(
      name: 'Claude',
      subtitle: 'Derin açıklama ve mantık yürütme'.tr(),
      badge: 'Aktif',
      accentColor: Color(0xFFD97757),
      // Claude uygulama ikonu: krem (ivory) zeminde turuncu yıldız işareti.
      logo: _brandLogo('claude', _claudeSvg,
          bg: Color(0xFFF0EEE5), lightBg: true),
    ),
  ];

  // ── Karosel modeli → foto-çözümde kullanılacak (vision-yetkin) sağlayıcı+model ──
  // ÖNEMLİ: foto-çözüm görsel (vision) gerektirir. grok-2-vision-1212 xAI'da
  // kaldırıldı ("Model not found") → grok-4.3 multimodal (text+vision) güncel
  // model; canlı testte görseli okuyup çözdü.
  // Deepseek burada YOK — kendi ayrı yolu (analyzeImageWithDeepseek) var.
  static const Map<String, (AiProvider, String)> _photoProvider = {
    'QuAlsar': (AiProvider.gemini, 'gemini-2.5-flash'),
    'Gemini':  (AiProvider.gemini, 'gemini-2.5-flash'),
    'ChatGPT': (AiProvider.openai, 'gpt-4o-mini'),
    'Grok':    (AiProvider.grok,   'grok-4.3'),
    'Claude':  (AiProvider.claude, 'claude-sonnet-4-6'),
  };

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

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadResultColors();
    // Varsayılan çözüm modu (Uygulama Ayarları > Çalışma) — kullanıcı
    // tercihine göre _selectedOption'ı önceden seç. Kullanıcı yine de
    // değiştirebilir; sadece açılışta hızlı seçim sağlanmış olur.
    final defaultMode = AppSettingsService.instance.defaultSolutionMode;
    final modeLabel = switch (defaultMode) {
      'quick' => 'Basit Çöz'.tr(),
      'stepbystep' => 'Adım Adım Çöz'.tr(),
      'detailed' => 'AI Arkadaşım'.tr(),
      _ => null,
    };
    if (modeLabel != null) {
      _selectedOption = modeLabel;
    }
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
    super.dispose();
  }

  // ─── Stream cancel + slow connection state ─────────────────────────────
  bool _cancelled = false;
  Timer? _slowConnTimer;
  bool _slowConnection = false;

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

    // Tüm sağlayıcılar aktif: QuAlsar/Gemini/ChatGPT/Grok/Claude → çoklu-sağlayıcı
    // proxy (aiProxy), Deepseek → kendi OCR+çözüm yolu. Engel yok.

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
    // NOT: Kota burada DÜŞÜLMEZ — yalnızca AI başarılı sonuç döndürünce
    // (aşağıda) düşülür. Aksi halde ağ/timeout/boş hata ve "Tekrar Dene"
    // her seferinde kullanıcının hakkından bir daha yerdi.
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

    // Kırpma özelliği kaldırıldı — görsel her zaman olduğu gibi gönderilir.
    final pathForAI = widget.imagePath;

    try {
      if (model.name == 'Deepseek') {
        result = await GeminiService.analyzeImageWithDeepseek(
          pathForAI,
          _selectedOption!,
          isMulti: widget.isMultiCapture,
        );
      } else {
        // Karoseldeki seçimi vision-yetkin sağlayıcı/modele eşle; askTask bunu
        // zincirin EN BAŞINDA dener, cevap gelmezse Gemini→OpenAI→Grok yedeğe
        // düşer. Bilinmeyen ad → null → Ayarlar'daki global seçim kullanılır.
        final pick = _photoProvider[model.name];
        result = await GeminiService.analyzeImage(
          pathForAI,
          _selectedOption!,
          isMulti: widget.isMultiCapture,
          provider: pick?.$1,
          model: pick?.$2,
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
      // Başarılı çözüm → kotayı şimdi düş (deneme değil, sonuç sayılır).
      await UsageQuota.increment(QuotaKind.solution);
      if (!mounted) return;
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
    return Column(
      children: [
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
                        // Üstten hafif renk tonu → alta beyaz degrade; seçimde
                        // ton belirginleşir — düz beyazdan daha derin görünüm.
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            c.withValues(alpha: sel ? 0.14 : 0.05),
                            AppPalette.card(context),
                          ],
                        ),
                        border: Border.all(
                          color: sel
                              ? c
                              : Colors.black.withValues(alpha: 0.10),
                          width: sel ? 2.2 : 1.0,
                        ),
                        boxShadow: [
                          // Çerçeve çizgisinin hemen bittiği yerde ince,
                          // sıkı gölge — kartı zeminden ayırır.
                          BoxShadow(
                            color: (sel ? c : Colors.black)
                                .withValues(alpha: sel ? 0.22 : 0.10),
                            blurRadius: 3,
                            spreadRadius: 0.6,
                            offset: Offset(0, 1),
                          ),
                          // Yumuşak derinlik gölgesi.
                          BoxShadow(
                            color: (sel ? c : Colors.black)
                                .withValues(alpha: sel ? 0.30 : 0.07),
                            blurRadius: sel ? 16 : 10,
                            offset: Offset(0, 5),
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
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            // Logo rozetine yer açmak için hafif uzatıldı.
            childAspectRatio: 1.18,
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
                      horizontal: 6, vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel
                          ? c.withValues(alpha: 0.70)
                          : Colors.black.withValues(alpha: 0.08),
                      width: sel ? 1.6 : 1.0,
                    ),
                    boxShadow: [
                      // Çerçeve çizgisinin hemen bittiği yerde ince, sıkı
                      // gölge — kart kenarını zeminden ayırır.
                      BoxShadow(
                        color: (sel ? c : Colors.black)
                            .withValues(alpha: sel ? 0.20 : 0.09),
                        blurRadius: 3,
                        spreadRadius: 0.6,
                        offset: Offset(0, 1),
                      ),
                      // Yumuşak derinlik gölgesi.
                      BoxShadow(
                        color: (sel ? c : Colors.black)
                            .withValues(alpha: sel ? 0.26 : 0.06),
                        blurRadius: sel ? 14 : 9,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo rozeti — her logo kendi marka zeminiyle gelir
                      // (gerçek uygulama ikonu görünümü).
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: model.logo,
                      ),
                      SizedBox(height: 3),
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
    // Tüm sağlayıcılar artık aktif (çoklu-sağlayıcı proxy + Deepseek yolu);
    // buton her zaman "Çözüme Başla" görünür.
    final color    = model.accentColor;

    return GestureDetector(
      onTap: _onSolveButtonTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.72), color.withValues(alpha: 0.50)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 0, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Çözüme Başla',
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
        GeminiErrorType.dailyLimitReached => Icons.lock_clock_rounded,
        GeminiErrorType.premiumFeature => Icons.workspace_premium_rounded,
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
        GeminiErrorType.dailyLimitReached => Color(0xFF8B5CF6),
        GeminiErrorType.premiumFeature => Color(0xFF8B5CF6),
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

