// ═══════════════════════════════════════════════════════════════════════════════
//  PomodoroStats — pomodoro / odak seanslarının kalıcı istatistiği.
//
//  İki kaynaktan veri alır:
//    • QuAlsar Mars Protokolü → her tamamlanan 25dk'lık fazı `recordFocusPhase`
//    • Yeşil Koloni → her tamamlanan focus oturumu `recordFocusPhase`
//
//  Saklananlar (SharedPreferences):
//    • total_phases  — tüm zamanlardaki toplam tamamlanmış focus fazı
//    • today_phases  — bugünkü tamamlanmış focus fazı
//    • today_date    — son güncelleme günü (gün değişimi tespiti için)
//    • streak_days   — peş peşe (en az 1 faz tamamlanan) gün sayısı
//    • last_focus_at — son focus tamamlama timestamp (ISO)
//    • mars_badges   — kazanılmış Mars rozetleri (CSV)
//    • colony_capsules — Yeşil Koloni toplam kapsül
//
//  Streak mantığı: bugün ilk faz tamamlanınca, dün de en az 1 faz olduysa
//  streak++; aksi halde streak=1. Ardışıklık gün başında kontrol edilir.
//
//  Tüm async API'lar UI'ı bloklamaz — SharedPreferences çağrıları kısa,
//  ekran tarafı `unawaited` ile çağırabilir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PomodoroStatsSnapshot {
  final int totalPhases;
  final int todayPhases;
  final int streakDays;
  final DateTime? lastFocusAt;
  final List<String> marsBadges;
  final int colonyCapsules;

  const PomodoroStatsSnapshot({
    required this.totalPhases,
    required this.todayPhases,
    required this.streakDays,
    required this.lastFocusAt,
    required this.marsBadges,
    required this.colonyCapsules,
  });

  static const empty = PomodoroStatsSnapshot(
    totalPhases: 0,
    todayPhases: 0,
    streakDays: 0,
    lastFocusAt: null,
    marsBadges: [],
    colonyCapsules: 0,
  );
}

class PomodoroStats {
  static const _kTotal = 'pomo_total_phases_v1';
  static const _kToday = 'pomo_today_phases_v1';
  static const _kTodayDate = 'pomo_today_date_v1';
  static const _kStreak = 'pomo_streak_days_v1';
  static const _kLastAt = 'pomo_last_focus_at_v1';
  static const _kMarsBadges = 'pomo_mars_badges_v1';
  static const _kColonyCapsules = 'pomo_colony_capsules_v1';

  /// Anlık snapshot — UI kart için. Gün değişimini de uygular (bugünkü
  /// counter sıfırlanır, ardışıklık zinciri kopmuşsa streak=0).
  static Future<PomodoroStatsSnapshot> read() async {
    final prefs = await SharedPreferences.getInstance();
    final total = prefs.getInt(_kTotal) ?? 0;
    int today = prefs.getInt(_kToday) ?? 0;
    int streak = prefs.getInt(_kStreak) ?? 0;
    final lastAtIso = prefs.getString(_kLastAt);
    final lastAt =
        lastAtIso == null ? null : DateTime.tryParse(lastAtIso);

    final storedDate = prefs.getString(_kTodayDate);
    final todayKey = _dayKey(DateTime.now());
    if (storedDate != todayKey) {
      // Yeni gün — bugünkü sayaç sıfırlanır. Ardışıklık: dün varsa korunur,
      // 2+ gün boşsa zincir kırıldı, streak=0.
      today = 0;
      if (storedDate != null) {
        final stored = DateTime.tryParse(storedDate);
        if (stored != null) {
          final diff = _daysBetween(stored, DateTime.now());
          if (diff >= 2) streak = 0;
        }
      }
    }

    final badges =
        (prefs.getStringList(_kMarsBadges) ?? const <String>[]);
    final capsules = prefs.getInt(_kColonyCapsules) ?? 0;

    return PomodoroStatsSnapshot(
      totalPhases: total,
      todayPhases: today,
      streakDays: streak,
      lastFocusAt: lastAt,
      marsBadges: badges,
      colonyCapsules: capsules,
    );
  }

