// ═══════════════════════════════════════════════════════════════════════════════
//  UserProfileService — Mevcut kullanıcının username/displayName/avatar'ını
//  uygulamanın HER yerinde tek bir kaynaktan okur ve canlı tutar.
//
//  Tasarım:
//   • SharedPreferences cache — uygulama açılır açılmaz (offline'da bile)
//     username görünür olsun. Firestore stream arkada güncel tutar.
//   • Firestore listener — kullanıcı başka cihazda profili değiştirirse
//     ya da bu cihazda profile sayfasından düzenlerse otomatik yansır.
//   • ChangeNotifier — UI `AnimatedBuilder` ile dinleyip rebuild eder.
//
//  Kullanım:
//    final p = UserProfileService.instance;
//    Text(p.username);            // sade görünüm — '@' YOK (C seçeneği)
//    Text(p.displayNameOrUsername); // ad varsa ad, yoksa username
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfileService extends ChangeNotifier {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  // ── State ─────────────────────────────────────────────────────────────────
  String _username = '';
  String _displayName = '';
  String _avatar = '👤';
  String _avatarData = ''; // base64 jpeg (varsa)
  String _statusMessage = '';
  String _email = '';

  bool _initialized = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  StreamSubscription<User?>? _authSub;

  // ── Pref keys ─────────────────────────────────────────────────────────────
  static const _kUsername = 'user_profile_username_v1';
  static const _kDisplayName = 'user_profile_display_name_v1';
  static const _kAvatar = 'user_profile_avatar_v1';
  static const _kAvatarData = 'user_profile_avatar_data_v1';
  static const _kStatus = 'user_profile_status_v1';
  static const _kEmail = 'user_profile_email_v1';

  // ── Public getters ────────────────────────────────────────────────────────
  String get username => _username;
  String get displayName => _displayName;
  String get avatar => _avatar;
  String get avatarData => _avatarData;
  String get statusMessage => _statusMessage;
  String get email => _email;

  /// Görünür isim — varsa ad, yoksa username, hiçbiri yoksa 'Kullanıcı'.
  String get displayNameOrUsername {
    if (_displayName.isNotEmpty) return _displayName;
    if (_username.isNotEmpty) return _username;
    return 'Kullanıcı';
  }

  bool get hasUsername => _username.isNotEmpty;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1) SharedPreferences cache'inden hemen yükle (offline OK).
    try {
      final prefs = await SharedPreferences.getInstance();
      _username = prefs.getString(_kUsername) ?? '';
      _displayName = prefs.getString(_kDisplayName) ?? '';
      _avatar = prefs.getString(_kAvatar) ?? '👤';
      _avatarData = prefs.getString(_kAvatarData) ?? '';
      _statusMessage = prefs.getString(_kStatus) ?? '';
      _email = prefs.getString(_kEmail) ?? '';
      notifyListeners();
    } catch (e) {
      debugPrint('[UserProfile] cache load fail: $e');
    }

    // 2) Auth state dinleyici — login/logout değişimlerinde dinleyicileri
    // yenile. Firebase app'i yoksa (örn. web config'i henüz üretilmedi)
    // FirebaseAuth.instance SENKRON fırlatır ve init'i kırardı — atla,
    // cache'ten yüklenen profil yeterli.
    try {
      if (Firebase.apps.isEmpty) return;
      _authSub?.cancel();
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        _attachFirestoreListener(user?.uid);
      });
      _attachFirestoreListener(FirebaseAuth.instance.currentUser?.uid);
    } catch (e) {
      debugPrint('[UserProfile] auth listener kurulamadı: $e');
    }
  }

  /// Belirli uid için Firestore listener bağla. uid null ise dinleyici durur
  /// ama cache korunur (offline davet kodu gibi).
  void _attachFirestoreListener(String? uid) {
    _docSub?.cancel();
    if (uid == null) return;
    _docSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      _username = (data['username'] ?? _username).toString();
      _displayName = (data['displayName'] ?? _displayName).toString();
      _avatar = (data['avatar'] ?? _avatar).toString();
      _avatarData = (data['avatarData'] ?? _avatarData).toString();
      _statusMessage = (data['statusMessage'] ?? _statusMessage).toString();
      _email = (data['email'] ?? _email).toString();
      await _persistCache();
      notifyListeners();
    }, onError: (e) {
      debugPrint('[UserProfile] firestore stream error: $e');
    });
  }

  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUsername, _username);
      await prefs.setString(_kDisplayName, _displayName);
      await prefs.setString(_kAvatar, _avatar);
      await prefs.setString(_kAvatarData, _avatarData);
      await prefs.setString(_kStatus, _statusMessage);
      await prefs.setString(_kEmail, _email);
    } catch (e) {
      debugPrint('[UserProfile] cache save fail: $e');
    }
  }

  /// Profil sayfası vs. yerel düzenleme yaptığında çağrılır. Firestore'a
  /// upsert yapılması için FriendService.upsertMyProfile beklenir; bu metod
  /// yalnızca lokal cache'i hemen günceller (UI gecikme olmasın).
  Future<void> updateLocalCache({
    String? username,
    String? displayName,
    String? avatar,
    String? avatarData,
    String? statusMessage,
    String? email,
  }) async {
    if (username != null) _username = username;
    if (displayName != null) _displayName = displayName;
    if (avatar != null) _avatar = avatar;
    if (avatarData != null) _avatarData = avatarData;
    if (statusMessage != null) _statusMessage = statusMessage;
    if (email != null) _email = email;
    await _persistCache();
    notifyListeners();
  }

  /// Logout sırasında local cache temizlenir.
  Future<void> clear() async {
    _username = '';
    _displayName = '';
    _avatar = '👤';
    _avatarData = '';
    _statusMessage = '';
    _email = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUsername);
      await prefs.remove(_kDisplayName);
      await prefs.remove(_kAvatar);
      await prefs.remove(_kAvatarData);
      await prefs.remove(_kStatus);
      await prefs.remove(_kEmail);
    } catch (_) {}
    _docSub?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _docSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
