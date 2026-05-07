import 'package:flutter/foundation.dart';

/// Sıralama / leaderboard segmentasyonu için kullanıcının coğrafi
/// konumunu temsil eder. ISO-3166 alpha-2 ülke kodu + slug şehir kodu
/// backend'de composite leaderboard anahtarları (örn. `TR_istanbul_weekly`)
/// için kullanılır.
@immutable
class UserLocation {
  /// Kullanıcının görebileceği ülke adı, yerelleştirilmemiş kanonik form
  /// (örn. "Türkiye"). UI için bu ya da Localized hâli kullanılır.
  final String country;

  /// ISO-3166 alpha-2 (örn. "TR", "DE", "US"). Backend sorguları ve
  /// composite leaderboard anahtarları bunu kullanır.
  final String countryCode;

  /// Kullanıcının görebileceği şehir adı (örn. "İstanbul").
  final String city;

  /// Şehir slug'ı — küçük harf, ASCII, tire yerine alt çizgi
  /// (örn. "istanbul", "ankara", "new_york"). Composite anahtarda yer alır.
  final String cityCode;

  const UserLocation({
    required this.country,
    required this.countryCode,
    required this.city,
    required this.cityCode,
  });

  /// ISO-3166 alpha-2 kodundan emoji bayrağı üretir.
  /// Örn. "TR" → 🇹🇷. Geçersiz/eksik kodlarda 🌍 fallback'i.
  String get countryFlag {
    if (countryCode.length != 2) return '🌍';
    const baseLetter = 0x41; // 'A'
    const baseRegional = 0x1F1E6;
    final upper = countryCode.toUpperCase();
    final c1 = upper.codeUnitAt(0);
    final c2 = upper.codeUnitAt(1);
    if (c1 < baseLetter || c1 > baseLetter + 25) return '🌍';
    if (c2 < baseLetter || c2 > baseLetter + 25) return '🌍';
    return String.fromCharCodes([
      baseRegional + (c1 - baseLetter),
      baseRegional + (c2 - baseLetter),
    ]);
  }

  /// Backend leaderboard anahtarı — `TR_istanbul_weekly` vb.
  String leaderboardKey(String period) =>
      '${countryCode}_${cityCode}_$period';

  Map<String, dynamic> toJson() => {
        'country': country,
        'countryCode': countryCode,
        'city': city,
        'cityCode': cityCode,
      };

  factory UserLocation.fromJson(Map<String, dynamic> j) => UserLocation(
        country: (j['country'] as String?) ?? '',
        countryCode: (j['countryCode'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        cityCode: (j['cityCode'] as String?) ?? '',
      );

  UserLocation copyWith({
    String? country,
    String? countryCode,
    String? city,
    String? cityCode,
  }) =>
      UserLocation(
        country: country ?? this.country,
        countryCode: countryCode ?? this.countryCode,
        city: city ?? this.city,
        cityCode: cityCode ?? this.cityCode,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserLocation &&
          country == other.country &&
          countryCode == other.countryCode &&
          city == other.city &&
          cityCode == other.cityCode;

  @override
  int get hashCode => Object.hash(country, countryCode, city, cityCode);

  @override
  String toString() =>
      'UserLocation($countryFlag $country / $city [$countryCode/$cityCode])';
}
