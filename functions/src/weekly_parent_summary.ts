/**
 * weekly_parent_summary — Haftada bir, bağlı her ebeveyne çocuğunun
 * son 7 günlük çalışma özetini push olarak gönderir.
 *
 * Akış:
 *   1. Scheduler tetikler (Pazartesi 09:00, Europe/Istanbul).
 *   2. collectionGroup('children') where status=='active' → tüm aktif
 *      (parentUid, childUid) çiftleri.
 *   3. Her çocuğun users/{childUid}/activity/{yyyy-MM-dd} son 7 gününü topla.
 *   4. Özet metin üret → notifications/{parentUid}/items'a doc yaz.
 *      (pushOnNotificationCreated trigger'ı push'u ebeveyne iletir.)
 *
 * Not: Aktivite hiç yoksa spam olmaması için bildirim gönderilmez.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

// Son 7 günün 'yyyy-MM-dd' anahtarları (bugün dahil), verilen TZ'ye göre.
function last7DateKeys(timeZone: string): string[] {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const keys: string[] = [];
  const now = Date.now();
  for (let i = 0; i < 7; i++) {
    const d = new Date(now - i * 86400000);
    keys.push(fmt.format(d)); // en-CA → yyyy-MM-dd
  }
  return keys;
}

function fmtDuration(sec: number): string {
  const m = Math.round(sec / 60);
  if (m < 1) return "1 dk";
  if (m < 60) return `${m} dk`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r === 0 ? `${h} sa` : `${h} sa ${r} dk`;
}

export const weeklyParentSummary = onSchedule(
  {
    schedule: "0 9 * * 1", // her Pazartesi 09:00
    timeZone: "Europe/Istanbul",
    region: "us-central1",
  },
  async () => {
    const db = getFirestore();
    const dateKeys = last7DateKeys("Europe/Istanbul");

    const links = await db
      .collectionGroup("children")
      .where("status", "==", "active")
      .get();

    if (links.empty) {
      logger.info("[weeklySummary] aktif bağlantı yok");
      return;
    }

    let sent = 0;
    for (const linkDoc of links.docs) {
      const parentUid = linkDoc.ref.parent.parent?.id;
      const childUid = linkDoc.id;
      if (!parentUid || !childUid) continue;
      const childName =
        (linkDoc.data().childDisplayName as string | undefined) ||
        (linkDoc.data().childUsername as string | undefined) ||
        "Çocuğun";

      try {
        // Son 7 gün activity dokümanlarını çek.
        const refs = dateKeys.map((k) =>
          db
            .collection("users")
            .doc(childUid)
            .collection("activity")
            .doc(k)
        );
        const snaps = await db.getAll(...refs);

        let focusSec = 0;
        let correct = 0;
        let wrong = 0;
        let activeDays = 0;
        const subjDur: Record<string, number> = {};

        for (const s of snaps) {
          if (!s.exists) continue;
          const d = s.data() || {};
          const fs = (d.focusSeconds as number) || 0;
          focusSec += fs;
          if (fs > 0) activeDays += 1;
          correct += (d.correctAnswers as number) || 0;
          wrong += (d.wrongAnswers as number) || 0;
          const sd = (d.subjectDurations as Record<string, number>) || {};
          for (const [k, v] of Object.entries(sd)) {
            subjDur[k] = (subjDur[k] || 0) + (v || 0);
          }
        }

        // Hiç aktivite yoksa bildirim gönderme (spam önleme).
        if (focusSec === 0 && correct + wrong === 0) continue;

        // En çok çalışılan ders.
        let topSubj = "";
        let topSec = 0;
        for (const [k, v] of Object.entries(subjDur)) {
          if (v > topSec) {
            topSec = v;
            topSubj = k;
          }
        }

        const answered = correct + wrong;
        const pct = answered > 0 ? Math.round((correct * 100) / answered) : 0;

        const parts: string[] = [];
        parts.push(`${activeDays}/7 gün aktifti`);
        parts.push(`toplam ${fmtDuration(focusSec)} çalıştı`);
        if (topSubj) parts.push(`en çok ${topSubj}`);
        if (answered > 0) parts.push(`test başarısı %${pct}`);

        const title = `${childName} — Haftalık Özet 📊`;
        const body = `${childName} bu hafta ${parts.join(", ")}.`;

        await db
          .collection("notifications")
          .doc(parentUid)
          .collection("items")
          .add({
            type: "weekly_summary",
            title,
            body,
            childUid,
            createdAt: FieldValue.serverTimestamp(),
            read: false,
          });
        sent += 1;
      } catch (e) {
        logger.warn(`[weeklySummary] çocuk=${childUid} özet hatası`, e);
      }
    }

    logger.info(`[weeklySummary] ${sent} ebeveyne özet gönderildi`);
  }
);
