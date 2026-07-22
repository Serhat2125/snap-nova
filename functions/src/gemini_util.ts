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

// ═══════════════════════════════════════════════════════════════════════════
//  Çok sağlayıcılı failover — arka plan üreticileri için.
//  Sıra (kullanıcı isteği): Gemini → ChatGPT (gpt-4o-mini) → Grok (grok-3-mini).
//  Gemini kredisi/kotası bittiğinde havuz doldurma durmasın.
// ═══════════════════════════════════════════════════════════════════════════

/** OpenAI-uyumlu chat/completions çağrısı (OpenAI ve xAI/Grok aynı şema). */
async function callChatCompletions(
  url: string,
  apiKey: string,
  model: string,
  prompt: string,
  generationConfig: Record<string, unknown>,
  timeoutMs: number
): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const body: Record<string, unknown> = {
      model,
      messages: [{ role: "user", content: prompt }],
      max_tokens: (generationConfig.maxOutputTokens as number) ?? 8192,
      temperature: (generationConfig.temperature as number) ?? 0.7,
    };
    if (generationConfig.responseMimeType === "application/json") {
      body.response_format = { type: "json_object" };
    }
    const resp = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timer);
    const raw = await resp.text();
    if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${raw.slice(0, 160)}`);
    const j = JSON.parse(raw) as {
      choices?: { message?: { content?: string } }[];
    };
    const text = j?.choices?.[0]?.message?.content ?? "";
    if (!text.trim()) throw new Error("boş yanıt");
    return text;
  } finally {
    clearTimeout(timer);
  }
}

/** Anthropic (Claude) messages çağrısı — şema OpenAI'dan farklı. */
async function callAnthropic(
  apiKey: string,
  model: string,
  prompt: string,
  generationConfig: Record<string, unknown>,
  timeoutMs: number
): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: (generationConfig.maxOutputTokens as number) ?? 8192,
        messages: [{ role: "user", content: prompt }],
      }),
      signal: controller.signal,
    });
    const raw = await resp.text();
    if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${raw.slice(0, 160)}`);
    const j = JSON.parse(raw) as {
      content?: { type?: string; text?: string }[];
    };
    const text = Array.isArray(j?.content)
      ? j.content.filter((b) => b?.type === "text").map((b) => b.text ?? "").join("")
      : "";
    if (!text.trim()) throw new Error("boş yanıt");
    return text;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Gemini → ChatGPT → DeepSeek → Grok → Claude sıralı failover ile metin üretimi
 * (uygulamadaki standart zincirle aynı sıra; Claude en pahalı → en son).
 * Anahtarı verilmeyen sağlayıcı atlanır (Gemini-only davranışa kadar düşer).
 * Hepsi başarısızsa son hatayı fırlatır.
 */
export async function generateTextFailover(
  keys: {
    gemini: string;
    openai?: string;
    xai?: string;
    deepseek?: string;
    anthropic?: string;
  },
  generationConfig: Record<string, unknown>,
  prompt: string,
  opts?: { primaryModel?: string; fallbackModel?: string }
): Promise<string> {
  let lastErr: unknown;
  try {
    return await generateGeminiText(keys.gemini, generationConfig, prompt, opts);
  } catch (e) {
    lastErr = e;
    console.warn(`[ai_failover] Gemini başarısız → sıradaki sağlayıcı: ${e}`);
  }
  // OpenAI-uyumlu sağlayıcılar tek şemadan sırayla denenir.
  const compat: { name: string; url: string; key?: string; model: string }[] = [
    { name: "ChatGPT", url: "https://api.openai.com/v1/chat/completions", key: keys.openai, model: "gpt-4o-mini" },
    { name: "DeepSeek", url: "https://api.deepseek.com/chat/completions", key: keys.deepseek, model: "deepseek-chat" },
    { name: "Grok", url: "https://api.x.ai/v1/chat/completions", key: keys.xai, model: "grok-3-mini" },
  ];
  for (const p of compat) {
    if (!p.key) continue;
    try {
      return await callChatCompletions(p.url, p.key, p.model, prompt, generationConfig, 45000);
    } catch (e) {
      lastErr = e;
      console.warn(`[ai_failover] ${p.name} başarısız → sıradaki sağlayıcı: ${e}`);
    }
  }
  if (keys.anthropic) {
    try {
      return await callAnthropic(
        keys.anthropic, "claude-haiku-4-5", prompt, generationConfig, 45000
      );
    } catch (e) {
      lastErr = e;
    }
  }
  throw new Error(`Tüm AI sağlayıcıları başarısız: ${lastErr}`);
}
