// ═══════════════════════════════════════════════════════════════════════════════
//  OfflineGenerationProvider — derse göre konu listesi + tek konu üretimi
//
//  Eski "tüm dersleri toplu indir" akışı kaldırıldı (her ders için tüm konuları
//  AI'dan çekmek pahalıydı). Yeni akış:
//   1. Kullanıcı ders kartına tıklar → konu BAŞLIKLARI AI'dan getirilir, cache'lenir
//   2. Bir konunun yanındaki "Oluştur" butonu → o konunun ÖZETİ üretilir
//   3. Aylık limit: ders başına 3 konu üretimi / ay
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/education_profile.dart';
import '../../../services/gemini_service.dart';
import '../domain/offline_subject_pack.dart';

/// Profil signature — pref key'lerinde scoping için.
String _sigOf(EduProfile p) =>
    '${p.country}_${p.level}_${p.grade}_${p.faculty ?? ""}_${p.track ?? ""}';

/// Konu BAŞLIKLARI cache (tek seferlik fetch, dersin müfredatı sabit).
String _topicNamesKey(EduProfile p, String subjectKey) =>
    'offline_topic_names_v1::${_sigOf(p)}::$subjectKey';

/// Üretilmiş konu özetleri (kullanıcı "Oluştur" basarak oluşturduğu).
String _generatedKey(EduProfile p, String subjectKey) =>
    'offline_generated_v1::${_sigOf(p)}::$subjectKey';

/// Aylık limit (ders başına ay başına 3 konu).
const int kMonthlyTopicLimit = 3;

