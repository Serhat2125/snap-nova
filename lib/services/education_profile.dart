import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  EĞİTİM PROFİLİ — ülke + seviye + sınıf + alan + fakülte
//  QuAlsar Arena'da kaydedilen profili her sayfanın okuyabilmesi için paylaşılır
// ═══════════════════════════════════════════════════════════════════════════════

class EduSubject {
  final String key;
  final String emoji;
  final String name;
  final Color color;
  const EduSubject(this.key, this.emoji, this.name, this.color);
}

/// Ülke kataloğu — dünya genelinden geniş liste (arama için)
class Country {
  final String key; // 'tr', 'us', 'de' vb. (ISO 3166-1 alpha-2'ye yakın)
  final String name;
  final String flag;
  const Country(this.key, this.name, this.flag);
}

/// Her ülkeyi destekler — ilk 8'de detaylı müfredat, diğerlerinde 'international' fallback
const List<Country> kAllCountries = [
  // Detaylı eğitim müfredatı olanlar (üstte) — ülkeler kendi dillerinde (endonym)
  Country('tr', 'Türkiye', '🇹🇷'),
  Country('us', 'United States', '🇺🇸'),
  Country('uk', 'United Kingdom', '🇬🇧'),
  Country('de', 'Deutschland', '🇩🇪'),
  Country('fr', 'France', '🇫🇷'),
  Country('jp', '日本', '🇯🇵'),
  Country('in', 'भारत / India', '🇮🇳'),
  // Diğer popüler ülkeler (international müfredat fallback kullanır)
  Country('af', 'افغانستان', '🇦🇫'),
  Country('al', 'Shqipëria', '🇦🇱'),
  Country('dz', 'الجزائر', '🇩🇿'),
  Country('ar', 'Argentina', '🇦🇷'),
  Country('am', 'Հայաստան', '🇦🇲'),
  Country('ao', 'Angola', '🇦🇴'),
  Country('au', 'Australia', '🇦🇺'),
  Country('at', 'Österreich', '🇦🇹'),
  Country('az', 'Azərbaycan', '🇦🇿'),
  Country('bh', 'البحرين', '🇧🇭'),
  Country('bd', 'বাংলাদেশ', '🇧🇩'),
  Country('by', 'Беларусь', '🇧🇾'),
  Country('be', 'België / Belgique', '🇧🇪'),
  Country('bo', 'Bolivia', '🇧🇴'),
  Country('ba', 'Bosna i Hercegovina', '🇧🇦'),
  Country('br', 'Brasil', '🇧🇷'),
  Country('bg', 'България', '🇧🇬'),
  Country('kh', 'កម្ពុជា', '🇰🇭'),
  Country('cm', 'Cameroun', '🇨🇲'),
  Country('ca', 'Canada', '🇨🇦'),
  Country('cl', 'Chile', '🇨🇱'),
  Country('cn', '中国', '🇨🇳'),
  Country('cd', 'RD Congo', '🇨🇩'),
  Country('co', 'Colombia', '🇨🇴'),
  Country('cr', 'Costa Rica', '🇨🇷'),
  Country('hr', 'Hrvatska', '🇭🇷'),
  Country('cu', 'Cuba', '🇨🇺'),
  Country('cy', 'Κύπρος', '🇨🇾'),
  Country('cz', 'Česko', '🇨🇿'),
  Country('dk', 'Danmark', '🇩🇰'),
  Country('do', 'República Dominicana', '🇩🇴'),
  Country('ec', 'Ecuador', '🇪🇨'),
  Country('eg', 'مصر', '🇪🇬'),
  Country('sv', 'El Salvador', '🇸🇻'),
  Country('ee', 'Eesti', '🇪🇪'),
  Country('et', 'ኢትዮጵያ', '🇪🇹'),
  Country('fi', 'Suomi', '🇫🇮'),
  Country('ge', 'საქართველო', '🇬🇪'),
  Country('gh', 'Ghana', '🇬🇭'),
  Country('gr', 'Ελλάδα', '🇬🇷'),
  Country('gt', 'Guatemala', '🇬🇹'),
  Country('hn', 'Honduras', '🇭🇳'),
  Country('hk', '香港 Hong Kong', '🇭🇰'),
  Country('hu', 'Magyarország', '🇭🇺'),
  Country('is', 'Ísland', '🇮🇸'),
  Country('id', 'Indonesia', '🇮🇩'),
  Country('ir', 'ایران', '🇮🇷'),
  Country('iq', 'العراق', '🇮🇶'),
  Country('ie', 'Éire / Ireland', '🇮🇪'),
  Country('il', 'ישראל', '🇮🇱'),
  Country('it', 'Italia', '🇮🇹'),
  Country('jm', 'Jamaica', '🇯🇲'),
  Country('jo', 'الأردن', '🇯🇴'),
  Country('kz', 'Қазақстан', '🇰🇿'),
  Country('ke', 'Kenya', '🇰🇪'),
  Country('xk', 'Kosova', '🇽🇰'),
  Country('kw', 'الكويت', '🇰🇼'),
  Country('kg', 'Кыргызстан', '🇰🇬'),
  Country('la', 'ລາວ', '🇱🇦'),
  Country('lv', 'Latvija', '🇱🇻'),
  Country('lb', 'لبنان', '🇱🇧'),
  Country('ly', 'ليبيا', '🇱🇾'),
  Country('lt', 'Lietuva', '🇱🇹'),
  Country('lu', 'Luxembourg', '🇱🇺'),
  Country('mk', 'Северна Македонија', '🇲🇰'),
  Country('my', 'Malaysia', '🇲🇾'),
  Country('mt', 'Malta', '🇲🇹'),
  Country('mg', 'Madagasikara', '🇲🇬'),
  Country('mx', 'México', '🇲🇽'),
  Country('md', 'Moldova', '🇲🇩'),
  Country('mc', 'Monaco', '🇲🇨'),
  Country('mn', 'Монгол', '🇲🇳'),
  Country('me', 'Crna Gora', '🇲🇪'),
  Country('ma', 'المغرب', '🇲🇦'),
  Country('mz', 'Moçambique', '🇲🇿'),
  Country('mm', 'မြန်မာ', '🇲🇲'),
  Country('np', 'नेपाल', '🇳🇵'),
  Country('nl', 'Nederland', '🇳🇱'),
  Country('nz', 'New Zealand', '🇳🇿'),
  Country('ni', 'Nicaragua', '🇳🇮'),
  Country('ng', 'Nigeria', '🇳🇬'),
  Country('kp', '조선민주주의인민공화국', '🇰🇵'),
  Country('no', 'Norge', '🇳🇴'),
  Country('om', 'عُمان', '🇴🇲'),
  Country('pk', 'پاکستان', '🇵🇰'),
  Country('ps', 'فلسطين', '🇵🇸'),
  Country('pa', 'Panamá', '🇵🇦'),
  Country('pe', 'Perú', '🇵🇪'),
  Country('ph', 'Pilipinas', '🇵🇭'),
  Country('pl', 'Polska', '🇵🇱'),
  Country('pt', 'Portugal', '🇵🇹'),
  Country('qa', 'قطر', '🇶🇦'),
  Country('ro', 'România', '🇷🇴'),
  Country('ru', 'Россия', '🇷🇺'),
  Country('sa', 'المملكة العربية السعودية', '🇸🇦'),
  Country('rs', 'Србија', '🇷🇸'),
  Country('sg', 'Singapore', '🇸🇬'),
  Country('sk', 'Slovensko', '🇸🇰'),
  Country('si', 'Slovenija', '🇸🇮'),
  Country('za', 'South Africa', '🇿🇦'),
  Country('kr', '대한민국', '🇰🇷'),
  Country('es', 'España', '🇪🇸'),
  Country('lk', 'ශ්‍රී ලංකා', '🇱🇰'),
  Country('sd', 'السودان', '🇸🇩'),
  Country('se', 'Sverige', '🇸🇪'),
  Country('ch', 'Schweiz / Suisse', '🇨🇭'),
  Country('sy', 'سوريا', '🇸🇾'),
  Country('tw', '臺灣', '🇹🇼'),
  Country('tj', 'Тоҷикистон', '🇹🇯'),
  Country('tz', 'Tanzania', '🇹🇿'),
  Country('th', 'ประเทศไทย', '🇹🇭'),
  Country('tn', 'تونس', '🇹🇳'),
  Country('tm', 'Türkmenistan', '🇹🇲'),
  Country('ug', 'Uganda', '🇺🇬'),
  Country('ua', 'Україна', '🇺🇦'),
  Country('ae', 'الإمارات العربية المتحدة', '🇦🇪'),
  Country('uy', 'Uruguay', '🇺🇾'),
  Country('uz', 'Oʻzbekiston', '🇺🇿'),
  Country('ve', 'Venezuela', '🇻🇪'),
  Country('vn', 'Việt Nam', '🇻🇳'),
  Country('ye', 'اليمن', '🇾🇪'),
  Country('zm', 'Zambia', '🇿🇲'),
  Country('zw', 'Zimbabwe', '🇿🇼'),
  // Genel fallback
  Country('international', 'International', '🌐'),
];

