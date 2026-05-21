// ═══════════════════════════════════════════════════════════════════════════════
//  AchievementService — Rozet kazanma kuralları (gerçek logic, mock YOK).
//
//  Kurallar (qualsar_arena_screen._allBadges ile eşleşir):
//    🔥 Ateşli      → Streak ≥ 7 gün (LeagueScores.currentStreak)
//    🎯 Sniper      → Tek bir attempt'ta % 100 doğru (ÖSYM net = soru sayısı)
//    🏆 Bilgi Ustası→ Toplam ≥10 attempt + ortalama net ≥ 70%
//    👑 Efsane      → Toplam ≥ 50 attempt
//    🌈 Çok Yönlü   → 5 farklı subjectKey
//    ⚡ Hız Şampiyonu→ Bir attempt'ı ≤ 60 saniyede bitirme (race-pace)
//    🎴 Kart Koleksiyoncusu → 10 farklı konuda özet/note (SharedPreferences)
//
//  Hesap: LeagueScores.loadAll() local cache'ten okur (offline-first).
//  Cloud sync gerekmez; her cihaz kendi attempt geçmişiyle hesaplar.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/league/league_scores.dart';

enum AchievementId {
  streak7,
  perfectQuiz,
  knowledgeMaster,
  legend,
  versatile,
  speedChamp,
  cardCollector,
}

class Achievement {
  final AchievementId id;
  final String emoji;
  final String name;
  final String rule;
  final bool unlocked;
  /// İnsan-okur kazanım zamanı — "Bugün", "3 gün önce", "Kilitli" vb.
  final String status;
  /// Eğer kilitli ise ilerleme yüzdesi (0-1). Kilitli olmayanlarda null.
  final double? progress;
  /// İlerleme mesajı — "7/10 test çözüldü" gibi.
  final String? progressText;

  const Achievement({
    required this.id,
    required this.emoji,
    required this.name,
    required this.rule,
    required this.unlocked,
    required this.status,
    this.progress,
    this.progressText,
  });
}

