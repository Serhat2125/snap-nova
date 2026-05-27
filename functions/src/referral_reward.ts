/**
 * referral_reward — referrals/{ownerUid}.invitedUsers değişince tetiklenir.
 *
 *   • invitedUsers boyutu ≥ targetCount (3) ise davet edene 30 gün Premium
 *     grant. Mevcut süre varsa üzerine eklenir (kümülatif).
 *   • Idempotency: aynı doc'ta `rewardGrantedAt` varsa skip → duplicate yok.
 *
 * KRITIK NEDEN (client-side neden olmaz):
 *   Firestore rules `users/{uid}/{sub=**}` sahibi-only. Client tarafında
 *   ReferralService _grantPremium owner'ın `users/{ownerUid}/premium/state`
 *   doc'una yazmaya çalışır → cross-user write → DENIED. Bu function admin
 *   SDK ile güvenli ve idempotent grant yapar.
 *
 * NOT: Davet edilen yeni kullanıcı 7 günlük "hoşgeldin" ödülünü
 * `redeemCode()` içinde KENDİ uid'sine yazarak alır (cross-user değil).
 */

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const TARGET_COUNT = 3;
const REWARD_DAYS = 30;

export const onReferralCompleted = onDocumentUpdated(
  {
    document: "referrals/{ownerUid}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const ownerUid = event.params.ownerUid;

    const beforeCount = Array.isArray(before.invitedUsers)
      ? before.invitedUsers.length
      : 0;
    const afterCount = Array.isArray(after.invitedUsers)
      ? after.invitedUsers.length
      : 0;

    if (afterCount <= beforeCount) return;

    if (afterCount < TARGET_COUNT) {
      logger.info(
        `[referral] ${ownerUid} progress ${afterCount}/${TARGET_COUNT}`
      );
      return;
    }

    if (after.rewardGrantedAt) {
      logger.info(`[referral] ${ownerUid} ödül zaten verilmiş, skip`);
      return;
    }

    const db = getFirestore();
    const premiumRef = db
      .collection("users")
      .doc(ownerUid)
      .collection("premium")
      .doc("state");
    const referralRef = db.collection("referrals").doc(ownerUid);

    try {
      await db.runTransaction(async (tx) => {
        const premiumSnap = await tx.get(premiumRef);
        const referralSnap = await tx.get(referralRef);

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
        const newUntil = new Date(base.getTime() + REWARD_DAYS * 86400 * 1000);

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
          rewardDays: REWARD_DAYS,
        });
      });
      logger.info(
        `[referral] ✅ ${ownerUid} → ${REWARD_DAYS} gün premium grant (toplam invite=${afterCount})`
      );

      // Bildirim doc'u — FCM trigger pushOnNotificationCreated yakalar
      try {
        await db
          .collection("notifications")
          .doc(ownerUid)
          .collection("items")
          .doc()
          .set({
            type: "streak_milestone",
            fromUsername: "QuAlsar",
            fromDisplayName: "QuAlsar Ödül",
            when: FieldValue.serverTimestamp(),
            read: false,
            milestone: "referral_3_friends",
            rewardDays: REWARD_DAYS,
          });
      } catch (e) {
        logger.warn(`[referral] notification yazılamadı: ${e}`);
      }
    } catch (e) {
      logger.error(`[referral] reward grant fail ownerUid=${ownerUid}`, e);
    }
  }
);
