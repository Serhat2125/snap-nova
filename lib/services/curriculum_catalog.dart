// ═══════════════════════════════════════════════════════════════════════════════
//  CURRICULUM CATALOG — 50+ ülkenin resmi eğitim müfredatı (sınıf × ders × konu)
//
//  Yapı:
//    _curriculum[country][levelGradeKey][subjectKey] = [topic1, topic2, ...]
//
//  levelGradeKey formatı:
//    primary_1 .. primary_6 | middle_5 .. middle_10 | high_9 .. high_12
//    high_11_{track} | high_12_{track}
//    university_{grade} | masters | doctorate
//
//  Kaynaklar (Jan 2026 bilgi güncelliği):
//    • Türkiye — MEB Talim ve Terbiye Kurulu (ttkb.meb.gov.tr) resmi müfredat
//    • ABD — Common Core State Standards (corestandards.org) + NGSS
//    • İngiltere — GOV.UK National Curriculum + GCSE/A-Level AQA, OCR
//    • Almanya — Kultusministerkonferenz (KMK) + Abitur Bildungsstandards
//    • Fransa — Éducation Nationale + programmes du Baccalauréat
//    • Japonya — MEXT Course of Study (学習指導要領)
//    • Çin — 人民教育出版社 (People's Education Press) Gaokao müfredatı
//    • Güney Kore — Ministry of Education + 수능 (Suneung) subjects
//    • Hindistan — NCERT + CBSE + CISCE
//    • Kanada — provincial curricula (Ontario, Quebec, British Columbia)
//    • Diğer ülkeler — UNESCO IBE + WorldData Education Systems
//
//  NOT: Bu katalog uygulama içi çevrimdışı çalışır; Firestore'a da replikası
//  atılabilir (config/curriculum/{country}) — böylece dönem değişikliklerinde
//  OTA güncelleme mümkün.
// ═══════════════════════════════════════════════════════════════════════════════

import 'education_profile.dart';

class CurriculumSubject {
  /// _allSubjects kataloğundaki anahtar ile aynı
  final String key;

  /// Ekranda gösterilecek isim (ülkenin dili; örn. "Matematik", "数学", "الرياضيات")
  final String displayName;

  /// Derse özel emoji
  final String emoji;

  /// Bu sınıf/dönem için müfredatta yer alan konu başlıkları
  final List<String> topics;

  const CurriculumSubject({
    required this.key,
    required this.displayName,
    required this.emoji,
    required this.topics,
  });
}

/// Eğitim profiline göre o dönem okutulan dersleri + konularını döndürür.
///
/// Arama sırası:
///   1) Tam eşleşme  (country_level_grade[_track])
///   2) Track'sız fallback (country_level_grade)
///   3) Seviye fallback (country_level)
///   4) Uluslararası şablon (international_level)
///   5) Son çare: generic primary/middle/high varsayılanı
List<CurriculumSubject> curriculumFor(EduProfile? profile) {
  if (profile == null) return _fallbackByLevel(null);
  final keys = _lookupKeys(profile);
  for (final k in keys) {
    final found = _curriculum[k];
    if (found != null) return _materialize(found, profile.country);
  }
  return _fallbackByLevel(profile.level);
}

List<String> _lookupKeys(EduProfile p) {
  final c = p.country.toLowerCase();
  final l = p.level;
  final g = p.grade;
  final t = p.track;
  return [
    if (t != null) '${c}_${l}_${g}_$t',
    '${c}_${l}_$g',
    '${c}_$l',
    'international_$l',
  ];
}

List<CurriculumSubject> _materialize(
  Map<String, List<String>> subjectToTopics,
  String country,
) {
  final result = <CurriculumSubject>[];
  for (final entry in subjectToTopics.entries) {
    final subj = _displayForSubject(entry.key, country);
    result.add(CurriculumSubject(
      key: entry.key,
      displayName: subj.name,
      emoji: subj.emoji,
      topics: entry.value,
    ));
  }
  return result;
}

class _SubjectDisplay {
  final String name;
  final String emoji;
  const _SubjectDisplay(this.name, this.emoji);
}

/// Ders key'inden ülkenin dilinde görsel ad döndürür.
_SubjectDisplay _displayForSubject(String key, String country) {
  final countryMap = _subjectDisplayOverrides[country];
  if (countryMap != null && countryMap[key] != null) return countryMap[key]!;
  // Generic fallback from shared subject names
  return _subjectDisplayDefaults[key] ??
      _SubjectDisplay(key, '📚');
}

