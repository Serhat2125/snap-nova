// ═══════════════════════════════════════════════════════════════════════════
//  AccountService — Kullanıcının hesap tipini (öğrenci / ebeveyn / öğretmen)
//  saklar ve uygulama açılışında yönlendirme için kullanılır.
//
//  Storage: SharedPreferences (offline-first) + Firestore users/{uid}.accountType
//  ile senkronize. İlk seçimden sonra değişmez (değiştirmek için profil >
//  hesap tipini yeniden seç akışı gerekir — şu an MVP'de yok).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics.dart';

enum AccountType { student, parent, teacher }

extension AccountTypeX on AccountType {
  String get key {
    switch (this) {
      case AccountType.student: return 'student';
      case AccountType.parent: return 'parent';
      case AccountType.teacher: return 'teacher';
    }
  }

  String get tr {
    switch (this) {
      case AccountType.student: return 'Öğrenci';
      case AccountType.parent: return 'Ebeveyn';
      case AccountType.teacher: return 'Öğretmen';
    }
  }

  String get emoji {
    switch (this) {
      case AccountType.student: return '🎓';
      case AccountType.parent: return '👨‍👩‍👧';
      case AccountType.teacher: return '👨‍🏫';
    }
  }

  static AccountType fromKey(String? k) {
    switch (k) {
      case 'parent': return AccountType.parent;
      case 'teacher': return AccountType.teacher;
      case 'student':
      default: return AccountType.student;
    }
  }
}

class AccountService extends ChangeNotifier {
  AccountService._();
  static final AccountService instance = AccountService._();

  static const _kPrefKey = 'account_type_v1';
  static const _kBranchKey = 'teacher_branch_v1';
  AccountType _type = AccountType.student;
  String? _teacherBranch;
  bool _loaded = false;

  AccountType get type => _type;
  bool get isStudent => _type == AccountType.student;
  bool get isParent  => _type == AccountType.parent;
  bool get isTeacher => _type == AccountType.teacher;
  bool get loaded => _loaded;

  /// Öğretmenin branşı (hesap kurulumunda seçilir). null → henüz seçilmemiş.
  String? get teacherBranch => _teacherBranch;

  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefKey);
      _type = AccountTypeX.fromKey(raw);
      _teacherBranch = prefs.getString(_kBranchKey);
    } catch (_) {}
    _loaded = true;
    notifyListeners();
    _reportSegment();
    // Firestore'dan canlı senkronize et (eğer cloud'da farklıysa cloud kazanır).
    unawaited(_syncFromFirestore());
  }

  Future<void> _syncFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final cloudType = AccountTypeX.fromKey(
          snap.data()?['accountType'] as String?);
      final cloudBranch = snap.data()?['teacherBranch'] as String?;
      bool changed = false;
      if (cloudType != _type) {
        _type = cloudType;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kPrefKey, _type.key);
        } catch (_) {}
        changed = true;
      }
      if (cloudBranch != null && cloudBranch != _teacherBranch) {
        _teacherBranch = cloudBranch;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kBranchKey, cloudBranch);
        } catch (_) {}
        changed = true;
      }
      if (changed) {
        notifyListeners();
        _reportSegment();
      }
    } catch (e) {
      debugPrint('[AccountService] firestore sync fail: $e');
    }
  }

  /// Onboarding'de seçilen tipi kalıcı yaz — hem prefs hem Firestore.
  Future<void> setType(AccountType t) async {
    _type = t;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefKey, t.key);
    } catch (_) {}
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'accountType': t.key}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[AccountService] firestore set fail: $e');
      }
    }
    notifyListeners();
    _reportSegment();
  }

  /// Öğretmen profilini (görünen ad + branş) Firestore users/{uid}'e yazar.
  /// Hesap tipi ayrıca [setType] ile teacher yapılmalıdır.
  Future<void> saveTeacherProfile({
    required String username,
    required String branch,
  }) async {
    _teacherBranch = branch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBranchKey, branch);
    } catch (_) {}
    notifyListeners();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'teacherUsername': username,
        'teacherBranch': branch,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AccountService] teacher profile save fail: $e');
    }
  }

  /// Hesap tipi + kullanıcı + branşı analytics user-property olarak yazar.
  /// Böylece "kim (öğrenci/öğretmen/ebeveyn) neyi kullanıyor" dilimlenebilir.
  void _reportSegment() {
    Analytics.setUserId(FirebaseAuth.instance.currentUser?.uid);
    Analytics.setUserProperty('account_type', _type.key);
    if (_teacherBranch != null && _teacherBranch!.trim().isNotEmpty) {
      Analytics.setUserProperty('teacher_branch', _teacherBranch);
    }
  }

  Future<void> clear() async {
    _type = AccountType.student;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefKey);
    } catch (_) {}
    notifyListeners();
  }
}
