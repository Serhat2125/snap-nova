import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_provider_service.dart';
import 'premium_status.dart';

/// Kullanıcının AI kullanım hakkını yönetir.
///
/// Kural:
///   • İlk 7 gün → herkes premium gibi (trial).
///   • 7 gün sonra:
///       - Premium aktif → sınırsız, kaliteli modeller.
///       - Ücretsiz      → günde [kFreeQuotaPerDay] soru hakkı.
class AiQuotaService {
  AiQuotaService._();
  static final instance = AiQuotaService._();

  static const _kCountKey = 'ai_free_daily_count';
  static const _kDateKey  = 'ai_free_daily_date';

  /// YAPIM AŞAMASI BAYRAĞI — true iken trial/abonelik aranmaz; herkes premium
  /// kabul edilir. Böylece "1 hafta sonra premium iste" paywall'u + günlük
  /// ücretsiz limit tamamen DEVRE DIŞI olur (tüm AI özellikleri açık).
  /// ⚠️ Yayına/satışa çıkarken bunu `false` yap → trial + abonelik mantığı
  /// yeniden devreye girer.
  static const bool kDevAllPremium = true;

  bool _isPremiumSubscriber = false;
  bool _isInTrial = false;

  /// Premium mi? (yapım aşaması bayrağı, trial veya aktif abonelik)
  bool get isPremium => kDevAllPremium || _isPremiumSubscriber || _isInTrial;

  /// Trial döneminde mi?
  bool get isInTrial => _isInTrial;

  /// Test/özet üretimi premium özelliğidir. Trial (ilk 7 gün) dahil premium
  /// sayılır; 7 gün sonra yalnız aktif abone üretebilir. Free + trial bitmiş
  /// kullanıcı sayfayı açar ama üretemez.
  bool get canGenerateStudyContent => isPremium;

  /// Kalan günlük ücretsiz hak (premium ise -1 döner).
  Future<int> remainingToday() async {
    if (isPremium) return -1;
    final count = await _todayCount();
    final rem = kFreeQuotaPerDay - count;
    return rem < 0 ? 0 : rem;
  }

  /// Uygulama açılışında çağır — premium + trial durumunu yükler.
  Future<void> init() => refresh();

  /// Satın alma tamamlandığında veya oturum değiştiğinde çağır.
  Future<void> refresh() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final created = user.metadata.creationTime;
        _isInTrial = created != null &&
            DateTime.now().difference(created).inDays < 7;
      } else {
        _isInTrial = false;
      }
      final status = await PremiumStatus.read();
      _isPremiumSubscriber = status.isActive;
    } catch (e) {
      debugPrint('[AiQuotaService] refresh error: $e');
    }
  }

  /// Bu çağrı yapılabilir mi? False ise UI "günlük limit doldu" mesajı göstermeli.
  Future<bool> canUseAi() async {
    if (isPremium) return true;
    return (await _todayCount()) < kFreeQuotaPerDay;
  }

  /// Bir AI çağrısı gerçekleştiğinde çağır (premium ise no-op).
  Future<void> recordUsage() async {
    if (isPremium) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      if ((prefs.getString(_kDateKey) ?? '') != today) {
        await prefs.setString(_kDateKey, today);
        await prefs.setInt(_kCountKey, 1);
      } else {
        await prefs.setInt(_kCountKey, (_todayCountSync(prefs)) + 1);
      }
    } catch (e) {
      debugPrint('[AiQuotaService] recordUsage error: $e');
    }
  }

  // ── iç yardımcılar ──────────────────────────────────────────────────────────

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  Future<int> _todayCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getString(_kDateKey) ?? '') != _todayKey()) return 0;
      return prefs.getInt(_kCountKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  int _todayCountSync(SharedPreferences prefs) {
    if ((prefs.getString(_kDateKey) ?? '') != _todayKey()) return 0;
    return prefs.getInt(_kCountKey) ?? 0;
  }
}
