// ═══════════════════════════════════════════════════════════════════════════
//  AccountService — Kullanıcının hesap tipini (öğrenci / ebeveyn / öğretmen)
//  saklar ve uygulama açılışında yönlendirme için kullanılır.
//
//  Storage: SharedPreferences (offline-first) + Firestore users/{uid}.accountType
//  ile senkronize. Rol DEĞİŞTİRİLEBİLİR: aynı e-posta ile öğrenci/öğretmen/
//  ebeveyn arasında geçilebilir (onboarding'de yeniden seçim veya panel >
//  "Hesap tipini değiştir"). Veriler uid+koleksiyon bazlı ayrı tutulduğundan
//  rol geçişi mevcut verileri silmez — eski role dönülünce geri gelir.
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
  static const _kLevelKey = 'teacher_level_v1';
  static const _kPhotoKey = 'teacher_photo_path_v1';
  static const _kStatusKey = 'teacher_status_v1';
  static const _kGradingKey = 'teacher_grading_country_v1';
  static const _kGradingProfileKey = 'teacher_grading_profile_v1';
  AccountType _type = AccountType.student;
  String? _teacherBranch;
  String? _teacherLevel;
  String? _teacherPhotoPath;
  String? _teacherStatus;
  String? _gradingCountry;
  String? _gradingProfile;
  bool _loaded = false;

  AccountType get type => _type;
  bool get isStudent => _type == AccountType.student;
  bool get isParent  => _type == AccountType.parent;
  bool get isTeacher => _type == AccountType.teacher;
  bool get loaded => _loaded;

  /// Öğretmenin branşı (hesap kurulumunda seçilir). null → henüz seçilmemiş.
  String? get teacherBranch => _teacherBranch;

  /// Öğretmenin öğrettiği eğitim seviyesi (İlkokul/Ortaokul/Lise/Üniversite).
  String? get teacherLevel => _teacherLevel;

  /// Öğretmenin profil fotoğrafı (yerel dosya yolu). null → emoji göster.
  String? get teacherPhotoPath => _teacherPhotoPath;

  /// Öğretmenin durum mesajı (örn: "10. sınıf fizik öğretmeni").
  String? get teacherStatus => _teacherStatus;

  /// Öğretmenin not sistemi/müfredat ülke kodu (ör. 'TR','US','DE').
  /// null → henüz seçilmemiş (TeacherShellScreen açılışında seçtirilir).
  String? get gradingCountry => _gradingCountry;

  /// Öğretmenin seçtiği TAM profil kimliği (ör. 'us' veya 'gpa4' — ikisi de
  /// countryCode='US'). countryCode tek başına aynı ülkede birden fazla
  /// profili ayırt edemiyor (bkz. grading_config.dart kCountryToProfile);
  /// bu alan olmadan "GPA 4.0" seçimi sessizce "USA (Weighted)"e dönüşürdü.
  String? get gradingProfile => _gradingProfile;

  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefKey);
      _type = AccountTypeX.fromKey(raw);
      _teacherBranch = prefs.getString(_kBranchKey);
      _teacherLevel = prefs.getString(_kLevelKey);
      _teacherPhotoPath = prefs.getString(_kPhotoKey);
      _teacherStatus = prefs.getString(_kStatusKey);
      _gradingCountry = prefs.getString(_kGradingKey);
      _gradingProfile = prefs.getString(_kGradingProfileKey);
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
      final rawCloudType = (snap.data()?['accountType'] as String?)?.trim();
      final cloudBranch = snap.data()?['teacherBranch'] as String?;
      bool changed = false;
      // KRİTİK: Cloud'da accountType alanı YOKSA fromKey(null) → student döner
      // ve yereldeki teacher/parent'ı ezerdi. Bu, anonim→e-posta uid geçişinde
      // öğretmeni sessizce öğrenciye düşürüp her açılışta yanlış ekrana atıyordu.
      // Çözüm: cloud yalnızca GERÇEK bir değer taşıyorsa kazanır; aksi halde
      // yereldeki tipi cloud'a geri yazıp (uid göçü onarımı) koru.
      if (rawCloudType != null && rawCloudType.isNotEmpty) {
        final cloudType = AccountTypeX.fromKey(rawCloudType);
        if (cloudType != _type) {
          _type = cloudType;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kPrefKey, _type.key);
          } catch (_) {}
          changed = true;
        }
      } else if (_type != AccountType.student) {
        // Cloud boş ama yerelde teacher/parent var → yereli cloud'a taşı.
        unawaited(setType(_type));
      }
      if (cloudBranch != null && cloudBranch != _teacherBranch) {
        _teacherBranch = cloudBranch;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kBranchKey, cloudBranch);
        } catch (_) {}
        changed = true;
      }
      final cloudLevel = snap.data()?['teacherLevel'] as String?;
      if (cloudLevel != null && cloudLevel != _teacherLevel) {
        _teacherLevel = cloudLevel;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kLevelKey, cloudLevel);
        } catch (_) {}
        changed = true;
      }
      final cloudGrading = snap.data()?['gradingCountry'] as String?;
      if (cloudGrading != null && cloudGrading != _gradingCountry) {
        _gradingCountry = cloudGrading;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kGradingKey, cloudGrading);
        } catch (_) {}
        changed = true;
      }
      final cloudGradingProfile = snap.data()?['gradingProfile'] as String?;
      if (cloudGradingProfile != null &&
          cloudGradingProfile != _gradingProfile) {
        _gradingProfile = cloudGradingProfile;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kGradingProfileKey, cloudGradingProfile);
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

  /// Cloud'daki (users/{uid}.accountType) kayıtlı hesap tipini okur.
  /// null → alan hiç yazılmamış, oturum yok veya okuma başarısız (fail-open:
  /// offline'da seçim engellenmez; cloud-wins sync sonradan düzeltir).
  ///
  /// ROL KİLİDİ için kullanılır: aynı e-posta ile tekrar giriş yapan kullanıcı
  /// onboarding'de farklı bir rol seçerse setType() mevcut rolü sessizce
  /// ezmesin diye çağıran taraf önce bunu kontrol eder.
  Future<AccountType?> fetchCloudType() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final raw = (snap.data()?['accountType'] as String?)?.trim();
      if (raw == null || raw.isEmpty) return null;
      return AccountTypeX.fromKey(raw);
    } catch (e) {
      debugPrint('[AccountService] fetchCloudType fail: $e');
      return null;
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

  /// Öğretmenin branş ve/veya öğrettiği seviyesini profilden günceller.
  /// Yalnızca verilen alanlar değişir (null → dokunulmaz). Hem yerel
  /// (prefs) hem Firestore users/{uid} güncellenir; teacherUsername'e dokunmaz.
  Future<void> updateTeacherProfile({String? branch, String? level}) async {
    if (branch != null) _teacherBranch = branch;
    if (level != null) _teacherLevel = level;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (branch != null) await prefs.setString(_kBranchKey, branch);
      if (level != null) await prefs.setString(_kLevelKey, level);
    } catch (_) {}
    notifyListeners();
    _reportSegment();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        if (branch != null) 'teacherBranch': branch,
        if (level != null) 'teacherLevel': level,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AccountService] updateTeacherProfile fail: $e');
    }
  }

  /// Öğretmenin not sistemi/müfredat ülke kodunu kalıcı yazar (prefs+Firestore).
  Future<void> setGradingCountry(String countryCode) async {
    _gradingCountry = countryCode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGradingKey, countryCode);
    } catch (_) {}
    notifyListeners();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'gradingCountry': countryCode,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AccountService] setGradingCountry fail: $e');
    }
  }

  /// Öğretmenin seçtiği TAM profil kimliğini kalıcı yazar (prefs+Firestore).
  /// setGradingCountry ile BİRLİKTE çağrılmalı — aynı ülkede birden fazla
  /// profil olabildiği için (US → us/gpa4) countryCode tek başına yetmez.
  Future<void> setGradingProfile(String profileId) async {
    _gradingProfile = profileId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGradingProfileKey, profileId);
    } catch (_) {}
    notifyListeners();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'gradingProfile': profileId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AccountService] setGradingProfile fail: $e');
    }
  }

  /// Öğretmenin profil fotoğrafı yolunu ve/veya durum mesajını kalıcı yazar.
  /// Yalnızca verilen alanlar güncellenir (null → değişmez).
  Future<void> saveTeacherPresentation({
    String? photoPath,
    String? status,
  }) async {
    if (photoPath != null) _teacherPhotoPath = photoPath;
    if (status != null) _teacherStatus = status;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (photoPath != null) await prefs.setString(_kPhotoKey, photoPath);
      if (status != null) await prefs.setString(_kStatusKey, status);
    } catch (_) {}
    notifyListeners();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        if (status != null) 'teacherStatus': status,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AccountService] teacher presentation save fail: $e');
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
