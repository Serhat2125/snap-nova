/**
 * push_on_teacher_note — öğretmen bir öğrenciye PAYLAŞILAN not/takdir
 * yazınca (classes/{c}/students/{s}/notes) bağlı VELİLERE bildirim kaydı
 * oluşturur. Bildirim doc'u yazılınca pushOnNotificationCreated FCM
 * push'unu otomatik gönderir.
 *
 * Neden burada: öğretmen istemcisi veli uid'lerini OKUYAMAZ
 * (child_invites rules: yalnız çocuk + ilgili veli). Admin SDK rules'u
 * bypass eder. Öğrenci bildirimi istemciden yazılır (class_service.addNote)
 * — burada yalnız veliler hedeflenir, çift bildirim olmaz.
 *
 * sharedWithParent == false (öğretmene özel gözlem) → HİÇ bildirim yok.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

interface NoteData {
  text?: string;
  sharedWithParent?: boolean;
  kind?: string;
}

export const pushOnTeacherNote = onDocumentCreated(
  {
    document: "classes/{classId}/students/{studentUid}/notes/{noteId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() as NoteData;
    if (data.sharedWithParent !== true) return; // özel not → veliye gitmez
    const { classId, studentUid } = event.params;
    const db = getFirestore();
    try {
      // Aktif bağlı veliler — child_invites/{child}/from/*.status == 'active'
      const parents = await db
        .collection("child_invites")
        .doc(studentUid)
        .collection("from")
        .where("status", "==", "active")
        .get();
      if (parents.empty) {
        logger.info(`[teacherNote] bağlı veli yok (child=${studentUid})`);
        return;
      }
      const clsSnap = await db.collection("classes").doc(classId).get();
      const className = (clsSnap.data()?.name ?? "").toString();
      const childSnap = await db.collection("users").doc(studentUid).get();
      const childName = (
        childSnap.data()?.displayName ||
        childSnap.data()?.username ||
        "Çocuğun"
      ).toString();
      const msg = (data.text ?? "").toString();
      const praise = data.kind === "praise";

      const batch = db.batch();
      for (const p of parents.docs) {
        batch.set(
          db.collection("notifications").doc(p.id).collection("items").doc(),
          {
            type: "teacher_note",
            className,
            message: msg,
            title: praise
              ? `${childName} için öğretmen takdiri 🌟`
              : `${childName} için öğretmen notu 📝`,
            body: className ? `${className}: “${msg}”` : `“${msg}”`,
            when: FieldValue.serverTimestamp(),
            read: false,
          }
        );
      }
      await batch.commit();
      logger.info(
        `[teacherNote] ${parents.size} veliye bildirim yazıldı ` +
          `(child=${studentUid}, class=${classId})`
      );
    } catch (e) {
      logger.error("[teacherNote] fail", e);
    }
  }
);
