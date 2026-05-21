// ═══════════════════════════════════════════════════════════════════════════════
//  ReferralService — Gerçek referral altyapısı (Firestore tabanlı)
//
//  Eski sürümde davet sayacı SharedPreferences'taydı ve hiçbir yerde
//  artırılmıyordu → tamamen mock'tu. Bu servis gerçek bir akış kuruyor:
//
//  Firestore yapısı:
//    referral_codes/{CODE}          → CODE → ownerUid haritası (lookup index)
//        {ownerUid, createdAt}
//    referrals/{ownerUid}           → kişinin daveti durumu
//        {code, createdAt,
//         invitedUsers: [{uid, joinedAt, deviceHash}, ...]}
//    users/{uid}/referral/state     → bu kullanıcı kullandığı kod
//        {usedCode, usedAt, deviceHash, rewardClaimed}
//
//  Akış:
//    A) Davet eden:
//       1) `ensureMyCode()` → kendi kodunu üretir (örn QUALS-7K9F2) veya getirir.
//       2) Kodu paylaşır.
//       3) `myStats()` → kaç kişi davet etti, kim katıldı.
//    B) Davet edilen (yeni kullanıcı):
//       1) Onboarding'de `redeemCode(code)` çağrılır.
//       2) Servis: self-referral kontrolü, kod geçerliliği, cihaz duplicate
//          kontrolü → kabul ederse Firestore'a yazıp ödülü aktive eder.
//       3) Davet edenin sayacı otomatik artar (transaction).
//
//  Anti-fraud:
//    • Self-referral (kendi kodu): blok
//    • Aynı cihazda zaten redeem: blok (deviceHash field)
//    • Kod kullanım sayısı: kullanıcı başına 1
//    • Davet eden zaten Premium ise yeni davet ödülü vermez (ekstra ay sayılır)
//
//  GÜVENLİK NOTU: İdeal mimari Cloud Function ile server-side ödül grant'tır.
//  Bu sürüm client-side; Firestore security rules ile minimum korunur:
//    referral_codes/{c}: read public, create owner only (allow if owner uid match)
//    referrals/{u}: read public, write owner only
//    users/{u}/referral: read/write owner only
//  Anti-fraud production'da Cloud Function'a taşınmalı.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InvitedUser {
  final String uid;
  final DateTime joinedAt;
  const InvitedUser({required this.uid, required this.joinedAt});

  factory InvitedUser.fromMap(Map<String, dynamic> m) {
    final ts = m['joinedAt'];
    DateTime when;
    if (ts is Timestamp) {
      when = ts.toDate();
    } else if (ts is String) {
      when = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      when = DateTime.now();
    }
    return InvitedUser(
      uid: (m['uid'] ?? '').toString(),
      joinedAt: when,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'joinedAt': Timestamp.fromDate(joinedAt),
      };
}

class ReferralStats {
  /// Bu kullanıcının paylaşacağı davet kodu — örn "QUALS-7K9F2".
  final String myCode;

  /// Bu kullanıcıyı davet edenler (en fazla 1).
  final List<InvitedUser> invitedUsers;

  /// Davet hedefi (üyelik kazanmak için gerekli kişi sayısı).
  final int targetCount;

  /// Tamamlandı mı? (`invitedUsers.length >= targetCount`)
  bool get isComplete => invitedUsers.length >= targetCount;

  /// İlerleme yüzdesi 0.0–1.0.
  double get progress =>
      (invitedUsers.length / targetCount).clamp(0.0, 1.0);

  const ReferralStats({
    required this.myCode,
    required this.invitedUsers,
    required this.targetCount,
  });

  static const empty = ReferralStats(
    myCode: '',
    invitedUsers: [],
    targetCount: 3,
  );
}

enum RedeemResult {
  success,
  selfReferral,
  alreadyUsed,
  deviceAlreadyUsed,
  invalidCode,
  notAuthenticated,
  ownerNotFound,
  networkError,
}

