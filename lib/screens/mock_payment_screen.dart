import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart' show localeService;

class MockPaymentScreen extends StatelessWidget {
  const MockPaymentScreen({super.key});

  static void show(
    BuildContext context, {
    String planLabel = 'Premium',
    String amount = '',
    String renewalDate = '',
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: Container(
            color: Colors.white,
            child: _MockPaymentContent(
              scrollController: scrollController,
              planLabel: planLabel,
              amount: amount,
              renewalDate: renewalDate,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _MockPaymentContent(),
      ),
    );
  }
}

class _MockPaymentContent extends StatelessWidget {
  final ScrollController? scrollController;
  final String planLabel;
  final String amount;
  final String renewalDate;
  const _MockPaymentContent({
    this.scrollController,
    this.planLabel = 'Premium',
    this.amount = '',
    this.renewalDate = '',
  });

  void _showComingSoon(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Bilgi',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Ödeme sistemi çok yakında aktif edilecektir.',
          style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF333333)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Tamam',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A73E8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Drag handle (sadece bottom sheet modunda görünür)
        if (scrollController != null)
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        // Üst bar
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF202124)),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ödeme yöntemleri',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF202124),
                      ),
                    ),
                    Text(
                      'serhatdsme@gmail.com',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: const Color(0xFF5F6368),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 8),
              // Kayıtlı kartlar
              _cardTile(
                context,
                brand: 'MC',
                brandColors: const [Color(0xFFEB001B), Color(0xFFF79E1B)],
                label: 'Mastercard-4051',
              ),
              _cardTile(
                context,
                brand: 'MC',
                brandColors: const [Color(0xFFEB001B), Color(0xFFF79E1B)],
                label: 'Mastercard-7293',
              ),
              _cardTile(
                context,
                brand: 'VISA',
                brandColors: const [Color(0xFF1A1F71), Color(0xFF1A1F71)],
                label: 'Visa-8827',
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  localeService.tr('add_payment_method_google'),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF202124),
                  ),
                ),
              ),
              _optionTile(
                context,
                icon: Icons.phone_android,
                title: localeService.tr('mobile_payment'),
              ),
              _optionTile(
                context,
                icon: Icons.credit_card,
                title: localeService.tr('add_card'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _miniMastercard(),
                    const SizedBox(width: 6),
                    _miniVisa(),
                    const SizedBox(width: 6),
                    _miniTroy(),
                    const SizedBox(width: 6),
                    Text(
                      'diğerleri',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFF5F6368),
                      ),
                    ),
                  ],
                ),
              ),
              _optionTile(
                context,
                icon: Icons.confirmation_number,
                title: localeService.tr('use_code'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardTile(
    BuildContext context, {
    required String brand,
    required List<Color> brandColors,
    required String label,
  }) {
    return InkWell(
      onTap: () => _showComingSoon(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: brand == 'VISA' ? const Color(0xFF1A1F71) : Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
              ),
              child: Center(
                child: brand == 'MC'
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: 8,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEB001B),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF79E1B).withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'VISA',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF202124),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _showUpdateCardSheet(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  'Güncelle',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A73E8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: () => _showComingSoon(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: const Color(0xFF5F6368)),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF202124),
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  void _showUpdateCardSheet(BuildContext context) {
    final dateCtrl = TextEditingController();
    final cvcCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String country = 'Türkiye';
    String? dateErr, cvcErr, nameErr;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.95,
          minChildSize: 0.6,
          maxChildSize: 0.98,
          builder: (c, scrollController) {
            return StatefulBuilder(
              builder: (ctx2, setSheetState) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          20 + MediaQuery.of(ctx).viewInsets.bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Text(
                                'Kart ayrıntılarını onaylayın',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF202124),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 130,
                                  child: _centerLabeledField(
                                    label: localeService.tr('card_expiry'),
                                    controller: dateCtrl,
                                    errorText: dateErr,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [_ExpiryFormatter()],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 90,
                                  child: _centerLabeledField(
                                    label: localeService.tr('card_cvc'),
                                    controller: cvcCtrl,
                                    errorText: cvcErr,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(3),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 48),
                            _leftLabeledField(
                              label: localeService.tr('cardholder_name'),
                              controller: nameCtrl,
                              errorText: nameErr,
                              textCapitalization: TextCapitalization.words,
                            ),
                            const SizedBox(height: 20),
                            _countryField(
                              context: ctx2,
                              value: country,
                              onChanged: (v) =>
                                  setSheetState(() => country = v),
                            ),
                            const SizedBox(height: 20),
                            _paymentDisclaimer(context),
                          ],
                        ),
                      ),
                    ),
                    // Alt sabit "Devam Et" butonu
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(
                              color: Color(0xFFE5E7EB), width: 0.5),
                        ),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        20,
                        12,
                        20,
                        12 + MediaQuery.of(ctx).viewInsets.bottom,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A73E8),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                          ),
                          onPressed: () {
                            setSheetState(() {
                              dateErr = dateCtrl.text.trim().isEmpty
                                  ? 'Bu alanı doldurun'
                                  : null;
                              cvcErr = cvcCtrl.text.trim().isEmpty
                                  ? 'Bu alanı doldurun'
                                  : null;
                              nameErr = nameCtrl.text.trim().isEmpty
                                  ? 'Bu alanı doldurun'
                                  : null;
                            });
                            if (dateErr == null &&
                                cvcErr == null &&
                                nameErr == null) {
                              final rootNav =
                                  Navigator.of(context, rootNavigator: true);
                              Navigator.pop(ctx); // kart sheet'ini kapat
                              Navigator.pop(context); // ödeme yöntemleri sheet'i
                              rootNav.push(
                                MaterialPageRoute(
                                  builder: (_) => _PaymentProcessingPage(
                                    planLabel: planLabel,
                                    amount: amount,
                                    renewalDate: renewalDate,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Text(
                            'Devam Et',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
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
      },
    );
  }

  Widget _centerLabeledField({
    required String label,
    required TextEditingController controller,
    String? errorText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    const blue = Color(0xFF1A73E8);
    const red = Color(0xFFD93025);
    final hasError = errorText != null && errorText.isNotEmpty;
    final borderColor = hasError ? red : blue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 52,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 1.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  textAlign: TextAlign.center,
                  cursorColor: blue,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF202124),
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  ),
                ),
              ),
              Positioned(
                top: -9,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: borderColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              errorText,
              style: GoogleFonts.poppins(fontSize: 11, color: red),
            ),
          ),
      ],
    );
  }

  Widget _leftLabeledField({
    required String label,
    required TextEditingController controller,
    String? errorText,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputType? keyboardType,
  }) {
    const blue = Color(0xFF1A73E8);
    const red = Color(0xFFD93025);
    final hasError = errorText != null && errorText.isNotEmpty;
    final borderColor = hasError ? red : blue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor, width: 1.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: controller,
                  cursorColor: blue,
                  keyboardType: keyboardType,
                  textCapitalization: textCapitalization,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF202124),
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Positioned(
                top: -9,
                left: 10,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: borderColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errorText,
              style: GoogleFonts.poppins(fontSize: 11, color: red),
            ),
          ),
      ],
    );
  }

  Widget _countryField({
    required BuildContext context,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    const blue = Color(0xFF1A73E8);
    return SizedBox(
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: () async {
              final selected = await _showCountryPicker(context, value);
              if (selected != null) onChanged(selected);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: blue, width: 1.2),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF202124),
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down,
                      color: Color(0xFF5F6368), size: 26),
                ],
              ),
            ),
          ),
          Positioned(
            top: -9,
            left: 10,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Ülke',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentDisclaimer(BuildContext context) {
    const baseStyle = TextStyle(
      fontSize: 12,
      color: Color(0xFF5F6368),
      height: 1.5,
    );
    final linkStyle = GoogleFonts.poppins(
      fontSize: 12,
      color: const Color(0xFF1A73E8),
      fontWeight: FontWeight.w500,
      height: 1.5,
    );
    final normal = GoogleFonts.poppins().copyWith(
      fontSize: 12,
      color: const Color(0xFF5F6368),
      height: 1.5,
    );
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: 'Devam ederek ', style: normal),
          TextSpan(
            text: 'Google Payments hizmet şartları',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _LegalTextPage(
                      title: 'Hizmet Şartları',
                      body: _kGooglePaymentsTerms,
                    ),
                  ),
                );
              },
          ),
          TextSpan(text: ' hükümlerini kabul etmiş olursunuz. ', style: normal),
          TextSpan(
            text: 'Gizlilik Bildirimi',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const _LegalTextPage(
                      title: 'Gizlilik Uyarısı',
                      body: _kGooglePaymentsPrivacy,
                    ),
                  ),
                );
              },
          ),
          TextSpan(
            text:
                ' hükümlerinde verilerinizin nasıl kullanıldığı açıklanır.',
            style: normal,
          ),
        ],
      ),
    );
  }

  Future<String?> _showCountryPicker(
      BuildContext context, String current) {
    const countries = <String>[
      'Türkiye', 'Afganistan', 'Almanya', 'Amerika Birleşik Devletleri',
      'Andorra', 'Angola', 'Antigua ve Barbuda', 'Arjantin', 'Arnavutluk',
      'Avustralya', 'Avusturya', 'Azerbaycan', 'Bahamalar', 'Bahreyn',
      'Bangladeş', 'Barbados', 'Belarus', 'Belçika', 'Belize', 'Benin',
      'Birleşik Arap Emirlikleri', 'Birleşik Krallık', 'Bolivya',
      'Bosna-Hersek', 'Botsvana', 'Brezilya', 'Brunei', 'Bulgaristan',
      'Burkina Faso', 'Burundi', 'Butan', 'Cezayir', 'Cibuti', 'Çad',
      'Çek Cumhuriyeti', 'Çin', 'Danimarka', 'Dominik Cumhuriyeti',
      'Dominika', 'Doğu Timor', 'Ekvador', 'Ekvator Ginesi', 'El Salvador',
      'Endonezya', 'Eritre', 'Ermenistan', 'Estonya', 'Esvatini', 'Etiyopya',
      'Fas', 'Fiji', 'Fildişi Sahili', 'Filipinler', 'Filistin', 'Finlandiya',
      'Fransa', 'Gabon', 'Gambiya', 'Gana', 'Gine', 'Gine-Bissau',
      'Grenada', 'Guatemala', 'Guyana', 'Güney Afrika', 'Güney Kore',
      'Güney Sudan', 'Gürcistan', 'Haiti', 'Hırvatistan', 'Hindistan',
      'Hollanda', 'Honduras', 'Irak', 'İran', 'İrlanda', 'İspanya',
      'İsrail', 'İsveç', 'İsviçre', 'İtalya', 'İzlanda', 'Jamaika',
      'Japonya', 'Kamboçya', 'Kamerun', 'Kanada', 'Karadağ', 'Katar',
      'Kazakistan', 'Kenya', 'Kıbrıs', 'Kırgızistan', 'Kiribati',
      'Kolombiya', 'Komorlar', 'Kongo Cumhuriyeti',
      'Kongo Demokratik Cumhuriyeti', 'Kosova', 'Kosta Rika', 'Kuveyt',
      'Kuzey Kore', 'Kuzey Makedonya', 'Küba', 'Laos', 'Lesotho', 'Letonya',
      'Liberya', 'Libya', 'Liechtenstein', 'Litvanya', 'Lübnan',
      'Lüksemburg', 'Macaristan', 'Madagaskar', 'Malavi', 'Maldivler',
      'Malezya', 'Mali', 'Malta', 'Marshall Adaları', 'Meksika',
      'Mikronezya', 'Mısır', 'Moğolistan', 'Moldova', 'Monako',
      'Moritanya', 'Mozambik', 'Myanmar', 'Namibya', 'Nauru', 'Nepal',
      'Nijer', 'Nijerya', 'Nikaragua', 'Norveç', 'Orta Afrika Cumhuriyeti',
      'Özbekistan', 'Pakistan', 'Palau', 'Panama', 'Papua Yeni Gine',
      'Paraguay', 'Peru', 'Polonya', 'Portekiz', 'Romanya', 'Ruanda',
      'Rusya', 'Saint Kitts ve Nevis', 'Saint Lucia',
      'Saint Vincent ve Grenadinler', 'Samoa', 'San Marino',
      'Sao Tome ve Principe', 'Senegal', 'Seyşeller', 'Sırbistan',
      'Sierra Leone', 'Singapur', 'Slovakya', 'Slovenya', 'Solomon Adaları',
      'Somali', 'Sri Lanka', 'Sudan', 'Surinam', 'Suriye', 'Suudi Arabistan',
      'Şili', 'Tacikistan', 'Tanzanya', 'Tayland', 'Tayvan', 'Togo',
      'Tonga', 'Trinidad ve Tobago', 'Tunus', 'Tuvalu', 'Türkmenistan',
      'Uganda', 'Ukrayna', 'Umman', 'Uruguay', 'Ürdün', 'Vanuatu',
      'Vatikan', 'Venezuela', 'Vietnam', 'Yemen', 'Yeni Zelanda',
      'Yunanistan', 'Zambiya', 'Zimbabve',
    ];
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (c, setS) {
            final filtered = query.isEmpty
                ? countries
                : countries
                    .where((e) =>
                        e.toLowerCase().contains(query.toLowerCase()))
                    .toList();
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, sc) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ülke seçin',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF202124),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Color(0xFF5F6368)),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: TextField(
                        onChanged: (v) => setS(() => query = v),
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Ara...',
                          hintStyle: GoogleFonts.poppins(
                              fontSize: 14, color: const Color(0xFF9AA0A6)),
                          prefixIcon: const Icon(Icons.search,
                              color: Color(0xFF5F6368)),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Color(0xFF1A73E8), width: 1.4),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    Expanded(
                      child: ListView.builder(
                        controller: sc,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final name = filtered[i];
                          final selected = name == current;
                          return InkWell(
                            onTap: () => Navigator.pop(ctx, name),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: selected
                                            ? const Color(0xFF1A73E8)
                                            : const Color(0xFF202124),
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(Icons.check,
                                        color: Color(0xFF1A73E8), size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniMastercard() {
    return SizedBox(
      width: 26,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Color(0xFFEB001B),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFFF79E1B).withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniVisa() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F71),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        'VISA',
        style: GoogleFonts.poppins(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _miniTroy() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE30613),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        'troy',
        style: GoogleFonts.poppins(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    String trimmed = digits.length > 4 ? digits.substring(0, 4) : digits;
    String formatted;
    if (trimmed.length >= 3) {
      formatted = '${trimmed.substring(0, 2)}/${trimmed.substring(2)}';
    } else if (trimmed.length == 2) {
      // Kullanıcı yazıyor: 2 hane dolduğunda otomatik '/' ekle.
      // Sadece metin uzuyorsa ekle, silme sırasında ekleme.
      final typing = newValue.text.length >= oldValue.text.length;
      formatted = typing ? '$trimmed/' : trimmed;
    } else {
      formatted = trimmed;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _LegalTextPage extends StatelessWidget {
  final String title;
  final String body;
  const _LegalTextPage({required this.title, required this.body});

  // Ana başlık (H2) olarak render edilecek, numaralı olmayan bilinen başlıklar.
  static const Set<String> _h2Known = {
    'Topladığımız bilgiler',
    'Topladığımız bilgileri nasıl kullanırız?',
    'Paylaştığımız bilgiler',
    'Bilgilerinizi güvende tutma',
  };

  // Alt başlık (H3) olarak render edilecek, bilinen başlıklar.
  static const Set<String> _h3Known = {
    'Kayıt bilgileri',
    'Üçüncü taraflardan alınan bilgiler',
    'İşlem bilgileri',
  };

  static final RegExp _h2Re = RegExp(r'^\d+\.\s+\S');
  static final RegExp _h3Re = RegExp(r'^\d+\.\d+\s+\S');
  static final RegExp _dateRe = RegExp(
      r'^(\d{1,2}\s+(Ocak|Şubat|Mart|Nisan|Mayıs|Haziran|Temmuz|Ağustos|Eylül|Ekim|Kasım|Aralık)\s+\d{4}|Son değiştirilme tarihi:.*)$');

  @override
  Widget build(BuildContext context) {
    const textColor = Color(0xFF202124);
    const mutedColor = Color(0xFF5F6368);

    final lines = body.split('\n');
    final widgets = <Widget>[];
    bool titleSeen = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 10));
        continue;
      }

      // İlk dolu satır = Ana başlık (H1)
      if (!titleSeen) {
        titleSeen = true;
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            trimmed,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1.25,
            ),
          ),
        ));
        continue;
      }

      // Tarih / alt bilgi
      if (_dateRe.hasMatch(trimmed)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            trimmed,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: mutedColor,
            ),
          ),
        ));
        continue;
      }

      // H2 — "1. …", "2. …" veya bilinen başlıklar
      if (_h2Re.hasMatch(trimmed) || _h2Known.contains(trimmed)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(
            trimmed,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1.3,
            ),
          ),
        ));
        continue;
      }

      // H3 — "3.1 …", "6.2 …" veya bilinen alt başlıklar
      if (_h3Re.hasMatch(trimmed) || _h3Known.contains(trimmed)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(
            trimmed,
            style: GoogleFonts.poppins(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Colors.black,
              height: 1.35,
            ),
          ),
        ));
        continue;
      }

      // Normal paragraf
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          line,
          style: GoogleFonts.poppins(
            fontSize: 13,
            height: 1.55,
            color: textColor,
          ),
        ),
      ));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widgets,
          ),
        ),
      ),
    );
  }
}

