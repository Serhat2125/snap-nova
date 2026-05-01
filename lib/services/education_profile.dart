import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  EĞİTİM PROFİLİ — ülke + seviye + sınıf + alan + fakülte
//  QuAlsar Arena'da kaydedilen profili her sayfanın okuyabilmesi için paylaşılır
// ═══════════════════════════════════════════════════════════════════════════════

/// Seçmeli ders anahtarları — bu derslerin grid'te ana 8 yerine "Diğer
/// Dersler" sekmesinde görünmesi tercih edilir. UI'da sıralama:
///   1) Çekirdek dersler — kullanım sıklığına göre azalan,
///   2) Seçmeliler — kullanım sıklığına göre azalan; tümü overflow'a düşer.
const Set<String> kElectiveSubjectKeys = {
  // Türkiye lise seçmeli/tamamlayıcı
  'beden', 'sanat_muzik', 'din_kultur', 'ikinci_dil',
  'drama', 'yazarlik', 'kuran', 'temel_din', 'peygamber_hayat',
  'girisimcilik', 'demokrasi',
  // Diğer ülkeler benzeri
  're', 'mfl', 'religion_ethik', 'sanskrit',
  'electives',
};

bool isElectiveSubjectKey(String key) =>
    kElectiveSubjectKeys.contains(key);

/// Kullanıcının ders kullanım istatistiklerini birleştiren yardımcı.
/// Kaynaklar:
///   • `library_activity_log_v2` (özet + soru üretim olayları)
///   • `arena_subject_play_counts_v1` (yarışma oturumları)
/// Ders adı (lowercase trim) → toplam etkinlik sayısı.
class SubjectUsageStats {
  static const _activityKey = 'library_activity_log_v2';
  static const _arenaKey = 'arena_subject_play_counts_v1';

  static String _norm(String s) => s.trim().toLowerCase();

  static Future<Map<String, int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, int>{};
    final list = prefs.getStringList(_activityKey) ?? [];
    for (final s in list) {
      try {
        final j = jsonDecode(s) as Map<String, dynamic>;
        final subject = (j['subject'] as String?)?.trim() ?? '';
        if (subject.isEmpty) continue;
        final k = _norm(subject);
        out[k] = (out[k] ?? 0) + 1;
      } catch (_) {}
    }
    final arenaRaw = prefs.getString(_arenaKey);
    if (arenaRaw != null) {
      try {
        final m = jsonDecode(arenaRaw) as Map<String, dynamic>;
        m.forEach((k, v) {
          if (v is num) {
            final key = _norm(k);
            out[key] = (out[key] ?? 0) + v.toInt();
          }
        });
      } catch (_) {}
    }
    return out;
  }

  static Future<void> incrementArena(String subjectName) async {
    final key = subjectName.trim();
    if (key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_arenaKey);
    final m = <String, int>{};
    if (raw != null) {
      try {
        final dec = jsonDecode(raw) as Map<String, dynamic>;
        dec.forEach((k, v) {
          if (v is num) m[k] = v.toInt();
        });
      } catch (_) {}
    }
    m[key] = (m[key] ?? 0) + 1;
    await prefs.setString(_arenaKey, jsonEncode(m));
  }
}

