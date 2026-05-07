import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/pricing_service.dart';
import '../main.dart' show localeService;
import 'mock_payment_screen.dart';

import '../theme/app_theme.dart';
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
                                  discount: null,
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
                                  discount: '%50',
                                  tickKey: _tickKey12Ay,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: 8),

                      // Günlük fiyat + footer bilgisi
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
                              _featureRow('Dünyada ve ülkende yarış'),
                              _featureRow('Konu özetleri'),
                              _featureRow('Test soruları oluşturma'),
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
                  // Devam et butonu
                  GestureDetector(
                    onTap: () => _onContinue(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
                        child: Text(
                          _selectedPlan == 2
                              ? '7 Günlük Ücretsiz Denemeye Başla'
                              : localeService.tr('continue_btn'),
                          style: GoogleFonts.poppins(
                            fontSize: _selectedPlan == 2 ? 15 : 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onContinue(BuildContext context) {
    _showPaymentSheet(context);
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

              // Google Play başlığı
              Text(
                'Google Play', // platform adı — çevrilmez
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

              // Fiyat çerçevesi
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Color(0xFFFAFAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppPalette.border(context), width: 0.5),
                ),
                child: Column(
                  children: [
                    // Bugün satırı
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${localeService.tr("today")} · ${_selectedPlan == 0 ? "1 ${localeService.tr("month_unit")}" : _selectedPlan == 1 ? localeService.tr("three_months_unit") : "12 ${localeService.tr("month_unit")}"} ${localeService.tr("period")}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                          Text(
                            _selectedPlan == 0 ? _plan.monthly : _selectedPlan == 1 ? _plan.quarterly : _plan.yearly,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Başlangıç tarihi satırı
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${localeService.tr("start_date")}: 12 May 2026',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                          Text(
                            '${_plan.monthlyOld}/${_selectedPlan == 0 ? localeService.tr("month_unit") : _selectedPlan == 1 ? localeService.tr("three_months_unit") : localeService.tr("year_unit")}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppPalette.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 14),

              // Bilgi maddeleri
              _infoBullet(localeService.tr('cancel_anytime_info')),
              SizedBox(height: 8),
              _infoBullet(localeService.tr('promo_reminder')),

              SizedBox(height: 16),

              // Ayırıcı
              Container(height: 0.5, color: AppPalette.border(context)),

              SizedBox(height: 14),

              // Ödeme yöntemi
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppPalette.textPrimary(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Mastercard',
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '····4051',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddressSheet(context);
                },
                child: Text(
                  localeService.tr('update_address'),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Color(0xFF3B82F6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Devam et butonu
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _showPaymentMethodsSheet(context);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFE8850C)],
                    ),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Center(
                    child: Text(
                      localeService.tr('continue_btn'),
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

  void _showAddressSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
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
                Text(
                  localeService.tr('address_info'),
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  localeService.tr('update_billing_address'),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
                SizedBox(height: 16),
                _addressField(localeService.tr('full_name')),
                SizedBox(height: 10),
                _addressField(localeService.tr('address_hint')),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _addressField(localeService.tr('city_hint'))),
                    SizedBox(width: 10),
                    Expanded(child: _addressField(localeService.tr('postal_code_hint'))),
                  ],
                ),
                SizedBox(height: 10),
                _addressField(localeService.tr('country_hint')),
                SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFE8850C)],
                      ),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Center(
                      child: Text(
                        localeService.tr('save'),
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
          ),
        );
      },
    );
  }

  Widget _addressField(String hint) {
    return TextField(
      style: GoogleFonts.poppins(fontSize: 13, color: Color(0xFF111111)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: AppPalette.textSecondary(context),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: Color(0xFFFAFAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppPalette.border(context), width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppPalette.border(context), width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Color(0xFFF59E0B), width: 1),
        ),
      ),
    );
  }

  void _showPaymentMethodsSheet(BuildContext context) {
    final periodLabel = _selectedPlan == 0
        ? localeService.tr('monthly_label')
        : _selectedPlan == 1
            ? localeService.tr('quarterly_label')
            : localeService.tr('yearly_label');
    final planLabel = 'QuAlsar $periodLabel Premium';
    final amount = _selectedPlan == 0
        ? _plan.monthly
        : _selectedPlan == 1
            ? _plan.quarterly
            : _plan.yearly;

    // Sonraki yenileme tarihi
    final now = DateTime.now();
    final next = _selectedPlan == 0
        ? DateTime(now.year, now.month + 1, now.day)
        : _selectedPlan == 1
            ? DateTime(now.year, now.month + 3, now.day)
            : DateTime(now.year + 1, now.month, now.day);
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
    final renewalDate = '${next.day} ${months[next.month - 1]} ${next.year}';

    MockPaymentScreen.show(
      context,
      planLabel: planLabel,
      amount: amount,
      renewalDate: renewalDate,
    );
  }

  // ignore: unused_element
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
                            '12 ${localeService.tr('month_jun_short')} 2026',
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

            // Süre — rakam ve Ay ayrı satır
            Text(
              title.split(' ').first,
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
          color: AppPalette.isDark(context)
              ? Colors.black
              : Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset('assets/app_icon.png',
                                width: 22, height: 22),
                          ),
                          SizedBox(width: 14),
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
                          SizedBox(width: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset('assets/app_icon.png',
                                width: 22, height: 22),
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
                    color: AppPalette.isDark(context)
                        ? Color(0xFF2E2E2E)
                        : Color(0xFFEEF0F3),
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
      'İade talepleri, ödeme yapıldıktan sonraki ilk 7 gün içinde "Bize Ulaşın" sekmesinden veya support@qualsar.com adresinden iletilebilir. İadeler, yalnızca Premium özellikler henüz kullanılmamışsa ve 7 günlük süre aşılmamışsa değerlendirmeye alınır.',
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
