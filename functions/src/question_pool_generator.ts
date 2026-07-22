/**
 * QUESTION POOL GENERATOR — 5000 soruluk havuz oluşturucu.
 *
 * AKIŞ:
 *   1. question_pool/{key} ilk kez oluşturulduğunda → onPoolCreated trigger
 *      ile generator başlar.
 *   2. Generator her çağırıldığında 50 soru üretir (Gemini Flash batch).
 *   3. Embedding dedup ile %95+ benzeyenler elenir.
 *   4. acceptedCount 5000'e ulaşana kadar Cloud Scheduler her saat 1 batch
 *      üretir. 5000'de status='frozen', generation durur.
 *   5. 1 yıl sonra veya curriculumVersion bumplandığında havuz invalidate
 *      olur (manuel admin tetik).
 *
 * MALİYET:
 *   100 batch × 50 soru × ~$0.0002/batch (Gemini Flash) = ~$0.02/konu.
 *   Bir kerelik — sonsuza kadar kullanıcılara 0 maliyet.
 *
 * NOT: Cloud Scheduler kurulumu için Firebase Console'dan "Cloud Scheduler"
 * etkinleştirilmeli. Crontab: her saat 1 batch işle.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { generateTextFailover } from "./gemini_util";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
// Failover (kullanıcı isteği): Gemini cevap vermezse ChatGPT, o da vermezse
// Grok. Anahtarlar aiProxy ile aynı Secret Manager kayıtları.
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const XAI_API_KEY = defineSecret("XAI_API_KEY");

// Hedef pool boyutu — konu başına 450 soru. Kullanıcı tarafı eşiği 400 (en az
// 400 soru birikmeden havuz devreye girmez), 450 tavanı küçük bir tampon
// bırakır. Maliyet çok düşük (konu başına ~$0,002), bu yüzden kapsama için
// yüksek tutuldu. Önceki 1000/5000 değerleri ülke×sınıf×konu çarpanında
// gereksiz devasa toplam üretiyordu — 450 hem geniş kapsama hem ekonomik.
const TARGET_POOL_SIZE = 450;
const BATCH_SIZE = 100; // her batch 100 soru (Gemini Flash)
const MAX_BATCHES_PER_RUN = 2; // her çalışmada 2 batch = 200 soru → ~3 turda dolar
const DEDUP_SIM_THRESHOLD = 0.92; // basit Jaccard similarity üzerinde
const POOL_REGENERATE_AFTER_DAYS = 365;

// ─── Trigger: pool doc'u yaratılırsa ilk batch'i hemen üret ──────────────────

export const onQuestionPoolCreated = onDocumentCreated(
  {
    document: "question_pool/{poolKey}",
    region: "us-central1",
    secrets: [GEMINI_API_KEY, OPENAI_API_KEY, XAI_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const poolKey = event.params.poolKey;
    const data = event.data?.data();
    if (!data) return;

    console.log(`[pool_gen] yeni pool: ${poolKey}`);
    await runBatchForPool(poolKey, data);
  }
);

// ─── Scheduled: her saat eksik pool'lar için 1 batch üret ────────────────────

export const scheduledPoolFill = onSchedule(
  {
    schedule: "every 1 hours",
    region: "us-central1",
    secrets: [GEMINI_API_KEY, OPENAI_API_KEY, XAI_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async () => {
    const db = getFirestore();
    // Tavana ulaşmamış pool'ları çek (her seferinde max 30 pool)
    const snap = await db
      .collection("question_pool")
      .where("status", "==", "generating")
      .where("acceptedCount", "<", TARGET_POOL_SIZE)
      .limit(30)
      .get();

    if (snap.empty) {
      console.log("[pool_gen] generating pool yok, sleep");
      return;
    }

    console.log(`[pool_gen] ${snap.size} pool için batch üretilecek`);
    for (const doc of snap.docs) {
      try {
        await runBatchForPool(doc.id, doc.data());
      } catch (e) {
        console.error(`[pool_gen] pool ${doc.id} batch error:`, e);
      }
    }
  }
);

// ─── HTTPS: manuel batch tetikleme (admin için) ──────────────────────────────

export const triggerPoolBatch = onCall(
  {
    region: "us-central1",
    secrets: [GEMINI_API_KEY, OPENAI_API_KEY, XAI_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const poolKey = request.data?.poolKey as string | undefined;
    if (!poolKey) {
      throw new HttpsError("invalid-argument", "poolKey required.");
    }
    const snap = await getFirestore()
      .collection("question_pool")
      .doc(poolKey)
      .get();
    if (!snap.exists) {
      throw new HttpsError("not-found", `pool ${poolKey} bulunamadı.`);
    }
    await runBatchForPool(poolKey, snap.data()!);
    return { success: true };
  }
);

// ─── Çekirdek: tek bir pool için 1 batch (50 soru) üret ──────────────────────

async function runBatchForPool(
  poolKey: string,
  poolData: FirebaseFirestore.DocumentData
): Promise<void> {
  const db = getFirestore();
  const poolRef = db.collection("question_pool").doc(poolKey);

  const accepted = (poolData.acceptedCount as number) ?? 0;
  if (accepted >= TARGET_POOL_SIZE) {
    await poolRef.update({ status: "frozen" });
    return;
  }

  const subjectName =
    (poolData.subjectName as string) || (poolData.subjectKey as string);
  const topicName = (poolData.topicName as string) || "Konu";
  const level = (poolData.level as string) || "high";
  const country = (poolData.country as string) || "tr";
  const grade = (poolData.grade as string) || "10";
  // Havuzun içerik dili — istemci _initPool'da yazar (poolKey'de de
  // Türkçe dışı dillerde `|lang` suffix'i vardır). Eski doc'larda alan
  // yok → 'tr' (o havuzlar zaten Türkçe içerikli).
  const lang = (poolData.lang as string) || "tr";

  // Çeşitlilik: batch içinde dağılımı garanti et
  const difficulties = ["easy", "medium", "hard", "exam"];
  const bloomLevels = [
    "remember",
    "understand",
    "apply",
    "analyze",
    "evaluate",
  ];
  const types = ["mcq", "tf", "short", "problem"];

  for (let batchIdx = 0; batchIdx < MAX_BATCHES_PER_RUN; batchIdx++) {
    const remaining = TARGET_POOL_SIZE - accepted;
    if (remaining <= 0) break;
    const batchSize = Math.min(BATCH_SIZE, remaining);

    // Var olan soruları çek (dedup için son 200 soru)
    const existingSnap = await poolRef
      .collection("questions")
      .orderBy(FieldValue.serverTimestamp() as never, "desc") // placeholder
      .limit(200)
      .get()
      .catch(() => null);
    const existingStems = existingSnap
      ? existingSnap.docs.map((d) => (d.data().stem as string) ?? "")
      : [];

    // Çeşitlilik dağılımı için rastgele kombinasyon iste
    const difficulty =
      difficulties[Math.floor(Math.random() * difficulties.length)];
    const bloom =
      bloomLevels[Math.floor(Math.random() * bloomLevels.length)];
    const qType = types[Math.floor(Math.random() * types.length)];

    const prompt = buildBatchPrompt({
      country,
      level,
      grade,
      subjectName,
      topicName,
      lang,
      batchSize,
      difficulty,
      bloomLevel: bloom,
      questionType: qType,
    });

    const generated = await callGeminiBatch(prompt);
    if (!generated || generated.length === 0) {
      console.warn(`[pool_gen] ${poolKey} batch boş döndü`);
      continue;
    }

    // Dedup + kaydet
    let added = 0;
    const batch = db.batch();
    for (const q of generated) {
      const stem = q.stem ?? "";
      if (stem.length < 20) continue;
      if (isDuplicate(stem, existingStems)) continue;

      const qRef = poolRef.collection("questions").doc();
      batch.set(qRef, {
        stem,
        options: q.options ?? [],
        correctIndex: q.correctIndex ?? 0,
        explanation: q.explanation ?? "",
        difficulty: q.difficulty ?? difficulty,
        bloomLevel: q.bloomLevel ?? bloom,
        subtopic: q.subtopic ?? "",
        questionType: q.questionType ?? qType,
        timesServed: 0,
        errorReports: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
      existingStems.push(stem);
      added += 1;
    }
    if (added > 0) {
      await batch.commit();
      await poolRef.update({
        acceptedCount: FieldValue.increment(added),
        generatedCount: FieldValue.increment(generated.length),
        lastBatchAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log(`[pool_gen] ${poolKey} batch +${added}`);
    }
  }

  // Hedefe ulaştıysa freeze
  const fresh = await poolRef.get();
  const curAccepted = (fresh.data()?.acceptedCount as number) ?? 0;
  if (curAccepted >= TARGET_POOL_SIZE) {
    await poolRef.update({ status: "frozen", frozenAt: FieldValue.serverTimestamp() });
    console.log(`[pool_gen] ${poolKey} FROZEN at ${curAccepted}`);
  }
}

// ─── Prompt builder ──────────────────────────────────────────────────────────

function buildBatchPrompt(p: {
  country: string;
  level: string;
  grade: string;
  subjectName: string;
  topicName: string;
  lang: string;
  batchSize: number;
  difficulty: string;
  bloomLevel: string;
  questionType: string;
}): string {
  // Çıktı dili — belirsiz bırakılırsa model Türkçe'ye kayıyor (prompt
  // iskeleti Türkçe olduğu için). Kod bazlı KESİN talimat verilir.
  const langLine =
    p.lang === "tr"
      ? "Türkçe — soru kökü, şıklar ve açıklamalar Türkçe yazılacak."
      : `ISO dil kodu "${p.lang}" olan dil — soru kökü, şıklar ve ` +
        `açıklamalar dahil HER ŞEY SADECE bu dilde yazılacak. ` +
        `Türkçe KULLANMA${p.lang === "en" ? "" : ", İngilizce KULLANMA"}.`;
  return `Sen bir sınav sorusu üreten eğitim materyali uzmanısın.
Aşağıdaki müfredata göre ${p.batchSize} adet ÇEŞİTLİ test sorusu üret.

PROFİL:
- Ülke: ${p.country}
- Seviye: ${p.level}
- Sınıf: ${p.grade}
- Ders: ${p.subjectName}
- Konu: ${p.topicName}
- ÇIKTI DİLİ: ${langLine}

PARAMETRELER:
- Zorluk: ${p.difficulty}
- Bloom seviyesi: ${p.bloomLevel}
- Soru tipi: ${p.questionType}

SORU KALİTESİ (EN ÖNEMLİ BÖLÜM — her maddeye uy; uygulamadaki düello
prompt'u ile aynı sözleşme, bkz. lib/screens/qualsar_arena_screen.dart):
- Her soru GERÇEK bir kazanımı ölçsün (kavrama, uygulama veya analiz).
  Dolgu / ezber / "soru sormuş olmak için" yazılmış soru YASAK.
- Soru kökü TEK OKUYUŞTA anlaşılsın: cevap için gereken TÜM bilgi ve
  bağlam kökte verilsin. Belirsiz ifade, çift olumsuz, kapalı gönderme yok.
- "Aşağıdakilerden hangisi doğrudur?" gibi KÖKSÜZ genel kalıplar YASAK —
  kök her zaman belirli bir kavramı, durumu veya işlemi sorsun.
- TEK ve TARTIŞMASIZ doğru cevap olsun; şıklar birbirini dışlasın.
- Çeldiriciler öğrencinin TİPİK HATALARINDAN türesin: makul, doğru cevapla
  aynı kategoride ve benzer uzunlukta. Bariz saçma şık ve "Hepsi"/"Hiçbiri"
  şıkkı YASAK.
- Sayısal soruda veriler tutarlı olsun, işlem TEK sonuç versin; yanlış
  şıklar yaygın hata sonuçları olsun (işaret hatası, ters oran vb.).
- Soru tiplerini çeşitlendir: hesaplama, günlük hayat bağlamı, neden-sonuç,
  karşılaştırma, örnek→kavram eşleştirme. Aynı kalıbı arka arkaya kullanma.
- Doğru cevap index'i sorular arasında dengeli/rastgele dağılsın.
- Dil sade ve sınıf seviyesine uygun; soru kökü ideal 10-35 kelime.

KURALLAR:
- Her soru özgün olsun (önceki sorulara benzemesin)
- Konu sınırları içinde kal (genişleme yok)
- Her soruda 4 şık (A, B, C, D)
- Doğru cevap index'i 0-3 arası
- Açıklama 2-4 cümle: doğrunun kısa gerekçesi + kullanılan kural/adım
- LaTeX KULLANMA — Unicode kullan (x², √, π, →, H₂O vb.)

YANIT FORMATI (sadece JSON array, başka hiçbir şey):
[
  {
    "stem": "soru metni",
    "options": ["A şıkkı", "B şıkkı", "C şıkkı", "D şıkkı"],
    "correctIndex": 0,
    "explanation": "neden doğru",
    "difficulty": "${p.difficulty}",
    "bloomLevel": "${p.bloomLevel}",
    "questionType": "${p.questionType}",
    "subtopic": "alt konu"
  },
  ...
]`;
}

// ─── Gemini batch call ───────────────────────────────────────────────────────

interface RawQuestion {
  stem?: string;
  options?: string[];
  correctIndex?: number;
  explanation?: string;
  difficulty?: string;
  bloomLevel?: string;
  subtopic?: string;
  questionType?: string;
}

async function callGeminiBatch(prompt: string): Promise<RawQuestion[]> {
  // flash-lite → (503/hata) → flash fallback (gemini_util). Eskiden tek
  // flash-lite + retry'sızdı; ~%60 503'te boş batch dönüyordu.
  let text: string;
  try {
    text = await generateTextFailover(
      {
        gemini: GEMINI_API_KEY.value(),
        openai: OPENAI_API_KEY.value() || undefined,
        xai: XAI_API_KEY.value() || undefined,
      },
      {
        temperature: 0.85, // çeşitlilik için yüksek
        maxOutputTokens: 6000,
        responseMimeType: "application/json",
      },
      prompt
    );
  } catch (e) {
    console.error("AI batch başarısız (Gemini→ChatGPT→Grok):", e);
    return [];
  }

  try {
    const parsed = JSON.parse(text) as RawQuestion[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    console.warn("batch JSON parse error:", e);
    return [];
  }
}

// ─── Basit dedup (Jaccard similarity) ────────────────────────────────────────

function isDuplicate(stem: string, existing: string[]): boolean {
  const normNew = normalize(stem);
  for (const old of existing) {
    const sim = jaccard(normNew, normalize(old));
    if (sim >= DEDUP_SIM_THRESHOLD) return true;
  }
  return false;
}

function normalize(s: string): Set<string> {
  return new Set(
    s
      .toLowerCase()
      .replace(/[^a-z0-9ıöçşğüâîû ]+/gi, " ")
      .split(/\s+/)
      .filter((w) => w.length > 2)
  );
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let intersection = 0;
  for (const x of a) {
    if (b.has(x)) intersection += 1;
  }
  const union = a.size + b.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

// ─── Manuel: pool'u resetle (1 yıl geçti veya curriculum değişti) ────────────

export const refreshOldPools = onSchedule(
  {
    schedule: "0 3 * * 1", // her Pazartesi 03:00 (TR saati ≠ UTC ama yaklaşık)
    region: "us-central1",
    timeoutSeconds: 120,
  },
  async () => {
    const db = getFirestore();
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - POOL_REGENERATE_AFTER_DAYS);

    const snap = await db
      .collection("question_pool")
      .where("status", "==", "frozen")
      .where("frozenAt", "<", cutoff)
      .limit(10)
      .get();

    console.log(`[pool_gen] eskimiş ${snap.size} pool resetlenecek`);
    for (const doc of snap.docs) {
      await doc.ref.update({
        status: "generating",
        acceptedCount: 0,
        generatedCount: 0,
        refreshedAt: FieldValue.serverTimestamp(),
      });
      // Eski soruları sub-collection'dan silme YAPILMAZ — eski sorular
      // archive olarak tutulur (analitik için). Yeni sorular da eklenir.
    }
  }
);