class AchievementService {
  /// Tüm rozetlerin güncel durumunu hesapla.
  static Future<List<Achievement>> compute() async {
    final attempts = await LeagueScores.loadAll();
    final streak = await LeagueScores.currentStreak();
    final totalAttempts = attempts.length;
    final subjects = attempts.map((a) => a.subjectKey).toSet();
    // En hızlı tek attempt (saniye)
    final fastestSec = attempts.isEmpty
        ? null
        : attempts
            .where((a) => a.durationSec > 0)
            .map((a) => a.durationSec)
            .fold<int?>(null,
                (min, s) => (min == null || s < min) ? s : min);
    // Perfect attempt = score eşit veya çok yakın 10 (10 soru tam doğru)
    final hasPerfect =
        attempts.any((a) => a.score >= 9.99); // 10 net
    // Ortalama net
    final avgScore = attempts.isEmpty
        ? 0.0
        : attempts.map((a) => a.score).reduce((a, b) => a + b) /
            attempts.length;
    // Note koleksiyonu — SharedPref'ten saved_notes_v1
    int noteSubjectCount = 0;
    try {
      final p = await SharedPreferences.getInstance();
      final notes = p.getStringList('saved_notes_topics_v1') ?? const [];
      noteSubjectCount = notes.toSet().length;
    } catch (e) {
      debugPrint('[Achievements] note count fail: $e');
    }

    String agoStatus(DateTime? when) {
      if (when == null) return 'Bilinmiyor';
      final d = DateTime.now().difference(when);
      if (d.inMinutes < 60) return 'Az önce';
      if (d.inHours < 24) return 'Bugün';
      if (d.inDays < 7) return '${d.inDays} gün önce';
      if (d.inDays < 30) return '${(d.inDays / 7).floor()} hafta önce';
      return '${(d.inDays / 30).floor()} ay önce';
    }

    DateTime? perfectAt = attempts
        .where((a) => a.score >= 9.99)
        .fold<DateTime?>(null,
            (acc, a) => acc == null || a.when.isAfter(acc) ? a.when : acc);
    DateTime? fastestAt = attempts
        .where((a) => a.durationSec > 0 && a.durationSec <= 60)
        .fold<DateTime?>(null,
            (acc, a) => acc == null || a.when.isAfter(acc) ? a.when : acc);
    DateTime? latestAttempt = attempts.isEmpty
        ? null
        : attempts.reduce((a, b) => a.when.isAfter(b.when) ? a : b).when;

    return [
      // 🔥 Streak
      Achievement(
        id: AchievementId.streak7,
        emoji: '🔥',
        name: 'Ateşli',
        rule: '7 gün üst üste test çöz. Seri devam ettikçe alev büyür.',
        unlocked: streak >= 7,
        status: streak >= 7
            ? '$streak gün streak'
            : 'Kilitli',
        progress: streak >= 7 ? null : (streak / 7).clamp(0, 1).toDouble(),
        progressText: streak >= 7 ? null : '$streak/7 gün',
      ),
      // 🎯 Sniper
      Achievement(
        id: AchievementId.perfectQuiz,
        emoji: '🎯',
        name: 'Sniper',
        rule: 'Bir testte hiç yanlış yapmadan tüm soruları doğru cevapla.',
        unlocked: hasPerfect,
        status: hasPerfect ? agoStatus(perfectAt) : 'Kilitli',
        progress: hasPerfect ? null : 0.0,
        progressText: hasPerfect ? null : 'Mükemmel test gerekli',
      ),
      // 🏆 Bilgi Ustası
      Achievement(
        id: AchievementId.knowledgeMaster,
        emoji: '🏆',
        name: 'Bilgi Ustası',
        rule: 'Toplam 10 test tamamla. Sonuçların ortalaması %70+ olmalı.',
        unlocked: totalAttempts >= 10 && avgScore >= 7.0,
        status: (totalAttempts >= 10 && avgScore >= 7.0)
            ? agoStatus(latestAttempt)
            : 'Kilitli',
        progress: (totalAttempts >= 10 && avgScore >= 7.0)
            ? null
            : (totalAttempts / 10).clamp(0, 1).toDouble(),
        progressText: (totalAttempts >= 10 && avgScore >= 7.0)
            ? null
            : '$totalAttempts/10 test (avg ${avgScore.toStringAsFixed(1)})',
      ),
      // 👑 Efsane
      Achievement(
        id: AchievementId.legend,
        emoji: '👑',
        name: 'Efsane',
        rule: 'Toplam 50 test tamamla. Hangi dersle olursa olsun devam et.',
        unlocked: totalAttempts >= 50,
        status: totalAttempts >= 50 ? agoStatus(latestAttempt) : 'Kilitli',
        progress: totalAttempts >= 50
            ? null
            : (totalAttempts / 50).clamp(0, 1).toDouble(),
        progressText:
            totalAttempts >= 50 ? null : '$totalAttempts/50 test',
      ),
      // 🌈 Çok Yönlü
      Achievement(
        id: AchievementId.versatile,
        emoji: '🌈',
        name: 'Çok Yönlü',
        rule: '5 farklı derste en az 1 test çöz. Çeşitlilik kazandırır.',
        unlocked: subjects.length >= 5,
        status: subjects.length >= 5
            ? agoStatus(latestAttempt)
            : 'Kilitli',
        progress: subjects.length >= 5
            ? null
            : (subjects.length / 5).clamp(0, 1).toDouble(),
        progressText:
            subjects.length >= 5 ? null : '${subjects.length}/5 ders',
      ),
      // ⚡ Hız Şampiyonu
      Achievement(
        id: AchievementId.speedChamp,
        emoji: '⚡',
        name: 'Hız Şampiyonu',
        rule: 'Bir testi 60 saniye altında bitir.',
        unlocked: (fastestSec ?? 999999) <= 60,
        status: (fastestSec ?? 999999) <= 60
            ? agoStatus(fastestAt)
            : 'Kilitli',
        progress: null,
        progressText: (fastestSec ?? 999999) <= 60
            ? null
            : (fastestSec == null
                ? 'Henüz test yok'
                : 'En hızlı: ${fastestSec}sn (60 hedef)'),
      ),
      // 🎴 Kart Koleksiyoncusu
      Achievement(
        id: AchievementId.cardCollector,
        emoji: '🎴',
        name: 'Kart Koleksiyoncusu',
        rule: '10 farklı konuda bilgi kartı / özet oluştur.',
        unlocked: noteSubjectCount >= 10,
        status: noteSubjectCount >= 10 ? 'Kazanıldı' : 'Kilitli',
        progress: noteSubjectCount >= 10
            ? null
            : (noteSubjectCount / 10).clamp(0, 1).toDouble(),
        progressText:
            noteSubjectCount >= 10 ? null : '$noteSubjectCount/10 konu',
      ),
    ];
  }
}