/// Ülkeye göre son çare varsayılanlar (kataloğa girmemiş ülke/seviye için).
List<CurriculumSubject> _fallbackByLevel(String? level) {
  final key = 'international_${level ?? 'high'}';
  final found = _curriculum[key];
  if (found != null) return _materialize(found, 'international');
  return _materialize(_curriculum['international_high']!, 'international');
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DERS GÖRSEL ADLARI — generic (EN) + ülke özel override'lar
// ═══════════════════════════════════════════════════════════════════════════════

const Map<String, _SubjectDisplay> _subjectDisplayDefaults = {
  'math': _SubjectDisplay('Mathematics', '📐'),
  'physics': _SubjectDisplay('Physics', '⚛️'),
  'chem': _SubjectDisplay('Chemistry', '🧪'),
  'bio': _SubjectDisplay('Biology', '🧬'),
  'lit': _SubjectDisplay('Literature', '✒️'),
  'lang_native': _SubjectDisplay('Native Language', '📖'),
  'history': _SubjectDisplay('History', '🏛️'),
  'geo': _SubjectDisplay('Geography', '🌍'),
  'english': _SubjectDisplay('English', '🇬🇧'),
  'ingilizce': _SubjectDisplay('İngilizce', '🇬🇧'),
  'second_lang': _SubjectDisplay('Second Language', '🗣️'),
  'philosophy': _SubjectDisplay('Philosophy', '🤔'),
  'psychology': _SubjectDisplay('Psychology', '🧠'),
  'sociology': _SubjectDisplay('Sociology', '👥'),
  'economics': _SubjectDisplay('Economics', '💰'),
  'business_studies': _SubjectDisplay('Business Studies', '💼'),
  'accountancy': _SubjectDisplay('Accountancy', '📊'),
  'political_science': _SubjectDisplay('Political Science', '🗳️'),
  'computer_science': _SubjectDisplay('Computer Science', '💻'),
  'religion': _SubjectDisplay('Religion / Ethics', '📿'),
  'pe': _SubjectDisplay('Physical Education', '⚽'),
  'art_music': _SubjectDisplay('Art / Music', '🎨'),
  'drama': _SubjectDisplay('Drama', '🎭'),
  'logic': _SubjectDisplay('Logic', '🧩'),
  'civics': _SubjectDisplay('Civics', '🗳️'),
  'earth_science': _SubjectDisplay('Earth Science', '🌋'),
  'environmental': _SubjectDisplay('Environmental Science', '🌿'),
  'technology': _SubjectDisplay('Technology / Design', '🛠️'),
  'health': _SubjectDisplay('Health', '🩺'),
  'ict': _SubjectDisplay('ICT', '💻'),
  'statistics': _SubjectDisplay('Statistics', '📊'),
  'calculus': _SubjectDisplay('Calculus', '∫'),
  'linear_algebra': _SubjectDisplay('Linear Algebra', '📐'),
  'anatomy': _SubjectDisplay('Anatomy', '🦴'),
  'physiology': _SubjectDisplay('Physiology', '💓'),
};

/// Ülke × dersKey → (yerel ad, emoji) override. Boş bırakılırsa defaults kullanılır.
const Map<String, Map<String, _SubjectDisplay>> _subjectDisplayOverrides = {
  'tr': {
    'math': _SubjectDisplay('Matematik', '📐'),
    'physics': _SubjectDisplay('Fizik', '⚛️'),
    'chem': _SubjectDisplay('Kimya', '🧪'),
    'bio': _SubjectDisplay('Biyoloji', '🧬'),
    'lit': _SubjectDisplay('Türk Dili ve Edebiyatı', '✒️'),
    'lang_native': _SubjectDisplay('Türkçe', '📖'),
    'history': _SubjectDisplay('Tarih', '🏛️'),
    'geo': _SubjectDisplay('Coğrafya', '🌍'),
    'ingilizce': _SubjectDisplay('İngilizce', '🇬🇧'),
    'second_lang': _SubjectDisplay('2. Yabancı Dil', '🗣️'),
    'philosophy': _SubjectDisplay('Felsefe', '🤔'),
    'psychology': _SubjectDisplay('Psikoloji', '🧠'),
    'sociology': _SubjectDisplay('Sosyoloji', '👥'),
    'religion': _SubjectDisplay('Din Kültürü ve Ahlak Bilgisi', '📿'),
    'pe': _SubjectDisplay('Beden Eğitimi', '⚽'),
    'art_music': _SubjectDisplay('Görsel Sanatlar / Müzik', '🎨'),
    'drama': _SubjectDisplay('Drama', '🎭'),
    'logic': _SubjectDisplay('Mantık', '🧩'),
    'economics': _SubjectDisplay('Ekonomi', '💰'),
  },
  'de': {
    'math': _SubjectDisplay('Mathematik', '📐'),
    'physics': _SubjectDisplay('Physik', '⚛️'),
    'chem': _SubjectDisplay('Chemie', '🧪'),
    'bio': _SubjectDisplay('Biologie', '🧬'),
    'lit': _SubjectDisplay('Deutsch (Literatur)', '✒️'),
    'lang_native': _SubjectDisplay('Deutsch', '📖'),
    'history': _SubjectDisplay('Geschichte', '🏛️'),
    'geo': _SubjectDisplay('Erdkunde / Geographie', '🌍'),
    'ingilizce': _SubjectDisplay('Englisch', '🇬🇧'),
    'english': _SubjectDisplay('Englisch', '🇬🇧'),
    'second_lang': _SubjectDisplay('Zweite Fremdsprache', '🗣️'),
    'philosophy': _SubjectDisplay('Philosophie', '🤔'),
    'religion': _SubjectDisplay('Religion / Ethik', '📿'),
    'pe': _SubjectDisplay('Sport', '⚽'),
    'art_music': _SubjectDisplay('Kunst / Musik', '🎨'),
    'economics': _SubjectDisplay('Wirtschaft', '💰'),
    'civics': _SubjectDisplay('Politik / Sozialkunde', '🗳️'),
  },
  'fr': {
    'math': _SubjectDisplay('Mathématiques', '📐'),
    'physics': _SubjectDisplay('Physique', '⚛️'),
    'chem': _SubjectDisplay('Chimie', '🧪'),
    'bio': _SubjectDisplay('SVT (Biologie-Géologie)', '🧬'),
    'lit': _SubjectDisplay('Français (Littérature)', '✒️'),
    'lang_native': _SubjectDisplay('Français', '📖'),
    'history': _SubjectDisplay('Histoire-Géographie', '🏛️'),
    'geo': _SubjectDisplay('Géographie', '🌍'),
    'english': _SubjectDisplay('Anglais', '🇬🇧'),
    'second_lang': _SubjectDisplay('LV2', '🗣️'),
    'philosophy': _SubjectDisplay('Philosophie', '🤔'),
    'pe': _SubjectDisplay('EPS', '⚽'),
    'art_music': _SubjectDisplay('Arts Plastiques / Musique', '🎨'),
    'economics': _SubjectDisplay('SES (Sciences Éco & Sociales)', '💰'),
  },
  'jp': {
    'math': _SubjectDisplay('数学 (Sūgaku)', '📐'),
    'physics': _SubjectDisplay('物理 (Butsuri)', '⚛️'),
    'chem': _SubjectDisplay('化学 (Kagaku)', '🧪'),
    'bio': _SubjectDisplay('生物 (Seibutsu)', '🧬'),
    'lit': _SubjectDisplay('国語 (Kokugo)', '✒️'),
    'history': _SubjectDisplay('歴史 (Rekishi)', '🏛️'),
    'geo': _SubjectDisplay('地理 (Chiri)', '🌍'),
    'english': _SubjectDisplay('英語 (Eigo)', '🇬🇧'),
    'civics': _SubjectDisplay('公民 (Kōmin)', '🗳️'),
    'pe': _SubjectDisplay('体育 (Taiiku)', '⚽'),
    'art_music': _SubjectDisplay('美術 / 音楽', '🎨'),
  },
  'cn': {
    'math': _SubjectDisplay('数学 (Shùxué)', '📐'),
    'physics': _SubjectDisplay('物理 (Wùlǐ)', '⚛️'),
    'chem': _SubjectDisplay('化学 (Huàxué)', '🧪'),
    'bio': _SubjectDisplay('生物 (Shēngwù)', '🧬'),
    'lit': _SubjectDisplay('语文 (Yǔwén)', '✒️'),
    'history': _SubjectDisplay('历史 (Lìshǐ)', '🏛️'),
    'geo': _SubjectDisplay('地理 (Dìlǐ)', '🌍'),
    'english': _SubjectDisplay('英语 (Yīngyǔ)', '🇬🇧'),
    'civics': _SubjectDisplay('政治 (Zhèngzhì)', '🗳️'),
  },
  'kr': {
    'math': _SubjectDisplay('수학 (Suhak)', '📐'),
    'physics': _SubjectDisplay('물리 (Mulli)', '⚛️'),
    'chem': _SubjectDisplay('화학 (Hwahak)', '🧪'),
    'bio': _SubjectDisplay('생물 (Saengmul)', '🧬'),
    'lit': _SubjectDisplay('국어 (Gugeo)', '✒️'),
    'history': _SubjectDisplay('역사 (Yeoksa)', '🏛️'),
    'geo': _SubjectDisplay('지리 (Jiri)', '🌍'),
    'english': _SubjectDisplay('영어 (Yeongeo)', '🇬🇧'),
  },
  'ru': {
    'math': _SubjectDisplay('Математика', '📐'),
    'physics': _SubjectDisplay('Физика', '⚛️'),
    'chem': _SubjectDisplay('Химия', '🧪'),
    'bio': _SubjectDisplay('Биология', '🧬'),
    'lit': _SubjectDisplay('Литература', '✒️'),
    'lang_native': _SubjectDisplay('Русский язык', '📖'),
    'history': _SubjectDisplay('История', '🏛️'),
    'geo': _SubjectDisplay('География', '🌍'),
    'english': _SubjectDisplay('Английский', '🇬🇧'),
  },
  'es': {
    'math': _SubjectDisplay('Matemáticas', '📐'),
    'physics': _SubjectDisplay('Física', '⚛️'),
    'chem': _SubjectDisplay('Química', '🧪'),
    'bio': _SubjectDisplay('Biología', '🧬'),
    'lit': _SubjectDisplay('Lengua y Literatura', '✒️'),
    'history': _SubjectDisplay('Historia', '🏛️'),
    'geo': _SubjectDisplay('Geografía', '🌍'),
    'english': _SubjectDisplay('Inglés', '🇬🇧'),
  },
  'mx': {
    'math': _SubjectDisplay('Matemáticas', '📐'),
    'physics': _SubjectDisplay('Física', '⚛️'),
    'chem': _SubjectDisplay('Química', '🧪'),
    'bio': _SubjectDisplay('Biología', '🧬'),
    'lit': _SubjectDisplay('Español (Lengua y Lit.)', '✒️'),
    'history': _SubjectDisplay('Historia de México', '🏛️'),
    'geo': _SubjectDisplay('Geografía', '🌍'),
    'english': _SubjectDisplay('Inglés', '🇬🇧'),
  },
  'it': {
    'math': _SubjectDisplay('Matematica', '📐'),
    'physics': _SubjectDisplay('Fisica', '⚛️'),
    'chem': _SubjectDisplay('Chimica', '🧪'),
    'bio': _SubjectDisplay('Biologia', '🧬'),
    'lit': _SubjectDisplay('Italiano (Letteratura)', '✒️'),
    'history': _SubjectDisplay('Storia', '🏛️'),
    'geo': _SubjectDisplay('Geografia', '🌍'),
    'english': _SubjectDisplay('Inglese', '🇬🇧'),
    'philosophy': _SubjectDisplay('Filosofia', '🤔'),
    'second_lang': _SubjectDisplay('Seconda Lingua', '🗣️'),
  },
  'br': {
    'math': _SubjectDisplay('Matemática', '📐'),
    'physics': _SubjectDisplay('Física', '⚛️'),
    'chem': _SubjectDisplay('Química', '🧪'),
    'bio': _SubjectDisplay('Biologia', '🧬'),
    'lit': _SubjectDisplay('Português (Literatura)', '✒️'),
    'history': _SubjectDisplay('História', '🏛️'),
    'geo': _SubjectDisplay('Geografia', '🌍'),
    'english': _SubjectDisplay('Inglês', '🇬🇧'),
    'philosophy': _SubjectDisplay('Filosofia', '🤔'),
    'sociology': _SubjectDisplay('Sociologia', '👥'),
  },
  'ar': {
    'math': _SubjectDisplay('Matemática', '📐'),
    'physics': _SubjectDisplay('Física', '⚛️'),
    'chem': _SubjectDisplay('Química', '🧪'),
    'bio': _SubjectDisplay('Biología', '🧬'),
    'lit': _SubjectDisplay('Lengua y Literatura', '✒️'),
    'history': _SubjectDisplay('Historia Argentina', '🏛️'),
    'geo': _SubjectDisplay('Geografía', '🌍'),
    'english': _SubjectDisplay('Inglés', '🇬🇧'),
  },
  'eg': {
    'math': _SubjectDisplay('الرياضيات', '📐'),
    'physics': _SubjectDisplay('الفيزياء', '⚛️'),
    'chem': _SubjectDisplay('الكيمياء', '🧪'),
    'bio': _SubjectDisplay('الأحياء', '🧬'),
    'lit': _SubjectDisplay('اللغة العربية', '✒️'),
    'history': _SubjectDisplay('التاريخ', '🏛️'),
    'geo': _SubjectDisplay('الجغرافيا', '🌍'),
    'english': _SubjectDisplay('اللغة الإنجليزية', '🇬🇧'),
    'religion': _SubjectDisplay('التربية الدينية', '📿'),
  },
  'sa': {
    'math': _SubjectDisplay('الرياضيات', '📐'),
    'physics': _SubjectDisplay('الفيزياء', '⚛️'),
    'chem': _SubjectDisplay('الكيمياء', '🧪'),
    'bio': _SubjectDisplay('الأحياء', '🧬'),
    'lit': _SubjectDisplay('اللغة العربية', '✒️'),
    'history': _SubjectDisplay('التاريخ', '🏛️'),
    'geo': _SubjectDisplay('الجغرافيا', '🌍'),
    'english': _SubjectDisplay('اللغة الإنجليزية', '🇬🇧'),
    'religion': _SubjectDisplay('الدراسات الإسلامية', '📿'),
  },
  'ir': {
    'math': _SubjectDisplay('ریاضی', '📐'),
    'physics': _SubjectDisplay('فیزیک', '⚛️'),
    'chem': _SubjectDisplay('شیمی', '🧪'),
    'bio': _SubjectDisplay('زیست‌شناسی', '🧬'),
    'lit': _SubjectDisplay('ادبیات فارسی', '✒️'),
    'history': _SubjectDisplay('تاریخ', '🏛️'),
    'geo': _SubjectDisplay('جغرافیا', '🌍'),
    'english': _SubjectDisplay('زبان انگلیسی', '🇬🇧'),
    'religion': _SubjectDisplay('دینی', '📿'),
  },
  'id': {
    'math': _SubjectDisplay('Matematika', '📐'),
    'physics': _SubjectDisplay('Fisika', '⚛️'),
    'chem': _SubjectDisplay('Kimia', '🧪'),
    'bio': _SubjectDisplay('Biologi', '🧬'),
    'lit': _SubjectDisplay('Bahasa Indonesia', '✒️'),
    'history': _SubjectDisplay('Sejarah', '🏛️'),
    'geo': _SubjectDisplay('Geografi', '🌍'),
    'english': _SubjectDisplay('Bahasa Inggris', '🇬🇧'),
    'religion': _SubjectDisplay('Pendidikan Agama', '📿'),
  },
  'th': {
    'math': _SubjectDisplay('คณิตศาสตร์', '📐'),
    'physics': _SubjectDisplay('ฟิสิกส์', '⚛️'),
    'chem': _SubjectDisplay('เคมี', '🧪'),
    'bio': _SubjectDisplay('ชีววิทยา', '🧬'),
    'lit': _SubjectDisplay('ภาษาไทย', '✒️'),
    'history': _SubjectDisplay('ประวัติศาสตร์', '🏛️'),
    'geo': _SubjectDisplay('ภูมิศาสตร์', '🌍'),
    'english': _SubjectDisplay('ภาษาอังกฤษ', '🇬🇧'),
  },
  'vn': {
    'math': _SubjectDisplay('Toán học', '📐'),
    'physics': _SubjectDisplay('Vật lý', '⚛️'),
    'chem': _SubjectDisplay('Hóa học', '🧪'),
    'bio': _SubjectDisplay('Sinh học', '🧬'),
    'lit': _SubjectDisplay('Ngữ văn', '✒️'),
    'history': _SubjectDisplay('Lịch sử', '🏛️'),
    'geo': _SubjectDisplay('Địa lý', '🌍'),
    'english': _SubjectDisplay('Tiếng Anh', '🇬🇧'),
  },
  'pk': {
    'math': _SubjectDisplay('Mathematics', '📐'),
    'physics': _SubjectDisplay('Physics', '⚛️'),
    'chem': _SubjectDisplay('Chemistry', '🧪'),
    'bio': _SubjectDisplay('Biology', '🧬'),
    'lit': _SubjectDisplay('Urdu Literature', '✒️'),
    'lang_native': _SubjectDisplay('Urdu', '📖'),
    'history': _SubjectDisplay('Pakistan Studies', '🏛️'),
    'geo': _SubjectDisplay('Geography', '🌍'),
    'english': _SubjectDisplay('English', '🇬🇧'),
    'religion': _SubjectDisplay('Islamiat', '📿'),
  },
  'bd': {
    'math': _SubjectDisplay('গণিত', '📐'),
    'physics': _SubjectDisplay('পদার্থবিজ্ঞান', '⚛️'),
    'chem': _SubjectDisplay('রসায়ন', '🧪'),
    'bio': _SubjectDisplay('জীববিজ্ঞান', '🧬'),
    'lit': _SubjectDisplay('বাংলা সাহিত্য', '✒️'),
    'history': _SubjectDisplay('ইতিহাস', '🏛️'),
    'geo': _SubjectDisplay('ভূগোল', '🌍'),
    'english': _SubjectDisplay('ইংরেজি', '🇬🇧'),
  },
  'in': {
    'math': _SubjectDisplay('Mathematics / गणित', '📐'),
    'physics': _SubjectDisplay('Physics / भौतिकी', '⚛️'),
    'chem': _SubjectDisplay('Chemistry / रसायन', '🧪'),
    'bio': _SubjectDisplay('Biology / जीव विज्ञान', '🧬'),
    'lit': _SubjectDisplay('Hindi / हिन्दी', '✒️'),
    'history': _SubjectDisplay('History / इतिहास', '🏛️'),
    'geo': _SubjectDisplay('Geography / भूगोल', '🌍'),
    'english': _SubjectDisplay('English', '🇬🇧'),
    'economics': _SubjectDisplay('Economics', '💰'),
    'accountancy': _SubjectDisplay('Accountancy', '📊'),
    'business_studies': _SubjectDisplay('Business Studies', '💼'),
    'political_science': _SubjectDisplay('Political Science', '🗳️'),
    'computer_science': _SubjectDisplay('Computer Science', '💻'),
  },
  'ng': {
    'math': _SubjectDisplay('Mathematics', '📐'),
    'physics': _SubjectDisplay('Physics', '⚛️'),
    'chem': _SubjectDisplay('Chemistry', '🧪'),
    'bio': _SubjectDisplay('Biology', '🧬'),
    'lit': _SubjectDisplay('English Literature', '✒️'),
    'history': _SubjectDisplay('History / Government', '🏛️'),
    'geo': _SubjectDisplay('Geography', '🌍'),
    'english': _SubjectDisplay('English Language', '🇬🇧'),
    'civics': _SubjectDisplay('Civic Education', '🗳️'),
  },
  'ph': {
    'math': _SubjectDisplay('Mathematics', '📐'),
    'physics': _SubjectDisplay('Physics', '⚛️'),
    'chem': _SubjectDisplay('Chemistry', '🧪'),
    'bio': _SubjectDisplay('Biology', '🧬'),
    'lit': _SubjectDisplay('Filipino (Panitikan)', '✒️'),
    'history': _SubjectDisplay('Araling Panlipunan', '🏛️'),
    'geo': _SubjectDisplay('Geography', '🌍'),
    'english': _SubjectDisplay('English', '🇬🇧'),
  },
};

// ═══════════════════════════════════════════════════════════════════════════════
//  CURRICULUM DB — {country}_{level}_{grade}[_{track}] → subject → topics
//
//  Dikkat:
//    - Konu başlıkları ülkenin öğretim diliyle yazılır (öğrenci o dilde arar).
//    - Seviye anahtarında track varsa önce onu arar, yoksa track'siz düşer.
//    - Bir ülke için tüm sınıflar girilmeyebilir; fallback zinciri devrededir.
// ═══════════════════════════════════════════════════════════════════════════════

const Map<String, Map<String, List<String>>> _curriculum = {
  // ═════════════════════════════════════════════════════════════════════════
  //  🇹🇷 TÜRKİYE — MEB resmi müfredatı (2024-25 yönergesine göre)
  // ═════════════════════════════════════════════════════════════════════════
  'tr_primary_1': {
    'math': ['0-20 arası sayılar', 'Toplama', 'Çıkarma', 'Geometrik şekiller', 'Uzunluk ölçme', 'Zaman (saat)', 'Para', 'Örüntüler'],
    'lang_native': ['Alfabe ve sesler', 'Okuma', 'Yazı yazma', 'Hikaye dinleme', 'Kısa cümle kurma', 'Noktalama (nokta, soru işareti)'],
    'ingilizce': ['Renkler', 'Sayılar 1-10', 'Aile üyeleri', 'Selamlaşma', 'Vücut parçaları'],
    'religion': ['Allah sevgisi', 'Temizlik', 'İyi davranışlar', 'Dua örnekleri'],
    'pe': ['Yürüyüş-koşu', 'Denge', 'Top oyunları', 'Ritim egzersizleri'],
    'art_music': ['Temel renkler', 'Çizgi çalışmaları', 'Çocuk şarkıları', 'Basit enstrüman'],
  },
  'tr_primary_2': {
    'math': ['100 içinde sayılar', 'Toplama-çıkarma', 'Çarpma tablosuna giriş', 'Çarpım tablosu 2-5', 'Ondalık kavramı', 'Kesir (yarım, çeyrek)', 'Uzunluk, tartma'],
    'lang_native': ['Okuduğunu anlama', 'Paragraf', 'Büyük-küçük harf', 'Eş ve zıt anlamlı kelimeler', 'Hikaye yazma'],
    'ingilizce': ['Yiyecek/İçecek', 'Hayvanlar', 'Zaman (gün/ay)', 'Hava durumu', 'Basit cümleler'],
  },
  'tr_primary_3': {
    'math': ['1000 içinde sayılar', 'Çarpım tablosu 2-10', 'Bölme', 'Geometri (üçgen, dörtgen)', 'Alan kavramı', 'Simetri', 'Olasılık (kesin/imkânsız)'],
    'lang_native': ['Sözcük türleri (ad, eylem)', 'Cümle ögeleri', 'Özet çıkarma', 'Betimleyici yazı', 'Mektup/davetiye'],
    'ingilizce': ['Can/can\'t', 'Saat', 'Meslekler', 'Odalar, mobilyalar', 'Oyunlar'],
  },
  'tr_primary_4': {
    'math': ['10000 içinde sayılar', 'Kesirler', 'Ondalık kesirler', 'Zaman ölçme', 'Çevre, alan', 'Grafikler', 'Olasılık'],
    'lang_native': ['Ad türleri (özel, somut)', 'Sıfat, zarf', 'Ekler', 'Yazım kuralları', 'Öykü yazma', 'Şiir'],
    'history': ['İlk insanlar', 'Anadolu medeniyetleri başlangıç', 'Osmanlıya giriş'],
    'geo': ['Türkiye haritası', 'Yön, pusula', 'İklim çeşitleri', 'Yerleşim'],
    'ingilizce': ['Past simple (was, were)', 'Like/don\'t like', 'Ülke-uyruk', 'Hobiler'],
  },
  'tr_middle_5': {
    'math': ['Doğal sayılar', 'Kesirlerle işlemler', 'Ondalık gösterim', 'Yüzdeler', 'Açılar', 'Alan hesapları', 'Veri toplama'],
    'turkish': ['Cümle bilgisi', 'Paragraf yapısı', 'Metin türleri (öykü, şiir, anı)', 'Sözcükte anlam', 'Noktalama'],
    'history': ['İlk Türk devletleri', 'İslamiyetin doğuşu', 'İlk Müslüman Türk devletleri', 'Selçuklular'],
    'geo': ['Harita okuma', 'Coğrafi konum', 'İklim bölgeleri', 'Türkiye yer şekilleri', 'Nüfus'],
    'ingilizce': ['Present simple', 'Present continuous', 'Daily routine', 'Food & drink', 'My week'],
    'religion': ['İslamda temel ibadetler', 'Peygamberimizin hayatı', 'Allah inancı'],
    'pe': ['Takım oyunları', 'Fiziksel uygunluk', 'Atletizm'],
    'art_music': ['Renk teorisi', 'Perspektif', 'Nota', 'Ritim'],
  },
  'tr_middle_6': {
    'math': ['Kümeler', 'Doğal sayılarla işlemler', 'Tam sayılar', 'Çarpanlar-katlar', 'Oran-orantı', 'Açılar ve üçgenler', 'Sıvı ölçme', 'Olasılık'],
    'turkish': ['Sözcük türleri', 'Fiil çekimleri', 'Yapım-çekim ekleri', 'Metin türleri (makale, fıkra)', 'Paragrafın ana fikri'],
    'history': ['Osmanlı Beyliği kuruluşu', 'Fetih hareketleri', 'Fatih Sultan Mehmet', 'İstanbul\'un fethi'],
    'geo': ['Kıtalar, okyanuslar', 'Dünyadaki iklim tipleri', 'Bitki örtüsü', 'Kaynaklar', 'Tarım'],
    'ingilizce': ['Past simple', 'Comparatives-superlatives', 'Future plans', 'Travel', 'Health'],
  },
  'tr_middle_7': {
    'math': ['Rasyonel sayılar', 'Cebirsel ifadeler', 'Eşitlik ve denklem', 'Doğrusal denklemler', 'Oran-orantı', 'Yüzde problemleri', 'Çember ve daire', 'İstatistik (ortalama, mod, medyan)'],
    'turkish': ['Cümle ögeleri', 'Cümle türleri', 'Anlatım bozuklukları', 'Metin türleri (deneme, röportaj)', 'Yazım kuralları'],
    'history': ['Kanuni devri', 'Duraklama dönemi', 'Islahatlar', 'Osmanlıda bilim ve sanat'],
    'geo': ['Türkiye\'nin coğrafi konumu', 'İklim ve yaşam', 'Nüfus dağılışı', 'Göçler', 'Ekonomi faaliyetleri'],
    'ingilizce': ['Present perfect', 'Modals (must, should, have to)', 'Relative clauses temeli', 'News & media'],
  },
  'tr_middle_8': {
    'math': ['Çarpanlar-katlar', 'Üslü sayılar (pozitif-negatif)', 'Kareköklü sayılar', 'Cebirsel ifadeler (özdeşlikler)', 'Denklemler ve eşitsizlikler', 'Üçgenler (Pisagor)', 'Dönüşüm geometrisi', 'Olasılık', 'Histogram'],
    'turkish': ['Fiilde çatı', 'Anlatım biçimleri', 'Söz sanatları', 'Cümle bilgisi', 'Paragraf yorumu (LGS)', 'Sözcükte anlam (LGS)'],
    'history': ['Atatürk\'ün hayatı', 'Kurtuluş Savaşı', 'Devrimler ve inkılaplar', 'Cumhuriyet dönemi'],
    'geo': ['Türkiye\'nin bölgeleri', 'Dünya ekonomisi', 'Uluslararası kuruluşlar', 'Çevre sorunları'],
    'ingilizce': ['Conditionals', 'Passive voice', 'Reported speech', 'Tourism & culture'],
    'religion': ['Kader ve kaza', 'Zekât ve sadaka', 'Hz. Muhammed örnekliği', 'İslam medeniyeti'],
  },
  'tr_high_9': {
    'lit': ['Giriş — Dil, iletişim, edebiyat kavramları', 'Sözlü anlatım türleri', 'Öykü', 'Masal-fabl', 'Şiir (ilk dönem)', 'Makale-fıkra', 'Tiyatro tanıtımı', 'Dil bilgisi (ses-kelime)'],
    'math': ['Mantık', 'Kümeler', 'Denklem-eşitsizlik', 'Üslü-köklü sayılar', 'Oran-orantı', 'Modüler aritmetik', 'Dörtgenler', 'Çokgenler', 'Çember'],
    'physics': ['Fiziğe giriş', 'Madde ve özellikleri', 'Hareket ve kuvvet', 'Enerji', 'Isı ve sıcaklık', 'Elektrostatik temel'],
    'chem': ['Kimyaya giriş', 'Atom modelleri', 'Periyodik tablo', 'Kimyasal türler arası etkileşimler', 'Maddenin halleri', 'Doğa ve kimya'],
    'bio': ['Canlıların ortak özellikleri', 'Canlıların çeşitliliği', 'Hücre', 'Dünyamız (ekoloji)'],
    'history': ['Tarih ve tarihçi', 'İlk çağ medeniyetleri', 'İlk Türk devletleri', 'İslam tarihine giriş'],
    'geo': ['Doğal sistemler', 'Coğrafi konum', 'Harita bilgisi', 'İklim', 'Yerleşme özellikleri'],
    'religion': ['İnanç esasları', 'İbadet', 'Ahlak', 'Değerler'],
    'ingilizce': ['Tenses genel tekrar', 'Daily life', 'Studying abroad', 'School life', 'Reading skills'],
    'second_lang': ['Alfabe-selamlama', 'Kendini tanıtma', 'Sayılar-zaman', 'Aile-arkadaşlar'],
    'logic': ['Önermeler', 'Bileşik önermeler', 'Açık önermeler', 'Mantık devreleri', 'Açık-kapalı önermeler, nicelik'],
  },
  'tr_high_10_sayisal': {
    'lit': ['Tanzimat edebiyatı', 'Servet-i Fünun', 'Milli edebiyat', 'Cumhuriyet dönemi', 'Şiir incelemesi', 'Öykü-roman', 'Tiyatro', 'Söz sanatları'],
    'math': ['Sayma ve olasılık (permütasyon-kombinasyon)', 'Fonksiyonlar', 'Polinomlar', 'İkinci dereceden denklemler', 'Çember', 'Üçgenler-dörtgenler (geometri)', 'Katı cisimler'],
    'physics': ['Elektrik ve manyetizma', 'Basınç ve kaldırma kuvveti', 'Dalgalar', 'Optik (ışık)'],
    'chem': ['Kimyanın temel kanunları', 'Mol kavramı ve hesaplamaları', 'Kimyasal tepkimeler', 'Asitler-bazlar-tuzlar', 'Karışımlar'],
    'bio': ['Hücre bölünmeleri (mitoz-mayoz)', 'Kalıtım', 'Ekosistem', 'Bitki ve hayvanlarda üreme'],
    'history': ['İslam tarihi (Hz. Peygamber-Dört Halife)', 'İlk Türk-İslam devletleri', 'Selçuklular', 'Anadolu Selçuklu', 'Osmanlı kuruluş'],
    'geo': ['Yer\'in şekli ve hareketleri', 'İç ve dış kuvvetler (yer şekilleri)', 'Biyoçeşitlilik', 'Nüfus'],
    'ingilizce': ['Advanced tenses', 'Modals', 'Passives', 'Reading comprehension', 'Essay intro'],
  },
  'tr_high_10_esit_agirlik': {
    'lit': ['Tanzimat edebiyatı', 'Servet-i Fünun', 'Milli edebiyat', 'Cumhuriyet dönemi', 'Şiir-öykü-roman', 'Söz sanatları', 'Eleştiri ve deneme'],
    'math': ['Sayma ve olasılık', 'Fonksiyonlar', 'Polinomlar', 'İkinci dereceden denklemler', 'Geometri (üçgen, dörtgen)', 'Analitik (doğrunun denklemi)'],
    'history': ['İslam tarihi', 'Türk-İslam devletleri', 'Selçuklular', 'Osmanlı kuruluş'],
    'geo': ['Yer hareketleri', 'Nüfus ve yerleşme', 'Bölgesel coğrafya', 'Ekonomik faaliyet'],
    'religion': ['Peygamberler tarihi', 'Kur\'an ve yorumu', 'Ahlak', 'Kelâm giriş'],
    'ingilizce': ['Past perfect', 'Reported speech', 'Adjective clauses', 'Paragraph writing'],
    'second_lang': ['Temel yapılar', 'Geçmiş zaman', 'Günlük konular'],
    'philosophy': ['Felsefeye giriş', 'Antik Yunan', 'Ortaçağ felsefesi'],
  },
  'tr_high_10_sozel': {
    'lit': ['Tanzimat', 'Servet-i Fünun', 'Milli edebiyat', 'Cumhuriyet dönemi', 'Şiir teorisi', 'Roman-öykü derin analiz', 'Tiyatro türleri'],
    'math': ['Sayma-olasılık', 'Fonksiyonlara giriş', 'Temel geometri'],
    'history': ['İslam tarihi', 'Türk-İslam devletleri', 'Selçuklular', 'Osmanlı kuruluş ve yükseliş'],
    'geo': ['Yer hareketleri', 'İklim ve bitki örtüsü', 'Beşeri coğrafya', 'Ekonomi coğrafyası'],
    'religion': ['Peygamberler tarihi', 'Tefsir', 'Hadis giriş'],
    'ingilizce': ['Reading-writing', 'Grammar review', 'Vocabulary building'],
    'second_lang': ['Günlük konuşma', 'Basit metin'],
    'philosophy': ['Felsefeye giriş', 'Antik Yunan felsefesi', 'Ortaçağ'],
    'logic': ['Önermeler mantığı', 'Çıkarım kuralları', 'Modal mantık temeli'],
  },
  'tr_high_10_dil': {
    'lit': ['Tanzimat', 'Servet-i Fünun', 'Milli edebiyat', 'Cumhuriyet'],
    'math': ['Sayma-olasılık', 'Temel fonksiyonlar'],
    'history': ['İslam tarihi', 'Türk-İslam devletleri', 'Osmanlı kuruluş-yükseliş'],
    'geo': ['Yer hareketleri', 'Beşeri coğrafya'],
    'ingilizce': ['Upper-intermediate: tenses, conditionals, modals', 'Reading, writing, speaking'],
    'second_lang': ['Orta seviye: zaman, kip, dilek', 'Konuşma - yazma'],
  },
  'tr_high_11_sayisal': {
    'lit': ['Tanzimat II. dönem', 'Servet-i Fünun derinleşme', 'Fecr-i Âti', 'Milli edebiyat', 'Türk halk edebiyatı', 'Metin analizi'],
    'math': ['Trigonometri (temel açılar, özdeşlikler)', 'Logaritma', 'Diziler (aritmetik, geometrik)', 'Limit', 'Türev', 'Analitik geometri (doğru, çember, parabol)'],
    'physics': ['Dalgalar (ses, ışık)', 'Optik', 'Manyetik alan ve indüksiyon', 'Modern fizik (foto-elektrik)'],
    'chem': ['Modern atom teorisi', 'Gazlar', 'Sıvı çözeltiler', 'Kimyasal tepkimelerde enerji', 'Kimyasal denge', 'Asit-baz dengesi'],
    'bio': ['İnsan fizyolojisi (sinir, endokrin)', 'Duyu organları', 'Destek ve hareket', 'Dolaşım, solunum', 'Boşaltım, üreme', 'Komünite ve popülasyon'],
    'history': ['Osmanlı duraklama', 'Gerileme', 'Yenileşme hareketleri (Tanzimat-Meşrutiyet)', 'II. Meşrutiyet'],
    'geo': ['Türkiye\'nin ekonomik coğrafyası', 'Doğal afetler', 'Çevre sorunları', 'Bölgesel kalkınma'],
    'religion': ['İslam düşünce ekolleri', 'Hadis usulü', 'Tasavvuf'],
    'ingilizce': ['Advanced grammar (subjunctive, inversion)', 'Academic reading', 'Essay writing'],
  },
  'tr_high_11_esit_agirlik': {
    'lit': ['Tanzimat II', 'Servet-i Fünun', 'Fecr-i Âti', 'Milli edebiyat', 'Cumhuriyet\'e hazırlık', 'Türk halk edebiyatı', 'Eleştiri-deneme'],
    'math': ['Trigonometri', 'Logaritma', 'Diziler', 'Limit-süreklilik', 'Türev temelleri', 'Analitik geometri (doğru, çember)'],
    'history': ['Osmanlı duraklama', 'Gerileme', 'Yenileşme', 'II. Meşrutiyet'],
    'geo': ['Ekonomik coğrafya', 'Ulaşım', 'Turizm', 'Çevre'],
    'religion': ['İslam düşünce ekolleri', 'Hadis', 'Tasavvuf'],
    'ingilizce': ['Advanced grammar', 'Academic English intro', 'Essay writing'],
    'second_lang': ['İleri zaman dilleri', 'Dilek ve koşul'],
    'philosophy': ['İslam felsefesi', 'Rönesans ve Aydınlanma felsefesi', 'Türk düşünürleri'],
    'psychology': ['Psikolojiye giriş', 'Öğrenme', 'Kişilik', 'Duygular'],
  },
  'tr_high_11_sozel': {
    'lit': ['Tanzimat II', 'Servet-i Fünun', 'Fecr-i Âti', 'Milli edebiyat', 'Cumhuriyet dönemi şiiri-romanı', 'Türk halk edebiyatı detay', 'Tiyatro yazarları'],
    'math': ['Temel trigonometri', 'Diziler'],
    'history': ['Osmanlı duraklama', 'Yenileşme hareketleri', 'II. Meşrutiyet', 'I. Dünya Savaşı'],
    'geo': ['Ekonomik coğrafya', 'Türkiye turizm', 'Bölgesel kalkınma'],
    'religion': ['İslam düşünce ekolleri', 'Tasavvuf'],
    'ingilizce': ['Advanced grammar', 'Reading-writing'],
    'second_lang': ['İleri konuşma'],
    'philosophy': ['İslam felsefesi', 'Rönesans', 'Aydınlanma', 'Türk düşünce tarihi'],
    'psychology': ['Psikolojiye giriş', 'Öğrenme', 'Kişilik'],
    'sociology': ['Sosyolojiye giriş', 'Toplumsal kurumlar', 'Kültür'],
    'logic': ['Klasik mantık', 'Modern sembolik mantık', 'Argümantasyon'],
  },
  'tr_high_11_dil': {
    'lit': ['Servet-i Fünun', 'Milli edebiyat', 'Cumhuriyet dönemi', 'Karşılaştırmalı edebiyat (TR-EN)'],
    'history': ['Osmanlı yenileşme', 'I. Dünya Savaşı'],
    'geo': ['Türkiye ekonomik coğrafyası'],
    'ingilizce': ['Proficient grammar', 'Academic essay', 'Advanced listening', 'IELTS/TOEFL hazırlık'],
    'second_lang': ['İleri konular', 'Dilek, koşul, edilgen'],
  },
  'tr_high_12_sayisal': {
    'lit': ['Cumhuriyet şiiri (Tan, Beş Hececiler, Garip, İkinci Yeni)', 'Cumhuriyet romanı (Halide Edip, Yakup Kadri, Orhan Kemal, Yaşar Kemal, O. Pamuk)', 'Tiyatro (Haldun Taner)', 'Dünya edebiyatından örnekler', 'YKS-edebiyat soru tipleri'],
    'math': ['Türev uygulamaları (ekstremum, türevle ilgili problemler)', 'İntegral (belirli, belirsiz)', 'Analitik geometri (elips, hiperbol, parabol)', 'Uzay geometri', 'Olasılık (koşullu)', 'İstatistik'],
    'physics': ['Elektrik ve elektronik (çember akım, Kirchhoff)', 'Basit harmonik hareket', 'Relativite girişi', 'Çekirdek fiziği (radyoaktivite)', 'Modern fizik (kuantum temelleri)'],
    'chem': ['Organik kimya (hidrokarbonlar)', 'Organik reaksiyonlar', 'Alkoller, eterler, aldehitler, ketonlar', 'Karboksilik asitler, esterler', 'Aromatik bileşikler', 'Kimya ve sağlık', 'YKS çıkmış soru tarama'],
    'bio': ['Genetik (Mendel, moleküler)', 'Biyoteknoloji-gen mühendisliği', 'Bitki fizyolojisi', 'İnsan fizyolojisi derin', 'Komünite-populasyon dinamikleri', 'Evrim'],
    'history': ['Çağdaş Türk ve dünya tarihi (20.yy)', 'Kurtuluş Savaşı', 'Cumhuriyet inkılapları', 'Atatürk dönemi iç-dış politika', 'Soğuk Savaş', 'Türkiye 1950 sonrası'],
    'geo': ['Küresel ortam (bölgeler, ülkeler)', 'Ekonomik coğrafya', 'Jeopolitik', 'Çevre ve sürdürülebilirlik'],
    'religion': ['Güncel dini meseleler', 'Çağdaş İslam düşüncesi'],
    'ingilizce': ['YKS YDT hazırlık (grammer, reading, cloze test)', 'Paragraph completion', 'Sentence completion'],
  },
  'tr_high_12_esit_agirlik': {
    'lit': ['Cumhuriyet şiiri-roman-tiyatro', 'YKS-edebiyat', 'Dünya edebiyatı'],
    'math': ['Türev uygulamaları', 'İntegral', 'Analitik geometri (konikler)', 'Olasılık-istatistik'],
    'history': ['Kurtuluş Savaşı', 'Cumhuriyet inkılapları', 'Atatürk dönemi', 'Soğuk Savaş', 'Türkiye 1950 sonrası'],
    'geo': ['Küresel ortam', 'Jeopolitik', 'Çevre'],
    'religion': ['Çağdaş İslam düşüncesi'],
    'ingilizce': ['YKS YDT hazırlık'],
    'second_lang': ['YKS YDT II. yabancı dil hazırlık'],
    'philosophy': ['Çağdaş felsefe (varoluşçuluk, fenomenoloji)', 'Bilim felsefesi', 'Etik'],
    'psychology': ['Bilişsel psikoloji', 'Anormal psikoloji'],
  },
  'tr_high_12_sozel': {
    'lit': ['Cumhuriyet şiiri-roman-tiyatro derin', 'YKS-edebiyat kritik konular', 'Metin analizi', 'Dünya edebiyatı'],
    'math': ['Temel türev-integral (TYT seviyesi)'],
    'history': ['Kurtuluş Savaşı', 'İnkılaplar', 'Atatürk ilkeleri', 'Soğuk Savaş', 'Türk siyasi tarihi'],
    'geo': ['Küresel ortam', 'Türkiye ve dünya (bölgeler)', 'Jeopolitik'],
    'religion': ['Çağdaş İslam düşüncesi', 'Dinler tarihi'],
    'ingilizce': ['YKS YDT'],
    'second_lang': ['YKS YDT'],
    'philosophy': ['Çağdaş felsefe', 'Bilim felsefesi', 'Etik', 'Sanat felsefesi'],
    'psychology': ['Öğrenme, gelişim, kişilik', 'Anormal psikoloji'],
    'sociology': ['Toplumsal değişim', 'Modernleşme', 'Küreselleşme'],
    'logic': ['Modern mantık', 'İnformel mantık (safsatalar)'],
  },
  'tr_high_12_dil': {
    'lit': ['Cumhuriyet dönemi', 'Dünya edebiyatından metinler', 'Karşılaştırmalı analiz'],
    'history': ['Kurtuluş Savaşı', 'Atatürk dönemi', 'Soğuk Savaş'],
    'geo': ['Küresel ortam'],
    'ingilizce': ['YKS YDT advanced', 'IELTS/TOEFL hazırlık'],
    'second_lang': ['YKS YDT II. dil advanced'],
  },
  'tr_exam_prep_yks_tyt': {
    'math': ['Temel kavramlar', 'Sayılar-işlemler', 'Rasyonel sayılar', 'Basit eşitsizlikler', 'Mutlak değer', 'Üslü-köklü sayılar', 'Oran-orantı', 'Denklem çözme', 'Problem çözme (hız, işçi, yaş)', 'Kümeler', 'Fonksiyonlar giriş', 'Geometri (açı, üçgen, dörtgen)'],
    'turkish': ['Sözcükte anlam', 'Cümlede anlam', 'Paragraf', 'Ses bilgisi', 'Yapı bilgisi', 'Sözcük türleri', 'Cümle ögeleri', 'Anlatım bozukluğu', 'Yazım-noktalama'],
    'physics': ['Fizik kavramları', 'Hareket', 'Kuvvet-denge', 'Enerji', 'Isı-sıcaklık'],
    'chem': ['Atom', 'Periyodik tablo', 'Kimyasal türler', 'Maddenin halleri', 'Asit-baz'],
    'bio': ['Hücre', 'Canlılar', 'Sistemler genel'],
    'history': ['İlk medeniyetler', 'İlk Türk devletleri', 'Osmanlı genel'],
    'geo': ['Türkiye coğrafyası temel', 'Harita bilgisi'],
    'philosophy': ['Felsefe giriş'],
    'religion': ['Din kültürü genel'],
  },
  'tr_exam_prep_yks_ayt': {
    'math': ['Polinomlar', 'Fonksiyonlar', 'İkinci dereceden denklem-eşitsizlik', 'Logaritma', 'Trigonometri', 'Diziler-seriler', 'Limit', 'Türev', 'İntegral', 'Analitik geometri', 'Olasılık', 'Sayma (permütasyon-kombinasyon)'],
    'physics': ['Elektrik-manyetizma', 'Dalgalar', 'Optik', 'Modern fizik', 'Basit harmonik hareket', 'Dönme hareketi'],
    'chem': ['Mol-kimyasal hesaplamalar', 'Gazlar', 'Çözeltiler', 'Kimyasal denge', 'Asit-baz-tuz', 'Elektrokimya', 'Organik kimya komple'],
    'bio': ['Sinir sistemi', 'Endokrin', 'Destek-hareket', 'Dolaşım-solunum', 'Boşaltım', 'Üreme', 'Kalıtım (Mendel, moleküler)', 'Biyoteknoloji', 'Evrim', 'Ekoloji'],
    'lit': ['Edebiyat tarihi (Divan, Tanzimat, Servet-i Fünun, Milli, Cumhuriyet)', 'Şiir bilgisi', 'Roman-öykü yazarları', 'Türlerin özellikleri'],
    'history': ['Tarih bilimi', 'İlk Türk devletleri', 'İlk Türk-İslam', 'Selçuklular', 'Osmanlı (kuruluş, yükseliş, duraklama, gerileme)', 'Kurtuluş Savaşı', 'İnkılaplar', 'Atatürk ilkeleri'],
    'geo': ['Doğal sistemler', 'Nüfus-yerleşme', 'Ekonomik faaliyet', 'Bölgesel-küresel ortam'],
    'philosophy': ['Felsefe tarihi', 'Bilgi-bilim-ahlak-siyaset-sanat-din felsefesi'],
  },
  'tr_exam_prep_lgs': {
    'math': ['8. sınıf tüm konular', 'Çarpanlar-katlar', 'Üslü-köklü', 'Cebir ve özdeşlikler', 'Eşitsizlikler', 'Üçgenler-Pisagor', 'Dönüşüm', 'Olasılık'],
    'turkish': ['Paragraf', 'Cümlede anlam', 'Anlatım biçimi ve düşünce yapısı', 'Fiilde çatı', 'Söz sanatları', 'Yazım ve noktalama'],
    'physics': ['8. sınıf: Basit makineler', 'Işık (yansıma-kırılma)', 'Elektrik devreleri'],
    'chem': ['8. sınıf: Periyodik tablo', 'Fiziksel-kimyasal olay', 'Asit-baz', 'Kimyasal tepkimeler'],
    'bio': ['8. sınıf: DNA-genetik', 'Hücre bölünmesi', 'Kalıtım'],
    'history': ['T.C. İnkılap Tarihi (Atatürk)', 'Kurtuluş Savaşı', 'Cumhuriyet', 'İnkılaplar'],
    'religion': ['Kader-irade', 'Zekât-sadaka', 'Hz. Muhammed', 'İslam ve bilim'],
    'ingilizce': ['LGS soru tipleri: visual-based, word-based', 'Vocab yoğun tekrar', 'Tenses (past/present/future)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇺🇸 UNITED STATES — Common Core + NGSS
  // ═════════════════════════════════════════════════════════════════════════
  'us_primary_1': {
    'math': ['Counting to 120', 'Addition & subtraction within 20', 'Place value (tens and ones)', 'Measurement (length)', 'Time (hour/half hour)', 'Basic geometry (shapes)'],
    'lang_native': ['Phonics', 'Reading simple texts', 'Sight words', 'Writing short sentences', 'Story sequencing'],
    'art_music': ['Color recognition', 'Simple songs', 'Rhythm basics'],
  },
  'us_primary_3': {
    'math': ['Multiplication (single digit)', 'Division basics', 'Fractions', 'Area & perimeter', 'Time (minutes)', 'Measurement'],
    'lang_native': ['Reading comprehension', 'Paragraph writing', 'Main idea', 'Parts of speech', 'Phonics'],
    'earth_science': ['Weather', 'Habitats', 'Rocks & soil'],
  },
  'us_primary_5': {
    'math': ['Decimals', 'Fractions — operations', 'Volume', 'Coordinate plane', 'Unit conversion', 'Algebraic thinking'],
    'lang_native': ['Reading literature/informational', 'Essay writing', 'Vocabulary', 'Grammar (conjunctions, tense)'],
    'earth_science': ['Ecosystems', 'Water cycle', 'Earth systems', 'Space basics'],
    'history': ['US history — colonial era', 'Revolutionary War', 'Constitution'],
  },
  'us_middle_7': {
    'math': ['Ratios & proportional relationships', 'Expressions & equations', 'Geometry (angles, surface area)', 'Statistics & probability', 'Integer operations'],
    'lang_native': ['Literary analysis', 'Argumentative writing', 'Research', 'Vocabulary in context'],
    'history': ['Ancient civilizations', 'World history — Rome, Medieval'],
    'geo': ['World geography', 'Physical vs. political maps', 'Climate'],
    'physics': ['Forces, motion', 'Energy'],
    'chem': ['Atoms & molecules', 'Periodic table'],
    'bio': ['Cells', 'Genetics basics', 'Ecosystems'],
  },
  'us_middle_8': {
    'math': ['Linear equations & functions', 'Systems of equations', 'Pythagorean theorem', 'Transformations', 'Statistics (scatter plots, regression intro)'],
    'lang_native': ['Literary analysis', 'Argumentative & narrative writing'],
    'history': ['US history — Civil War & Reconstruction', 'Industrial Revolution'],
    'physics': ['Waves', 'Electricity', 'Matter'],
  },
  'us_high_9': {
    'math': ['Algebra I (linear equations, inequalities, functions, quadratics, exponents, radicals, polynomials)'],
    'lang_native': ['Literature survey (short stories, novels)', 'Grammar review', 'Analytical essays', 'Research papers'],
    'physics': ['Physical science (motion, forces, energy, waves)'],
    'bio': ['Biology — cell biology, genetics, evolution, ecology'],
    'history': ['World History — classical civilizations → Renaissance'],
    'geo': ['Human Geography (AP possible)'],
    'second_lang': ['Spanish / French / Mandarin I'],
    'pe': ['Physical education'],
  },
  'us_high_10': {
    'math': ['Geometry (triangles, circles, proofs, coordinate geometry, transformations, 3D)'],
    'lang_native': ['American literature', 'Rhetoric', 'Research'],
    'chem': ['Chemistry (atomic theory, periodic table, bonding, stoichiometry, thermochem, equilibrium, acids/bases)'],
    'history': ['Modern World History', 'US History survey'],
  },
  'us_high_11': {
    'math': ['Algebra II / Pre-Calculus (functions, logarithms, exponentials, trigonometry, conic sections, sequences, series, complex numbers, matrices)'],
    'lang_native': ['American literature', 'SAT/ACT prep', 'Advanced writing'],
    'physics': ['Physics (kinematics, dynamics, energy, momentum, electricity, waves)'],
    'history': ['AP US History or US History'],
    'second_lang': ['Intermediate foreign language'],
    'electives': ['AP options: Calc AB, Statistics, Environmental Science, Psychology'],
  },
  'us_high_12_ap': {
    'math': ['AP Calculus AB/BC (limits, derivatives, integrals, series)'],
    'lang_native': ['AP English Literature or AP Language'],
    'physics': ['AP Physics 1/2 or C (mechanics, E&M)'],
    'chem': ['AP Chemistry (advanced)'],
    'bio': ['AP Biology'],
    'history': ['AP Government, AP World History'],
    'computer_science': ['AP CS A (Java)', 'AP CS Principles'],
    'economics': ['AP Microeconomics / Macroeconomics'],
    'statistics': ['AP Statistics'],
  },
  'us_high_12': {
    'math': ['Statistics / Pre-Calc / Calculus (honors or regular)'],
    'lang_native': ['English 12 — contemporary literature & composition'],
    'history': ['Government', 'Economics'],
    'electives': ['Electives — computer science, psychology, art, health'],
  },
  'us_exam_prep_sat': {
    'math': ['Heart of Algebra (linear equations, inequalities, functions)', 'Problem solving (ratios, percent, rates, scatter plots)', 'Passport to Advanced Math (quadratics, exponentials, polynomials, rational expressions)', 'Additional topics (geometry, trig, complex numbers)'],
    'lang_native': ['Reading (vocabulary in context, main idea, evidence, inference)', 'Writing (grammar, rhetoric, punctuation)', 'Essay (optional): analyze argument'],
  },
  'us_exam_prep_act': {
    'math': ['Pre-algebra, elementary algebra, intermediate algebra, coordinate geometry, plane geometry, trigonometry'],
    'english_lang': ['Usage, grammar, rhetoric'],
    'lang_native': ['Reading comprehension'],
    'physics': ['Science reasoning (interpretation of data, hypotheses)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇬🇧 UNITED KINGDOM — National Curriculum / GCSE / A-Level
  // ═════════════════════════════════════════════════════════════════════════
  'uk_primary_1': {
    'math': ['Number to 20', 'Addition & subtraction', '2D shapes', 'Measures (length, weight)'],
    'lang_native': ['Phonics (Letters & Sounds)', 'Reading', 'Handwriting', 'Spelling'],
    'pe': ['Movement', 'Team games'],
  },
  'uk_primary_6': {
    'math': ['Place value up to 10 million', 'Four operations', 'Fractions, decimals, percentages', 'Algebra (simple)', 'Ratio & proportion', 'Geometry (properties of shapes, coordinates)', 'Statistics'],
    'lang_native': ['Reading comprehension', 'Writing (narrative, non-fiction)', 'SPaG (spelling, punctuation, grammar)'],
    'bio': ['Living things & habitats', 'Animals including humans', 'Evolution & inheritance'],
    'history': ['British & world history (KS2)'],
  },
  'uk_middle_7': {
    'math': ['Numbers (BIDMAS)', 'Negative numbers', 'Fractions-decimals-percentages', 'Algebra intro', 'Geometry (angles, triangles, quadrilaterals)', 'Probability'],
    'lang_native': ['Shakespeare intro', 'Poetry', 'Fiction & non-fiction analysis', 'Creative writing'],
    'history': ['Medieval England', 'Renaissance'],
    'geo': ['Rivers, coasts, settlements'],
    'physics': ['Forces, energy, waves'],
    'chem': ['Particle theory, elements, compounds'],
    'bio': ['Cells, organisms'],
  },
  'uk_high_10': {
    'math': ['GCSE Maths: Number, Algebra, Ratio/Proportion, Geometry, Trigonometry, Probability, Statistics'],
    'english_lit': ['GCSE English Literature: Shakespeare play, 19th century novel, modern text, poetry anthology'],
    'english_lang': ['GCSE English Language: Reading fiction/non-fiction, writing narrative/argumentative'],
    'bio': ['GCSE Biology: Cell biology, organisation, infection & response, bioenergetics, homeostasis, inheritance, ecology'],
    'chem': ['GCSE Chemistry: Atomic structure, bonding, quantitative chemistry, chemical changes, energy changes, rates, organic'],
    'physics': ['GCSE Physics: Energy, electricity, particle model, atomic structure, forces, waves, magnetism'],
    'history': ['GCSE History: Depth studies (e.g., Weimar & Nazi Germany)', 'Period studies', 'Thematic studies'],
    'geo': ['GCSE Geography: Physical (tectonics, weather, ecosystems, UK landscapes)', 'Human (urban, development, resources)'],
    'mfl': ['GCSE French / German / Spanish: Identity, local area, global issues, travel'],
    're': ['GCSE RE: Christianity, Islam, ethics'],
  },
  'uk_high_11': {
    'math': ['GCSE Maths (continued / exam prep)', 'Further Maths GCSE (algebra, calculus intro, matrices)'],
    'english_lit': ['Exam preparation & essay technique'],
    'english_lang': ['Speaking & listening assessed'],
    'bio': ['GCSE Biology final year'],
    'chem': ['GCSE Chemistry final year'],
    'physics': ['GCSE Physics final year'],
  },
  'uk_high_12_sciences': {
    'math': ['A-Level Maths Year 1: Pure (algebra, functions, trig, differentiation, integration, exponentials, logarithms)', 'Statistics, Mechanics'],
    'physics': ['A-Level Physics: Mechanics, electric circuits, waves, photons'],
    'chem': ['A-Level Chemistry: Physical (atomic, bonding, energetics, kinetics, equilibria)', 'Inorganic (periodicity, Group 2, 7)', 'Organic (alkanes, alkenes, halogenoalkanes, alcohols, analysis)'],
    'bio': ['A-Level Biology: Biological molecules, cells, exchange, genetic information'],
  },
  'uk_high_12_humanities': {
    'english_lit': ['A-Level English Literature: Drama, prose, poetry pre-1900 and post-2000'],
    'history': ['A-Level History: British / European / World in depth + breadth study'],
    'geo': ['A-Level Geography: Physical (coasts, water, carbon)', 'Human (globalisation, population, regeneration)'],
    'philosophy': ['A-Level Philosophy: Epistemology, moral philosophy, metaphysics'],
  },
  'uk_exam_prep_alevel': {
    'math': ['A-Level Mathematics: Pure Maths, Statistics, Mechanics — full syllabus'],
    'physics': ['A-Level Physics full syllabus'],
    'chem': ['A-Level Chemistry full syllabus'],
    'bio': ['A-Level Biology full syllabus'],
    'english_lit': ['A-Level English Literature full syllabus'],
    'history': ['A-Level History full syllabus'],
    'geo': ['A-Level Geography full syllabus'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇩🇪 DEUTSCHLAND — Gymnasium / Abitur
  // ═════════════════════════════════════════════════════════════════════════
  'de_primary_4': {
    'math': ['Zahlenraum bis 1000', 'Schriftliches Rechnen', 'Einmaleins', 'Geometrie (Formen, Symmetrie)', 'Sachrechnen'],
    'lang_native': ['Deutsch — Rechtschreibung, Grammatik, Lesen, Schreiben'],
    'history': ['Sachkunde (Heimatkunde)'],
    'geo': ['Sachkunde (Orientierung im Raum)'],
    'english': ['Englisch — erste Begegnung, einfache Gespräche'],
  },
  'de_middle_7': {
    'math': ['Rationale Zahlen', 'Prozentrechnung', 'Zuordnungen (proportional, antiproportional)', 'Terme und Gleichungen', 'Dreiecksgeometrie'],
    'lang_native': ['Deutsch — Literatur, Grammatik, Aufsatz'],
    'history': ['Mittelalter', 'Reformation'],
    'geo': ['Europa', 'Klima und Vegetation'],
    'physics': ['Mechanik (Kräfte, Arbeit)', 'Optik'],
    'chem': ['Stoffe, Atome', 'Chemische Reaktionen'],
    'bio': ['Pflanzen, Tiere', 'Ökologie'],
    'english': ['English — Grammar (tenses), vocabulary, reading'],
    'second_lang': ['Zweite Fremdsprache (Französisch/Latein/Spanisch) Jahr 1-2'],
  },
  'de_high_10': {
    'math': ['Funktionen (quadratisch, Potenz, Exponential, Logarithmus)', 'Trigonometrie', 'Analytische Geometrie (Vektoren)', 'Stochastik'],
    'lang_native': ['Deutsch — Literaturepochen (Aufklärung, Sturm und Drang)', 'Argumentation'],
    'history': ['19. Jahrhundert (Industrialisierung, Kaiserreich)'],
    'geo': ['Globale Herausforderungen'],
    'physics': ['Elektrizität, Magnetismus', 'Wellen'],
    'chem': ['Redoxreaktionen', 'Säuren-Basen'],
    'bio': ['Genetik', 'Evolution'],
    'english': ['English — Advanced grammar, reading, writing'],
    'second_lang': ['Zweite Fremdsprache — fortgeschritten'],
  },
  'de_high_11': {
    'math': ['Differentialrechnung', 'Integralrechnung', 'Vektoren im Raum', 'Stochastik (Binomial-, Normalverteilung)'],
    'lang_native': ['Deutsch — Weimarer Klassik (Goethe, Schiller), Moderne'],
    'history': ['Weimarer Republik', 'Nationalsozialismus'],
    'physics': ['Elektromagnetische Induktion', 'Quantenphysik (Einführung)'],
    'chem': ['Organische Chemie (Alkane, Alkene, Alkohole)'],
    'bio': ['Neurobiologie', 'Ökologie vertieft'],
    'philosophy': ['Ethik-Einführung'],
  },
  'de_high_12': {
    'math': ['Abitur-Vorbereitung: Analysis, Lineare Algebra, Stochastik'],
    'lang_native': ['Deutsch — Gegenwartsliteratur, Kafka, Brecht, Essays'],
    'history': ['Deutschland nach 1945', 'Kalter Krieg', 'Wiedervereinigung'],
    'physics': ['Abitur-Niveau: Quantenphysik, Atomphysik, Kernphysik, Relativitätstheorie'],
    'chem': ['Biochemie, Farbstoffe, Naturstoffe'],
    'bio': ['Genetik auf molekularer Ebene', 'Immunologie', 'Evolution'],
  },
  'de_exam_prep_abitur': {
    'math': ['Abitur Mathematik: Analysis, Analytische Geometrie/Lineare Algebra, Stochastik'],
    'lang_native': ['Abitur Deutsch — Lyrik, Drama, Epik, Erörterung'],
    'english': ['Abitur Englisch — Textanalyse, Comment, Mediation'],
    'physics': ['Abitur Physik — Mechanik, E-Lehre, Quantenphysik'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇫🇷 FRANCE — Éducation Nationale / Baccalauréat
  // ═════════════════════════════════════════════════════════════════════════
  'fr_primary_5': {
    'math': ['Nombres entiers et décimaux', 'Fractions simples', 'Géométrie (figures usuelles)', 'Proportionnalité', 'Mesures'],
    'lang_native': ['Français — lecture, vocabulaire, grammaire, orthographe, rédaction'],
    'history': ['Histoire — Antiquité, Moyen Âge'],
    'geo': ['Géographie — France, Europe'],
    'english': ['Anglais — CM2 niveau A1'],
  },
  'fr_middle_9': {
    'math': ['Nombres rationnels', 'Calcul littéral', 'Équations', 'Fonctions linéaires, affines', 'Théorème de Pythagore', 'Théorème de Thalès', 'Trigonométrie (triangles rectangles)'],
    'lang_native': ['Français — roman, poésie, théâtre, argumentation'],
    'history': ['XXe siècle', 'Guerres mondiales', 'Décolonisation'],
    'geo': ['Mondialisation', 'Territoires'],
    'physics': ['Mécanique', 'Électricité', 'Chimie (réactions)'],
    'bio': ['SVT — corps humain, biologie cellulaire'],
    'english': ['Anglais niveau A2-B1'],
    'second_lang': ['LV2 (Espagnol/Allemand) niveau A2'],
  },
  'fr_high_10': {
    'math': ['Seconde : fonctions, vecteurs, probabilités, statistiques, géométrie'],
    'lang_native': ['Français — préparation Bac Français'],
    'history': ['Histoire moderne'],
    'physics': ['Physique-Chimie — mesure, ondes, matière, énergie'],
    'bio': ['SVT — biologie, géologie'],
    'english': ['Anglais niveau B1-B2'],
  },
  'fr_high_11_general': {
    'math': ['Première : spécialité mathématiques (suites, dérivation, fonctions exponentielles, probabilités)'],
    'lang_native': ['Français — épreuve anticipée du Bac'],
    'history': ['Histoire-Géo : XIXe-XXe siècles'],
    'physics': ['Physique-Chimie : cinématique, électromagnétisme, chimie organique'],
    'bio': ['SVT : génétique, évolution, écosystèmes'],
    'philosophy': ['Initiation philosophie'],
  },
  'fr_high_12_general': {
    'math': ['Terminale spécialité maths : continuité, dérivation, primitives, intégrales, logarithmes, complexes (option expert)'],
    'philosophy': ['Philosophie — sujets type Bac : conscience, désir, liberté, devoir, vérité, bonheur'],
    'history': ['Histoire-Géo : Guerres mondiales, guerre froide, mondialisation'],
    'physics': ['Physique-Chimie : mécanique, thermodynamique, ondes, nucléaire'],
    'bio': ['SVT : génétique moléculaire, climat, neurobiologie'],
    'lang_native': ['Français (le cas échéant pour Bac littéraire)'],
    'english': ['Anglais niveau B2'],
    'second_lang': ['LV2 niveau B1-B2'],
  },
  'fr_exam_prep_bac': {
    'math': ['Bac spécialité maths — toutes les notions du programme'],
    'philosophy': ['Bac philosophie — dissertation et explication de texte'],
    'physics': ['Bac Physique-Chimie'],
    'bio': ['Bac SVT'],
    'lang_native': ['Bac Français (oral + écrit)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇯🇵 JAPAN — MEXT Course of Study
  // ═════════════════════════════════════════════════════════════════════════
  'jp_primary_6': {
    'math': ['分数と小数の計算', '比と比の値', '面積と体積', '速さ', '割合', 'グラフと整理'],
    'lit': ['国語 — 物語、説明文、詩、漢字、作文'],
    'history': ['社会 — 日本の歴史概観'],
    'geo': ['社会 — 日本の地理'],
    'physics': ['理科 — 物の燃え方、電気'],
    'english': ['英語 — 基本の挨拶、自己紹介'],
    'pe': ['体育'],
    'art_music': ['図工、音楽'],
  },
  'jp_middle_9': {
    'math': ['式の展開と因数分解', '平方根', '二次方程式', '関数 y=ax²', '相似', '三平方の定理', '円周角', '標本調査'],
    'lit': ['国語 — 古文、漢文入門、文学作品'],
    'history': ['社会 — 近現代史、公民'],
    'geo': ['社会 — 世界地理'],
    'physics': ['理科 — 運動とエネルギー、電気・磁気'],
    'chem': ['理科 — 化学変化、酸とアルカリ'],
    'bio': ['理科 — 生命の連続性、遺伝'],
    'english': ['英語 — 現在完了、関係代名詞、長文読解'],
  },
  'jp_high_10': {
    'math': ['数学I (数と式、2次関数、図形と計量、データの分析)', '数学A (場合の数、確率、整数、図形の性質)'],
    'lit': ['国語総合 — 現代文、古典'],
    'physics': ['物理基礎 — 運動、エネルギー、波、電気'],
    'chem': ['化学基礎 — 物質の構成、物質量、化学反応'],
    'bio': ['生物基礎 — 細胞、代謝、遺伝情報、生体防御'],
    'history': ['世界史A または 日本史A'],
    'geo': ['地理A'],
    'english': ['コミュニケーション英語I, 英語表現I'],
  },
  'jp_high_11': {
    'math': ['数学II (式と証明、複素数、三角関数、指数対数、微分積分入門)', '数学B (数列、ベクトル、統計的な推測)'],
    'lit': ['現代文B、古典B'],
    'physics': ['物理 — 力学、熱、波動、電磁気 (発展)'],
    'chem': ['化学 — 物質の状態、化学反応と熱、化学平衡、無機・有機化学'],
    'bio': ['生物 — 生物の進化、遺伝情報と発現、生命現象、生物の環境応答'],
    'history': ['世界史B、日本史B (受験向け)'],
    'english': ['コミュニケーション英語II'],
  },
  'jp_high_12': {
    'math': ['数学III (極限、微分、積分、複素数平面、式と曲線)'],
    'lit': ['大学入試対策'],
    'physics': ['原子物理、相対性理論入門 (発展)'],
    'chem': ['高分子化合物、天然・合成有機'],
    'bio': ['生態系、進化の総合'],
    'english': ['コミュニケーション英語III、英語表現II'],
  },
  'jp_exam_prep_kyotsu': {
    'math': ['共通テスト数学I・A, II・B'],
    'lit': ['共通テスト国語 — 現代文、古文、漢文'],
    'physics': ['共通テスト物理'],
    'chem': ['共通テスト化学'],
    'bio': ['共通テスト生物'],
    'history': ['共通テスト世界史B / 日本史B'],
    'english': ['共通テスト英語 (リーディング・リスニング)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇨🇳 CHINA — 高考 curriculum
  // ═════════════════════════════════════════════════════════════════════════
  'cn_high_12_lixue': {
    'math': ['函数与导数', '三角函数', '数列', '立体几何', '解析几何 (圆锥曲线)', '概率与统计', '不等式', '复数'],
    'physics': ['力学 (牛顿定律、动量、能量)', '电磁学', '热学', '光学', '原子物理', '振动与波'],
    'chem': ['物质结构与性质', '化学反应原理', '有机化学基础', '物质的量', '电化学'],
    'bio': ['分子与细胞', '遗传与进化', '稳态与环境', '生物技术实践'],
    'lit': ['语文 — 古代诗文、现代文阅读、写作'],
    'english': ['英语 — 阅读、写作、听力、语法'],
  },
  'cn_high_12_wenxue': {
    'math': ['函数', '三角', '数列', '立体几何', '解析几何基础', '概率统计', '不等式'],
    'lit': ['语文 — 古诗文、现代文深入分析、议论文写作'],
    'history': ['中国古代史', '中国近现代史', '世界史'],
    'geo': ['人文地理', '自然地理', '区域地理'],
    'civics': ['政治 — 经济生活、政治生活、文化生活、哲学'],
    'english': ['英语'],
  },
  'cn_exam_prep_gaokao': {
    'math': ['高考数学 (文科 or 理科全套)'],
    'lit': ['高考语文'],
    'english': ['高考英语'],
    'physics': ['高考物理 (理科)'],
    'chem': ['高考化学 (理科)'],
    'bio': ['高考生物 (理科)'],
    'history': ['高考历史 (文科)'],
    'geo': ['高考地理 (文科)'],
    'civics': ['高考政治 (文科)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇰🇷 KOREA — 수능 / CSAT
  // ═════════════════════════════════════════════════════════════════════════
  'kr_high_12_jayeon': {
    'math': ['수학 I (지수, 로그, 삼각함수, 수열)', '수학 II (극한, 미분, 적분)', '미적분 (급수, 다변수, 심화 적분)', '기하 (이차곡선, 공간도형)'],
    'physics': ['물리학 I (역학, 전자기)', '물리학 II (파동, 현대물리)'],
    'chem': ['화학 I (물질의 구성, 화학결합)', '화학 II (물질의 상태와 용액, 화학반응, 평형)'],
    'bio': ['생명과학 I (세포, 유전)', '생명과학 II (유전자, 진화, 생태)'],
    'lit': ['국어 — 화법, 작문, 문학, 독서, 문법'],
    'history': ['한국사 (필수)'],
    'english': ['영어 — 독해, 어휘, 문법'],
  },
  'kr_high_12_insa': {
    'math': ['수학 I, 수학 II (기본)', '확률과 통계'],
    'lit': ['국어 — 심화 문학, 독서'],
    'history': ['한국사', '동아시아사', '세계사'],
    'geo': ['한국지리', '세계지리'],
    'civics': ['생활과 윤리', '윤리와 사상', '사회·문화', '정치와 법', '경제'],
    'english': ['영어'],
  },
  'kr_exam_prep_suneung': {
    'math': ['수능 수학 (수학 I, 수학 II, 확률과 통계 or 미적분 or 기하)'],
    'lit': ['수능 국어 — 독서, 문학, 화법과 작문'],
    'english': ['수능 영어'],
    'history': ['수능 한국사'],
    'physics': ['수능 물리 (선택)'],
    'chem': ['수능 화학 (선택)'],
    'bio': ['수능 생명과학 (선택)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇮🇳 INDIA — CBSE / NCERT
  // ═════════════════════════════════════════════════════════════════════════
  'in_high_10': {
    'math': ['Real numbers', 'Polynomials', 'Linear equations in two variables', 'Quadratic equations', 'Arithmetic progressions', 'Triangles', 'Coordinate geometry', 'Trigonometry', 'Circles', 'Surface area & volumes', 'Statistics', 'Probability'],
    'physics': ['Light — reflection & refraction', 'Electricity', 'Magnetic effects of current', 'Human eye & colourful world', 'Our environment (physics aspects)'],
    'chem': ['Chemical reactions & equations', 'Acids, bases & salts', 'Metals & non-metals', 'Carbon & its compounds', 'Periodic classification'],
    'bio': ['Life processes', 'Control & coordination', 'How do organisms reproduce', 'Heredity & evolution', 'Our environment'],
    'lit': ['Hindi / English Literature — prose, poetry, drama'],
    'history': ['History — Nationalism in India, Making of Global World'],
    'geo': ['Geography — Resources, forests, wildlife, water, agriculture'],
    'political_science': ['Civics — Power sharing, federalism, democracy'],
    'economics': ['Economics — Development, sectors, money, globalisation'],
    'english': ['English Grammar & Comprehension'],
  },
  'in_high_11_science': {
    'math': ['Sets', 'Relations & functions', 'Trigonometric functions', 'Complex numbers', 'Linear inequalities', 'Permutations & combinations', 'Binomial theorem', 'Sequences & series', 'Coordinate geometry', 'Limits & derivatives intro', 'Statistics', 'Probability'],
    'physics': ['Physical world & measurement', 'Kinematics', 'Laws of motion', 'Work, energy, power', 'Rotational motion', 'Gravitation', 'Mechanical properties of solids/fluids', 'Thermodynamics', 'Kinetic theory', 'Oscillations', 'Waves'],
    'chem': ['Some basic concepts', 'Structure of atom', 'Periodic classification', 'Chemical bonding', 'States of matter', 'Thermodynamics', 'Equilibrium', 'Redox reactions', 'Hydrogen', 's-block, p-block', 'Organic chemistry basics', 'Hydrocarbons'],
    'bio': ['Diversity of living organisms', 'Structural organisation in animals & plants', 'Cell structure & function', 'Plant physiology', 'Human physiology'],
    'english': ['English Core — Hornbill, Snapshots'],
    'computer_science': ['Computer Science — Python, algorithms, data structures intro'],
  },
  'in_high_12_science': {
    'math': ['Relations & functions (advanced)', 'Inverse trigonometric functions', 'Matrices', 'Determinants', 'Continuity & differentiability', 'Applications of derivatives', 'Integrals', 'Applications of integrals', 'Differential equations', 'Vector algebra', '3D geometry', 'Linear programming', 'Probability'],
    'physics': ['Electrostatics', 'Current electricity', 'Magnetic effects & magnetism', 'Electromagnetic induction & AC', 'EM waves', 'Optics', 'Dual nature of matter', 'Atoms & nuclei', 'Electronic devices', 'Communication systems'],
    'chem': ['Solid state', 'Solutions', 'Electrochemistry', 'Chemical kinetics', 'Surface chemistry', 'd & f block', 'Coordination compounds', 'Haloalkanes', 'Alcohols & ethers', 'Aldehydes & ketones', 'Amines', 'Biomolecules', 'Polymers', 'Chemistry in everyday life'],
    'bio': ['Reproduction', 'Genetics & evolution', 'Biology & human welfare', 'Biotechnology', 'Ecology & environment'],
    'english': ['English Core — Flamingo, Vistas'],
    'computer_science': ['Data structures, algorithms, databases, Python'],
  },
  'in_high_12_commerce': {
    'math': ['Applied Mathematics (or regular Maths)'],
    'accountancy': ['Accounting for partnership firms', 'Company accounts', 'Financial statement analysis', 'Cash flow statement'],
    'business_studies': ['Principles of management', 'Business environment', 'Planning, organising', 'Directing, controlling', 'Financial management', 'Marketing'],
    'economics': ['Microeconomics (consumer equilibrium, demand, supply, market)', 'Macroeconomics (national income, money, banking, government budget, BoP)'],
    'english': ['English Core'],
  },
  'in_high_12_arts': {
    'history': ['Themes in Indian history (Harappan, Mauryan, Mughal, colonial, freedom struggle)'],
    'geo': ['Fundamentals of human geography', 'India: people & economy'],
    'political_science': ['Indian politics since Independence', 'Contemporary world politics'],
    'economics': ['Microeconomics & Macroeconomics'],
    'english': ['English Core or English Elective'],
    'psychology': ['Psychology — variations in psychological attributes, self & personality, meeting life challenges'],
  },
  'in_exam_prep_jee_main': {
    'math': ['Sets, functions, matrices, determinants, sequences, permutations, binomial, limits, continuity, differentiation, integration, differential equations, vectors, 3D geometry, probability, statistics, conic sections, straight lines, circles, trigonometry, complex numbers'],
    'physics': ['Kinematics, laws of motion, work-energy, rotational, gravitation, properties of solids/fluids, thermodynamics, oscillations, waves, electrostatics, current electricity, magnetism, EMI, AC, EM waves, optics, modern physics'],
    'chem': ['Physical (atoms, chemical bonding, thermodynamics, equilibrium, kinetics, solutions, electrochem)', 'Inorganic (periodic table, coordination, metallurgy, s/p/d/f blocks)', 'Organic (hydrocarbons, haloalkanes, alcohols, aldehydes, amines, biomolecules, polymers)'],
  },
  'in_exam_prep_neet': {
    'bio': ['Diversity of living world, cell structure & function, plant physiology, human physiology, reproduction, genetics, evolution, biology & human welfare, biotechnology, ecology'],
    'physics': ['NEET physics (concepts, application)'],
    'chem': ['NEET chemistry (physical, inorganic, organic)'],
  },
  'in_exam_prep_cat': {
    'math': ['CAT Quantitative Ability (numbers, algebra, geometry, arithmetic, modern math, functions)'],
    'english': ['CAT Verbal Ability & Reading Comprehension'],
    'statistics': ['CAT Data Interpretation & Logical Reasoning'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇨🇦 CANADA — Ontario / Quebec / BC curricula
  // ═════════════════════════════════════════════════════════════════════════
  'ca_high_11': {
    'math': ['Functions 11 (exponential, logarithmic, trigonometric, sequences, discrete)', 'Pre-Calculus (Western provinces)'],
    'physics': ['Physics 11 — kinematics, forces, energy, momentum, waves, electricity'],
    'chem': ['Chemistry 11 — matter, bonding, mole concept, solutions, gases'],
    'bio': ['Biology 11 — biodiversity, cellular processes, evolution, animal systems'],
    'english_lang': ['English 11 — literary analysis, essay writing'],
    'history': ['Canadian History (Grade 10-11 depending on province)'],
    'second_lang': ['French / other second language (Core French mandatory early grades)'],
  },
  'ca_high_12': {
    'math': ['Advanced Functions / MHF4U (polynomial, rational, exponential, logarithmic, trig, combinations)', 'Calculus & Vectors (MCV4U)', 'Data Management (MDM4U) — probability, statistics'],
    'physics': ['Physics 12 — forces, energy, electromagnetism, optics, modern physics'],
    'chem': ['Chemistry 12 — thermochemistry, rates, equilibrium, acids/bases, electrochem, organic'],
    'bio': ['Biology 12 — biochemistry, metabolic processes, molecular genetics, homeostasis, population dynamics'],
    'english_lang': ['English 12 (ENG4U) — Canadian literature, advanced composition'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇦🇺 AUSTRALIA — Australian Curriculum + state frameworks (NSW/VIC/QLD)
  // ═════════════════════════════════════════════════════════════════════════
  'au_high_11': {
    'math': ['Mathematics Advanced (functions, calculus intro, trigonometric functions, probability)', 'Mathematics Extension (advanced topics)', 'Mathematics Standard (applications)'],
    'physics': ['Physics — kinematics, dynamics, waves, thermodynamics, electricity'],
    'chem': ['Chemistry — periodic table, bonding, reactions, acids/bases, equilibrium'],
    'bio': ['Biology — cells, genetics, evolution, ecosystems'],
    'english_lang': ['English Advanced — texts & human experiences, texts & society'],
    'history': ['Modern History / Ancient History'],
    'geo': ['Geography — biophysical, human, environmental'],
  },
  'au_high_12': {
    'math': ['Mathematics Extension 2 (HSC): complex numbers, proof, vectors, calculus, mechanics'],
    'physics': ['HSC Physics — advanced mechanics, electromagnetism, nature of light, quantum mechanics'],
    'chem': ['HSC Chemistry — equilibrium, acid/base, organic, applied chemistry'],
    'bio': ['HSC Biology — heredity, genetic change, infectious disease, non-infectious disease'],
    'english_lang': ['HSC English Advanced — common module, module A (textual conversations), B, C'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇷🇺 RUSSIA — школьная программа (ФГОС)
  // ═════════════════════════════════════════════════════════════════════════
  'ru_high_10': {
    'math': ['Алгебра 10 класс — тригонометрические функции, уравнения, производная', 'Геометрия 10 класс — стереометрия, многогранники'],
    'physics': ['Механика (кинематика, динамика, законы сохранения)', 'Молекулярная физика, термодинамика', 'Электростатика'],
    'chem': ['Строение атома, периодический закон', 'Химическая связь', 'Органическая химия (углеводороды, спирты, альдегиды)'],
    'bio': ['Клетка, метаболизм', 'Размножение, индивидуальное развитие', 'Генетика, селекция'],
    'lit': ['Русская литература XIX века — Пушкин, Лермонтов, Гоголь, Тургенев, Достоевский, Толстой'],
    'lang_native': ['Русский язык — орфография, пунктуация, стилистика'],
    'history': ['История России (с древнейших времён до XIX века)', 'Всеобщая история'],
    'geo': ['Экономическая и социальная география мира'],
    'english': ['Английский язык — грамматика, чтение, аудирование'],
  },
  'ru_high_11': {
    'math': ['Алгебра 11 — показательные, логарифмические, тригонометрические уравнения, первообразная, интеграл', 'Геометрия 11 — тела вращения, объемы'],
    'physics': ['Электромагнетизм, электромагнитная индукция', 'Оптика, волны', 'Квантовая физика, ядерная физика', 'Астрофизика'],
    'chem': ['Общая и неорганическая химия', 'Органическая химия (ароматические, азотсодержащие, биополимеры)', 'Химия в жизни'],
    'bio': ['Эволюция, происхождение жизни', 'Экология, биосфера'],
    'lit': ['Русская литература XX века — Блок, Маяковский, Есенин, Булгаков, Шолохов, Солженицын'],
    'history': ['История России XX века — революции, ВОВ, СССР, постсоветская Россия'],
    'english': ['Английский язык — подготовка к ЕГЭ'],
  },
  'ru_exam_prep_ege': {
    'math': ['ЕГЭ Математика (профиль или база) — полный курс'],
    'physics': ['ЕГЭ Физика'],
    'chem': ['ЕГЭ Химия'],
    'bio': ['ЕГЭ Биология'],
    'lit': ['ЕГЭ Литература'],
    'lang_native': ['ЕГЭ Русский язык'],
    'history': ['ЕГЭ История'],
    'english': ['ЕГЭ Английский язык'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇧🇷 BRAZIL — BNCC / ENEM
  // ═════════════════════════════════════════════════════════════════════════
  'br_high_11': {
    'math': ['Matemática — funções exponenciais e logarítmicas, trigonometria, sequências, progressões'],
    'physics': ['Física — eletrostática, eletrodinâmica, eletromagnetismo, ondas'],
    'chem': ['Química — soluções, termoquímica, cinética, equilíbrio, eletroquímica'],
    'bio': ['Biologia — genética, evolução, ecologia'],
    'lit': ['Literatura — Realismo, Naturalismo, Modernismo brasileiro'],
    'lang_native': ['Português — produção textual, redação dissertativa-argumentativa'],
    'history': ['História do Brasil — Império a República Velha'],
    'geo': ['Geografia — globalização, geopolítica, questões ambientais'],
    'philosophy': ['Filosofia — ética, política, estética'],
    'sociology': ['Sociologia — cultura, trabalho, movimentos sociais'],
    'english': ['Inglês'],
  },
  'br_high_12': {
    'math': ['Matemática — geometria analítica, matrizes, determinantes, sistemas lineares, análise combinatória, probabilidade, números complexos'],
    'physics': ['Física — física moderna, relatividade, quantização'],
    'chem': ['Química orgânica (hidrocarbonetos, álcoois, aldeídos, cetonas, ácidos, ésteres, aromáticos, biomoléculas)'],
    'bio': ['Biologia — biotecnologia, fisiologia humana completa, sistemas'],
    'lit': ['Literatura — Modernismo brasileiro fase 3, contemporânea, autores ENEM'],
    'history': ['História contemporânea — Guerra Fria, Brasil República'],
    'geo': ['Geografia do Brasil, cartografia, relevo, clima'],
  },
  'br_exam_prep_enem': {
    'math': ['ENEM Matemática e suas Tecnologias'],
    'physics': ['ENEM Ciências da Natureza — Física'],
    'chem': ['ENEM Ciências da Natureza — Química'],
    'bio': ['ENEM Ciências da Natureza — Biologia'],
    'lit': ['ENEM Linguagens, Códigos e Literatura'],
    'history': ['ENEM Ciências Humanas — História'],
    'geo': ['ENEM Ciências Humanas — Geografia'],
    'philosophy': ['ENEM Filosofia e Sociologia'],
    'english': ['ENEM Língua Estrangeira (Inglês ou Espanhol)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇪🇸 SPAIN — LOMLOE Bachillerato
  // ═════════════════════════════════════════════════════════════════════════
  'es_high_11': {
    'math': ['Matemáticas I (funciones, trigonometría, geometría analítica, probabilidad)'],
    'physics': ['Física y Química — cinemática, dinámica, energía, electricidad, química'],
    'bio': ['Biología y Geología — anatomía, fisiología, geología'],
    'lit': ['Lengua Castellana y Literatura — Edad Media a Siglo de Oro'],
    'history': ['Historia del Mundo Contemporáneo'],
    'philosophy': ['Filosofía'],
    'english': ['Inglés — nivel B1-B2'],
  },
  'es_high_12': {
    'math': ['Matemáticas II (análisis, álgebra, geometría, probabilidad avanzada)'],
    'physics': ['Física — mecánica, electromagnetismo, ondas, física moderna'],
    'chem': ['Química — estructura atómica, enlace, termoquímica, cinética, equilibrio, ácidos/bases, electroquímica, orgánica'],
    'bio': ['Biología — bioquímica, genética, microbiología, inmunología'],
    'lit': ['Lengua Castellana y Literatura II — Generación del 98, 27, Posguerra, Contemporánea'],
    'history': ['Historia de España'],
    'philosophy': ['Historia de la Filosofía'],
    'english': ['Inglés — nivel B2'],
  },
  'es_exam_prep_evau': {
    'math': ['EvAU/EBAU Matemáticas II'],
    'lit': ['EvAU Lengua Castellana y Literatura'],
    'english': ['EvAU Inglés'],
    'history': ['EvAU Historia de España'],
    'physics': ['EvAU Física'],
    'chem': ['EvAU Química'],
    'bio': ['EvAU Biología'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇮🇹 ITALY — Liceo / Maturità
  // ═════════════════════════════════════════════════════════════════════════
  'it_high_11': {
    'math': ['Matematica — funzioni, geometria analitica, trigonometria, esponenziali, logaritmi'],
    'physics': ['Fisica — elettromagnetismo, ottica'],
    'chem': ['Chimica — chimica organica base'],
    'bio': ['Biologia — genetica, evoluzione'],
    'lit': ['Italiano — Dante, Petrarca, Boccaccio, Ariosto, Tasso (Rinascimento)'],
    'history': ['Storia — Età Moderna (Illuminismo, Rivoluzioni)'],
    'philosophy': ['Filosofia — Filosofia Moderna (Cartesio, Kant, Hegel)'],
    'english': ['Inglese — livello B1-B2'],
    'second_lang': ['Seconda lingua (francese/tedesco/spagnolo)'],
  },
  'it_high_12': {
    'math': ['Matematica — analisi (derivate, integrali), probabilità, statistica'],
    'physics': ['Fisica — fisica moderna (relatività, quantistica)'],
    'lit': ['Italiano — Verismo, Decadentismo, Novecento (Pirandello, Ungaretti, Montale, Calvino)'],
    'history': ['Storia contemporanea (XX secolo)'],
    'philosophy': ['Filosofia Contemporanea (Nietzsche, Marx, Freud, Esistenzialismo)'],
    'english': ['Inglese — livello B2'],
  },
  'it_exam_prep_maturita': {
    'math': ['Maturità scientifica Matematica'],
    'physics': ['Maturità Fisica'],
    'lit': ['Maturità prima prova — saggio breve, articolo, analisi del testo'],
    'history': ['Maturità Storia'],
    'philosophy': ['Maturità Filosofia'],
    'english': ['Maturità seconda prova Inglese (liceo linguistico)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇳🇱 NETHERLANDS — HAVO/VWO
  // ═════════════════════════════════════════════════════════════════════════
  'nl_high_11': {
    'math': ['Wiskunde A (statistiek, kansrekening) of B (analyse, meetkunde) of C (maatschappelijk)', 'Wiskunde D (verdieping)'],
    'physics': ['Natuurkunde — mechanica, golven, elektromagnetisme'],
    'chem': ['Scheikunde — organische chemie, reactiekinetiek'],
    'bio': ['Biologie — genetica, ecologie, anatomie'],
    'lit': ['Nederlands — literatuurgeschiedenis, betogen'],
    'history': ['Geschiedenis — oriëntatiekennis op tien tijdvakken'],
    'geo': ['Aardrijkskunde — wereld, globalisering'],
    'english': ['Engels — niveau B2'],
    'second_lang': ['Duits / Frans'],
  },
  'nl_high_12': {
    'math': ['Wiskunde — eindexamenjaar, differentiaal- en integraalrekening'],
    'physics': ['Natuurkunde — kwantummechanica, relativiteit'],
    'chem': ['Scheikunde — biochemie'],
    'bio': ['Biologie — evolutie, homeostase'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇸🇪 SWEDEN — Gymnasium
  // ═════════════════════════════════════════════════════════════════════════
  'se_high_11': {
    'math': ['Matematik 3 (trigonometri, derivata, integraler intro)', 'Matematik 4 (komplexa tal, vidare analys)'],
    'physics': ['Fysik 1 & 2 — mekanik, elektricitet, termodynamik, vågor, modern fysik'],
    'chem': ['Kemi 1 & 2 — atomer, bindningar, reaktioner, organisk kemi'],
    'bio': ['Biologi 1 & 2 — genetik, evolution, ekologi, människokroppen'],
    'lit': ['Svenska 2 — litteraturhistoria, skrivande'],
    'history': ['Historia — 1500-talet till nutid'],
    'english': ['Engelska 6'],
    'philosophy': ['Filosofi'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇫🇮 FINLAND — Lukio
  // ═════════════════════════════════════════════════════════════════════════
  'fi_high_11': {
    'math': ['Pitkä matematiikka — algebra, funktiot, derivaatta, integraali, vektorit, todennäköisyys'],
    'physics': ['Fysiikka — mekaniikka, sähkömagnetismi, aaltoliike, moderni fysiikka'],
    'chem': ['Kemia — atomirakenne, sidokset, reaktiot, orgaaninen kemia'],
    'bio': ['Biologia — solubiologia, genetiikka, evoluutio, ekologia'],
    'lit': ['Äidinkieli (suomi) — kirjallisuushistoria, kirjoittaminen'],
    'history': ['Historia — 1800-1900-luku'],
    'english': ['Englanti — B2-C1 taso'],
    'second_lang': ['Ruotsi — pakollinen'],
    'philosophy': ['Filosofia'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇵🇱 POLAND — Liceum / Matura
  // ═════════════════════════════════════════════════════════════════════════
  'pl_high_11': {
    'math': ['Matematyka — funkcja kwadratowa, wielomiany, funkcje wykładnicze i logarytmiczne, trygonometria, ciągi'],
    'physics': ['Fizyka — mechanika, termodynamika, elektryczność, magnetyzm'],
    'chem': ['Chemia — atomy, wiązania, reakcje, chemia organiczna'],
    'bio': ['Biologia — biochemia, genetyka, ewolucja, ekologia'],
    'lit': ['Język polski — literatura (Romantyzm, Pozytywizm, Młoda Polska)'],
    'history': ['Historia — XIX-XX wiek'],
    'geo': ['Geografia — fizyczna, społeczno-ekonomiczna'],
    'english': ['Język angielski — poziom B2'],
    'second_lang': ['Język niemiecki / hiszpański / francuski'],
  },
  'pl_high_12': {
    'math': ['Matematyka — rachunek różniczkowy i całkowy, geometria analityczna, prawdopodobieństwo, statystyka, przygotowanie do matury'],
    'physics': ['Fizyka — elektromagnetyzm, optyka, fizyka współczesna, fizyka kwantowa'],
    'lit': ['Język polski — Dwudziestolecie międzywojenne, literatura współczesna'],
    'history': ['Historia — historia Polski XX wieku'],
  },
  'pl_exam_prep_matura': {
    'math': ['Matura z matematyki (poziom podstawowy i rozszerzony)'],
    'lit': ['Matura z języka polskiego'],
    'english': ['Matura z języka angielskiego'],
    'physics': ['Matura z fizyki'],
    'chem': ['Matura z chemii'],
    'bio': ['Matura z biologii'],
    'history': ['Matura z historii'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇺🇦 UKRAINE — ЗНО / НМТ
  // ═════════════════════════════════════════════════════════════════════════
  'ua_high_11': {
    'math': ['Алгебра та початки аналізу — похідна, інтеграл', 'Геометрія — стереометрія, об\'єми'],
    'physics': ['Фізика — електромагнетизм, оптика, атомна та ядерна фізика'],
    'chem': ['Хімія — органічна хімія, неорганічні сполуки'],
    'bio': ['Біологія — генетика, еволюція, екологія'],
    'lit': ['Українська література — Підкарпаття, Шевченко, Франко, Леся Українка, Тичина, Довженко'],
    'lang_native': ['Українська мова — синтаксис, стилістика'],
    'history': ['Історія України', 'Всесвітня історія'],
    'geo': ['Географія України та світу'],
    'english': ['Англійська мова'],
  },
  'ua_exam_prep_zno': {
    'math': ['ЗНО/НМТ Математика'],
    'lang_native': ['ЗНО/НМТ Українська мова та література'],
    'english': ['ЗНО/НМТ Англійська мова'],
    'history': ['ЗНО/НМТ Історія України'],
    'physics': ['ЗНО Фізика'],
    'chem': ['ЗНО Хімія'],
    'bio': ['ЗНО Біологія'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇲🇽 MEXICO — SEP Bachillerato
  // ═════════════════════════════════════════════════════════════════════════
  'mx_high_11': {
    'math': ['Matemáticas III — Trigonometría, geometría analítica', 'Matemáticas IV — Funciones, límites'],
    'physics': ['Física — mecánica, fluidos, termodinámica, electricidad'],
    'chem': ['Química — enlaces químicos, reacciones, estequiometría, soluciones'],
    'bio': ['Biología — genética, evolución, ecología'],
    'lit': ['Literatura — literatura mexicana, latinoamericana, universal'],
    'lang_native': ['Español — comunicación oral y escrita'],
    'history': ['Historia de México'],
    'geo': ['Geografía de México'],
    'english': ['Inglés'],
  },
  'mx_high_12': {
    'math': ['Matemáticas V — Cálculo diferencial', 'Matemáticas VI — Cálculo integral'],
    'physics': ['Física — electromagnetismo, óptica, física moderna'],
    'chem': ['Química orgánica, bioquímica'],
    'bio': ['Biología — biotecnología, fisiología humana'],
    'history': ['Historia mundial siglo XX'],
    'philosophy': ['Filosofía'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇦🇷 ARGENTINA — Educación Secundaria
  // ═════════════════════════════════════════════════════════════════════════
  'ar_high_11': {
    'math': ['Matemática — funciones, trigonometría, estadística'],
    'physics': ['Física — mecánica, electricidad, ondas'],
    'chem': ['Química — reacciones, estequiometría, química orgánica'],
    'bio': ['Biología — genética, evolución, ecología'],
    'lit': ['Literatura — literatura argentina (Borges, Cortázar, Sábato)'],
    'history': ['Historia argentina y contemporánea'],
    'geo': ['Geografía argentina y mundial'],
    'english': ['Inglés'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇵🇪 PERU / 🇨🇴 COLOMBIA / 🇻🇪 VENEZUELA — Latin America general
  // ═════════════════════════════════════════════════════════════════════════
  'pe_high_11': {
    'math': ['Matemática — álgebra, geometría, estadística, trigonometría'],
    'physics': ['Física — cinemática, dinámica, energía, electromagnetismo'],
    'chem': ['Química — reacciones, soluciones, química orgánica'],
    'bio': ['Biología — genética, ecología, anatomía'],
    'lit': ['Literatura peruana e hispanoamericana'],
    'history': ['Historia del Perú y universal'],
    'geo': ['Geografía del Perú'],
    'english': ['Inglés'],
  },
  'co_high_11': {
    'math': ['Matemáticas — funciones, trigonometría, cálculo intro'],
    'physics': ['Física — mecánica, ondas, electricidad'],
    'chem': ['Química — enlaces, reacciones, química orgánica'],
    'bio': ['Biología — genética, ecología'],
    'lit': ['Literatura colombiana y latinoamericana'],
    'history': ['Historia de Colombia'],
    'english': ['Inglés'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇮🇩 INDONESIA — Kurikulum Merdeka
  // ═════════════════════════════════════════════════════════════════════════
  'id_high_11_ipa': {
    'math': ['Matematika Wajib — logaritma, fungsi, trigonometri, vektor'],
    'physics': ['Fisika — fluida, suhu, kalor, gelombang, optik, listrik'],
    'chem': ['Kimia — termokimia, laju reaksi, kesetimbangan, asam-basa, kimia organik'],
    'bio': ['Biologi — jaringan, sistem organ, genetika, evolusi'],
    'lit': ['Bahasa Indonesia — sastra, teks argumentasi, pidato'],
    'history': ['Sejarah Indonesia, Sejarah Dunia'],
    'english': ['Bahasa Inggris'],
    'religion': ['Pendidikan Agama'],
  },
  'id_high_12_ipa': {
    'math': ['Matematika — integral, trigonometri lanjut, statistika'],
    'physics': ['Fisika — listrik dinamis, gelombang elektromagnetik, relativitas, fisika atom dan inti'],
    'chem': ['Kimia — senyawa karbon, biomolekul, polimer'],
    'bio': ['Biologi — metabolisme, bioteknologi, mutasi'],
    'lit': ['Bahasa Indonesia — kritik dan esai'],
    'history': ['Sejarah Indonesia abad 20, sejarah dunia kontemporer'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇻🇳 VIETNAM — THPT
  // ═════════════════════════════════════════════════════════════════════════
  'vn_high_11': {
    'math': ['Toán 11 — hàm số, lượng giác, đạo hàm, tích phân intro, hình học không gian, vector'],
    'physics': ['Vật lý 11 — điện học, dòng điện, từ trường, cảm ứng điện từ, quang học'],
    'chem': ['Hóa học 11 — nguyên tố, liên kết, phản ứng, hóa hữu cơ cơ bản'],
    'bio': ['Sinh học 11 — chuyển hóa vật chất, cảm ứng, sinh trưởng, sinh sản'],
    'lit': ['Ngữ văn 11 — văn học trung đại, văn học hiện đại'],
    'history': ['Lịch sử Việt Nam', 'Lịch sử thế giới'],
    'geo': ['Địa lý Việt Nam'],
    'english': ['Tiếng Anh 11'],
  },
  'vn_high_12': {
    'math': ['Toán 12 — đạo hàm, tích phân, số phức, hình học tọa độ không gian'],
    'physics': ['Vật lý 12 — dao động, sóng, điện xoay chiều, lượng tử, hạt nhân'],
    'chem': ['Hóa học 12 — hóa hữu cơ nâng cao, kim loại, phi kim, hóa polymer'],
    'bio': ['Sinh học 12 — di truyền, tiến hóa, sinh thái'],
    'lit': ['Ngữ văn 12 — văn học hiện đại VN, thơ-văn lãng mạn, cách mạng'],
  },
  'vn_exam_prep_thpt': {
    'math': ['THPT Quốc gia Toán'],
    'lit': ['THPT QG Ngữ văn'],
    'english': ['THPT QG Tiếng Anh'],
    'physics': ['THPT QG Vật lý'],
    'chem': ['THPT QG Hóa học'],
    'bio': ['THPT QG Sinh học'],
    'history': ['THPT QG Lịch sử'],
    'geo': ['THPT QG Địa lý'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇹🇭 THAILAND — Matthayom
  // ═════════════════════════════════════════════════════════════════════════
  'th_high_11': {
    'math': ['คณิตศาสตร์ ม.5 — ลำดับและอนุกรม, ความน่าจะเป็น, ตรีโกณมิติ, เมทริกซ์'],
    'physics': ['ฟิสิกส์ ม.5 — ไฟฟ้า, แม่เหล็ก, ดวงดาว, ฟิสิกส์แผนใหม่'],
    'chem': ['เคมี ม.5 — ปริมาณสารสัมพันธ์, สารละลาย, กรด-เบส, เคมีอินทรีย์'],
    'bio': ['ชีววิทยา ม.5 — ระบบในร่างกาย, พันธุศาสตร์, วิวัฒนาการ'],
    'lit': ['ภาษาไทย — วรรณคดี, การเขียน'],
    'history': ['ประวัติศาสตร์ไทย, ประวัติศาสตร์สากล'],
    'english': ['ภาษาอังกฤษ'],
  },
  'th_exam_prep_tcas': {
    'math': ['TCAS/A-Level คณิตศาสตร์'],
    'physics': ['TCAS ฟิสิกส์'],
    'chem': ['TCAS เคมี'],
    'bio': ['TCAS ชีววิทยา'],
    'lit': ['TCAS ภาษาไทย'],
    'english': ['TCAS ภาษาอังกฤษ'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇵🇭 PHILIPPINES — K-12 Senior High (STEM)
  // ═════════════════════════════════════════════════════════════════════════
  'ph_high_11_stem': {
    'math': ['General Mathematics — functions, logic, business math', 'Pre-Calculus — analytic geometry, matrices, series'],
    'physics': ['General Physics 1 — kinematics, forces, energy, momentum, waves'],
    'chem': ['General Chemistry 1 — matter, atomic structure, bonding, stoichiometry'],
    'bio': ['General Biology 1 — cell biology, biomolecules, genetics intro'],
    'lit': ['21st Century Literature from the Philippines and the World'],
    'english': ['Reading & Writing, Oral Communication'],
    'history': ['Understanding Culture, Society, and Politics'],
  },
  'ph_high_12_stem': {
    'math': ['Basic Calculus — limits, derivatives, integrals'],
    'physics': ['General Physics 2 — electricity, magnetism, optics, modern physics'],
    'chem': ['General Chemistry 2 — chemistry of life, equilibrium, electrochemistry, organic'],
    'bio': ['General Biology 2 — plant & animal physiology, ecology, evolution'],
    'lit': ['Creative Writing, Literary Criticism'],
    'history': ['Philippine Politics and Governance'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇲🇾 MALAYSIA — SPM / STPM
  // ═════════════════════════════════════════════════════════════════════════
  'my_high_11': {
    'math': ['Matematik Tambahan — fungsi, persamaan kuadratik, indeks dan logaritma, statistik, geometri koordinat, vektor, trigonometri, kalkulus diferensiasi'],
    'physics': ['Fizik — daya dan gerakan, tenaga, haba, gelombang, elektrik, elektromagnet'],
    'chem': ['Kimia — struktur atom, ikatan, mol, elektrokimia, asid-bes, kimia organik'],
    'bio': ['Biologi — sel, pemakanan, pernafasan, darah, gerakan bahan, pembiakan, evolusi'],
    'lit': ['Bahasa Melayu — kesusasteraan'],
    'english': ['Bahasa Inggeris'],
    'religion': ['Pendidikan Islam / Moral'],
    'history': ['Sejarah — Malaysia, dunia'],
  },
  'my_exam_prep_spm': {
    'math': ['SPM Matematik Tambahan'],
    'physics': ['SPM Fizik'],
    'chem': ['SPM Kimia'],
    'bio': ['SPM Biologi'],
    'lit': ['SPM Bahasa Melayu'],
    'english': ['SPM Bahasa Inggeris'],
    'history': ['SPM Sejarah'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇵🇰 PAKISTAN — Matric / FSc
  // ═════════════════════════════════════════════════════════════════════════
  'pk_high_12_pre_eng': {
    'math': ['Mathematics (FSc Pre-Engineering) — functions, differentiation, integration, vectors, analytic geometry'],
    'physics': ['Physics (FSc) — motion, work-energy, oscillations, waves, thermodynamics, electrostatics, current electricity, electromagnetism, electronics, modern physics'],
    'chem': ['Chemistry (FSc) — atomic structure, chemical bonding, states of matter, chemical equilibria, thermochemistry, electrochemistry, organic chemistry (alkanes, alkenes, aromatic), biochemistry'],
    'english': ['English compulsory — essays, letters, comprehension'],
    'lit': ['Urdu compulsory — poetry, prose'],
    'religion': ['Islamiat'],
    'history': ['Pakistan Studies'],
  },
  'pk_high_12_pre_med': {
    'math': ['Mathematics (optional — if pre-med with math)'],
    'physics': ['Physics (FSc Pre-Medical)'],
    'chem': ['Chemistry (FSc Pre-Medical)'],
    'bio': ['Biology (FSc) — cell biology, biological molecules, enzymes, bioenergetics, biodiversity, prokaryotes, eukaryotes, kingdom fungi/plantae/animalia, physiology, ecology, evolution, genetics'],
    'english': ['English compulsory'],
    'lit': ['Urdu compulsory'],
    'religion': ['Islamiat'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇧🇩 BANGLADESH — SSC/HSC
  // ═════════════════════════════════════════════════════════════════════════
  'bd_high_12': {
    'math': ['Higher Mathematics (HSC) — matrix, vector, complex numbers, trigonometry, differentiation, integration, probability'],
    'physics': ['Physics (HSC) — mechanics, heat, wave, optics, electricity, magnetism, modern physics'],
    'chem': ['Chemistry (HSC) — atomic structure, periodic properties, bonding, gaseous state, chemical kinetics, equilibrium, organic chemistry'],
    'bio': ['Biology (HSC) — botany (plant anatomy, physiology), zoology (animal physiology, genetics, evolution)'],
    'lit': ['বাংলা সাহিত্য (Bengali Literature) — Tagore, Nazrul, modern poetry/prose'],
    'english': ['English Paper 1 & 2 — grammar, composition, literature'],
    'religion': ['Religion (Islam / Hindu / Christian based on student)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇮🇷 IRAN — دبیرستان / کنکور
  // ═════════════════════════════════════════════════════════════════════════
  'ir_high_11_riyazi': {
    'math': ['ریاضیات — هندسه تحلیلی، حساب دیفرانسیل، مثلثات، توابع نمایی و لگاریتمی'],
    'physics': ['فیزیک — الکتریسیته، مغناطیس، موج و نور، فیزیک جدید (نسبیت، کوانتومی)'],
    'chem': ['شیمی — ساختار اتم، پیوندها، ترمودینامیک، سینتیک، تعادل، شیمی آلی'],
    'lit': ['ادبیات فارسی — حافظ، سعدی، مولوی، ادبیات معاصر'],
    'english': ['زبان انگلیسی'],
    'religion': ['دینی — اعتقادات، اخلاق، تاریخ اسلام'],
  },
  'ir_exam_prep_konkoor': {
    'math': ['کنکور ریاضی'],
    'physics': ['کنکور فیزیک'],
    'chem': ['کنکور شیمی'],
    'bio': ['کنکور زیست‌شناسی (علوم تجربی)'],
    'lit': ['کنکور ادبیات فارسی'],
    'english': ['کنکور زبان انگلیسی'],
    'religion': ['کنکور دینی'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇪🇬 EGYPT / 🇸🇦 SAUDI / 🇶🇦 QATAR / 🇦🇪 UAE — Arabic system
  // ═════════════════════════════════════════════════════════════════════════
  'eg_high_12_ilmi': {
    'math': ['الرياضيات — التفاضل والتكامل، الهندسة الفراغية، الإحصاء'],
    'physics': ['الفيزياء — الكهرباء، المغناطيسية، الفيزياء الحديثة'],
    'chem': ['الكيمياء — الكيمياء العضوية، الكيمياء غير العضوية، الاتزان الكيميائي'],
    'bio': ['الأحياء — الوراثة، التطور، فسيولوجيا الإنسان'],
    'lit': ['اللغة العربية — النحو، الأدب العربي الحديث، النصوص الأدبية'],
    'history': ['التاريخ — تاريخ مصر الحديث والمعاصر'],
    'geo': ['الجغرافيا — جغرافيا مصر والعالم العربي'],
    'english': ['اللغة الإنجليزية'],
    'religion': ['التربية الدينية'],
  },
  'sa_high_12': {
    'math': ['الرياضيات — التكامل، المعادلات التفاضلية، الإحصاء المتقدم'],
    'physics': ['الفيزياء — الكهرومغناطيسية، الفيزياء النووية، الكوانتم'],
    'chem': ['الكيمياء — الكيمياء العضوية، الاتزان، الكيمياء الكهربائية'],
    'bio': ['الأحياء — البيولوجيا الجزيئية، الوراثة، علم البيئة'],
    'lit': ['اللغة العربية — النحو، البلاغة، الأدب'],
    'history': ['تاريخ المملكة العربية السعودية'],
    'geo': ['الجغرافيا'],
    'english': ['اللغة الإنجليزية'],
    'religion': ['الدراسات الإسلامية (توحيد، فقه، تفسير، حديث)'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇳🇬 NIGERIA — WAEC/WASSCE
  // ═════════════════════════════════════════════════════════════════════════
  'ng_high_12': {
    'math': ['Mathematics — algebra, calculus, trigonometry, statistics, geometry'],
    'physics': ['Physics — mechanics, waves, electricity, magnetism, modern physics'],
    'chem': ['Chemistry — atomic structure, bonding, acids/bases, redox, organic'],
    'bio': ['Biology — cell biology, physiology, genetics, ecology, evolution'],
    'lit': ['Literature in English — African, British, American'],
    'english': ['English Language — essays, comprehension, grammar'],
    'history': ['History — Nigerian, African, world'],
    'geo': ['Geography — physical, human, economic'],
    'civics': ['Civic Education'],
    'religion': ['Christian/Islamic Religious Studies'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  🇿🇦 SOUTH AFRICA — CAPS / Matric (NSC)
  // ═════════════════════════════════════════════════════════════════════════
  'za_high_12': {
    'math': ['Mathematics — functions, algebra, calculus, trigonometry, analytical geometry, statistics, probability'],
    'physics': ['Physical Sciences — mechanics, matter, waves, sound, light, electricity, magnetism, chemical change'],
    'chem': ['Physical Sciences (chemistry portion)'],
    'bio': ['Life Sciences — cells, molecules, life processes, diversity, ecology'],
    'lit': ['English Home Language — literature, essays'],
    'history': ['History — 20th century southern Africa, apartheid, global events'],
    'geo': ['Geography — physical, human, environment'],
    'accountancy': ['Accounting'],
    'business_studies': ['Business Studies'],
    'economics': ['Economics'],
  },

  // ═════════════════════════════════════════════════════════════════════════
  //  ULUSLARARASI FALLBACK — IB / Cambridge tarzı
  // ═════════════════════════════════════════════════════════════════════════
  'international_primary': {
    'math': ['Numbers & operations', 'Fractions & decimals', 'Measurement', 'Basic geometry', 'Data handling'],
    'lang_native': ['Reading', 'Writing', 'Grammar basics', 'Vocabulary'],
    'english': ['English as Second Language — basic'],
    'pe': ['Physical Education'],
    'art_music': ['Art & Music'],
  },
  'international_middle': {
    'math': ['Pre-algebra', 'Ratios, proportions, percentages', 'Integers, rational numbers', 'Geometry (angles, triangles, quadrilaterals, circles)', 'Basic statistics & probability', 'Linear equations'],
    'lang_native': ['Reading comprehension', 'Narrative & descriptive writing', 'Grammar'],
    'english': ['English grammar, vocab, reading'],
    'history': ['World History survey'],
    'geo': ['Physical & human geography'],
    'physics': ['Introduction to Physics — forces, energy, waves'],
    'chem': ['Introduction to Chemistry — atoms, elements, reactions'],
    'bio': ['Introduction to Biology — cells, organisms, ecosystems'],
    'ict': ['ICT basics'],
  },
  'international_high': {
    'math': ['Algebra, functions, trigonometry, calculus intro, statistics, probability'],
    'physics': ['Mechanics, waves, electricity, thermodynamics, modern physics intro'],
    'chem': ['Stoichiometry, bonding, energetics, kinetics, equilibrium, acids/bases, organic chem intro'],
    'bio': ['Cells, genetics, evolution, ecology, human physiology'],
    'lit': ['World literature — prose, poetry, drama'],
    'history': ['Modern history (19th-20th century)'],
    'geo': ['Physical & human geography'],
    'english': ['English — advanced grammar, essay writing, reading'],
    'second_lang': ['Second language — intermediate'],
    'economics': ['Introduction to Economics'],
    'computer_science': ['Computer Science basics — algorithms, programming'],
  },
  'international_university': {
    'math': ['Calculus I & II', 'Linear algebra', 'Discrete mathematics'],
    'physics': ['University Physics'],
    'chem': ['General Chemistry'],
    'bio': ['General Biology'],
    'english': ['Academic English'],
    'computer_science': ['Programming, data structures, algorithms'],
    'statistics': ['Statistics'],
    'economics': ['Microeconomics, Macroeconomics'],
  },
  'international_masters': {
    'math': ['Advanced research methods in the chosen field'],
    'statistics': ['Advanced statistical methods'],
    'english': ['Academic writing & publication'],
  },
  'international_doctorate': {
    'math': ['Research methodology', 'Domain-specific advanced topics'],
    'english': ['Thesis writing & defense'],
  },
};

// ═══════════════════════════════════════════════════════════════════════════════
//  AI PROMPT YARDIMCISI — profilden müfredat bağlamını kısa metne dönüştür
// ═══════════════════════════════════════════════════════════════════════════════

/// Gemini/OpenAI system prompt'una inject edilen "öğrenci hangi dersleri
/// görüyor?" bağlamı. AI bu bilgiyle soruları öğrencinin seviyesine özgü çözer.
String curriculumContextForPrompt(EduProfile? profile) {
  final subs = curriculumFor(profile);
  if (subs.isEmpty) return '';
  final lines = <String>['[CURRICULUM CONTEXT]'];
  lines.add('Student profile: ${profile?.displayLabel() ?? 'unknown'}');
  lines.add('Currently studying these subjects and topics:');
  for (final s in subs.take(10)) {
    final topics = s.topics.take(6).join(', ');
    lines.add('• ${s.displayName}: $topics${s.topics.length > 6 ? '…' : ''}');
  }
  lines.add('Use these topics as context: pick the exact grade-appropriate terminology, assumptions, and depth when solving questions.');
  return lines.join('\n');
}

/// curriculum_catalog'u education_profile'a bir kez bağlar.
/// main.dart bunu başlangıçta çağırır.
void initCurriculumCatalog() {
  registerCurriculumContextBuilder(curriculumContextForPrompt);
}
