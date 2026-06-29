/**
 * publishScheduledAnnouncements — Yayın zamanı (publishAt) gelmiş ZAMANLANMIŞ
 * duyuruları öğrencilere bildirir + içerik akışına ve ebeveyn şeridine yansıtır.
 *
 * Akış:
 *   1. Scheduler her 10 dakikada tetikler.
 *   2. collectionGroup('scheduled_announcements') where announceNotified==false
 *      → henüz dağıtılmamış zamanlanmış duyurular.
 *   3. publishAt<=now olanları seç (ileri tarihliler atlanır).
 *   4. O sınıftaki her öğrenciye 'class_announcement' bildirimi yaz, sınıf
 *      content akışına 'announcement' kaydı düş, sınıf statusMessage'ını
 *      güncelle + announceNotified=true işaretle (idempotency).
 *
 * ClassService.scheduleAnnouncement bu kayıtları üretir; ClassService
 * .publishAnnouncement ise anlık dağıtımı uygular (bu function'ı atlar).
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

export const publishScheduledAnnouncements = onSchedule(
  {
    schedule: "*/10 * * * *", // her 10 dakikada bir
    timeZone: "Europe/Istanbul",
    region: "us-central1",
  },
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();

    // Henüz dağıtılmamış zamanlanmış duyurular (tek-alan eşitlik → auto index).
    const pending = await db
      .collectionGroup("scheduled_announcements")
      .where("announceNotified", "==", false)
      .get();

    if (pending.empty) {
      logger.info("[publishAnnounce] bekleyen zamanlanmış duyuru yok");
      return;
    }

    let published = 0;
    for (const annDoc of pending.docs) {
      const data = annDoc.data() || {};
      const publishAt = data.publishAt as Timestamp | undefined;

      // Yayın zamanı yok ya da gelecekte → atla.
      if (!publishAt || publishAt.toMillis() > now.toMillis()) continue;

      const classRef = annDoc.ref.parent.parent;
      if (!classRef) continue;
      const message = (data.message as string) || "";
      if (!message.trim()) {
        // Boş duyuru: idempotency işaretle, geç.
        await annDoc.ref.set({ announceNotified: true }, { merge: true });
        continue;
      }
      const className = (data.className as string) || "";
      const subject = (data.subject as string) || "";
      const teacherName = (data.teacherName as string) || "Öğretmen";

      try {
        // 1) Öğrenci bildirimleri (parça parça commit — 500 limiti).
        const students = await classRef.collection("students").get();
        let batch = db.batch();
        let ops = 0;
        for (const s of students.docs) {
          const notifRef = db
            .collection("notifications")
            .doc(s.id)
            .collection("items")
            .doc();
          batch.set(notifRef, {
            type: "class_announcement",
            classId: classRef.id,
            className,
            message,
            fromDisplayName: teacherName,
            when: FieldValue.serverTimestamp(),
            read: false,
          });
          if (++ops >= 400) {
            await batch.commit();
            batch = db.batch();
            ops = 0;
          }
        }
        if (ops > 0) await batch.commit();

        // 2) Sınıf içerik akışına kalıcı duyuru kaydı.
        await classRef.collection("content").doc().set({
          teacherUid: (data.teacherUid as string) || "",
          type: "announcement",
          title: "Duyuru",
          topic: "",
          subject,
          payload: { message, teacherName },
          sharedAt: FieldValue.serverTimestamp(),
        });

        // 3) Ebeveyn şeridi için son duyuruyu sınıf dokümanına yansıt.
        await classRef.set(
          {
            statusMessage: message,
            statusUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true }
        );

        // 4) Idempotency işareti.
        await annDoc.ref.set({ announceNotified: true }, { merge: true });
        published += 1;
      } catch (e) {
        logger.warn(`[publishAnnounce] duyuru=${annDoc.id} dağıtım hatası`, e);
      }
    }

    logger.info(`[publishAnnounce] ${published} zamanlanmış duyuru yayınlandı`);
  }
);
