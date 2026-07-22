/**
 * LESSON PACK GENERATOR — İndirilebilir dil paketi üreticisi.
 *
 * AMAÇ: 3D ders sahnelerinin (ve tüm UI metinlerinin) çevirisi her kullanıcının
 * cihazında Gemini ile tekrar tekrar üretilmesin. Bir dil SUNUCUDA bir kez
 * çevrilir → Firebase Storage'a yazılır → o dildeki TÜM kullanıcılara servis
 * edilir (istemci: lesson_pack_service.dart). Netflix'in altyazı izini indirmesi
 * modeli; maliyet cihaz-başına değil DİL-başına-bir-kez.
 *
 * VERİ:
 *   Storage lesson_i18n/_sources.json   → TR kaynak string dizisi (build çıktısı;
 *                                          tool/extract_lesson_i18n.js üretir,
 *                                          bir kez Storage'a yüklenir).
 *   Storage lesson_i18n/{lang}.json     → { kaynak: çeviri } paketi (birikimli).
 *   Firestore lesson_packs/{lang}       → { version, count, path, status }.
 *
 * DİRENÇ: Her koşu, eksik kaynakların yalnızca bir DİLİMİNİ çevirir (sıkı tavan
 * MAX_AI_CALLS_PER_RUN) ve pakete ekler; sonraki koşu kaldığı yerden devam eder
 * (kontrolsüz şişme/uzun koşu YOK). Tümü bitince status='ready'.
 *
 * KREDİ: Yalnızca Gemini çağrısı yapar; kredi/anahtar yoksa çeviri adımı
 * başarısız olur ama iskelet + tetikleyiciler hazırdır. Kredi gelince çalışır.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { generateTextFailover } from "./gemini_util";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const XAI_API_KEY = defineSecret("XAI_API_KEY");
const DEEPSEEK_API_KEY = defineSecret("DEEPSEEK_API_KEY");
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

function aiKeys() {
  return {
    gemini: GEMINI_API_KEY.value(),
    openai: OPENAI_API_KEY.value() || undefined,
    xai: XAI_API_KEY.value() || undefined,
    deepseek: DEEPSEEK_API_KEY.value() || undefined,
    anthropic: ANTHROPIC_API_KEY.value() || undefined,
  };
}

// Varsayılan bucket bu projede *.firebasestorage.app; admin'in otomatik
// algıladığı *.appspot.com ile karışmasın diye AÇIKÇA belirtilir.
const BUCKET = "qualsar2-640f0.firebasestorage.app";
const bucketRef = () => getStorage().bucket(BUCKET);

const SOURCES_PATH = "lesson_i18n/_sources.json";
const packPath = (lang: string) => `lesson_i18n/${lang}.json`;

const BATCH = 60;                 // her AI çağrısında çevrilen string
const MAX_AI_CALLS_PER_RUN = 6;   // koşu başına sıkı tavan (şişme yok)
const PACK_VERSION = 1;           // paket şeması sürümü (kaynak değişince artır)

// Desteklenen diller (locale_service.dart supportedLocales ile hizalı; TR hariç).
const LANG_NAMES: Record<string, string> = {
  en: "English", es: "Spanish", fr: "French", de: "German", it: "Italian",
  pt: "Portuguese", ru: "Russian", zh: "Simplified Chinese", ja: "Japanese",
  ko: "Korean", ar: "Arabic", hi: "Hindi", nl: "Dutch", pl: "Polish",
  sv: "Swedish", vi: "Vietnamese", th: "Thai", id: "Indonesian", el: "Greek",
  cs: "Czech", da: "Danish", fi: "Finnish", hu: "Hungarian", no: "Norwegian",
  ro: "Romanian", sk: "Slovak", bg: "Bulgarian", hr: "Croatian", sr: "Serbian",
  uk: "Ukrainian", he: "Hebrew", fa: "Persian", ur: "Urdu", bn: "Bengali",
  ta: "Tamil", te: "Telugu", ms: "Malay", tl: "Filipino", sw: "Swahili",
  af: "Afrikaans", am: "Amharic", my: "Burmese", km: "Khmer", lo: "Lao",
  ne: "Nepali", si: "Sinhala", ka: "Georgian", az: "Azerbaijani",
  kk: "Kazakh", uz: "Uzbek", mn: "Mongolian", et: "Estonian", lt: "Lithuanian",
  lv: "Latvian", pa: "Punjabi", mr: "Marathi", ha: "Hausa",
};

type Pack = Record<string, string>;

async function readJson<T>(path: string): Promise<T | null> {
  try {
    const file = bucketRef().file(path);
    const [exists] = await file.exists();
    if (!exists) return null;
    const [buf] = await file.download();
    return JSON.parse(buf.toString("utf8")) as T;
  } catch (e) {
    console.warn(`[lesson_pack] readJson(${path}) hata: ${e}`);
    return null;
  }
}

async function writeJson(path: string, data: unknown): Promise<void> {
  const file = bucketRef().file(path);
  await file.save(JSON.stringify(data), {
    contentType: "application/json; charset=utf-8",
    resumable: false,
  });
}

// Gemini'ye TR→hedef dil batch çeviri. Girdi/çıktı JSON dizisi, aynı uzunluk/sıra.
async function translateBatch(chunk: string[], langName: string): Promise<Pack> {
  const prompt = `You are a professional translator for an education app (QuAlsar).
Translate each string in the JSON array below from Turkish to ${langName}.
STRICT RULES:
- Output ONLY a JSON array with the same length and order as the input.
- No explanation, no markdown, no code fences.
- Preserve emojis, punctuation, numbers, and math notation between $...$ EXACTLY (do not translate content inside $...$).
- Keep chemistry/physics symbols and abbreviations (VSEPR, DNA, RNA, C3/C4/CAM, →, ×, ²) unchanged.
- Translate technical terms naturally using the target country's school terminology.

Input:
${JSON.stringify(chunk)}

Output (JSON array only):`;

  const raw = await generateTextFailover(
    aiKeys(),
    { temperature: 0, topP: 0.1, maxOutputTokens: 8192 },
    prompt,
    { primaryModel: "gemini-2.5-flash-lite", fallbackModel: "gemini-2.5-flash" }
  );

  let s = (raw || "").trim();
  if (s.startsWith("```")) {
    const end = s.lastIndexOf("```");
    if (end > 3) {
      s = s.slice(3, end);
      const nl = s.indexOf("\n");
      if (nl > -1) s = s.slice(nl + 1);
    }
    s = s.trim();
  }
  let arr: unknown;
  try { arr = JSON.parse(s); } catch { return {}; }
  if (!Array.isArray(arr) || arr.length !== chunk.length) return {};
  const out: Pack = {};
  for (let i = 0; i < chunk.length; i++) {
    const t = String(arr[i] ?? "").trim();
    if (t) out[chunk[i]] = t;
  }
  return out;
}

/**
 * Bir dilin paketini eksik kısımdan devam ederek doldurur. Koşu başına en fazla
 * MAX_AI_CALLS_PER_RUN batch çevirir; tümü bitince status='ready' yazar.
 * @returns { done, translated, remaining }
 */
