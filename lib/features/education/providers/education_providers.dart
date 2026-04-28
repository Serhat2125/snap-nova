// ═══════════════════════════════════════════════════════════════════════════════
//  Education Providers — yeni feature katmanları için Riverpod erişim noktaları
//
//  • educationRepositoryProvider — seed sistemleri okuyan repository
//  • selectedCountryProvider     — ana profilin ülkesi (`primaryProfileProvider`'dan türev)
//  • selectedSystemProvider      — ülkeye karşılık gelen EducationSystem (varsa)
//  • selectedLevelProvider       — ana profilin seviyesi (varsa)
//
//  Eski ekranlar bu provider'ları okumaya zorunlu değil; sadece YENİ feature
//  katmanları kullanır. EduProfile.current ile yan yana yaşar.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/education_repository.dart';
import '../domain/country.dart';
import '../domain/education_level.dart';
import '../domain/education_system.dart';
import 'user_profiles_provider.dart';

/// Tek instance — uygulama yaşam döngüsü boyunca seed'i sağlar.
final educationRepositoryProvider = Provider<EducationRepository>((ref) {
  return EducationRepository.seeded();
});

/// Tüm desteklenen ülkelerin listesi (UI ülke seçici için kestirme).
final supportedCountriesProvider = Provider<List<Country>>((ref) {
  return ref.watch(educationRepositoryProvider).countries;
});

/// Aktif (primary) profilin ülkesi — yoksa null.
final selectedCountryProvider = Provider<Country?>((ref) {
  final p = ref.watch(primaryProfileProvider);
  if (p == null) return null;
  final repo = ref.watch(educationRepositoryProvider);
  final sys = repo.findByCountry(p.country);
  return sys?.country;
});

/// Aktif profile karşılık gelen EducationSystem (ülke detaylı seed'de yoksa null).
final selectedSystemProvider = Provider<EducationSystem?>((ref) {
  final p = ref.watch(primaryProfileProvider);
  if (p == null) return null;
  return ref.watch(educationRepositoryProvider).findByCountry(p.country);
});

/// Aktif profilin EducationLevel'i (ülke + level eşleşirse).
final selectedLevelProvider = Provider<EducationLevel?>((ref) {
  final sys = ref.watch(selectedSystemProvider);
  final p = ref.watch(primaryProfileProvider);
  if (sys == null || p == null) return null;
  // Direkt key eşleşmesi denenir (ör. 'primary'/'high'/'university').
  final byKey = sys.findLevelByKey(p.level);
  if (byKey != null) return byKey;
  // Fallback: kategori bazlı eşleştirme — eski schema ile yeni level keys
  // arasında köprü kurar.
  final cat = _legacyLevelToCategory(p.level);
  if (cat == null) return null;
  for (final l in sys.levels) {
    if (l.category == cat) return l;
  }
  return null;
});

LevelCategory? _legacyLevelToCategory(String legacyLevel) {
  switch (legacyLevel) {
    case 'primary':
      return LevelCategory.primary;
    case 'middle':
      return LevelCategory.middle;
    case 'high':
      return LevelCategory.high;
    case 'exam_prep':
      return LevelCategory.examPrep;
    case 'university':
      return LevelCategory.bachelor;
    case 'masters':
      return LevelCategory.masters;
    case 'doctorate':
      return LevelCategory.doctorate;
    default:
      return null;
  }
}
