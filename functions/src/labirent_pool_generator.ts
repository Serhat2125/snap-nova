/**
 * LABİRENT POOL GENERATOR — Bilgi Labirenti topluluk içerik havuzu doldurucu.
 *
 * Havuz: labirent_pool/{country|level|grade|track|lang}
 *   /q/{hash} → {q, opts[], a, sol}   (hedef ≥300, tavan 360)
 *   /f/{hash} → {t}                    (hedef ≥500, tavan 600)
 *
 * AKIŞ:
 *   1. İstemci havuz doc'unu init eder → onLabirentPoolCreated ilk batch'i üretir.
 *   2. scheduledLabirentPoolFill her saat 'generating' havuzları hedefe tamamlar.
 *   3. Hedefe ulaşınca status='ready' → istemciler yalnız havuzdan çeker, AI biter.
 *
 * ÜLKELER ARASI PAYLAŞIM (curriculumSig):
 *   Aynı level+grade+curriculumSig'e sahip DOLU bir donör havuz varsa:
 *     • donör aynı dilde  → içerik DOĞRUDAN kopyalanır (AI maliyeti 0).
 *     • donör farklı dilde → içerik AI ile HEDEF DİLE ÇEVRİLİR (üretimden ucuz
 *       ve içerik tutarlı). Donör yoksa sıfırdan üretilir.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { generateTextFailover } from "./gemini_util";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
// Failover (kullanıcı isteği): Gemini cevap vermezse ChatGPT, o da vermezse
// Grok. Anahtarlar aiProxy ile aynı Secret Manager kayıtları.
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const XAI_API_KEY = defineSecret("XAI_API_KEY");

function aiKeys() {
  return {
    gemini: GEMINI_API_KEY.value(),
    openai: OPENAI_API_KEY.value() || undefined,
    xai: XAI_API_KEY.value() || undefined,
  };
}

const Q_TARGET = 300;
const F_TARGET = 500;
const Q_CAP = 360;
const F_CAP = 600;
const Q_BATCH = 40; // her AI çağrısında istenen soru
const F_BATCH = 60; // her AI çağrısında istenen bilgi
const MAX_AI_CALLS_PER_RUN = 4; // koşu başına sıkı tavan (kontrolsüz şişme yok)

// ─── Trigger: havuz doc'u yaratılınca ilk doldurma ───────────────────────────

export const onLabirentPoolCreated = onDocumentCreated(
  {
    document: "labirent_pool/{poolKey}",
    region: "us-central1",
    secrets: [GEMINI_API_KEY, OPENAI_API_KEY, XAI_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    console.log(`[labirent_pool] yeni havuz: ${event.params.poolKey}`);
    await fillPool(event.params.poolKey, data);
  }
);

// ─── Scheduled: her saat eksik havuzları tamamla ─────────────────────────────

export const scheduledLabirentPoolFill = onSchedule(
  {
    schedule: "every 1 hours",
    region: "us-central1",
    secrets: [GEMINI_API_KEY, OPENAI_API_KEY, XAI_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async () => {
    const db = getFirestore();
    const snap = await db
      .collection("labirent_pool")
      .where("status", "==", "generating")
      .limit(12)
      .get();
    if (snap.empty) {
      console.log("[labirent_pool] generating havuz yok");
      return;
    }
    for (const doc of snap.docs) {
      try {
        await fillPool(doc.id, doc.data());
      } catch (e) {
        console.error(`[labirent_pool] ${doc.id} doldurma hatası:`, e);
      }
    }
  }
);

// ─── Çekirdek doldurucu ──────────────────────────────────────────────────────

type PoolData = FirebaseFirestore.DocumentData;

async function fillPool(poolKey: string, data: PoolData): Promise<void> {
  const db = getFirestore();
  const ref = db.collection("labirent_pool").doc(poolKey);

  let qCount = (data.questionCount as number) ?? 0;
  let fCount = (data.factCount as number) ?? 0;
  if (qCount >= Q_TARGET && fCount >= F_TARGET) {
    await ref.update({ status: "ready", updatedAt: FieldValue.serverTimestamp() });
    return;
  }

  const lang = (data.lang as string) || "tr";
  const sig = (data.curriculumSig as string) || "";
  const level = (data.level as string) || "";
  const grade = (data.grade as string) || "";
  const subjectsHint = (data.subjectsHint as string) || "";
  const optionCount = Math.min(Math.max((data.optionCount as number) ?? 4, 3), 5);

  // 1) DONÖR ara: aynı müfredat imzası + level + grade, DOLU başka havuz.
  let donor: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  if (sig) {
    const dsnap = await db
      .collection("labirent_pool")
      .where("curriculumSig", "==", sig)
      .where("level", "==", level)
      .where("grade", "==", grade)
      .where("status", "==", "ready")
      .limit(3)
      .get();
    for (const d of dsnap.docs) {
      if (d.id !== poolKey) { donor = d; break; }
    }
  }

  let aiCalls = 0;
  while ((qCount < Q_TARGET || fCount < F_TARGET) && aiCalls < MAX_AI_CALLS_PER_RUN) {
    let added: { q: number; f: number };
    if (donor && (donor.data().lang as string) === lang) {
      added = await copyFromDonor(ref, donor.ref, qCount, fCount);
      if (added.q === 0 && added.f === 0) donor = null; // donörde yeni içerik kalmadı
    } else if (donor) {
      aiCalls++;
      added = await translateFromDonor(ref, donor.ref, lang, qCount, fCount);
      if (added.q === 0 && added.f === 0) donor = null;
    } else {
      aiCalls++;
      added = await generateFresh(ref, {
        lang, subjectsHint, grade, level, optionCount,
        needQ: qCount < Q_TARGET, needF: fCount < F_TARGET,
      });
      if (added.q === 0 && added.f === 0) break; // üretim tıkandı — bir sonraki koşu
    }
    qCount += added.q;
    fCount += added.f;
  }

  const update: Record<string, unknown> = {
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (qCount >= Q_TARGET && fCount >= F_TARGET) update.status = "ready";
  await ref.update(update);
  console.log(`[labirent_pool] ${poolKey} → soru=${qCount} bilgi=${fCount} ${update.status ?? ""}`);
}

// ─── Donörden doğrudan kopya (aynı dil — AI yok) ─────────────────────────────

async function copyFromDonor(
  ref: FirebaseFirestore.DocumentReference,
  donorRef: FirebaseFirestore.DocumentReference,
  qCount: number,
  fCount: number
): Promise<{ q: number; f: number }> {
  const db = getFirestore();
  let q = 0, f = 0;
  const batch = db.batch();
  if (qCount < Q_CAP) {
    const snap = await donorRef.collection("q").limit(Q_CAP).get();
    for (const d of snap.docs) {
      if (qCount + q >= Q_CAP) break;
      const target = ref.collection("q").doc(d.id);
      if ((await target.get()).exists) continue;
      batch.set(target, { ...d.data(), src: "donor_copy" });
      q++;
    }
  }
  if (fCount < F_CAP) {
    const snap = await donorRef.collection("f").limit(F_CAP).get();
    for (const d of snap.docs) {
      if (fCount + f >= F_CAP) break;
      const target = ref.collection("f").doc(d.id);
      if ((await target.get()).exists) continue;
      batch.set(target, { ...d.data(), src: "donor_copy" });
      f++;
    }
  }
  if (q > 0 || f > 0) {
    batch.set(ref, {
      ...(q > 0 ? { questionCount: FieldValue.increment(q) } : {}),
      ...(f > 0 ? { factCount: FieldValue.increment(f) } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();
    console.log(`[labirent_pool] donör kopya: +${q} soru +${f} bilgi`);
  }
  return { q, f };
}

// ─── Donörden çeviri (farklı dil — üretim yerine çeviri) ─────────────────────

async function translateFromDonor(
  ref: FirebaseFirestore.DocumentReference,
  donorRef: FirebaseFirestore.DocumentReference,
  lang: string,
  qCount: number,
  fCount: number
): Promise<{ q: number; f: number }> {
  // Donörden henüz bu havuzda olmayan bir dilim al (id'ler içerik hash'i —
  // çeviri sonrası id'yi hedef metinden yeniden üretmek yerine donör id'si
  // `t_` önekiyle kullanılır ki "hangi donör içeriği çevrildi" izlenebilsin).
  const wantQ = qCount < Q_TARGET ? Q_BATCH : 0;
  const wantF = fCount < F_TARGET ? F_BATCH : 0;

  const qDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  if (wantQ > 0) {
    const snap = await donorRef.collection("q").limit(Q_CAP).get();
    for (const d of snap.docs) {
      if (qDocs.length >= wantQ) break;
      if ((await ref.collection("q").doc(`t_${d.id}`).get()).exists) continue;
      qDocs.push(d);
    }
  }
  const fDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  if (wantF > 0) {
    const snap = await donorRef.collection("f").limit(F_CAP).get();
    for (const d of snap.docs) {
      if (fDocs.length >= wantF) break;
      if ((await ref.collection("f").doc(`t_${d.id}`).get()).exists) continue;
      fDocs.push(d);
    }
  }
  if (qDocs.length === 0 && fDocs.length === 0) return { q: 0, f: 0 };

  const payload = {
    questions: qDocs.map((d) => ({
      q: d.data().q, opts: d.data().opts, sol: d.data().sol ?? "",
    })),
    facts: fDocs.map((d) => d.data().t),
  };
  const prompt = `Aşağıdaki eğitim içeriğini (sorular + bilgi cümleleri) ISO dil kodu "${lang}" olan dile çevir.
KURALLAR:
- SADECE geçerli JSON döndür, aynı yapıda: {"questions":[{"q":"..","opts":["..",..],"sol":".."}],"facts":[".."]}
- Soru/şık/çözüm sayıları ve SIRALARI aynen korunur ("a" indeksi değişmez, o yüzden şık sırasını ASLA değiştirme).
- Sayılar, formüller, Unicode semboller (H₂O, x², →, ×, ÷, π) aynen kalır.
- Doğal, ders kitabı kalitesinde çeviri; hedef dil dışında dil KULLANMA.

${JSON.stringify(payload)}`;

  const raw = await generateTextFailover(
    aiKeys(),
    { temperature: 0.2, maxOutputTokens: 16384, responseMimeType: "application/json" },
    prompt
  );
  let dec: { questions?: { q: string; opts: string[]; sol?: string }[]; facts?: string[] };
  try {
    dec = JSON.parse(raw.replace(/^```[a-z]*\n?/i, "").replace(/```\s*$/, ""));
  } catch {
    console.warn("[labirent_pool] çeviri JSON parse hatası");
    return { q: 0, f: 0 };
  }

  const db = getFirestore();
  const batch = db.batch();
  let q = 0, f = 0;
  (dec.questions ?? []).forEach((tq, i) => {
    const src = qDocs[i];
    if (!src || !tq?.q || !Array.isArray(tq.opts)) return;
    if (tq.opts.length !== (src.data().opts as string[]).length) return;
    batch.set(ref.collection("q").doc(`t_${src.id}`), {
      q: tq.q,
      opts: tq.opts,
      a: src.data().a,
      sol: tq.sol ?? "",
      src: "donor_translate",
      createdAt: FieldValue.serverTimestamp(),
    });
    q++;
  });
  (dec.facts ?? []).forEach((tf, i) => {
    const src = fDocs[i];
    if (!src || typeof tf !== "string" || tf.trim().length < 10) return;
    batch.set(ref.collection("f").doc(`t_${src.id}`), {
      t: tf.trim(),
      src: "donor_translate",
      createdAt: FieldValue.serverTimestamp(),
    });
    f++;
  });
  if (q > 0 || f > 0) {
    batch.set(ref, {
      ...(q > 0 ? { questionCount: FieldValue.increment(q) } : {}),
      ...(f > 0 ? { factCount: FieldValue.increment(f) } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();
    console.log(`[labirent_pool] donör çeviri: +${q} soru +${f} bilgi (${lang})`);
  }
  return { q, f };
}

// ─── Sıfırdan üretim ─────────────────────────────────────────────────────────

function stableHash(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(36);
}

async function generateFresh(
  ref: FirebaseFirestore.DocumentReference,
  p: {
    lang: string; subjectsHint: string; grade: string; level: string;
    optionCount: number; needQ: boolean; needF: boolean;
  }
): Promise<{ q: number; f: number }> {
  const langLine = p.lang === "tr"
    ? "Tüm metinleri Türkçe yaz."
    : `TÜM çıktıyı ISO dil kodu "${p.lang}" olan dilde yaz. Bu dil dışında Türkçe veya İngilizce KULLANMA.`;
  const wantQ = p.needQ ? Q_BATCH : 0;
  const wantF = p.needF ? F_BATCH : 0;

  const prompt = `[BİLGİ LABİRENTİ İÇERİK ÜRETİMİ · JSON]
Seviye/Sınıf: ${p.level} ${p.grade}
Dersler: ${p.subjectsHint}
Dil: ${langLine}

GÖREV: Yukarıdaki derslerden KARIŞIK olarak${wantQ > 0 ? ` TAM ${wantQ} adet ÇOKTAN SEÇMELİ soru (${p.optionCount} şıklı)` : ""}${wantQ > 0 && wantF > 0 ? " ve" : ""}${wantF > 0 ? ` TAM ${wantF} adet KISA (tek cümle, ≤120 karakter) öğretici bilgi cümlesi` : ""} üret.

SADECE geçerli JSON döndür:
{"questions":[{"q":"soru kökü","opts":["şık1",...],"a":0,"sol":"kısa çözüm"}],"facts":["bilgi", ...]}

KURALLAR:
- "a": doğru şıkkın 0-tabanlı indeksi. Tek tartışmasız doğru cevap; çeldiriciler tipik öğrenci hatalarından.
- Sorular bu sınıf düzeyinin GERÇEK müfredat kazanımlarını ölçmeli; sınıf altı basit aritmetik YASAK.
- Matematik/fen gösterimi DÜZ UNICODE (H₂O, x², →, ×, ÷, π, √); LaTeX ve markdown YOK.
- Sorular ve bilgiler kendi aralarında ÇEŞİTLİ olsun (farklı ders/konu/kalıp).`;

  const raw = await generateTextFailover(
    aiKeys(),
    { temperature: 0.85, maxOutputTokens: 16384, responseMimeType: "application/json" },
    prompt,
    { primaryModel: "gemini-2.5-flash-lite", fallbackModel: "gemini-2.5-flash" }
  );
  let dec: { questions?: { q: string; opts: string[]; a: number; sol?: string }[]; facts?: string[] };
  try {
    dec = JSON.parse(raw.replace(/^```[a-z]*\n?/i, "").replace(/```\s*$/, ""));
  } catch {
    console.warn("[labirent_pool] üretim JSON parse hatası");
    return { q: 0, f: 0 };
  }

  const db = getFirestore();
  const batch = db.batch();
  let q = 0, f = 0;
  for (const it of dec.questions ?? []) {
    const text = (it?.q ?? "").trim();
    const opts = Array.isArray(it?.opts) ? it.opts.map(String) : [];
    const a = typeof it?.a === "number" ? it.a : 0;
    if (text.length < 10 || opts.length < 3 || a < 0 || a >= opts.length) continue;
    const id = stableHash(text.toLowerCase().replace(/\s+/g, " "));
    const target = ref.collection("q").doc(id);
    if ((await target.get()).exists) continue;
    batch.set(target, {
      q: text, opts, a, sol: (it.sol ?? "").toString(),
      src: "cf_gen", createdAt: FieldValue.serverTimestamp(),
    });
    q++;
  }
  for (const it of dec.facts ?? []) {
    const t = (typeof it === "string" ? it : "").trim();
    if (t.length < 10 || t.length > 380) continue;
    const id = stableHash(t.toLowerCase());
    const target = ref.collection("f").doc(id);
    if ((await target.get()).exists) continue;
    batch.set(target, { t, src: "cf_gen", createdAt: FieldValue.serverTimestamp() });
    f++;
  }
  if (q > 0 || f > 0) {
    batch.set(ref, {
      ...(q > 0 ? { questionCount: FieldValue.increment(q) } : {}),
      ...(f > 0 ? { factCount: FieldValue.increment(f) } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();
    console.log(`[labirent_pool] üretim: +${q} soru +${f} bilgi`);
  }
  return { q, f };
}
