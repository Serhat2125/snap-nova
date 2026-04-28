// ═══════════════════════════════════════════════════════════════════════════════
//  CurriculumRepository — UserPreference → CurriculumSubject ağacı
//
//  Şu an seed'den çalışır (yerel JSON). İleride Firestore eklenirse
//  burası değişir; tüketici controller değişmez.
// ═══════════════════════════════════════════════════════════════════════════════

import '../domain/curriculum_node.dart';
import '../domain/user_preference.dart';
import 'seed_curriculum.dart';

class CurriculumRepository {
  final Map<String, List<CurriculumSubject>> _byPreference;

  CurriculumRepository._(this._byPreference);

  factory CurriculumRepository.seeded() =>
      CurriculumRepository._(loadSeedCurriculum());

  /// Verilen tercih için müfredat ağacını döndür. Bulunmazsa boş liste.
  List<CurriculumSubject> fetch(UserPreference pref) {
    return _byPreference[pref.signature] ?? const [];
  }

  /// Bir profilde belirli bir dersin konularını getir.
  List<CurriculumTopic> topicsFor(UserPreference pref, String subjectKey) {
    final subjects = fetch(pref);
    for (final s in subjects) {
      if (s.key == subjectKey) return s.topics;
    }
    return const [];
  }

  /// Bir konunun alt-konularını getir.
  List<CurriculumSubtopic> subtopicsFor(
      UserPreference pref, String subjectKey, String topicKey) {
    final topics = topicsFor(pref, subjectKey);
    for (final t in topics) {
      if (t.key == topicKey) return t.subtopics;
    }
    return const [];
  }
}
