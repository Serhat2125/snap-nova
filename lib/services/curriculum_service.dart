// ═══════════════════════════════════════════════════════════════════════════
//  CurriculumService — Locale + ülke + seviye + branş bazlı müfredat akışı.
//
//  Öğretmen branş + seviye seçince hangi kazanımların görünmesi gerektiğini
//  belirler. Statik baz + AI-genişletme: önce yerel sabit kazanımlar gelir,
//  hızlı veri; sonra (opsiyonel) Gemini ile fine-tune edilebilir.
//
//  Desteklenen müfredatlar (MVP):
//    - tr-MEB     : Türkiye MEB (Milli Eğitim Bakanlığı)
//    - us-CCSS    : Amerika Common Core State Standards
//    - gb-NC      : İngiltere National Curriculum
//    - de-LP      : Almanya Lehrplan
//    - generic    : Genel/uluslararası fallback
// ═══════════════════════════════════════════════════════════════════════════

import '../models/education_models.dart';

class CurriculumService {
  CurriculumService._();

  /// Desteklenen tüm standart şemalar.
  static const standards = <CurriculumStandard>[
    CurriculumStandard(key: 'tr-MEB',   label: 'MEB (Türkiye)',          countryCode: 'TR'),
    CurriculumStandard(key: 'us-CCSS',  label: 'Common Core (USA)',      countryCode: 'US'),
    CurriculumStandard(key: 'gb-NC',    label: 'National Curriculum (UK)', countryCode: 'GB'),
    CurriculumStandard(key: 'de-LP',    label: 'Lehrplan (Deutschland)', countryCode: 'DE'),
    CurriculumStandard(key: 'generic',  label: 'Uluslararası',           countryCode: 'XX'),
  ];

  /// Locale + ülke bazlı varsayılan müfredat anahtarı.
  static String defaultCurriculumKey(String localeCode, [String? countryCode]) {
    final lc = localeCode.toLowerCase();
    final cc = (countryCode ?? '').toUpperCase();
    if (cc == 'TR' || lc == 'tr') return 'tr-MEB';
    if (cc == 'US' || lc == 'en' && cc == 'US') return 'us-CCSS';
    if (cc == 'GB' || cc == 'UK') return 'gb-NC';
    if (cc == 'DE' || lc == 'de') return 'de-LP';
    return 'generic';
  }

  /// Seçilen müfredat + seviye + ders için kazanım listesi döner.
  /// MVP: statik bir baz (her müfredat 2-3 ders, her ders 4-6 konu, her konu
  /// 3-4 kazanım). Gerçek kapsamlı müfredat ileride server-side.
  static List<CurriculumTopic> topicsFor({
    required String curriculumKey,
    required String level,
    required String subject,
  }) {
    final baseFor = _matrix[curriculumKey] ?? _matrix['generic']!;
    return baseFor
        .where((t) => t.level == level && t.subject == subject)
        .toList();
  }

  /// Bir müfredat anahtarına ait tüm desteklenen ders adları (level filtreli).
  static List<String> subjectsFor({
    required String curriculumKey,
    required String level,
  }) {
    final base = _matrix[curriculumKey] ?? _matrix['generic']!;
    return base
        .where((t) => t.level == level)
        .map((t) => t.subject)
        .toSet()
        .toList();
  }

  static List<String> levelsFor(String curriculumKey) {
    final base = _matrix[curriculumKey] ?? _matrix['generic']!;
    return base.map((t) => t.level).toSet().toList();
  }

