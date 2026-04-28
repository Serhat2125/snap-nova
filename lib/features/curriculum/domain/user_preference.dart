// ═══════════════════════════════════════════════════════════════════════════════
//  UserPreference — kullanıcının aktif seçimi (ülke + seviye + sınıf + dal)
//
//  Mevcut `UserEducationProfile` ile yan yana yaşar; bu sınıf `CurriculumController`
//  için sadeleştirilmiş bir snapshot tutar. Aynı profile karşılık gelen iki
//  UserPreference == operatörü ile eşittir; cache invalidation hızlanır.
// ═══════════════════════════════════════════════════════════════════════════════

class UserPreference {
  /// ISO ülke kodu (örn. 'tr', 'de', 'us'). 'international' fallback.
  final String country;

  /// Uygulama dili — ISO 639-1 (örn. 'tr', 'de', 'en').
  /// AI prompt'larında "respond in this language" direktifi olarak gider.
  final String languageCode;

  /// Eğitim seviyesi anahtarı: primary, middle, high, university,
  /// masters, doctorate, exam_prep, lgs_prep.
  final String levelKey;

  /// Sınıf anahtarı (örn. '12', '3', 'YKS', 'ALES'). Sınava hazırlık
  /// modunda sınav adı buraya gelir.
  final String gradeKey;

  /// Dal/bölüm anahtarı (örn. 'sayisal', 'sozel' lise için; 'insaat_muh',
  /// 'tip' üniversite için). Boş olabilir.
  final String? branchKey;

  const UserPreference({
    required this.country,
    required this.languageCode,
    required this.levelKey,
    required this.gradeKey,
    this.branchKey,
  });

  /// Müfredat lookup için unique key (dilden bağımsız — TR 10 öğrencisi ne
  /// zaman İngilizce kullansa bile aynı müfredat).
  String get signature =>
      '$country|$levelKey|$gradeKey|${branchKey ?? ''}';

  /// Dünya genelinde "eşdeğer sınıf" eşleşme anahtarı. Aynı eğitim
  /// kategorisindeki kullanıcılar (TR 10. sınıf ↔ DE 10. Klasse ↔ US Grade 10)
  /// bu anahtarda uyuşur. Yarışma matchmaking'te world scope için kullanılır.
  String get worldMatchKey {
    // levelKey + gradeKey kombinasyonu, ülke-bağımsız.
    // exam_prep modunda gradeKey sınav adı (YKS/SAT/Abitur) — bunlar
    // ülkeye özgü olduğundan world match yapılmaz; ülke içi match olur.
    if (levelKey == 'exam_prep' || levelKey == 'lgs_prep') {
      return 'EXAM:$country:$gradeKey'; // sadece aynı ülke + sınav
    }
    return '$levelKey:$gradeKey';
  }

  /// Ülke içi matchmaking anahtarı. Aynı ülke + aynı sınıf + (varsa) bölüm.
  String get countryMatchKey =>
      '$country:$levelKey:$gradeKey:${branchKey ?? ''}';

  /// AI'ya gönderilecek system prompt parçası — "Bağlam Kilidi" (Context Lock).
  /// Her LLM çağrısında prepend edilir.
  String get aiContextBlock {
    final branchPart = (branchKey != null && branchKey!.isNotEmpty)
        ? ' · Bölüm: $branchKey'
        : '';
    return '''[STUDENT CONTEXT — STRICT FILTER]
Country code: $country
Response language (ISO 639-1): $languageCode
Education level: $levelKey
Grade/Exam: $gradeKey$branchPart

CRITICAL RULES:
• Stay strictly within this country's official curriculum for this level/grade.
• Use the OFFICIAL terminology and depth expected at this stage.
• Respond ONLY in the language matching code "$languageCode".
• Do NOT pull content from higher or lower grades.
• If a question crosses the syllabus boundary, note it briefly but answer at this level.''';
  }

  UserPreference copyWith({
    String? country,
    String? languageCode,
    String? levelKey,
    String? gradeKey,
    String? branchKey,
  }) =>
      UserPreference(
        country: country ?? this.country,
        languageCode: languageCode ?? this.languageCode,
        levelKey: levelKey ?? this.levelKey,
        gradeKey: gradeKey ?? this.gradeKey,
        branchKey: branchKey ?? this.branchKey,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserPreference &&
          other.signature == signature &&
          other.languageCode == languageCode);

  @override
  int get hashCode => Object.hash(signature, languageCode);

  @override
  String toString() => 'UserPreference($signature, lang=$languageCode)';
}
