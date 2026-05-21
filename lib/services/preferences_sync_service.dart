// ═══════════════════════════════════════════════════════════════════════════════
//  PreferencesSyncService — Kullanıcı tercihlerinin merkezi cloud sync'i.
//
//  Şu ana kadar her tercih (dil, tema, bildirim, açılış ekranı) sadece
//  SharedPreferences'taydı → telefon değişince kayıp. Bu servis tek bir
//  Firestore doc'una (users/{uid}/preferences/main) hepsini yazar, yerelden
//  cloud'a otomatik sync eder ve yeni cihazda restore eder.
//
//  ŞEMA:
//    users/{uid}/preferences/main
//      locale: 'tr'/'en'/'de'/...
//      themeIndex: 0 (dark) | 1 (light) | 2 (system)
//      startupScreen: 'camera' | 'library'
//      notifications: {
//        master: bool
//        study_reminder: bool
//        streak_alert: bool
//        league_update: bool
//        premium_offer: bool
//        newsletter: bool
//      }
//      updatedAt: serverTimestamp
//
//  Kullanım:
//    1. main.dart bootstrap → PreferencesSyncService.restoreFromCloudIfEmpty()
//    2. Tercih değişiminde → PreferencesSyncService.syncFromLocal()
//
//  Tüm metotlar auth yoksa veya offline'da sessiz no-op.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesSyncService {
  PreferencesSyncService._();

  // Yerel SharedPref key'leri — diğer servisler ile uyumlu
  static const _kLocale = 'app_locale_v1';
  static const _kThemeIdx = 'theme_mode_index';
  static const _kStartup = 'startup_screen';
  static const _kNotifPrefix = 'notif_';
  static const _notifKeys = [
    'master',
    'study_reminder',
    'streak_alert',
    'league_update',
    'premium_offer',
    'newsletter',
  ];

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  static DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('preferences')
        .doc('main');
  }

  /// Yerel tercihleri Firestore'a yaz.
  /// UI tercihi değiştirdikten sonra fire-and-forget çağırılır.
  static Future<void> syncFromLocal() async {
    try {
      final doc = _doc;
      if (doc == null) return;
      final prefs = await SharedPreferences.getInstance();
      final notif = <String, bool>{};
      for (final key in _notifKeys) {
        notif[key] = prefs.getBool('$_kNotifPrefix$key') ?? true;
      }
      await doc.set({
        'locale': prefs.getString(_kLocale) ?? '',
        'themeIndex': prefs.getInt(_kThemeIdx) ?? 2,
        'startupScreen': prefs.getString(_kStartup) ?? 'camera',
        'notifications': notif,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Prefs] cloud sync fail: $e');
    }
  }

  /// Yerel boşsa cloud'dan restore — telefon değişti / uygulama yeniden yüklendi.
  /// Locale yoksa cloud'daki dili yereline yaz ve `true` döner.
  /// Çağıran (main.dart) true alırsa locale/theme servislerini yeniden init eder.
  static Future<bool> restoreFromCloudIfEmpty() async {
    try {
      final doc = _doc;
      if (doc == null) return false;
      final prefs = await SharedPreferences.getInstance();
      // Yerel boş kriteri: locale yok VE startup yok VE theme default (2)
      final hasLocale = (prefs.getString(_kLocale) ?? '').isNotEmpty;
      final hasStartup = (prefs.getString(_kStartup) ?? '').isNotEmpty;
      final hasTheme = prefs.containsKey(_kThemeIdx);
      if (hasLocale && hasStartup && hasTheme) return false;
      final snap = await doc.get();
      if (!snap.exists) return false;
      final m = snap.data() ?? const <String, dynamic>{};
      bool changed = false;
      final loc = (m['locale'] ?? '').toString();
      if (!hasLocale && loc.isNotEmpty) {
        await prefs.setString(_kLocale, loc);
        changed = true;
      }
      final theme = m['themeIndex'];
      if (!hasTheme && theme is num) {
        await prefs.setInt(_kThemeIdx, theme.toInt().clamp(0, 2));
        changed = true;
      }
      final startup = (m['startupScreen'] ?? '').toString();
      if (!hasStartup && startup.isNotEmpty) {
        await prefs.setString(_kStartup, startup);
        changed = true;
      }
      final notif = m['notifications'];
      if (notif is Map) {
        for (final key in _notifKeys) {
          final localKey = '$_kNotifPrefix$key';
          if (!prefs.containsKey(localKey) && notif[key] is bool) {
            await prefs.setBool(localKey, notif[key] as bool);
            changed = true;
          }
        }
      }
      if (changed) {
        debugPrint('[Prefs] cloud restore tamamlandı');
      }
      return changed;
    } catch (e) {
      debugPrint('[Prefs] cloud restore fail: $e');
      return false;
    }
  }

  /// Tek bir bildirim tercihini set et + cloud'a yaz.
  static Future<void> setNotificationPref(String key, bool value) async {
    if (!_notifKeys.contains(key)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kNotifPrefix$key', value);
    unawaited(syncFromLocal());
  }

  /// Bildirim tercihlerini okur — varsayılan true.
  static Future<Map<String, bool>> readNotificationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, bool>{};
    for (final k in _notifKeys) {
      out[k] = prefs.getBool('$_kNotifPrefix$k') ?? true;
    }
    return out;
  }
}
