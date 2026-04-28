// ═══════════════════════════════════════════════════════════════════════════════
//  Seed — TR/DE/US/UK/FR için EducationSystem yapıları
//
//  Bu seed kod tabanlıdır (JSON değil) — derlemede inline gelir, internet
//  gerekmez. Yeni ülke eklemek için bu dosyaya bir entry eklemek + ülkeyi
//  `kAllCountries`'e (services/education_profile.dart) eklemek yeterli.
// ═══════════════════════════════════════════════════════════════════════════════

import '../domain/country.dart';
import '../domain/education_level.dart';
import '../domain/education_system.dart';
import '../domain/grade.dart';

/// 1. Sınıf … N. Sınıf üretir (level içi sınıflar için kestirme).
List<Grade> _gradeRange(int from, int to, {String suffix = '. Sınıf'}) {
  return [
    for (int i = from; i <= to; i++)
      Grade(key: '$i', displayName: '$i$suffix'),
  ];
}

const _trCountry = Country(code: 'tr', name: 'Türkiye', flag: '🇹🇷');
const _deCountry = Country(code: 'de', name: 'Deutschland', flag: '🇩🇪');
const _usCountry = Country(code: 'us', name: 'United States', flag: '🇺🇸');
const _ukCountry = Country(code: 'uk', name: 'United Kingdom', flag: '🇬🇧');
const _frCountry = Country(code: 'fr', name: 'France', flag: '🇫🇷');

EducationSystem _trSystem() => EducationSystem(
      country: _trCountry,
      levels: [
        EducationLevel(
          key: 'primary',
          displayName: 'İlkokul',
          category: LevelCategory.primary,
          grades: _gradeRange(1, 4),
        ),
        EducationLevel(
          key: 'middle',
          displayName: 'Ortaokul',
          category: LevelCategory.middle,
          grades: _gradeRange(5, 8),
        ),
        EducationLevel(
          key: 'high',
          displayName: 'Lise',
          category: LevelCategory.high,
          grades: _gradeRange(9, 12),
        ),
        EducationLevel(
          key: 'exam_prep',
          displayName: 'Sınavlara Hazırlık',
          category: LevelCategory.examPrep,
          grades: const [
            Grade(key: 'YKS', displayName: 'YKS'),
            Grade(key: 'MSU', displayName: 'MSÜ'),
            Grade(key: 'KPSS_ORTA', displayName: 'KPSS Ortaöğretim'),
            Grade(key: 'DGS', displayName: 'DGS'),
            Grade(key: 'YDS', displayName: 'YDS / YÖKDİL'),
            Grade(key: 'PMYO', displayName: 'PMYO'),
          ],
        ),
        const EducationLevel(
          key: 'university',
          displayName: 'Üniversite',
          category: LevelCategory.bachelor,
          // Sınıflar bölüme göre değişir; UI runtime'da Grade üretir.
          grades: [],
        ),
        const EducationLevel(
          key: 'post_uni_exam',
          displayName: 'Üniversite Sonrası Sınavlar',
          category: LevelCategory.postGradExam,
          grades: [
            Grade(key: 'ALES', displayName: 'ALES'),
            Grade(key: 'KPSS_LISANS', displayName: 'KPSS Lisans'),
            Grade(key: 'YDS_POST', displayName: 'YDS / YÖKDİL'),
            Grade(key: 'KPSS_OABT', displayName: 'KPSS ÖABT'),
            Grade(key: 'TUS', displayName: 'TUS / DUS / EUS'),
            Grade(key: 'HAKIMLIK', displayName: 'Hâkimlik / Savcılık'),
            Grade(key: 'KAYMAKAM', displayName: 'Kaymakamlık'),
            Grade(key: 'SAYISTAY', displayName: 'Sayıştay Denetçi'),
            Grade(key: 'SMMM', displayName: 'SMMM'),
            Grade(key: 'ISG', displayName: 'İSG'),
          ],
        ),
        const EducationLevel(
          key: 'masters',
          displayName: 'Yüksek Lisans',
          category: LevelCategory.masters,
          grades: [],
        ),
        const EducationLevel(
          key: 'doctorate',
          displayName: 'Doktora',
          category: LevelCategory.doctorate,
          grades: [],
        ),
      ],
    );

EducationSystem _deSystem() => EducationSystem(
      country: _deCountry,
      levels: [
        EducationLevel(
          key: 'grundschule',
          displayName: 'Grundschule',
          category: LevelCategory.primary,
          grades: _gradeRange(1, 4, suffix: '. Klasse'),
        ),
        EducationLevel(
          key: 'sek_1',
          displayName: 'Sekundarstufe I',
          category: LevelCategory.middle,
          grades: _gradeRange(5, 10, suffix: '. Klasse'),
        ),
        EducationLevel(
          key: 'sek_2',
          displayName: 'Sekundarstufe II / Gymnasium',
          category: LevelCategory.high,
          grades: _gradeRange(11, 13, suffix: '. Klasse'),
        ),
        const EducationLevel(
          key: 'berufsschule',
          displayName: 'Berufsschule',
          category: LevelCategory.vocational,
          grades: [],
        ),
        const EducationLevel(
          key: 'exam_prep',
          displayName: 'Aufnahmeprüfungen',
          category: LevelCategory.examPrep,
          grades: [
            Grade(key: 'Abitur', displayName: 'Abitur'),
            Grade(key: 'TMS', displayName: 'TMS (Medizin)'),
            Grade(key: 'TestAS', displayName: 'TestAS'),
          ],
        ),
        const EducationLevel(
          key: 'universitaet',
          displayName: 'Universität / Hochschule',
          category: LevelCategory.bachelor,
          grades: [],
        ),
        const EducationLevel(
          key: 'master',
          displayName: 'Master',
          category: LevelCategory.masters,
          grades: [],
        ),
        const EducationLevel(
          key: 'promotion',
          displayName: 'Promotion',
          category: LevelCategory.doctorate,
          grades: [],
        ),
      ],
    );

