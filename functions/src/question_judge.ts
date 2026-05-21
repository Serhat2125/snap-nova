/**
 * QUESTION JUDGE — Havuza yazılan her soruyu otomatik kalite puanı verir.
 *
 * TETİK:
 *   Firestore: question_pool/{poolKey}/questions/{questionId} → onCreate
 *
 * AKIŞ:
 *   1. Yeni soru havuza eklendi (organic AI üretim veya pool generator)
 *   2. Bu trigger anında çalışır, Gemini Flash'a soruyu puanlatır
 *   3. Sonuç:
 *        score >= 3 → qualityChecked=true, qualityScore=N (normal serve)
 *        score <  3 → quarantined=true (drawQuestions filtreler, serve etmez)
 *
 * NEDEN BU YAKLAŞIM:
 *   - Kullanıcı akışını yavaşlatmaz (async, arka planda)
 *   - Yargılama sadece BİR yapay zekâ ile (Gemini Flash) → ucuz, hızlı
 *   - Düşük puanlı sorular silinmez, sadece servis dışında bırakılır →
 *     ileride farklı judge ile yeniden değerlendirilebilir
 *   - Kullanıcı errorReports'u tamamlayıcı sinyal — judge teknik kaliteyi,
 *     öğrenci pedagojik doğruluğu değerlendirir
 *
 * MALİYET:
 *   1 soru ≈ 200 token in + 50 token out = ~$0.0001 (Gemini Flash)
 *   1000 soru/konu × 100 konu × 30 sınıf = 3M judge call = $300 toplam
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

// 1-5 arası score eşiği. 3 ve üstü "yeterli" sayılır.
const MIN_PASS_SCORE = 3;

// Concurrency limiti — Gemini rate limit'e takılmayalım.
const MAX_CONCURRENT = 50;

interface JudgeResult {
  score: number; // 1-5
  reason: string;
}

export const onQuestionInserted = onDocumentCreated(
  {
    document: "question_pool/{poolKey}/questions/{questionId}",
    region: "us-central1",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 60,
    memory: "256MiB",
    concurrency: MAX_CONCURRENT,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();

    // Zaten puanlanmışsa atla (idempotent — geri-tetikleme koruması).
    if (data.qualityChecked === true) return;

    const stem = (data.stem as string | undefined) ?? "";
    const options = (data.options as string[] | undefined) ?? [];
    const correctIndex = (data.correctIndex as number | undefined) ?? 0;
    const explanation = (data.explanation as string | undefined) ?? "";

    // Heuristik mini ön-kontrol — gerçekten bozuk sorularda AI'a hiç gitme.
    if (stem.length < 20 || options.length < 2) {
      await snap.ref.update({
        qualityChecked: true,
        qualityScore: 1,
        quarantined: true,
        judgeReason: "Heuristik fail: stem veya options yetersiz",
      });
      return;
    }
    if (correctIndex < 0 || correctIndex >= options.length) {
      await snap.ref.update({
        qualityChecked: true,
        qualityScore: 1,
        quarantined: true,
        judgeReason: "correctIndex aralık dışında",
      });
      return;
    }

    try {
      const result = await judgeWithGemini({
        stem,
        options,
        correctIndex,
        explanation,
      });

      const passed = result.score >= MIN_PASS_SCORE;
      await snap.ref.update({
        qualityChecked: true,
        qualityScore: result.score,
        judgeReason: result.reason,
        quarantined: !passed,
        judgedAt: new Date(),
      });
    } catch (err) {
      console.warn(`[question_judge] başarısız ${event.params.questionId}:`, err);
      // Hata durumunda quarantine ETME — sorunun nasıl bir hata olduğu belli
      // değil. qualityChecked=false kalır, ileride yeniden judge edilebilir.
    }
  }
);

// ─── Gemini judge çağrısı ─────────────────────────────────────────────────────

async function judgeWithGemini(q: {
  stem: string;
  options: string[];
  correctIndex: number;
  explanation: string;
}): Promise<JudgeResult> {
  const apiKey = GEMINI_API_KEY.value();
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;

  const prompt = buildJudgePrompt(q);

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.1, // Deterministik puanlama
        maxOutputTokens: 200,
        responseMimeType: "application/json",
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`Gemini HTTP ${response.status}`);
  }

  const j = (await response.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const text = j?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  if (!text) throw new Error("Empty response");

  // Yanıt: {"score": 4, "reason": "..."}
  const parsed = JSON.parse(text) as JudgeResult;
  const score = Math.max(1, Math.min(5, Math.round(parsed.score || 0)));
  return {
    score,
    reason: (parsed.reason || "").slice(0, 200),
  };
}

function buildJudgePrompt(q: {
  stem: string;
  options: string[];
  correctIndex: number;
  explanation: string;
}): string {
  const optsBlock = q.options
    .map((o, i) => `${String.fromCharCode(65 + i)}) ${o}`)
    .join("\n");
  const correctLetter = String.fromCharCode(65 + q.correctIndex);

  return `Sen bir eğitim materyali değerlendirme uzmanısın. Aşağıdaki çoktan seçmeli soruyu 1-5 arası puanla.

SORU:
${q.stem}

ŞIKLAR:
${optsBlock}

DOĞRU CEVAP: ${correctLetter}

AÇIKLAMA: ${q.explanation || "(yok)"}

DEĞERLENDİRME KRİTERLERİ:
- Soru metni anlaşılır mı? (dilbilgisi, anlam karışıklığı)
- Şıklar makul mü? (çeldiriciler mantıklı, doğru cevap gerçekten doğru)
- Konu/zorluk seviyesine uygun mu?
- Birden fazla doğru cevap içermiyor mu?
- Açıklama tutarlı mı?

PUANLAMA:
5 = mükemmel, sınava hazır
4 = iyi, küçük iyileştirme olabilir
3 = kabul edilebilir, kusurlu ama servis edilebilir
2 = sorunlu (yanıltıcı çeldirici, belirsiz dil, vb.)
1 = hatalı (yanlış cevap, birden fazla doğru, anlamsız)

YANIT FORMATI (sadece JSON, başka hiçbir şey):
{"score": 4, "reason": "kısa gerekçe — 1 cümle"}`;
}

// ─── Manuel toplu yeniden değerlendirme (henüz puanlanmamış sorular için) ─
//
// Eğer judge sonradan eklenirse ve havuzda zaten qualityChecked=false sorular
// varsa, bu function manuel olarak çağrılarak hepsini puanlatır.
//
// Çağırma: gcloud functions call rejudgeUnchecked --region us-central1
// Daha güvenli: bunu admin SDK ile küçük komut script'i çalıştır.
// (Bu function şu an stub — gerek olunca implement edilebilir.)

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";

export const rejudgeUnchecked = onCall(
  {
    region: "us-central1",
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (request) => {
    // Sadece admin (custom claim ile) çağırabilsin.
    if (!request.auth || request.auth.token.admin !== true) {
      throw new HttpsError("permission-denied", "Sadece admin");
    }

    const db = getFirestore();
    const snap = await db
      .collectionGroup("questions")
      .where("qualityChecked", "==", false)
      .limit(100)
      .get();

    let judged = 0;
    for (const doc of snap.docs) {
      const data = doc.data();
      try {
        const result = await judgeWithGemini({
          stem: (data.stem as string) ?? "",
          options: (data.options as string[]) ?? [],
          correctIndex: (data.correctIndex as number) ?? 0,
          explanation: (data.explanation as string) ?? "",
        });
        await doc.ref.update({
          qualityChecked: true,
          qualityScore: result.score,
          judgeReason: result.reason,
          quarantined: result.score < MIN_PASS_SCORE,
          judgedAt: new Date(),
        });
        judged++;
      } catch (err) {
        console.warn(`rejudge fail ${doc.id}:`, err);
      }
    }
    return { judged };
  }
);
