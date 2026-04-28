// ═══════════════════════════════════════════════════════════════════════════════
//  EducationRepository — EducationSystem'leri sorgu noktası
//
//  Şu an seed-only (kod içinde gömülü). İleride Firestore/JSON-load
//  eklemek istenirse bu sınıf değiştirilir; tüketici provider'lar değişmez.
// ═══════════════════════════════════════════════════════════════════════════════

import '../domain/country.dart';
import '../domain/education_system.dart';
import 'seed_education_systems.dart';

class EducationRepository {
  final List<EducationSystem> _systems;

  EducationRepository._(this._systems);

  factory EducationRepository.seeded() =>
      EducationRepository._(seedEducationSystems());

  /// Desteklenen tüm sistemler.
  List<EducationSystem> get all => List.unmodifiable(_systems);

  /// Desteklenen ülkelerin listesi.
  List<Country> get countries =>
      _systems.map((s) => s.country).toList(growable: false);

  /// Bir ülke kodu için sistemi getir (yoksa null).
  EducationSystem? findByCountry(String countryCode) {
    for (final s in _systems) {
      if (s.country.code == countryCode) return s;
    }
    return null;
  }
}
