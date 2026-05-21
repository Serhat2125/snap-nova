/**
 * duelo_invite_accepted — duelo_invites/{targetUid}/inbox/{iid} status
 * 'accepted' olunca tetiklenir, iki taraf için duelo_sessions doc'u açar
 * + her iki tarafa bildirim yazar (FCM trigger yakalar).
 *
 * Akış:
 *   1. Target user B davet doc'unu accept et → status='accepted'.
 *   2. Bu trigger çalışır:
 *      - sessionId üret (sortedUids + timestamp)
 *      - duelo_sessions/{sessionId} oluştur — iki taraf da okur, soruları
 *        ilk yazan AI ile üretir (istemci tarafı).
 *      - Her iki tarafa "düello başladı" bildirimi.
 *   3. notifications/{uid}/items/{auto} yazılır → FCM trigger push atar.
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

export const onDueloInviteAccepted = onDocumentUpdated(
  {
    document: "duelo_invites/{targetUid}/inbox/{iid}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    // Sadece status pending → accepted geçişini yakala
    if (before.status === "accepted" || after.status !== "accepted") return;

    const targetUid = event.params.targetUid; // davet edilen (B)
    const inviterUid = after.fromUid as string | undefined ?? before.fromUid;
    if (!inviterUid) {
      logger.warn("duelo_invite: fromUid yok, atla");
      return;
    }

    const db = getFirestore();

    // sessionId — iki uid'yi sortla + timestamp (her zaman aynı format).
    const uids = [inviterUid, targetUid].sort();
    const sid = `${uids[0]}_${uids[1]}_${Date.now()}`;

    // Profilleri çek (snapshot olarak session'a göm)
    const [aSnap, bSnap] = await Promise.all([
      db.collection("users").doc(inviterUid).get(),
      db.collection("users").doc(targetUid).get(),
    ]);
    const a = aSnap.data() ?? {};
    const b = bSnap.data() ?? {};

    // duelo_sessions doc'u — istemciler bu doc'u izleyip sorulara akar.
    await db.collection("duelo_sessions").doc(sid).set({
      sessionId: sid,
      participants: uids,
      inviterUid,
      targetUid,
      inviter: {
        uid: inviterUid,
        username: a.username ?? "",
        displayName: a.displayName ?? "",
        avatar: a.avatar ?? "",
      },
      target: {
        uid: targetUid,
        username: b.username ?? "",
        displayName: b.displayName ?? "",
        avatar: b.avatar ?? "",
      },
      subjectKey: after.subjectKey ?? null,
      topic: after.topic ?? null,
      status: "ready", // ready → playing → finished
      createdAt: FieldValue.serverTimestamp(),
    });

    // İki tarafa "düello başladı" bildirimi → FCM otomatik push
    const writes = [
      db
        .collection("notifications")
        .doc(inviterUid)
        .collection("items")
        .doc()
        .set({
          type: "duelo_invite",
          fromUid: targetUid,
          fromUsername: b.username ?? "",
          fromDisplayName: b.displayName ?? "",
          fromAvatar: b.avatar ?? "",
          sessionId: sid,
          subjectKey: after.subjectKey ?? null,
          when: FieldValue.serverTimestamp(),
          read: false,
        }),
      db
        .collection("notifications")
        .doc(targetUid)
        .collection("items")
        .doc()
        .set({
          type: "duelo_invite",
          fromUid: inviterUid,
          fromUsername: a.username ?? "",
          fromDisplayName: a.displayName ?? "",
          fromAvatar: a.avatar ?? "",
          sessionId: sid,
          subjectKey: after.subjectKey ?? null,
          when: FieldValue.serverTimestamp(),
          read: false,
        }),
    ];
    await Promise.allSettled(writes);
    logger.info(`[duelo] session=${sid} created for ${inviterUid} ↔ ${targetUid}`);

    // Davet doc'una sessionId işle — istemci tarafı session'a yönlendirir.
    await event.data?.after.ref.update({
      sessionId: sid,
      acceptedAt: FieldValue.serverTimestamp(),
    });
  }
);
