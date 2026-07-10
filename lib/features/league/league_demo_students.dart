// ═══════════════════════════════════════════════════════════════════════════════
//  LeagueDemoStudents — Bilgi Ligi kapalı test dönemi demo sıralama dolgusu.
//
//  Amaç: Kapalı testte gerçek kullanıcı azken sıralama boş görünmesin. Her
//  görünüm (scope × mode × periyot kovası × seviye/sınıf) için 8 deterministik
//  demo öğrenci üretilir; gerçek Firestore satırlarıyla İSTEMCİDE birleştirilip
//  puana göre sıralanır — test eden gerçek kullanıcılar hak ettikleri sırada
//  demo öğrencilerin arasında görünür.
//
//  Deterministiklik: seed = scopeKey|modeKey|bucket hash'i.
//    • Aynı gün/hafta/ay içinde liste SABİT (her açılışta aynı isim ve puan).
//    • Kova değişince (yeni gün/hafta/ay) puanlar ve isimler otomatik yenilenir.
//    • Şehir/ülke/seviye/sınıf scopeKey'de olduğundan her kademe kendi 8
//      öğrencisini görür; dünya tek küresel havuz (level'a bölünmez).
//
//  Firestore'a HİÇBİR yazma yapılmaz (istemci lig koleksiyonlarına yazamaz);
//  tamamen istemci tarafı görsel dolgu. Lansmanda `enabled=false` yapmak
//  tek satırlık iştir.
//
//  GLOBAL-FIRST: isimler kullanıcının ülkesine göre yerel havuzdan seçilir;
//  dünya kapsamında karma ülkeler bayraklarıyla görünür.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/education_profile.dart';
import '../leaderboard/domain/user_location.dart';
import 'league_leaderboard_service.dart';
import 'league_scores.dart';

class LeagueDemoStudents {
  /// Demo dolgu anahtarı — UZAKTAN kontrollü (APK güncellemesi gerekmez).
  ///
  /// Karar (2026-07-10): demo dolgu, gerçek kullanıcı sayısı 10.000'e
  /// ulaşana kadar AÇIK kalır. Günlük scheduled Cloud Function
  /// (autoDisableLeagueDemo) kullanıcı sayısını sayar ve eşik aşılınca
  /// Firestore `app_config/league.demoEnabled=false` yazar; istemci bunu
  /// [refreshEnabledFromCloud] ile okur. Doküman yoksa / offline'da
  /// varsayılan AÇIK (son bilinen değer prefs'te saklanır).
  static bool _enabled = true;
  static bool get enabled => _enabled;

  static const _prefsKey = 'league_demo_enabled_v1';
  static bool _cloudChecked = false;