/// Çekirdek (kullanım azalan) → Seçmeli (kullanım azalan) sırasına dizer.
/// `usageByName` anahtarları ders adının normalize hali (trim+lowercase).
List<EduSubject> orderSubjectsByUsage(
  List<EduSubject> subjects,
  Map<String, int> usageByName,
) {
  String norm(String s) => s.trim().toLowerCase();
  final core = <EduSubject>[];
  final electives = <EduSubject>[];
  for (final s in subjects) {
    if (isElectiveSubjectKey(s.key)) {
      electives.add(s);
    } else {
      core.add(s);
    }
  }
  int u(EduSubject s) => usageByName[norm(s.name)] ?? 0;
  // Stable sort: kullanım eşitse orijinal sıra korunur (Dart List.sort stable).
  core.sort((a, b) => u(b).compareTo(u(a)));
  electives.sort((a, b) => u(b).compareTo(u(a)));
  return [...core, ...electives];
}

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

  // ───────── AI tarafından üretilen müfredat cache'i ─────────────────────
  // Static `_curriculum` haritasında olmayan ülke/seviye/sınıf kombinasyonu
  // seçildiğinde AI runtime'da o profilin derslerini + konularını üretir.
  // Cache iki kademeli: subjects (görsel meta) + topics (konu listesi).
  // Library / Arena / Konu Özeti bunu gösterir.
  static final Map<String, List<EduSubject>> _aiSubjectCache = {};
  /// Profil imzası → ders_key → konu listesi. AI fetch'i tarafından doldurulur.
  static final Map<String, Map<String, List<String>>> _aiTopicsCache = {};

  /// Bir profil için unique key — country/level/grade/faculty/track.
  static String _signature(EduProfile p) =>
      '${p.country}|${p.level}|${p.grade}|${p.faculty ?? ''}|${p.track ?? ''}';

  static String _aiPrefsKey(EduProfile p) =>
      'ai_subjects_cache_v1::${_signature(p)}';

  /// Mevcut profil için AI cache'i pref'ten yükler (senkron sonrası kullanım).
  /// main.dart EduProfile.load sonrası bunu çağırır.
  static Future<void> loadAiSubjectCache() async {
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aiPrefsKey(current!));
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _aiSubjectCache[_signature(current!)] = list
          .map((e) => EduSubject(
                (e['key'] ?? 'custom').toString(),
                (e['emoji'] ?? '📚').toString(),
                (e['name'] ?? 'Ders').toString(),
                _blue,
              ))
          .toList();
    } catch (_) {}
  }

  /// Mevcut profil için AI cache'i kaydet — fetcher (gemini_service) çağırır.
  /// `subjects` her elemanı: `{key, name, emoji, topics?: comma-separated}`.
  /// Topics varsa `_aiTopicsCache`'e de yazılır.
  static Future<void> saveAiSubjectCache(
      EduProfile p, List<Map<String, String>> subjects) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiPrefsKey(p), jsonEncode(subjects));
    _aiSubjectCache[_signature(p)] = subjects
        .map((e) => EduSubject(
              e['key'] ?? 'custom',
              e['emoji'] ?? '📚',
              e['name'] ?? 'Ders',
              _blue,
            ))
        .toList();
  }

  /// AI'dan gelen "ders_key → konular" haritasını cache'le.
  /// curriculum_catalog `curriculumFor()` bu cache'i öncelikli okur.
  static Future<void> saveAiTopicsCache(
      EduProfile p, Map<String, List<String>> topicsBySubject) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'ai_topics_cache_v1::${_signature(p)}',
      jsonEncode(topicsBySubject),
    );
    _aiTopicsCache[_signature(p)] = topicsBySubject;
  }

  /// Profil için topics cache (in-memory). curriculum_catalog kullanır.
  static Map<String, List<String>>? aiCachedTopics(EduProfile p) =>
      _aiTopicsCache[_signature(p)];

  /// AI topics cache'i pref'ten yükle (uygulama açılışında).
  static Future<void> loadAiTopicsCache() async {
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ai_topics_cache_v1::${_signature(current!)}');
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, List<String>>{};
      decoded.forEach((k, v) {
        if (v is List) {
          out[k] = v.map((e) => e.toString()).toList();
        }
      });
      _aiTopicsCache[_signature(current!)] = out;
    } catch (_) {}
  }

  /// Profil için cache var mı?
  static List<EduSubject>? aiCachedSubjects(EduProfile p) =>
      _aiSubjectCache[_signature(p)];

  /// Cihaz locale'ine göre ülkeyi otomatik tespit eder ve `mini_test_country`
  /// pref'ine yazar (yalnızca pref boşsa). Onboarding ülke seçici bu pref'i
  /// varsayılan olarak kullanır → kullanıcının ülkesi otomatik seçili gelir.
  ///
  /// `gb` → `uk` map'lenir; desteklenen ülkeler dışında ise `international`.
  static Future<void> autoDetectCountryIfMissing() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('mini_test_country') != null) return;
    String? raw;
    try {
      raw = ui.PlatformDispatcher.instance.locale.countryCode?.toLowerCase();
    } catch (_) {}
    String detected = 'international';
    if (raw != null && raw.isNotEmpty) {
      final mapped = raw == 'gb' ? 'uk' : raw;
      if (_countriesWithDetailedCurriculum.contains(mapped)) {
        detected = mapped;
      } else {
        // Detaylı müfredatı olmayan ülkeler için ham ülke kodunu da sakla;
        // kAllCountries'te varsa picker bu kodu seçili gösterir.
        final inAll = kAllCountries.any((c) => c.key == mapped);
        if (inAll) detected = mapped;
      }
    }
    await prefs.setString('mini_test_country', detected);
  }

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

  /// Türkçe seviye etiketi (üst başlıklarda gösterilir).
  /// Ülke adı: önce kısa map (TR/ABD/Almanya...), yoksa tüm ülke listesinden
  /// (kAllCountries) bayrak + endonim ad alınır → 58 ülkenin tamamı için
  /// "🇧🇷 Brasil · Lise 11" gibi anlamlı etiket çıkar.
  String displayLabel() {
    String cn = _countryNames[country] ?? '';
    if (cn.isEmpty) {
      try {
        final c = kAllCountries.firstWhere((c) => c.key == country);
        cn = '${c.flag} ${c.name}';
      } catch (_) {
        cn = country;
      }
    }
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
        // Sınav anahtarlarını insan-okur etikete çevir.
        // TR + uluslararası sınavlar tek haritada.
        const examLabels = {
          // TR
          'yks_tyt': 'YKS · TYT',
          'yks_ayt': 'YKS · AYT',
          'yks': 'YKS',
          'lgs': 'LGS',
          'msu': 'MSÜ',
          'kpss': 'KPSS Lisans',
          'kpss_ortaogretim': 'KPSS Ortaöğretim',
          'dgs': 'DGS',
          'pmyo': 'PMYO',
          'ales': 'ALES',
          'yds': 'YDS / YÖKDİL',
          // Uluslararası
          'sat': 'SAT',
          'act': 'ACT',
          'ib': 'IB Diploma',
          'alevel': 'A-Level',
          'gcse': 'GCSE',
          'ielts': 'IELTS',
          'toefl': 'TOEFL',
          'duolingo': 'Duolingo English Test',
          'gre': 'GRE',
          'gmat': 'GMAT',
          'national_exam': 'National School-Leaving Exam',
          'university_entrance': 'University Entrance Exam',
          // Diğer ülke önemli sınavlar
          'gaokao': 'Gaokao 高考',
          'jee_main': 'JEE Main',
          'jee_adv': 'JEE Advanced',
          'neet': 'NEET',
          'suneung': '수능 (CSAT)',
          'kyotsu': '共通テスト',
          'abitur': 'Abitur',
          'bac': 'Baccalauréat',
          'matura': 'Matura',
          'maturita': 'Maturità',
        };
        final pretty = examLabels[grade.toLowerCase()] ?? grade;
        label = 'Sınava Hazırlık: $pretty';
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
  // Üniversite — Sağlık (Tıp / Diş / Eczacılık / Veterinerlik / Hemşirelik)
  'anatomi': EduSubject('anatomi', '🦴', 'Anatomi', _red),
  'fizyoloji': EduSubject('fizyoloji', '💓', 'Fizyoloji', _red),
  'biyokimya': EduSubject('biyokimya', '🧪', 'Biyokimya', _green),
  'histoloji': EduSubject('histoloji', '🔬', 'Histoloji', _purple),
  'embriyoloji': EduSubject('embriyoloji', '🧬', 'Embriyoloji', _amber),
  'mikrobiyoloji': EduSubject('mikrobiyoloji', '🦠', 'Mikrobiyoloji', _amber),
  'patoloji': EduSubject('patoloji', '🩸', 'Patoloji', _red),
  'farmakoloji': EduSubject('farmakoloji', '💊', 'Farmakoloji', _green),
  'ic_hast': EduSubject('ic_hast', '🩺', 'İç Hastalıkları', _cyan),
  'cerrahi': EduSubject('cerrahi', '⚕️', 'Cerrahi', _blue),
  'pediatri': EduSubject('pediatri', '👶', 'Pediatri', _pink),
  'kadin_dogum': EduSubject('kadin_dogum', '🤰', 'Kadın-Doğum', _pink),
  'radyoloji': EduSubject('radyoloji', '☢️', 'Radyoloji', _slate),
  'halk_sagligi': EduSubject('halk_sagligi', '🌐', 'Halk Sağlığı', _cyan),
  'psikiyatri': EduSubject('psikiyatri', '🧠', 'Psikiyatri', _purple),
  'noroloji': EduSubject('noroloji', '🧠', 'Nöroloji', _purple),
  // Diş
  'restoratif': EduSubject('restoratif', '🦷', 'Restoratif Diş', _blue),
  'periodontoloji': EduSubject('periodontoloji', '🦷', 'Periodontoloji', _teal),
  'oral_cerrahi': EduSubject('oral_cerrahi', '🦷', 'Oral Cerrahi', _red),
  // Eczacılık
  'farmasotik_kimya': EduSubject('farmasotik_kimya', '⚗️', 'Farmasötik Kimya', _green),
  'farmakognozi': EduSubject('farmakognozi', '🌿', 'Farmakognozi', _success),
  'farmasotik_tek': EduSubject('farmasotik_tek', '💊', 'Farmasötik Teknoloji', _purple),
  // Hemşirelik / FZT / Beslenme
  'klinik_hem': EduSubject('klinik_hem', '🩺', 'Klinik Hemşirelik', _cyan),
  'biyomekanik': EduSubject('biyomekanik', '🦴', 'Biyomekanik', _teal),
  'kinezyoloji': EduSubject('kinezyoloji', '🏃', 'Kinezyoloji', _success),
  'klinik_fzt': EduSubject('klinik_fzt', '🤸', 'Klinik FZT', _success),
  'beslenme': EduSubject('beslenme', '🥗', 'Beslenme', _green),
  'klinik_beslenme': EduSubject('klinik_beslenme', '🍎', 'Klinik Beslenme', _green),

  // Hukuk
  'anayasa': EduSubject('anayasa', '📜', 'Anayasa Hukuku', _brown),
  'medeni_hukuk': EduSubject('medeni_hukuk', '⚖️', 'Medeni Hukuk', _slate),
  'borclar_hukuku': EduSubject('borclar_hukuku', '💼', 'Borçlar Hukuku', _slate),
  'ticaret_hukuku': EduSubject('ticaret_hukuku', '🏢', 'Ticaret Hukuku', _gold),
  'ceza_hukuku': EduSubject('ceza_hukuku', '🚓', 'Ceza Hukuku', _red),
  'idare_hukuku': EduSubject('idare_hukuku', '🏛️', 'İdare Hukuku', _cyan),
  'is_hukuku': EduSubject('is_hukuku', '👷', 'İş Hukuku', _amber),
  'milletlerarasi': EduSubject('milletlerarasi', '🌍', 'Milletlerarası Hukuk', _blue),
  'hukuk_tarihi': EduSubject('hukuk_tarihi', '📚', 'Hukuk Tarihi', _brown),

  // İşletme / İktisat
  'mikroekonomi': EduSubject('mikroekonomi', '📉', 'Mikroekonomi', _gold),
  'makroekonomi': EduSubject('makroekonomi', '📈', 'Makroekonomi', _gold),
  'muhasebe': EduSubject('muhasebe', '🧾', 'Muhasebe', _slate),
  'finans': EduSubject('finans', '💰', 'Finans', _gold),
  'pazarlama': EduSubject('pazarlama', '📣', 'Pazarlama', _pink),
  'yonetim': EduSubject('yonetim', '👥', 'Yönetim ve Organizasyon', _slate),
  'istatistik': EduSubject('istatistik', '📊', 'İstatistik', _indigo),
  'ekonometri': EduSubject('ekonometri', '🧮', 'Ekonometri', _indigo),
  'kamu_maliyesi': EduSubject('kamu_maliyesi', '🏦', 'Kamu Maliyesi', _gold),
  'para_banka': EduSubject('para_banka', '💵', 'Para ve Banka', _gold),
  'iktisat_tarihi': EduSubject('iktisat_tarihi', '📜', 'İktisat Tarihi', _brown),

  // Mühendislik
  'statik': EduSubject('statik', '⚖️', 'Statik', _teal),
  'dinamik': EduSubject('dinamik', '🌀', 'Dinamik', _purple),
  'mukavemet': EduSubject('mukavemet', '💪', 'Mukavemet', _cyan),
  'termodinamik': EduSubject('termodinamik', '🔥', 'Termodinamik', _red),
  'akiskan': EduSubject('akiskan', '🌊', 'Akışkanlar Mekaniği', _cyan),
  'malzeme_bilimi': EduSubject('malzeme_bilimi', '⚙️', 'Malzeme Bilimi', _slate),
  'topografya': EduSubject('topografya', '🗺️', 'Topografya', _brown),
  'beton_tek': EduSubject('beton_tek', '🏗️', 'Beton Teknolojisi', _slate),
  'yapi_statigi': EduSubject('yapi_statigi', '🏛️', 'Yapı Statiği', _teal),
  'zemin_mek': EduSubject('zemin_mek', '⛰️', 'Zemin Mekaniği', _brown),
  'hidrolik': EduSubject('hidrolik', '💧', 'Hidrolik', _cyan),
  'devre_analizi': EduSubject('devre_analizi', '⚡', 'Devre Analizi', _amber),
  'elektromag': EduSubject('elektromag', '🧲', 'Elektromanyetik', _purple),
  'sinyal_isleme': EduSubject('sinyal_isleme', '📡', 'Sinyal İşleme', _indigo),
  'elektronik': EduSubject('elektronik', '💡', 'Elektronik', _amber),
  'kontrol': EduSubject('kontrol', '🎛️', 'Kontrol Sistemleri', _slate),
  'mantik_devre': EduSubject('mantik_devre', '🔌', 'Mantıksal Devre', _indigo),
  'isletim_sistemi': EduSubject('isletim_sistemi', '🖥️', 'İşletim Sistemi', _slate),
  'veritabani': EduSubject('veritabani', '🗄️', 'Veritabanı', _purple),
  'ag_iletisim': EduSubject('ag_iletisim', '🌐', 'Ağ ve İletişim', _cyan),
  'yapay_zeka': EduSubject('yapay_zeka', '🤖', 'Yapay Zekâ', _indigo),
  'algoritma': EduSubject('algoritma', '🧮', 'Algoritmalar', _indigo),
  'veri_yapi': EduSubject('veri_yapi', '📊', 'Veri Yapıları', _purple),
  'yazilim_muh_ders': EduSubject('yazilim_muh_ders', '🛠️', 'Yazılım Mühendisliği', _blue),
  'yoneylem': EduSubject('yoneylem', '⚙️', 'Yöneylem', _slate),
  'uretim': EduSubject('uretim', '🏭', 'Üretim Yönetimi', _amber),
  'tedarik_zinciri': EduSubject('tedarik_zinciri', '🚚', 'Tedarik Zinciri', _gold),
  'kalite_yonetimi': EduSubject('kalite_yonetimi', '✅', 'Kalite Yönetimi', _success),

  // Mimarlık
  'tasarim_studyo': EduSubject('tasarim_studyo', '🏛️', 'Tasarım Stüdyosu', _pink),
  'yapi_bilgisi': EduSubject('yapi_bilgisi', '🏗️', 'Yapı Bilgisi', _slate),
  'mimari_tarih': EduSubject('mimari_tarih', '🏰', 'Mimari Tarih', _brown),
  'sehir_planlama': EduSubject('sehir_planlama', '🏙️', 'Şehir Planlama', _cyan),

  // Psikoloji
  'gelisim_psik': EduSubject('gelisim_psik', '👶', 'Gelişim Psikolojisi', _pink),
  'sosyal_psik': EduSubject('sosyal_psik', '👥', 'Sosyal Psikoloji', _cyan),
  'klinik_psik': EduSubject('klinik_psik', '🛋️', 'Klinik Psikoloji', _purple),
  'arastirma_yontem': EduSubject('arastirma_yontem', '🔬', 'Araştırma Yöntemleri', _indigo),

  // Eğitim
  'matematik_ogretim': EduSubject('matematik_ogretim', '📐', 'Matematik Öğretimi', _blue),
  'fen_bilg_ogretmen': EduSubject('fen_bilg_ogretmen', '🔬', 'Fen Bilgisi Öğretimi', _purple),
  'sosyal_bilg_ogr': EduSubject('sosyal_bilg_ogr', '🌍', 'Sosyal Bilgiler Öğretimi', _brown),
  'cocuk_psik': EduSubject('cocuk_psik', '🧒', 'Çocuk Psikolojisi', _pink),

  // Orange for custom
  'custom': EduSubject('custom', '📚', 'Diğer', _orange),
};

