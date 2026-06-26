// ═══════════════════════════════════════════════════════════════════════════
//  gemini_util — Arka plan (batch) Gemini çağrıları için dayanıklı yardımcı.
//
//  SORUN: gemini-2.5-flash-lite Google tarafında kalıcı olarak ~%60 oranında
//  503 "high demand" döndürüyordu (canlı ölçüm). Tek-anahtar, retry'sız doğrudan
//  çağrılar (soru havuzu, soru jürisi, özet jürisi) bu yüzden çoğunlukla
//  başarısız oluyordu → "cevap vermiyor".
//
//  ÇÖZÜM: önce ucuz flash-lite'ı BİR kez dene (sağlıklıyken maliyet düşük);
//  503/429/5xx/timeout gelirse anında güvenilir gemini-2.5-flash'a düş
//  (canlı testte %0 hata). Böylece hem maliyet-uyumlu hem garantili yanıt.
// ═══════════════════════════════════════════════════════════════════════════

const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const RETRYABLE = new Set([408, 429, 500, 502, 503, 504]);

interface OnceResult {
  ok: boolean;
  status: number;
  text: string;
}

async function callOnce(
  model: string,
  apiKey: string,
  body: unknown,
  timeoutMs: number
): Promise<OnceResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const resp = await fetch(`${BASE}/${model}:generateContent?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timer);
    const raw = await resp.text();
    if (!resp.ok) return { ok: false, status: resp.status, text: raw };
    const j = JSON.parse(raw) as {
      candidates?: { content?: { parts?: { text?: string }[] } }[];
    };
    const text =
      j?.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ??
      "";
    return { ok: true, status: 200, text };
  } catch (e) {
    clearTimeout(timer);
    // AbortError (timeout) dahil → retryable say (504)
    return { ok: false, status: 504, text: String(e) };
  }
}

/**
 * Dayanıklı Gemini metin üretimi. flash-lite → (hata) → flash fallback.
 * Döndürdüğü: model çıktısının düz metni (JSON modunda JSON string'i).
 * Tüm denemeler boş/başarısızsa hata fırlatır.
 */
export async function generateGeminiText(
  apiKey: string,
  generationConfig: Record<string, unknown>,
  prompt: string,
  opts?: { primaryModel?: string; fallbackModel?: string }
): Promise<string> {
  if (!apiKey) throw new Error("Gemini anahtarı yok.");
  const primary = opts?.primaryModel ?? "gemini-2.5-flash-lite";
  const fallback = opts?.fallbackModel ?? "gemini-2.5-flash";
  const body = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig,
  };

  // 1) Ucuz flash-lite — tek hızlı deneme.
  const first = await callOnce(primary, apiKey, body, 12000);
  if (first.ok && first.text.trim().length > 0) return first.text;

  // 2) flash-lite başarısız (503/429/timeout/boş) → güvenilir flash (2 deneme).
  let lastStatus = first.status;
  for (let attempt = 0; attempt < 2; attempt++) {
    const f = await callOnce(fallback, apiKey, body, 15000);
    if (f.ok && f.text.trim().length > 0) return f.text;
    lastStatus = f.status;
    if (!RETRYABLE.has(f.status)) break;
    await new Promise((r) => setTimeout(r, 600 * (attempt + 1)));
  }
  throw new Error(`Gemini başarısız (son durum ${lastStatus}).`);
}
