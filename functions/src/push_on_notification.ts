/**
 * push_on_notification — notifications/{uid}/items/{nid} koleksiyonuna
 * yeni doc yazılınca FCM push gönderir.
 *
 * Akış:
 *   1. Yeni notification doc oluşur (örn. arkadaşlık isteği, düello daveti).
 *   2. Trigger: hedef uid'nin fcmTokens alt koleksiyonundan tüm token'ları çek.
 *   3. Tüm token'lara multicast push gönder (title/body type'a göre üretilir).
 *   4. Geçersiz/inactive token'lar (FCM not-registered hatası dönen) silinir.
 *
 * Bağımlılık:
 *   • firebase-functions v2 onDocumentCreated
 *   • firebase-admin messaging
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging, MulticastMessage } from "firebase-admin/messaging";

interface NotifData {
  type?: string;
  fromUid?: string;
  fromUsername?: string;
  fromDisplayName?: string;
  targetUsername?: string;
  subjectKey?: string;
}

function buildContent(data: NotifData): { title: string; body: string } {
  const who = data.fromDisplayName || data.fromUsername || "Birisi";
  switch (data.type) {
    case "friend_request":
      return {
        title: "Yeni arkadaşlık isteği",
        body: `${who} sana arkadaşlık isteği gönderdi`,
      };
    case "friend_accepted":
      return {
        title: "İsteğin kabul edildi",
        body: `${who} arkadaşlık isteğini kabul etti`,
      };
    case "duelo_invite":
      return {
        title: "Düello daveti",
        body: `${who} seninle yarışmak istiyor`,
      };
    case "rank_passed":
      return {
        title: "Sıralamada geçildin",
        body: `${who} seni sıralamada geçti — geri al!`,
      };
    case "streak_milestone":
      return {
        title: "Streak ödülü",
        body: `Üst üste günlerin yeni rekor`,
      };
    default:
      return {
        title: "QuAlsar",
        body: "Yeni bir bildirimin var",
      };
  }
}

export const pushOnNotificationCreated = onDocumentCreated(
  {
    document: "notifications/{uid}/items/{nid}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn("notification doc snap yok");
      return;
    }
    const uid = event.params.uid;
    const data = snap.data() as NotifData;

    // 1) Hedefin fcmTokens'larını çek
    const db = getFirestore();
    const tokensSnap = await db
      .collection("users")
      .doc(uid)
      .collection("fcmTokens")
      .get();

    if (tokensSnap.empty) {
      logger.info(`[push] no tokens for uid=${uid}`);
      return;
    }

    const tokens = tokensSnap.docs.map((d) => d.id);
    const { title, body } = buildContent(data);

    // 2) Multicast push gönder
    const message: MulticastMessage = {
      tokens,
      notification: { title, body },
      data: {
        type: data.type || "unknown",
        fromUid: data.fromUid || "",
        fromUsername: data.fromUsername || "",
        targetUsername: data.targetUsername || "",
        nid: event.params.nid,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "qualsar_default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const res = await getMessaging().sendEachForMulticast(message);
      logger.info(
        `[push] uid=${uid} sent=${res.successCount}/${tokens.length}`
      );

      // 3) Geçersiz token'ları temizle
      const toDelete: Promise<unknown>[] = [];
      res.responses.forEach((r, i) => {
        if (!r.success) {
          const err = r.error?.code || "";
          if (
            err === "messaging/invalid-registration-token" ||
            err === "messaging/registration-token-not-registered"
          ) {
            toDelete.push(
              db
                .collection("users")
                .doc(uid)
                .collection("fcmTokens")
                .doc(tokens[i])
                .delete()
            );
          }
        }
      });
      if (toDelete.length > 0) {
        await Promise.allSettled(toDelete);
        logger.info(`[push] cleaned ${toDelete.length} stale tokens`);
      }
    } catch (e) {
      logger.error("[push] send fail", e);
    }

    // 4) Bildirim doc'una "pushed" işareti — debug ve analytics için
    try {
      await snap.ref.update({ pushedAt: FieldValue.serverTimestamp() });
    } catch (_) {/* yok say */}
  }
);
