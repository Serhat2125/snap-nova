// ═══════════════════════════════════════════════════════════════════════════════
//  Matchmaking — yarışma eşleştirme anahtarları + Firestore filter helper
//
//  • countryMatchKey: aynı ülke + sınıf + bölüm
//  • worldMatchKey: dünya çapı eşdeğer (TR 10 ↔ DE 10 ↔ US Grade 10)
//
//  Bu sağlayıcılar Firestore query'lerinde where(...) parametresi olarak
//  doğrudan kullanılabilir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/user_preference.dart';
import 'curriculum_controller.dart';

/// Ülke içi eşleştirme anahtarı.
final countryMatchKeyProvider = Provider<String?>((ref) {
  return ref.watch(activePreferenceProvider)?.countryMatchKey;
});

/// Dünya çapı eşleştirme anahtarı (eşdeğer sınıf).
/// Sınava hazırlık modunda → null (sınavlar ülke spesifik, world match yok).
final worldMatchKeyProvider = Provider<String?>((ref) {
  final p = ref.watch(activePreferenceProvider);
  if (p == null) return null;
  if (p.levelKey == 'exam_prep' || p.levelKey == 'lgs_prep') return null;
  return p.worldMatchKey;
});

/// İki kullanıcı aynı dünya kategorisinde mi?
/// Firestore document'ten gelen verilerle karşılaştırma.
bool isWorldEquivalent(UserPreference a, UserPreference b) =>
    a.worldMatchKey == b.worldMatchKey &&
    a.levelKey != 'exam_prep' &&
    a.levelKey != 'lgs_prep';

/// Aynı ülke içinde tam eşitlik (matchmaking kesin).
bool isCountryEquivalent(UserPreference a, UserPreference b) =>
    a.countryMatchKey == b.countryMatchKey;