  /// Bulut bayrağını yükle — Bilgi Ligi ekranı açılışında çağrılır.
  /// Önce prefs'teki son bilinen değer anında uygulanır (offline garanti),
  /// ardından Firestore'dan taze değer çekilir. Oturum başına bir kez ağa
  /// çıkar; hata durumunda mevcut değer korunur.
  static Future<void> refreshEnabledFromCloud() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool(_prefsKey);
      if (cached != null) _enabled = cached;
      if (_cloudChecked) return;
      _cloudChecked = true;
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('league')
          .get()
          .timeout(const Duration(seconds: 6));
      final v = doc.data()?['demoEnabled'];
      if (v is bool) {
        _enabled = v;
        await prefs.setBool(_prefsKey, v);
      }
    } catch (_) {/* offline / izin → son bilinen değerle devam */}
  }

  /// Görünüm başına demo öğrenci sayısı — her şehir/ülke/dünya görünümünde
  /// ve her periyotta (günlük/haftalık/aylık/genel) EN AZ bu kadar demo
  /// öğrenci yarışıyormuş gibi görünür; geniş gerçek kullanıcı tabanına
  /// ulaşınca `enabled=false` ile tamamı kaldırılır.
  static const int count = 30;

  /// Bu görünümün demo öğrencileri — puan DESC sıralı.
  /// `modeKey`: `'all' | 's:subject' | 't:subject|topic'` (servisle aynı).
  ///
  /// `profile`/`location` null olabilir — kapalı testte liste ASLA boş
  /// kalmasın diye her kapsam yine de üretir:
  ///   • Konum seçiliyse kapsam anahtarı gerçek sıralamayla birebir aynı
  ///     (aynı görünüm = aynı kadro).
  ///   • Konum seçilmemişse eğitim profilinin ülkesi + yer tutucu şehirle
  ///     seed kurulur; kullanıcı konum seçince kadro doğal olarak yenilenir.
  static List<LeagueLeaderRow> forView({
    required LeagueScope scope,
    EduProfile? profile,
    UserLocation? location,
    required LeaguePeriod period,
    required String modeKey,
  }) {
    if (!enabled) return const [];

    // Ülke: önce lig konumu, yoksa eğitim profili ülkesi, o da yoksa 'intl'.
    final String countryKey =
        (location != null && location.countryCode.isNotEmpty)
            ? location.countryCode
            : ((profile?.country.isNotEmpty ?? false)
                ? profile!.country
                : 'intl');
    final String cityKey =
        (location != null && location.cityCode.isNotEmpty)
            ? location.cityCode
            : '_';
    final String levelKey = profile?.level ?? '-';
    final String gradeKey = profile?.grade ?? '-';

    // Servisteki scope anahtarlarıyla aynı biçim — konum seçiliyken birebir
    // aynı seed (kadro sabit kalır), seçili değilken yer tutucu fallback.
    final String scopeKey;
    switch (scope) {
      case LeagueScope.city:
        scopeKey = '$countryKey|$cityKey|$levelKey|$gradeKey';
        break;
      case LeagueScope.country:
        scopeKey = '$countryKey|$levelKey|$gradeKey';
        break;
      case LeagueScope.world:
        scopeKey = 'world';
        break;
    }
    // İsim/şehir üretiminde kullanılan normalize ülke kodu ('uk' → 'gb').
    final userCc = _normCc(countryKey);

    final bucket = LeagueScores.bucketFor(period);
    final seed = _fnv1a('$scopeKey|$modeKey|$bucket');
    final rng = _Rng(seed);

    // Periyoda göre gerçekçi puan aralığı (1 net = 1 puan; test ~10-15 puan).
    // Alt uç düşük tutulur ki 1-2 test çözen gerçek kullanıcı demo
    // öğrencilerin bir kısmını geçebilsin.
    final (double lo, double hi) = switch (period) {
      LeaguePeriod.daily => (3.0, 16.0),
      LeaguePeriod.weekly => (10.0, 70.0),
      LeaguePeriod.monthly => (25.0, 160.0),
      LeaguePeriod.allTime => (50.0, 340.0),
    };

    final rows = <LeagueLeaderRow>[];
    final usedNames = <String>{};
    for (int i = 0; i < count; i++) {
      // Ülke: şehir/ülke kapsamında kullanıcının ülkesi; dünyada karma.
      final cc = scope == LeagueScope.world
          ? _worldCountries[rng.nextInt(_worldCountries.length)]
          : userCc;

      // İsim — aynı listede tekrar etmesin.
      String name;
      int guard = 0;
      do {
        name = _nameFor(cc, rng);
      } while (!usedNames.add(name) && ++guard < 12);

      // Konum metni — servis _formatLocation çıktısıyla aynı biçim.
      final String loc;
      switch (scope) {
        case LeagueScope.city:
          // Şehir kapsamında UI konum satırını zaten gizler (hideLocation);
          // konum seçilmemişse boş kalması sorun değil.
          loc = _humanCity(location?.cityCode ?? '');
          break;
        case LeagueScope.country:
          // TR: 81 ilin tamamı, NÜFUSA AĞIRLIKLI seçim — büyük şehirler
          // daha sık görünür ama küçük iller de listeye karışır (kullanıcı
          // isteği: yalnız 3-4 büyükşehir dönmesin). Diğer ülkeler şimdilik
          // küçük eşit-olasılıklı havuzdan; istenirse aynı ağırlık deseni
          // onlara da uygulanabilir.
          if (cc == 'tr') {
            loc = _trCityWeighted(rng);
          } else {
            final cities = _cityPools[cc];
            loc = cities == null ? '' : cities[rng.nextInt(cities.length)];
          }
          break;
        case LeagueScope.world:
          loc = '${_flag(cc)} ${_countryName(cc)}';
          break;
      }

      // Puan — çeyrek adımlı (net biçimi: 7.75 gibi).
      final score = ((lo + rng.nextDouble() * (hi - lo)) * 4).round() / 4.0;
      // Süre — puan başına 25-75 sn (tiebreaker gerçekçi kalsın).
      final durationSec = (score * (25 + rng.nextInt(50))).round();

      rows.add(LeagueLeaderRow(
        uid: 'demo|$seed|$i',
        displayName: name,
        avatar: _avatars[rng.nextInt(_avatars.length)],
        location: loc,
        score: score,
        durationSec: durationSec,
      ));
    }

    rows.sort((a, b) => b.score.compareTo(a.score));
    return rows;
  }

  /// Bir uid demo öğrenciye mi ait?
  static bool isDemoUid(String uid) => uid.startsWith('demo|');

  /// Dış kullanım (ör. Arkadaşlarınla Yarış hero kartındaki değişen
  /// isimler): ülkeye uygun havuzdan "Ad B." biçiminde isim üretir —
  /// aynı seed her zaman aynı ismi verir.
  static String sampleName(String countryCode, int seed) {
    final rng = _Rng(seed == 0 ? 1 : seed);
    return _nameFor(_normCc(countryCode), rng);
  }

  /// Ülkeye/dile uygun EĞLENCELİ grup adı (Grup Yarışı hero kartındaki
  /// canlı sıralama panelinin başlığı) — aynı seed aynı adı verir.
  static String sampleGroupName(String countryCode, int seed) {
    final pool = _groupNamePools[_poolKey(_normCc(countryCode))] ??
        _groupNamePools['intl']!;
    return pool[seed.abs() % pool.length];
  }

  /// Dil havuzu → komik grup adları. Kültüre uygun, kısa ve espirili.
  static const _groupNamePools = <String, List<String>>{
    'tr': [
      'Koalalar', 'Cadılar', 'Kızlarım 💅', 'Karınca Grubu',
      'Moğol İstilası', 'Çirkin Ördek Yavruları', 'Beyin Takımı',
      'Uykusuzlar', 'Son Dakikacılar', 'Einstein Torunları',
    ],
    'en': [
      'The Koalas', 'The Witches', 'Brain Squad', 'Night Owls',
      'Ugly Ducklings', 'Ant Colony', 'Last Minute Club', 'Quiz Wizards',
    ],
    'de': [
      'Die Koalas', 'Die Hexen', 'Denkfabrik', 'Nachteulen',
      'Hässliche Entlein', 'Ameisenbande', 'Last-Minute-Club', 'Die Streber',
    ],
    'fr': [
      'Les Koalas', 'Les Sorcières', 'Les Cerveaux', 'Les Noctambules',
      'Vilains Petits Canards', 'Les Fourmis', 'Les Retardataires',
      'Brigade Quiz',
    ],
    'es': [
      'Los Koalas', 'Las Brujas', 'Cerebritos', 'Búhos Nocturnos',
      'Patitos Feos', 'Hormigas Locas', 'Los Últimos', 'Magos del Quiz',
    ],
    'pt': [
      'Os Coalas', 'As Bruxas', 'Cérebros', 'Corujas da Noite',
      'Patinhos Feios', 'Formigas Loucas', 'Os Atrasados', 'Magos do Quiz',
    ],
    'ru': [
      'Коалы', 'Ведьмы', 'Мозговой штурм', 'Ночные совы',
      'Гадкие утята', 'Муравейник', 'Последняя парта', 'Знатоки',
    ],
    'ar': [
      'الكوالا', 'الساحرات', 'فريق العباقرة', 'بوم الليل',
      'البطة القبيحة', 'مملكة النمل', 'الصف الأخير', 'سحرة الأسئلة',
    ],
    'fa': [
      'کوالاها', 'جادوگرها', 'تیم نابغه‌ها', 'جغدهای شب',
      'جوجه اردک زشت', 'کلونی مورچه‌ها', 'دقیقه نودی‌ها', 'استاد کوییز',
    ],
    'hi': [
      'कोआला टीम', 'जादूगरनियाँ', 'दिमाग़ी टीम', 'रात के उल्लू',
      'बदसूरत बत्तख', 'चींटी दल', 'आख़िरी मिनट', 'क्विज़ मास्टर',
    ],
    'id': [
      'Para Koala', 'Penyihir', 'Tim Jenius', 'Burung Hantu',
      'Itik Buruk Rupa', 'Koloni Semut', 'Pasukan Deadline', 'Ahli Kuis',
    ],
    'ja': [
      'コアラ組', '魔女たち', '天才チーム', '夜ふかし組',
      'みにくいアヒル', 'アリの行列', 'ギリギリ隊', 'クイズの達人',
    ],
    'ko': [
      '코알라들', '마녀들', '천재팀', '올빼미들',
      '미운 오리들', '개미군단', '벼락치기팀', '퀴즈의 달인',
    ],
    'zh': [
      '考拉队', '女巫团', '最强大脑', '夜猫子',
      '丑小鸭', '蚂蚁军团', '临时抱佛脚', '答题大师',
    ],
    'it': [
      'I Koala', 'Le Streghe', 'I Cervelloni', 'Gufi Notturni',
      'Brutti Anatroccoli', 'Formiche Pazze', 'Gli Ultimi', 'Maghi del Quiz',
    ],
    'el': [
      'Τα Κοάλα', 'Οι Μάγισσες', 'Τα Μυαλά', 'Νυχτοπούλια',
      'Ασχημόπαπα', 'Μυρμήγκια', 'Της Τελευταίας Στιγμής', 'Μάγοι του Κουίζ',
    ],
    'nl': [
      'De Koalas', 'De Heksen', 'Breinbrigade', 'Nachtuilen',
      'Lelijke Eendjes', 'Mierenkolonie', 'Laatste-Minuut-Club',
      'Quizmeesters',
    ],
    'pl': [
      'Koale', 'Czarownice', 'Mózgowcy', 'Nocne Sowy',
      'Brzydkie Kaczątka', 'Mrówcza Brygada', 'Na Ostatnią Chwilę',
      'Mistrzowie Quizu',
    ],
    'intl': [
      'The Koalas', 'The Witches', 'Brain Squad', 'Night Owls',
      'Ugly Ducklings', 'Ant Colony', 'Last Minute Club', 'Quiz Wizards',
    ],
  };

  /// Ülkeye uygun şehir/il adı — TR'de 81 İLİN TAMAMI: gösterimlerin ~%70'i
  /// nüfusa ağırlıklı (büyük iller sık), ~%30'u 81 il arasından eşit
  /// olasılıklı → küçük iller de (Ardahan, Bayburt, Tunceli…) düzenli
  /// aralıklarla mutlaka görünür. Diğer ülkelerde şehir havuzundan; havuzu
  /// olmayan ülkede boş döner.
  static String sampleCity(String countryCode, int seed) {
    final cc = _normCc(countryCode);
    final rng = _Rng(seed == 0 ? 1 : seed);
    if (cc == 'tr') {
      if (rng.nextInt(10) < 3) {
        // Eşit olasılıklı tur — 81 ilin hepsi eşit şansla.
        return _trCityWeights[rng.nextInt(_trCityWeights.length)].$1;
      }
      return _trCityWeighted(rng);
    }
    final cities = _cityPools[cc];
    if (cities == null || cities.isEmpty) return '';
    return cities[rng.nextInt(cities.length)];
  }

  // ── İsim üretimi ──────────────────────────────────────────────────────────
  /// "Elif K." biçimi — gerçek kişi izlenimi vermeden doğal görünür.
  static String _nameFor(String cc, _Rng rng) {
    final pool = _namePools[_poolKey(cc)] ?? _namePools['intl']!;
    final first = pool.$1[rng.nextInt(pool.$1.length)];
    final lastInitial = pool.$2[rng.nextInt(pool.$2.length)];
    return '$first $lastInitial.';
  }

  static String _poolKey(String cc) => _countryToPool[cc] ?? 'intl';

  static const _countryToPool = <String, String>{
    'tr': 'tr', 'az': 'tr',
    'us': 'en', 'gb': 'en', 'uk': 'en', 'ca': 'en', 'au': 'en', 'nz': 'en',
    'ie': 'en',
    'de': 'de', 'at': 'de', 'ch': 'de',
    'fr': 'fr', 'be': 'fr',
    'es': 'es', 'mx': 'es', 'ar': 'es', 'co': 'es', 'cl': 'es', 'pe': 'es',
    'br': 'pt', 'pt': 'pt',
    'eg': 'ar', 'sa': 'ar', 'ae': 'ar', 'jo': 'ar', 'ma': 'ar', 'dz': 'ar',
    'tn': 'ar', 'iq': 'ar', 'sy': 'ar', 'lb': 'ar',
    'ru': 'ru', 'kz': 'ru', 'ua': 'ru', 'kg': 'ru',
    'ir': 'fa',
    'in': 'hi', 'pk': 'hi', 'bd': 'hi',
    'id': 'id', 'my': 'id',
    'jp': 'ja',
    'kr': 'ko',
    'cn': 'zh',
    'it': 'it',
    'gr': 'el',
    'nl': 'nl',
    'pl': 'pl',
  };

  /// (ilk adlar, soyad baş harfleri) — baş harf havuzu kültüre uygun seçildi.
  static const _namePools = <String, (List<String>, List<String>)>{
    'tr': (
      ['Elif', 'Yusuf', 'Zeynep', 'Emir', 'Defne', 'Ali', 'Ecrin', 'Ömer',
       'Azra', 'Mert', 'Eylül', 'Kerem', 'Nisa', 'Baran', 'Duru', 'Çınar'],
      ['K', 'Y', 'A', 'D', 'S', 'T', 'B', 'Ç', 'E', 'G', 'Ö', 'M'],
    ),
    'en': (
      ['Emma', 'Liam', 'Olivia', 'Noah', 'Ava', 'Ethan', 'Mia', 'Lucas',
       'Sophie', 'Jack', 'Lily', 'Oscar', 'Grace', 'Henry', 'Ruby', 'Leo'],
      ['B', 'C', 'D', 'H', 'J', 'M', 'P', 'R', 'S', 'T', 'W', 'K'],
    ),
    'de': (
      ['Mia', 'Ben', 'Emma', 'Paul', 'Hannah', 'Jonas', 'Lea', 'Finn',
       'Anna', 'Luis', 'Marie', 'Felix', 'Lena', 'Max', 'Clara', 'Elias'],
      ['B', 'F', 'H', 'K', 'L', 'M', 'R', 'S', 'W', 'Z', 'G', 'N'],
    ),
    'fr': (
      ['Léa', 'Hugo', 'Chloé', 'Louis', 'Manon', 'Jules', 'Camille', 'Lucas',
       'Emma', 'Nathan', 'Inès', 'Théo', 'Jade', 'Gabriel', 'Zoé', 'Arthur'],
      ['B', 'D', 'F', 'G', 'L', 'M', 'P', 'R', 'C', 'V', 'T', 'S'],
    ),
    'es': (
      ['Lucía', 'Mateo', 'Sofía', 'Santiago', 'Valentina', 'Diego', 'Camila',
       'Daniel', 'Martina', 'Pablo', 'Emma', 'Álvaro', 'Julia', 'Hugo',
       'Paula', 'Adrián'],
      ['G', 'R', 'M', 'L', 'S', 'F', 'P', 'C', 'V', 'H', 'D', 'T'],
    ),
    'pt': (
      ['Alice', 'Miguel', 'Sophia', 'Arthur', 'Helena', 'Davi', 'Laura',
       'Gabriel', 'Valentina', 'Pedro', 'Cecília', 'Lucas', 'Lívia', 'Rafael',
       'Beatriz', 'Enzo'],
      ['S', 'O', 'C', 'P', 'A', 'L', 'R', 'F', 'M', 'B', 'G', 'T'],
    ),
    'ar': (
      ['Omar', 'Layla', 'Youssef', 'Fatima', 'Ahmed', 'Mariam', 'Karim',
       'Nour', 'Hassan', 'Salma', 'Ali', 'Huda', 'Tariq', 'Amira', 'Ziad',
       'Rania'],
      ['A', 'H', 'M', 'S', 'K', 'R', 'B', 'F', 'N', 'T', 'E', 'D'],
    ),
    'ru': (
      ['Sofia', 'Artem', 'Anna', 'Maxim', 'Alina', 'Ivan', 'Polina', 'Dmitri',
       'Ksenia', 'Nikita', 'Vera', 'Egor', 'Dasha', 'Kirill', 'Mila', 'Timur'],
      ['K', 'P', 'S', 'V', 'M', 'B', 'L', 'G', 'R', 'T', 'Z', 'N'],
    ),
    'fa': (
      ['Sara', 'Amir', 'Niloufar', 'Reza', 'Yasmin', 'Arman', 'Shirin',
       'Kian', 'Leila', 'Navid', 'Roya', 'Parsa', 'Mina', 'Danial', 'Setareh',
       'Ashkan'],
      ['A', 'M', 'R', 'S', 'K', 'H', 'N', 'T', 'J', 'F', 'B', 'G'],
    ),
    'hi': (
      ['Aarav', 'Ananya', 'Vihaan', 'Diya', 'Arjun', 'Ishita', 'Reyansh',
       'Saanvi', 'Ayaan', 'Myra', 'Kabir', 'Aditi', 'Vivaan', 'Kiara',
       'Dhruv', 'Navya'],
      ['S', 'P', 'K', 'R', 'M', 'G', 'V', 'J', 'B', 'D', 'N', 'T'],
    ),
    'id': (
      ['Putri', 'Budi', 'Sari', 'Adi', 'Dewi', 'Rizki', 'Ayu', 'Fajar',
       'Intan', 'Bayu', 'Citra', 'Dimas', 'Nadia', 'Eko', 'Ratna', 'Galih'],
      ['S', 'W', 'P', 'H', 'K', 'R', 'A', 'N', 'M', 'D', 'L', 'B'],
    ),
    'ja': (
      ['Yui', 'Haruto', 'Sakura', 'Sota', 'Hina', 'Ren', 'Aoi', 'Yuto',
       'Mio', 'Riku', 'Koharu', 'Hayato', 'Rin', 'Kaito', 'Mei', 'Sora'],
      ['S', 'T', 'K', 'M', 'N', 'H', 'Y', 'I', 'O', 'F', 'W', 'A'],
    ),
    'ko': (
      ['Seo-yeon', 'Min-jun', 'Ji-woo', 'Do-yun', 'Ha-eun', 'Ye-jun',
       'Su-bin', 'Ji-ho', 'Chae-won', 'Jun-seo', 'Da-eun', 'Si-woo',
       'Ye-rin', 'Ha-jun', 'Yu-na', 'Eun-woo'],
      ['K', 'L', 'P', 'C', 'J', 'S', 'H', 'Y', 'O', 'M', 'B', 'N'],
    ),
    'zh': (
      ['Wei', 'Xin', 'Hao', 'Mei', 'Jun', 'Ling', 'Yan', 'Tao', 'Fang',
       'Lei', 'Na', 'Bo', 'Jing', 'Kai', 'Yue', 'Cheng'],
      ['W', 'L', 'Z', 'C', 'H', 'Y', 'X', 'S', 'T', 'G', 'J', 'M'],
    ),
    'it': (
      ['Sofia', 'Leonardo', 'Giulia', 'Francesco', 'Aurora', 'Alessandro',
       'Ginevra', 'Lorenzo', 'Emma', 'Mattia', 'Beatrice', 'Tommaso',
       'Vittoria', 'Riccardo', 'Alice', 'Edoardo'],
      ['R', 'B', 'C', 'F', 'G', 'M', 'P', 'S', 'V', 'D', 'L', 'T'],
    ),
    'el': (
      ['Maria', 'Giorgos', 'Eleni', 'Nikos', 'Katerina', 'Dimitris',
       'Sofia', 'Kostas', 'Ioanna', 'Panos', 'Despina', 'Andreas',
       'Anna', 'Stavros', 'Christina', 'Vasilis'],
      ['P', 'K', 'M', 'S', 'T', 'G', 'D', 'A', 'V', 'L', 'C', 'N'],
    ),
    'nl': (
      ['Emma', 'Daan', 'Julia', 'Sem', 'Mila', 'Lucas', 'Tess', 'Finn',
       'Sophie', 'Levi', 'Zoë', 'Luuk', 'Saar', 'Jesse', 'Nora', 'Bram'],
      ['V', 'D', 'B', 'J', 'K', 'M', 'S', 'H', 'T', 'W', 'G', 'R'],
    ),
    'pl': (
      ['Zuzanna', 'Jakub', 'Julia', 'Antoni', 'Maja', 'Jan', 'Hanna',
       'Aleksander', 'Lena', 'Franciszek', 'Alicja', 'Mikołaj', 'Oliwia',
       'Wojciech', 'Pola', 'Stanisław'],
      ['K', 'N', 'W', 'S', 'M', 'Z', 'D', 'L', 'P', 'B', 'G', 'J'],
    ),
    // Karma uluslararası havuz — eşleşmeyen ülkeler için.
    'intl': (
      ['Maya', 'Adam', 'Lina', 'Sami', 'Nora', 'Dani', 'Sara', 'Alex',
       'Aya', 'Timo', 'Mira', 'Eli', 'Tara', 'Robin', 'Ela', 'Noel'],
      ['A', 'B', 'D', 'E', 'H', 'K', 'L', 'M', 'N', 'R', 'S', 'T'],
    ),
  };

  /// Dünya kapsamında demo öğrencilerin geldiği ülkeler.
  static const _worldCountries = <String>[
    'tr', 'de', 'us', 'gb', 'fr', 'es', 'it', 'br', 'mx', 'ar', 'eg', 'sa',
    'pk', 'in', 'id', 'jp', 'kr', 'ru', 'ua', 'pl', 'nl', 'ca', 'au', 'gr',
    'az', 'kz', 'ma', 'ng',
  ];

  /// TR — 81 ilin tamamı, yaklaşık nüfusla (bin kişi, TÜİK ~2023) ağırlıklı.
  /// Demo satırlarında şehir bu listeden kümülatif ağırlıkla seçilir:
  /// İstanbul en sık, ama Bayburt/Ardahan dahil her il görünebilir.
  static const _trCityWeights = <(String, int)>[
    ('İstanbul', 15907), ('Ankara', 5803), ('İzmir', 4479), ('Bursa', 3194),
    ('Antalya', 2688), ('Konya', 2296), ('Adana', 2274), ('Şanlıurfa', 2170),
    ('Gaziantep', 2154), ('Kocaeli', 2079), ('Mersin', 1916),
    ('Diyarbakır', 1804), ('Hatay', 1686), ('Manisa', 1468), ('Kayseri', 1441),
    ('Samsun', 1368), ('Balıkesir', 1257), ('Kahramanmaraş', 1177),
    ('Aydın', 1148), ('Tekirdağ', 1142), ('Van', 1128), ('Sakarya', 1080),
    ('Denizli', 1056), ('Muğla', 1049), ('Eskişehir', 906), ('Mardin', 870),
    ('Trabzon', 818), ('Malatya', 812), ('Ordu', 763), ('Erzurum', 749),
    ('Afyonkarahisar', 747), ('Sivas', 634), ('Batman', 634), ('Adıyaman', 604),
    ('Tokat', 596), ('Elazığ', 591), ('Zonguldak', 588), ('Kütahya', 575),
    ('Şırnak', 570), ('Çanakkale', 559), ('Osmaniye', 557), ('Çorum', 528),
    ('Ağrı', 511), ('Giresun', 461), ('Isparta', 449), ('Aksaray', 433),
    ('Yozgat', 418), ('Edirne', 414), ('Düzce', 405), ('Muş', 399),
    ('Kastamonu', 388), ('Uşak', 377), ('Kırklareli', 377), ('Niğde', 377),
    ('Bitlis', 353), ('Siirt', 347), ('Rize', 344), ('Amasya', 338),
    ('Bolu', 320), ('Nevşehir', 315), ('Yalova', 296), ('Kars', 285),
    ('Bingöl', 282), ('Kırıkkale', 277), ('Hakkari', 275), ('Burdur', 273),
    ('Karaman', 260), ('Karabük', 252), ('Kırşehir', 244), ('Erzincan', 239),
    ('Bilecik', 228), ('Sinop', 218), ('Bartın', 203), ('Iğdır', 203),
    ('Çankırı', 195), ('Artvin', 169), ('Kilis', 155), ('Gümüşhane', 144),
    ('Ardahan', 92), ('Tunceli', 89), ('Bayburt', 86),
  ];

  /// Kümülatif ağırlıkla il seçimi (toplam bir kez hesaplanıp saklanır).
  static int _trTotalWeight = 0;
  static String _trCityWeighted(_Rng rng) {
    if (_trTotalWeight == 0) {
      for (final e in _trCityWeights) {
        _trTotalWeight += e.$2;
      }
    }
    var r = rng.nextInt(_trTotalWeight);
    for (final e in _trCityWeights) {
      r -= e.$2;
      if (r < 0) return e.$1;
    }
    return _trCityWeights.first.$1;
  }

  /// Ülke kapsamı satırlarında görünen şehir adları (gerçek satırlarda
  /// cityCode insanlaştırılır; demo için küçük havuz yeterli).
  /// NOT: TR bu haritada değil — 81 il nüfus ağırlıklı [_trCityWeights]
  /// üzerinden seçilir.
  static const _cityPools = <String, List<String>>{
    'de': ['Berlin', 'Hamburg', 'München', 'Köln', 'Frankfurt'],
    'us': ['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix'],
    'gb': ['London', 'Manchester', 'Birmingham', 'Leeds', 'Glasgow'],
    'fr': ['Paris', 'Lyon', 'Marseille', 'Toulouse', 'Nice'],
    'es': ['Madrid', 'Barcelona', 'Valencia', 'Sevilla', 'Bilbao'],
    'it': ['Roma', 'Milano', 'Napoli', 'Torino', 'Bologna'],
    'br': ['São Paulo', 'Rio de Janeiro', 'Brasília', 'Salvador', 'Curitiba'],
    'mx': ['Ciudad de México', 'Guadalajara', 'Monterrey', 'Puebla'],
    'ar': ['Buenos Aires', 'Córdoba', 'Rosario', 'Mendoza'],
    'eg': ['Cairo', 'Alexandria', 'Giza', 'Mansoura'],
    'sa': ['Riyadh', 'Jeddah', 'Mecca', 'Dammam'],
    'in': ['Mumbai', 'Delhi', 'Bengaluru', 'Chennai', 'Kolkata'],
    'id': ['Jakarta', 'Surabaya', 'Bandung', 'Medan'],
    'jp': ['Tokyo', 'Osaka', 'Nagoya', 'Fukuoka', 'Sapporo'],
    'kr': ['Seoul', 'Busan', 'Incheon', 'Daegu'],
    'ru': ['Moskva', 'Sankt-Peterburg', 'Kazan', 'Novosibirsk'],
    'pl': ['Warszawa', 'Kraków', 'Wrocław', 'Gdańsk'],
    'nl': ['Amsterdam', 'Rotterdam', 'Utrecht', 'Eindhoven'],
    'az': ['Bakı', 'Gəncə', 'Sumqayıt'],
    'kz': ['Almatı', 'Astana', 'Şımkent'],
    'ua': ['Kyiv', 'Kharkiv', 'Odesa', 'Lviv'],
    'gr': ['Athina', 'Thessaloniki', 'Patra'],
    'ca': ['Toronto', 'Montréal', 'Vancouver', 'Calgary'],
    'au': ['Sydney', 'Melbourne', 'Brisbane', 'Perth'],
    'ma': ['Casablanca', 'Rabat', 'Marrakech', 'Fès'],
    'ng': ['Lagos', 'Abuja', 'Ibadan', 'Kano'],
    'pk': ['Karachi', 'Lahore', 'Islamabad', 'Faisalabad'],
    'ir': ['Tehran', 'Mashhad', 'Isfahan', 'Shiraz'],
    'bd': ['Dhaka', 'Chattogram', 'Khulna'],
  };

  static const _avatars = <String>[
    '🦊', '🐼', '🦁', '🐯', '🐨', '🦉', '🐧', '🦄', '🐸', '🐙', '🦋', '🐢',
    '🦜', '🐬', '🦖', '🐝', '🦔', '🐿️', '🦈', '🐳',
  ];

  // ── Yardımcılar ───────────────────────────────────────────────────────────
  /// Uygulama içi ülke kodu normalize — EduProfile 'uk' kullanır, bayrak/
  /// şehir havuzları ISO 'gb' bekler.
  static String _normCc(String cc) {
    final c = cc.toLowerCase().trim();
    return c == 'uk' ? 'gb' : c;
  }

  /// Ülkenin YEREL (native) adı — servis _countryName ile aynı yaklaşım.
  static String _countryName(String cc) {
    final lc = cc.toLowerCase() == 'gb' ? 'uk' : cc.toLowerCase();
    for (final c in kAllCountries) {
      if (c.key == lc) return c.name;
    }
    return cc.toUpperCase();
  }

  static String _humanCity(String code) {
    if (code.isEmpty) return '';
    final cleaned = code.replaceAll('_', ' ');
    if (cleaned.isEmpty) return code;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  static String _flag(String cc) {
    if (cc.length != 2) return '🌍';
    const baseLetter = 0x41;
    const baseRegional = 0x1F1E6;
    final upper = cc.toUpperCase();
    final c1 = upper.codeUnitAt(0);
    final c2 = upper.codeUnitAt(1);
    if (c1 < baseLetter || c1 > baseLetter + 25) return '🌍';
    if (c2 < baseLetter || c2 > baseLetter + 25) return '🌍';
    return String.fromCharCodes([
      baseRegional + (c1 - baseLetter),
      baseRegional + (c2 - baseLetter),
    ]);
  }

  /// FNV-1a 32-bit string hash — platformdan bağımsız deterministik seed.
  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final cu in s.codeUnits) {
      h ^= cu;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h == 0 ? 1 : h;
  }
}

/// Xorshift32 — dart:math Random yerine platform/versiyon bağımsız,
/// seed'e sadık deterministik üretici (demo liste her cihazda aynı olsun).
class _Rng {
  int _s;
  _Rng(int seed) : _s = seed & 0xFFFFFFFF;

  int _next() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x & 0xFFFFFFFF;
    return _s;
  }

  /// [0, max) tam sayı.
  int nextInt(int max) => _next() % max;

  /// [0, 1) double.
  double nextDouble() => _next() / 0x100000000;
}
