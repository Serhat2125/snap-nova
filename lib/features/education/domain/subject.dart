// ═══════════════════════════════════════════════════════════════════════════════
//  Subject — bir ders (Matematik, Fizik, Anatomi, ...)
//
//  Her seviye + sınıf kombinasyonunun farklı dersleri olabilir. AI runtime
//  cache'i (EduProfile.aiCachedSubjects) bu modele direkt çevrilebilir.
// ═══════════════════════════════════════════════════════════════════════════════

class Subject {
  /// snake_case ASCII unique anahtar — ör. 'math', 'anatomy', 'edebiyat'.
  final String key;

  /// Endonim ad — UI'de gösterilen.
  final String name;

  /// Görsel emoji.
  final String emoji;

  const Subject({
    required this.key,
    required this.name,
    required this.emoji,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Subject && other.key == key);

  @override
  int get hashCode => key.hashCode;
}