async function fillLang(lang: string): Promise<{ done: boolean; translated: number; remaining: number }> {
  const langName = LANG_NAMES[lang];
  if (!langName) throw new Error(`desteklenmeyen dil: ${lang}`);

  const sources = await readJson<string[]>(SOURCES_PATH);
  if (!sources || !sources.length) {
    throw new Error("kaynak listesi (_sources.json) Storage'da yok/boş");
  }
  const pack = (await readJson<Pack>(packPath(lang))) || {};

  const missing = sources.filter((s) => !(s in pack));
  if (missing.length === 0) {
    await getFirestore().collection("lesson_packs").doc(lang).set(
      {
        version: PACK_VERSION,
        count: Object.keys(pack).length,
        path: packPath(lang),
        status: "ready",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { done: true, translated: 0, remaining: 0 };
  }

  let translated = 0;
  let calls = 0;
  for (let i = 0; i < missing.length && calls < MAX_AI_CALLS_PER_RUN; i += BATCH) {
    const chunk = missing.slice(i, i + BATCH);
    calls++;
    try {
      const res = await translateBatch(chunk, langName);
      Object.assign(pack, res);
      translated += Object.keys(res).length;
    } catch (e) {
      console.warn(`[lesson_pack] ${lang} batch hata: ${e}`);
    }
  }

  if (translated > 0) await writeJson(packPath(lang), pack);

  const remaining = sources.filter((s) => !(s in pack)).length;
  const done = remaining === 0;
  await getFirestore().collection("lesson_packs").doc(lang).set(
    {
      version: PACK_VERSION,
      count: Object.keys(pack).length,
      total: sources.length,
      path: packPath(lang),
      status: done ? "ready" : "generating",
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return { done, translated, remaining };
}

// ─── Callable: istemci bir dile geçince "bu dilin paketini üret/devam et" ────
//   İstemci hemen sonucu beklemez; manifest 'generating' ise runtime akışı
//   geçici devrededir, paket hazır olunca bir sonraki sync'te iner.
export const ensureLessonPack = onCall(
  {
    region: "us-central1",
    secrets: [GEMINI_API_KEY, OPENAI_API_KEY, XAI_API_KEY, DEEPSEEK_API_KEY, ANTHROPIC_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (req) => {
    const lang = String(req.data?.lang || "").trim();
    if (!lang || !LANG_NAMES[lang]) {
      throw new HttpsError("invalid-argument", "geçersiz dil");
    }
    const manifest = await getFirestore().collection("lesson_packs").doc(lang).get();
    if (manifest.data()?.status === "ready") {
      return { status: "ready" };
    }
    const r = await fillLang(lang);
    return { status: r.done ? "ready" : "generating", ...r };
  }
);

// ─── Scheduled: yarım kalan (generating) dilleri hedefe kadar tamamla ────────
export const scheduledLessonPackFill = onSchedule(
  {
    schedule: "every 2 hours",
    region: "us-central1",
    secrets: [GEMINI_API_KEY, OPENAI_API_KEY, XAI_API_KEY, DEEPSEEK_API_KEY, ANTHROPIC_API_KEY],
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async () => {
    const snap = await getFirestore()
      .collection("lesson_packs")
      .where("status", "==", "generating")
      .limit(3) // koşu başına en fazla 3 dil (şişme yok)
      .get();
    for (const doc of snap.docs) {
      try {
        const r = await fillLang(doc.id);
        console.log(`[lesson_pack] ${doc.id}: +${r.translated}, kalan ${r.remaining}`);
      } catch (e) {
        console.warn(`[lesson_pack] ${doc.id} fill hata: ${e}`);
      }
    }
  }
);
