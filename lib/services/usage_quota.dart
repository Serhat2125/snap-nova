// Kullanıcı başına günlük/aylık AI kullanım kotası.
// Gemini çağrılarının (test soru üretimi, konu özeti, çözüm) sayısını
// SharedPreferences'ta tutar; UI buradan kontrol ederek soft-block yapar.
//
// Tasarım: tek tip + durum bağımsız "increment" + "remaining" çağrısı.
// Quota dolarsa kullanıcıya net mesaj gösterilir, gün sonu / ay sonu reset.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanım türleri — her birinin ayrı kotası vardır.
enum QuotaKind {
  /// Konu özeti üretimi (en pahalı: 32K token).
  topicSummary,

  /// Test soruları üretimi (~5K token x soru sayısı).
  testQuestions,

  /// Bilgi yarışı eşleştirme/test soruları.
  arenaQuiz,

  /// Çözüm ekranı (Basit / Adım adım / AI Öğretmen).
  solution,
}

/// Quota limitleri — feature flag, env veya remote config ile override edilebilir.
/// Şimdilik free tier için makul defaultlar; premium kullanıcı için ileride
/// ayrı set tutulabilir.
class QuotaLimits {
  /// Günlük limit (UTC midnight reset).
  final Map<QuotaKind, int> daily;

  /// Aylık limit (ay başı reset).
  final Map<QuotaKind, int> monthly;

  const QuotaLimits({required this.daily, required this.monthly});

  /// Free tier — geliştirme aşamasında bol; yayında bu değerler düşürülecek.
  static const free = QuotaLimits(
    daily: {
      QuotaKind.topicSummary: 20,
      QuotaKind.testQuestions: 30,
      QuotaKind.arenaQuiz: 50,
      QuotaKind.solution: 100,
    },
    monthly: {
      QuotaKind.topicSummary: 200,
      QuotaKind.testQuestions: 300,
      QuotaKind.arenaQuiz: 500,
      QuotaKind.solution: 1500,
    },
  );

  /// Premium — gelecekte aboneliği olan kullanıcılar için.
  static const premium = QuotaLimits(
    daily: {
      QuotaKind.topicSummary: 200,
      QuotaKind.testQuestions: 300,
      QuotaKind.arenaQuiz: 500,
      QuotaKind.solution: 2000,
    },
    monthly: {
      QuotaKind.topicSummary: 5000,
      QuotaKind.testQuestions: 8000,
      QuotaKind.arenaQuiz: 12000,
      QuotaKind.solution: 50000,
    },
  );
}

class QuotaUsage {
  final int dailyUsed;
  final int monthlyUsed;
  final int dailyLimit;
  final int monthlyLimit;
  const QuotaUsage({
    required this.dailyUsed,
    required this.monthlyUsed,
    required this.dailyLimit,
    required this.monthlyLimit,
  });

  bool get isDailyExhausted => dailyUsed >= dailyLimit;
  bool get isMonthlyExhausted => monthlyUsed >= monthlyLimit;
  bool get isExhausted => isDailyExhausted || isMonthlyExhausted;

  int get dailyRemaining => (dailyLimit - dailyUsed).clamp(0, dailyLimit);
  int get monthlyRemaining =>
      (monthlyLimit - monthlyUsed).clamp(0, monthlyLimit);
}

class UsageQuota {
  static QuotaLimits limits = QuotaLimits.free;

  static String _kindKey(QuotaKind k) => switch (k) {
        QuotaKind.topicSummary => 'topic_summary',
        QuotaKind.testQuestions => 'test_questions',
        QuotaKind.arenaQuiz => 'arena_quiz',
        QuotaKind.solution => 'solution',
      };

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static String _monthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// Günlük + aylık kullanımı oku. Dönen QuotaUsage'da
  /// `isExhausted` = true ise UI soft-block yapmalı.
  static Future<QuotaUsage> get(QuotaKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _kindKey(kind);
    final dailyRaw = prefs.getString('quota_daily_$key') ?? '{}';
    final monthlyRaw = prefs.getString('quota_monthly_$key') ?? '{}';

    int dailyUsed = 0;
    int monthlyUsed = 0;
    try {
      final m = jsonDecode(dailyRaw) as Map<String, dynamic>;
      if (m['date'] == _todayKey()) {
        dailyUsed = (m['count'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    try {
      final m = jsonDecode(monthlyRaw) as Map<String, dynamic>;
      if (m['month'] == _monthKey()) {
        monthlyUsed = (m['count'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    return QuotaUsage(
      dailyUsed: dailyUsed,
      monthlyUsed: monthlyUsed,
      dailyLimit: limits.daily[kind] ?? 9999,
      monthlyLimit: limits.monthly[kind] ?? 99999,
    );
  }

  /// AI çağrısı YAPMADAN ÖNCE çağır. Quota varsa true döner + sayaç artırır.
  /// Quota dolu ise false döner + sayaç değişmez.
  /// `force=true` (admin/dev) sayacı ileri alır ama doluysa bile true döner.
  static Future<bool> tryConsume(QuotaKind kind, {bool force = false}) async {
    final usage = await get(kind);
    if (usage.isExhausted && !force) return false;
    await _incrementSilent(kind);
    return true;
  }

  /// Sadece sayacı artır (quota kontrolü yapmaz). Force / arka plan retry vb.
  static Future<void> increment(QuotaKind kind) => _incrementSilent(kind);

  static Future<void> _incrementSilent(QuotaKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _kindKey(kind);

    // Daily
    final today = _todayKey();
    int dailyCount = 0;
    try {
      final raw = prefs.getString('quota_daily_$key');
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['date'] == today) {
          dailyCount = (m['count'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (_) {}
    dailyCount++;
    await prefs.setString(
      'quota_daily_$key',
      jsonEncode({'date': today, 'count': dailyCount}),
    );

    // Monthly
    final month = _monthKey();
    int monthlyCount = 0;
    try {
      final raw = prefs.getString('quota_monthly_$key');
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['month'] == month) {
          monthlyCount = (m['count'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (_) {}
    monthlyCount++;
    await prefs.setString(
      'quota_monthly_$key',
      jsonEncode({'month': month, 'count': monthlyCount}),
    );
  }

  /// Tüm kotaları sıfırla (dev / test / "premium upgrade" sonrası).
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final kind in QuotaKind.values) {
      final key = _kindKey(kind);
      await prefs.remove('quota_daily_$key');
      await prefs.remove('quota_monthly_$key');
    }
  }

  /// Tek bir feature için reset (örn. premium aboneliği başlatıldı → topicSummary
  /// sayacı sıfır).
  static Future<void> reset(QuotaKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _kindKey(kind);
    await prefs.remove('quota_daily_$key');
    await prefs.remove('quota_monthly_$key');
  }
}
