/**
 * parent_fanout — ÇOCUĞUN sınıf yaşamındaki olayları bağlı VELİLERE bildirim
 * olarak kopyalar. Ebeveyn panelindeki gelen kutusu yalnız bu tipleri
 * gösterir (notifications_inbox_screen._kParentNotifTypes):
 *
 *   • child_homework      — öğretmen çocuğa ödev verdi/yayınladı
 *   • child_class_invite  — öğretmen çocuğu derse davet etti
 *   • child_announcement  — öğretmen sınıfa duyuru/mesaj attı
 *   • child_submission    — çocuk ödevini teslim etti
 *
 * Kaynaklar:
 *   1) fanoutChildNotifToParents — çocuğun notifications/{uid}/items doc'u
 *      oluşunca (homework_assigned/published, class_invite,
 *      class_announcement) velilere kopya yazar. Fan-out tipleri kaynak
 *      listesinde OLMADIĞI için sonsuz döngü oluşmaz.
 *   2) notifyParentsOnSubmission — submission status'u submitted/late'e
 *      GEÇİNCE velilere teslim bildirimi yazar.
 *
 * Yazılan doc'lar title/body taşır → pushOnNotificationCreated bunları
 * olduğu gibi FCM push olarak iletir.
 */

import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import {
  getFirestore,
  FieldValue,
  Firestore,
} from "firebase-admin/firestore";

/** Çocuğun AKTİF bağlı veli uid'leri (child_invites/{child}/from). */
async function activeParentsOf(
  db: Firestore,
  childUid: string
): Promise<string[]> {
  const snap = await db
    .collection("child_invites")
    .doc(childUid)
    .collection("from")
    .where("status", "==", "active")
    .get();
  return snap.docs.map((d) => d.id);
}

async function childDisplayName(
  db: Firestore,
  childUid: string
): Promise<string> {
  const u = await db.collection("users").doc(childUid).get();
  return (u.data()?.displayName || u.data()?.username || "Çocuğun").toString();
}

/** Velilere aynı bildirimi toplu yazar. */
async function writeToParents(
  db: Firestore,
  parents: string[],
  payload: Record<string, unknown>
): Promise<void> {
  const batch = db.batch();
  for (const p of parents) {
    batch.set(
      db.collection("notifications").doc(p).collection("items").doc(),
      { ...payload, when: FieldValue.serverTimestamp(), read: false }
    );
  }
  await batch.commit();
}

interface SrcNotif {
  type?: string;
  fromDisplayName?: string;
  homeworkTitle?: string;
  className?: string;
  subject?: string;
  message?: string;
  classId?: string;
  homeworkId?: string;
}

export const fanoutChildNotifToParents = onDocumentCreated(
  {
    document: "notifications/{uid}/items/{nid}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() as SrcNotif;
    const type = data.type ?? "";
    // Yalnız çocuğun SINIF olayları veliye kopyalanır.
    const relevant = [
      "homework_assigned",
      "homework_published",
      "class_invite",
      "class_announcement",
    ];
    if (!relevant.includes(type)) return;
    const childUid = event.params.uid;
    const db = getFirestore();
    try {
      const parents = await activeParentsOf(db, childUid);
      if (parents.length === 0) return;
      const child = await childDisplayName(db, childUid);
      const className = (data.className ?? "").toString();
      // homework_assigned ödev başlığını fromDisplayName'de taşır (bkz.
      // homework_service.assignToClass); homework_published homeworkTitle'da.
      const hwTitle = (
        data.homeworkTitle ||
        data.fromDisplayName ||
        "Ödev"
      ).toString();
      let payload: Record<string, unknown> | null = null;
      if (type === "homework_assigned" || type === "homework_published") {
        payload = {
          type: "child_homework",
          title: "Çocuğuna yeni ödev verildi 📚",
          body: className
            ? `${child} — ${className}: "${hwTitle}"`
            : `${child} için yeni ödev: "${hwTitle}"`,
        };
      } else if (type === "class_invite") {
        const teacher = (data.fromDisplayName ?? "Öğretmen").toString();
        payload = {
          type: "child_class_invite",
          title: "Öğretmen çocuğunu derse davet etti 🎓",
          body: `${teacher}, ${child} adlı çocuğunu "${
            data.subject || className
          }" dersine davet etti`,
        };
      } else if (type === "class_announcement") {
        const teacher = (data.fromDisplayName ?? "Öğretmen").toString();
        payload = {
          type: "child_announcement",
          title: `Öğretmenden duyuru 📢${className ? ` — ${className}` : ""}`,
          body: data.message
            ? `${teacher}: "${data.message}"`
            : `${teacher} sınıfa yeni bir duyuru paylaştı`,
        };
      }
      if (payload == null) return;
      payload["classId"] = data.classId ?? "";
      payload["childUid"] = childUid;
      await writeToParents(db, parents, payload);
      logger.info(
        `[parentFanout] ${type} → ${parents.length} veli (child=${childUid})`
      );
    } catch (e) {
      logger.error("[parentFanout] fail", e);
    }
  }
);

interface SubmissionDoc {
  status?: string;
}

export const notifyParentsOnSubmission = onDocumentWritten(
  {
    document:
      "classes/{classId}/homeworks/{homeworkId}/submissions/{studentUid}",
    region: "us-central1",
  },
  async (event) => {
    const before = event.data?.before?.data() as SubmissionDoc | undefined;
    const after = event.data?.after?.data() as SubmissionDoc | undefined;
    if (!after) return; // silme
    const done = (s?: string) => s === "submitted" || s === "late";
    // Yalnız teslim ANINDA (status geçişinde) bildir — aiComment/cevap
    // paylaşımı gibi sonraki güncellemelerde tekrar tetiklenmesin.
    if (!done(after.status) || done(before?.status)) return;
    const { classId, homeworkId, studentUid } = event.params;
    const db = getFirestore();
    try {
      const parents = await activeParentsOf(db, studentUid);
      if (parents.length === 0) return;
      const child = await childDisplayName(db, studentUid);
      const hwSnap = await db
        .collection("classes")
        .doc(classId)
        .collection("homeworks")
        .doc(homeworkId)
        .get();
      const hwTitle = (hwSnap.data()?.title ?? "Ödev").toString();
      const clsSnap = await db.collection("classes").doc(classId).get();
      const className = (clsSnap.data()?.name ?? "").toString();
      await writeToParents(db, parents, {
        type: "child_submission",
        title: `${child} ödevini teslim etti ✅`,
        body: className ? `"${hwTitle}" — ${className}` : `"${hwTitle}"`,
        classId,
        homeworkId,
        childUid: studentUid,
      });
      logger.info(
        `[parentFanout] teslim → ${parents.length} veli (child=${studentUid})`
      );
    } catch (e) {
      logger.error("[parentFanout] submission fail", e);
    }
  }
);
