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
  milestone?: string;
  rewardDays?: number;
  // Dinamik bildirimler (örn. haftalık ebeveyn özeti) title/body'yi doc'a
  // doğrudan yazar; buildContent bunları olduğu gibi kullanır.
  title?: string;
  body?: string;
}

/**
 * Bildirim türünü, kullanıcı ayarlarındaki kategori anahtarına eşler.
 * (Bkz. PreferencesSyncService._notifKeys + bildirim ayarları sheet'i.)
 * null dönerse → kategorisiz/sistem bildirimi, her zaman gönderilir.
 */
function categoryForType(type?: string): string | null {
  switch (type) {
    case "friend_request":
    case "friend_accepted":
    case "referral_joined":
    case "referral_complete":
      return "friend_request";
    case "duelo_invite":
      return "duello_invite";
    case "rank_passed":
      return "league_update";
    case "streak_milestone":
      return "streak_alert";
    // ── Öğretmen kategorileri (panel ayarındaki toggle'ları gerçekten gate'le) ──
    case "homework_submission": // öğrenci ödevi teslim etti → öğretmene
      return "homework_submission";
    case "student_joined": // yeni öğrenci sınıfa katıldı → öğretmene
      return "student_joined";
    case "class_activity":
    case "class_announcement":
    case "announcement":
    case "homework_published":
    case "homework_all_done":
    case "material":
      return "class_activity";
    default:
      return null;
  }
}

function buildContent(data: NotifData): { title: string; body: string } {
  // Doc'a doğrudan yazılmış dinamik metin varsa onu kullan.
  if (data.title && data.body) {
    return { title: data.title, body: data.body };
  }
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
    case "referral_joined": {
      const progress = data.subjectKey || "";
      return {
        title: "Arkadaşın QuAlsar'a katıldı!",
        body: `Davet hedefin: ${progress} — devam et!`,
      };
    }
    case "referral_complete":
      return {
        title: "Tebrikler! 30 gün Premium kazandın",
        body: "3 arkadaşını davet ettin — Premium ödülün aktif!",
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
    const db = getFirestore();

    // 0) Kullanıcının bildirim tercihlerini oku — kapalı kategoriye veya
    //    ana anahtar kapalıyken HİÇ push gönderme. (İn-app inbox doc'u yine
    //    durur; sadece push pop-up bastırılır.) Tercih okunamazsa gönder.
    try {
      const prefSnap = await db
        .collection("users")
        .doc(uid)
        .collection("preferences")
        .doc("main")
        .get();
      const notif =
        (prefSnap.data()?.notifications as Record<string, boolean>) || {};
      if (notif.master === false) {
        logger.info(`[push] master kapalı uid=${uid} — atlandı`);
        return;
      }
      const cat = categoryForType(data.type);
      if (cat && notif[cat] === false) {
        logger.info(`[push] '${cat}' kategorisi kapalı uid=${uid} — atlandı`);
        return;
      }
    } catch (e) {
      logger.warn("[push] tercih okunamadı, yine de gönderiliyor", e);
    }

    // 1) Hedefin fcmTokens'larını çek
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
