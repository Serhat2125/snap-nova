// ═══════════════════════════════════════════════════════════════════════════════
//  SubscriptionService — Google Play Billing + StoreKit abone akışı.
//
//  Sorumluluklar:
//   • Mağazadan ürün listesi çek (price/title) — UI fiyatlandırma için
//   • Satın alma başlat (Play Console / App Store Connect SKU'ları)
//   • Purchase stream'i dinle, başarılı abonelikte PremiumStatus'u güncelle
//   • Restore Purchases (Apple Guideline 3.1.1 zorunlu)
//   • Pending / error durumlarını UI'a callback ile bildir
//
//  ⚠️ Play Console kurulumu (kod dışı, kullanıcı yapacak):
//   1. Play Console → Monetize → Subscriptions → Yeni abonelik oluştur:
//        - qualsar_premium_monthly      (Aylık, 30 gün)
//        - qualsar_premium_quarterly    (3 Aylık, 90 gün)
//        - qualsar_premium_yearly       (Yıllık, 365 gün)
//   2. Her abonelik için Türk lirası bazlı fiyat belirle.
//   3. Internal Testing track'inde test hesabıyla deneme.
//
//  ⚠️ Güvenlik notu: Satın alma doğrulaması şu an client-side'da temel
//  PurchaseStatus kontrolüyle yapılıyor. PRODUCTION için backend imza
//  doğrulaması (Cloud Function + Google Play Developer API) eklenmesi
//  şiddetle önerilir. Aksi takdirde rooted cihazda sahte satın alma riski.
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_quota_service.dart';

/// Plan tipi ve karşılık gelen Play/Store product ID + süresi.
enum SubscriptionPlan {
  monthly('qualsar_premium_monthly', 30),
  quarterly('qualsar_premium_quarterly', 90),
  yearly('qualsar_premium_yearly', 365);

  final String productId;
  final int durationDays;
  const SubscriptionPlan(this.productId, this.durationDays);

  static SubscriptionPlan? byProductId(String id) {
    for (final p in SubscriptionPlan.values) {
      if (p.productId == id) return p;
    }
    return null;
  }
}

/// UI'ın subscribe akışından alacağı sonuç tipi.
enum SubscriptionPurchaseResult {
  /// Satın alma başarılı, premium aktif edildi.
  success,

  /// Kullanıcı satın almayı iptal etti.
  canceled,

  /// Mağaza hazır değil veya cihaz desteklemiyor.
  unavailable,

  /// Beklenmedik hata.
  error,

  /// Satın alma "pending" — örn. ailenin onayı bekleniyor (Family Library).
  pending,
}