  /// Tek bir tamamlanmış focus fazı kaydet. `durationSec` rozet eşikleri
  /// için kullanılır (Yeşil Koloni 25dk = 1500sn, Mars 5dk veya 25dk).
  static Future<PomodoroStatsSnapshot> recordFocusPhase({
    required int durationSec,
    String? badgeOnTotal,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final total = (prefs.getInt(_kTotal) ?? 0) + 1;
    int today = prefs.getInt(_kToday) ?? 0;
    int streak = prefs.getInt(_kStreak) ?? 0;
    final storedDate = prefs.getString(_kTodayDate);
    final todayKey = _dayKey(DateTime.now());
    if (storedDate != todayKey) {
      // Yeni gün açıldı; bugünkü = 1 (bu kayıt), streak güncelle.
      final wasYesterday = storedDate != null &&
          _daysBetween(DateTime.parse(storedDate), DateTime.now()) == 1;
      streak = wasYesterday ? streak + 1 : 1;
      today = 1;
    } else {
      today += 1;
      if (streak == 0) streak = 1;
    }
    await prefs.setInt(_kTotal, total);
    await prefs.setInt(_kToday, today);
    await prefs.setInt(_kStreak, streak);
    await prefs.setString(_kTodayDate, todayKey);
    await prefs.setString(_kLastAt, DateTime.now().toIso8601String());
    final snap = await read();
    unawaited(_cloudSync(snap));
    return snap;
  }

  /// Mars: bir aşama tamamlandığında rozet kazandır.
  ///   • mars_phase1 / mars_phase2 / mars_phase3 / mars_phase4
  ///   • mars_complete (4 aşama)
  ///   • streak_3 / streak_7 / streak_30
  ///   • total_10 / total_50 / total_100
  /// Yeni kazanılanları döner; UI bunlarla "Rozet kazandın" bildirimi gösterir.
  static Future<List<String>> awardBadges(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final existing =
        (prefs.getStringList(_kMarsBadges) ?? const <String>[]).toSet();
    final newOnes = <String>[];
    for (final id in ids) {
      if (existing.add(id)) newOnes.add(id);
    }
    if (newOnes.isNotEmpty) {
      await prefs.setStringList(_kMarsBadges, existing.toList());
      unawaited(_cloudSync(await read()));
    }
    return newOnes;
  }

  /// Yeşil Koloni: tamamlanan kapsül sayısını artır.
  static Future<int> incrementCapsule() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getInt(_kColonyCapsules) ?? 0) + 1;
    await prefs.setInt(_kColonyCapsules, v);
    unawaited(_cloudSync(await read()));
    return v;
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CLOUD SYNC — users/{uid}/pomodoro_stats/main
  //  Yerel her zaman kaynak; cloud yedek. Auth yoksa sessiz no-op.
  // ═══════════════════════════════════════════════════════════════════════

  static Future<void> _cloudSync(PomodoroStatsSnapshot s) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('pomodoro_stats')
          .doc('main')
          .set({
        'totalPhases': s.totalPhases,
        'todayPhases': s.todayPhases,
        'streakDays': s.streakDays,
        'lastFocusAt':
            s.lastFocusAt == null ? null : Timestamp.fromDate(s.lastFocusAt!),
        'marsBadges': s.marsBadges,
        'colonyCapsules': s.colonyCapsules,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[PomodoroStats] cloud sync fail: $e');
    }
  }

