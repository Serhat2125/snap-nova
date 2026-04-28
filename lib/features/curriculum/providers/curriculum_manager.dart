// ═══════════════════════════════════════════════════════════════════════════════
//  CurriculumManager — Yüksek Seviyeli Cephe (Facade)
//
//  PROTOKOL:
//   1) onChangeLevel(newPref): Hard Reset
//      • RAM state'i sıfırla
//      • Eski profile ait cache prefs'i (offline pack, AI subjects) temizle
//      • Yeniden "ilk giriş" gibi kabul et
//      • Yeni profil için fetchSubjects → fetchTopics zincirini başlat
//
//   2) fetchSubjects(levelID): tek aşama — sadece dersler listesi
//   3) fetchTopics(subjectID, levelID): istenen dersin konuları
//
//   4) canTriggerAction({subjectID, topicID, subtopicID}):
//      Subtopic seçilmeden hiçbir Action (AI sorgusu, sınav, yarışma)
//      tetiklenmesini engeller — UI'de buton enable/disable kontrolü.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/curriculum_node.dart';
import '../domain/user_preference.dart';
import 'curriculum_controller.dart';

class CurriculumManager {
  final Ref _ref;
  CurriculumManager(this._ref);

  /// Aktif tercih (read-only kestirme).
  UserPreference? get activePreference =>
      _ref.read(curriculumControllerProvider).preference;

  /// Aktif derslerin listesi.
  List<CurriculumSubject> get activeSubjects =>
      _ref.read(curriculumControllerProvider).subjects;

  // ─── HARD RESET PROTOKOLÜ ────────────────────────────────────────────────

  /// Eğitim düzeyi değiştiğinde tetiklenir. State + cache TAMAMEN sıfırlanır,
  /// sonra yeni profilin müfredatı yüklenir. Re-Authentication yaklaşımı.
  Future<void> onChangeLevel(UserPreference newPref) async {
    final ctrl = _ref.read(curriculumControllerProvider.notifier);
    final old = _ref.read(curriculumControllerProvider).preference;

    // 1. State'i tamamen boşalt — ref.watch dinleyen TÜM modüller
    //    (Library, Quiz, Arena) anında boş listeye düşer.
    ctrl.clear();

    // 2. Eski profile ait önbellek prefs'lerini temizle.
    if (old != null && old != newPref) {
      await _wipeCacheForPreference(old);
    }

    // 3. Yeni müfredat ağacını yükle (controller içinde subjects → topics
    //    zinciri otomatik). Subjects + Topics + Subtopics tek seferde gelir;
    //    bu yapı seed/repository'de zaten hierarchical (loadSeedCurriculum
    //    konuları + alt konuları tek fetchde döner).
    ctrl.updateCurriculum(newPref);

    debugPrint('[CurriculumManager] Hard Reset → ${newPref.signature}');
  }

  /// Sadece dersleri getir (Repository'nin direkt dönüşü).
  /// Hiyerarşik yapıda subjects + topics + subtopics tek seferde gelir;
  /// bu yüzden ayrı bir fetchTopics çağrısı gerekmez. Yine de spec
  /// uyumluluğu için ayrı metod sağlanıyor.
  List<CurriculumSubject> fetchSubjects(UserPreference levelID) {
    return _ref.read(curriculumRepositoryProvider).fetch(levelID);
  }

  /// Bir dersin konularını getir (Level 2).
  List<CurriculumTopic> fetchTopics(String subjectID, UserPreference levelID) {
    return _ref
        .read(curriculumRepositoryProvider)
        .topicsFor(levelID, subjectID);
  }

  /// Bir konunun alt konularını getir (Level 3).
  List<CurriculumSubtopic> fetchSubtopics(
    String subjectID,
    String topicID,
    UserPreference levelID,
  ) {
    return _ref
        .read(curriculumRepositoryProvider)
        .subtopicsFor(levelID, subjectID, topicID);
  }

  // ─── ACTION GATE ─────────────────────────────────────────────────────────

  /// Sınav, Özet veya Yarışma butonları sadece subtopicID dolu olduğunda
  /// true döner. UI'de `onPressed: manager.canTriggerAction(...) ? cb : null`.
  bool canTriggerAction({
    String? subjectID,
    String? topicID,
    String? subtopicID,
  }) {
    if (activePreference == null) return false;
    if (subjectID == null || subjectID.isEmpty) return false;
    if (topicID == null || topicID.isEmpty) return false;
    if (subtopicID == null || subtopicID.isEmpty) return false;
    // Mevcut subjects içinde varlık doğrulaması
    final subjects = activeSubjects;
    final s = subjects.where((x) => x.key == subjectID).toList();
    if (s.isEmpty) return false;
    final t = s.first.topics.where((x) => x.key == topicID).toList();
    if (t.isEmpty) return false;
    return t.first.subtopics.any((x) => x.id == subtopicID);
  }

  // ─── CACHE TEMİZLEME ─────────────────────────────────────────────────────

  /// Profil değişiminde eski profile özgü tüm cache key'lerini sil.
  Future<void> _wipeCacheForPreference(UserPreference p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sig = p.signature;
      // Bu key prefix'leriyle yazılan TÜM girişleri temizle.
      const prefixes = [
        'offline_pack_v1::',
        'offline_topic_names_v1::',
        'offline_generated_v1::',
        'ai_subjects_cache_v1::',
      ];
      final allKeys = prefs.getKeys();
      for (final k in allKeys) {
        for (final pfx in prefixes) {
          if (k.startsWith(pfx) && k.contains(sig)) {
            await prefs.remove(k);
          }
        }
      }
      debugPrint('[CurriculumManager] cache wipe done for $sig');
    } catch (e) {
      debugPrint('[CurriculumManager] cache wipe failed: $e');
    }
  }
}

final curriculumManagerProvider = Provider<CurriculumManager>((ref) {
  return CurriculumManager(ref);
});
