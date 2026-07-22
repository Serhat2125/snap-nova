/**
 * dailyReportDigest — Kullanıcı geri bildirimlerinin GÜNLÜK ÖZETİ.
 *
 * Her sabah 08:00 (Europe/Istanbul) son 24 saatte gelen kayıtları sayar:
 *   • feedback              (Profil → Geri Bildirim)        createdAt
 *   • feedbacks             (AI çözüm 👍/👎)                 tarih
 *   • incorrect_reports     ("çözüm yanlış")                reportedAt
 *   • inappropriate_reports (uygunsuz içerik)               reportedAt
 *   • question_error_reports("bu soru hatalı" düz kopyası)  reportedAt
 *
 * Toplam > 0 ise admin hesabına (ADMIN_EMAIL) notifications/{uid}/items
 * dokümanı yazar → mevcut pushOnNotificationCreated CF'i telefona push atar.
 * Hiç kayıt yoksa bildirim GÖNDERİLMEZ (gürültü olmasın).
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";

const ADMIN_EMAIL = "serhatdsme@gmail.com";

/** Sayılacak koleksiyonlar ve zaman alanları (koleksiyon, alan, kısa etiket). */
const SOURCES: [string, string, string][] = [
  ["feedback", "createdAt", "geri bildirim"],
  ["feedbacks", "tarih", "çözüm oyu"],
  ["incorrect_reports", "reportedAt", "yanlış çözüm"],
  ["inappropriate_reports", "reportedAt", "uygunsuz içerik"],
  ["question_error_reports", "reportedAt", "hatalı soru"],
];

export const dailyReportDigest = onSchedule(
  {
    schedule: "every day 08:00",
    timeZone: "Europe/Istanbul",
    region: "us-central1",
    timeoutSeconds: 120,
  },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);

    const parts: string[] = [];
    let total = 0;
    for (const [col, field, label] of SOURCES) {
      try {
        const snap = await db
          .collection(col)
          .where(field, ">", cutoff)
          .count()
          .get();
        const n = snap.data().count;
        if (n > 0) {
          total += n;
          parts.push(`${n} ${label}`);
        }
      } catch (e) {
        console.warn(`[digest] ${col} sayılamadı:`, e);
      }
    }

    if (total === 0) {
      console.log("[digest] son 24 saatte kayıt yok — bildirim gönderilmedi");
      return;
    }

    let adminUid: string;
    try {
      adminUid = (await getAuth().getUserByEmail(ADMIN_EMAIL)).uid;
    } catch (e) {
      console.error(`[digest] admin hesabı bulunamadı (${ADMIN_EMAIL}):`, e);
      return;
    }

    await db
      .collection("notifications")
      .doc(adminUid)
      .collection("items")
      .add({
        type: "admin_daily_digest",
        title: `📋 Günlük özet: ${total} yeni kayıt`,
        body: `${parts.join(" · ")} — detay: Firebase Console → Firestore`,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    console.log(`[digest] gönderildi → ${total} kayıt (${parts.join(", ")})`);
  }
);
