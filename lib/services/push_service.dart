// ═══════════════════════════════════════════════════════════════════════════════
//  PushService — Firebase Cloud Messaging + local notifications.
//
//  Akış:
//    1. App açılırken init() — permission + token yazma + listener'lar.
//    2. FCM token `users/{uid}/fcmTokens/{token}` doc'una yazılır (multi-device).
//    3. Foreground: gelen RemoteMessage → flutter_local_notifications ile UI.
//       Arka plan / kapalı: Android sistem bildirimi (FCM default davranışı).
//    4. Bildirime tıklanma → main.dart navigator key üzerinden ilgili sayfaya
//       (arkadaşlık isteği → inbox; düello → arena lobi).
//
//  Cloud Function tarafı (functions/src/push_on_notification.ts):
//    notifications/{uid}/items/{nid} onCreate trigger →
//      users/{uid}/fcmTokens altındaki tokenları çek → multicast push.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../firebase_options.dart';
import 'app_settings_service.dart';

/// Top-level background message handler — data-only push'lar için.
/// Android ve iOS arka planda app suspended'ken bile çağrılır.
/// İçinde Firebase'i tekrar init etmek gerekir (yeni isolate'de çalışır).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    debugPrint('[Push.bg] msg=${message.messageId} type=${message.data["type"]}');
    // notifications/{uid}/items doc'u zaten Cloud Function tarafından
    // FCM trigger'la yazılıyor; bu handler sadece data-only push'lar için
    // gerekirse local notification göstermek için kullanılabilir.
  } catch (e) {
    debugPrint('[Push.bg] error: $e');
  }
}