/// Detaylı müfredat olmayan ülkeler için 'international' müfredat kullanılır
const Set<String> _countriesWithDetailedCurriculum = {'tr', 'us', 'uk', 'de', 'fr', 'jp', 'in'};

/// Bir ülke için eğitim müfredat anahtarını döndürür
String curriculumKeyForCountry(String countryKey) {
  return _countriesWithDetailedCurriculum.contains(countryKey) ? countryKey : 'international';
}

class EduProfile {
  final String country; // tr, us, uk, de, fr, jp, in, international
  final String level; // primary, middle, high, exam_prep, university, masters, doctorate, other
  final String grade;
  final String? track;
  final String? faculty;
  const EduProfile({
    required this.country,
    required this.level,
    required this.grade,
    this.track,
    this.faculty,
  });

  static String _normalizeLevel(String raw) {
    switch (raw) {
      case 'ilkokul':
        return 'primary';
      case 'ortaokul':
        return 'middle';
      case 'lise':
        return 'high';
      case 'sinav_hazirlik':
        return 'exam_prep';
      case 'universite':
        return 'university';
      case 'yuksek_lisans':
        return 'masters';
      case 'doktora':
        return 'doctorate';
      case 'diger':
        return 'other';
      default:
        return raw;
    }
  }

  /// Uygulama genelinde mevcut öğrenci profili (cache).
  /// main.dart init'te yüklenir; EducationSetupScreen save'de güncellenir.
  /// Senkron erişim — gemini_service prompt inşasında kullanır.
  static EduProfile? current;

