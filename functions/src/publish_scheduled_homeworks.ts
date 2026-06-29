/**
 * publishScheduledHomeworks — Yayın zamanı (publishAt) gelmiş ZAMANLANMIŞ
 * ödevleri öğrencilere bildirir.
 *
 * Akış:
 *   1. Scheduler her 10 dakikada tetikler.
 *   2. collectionGroup('homeworks') where publishNotified==false → henüz
 *      bildirilmemiş ödevler (taslaklar + zamanlanmışlar).
 *   3. status=='published' VE publishAt<=now olanları seç (taslaklar atlanır).
 *   4. O sınıftaki her öğrenciye 'homework_assigned' bildirimi yaz
 *      (pushOnNotificationCreated push'u iletir) + publishNotified=true işaretle.
 *
 * Not: assignToClass/publishDraft, yayın zamanı GEÇMİŞSE publishNotified=true
 * yazar; bu function yalnızca ileri tarihe zamanlananları yakalar.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

export const publishScheduledHomeworks = onSchedule(
  {
    schedule: "*/10 * * * *", // her 10 dakikada bir
    timeZone: "Europe/Istanbul",
    region: "us-central1",
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();

    // Henüz bildirilmemiş ödevler (tek-alan eşitlik → otomatik index).
    const pending = await db
      .collectionGroup("homeworks")
      .where("publishNotified", "==", false)
      .get();

    if (pending.empty) {
      logger.info("[publishHw] bekleyen zamanlanmış ödev yok");
      return;
    }

    let published = 0;
    for (const hwDoc of pending.docs) {
      const data = hwDoc.data() || {};
      const status = (data.status as string) || "published";
      const publishAt = data.publishAt as Timestamp | undefined;

      // Taslak → atla. publishAt yok ya da gelecekte → atla.
      if (status === "draft") continue;
      if (!publishAt || publishAt.toMillis() > now.toMillis()) continue;

      const classRef = hwDoc.ref.parent.parent;
      if (!classRef) continue;
      const title = (data.title as string) || "Yeni ödev";
      const dueAt = data.dueAt as Timestamp | undefined;

      try {
        const students = await classRef.collection("students").get();
        const batch = db.batch();
        for (const s of students.docs) {
          const notifRef = db
            .collection("notifications")
            .doc(s.id)
            .collection("items")
            .doc();
          batch.set(notifRef, {
            type: "homework_assigned",
            fromUsername: "Öğretmen",
            fromDisplayName: title,
            when: FieldValue.serverTimestamp(),
            read: false,
            classId: classRef.id,
            homeworkId: hwDoc.id,
            ...(dueAt ? { dueAt } : {}),
          });
        }
        // Idempotency işareti.
        batch.set(
          hwDoc.ref,
          { publishNotified: true },
          { merge: true }
        );
        await batch.commit();
        published += 1;
      } catch (e) {
        logger.warn(`[publishHw] ödev=${hwDoc.id} bildirim hatası`, e);
      }
    }

    logger.info(`[publishHw] ${published} zamanlanmış ödev yayınlandı`);
  }
);
