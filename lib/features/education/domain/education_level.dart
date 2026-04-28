// ═══════════════════════════════════════════════════════════════════════════════
//  EducationLevel — bir eğitim kademesi (İlkokul, Ortaokul, Lise vb.)
//
//  Her ülkenin farklı kademe yapısı vardır (Almanya'da Grundschule/
//  Sekundarstufe I/II, Türkiye'de İlkokul/Ortaokul/Lise vb.). Bu yüzden
//  EducationSystem.levels listesi country-specific.
// ═══════════════════════════════════════════════════════════════════════════════

import 'grade.dart';

/// Standardize edilmiş kademe anahtarları (cross-country comparison için).
/// Ülke-specific level adı (ör. "Gymnasium") ayrıca `displayName` ile tutulur.
enum LevelCategory {
  primary,
  middle,
  high,
  examPrep,
  vocational,
  bachelor,
  masters,
  doctorate,
  postGradExam,
  other,
}

class EducationLevel {
  /// Ülke içinde unique kısa anahtar ('primary', 'gymnasium', 'lycee', vb.).
  final String key;

  /// Endonim ad — UI'de kullanıcının göreceği isim.
  /// Ör. "Lise", "Gymnasium", "High School", "Lycée".
  final String displayName;

  /// Standardize kategori (cross-country yarış eşleşmesi için).
  final LevelCategory category;

  /// Bu kademede yer alan sınıflar.
  final List<Grade> grades;

  const EducationLevel({
    required this.key,
    required this.displayName,
    required this.category,
    required this.grades,
  });
}