  static Future<EduProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final level = prefs.getString('mini_test_level');
    final grade = prefs.getString('mini_test_grade');
    if (level == null || grade == null) {
      current = null;
      return null;
    }
    final p = EduProfile(
      country: prefs.getString('mini_test_country') ?? 'tr',
      level: _normalizeLevel(level),
      grade: grade,
      track: prefs.getString('mini_test_track'),
      faculty: prefs.getString('mini_test_faculty'),
    );
    current = p;
    return p;
  }

  /// Türkçe seviye etiketi (üst başlıklarda gösterilir)
  String displayLabel() {
    final cn = _countryNames[country] ?? country;
    String label;
    switch (level) {
      case 'primary':
        label = 'İlkokul $grade';
        break;
      case 'middle':
        label = 'Ortaokul $grade';
        break;
      case 'high':
        label = 'Lise $grade';
        if (track != null) label = '$label · ${_trackLabel(track!)}';
        break;
      case 'exam_prep':
        label = 'Sınava Hazırlık: $grade';
        break;
      case 'university':
        final f = faculty != null ? _facultyNames[faculty!] ?? faculty! : 'Üniversite';
        label = '$f · $grade';
        break;
      case 'masters':
        label = 'Yüksek Lisans';
        if (faculty != null) label = '${_facultyNames[faculty!] ?? faculty!} · $label';
        break;
      case 'doctorate':
        label = 'Doktora';
        if (faculty != null) label = '${_facultyNames[faculty!] ?? faculty!} · $label';
        break;
      default:
        label = 'Serbest';
    }
    return '$cn · $label';
  }

  static const Map<String, String> _countryNames = {
    'tr': '🇹🇷 Türkiye',
    'us': '🇺🇸 ABD',
    'uk': '🇬🇧 UK',
    'de': '🇩🇪 Almanya',
    'fr': '🇫🇷 Fransa',
    'jp': '🇯🇵 Japonya',
    'in': '🇮🇳 Hindistan',
    'international': '🌐 Uluslararası',
  };

  static String _trackLabel(String t) {
    const labels = {
      'sayisal': 'Sayısal',
      'sozel': 'Sözel',
      'esit_agirlik': 'Eşit Ağırlık',
      'dil': 'Dil',
      'regular': 'Regular',
      'honors': 'Honors',
      'ap': 'AP',
      'ib': 'IB',
      'sciences': 'Sciences',
      'humanities': 'Humanities',
      'languages': 'Languages',
      'maths': 'Maths',
      'naturwiss': 'Naturwissenschaften',
      'sprachen': 'Sprachen',
      'gesell': 'Gesellschaftswiss.',
      'kunst': 'Kunst',
      'general': 'Bac Général',
      'tech': 'Bac Technologique',
      'pro': 'Bac Professionnel',
      'futsu': '普通科',
      'senmon': '専門学科',
      'science': 'Science',
      'commerce': 'Commerce',
      'arts': 'Arts',
      'mixed': 'Mixed',
      'language': 'Language',
    };
    return labels[t] ?? t;
  }

  static const Map<String, String> _facultyNames = {
    'tip': 'Tıp',
    'dis_hekimligi': 'Diş Hekimliği',
    'eczacilik': 'Eczacılık',
    'veteriner': 'Veterinerlik',
    'hukuk': 'Hukuk',
    'psikoloji': 'Psikoloji',
    'bilgisayar_muh': 'Bilgisayar Mühendisliği',
    'yazilim_muh': 'Yazılım Mühendisliği',
    'elektrik_elektronik_muh': 'Elektrik-Elektronik Müh.',
    'endustri_muh': 'Endüstri Mühendisliği',
    'makine_muh': 'Makine Mühendisliği',
    'insaat_muh': 'İnşaat Mühendisliği',
    'mimarlik': 'Mimarlık',
    'isletme': 'İşletme',
    'iktisat': 'İktisat',
    'uluslararasi_iliskiler': 'Uluslararası İlişkiler',
    // Kısa liste, tam harita qualsar_arena içinde
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DERSLER — ülke × seviye × (sınıf × alan)
// ═══════════════════════════════════════════════════════════════════════════════

const _blue = Color(0xFF2563EB);
const _purple = Color(0xFF8B5CF6);
const _green = Color(0xFF10B981);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFEF4444);
const _brown = Color(0xFFA16207);
const _cyan = Color(0xFF0891B2);
const _pink = Color(0xFFDB2777);
const _teal = Color(0xFF0F766E);
const _indigo = Color(0xFF4F46E5);
const _success = Color(0xFF059669);
const _orange = Color(0xFFFF6A00);
const _slate = Color(0xFF475569);
const _gold = Color(0xFFFFB800);