const String _kGooglePaymentsTerms = '''Google Payments - Hizmet Şartları - Alıcı (TR)
1 Mayıs 2019

İşbu Hizmet Şartları, tamamen Google LLC ("Google") şirketine ait bir yan kuruluş olan Google Payment Corp. ile sizin aranızdaki bir yasal sözleşmeyi teşkil eder. Ürün, mal veya hizmet alıcısı olarak Google Payments'a erişiminiz ve Google Payments'ı kullanımınız bu sözleşmeye tabidir. Bu sözleşmeyi kabul edip etmeyeceğinize karar vermeden ve kayıt işlemine devam etmeden önce lütfen bu Hizmet Şartları'nın tamamını inceleyin.

Google Payments hesabınıza kaydedilen Ödeme Araçları size Google Pay markası altında sunulabilir ancak aşağıda açıklanan hizmetler ve tekliflerle birlikte kullanıldığında bu Hizmet Şartları tarafından yönetilmeye devam edebilir.

KAYIT SAYFASINDAKİ "KABUL ET VE DEVAM ET" DÜĞMESİNİ TIKLAYARAK BU HİZMET ŞARTLARI'NA TABİ OLMAYI KABUL ETMİŞ OLURSUNUZ.

1. Belirli Tanımlanmış Terimler
Aşağıda tanımlanan terimler bu Hizmet Şartları'nda yer alır.

"Siz", "size" veya "Alıcı": Ödeme İşlemleri yapmak için Hizmete başvuran, Hizmeti kullanmak için kaydolan veya Hizmeti kullanan bir Müşteri.
Operatör Faturalandırması: GPC'nin, Satıcı adına Alıcının Operatör Faturalandırması Hesabına faturalandırma amacıyla Operatöre bir Ödeme İşlemi göndermesi sayesinde size ödeme işleminin sunulması.
Operatör: Bir Operatör Faturalandırma Hesabı sunan, GPC tarafından onaylanmış bir cep telefonu operatörü.
Operatör Faturalandırma Hesabı: Belirli Ödeme İşlemlerinin ödenmesi için Hizmete kaydolduğunuz Operatörünüz tarafından size sağlanan aylık veya başka dönemsel faturalandırma hesabı.
Müşteri: Alıcı veya Satıcı olarak Hizmete kaydolmuş bir kişi.
Satıcı: Alıcıların Ödeme İşlemlerini yapmak için Hizmeti kullanan bir Müşteri.
Google İnternet Siteleri: GPC, Google veya Google ile ilişkili ya da iş ortağı olan bir şirketin internet sitesi sayfaları.
Ödeme Aracı: Ödeme İşlemlerini kolaylaştırmak için Müşteri tarafından Hizmete kaydedilen kredi kartı veya banka kartı ya da Operatör Faturalandırma Hesabı. Ödeme Aracı, Hizmetin kullanıma sunulduğu bir ülkedeki fatura adresi ile ilişkilendirilmelidir.
Ödeme İşlemi: Satın Alma Tutarının, bir Alıcının Ödeme Aracına borçlandırılması ya da yansıtılması ve tutarların bir Satıcıya alacaklandırılması ile sonuçlanan, Hizmet aracılığıyla bir ödeme yapılması.
Ürün: Bir Alıcının Hizmeti kullanmak için ödeme yapabileceği, satış amaçlı listelenen herhangi bir ürün, mal veya hizmet.
Satın Alma Tutarı: Dolar olarak bir Ürün için ödenecek Ödeme İşlemi tutarı ve varsa ilgili ücretler, vergiler veya gönderim bedelleri.
Hizmet: Satıcı adına Ödeme İşlemleri yapılmasını kolaylaştıran, bu Hizmet Şartları'nda açıklanan Google Payments hizmeti.
"GAZ": Google Arizona LLC.
"GPC", "biz" veya "bize": Google Payment Corporation.

2. Kayıt Koşulları
Hizmeti kullanmak için Hizmet kaydı internet sayfalarında gerekli tüm bilgi bölümlerini doldurmalısınız. Ödeme İşlemlerini yapmak ve ücretler ile Hizmeti kullanımınızdan kaynaklanan diğer borçları ödemek için Ödeme Aracı olarak geçerli bir kredi kartı veya banka kartı ya da Operatör Faturalandırma Hesabı kaydetmelisiniz. Güncel, eksiksiz ve doğru bilgiler sunmalı ve bunların güncel ve doğru kalmasını sağlamalısınız. Hizmeti kullanmaya devam etmenin bir koşulu olarak ek bilgi sunmanızı veya Hizmeti kullanmaya devam etmenize izin verilip verilmeyeceğinin belirlenmesine yardımcı olmanızı isteyebiliriz.

İlgili kart birliği veya Operatör kuralları (hangisi geçerliyse) gereğince, bir ödeme yetkisi ve/veya Ödeme Aracına ödeme yetkisi, düşük tutarda bir dolar kredisi ve/veya borcu gönderme talebi de dahil ancak bunlarla sınırlı olmamak üzere, aracı veren finansal kuruluşla ve/veya Operatörle (hangisi geçerliyse) birlikte Ödeme Aracınızın iyi durumda olduğunu onaylamak için bizi yetkilendirirsiniz. Bize, Hizmete kaydınızı veya Hizmeti kullanmaya devam etmenizi değerlendirmek için uygun gördüğümüz durumlarda zaman zaman bir kredi raporu alma ve/veya krediyle ilgili ya da başka konularda bilgi edinmeye yönelik sorgularda bulunma yetkisi de verirsiniz.

Tamamen kendi mutlak takdirimizle, burada feragat edilmeyen ve ilgili herhangi bir yasanın gerektirdiği herhangi bir bildirim dışında bildirimde bulunmaksızın veya bulunarak ya da gerekçeli veya gerekçesiz olarak mevcut kayıtları onaylamayı reddedebilir veya sonlandırabiliriz.

Alıcılara ilişkin bu Hizmet Şartları'nı kabul etmekle aşağıdakileri beyan etmiş olursunuz:

• 13-17 yaş arasında olduğunuzu ve ilgili yasalara tabi olarak ve Google'ın takdirine göre, Google Play'de satın almaya uygun olan seçili ürünler için Google Play Hediye Kartı bedelini tek ve sınırlı bir şekilde kullanmak amacıyla bir Google Payments hesabı oluşturduğunuzu;
• veya 18 yaşında (veya ülkenizde reşit olma yaşına varılmış başka bir yaşta) veya üzerinde olduğunuzu ve
• GPC ve Satıcılarla yasal olarak bağlayıcı bir sözleşme yapabildiğinizi.

Bir ticari işletmeyseniz aşağıdakileri de beyan edersiniz:

• Faaliyet gösterdiğiniz ülke veya ülkelerde iş yapmak üzere usulünce yetkili olduğunuzu ve
• Çalışanlarınızın, görevlilerinizin, temsilcilerinizin ve Hizmete erişimi bulunan diğer aracıların, Hizmete erişmek ve bu Hizmet Şartları ile kullanıcı adınız ve şifreniz kullanılarak yapılan tüm işlemlerle sizi yasal olarak bağlayıcı kılmak üzere usulünce yetkili olduklarını.

3. İşlem Yapma Hizmeti

3.1 Ödeme İşlemi Yapılması
Hizmet, bir Alıcı ile Satıcı arasındaki satın alma işlemine ilişkin bir ödeme gerçekleştirmek için Ödeme İşlemleri yapılmasını kolaylaştırır. Hizmet, Ödeme Araçları ve gönderim bilgileri gibi Alıcılardan gelen bilgileri saklar ve uygun kredi kartı veya banka kartı ağı ya da katılımcı bir Operatör (hangisi geçerliyse) aracılığıyla Satıcılar adına Ödeme İşlemleri yapar. GPC, tamamen kendi mutlak takdir yetkisine bağlı olarak belirlendiği şekilde, sahtekarlık, suistimal içerebilecek veya ilgili yasaları, Alıcılara ilişkin Hizmet Şartları'nı ya da diğer ilgili GPC veya Hizmet politikalarını ihlal edebilecek işlemlerin ya da şüpheli işlemlerin ödeme işlemini geciktirebilir. Alıcı, bir Ödeme İşlemi yapılması için gerekli olduğu şekilde Alıcının Ödeme Aracına yansıtma ya da borçlandırma yapılması yetkisini verir. Alıcı ayrıca iptaller, geri ödemeler veya düzenlemelerle ile ilgili olarak Alıcının Ödeme Aracına kredi ekleme yetkisi de verir.

Ürün satın alımlarınızın, GPC, Google veya GPC'nin satış ortakları ile değil, Satıcı ile sizin aranızdaki işlemler olduğunu kabul eder ve onaylarsınız. GPC, Ürün satın alımınızda taraf değildir ve bir Google İnternet Sitesi'nde yer alan Ürün listesindeki gibi açıkça belirtilmedikçe GPC, Google veya diğer GPC satış ortakları, herhangi bir Ödeme İşlemi ile bağlantılı bir alıcı ya da satıcı değildir.

Ayrıca Satıcı ve Satıcı adına hareket eden GPC, önceki bir Ödeme İşleminin ödeme ağı tarafından reddedilmesi veya iade edilmesi durumunda, bir veya daha fazla kez işlenmek üzere ödeme ağına satın alınan bir ürün için tekrar Ödeme İşlemi gönderebilir.

3.2 Operatör Faturalandırması
Google Payments'ı kabul eden belirli Satıcılar, satın alma işleminizi Operatör Faturalandırması Hesabınıza faturalandırmanıza izin verebilir. Google Payments aracılığıyla Operatör Faturalandırmasını kullandığınızda şu ek şartlar geçerlidir:

• Google Payments, Operatör Faturalandırması Hesabınızı bir ödeme seçeneği olarak kaydettirmek için cep telefonu numaranızı ve o numarayla ilişkilendirilmiş Operatör Faturalandırması Hesabı'nın ad bilgisi ile posta kodu dahil fatura adresi bilgilerini ister. Operatörünüzün, Google Payments'a bu bilgileri sağlamasına izin verirsiniz ve Operatör Faturalandırmasına kaydolma işlemi sırasında bu bilgileri inceler ve her türlü yanlışlığı düzeltirsiniz.
• Operatör Faturalandırması ile bir işlem için ödeme yapmayı tercih ettiğinizde borç ve kredileri Operatörünüze göndermesi için Satıcıya ve Satıcının işlemcisi olarak GPC'ye ve Ödeme İşlemini gerçekleştirmek için gerekli olduğu şekilde, bu borç ve kredileri Operatör Faturalandırması Hesabınıza yansıtması ya da söz konusu Ödeme İşleminin iptal, geri ödeme veya düzeltme işlemlerini gerçekleştirmesi için Operatörünüze yetki verirsiniz.
• Google Play'deki belirli satıcılardan uyumlu cihazınızla ve bu cihazınız için uygulamalar ("Uygulamalar") satın almak için Operatör Faturalandırmasını kullanabilirsiniz. Bu Uygulamalar Operatörünüz, Google, GPC veya Google Play tarafından satılmaz. İlgili Uygulamanın Satıcısını satın alma noktasında belirleyebilirsiniz.
• Operatör Faturalandırması yöntemiyle yapılan satın alma işlemleri aynı zamanda Operatör Faturalandırması Hesabının şartlarına ve koşullarına da tabidir. Operatör Faturalandırması yöntemini kullanımınız sonucunda Operatör Faturalandırması Hesabınızın şartları ve koşulları gereği ortaya çıkabilecek ödemelerden ve ilişkili ücretlerden siz sorumlu olursunuz.
• Operatör Faturalandırması Hesabınıza faturalanan ödemeler ve ücretler hakkında sorularınız varsa Operatör'ün müşteri hizmetleriyle iletişime geçebilirsiniz. Google Payments ile ilgili konular hakkında bir sorunuz olursa Google Payments müşteri hizmetleriyle iletişime geçebilirsiniz.
• Operatör Faturalandırması ile satın alınan ürünlerle (ör. Uygulamalar) ilgili destek sorularını doğrudan uygulamayı satın aldığınız Satıcıya yöneltmelisiniz.
• Hiçbir Operatör, Google, GPC veya Google Play; Uygulama aracılığıyla erişim sağlayabileceğiniz herhangi bir içerik veya internet sitesi ya da Operatörünüzün planı, hizmeti veya faturalandırmasını etkileyebilecek her türlü değişiklik dahil olmak üzere herhangi bir Uygulamanın cihazınızın işlevselliğini etkileyebileceği değişiklikler, Uygulamayı kullanırken karşılaşabileceğiniz üçüncü taraf reklamları, geri ödemeler ya da indirme, yükleme, kullanma, iletim hatası, kesinti veya gecikme dahil, Operatör Faturalandırması ile satın alınan herhangi bir üründen (bir Uygulama dahil) sorumlu değildir.

3.3 Abonelikler/Yinelenen Satın Alma İşlemleri
İşleme Hizmeti'nin size abonelikler için ödeme yapma olanağı sunması durumunda belirli bir abonelik satın alma işlemine yönelik aboneliğiniz "Kabul et ve satın al" (veya eşdeğeri bir ifade) öğesini tıkladığınızda başlatılır. Bu, yinelenen bir faturalandırma işlemidir ve tarafınızdan belirli aralıklarla ve otomatik olarak ücret alınır. Aksi belirtilmediği sürece aboneliğiniz ve alakalı faturalandırma yetkilendirmesi tarafınızdan iptal edilmedikçe hep devam edecektir.

"Kabul et ve satın al" (veya eşdeğeri bir ifade) öğesini tıkladığınızda geçerli Satıcıya, Satın Alma Tutarı karşılığında abonelik için seçtiğiniz Ödeme Aracını belirlenmiş her fatura döneminde faturalandırma yetkisi verirsiniz. Ayrıca, Satıcının herhangi bir nedenle belirlenmiş Ödeme Aracınızdan ödeme alamaması durumunda, geçerli Satıcıya Satın Alma Tutarını alternatif Ödeme Aracından alma yetkisini verirsiniz (Google Payments Hesabınızda alternatif bir Ödeme Aracı seçtiyseniz). Şartlar ve Koşullarda aksi belirtilmediği takdirde, aboneliğinizi iptal edene kadar Satın Alma Tutarı, her fatura döneminde belirlenmiş Ödeme Aracınızdan veya alternatif Ödeme Aracınızdan (varsa) alınmaya devam eder.

Satın Alma Tutarı, abonelik süresi boyunca Satıcı tarafından değiştirilebilir. Ödeme Aracınız, aboneliğin satın alındığı tarihe bağlı olarak her dönem faturalandırılır. Aboneliği burada açıklanan süreci takip ederek dilediğiniz zaman iptal edebilirsiniz ancak iptal işlemi, geçerli fatura döneminin sonuna kadar geçerli olmaz.

Tamamen kendi takdir yetkimize bağlı olarak geri ödeme yapma veya kredi gönderme hakkımızı saklı tutarız. Geri ödeme yaptığımızda veya kredi gönderdiğimizde, gelecekte aynı veya benzer bir geri ödeme yapma yükümlülüğü altına girmeyiz.

4. İzin Verilen Ödeme İşlemleri
Bu Hizmeti yalnızca bir Satıcıdan meşru, gerçek bir Ürün satışı yoluyla satın alınan bir Ürünün Ödeme İşlemini yapmak için kullanabilirsiniz. Hizmet, bir Ürün satın alımıyla ilgili olmayan bir Ödeme İşlemi yapmak veya başka bir şekilde bir Alıcı ile Satıcı arasında para aktarımı yapmak için kullanılamaz. Hizmet, Satıcılardan nakit avans almak veya nakit benzerlerinin (ör. seyahat çekleri, ön ödemeli kartlar, posta çekleri vb.) satın alımını kolaylaştırmak için kullanılamaz. Hizmeti, yasa dışı mal veya hizmetlerin satılması veya alışverişinin yapılması ya da başka herhangi bir temel yasa dışı işlem ile bağlantılı Ödeme İşlemleri yapmak için kullanamazsınız.

Hizmeti, işbu Hizmet Şartları'nı, Hizmet ile ilgili diğer politikaları veya kuralları ya da ilgili yasaları ihlal eden Ürünlere ilişkin Ödeme İşlemleri yapmak için kullanmayacağınızı kabul edersiniz. Bu Hizmet kullanılarak ödeme yapılamayacak olan Ürünleri ve diğer işlemleri belirten geçerli politika burada sunulmuştur. Bu sınırlamalara uyulmaması, Hizmet kullanımınızın askıya alınmasına veya sonlandırılmasına neden olabilir.

5. Ödeme Aracı Ayrıntılarının Üçüncü Taraflara Verilmesi
Tarafınızca talep edildiğinde, üçüncü tarafın Size tedarik edeceği mal veya hizmetlerin ücretini Ödeme Aracına yansıtması için GPC, Ödeme Aracınızın ayrıntılarını ve ilgili bilgileri söz konusu üçüncü tarafa verebilir. Bu tür durumlarda, Ödeme Aracı ayrıntılarını söz konusu üçüncü tarafa verdikten sonra GPC'nin, bu üçüncü tarafla yaptığınız işlemlere ayrıca müdahalesi olmaz. Bu bir Ödeme İşlemi değildir. Geri ödemeler ve itirazlar dahil, bu tür üçüncü taraf işlemlerine yönelik her türlü sorun ile ilgili olarak doğrudan üçüncü taraf veya Ödeme Aracı sağlayıcınız ile iletişime geçmelisiniz.

6. Google Play Hediye Kartları

6.1 Uygunluk ve Kullanım
Google Play Hediye Kartları ("Hediye Kartları") yalnızca 13 veya üzeri yaşta olan ve Kanada'da ikamet eden kullanıcılar için geçerlidir. Hediye Kartları, kullanıcının edindiği anda Hediye Kartının üzerinde belirtilen kuruluşun kimliğine bakılmaksızın GAZ tarafından verilir. Google Play Hediye Kartını kullanabilmek için internet erişiminizin olması ve bir Google Payments hesabı oluşturmanız gerekir. 13-17 yaş arasındaki kullanıcıların oluşturduğu Google Payments kaydı, yalnızca Google Play'deki Hediye Kartlarının kullanımıyla sınırlıdır.

6.2 Sınırlamalar
Play Hediye Kartı nakit olarak veya başka kartlar yerine kullanılamaz, yeniden yükleme veya kart için geri ödeme talep edilemez, Google Payments Hesabınızdaki diğer bakiyelerle birleştirilemez ve yasaların gerektirdiği durumlar dışında bir değer karşılığında yeniden satılamaz, takas edilemez ya da devredilemez. Sipariş tutarının, Play Hediye Kartı veya Store Kredisi tutarını aşması halinde işlemi tamamlamak için başka bir geçerli Ödeme Aracı seçilmedikçe ya da bakiyeye daha fazla değer eklenmedikçe sipariş işlemi reddedilir.

6.3 Sahtekarlık
Hediye Kartının kaybedilmesi, çalınması, tahrip edilmesi veya izniniz olmadan kullanılması durumlarında sorumluluk üstlenmeyiz. Hile yoluyla elde edilen bir Hediye Kartının kullanılması ve/veya Google Play'de satın alma işlemi gerçekleştirmek üzere bu Hediye Kartından yararlanılması halinde müşteri hesaplarını askıya alma ya da kapatma ve alternatif ödeme şekilleriyle faturalandırma hakkına sahibiz.

7. Hizmet Kullanımıyla İlgili Sınırlamalar
Belirli dönemlerde yapılabilecek Ödeme İşlemlerinin sayısında ya da dolar tutarında bireysel veya toplu işlem sınırlamaları dahil olmak üzere Hizmetin kullanımıyla ilgili genel uygulamalar ve sınırlamalar getirebiliriz. İşlem saatleri, Hizmetin kullanılabilirliği veya herhangi bir Hizmet özelliği dahil olmak üzere, dilediğimiz zaman herhangi bir Hizmet özelliğini değiştirme, askıya alma veya sonlandırma hakkını saklı tutarız. Ayrıca, bildirimde bulunmaksızın ve sorumluluk yüklenmeksizin belirli Hizmet özelliklerine sınırlar koyma veya Hizmetin bir kısmına ya da tamamına erişimi kısıtlama hakkını da saklı tutarız. Alıcıya veya Satıcıya önceden bildirimde bulunmaksızın herhangi bir Ödeme İşleminin yapılmasını reddedebiliriz.

Hizmet kapsamındaki özelliklerin kesintisiz veya hatasız olacağı konusunda garanti vermeyiz ve herhangi bir Hizmet kesintisinden sorumlu olmayız.

Tamamen kendi mutlak takdir yetkimize bağlı olarak, dilediğimiz zaman Hizmet kullanımınızı sınırlandırabilir veya askıya alabiliriz. Hizmet kullanımınızı askıya almamız durumunda, elektronik posta ile tarafınıza bilgilendirme yaparız. Hizmet kullanımınızın askıya alınması, işbu Hizmet Şartları uyarınca söz konusu askıya alma işleminden önce veya sonra ortaya çıkan haklarınızı ve yükümlülüklerinizi etkilemez.

8. Kullanıcı Adı ve Şifre Bilgileri
Şunlardan sorumlusunuzdur:

(a) kullanıcı adınızın ve şifrenizin gizliliğini koruma,
(b) bu kullanıcı adına veya şifreye erişim verdiğiniz ya da başka bir şekilde bu kullanıcı adını veya şifreyi kullandırdığınız kişiler tarafından gerçekleştirilen tüm işlemler ve
(c) kullanıcı adınızın ve şifrenizin kullanımından ya da kötüye kullanımından kaynaklanan tüm sonuçlar.

Kullanıcı adınızın veya şifrenizin yetkisiz kullanımını veya Hizmetle ilgili bilgi sahibi olduğunuz başka herhangi bir güvenlik ihlalini anında bize bildirmeyi kabul edersiniz.

Alıcı bir ticari işletme ise; tüm görevlilere, çalışanlara, aracılara, temsilcilere ve Hizmetin kullanıcı adına/şifresine erişimi olan diğer kişilere Hizmeti kullanma yetkisi vereceğini ve bunun yasal olarak Alıcının kendisini bağlayacağını kabul eder.

9. Gizlilik
Hizmet ile bağlantılı olarak bize sunulan kişisel bilgilerin, Hizmet Gizlilik Politikası'na tabi olduğunu anlar ve kabul edersiniz.

10. Elektronik İletişim Araçlarının Kullanımı
Kayıt sırasında sunduğunuz e-posta adresi ve diğer elektronik iletişim bilgileri aracılığıyla sizinle iletişim kurabileceğimizi kabul edersiniz.
''';

