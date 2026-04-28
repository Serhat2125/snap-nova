// ═══════════════════════════════════════════════════════════════════════════════
//  CurriculumNode — 3 katmanlı müfredat ağacı
//
//   Level 1: CurriculumSubject (Ders)       → "Matematik", "Mukavemet"
//   Level 2: CurriculumTopic (Konu)         → "Türev", "Gerilme"
//   Level 3: String (Alt konu / mikro konu) → "Polinomlar", "Eksenel Yükler"
//
//  Sınav/özet üretimi Level 3 (subtopics) üzerinden çalışır → AI prompt'ları
//  tam başlık adıyla beslenir.
// ═══════════════════════════════════════════════════════════════════════════════

/// Veri tabanı/Firestore karşılığı: `sub_topics` tablosu (course_id + topic_id'ye bağlı).
class CurriculumSubtopic {
  /// `${gradeId}:${courseId}:${topicKey}:${index}` benzeri unique id.
  final String id;

  /// Kullanıcı dilinde görünür ad — ör. "Polinomlar", "Eksenel Yükler".
  final String name;

  const CurriculumSubtopic({required this.id, required this.name});

  @override
  String toString() => name;
}

class CurriculumTopic {
  /// snake_case ASCII unique anahtar — ör. 'turev', 'gerilme'.
  final String key;

  /// Kullanıcı dilinde görünür ad — ör. "Türev", "Gerilme".
  final String name;

  /// Bu konunun alt-mikro konuları (Level 3).
  final List<CurriculumSubtopic> subtopics;

  const CurriculumTopic({
    required this.key,
    required this.name,
    this.subtopics = const [],
  });
}

class CurriculumSubject {
  /// Veri tabanı `course_id` karşılığı (snake_case ASCII).
  final String key;
  final String name;
  final String emoji;
  final List<CurriculumTopic> topics;

  const CurriculumSubject({
    required this.key,
    required this.name,
    required this.emoji,
    required this.topics,
  });

  /// Bu derse ait tüm alt konuları (her topic'ten) düzleştir — Sınav
  /// Hazırlama ekranı için kestirme.
  List<CurriculumSubtopic> flattenSubtopics() {
    final out = <CurriculumSubtopic>[];
    for (final t in topics) {
      out.addAll(t.subtopics);
    }
    return out;
  }
}