// ─── Üniversite bölüm bazlı müfredat ──────────────────────────────────────
// Anahtar = onboarding'de saklanan faculty stringi (tıpatıp Türkçe ad).
// Lookup: subjectsForProfile() önce country+faculty'i dener; bulamazsa
// country+level fallback'ine düşer.
final Map<String, List<String>> _facultySubjectKeys = {
  // ─── Sağlık ─────────────────────────────────────────────────────────
  'Tıp': [
    'anatomi', 'fizyoloji', 'biyokimya', 'histoloji', 'embriyoloji',
    'mikrobiyoloji', 'patoloji', 'farmakoloji',
    'ic_hast', 'cerrahi', 'pediatri', 'kadin_dogum',
    'radyoloji', 'halk_sagligi', 'psikiyatri', 'noroloji',
  ],
  'Diş Hekimliği': [
    'anatomi', 'fizyoloji', 'biyokimya', 'histoloji',
    'mikrobiyoloji', 'patoloji', 'farmakoloji',
    'restoratif', 'periodontoloji', 'oral_cerrahi',
  ],
  'Eczacılık': [
    'biyokimya', 'mikrobiyoloji', 'farmakoloji',
    'farmasotik_kimya', 'farmakognozi', 'farmasotik_tek',
  ],
  'Veterinerlik': [
    'anatomi', 'fizyoloji', 'biyokimya',
    'mikrobiyoloji', 'patoloji', 'farmakoloji',
    'cerrahi', 'ic_hast',
  ],
  'Hemşirelik': [
    'anatomi', 'fizyoloji', 'biyokimya', 'farmakoloji',
    'klinik_hem', 'halk_sagligi',
  ],
  'Fizyoterapi ve Rehabilitasyon': [
    'anatomi', 'fizyoloji', 'biyomekanik', 'kinezyoloji', 'klinik_fzt',
  ],
  'Beslenme ve Diyetetik': [
    'anatomi', 'fizyoloji', 'biyokimya', 'beslenme', 'klinik_beslenme',
  ],

  // ─── Hukuk ──────────────────────────────────────────────────────────
  'Hukuk': [
    'anayasa', 'medeni_hukuk', 'borclar_hukuku',
    'ticaret_hukuku', 'ceza_hukuku', 'idare_hukuku',
    'is_hukuku', 'milletlerarasi', 'hukuk_tarihi',
  ],

  // ─── İşletme / İktisat ──────────────────────────────────────────────
  'İşletme': [
    'mikroekonomi', 'makroekonomi', 'muhasebe', 'finans',
    'pazarlama', 'yonetim', 'istatistik',
  ],
  'İktisat': [
    'mikroekonomi', 'makroekonomi', 'ekonometri', 'istatistik',
    'kamu_maliyesi', 'para_banka', 'iktisat_tarihi',
  ],

  // ─── Mühendislik ────────────────────────────────────────────────────
  'Bilgisayar Mühendisliği': [
    'math', 'physics', 'algoritma', 'veri_yapi',
    'isletim_sistemi', 'veritabani', 'ag_iletisim',
    'yapay_zeka', 'mantik_devre', 'yazilim_muh_ders',
  ],
  'Yazılım Mühendisliği': [
    'math', 'algoritma', 'veri_yapi', 'yazilim_muh_ders',
    'veritabani', 'ag_iletisim', 'yapay_zeka',
  ],
  'Elektrik-Elektronik Mühendisliği': [
    'math', 'physics', 'devre_analizi', 'elektromag',
    'sinyal_isleme', 'elektronik', 'kontrol', 'mantik_devre',
  ],
  'Makine Mühendisliği': [
    'math', 'physics', 'statik', 'dinamik', 'mukavemet',
    'termodinamik', 'akiskan', 'malzeme_bilimi',
  ],
  'İnşaat Mühendisliği': [
    'math', 'physics', 'statik', 'mukavemet', 'malzeme_bilimi',
    'topografya', 'akiskan', 'hidrolik',
    'beton_tek', 'yapi_statigi', 'zemin_mek',
  ],
  'Endüstri Mühendisliği': [
    'math', 'physics', 'istatistik', 'yoneylem',
    'uretim', 'tedarik_zinciri', 'kalite_yonetimi',
  ],
  'Mimarlık': [
    'math', 'tasarim_studyo', 'malzeme_bilimi', 'yapi_bilgisi',
    'mimari_tarih', 'sehir_planlama',
  ],

  // ─── Sosyal Bilimler ────────────────────────────────────────────────
  'Psikoloji': [
    'gelisim_psik', 'sosyal_psik', 'klinik_psik',
    'arastirma_yontem', 'istatistik',
  ],

  // ─── Eğitim ─────────────────────────────────────────────────────────
  'Sınıf Öğretmenliği': [
    'turkish', 'math', 'fen_bilg_ogretmen', 'sosyal_bilg_ogr',
    'sanat_muzik', 'beden', 'cocuk_psik',
  ],
  'Matematik Öğretmenliği': [
    'math', 'matematik_ogretim', 'istatistik', 'felsefe',
  ],
  'Fen Bilgisi Öğretmenliği': [
    'physics', 'chem', 'bio', 'fen_bilg_ogretmen', 'matematik_ogretim',
  ],
  'İngilizce Öğretmenliği': [
    'ingilizce', 'lit', 'felsefe', 'arastirma_yontem',
  ],
  'Türkçe Öğretmenliği': [
    'turkish', 'lit', 'felsefe', 'arastirma_yontem',
  ],
};