const String _kGooglePaymentsPrivacy = '''Google Payments Gizlilik Uyarısı
Son değiştirilme tarihi: 16 Mart 2026

Google Gizlilik Politikası, Google'ın ürün ve hizmetlerini kullanımınızla ilişkili kişisel bilgileri nasıl kullandığımızı açıklar. 18 yaşından küçükseniz ilgili diğer kaynakları Google Gençler İçin Gizlilik Kılavuzu ve Çocuklar İçin Google Payments Gizlilik Rehberi'nde bulabilirsiniz.

Google Payments, Google Hesabı sahiplerine sunulur ve kullanımı Google Gizlilik Politikası'na tabidir. Bu Gizlilik Uyarısı'nda, Google Payments'a özgü Google gizlilik uygulamaları da açıklanmaktadır.

Google Payments kullanımınız, bu Gizlilik Uyarısı kapsamındaki hizmetlerin daha ayrıntılı olarak açıklandığı Google Payments Hizmet Şartları'na tabidir. Bu Gizlilik Uyarısı'nda tanımlanmayan, büyük harfle yazılmış terimler, kendilerine Google Payments Hizmet Şartları'nda atfedilmiş anlamları taşır.

Google Payments Gizlilik Uyarısı, Google LLC tarafından veya Google Payment Corp. ("GPC") dahil olmak üzere Google LLC'nin tamamıyla sahip olduğu yan kuruluşlar tarafından sağlanan hizmetler için geçerlidir. Hizmeti sunan yan kuruluşu öğrenmek için hizmet dahilinde erişebildiğiniz Google Payments Hizmet Şartları'na bakın.

• Brezilya'da ikamet eden kullanıcıların bilgilerinden sorumlu veri denetleyici, Google LLC şirketidir. Brezilya'daki yasalar uyarınca gerekli olduğu takdirde, ilgili yetkiyi Google Brasil Pagamentos Ltda şirketi üstlenebilir.
• Birleşik Krallık hariç olmak üzere Avrupa Ekonomik Alanı'nda ikamet eden (bir Google pazar yerinde satış yapanlar dışındaki) kullanıcıların bilgilerinden sorumlu veri denetleyici, Google Ireland Limited şirketidir.
• Birleşik Krallık hariç olmak üzere Avrupa Ekonomik Alanı'nda ikamet eden ve bir Google pazar yerinde satış yapan kullanıcıların bilgilerinden sorumlu veri denetleyici, Google Payment Ireland Limited şirketidir.
• Birleşik Krallık'ta ikamet eden (herhangi bir Google pazar yerinde satış yapanlar dışındaki) kullanıcıların bilgilerinden sorumlu veri denetleyici, Google LLC şirketidir.
• Birleşik Krallık'ta veya İsrail'de ikamet eden ve bir Google pazar yerinde satış yapan kullanıcıların bilgilerinden sorumlu veri denetleyici, Google Payment Limited şirketidir.
• Google Payments Gizlilik Uyarısı, Google India Digital Services Private Limited tarafından Hindistan'daki kullanıcılara sağlanan Google Pay hizmeti için geçerli değildir.

Topladığımız bilgiler
Google Gizlilik Politikası'nda verilen bilgilere ek olarak aşağıdaki bilgileri de toplayabiliriz:

Kayıt bilgileri
Google Payments'a kaydolduğunuzda, Google Hesabınızla ilişkilendirilen bir Google ödeme profili oluşturursunuz. Kullandığınız Google Payments hizmetlerine bağlı olarak Google Gizlilik Politikası'nda listelenenlerin yanı sıra şu bilgileri de sunmanız istenebilir:

• Kredi veya banka kartının numarası ve son kullanma tarihi
• Banka hesap numarası ve son kullanma tarihi
• Adres
• Telefon numarası
• Doğum tarihi
• Ulusal sigorta numarası veya vergi kimlik numarası (ya da diğer resmi kimlik belgesi numaraları)
• Özellikle satıcılar ya da işletmeler için işletme kategorisi ve satış veya işlem hacmiyle ilgili belirli bilgiler

Bazı durumlarda, bilgilerinizin veya kimliğinizin doğrulanması için ek bilgiler göndermenizi veya ek soruları yanıtlamanızı da isteyebiliriz. Son olarak, bir operatör faturalandırma hesabı kaydederseniz bu hesapla ilgili belirli bilgileri bizimle paylaşmanızı isteriz.

Kayıt bilgileriniz Google Hesabınızla ilişkilendirilerek Google'ın sunucularında saklanır. Belirli türde veriler mobil cihazınızda da saklanabilir.

Üçüncü taraflardan alınan bilgiler
Üçüncü taraf doğrulama hizmetleri gibi üçüncü taraflardan sizinle ilgili bilgiler alabiliriz. Bu kapsamda alabileceğimiz bilgiler şunlardır:

• Satıcı konumlarında yapılan Google Payments işlemleri sonucu oluşan bilgiler
• Google Payments'a bağlı üçüncü taraflarca oluşturulan ödeme yöntemlerini ve hesaplarınızı kullanımınızla ilgili bilgiler
• Kartınızı veren kuruluşun ya da finans kuruluşunun kimliği
• Ödeme yönteminizle ilgili özellik ve avantaj bilgileri
• Google ödeme profilinizde tutulan bakiyeye erişimle ilgili bilgiler
• Operatör faturalandırması ile bağlantılı olarak operatörden alınan bilgiler
• ABD Adil Kredi Raporlaması Yasası'nda tanımlandığı anlamıyla tüketici raporları
• Üçüncü taraflarla (ör. satıcılar ve ödeme hizmeti sağlayıcıları) yaptığınız işlemlerle ilgili bilgiler. Bu bilgiler, sahtekarlık riski modellemesi için ve üçüncü taraflara sahtekarlık riski skorları ile sahtekarlık önleme hizmetleri sunmak amacıyla kullanılır.

Ayrıca, kredi bürolarından veya işletme bilgi hizmetlerinden satıcılar ve işletmeleri ile ilgili bilgiler alabiliriz.

İşlem bilgileri
İşlem yapmak için Google Payments'ı kullandığınızda, işlemle ilgili olarak şu bilgileri toplayabiliriz:

• İşlemin tarihi, saati ve tutarı
• Satıcının konumu ve açıklaması
• Satın alınan mal veya hizmetlerin satıcısı tarafından sağlanan açıklama
• İşlemle ilişkilendirmek için seçtiğiniz tüm fotoğraflar
• Satıcının ve alıcının (veya gönderenin ve alıcının) adları ve e-posta adresleri
• Kullanılan ödeme yönteminin türü
• İşlemin nedeni kısmına eklediğiniz açıklama ve varsa işlemle ilişkilendirilen teklif

Topladığımız bilgileri nasıl kullanırız?
Bizimle, Google Payment Corp. (GPC) ile veya diğer yan kuruluşlarımızla paylaştığınız bilgileri ve üçüncü taraflardan aldığımız sizinle ilgili bilgileri, Google Gizlilik Politikası'nda belirtilen kullanımlara uygun şekilde aşağıdaki gibi amaçlarla kullanırız:

• Size Google Payments ile ilgili müşteri hizmetleri sunmak
• Google'ın haklarını, mülklerini, güvenliğini, kullanıcılarımızı ve kamuyu sahtekarlık, kimlik avı veya diğer kusurlu davranışlara karşı korumak
• Üçüncü taraflardan talep ettiğiniz ürün veya hizmetlerin sağlanmasında üçüncü taraflara yardımcı olmak
• Hizmet şartlarını karşılamaya devam edip etmediğinizi belirlemek için Google ödeme profilinizi incelemek
• Yapacağınız Google Payments işlemleriyle ilgili karar almak
• Geçmiş ve güncel bilgilerinizle sahtekarlık risk modeli oluşturup eğitmek ve yalnızca sahtekarlığı veya kötüye kullanımı önleme amaçlarıyla üçüncü taraflarla paylaşılacak sahtekarlık risk skorları ve değerlendirmeleri oluşturmak
• Ödeme yönteminizin özellikleri ve avantajları hakkında size bilgi vermek
• Başlattığınız Google Payments ödemeleriyle ilgili diğer meşru ticari ihtiyaçları karşılamak
• Reklamların performansları da (yalnızca belirli ülkelerde) dahil olmak üzere Google Payments'ın ve Google hizmetlerinin nasıl kullanıldığını anlamak için analizler ve ölçümler gerçekleştirmek
• Ayarlarınıza bağlı olarak gördüğünüz reklamları kişiselleştirmek de (yalnızca belirli ülkelerde) dahil olmak üzere, Google Payments ve diğer Google hizmetleri tarafından size sunulan deneyimleri kişiselleştirmek

Sağladığınız bilgileri, Google Payments'ı kullandığınız süre boyunca veya gerektiğinde düzenleme ve yükümlülüklere uymak amacıyla ek süreyle saklayabiliriz.

Paylaştığımız bilgiler
Kişisel bilgileriniz, Google dışındaki diğer şirketler veya kişilerle yalnızca aşağıdaki amaçlarla paylaşılır:

• Google Gizlilik Politikası'nda izin verilen şekilde
• Yasaların izin verdiği şekilde
• İşleminizi gerçekleştirmek ve hesabınızı korumak için gerekli olduğu ölçüde, güvenlik iyileştirmeleri sağlamak, hesabınızı dolandırıcılığa karşı korumak ve diğer günlük iş faaliyetleri için
• Üçüncü tarafların sağladığı bir hizmete kaydınızı tamamlamak için
• Google Pay'in kullanılabildiği yerlerde, sitesini veya uygulamasını ziyaret ettiğiniz bir üçüncü taraf satıcıyı, satıcının sitesi veya uygulaması üzerinden ödeme yapmak için kullanılabilecek bir Google ödeme profiliniz olup olmadığı konusunda bilgi vermek amacıyla.
• Üçüncü taraflarla yaptığınız işlemlerinizi sahtekarlık ve kötüye kullanıma karşı korumak amacıyla sahtekarlık riski skorlarını ve diğer sahtekarlık değerlendirmelerini Google'ın risk skoru ve sahtekarlık önleme hizmetlerini kullanan üçüncü taraflarla paylaşmak için
• Ödeme yönteminizin güvenli ve geçerli olduğundan emin olmanın yanı sıra size ödeme yönteminizin özellikleri ve avantajlarıyla ilgili bilgiler sunmak amacıyla kişisel bilgilerinizi ödeme yöntemi sağlayıcınız, ödeme ağınız, işlemcileriniz ve bunların satış ortaklarıyla paylaşmak için

Bilgiler şu gibi durumlarda paylaşılabilir:

• Google Payments'ı kullanarak bir satın alma işlemi gerçekleştirdiğinizde veya işlem yaptığınızda sizinle ilgili belirli kişisel bilgiler, satın alma işlemini gerçekleştirdiğiniz ya da işlem yaptığınız şirketle veya kişiyle paylaşılır.
• Bir web sitesi veya uygulama üzerinden Google Pay ile ödeme yaptığınızda, satıcının vergiyi, kargo ücretini ve siparişinizin maliyetiyle ilgili diğer ayrıntıları hesaplayabilmesi için posta kodunuzu ve ödeme yönteminizle ilgili bilgileri paylaşabiliriz.
• Google ödeme profilinize üçüncü taraf ödeme yöntemi eklediğinizde, hem üçüncü tarafın hem bizim hizmeti size sunabilmemiz için belirli kişisel bilgileri üçüncü taraf ödeme sağlayıcısıyla paylaşabiliriz. Adınız, profil resminiz, e-posta adresiniz, internet protokolü (IP) adresiniz, fatura adresiniz, telefon numaranız, cihaz bilgileriniz, konumunuz ve Google Hesap hareketlerinizle ilgili bilgiler bu kapsamda yer alır.
• Google Pay'in kullanılabildiği yerlerde, katılımcı bir satıcının sitesini veya uygulamasını ziyaret ettiğinizde size daha sorunsuz bir deneyim sunmak ve alakalı ödeme seçenekleri göstermek için satıcı, uygun bir ödeme yöntemine sahip bir Google ödeme profiliniz olup olmadığını doğrulayabilir.
• Üçüncü taraflarla (satıcılar ve ödeme hizmeti sağlayıcılar) işlem yaptığınızda, ödeme işleminizle ilgili sahtekarlık risk skorlarını ve diğer sahtekarlık değerlendirmelerini yalnızca sahtekarlığı veya kötüye kullanımı önleme amaçlarıyla söz konusu üçüncü taraflara gönderebiliriz.

Üçüncü taraflardan edinilen bilgiler dahil olmak üzere topladığımız bilgiler satış ortaklarımızla, yani Google LLC'nin sahibi olduğu veya yönettiği diğer şirketlerle paylaşılabilir. Finansal veya finansal olmayan tüzel kişiler olabilecek satış ortaklarımız, bu bilgileri günlük ticari amaçları dahil olmak üzere, bu Gizlilik Uyarısı'nda ve Google Gizlilik Politikası'nda açıklanan amaçlarla kullanır.

GPC ile satış ortakları arasındaki belirli paylaşımların kapsamı dışında kalma hakkınızı kullanabilirsiniz. Özel olarak aşağıdakilerin kapsamı dışında kalmayı seçebilirsiniz:

• Gündelik iş amaçları için size ait kredi itibarı bilgilerinin GPC ile satış ortakları arasında paylaşılması ve/veya
• Toplayıp onlarla paylaştığımız kişisel bilgilerinize dayanarak satış ortaklarımızın size ürünlerini veya hizmetlerini pazarlamaları. Bizimle olan hesap geçmişiniz bu bilgilere dahildir.

Google LLC veya satış ortakları, sitesini ya da uygulamasını ziyaret ettiğiniz bir üçüncü taraf satıcıyı, söz konusu satıcının sitesine veya uygulamasına yapılacak ödeme için kullanılabilecek bir Google ödeme profiliniz olup olmadığı konusunda bilgilendirir. Bu bilgilendirmenin kapsamı dışında kalmayı da tercih edebilirsiniz.

Bu ayarı devre dışı bırakmayı seçerseniz tercihinizi değiştirdiğinizi bize bildirene kadar bu tercihiniz geçerli olacaktır.

Kredi itibarıyla ilgili kişisel bilgilerinizi GPC ile satış ortakları arasında paylaşmamızı; satış ortaklarımızın, topladığımız ve size yönelik pazarlama çalışmalarında kullanabilmeleri için kendileriyle paylaştığımız kişisel bilgilerinizi kullanmasını veya Google LLC'nin ya da satış ortaklarının, sitesini veya uygulamasını ziyaret ettiğiniz bir üçüncü taraf satıcıyı Google ödeme profiliniz olup olmadığı konusunda bilgilendirmesini istemiyorsanız lütfen hesabınıza giriş yaptıktan sonra Google Payments gizlilik ayarları sayfanıza gidip tercihlerinizi güncelleyerek söz konusu tercihleri belirtin.

Kişisel bilgileriniz, bu Gizlilik Uyarısı'nda veya Google Gizlilik Politikası'nda tanımlanan durumlar hariç olmak üzere, GPC veya satış ortaklarımız dışında kimseyle paylaşılmaz. Google Payments, Google Hesabı sahiplerine sunulan bir üründür. Google Hesabı'na kaydolmak için Google LLC ile paylaştığınız veriler, bu Gizlilik Uyarısı'ndaki kapsam dışında kalmayı seçme hükümlerinden etkilenmez.

Bilgilerinizi güvende tutma
Güvenlik uygulamalarımızla ilgili daha fazla bilgi için lütfen ana Google Gizlilik Politikası'na bakın.

Google ödeme profilinizin güvenliği; hesap şifrelerinizi, PIN'lerini ve hizmete erişime yönelik diğer bilgileri gizli tutmanıza bağlıdır:

• Google Hesabı bilgilerinizi üçüncü taraflarla paylaştığınız takdirde söz konusu üçüncü taraflar, Google ödeme profilinize ve kişisel bilgilerinize erişebilir.
• Şifrelerinizi ve/veya PIN'inizi gizli tutmak ve kimseyle paylaşmamak dahil olmak üzere, mobil cihazınıza ve cihazınızdaki Google Cüzdan'a erişimi kontrol etmek sizin sorumluluğunuzdadır.
• Google Payments'taki bilgilerin güvenliğinin tehlikede olduğunu düşünüyorsanız Google'ı veya ilgili iş ortağını uyarmak da sizin sorumluluğunuzdadır.

Bir üçüncü taraf satıcıyla, web sitesiyle veya uygulamayla doğrudan paylaştığınız bilgiler, bu Gizlilik Uyarısı'nın kapsamında değildir. Kişisel bilgilerinizi doğrudan paylaşmayı tercih ettiğiniz satıcıların veya diğer üçüncü tarafların gizlilik ya da güvenlik uygulamalarından biz sorumlu olmayız. Kişisel bilgilerinizi doğrudan paylaşmayı tercih ettiğiniz tüm üçüncü tarafların gizlilik politikalarını incelemenizi öneririz.

© 2026 Google — Google Hizmet Şartları — Önceki Gizlilik Uyarıları
''';

