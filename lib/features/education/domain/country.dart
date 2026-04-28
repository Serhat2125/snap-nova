// ═══════════════════════════════════════════════════════════════════════════════
//  Country — formal domain modeli
//
//  Eski `services/education_profile.dart`'taki `Country` ile yan yana yaşar.
//  Yeni feature katmanları (Riverpod-based) bu modeli kullanır.
// ═══════════════════════════════════════════════════════════════════════════════

class Country {
  /// ISO 3166-1 alpha-2'ye yakın kısa kod ('tr', 'de', 'us', 'uk', 'fr', ...).
  final String code;

  /// Endonim ad — kendi dilinde, ör. "Türkiye", "Deutschland".
  final String name;

  /// Bayrak emoji (🇹🇷, 🇩🇪, ...). Boş string olabilir.
  final String flag;

  const Country({
    required this.code,
    required this.name,
    required this.flag,
  });

  Map<String, dynamic> toJson() =>
      {'code': code, 'name': name, 'flag': flag};

  factory Country.fromJson(Map<String, dynamic> j) => Country(
        code: (j['code'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        flag: (j['flag'] ?? '').toString(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Country && other.code == code);

  @override
  int get hashCode => code.hashCode;
}