class PushService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'qualsar_default',
    'QuAlsar Bildirimleri',
    description: 'Arkadaş istekleri, düello daveti, sıralama değişiklikleri',
    importance: Importance.high,
  );
  static bool _initialized = false;

  /// Uygulama açılışında main.dart tarafından çağrılır.
  /// Firebase başlatılmadan ÖNCE çağrılırsa sessizce no-op.
  static Future<void> init({
    void Function(Map<String, dynamic> payload)? onTap,
  }) async {
    if (_initialized) return;
    try {
      // Zamanlanmış yerel bildirimler (sınav geri sayımı) için timezone DB.
      try {
        tzdata.initializeTimeZones();
      } catch (_) {}
      // Background handler — uygulama kapalı/arka plandayken gelen
      // data-only push'lar için. notification: payload'lu mesajları
      // OS otomatik gösterir; bu handler ek mantık için.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // ── İzin (iOS + Android 13+) ─────────────────────────────────────────
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[Push] permission: ${settings.authorizationStatus}');

      // ── Local notifications channel (Android) ────────────────────────────
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (resp) {
          // Bildirime tıklanma — payload string'i Map'e parse et
          final payload = resp.payload;
          if (payload == null || payload.isEmpty) return;
          // Basit key=value ayrıştırma (push trigger function aynı formatı yazar)
          final map = <String, dynamic>{};
          for (final part in payload.split('&')) {
            final kv = part.split('=');
            if (kv.length == 2) map[kv[0]] = kv[1];
          }
          onTap?.call(map);
        },
      );
      if (Platform.isAndroid) {
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);
      }

      // ── Foreground listener: kendimiz UI gösteriyoruz ────────────────────
      FirebaseMessaging.onMessage.listen((msg) {
        final notif = msg.notification;
        final data = msg.data;
        final title = notif?.title ?? data['title']?.toString() ?? 'QuAlsar';
        final body = notif?.body ?? data['body']?.toString() ?? '';
        if (body.isEmpty) return;
        final payload = data.entries.map((e) => '${e.key}=${e.value}').join('&');
        // showLocal üzerinden → master + kategori + sessiz saatler uygulanır.
        showLocal(
          title: title,
          body: body,
          payload: payload,
          id: msg.hashCode,
          type: data['type']?.toString(),
        );
      });

      // ── Bildirimden açılma (background → foreground transition) ──────────
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        if (onTap != null) onTap(Map<String, dynamic>.from(msg.data));
      });
      final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMsg != null && onTap != null) {
        onTap(Map<String, dynamic>.from(initialMsg.data));
      }

      // ── Token kayıt + auth state listener ────────────────────────────────
      await _persistToken();
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => _persistToken());
      FirebaseAuth.instance.authStateChanges().listen((_) => _persistToken());

      _initialized = true;
    } catch (e) {
      debugPrint('[Push] init fail: $e');
    }
  }

  /// FCM token'ı kullanıcının fcmTokens alt koleksiyonuna yazar.
  /// Token doc id'si = token kendisi (idempotent, aynı cihazda overwrite).
  static Future<void> _persistToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('[Push] token persisted');
    } catch (e) {
      debugPrint('[Push] persist token fail: $e');
    }
  }

  /// Anlık local notification göster — push trigger gerek olmadan
  /// kullanıcıya uyarı (örn. "Hâlâ burada mısın?" idle warning).
  /// Foreground'da da görünür; AppDelegate alert/badge/sound izinleri zaten
  /// Bildirim türünü ayar kategorisine eşler (sunucudaki categoryForType ile
  /// AYNI — foreground gating için). Eşi yoksa null → yalnız master gate'lenir.
  static String? _categoryForType(String? type) {
    switch (type) {
      case 'friend_request':
      case 'friend_accepted':
      case 'referral_joined':
      case 'referral_complete':
        return 'friend_request';
      case 'duelo_invite':
        return 'duello_invite';
      case 'rank_passed':
        return 'league_update';
      case 'streak_milestone':
        return 'streak_alert';
      // Cihaz-içi hatırlatıcılar — tip = kategori anahtarı (identity).
      case 'study_reminder':
        return 'study_reminder';
      case 'streak_alert':
        return 'streak_alert';
      case 'exam_countdown':
        return 'exam_countdown';
      case 'achievement':
        return 'achievement';
      case 'homework_submission':
        return 'homework_submission';
      case 'student_joined':
        return 'student_joined';
      case 'class_activity':
      case 'class_announcement':
      case 'announcement':
      case 'homework_published':
      case 'homework_all_done':
      case 'material':
        return 'class_activity';
      default:
        return null;
    }
  }

  /// init() içinde alındı.
  static Future<void> showLocal({
    required String title,
    required String body,
    String? payload,
    int id = 0xFA001,
    String? type,
  }) async {
    // Ana anahtar + kategori kontrolü — "Tüm bildirimler" kapalıysa ya da bu
    // bildirim türünün kategorisi kapalıysa gösterme (kanonik: notif_master,
    // notif_<kategori>). Foreground push da bu yoldan geçer → ayarlar uygulanır.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('notif_master') == false) {
        debugPrint('[Push] tüm bildirimler kapalı — atlandı: $title');
        return;
      }
      final cat = _categoryForType(type);
      if (cat != null && prefs.getBool('notif_$cat') == false) {
        debugPrint('[Push] kategori kapalı ($cat) — atlandı: $title');
        return;
      }
    } catch (_) {/* pref okunamadı → göster */}
    // Sessiz Saatler kontrolü — kullanıcı belirli aralık tanımlamışsa
    // o aralıkta hiçbir bildirim göstermeyiz.
    if (AppSettingsService.instance.inQuietHours) {
      debugPrint('[Push] sessiz saatlerde — bildirim atlandı: $title');
      return;
    }
    try {
      await _local.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[Push] showLocal fail: $e');
    }
  }

  // ── Zamanlanmış yerel bildirimler (hatırlatıcılar) ─────────────────────────
  // Gating SCHEDULE anında yapılır (kapalıysa hiç planlanmaz); ayar değişince
  // çağıran (LocalReminderService) yeniden planlar.

  /// master + kategori açık mı?
  static Future<bool> _allowed(String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('notif_master') == false) return false;
      final cat = _categoryForType(type);
      if (cat != null && prefs.getBool('notif_$cat') == false) return false;
    } catch (_) {}
    return true;
  }

  static NotificationDetails _details() => NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id, _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high, priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      );

  /// Günlük tekrar eden hatırlatma (çalışma/seri). Belirli saat değil, ilk
  /// planlamadan itibaren ~24 saatte bir (timezone gerektirmez).
  static Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required String type,
  }) async {
    await cancelScheduled(id);
    if (!await _allowed(type)) return;
    try {
      await _local.periodicallyShow(
        id, title, body, RepeatInterval.daily, _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'type=$type',
      );
    } catch (e) {
      debugPrint('[Push] scheduleDaily fail: $e');
    }
  }

  /// Belirli bir ana zamanlanmış tek seferlik hatırlatma (sınav geri sayımı).
  /// Mutlak-an (tz.UTC) kullanır → cihaz IANA zonu gerekmez, doğru anda atar.
  static Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required String type,
    required DateTime when,
  }) async {
    await cancelScheduled(id);
    if (when.isBefore(DateTime.now())) return;
    if (!await _allowed(type)) return;
    try {
      final scheduled = tz.TZDateTime.from(when.toUtc(), tz.UTC);
      await _local.zonedSchedule(
        id, title, body, scheduled, _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'type=$type',
      );
    } catch (e) {
      debugPrint('[Push] scheduleAt fail: $e');
    }
  }

  static Future<void> cancelScheduled(int id) async {
    try {
      await _local.cancel(id);
    } catch (_) {}
  }

  /// Logout sırasında çağrılır — bu cihazın token'ı silinir.
  static Future<void> clearTokenOnLogout() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .delete();
    } catch (e) {
      debugPrint('[Push] clear token fail: $e');
    }
  }
}