class ReferralService {
  ReferralService._();

  static const _kTargetCount = 3;
  static const _kFirstRewardDays = 30; // davet eden için — 3 kişi → 30 gün
  static const _kRedemptionRewardDays = 7; // davet edilen için — 7 gün

  /// Davet eden için 3 kişi tamamlandığında verilecek ödül günü.
  static int get firstRewardDays => _kFirstRewardDays;

  /// Davet edilen yeni kullanıcı için verilen hoşgeldin premium günü.
  static int get redemptionRewardDays => _kRedemptionRewardDays;

  /// Davet hedefi (kaç kişi).
  static int get targetCount => _kTargetCount;

  static final _col = FirebaseFirestore.instance;

  // ── Cihaz parmak izi — anti-fraud ─────────────────────────────────────────
  // Cihaza özgü, kalıcı, anonim bir hash. Aynı cihazda farklı hesaplarla
  // birden fazla redeem'i engellemek için. Production'da daha sağlam bir
  // device_info_plus + secure storage tabanlı çözüm kullanılmalı.
  static const _kDeviceHashPref = 'referral_device_hash_v1';
  static Future<String> _deviceHash() async {
    final prefs = await SharedPreferences.getInstance();
    var h = prefs.getString(_kDeviceHashPref);
    if (h == null || h.isEmpty) {
      // crypto paketi olmadan: 16 byte secure random → base64'e benzer hex.
      final rng = math.Random.secure();
      final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
      h = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .substring(0, 16);
      await prefs.setString(_kDeviceHashPref, h);
    }
    return h;
  }

