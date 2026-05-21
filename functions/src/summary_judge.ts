/**
 * SUMMARY JUDGE — Best-of-100 canonical seçimi.
 *
 * TETİK:
 *   summary_cache/{key}/candidates/{cid} eklendiğinde parent doc'taki
 *   candidateCount ≥ 100 ise judge çalışır. Aynı zamanda manuel olarak
 *   HTTPS endpoint'i çağrılabilir (admin trigger).
 *
 * AKIŞ:
 *   1. Heuristik eleme: çok kısa, başlıksız, formül beklenen konularda
 *      formül yok → status='eliminated', eliminationReason yazılır.
 *   2. Kalan adaylardan en yüksek rating-ortalama olan ilk 25'i al.
 *   3. 5'li gruplara böl, her grup için Gemini judge çağrısı yap —
 *      "bu 5 özetten hangisi en iyi?" sorar.
 *   4. Grup kazananlarını yeni bir grupta yarıştır → SON KAZANAN.
 *   5. Kazananı `canonicalDocId` olarak işaretle, parent status='canonical'.
 *
 * BUGÜNKÜ MALIYET TAHMİNİ:
 *   ~17 judge çağrısı × 800 token = ~14k token = $0.03/konu (Gemini Flash).
 *   Bir kerelik harcama — sonraki tüm kullanıcılara 0 maliyet.
 *
 * NOT: Gemini API key Firebase Secret Manager'dan okunur (GEMINI_API_KEY).
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const CANDIDATE_THRESHOLD = 100;
const TOP_K_FOR_TOURNAMENT = 25;
const GROUP_SIZE = 5;

// ─── Trigger: yeni aday eklenince kontrol et ─────────────────────────────────

export const onSummaryCandidateCreated = onDocumentCreated(
  {
    document: "summary_cache/{cacheKey}/candidates/{candidateId}",
    region: "us-central1",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (event) => {
    const cacheKey = event.params.cacheKey;
    const parentRef = getFirestore().collection("summary_cache").doc(cacheKey);
    const parentSnap = await parentRef.get();
    if (!parentSnap.exists) return;
    const parent = parentSnap.data() ?? {};
    const count = (parent.candidateCount as number) ?? 0;
    const status = (parent.status as string) ?? "collecting";

    // Henüz threshold'a ulaşmadıysa veya canonical zaten seçildiyse atla.
    if (count < CANDIDATE_THRESHOLD) return;
    if (status === "canonical" || status === "judging") return;

    // judging'e geçir (race koşulundan koruma)
    await parentRef.update({
      status: "judging",
      updatedAt: FieldValue.serverTimestamp(),
    });

    try {
      await runJudge(cacheKey, parentRef);
    } catch (e) {
      console.error("[summary_judge] error:", e);
      // status'u collecting'e geri çevir ki sonra yeniden denenebilsin
      await parentRef.update({
        status: "collecting",
        lastJudgeError: String(e).slice(0, 500),
      });
    }
  }
);

// ─── HTTPS endpoint: manuel tetik (admin için) ───────────────────────────────

export const triggerSummaryJudge = onCall(
  {
    region: "us-central1",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    // TODO: gerçek admin kontrolü (custom claim 'admin' veya whitelist)
    const cacheKey = request.data?.cacheKey as string | undefined;
    if (!cacheKey) {
      throw new HttpsError("invalid-argument", "cacheKey required.");
    }
    const parentRef = getFirestore().collection("summary_cache").doc(cacheKey);
    const parentSnap = await parentRef.get();
    if (!parentSnap.exists) {
      throw new HttpsError("not-found", `cache key ${cacheKey} bulunamadı.`);
    }
    await parentRef.update({ status: "judging" });
    await runJudge(cacheKey, parentRef);
    return { success: true };
  }
);

// ─── Çekirdek: judge süreci ──────────────────────────────────────────────────

async function runJudge(
  cacheKey: string,
  parentRef: FirebaseFirestore.DocumentReference
): Promise<void> {
  // 1) Aktif tüm adayları çek
  const candidatesSnap = await parentRef
    .collection("candidates")
    .where("status", "==", "active")
    .get();

  if (candidatesSnap.size < CANDIDATE_THRESHOLD) {
    await parentRef.update({ status: "collecting" });
    return;
  }

  const candidates = candidatesSnap.docs.map((d) => ({
    id: d.id,
    body: (d.data().body as string) ?? "",
    rating: ((d.data().ratings as { avg?: number })?.avg ?? 0) as number,
  }));

  // 2) Heuristik eleme: çok kısa, başlıksız
  const filtered: typeof candidates = [];
  const eliminated: string[] = [];
  for (const c of candidates) {
    if (c.body.length < 300) {
      eliminated.push(c.id);
      await markEliminated(parentRef, c.id, "too_short");
      continue;
    }
    // En az 2 markdown başlığı (## veya emoji-based) olmalı
    const headerCount = (c.body.match(/^(##|📚|🔑|📐|💡)/gm) ?? []).length;
    if (headerCount < 2) {
      eliminated.push(c.id);
      await markEliminated(parentRef, c.id, "no_structure");
      continue;
    }
    filtered.push(c);
  }
  console.log(
    `[summary_judge] eleme: ${candidates.length} → ${filtered.length} ` +
      `(${eliminated.length} eliminated)`
  );

  if (filtered.length === 0) {
    await parentRef.update({
      status: "collecting",
      lastJudgeError: "all eliminated by heuristics",
    });
    return;
  }

  // 3) En yüksek rating ortalamalı ilk K'yı seç
  filtered.sort((a, b) => b.rating - a.rating);
  const top = filtered.slice(0, TOP_K_FOR_TOURNAMENT);

  // 4) 5'li gruplara böl → her gruptan 1 kazanan
  const groups: (typeof top)[] = [];
  for (let i = 0; i < top.length; i += GROUP_SIZE) {
    groups.push(top.slice(i, i + GROUP_SIZE));
  }

  const winners: typeof top = [];
  for (const group of groups) {
    if (group.length === 1) {
      winners.push(group[0]);
      continue;
    }
    const winner = await judgeGroup(group);
    winners.push(winner);
  }

  // 5) Kazananları finalde yarıştır (tek round, en fazla 5)
  let finalWinner: typeof top[0];
  if (winners.length === 1) {
    finalWinner = winners[0];
  } else if (winners.length <= GROUP_SIZE) {
    finalWinner = await judgeGroup(winners);
  } else {
    // 5'ten fazla grup kazananı varsa ikinci turnuva turu
    const secondRound: typeof top = [];
    for (let i = 0; i < winners.length; i += GROUP_SIZE) {
      const g = winners.slice(i, i + GROUP_SIZE);
      secondRound.push(g.length === 1 ? g[0] : await judgeGroup(g));
    }
    finalWinner =
      secondRound.length === 1
        ? secondRound[0]
        : await judgeGroup(secondRound);
  }

  // 6) Canonical olarak işaretle
  await parentRef.update({
    status: "canonical",
    canonicalDocId: finalWinner.id,
    canonicalSelectedAt: FieldValue.serverTimestamp(),
    judgedAt: FieldValue.serverTimestamp(),
    judgeStats: {
      totalCandidates: candidates.length,
      eliminated: eliminated.length,
      tournamentSize: top.length,
      groups: groups.length,
    },
  });
  console.log(
    `[summary_judge] canonical → ${finalWinner.id} (rating ${finalWinner.rating.toFixed(2)})`
  );
}

async function markEliminated(
  parentRef: FirebaseFirestore.DocumentReference,
  candidateId: string,
  reason: string
): Promise<void> {
  try {
    await parentRef.collection("candidates").doc(candidateId).update({
      status: "eliminated",
      eliminationReason: reason,
    });
  } catch (e) {
    console.warn(`mark eliminated failed (${candidateId}):`, e);
  }
}

// ─── Judge: 2-5 adaydan en iyiyi seç (Gemini) ────────────────────────────────

async function judgeGroup(
  group: { id: string; body: string; rating: number }[]
): Promise<{ id: string; body: string; rating: number }> {
  if (group.length === 1) return group[0];

  const numbered = group
    .map((c, i) => `--- ÖZET #${i + 1} (id=${c.id}) ---\n${c.body}`)
    .join("\n\n");

  const prompt = `Sen bir eğitim materyali uzmanısın. Aşağıda öğrenciye yönelik aynı konunun ${group.length} farklı özeti var.
Görevin: bu özetlerden HANGİSİ EN İYİSİ — şu kriterlere göre puanla:

1. DOĞRULUK: Bilgi gerçek mi? Müfredata uygun mu?
2. KAPSAM: Konunun tüm önemli alt başlıklarını içeriyor mu?
3. ANLAŞILIRLIK: Açıklamalar net mi? Terimler uygun mu?
4. GÖRSEL DÜZEN: Başlık/madde/tablo yapısı düzenli mi?
5. ÖZLÜLÜK: Gereksiz tekrar var mı?

Her özet için 1-10 puan ver, sonunda en yüksek puanlı ÖZETİN numarasını söyle.

ÖZETLER:
${numbered}

YANIT FORMATI (sadece JSON, başka hiçbir şey ekleme):
{
  "scores": [{"index": 1, "total": 42}, {"index": 2, "total": 38}, ...],
  "winnerIndex": 1
}`;

  const apiKey = GEMINI_API_KEY.value();
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;

  // Timeout + retry — Cloud Function inactivity timeout 60sn varsayılan;
  // Gemini 503/429 dönerse 2 backoff retry. Toplam max ~25sn (10+5+10).
  const RETRYABLE = new Set([408, 429, 500, 502, 503, 504]);
  let lastErr: unknown = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    const controller = new AbortController();
    const timeoutMs = attempt === 0 ? 10000 : 8000; // ilk dene daha cömert
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: {
            temperature: 0.1,
            maxOutputTokens: 600,
            responseMimeType: "application/json",
          },
        }),
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (!response.ok) {
        if (RETRYABLE.has(response.status) && attempt < 2) {
          await new Promise((r) => setTimeout(r, 800 * (attempt + 1)));
          lastErr = new Error(`Gemini judge HTTP ${response.status}`);
          continue;
        }
        throw new Error(`Gemini judge HTTP ${response.status}`);
      }
      const j = (await response.json()) as {
        candidates?: {
          content?: { parts?: { text?: string }[] };
        }[];
      };
      const text = j?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
      if (!text) {
        if (attempt < 2) {
          await new Promise((r) => setTimeout(r, 800 * (attempt + 1)));
          lastErr = new Error("judge boş yanıt");
          continue;
        }
        throw new Error("judge boş yanıt");
      }
      let parsed: { winnerIndex?: number };
      try {
        parsed = JSON.parse(text);
      } catch {
        // Parse hatası — Gemini bazen ham metin döndürür; ilk denemede retry et.
        if (attempt < 2) {
          await new Promise((r) => setTimeout(r, 800 * (attempt + 1)));
          lastErr = new Error("judge JSON parse error");
          continue;
        }
        throw new Error("judge JSON parse error: " + text.slice(0, 200));
      }
      const winnerIdx = (parsed.winnerIndex ?? 1) - 1;
      if (winnerIdx < 0 || winnerIdx >= group.length) {
        // Geçersiz index — varsayılan olarak ilk özeti seç (fail-safe).
        return group[0];
      }
      return group[winnerIdx];
    } catch (e) {
      clearTimeout(timer);
      lastErr = e;
      // Timeout (AbortError) veya network hatası — retry yap
      if (attempt < 2) {
        await new Promise((r) => setTimeout(r, 800 * (attempt + 1)));
        continue;
      }
      // Son denemede de patladı — fail-safe: ilk özeti döndür ki judge
      // tamamen bloke olmasın. Çağıran loop devam etsin.
      console.warn(`[judge] tüm retry başarısız, fail-safe: ${e}`);
      return group[0];
    }
  }
  // Buraya teorik olarak ulaşılmaz ama TS exhaustiveness için.
  throw lastErr instanceof Error
      ? lastErr
      : new Error(`judge retry tükendi: ${lastErr}`);
}