class OfflineGeneratedTopic {
  final String name;
  final String summary;
  final DateTime generatedAt;
  const OfflineGeneratedTopic({
    required this.name,
    required this.summary,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'summary': summary,
        'generatedAt': generatedAt.toIso8601String(),
      };

  factory OfflineGeneratedTopic.fromJson(Map<String, dynamic> j) =>
      OfflineGeneratedTopic(
        name: (j['name'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
        generatedAt: DateTime.tryParse(j['generatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class OfflineGenerationStatus {
  /// Şu anda devam eden işlemler — UI'de spinner için.
  final Set<String> generatingTopics; // formatted: '$subjectKey::$topicName'
  final String? errorMessage;
  const OfflineGenerationStatus({
    this.generatingTopics = const {},
    this.errorMessage,
  });

  bool isGenerating(String subjectKey, String topicName) =>
      generatingTopics.contains('$subjectKey::$topicName');

  OfflineGenerationStatus copyWith({
    Set<String>? generatingTopics,
    String? errorMessage,
    bool clearError = false,
  }) =>
      OfflineGenerationStatus(
        generatingTopics: generatingTopics ?? this.generatingTopics,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class OfflineGenerationController
    extends StateNotifier<OfflineGenerationStatus> {
  OfflineGenerationController() : super(const OfflineGenerationStatus());

  // ─── Konu BAŞLIKLARI ─────────────────────────────────────────────────────

  /// Cache'lenen başlıkları oku (varsa).
  Future<List<String>?> readTopicNames({
    required EduProfile profile,
    required String subjectKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_topicNamesKey(profile, subjectKey));
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  /// AI'dan konu başlıklarını çek + cache'le (yoksa).
  Future<List<String>> ensureTopicNames({
    required EduProfile profile,
    required String subjectKey,
    required String subjectName,
  }) async {
    final cached = await readTopicNames(
      profile: profile,
      subjectKey: subjectKey,
    );
    if (cached != null && cached.isNotEmpty) return cached;
    final names = await GeminiService.fetchTopicNames(
      subjectName: subjectName,
      profile: profile,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _topicNamesKey(profile, subjectKey),
      jsonEncode(names),
    );
    return names;
  }

  // ─── Üretilmiş konu özetleri ─────────────────────────────────────────────

  Future<List<OfflineGeneratedTopic>> readGenerated({
    required EduProfile profile,
    required String subjectKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_generatedKey(profile, subjectKey));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(OfflineGeneratedTopic.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveGenerated({
    required EduProfile profile,
    required String subjectKey,
    required List<OfflineGeneratedTopic> list,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _generatedKey(profile, subjectKey),
      jsonEncode(list.map((g) => g.toJson()).toList()),
    );
  }

  /// Bu ay bu ders için üretilen konu sayısı.
  Future<int> monthlyUsage({
    required EduProfile profile,
    required String subjectKey,
  }) async {
    final list = await readGenerated(profile: profile, subjectKey: subjectKey);
    final now = DateTime.now();
    return list
        .where((g) =>
            g.generatedAt.year == now.year &&
            g.generatedAt.month == now.month)
        .length;
  }

  /// Tek bir konuyu AI'dan üret + kaydet. Aylık limit kontrolü yapar.
  /// Daha önce üretildiyse cache'den döner.
  Future<({bool success, String? errorMessage})> generateTopic({
    required EduProfile profile,
    required String subjectKey,
    required String subjectName,
    required String topicName,
  }) async {
    final marker = '$subjectKey::$topicName';
    if (state.isGenerating(subjectKey, topicName)) {
      return (success: false, errorMessage: 'Zaten üretiliyor.');
    }
    // Daha önce üretilmiş mi?
    final existing =
        await readGenerated(profile: profile, subjectKey: subjectKey);
    final already = existing.any((g) => g.name == topicName);
    if (already) {
      return (success: true, errorMessage: null);
    }
    // Aylık limit
    final used =
        await monthlyUsage(profile: profile, subjectKey: subjectKey);
    if (used >= kMonthlyTopicLimit) {
      return (
        success: false,
        errorMessage:
            'Bu ay $subjectName dersinde sınıra ulaştın ($used/$kMonthlyTopicLimit). Önümüzdeki ay sıfırlanır.',
      );
    }
    // Üret
    state = state.copyWith(
      generatingTopics: {...state.generatingTopics, marker},
      clearError: true,
    );
    try {
      final summary = await GeminiService.fetchSingleTopicSummary(
        subjectName: subjectName,
        topicName: topicName,
        profile: profile,
      );
      final newList = [
        ...existing,
        OfflineGeneratedTopic(
          name: topicName,
          summary: summary,
          generatedAt: DateTime.now(),
        ),
      ];
      await _saveGenerated(
        profile: profile,
        subjectKey: subjectKey,
        list: newList,
      );
      // Eski OfflineSubjectPack key'ine de yaz (dialog cache'i için).
      await _mergeIntoPack(
        profile: profile,
        subjectKey: subjectKey,
        subjectName: subjectName,
        topicName: topicName,
        summary: summary,
      );
      state = state.copyWith(
        generatingTopics:
            state.generatingTopics.where((m) => m != marker).toSet(),
      );
      return (success: true, errorMessage: null);
    } catch (e) {
      state = state.copyWith(
        generatingTopics:
            state.generatingTopics.where((m) => m != marker).toSet(),
        errorMessage: 'Üretilemedi: $e',
      );
      return (success: false, errorMessage: 'Üretilemedi: $e');
    }
  }

  /// Var olan OfflineSubjectPack pref'ine bu üretileni ekle (her iki cache de
  /// senkron kalsın → konu özetleri sayfası anında görür).
  Future<void> _mergeIntoPack({
    required EduProfile profile,
    required String subjectKey,
    required String subjectName,
    required String topicName,
    required String summary,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'offline_pack_v1::${_sigOf(profile)}::$subjectKey';
    OfflineSubjectPack? existing;
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      existing = OfflineSubjectPack.decodeOrNull(raw);
    }
    final newTopic = OfflineTopic(name: topicName, summary: summary);
    final allTopics = <OfflineTopic>[];
    if (existing != null) {
      allTopics.addAll(existing.topics.where((t) => t.name != topicName));
    }
    allTopics.add(newTopic);
    final pack = OfflineSubjectPack(
      subjectKey: subjectKey,
      subjectName: subjectName,
      emoji: existing?.emoji ?? '📚',
      topics: allTopics,
      cachedAt: DateTime.now(),
    );
    await prefs.setString(key, pack.encode());
  }

  /// Statik erişim — eski kodun read pack çağrısı için (UI sheet kullanıyor).
  static Future<OfflineSubjectPack?> readPack({
    required EduProfile profile,
    required String subjectKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
        'offline_pack_v1::${_sigOf(profile)}::$subjectKey');
    if (raw == null) return null;
    return OfflineSubjectPack.decodeOrNull(raw);
  }
}

final offlineGenerationProvider = StateNotifierProvider<
    OfflineGenerationController, OfflineGenerationStatus>(
  (ref) => OfflineGenerationController(),
);

/// Geriye dönük uyum: eski tip aliası
typedef OfflineDownloadController = OfflineGenerationController;
final offlineDownloadProvider = offlineGenerationProvider;