  /// Yerel boşsa cloud'dan geri yükle — bootstrap'ta çağrılır.
  /// Yeni cihaz/yeniden yükleme sonrası streak + toplam faz + rozet restore.
  static Future<bool> restoreFromCloudIfEmpty() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasLocal = (prefs.getInt(_kTotal) ?? 0) > 0;
      if (hasLocal) return false;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return false;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('pomodoro_stats')
          .doc('main')
          .get();
      if (!doc.exists) return false;
      final m = doc.data() ?? const <String, dynamic>{};
      final total = (m['totalPhases'] as num?)?.toInt() ?? 0;
      if (total == 0) return false;
      await prefs.setInt(_kTotal, total);
      await prefs.setInt(
          _kToday, (m['todayPhases'] as num?)?.toInt() ?? 0);
      await prefs.setInt(
          _kStreak, (m['streakDays'] as num?)?.toInt() ?? 0);
      final lastTs = m['lastFocusAt'];
      if (lastTs is Timestamp) {
        await prefs.setString(
            _kLastAt, lastTs.toDate().toIso8601String());
      }
      final badges = m['marsBadges'];
      if (badges is List) {
        await prefs.setStringList(
            _kMarsBadges, badges.map((e) => e.toString()).toList());
      }
      await prefs.setInt(_kColonyCapsules,
          (m['colonyCapsules'] as num?)?.toInt() ?? 0);
      debugPrint('[PomodoroStats] cloud restore tamamlandı');
      return true;
    } catch (e) {
      debugPrint('[PomodoroStats] cloud restore fail: $e');
      return false;
    }
  }

  /// Yeşil Koloni: O2 / capsule durumunu persist et (oturum durumu).
  static Future<void> saveColonySession({
    required int capsules,
    required double o2,
    required int session,
    required int timeLeft,
    required String mode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('colony_session_capsules', capsules);
    await prefs.setDouble('colony_session_o2', o2);
    await prefs.setInt('colony_session_idx', session);
    await prefs.setInt('colony_session_time_left', timeLeft);
    await prefs.setString('colony_session_mode', mode);
    await prefs.setString(
        'colony_session_when', DateTime.now().toIso8601String());
  }

  /// Açılışta önceki Koloni oturumunu döner (null ise yok).
  static Future<({int capsules, double o2, int session, int timeLeft, String mode})?>
      readColonySession() async {
    final prefs = await SharedPreferences.getInstance();
    final when = prefs.getString('colony_session_when');
    if (when == null) return null;
    final whenT = DateTime.tryParse(when);
    // 6 saatten eski oturumları geri yükleme.
    if (whenT == null ||
        DateTime.now().difference(whenT) > const Duration(hours: 6)) {
      return null;
    }
    return (
      capsules: prefs.getInt('colony_session_capsules') ?? 0,
      o2: prefs.getDouble('colony_session_o2') ?? 100,
      session: prefs.getInt('colony_session_idx') ?? 1,
      timeLeft: prefs.getInt('colony_session_time_left') ?? 0,
      mode: prefs.getString('colony_session_mode') ?? 'focus',
    );
  }

  static Future<void> clearColonySession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('colony_session_capsules');
    await prefs.remove('colony_session_o2');
    await prefs.remove('colony_session_idx');
    await prefs.remove('colony_session_time_left');
    await prefs.remove('colony_session_mode');
    await prefs.remove('colony_session_when');
  }

  static String _dayKey(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  static int _daysBetween(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return db.difference(da).inDays.abs();
  }
}

/// Rozet kataloğu — id → (emoji, başlık, açıklama).
class PomodoroBadge {
  final String id;
  final String emoji;
  final String title;
  final String desc;
  const PomodoroBadge(this.id, this.emoji, this.title, this.desc);
}

const pomodoroBadgeCatalog = <PomodoroBadge>[
  PomodoroBadge('mars_phase1', '🛸', 'İlk İniş',
      'Mars protokolünde 1. aşamayı tamamladın.'),
  PomodoroBadge('mars_phase2', '🌱', 'Sera Mühendisi',
      'Mars protokolünde 2. aşamayı tamamladın.'),
  PomodoroBadge('mars_phase3', '💧', 'Yaşam Destek',
      'Mars protokolünde 3. aşamayı tamamladın.'),
  PomodoroBadge('mars_phase4', '📡', 'İletişim Uzmanı',
      'Mars protokolünde 4. aşamayı tamamladın.'),
  PomodoroBadge('mars_complete', '🏅', 'Koloni Kurucusu',
      'Tüm Mars protokolünü baştan sona bitirdin.'),
  PomodoroBadge('streak_3', '🔥', '3 Gün Üst Üste', 'Üç gün ardışık odaklandın.'),
  PomodoroBadge('streak_7', '🔥🔥', '7 Gün Üst Üste',
      'Bir hafta boyunca her gün odaklandın.'),
  PomodoroBadge('streak_30', '🔥🔥🔥', '30 Gün Üst Üste',
      'Bir ay boyunca her gün odaklandın.'),
  PomodoroBadge('total_10', '🎯', '10 Odak Seansı',
      'Toplam 10 odak fazı tamamladın.'),
  PomodoroBadge('total_50', '🏆', '50 Odak Seansı',
      'Toplam 50 odak fazı tamamladın.'),
  PomodoroBadge('total_100', '👑', '100 Odak Seansı',
      'Yüzü gördün! 100 fazı bitirdin.'),
];

PomodoroBadge? findPomodoroBadge(String id) {
  for (final b in pomodoroBadgeCatalog) {
    if (b.id == id) return b;
  }
  return null;
}
