// ═══════════════════════════════════════════════════════════════════════════════
//  AI Context — LLM çağrılarına eklenmesi GEREKEN system prompt parçası
//
//  Curriculum + UserPreference birleşiminden tek bir string üretir.
//  Her AI çağrısı bu bloğu prepend ederek "Bağlam Kilidi" garantisi sağlar.
//  Subject + Topic + Subtopic seçildiyse, AI hangi spesifik mikro-konuda
//  içerik üreteceğini bilir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'curriculum_controller.dart';

/// Aktif bağlam → string. Yoksa boş.
final aiSystemContextProvider = Provider<String>((ref) {
  final pref = ref.watch(activePreferenceProvider);
  if (pref == null) return '';
  return pref.aiContextBlock;
});

/// Belirli bir alt-konu hedeflenirken kullanılacak genişletilmiş prompt.
/// AI Quiz / Summary endpoint'leri bunu çağırır.
String buildLockedAiPrompt({
  required String basePrompt,
  required String? country,
  required String? language,
  required String? levelKey,
  required String? gradeKey,
  String? branchKey,
  String? subjectName,
  String? topicName,
  String? subtopicName,
}) {
  final context = StringBuffer();
  context.writeln('[STUDENT CONTEXT — STRICT FILTER]');
  if (country != null) context.writeln('Country: $country');
  if (language != null) context.writeln('Language (ISO 639-1): $language');
  if (levelKey != null) context.writeln('Level: $levelKey');
  if (gradeKey != null) context.writeln('Grade/Exam: $gradeKey');
  if (branchKey != null && branchKey.isNotEmpty) {
    context.writeln('Branch: $branchKey');
  }
  if (subjectName != null) context.writeln('Subject: $subjectName');
  if (topicName != null) context.writeln('Topic: $topicName');
  if (subtopicName != null) context.writeln('Subtopic: $subtopicName');
  context.writeln('');
  context.writeln('CRITICAL RULES:');
  context.writeln('• Stay strictly within this country\'s curriculum.');
  context.writeln('• Match the depth and terminology of this level/grade.');
  if (language != null) {
    context.writeln('• Respond ONLY in language code "$language".');
  }
  if (subtopicName != null) {
    context.writeln('• Focus exclusively on the listed Subtopic.');
  }
  context.writeln('');
  context.writeln(basePrompt);
  return context.toString();
}