EducationSystem _usSystem() => EducationSystem(
      country: _usCountry,
      levels: [
        EducationLevel(
          key: 'elementary',
          displayName: 'Elementary School',
          category: LevelCategory.primary,
          grades: [
            const Grade(key: 'K', displayName: 'Kindergarten'),
            ..._gradeRange(1, 5, suffix: 'th Grade'),
          ],
        ),
        EducationLevel(
          key: 'middle',
          displayName: 'Middle School',
          category: LevelCategory.middle,
          grades: _gradeRange(6, 8, suffix: 'th Grade'),
        ),
        EducationLevel(
          key: 'high',
          displayName: 'High School',
          category: LevelCategory.high,
          grades: _gradeRange(9, 12, suffix: 'th Grade'),
        ),
        const EducationLevel(
          key: 'tests',
          displayName: 'Standardized Tests',
          category: LevelCategory.examPrep,
          grades: [
            Grade(key: 'SAT', displayName: 'SAT'),
            Grade(key: 'ACT', displayName: 'ACT'),
            Grade(key: 'AP', displayName: 'AP Exams'),
            Grade(key: 'PSAT', displayName: 'PSAT'),
          ],
        ),
        const EducationLevel(
          key: 'college',
          displayName: 'College / University',
          category: LevelCategory.bachelor,
          grades: [],
        ),
        const EducationLevel(
          key: 'graduate',
          displayName: 'Graduate (Master / PhD)',
          category: LevelCategory.masters,
          grades: [],
        ),
      ],
    );

EducationSystem _ukSystem() => EducationSystem(
      country: _ukCountry,
      levels: [
        EducationLevel(
          key: 'primary',
          displayName: 'Primary School',
          category: LevelCategory.primary,
          grades: _gradeRange(1, 6, suffix: ' (Year)'),
        ),
        EducationLevel(
          key: 'secondary',
          displayName: 'Secondary School',
          category: LevelCategory.middle,
          grades: _gradeRange(7, 11, suffix: ' (Year)'),
        ),
        const EducationLevel(
          key: 'sixth_form',
          displayName: 'Sixth Form / A-Levels',
          category: LevelCategory.high,
          grades: [
            Grade(key: 'AS', displayName: 'AS Level'),
            Grade(key: 'A2', displayName: 'A2 Level'),
          ],
        ),
        const EducationLevel(
          key: 'tests',
          displayName: 'Entry Tests',
          category: LevelCategory.examPrep,
          grades: [
            Grade(key: 'GCSE', displayName: 'GCSE'),
            Grade(key: 'BMAT', displayName: 'BMAT'),
            Grade(key: 'UCAT', displayName: 'UCAT'),
          ],
        ),
        const EducationLevel(
          key: 'university',
          displayName: 'University',
          category: LevelCategory.bachelor,
          grades: [],
        ),
        const EducationLevel(
          key: 'postgraduate',
          displayName: 'Postgraduate',
          category: LevelCategory.masters,
          grades: [],
        ),
      ],
    );

EducationSystem _frSystem() => EducationSystem(
      country: _frCountry,
      levels: [
        EducationLevel(
          key: 'primaire',
          displayName: 'École primaire',
          category: LevelCategory.primary,
          grades: const [
            Grade(key: 'CP', displayName: 'CP'),
            Grade(key: 'CE1', displayName: 'CE1'),
            Grade(key: 'CE2', displayName: 'CE2'),
            Grade(key: 'CM1', displayName: 'CM1'),
            Grade(key: 'CM2', displayName: 'CM2'),
          ],
        ),
        EducationLevel(
          key: 'college',
          displayName: 'Collège',
          category: LevelCategory.middle,
          grades: const [
            Grade(key: '6e', displayName: '6ème'),
            Grade(key: '5e', displayName: '5ème'),
            Grade(key: '4e', displayName: '4ème'),
            Grade(key: '3e', displayName: '3ème'),
          ],
        ),
        EducationLevel(
          key: 'lycee',
          displayName: 'Lycée',
          category: LevelCategory.high,
          grades: const [
            Grade(key: '2nde', displayName: 'Seconde'),
            Grade(key: '1re', displayName: 'Première'),
            Grade(key: 'tle', displayName: 'Terminale'),
          ],
        ),
        const EducationLevel(
          key: 'tests',
          displayName: 'Examens',
          category: LevelCategory.examPrep,
          grades: [
            Grade(key: 'BAC', displayName: 'Baccalauréat'),
            Grade(key: 'PARCOURSUP', displayName: 'Parcoursup'),
          ],
        ),
        const EducationLevel(
          key: 'universite',
          displayName: 'Université / Grandes Écoles',
          category: LevelCategory.bachelor,
          grades: [],
        ),
        const EducationLevel(
          key: 'master',
          displayName: 'Master',
          category: LevelCategory.masters,
          grades: [],
        ),
        const EducationLevel(
          key: 'doctorat',
          displayName: 'Doctorat',
          category: LevelCategory.doctorate,
          grades: [],
        ),
      ],
    );

/// Tüm seed sistemleri tek liste olarak döndürür.
List<EducationSystem> seedEducationSystems() => [
      _trSystem(),
      _deSystem(),
      _usSystem(),
      _ukSystem(),
      _frSystem(),
    ];
