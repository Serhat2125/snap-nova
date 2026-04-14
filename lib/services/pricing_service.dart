import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'locale_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  PricingService — Ülke bazlı 5 kademeli fiyatlandırma + Canlı döviz kuru
// ═══════════════════════════════════════════════════════════════════════════════

class PricingPlan {
  final String monthly;
  final String quarterly;
  final String yearly;
  final String quarterlyPerMonth; // 3 aylık / 3 = aylık birim fiyat
  final String yearlyPerMonth;    // 12 aylık / 12 = aylık birim fiyat
  final String monthlyPerDay;
  final String quarterlyPerDay;
  final String yearlyPerDay;
  final String monthlyOld;
  final String currencySymbol;
  final String footerMonthly;
  final String footerQuarterly;
  final String footerYearly;
  final String dailyMonthly;
  final String dailyQuarterly;
  final String dailyYearly;

  const PricingPlan({
    required this.monthly,
    required this.quarterly,
    required this.yearly,
    required this.quarterlyPerMonth,
    required this.yearlyPerMonth,
    required this.monthlyPerDay,
    required this.quarterlyPerDay,
    required this.yearlyPerDay,
    required this.monthlyOld,
    required this.currencySymbol,
    required this.footerMonthly,
    required this.footerQuarterly,
    required this.footerYearly,
    required this.dailyMonthly,
    required this.dailyQuarterly,
    required this.dailyYearly,
  });
}

class PricingService {
  PricingService._();

  // ── Önbellekteki kur verileri ────────────────────────────────────────────
  static Map<String, double>? _cachedRates;

  // ── Ülke kodunu cihazdan algıla ──────────────────────────────────────────
  static String detectCountryCode() {
    try {
      final locale = Platform.localeName;
      final parts = locale.split('_');
      if (parts.length >= 2) return parts[1].toUpperCase();
      return parts[0].toUpperCase();
    } catch (_) {
      return 'US';
    }
  }

  static String detectFromContext(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return (locale.countryCode ?? detectCountryCode()).toUpperCase();
  }

  // ── Dil kodu → Ülke kodu eşlemesi ───────────────────────────────────────
  // Uygulama içinden dil değiştirildiğinde fiyatlar da o ülkeye göre değişir
  static const Map<String, String> langToCountry = {
    'tr': 'TR', // Türkçe → Türkiye
    'en': 'US', // İngilizce → ABD
    'es': 'ES', // İspanyolca → İspanya
    'fr': 'FR', // Fransızca → Fransa
    'de': 'DE', // Almanca → Almanya
    'it': 'IT', // İtalyanca → İtalya
    'pt': 'BR', // Portekizce → Brezilya
    'ru': 'RU', // Rusça → Rusya
    'zh': 'CN', // Çince → Çin
    'ja': 'JP', // Japonca → Japonya
    'ko': 'KR', // Korece → Güney Kore
    'ar': 'SA', // Arapça → Suudi Arabistan
    'hi': 'IN', // Hintçe → Hindistan
    'nl': 'NL', // Hollandaca → Hollanda
    'pl': 'PL', // Lehçe → Polonya
    'sv': 'SE', // İsveççe → İsveç
    'vi': 'VN', // Vietnamca → Vietnam
    'th': 'TH', // Tayca → Tayland
    'id': 'ID', // Endonezce → Endonezya
    'el': 'GR', // Yunanca → Yunanistan
    'cs': 'CZ', // Çekçe → Çekya
    'da': 'DK', // Danca → Danimarka
    'fi': 'FI', // Fince → Finlandiya
    'hu': 'HU', // Macarca → Macaristan
    'no': 'NO', // Norveççe → Norveç
    'ro': 'RO', // Romence → Romanya
    'sk': 'SK', // Slovakça → Slovakya
    'bg': 'BG', // Bulgarca → Bulgaristan
    'hr': 'HR', // Hırvatça → Hırvatistan
    'sr': 'RS', // Sırpça → Sırbistan
    'uk': 'UA', // Ukraynaca → Ukrayna
    'he': 'IL', // İbranice → İsrail
    'fa': 'IR', // Farsça → İran
    'ur': 'PK', // Urduca → Pakistan
    'bn': 'BD', // Bengalce → Bangladeş
    'ta': 'IN', // Tamilce → Hindistan
    'te': 'IN', // Telugu → Hindistan
    'ms': 'MY', // Malayca → Malezya
    'tl': 'PH', // Filipince → Filipinler
    'sw': 'KE', // Svahili → Kenya
    'af': 'ZA', // Afrikaanca → Güney Afrika
    'am': 'ET', // Amharca → Etiyopya
    'my': 'MM', // Birmanca → Myanmar
    'km': 'KH', // Kmerce → Kamboçya
    'lo': 'LA', // Laoca → Laos
    'ne': 'NP', // Nepalce → Nepal
    'si': 'LK', // Seylanca → Sri Lanka
    'ka': 'GE', // Gürcüce → Gürcistan
    'az': 'AZ', // Azerice → Azerbaycan
    'kk': 'KZ', // Kazakça → Kazakistan
    'uz': 'UZ', // Özbekçe → Özbekistan
    'mn': 'MN', // Moğolca → Moğolistan
    'et': 'EE', // Estonca → Estonya
    'lt': 'LT', // Litvanca → Litvanya
    'lv': 'LV', // Letonca → Letonya
  };