class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _streamSub;
  bool _available = false;
  List<ProductDetails> _products = const [];
  bool _initialized = false;

  /// Aktif satın alma için completer — buy() çağrısı stream sonuna kadar bekler.
  Completer<SubscriptionPurchaseResult>? _activeCompleter;

  /// UI yansıması için — premium aktivasyonunda revision++ et.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// App startup'ta bir kere çağrılır (main.dart).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _available = await _iap.isAvailable();
    } catch (e) {
      debugPrint('[SubscriptionService] isAvailable error: $e');
      _available = false;
    }

    if (!_available) return;

    // Purchase stream — başarılı/başarısız tüm satın alma olayları buraya düşer.
    _streamSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _streamSub?.cancel(),
      onError: (Object e) {
        debugPrint('[SubscriptionService] purchase stream error: $e');
      },
    );

    // İlk açılışta product list'i çek — UI fiyat gösterimi için.
    await refreshProducts();
  }

  bool get isAvailable => _available;
  List<ProductDetails> get products => _products;

  ProductDetails? productFor(SubscriptionPlan plan) {
    for (final p in _products) {
      if (p.id == plan.productId) return p;
    }
    return null;
  }

  /// Play/Store'dan ürün detaylarını çeker. UI'ın "₺149.99/ay" gibi mağaza
  /// fiyatını göstermesi için kullanılır (PricingService fallback'i).
  Future<void> refreshProducts() async {
    if (!_available) return;
    try {
      final ids = SubscriptionPlan.values.map((p) => p.productId).toSet();
      final response = await _iap.queryProductDetails(ids);
      if (response.error != null) {
        debugPrint(
            '[SubscriptionService] queryProductDetails error: ${response.error}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
            '[SubscriptionService] missing SKUs: ${response.notFoundIDs} '
            '(Play Console / App Store Connect\'te oluşturulmalı)');
      }
      _products = response.productDetails;
    } catch (e) {
      debugPrint('[SubscriptionService] refreshProducts error: $e');
    }
  }

  /// Satın alma akışını başlat. Play Billing dialog'u açılır; sonuç stream'den
  /// gelir. Buy() bekleyen completer yapısıyla sonucu döner.
  ///
  /// NOT: Eskiden debug modda mock akış devreye giriyordu (Play Console SKU
  /// eksik olduğunda otomatik premium grant). Kullanıcı talebi gereği bu
  /// devre dışı bırakıldı — premium SADECE gerçek satın alma ile aktive
  /// olur. SKU yüklü değilse `unavailable` dönülür, UI hata gösterir.
  Future<SubscriptionPurchaseResult> buy(SubscriptionPlan plan) async {
    if (!_available) return SubscriptionPurchaseResult.unavailable;

    final product = productFor(plan);
    if (product == null) {
      // Olası neden: Play Console'da SKU yaratılmamış veya app review aşamasında.
      debugPrint(
          '[SubscriptionService] product ${plan.productId} not loaded — '
          'Play Console konfigürasyonunu kontrol et.');
      return SubscriptionPurchaseResult.unavailable;
    }

    // Aynı anda birden fazla satın alma akışını engelle.
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      return SubscriptionPurchaseResult.error;
    }
    _activeCompleter = Completer<SubscriptionPurchaseResult>();

    final purchaseParam = PurchaseParam(productDetails: product);
    try {
      // buyNonConsumable Play Billing'te subscriptionlar dahil tüm
      // tekrar-tekrar-alınamayan ürünler için kullanılır.
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint('[SubscriptionService] buy error: $e');
      _completeActive(SubscriptionPurchaseResult.error);
    }

    return _activeCompleter!.future;
  }

  /// Apple Guideline 3.1.1: "Restore Purchases" butonu zorunludur.
  Future<void> restorePurchases() async {
    if (!_available) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[SubscriptionService] restorePurchases error: $e');
    }
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _completeActive(SubscriptionPurchaseResult.pending);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Server-side doğrulama burada yapılır. SADECE verifyPurchase
          // başarılı dönerse UI'a `success` bildirilir; aksi halde `error`
          // ile döner ki kullanıcıya "premium aktif" yalanı söylenmesin.
          final verified = await _grantPremiumFor(p);
          // Play Billing: complete edilmezse 3 gün içinde para iade edilir.
          // Doğrulama başarısız olsa da satın alma akışını kapatmak gerekir;
          // aksi halde aynı purchase tekrar tekrar stream'e düşer.
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          _completeActive(verified
              ? SubscriptionPurchaseResult.success
              : SubscriptionPurchaseResult.error);
          break;

        case PurchaseStatus.canceled:
          _completeActive(SubscriptionPurchaseResult.canceled);
          break;

        case PurchaseStatus.error:
          debugPrint('[SubscriptionService] purchase error: ${p.error}');
          _completeActive(SubscriptionPurchaseResult.error);
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          break;
      }
    }
  }

  void _completeActive(SubscriptionPurchaseResult result) {
    final c = _activeCompleter;
    if (c != null && !c.isCompleted) c.complete(result);
  }

  /// Başarılı satın alma → server-side doğrulama + Premium aktivasyonu.
  ///
  /// AKIŞ:
  ///   1) verifyPurchase Cloud Function çağrılır (purchaseToken / receipt
  ///      Google Play Developer API veya App Store Server API ile doğrulanır)
  ///   2) Function `users/{uid}/premium/state` doc'una `verified=true` yazar
  ///   3) purchaseToken → uid mapping de yazılır (RTDN webhook için)
  ///   4) Client local cache + revision tick (UI rebuild)
  ///
  /// firestore.rules client'in premium doc'una direkt yazmasını engelliyor;
  /// bu fonksiyon Cloud Function'a delege etmek zorunda. Cloud Function
  /// deploy edilmemişse hata loglanır ve premium aktive olmaz — bu doğru
  /// güvenlik davranışı (sahte purchase event'leri engellenmiş olur).
  Future<bool> _grantPremiumFor(PurchaseDetails p) async {
    final plan = SubscriptionPlan.byProductId(p.productID);
    if (plan == null) {
      debugPrint(
          '[SubscriptionService] unknown productID ${p.productID} — grant skipped');
      return false;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[SubscriptionService] no user — grant skipped');
      return false;
    }

    // 1) Server-side doğrulama — Google Play / App Store receipt validate
    //
    // ⚠️ Android için purchaseToken = serverVerificationData (Purchase.getPurchaseToken()).
    // p.purchaseID Android'de orderId döner ("GPA.xxxx-xxxx") — Google Play
    // Developer API ise PurchaseToken bekler. Yanlış kullanılırsa API 404 verir
    // ve RTDN webhook mapping de bulunamaz.
    final platform = Platform.isIOS ? 'ios' : 'android';
    final serverData = p.verificationData.serverVerificationData;
    // Android: purchaseToken (subscription doğrulama + RTDN mapping anahtarı).
    // iOS: base64-encoded App Store receipt.
    int? serverExpiryMs;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('verifyPurchase',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 30),
              ));
      final res = await callable.call(<String, dynamic>{
        'platform': platform,
        'productId': p.productID,
        if (platform == 'android') 'purchaseToken': serverData,
        if (platform == 'ios') 'receipt': serverData,
      });
      debugPrint('[SubscriptionService] verifyPurchase ok: ${res.data}');
      // Server'ın döndüğü gerçek expiry'yi al — local hesaplama yerine
      // grace period / trial / proration durumlarında daha doğru.
      if (res.data is Map) {
        final raw = (res.data as Map)['premiumUntil'];
        if (raw is int) serverExpiryMs = raw;
        if (raw is num) serverExpiryMs = raw.toInt();
      }

      // purchaseToken → uid mapping (RTDN webhook için).
      // RTDN payload'ı purchaseToken ile gelir; bu mapping olmadan webhook
      // hangi user'a yazacağını bilemez.
      if (platform == 'android' && serverData.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('purchaseTokens').doc(serverData).set({
            'uid': user.uid,
            'productId': p.productID,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('[SubscriptionService] token mapping fail: $e');
        }
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          '[SubscriptionService] verifyPurchase FAIL code=${e.code} msg=${e.message}');
      // Premium AKTİVE EDİLMEZ — doğrulama başarısız olursa kullanıcı
      // gerçek satın alma yapmış olsa bile riskli kabul edilir.
      return false;
    } catch (e) {
      debugPrint('[SubscriptionService] verifyPurchase error: $e');
      return false;
    }

    // 2) Local cache — UI hızlı yansıma için (Firestore stream gecikme yapabilir).
    // Server gerçek expiry döndürdüyse onu kullan; yoksa plan süresine düş.
    try {
      final until = serverExpiryMs != null
          ? DateTime.fromMillisecondsSinceEpoch(serverExpiryMs)
          : DateTime.now().add(Duration(days: plan.durationDays));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('premium_until_iso', until.toIso8601String());
      await prefs.setString('premium_source', 'subscription');
    } catch (e) {
      debugPrint('[SubscriptionService] local write error: $e');
    }

    // AI kota servisi premium durumunu hemen yenilesin → satın alma sonrası
    // kullanıcı uygulamayı kapatmadan sınırsız erişime geçer.
    try { await AiQuotaService.instance.refresh(); } catch (_) {}

    revision.value++;
    return true;
  }

  /// App shutdown / hot restart için.
  void dispose() {
    _streamSub?.cancel();
    _streamSub = null;
  }
}
