/**
 * BİLGİ LİGİ — Pre-aggregated Liderlik Cloud Function (taslak)
 *
 * AMAÇ
 *   league_attempts collection büyüdüğünde her sıralama açılışında
 *   200 doküman çekip client-side dedupe yapmak yavaşlar. Bu fonksiyon
 *   her yeni attempt'ta tetiklenir; (scope × subject × topic × period)
 *   kombinasyonu için pre-aggregated `leaderboards/{key}` dokümanını
 *   günceller. Client tek doc okuyarak hazır listeyi alır.
 *
 * ÖN HAZIRLIK
 *   1. Firebase CLI: `npm install -g firebase-tools`
 *   2. Functions init: `firebase init functions` (TypeScript seçin)
 *   3. Bu dosyayı `functions/src/league_aggregate.ts` olarak kopyalayın.
 *   4. `functions/src/index.ts` içinde re-export edin:
 *        export * from "./league_aggregate";
 *   5. Bağımlılıklar (functions/package.json):
 *        firebase-admin ^12, firebase-functions ^5
 *   6. Deploy: `firebase deploy --only functions`
 *
 * SCHEMA
 *   leaderboards/{scopeKey}__{mode}__{subjectKey}__{topic}__{period}
 *     entries: [{ uid, displayName, avatar, location, score }]   // top 50
 *     updatedAt: Timestamp
 *
 *   `period` burada "allTime"; günlük/haftalık/aylık ayrı doc tutulur veya
 *   client tarafı when filtresi sürdürülür (öneri: scale gelene kadar
 *   client-side; gerekirse buraya 4 ayrı doc eklenir).
 *
 * NOT
 *   - Şu anki uygulama (200 doc çekip client-side dedupe) ~1000 attempts'a
 *     kadar gayet hızlı. Bu fonksiyonu enable etmek istersen aşağıdaki
 *     kodu deploy et + `LeagueLeaderboardService.fetch()` içine optional
 *     "pre-aggregate read" yolu ekle.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

if (getApps().length === 0) {
  initializeApp();
}
const db = getFirestore();

interface AttemptDoc {
  uid: string;
  displayName: string;
  avatar: string;
  countryCode: string;
  cityCode: string;
  level: string;
  grade: string;
  scopeWorld: string;
  scopeCountry: string;
  scopeCity: string;
  subjectKey: string;
  topic: string;
  hasTopic: boolean;
  score: number;
  when: FirebaseFirestore.Timestamp;
}

/**
 * Yeni bir attempt eklendiğinde tetiklenir.
 * Her seviyede 9 sıralama dokümanını günceller (3 scope × 3 mode).
 */
export const onLeagueAttemptCreate = onDocumentCreated(
  "league_attempts/{attemptId}",
  async (event) => {
    const data = event.data?.data() as AttemptDoc | undefined;
    if (!data) return;

    const scopes: Array<{ name: "city" | "country" | "world"; key: string }> = [
      { name: "city", key: data.scopeCity },
      { name: "country", key: data.scopeCountry },
      { name: "world", key: data.scopeWorld },
    ];

    // 3 mode varyasyonu — sadece eşleşen filtrelerin doc'u güncellenir.
    const modes: Array<{
      name: "overall" | "subject" | "topic";
      docSuffix: string;
    }> = [
      { name: "overall", docSuffix: "overall" },
      { name: "subject", docSuffix: `subject__${data.subjectKey}` },
      ...(data.hasTopic
        ? [
            {
              name: "topic" as const,
              docSuffix: `topic__${data.subjectKey}__${data.topic}`,
            },
          ]
        : []),
    ];

    const writes: Promise<unknown>[] = [];
    for (const scope of scopes) {
      for (const mode of modes) {
        const docId = `${scope.key}__${mode.docSuffix}`;
        const ref = db.collection("leaderboards").doc(docId);
        writes.push(updateLeaderboardDoc(ref, data, scope.name));
      }
    }
    await Promise.all(writes);
  }
);

async function updateLeaderboardDoc(
  ref: FirebaseFirestore.DocumentReference,
  attempt: AttemptDoc,
  scope: "city" | "country" | "world"
) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = (snap.data()?.entries as Array<any> | undefined) ?? [];

    // Aynı uid'nin önceki kaydını çıkar; daha yüksek skoru tut.
    const filtered = existing.filter((e) => e.uid !== attempt.uid);
    const myExisting = existing.find((e) => e.uid === attempt.uid);
    const myBestScore = Math.max(myExisting?.score ?? 0, attempt.score);

    const merged = [
      ...filtered,
      {
        uid: attempt.uid,
        displayName: attempt.displayName ?? "",
        avatar: attempt.avatar ?? "",
        location:
          scope === "world"
            ? attempt.countryCode
            : capitalize((attempt.cityCode ?? "").replace(/_/g, " ")),
        score: myBestScore,
      },
    ];

    merged.sort((a, b) => b.score - a.score);
    const top = merged.slice(0, 50);

    tx.set(
      ref,
      {
        entries: top,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });
}

function capitalize(s: string): string {
  if (!s) return s;
  return s.charAt(0).toUpperCase() + s.slice(1);
}