// ───────────────────────────────────────────────────────────────────────────
// Ödeme işleniyor → Başarı ekranı (QandA tarzı)
// ───────────────────────────────────────────────────────────────────────────

class _PaymentProcessingPage extends StatefulWidget {
  final String planLabel;
  final String amount;
  final String renewalDate;
  const _PaymentProcessingPage({
    required this.planLabel,
    required this.amount,
    required this.renewalDate,
  });

  @override
  State<_PaymentProcessingPage> createState() => _PaymentProcessingPageState();
}

class _PaymentProcessingPageState extends State<_PaymentProcessingPage> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _done, // işlem sırasında geri alınamaz
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _done ? _buildSuccess(context) : _buildLoading(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      key: const ValueKey('loading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFF1A73E8)),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Ödeme işleniyor…',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF202124),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Lütfen bu ekrandan ayrılma',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF5F6368),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Padding(
      key: const ValueKey('success'),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          // Büyük yeşil tik
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 72,
                color: Color(0xFF22C55E),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Ödemen alındı',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Premium üyeliğin aktif edildi.\nTüm özelliklerin keyfini çıkar!',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              height: 1.5,
              color: const Color(0xFF5F6368),
            ),
          ),
          const SizedBox(height: 28),
          // Plan özeti kartı
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFE5E7EB), width: 0.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                _summaryRow('Plan', widget.planLabel),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                if (widget.amount.isNotEmpty) ...[
                  _summaryRow('Ödenen tutar', widget.amount),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                ],
                if (widget.renewalDate.isNotEmpty)
                  _summaryRow('Sonraki yenileme', widget.renewalDate),
              ],
            ),
          ),
          const Spacer(),
          // Ana buton
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                "Premium'un keyfini çıkar",
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: const Color(0xFF6B7280),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF202124),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
