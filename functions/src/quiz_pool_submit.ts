/**
 * quiz_pool_submit — Bilgi Ligi soru havuzuna SUNUCU doğrulamalı yazım.
 *
 * NEDEN
 *   quiz_pool istemciden doğrudan yazılabiliyordu; 100'lük havuz tavanı
 *   yalnızca İSTEMCİDE denetleniyordu. Kötü niyetli bir istemci API ile
 *   havuzu sınırsız çöp soruyla doldurabilir (içerik zehirlenmesi) veya
 *   depolamayı şişirebilirdi.
 *
 *   Bu callable:
 *     1. Şema doğrulama — soru/şık/uzunluk sınırları.
 *     2. Havuz tavanı — quiz_pool_counters/{hash} sayaç dokümanıyla
 *        TRANSACTION içinde kesin cap (count() yarışı yok).
 *     3. Rate limit — kullanıcı başına min. aralık + günlük tavan
 *        (rate_limits/quizpool_{uid}).
 *
 *   Rules tarafında quiz_pool create artık admin-only'dir; tek yazım yolu
 *   bu fonksiyondur. (Eski APK'lardaki doğrudan create denemesi rules'tan
 *   döner; istemci kodu bunu zaten "havuz dolu" gibi sessizce karşılıyor.)
 *
 * İSTEMCİ: lib/features/league/quiz_pool_service.dart → addToPool()
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const POOL_CAP = 100;          // havuz başına test tavanı (istemcideki kQuizPoolCap ile aynı)
const MIN_INTERVAL_SEC = 5;    // iki havuz yazımı arası min. süre
const DAILY_CAP = 60;          // kullanıcı başına günlük havuz yazım tavanı
const MAX_QUESTIONS = 15;
const MAX_Q_LEN = 1500;
const MAX_OPT_LEN = 500;
const MAX_EXPL_LEN = 2500;

function asTrimmedString(v: unknown, maxLen: number): string {
  return typeof v === "string" ? v.trim().slice(0, maxLen) : "";
}

/** FNV-1a 32-bit — poolKey → sayaç doküman id'si (dart questionHash ile uyumlu olması gerekmez). */
function fnv1a(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16);
}

function dayKey(ms: number): string {
  const d = new Date(ms);
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${d.getUTCFullYear()}-${m}-${day}`;
}

export const addQuizPoolTest = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Oturum gerekli.");
    }

    // ── 1) Girdi doğrulama ──────────────────────────────────────────────
    const d = (req.data ?? {}) as Record<string, unknown>;
    const poolKey = asTrimmedString(d.poolKey, 220);
    const country = asTrimmedString(d.country, 8);
    const level = asTrimmedString(d.level, 40);
    const grade = asTrimmedString(d.grade, 60);
    const subjectKey = asTrimmedString(d.subjectKey, 80);
    const topic = asTrimmedString(d.topic, 160) || "*";

    if (poolKey.length < 5 || poolKey.split("|").length < 5) {
      throw new HttpsError("invalid-argument", "poolKey geçersiz.");
    }
    if (!country || !level || !grade || !subjectKey) {
      throw new HttpsError("invalid-argument", "profil alanları zorunlu.");
    }

    const rawQuestions = d.questions;
    if (!Array.isArray(rawQuestions) || rawQuestions.length === 0 ||
        rawQuestions.length > MAX_QUESTIONS) {
      throw new HttpsError("invalid-argument", "questions 1..15 olmalı.");
    }
    const questions = rawQuestions.map((raw) => {
      const q = (raw ?? {}) as Record<string, unknown>;
      const text = asTrimmedString(q.q, MAX_Q_LEN);
      const explanation = asTrimmedString(q.explanation, MAX_EXPL_LEN);
      const optsRaw = q.options;
      if (text.length === 0) {
        throw new HttpsError("invalid-argument", "boş soru metni.");
      }
      if (!Array.isArray(optsRaw) || optsRaw.length < 2 || optsRaw.length > 6) {
        throw new HttpsError("invalid-argument", "şık sayısı 2..6 olmalı.");
      }
      const options = optsRaw.map((o) => asTrimmedString(o, MAX_OPT_LEN));
      if (options.some((o) => o.length === 0)) {
        throw new HttpsError("invalid-argument", "boş şık.");
      }
      const correct = typeof q.correct === "number" ? Math.round(q.correct) : -1;
      if (correct < 0 || correct >= options.length) {
        throw new HttpsError("invalid-argument", "correct indeksi aralık dışı.");
      }
      return { q: text, options, correct, explanation };
    });

    // ── 2) Transaction: rate limit + kesin cap + yazım ──────────────────
    const db = getFirestore();
    const now = Date.now();
    const counterRef = db
      .collection("quiz_pool_counters")
      .doc(fnv1a(poolKey));
    const rateRef = db.collection("rate_limits").doc(`quizpool_${uid}`);
    const poolRef = db.collection("quiz_pool").doc();
    const today = dayKey(now);

    const accepted = await db.runTransaction(async (tx) => {
      const [counterSnap, rateSnap] = await Promise.all([
        tx.get(counterRef),
        tx.get(rateRef),
      ]);

      const rate = rateSnap.data() ?? {};
      const lastAtMs = (rate.lastAtMs as number | undefined) ?? 0;
      const rateDayKey = (rate.dayKey as string | undefined) ?? "";
      const dayCount =
        rateDayKey === today ? ((rate.dayCount as number | undefined) ?? 0) : 0;

      if (now - lastAtMs < MIN_INTERVAL_SEC * 1000) {
        throw new HttpsError("resource-exhausted", "Çok hızlı gönderim.");
      }
      if (dayCount >= DAILY_CAP) {
        throw new HttpsError("resource-exhausted", "Günlük havuz tavanı.");
      }

      // Sayaç yoksa (CF öncesi doldurulmuş eski havuz) gerçek count ile
      // tohumla — yoksa dolu havuz 0 sanılıp tavan ikinci kez dolardı.
      let count = counterSnap.data()?.count as number | undefined;
      if (count === undefined) {
        const aggSnap = await tx.get(
          db.collection("quiz_pool").where("poolKey", "==", poolKey).count()
        );
        count = aggSnap.data().count;
      }
      if (count >= POOL_CAP) {
        return false; // havuz dolu — hata değil, "yazılmadı" bilgisi
      }

      tx.set(rateRef, {
        uid,
        lastAtMs: now,
        dayKey: today,
        dayCount: dayCount + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(counterRef, {
        poolKey,
        count: count + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(poolRef, {
        poolKey,
        country,
        level,
        grade,
        subjectKey,
        topic,
        questions,
        questionCount: questions.length,
        createdBy: uid,
        createdAt: FieldValue.serverTimestamp(),
      });
      return true;
    });

    logger.info(
      `[quizPool] uid=${uid} key=${poolKey} accepted=${accepted} n=${questions.length}`
    );
    return { ok: true, accepted };
  }
);
