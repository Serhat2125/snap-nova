import 'dart:async';
import 'dart:convert';
import 'error_logger.dart';
import 'friend_service.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  AuthService — Çoklu sağlayıcılı kimlik doğrulama
//
//  TASARIM NOTU:
//  Şu an gerçek FirebaseAuth + Google Sign-In + Apple Sign-In + Email/Şifre
//  entegrasyonları aktif. Sadece misafir (guest) ve telefon doğrulama placeholder
//  (telefon verifyCode akışı stub — gerçek SMS doğrulama Firebase Phone Auth ile).
//
//  Platform tarafı önkoşullar:
//   • Android: Release SHA-1 / SHA-256 → Firebase Console'a eklenmiş olmalı;
//              google-services.json yerleşik.
//   • iOS:     Info.plist URL schemes (Google client id) + GoogleService-Info.plist
//              + Apple Sign In capability eklenmeli.
//   • Apple Sign In: iOS 13+; entitlements; Apple Developer Console'da etkin.
// ═══════════════════════════════════════════════════════════════════════════════

enum AuthProvider { google, apple, microsoft, phone, email, guest }

extension AuthProviderX on AuthProvider {
  String get id => switch (this) {
        AuthProvider.google    => 'google',
        AuthProvider.apple     => 'apple',
        AuthProvider.microsoft => 'microsoft',
        AuthProvider.phone     => 'phone',
        AuthProvider.email     => 'email',
        AuthProvider.guest     => 'guest',
      };

  static AuthProvider fromId(String id) => switch (id) {
        'google'    => AuthProvider.google,
        'apple'     => AuthProvider.apple,
        'microsoft' => AuthProvider.microsoft,
        'phone'     => AuthProvider.phone,
        'email'     => AuthProvider.email,
        _           => AuthProvider.guest,
      };
}

class AppUser {
  final String id;
  final String? name;
  final String? email;
  final String? photoUrl;
  final AuthProvider provider;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.provider,
    required this.createdAt,
    this.name,
    this.email,
    this.photoUrl,
  });

  bool get isGuest => provider == AuthProvider.guest;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
        'provider': provider.id,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString(),
        email: j['email']?.toString(),
        photoUrl: j['photoUrl']?.toString(),
        provider: AuthProviderX.fromId(j['provider']?.toString() ?? 'guest'),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class AuthException implements Exception {
  final String message;
  final String code;
  const AuthException(this.code, this.message);
  @override
  String toString() => 'AuthException($code): $message';
}

class AuthService {
  static const _kUserKey = 'auth_user_v1';

  static AppUser? _current;
  static AppUser? get current => _current;
  static bool get isSignedIn => _current != null;

  /// `Firebase.initializeApp` başarıyla tamamlandı mı? main.dart başlatma
  /// sırasında set eder. Telefon doğrulama gibi Firebase'e bağımlı akışlar
  /// bunu kontrol edip, false ise kullanıcıya net mesaj gösterir.
  static bool firebaseReady = false;

  static final _changes = StreamController<AppUser?>.broadcast();
  static Stream<AppUser?> get onChange => _changes.stream;