// Tüm bilinen dersler (key → subject)
const Map<String, EduSubject> _allSubjects = {
  'math': EduSubject('math', '📐', 'Matematik', _blue),
  'physics': EduSubject('physics', '⚛️', 'Fizik', _purple),
  'chem': EduSubject('chem', '🧪', 'Kimya', _green),
  'bio': EduSubject('bio', '🧬', 'Biyoloji', _amber),
  'turkish': EduSubject('turkish', '📖', 'Türkçe', _red),
  'lit': EduSubject('lit', '✒️', 'Edebiyat', _pink),
  'history': EduSubject('history', '🏛️', 'Tarih', _brown),
  'geo': EduSubject('geo', '🌍', 'Coğrafya', _cyan),
  'din_kultur': EduSubject('din_kultur', '📿', 'Din Kültürü', _teal),
  'ingilizce': EduSubject('ingilizce', '🇬🇧', 'İngilizce', _blue),
  'beden': EduSubject('beden', '⚽', 'Beden Eğitimi', _success),
  'sanat_muzik': EduSubject('sanat_muzik', '🎨', 'Sanat / Müzik', _pink),
  'felsefe': EduSubject('felsefe', '🤔', 'Felsefe', _purple),
  'ikinci_dil': EduSubject('ikinci_dil', '🗣️', '2. Yabancı Dil', _indigo),
  'psikoloji_dersi': EduSubject('psikoloji_dersi', '🧠', 'Psikoloji', _pink),
  'sosyoloji': EduSubject('sosyoloji', '👥', 'Sosyoloji', _cyan),
  'mantik': EduSubject('mantik', '🧩', 'Mantık', _indigo),
  'girisimcilik': EduSubject('girisimcilik', '🚀', 'Girişimcilik', _red),
  'demokrasi': EduSubject('demokrasi', '🗳️', 'İnsan Hakları', _cyan),
  'kuran': EduSubject('kuran', '📿', 'Kur\'an-ı Kerim', _teal),
  'temel_din': EduSubject('temel_din', '🕌', 'Temel Din', _teal),
  'peygamber_hayat': EduSubject('peygamber_hayat', '📜', 'Peygamber Hayatı', _teal),
  'drama': EduSubject('drama', '🎭', 'Drama', _pink),
  'yazarlik': EduSubject('yazarlik', '✍️', 'Yazarlık', _brown),
  'cagdas_tarih': EduSubject('cagdas_tarih', '🌐', 'Çağdaş Tarih', _brown),
  'kultur_tarihi': EduSubject('kultur_tarihi', '🏺', 'Kültür Tarihi', _brown),
  // ABD
  'us_history': EduSubject('us_history', '🇺🇸', 'US History', _brown),
  'world_history': EduSubject('world_history', '📜', 'World History', _brown),
  'english_lang': EduSubject('english_lang', '📖', 'English Language', _red),
  'spanish': EduSubject('spanish', '🇪🇸', 'Spanish', _indigo),
  'electives': EduSubject('electives', '🎓', 'Electives', _slate),
  // UK
  'english_lit': EduSubject('english_lit', '📚', 'English Literature', _red),
  're': EduSubject('re', '📿', 'Religious Education', _teal),
  'mfl': EduSubject('mfl', '🗣️', 'Modern Foreign Language', _indigo),
  // Almanya
  'deutsch': EduSubject('deutsch', '📖', 'Deutsch', _red),
  'politik': EduSubject('politik', '🏛️', 'Politik', _cyan),
  'religion_ethik': EduSubject('religion_ethik', '📿', 'Religion / Ethik', _teal),
  // Fransa
  'francais': EduSubject('francais', '📖', 'Français', _red),
  'histoire_geo': EduSubject('histoire_geo', '🏛️', 'Histoire-Géographie', _brown),
  'svt': EduSubject('svt', '🧬', 'SVT', _amber),
  'physique_chimie': EduSubject('physique_chimie', '⚛️', 'Physique-Chimie', _purple),
  'philo': EduSubject('philo', '🤔', 'Philosophie', _purple),
  // Japonya
  'kokugo': EduSubject('kokugo', '📖', '国語 Kokugo', _red),
  'shakai': EduSubject('shakai', '🏛️', '社会 Shakai', _cyan),
  'rika': EduSubject('rika', '🔬', '理科 Rika', _purple),
  // Hindistan
  'hindi': EduSubject('hindi', '📖', 'Hindi', _red),
  'sanskrit': EduSubject('sanskrit', '📜', 'Sanskrit', _teal),
  'accountancy': EduSubject('accountancy', '📊', 'Accountancy', _gold),
  'economics': EduSubject('economics', '💰', 'Economics', _gold),
  'business_studies': EduSubject('business_studies', '💼', 'Business Studies', _slate),
  'political_science': EduSubject('political_science', '🗳️', 'Political Science', _cyan),
  'computer_science': EduSubject('computer_science', '💻', 'Computer Science', _indigo),
  // Üniversite generic
  'anatomi': EduSubject('anatomi', '🦴', 'Anatomi', _red),
  'fizyoloji': EduSubject('fizyoloji', '💓', 'Fizyoloji', _red),
  'algoritma': EduSubject('algoritma', '🧮', 'Algoritmalar', _indigo),
  'veri_yapi': EduSubject('veri_yapi', '📊', 'Veri Yapıları', _purple),
  'statik': EduSubject('statik', '⚖️', 'Statik', _teal),
  'mukavemet': EduSubject('mukavemet', '💪', 'Mukavemet', _cyan),
  // Orange for custom
  'custom': EduSubject('custom', '📚', 'Diğer', _orange),
};

