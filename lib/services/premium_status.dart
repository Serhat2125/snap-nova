// ═══════════════════════════════════════════════════════════════════════════════
//  PremiumStatus — Premium üyelik durumunu TEK kaynaktan döner.
//
//  Eski sürümde "premium aktif mi?" mantığı birkaç farklı yerde dağılmıştı:
//    • SharedPreferences `is_premium` boolean (davet sisteminden)
//    • SharedPreferences `premium_until` (davet sisteminden)
//    • PremiumScreen mock satın alma akışı
//
//  Bu servis hepsini birleştirir:
//    • Yerel cache (offline)        → `premium_until_iso` + `premium_source`
//    • Cloud kaynağı (varsa)        → Firestore users/{uid}/premium/state
//    • Auth yoksa sadece local cache.
//
//  Source değerleri:
//    'subscription'         → IAP abonelik
//    'referral_complete'    → 3 kişi davet edip 30 gün kazandı
//    'referral_redeem'      → Davet kodu kullanan kullanıcı için 7 gün
//    'manual_test'          → Geliştirici / test
//    null                   → Premium değil
//
//  Kullanım:
//    final status = await PremiumStatus.read();
//    if (status.isActive) { ... }
//    print(status.daysRemaining);
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PremiumStatusSnapshot {
  /// Aktif mi?
  final bool isActive;

  /// Premium ne zaman sona erer (aktif ise).
  final DateTime? until;

  /// Kaynak: 'subscription' | 'referral_complete' | 'referral_redeem' | 'manual_test' | null.
  final String? source;

  const PremiumStatusSnapshot({
    required this.isActive,
    this.until,
    this.source,
  });

  static const inactive = PremiumStatusSnapshot(isActive: false);

  /// Kaç gün kaldı? Aktif değilse 0.
  int get daysRemaining {
    if (!isActive || until == null) return 0;
    final diff = until!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// "Davet ödülü mü, abonelik mi?" UI'da farklı badge gösterilebilir.
  bool get isFromReferral =>
      source == 'referral_complete' || source == 'referral_redeem';
  bool get isFromSubscription => source == 'subscription';
}

class PremiumStatus {
  PremiumStatus._();

  static const _kPrefUntil = 'premium_until_iso';
  static const _kPrefSource = 'premium_source';

  // Listener pattern — UI premium aktivasyonunda anında rebuild olabilsin
  // diye basit bir notifier. ChangeNotifier kullanmıyoruz çünkü servis
  // singleton ve dispose karmaşası yok.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Geçerli premium kaynakları — yalnızca bu source'lar aktif Premium sayılır.
  /// Eski test/mock grantları ('debug_mock', 'manual_test') stale data olarak
  /// kabul edilip otomatik temizlenir.
  static const _validSources = <String>{
    'subscription',
    'referral_complete',
    'referral_redeem',
  };

  /// Anlık snapshot — cache + cloud. Geçersiz kaynaklı (mock/test) kayıtlar
  /// hem cloud hem de lokal cache'ten temizlenir.
  static Future<PremiumStatusSnapshot> read() async {
    // 1) Lokal cache hemen
    final local = await _readLocal();
    if (local.source != null && !_validSources.contains(local.source)) {
      // Eski mock/test kaydı bulundu → temizle, inactive dön.
      debugPrint(
          '[PremiumStatus] geçersiz kaynak temizleniyor: ${local.source}');
      await clear();
      return PremiumStatusSnapshot.inactive;
    }
    // 2) Auth varsa cloud ile senkronize et
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return local;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('premium')
          .doc('state');
      final snap = await docRef.get();
      if (!snap.exists) return local;
      final data = snap.data() ?? const <String, dynamic>{};
      DateTime? until;
      final raw = data['premiumUntil'];
      if (raw is Timestamp) until = raw.toDate();
      final source = data['lastGrantSource'] as String?;
      if (until == null) return local;

      // Stale/mock kaynak ise cloud'da da temizle, inactive dön.
      if (source != null && !_validSources.contains(source)) {
        debugPrint(
            '[PremiumStatus] cloud\'da geçersiz kaynak: $source — temizleniyor');
        try {
          await docRef.delete();
        } catch (e) {
          debugPrint('[PremiumStatus] cloud delete fail: $e');
        }
        await clear();
        return PremiumStatusSnapshot.inactive;
      }

      // Cloud > lokal ise cloud'u kabul et, lokal cache'i güncelle
      if (local.until == null || until.isAfter(local.until!)) {
        await _writeLocal(until: until, source: source);
        return PremiumStatusSnapshot(
          isActive: until.isAfter(DateTime.now()),
          until: until,
          source: source,
        );
      }
      return local;
    } catch (e) {
      debugPrint('[PremiumStatus] cloud read error: $e');
      return local;
    }
  }

  /// Yalnızca lokal cache okuması — offline / fast path.
  static Future<PremiumStatusSnapshot> _readLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final iso = prefs.getString(_kPrefUntil);
      final source = prefs.getString(_kPrefSource);
      if (iso == null || iso.isEmpty) return PremiumStatusSnapshot.inactive;
      final until = DateTime.tryParse(iso);
      if (until == null) return PremiumStatusSnapshot.inactive;
      return PremiumStatusSnapshot(
        isActive: until.isAfter(DateTime.now()),
        until: until,
        source: source,
      );
    } catch (_) {
      return PremiumStatusSnapshot.inactive;
    }
  }

  static Future<void> _writeLocal(
      {required DateTime until, String? source}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefUntil, until.toIso8601String());
    if (source != null) await prefs.setString(_kPrefSource, source);
    revision.value++;
  }

  /// TAMAMEN DEVRE DIŞI (kullanıcı talebi: "sahte premium olmasın").
  /// Premium SADECE gerçek IAP satın alma ile aktive olur. Bu fonksiyon
  /// imza geriye dönük uyumluluk için kalıyor ama hiçbir şey yapmaz.
  static Future<void> grantManualTest({int days = 30}) async {
    debugPrint('[Premium] grantManualTest devre dışı — gerçek ödeme gerekir');
  }

  /// Premium'u sıfırla (test / hesap silme / logout sonrası).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefUntil);
    await prefs.remove(_kPrefSource);
    revision.value++;
  }

  /// Hızlı boolean check — UI'da sık çağrılır.
  static bool isActiveSync() {
    // Bu sync versiyon SharedPreferences olmadığı için memoized değil; ama
    // pratikte ValueListenableBuilder + read() kullanılır. Bu sadece
    // çağrı kolaylığı için.
    return revision.value > 0; // placeholder — async read() tercih edilir
  }
}
