// ═══════════════════════════════════════════════════════════════════════════════
//  CurriculumController — aktif müfredatın canlı state'i
//
//  RESET-FIRST KURALI:
//   Kullanıcı seviye/bölüm değiştirdiğinde, mevcut state önce TAMAMEN BOŞALIR
//   (state = empty), ardından yeni müfredat yüklenir. Bu sayede UI'da eski
//   sınıfa ait HİÇBİR kalıntı (subjects, topics, subtopics) görünmez.
//
//  Dinleyiciler (Library, Quiz, Matchmaking widget'ları) `notifyListeners()`
//  yerine Riverpod ref.watch ile otomatik tetiklenir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/curriculum_repository.dart';
import '../domain/curriculum_node.dart';
import '../domain/user_preference.dart';

/// CurriculumController'ın sahip olduğu state. Sealed-style 3 durum:
///  • empty     — ilk açılış veya geçiş anı
///  • loading   — fetch sırasında (gelecek async fetch için)
///  • loaded    — aktif müfredat var
class CurriculumState {
  final UserPreference? preference;
  final List<CurriculumSubject> subjects;
  final bool isLoading;

  const CurriculumState._({
    this.preference,
    this.subjects = const [],
    this.isLoading = false,
  });

  const CurriculumState.empty() : this._();
  const CurriculumState.loading(UserPreference pref)
      : this._(preference: pref, isLoading: true);
  const CurriculumState.loaded(UserPreference pref, List<CurriculumSubject> s)
      : this._(preference: pref, subjects: s);

  bool get hasData => subjects.isNotEmpty;
}

class CurriculumController extends StateNotifier<CurriculumState> {
  final CurriculumRepository _repo;

  CurriculumController(this._repo) : super(const CurriculumState.empty());

  /// RESET-FIRST: önce empty'e düş, sonra yeni müfredatı yükle.
  /// "Lise 10'dan Tıp 3'e geçiş" anında UI'da eski derslerin GÖRÜNMEMESİNİ
  /// garanti eder.
  void updateCurriculum(UserPreference pref) {
    // 1) Mevcut state'i tamamen sıfırla (eski subjects/topics/subtopics gider)
    state = const CurriculumState.empty();
    // 2) Yeni profil için yükleniyor durumu
    state = CurriculumState.loading(pref);
    // 3) Repo'dan fetch + state güncelle
    final subjects = _repo.fetch(pref);
    state = CurriculumState.loaded(pref, subjects);
  }

  /// Manuel temizleme — kullanıcı çıkış yapınca veya profil silince.
  void clear() {
    state = const CurriculumState.empty();
  }

  /// Aktif profile bağlı belirli bir dersin konuları (Level 2).
  List<CurriculumTopic> topicsForSubject(String subjectKey) {
    final pref = state.preference;
    if (pref == null) return const [];
    return _repo.topicsFor(pref, subjectKey);
  }

  /// Bir konunun alt konuları (Level 3) — sınav/özet üretimi için.
  List<CurriculumSubtopic> subtopicsForTopic(
      String subjectKey, String topicKey) {
    final pref = state.preference;
    if (pref == null) return const [];
    return _repo.subtopicsFor(pref, subjectKey, topicKey);
  }
}

// ─── Riverpod sağlayıcıları ────────────────────────────────────────────────

final curriculumRepositoryProvider = Provider<CurriculumRepository>(
  (ref) => CurriculumRepository.seeded(),
);

final curriculumControllerProvider =
    StateNotifierProvider<CurriculumController, CurriculumState>((ref) {
  return CurriculumController(ref.watch(curriculumRepositoryProvider));
});

/// Aktif tercih (UserPreference) için kestirme — Library/Quiz/Matchmaking
/// modüllerinde kolayca okunabilir.
final activePreferenceProvider = Provider<UserPreference?>((ref) {
  return ref.watch(curriculumControllerProvider).preference;
});

/// Aktif derslerin listesi — Library bunu watch eder.
final activeSubjectsProvider = Provider<List<CurriculumSubject>>((ref) {
  return ref.watch(curriculumControllerProvider).subjects;
});
