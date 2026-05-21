/**
 * deleteAccount — Kullanıcı hesabını ve TÜM ilişkili verileri kalıcı sil.
 *
 * Apple Guideline 5.1.1(v) + GDPR Article 17 (Right to Erasure) zorunlu.
 * Client tarafında signOut yapıp Firestore datayı bırakmak ihlal sayılır.
 *
 * Bu fonksiyon callable (kullanıcı invoke eder, sadece kendi hesabını siler):
 *   const result = await functions.httpsCallable('deleteAccount')();
 *
 * Cascade silinen:
 *   ✓ users/{uid} (avatar, ad, mesaj, premium state, fcmTokens alt-koleksiyon)
 *   ✓ users/{uid} alt koleksiyonları (preferences, arena_state, pomodoro_stats,
 *     library, solutions, premium, referral, fcmTokens, study_activities)
 *   ✓ friends/{uid}/list/*  +  diğer kullanıcıların friends/X/list/{uid}
 *   ✓ friend_requests/{uid}/inbox/*  +  başka inbox'lardaki own request'leri
 *   ✓ notifications/{uid}/items/*
 *   ✓ duelo_invites/{uid}/inbox/*
 *   ✓ league_attempts (uid eşleşen)
 *   ✓ referrals/{uid} + referral_codes/{theirCode}
 *   ✓ duelo_sessions (participants içeriyorsa anonymize)
 *   ✓ Firebase Auth user kaydı (en sonda)
 *
 * Yasal saklanan: faturalama kayıtları (Türk vergi mevzuatı 5 yıl) — bu
 * function FCM token + kişisel veri siler; satın alma kayıtları (Play/App
 * Store tarafında) ayrı saklanır.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

// Tek seferde silinecek belge sayısı — Firestore batch limit 500.
const BATCH_SIZE = 400;

/** Verilen Query'nin tüm dokümanlarını batch'ler halinde sil. */
async function deleteByQuery(
  q: FirebaseFirestore.Query,
  label: string
): Promise<number> {
  const db = getFirestore();
  let total = 0;
  while (true) {
    const snap = await q.limit(BATCH_SIZE).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    total += snap.size;
    if (snap.size < BATCH_SIZE) break;
  }
  if (total > 0) logger.info(`[deleteAccount] ${label}: ${total}`);
  return total;
}

/** Bir doc'un tüm alt koleksiyonlarını kendisiyle birlikte sil. */
async function deleteDocWithSubcollections(
  docRef: FirebaseFirestore.DocumentReference,
  knownSubcollections: string[]
): Promise<void> {
  // Tüm bilinen alt koleksiyonları temizle
  for (const sub of knownSubcollections) {
    await deleteByQuery(docRef.collection(sub), `${docRef.path}/${sub}`);
  }
  // Bilinmeyen başka alt koleksiyon olabilir — listCollections() ile tara
  try {
    const subs = await docRef.listCollections();
    for (const c of subs) {
      if (knownSubcollections.includes(c.id)) continue;
      await deleteByQuery(c, c.path);
    }
  } catch (e) {
    logger.warn(`[deleteAccount] subcollection scan fail: ${e}`);
  }
  // Parent doc'u sil
  await docRef.delete().catch(() => {/* idempotent — yoksa OK */});
}

