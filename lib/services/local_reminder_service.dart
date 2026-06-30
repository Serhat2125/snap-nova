// ═══════════════════════════════════════════════════════════════════════════
//  LocalReminderService — Öğrenci bildirim kategorilerinin gerçek üreticisi.
//
//  Bu servis, ayar ekranındaki şu toggle'ları "canlandırır":
//    • study_reminder  → günlük çalışma hatırlatıcısı (tekrarlı)
//    • streak_alert    → günlük seri koruma hatırlatması (tekrarlı)
//    • exam_countdown  → yaklaşan resmi sınavlardan 1 gün önce (tek seferlik)
//    • achievement     → yeni rozet açıldığında anlık bildirim
//
//  Gating: PushService.scheduleX/showLocal master + kategori tercihini
//  kontrol eder; ayrıca planlama YALNIZCA ayar açıkken yapılır. Tercih
//  değişince çağıran rescheduleAll() ile yeniden planlar.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/exam_dates.dart';
import 'achievement_service.dart';
import 'push_service.dart';
import 'runtime_translator.dart';

class LocalReminderService {
  LocalReminderService._();

  static const _idStudy = 0xFB001;
  static const _idStreak = 0xFB002;
  static const _examBase = 0xFB100; // _examBase + index
  static const _examMax = 8;
  static const _kNotified = 'notified_achievements_v1';

  /// Tüm öğrenci hatırlatıcılarını (yeniden) planlar. Kapalı kategori
  /// planlanmaz (PushService gate'ler). Öğretmen için çağrılmaz.
  static Future<void> rescheduleAll() async {
    // Çalışma hatırlatıcısı (günlük tekrar)
    await PushService.scheduleDaily(
      id: _idStudy,
      type: 'study_reminder',
      title: 'Çalışma zamanı 📚'.tr(),
      body: 'Bugünkü hedefini tamamlamayı unutma!'.tr(),
    );
    // Seri koruma (günlük tekrar)
    await PushService.scheduleDaily(
      id: _idStreak,
      type: 'streak_alert',
      title: 'Serini koru 🔥'.tr(),
      body: 'Bugün de çalışarak çalışma serini sürdür.'.tr(),
    );
    // Sınav geri sayımı — yaklaşan sınavlardan 1 gün önce 18:00.
    for (int i = 0; i < _examMax; i++) {
      await PushService.cancelScheduled(_examBase + i);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final country =
          (prefs.getString('mini_test_country') ?? 'tr').toUpperCase();
      final exams = upcomingExamsForCountry(country);
      var i = 0;
      for (final e in exams) {
        if (i >= _examMax) break;
        final d = e.date.subtract(const Duration(days: 1));
        final remindAt = DateTime(d.year, d.month, d.day, 18, 0);
        await PushService.scheduleAt(
          id: _examBase + i,
          type: 'exam_countdown',
          title: 'Sınav yaklaşıyor ⏰'.tr(),
          body: '${e.fullTitle} — yarın!'.tr(),
          when: remindAt,
        );
        i++;
      }
    } catch (_) {/* sınav verisi okunamadı → atla */}
  }

  /// Hatırlatıcıları tamamen iptal eder (öğretmen hesabı / çıkış).
  static Future<void> cancelAll() async {
    await PushService.cancelScheduled(_idStudy);
    await PushService.cancelScheduled(_idStreak);
    for (int i = 0; i < _examMax; i++) {
      await PushService.cancelScheduled(_examBase + i);
    }
  }

  /// Yeni açılan rozetleri bildir. Önceki bildirilenlerle karşılaştırır;
  /// sadece YENİ açılanlar için anlık bildirim atar (ilk çalıştırmada spam yok).
  static Future<void> syncAchievements() async {
    try {
      final list = await AchievementService.compute();
      final prefs = await SharedPreferences.getInstance();
      final unlocked = list.where((a) => a.unlocked).toList();
      final unlockedIds = unlocked.map((a) => a.id.name).toSet();

      final hasRecord = prefs.containsKey(_kNotified);
      final notified =
          (prefs.getStringList(_kNotified) ?? const <String>[]).toSet();

      // İlk kez: mevcut açık rozetleri sessizce kaydet (geçmişi bildirme).
      if (!hasRecord) {
        await prefs.setStringList(_kNotified, unlockedIds.toList());
        return;
      }
      for (final a in unlocked) {
        if (!notified.contains(a.id.name)) {
          await PushService.showLocal(
            title: '🏆 ${'Yeni rozet!'.tr()}',
            body: '${a.emoji} ${a.name}',
            type: 'achievement',
          );
        }
      }
      await prefs.setStringList(_kNotified, unlockedIds.toList());
    } catch (_) {/* sessizce geç */}
  }
}
