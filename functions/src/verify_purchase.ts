/**
 * verifyPurchase — Client'tan gelen IAP receipt'i server-side doğrular.
 *
 * Akış:
 *   1) Client (SubscriptionService) purchase complete olunca bu fonksiyonu
 *      callable olarak çağırır: { platform, productId, purchaseToken/receipt }
 *   2) Bu fonksiyon Google Play Developer API / App Store Server API ile
 *      receipt'i doğrular (gerçek satın alma mı, aktif mi, expiry vb.)
 *   3) Geçerliyse `users/{uid}/premium/state` doc'una yazar — client direkt
 *      yazamaz (firestore.rules `allow write: if false`).
 *
 * Güvenlik: Rooted cihaz / Frida bypass'la sahte purchase event'i client'tan
 * direkt Firestore'a yazılamaz çünkü rules engelliyor; bu function ise ancak
 * gerçek bir Google Play Developer API response'u geçerli kabul ediyor.
 *
 * Kurulum gereksinimleri (DEPLOY ÖNCESİ):
 *   ANDROID:
 *     - Google Cloud Console'da service account oluştur, Google Play
 *       Developer API enable et, JSON key indir.
 *     - Play Console > Settings > API access > service account'a "View
 *       financial data" + "Manage orders" izni ver.
 *     - `firebase functions:config:set google_play.service_account="$(cat sa.json)"`
 *       VEYA Secret Manager kullan (önerilen): `firebase functions:secrets:set GOOGLE_PLAY_SA`
 *
 *   iOS:
 *     - App Store Connect > Keys > In-App Purchase key oluştur (P8).
 *     - Issuer ID + Key ID + private key'i Secret Manager'a koy.
 *
 * NOT: Test ortamında bu function deploy edilmeden de SubscriptionService
 *      çalışır; sadece "verified" işareti olmadan premium yazılmaz. Prod'da
 *      ZORUNLU.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { google } from "googleapis";

const PLAN_DURATIONS_MS: Record<string, number> = {
  qualsar_premium_monthly: 30 * 24 * 60 * 60 * 1000,
  qualsar_premium_quarterly: 90 * 24 * 60 * 60 * 1000,
  qualsar_premium_yearly: 365 * 24 * 60 * 60 * 1000,
};

interface VerifyData {
  platform: "android" | "ios";
  productId: string;
  purchaseToken?: string; // Android
  receipt?: string;        // iOS (base64)
  packageName?: string;    // Android — varsayılan com.qualsar.ai
}

export const verifyPurchase = onCall<VerifyData>(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    memory: "256MiB",
    // Functions v2 secrets — bunlar deklare edilmezse process.env undefined döner.
    //   firebase functions:secrets:set GOOGLE_PLAY_SA < service-account.json
    // iOS yayını yapılınca ek olarak:
    //   firebase functions:secrets:set APP_STORE_SHARED_SECRET
    //   ve aşağıdaki array'i ["GOOGLE_PLAY_SA","APP_STORE_SHARED_SECRET"] yap.
    // Şu an APP_STORE_SHARED_SECRET deklare edilmediği için iOS dalı
    // process.env.APP_STORE_SHARED_SECRET = undefined görüp fail-closed döner —
    // bu doğru güvenlik davranışı (sahte iOS receipt'leri reddedilir).
    secrets: ["GOOGLE_PLAY_SA"],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Auth gerekli");
    }

    const { platform, productId, purchaseToken, receipt } = request.data;
    if (!platform || !productId) {
      throw new HttpsError("invalid-argument", "platform ve productId zorunlu");
    }
    if (!PLAN_DURATIONS_MS[productId]) {
      throw new HttpsError("invalid-argument", `Geçersiz productId: ${productId}`);
    }

    const fs = getFirestore();
    let expiryMs: number;
    let receiptIdentifier: string;
    let state: "active" | "in_grace" | "on_hold" | "canceled";

    try {
      if (platform === "android") {
        if (!purchaseToken) {
          throw new HttpsError("invalid-argument", "purchaseToken zorunlu (Android)");
        }
        const result = await verifyAndroid({
          packageName: request.data.packageName ?? "com.qualsar.ai",
          productId,
          purchaseToken,
        });
        expiryMs = result.expiryMs;
        receiptIdentifier = purchaseToken;
        state = result.state;
      } else {
        if (!receipt) {
          throw new HttpsError("invalid-argument", "receipt zorunlu (iOS)");
        }
        const result = await verifyIos({ productId, receipt });
        expiryMs = result.expiryMs;
        receiptIdentifier = result.transactionId;
        state = result.state;
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error(`[verifyPurchase] validation fail uid=${uid}:`, e);
      throw new HttpsError("internal", `Doğrulama başarısız: ${(e as Error).message}`);
    }

    // Firestore'a yaz — premium/state doc.
    // ⚠️ ALAN ADLARI: premium_status.dart `premiumUntil` ve `lastGrantSource`
    // okuyor (referral path ile tutarlı). BU İSİMLERİ DEĞİŞTİRME — değişirse
    // client cloud state'i bulamaz.
    try {
      await fs.collection("users").doc(uid).collection("premium").doc("state").set(
        {
          active: state === "active" || state === "in_grace",
          state, // active | in_grace | on_hold | canceled
          lastGrantSource: "subscription",
          productId,
          platform,
          purchasedAt: FieldValue.serverTimestamp(),
          premiumUntil: Timestamp.fromMillis(expiryMs),
          receiptIdentifier,
          verified: true,
          lastVerifiedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      logger.info(
        `[verifyPurchase] OK uid=${uid} productId=${productId} expires=${new Date(expiryMs).toISOString()}`
      );
      return {
        ok: true,
        premiumUntil: expiryMs,
        state,
      };
    } catch (e) {
      logger.error(`[verifyPurchase] firestore write fail uid=${uid}:`, e);
      throw new HttpsError("internal", "Premium kayıt edilemedi");
    }
  }
);

// ─── Android: Google Play Developer API ile subscription doğrula ───────────
async function verifyAndroid(opts: {
  packageName: string;
  productId: string;
  purchaseToken: string;
}): Promise<{
  expiryMs: number;
  state: "active" | "in_grace" | "on_hold" | "canceled";
}> {
  const saJson = process.env.GOOGLE_PLAY_SA;
  if (!saJson) {
    throw new HttpsError(
      "failed-precondition",
      "GOOGLE_PLAY_SA secret konfigüre edilmemiş. " +
      "Firebase Secret Manager'a JSON key ekle."
    );
  }
  const credentials = JSON.parse(saJson);

  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const androidPublisher = google.androidpublisher({ version: "v3", auth });

  const res = await androidPublisher.purchases.subscriptionsv2.get({
    packageName: opts.packageName,
    token: opts.purchaseToken,
  });

  const data = res.data;
  // SubscriptionPurchaseV2:
  //   subscriptionState: SUBSCRIPTION_STATE_ACTIVE | _IN_GRACE_PERIOD |
  //                      _ON_HOLD | _CANCELED | _EXPIRED | _PAUSED
  //   lineItems[0].expiryTime: ISO timestamp
  const subState = data.subscriptionState ?? "";
  const lineItem = data.lineItems?.[0];
  const expiryIso = lineItem?.expiryTime;
  if (!expiryIso) {
    throw new HttpsError("internal", "Google Play response'da expiryTime yok");
  }
  const expiryMs = Date.parse(expiryIso);
  if (isNaN(expiryMs)) {
    throw new HttpsError("internal", `Invalid expiry: ${expiryIso}`);
  }

  let mapped: "active" | "in_grace" | "on_hold" | "canceled" = "canceled";
  if (subState === "SUBSCRIPTION_STATE_ACTIVE") mapped = "active";
  else if (subState === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD") mapped = "in_grace";
  else if (subState === "SUBSCRIPTION_STATE_ON_HOLD") mapped = "on_hold";

  // Süresi geçmişse force canceled
  if (expiryMs < Date.now() - 60_000) mapped = "canceled";

  return { expiryMs, state: mapped };
}

// ─── iOS: App Store /verifyReceipt ile receipt doğrula ──────────────────────
// App Store Server API v2 daha modern (JWT-signed) ama P8 key + Issuer ID
// gerektirir. verifyReceipt deprecated ama hâlâ çalışıyor ve sadece shared
// secret istiyor — App Store Connect → Apps → QuAlsar → App Information
// → App-Specific Shared Secret'tan alınır. Production'da Apple
// önce production endpoint'ini dener, 21007 dönerse sandbox'a fallback
// yapılır (Apple'ın tavsiye ettiği akış).
async function verifyIos(opts: {
  productId: string;
  receipt: string;
}): Promise<{
  expiryMs: number;
  state: "active" | "in_grace" | "on_hold" | "canceled";
  transactionId: string;
}> {
  const sharedSecret = process.env.APP_STORE_SHARED_SECRET;
  if (!sharedSecret) {
    throw new HttpsError(
      "failed-precondition",
      "APP_STORE_SHARED_SECRET secret konfigüre edilmemiş. " +
      "App Store Connect → Apps → QuAlsar → App Information → " +
      "App-Specific Shared Secret'tan alıp Firebase Secret Manager'a ekle."
    );
  }

  const body = JSON.stringify({
    "receipt-data": opts.receipt,
    "password": sharedSecret,
    "exclude-old-transactions": true,
  });

  // 1) Production endpoint
  let json = await postVerify("https://buy.itunes.apple.com/verifyReceipt", body);

  // 2) Sandbox fallback — Apple'ın istediği akış: prod 21007 dönerse sandbox dene.
  if (json.status === 21007) {
    json = await postVerify("https://sandbox.itunes.apple.com/verifyReceipt", body);
  }

  if (json.status !== 0) {
    throw new HttpsError(
      "internal",
      `App Store verifyReceipt status=${json.status} — geçersiz receipt`
    );
  }

  // latest_receipt_info en son transaction'ı (yenileme dahil) verir.
  const items = Array.isArray(json.latest_receipt_info) ? json.latest_receipt_info : [];
  // İlgili productId için en yeni transaction
  const matching = items
    .filter((it: { product_id?: string }) => it.product_id === opts.productId)
    .sort((a: { expires_date_ms?: string }, b: { expires_date_ms?: string }) =>
      Number(b.expires_date_ms ?? 0) - Number(a.expires_date_ms ?? 0)
    );
  const latest = matching[0];
  if (!latest) {
    throw new HttpsError(
      "internal",
      `App Store receipt'inde ${opts.productId} için transaction yok`
    );
  }

  const expiryMs = Number(latest.expires_date_ms ?? 0);
  if (!expiryMs) {
    throw new HttpsError("internal", "App Store response'da expires_date_ms yok");
  }

  // pending_renewal_info ile iptal/grace durumunu kontrol et.
  const pending = Array.isArray(json.pending_renewal_info) ? json.pending_renewal_info : [];
  const renewalInfo = pending.find(
    (r: { product_id?: string }) => r.product_id === opts.productId
  );
  let state: "active" | "in_grace" | "on_hold" | "canceled" = "canceled";
  if (expiryMs > Date.now()) {
    state = "active";
  } else if (renewalInfo?.is_in_billing_retry_period === "1") {
    state = "on_hold"; // ödeme başarısız, retry sürüyor
  } else if (renewalInfo?.grace_period_expires_date_ms) {
    const graceMs = Number(renewalInfo.grace_period_expires_date_ms);
    if (graceMs > Date.now()) state = "in_grace";
  }

  return {
    expiryMs,
    state,
    transactionId: String(latest.original_transaction_id ?? latest.transaction_id ?? "ios"),
  };
}

interface VerifyReceiptResponse {
  status: number;
  latest_receipt_info?: Array<Record<string, unknown>>;
  pending_renewal_info?: Array<Record<string, unknown>>;
  receipt?: Record<string, unknown>;
}

async function postVerify(url: string, body: string): Promise<VerifyReceiptResponse> {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
  });
  if (!res.ok) {
    throw new HttpsError(
      "internal",
      `App Store HTTP ${res.status} — ${url}`
    );
  }
  return (await res.json()) as VerifyReceiptResponse;
}