// ─── Sınava göre sorumlu dersler ──────────────────────────────────────────
// EduProfile.level == 'exam_prep' iken EduProfile.grade sınav adıdır
// (örn. "YKS (Yükseköğretim Kurumları Sınavı)"). Burası o sınavda sorumlu
// derslerin listesini döndürür. Lookup substring-based — tam eşleşme şart değil.
final Map<String, List<String>> _examSubjectKeys = {
  // ─── Ortaokul sonrası ────────────────────────────────────────────────
  'LGS': [
    'turkish', 'math', 'physics', 'chem', 'bio',
    'history', 'geo', 'din_kultur', 'ingilizce',
  ],
  // ─── Lise sonrası (uni_prep) ─────────────────────────────────────────
  'YKS': [
    // TYT + AYT toplu — sınava hazırlanan tüm dersler
    'turkish', 'math', 'lit', 'physics', 'chem', 'bio',
    'history', 'geo', 'felsefe', 'din_kultur', 'ingilizce', 'mantik',
  ],
  'MSÜ': [
    'turkish', 'math', 'physics', 'chem', 'bio', 'history', 'geo',
  ],
  'KPSS_ORTA': [
    'turkish', 'math', 'history', 'geo', 'demokrasi',
  ],
  'DGS': ['math', 'turkish'],
  'YDS': ['ingilizce'],
  'PMYO': [
    'turkish', 'math', 'physics', 'chem', 'bio', 'history', 'geo',
  ],

  // ─── Üniversite sonrası (post_uni_exam) ──────────────────────────────
  'ALES': ['math', 'turkish'],
  'KPSS_LISANS': [
    'turkish', 'math', 'history', 'geo', 'demokrasi', 'felsefe',
    'mikroekonomi', 'makroekonomi',
  ],
  'KPSS_OABT': [
    // ÖABT branş bazlı — burası genel öğretmenlik dersleri
    'matematik_ogretim', 'fen_bilg_ogretmen', 'sosyal_bilg_ogr',
    'gelisim_psik', 'cocuk_psik', 'turkish', 'math',
  ],
  'TUS': [
    // TUS / DUS / EUS — tıp + diş + eczacılık merkez sınavları birlikte
    'anatomi', 'fizyoloji', 'biyokimya', 'histoloji', 'embriyoloji',
    'mikrobiyoloji', 'patoloji', 'farmakoloji',
    'ic_hast', 'cerrahi', 'pediatri', 'kadin_dogum',
    'psikiyatri', 'halk_sagligi', 'radyoloji',
    'restoratif', 'periodontoloji', 'oral_cerrahi',
    'farmasotik_kimya', 'farmakognozi', 'farmasotik_tek',
  ],
  'HAKIMLIK': [
    'anayasa', 'medeni_hukuk', 'borclar_hukuku',
    'ticaret_hukuku', 'ceza_hukuku', 'idare_hukuku',
    'is_hukuku', 'milletlerarasi', 'hukuk_tarihi',
  ],
  'KAYMAKAM': [
    'anayasa', 'idare_hukuku', 'ceza_hukuku',
    'history', 'geo', 'demokrasi',
    'mikroekonomi', 'makroekonomi', 'kamu_maliyesi',
  ],
  'SAYISTAY': [
    'muhasebe', 'finans', 'kamu_maliyesi',
    'anayasa', 'idare_hukuku', 'math', 'istatistik',
  ],
  'SMMM': [
    'muhasebe', 'finans', 'kamu_maliyesi',
    'ticaret_hukuku', 'is_hukuku', 'borclar_hukuku',
    'mikroekonomi', 'makroekonomi', 'math',
  ],
  'ISG': [
    'physics', 'chem', 'bio', 'is_hukuku', 'idare_hukuku', 'math',
  ],

  // ─── Uluslararası sınavlar (her ülkede çalışır) ──────────────────────
  'SAT': ['math', 'english_lang', 'lit'],
  'ACT': ['math', 'english_lang', 'physics', 'chem', 'bio', 'lit'],
  'IB': [
    'math', 'physics', 'chem', 'bio', 'english_lang', 'lit',
    'history', 'geo', 'economics', 'felsefe', 'computer_science',
  ],
  'ALEVEL': [
    'math', 'physics', 'chem', 'bio', 'english_lit', 'history',
    'geo', 'economics', 'computer_science',
  ],
  'GCSE': [
    'math', 'english_lang', 'english_lit', 'physics', 'chem', 'bio',
    'history', 'geo', 're', 'mfl', 'computer_science',
  ],
  'IELTS': ['ingilizce'],
  'TOEFL': ['ingilizce'],
  'DUOLINGO': ['ingilizce'],
  'GRE': ['math', 'english_lang'],
  'GMAT': ['math', 'english_lang', 'economics'],
  // Generic — herhangi bir ulusal sınav anahtarı için varsayılan
  'NATIONAL_EXAM': [
    'math', 'english_lang', 'physics', 'chem', 'bio',
    'history', 'geo', 'lit',
  ],
  'UNIVERSITY_ENTRANCE': [
    'math', 'english_lang', 'physics', 'chem', 'bio', 'lit',
  ],
};

