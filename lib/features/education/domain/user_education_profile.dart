// ═══════════════════════════════════════════════════════════════════════════════
//  UserEducationProfile — kullanıcının seçtiği TEK bir eğitim seviyesi/sınıfı
//
//  Multi-select destek: kullanıcı birden fazla profile sahip olabilir
//  (örn. "Lise 11" + "YKS hazırlığı"). Her bir seçim bir UserEducationProfile.
//
//  Bu yeni domain modeli, eski services/education_profile.dart'taki EduProfile
//  ile yan yana yaşar — eski ekranlar EduProfile.current'i okumaya devam eder,
//  yeni ekranlar Riverpod provider üzerinden bu modeli kullanır.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

class UserEducationProfile {
  /// Ülke kodu (ISO 3166-1 alpha-2'ye yakın), ör. 'tr', 'de', 'us'.
  final String country;

  /// Eğitim seviyesi anahtarı: primary, middle, high, exam_prep,
  /// university, masters, doctorate, other.
  final String level;

  /// Sınıf veya sınav adı, ör. '11. Sınıf', 'YKS (Yükseköğretim Kurumları Sınavı)'.
  final String grade;

  /// Lise alanı (sayisal/sözel/EA/dil) veya benzeri opsiyonel kategori.
  final String? track;

  /// Üniversite/lisansüstü için bölüm/fakülte.
  final String? faculty;

  /// Profil eklenme zamanı — sıralama / "ne kadar süredir aktif" için.
  final DateTime addedAt;

  const UserEducationProfile({
    required this.country,
    required this.level,
    required this.grade,
    this.track,
    this.faculty,
    required this.addedAt,
  });

  /// Profil için unique key — country/level/grade/faculty/track kombinasyonu.
  String get signature =>
      '$country|$level|$grade|${faculty ?? ''}|${track ?? ''}';

  /// İnsan tarafından okunabilir kısa etiket (UI listelerinde, chip'lerde).
  String get displayLabel {
    final parts = <String>[];
    parts.add(level);
    if (faculty != null && faculty!.isNotEmpty) parts.add(faculty!);
    parts.add(grade);
    if (track != null && track!.isNotEmpty) parts.add(track!);
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'country': country,
        'level': level,
        'grade': grade,
        'track': track,
        'faculty': faculty,
        'addedAt': addedAt.toIso8601String(),
      };

  factory UserEducationProfile.fromJson(Map<String, dynamic> j) =>
      UserEducationProfile(
        country: (j['country'] ?? 'tr').toString(),
        level: (j['level'] ?? 'primary').toString(),
        grade: (j['grade'] ?? '').toString(),
        track: j['track']?.toString(),
        faculty: j['faculty']?.toString(),
        addedAt: DateTime.tryParse(j['addedAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  UserEducationProfile copyWith({
    String? country,
    String? level,
    String? grade,
    String? track,
    String? faculty,
    DateTime? addedAt,
  }) =>
      UserEducationProfile(
        country: country ?? this.country,
        level: level ?? this.level,
        grade: grade ?? this.grade,
        track: track ?? this.track,
        faculty: faculty ?? this.faculty,
        addedAt: addedAt ?? this.addedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserEducationProfile && other.signature == signature);

  @override
  int get hashCode => signature.hashCode;
}

/// JSON list ↔ `List<UserEducationProfile>` dönüşümü.
List<UserEducationProfile> decodeProfilesJson(String raw) {
  if (raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List;
    return list
        .whereType<Map<String, dynamic>>()
        .map(UserEducationProfile.fromJson)
        .toList();
  } catch (_) {
    return const [];
  }
}

String encodeProfilesJson(List<UserEducationProfile> profiles) =>
    jsonEncode(profiles.map((p) => p.toJson()).toList());
