/**
 * referral_reward — referrals/{ownerUid}.invitedUsers değişince tetiklenir.
 *
 * Akış:
 *   1. Yeni invitee tespit edilir → invitee'ye 7 gün Premium grant (trial bitişi
 *      baz alınır → signup'tan 14 gün toplam kullanım).
 *   2. Davet edenin ilerleme bildirimi (1/3, 2/3, 3/3) gönderilir.
 *   3. 3. kişide davet edene 30 gün Premium grant + "tamamlandı" bildirimi.
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

const TARGET_COUNT = 3;
const INVITER_REWARD_DAYS = 30;
const INVITEE_REWARD_DAYS = 7;
const TRIAL_DAYS = 7;

/**
 * Bir kullanıcıya N gün Premium grant eder (admin SDK — rules kısıtı yok).
 * Base = max(şimdi, trial sonu, mevcut premiumUntil)
 * Böylece trial döneminde giren kullanıcı hem 7 gün trial hem 7 gün referral
 * → signup'tan itibaren 14 gün kesintisiz Premium alır.
 */
async function grantPremiumToUser(
  db: FirebaseFirestore.Firestore,
  uid: string,
  days: number,
  source: string
): Promise<void> {
  const premiumRef = db
    .collection("users")
    .doc(uid)
    .collection("premium")
    .doc("state");

  // Trial bitiş tarihini Auth'dan al (transaction dışında — async getUser)
  let trialEnd: Date | null = null;
  try {
    const userRecord = await getAuth().getUser(uid);
    const creationTime = new Date(userRecord.metadata.creationTime);
    trialEnd = new Date(creationTime.getTime() + TRIAL_DAYS * 86400 * 1000);
  } catch (e) {
    logger.warn(`[referral] trial sonu hesaplanamadı uid=${uid}`, e);
  }

  await db.runTransaction(async (tx) => {
    const premiumSnap = await tx.get(premiumRef);
    const now = new Date();
    let base = now;

    // Trial sonu > now ise trial sonu baz
    if (trialEnd && trialEnd > base) base = trialEnd;

    // Mevcut premium daha ilerideyse onu baz al
    const premiumData = premiumSnap.data();
    if (premiumData) {
      const until = premiumData.premiumUntil;
      if (until instanceof Timestamp) {
        const t = until.toDate();
        if (t > base) base = t;
      }
    }

    const newUntil = new Date(base.getTime() + days * 86400 * 1000);
    tx.set(
      premiumRef,
      {
        premiumUntil: Timestamp.fromDate(newUntil),
        lastGrantSource: source,
        lastGrantAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

export const onReferralCompleted = onDocumentUpdated(
  {
    document: "referrals/{ownerUid}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const ownerUid = event.params.ownerUid;
    const db = getFirestore();

    const beforeList: Array<{ uid: string }> = Array.isArray(before.invitedUsers)
      ? before.invitedUsers
      : [];
    const afterList: Array<{ uid: string }> = Array.isArray(after.invitedUsers)
      ? after.invitedUsers
      : [];

    const beforeCount = beforeList.length;
    const afterCount = afterList.length;

    // Değişiklik yoksa çık
    if (afterCount <= beforeCount) return;

    // ── 1) Yeni eklenen invitee(ler)'ye Premium grant ────────────────────────
    const beforeUids = new Set(beforeList.map((u) => u.uid).filter(Boolean));
    const newInvitees = afterList.filter(
      (u) => u.uid && !beforeUids.has(u.uid)
    );

    for (const invitee of newInvitees) {
      if (!invitee.uid) continue;
      try {
        await grantPremiumToUser(
          db,
          invitee.uid,
          INVITEE_REWARD_DAYS,
          "referral_redeem"
        );
        logger.info(
          `[referral] invitee ${invitee.uid} → ${INVITEE_REWARD_DAYS} gün premium`
        );
      } catch (e) {
        logger.error(
          `[referral] invitee premium grant fail uid=${invitee.uid}`,
          e
        );
      }
    }

    // ── 2) Davet edene ilerleme bildirimi (her yeni üye) ─────────────────────
    const notifType =
      afterCount >= TARGET_COUNT ? "referral_complete" : "referral_joined";

    try {
      await db
        .collection("notifications")
        .doc(ownerUid)
        .collection("items")
        .doc()
        .set({
          type: notifType,
          fromUsername: "QuAlsar",
          fromDisplayName: "QuAlsar Ödül",
          subjectKey: `${afterCount}/${TARGET_COUNT}`,
          when: FieldValue.serverTimestamp(),
          read: false,
        });
    } catch (e) {
      logger.warn(`[referral] ilerleme bildirimi yazılamadı ownerUid=${ownerUid}`, e);
    }

    // ── 3) 3. kişide davet edene 30 gün Premium grant ───────────────────────
    if (afterCount < TARGET_COUNT) {
      logger.info(
        `[referral] ${ownerUid} ilerleme ${afterCount}/${TARGET_COUNT}`
      );
      return;
    }

    // Idempotency — daha önce verilmişse atla
    if (after.rewardGrantedAt) {
      logger.info(`[referral] ${ownerUid} ödül zaten verilmiş, skip`);
      return;
    }

    const referralRef = db.collection("referrals").doc(ownerUid);

    try {
      // Davet edenin Premium grant'ı (30 gün) + idempotency işareti
      const premiumRef = db
        .collection("users")
        .doc(ownerUid)
        .collection("premium")
        .doc("state");

      await db.runTransaction(async (tx) => {
        const premiumSnap = await tx.get(premiumRef);
        const referralSnap = await tx.get(referralRef);

        // Double-check idempotency
        if (referralSnap.data()?.rewardGrantedAt) {
          logger.info(`[referral] tx içinde duplicate fark edildi, skip`);
          return;
        }

        const now = new Date();
        let base = now;
        const premiumData = premiumSnap.data();
        if (premiumData) {
          const until = premiumData.premiumUntil;
          if (until instanceof Timestamp) {
            const t = until.toDate();
            if (t > now) base = t;
          }
        }
        const newUntil = new Date(
          base.getTime() + INVITER_REWARD_DAYS * 86400 * 1000
        );

        tx.set(
          premiumRef,
          {
            premiumUntil: Timestamp.fromDate(newUntil),
            lastGrantSource: "referral_complete",
            lastGrantAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        tx.update(referralRef, {
          rewardGrantedAt: FieldValue.serverTimestamp(),
          rewardDays: INVITER_REWARD_DAYS,
        });
      });

      logger.info(
        `[referral] ✅ ${ownerUid} → ${INVITER_REWARD_DAYS} gün premium (3 davet tamamlandı)`
      );
    } catch (e) {
      logger.error(
        `[referral] inviter reward grant fail ownerUid=${ownerUid}`,
        e
      );
    }
  }
);