/// Onboarding'de `EduProfile.grade` olarak tutulan sınav adından (örn.
/// "YKS (Yükseköğretim Kurumları Sınavı)") sorumlu ders anahtarlarını çıkarır.
List<String>? _examSubjectsForGrade(String grade) {
  // Türkçe karakter normalizasyonu (büyük harf + uppercase mapping).
  final n = grade
      .toUpperCase()
      .replaceAll('İ', 'I')
      .replaceAll('Ö', 'O')
      .replaceAll('Ü', 'U')
      .replaceAll('Ş', 'S')
      .replaceAll('Ç', 'C')
      .replaceAll('Ğ', 'G');
  if (n.startsWith('LGS')) return _examSubjectKeys['LGS'];
  if (n.startsWith('YKS')) return _examSubjectKeys['YKS'];
  if (n.startsWith('MSU')) return _examSubjectKeys['MSÜ'];
  if (n.startsWith('KPSS ORTAOGRETIM') || n.startsWith('KPSS ORTA')) {
    return _examSubjectKeys['KPSS_ORTA'];
  }
  if (n.startsWith('DGS')) return _examSubjectKeys['DGS'];
  if (n.startsWith('YDS') || n.contains('YOKDIL')) {
    return _examSubjectKeys['YDS'];
  }
  if (n.startsWith('PMYO')) return _examSubjectKeys['PMYO'];
  if (n.startsWith('ALES')) return _examSubjectKeys['ALES'];
  if (n.startsWith('KPSS LISANS')) return _examSubjectKeys['KPSS_LISANS'];
  if (n.startsWith('KPSS OABT')) return _examSubjectKeys['KPSS_OABT'];
  if (n.startsWith('TUS') || n.startsWith('DUS') || n.startsWith('EUS')) {
    return _examSubjectKeys['TUS'];
  }
  if (n.startsWith('HAKIM') || n.startsWith('SAVCI')) {
    return _examSubjectKeys['HAKIMLIK'];
  }
  if (n.startsWith('KAYMAKAM')) return _examSubjectKeys['KAYMAKAM'];
  if (n.startsWith('SAYISTAY')) return _examSubjectKeys['SAYISTAY'];
  if (n.startsWith('SMMM')) return _examSubjectKeys['SMMM'];
  if (n.startsWith('ISG')) return _examSubjectKeys['ISG'];

  // ─── Uluslararası sınavlar (ülke-bağımsız) ───────────────────────────
  if (n.startsWith('SAT')) return _examSubjectKeys['SAT'];
  if (n.startsWith('ACT')) return _examSubjectKeys['ACT'];
  if (n.startsWith('IB')) return _examSubjectKeys['IB'];
  if (n.startsWith('ALEVEL') || n.startsWith('A-LEVEL') || n.startsWith('A_LEVEL')) {
    return _examSubjectKeys['ALEVEL'];
  }
  if (n.startsWith('GCSE')) return _examSubjectKeys['GCSE'];
  if (n.startsWith('IELTS')) return _examSubjectKeys['IELTS'];
  if (n.startsWith('TOEFL')) return _examSubjectKeys['TOEFL'];
  if (n.startsWith('DUOLINGO')) return _examSubjectKeys['DUOLINGO'];
  if (n.startsWith('GRE')) return _examSubjectKeys['GRE'];
  if (n.startsWith('GMAT')) return _examSubjectKeys['GMAT'];
  if (n.startsWith('NATIONAL_EXAM') || n.startsWith('NATIONAL EXAM')) {
    return _examSubjectKeys['NATIONAL_EXAM'];
  }
  if (n.startsWith('UNIVERSITY_ENTRANCE') ||
      n.startsWith('UNIVERSITY ENTRANCE') ||
      n.startsWith('GAOKAO') || n.startsWith('NEET') ||
      n.startsWith('JEE') || n.startsWith('SUNEUNG') ||
      n.startsWith('KYOTSU') || n.startsWith('NYUSHI')) {
    return _examSubjectKeys['UNIVERSITY_ENTRANCE'];
  }
  return null;
}

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

  // 🌐 International (generic) — ülkeye özel anahtar yoksa devreye girer.
  // subjectsForProfile() bu anahtarları otomatik dener.
  'international_primary': ['math', 'english_lang', 'sanat_muzik', 'beden', 'history'],
  'international_middle': ['math', 'english_lang', 'bio', 'history', 'geo', 'ingilizce', 'beden', 'sanat_muzik', 'computer_science'],
  'international_high': [
    'math', 'english_lang', 'physics', 'chem', 'bio',
    'history', 'geo', 'felsefe', 'ingilizce', 'beden', 'sanat_muzik',
    'psikoloji_dersi', 'economics', 'computer_science',
  ],
  'international_exam_prep': [
    'math', 'english_lang', 'physics', 'chem', 'bio',
    'history', 'geo', 'ingilizce',
  ],
  'international_university': ['math', 'physics', 'chem', 'bio', 'history', 'english_lang', 'felsefe'],
  'international_masters': ['math', 'english_lang', 'felsefe', 'computer_science', 'economics'],
  'international_doctorate': ['english_lang', 'felsefe', 'computer_science'],
  'international_other': ['math', 'english_lang', 'history', 'geo', 'sanat_muzik'],
};

