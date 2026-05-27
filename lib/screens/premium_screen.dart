import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pricing_service.dart';
import '../services/runtime_translator.dart';
import '../main.dart' show localeService;
import '../services/error_logger.dart';
import '../services/subscription_service.dart';

import '../theme/app_theme.dart';
import 'mock_payment_screen.dart';
// ═══════════════════════════════════════════════════════════════════════════════
//  PremiumScreen — Abonelik & Avantajlar (Ülke Bazlı Fiyatlandırma)
// ═══════════════════════════════════════════════════════════════════════════════

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  // 0 = 1 Ay, 1 = 3 Ay, 2 = 12 Ay
  int _selectedPlan = 2;

  static const _checkColor = Color(0xFF22C55E);
  static const _crossColor = Color(0xFFEF4444);
  static const _gold = Color(0xFFF59E0B);
  static const _pink = Color(0xFFEC4899);

  final GlobalKey _tickKey12Ay = GlobalKey();
  final GlobalKey _confettiKey = GlobalKey();
  OverlayEntry? _balloonEntry;
  bool _balloonVisible = false;

  late String _countryCode;
  late PricingPlan _plan;

  @override
  void initState() {
    super.initState();
    _updatePricing();
    localeService.addListener(_onLocaleChanged);
    _loadLiveRates();
  }

  void _onLocaleChanged() {
    _updatePricing();
  }

  void _updatePricing() {
    final lang = localeService.localeCode;
    _countryCode = PricingService.countryFromLang(lang);
    setState(() {
      _plan = PricingService.getPlan(_countryCode, locale: localeService);
    });
  }

  Future<void> _loadLiveRates() async {
    await PricingService.loadExchangeRates();
    if (mounted) _updatePricing();
  }

  @override
  void dispose() {
    localeService.removeListener(_onLocaleChanged);
    _balloonEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Üst içerik — slider sabit yükseklik, tablo ile birlikte tüm
            // bölge SingleChildScrollView içinde dikey scroll olur.
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    child: Column(
                    children: [
                      // 10-madde dikey slider — 4. madde tam görünecek
                      // şekilde sabit yükseklik (~440px). Başlık sabit;
                      // içinde dikey scroll. Tüm sayfa dış scroll ile kayar.
                      SizedBox(
                        height: 415,
                        child: _PremiumFeaturesSlider(),
                      ),

                      SizedBox(height: 10),

                      // Fiyat Kartları — 1 Ay | 3 Ay | 12 Ay
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _buildPlanCard(
                                  index: 0,
                                  title:
                                      '1 ${localeService.tr("month_unit")}',
                                  price: _plan.monthly,
                                  priceSuffix:
                                      '/${localeService.tr("month_unit")}',
                                  total: _plan.monthly,
                                  oldPrice: _plan.monthlyOld,
                                  discount: null,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _buildPlanCard(
                                  index: 1,
                                  title:
                                      '3 ${localeService.tr("month_unit")}',
                                  price: _plan.quarterlyPerMonth,
                                  priceSuffix:
                                      '/${localeService.tr("month_unit")}',
                                  total: _plan.quarterly,
                                  oldPrice: null,
                                  discount: '%10',
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _buildPlanCard(
                                  index: 2,
                                  title:
                                      '12 ${localeService.tr("month_unit")}',
                                  price: _plan.yearlyPerMonth,
                                  priceSuffix:
                                      '/${localeService.tr("month_unit")}',
                                  total: _plan.yearly,
                                  oldPrice: null,
                                  discount: '%33',
                                  tickKey: _tickKey12Ay,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: 8),

                      // Günlük fiyat + footer bilgisi + auto-renewal disclosure
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            Text(
                              _dailyText(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF555555),
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _footerText(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: AppPalette.textSecondary(context),
                                height: 1.4,
                              ),
                            ),
                            SizedBox(height: 6),
                            // Auto-renewal + cayma + tax disclosure satırı
                            // (Apple Guideline 3.1.2 + AB tüketici hukuku).
                            Text(
                              _disclosureText(),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 9.5,
                                color: AppPalette.textSecondary(context)
                                    .withValues(alpha: 0.85),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 12),

                      // ═══════════════════════════════════════════════════════
                      //  Avantajlar — Ücretsiz vs Premium karşılaştırma tablosu
                      // ═══════════════════════════════════════════════════════
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 36, right: 24),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            localeService.tr('advantages'),
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFFFFCC80),
                                Color(0xFFFFDDA6),
                                Color(0xFFFFECC8),
                                Color(0xFFFFF6E6),
                                Colors.white,
                              ],
                              stops: [0.0, 0.2, 0.45, 0.7, 1.0],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    Colors.black.withValues(alpha: 0.06),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 16, 20, 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: Text(
                                        localeService.tr('features'),
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppPalette.textSecondary(context),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 56,
                                      child: Text(
                                        localeService.tr('free'),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppPalette.textPrimary(context),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 14),
                                    Container(
                                      width: 72,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 5),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [_gold, _pink],
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Premium',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 20),
                                height: 1,
                                color: AppPalette.border(context),
                              ),
                              SizedBox(height: 6),
                              _featureRow(
                                  localeService.tr('unlimited_models')),
                              _featureRow(localeService.tr('max_accuracy')),
                              _featureRow(localeService.tr('ad_free')),
                              _featureRow('Dünyada ve ülkende yarış'.tr()),
                              _featureRow('Konu özetleri'.tr()),
                              _featureRow('Test soruları oluşturma'.tr()),
                              _featureRowSub(
                                  localeService.tr('similar_q'),
                                  localeService.tr('similar_q_desc')),
                              _featureRowSub(
                                  localeService.tr('match_cards'),
                                  localeService.tr('match_cards_desc')),
                              _featureRowSub(
                                  localeService.tr('info_cards'),
                                  localeService.tr('info_cards_desc')),
                              SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: 18),

                      // ═══════════════════════════════════════════════════════
                      //  Kullanım Koşulları — sayfanın en altında
                      // ═══════════════════════════════════════════════════════
                      const _TermsSection(),

                      SizedBox(height: 12),
                    ],
                  ),
                  ),
                  // Blur overlay — balon açıkken
                  if (_balloonVisible)
                    Positioned.fill(
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ═══════════════════════════════════════════════════════════════
            //  Alt sabit alan — Devam et butonu + footer
            // ═══════════════════════════════════════════════════════════════
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              decoration: BoxDecoration(
                color: AppPalette.bg(context),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Devam et butonu — uzun metinde FittedBox ile küçülterek
                  // taşma engellenir (örn. "7 Günlük Ücretsiz Denemeye Başla").
                  GestureDetector(
                    onTap: () => _onContinue(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFE8850C)],
                        ),
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFFF59E0B).withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _selectedPlan == 2
                                ? '7 Günlük Ücretsiz Denemeye Başla'.tr()
                                : localeService.tr('continue_btn'),
                            maxLines: 1,
                            style: GoogleFonts.poppins(
                              fontSize: _selectedPlan == 2 ? 15 : 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Not: Önceden burada "Satın Alımları Geri Yükle",
                  // "Aboneliği Yönet", "Kullanım Koşulları", "Gizlilik
                  // Politikası" mavi linkleri vardı. Kullanıcı isteği üzerine
                  // butonun altından temizlendi. Yardımcı metotlar (_smallLink,
                  // _onRestorePurchases, _openManageSubscriptions,
                  // _showTermsBottomSheet, _showPrivacyBottomSheet) ileride
                  // tekrar açılabilmesi için dosyada korunuyor.
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Aboneliği Yönet — iOS itms-services veya Play Store derin linki.
  /// Apple Guideline 3.1.2(a) — kullanıcı kolayca iptal edebilmelidir.
  // ignore: unused_element
  Future<void> _openManageSubscriptions(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Uri uri;
    if (Platform.isIOS || Platform.isMacOS) {
      // iOS: App Store abonelikleri direkt açar
      uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    } else {
      // Android: Play Store abonelik yönetimi
      uri = Uri.parse(
          'https://play.google.com/store/account/subscriptions?sku=qualsar_premium_monthly&package=com.qualsar.ai');
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Aboneliği yönetme sayfası açılamadı.'.tr()),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Hata: $e'),
        ));
      }
    }
  }

  void _onContinue(BuildContext context) {
    _showPaymentSheet(context);
  }

  // ─── Restore Purchases (Apple Guideline 3.1.1 + Play Store iyi pratik) ───
  // SubscriptionService.restorePurchases() çağırır; purchase stream'den dönen
  // `PurchaseStatus.restored` event'i PremiumStatus'u günceller.
  // ignore: unused_element
  Future<void> _onRestorePurchases(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!SubscriptionService.instance.isAvailable) {
      messenger.showSnackBar(
        SnackBar(content: Text('Mağaza şu an kullanılamıyor.'.tr())),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('Satın alımlar geri yükleniyor…'.tr()),
        duration: const Duration(seconds: 2),
      ),
    );
    await SubscriptionService.instance.restorePurchases();
    // Restore başarılıysa purchase stream içinden PremiumStatus güncellenir;
    // bir saniye bekleyip kullanıcıya feedback verelim.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'İşlem tamamlandı. Premium aktifse menüde görünecek.'.tr(),
        ),
        backgroundColor: const Color(0xFF22C55E),
      ),
    );
  }

  // ignore: unused_element
  void _showTermsBottomSheet(BuildContext context) {
    _showSimpleLegal(
      context,
      title: 'Kullanım Koşulları'.tr(),
      body: _kSubscriptionTermsBody.tr(),
    );
  }

  // ignore: unused_element
  void _showPrivacyBottomSheet(BuildContext context) {
    _showSimpleLegal(
      context,
      title: 'Gizlilik Politikası'.tr(),
      body: _kSubscriptionPrivacyBody.tr(),
    );
  }

  static const _kSubscriptionTermsBody = '''Bu abonelik 7 günlük ücretsiz deneme ile başlar. Deneme süresi sona ermeden en az 24 saat önce iptal edilmezse, abonelik otomatik olarak yenilenir ve seçtiğin plan tutarı ödeme yönteminden tahsil edilir.

Abonelik aktif olduğu sürece uygulamadaki tüm Premium özelliklere sınırsız erişim sağlanır.

İptal: Aboneliğini istediğin zaman iptal edebilirsin. iOS'ta App Store ayarlarından, Android'de Google Play aboneliklerinden yönetebilirsin. İptal işlemi mevcut faturalandırma döneminin sonunda etkin olur; orta dönem iadesi yapılmaz.

Yenileme: Süre dolduğunda indirimsiz aylık/üç aylık/yıllık fiyatla otomatik yenilenir. Fiyat değişiklikleri yenileme öncesinde sana bildirilir.

Cayma Hakkı (Avrupa Birliği): AB tüketicileri, sözleşme tarihinden itibaren 14 gün içinde herhangi bir neden göstermeden cayabilir. Ancak dijital içerik tüketimi başladıktan sonra cayma hakkı sona erer.

Fiyat ve Vergiler: Ekranda gösterilen fiyat, ülkenize uygulanan KDV/satış vergisi dahil veya hariç olabilir; nihai tutar ödeme adımında platform tarafından gösterilir.

Aile Paylaşımı: iOS Family Sharing destekleniyorsa, bir abone aile grubundaki diğer üyelere de erişim verebilir.

Bu koşullar geçerli olmaya devam ederken uygulamanın güncellenmiş sürümlerinde değişiklik yapılabilir; önemli değişiklikler önceden bildirilir.''';

  static const _kSubscriptionPrivacyBody = '''Premium abonelik akışı sırasında işlenen kişisel veriler:

• Ödeme yöntemi bilgileri (kart numarası, son kullanma tarihi, CVC) doğrudan Apple App Store veya Google Play tarafından işlenir; QuAlsar bu verileri saklamaz veya görmez.

• Abonelik durumu (aktif/iptal, plan tipi, yenileme tarihi) cihaz üzerinde lokal olarak ve isteğe bağlı olarak hesabınla ilişkilendirilmiş sunucuda tutulur.

• Fatura adresi (varsa) sadece ödeme platformuyla paylaşılır.

Veri Saklama: Abonelik durumu, hesabın aktif olduğu sürece saklanır. Hesap silme talebinde bu veriler 30 gün içinde silinir; yasal saklama yükümlülükleri bu süreyi etkileyebilir.

Veri Paylaşımı: QuAlsar abonelik bilgilerinizi üçüncü taraflarla pazarlama amaçlı paylaşmaz. Sadece (a) ödeme platformları (Apple, Google), (b) yasal yükümlülükler gerektirdiğinde resmi kurumlar, (c) hizmet sağlayıcılar (sunucu altyapısı, hata izleme) ile sınırlı veri paylaşımı yapılabilir.

GDPR (AB) / KVKK (Türkiye) Hakların: Kişisel verilerine erişim, düzeltme, silme, işlemeyi sınırlama ve veri taşınabilirliği taleplerinde bulunabilirsin. Talebini serhatdsme@gmail.com adresine yönelt.

Veri Aktarımı: Sunucu altyapısı bulutta (örn. Google Cloud) çalıştığından, verilerin AB dışına aktarılabilir. Bu aktarım standart sözleşme maddelerine ve uygun korumalara dayanır.

Çocuklar: 13 yaşından (AB'de 16) küçük kullanıcılar ebeveyn izniyle abone olabilir.''';

  void _showSimpleLegal(BuildContext context,
      {required String title, required String body}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => Container(
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  child: Text(
                    body,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.55,
                      color: AppPalette.textPrimary(context),
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

  // ignore: unused_element
  Widget _smallLink({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A73E8),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF1A73E8),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _dotSep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '·',
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: AppPalette.textSecondary(context),
        ),
      ),
    );
  }

  /// Platform mağaza adı — iOS'ta "App Store", Android'de "Google Play",
  /// web/diğerlerde "Mağaza".
  String _storePlatformName() {
    if (kIsWeb) return 'Mağaza'.tr();
    try {
      if (Platform.isIOS || Platform.isMacOS) return 'App Store';
      if (Platform.isAndroid) return 'Google Play';
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'premium_screen'); }
    return 'Mağaza'.tr();
  }

  /// Tarih formatı — uygulamanın aktif diline kabaca uygun.
  /// CJK için "yyyy年MM月dd日", Arapça için sayılar Arapçaya çevrilmiyor
  /// (intl paketine geçilince düzgün olur).
  String _formatDate(DateTime d) {
    final months = [
      localeService.tr('month_jan_short'),
      localeService.tr('month_feb_short'),
      localeService.tr('month_mar_short'),
      localeService.tr('month_apr_short'),
      localeService.tr('month_may_short'),
      localeService.tr('month_jun_short'),
      localeService.tr('month_jul_short'),
      localeService.tr('month_aug_short'),
      localeService.tr('month_sep_short'),
      localeService.tr('month_oct_short'),
      localeService.tr('month_nov_short'),
      localeService.tr('month_dec_short'),
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// Ay-overflow safe yenileme tarihi.
  /// Eski sürüm: DateTime(year, month+3, day) — Mart 31 + 3 ay = Temmuz 1 (kayar).
  /// Yeni: hedef ayın son gününü geçerse o ayın son gününe yuvarla.
  DateTime _addMonthsSafe(DateTime base, int months) {
    final newYear = base.year + ((base.month - 1 + months) ~/ 12);
    final newMonth = ((base.month - 1 + months) % 12) + 1;
    final lastDayInTarget = DateTime(newYear, newMonth + 1, 0).day;
    final day = base.day > lastDayInTarget ? lastDayInTarget : base.day;
    return DateTime(newYear, newMonth, day);
  }

  DateTime _addYearsSafe(DateTime base, int years) {
    final newYear = base.year + years;
    final lastDayInTarget = DateTime(newYear, base.month + 1, 0).day;
    final day = base.day > lastDayInTarget ? lastDayInTarget : base.day;
    return DateTime(newYear, base.month, day);
  }

  /// "12 ay" → "12", "12个月" → "12", "١٢ شهر" → "١٢"
  /// Tüm ardışık ilk rakam karakterlerini (Latin + Arap-Hint + Doğu Arap) çeker.
  String? _extractLeadingNumber(String s) {
    final m = RegExp(r'^[\d٠-٩۰-۹]+').firstMatch(s);
    return m?.group(0);
  }

  void _showPaymentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tutma çubuğu
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Platform adı (App Store / Google Play) dinamik.
              Text(
                _storePlatformName(),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              SizedBox(height: 10),
              Container(height: 0.5, color: AppPalette.border(context)),
              SizedBox(height: 14),

              // Uygulama adı + açıklama
              Text(
                'QuAlsar ${_selectedPlan == 0 ? localeService.tr("monthly_label") : _selectedPlan == 1 ? localeService.tr("quarterly_label") : localeService.tr("yearly_label")} Premium',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'QuAlsar - ${localeService.tr("all_lessons")}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppPalette.textSecondary(context),
                ),
              ),

              SizedBox(height: 16),

              // Ayırıcı
              Container(height: 0.5, color: AppPalette.border(context)),

              SizedBox(height: 14),

              // Fiyat çerçevesi — Google Play tarzı 2 satır.
              //  • Satır 1 = bugün ödenecek (yıllık planda 7 gün deneme → "1
              //    haftalık ücretsiz deneme", diğerlerinde ilk dönem fiyatı)
              //  • Satır 2 = yenileme tarihi + o tarihte ödenecek tutar (aynı
              //    plan, /birim ile)
              Builder(builder: (_) {
                final isTrial = _selectedPlan == 2; // yıllık plan = 7 gün deneme
                final periodLabel = _selectedPlan == 0
                    ? '1 ${localeService.tr("month_unit")}'
                    : _selectedPlan == 1
                        ? localeService.tr('three_months_unit')
                        : '12 ${localeService.tr("month_unit")}';
                final unitLabel = _selectedPlan == 0
                    ? localeService.tr('month_unit')
                    : _selectedPlan == 1
                        ? localeService.tr('three_months_unit')
                        : localeService.tr('year_unit');
                final price = _selectedPlan == 0
                    ? _plan.monthly
                    : _selectedPlan == 1
                        ? _plan.quarterly
                        : _plan.yearly;
                // Deneme planında yenileme = bugün + 7 gün; diğerlerinde
                // bugün + plan süresi.
                final renewDate = isTrial
                    ? DateTime.now().add(const Duration(days: 7))
                    : _selectedPlan == 0
                        ? DateTime(DateTime.now().year,
                            DateTime.now().month + 1, DateTime.now().day)
                        : _selectedPlan == 1
                            ? DateTime(DateTime.now().year,
                                DateTime.now().month + 3, DateTime.now().day)
                            : DateTime(DateTime.now().year + 1,
                                DateTime.now().month, DateTime.now().day);
                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Color(0xFFFAFAFB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppPalette.border(context), width: 0.5),
                  ),
                  child: Column(
                    children: [
                      // Satır 1: Başlangıç tarihi: bugün
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${localeService.tr("start_date")}: ${localeService.tr("today")}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: AppPalette.textPrimary(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isTrial
                                  ? '1 haftalık ücretsiz deneme'.tr()
                                  : '$price · $periodLabel',
                              textAlign: TextAlign.end,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Ayraç
                      Container(
                          height: 0.5, color: AppPalette.border(context)),
                      // Satır 2: Başlangıç tarihi: [yenileme tarihi]
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${localeService.tr("start_date")}: ${_formatDate(renewDate)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: AppPalette.textPrimary(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$price/$unitLabel',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              SizedBox(height: 14),

              // Bilgi maddeleri
              _infoBullet(localeService.tr('cancel_anytime_info')),
              SizedBox(height: 8),
              _infoBullet(localeService.tr('promo_reminder')),

              SizedBox(height: 16),

              // Ayırıcı
              Container(height: 0.5, color: AppPalette.border(context)),

              SizedBox(height: 14),

              // ── Mastercard satırı — debug build'de MockPaymentScreen
              //    tasarım önizlemesi açar; release build'de doğrudan gerçek
              //    Google Play / App Store sheet'i tetiklenir (asıl ödeme
              //    yöntemi seçimi store kendi sheet'inde yapılır).
              InkWell(
                onTap: () {
                  if (kDebugMode) {
                    MockPaymentScreen.show(context);
                  } else {
                    Navigator.pop(ctx);
                    _showPaymentMethodsSheet(context);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      // Mastercard ikonu — 2 daire (kırmızı + turuncu, üst üste)
                      Container(
                        width: 44, height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppPalette.border(context),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Stack(
                          children: const [
                            Positioned(
                              left: 4,
                              child: _MastercardCircle(
                                color: Color(0xFFEB001B),
                              ),
                            ),
                            Positioned(
                              right: 4,
                              child: _MastercardCircle(
                                color: Color(0xFFF79E1B),
                                opacity: 0.85,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Mastercard-9078',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimary(context),
                          ),
                        ),
                      ),
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppPalette.border(context).withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 12,
                          color: AppPalette.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 0.5, color: AppPalette.border(context)),

              SizedBox(height: 14),

              // ── "Abone Ol düğmesine dokunarak..." paragrafı ──────────────
              RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: AppPalette.textPrimary(context),
                    height: 1.45,
                  ),
                  children: [
                    TextSpan(
                      text: '"Abone Ol" düğmesine dokunarak iptal edilene '
                          'kadar aboneliğinizin otomatik olarak '
                          'yenileneceğini kabul etmiş olursunuz. ',
                    ),
                    TextSpan(
                      text: Platform.isIOS
                          ? 'App Store Hizmet Şartları'
                          : 'Google Play Hizmet Şartları',
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text: ' içinde açıklandığı üzere fiyatınız değişirse '
                          'sizi bilgilendiririz. ',
                    ),
                    TextSpan(
                      text: 'Nasıl iptal edeceğinizi öğrenin',
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: '. ',
                    ),
                    TextSpan(
                      text: 'Daha fazla',
                      style: TextStyle(
                        color: const Color(0xFF1A73E8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20),

              // ── "Abone Ol" mavi butonu (Google Play tarzı) ───────────────
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _showPaymentMethodsSheet(context);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A73E8),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Center(
                    child: Text(
                      'Abone Ol'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // NOT: Daha önce burada _showAddressSheet + _addressField vardı; kullanıcı
  // adres bilgisi giriyordu. Bu KALDIRILDI çünkü:
  //   1. Apple StoreKit / Google Play Billing kendi hesap adresini kullanır.
  //   2. Kullanıcının girdiği veri hiçbir yere gitmiyordu (sahte form).
  //   3. Apple Guideline 3.1.1 — IAP dışı ödeme akışı/UI yasak.

  Future<void> _showPaymentMethodsSheet(BuildContext context) async {
    // Play Billing / StoreKit akışı — seçili plana göre SKU belirle.
    final plan = _selectedPlan == 0
        ? SubscriptionPlan.monthly
        : _selectedPlan == 1
            ? SubscriptionPlan.quarterly
            : SubscriptionPlan.yearly;

    final messenger = ScaffoldMessenger.of(context);

    if (!SubscriptionService.instance.isAvailable) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Ödeme sistemi şu an kullanılamıyor.'.tr()),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    // Loading snackbar — Play Billing dialog'u açılırken kullanıcı görsün.
    messenger.showSnackBar(
      SnackBar(
        content: Text('Satın alma başlatılıyor…'.tr()),
        duration: const Duration(seconds: 2),
      ),
    );

    final result = await SubscriptionService.instance.buy(plan);
    if (!mounted) return;

    switch (result) {
      case SubscriptionPurchaseResult.success:
        // Güzel başarı modalı göster — plan + tutar + sonraki yenileme tarihi.
        // _showConfirmSheet kullanıcının "Tamam"a basmasından sonra premium
        // sayfasını otomatik pop eder. State'in kendi context'i — mounted OK.
        if (!mounted) return;
        _showConfirmSheet(this.context);
        break;
      case SubscriptionPurchaseResult.canceled:
        // Sessizce — kullanıcı iptal etti, snackbar göstermeye gerek yok.
        break;
      case SubscriptionPurchaseResult.pending:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Ödeme bekleniyor (aile onayı / banka doğrulaması).'.tr(),
            ),
          ),
        );
        break;
      case SubscriptionPurchaseResult.unavailable:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Bu ürün şu an mağazada mevcut değil. Lütfen daha sonra tekrar deneyin.'
                  .tr(),
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        break;
      case SubscriptionPurchaseResult.error:
        messenger.showSnackBar(
          SnackBar(
            content: Text('Satın alma sırasında bir hata oluştu.'.tr()),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        break;
    }
  }

  /// Satın alma başarılı sonrası modal — yeşil checkmark + plan + tutar
  /// + sonraki yenileme tarihi + Tamam butonu.
  void _showConfirmSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppPalette.card(context),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tutma çubuğu
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.border(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Başarı ikonu
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Color(0xFF22C55E).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 40,
                  color: Color(0xFF22C55E),
                ),
              ),

              SizedBox(height: 16),

              Text(
                localeService.tr('payment_success'),
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                ),
              ),

              SizedBox(height: 8),

              Text(
                localeService.tr('premium_activated'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppPalette.textSecondary(context),
                  height: 1.5,
                ),
              ),

              SizedBox(height: 16),

              // Detaylar çerçevesi
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Color(0xFFFAFAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppPalette.border(context), width: 0.5),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            localeService.tr('plan_label'),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                          Text(
                            '${_selectedPlan == 0 ? localeService.tr("monthly_label") : _selectedPlan == 1 ? localeService.tr("quarterly_label") : localeService.tr("yearly_label")} Premium',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      height: 0.5,
                      color: AppPalette.border(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            localeService.tr('amount_paid'),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                          Text(
                            _selectedPlan == 0 ? _plan.monthly : _selectedPlan == 1 ? _plan.quarterly : _plan.yearly,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      height: 0.5,
                      color: AppPalette.border(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            localeService.tr('next_renewal'),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                          Text(
                            _formatDate(_selectedPlan == 0
                                ? _addMonthsSafe(DateTime.now(), 1)
                                : _selectedPlan == 1
                                    ? _addMonthsSafe(DateTime.now(), 3)
                                    : _addYearsSafe(DateTime.now(), 1)),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20),

              // Tamam butonu
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                    ),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Center(
                    child: Text(
                      localeService.tr('ok'),
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: AppPalette.textSecondary(context),
              shape: BoxShape.circle,
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppPalette.textSecondary(context),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  String _dailyText() {
    switch (_selectedPlan) {
      case 0:
        return _plan.dailyMonthly;
      case 1:
        return _plan.dailyQuarterly;
      case 2:
        return _plan.dailyYearly;
      default:
        return '';
    }
  }

  String _footerText() {
    switch (_selectedPlan) {
      case 0:
        return _plan.footerMonthly;
      case 1:
        return _plan.footerQuarterly;
      case 2:
        return _plan.footerYearly;
      default:
        return '';
    }
  }

  /// Auto-renewal disclosure + AB cayma hakkı + KDV/tax notu.
  /// AB ülkelerinde KDV dahil, diğerlerinde "vergi ödeme adımında" notu.
  String _disclosureText() {
    final inclusive = PricingService.isVatInclusiveCountry(_countryCode);
    final taxLine = inclusive
        ? 'Fiyatlar KDV dahildir.'.tr()
        : 'Vergiler ödeme adımında hesaplanır.'.tr();
    return '${'Abonelik otomatik yenilenir; iptal mevcut dönem sonunda etkindir. AB tüketicileri 14 gün cayma hakkına sahiptir.'.tr()} $taxLine';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  %50 İndirim Balonu
  // ═══════════════════════════════════════════════════════════════════════════

  void _showDiscountBalloon(BuildContext context) {
    // Zaten görünüyorsa tekrar açma
    if (_balloonVisible) return;

    final overlay = Overlay.of(context);

    // Tik ikonunun ekran pozisyonunu al
    final renderBox =
        _tickKey12Ay.currentContext?.findRenderObject() as RenderBox?;
    Offset tickPos = Offset.zero;
    if (renderBox != null) {
      tickPos = renderBox.localToGlobal(Offset.zero);
      tickPos = Offset(
        tickPos.dx + renderBox.size.width,
        tickPos.dy + renderBox.size.height,
      );
    }

    _balloonEntry = OverlayEntry(
      builder: (ctx) => _DiscountBalloon(
        anchorPos: tickPos,
      ),
    );

    overlay.insert(_balloonEntry!);
    setState(() => _balloonVisible = true);

    // 4 saniye sonra kapat
    Future.delayed(Duration(seconds: 4), () {
      if (_balloonVisible) {
        _balloonEntry?.remove();
        _balloonEntry = null;
        setState(() => _balloonVisible = false);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Fiyat Kartı
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPlanCard({
    required int index,
    required String title,
    required String price,
    required String priceSuffix,
    String? total,
    String? oldPrice,
    String? discount,
    Key? tickKey,
  }) {
    final selected = _selectedPlan == index;
    final dark = AppPalette.isDark(context);
    final tabBg = dark
        ? Colors.black
        : (selected ? Color(0xFFF0FFF4) : Color(0xFFF3F4F6));
    final tabBorder = selected
        ? Color(0xFF22C55E)
        : (dark ? Color(0xFF2E2E2E) : Color(0xFFE8E8EE));

    return GestureDetector(
      onTap: () {
        setState(() => _selectedPlan = index);
        if (index == 2) _showDiscountBalloon(context);
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 16),
        decoration: BoxDecoration(
          color: tabBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: tabBorder,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? Color(0xFF22C55E).withValues(alpha: 0.15)
                  : Color(0xFF9CA3AF).withValues(alpha: 0.10),
              blurRadius: selected ? 18 : 10,
              spreadRadius: selected ? 1 : 0,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // İndirim badge — üst çizgiye yakın
            if (discount != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFEF4444)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$discount ${localeService.tr("discount_label")}',
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            else
              SizedBox(height: 22),

            SizedBox(height: 12),

            // Süre — rakam ve Ay ayrı satır.
            // Eski: `title.split(' ').first` → "12 个月" (Çince) için "12个月"
            // tek kelime olarak gelir, bozulurdu. Şimdi rakamları regex ile
            // ayıkla; rakam yoksa olduğu gibi göster.
            Text(
              _extractLeadingNumber(title) ?? title,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: dark ? Colors.white : AppPalette.textPrimary(context),
                height: 1.1,
              ),
            ),
            Text(
              localeService.tr('month_unit'),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : Color(0xFF777777),
              ),
            ),

            SizedBox(height: 10),

            // Fiyat + süre etiketi
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    price,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? Color(0xFF22C55E)
                          : (dark ? Colors.white : Color(0xFF444444)),
                      height: 1.1,
                    ),
                  ),
                  Text(
                    priceSuffix,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      color: dark ? Colors.white : Color(0xFFAAAAAA),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 12),

            // İnce ayırıcı çizgi
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              height: 0.5,
              color: dark ? Color(0xFF2E2E2E) : Color(0xFFE0E0E0),
            ),

            SizedBox(height: 12),

            // Alt bilgi — toplam fiyat (çizgi altı)
            if (total != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${localeService.tr("total_label")} $total',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: dark ? Colors.white : AppPalette.textSecondary(context),
                  ),
                ),
              )
            else
              SizedBox(height: 12),

            SizedBox(height: 10),

            // Seçim göstergesi + confetti ikonu
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  key: tickKey,
                  duration: Duration(milliseconds: 200),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Color(0xFF22C55E)
                          : Color(0xFFD1D5DB),
                      width: 2,
                    ),
                    color: selected
                        ? Color(0xFF22C55E)
                        : Colors.transparent,
                  ),
                  child: selected
                      ? Icon(Icons.check_rounded,
                          size: 11, color: Colors.white)
                      : null,
                ),
                // Confetti ikonu — tik ile sağ çerçeve çizgisi arasında
                if (index == 2) ...[
                  SizedBox(width: 4),
                  GestureDetector(
                    key: _confettiKey,
                    onTap: () => _showDiscountBalloon(context),
                    child: Text(
                      '🎉',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Avantajlar tablosu satırları — Ücretsiz vs Premium karşılaştırma
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _featureRow(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111))),
          ),
          SizedBox(
              width: 52,
              child:
                  Icon(Icons.close_rounded, size: 18, color: _crossColor)),
          SizedBox(width: 8),
          SizedBox(
              width: 72,
              child: Icon(Icons.check_circle_rounded,
                  size: 22, color: _checkColor)),
        ],
      ),
    );
  }

  Widget _featureRowSub(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppPalette.textPrimary(context))),
                Text(sub,
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF555555),
                        height: 1.3)),
              ],
            ),
          ),
          SizedBox(
              width: 52,
              child:
                  Icon(Icons.close_rounded, size: 18, color: _crossColor)),
          SizedBox(width: 8),
          SizedBox(
              width: 72,
              child: Icon(Icons.check_circle_rounded,
                  size: 22, color: _checkColor)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  İndirim Balonu — 5 saniye görünür, confetti ikonuyla tekrar açılır
// ═══════════════════════════════════════════════════════════════════════════════

class _DiscountBalloon extends StatefulWidget {
  final Offset anchorPos;
  const _DiscountBalloon({
    required this.anchorPos,
  });

  @override
  State<_DiscountBalloon> createState() => _DiscountBalloonState();
}

class _DiscountBalloonState extends State<_DiscountBalloon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 350),
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const balloonWidth = 240.0;
    // Ortalanmış yatay pozisyon
    final left = (screenWidth - balloonWidth) / 2;
    // Butonun ~3cm (115px) üstünde — alttan konumla
    // Buton alanı yaklaşık 70px alt kısımda, 115px daha yukarı
    const bottomOffset = 70.0 + 115.0;

    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned(
              left: left,
              bottom: bottomOffset,
              child: ScaleTransition(
                alignment: Alignment.topCenter,
                scale: _scale,
                child: Container(
                  width: balloonWidth,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
            color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppPalette.textPrimary(context),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '🎉',
                        style: GoogleFonts.poppins(fontSize: 28),
                      ),
                      SizedBox(height: 10),
                      Text(
                        localeService.tr('discount_50'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFEF6C00),
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${localeService.tr("half_year_free")} 😍',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textPrimary(context),
                            height: 1.5,
                          ),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _PremiumFeaturesSlider — dikey 10-madde scroll listesi.
//  Premium ödeme sayfasında üst kısımda Expanded ile fiyat sekmelerine kadar
//  yer kaplar. Çerçeve içinde dikey scroll; alttaki maddeler kaydırılarak
//  görünür. Her madde bir premium avantajını "değer odaklı" anlatır.
// ═══════════════════════════════════════════════════════════════════════════
class _PremiumFeaturesSlider extends StatelessWidget {
  const _PremiumFeaturesSlider();

  static const _items = <_FeatureItem>[
    _FeatureItem(
      n: '01',
      title: 'Dünyanın en güçlü AI modelleri tek uygulamada',
      body:
          'QuAlsar yanında ChatGPT-5.5, Gemini 3.1, Claude 4.7 Opus, DeepSeek-V4 Pro ve Grok 4.3 — hangisini istersen seç, sorunu o çözsün.',
    ),
    _FeatureItem(
      n: '02',
      title: 'Sana uygun çözüm modu',
      body:
          'İstediğin sorunun fotoğrafını çek; sade çözüm, adım adım çözüm veya AI arkadaşın sohbet havasında çözsün.',
    ),
    _FeatureItem(
      n: '03',
      title: 'Kişiselleştirilmiş konu özetleri',
      body:
          'İstediğin dersten istediğin konudan kendi seviyene göre özet oluştur. Özetin içinde sesli ve yazılı not oluştur.',
    ),
    _FeatureItem(
      n: '04',
      title: 'Sana özel test soruları',
      body:
          'İstediğin dersten istediğin konudan kendi seviyene göre test soruları oluştur.',
    ),
    _FeatureItem(
      n: '05',
      title: 'Her soruyu kalıcı öğren',
      body:
          'Çözdüğün her sorunun ardından 5 benzer soru, bilgi kartları ve eşleştirme kartları ile pekiştir.',
    ),
    _FeatureItem(
      n: '06',
      title: 'QuAlsar Arena: yarış ve sırala',
      body:
          'Şehrinde, ülkende ve dünyada kendi seviyendeki öğrencilerle 1v1 yarış. Günlük, haftalık, aylık ve genel sıralamanı gör.',
    ),
    _FeatureItem(
      n: '07',
      title: 'Hatanı anla, ezberlemeden öğren',
      body:
          'QuAlsar doğru cevabın yanında neyi neden yanlış yaptığını gösterir.',
    ),
    _FeatureItem(
      n: '08',
      title: 'Sesli komut + canlı kamera',
      body:
          'Kamerayı aç sesinle komut ver. QuAlsar anında cevap versin.',
    ),
    _FeatureItem(
      n: '09',
      title: '55 dil, 131 ülke',
      body:
          'Kendi dilini ve ülkeni seç — müfredat sana göre özelleşsin.',
    ),
    _FeatureItem(
      n: '10',
      title: 'Ebeveyn destek modu (isteğe bağlı)',
      body:
          'Sen açarsan ailen sadece çalışma süreni ve başarını görür. Detaylar gizli, kontrol sende.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          // Turuncu → açık turuncu → krem → beyaz dikey gradient
          // (Avantajlar tablosu ile aynı palet — premium aviation feel)
          gradient: AppPalette.isDark(context)
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFCC80), // turuncu (başlık ile aynı)
                    Color(0xFFFFDDA6), // açık turuncu
                    Color(0xFFFFECC8), // daha açık
                    Color(0xFFFFF6E6), // krem
                    Colors.white,       // dipte beyaz
                  ],
                  stops: [0.0, 0.2, 0.45, 0.7, 1.0],
                ),
          color: AppPalette.isDark(context) ? Colors.black : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              // Sabit başlık — turuncu pill, 4 köşesi yuvarlak. Çerçeve
              // içinde "kart" gibi durur; sol üstte geri butonu overlay.
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Color(0xFFFFCC80), // turuncu
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding:
                          const EdgeInsets.fromLTRB(50, 12, 12, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Premium Avantajları',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF111111),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Geri butonu — sol üstte overlay
                    Positioned(
                      left: 6,
                      child: Builder(
                        builder: (ctx) => GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
            color: AppPalette.card(context),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.08),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.arrow_back_ios_rounded,
                              size: 15,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 1,
                  color: AppPalette.isDark(context)
                      ? Color(0xFF2E2E2E)
                      : Color(0xFFEEF0F3)),
              // Dikey scroll listesi — başlık altta sabit kalır
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                  physics: BouncingScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 18,
                    thickness: 1,
                    // Gradient turuncuyla uyumlu yarı şeffaf koyu turuncu çizgi
                    color: AppPalette.isDark(context)
                        ? Color(0xFF2E2E2E)
                        : const Color(0xFFE8850C).withValues(alpha: 0.18),
                  ),
                  itemBuilder: (_, i) => _PremiumRow(item: _items[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureItem {
  final String n;
  final String title;
  final String body;
  const _FeatureItem({
    required this.n,
    required this.title,
    required this.body,
  });
}

class _PremiumRow extends StatelessWidget {
  final _FeatureItem item;
  const _PremiumRow({required this.item});
  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.isDark(context);
    final titleColor = dark ? Colors.white : const Color(0xFF111111);
    final bodyColor = dark ? Colors.white : const Color(0xFF555555);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sıra numarası — sol kenarda, turuncu
        SizedBox(
          width: 38,
          child: Text(
            item.n,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFFE8850C),
              height: 1.0,
              letterSpacing: -0.4,
            ),
          ),
        ),
        SizedBox(width: 8),
        // Başlık + açıklama
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                  height: 1.25,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 4),
              Text(
                item.body,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: bodyColor,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _TermsSection — QuAlsar Premium Kullanım Koşulları metni.
//  Avantajlar tablosunun altında; ortalı ana başlık + 10 alt başlık paragrafı.
// ═══════════════════════════════════════════════════════════════════════════
class _TermsSection extends StatelessWidget {
  const _TermsSection();

  static const _items = <(String, String)>[
    (
      'QuAlsar Premium Üyeliği',
      'Premium paketimiz; sınırsız Yapay Zeka destekli arama, yüksek performanslı çözümleme algoritmaları ve tamamen reklamsız bir deneyim sunar.',
    ),
    (
      'Ücretsiz Deneme Hakkı',
      'Deneme süresi her hesap ve cihaz için bir defaya mahsus 7 gündür. Deneme süresi bitiminde, kayıtlı ödeme yönteminiz üzerinden abonelik ücreti otomatik olarak tahsil edilecektir.',
    ),
    (
      'Fiyatlandırma ve KDV',
      'Belirtilen tüm ücretlere KDV dahildir. QuAlsar, fiyatlar üzerinde önceden haber vermeksizin değişiklik yapma hakkını saklı tutar; ancak mevcut aktif aboneler, yenileme dönemlerinde kendi başlangıç fiyatlarını koruyacaklardır.',
    ),
    (
      'Abonelik Süresi',
      'Satın alınan veya yenilenen abonelikler, işlem tarihinden itibaren 30 gün boyunca geçerlidir.',
    ),
    (
      'Otomatik Yenileme',
      'Üyeliğiniz her ay otomatik olarak yenilenir. Aylık abonelik bedeli, yenileme tarihinde kayıtlı kartınızdan çekilir.',
    ),
    (
      'İptal İşlemi',
      'Üyeliğinizi dilediğiniz zaman "Menü > Aboneliğim" adımlarını takip ederek iptal edebilirsiniz. İptal durumunda mevcut süreniz dolana kadar Premium özelliklere erişiminiz devam eder ve yeni bir ücret alınmaz.',
    ),
    (
      'İade Politikası',
      'İade talepleri, ödeme yapıldıktan sonraki ilk 7 gün içinde "Bize Ulaşın" sekmesinden veya serhatdsme@gmail.com adresinden iletilebilir. İadeler, yalnızca Premium özellikler henüz kullanılmamışsa ve 7 günlük süre aşılmamışsa değerlendirmeye alınır.',
    ),
    (
      'İade Yöntemi',
      'Onaylanan iadeler, satın alma sırasında kullanılan orijinal ödeme yöntemine geri aktarılır.',
    ),
    (
      'Hesap Güvenliği ve Kullanım',
      'QuAlsar içeriğine yalnızca kendi hesabınızla giriş yaparak erişebilirsiniz. Hesapların devredilmesi, kiralanması veya üçüncü şahıslara satılması kesinlikle yasaktır.',
    ),
    (
      'Telif Hakları',
      'İçeriğin kopyalanması, dağıtılması veya izinsiz satılması gibi yetkisiz faaliyetler; hesabın kalıcı olarak askıya alınmasına ve yasal süreç başlatılmasına neden olabilir.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ana başlık — çerçeve içinde, ortalı; "Al" hecesi kırmızı.
            Center(
              child: Text.rich(
                TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
                    letterSpacing: -0.2,
                  ),
                  children: const [
                    TextSpan(text: 'Qu'),
                    TextSpan(
                      text: 'Al',
                      style: TextStyle(color: Color(0xFFE53935)),
                    ),
                    TextSpan(text: 'sar Premium Kullanım Koşulları'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 14),
            // Alt başlıklar + açıklama paragrafları
            for (final item in _items) ...[
              Text(
                item.$1,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                  letterSpacing: -0.1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                item.$2,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF555555),
                  height: 1.5,
                ),
              ),
              SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mastercard logosundaki iki halkadan biri (yarı saydam kesişim için).
class _MastercardCircle extends StatelessWidget {
  final Color color;
  final double opacity;
  const _MastercardCircle({required this.color, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18, height: 18,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}
