// ═══════════════════════════════════════════════════════════════════════════════
//  OfflineSubjectPack — bir dersin offline kullanım için indirilmiş içeriği
//
//  Her pack, dersin:
//   • topics — konu başlıkları + her birinin 100-200 kelimelik özeti
//  içerir. Kullanıcı ağa bağlı değilken bile bu özetlere kütüphaneden erişir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

class OfflineTopic {
  final String name;
  final String summary;
  const OfflineTopic({required this.name, required this.summary});

  Map<String, dynamic> toJson() => {'name': name, 'summary': summary};

  factory OfflineTopic.fromJson(Map<String, dynamic> j) => OfflineTopic(
        name: (j['name'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
      );
}

class OfflineSubjectPack {
  final String subjectKey;
  final String subjectName;
  final String emoji;
  final List<OfflineTopic> topics;
  final DateTime cachedAt;

  const OfflineSubjectPack({
    required this.subjectKey,
    required this.subjectName,
    required this.emoji,
    required this.topics,
    required this.cachedAt,
  });

  Map<String, dynamic> toJson() => {
        'subjectKey': subjectKey,
        'subjectName': subjectName,
        'emoji': emoji,
        'topics': topics.map((t) => t.toJson()).toList(),
        'cachedAt': cachedAt.toIso8601String(),
      };

  factory OfflineSubjectPack.fromJson(Map<String, dynamic> j) =>
      OfflineSubjectPack(
        subjectKey: (j['subjectKey'] ?? '').toString(),
        subjectName: (j['subjectName'] ?? '').toString(),
        emoji: (j['emoji'] ?? '📚').toString(),
        topics: ((j['topics'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OfflineTopic.fromJson)
            .toList(),
        cachedAt: DateTime.tryParse(j['cachedAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  String encode() => jsonEncode(toJson());

  static OfflineSubjectPack? decodeOrNull(String raw) {
    if (raw.isEmpty) return null;
    try {
      return OfflineSubjectPack.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
