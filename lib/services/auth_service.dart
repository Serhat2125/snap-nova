import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  AuthService — Çoklu sağlayıcılı kimlik doğrulama
//
//  TASARIM NOTU:
//  Bu servis çağıran tarafa SOYUT bir API sunar. Şu an mock (simulasyon)
//  implementasyon kullanılıyor — Google, Apple, Facebook ve e-posta akışları
//  yerel olarak çalışır, kullanıcı ID'si oluşturup SharedPreferences'a yazar.
//  Üretim için aşağıdaki paketler eklenmeli ve TODO kısımları gerçek SDK
//  çağrılarıyla değiştirilmeli:
//
//   firebase_auth: ^5.x
//   google_sign_in: ^6.x
//   sign_in_with_apple: ^6.x
//   flutter_facebook_auth: ^7.x
//
//  Paket entegrasyonu sırasında platform tarafı:
//   • Android: SHA-1 / SHA-256 → Firebase Console; google-services.json
//   • iOS: Info.plist URL schemes; GoogleService-Info.plist; Apple capability
//   • Facebook: Meta Developers app ID + URL scheme
//   • Apple Sign In: iOS 13+; entitlements; Apple Developer onayı
//
//  Tüm UI çağrıları zaten doğru imzalarla yapıldığı için gerçek sağlayıcılara
//  geçiş tek dosya değişikliğiyle (bu dosya) tamamlanabilir.
// ═══════════════════════════════════════════════════════════════════════════════

enum AuthProvider { google, apple, phone, email, guest }

extension AuthProviderX on AuthProvider {
  String get id => switch (this) {
        AuthProvider.google => 'google',
        AuthProvider.apple  => 'apple',
        AuthProvider.phone  => 'phone',
        AuthProvider.email  => 'email',
        AuthProvider.guest  => 'guest',
      };

  static AuthProvider fromId(String id) => switch (id) {
        'google' => AuthProvider.google,
        'apple'  => AuthProvider.apple,
        'phone'  => AuthProvider.phone,
        'email'  => AuthProvider.email,
        _        => AuthProvider.guest,
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
    _changes.add(u);
    return u;
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
      final googleUser = await GoogleSignIn().signIn();
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
    // TODO(prod): FirebaseAuth.instance.createUserWithEmailAndPassword(...)
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return _persist(AppUser(
      id: _genId('e'),
      name: name.trim(),
      email: email.trim(),
      provider: AuthProvider.email,
      createdAt: DateTime.now(),
    ));
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
    // TODO(prod): FirebaseAuth.instance.signInWithEmailAndPassword(...)
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return _persist(AppUser(
      id: _genId('e'),
      email: email.trim(),
      provider: AuthProvider.email,
      createdAt: DateTime.now(),
    ));
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
  static Future<void> signOut() async {
    _current = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUserKey);
    } catch (_) {}
    _changes.add(null);
  }

  static bool _isValidEmail(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$')
        .hasMatch(t);
  }
}