  /// Dil kodundan ülke kodu döndürür
  static String countryFromLang(String langCode) {
    return langToCountry[langCode.toLowerCase()] ?? 'US';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Canlı döviz kuru al (ücretsiz API)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> loadExchangeRates() async {
    if (_cachedRates != null) return;
    try {
      final response = await http.get(
        Uri.parse('https://open.er-api.com/v6/latest/USD'),
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rates = data['rates'] as Map<String, dynamic>;
        _cachedRates = rates.map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble()));
      }
    } catch (_) {
      // API çalışmazsa fallback kurlar kullanılır
    }
  }

  static double _getRate(String currency) {
    if (_cachedRates != null && _cachedRates!.containsKey(currency.toUpperCase())) {
      return _cachedRates![currency.toUpperCase()]!;
    }
    return _fallbackRates[currency.toUpperCase()] ?? 1.0;
  }

  // ── Fallback kurlar (API çalışmazsa) ─────────────────────────────────────
  static const Map<String, double> _fallbackRates = {
    'USD': 1.0,
    'EUR': 0.92,
    'GBP': 0.79,
    'TRY': 38.5,
    'NOK': 10.8,
    'SEK': 10.5,
    'DKK': 6.88,
    'CHF': 0.88,
    'CAD': 1.37,
    'AUD': 1.53,
    'NZD': 1.67,
    'JPY': 154.0,
    'KRW': 1350.0,
    'CNY': 7.25,
    'INR': 83.5,
    'BRL': 5.0,
    'MXN': 17.2,
    'ARS': 870.0,
    'COP': 3950.0,
    'PEN': 3.72,
    'CLP': 940.0,
    'RUB': 92.0,
    'UAH': 37.5,
    'PLN': 4.05,
    'CZK': 23.2,
    'HUF': 360.0,
    'RON': 4.6,
    'BGN': 1.8,
    'HRK': 7.0,
    'RSD': 108.0,
    'THB': 35.5,
    'IDR': 15700.0,
    'MYR': 4.7,
    'PHP': 56.0,
    'VND': 24800.0,
    'SGD': 1.35,
    'HKD': 7.82,
    'TWD': 31.5,
    'AED': 3.67,
    'SAR': 3.75,
    'QAR': 3.64,
    'KWD': 0.31,
    'BHD': 0.38,
    'OMR': 0.385,
    'JOD': 0.71,
    'EGP': 30.9,
    'NGN': 770.0,
    'ZAR': 18.5,
    'KES': 153.0,
    'GHS': 12.5,
    'TZS': 2500.0,
    'UGX': 3800.0,
    'PKR': 280.0,
    'BDT': 110.0,
    'LKR': 320.0,
    'NPR': 133.0,
    'KHR': 4100.0,
    'MMK': 2100.0,
    'ILS': 3.65,
    'GEL': 2.7,
    'AZN': 1.7,
    'KZT': 450.0,
    'BYN': 3.3,
    'UZS': 12400.0,
    'DZD': 135.0,
    'MAD': 10.0,
    'TND': 3.1,
    'IQD': 1310.0,
    'LBP': 89500.0,
    'ISK': 138.0,
    'UYU': 39.0,
    'PAB': 1.0,
    'CRC': 520.0,
    'BOB': 6.91,
    'DOP': 57.0,
    'SYP': 13000.0,
    'YER': 250.0,
    'SDG': 600.0,
    'BND': 1.35,
    'MNT': 3450.0,
    'IRR': 42000.0,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  5 KATEGORİ — Kişi başı gelir seviyesine göre (USD bazlı fiyatlar)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  //  Tier 1 — Çok yüksek gelir  → Aylık  $9.99
  //  Tier 2 — Yüksek gelir      → Aylık  $9.99
  //  Tier 3 — Orta-üst gelir    → Aylık  $6.99
  //  Tier 4 — Orta gelir        → Aylık  $4.99
  //  Tier 5 — Düşük gelir       → Aylık  $2.99
  //
  //  3 Aylık = Aylık x 3 (indirim yok)
  //  Yıllık  = Aylık x 12 x 0.50 (%50 indirim)
  //  Süre dolunca indirimsiz fiyatla (aylık x süre) yenilenir
  // ═══════════════════════════════════════════════════════════════════════════

  static const Map<int, double> _tierMonthlyUsd = {
    1: 9.99,
    2: 9.99,
    3: 6.99,
    4: 4.99,
    5: 2.99,
  };

  // ── Ülke → Tier eşleşmesi ───────────────────────────────────────────────
  static const Map<String, int> _countryTier = {
    // Tier 1 — Çok yüksek gelir
    'NO': 1, 'SE': 1, 'DK': 1, 'FI': 1, 'IS': 1,
    'CH': 1, 'LU': 1, 'IE': 1, 'SG': 1,
    'QA': 1, 'AE': 1, 'KW': 1, 'BH': 1, 'BN': 1, 'MC': 1,

    // Tier 2 — Yüksek gelir
    'US': 2, 'CA': 2, 'GB': 2, 'DE': 2, 'FR': 2,
    'NL': 2, 'BE': 2, 'AT': 2, 'AU': 2, 'NZ': 2,
    'IL': 2, 'SA': 2, 'OM': 2, 'HK': 2, 'TW': 2,
    'MT': 2, 'CY': 2, 'EE': 2, 'SI': 2, 'LT': 2,

    // Tier 3 — Orta-üst gelir
    'JP': 3, 'KR': 3, 'IT': 3, 'ES': 3, 'PT': 3,
    'GR': 3, 'CZ': 3, 'SK': 3, 'HR': 3, 'LV': 3,
    'CL': 3, 'UY': 3, 'PA': 3, 'CR': 3, 'MY': 3,
    'CN': 3, 'RO': 3, 'BG': 3, 'HU': 3, 'RS': 3,

    // Tier 4 — Orta gelir
    'TR': 4, 'BR': 4, 'MX': 4, 'AR': 4, 'CO': 4,
    'PE': 4, 'PL': 4, 'RU': 4, 'UA': 4, 'TH': 4,
    'ZA': 4, 'JO': 4, 'LB': 4, 'TN': 4, 'DZ': 4,
    'MA': 4, 'GE': 4, 'AZ': 4, 'KZ': 4, 'BY': 4,
    'PH': 4, 'IQ': 4, 'EC': 4, 'BO': 4, 'DO': 4,

    // Tier 5 — Düşük gelir
    'IR': 4, // İran
    'MN': 4, // Moğolistan
    'IN': 5, 'ID': 5, 'PK': 5, 'BD': 5, 'VN': 5,
    'EG': 5, 'NG': 5, 'KE': 5, 'GH': 5, 'TZ': 5,
    'ET': 5, 'UG': 5, 'MM': 5, 'KH': 5, 'LA': 5,
    'NP': 5, 'LK': 5, 'UZ': 5, 'SN': 5, 'CM': 5,
    'ZW': 5, 'MZ': 5, 'AF': 5, 'SD': 5, 'SY': 5, 'YE': 5,
  };

  // ── Ülke → Para birimi kodu ──────────────────────────────────────────────
  static const Map<String, String> _countryCurrency = {
    'US': 'USD', 'CA': 'CAD', 'GB': 'GBP', 'AU': 'AUD', 'NZ': 'NZD',
    'DE': 'EUR', 'FR': 'EUR', 'IT': 'EUR', 'ES': 'EUR', 'PT': 'EUR',
    'NL': 'EUR', 'BE': 'EUR', 'AT': 'EUR', 'IE': 'EUR', 'FI': 'EUR',
    'GR': 'EUR', 'SK': 'EUR', 'SI': 'EUR', 'EE': 'EUR', 'LT': 'EUR',
    'LV': 'EUR', 'HR': 'EUR', 'CY': 'EUR', 'MT': 'EUR', 'LU': 'EUR',
    'MC': 'EUR',
    'NO': 'NOK', 'SE': 'SEK', 'DK': 'DKK', 'IS': 'ISK',
    'CH': 'CHF',
    'TR': 'TRY',
    'JP': 'JPY', 'KR': 'KRW', 'CN': 'CNY', 'HK': 'HKD', 'TW': 'TWD',
    'SG': 'SGD', 'MY': 'MYR', 'TH': 'THB', 'ID': 'IDR', 'PH': 'PHP',
    'VN': 'VND', 'KH': 'KHR', 'MM': 'MMK', 'BN': 'BND', 'LA': 'USD',
    'IN': 'INR', 'PK': 'PKR', 'BD': 'BDT', 'LK': 'LKR', 'NP': 'NPR',
    'IL': 'ILS',
    'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR', 'KW': 'KWD', 'BH': 'BHD',
    'OM': 'OMR', 'JO': 'JOD', 'IQ': 'IQD', 'LB': 'LBP',
    'EG': 'EGP', 'NG': 'NGN', 'ZA': 'ZAR', 'KE': 'KES', 'GH': 'GHS',
    'TZ': 'TZS', 'UG': 'UGX', 'ET': 'USD', 'SN': 'USD', 'CM': 'USD',
    'ZW': 'USD', 'MZ': 'USD', 'SD': 'SDG', 'SY': 'SYP', 'YE': 'YER',
    'AF': 'USD',
    'BR': 'BRL', 'MX': 'MXN', 'AR': 'ARS', 'CO': 'COP', 'PE': 'PEN',
    'CL': 'CLP', 'UY': 'UYU', 'PA': 'USD', 'CR': 'CRC',
    'EC': 'USD', 'BO': 'BOB', 'DO': 'DOP',
    'RU': 'RUB', 'UA': 'UAH', 'PL': 'PLN', 'CZ': 'CZK', 'HU': 'HUF',
    'RO': 'RON', 'BG': 'BGN', 'RS': 'RSD', 'BY': 'BYN',
    'GE': 'GEL', 'AZ': 'AZN', 'KZ': 'KZT', 'UZ': 'UZS', 'MN': 'MNT',
    'IR': 'IRR',
    'TN': 'TND', 'DZ': 'DZD', 'MA': 'MAD',
  };

  // ── Para birimi sembolleri ───────────────────────────────────────────────
  static const Map<String, String> _currencySymbols = {
    'USD': '\$', 'EUR': '€', 'GBP': '£', 'TRY': '₺',
    'NOK': 'kr', 'SEK': 'kr', 'DKK': 'kr', 'ISK': 'kr',
    'CHF': 'CHF', 'CAD': 'CA\$', 'AUD': 'A\$', 'NZD': 'NZ\$',
    'JPY': '¥', 'KRW': '₩', 'CNY': '¥',
    'HKD': 'HK\$', 'TWD': 'NT\$', 'SGD': 'S\$',
    'MYR': 'RM', 'THB': '฿', 'IDR': 'Rp', 'PHP': '₱', 'VND': '₫',
    'INR': '₹', 'PKR': 'Rs', 'BDT': '৳', 'LKR': 'Rs', 'NPR': 'Rs',
    'ILS': '₪',
    'AED': 'AED', 'SAR': 'SAR', 'QAR': 'QAR', 'KWD': 'KD',
    'BHD': 'BD', 'OMR': 'OMR', 'JOD': 'JD', 'IQD': 'IQD', 'LBP': 'L£',
    'EGP': 'E£', 'NGN': '₦', 'ZAR': 'R', 'KES': 'KSh', 'GHS': 'GH₵',
    'TZS': 'TSh', 'UGX': 'USh',
    'BRL': 'R\$', 'MXN': 'MX\$', 'ARS': 'ARS', 'COP': 'COP',
    'PEN': 'S/', 'CLP': 'CLP', 'UYU': '\$U', 'CRC': '₡',
    'BOB': 'Bs', 'DOP': 'RD\$',
    'RUB': '₽', 'UAH': '₴', 'PLN': 'zł', 'CZK': 'Kč', 'HUF': 'Ft',
    'RON': 'lei', 'BGN': 'лв', 'RSD': 'din', 'BYN': 'Br',
    'GEL': '₾', 'AZN': '₼', 'KZT': '₸', 'UZS': 'сўм',
    'TND': 'DT', 'DZD': 'DA', 'MAD': 'MAD',
    'SDG': 'SDG', 'SYP': 'S£', 'YER': 'YER',
    'KHR': '៛', 'MMK': 'K', 'BND': 'B\$',
    'MNT': '₮', 'IRR': 'IRR',
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  ANA FONKSİYON — Ülke koduna göre plan oluştur
  // ═══════════════════════════════════════════════════════════════════════════

  static PricingPlan getPlan(String countryCode, {LocaleService? locale}) {
    final code = countryCode.toUpperCase();
    final tier = _countryTier[code] ?? 3;
    final monthlyUsd = _tierMonthlyUsd[tier]!;

    // 3 Aylık = aylık x 3 (indirim yok)
    // Yıllık  = aylık x 12 x 0.50 (%50 indirim)
    final quarterlyUsd = monthlyUsd * 3;
    final yearlyUsd = monthlyUsd * 12 * 0.50;

    // İndirimsiz yenileme fiyatları (süre dolunca bu fiyatla devam eder)
    final monthlyRenewUsd = monthlyUsd;        // aylık zaten indirimsiz
    final quarterlyRenewUsd = monthlyUsd * 3;  // 3 aylık zaten indirimsiz
    final yearlyRenewUsd = monthlyUsd * 12;    // yıllık indirimsiz = aylık x 12

    final currency = _countryCurrency[code] ?? 'USD';
    final symbol = _currencySymbols[currency] ?? currency;
    final rate = _getRate(currency);

    // USD → yerel para birimine çevir
    final m = monthlyUsd * rate;
    final q = quarterlyUsd * rate;
    final y = yearlyUsd * rate;

    // Yenileme fiyatları (indirimsiz)
    final mRenew = monthlyRenewUsd * rate;
    final qRenew = quarterlyRenewUsd * rate;
    final yRenew = yearlyRenewUsd * rate;

    // Eski fiyat (üstü çizili) — aylık kartında yıllık indirimsiz aylık fiyatı göster
    final mOld = m * 1.30; // %30 daha pahalı göster

    // Fiyatı güzel formatla
    String fmt(double val) => _formatPrice(val, currency, symbol);

    // Çeviri fonksiyonu — locale yoksa Türkçe fallback
    String t(String key) => locale?.tr(key) ?? _fallbackTr[key] ?? key;

    final perDay = t('per_day');
    final mo = t('month_unit');
    final mo3 = t('three_months_unit');
    final yr = t('year_unit');

    return PricingPlan(
      monthly: fmt(m),
      quarterly: fmt(q),
      yearly: fmt(y),
      quarterlyPerMonth: fmt(q / 3),
      yearlyPerMonth: fmt(y / 12),
      monthlyPerDay: '${fmt(m / 30)}$perDay',
      quarterlyPerDay: '${fmt(q / 90)}$perDay',
      yearlyPerDay: '${fmt(y / 365)}$perDay',
      monthlyOld: fmt(mOld),
      currencySymbol: symbol,
      footerMonthly: '${t("renewal_notice")} ${fmt(mRenew)}/$mo ${t("renewal_suffix")}',
      footerQuarterly: '${t("renewal_notice")} ${fmt(qRenew)}/$mo3 ${t("renewal_suffix")}',
      footerYearly: '${t("renewal_notice")} ${fmt(yRenew)}/$yr ${t("renewal_suffix_yearly")}',
      dailyMonthly: '${t("daily_only")} ${fmt(m / 30)} ${t("daily_suffix")}',
      dailyQuarterly: '${t("daily_only")} ${fmt(q / 90)} ${t("daily_suffix")}',
      dailyYearly: '${t("daily_only")} ${fmt(y / 365)} ${t("daily_suffix")}',
    );
  }

  // Türkçe fallback (locale olmadan çağrıldığında)
  static const _fallbackTr = {
    'per_day': '/gün',
    'month_unit': 'ay',
    'three_months_unit': '3 ay',
    'year_unit': 'yıl',
    'renewal_notice': 'Süre dolduğunda',
    'renewal_suffix': 'ile yenilenir. İstediğiniz zaman iptal edebilirsiniz.',
    'renewal_suffix_yearly': 'ile yenilenir (indirimsiz). İstediğiniz zaman iptal edebilirsiniz.',
    'daily_only': 'Günlük sadece',
    'daily_suffix': 'ile sınırsız eriş',
  };

  // ═══════════════════════════════════════════════════════════════════════════
  //  Fiyat formatlama yardımcıları
  // ═══════════════════════════════════════════════════════════════════════════

  /// Yüksek değerli para birimlerinde ondalık gösterme, düşüklerde göster
  static String _formatPrice(double value, String currency, String symbol) {
    // Ondalık gösterilmeyecek para birimleri (1 USD = 100+ birim)
    const noDecimal = {
      'JPY', 'KRW', 'VND', 'IDR', 'CLP', 'COP', 'HUF', 'ISK',
      'KHR', 'MMK', 'UGX', 'TZS', 'UZS', 'IQD', 'LBP', 'SYP',
      'YER', 'SDG', 'PKR', 'BDT', 'NPR', 'LKR', 'KES', 'GHS',
      'ARS', 'NGN', 'KZT', 'RSD', 'DZD',
    };

    // Sembol önde mi arkada mı
    const symbolAfter = {
      'NOK', 'SEK', 'DKK', 'ISK', 'CZK', 'HUF', 'PLN', 'RON',
      'BGN', 'RSD', 'RUB', 'UAH', 'BYN', 'GEL', 'AZN', 'KZT',
      'UZS', 'TND', 'DZD', 'MAD', 'THB',
    };

    String formatted;
    if (noDecimal.contains(currency)) {
      formatted = _roundNice(value).toString();
    } else {
      formatted = value.toStringAsFixed(2);
    }

    // Binlik ayracı ekle
    formatted = _addThousandSep(formatted, currency);

    if (symbolAfter.contains(currency)) {
      return '$formatted $symbol';
    }
    return '$symbol$formatted';
  }

  /// Yuvarlama: 100'den büyükse en yakın 10'a, 1000'den büyükse en yakın 100'e
  static int _roundNice(double value) {
    if (value >= 10000) return (value / 1000).round() * 1000;
    if (value >= 1000) return (value / 100).round() * 100;
    if (value >= 100) return (value / 10).round() * 10;
    return value.round();
  }

  /// Binlik ayracı: 1234567 → 1.234.567 veya 1,234,567
  static String _addThousandSep(String number, String currency) {
    // Virgül kullanan para birimleri (Türkiye, Almanya vb.)
    const commaCurrencies = {'TRY', 'EUR', 'BRL', 'PLN', 'CZK', 'HUF', 'RON', 'BGN', 'RSD', 'UAH', 'RUB'};
    final sep = commaCurrencies.contains(currency) ? '.' : ',';
    final decSep = commaCurrencies.contains(currency) ? ',' : '.';

    final parts = number.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : null;

    // Binlik ayracı ekle
    final buffer = StringBuffer();
    final len = intPart.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buffer.write(sep);
      buffer.write(intPart[i]);
    }

    if (decPart != null) {
      buffer.write(decSep);
      buffer.write(decPart);
    }

    return buffer.toString();
  }
}
