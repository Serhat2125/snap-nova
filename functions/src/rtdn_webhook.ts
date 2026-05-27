/**
 * rtdnWebhook — Google Play Real-Time Developer Notifications handler.
 *
 * Akış:
 *   Google Play → Pub/Sub topic (qualsar-rtdn) → bu function → Firestore sync.
 *
 * Yakalanan event'ler (SubscriptionNotificationType):
 *   1  SUBSCRIPTION_RECOVERED   (grace period sonrası geri aktif)
 *   2  SUBSCRIPTION_RENEWED      (otomatik yenilendi)
 *   3  SUBSCRIPTION_CANCELED     (kullanıcı iptal etti — abonelik dönem sonuna kadar aktif)
 *   4  SUBSCRIPTION_PURCHASED    (yeni satın alma)
 *   5  SUBSCRIPTION_ON_HOLD      (ödeme başarısız)
 *   6  SUBSCRIPTION_IN_GRACE_PERIOD (grace period başladı)
 *   7  SUBSCRIPTION_RESTARTED    (iptal sonrası tekrar abone oldu)
 *   8  SUBSCRIPTION_PRICE_CHANGE_CONFIRMED
 *   9  SUBSCRIPTION_DEFERRED
 *   10 SUBSCRIPTION_PAUSED
 *   11 SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED
 *   12 SUBSCRIPTION_REVOKED      (iade — anında erişimi kes!)
 *   13 SUBSCRIPTION_EXPIRED      (süresi doldu)
 *   20 SUBSCRIPTION_PENDING_PURCHASE_CANCELED
 *
 * Kurulum (DEPLOY ÖNCESİ):
 *   1) Google Cloud Console > Pub/Sub > Create topic: `qualsar-rtdn`
 *   2) Play Console > Settings > Monetization setup > Real-time developer
 *      notifications → Topic name: `projects/qualsar2-640f0/topics/qualsar-rtdn`
 *   3) Bu function deploy edilince Firebase otomatik subscription oluşturur.
 *
 * NOT: Pub/Sub mesajı içinde subscriptionId değil purchaseToken gelir.
 *      Firestore'da `purchaseTokens` koleksiyonunda token → uid mapping
 *      tutuyoruz (verifyPurchase yazarken oluşturur) — RTDN'de bu mapping
 *      ile uid'i bulup premium/state'i güncelliyoruz.
 */

import { onMessagePublished } from "firebase-functions/v2/pubsub";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { google } from "googleapis";

interface RtdnPayload {
  version: string;
  packageName: string;
  eventTimeMillis: string;
  subscriptionNotification?: {
    version: string;
    notificationType: number;
    purchaseToken: string;
    subscriptionId: string;
  };
  testNotification?: { version: string };
  oneTimeProductNotification?: unknown;
}

const TYPE_LABELS: Record<number, string> = {
  1: "RECOVERED",
  2: "RENEWED",
  3: "CANCELED",
  4: "PURCHASED",
  5: "ON_HOLD",
  6: "IN_GRACE_PERIOD",
  7: "RESTARTED",
  8: "PRICE_CHANGE_CONFIRMED",
  9: "DEFERRED",
  10: "PAUSED",
  11: "PAUSE_SCHEDULE_CHANGED",
  12: "REVOKED",
  13: "EXPIRED",
  20: "PENDING_PURCHASE_CANCELED",
};