const List<String> _fallbackKeys = ['math', 'physics', 'chem', 'bio', 'history', 'geo', 'lit', 'ingilizce'];

/// "12. Sınıf" / "12" / "12th" gibi grade stringinden sayıyı çıkar.
int? _extractGradeNumber(String grade) {
  final m = RegExp(r'(\d{1,2})').firstMatch(grade);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

List<EduSubject> subjectsForProfile(EduProfile? profile) {
  if (profile == null) return _fallbackKeys.map((k) => _allSubjects[k]!).toList();

  // ÖNCE: AI üretmiş cache varsa onu kullan (her profil için dinamik müfredat).
  // Hardcoded haritalar yalnızca offline / fetch öncesi fallback rolü.
  final aiCached = EduProfile.aiCachedSubjects(profile);
  if (aiCached != null && aiCached.isNotEmpty) return aiCached;

  // Üniversite/Lisansüstü → bölüm bazlı müfredat (varsa) — ülkeden bağımsız.
  // Onboarding'de Türkçe bölüm adı saklanır (örn. "Tıp", "İnşaat Mühendisliği");
  // ülkesi neresi olursa olsun bölüme uyan müfredatı çıkarırız.
  if ((profile.level == 'university' ||
          profile.level == 'masters' ||
          profile.level == 'doctorate') &&
      profile.faculty != null) {
    final facultyKeys = _facultySubjectKeys[profile.faculty];
    if (facultyKeys != null) {
      return facultyKeys
          .map((s) => _allSubjects[s])
          .whereType<EduSubject>()
          .toList();
    }
  }

  // Sınava hazırlık → grade alanından sınav adını çıkar, sorumlu dersleri ver.
  // Örn. "YKS (Yükseköğretim Kurumları Sınavı)" → TYT+AYT dersleri.
  if (profile.level == 'exam_prep') {
    final examKeys = _examSubjectsForGrade(profile.grade);
    if (examKeys != null) {
      return examKeys
          .map((s) => _allSubjects[s])
          .whereType<EduSubject>()
          .toList();
    }
  }

  // Türkiye lise — alandan (sayısal/sözel/eşit ağırlık/dil) bağımsız olarak
  // o sınıfın TÜM alan derslerini birleştirip ver. Kullanıcı profilinde alan
  // seçili olsa bile yine tam liste çıksın (özet/test/yarışma akışlarında
  // hepsi tıklanabilir kalır).
  if (profile.country == 'tr' && profile.level == 'high') {
    if (profile.grade == '9' || profile.grade == '9. Sınıf') {
      final g9 = _subjectKeysByProfile['tr_high_9'];
      if (g9 != null) {
        return g9.map((s) => _allSubjects[s]).whereType<EduSubject>().toList();
      }
    }
    final gradeNum = _extractGradeNumber(profile.grade);
    if (gradeNum != null && gradeNum >= 10 && gradeNum <= 12) {
      final seen = <String>{};
      final merged = <String>[];
      const tracks = ['sayisal', 'esit_agirlik', 'sozel', 'dil'];
      for (final t in tracks) {
        final keys = _subjectKeysByProfile['tr_high_${gradeNum}_$t'];
        if (keys == null) continue;
        for (final k in keys) {
          if (seen.add(k)) merged.add(k);
        }
      }
      if (merged.isNotEmpty) {
        return merged
            .map((s) => _allSubjects[s])
            .whereType<EduSubject>()
            .toList();
      }
    }
    final g9 = _subjectKeysByProfile['tr_high_9'];
    if (g9 != null) return g9.map((s) => _allSubjects[s]).whereType<EduSubject>().toList();
  }

  // Hindistan lise — science/commerce/arts ayrımını kaldır, tümünü birleştir.
  if (profile.country == 'in' && profile.level == 'high') {
    final seen = <String>{};
    final merged = <String>[];
    const tracks = ['science', 'commerce', 'arts'];
    for (final t in tracks) {
      final keys = _subjectKeysByProfile['in_high_$t'];
      if (keys == null) continue;
      for (final k in keys) {
        if (seen.add(k)) merged.add(k);
      }
    }
    if (merged.isNotEmpty) {
      return merged
          .map((s) => _allSubjects[s])
          .whereType<EduSubject>()
          .toList();
    }
  }

  // Diğer: country × level
  final k = '${profile.country}_${profile.level}';
  final list = _subjectKeysByProfile[k];
  if (list != null) {
    return list.map((s) => _allSubjects[s]).whereType<EduSubject>().toList();
  }
  // Country bazlı anahtar yoksa: international_${level} jenerik şablonu.
  // Bu sayede branch'ı olmayan ülkelerde de seviyeye uygun zengin liste gelir
  // (sadece 8'lik _fallbackKeys'e düşmez).
  final intl = _subjectKeysByProfile['international_${profile.level}'];
  if (intl != null) {
    return intl.map((s) => _allSubjects[s]).whereType<EduSubject>().toList();
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
