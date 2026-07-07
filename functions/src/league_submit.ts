/**
 * BİLGİ LİGİ — Sunucu tarafı skor gönderimi (production).
 *
 * NEDEN
 *   Skorlar eskiden istemciden doğrudan Firestore'a yazılıyordu. Rules
 *   yazım başına tavanı doğruluyordu ama:
 *     • frekans sınırı yoktu (oynamadan API ile puan basılabiliyordu),
 *     • takvim kovası istemci saatinden hesaplanıyordu (saat hilesi),
 *     • attempt + totals yazımı atomik değildi (timeout → eksik toplam),
 *     • retry'da totals increment'i çift sayılabiliyordu.
 *
 *   Bu callable hepsini sunucuda çözer:
 *     1. Rate limit  — kullanıcı başına min. aralık + günlük tavan
 *        (rate_limits/league_{uid} dokümanı, transaction içinde).
 *     2. Sunucu saati — takvim kovaları (gün/hafta/ay) SUNUCU zamanından
 *        hesaplanır. İstemcinin bildirdiği `whenMs` yalnızca son 12 saat
 *        içindeyse kullanılır (offline oynayıp geç senkron olan dürüst
 *        kullanıcı doğru güne yazılır; saat hilesi işe yaramaz).
 *     3. Atomiklik  — attempt dokümanı + 12 totals increment'i TEK
 *        transaction'da. Ya hepsi yazılır ya hiçbiri.
 *     4. Idempotens — doc id = uid_clientSubmitId. Attempt zaten varsa
 *        totals'a İKİNCİ KEZ increment YAPILMAZ (retry çift saymaz).
 *
 *   Firestore rules tarafında league_attempts / league_totals istemci
 *   yazımına KAPALIDIR — tek yazım yolu bu fonksiyondur (admin SDK).
 *
 * İSTEMCİ
 *   lib/features/league/league_scores.dart → _submitToCloud()
 *   Başarısız gönderimler yerel outbox'a girer, sonraki açılışta tekrar
 *   denenir (clientSubmitId sayesinde güvenli).
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

// ── Politika sabitleri ───────────────────────────────────────────────────────
const MIN_INTERVAL_SEC = 45;    // iki gönderim arası min. süre (10 soruluk test < 45sn bitmez)
const DAILY_CAP = 300;          // kullanıcı başına günlük gönderim tavanı (bot freni)
const MAX_SCORE = 10.01;        // tek test tavanı (10 net + float payı)
const MIN_DURATION_SEC = 5;
const MAX_DURATION_SEC = 3600;
const CLIENT_WHEN_TOLERANCE_MS = 12 * 3600 * 1000; // offline senkron toleransı
const MAX_NAME_LEN = 40;

// ── Takvim kovaları — lib/features/league/league_scores.dart ile BİREBİR ────
// Dart tarafındaki dayBucket/weekBucket/monthBucket'ın TS kopyası.
// Format değişirse iki taraf birlikte güncellenmeli.
function dayBucket(ms: number): string {
  const d = new Date(ms);
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `d:${d.getUTCFullYear()}-${m}-${day}`;
}

function weekBucket(ms: number): string {
  const d = new Date(ms);
  // Dart weekday: Pzt=1..Paz=7; JS getUTCDay: Paz=0..Cmt=6.
  const isoWeekday = d.getUTCDay() === 0 ? 7 : d.getUTCDay();
  const thuMs = ms + (4 - isoWeekday) * 86400000;
  const thu = new Date(thuMs);
  const jan1 = Date.UTC(thu.getUTCFullYear(), 0, 1);
  const days = Math.floor((thuMs - jan1) / 86400000);
  const week = Math.floor(days / 7) + 1;
  return `w:${thu.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

function monthBucket(ms: number): string {
  const d = new Date(ms);
  return `m:${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

/** Doc id'de kullanılamayan '/' karakterini değiştir (Dart _san ile aynı). */
function san(s: string): string {
  return s.replace(/\//g, "⁄");
}

function asTrimmedString(v: unknown, maxLen: number): string {
  return typeof v === "string" ? v.trim().slice(0, maxLen) : "";
}

export const submitLeagueAttempt = onCall(
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
    const clientSubmitId = asTrimmedString(d.clientSubmitId, 64);
    const subjectKey = asTrimmedString(d.subjectKey, 80);
    const topic = asTrimmedString(d.topic, 160);
    const score = typeof d.score === "number" ? d.score : NaN;
    const durationSec =
      typeof d.durationSec === "number" ? Math.round(d.durationSec) : NaN;
    const whenMs = typeof d.whenMs === "number" ? d.whenMs : NaN;
    const countryCode = asTrimmedString(d.countryCode, 8).toUpperCase();
    const cityCode = asTrimmedString(d.cityCode, 64);
    const level = asTrimmedString(d.level, 40);
    const grade = asTrimmedString(d.grade, 60);
    const displayName = asTrimmedString(d.displayName, MAX_NAME_LEN);
    const avatar = asTrimmedString(d.avatar, 16);

    if (!/^[a-z0-9_\-]{6,64}$/i.test(clientSubmitId)) {
      throw new HttpsError("invalid-argument", "clientSubmitId geçersiz.");
    }
    if (subjectKey.length === 0) {
      throw new HttpsError("invalid-argument", "subjectKey zorunlu.");
    }
    if (!Number.isFinite(score) || score < 0 || score > MAX_SCORE) {
      throw new HttpsError("invalid-argument", "score aralık dışı.");
    }
    if (
      !Number.isFinite(durationSec) ||
      durationSec < MIN_DURATION_SEC ||
      durationSec > MAX_DURATION_SEC
    ) {
      throw new HttpsError("invalid-argument", "durationSec aralık dışı.");
    }
    if (level.length === 0 || grade.length === 0 || countryCode.length === 0) {
      throw new HttpsError("invalid-argument", "level/grade/countryCode zorunlu.");
    }

    // ── 2) Zaman: sunucu saati esas ─────────────────────────────────────
    const serverNowMs = Date.now();
    // İstemci zamanı yalnızca makul penceredeyse kullanılır (offline oyun
    // geç senkron olursa doğru güne yazılır); aksi halde sunucu zamanı.
    const effectiveMs =
      Number.isFinite(whenMs) &&
      whenMs <= serverNowMs + 2 * 60 * 1000 &&
      serverNowMs - whenMs <= CLIENT_WHEN_TOLERANCE_MS
        ? whenMs
        : serverNowMs;

    const scopeWorld = `${level}|${grade}`;
    const scopeCountry = `${countryCode}|${level}|${grade}`;
    const scopeCity =
      cityCode.length === 0 ? "" : `${countryCode}|${cityCode}|${level}|${grade}`;

    const buckets = [
      "all",
      dayBucket(effectiveMs),
      weekBucket(effectiveMs),
      monthBucket(effectiveMs),
    ];
    const modes = [
      "all",
      `s:${subjectKey}`,
      ...(topic.length > 0 ? [`t:${subjectKey}|${topic}`] : []),
    ];

    const db = getFirestore();
    const attemptRef = db
      .collection("league_attempts")
      .doc(`${uid}_${clientSubmitId}`);
    const rateRef = db.collection("rate_limits").doc(`league_${uid}`);
    const todayKey = dayBucket(serverNowMs);

    // ── 3) Transaction: rate limit + idempotent attempt + totals ────────
    let duplicate = false;
    await db.runTransaction(async (tx) => {
      const attemptSnap = await tx.get(attemptRef);
      if (attemptSnap.exists) {
        // Retry — daha önce işlendi; totals'a tekrar increment YAPMA.
        duplicate = true;
        return;
      }

      const rateSnap = await tx.get(rateRef);
      const rate = rateSnap.data() ?? {};
      const lastAtMs = (rate.lastAtMs as number | undefined) ?? 0;
      const rateDayKey = (rate.dayKey as string | undefined) ?? "";
      const dayCount =
        rateDayKey === todayKey ? ((rate.dayCount as number | undefined) ?? 0) : 0;

      if (serverNowMs - lastAtMs < MIN_INTERVAL_SEC * 1000) {
        throw new HttpsError(
          "resource-exhausted",
          "Çok hızlı gönderim — lütfen biraz bekle."
        );
      }
      if (dayCount >= DAILY_CAP) {
        throw new HttpsError(
          "resource-exhausted",
          "Günlük gönderim tavanına ulaşıldı."
        );
      }

      tx.set(rateRef, {
        uid,
        lastAtMs: serverNowMs,
        dayKey: todayKey,
        dayCount: dayCount + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });

      tx.set(attemptRef, {
        uid,
        clientSubmitId,
        displayName,
        avatar,
        countryCode,
        cityCode,
        level,
        grade,
        scopeWorld,
        scopeCountry,
        scopeCity,
        subjectKey,
        topic,
        hasTopic: topic.length > 0,
        score,
        durationSec,
        when: Timestamp.fromMillis(effectiveMs),
        clientWhenMs: Number.isFinite(whenMs) ? whenMs : null,
        serverWhen: FieldValue.serverTimestamp(),
      });

      for (const bucket of buckets) {
        for (const mode of modes) {
          const ref = db
            .collection("league_totals")
            .doc(san(`${uid}_${bucket}_${mode}`));
          tx.set(
            ref,
            {
              uid,
              displayName,
              avatar,
              bucket,
              modeKey: mode,
              countryCode,
              cityCode,
              level,
              grade,
              scopeWorld,
              scopeCountry,
              scopeCity,
              subjectKey,
              topic,
              score: FieldValue.increment(score),
              durationSec: FieldValue.increment(durationSec),
              attempts: FieldValue.increment(1),
              lastWhen: Timestamp.fromMillis(effectiveMs),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        }
      }
    });

    logger.info(
      `[league] submit uid=${uid} subj=${subjectKey} score=${score} dup=${duplicate}`
    );
    return {
      ok: true,
      duplicate,
      serverNowMs,
      dayBucket: dayBucket(effectiveMs),
    };
  }
);

/**
 * updateLeagueDisplayName — kullanıcının liderlik tablolarındaki görünen
 * adını (ve avatarını) geriye dönük günceller.
 *
 * Anonim mod açılıp kapandığında veya profil adı değiştiğinde çağrılır;
 * aksi halde eski dönem kovalarındaki totals dokümanlarında eski ad kalır.
 * league_totals/league_attempts istemci yazımına kapalı olduğu için bu da
 * fonksiyon üzerinden yapılır. Sadece kendi (uid eşleşen) dokümanları etkiler.
 */
export const updateLeagueDisplayName = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Oturum gerekli.");
    }
    const d = (req.data ?? {}) as Record<string, unknown>;
    const displayName = asTrimmedString(d.displayName, MAX_NAME_LEN);
    const avatar = asTrimmedString(d.avatar, 16);
    if (displayName.length === 0) {
      throw new HttpsError("invalid-argument", "displayName zorunlu.");
    }

    const db = getFirestore();
    let updated = 0;
    for (const col of ["league_totals", "league_attempts"]) {
      // Kullanıcı başına doc sayısı sınırlı (totals: kova×mod, attempts:
      // oynadığı test sayısı) — 400'lük batch'lerle tara.
      let last: FirebaseFirestore.QueryDocumentSnapshot | null = null;
      for (;;) {
        let q = db.collection(col).where("uid", "==", uid).limit(400);
        if (last) q = q.startAfter(last);
        const snap = await q.get();
        if (snap.empty) break;
        const batch = db.batch();
        for (const doc of snap.docs) {
          batch.update(doc.ref, {
            displayName,
            ...(avatar.length > 0 ? { avatar } : {}),
          });
        }
        await batch.commit();
        updated += snap.size;
        if (snap.size < 400) break;
        last = snap.docs[snap.docs.length - 1];
      }
    }
    logger.info(`[league] name sync uid=${uid} docs=${updated}`);
    return { ok: true, updated };
  }
);