// Ülke × seviye × sınıf × alan → ders anahtarları
// Türkiye müfredatı detaylı (sınıf+alan), diğer ülkeler seviye bazlı
final Map<String, List<String>> _subjectKeysByProfile = {
  // 🇹🇷 Türkiye
  'tr_primary': ['math', 'turkish', 'sanat_muzik', 'beden', 'ingilizce', 'din_kultur'],
  'tr_middle': ['math', 'turkish', 'history', 'geo', 'ingilizce', 'din_kultur', 'beden', 'sanat_muzik'],
  'tr_high_9': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo',
    'din_kultur', 'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'mantik',
  ],
  'tr_high_10_sayisal': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo',
    'din_kultur', 'ingilizce', 'beden', 'sanat_muzik', 'mantik', 'drama',
  ],
  'tr_high_10_esit_agirlik': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo',
    'din_kultur', 'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'mantik',
    'yazarlik', 'temel_din', 'kuran', 'peygamber_hayat',
  ],
  'tr_high_10_sozel': [
    'lit', 'math', 'history', 'geo', 'din_kultur',
    'ingilizce', 'beden', 'sanat_muzik', 'ikinci_dil', 'mantik',
    'drama', 'yazarlik', 'felsefe',
  ],
  'tr_high_10_dil': [
    'lit', 'math', 'history', 'geo', 'din_kultur',
    'ingilizce', 'ikinci_dil', 'beden', 'sanat_muzik', 'drama', 'yazarlik',
  ],
  'tr_high_11_sayisal': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo', 'felsefe',
    'din_kultur', 'ingilizce', 'beden', 'mantik', 'girisimcilik',
  ],
  'tr_high_11_esit_agirlik': [
    'lit', 'math', 'history', 'geo', 'felsefe', 'physics', 'chem', 'bio',
    'din_kultur', 'ingilizce', 'beden', 'psikoloji_dersi', 'sosyoloji', 'mantik',
    'ikinci_dil', 'girisimcilik', 'demokrasi', 'kuran', 'temel_din',
  ],
  'tr_high_11_sozel': [
    'lit', 'math', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'beden', 'psikoloji_dersi', 'sosyoloji', 'mantik',
    'ikinci_dil', 'girisimcilik', 'demokrasi',
  ],
  'tr_high_11_dil': [
    'lit', 'math', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'ikinci_dil', 'beden', 'mantik', 'girisimcilik',
  ],
  'tr_high_12_sayisal': [
    'lit', 'math', 'physics', 'chem', 'bio', 'history', 'geo', 'felsefe',
    'din_kultur', 'ingilizce', 'beden', 'mantik', 'girisimcilik', 'cagdas_tarih',
  ],
  'tr_high_12_esit_agirlik': [
    'lit', 'math', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'beden', 'psikoloji_dersi', 'sosyoloji', 'mantik',
    'cagdas_tarih', 'kultur_tarihi', 'ikinci_dil', 'girisimcilik',
    'kuran', 'peygamber_hayat',
  ],
  'tr_high_12_sozel': [
    'lit', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'beden', 'psikoloji_dersi', 'sosyoloji', 'mantik',
    'cagdas_tarih', 'kultur_tarihi', 'ikinci_dil', 'girisimcilik',
  ],
  'tr_high_12_dil': [
    'lit', 'history', 'geo', 'felsefe', 'din_kultur',
    'ingilizce', 'ikinci_dil', 'beden', 'mantik', 'girisimcilik',
    'cagdas_tarih',
  ],
  'tr_university': ['math', 'physics', 'chem', 'bio', 'history', 'lit', 'felsefe', 'ingilizce'],

  // 🇺🇸 ABD — Common Core temelli
  'us_primary': ['math', 'english_lang', 'sanat_muzik', 'beden', 'history'],
  'us_middle': ['math', 'english_lang', 'bio', 'us_history', 'world_history', 'spanish', 'beden', 'sanat_muzik', 'computer_science'],
  'us_high': [
    'math', 'english_lang', 'english_lit', 'physics', 'chem', 'bio',
    'us_history', 'world_history', 'geo', 'spanish', 'beden', 'sanat_muzik',
    'computer_science', 'psikoloji_dersi', 'economics', 'electives',
  ],
  'us_university': ['math', 'physics', 'chem', 'bio', 'world_history', 'english_lit', 'felsefe', 'economics'],

  // 🇬🇧 UK — National Curriculum + GCSE/A-Level
  'uk_primary': ['math', 'english_lang', 'sanat_muzik', 'beden', 're'],
  'uk_middle': ['math', 'english_lang', 'physics', 'chem', 'bio', 'history', 'geo', 'mfl', 're', 'beden', 'sanat_muzik', 'computer_science'],
  'uk_high': [
    'math', 'english_lang', 'english_lit', 'physics', 'chem', 'bio',
    'history', 'geo', 'felsefe', 'mfl', 're', 'beden', 'sanat_muzik',
    'psikoloji_dersi', 'economics', 'computer_science',
  ],
  'uk_university': ['math', 'physics', 'chem', 'bio', 'english_lit', 'history', 'felsefe', 'economics'],

  // 🇩🇪 Almanya — KMK
  'de_primary': ['math', 'deutsch', 'sanat_muzik', 'beden', 'ingilizce', 'religion_ethik'],
  'de_middle': ['math', 'deutsch', 'physics', 'chem', 'bio', 'history', 'geo', 'ingilizce', 'ikinci_dil', 'politik', 'religion_ethik', 'beden', 'sanat_muzik'],
  'de_high': [
    'math', 'deutsch', 'physics', 'chem', 'bio', 'history', 'geo',
    'felsefe', 'ingilizce', 'ikinci_dil', 'politik', 'religion_ethik',
    'beden', 'sanat_muzik', 'psikoloji_dersi', 'sosyoloji', 'computer_science',
  ],
  'de_university': ['math', 'physics', 'chem', 'bio', 'history', 'deutsch', 'felsefe'],

  // 🇫🇷 Fransa — Éducation nationale
  'fr_primary': ['math', 'francais', 'sanat_muzik', 'beden'],
  'fr_middle': ['math', 'francais', 'svt', 'physique_chimie', 'histoire_geo', 'ingilizce', 'ikinci_dil', 'beden', 'sanat_muzik'],
  'fr_high': [
    'math', 'francais', 'philo', 'svt', 'physique_chimie',
    'histoire_geo', 'ingilizce', 'ikinci_dil', 'beden', 'sanat_muzik',
    'economics',
  ],
  'fr_university': ['math', 'physique_chimie', 'svt', 'histoire_geo', 'francais', 'philo'],

  // 🇯🇵 Japonya — Monbushō
  'jp_primary': ['math', 'kokugo', 'sanat_muzik', 'beden', 'shakai'],
  'jp_middle': ['math', 'kokugo', 'rika', 'shakai', 'ingilizce', 'beden', 'sanat_muzik', 'computer_science'],
  'jp_high': [
    'math', 'kokugo', 'physics', 'chem', 'bio', 'shakai',
    'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik', 'computer_science',
  ],
  'jp_university': ['math', 'physics', 'chem', 'bio', 'history', 'kokugo', 'felsefe'],

  // 🇮🇳 Hindistan — CBSE/ICSE
  'in_primary': ['math', 'english_lang', 'hindi', 'sanat_muzik', 'beden'],
  'in_middle': ['math', 'english_lang', 'hindi', 'physics', 'chem', 'bio', 'history', 'geo', 'computer_science', 'sanskrit', 'beden', 'sanat_muzik'],
  'in_high_science': [
    'physics', 'chem', 'bio', 'math', 'computer_science',
    'english_lang', 'hindi', 'beden', 'sanat_muzik',
  ],
  'in_high_commerce': [
    'accountancy', 'business_studies', 'economics', 'math',
    'english_lang', 'hindi', 'computer_science', 'beden',
  ],
  'in_high_arts': [
    'history', 'geo', 'political_science', 'psikoloji_dersi', 'sosyoloji',
    'english_lang', 'hindi', 'sanat_muzik', 'beden',
  ],
  'in_university': ['math', 'physics', 'chem', 'bio', 'history', 'english_lang', 'felsefe'],

  // 🌐 International (generic)
  'international_primary': ['math', 'english_lang', 'sanat_muzik', 'beden', 'history'],
  'international_middle': ['math', 'english_lang', 'bio', 'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik', 'computer_science'],
  'international_high': [
    'math', 'english_lang', 'physics', 'chem', 'bio',
    'history', 'geo', 'felsefe', 'ingilizce', 'beden', 'sanat_muzik',
    'psikoloji_dersi', 'economics', 'computer_science',
  ],
  'international_university': ['math', 'physics', 'chem', 'bio', 'history', 'english_lang', 'felsefe'],
};

