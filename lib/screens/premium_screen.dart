import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/pricing_service.dart';
import '../main.dart' show localeService;
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
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Column(
          children: [
            // Üst içerik — scroll edilebilir
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    // ═══════════════════════════════════════════════════════
                    //  Banner Görseli + Geri butonu üstünde
                    // ═══════════════════════════════════════════════════════
                    // Banner + Slogan — tek parça beyaz alan
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          // Banner görseli
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                ),
                                child: Image.asset(
                                  'lib/assets/9ejrn (1).jpg',
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              // Geri butonu
                              Positioned(
                                top: 8,
                                left: 10,
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.08),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                        Icons.arrow_back_ios_rounded,
                                        size: 16,
                                        color: Color(0xFF333333)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Slogan — aynı beyaz alan, arada boşluk/çizgi yok
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            child: Text(
                              localeService.tr('premium_slogan'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF111111),
                                height: 1.4,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ═══════════════════════════════════════════════════════
                    //  Fiyat Kartları — 1 Ay | 3 Ay | 12 Ay
                    // ═══════════════════════════════════════════════════════
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: IntrinsicHeight(
                        child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildPlanCard(
                              index: 0,
                              title: '1 ${localeService.tr("month_unit")}',
                              price: _plan.monthly,
                              priceSuffix: '/${localeService.tr("month_unit")}',
                              total: _plan.monthly,
                              oldPrice: _plan.monthlyOld,
                              discount: null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildPlanCard(
                              index: 1,
                              title: '3 ${localeService.tr("month_unit")}',
                              price: _plan.quarterlyPerMonth,
                              priceSuffix: '/${localeService.tr("month_unit")}',
                              total: _plan.quarterly,
                              oldPrice: null,
                              discount: null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildPlanCard(
                              index: 2,
                              title: '12 ${localeService.tr("month_unit")}',
                              price: _plan.yearlyPerMonth,
                              priceSuffix: '/${localeService.tr("month_unit")}',
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

                    const SizedBox(height: 10),

                    // Günlük fiyat + footer bilgisi
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          Text(
                            _dailyText(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFF555555),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _footerText(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: const Color(0xFF9CA3AF),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ═══════════════════════════════════════════════════════
                    //  Avantajlar başlığı
                    // ═══════════════════════════════════════════════════════
                    Padding(
                      padding: const EdgeInsets.only(left: 36, right: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          localeService.tr('advantages'),
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF333333),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Özellikler tablosu — turuncu→beyaz gradient
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFFFCC80), // koyu turuncu ton
                              Color(0xFFFFDDA6), // orta-koyu turuncu
                              Color(0xFFFFECC8), // orta turuncu
                              Color(0xFFFFF6E6), // açık turuncu
                              Colors.white,       // beyaz
                            ],
                            stops: [0.0, 0.2, 0.45, 0.7, 1.0],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 18, 20, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: Text(
                                      localeService.tr('features'),
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF6B7280),
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
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF9CA3AF),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Container(
                                    width: 72,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 5),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [_gold, _pink],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
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
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              height: 1,
                              color: const Color(0xFFE5E7EB),
                            ),
                            const SizedBox(height: 8),
                            _featureRow(localeService.tr('unlimited_models')),
                            _featureRow(localeService.tr('max_accuracy')),
                            _featureRow(localeService.tr('ad_free')),
                            _featureRowSub(localeService.tr('similar_q'),
                                localeService.tr('similar_q_desc')),
                            _featureRowSub(localeService.tr('match_cards'),
                                localeService.tr('match_cards_desc')),
                            _featureRowSub(
                                localeService.tr('info_cards'), localeService.tr('info_cards_desc')),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
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
                color: const Color(0xFFF0F2F5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
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
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFE8850C)],
                        ),
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _selectedPlan == 2
                              ? localeService.tr('free_trial_3day')
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
                  const SizedBox(height: 6),
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
          decoration: const BoxDecoration(
            color: Colors.white,
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
                    color: const Color(0xFFD1D5DB),
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
                  color: const Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 10),
              Container(height: 0.5, color: const Color(0xFFE5E7EB)),
              const SizedBox(height: 14),

              // Uygulama adı + açıklama
              Text(
                'QuAlsar ${_selectedPlan == 0 ? localeService.tr("monthly_label") : _selectedPlan == 1 ? localeService.tr("quarterly_label") : localeService.tr("yearly_label")} Premium',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'QuAlsar - ${localeService.tr("all_lessons")}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF6B7280),
                ),
              ),

              const SizedBox(height: 16),

              // Ayırıcı
              Container(height: 0.5, color: const Color(0xFFE5E7EB)),

              const SizedBox(height: 14),

              // Fiyat çerçevesi
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
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
                              color: const Color(0xFF333333),
                            ),
                          ),
                          Text(
                            _selectedPlan == 0 ? _plan.monthly : _selectedPlan == 1 ? _plan.quarterly : _plan.yearly,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111111),
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
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                          Text(
                            '${_plan.monthlyOld}/${_selectedPlan == 0 ? localeService.tr("month_unit") : _selectedPlan == 1 ? localeService.tr("three_months_unit") : localeService.tr("year_unit")}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Bilgi maddeleri
              _infoBullet(localeService.tr('cancel_anytime_info')),
              const SizedBox(height: 8),
              _infoBullet(localeService.tr('promo_reminder')),

              const SizedBox(height: 16),

              // Ayırıcı
              Container(height: 0.5, color: const Color(0xFFE5E7EB)),

              const SizedBox(height: 14),

              // Ödeme yöntemi
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
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
                  const SizedBox(width: 8),
                  Text(
                    '····4051',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF333333),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddressSheet(context);
                },
                child: Text(
                  localeService.tr('update_address'),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: const Color(0xFF3B82F6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 20),

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
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFE8850C)],
                    ),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Center(
                    child: Text(
                      'Devam et',
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
            decoration: const BoxDecoration(
              color: Colors.white,
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
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Adres Bilgileri',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111111),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Fatura adresinizi güncelleyin',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 16),
                _addressField('Ad Soyad'),
                const SizedBox(height: 10),
                _addressField('Adres'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _addressField('Şehir')),
                    const SizedBox(width: 10),
                    Expanded(child: _addressField('Posta Kodu')),
                  ],
                ),
                const SizedBox(height: 10),
                _addressField('Ülke'),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFE8850C)],
                      ),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Center(
                      child: Text(
                        'Kaydet',
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
      style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF111111)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: const Color(0xFF9CA3AF),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFFAFAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1),
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
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
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
          decoration: const BoxDecoration(
            color: Colors.white,
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
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Başarı ikonu
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 40,
                  color: Color(0xFF22C55E),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                localeService.tr('payment_success'),
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111111),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                localeService.tr('premium_activated'),
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 16),

              // Detaylar çerçevesi
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFFE5E7EB), width: 0.5),
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
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                          Text(
                            '${_selectedPlan == 0 ? localeService.tr("monthly_label") : _selectedPlan == 1 ? localeService.tr("quarterly_label") : localeService.tr("yearly_label")} Premium',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      height: 0.5,
                      color: const Color(0xFFE5E7EB),
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
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                          Text(
                            _selectedPlan == 0 ? _plan.monthly : _selectedPlan == 1 ? _plan.quarterly : _plan.yearly,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      height: 0.5,
                      color: const Color(0xFFE5E7EB),
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
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                          Text(
                            '12 Haz 2026',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

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
                    gradient: const LinearGradient(
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
            decoration: const BoxDecoration(
              color: Color(0xFF9CA3AF),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: const Color(0xFF6B7280),
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
    Future.delayed(const Duration(seconds: 4), () {
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

    return GestureDetector(
      onTap: () {
        setState(() => _selectedPlan = index);
        if (index == 2) _showDiscountBalloon(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF0FFF4) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF22C55E) : const Color(0xFFE8E8EE),
            width: selected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                  : const Color(0xFF9CA3AF).withValues(alpha: 0.10),
              blurRadius: selected ? 18 : 10,
              spreadRadius: selected ? 1 : 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
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
                    gradient: const LinearGradient(
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
              const SizedBox(height: 22),

            const SizedBox(height: 12),

            // Süre — rakam ve Ay ayrı satır
            Text(
              title.split(' ').first,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF333333),
                height: 1.1,
              ),
            ),
            Text(
              localeService.tr('month_unit'),
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF777777),
              ),
            ),

            const SizedBox(height: 10),

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
                      color: selected ? const Color(0xFF22C55E) : const Color(0xFF444444),
                      height: 1.1,
                    ),
                  ),
                  Text(
                    priceSuffix,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFAAAAAA),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // İnce ayırıcı çizgi
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              height: 0.5,
              color: const Color(0xFFE0E0E0),
            ),

            const SizedBox(height: 12),

            // Alt bilgi — toplam fiyat (çizgi altı)
            if (total != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${localeService.tr("total_label")} $total',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              )
            else
              const SizedBox(height: 12),

            const SizedBox(height: 10),

            // Seçim göstergesi + confetti ikonu
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  key: tickKey,
                  duration: const Duration(milliseconds: 200),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFD1D5DB),
                      width: 2,
                    ),
                    color: selected
                        ? const Color(0xFF22C55E)
                        : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 11, color: Colors.white)
                      : null,
                ),
                // Confetti ikonu — tik ile sağ çerçeve çizgisi arasında
                if (index == 2) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    key: _confettiKey,
                    onTap: () => _showDiscountBalloon(context),
                    child: const Text(
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
  //  Özellik Satırları
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _featureRow(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111111))),
          ),
          SizedBox(
              width: 52,
              child:
                  Icon(Icons.close_rounded, size: 20, color: _crossColor)),
          const SizedBox(width: 8),
          SizedBox(
              width: 72,
              child:
                  Icon(Icons.check_circle_rounded, size: 24, color: _checkColor)),
        ],
      ),
    );
  }

  Widget _featureRowSub(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF333333))),
                Text(sub,
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF555555),
                        height: 1.3)),
              ],
            ),
          ),
          SizedBox(
              width: 52,
              child:
                  Icon(Icons.close_rounded, size: 20, color: _crossColor)),
          const SizedBox(width: 8),
          SizedBox(
              width: 72,
              child:
                  Icon(Icons.check_circle_rounded, size: 24, color: _checkColor)),
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
      duration: const Duration(milliseconds: 350),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF222222),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
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
                      const SizedBox(height: 10),
                      Text(
                        localeService.tr('discount_50'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFEF6C00),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${localeService.tr("half_year_free")} 😍',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF333333),
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
