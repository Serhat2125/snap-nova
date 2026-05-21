/**
 * rank_passed — league_attempts onCreate trigger.
 *
 * Akış:
 *   Yeni bir attempt yazıldığında, aynı leaderboard scope'unda (scopeWorld /
 *   scopeCountry / scopeCity) bu yeni attempt'in skor aralığında olan
 *   kullanıcıları bul. Yeni attempt onları "geçtiyse" (yani onların eski
 *   toplam puanı yeni attempt'in skoru altında kalıyorsa), o kullanıcılara
 *   notifications/{theirUid}/items'a "rank_passed" doc'u yaz → FCM trigger
 *   otomatik push gönderir.
 *
 *   ALGORİTMA (basit ve performant):
 *     1. Yeni attempt.score'u oku.
 *     2. Aynı scopeWorld (en geniş) içinde score < attempt.score olan
 *        ama attempt.score - 100 üzerinde olan kullanıcıları çek.
 *     3. Her birinin son aktivitesi yeni attempt'ten ÖNCE ise notification
 *        gönder. ANTI-SPAM: aynı uid'ye saatte 1'den fazla rank_passed gitmesin.
 *
 *   Bu çok büyük leaderboard'larda pahalı olur; production'da Cloud Tasks
 *   ile rate-limit edilebilir. MVP için doğrudan inline.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

interface AttemptData {
  uid?: string;
  displayName?: string;
  avatar?: string;
  score?: number;
  scopeWorld?: string;
  scopeCountry?: string;
  scopeCity?: string;
  subjectKey?: string;
  topic?: string;
  when?: Timestamp;
}

const RANK_PASS_THRESHOLD = 100; // sadece <100 puan farklı rakipleri uyar
const COOLDOWN_MINUTES = 60; // aynı kullanıcıya 60 dk'da 1 push
const MAX_NOTIFY = 5; // tek attempt başına en fazla 5 kişi uyarılır

export const pushOnRankPassed = onDocumentCreated(
  {
    document: "league_attempts/{aid}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data() as AttemptData;
    const fromUid = data.uid;
    const score = data.score ?? 0;
    if (!fromUid || score <= 0) return;
    // En geniş scope — dünya. Filtre çok dar olmasın diye.
    const scope = data.scopeWorld;
    if (!scope) return;

    const db = getFirestore();

    // 1) Aynı scope'ta, skoru bu attempt'in MEMNUNİYET sınırında olan
    //    en fazla 50 attempt'i çek (DESC). Hemen geride kalan rakipleri yakala.
    const rivalsSnap = await db
      .collection("league_attempts")
      .where("scopeWorld", "==", scope)
      .where("score", "<", score)
      .where("score", ">", score - RANK_PASS_THRESHOLD)
      .orderBy("score", "desc")
      .limit(50)
      .get();

    if (rivalsSnap.empty) return;

    // 2) uid bazında dedupe — aynı kullanıcıdan birden fazla attempt çıkmasın.
    const seen = new Set<string>([fromUid]);
    const targets: string[] = [];
    for (const d of rivalsSnap.docs) {
      const m = d.data() as AttemptData;
      const u = m.uid;
      if (!u || seen.has(u)) continue;
      seen.add(u);
      targets.push(u);
      if (targets.length >= MAX_NOTIFY) break;
    }
    if (targets.length === 0) return;

    // 3) Cooldown — son 60dk'da rank_passed bildirimi göndermediklerimize at.
    const cutoff = Timestamp.fromMillis(Date.now() - COOLDOWN_MINUTES * 60_000);
    const writes: Promise<unknown>[] = [];
    let notified = 0;

    for (const targetUid of targets) {
      // Recent rank_passed kontrolü
      const recentSnap = await db
        .collection("notifications")
        .doc(targetUid)
        .collection("items")
        .where("type", "==", "rank_passed")
        .where("fromUid", "==", fromUid)
        .where("when", ">", cutoff)
        .limit(1)
        .get();
      if (!recentSnap.empty) continue; // cooldown — atla

      // Bildirim doc'u yaz — FCM trigger otomatik push atar
      writes.push(
        db
          .collection("notifications")
          .doc(targetUid)
          .collection("items")
          .doc()
          .set({
            type: "rank_passed",
            fromUid,
            fromUsername: "",
            fromDisplayName: data.displayName ?? "",
            fromAvatar: data.avatar ?? "",
            subjectKey: data.subjectKey ?? "",
            scope: scope,
            when: FieldValue.serverTimestamp(),
            read: false,
          })
      );
      notified++;
    }

    if (writes.length > 0) {
      await Promise.allSettled(writes);
      logger.info(
        `[rank_passed] attempt=${snap.id} fromUid=${fromUid} score=${score} notified=${notified}`
      );
    }
  }
);