const List<String> _fallbackKeys = ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'ingilizce'];

List<EduSubject> subjectsForProfile(EduProfile? profile) {
  if (profile == null) return _fallbackKeys.map((k) => _allSubjects[k]!).toList();

  // Türkiye lise için sınıf+alan dene
  if (profile.country == 'tr' && profile.level == 'high') {
    if (profile.track != null) {
      final k = 'tr_high_${profile.grade}_${profile.track}';
      final list = _subjectKeysByProfile[k];
      if (list != null) {
        return list.map((s) => _allSubjects[s]).whereType<EduSubject>().toList();
      }
    }
    // Alan yoksa 9. sınıf müfredatı
    final g9 = _subjectKeysByProfile['tr_high_9'];
    if (g9 != null) return g9.map((s) => _allSubjects[s]).whereType<EduSubject>().toList();
  }

  // Hindistan lise için alan bazlı
  if (profile.country == 'in' && profile.level == 'high' && profile.track != null) {
    final k = 'in_high_${profile.track}';
    final list = _subjectKeysByProfile[k];
    if (list != null) {
      return list.map((s) => _allSubjects[s]).whereType<EduSubject>().toList();
    }
  }

  // Diğer: country × level
  final k = '${profile.country}_${profile.level}';
  final list = _subjectKeysByProfile[k];
  if (list != null) {
    return list.map((s) => _allSubjects[s]).whereType<EduSubject>().toList();
  }
  return _fallbackKeys.map((k) => _allSubjects[k]!).toList();
}