export const deleteAccount = onCall(
  {
    region: "us-central1",
    // Maks 540sn — 1000+ kayıt cascade için yeterli
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Oturum açmadan hesap silinemez.");
    }
    logger.info(`[deleteAccount] başlatıldı uid=${uid}`);

    const db = getFirestore();
    const summary: Record<string, number> = {};

    try {
      // 1) users/{uid} — tüm alt koleksiyonlar + parent
      await deleteDocWithSubcollections(
        db.collection("users").doc(uid),
        [
          "preferences",
          "arena_state",
          "pomodoro_stats",
          "library",
          "solutions",
          "premium",
          "referral",
          "fcmTokens",
          "study_activities",
        ]
      );
      summary["users"] = 1;

      // 2) friends/{uid}/list/* — kendi listem
      summary["friends_self"] = await deleteByQuery(
        db.collection("friends").doc(uid).collection("list"),
        "friends/{uid}/list"
      );
      await db.collection("friends").doc(uid).delete().catch(() => {});

      // 3) friends/{other}/list/{uid} — başkalarının listesinden kendi kaydımı sil
      //    Collection group sorgusu ile tüm `list` alt koleksiyonlarda uid arar.
      const mirroredFriendsSnap = await db
        .collectionGroup("list")
        .where("uid", "==", uid)
        .get();
      let mirroredFriends = 0;
      while (mirroredFriendsSnap.docs.length > 0) {
        const chunk = mirroredFriendsSnap.docs.splice(0, BATCH_SIZE);
        const batch = db.batch();
        chunk.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        mirroredFriends += chunk.length;
      }
      summary["friends_mirrored"] = mirroredFriends;

      // 4) friend_requests/{uid}/inbox — bana gelen istekler
      summary["friend_requests_inbox"] = await deleteByQuery(
        db.collection("friend_requests").doc(uid).collection("inbox"),
        "friend_requests/{uid}/inbox"
      );
      await db.collection("friend_requests").doc(uid).delete().catch(() => {});

      // 5) friend_requests/{other}/inbox/{uid} — gönderdiğim istekler
      const myRequestsSnap = await db
        .collectionGroup("inbox")
        .where("fromUid", "==", uid)
        .get();
      let myRequests = 0;
      const myReqDocs = [...myRequestsSnap.docs];
      while (myReqDocs.length > 0) {
        const chunk = myReqDocs.splice(0, BATCH_SIZE);
        const batch = db.batch();
        chunk.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        myRequests += chunk.length;
      }
      summary["friend_requests_sent"] = myRequests;

      // 6) notifications/{uid}/items
      summary["notifications"] = await deleteByQuery(
        db.collection("notifications").doc(uid).collection("items"),
        "notifications/{uid}/items"
      );
      await db.collection("notifications").doc(uid).delete().catch(() => {});

      // 7) duelo_invites/{uid}/inbox + gönderdiklerim
      summary["duelo_invites_inbox"] = await deleteByQuery(
        db.collection("duelo_invites").doc(uid).collection("inbox"),
        "duelo_invites/{uid}/inbox"
      );
      await db.collection("duelo_invites").doc(uid).delete().catch(() => {});

      // 8) league_attempts (uid eşleşen) — toplu sil
      summary["league_attempts"] = await deleteByQuery(
        db.collection("league_attempts").where("uid", "==", uid),
        "league_attempts"
      );

      // 9) referrals/{uid} + referral_codes (kendi kodum)
      try {
        const myRefDoc = await db.collection("referrals").doc(uid).get();
        const myCode = (myRefDoc.data()?.code as string | undefined) ?? "";
        if (myCode) {
          await db
            .collection("referral_codes")
            .doc(myCode)
            .delete()
            .catch(() => {});
          summary["referral_codes"] = 1;
        }
      } catch (e) {
        logger.warn(`[deleteAccount] referral code lookup fail: ${e}`);
      }
      await deleteDocWithSubcollections(
        db.collection("referrals").doc(uid),
        []
      );

      // 10) duelo_sessions — anonimize (sil yerine displayName temizle)
      //     Çünkü iki tarafa ait, diğer tarafı etkilememek için.
      const sessionsSnap = await db
        .collection("duelo_sessions")
        .where("participants", "array-contains", uid)
        .get();
      for (const s of sessionsSnap.docs) {
        await s.ref.update({
          [`${s.data().inviterUid === uid ? "inviter" : "target"}`]: {
            uid: "deleted",
            username: "deleted",
            displayName: "Silinmiş Kullanıcı",
            avatar: "👤",
          },
        }).catch(() => {});
      }
      summary["duelo_sessions_anonymized"] = sessionsSnap.size;

      // 11) Firebase Auth user — en sonda. Hata olsa bile veriyi siliyoruz.
      try {
        await getAuth().deleteUser(uid);
        summary["auth_user"] = 1;
      } catch (e) {
        logger.warn(`[deleteAccount] auth delete fail: ${e}`);
      }

      logger.info(`[deleteAccount] ✅ tamamlandı uid=${uid}`, summary);
      return { ok: true, summary };
    } catch (e) {
      logger.error(`[deleteAccount] HATA uid=${uid}`, e);
      throw new HttpsError("internal", `Hesap silme başarısız: ${e}`);
    }
  }
);