export const rtdnWebhook = onMessagePublished(
  {
    topic: "qualsar-rtdn",
    region: "us-central1",
    timeoutSeconds: 30,
    memory: "256MiB",
    secrets: ["GOOGLE_PLAY_SA"],
  },
  async (event) => {
    const fs = getFirestore();
    let payload: RtdnPayload;
    try {
      const raw = Buffer.from(event.data.message.data, "base64").toString("utf-8");
      payload = JSON.parse(raw);
    } catch (e) {
      logger.error("[RTDN] payload parse fail:", e);
      return;
    }

    if (payload.testNotification) {
      logger.info("[RTDN] Test notification received — handshake OK");
      return;
    }

    const sn = payload.subscriptionNotification;
    if (!sn) {
      logger.warn("[RTDN] subscriptionNotification yok (ürün/test bildirimi):", payload);
      return;
    }

    const label = TYPE_LABELS[sn.notificationType] ?? `UNKNOWN(${sn.notificationType})`;
    logger.info(
      `[RTDN] ${label} — productId=${sn.subscriptionId} token=${sn.purchaseToken.substring(0, 20)}…`
    );

    // purchaseToken → uid mapping
    let uid: string | null = null;
    try {
      const mapping = await fs
        .collection("purchaseTokens")
        .doc(sn.purchaseToken)
        .get();
      uid = mapping.exists ? (mapping.data()?.uid ?? null) : null;
    } catch (e) {
      logger.error("[RTDN] mapping read fail:", e);
    }

    if (!uid) {
      logger.warn(
        `[RTDN] purchaseToken için uid mapping bulunamadı — token=${sn.purchaseToken.substring(0, 20)}… (verifyPurchase önce çalışmamış olabilir)`
      );
      return;
    }

    // Google Play Developer API ile current state'i çek
    let expiryMs = 0;
    let active = false;
    let stateLabel = "canceled";
    try {
      const res = await fetchSubscriptionState(
        payload.packageName,
        sn.purchaseToken
      );
      expiryMs = res.expiryMs;
      active = res.active;
      stateLabel = res.state;
    } catch (e) {
      logger.error("[RTDN] Google Play fetch fail:", e);
      // Fallback: notification type'a göre minimal güncelleme
      if (sn.notificationType === 12 || sn.notificationType === 13) {
        active = false; // REVOKED veya EXPIRED — anında kapat
        stateLabel = "canceled";
      }
    }

    // Firestore'a yaz
    // ⚠️ Alan adları premium_status.dart ile tutarlı olmalı: premiumUntil + lastGrantSource.
    try {
      await fs.collection("users").doc(uid).collection("premium").doc("state").set(
        {
          active,
          state: stateLabel,
          lastGrantSource: "subscription",
          productId: sn.subscriptionId,
          platform: "android",
          premiumUntil: expiryMs > 0 ? Timestamp.fromMillis(expiryMs) : FieldValue.delete(),
          lastRtdnEvent: label,
          lastRtdnAt: FieldValue.serverTimestamp(),
          verified: true,
        },
        { merge: true }
      );
      logger.info(`[RTDN] uid=${uid} updated — active=${active} state=${stateLabel}`);
    } catch (e) {
      logger.error(`[RTDN] firestore write fail uid=${uid}:`, e);
    }
  }
);

async function fetchSubscriptionState(
  packageName: string,
  purchaseToken: string
): Promise<{ expiryMs: number; active: boolean; state: string }> {
  const saJson = process.env.GOOGLE_PLAY_SA;
  if (!saJson) {
    throw new Error("GOOGLE_PLAY_SA secret yok");
  }
  const auth = new google.auth.GoogleAuth({
    credentials: JSON.parse(saJson),
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const androidPublisher = google.androidpublisher({ version: "v3", auth });
  const res = await androidPublisher.purchases.subscriptionsv2.get({
    packageName,
    token: purchaseToken,
  });
  const data = res.data;
  const subState = data.subscriptionState ?? "";
  const expiryIso = data.lineItems?.[0]?.expiryTime;
  const expiryMs = expiryIso ? Date.parse(expiryIso) : 0;
  const active =
    subState === "SUBSCRIPTION_STATE_ACTIVE" ||
    subState === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD";
  let stateLabel = "canceled";
  if (subState === "SUBSCRIPTION_STATE_ACTIVE") stateLabel = "active";
  else if (subState === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD") stateLabel = "in_grace";
  else if (subState === "SUBSCRIPTION_STATE_ON_HOLD") stateLabel = "on_hold";
  else if (subState === "SUBSCRIPTION_STATE_EXPIRED") stateLabel = "canceled";
  return { expiryMs, active, state: stateLabel };
}