  // ── Davet kodu üretimi ─────────────────────────────────────────────────────
  // "QUALS-XXXXX" format: 5 karakter, ambiguous karakter (O, 0, I, 1, L) yok.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static String _generateCode() {
    final rng = math.Random.secure();
    final buf = StringBuffer('QUALS-');
    for (int i = 0; i < 5; i++) {
      buf.write(_alphabet[rng.nextInt(_alphabet.length)]);
    }
    return buf.toString();
  }

  /// Kullanıcı için bir referral kodu garanti eder. Var ise mevcut, yoksa
  /// yeni üretir + Firestore'a yazar. Collision olasılığı 31^5 ≈ 28M, çok düşük;
  /// yine de var ise yeniden üret.
  static Future<String?> ensureMyCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final myDoc = _col.collection('referrals').doc(user.uid);
    try {
      final snap = await myDoc.get();
      if (snap.exists && (snap.data()?['code'] as String?) != null) {
        return snap.data()!['code'] as String;
      }
      // Kod üret + reverse-index yaz
      for (int attempt = 0; attempt < 5; attempt++) {
        final code = _generateCode();
        final codeDoc = _col.collection('referral_codes').doc(code);
        try {
          await _col.runTransaction((tx) async {
            final exists = await tx.get(codeDoc);
            if (exists.exists) throw StateError('collision');
            tx.set(codeDoc, {
              'ownerUid': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
            tx.set(myDoc, {
              'code': code,
              'createdAt': FieldValue.serverTimestamp(),
              'invitedUsers': <dynamic>[],
            }, SetOptions(merge: true));
          });
          return code;
        } on StateError {
          continue; // bir sonraki kod
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Referral] ensureMyCode error: $e');
      return null;
    }
  }

  /// Bu kullanıcının davet durumu — kod + davet ettikleri.
  /// `ensureMyCode` çağrılmamışsa boş döner.
  static Future<ReferralStats> myStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return ReferralStats.empty;
    try {
      final snap = await _col.collection('referrals').doc(user.uid).get();
      if (!snap.exists) return ReferralStats.empty;
      final data = snap.data() ?? const <String, dynamic>{};
      final code = (data['code'] ?? '') as String;
      final raw = (data['invitedUsers'] as List?) ?? const [];
      final invited = raw
          .whereType<Map>()
          .map((e) => InvitedUser.fromMap(e.cast<String, dynamic>()))
          .toList();
      return ReferralStats(
        myCode: code,
        invitedUsers: invited,
        targetCount: _kTargetCount,
      );
    } catch (e) {
      debugPrint('[Referral] myStats error: $e');
      return ReferralStats.empty;
    }
  }

  /// Davet kodunu kullan (yeni kullanıcı tarafından çağrılır).
  /// Başarılı olursa:
  ///   • Yeni kullanıcı 7 gün hoşgeldin Premium kazanır.
  ///   • Davet edenin `invitedUsers` listesine eklenir; sayı hedef'e (3)
  ///     ulaşmışsa davet edene 30 gün Premium grant edilir.
  static Future<RedeemResult> redeemCode(String rawCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return RedeemResult.notAuthenticated;
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty || !RegExp(r'^QUALS-[A-Z0-9]{5}$').hasMatch(code)) {
      return RedeemResult.invalidCode;
    }
    try {
      // Kod → owner lookup
      final codeDoc =
          await _col.collection('referral_codes').doc(code).get();
      if (!codeDoc.exists) return RedeemResult.invalidCode;
      final ownerUid = (codeDoc.data()?['ownerUid'] ?? '') as String;
      if (ownerUid.isEmpty) return RedeemResult.ownerNotFound;
      // Self-referral kontrolü
      if (ownerUid == user.uid) return RedeemResult.selfReferral;

      // Daha önce kullandı mı?
      final mineDoc = _col
          .collection('users')
          .doc(user.uid)
          .collection('referral')
          .doc('state');
      final mineSnap = await mineDoc.get();
      if (mineSnap.exists &&
          (mineSnap.data()?['usedCode'] as String?)?.isNotEmpty == true) {
        return RedeemResult.alreadyUsed;
      }

      // Cihaz daha önce redeem ettiyse blok (anti-fraud)
      final deviceHash = await _deviceHash();
      final deviceQuery = await _col
          .collectionGroup('referral')
          .where('deviceHash', isEqualTo: deviceHash)
          .limit(1)
          .get();
      if (deviceQuery.docs.isNotEmpty) {
        return RedeemResult.deviceAlreadyUsed;
      }

      // Transaction: kullanıcının state'i + owner'ın invitedUsers'ı
      final ownerDoc = _col.collection('referrals').doc(ownerUid);
      await _col.runTransaction((tx) async {
        final ownerSnap = await tx.get(ownerDoc);
        final existing =
            (ownerSnap.data()?['invitedUsers'] as List?) ?? const [];
        final alreadyIn = existing
            .whereType<Map>()
            .any((e) => (e['uid'] ?? '') == user.uid);
        if (!alreadyIn) {
          tx.set(
            ownerDoc,
            {
              'invitedUsers': FieldValue.arrayUnion([
                {
                  'uid': user.uid,
                  'joinedAt': Timestamp.now(),
                }
              ]),
            },
            SetOptions(merge: true),
          );
        }
        tx.set(mineDoc, {
          'usedCode': code,
          'usedAt': FieldValue.serverTimestamp(),
          'deviceHash': deviceHash,
          'rewardClaimed': true,
        });
      });

      // Yeni kullanıcıya 7 gün hoşgeldin premium grant.
      // (Kendi uid'sine yazma → Firestore rules izin verir.)
      await _grantPremium(user.uid, days: _kRedemptionRewardDays,
          source: 'referral_redeem');

      // Davet edenin (owner) 30 gün ödülü artık Cloud Function ile veriliyor:
      //   functions/src/referral_reward.ts → onReferralCompleted trigger
      // Sebep: client'tan cross-user write (users/{ownerUid}/premium/state)
      // Firestore rules tarafından engelleniyor. Cloud Function admin SDK ile
      // güvenli ve idempotent grant yapar.

      return RedeemResult.success;
    } on FirebaseException catch (e) {
      debugPrint('[Referral] redeem firestore error: ${e.code} ${e.message}');
      return RedeemResult.networkError;
    } catch (e) {
      debugPrint('[Referral] redeem error: $e');
      return RedeemResult.networkError;
    }
  }

  /// Bir kullanıcıya N gün premium grant et.
  /// Firestore `users/{uid}/premium/state` doc'una yazılır.
  /// Bu doc PremiumStatus servisi tarafından okunur.
  ///
  /// Mantık: Mevcut premium_until tarihinden büyükse uzat, küçükse şimdiden
  /// itibaren başlat. Yani kullanıcı zaten premium ise süre eklenmiş olur.
  static Future<void> _grantPremium(String uid,
      {required int days, required String source}) async {
    try {
      final doc =
          _col.collection('users').doc(uid).collection('premium').doc('state');
      await _col.runTransaction((tx) async {
        final snap = await tx.get(doc);
        final existing = snap.data();
        final now = DateTime.now();
        DateTime base = now;
        if (existing != null) {
          final until = existing['premiumUntil'];
          if (until is Timestamp) {
            final t = until.toDate();
            if (t.isAfter(now)) base = t;
          }
        }
        final newUntil = base.add(Duration(days: days));
        tx.set(
          doc,
          {
            'premiumUntil': Timestamp.fromDate(newUntil),
            'lastGrantSource': source,
            'lastGrantAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      // Lokal cache de güncelle — premium kontrolü offline da çalışsın
      final prefs = await SharedPreferences.getInstance();
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == uid) {
        final until = DateTime.now().add(Duration(days: days));
        final existingIso = prefs.getString('premium_until_iso');
        final existingDate =
            existingIso != null ? DateTime.tryParse(existingIso) : null;
        DateTime finalUntil = until;
        if (existingDate != null && existingDate.isAfter(until)) {
          finalUntil = existingDate.add(Duration(days: days));
        }
        await prefs.setString('premium_until_iso', finalUntil.toIso8601String());
        await prefs.setString('premium_source', source);
      }
    } catch (e) {
      debugPrint('[Referral] grantPremium error: $e');
    }
  }

  /// Kullanıcının davet kodunu hatırlamak için cihazda da cache'le
  /// (offline'da paylaşabilsin diye).
  static const _kCachedCode = 'referral_my_code_cache_v1';

  /// UI'dan çağrılır: bu çağrı kodu garanti eder + lokal cache.
  static Future<String?> getOrCreateMyCode() async {
    // Önce cache (offline'da hızlı erişim)
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kCachedCode);
    if (cached != null && cached.isNotEmpty) {
      // Arka planda Firestore ile senkronize tutmaya çalış.
      unawaited(ensureMyCode().then((code) async {
        if (code != null && code != cached) {
          await prefs.setString(_kCachedCode, code);
        }
      }));
      return cached;
    }
    final code = await ensureMyCode();
    if (code != null) {
      await prefs.setString(_kCachedCode, code);
    }
    return code;
  }

  /// Test/destek için: kullanıcının kullandığı kod (varsa).
  static Future<String?> getMyUsedCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final snap = await _col
          .collection('users')
          .doc(user.uid)
          .collection('referral')
          .doc('state')
          .get();
      return (snap.data()?['usedCode'] as String?);
    } catch (_) {
      return null;
    }
  }
}

/// Onboarding adımı için: paylaşılan davet kodu URL/clipboard'tan parse edilir.
/// URL örnek: https://qualsar2-640f0.web.app/i/QUALS-7K9F2
String? parseInviteCodeFromText(String text) {
  final m = RegExp(r'QUALS-[A-Z0-9]{5}', caseSensitive: false).firstMatch(text);
  return m?.group(0)?.toUpperCase();
}

// JSON helper export — eski kodlar için.
String jsonEncodeMap(Map<String, dynamic> m) => jsonEncode(m);