/// AI prompt'una eklenecek bağlam metni.
/// Ülke+sınıf+alan bilgisi + o dönem okutulan dersler + konu başlıkları.
/// `curriculum_catalog.dart` otomatik olarak çağrılır; AI öğrencinin tam
/// müfredatını bilir, seviyeye uygun terminoloji + derinlik kullanır.
String educationContext(EduProfile? p) {
  if (p == null) return '';
  final base = 'Öğrenci profili: ${p.displayLabel()}. Soruları ve açıklamaları bu seviyeye uygun hazırla.';
  // curriculum_catalog.dart'tan detaylı müfredat bağlamı — eğer mevcutsa ekle
  try {
    // ignore: unused_import, avoid_dynamic_calls
    final detailed = _detailedCurriculumContext(p);
    if (detailed.isNotEmpty) return '$base\n$detailed';
  } catch (_) {}
  return base;
}

/// `curriculum_catalog.dart` importunu tek bir yerde çağır. Böylece
/// döngüsel import riski ortadan kalkar (curriculum_catalog, profile'ı
/// kullanır; profile, catalog'u çağırır — sadece function pointer).
String Function(EduProfile)? _curriculumContextBuilder;

/// curriculum_catalog.dart başlangıçta kendini buraya kaydeder.
void registerCurriculumContextBuilder(String Function(EduProfile) fn) {
  _curriculumContextBuilder = fn;
}

String _detailedCurriculumContext(EduProfile p) {
  final fn = _curriculumContextBuilder;
  if (fn == null) return '';
  return fn(p);
}