  // ─── STATIK MÜFREDAT MATRİSİ ──────────────────────────────────────────
  // Üretim için yeterli, genişletilebilir. Her standart için ayrı liste.
  // Kazanım (outcome) formatı standart kodla başlar (M.5.1.1.1, CCSS.MATH.5.NBT.A.1).
  static final Map<String, List<CurriculumTopic>> _matrix = {
    'tr-MEB': [
      CurriculumTopic(
        id: 'tr-meb-mat-il5-uslu', level: 'Ortaokul', grade: '5. sınıf',
        subject: 'Matematik', topic: 'Üslü Sayılar',
        outcomes: [
          'M.5.1.1.1. Bir doğal sayının pozitif tam sayı kuvvetini hesaplar.',
          'M.5.1.1.2. Üslü sayılarla ilgili problem çözer.',
          'M.5.1.1.3. 10\'un kuvvetlerini ve bilimsel gösterimi tanır.',
        ],
      ),
      CurriculumTopic(
        id: 'tr-meb-mat-il5-cikarma', level: 'Ortaokul', grade: '5. sınıf',
        subject: 'Matematik', topic: 'Doğal Sayılarda Çıkarma',
        outcomes: [
          'M.5.1.2.1. En çok dokuz basamaklı doğal sayılarla çıkarma yapar.',
          'M.5.1.2.2. Çıkarma işlemini içeren problem çözer.',
        ],
      ),
      CurriculumTopic(
        id: 'tr-meb-fiz-l9-kuvvet', level: 'Lise', grade: '9. sınıf',
        subject: 'Fizik', topic: 'Kuvvet ve Hareket',
        outcomes: [
          'F.9.1.1. Kuvveti birim ve özellikleriyle tanır.',
          'F.9.1.2. Newton\'ın hareket yasalarını uygular.',
          'F.9.1.3. Bileşke kuvvet hesabı yapar.',
        ],
      ),
      CurriculumTopic(
        id: 'tr-meb-kim-l10-asitbaz', level: 'Lise', grade: '10. sınıf',
        subject: 'Kimya', topic: 'Asitler ve Bazlar',
        outcomes: [
          'K.10.1.1. Asit-baz tanımlarını karşılaştırır.',
          'K.10.1.2. pH ölçeğini yorumlar.',
          'K.10.1.3. Asit-baz titrasyonunu açıklar.',
        ],
      ),
      CurriculumTopic(
        id: 'tr-meb-bio-l11-genetik', level: 'Lise', grade: '11. sınıf',
        subject: 'Biyoloji', topic: 'Kalıtım',
        outcomes: [
          'B.11.1.1. Mendel yasalarını açıklar.',
          'B.11.1.2. Genotip ve fenotip kavramlarını ayırt eder.',
          'B.11.1.3. Soyağacı analizi yapar.',
        ],
      ),
      CurriculumTopic(
        id: 'tr-meb-tar-l11-cumhuriyet', level: 'Lise', grade: '11. sınıf',
        subject: 'Tarih', topic: 'Cumhuriyet Dönemi İnkılapları',
        outcomes: [
          'T.11.1.1. Saltanatın kaldırılmasını ve gerekçelerini açıklar.',
          'T.11.1.2. Halifeliğin kaldırılması sürecini değerlendirir.',
          'T.11.1.3. Hukuk inkılaplarını sıralar.',
        ],
      ),
    ],
    'us-CCSS': [
      CurriculumTopic(
        id: 'us-ccss-math-5-frac', level: 'Ortaokul', grade: 'Grade 5',
        subject: 'Matematik', topic: 'Fractions',
        outcomes: [
          'CCSS.MATH.5.NF.A.1 Add and subtract fractions with unlike denominators.',
          'CCSS.MATH.5.NF.B.4 Multiply fractions or whole number by a fraction.',
          'CCSS.MATH.5.NF.B.7 Divide unit fractions.',
        ],
      ),
      CurriculumTopic(
        id: 'us-ccss-sci-hs-newton', level: 'Lise', grade: 'Grade 9',
        subject: 'Fizik', topic: 'Newton\'s Laws of Motion',
        outcomes: [
          'HS-PS2-1 Analyze data to support Newton\'s second law of motion.',
          'HS-PS2-2 Use math to support net force claims.',
        ],
      ),
    ],
    'gb-NC': [
      CurriculumTopic(
        id: 'gb-nc-math-ks3-alg', level: 'Ortaokul', grade: 'KS3 Year 7',
        subject: 'Matematik', topic: 'Algebra',
        outcomes: [
          'Use and interpret algebraic notation.',
          'Substitute numerical values into formulae.',
          'Simplify and manipulate algebraic expressions.',
        ],
      ),
    ],
    'de-LP': [
      CurriculumTopic(
        id: 'de-lp-math-7-gleich', level: 'Ortaokul', grade: 'Klasse 7',
        subject: 'Matematik', topic: 'Lineare Gleichungen',
        outcomes: [
          'Lineare Gleichungen aufstellen.',
          'Gleichungen mit einer Variablen lösen.',
        ],
      ),
    ],
    'generic': [
      CurriculumTopic(
        id: 'gen-math-il-arith', level: 'İlkokul', grade: '3',
        subject: 'Matematik', topic: 'Toplama-Çıkarma',
        outcomes: [
          'İki basamaklı sayıları toplar ve çıkarır.',
          'Toplama-çıkarma içeren problemi çözer.',
        ],
      ),
      CurriculumTopic(
        id: 'gen-math-ort-frac', level: 'Ortaokul', grade: '6',
        subject: 'Matematik', topic: 'Kesirler',
        outcomes: [
          'Kesirleri karşılaştırır.',
          'Kesirlerle dört işlem yapar.',
        ],
      ),
      CurriculumTopic(
        id: 'gen-fiz-l-kuv', level: 'Lise', grade: '10',
        subject: 'Fizik', topic: 'Kuvvet',
        outcomes: [
          'Kuvvet birim ve büyüklüğünü tanımlar.',
          'Bileşke kuvvet bulur.',
        ],
      ),
      CurriculumTopic(
        id: 'gen-kim-l-mol', level: 'Lise', grade: '11',
        subject: 'Kimya', topic: 'Mol Kavramı',
        outcomes: [
          'Mol birimini açıklar.',
          'Avogadro sayısını kullanır.',
        ],
      ),
    ],
  };
}
