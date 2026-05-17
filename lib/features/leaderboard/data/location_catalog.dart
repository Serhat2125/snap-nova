/// Sıralama segmentasyonu için ülke + şehir kataloğu.
///
/// Şu an statik tutuluyor (ihtiyaç duyulan top 30 ülke + büyük şehirleri);
/// production sürümünde backend'den (`/locations/countries`) Firestore
/// dokümanı veya REST endpoint olarak gelecek. Static katalog offline-first
/// fallback olarak da kalır.
class CountryEntry {
  final String code; // ISO-3166 alpha-2 (TR, DE, ...)
  final String name; // Türkçe görünen ad
  final List<CityEntry> cities;
  const CountryEntry({
    required this.code,
    required this.name,
    required this.cities,
  });

  String get flag {
    if (code.length != 2) return '🌍';
    const base = 0x1F1E6;
    const a = 0x41;
    return String.fromCharCodes([
      base + (code.codeUnitAt(0) - a),
      base + (code.codeUnitAt(1) - a),
    ]);
  }
}

class CityEntry {
  final String code; // slug (istanbul, new_york, ...)
  final String name; // Görünen ad (İstanbul, New York)
  const CityEntry({required this.code, required this.name});
}

class LocationCatalog {
  LocationCatalog._();

  /// Türkiye ilk sırada — ana hedef pazar.
  static const List<CountryEntry> countries = [
    CountryEntry(code: 'TR', name: 'Türkiye', cities: [
      // Türkiye Cumhuriyeti'nin 81 ili (alfabetik).
      CityEntry(code: 'adana', name: 'Adana'),
      CityEntry(code: 'adiyaman', name: 'Adıyaman'),
      CityEntry(code: 'afyonkarahisar', name: 'Afyonkarahisar'),
      CityEntry(code: 'agri', name: 'Ağrı'),
      CityEntry(code: 'aksaray', name: 'Aksaray'),
      CityEntry(code: 'amasya', name: 'Amasya'),
      CityEntry(code: 'ankara', name: 'Ankara'),
      CityEntry(code: 'antalya', name: 'Antalya'),
      CityEntry(code: 'ardahan', name: 'Ardahan'),
      CityEntry(code: 'artvin', name: 'Artvin'),
      CityEntry(code: 'aydin', name: 'Aydın'),
      CityEntry(code: 'balikesir', name: 'Balıkesir'),
      CityEntry(code: 'bartin', name: 'Bartın'),
      CityEntry(code: 'batman', name: 'Batman'),
      CityEntry(code: 'bayburt', name: 'Bayburt'),
      CityEntry(code: 'bilecik', name: 'Bilecik'),
      CityEntry(code: 'bingol', name: 'Bingöl'),
      CityEntry(code: 'bitlis', name: 'Bitlis'),
      CityEntry(code: 'bolu', name: 'Bolu'),
      CityEntry(code: 'burdur', name: 'Burdur'),
      CityEntry(code: 'bursa', name: 'Bursa'),
      CityEntry(code: 'canakkale', name: 'Çanakkale'),
      CityEntry(code: 'cankiri', name: 'Çankırı'),
      CityEntry(code: 'corum', name: 'Çorum'),
      CityEntry(code: 'denizli', name: 'Denizli'),
      CityEntry(code: 'diyarbakir', name: 'Diyarbakır'),
      CityEntry(code: 'duzce', name: 'Düzce'),
      CityEntry(code: 'edirne', name: 'Edirne'),
      CityEntry(code: 'elazig', name: 'Elazığ'),
      CityEntry(code: 'erzincan', name: 'Erzincan'),
      CityEntry(code: 'erzurum', name: 'Erzurum'),
      CityEntry(code: 'eskisehir', name: 'Eskişehir'),
      CityEntry(code: 'gaziantep', name: 'Gaziantep'),
      CityEntry(code: 'giresun', name: 'Giresun'),
      CityEntry(code: 'gumushane', name: 'Gümüşhane'),
      CityEntry(code: 'hakkari', name: 'Hakkari'),
      CityEntry(code: 'hatay', name: 'Hatay'),
      CityEntry(code: 'igdir', name: 'Iğdır'),
      CityEntry(code: 'isparta', name: 'Isparta'),
      CityEntry(code: 'istanbul', name: 'İstanbul'),
      CityEntry(code: 'izmir', name: 'İzmir'),
      CityEntry(code: 'kahramanmaras', name: 'Kahramanmaraş'),
      CityEntry(code: 'karabuk', name: 'Karabük'),
      CityEntry(code: 'karaman', name: 'Karaman'),
      CityEntry(code: 'kars', name: 'Kars'),
      CityEntry(code: 'kastamonu', name: 'Kastamonu'),
      CityEntry(code: 'kayseri', name: 'Kayseri'),
      CityEntry(code: 'kilis', name: 'Kilis'),
      CityEntry(code: 'kirikkale', name: 'Kırıkkale'),
      CityEntry(code: 'kirklareli', name: 'Kırklareli'),
      CityEntry(code: 'kirsehir', name: 'Kırşehir'),
      CityEntry(code: 'kocaeli', name: 'Kocaeli'),
      CityEntry(code: 'konya', name: 'Konya'),
      CityEntry(code: 'kutahya', name: 'Kütahya'),
      CityEntry(code: 'malatya', name: 'Malatya'),
      CityEntry(code: 'manisa', name: 'Manisa'),
      CityEntry(code: 'mardin', name: 'Mardin'),
      CityEntry(code: 'mersin', name: 'Mersin'),
      CityEntry(code: 'mugla', name: 'Muğla'),
      CityEntry(code: 'mus', name: 'Muş'),
      CityEntry(code: 'nevsehir', name: 'Nevşehir'),
      CityEntry(code: 'nigde', name: 'Niğde'),
      CityEntry(code: 'ordu', name: 'Ordu'),
      CityEntry(code: 'osmaniye', name: 'Osmaniye'),
      CityEntry(code: 'rize', name: 'Rize'),
      CityEntry(code: 'sakarya', name: 'Sakarya'),
      CityEntry(code: 'samsun', name: 'Samsun'),
      CityEntry(code: 'sanliurfa', name: 'Şanlıurfa'),
      CityEntry(code: 'siirt', name: 'Siirt'),
      CityEntry(code: 'sinop', name: 'Sinop'),
      CityEntry(code: 'sivas', name: 'Sivas'),
      CityEntry(code: 'sirnak', name: 'Şırnak'),
      CityEntry(code: 'tekirdag', name: 'Tekirdağ'),
      CityEntry(code: 'tokat', name: 'Tokat'),
      CityEntry(code: 'trabzon', name: 'Trabzon'),
      CityEntry(code: 'tunceli', name: 'Tunceli'),
      CityEntry(code: 'usak', name: 'Uşak'),
      CityEntry(code: 'van', name: 'Van'),
      CityEntry(code: 'yalova', name: 'Yalova'),
      CityEntry(code: 'yozgat', name: 'Yozgat'),
      CityEntry(code: 'zonguldak', name: 'Zonguldak'),
    ]),
    CountryEntry(code: 'DE', name: 'Almanya', cities: [
      CityEntry(code: 'berlin', name: 'Berlin'),
      CityEntry(code: 'munich', name: 'München'),
      CityEntry(code: 'hamburg', name: 'Hamburg'),
      CityEntry(code: 'cologne', name: 'Köln'),
      CityEntry(code: 'frankfurt', name: 'Frankfurt'),
      CityEntry(code: 'stuttgart', name: 'Stuttgart'),
      CityEntry(code: 'dusseldorf', name: 'Düsseldorf'),
    ]),
    CountryEntry(code: 'US', name: 'Amerika Birleşik Devletleri', cities: [
      CityEntry(code: 'new_york', name: 'New York'),
      CityEntry(code: 'los_angeles', name: 'Los Angeles'),
      CityEntry(code: 'chicago', name: 'Chicago'),
      CityEntry(code: 'houston', name: 'Houston'),
      CityEntry(code: 'phoenix', name: 'Phoenix'),
      CityEntry(code: 'san_francisco', name: 'San Francisco'),
      CityEntry(code: 'boston', name: 'Boston'),
    ]),
    CountryEntry(code: 'GB', name: 'Birleşik Krallık', cities: [
      CityEntry(code: 'london', name: 'Londra'),
      CityEntry(code: 'manchester', name: 'Manchester'),
      CityEntry(code: 'birmingham', name: 'Birmingham'),
      CityEntry(code: 'edinburgh', name: 'Edinburgh'),
      CityEntry(code: 'liverpool', name: 'Liverpool'),
    ]),
    CountryEntry(code: 'FR', name: 'Fransa', cities: [
      CityEntry(code: 'paris', name: 'Paris'),
      CityEntry(code: 'marseille', name: 'Marsilya'),
      CityEntry(code: 'lyon', name: 'Lyon'),
      CityEntry(code: 'toulouse', name: 'Toulouse'),
      CityEntry(code: 'nice', name: 'Nice'),
    ]),
    CountryEntry(code: 'IT', name: 'İtalya', cities: [
      CityEntry(code: 'rome', name: 'Roma'),
      CityEntry(code: 'milan', name: 'Milano'),
      CityEntry(code: 'naples', name: 'Napoli'),
      CityEntry(code: 'turin', name: 'Torino'),
      CityEntry(code: 'florence', name: 'Floransa'),
    ]),
    CountryEntry(code: 'ES', name: 'İspanya', cities: [
      CityEntry(code: 'madrid', name: 'Madrid'),
      CityEntry(code: 'barcelona', name: 'Barselona'),
      CityEntry(code: 'valencia', name: 'Valensiya'),
      CityEntry(code: 'seville', name: 'Sevilla'),
    ]),
    CountryEntry(code: 'NL', name: 'Hollanda', cities: [
      CityEntry(code: 'amsterdam', name: 'Amsterdam'),
      CityEntry(code: 'rotterdam', name: 'Rotterdam'),
      CityEntry(code: 'the_hague', name: 'Lahey'),
      CityEntry(code: 'utrecht', name: 'Utrecht'),
    ]),
    CountryEntry(code: 'BE', name: 'Belçika', cities: [
      CityEntry(code: 'brussels', name: 'Brüksel'),
      CityEntry(code: 'antwerp', name: 'Anvers'),
      CityEntry(code: 'ghent', name: 'Gent'),
    ]),
    CountryEntry(code: 'CH', name: 'İsviçre', cities: [
      CityEntry(code: 'zurich', name: 'Zürih'),
      CityEntry(code: 'geneva', name: 'Cenevre'),
      CityEntry(code: 'basel', name: 'Basel'),
      CityEntry(code: 'bern', name: 'Bern'),
    ]),
    CountryEntry(code: 'AT', name: 'Avusturya', cities: [
      CityEntry(code: 'vienna', name: 'Viyana'),
      CityEntry(code: 'graz', name: 'Graz'),
      CityEntry(code: 'salzburg', name: 'Salzburg'),
    ]),
    CountryEntry(code: 'SE', name: 'İsveç', cities: [
      CityEntry(code: 'stockholm', name: 'Stockholm'),
      CityEntry(code: 'gothenburg', name: 'Göteborg'),
      CityEntry(code: 'malmo', name: 'Malmö'),
    ]),
    CountryEntry(code: 'NO', name: 'Norveç', cities: [
      CityEntry(code: 'oslo', name: 'Oslo'),
      CityEntry(code: 'bergen', name: 'Bergen'),
    ]),
    CountryEntry(code: 'PL', name: 'Polonya', cities: [
      CityEntry(code: 'warsaw', name: 'Varşova'),
      CityEntry(code: 'krakow', name: 'Krakov'),
      CityEntry(code: 'gdansk', name: 'Gdańsk'),
    ]),
    CountryEntry(code: 'RU', name: 'Rusya', cities: [
      CityEntry(code: 'moscow', name: 'Moskova'),
      CityEntry(code: 'saint_petersburg', name: 'Saint Petersburg'),
      CityEntry(code: 'novosibirsk', name: 'Novosibirsk'),
    ]),
    CountryEntry(code: 'AZ', name: 'Azerbaycan', cities: [
      CityEntry(code: 'baku', name: 'Bakü'),
      CityEntry(code: 'ganja', name: 'Gence'),
    ]),
    CountryEntry(code: 'IR', name: 'İran', cities: [
      CityEntry(code: 'tehran', name: 'Tahran'),
      CityEntry(code: 'tabriz', name: 'Tebriz'),
      CityEntry(code: 'isfahan', name: 'İsfahan'),
    ]),
    CountryEntry(code: 'IQ', name: 'Irak', cities: [
      CityEntry(code: 'baghdad', name: 'Bağdat'),
      CityEntry(code: 'erbil', name: 'Erbil'),
    ]),
    CountryEntry(code: 'SA', name: 'Suudi Arabistan', cities: [
      CityEntry(code: 'riyadh', name: 'Riyad'),
      CityEntry(code: 'jeddah', name: 'Cidde'),
      CityEntry(code: 'mecca', name: 'Mekke'),
    ]),
    CountryEntry(code: 'AE', name: 'Birleşik Arap Emirlikleri', cities: [
      CityEntry(code: 'dubai', name: 'Dubai'),
      CityEntry(code: 'abu_dhabi', name: 'Abu Dabi'),
    ]),
    CountryEntry(code: 'EG', name: 'Mısır', cities: [
      CityEntry(code: 'cairo', name: 'Kahire'),
      CityEntry(code: 'alexandria', name: 'İskenderiye'),
    ]),
    CountryEntry(code: 'MA', name: 'Fas', cities: [
      CityEntry(code: 'casablanca', name: 'Kazablanka'),
      CityEntry(code: 'rabat', name: 'Rabat'),
      CityEntry(code: 'marrakech', name: 'Marakeş'),
    ]),
    CountryEntry(code: 'IN', name: 'Hindistan', cities: [
      CityEntry(code: 'mumbai', name: 'Mumbai'),
      CityEntry(code: 'delhi', name: 'Delhi'),
      CityEntry(code: 'bangalore', name: 'Bangalore'),
      CityEntry(code: 'kolkata', name: 'Kalküta'),
    ]),
    CountryEntry(code: 'JP', name: 'Japonya', cities: [
      CityEntry(code: 'tokyo', name: 'Tokyo'),
      CityEntry(code: 'osaka', name: 'Osaka'),
      CityEntry(code: 'kyoto', name: 'Kyoto'),
    ]),
    CountryEntry(code: 'KR', name: 'Güney Kore', cities: [
      CityEntry(code: 'seoul', name: 'Seul'),
      CityEntry(code: 'busan', name: 'Busan'),
    ]),
    CountryEntry(code: 'CN', name: 'Çin', cities: [
      CityEntry(code: 'beijing', name: 'Pekin'),
      CityEntry(code: 'shanghai', name: 'Şanghay'),
      CityEntry(code: 'shenzhen', name: 'Shenzhen'),
    ]),
    CountryEntry(code: 'AU', name: 'Avustralya', cities: [
      CityEntry(code: 'sydney', name: 'Sidney'),
      CityEntry(code: 'melbourne', name: 'Melbourne'),
    ]),
    CountryEntry(code: 'CA', name: 'Kanada', cities: [
      CityEntry(code: 'toronto', name: 'Toronto'),
      CityEntry(code: 'montreal', name: 'Montreal'),
      CityEntry(code: 'vancouver', name: 'Vancouver'),
    ]),
    CountryEntry(code: 'BR', name: 'Brezilya', cities: [
      CityEntry(code: 'sao_paulo', name: 'São Paulo'),
      CityEntry(code: 'rio_de_janeiro', name: 'Rio de Janeiro'),
    ]),
    CountryEntry(code: 'MX', name: 'Meksika', cities: [
      CityEntry(code: 'mexico_city', name: 'Meksiko'),
      CityEntry(code: 'guadalajara', name: 'Guadalajara'),
    ]),
  ];

  /// Ülke kodundan CountryEntry getir; yoksa null.
  static CountryEntry? findByCode(String code) {
    final upper = code.toUpperCase();
    for (final c in countries) {
      if (c.code == upper) return c;
    }
    return null;
  }

  /// Ülke kodundan şehir listesini getir.
  static List<CityEntry> citiesOf(String countryCode) =>
      findByCode(countryCode)?.cities ?? const [];

  /// Şehir kodundan CityEntry getir.
  static CityEntry? findCity(String countryCode, String cityCode) {
    final cities = citiesOf(countryCode);
    for (final c in cities) {
      if (c.code == cityCode) return c;
    }
    return null;
  }
}