  /// Uygulama açılışında çağırın — saklı kullanıcıyı bellekteki state'e yükler.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kUserKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _current = AppUser.fromJson(m);
      _changes.add(_current);
    } catch (e) {
      debugPrint('[Auth] init error: $e');
    }
  }

  static Future<AppUser> _persist(AppUser u) async {
    _current = u;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUserKey, jsonEncode(u.toJson()));
    } catch (e) {
      debugPrint('[Auth] persist error: $e');
    }
    // Friends sistemi için Firestore'a public profil yaz (idempotent).
    // Username yoksa email/name'den türetilir; kullanıcı sonradan değiştirebilir.
    unawaited(_writePublicProfile(u));
    _changes.add(u);
    return u;
  }

  /// users/{uid} public profile — FriendService araması ve arkadaşlık için.
  /// Kullanıcı `user_username_v1` pref'inde bir username KAYDETMİŞSE
  /// (yani onboarding'deki _UsernameCreateSheet'i tamamlamışsa) tam profil
  /// upsert edilir. AKSİ TAKDİRDE `username` alanı yazılmaz — bu sayede
  /// onboarding'in _needsUsernameSetup kontrolü username sheet'ini açar.
  /// Eskiden burada email/name'den otomatik username türetiliyordu; bu
  /// kullanıcının kendi adını seçmesini engelliyordu (sheet hiç açılmıyordu).
  static Future<void> _writePublicProfile(AppUser u) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('user_username_v1');
      final avatar = (u.photoUrl != null && u.photoUrl!.isNotEmpty)
          ? u.photoUrl!
          : _avatarEmojiFor(u.id);
      if (saved != null && saved.length >= 3) {
        // Kullanıcı zaten bir username belirlemiş → tam profil upsert.
        await FriendService.upsertMyProfile(
          username: saved,
          displayName: u.name ?? saved,
          avatar: avatar,
          email: u.email,
        );
      } else {
        // Username yok → username alanı YAZILMAZ; onboarding sheet'i açılır.
        // Yine de avatar/email/lastSeen güncellenir.
        final payload = <String, dynamic>{
          'avatar': avatar,
          if (u.name != null && u.name!.isNotEmpty) 'displayName': u.name,
          if (u.email != null && u.email!.isNotEmpty)
            'email': u.email!.trim().toLowerCase(),
          'lastSeen': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        };
        await FirebaseFirestore.instance
            .collection('users')
            .doc(u.id)
            .set(payload, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[Auth] public profile write fail: $e');
    }
  }

  static String _avatarEmojiFor(String uid) {
    const pool = ['🦁', '🐯', '🐺', '🦊', '🐼', '🐨', '🐸', '🦄', '🐲', '🦅'];
    return pool[uid.hashCode.abs() % pool.length];
  }

  static String _genId(String prefix) {
    final rng = math.Random();
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = rng.nextInt(0xFFFFFF).toRadixString(36).padLeft(4, '0');
    return '${prefix}_${t}_$r';
  }

  // ── GOOGLE ────────────────────────────────────────────────────────────────
  // google_sign_in plugin'i platform sheet'i açar (Android: GoogleSignIn,
  // iOS: ASAuthorizationController). Sonra Firebase credential ile sign-in.
  static Future<AppUser> signInWithGoogle() async {
    if (!firebaseReady) {
      throw const AuthException(
          'firebase-not-configured',
          'Google girişi için Firebase yapılandırılmamış. '
          'Terminalde "flutterfire configure" çalıştır + Firebase Console\'da '
          'Google sign-in provider\'ı aktive et.');
    }
    try {
      // iOS'ta plist eksikse veya bundle Id mismatch durumunda runtime
      // fallback olarak clientId'i doğrudan geçiyoruz; plist varsa zaten
      // override etmez. Android'de clientId default davranışı kullanır
      // (google-services.json otomatik okunur).
      final googleSignIn = (!kIsWeb && Platform.isIOS)
          ? GoogleSignIn(
              clientId:
                  '828607169326-f2j8au8cjoiuh8bp3c2l14qi61jfmd26.apps.googleusercontent.com',
              serverClientId:
                  '828607169326-os08cs4ik9e8ki9m7enbfbju2vuf6b2u.apps.googleusercontent.com',
            )
          : GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException(
            'cancelled', 'Google girişi iptal edildi.');
      }
      final googleAuth = await googleUser.authentication;
      final credential = fb_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await fb_auth.FirebaseAuth.instance
          .signInWithCredential(credential);
      final fbUser = result.user;
      if (fbUser == null) {
        throw const AuthException('no-user', 'Kullanıcı oluşturulamadı.');
      }
      return _persist(AppUser(
        id: fbUser.uid,
        name: fbUser.displayName ?? googleUser.displayName,
        email: fbUser.email ?? googleUser.email,
        photoUrl: fbUser.photoURL ?? googleUser.photoUrl,
        provider: AuthProvider.google,
        createdAt: DateTime.now(),
      ));
    } on AuthException {
      rethrow;
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('[Auth][google] firebase: ${e.code} ${e.message}');
      throw AuthException(e.code, e.message ?? 'Google girişi başarısız.');
    } catch (e) {
      debugPrint('[Auth][google] error: $e');
      throw AuthException('unknown', e.toString());
    }
  }

  // ── APPLE ─────────────────────────────────────────────────────────────────
  // sign_in_with_apple plugin'i ASAuthorizationAppleIDProvider'ı çağırır.
  // Apple sadece iOS 13+ ve macOS'ta gerçek; diğer platformlarda webview.
  static Future<AppUser> signInWithApple() async {
    if (!firebaseReady) {
      throw const AuthException(
          'firebase-not-configured',
          'Apple girişi için Firebase yapılandırılmamış. '
          'Terminalde "flutterfire configure" çalıştır + Firebase Console\'da '
          'Apple sign-in provider\'ı aktive et.');
    }
    try {
      // Android ve web'de native Apple sheet yok — Firebase'in kendi OAuth
      // akışı (tarayıcı/custom tab) üzerinden giriş yapılır. Firebase
      // Console'da Apple provider'ın etkin olması gerekir.
      if (kIsWeb || Platform.isAndroid) {
        final provider = fb_auth.AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
        final result = kIsWeb
            ? await fb_auth.FirebaseAuth.instance.signInWithPopup(provider)
            : await fb_auth.FirebaseAuth.instance.signInWithProvider(provider);
        final fbUser = result.user;
        if (fbUser == null) {
          throw const AuthException('no-user', 'Kullanıcı oluşturulamadı.');
        }
        return _persist(AppUser(
          id: fbUser.uid,
          name: fbUser.displayName,
          email: fbUser.email,
          photoUrl: fbUser.photoURL,
          provider: AuthProvider.apple,
          createdAt: DateTime.now(),
        ));
      }

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Firebase için OAuthCredential — apple.com provider ID.
      final oauthCredential = fb_auth.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final result = await fb_auth.FirebaseAuth.instance
          .signInWithCredential(oauthCredential);
      final fbUser = result.user;
      if (fbUser == null) {
        throw const AuthException('no-user', 'Kullanıcı oluşturulamadı.');
      }

      // Apple sadece İLK girişte ad/soyad gönderir; sonraki girişlerde null.
      final fullName = [
        appleCredential.givenName,
        appleCredential.familyName
      ].where((s) => s != null && s.isNotEmpty).join(' ').trim();

      return _persist(AppUser(
        id: fbUser.uid,
        name: fullName.isNotEmpty ? fullName : fbUser.displayName,
        email: appleCredential.email ?? fbUser.email,
        photoUrl: fbUser.photoURL,
        provider: AuthProvider.apple,
        createdAt: DateTime.now(),
      ));
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint('[Auth][apple] auth error: ${e.code} ${e.message}');
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthException('cancelled', 'Apple girişi iptal edildi.');
      }
      throw AuthException(e.code.name, e.message);
    } on AuthException {
      rethrow;
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('[Auth][apple] firebase: ${e.code} ${e.message}');
      throw AuthException(e.code, e.message ?? 'Apple girişi başarısız.');
    } catch (e) {
      debugPrint('[Auth][apple] error: $e');
      throw AuthException('unknown', e.toString());
    }
  }

  // ── MICROSOFT ─────────────────────────────────────────────────────────────
  // Firebase'in kendi OAuth akışı (tarayıcı/custom tab) üzerinden giriş.
  // Firebase Console'da Microsoft provider etkinleştirilmeli (Azure AD app
  // kaydı + client id/secret). Kişisel + kurumsal Microsoft hesapları çalışır.
  static Future<AppUser> signInWithMicrosoft() async {
    if (!firebaseReady) {
      throw const AuthException(
          'firebase-not-configured',
          'Microsoft girişi için Firebase yapılandırılmamış. '
          'Terminalde "flutterfire configure" çalıştır + Firebase Console\'da '
          'Microsoft sign-in provider\'ı aktive et.');
    }
    try {
      final provider = fb_auth.MicrosoftAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      final result = kIsWeb
          ? await fb_auth.FirebaseAuth.instance.signInWithPopup(provider)
          : await fb_auth.FirebaseAuth.instance.signInWithProvider(provider);
      final fbUser = result.user;
      if (fbUser == null) {
        throw const AuthException('no-user', 'Kullanıcı oluşturulamadı.');
      }
      return _persist(AppUser(
        id: fbUser.uid,
        name: fbUser.displayName,
        email: fbUser.email,
        photoUrl: fbUser.photoURL,
        provider: AuthProvider.microsoft,
        createdAt: DateTime.now(),
      ));
    } on AuthException {
      rethrow;
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('[Auth][microsoft] firebase: ${e.code} ${e.message}');
      if (e.code == 'web-context-canceled' ||
          e.code == 'web-context-cancelled' ||
          e.code == 'canceled' ||
          e.code == 'user-cancelled') {
        throw const AuthException('cancelled', 'Microsoft girişi iptal edildi.');
      }
      throw AuthException(e.code, e.message ?? 'Microsoft girişi başarısız.');
    } catch (e) {
      debugPrint('[Auth][microsoft] error: $e');
      throw AuthException('unknown', e.toString());
    }
  }

  // ── TELEFON (OTP) — Firebase Phone Auth ile gerçek SMS ────────────────────
  // İki aşamalı: requestPhoneCode → Firebase üzerinden gerçek SMS gönderir;
  // verifyPhoneCode → kullanıcının girdiği kodu Firebase ile doğrular.
  //
  // Üretim için Firebase Console gereklilikleri (eğer SMS GELMİYORSA bunları kontrol et):
  //   1. Authentication → Sign-in method → Phone → ENABLE
  //   2. Android: Project Settings → SHA-1 / SHA-256 parmak izlerini ekle
  //      (debug ve release imzaları için ayrı ayrı). Sonra google-services.json
  //      güncellenmiş halini indir → android/app/ altına koy.
  //   3. iOS: APNs Auth Key ekle (Project Settings → Cloud Messaging →
  //      Apple app configuration → APNs Authentication Key). Yoksa reCAPTCHA
  //      fallback devreye girer.
  //   4. Firebase'in Play Integrity API'si etkin olmalı (otomatik gelir).
  //   5. Test için: Authentication → Phone → "Phone numbers for testing"
  //      kısmından test numarası + sabit kod ekleyebilirsin (üretim faturası
  //      olmadan denemek için).
  //
  // Not: emülatörde reCAPTCHA / Play Integrity test bayrağı gerekebilir;
  // gerçek cihazda doğrudan SMS gelir.

  // Son verificationId — codeAutoRetrievalTimeout sonrası güncellenir;
  // gerekirse resend / debug için tutuluyor.
  // ignore: unused_field
  static String? _pendingPhoneSession;
  static String? _pendingPhone;

  /// Verilen telefon numarasına Firebase üzerinden SMS gönderir.
  /// Geriye verificationId (sessionId) döner.
  static Future<String> requestPhoneCode(String phoneE164) async {
    if (!firebaseReady) {
      throw const AuthException(
          'firebase-not-configured',
          'Telefon doğrulama için Firebase yapılandırılmamış. '
          'Terminalde "flutterfire configure" çalıştırıp uygulamayı yeniden başlat.');
    }
    final phone = phoneE164.replaceAll(RegExp(r'[\s\-]'), '');
    if (!_isValidPhone(phone)) {
      throw const AuthException(
          'invalid-phone',
          'Geçerli bir telefon numarası gir (örn. +90 555 123 45 67).');
    }
    if (!phone.startsWith('+')) {
      throw const AuthException(
          'invalid-phone',
          'Telefon numarası ülke kodu ile başlamalı (örn. +90 …).');
    }

    final completer = Completer<String>();
    Timer? timeoutTimer;

    try {
      timeoutTimer = Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          completer.completeError(const AuthException(
              'timeout',
              'Doğrulama zaman aşımına uğradı. Numarayı kontrol edip tekrar dene.'));
        }
      });

      await fb_auth.FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        // Android otomatik doğrulama (SMS auto-retrieval) — kullanıcı
        // SMS'i kendisi yazmadan da Firebase doğrular.
        verificationCompleted: (fb_auth.PhoneAuthCredential credential) async {
          try {
            await fb_auth.FirebaseAuth.instance
                .signInWithCredential(credential);
            // signInWithCredential başarılıysa _pendingPhone'u kaydet ki
            // verifyPhoneCode tekrar çağrılırsa anlamsız olmasın.
            _pendingPhone = phone;
          } catch (e) {
            debugPrint('[Auth][phone] auto verify error: $e');
          }
        },
        verificationFailed: (fb_auth.FirebaseAuthException e) {
          debugPrint('[Auth][phone] verificationFailed: ${e.code} ${e.message}');
          if (!completer.isCompleted) {
            completer.completeError(AuthException(
                e.code,
                e.message ?? 'Telefon doğrulama başarısız.'));
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _pendingPhoneSession = verificationId;
          _pendingPhone = phone;
          debugPrint('[Auth][phone] codeSent — SMS yollandı: $phone');
          if (!completer.isCompleted) {
            completer.complete(verificationId);
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Otomatik retrieval zaman aşımı — kullanıcı kodu manuel girecek.
          _pendingPhoneSession = verificationId;
        },
      );
    } catch (e) {
      debugPrint('[Auth][phone] requestPhoneCode threw: $e');
      if (!completer.isCompleted) {
        completer.completeError(AuthException('unknown', e.toString()));
      }
    }

    try {
      final id = await completer.future;
      timeoutTimer?.cancel();
      return id;
    } catch (e) {
      timeoutTimer?.cancel();
      rethrow;
    }
  }

  /// Kullanıcının girdiği SMS kodunu Firebase ile doğrular.
  static Future<AppUser> verifyPhoneCode({
    required String sessionId,
    required String code,
  }) async {
    final c = code.trim();
    if (c.length != 6 || int.tryParse(c) == null) {
      throw const AuthException(
          'invalid-code', '6 haneli sayısal kodu doğru gir.');
    }
    if (sessionId.isEmpty) {
      throw const AuthException(
          'invalid-session', 'Oturum süresi doldu. Yeni kod iste.');
    }

    try {
      final credential = fb_auth.PhoneAuthProvider.credential(
        verificationId: sessionId,
        smsCode: c,
      );
      final result = await fb_auth.FirebaseAuth.instance
          .signInWithCredential(credential);
      final fbUser = result.user;
      if (fbUser == null) {
        throw const AuthException('no-user', 'Kullanıcı oluşturulamadı.');
      }
      final phone = fbUser.phoneNumber ?? _pendingPhone ?? '';
      _pendingPhone = null;
      _pendingPhoneSession = null;
      return _persist(AppUser(
        id: fbUser.uid,
        name: phone,
        email: fbUser.email,
        photoUrl: fbUser.photoURL,
        provider: AuthProvider.phone,
        createdAt: DateTime.now(),
      ));
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('[Auth][phone] verify error: ${e.code} ${e.message}');
      if (e.code == 'invalid-verification-code' ||
          e.code == 'invalid-verification-id') {
        throw const AuthException('wrong-code', 'Kod hatalı. Tekrar dene.');
      }
      if (e.code == 'session-expired') {
        throw const AuthException(
            'invalid-session', 'Oturum süresi doldu. Yeni kod iste.');
      }
      throw AuthException(e.code, e.message ?? 'Doğrulama başarısız.');
    } catch (e) {
      debugPrint('[Auth][phone] unknown verify error: $e');
      throw AuthException('unknown', e.toString());
    }
  }

  static bool _isValidPhone(String s) {
    final t = s.replaceAll(RegExp(r'[\s\-]'), '');
    // Esnek E.164 — başında + olabilir, en az 7 en fazla 15 rakam.
    return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(t);
  }

  // ── E-POSTA ───────────────────────────────────────────────────────────────
  static Future<AppUser> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    if (name.trim().isEmpty) {
      throw const AuthException('weak-name', 'İsim boş olamaz.');
    }
    if (!_isValidEmail(email)) {
      throw const AuthException('invalid-email', 'Geçerli bir e-posta gir.');
    }
    if (password.length < 6) {
      throw const AuthException(
          'weak-password', 'Şifre en az 6 karakter olmalı.');
    }
    if (!firebaseReady) {
      throw const AuthException(
          'firebase-not-configured',
          'E-posta kaydı için Firebase yapılandırılmamış. '
          'Firebase Console\'da Email/Password sign-in provider\'ı aktive et.');
    }
    try {
      final result = await fb_auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final fbUser = result.user;
      if (fbUser == null) {
        throw const AuthException('no-user', 'Kullanıcı oluşturulamadı.');
      }
      // displayName'i kaydet (Firebase'de async update)
      try {
        await fbUser.updateDisplayName(name.trim());
      } catch (e, st) {
        ErrorLogger.instance
            .capture(e, st, context: 'auth_service.updateDisplayName');
      }
      return _persist(AppUser(
        id: fbUser.uid,
        name: name.trim(),
        email: fbUser.email ?? email.trim(),
        provider: AuthProvider.email,
        createdAt: DateTime.now(),
      ));
    } on AuthException {
      rethrow;
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('[Auth][email-signup] firebase: ${e.code} ${e.message}');
      // Firebase error code → kullanıcı dostu mesaj
      final msg = switch (e.code) {
        'email-already-in-use' =>
          'Bu e-posta zaten kayıtlı. Giriş yapmayı dene.',
        'invalid-email' => 'E-posta formatı geçersiz.',
        'weak-password' => 'Şifre çok zayıf — en az 6 karakter ve karışık olsun.',
        'operation-not-allowed' =>
          'E-posta kaydı şu an aktif değil. Lütfen Google ile giriş yap.',
        _ => e.message ?? 'Kayıt başarısız.',
      };
      throw AuthException(e.code, msg);
    } catch (e) {
      debugPrint('[Auth][email-signup] error: $e');
      throw AuthException('unknown', e.toString());
    }
  }

  static Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (!_isValidEmail(email)) {
      throw const AuthException('invalid-email', 'Geçerli bir e-posta gir.');
    }
    if (password.length < 6) {
      throw const AuthException(
          'weak-password', 'Şifre en az 6 karakter olmalı.');
    }
    if (!firebaseReady) {
      throw const AuthException(
          'firebase-not-configured',
          'E-posta girişi için Firebase yapılandırılmamış.');
    }
    try {
      final result = await fb_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final fbUser = result.user;
      if (fbUser == null) {
        throw const AuthException('no-user', 'Kullanıcı bulunamadı.');
      }
      return _persist(AppUser(
        id: fbUser.uid,
        name: fbUser.displayName,
        email: fbUser.email ?? email.trim(),
        photoUrl: fbUser.photoURL,
        provider: AuthProvider.email,
        createdAt: DateTime.now(),
      ));
    } on AuthException {
      rethrow;
    } on fb_auth.FirebaseAuthException catch (e) {
      debugPrint('[Auth][email-signin] firebase: ${e.code} ${e.message}');
      final msg = switch (e.code) {
        'user-not-found' || 'invalid-credential' =>
          'E-posta veya şifre hatalı.',
        'wrong-password' => 'Şifre hatalı.',
        'user-disabled' => 'Bu hesap askıya alınmış.',
        'too-many-requests' =>
          'Çok fazla deneme yapıldı. Lütfen birkaç dakika sonra tekrar dene.',
        _ => e.message ?? 'Giriş başarısız.',
      };
      throw AuthException(e.code, msg);
    } catch (e) {
      debugPrint('[Auth][email-signin] error: $e');
      throw AuthException('unknown', e.toString());
    }
  }

  /// Şifre sıfırlama e-postası gönder.
  static Future<void> sendPasswordResetEmail(String email) async {
    if (!_isValidEmail(email)) {
      throw const AuthException('invalid-email', 'Geçerli bir e-posta gir.');
    }
    if (!firebaseReady) {
      throw const AuthException(
          'firebase-not-configured', 'Firebase yapılandırılmamış.');
    }
    try {
      await fb_auth.FirebaseAuth.instance
          .sendPasswordResetEmail(email: email.trim());
    } on fb_auth.FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'user-not-found' => 'Bu e-postaya kayıtlı kullanıcı bulunamadı.',
        'invalid-email' => 'E-posta formatı geçersiz.',
        _ => e.message ?? 'Şifre sıfırlama maili gönderilemedi.',
      };
      throw AuthException(e.code, msg);
    }
  }

  // ── MİSAFİR ───────────────────────────────────────────────────────────────
  static Future<AppUser> continueAsGuest() async {
    return _persist(AppUser(
      id: _genId('guest'),
      provider: AuthProvider.guest,
      createdAt: DateTime.now(),
    ));
  }

  // ── ÇIKIŞ ─────────────────────────────────────────────────────────────────
  // Firebase + Google + local state tümünü temizler. Bunlardan biri atılırsa
  // kullanıcı tekrar açılışta otomatik giriş yapmış görünür → "logout çalışmıyor"
  // hatası.
  static Future<void> signOut() async {
    // 1) Local state + persist temizle
    _current = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUserKey);
      // Username pref'ini de temizle → kullanıcı tekrar giriş yaparsa
      // onboarding sheet'i yeniden açılır.
      await prefs.remove('user_username_v1');
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'auth_service'); }

    // 2) Firebase Auth oturumunu kapat
    if (firebaseReady) {
      try {
        await fb_auth.FirebaseAuth.instance.signOut();
      } catch (e, st) {
        ErrorLogger.instance.capture(e, st, context: 'auth_service.firebase_signout');
      }
    }

    // 3) Google Sign-In oturumunu kapat (cache'li token silinir)
    try {
      final googleSignIn = (!kIsWeb && Platform.isIOS)
          ? GoogleSignIn(
              clientId:
                  '828607169326-f2j8au8cjoiuh8bp3c2l14qi61jfmd26.apps.googleusercontent.com',
              serverClientId:
                  '828607169326-os08cs4ik9e8ki9m7enbfbju2vuf6b2u.apps.googleusercontent.com',
            )
          : GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'auth_service.google_signout');
    }

    // 4) Listener'lara bildir → UI yenilenir
    _changes.add(null);
  }

  static bool _isValidEmail(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$')
        .hasMatch(t);
  }
}
