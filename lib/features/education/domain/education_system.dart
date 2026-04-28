// ═══════════════════════════════════════════════════════════════════════════════
//  EducationSystem — Country + tüm Level'ları (ve onların Grade'leri) tutar
//
//  Bir ülkenin "tam yapısı":
//    Country → EducationSystem → List<EducationLevel> → List<Grade>
//
//  Subject'ler runtime AI ile her Grade için üretilir (statik tutmuyoruz;
//  müfredat değişir + ülke sayısı çok).
// ═══════════════════════════════════════════════════════════════════════════════

import 'country.dart';
import 'education_level.dart';

class EducationSystem {
  final Country country;
  final List<EducationLevel> levels;

  const EducationSystem({
    required this.country,
    required this.levels,
  });

  EducationLevel? findLevelByKey(String key) {
    for (final l in levels) {
      if (l.key == key) return l;
    }
    return null;
  }
}
