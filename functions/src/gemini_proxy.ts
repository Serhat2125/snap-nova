/**
 * GEMINI PROXY — Güvenli API anahtarı kullanımı.
 *
 * AMAÇ:
 *   Gemini API anahtarı APK içinde gömülü olursa reverse engineering ile çekilir
 *   ve sınırsız kullanıma açılır. Bu fonksiyon anahtarı Firebase env'inde tutar;
 *   Flutter app Firebase Auth ID token ile çağırır, sadece authenticated
 *   kullanıcılar AI çağrısı yapabilir.
 *
 * KURULUM (kullanıcı tarafından):
 *   1. Firebase CLI yükle: `npm install -g firebase-tools`
 *   2. functions/ klasöründe: `npm install`
 *   3. Anahtarı set et:
 *        firebase functions:secrets:set GEMINI_API_KEY
 *        (sorduğunda gerçek key'i yapıştır)
 *   4. (opsiyonel) Yedek anahtar:
 *        firebase functions:secrets:set GEMINI_API_KEY_FALLBACK
 *   5. Deploy:
 *        firebase deploy --only functions:geminiProxy
 *
 * KULLANIM (Flutter tarafında):
 *   const url = 'https://us-central1-qualsar2-640f0.cloudfunctions.net/geminiProxy';
 *   final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
 *   final response = await http.post(
 *     Uri.parse(url),
 *     headers: {
 *       'Content-Type': 'application/json',
 *       'Authorization': 'Bearer $idToken',
 *     },
 *     body: jsonEncode({
 *       'model': 'gemini-2.5-flash',
 *       'contents': [...],
 *       'generationConfig': {...},
 *     }),
 *   );
 *
 * RATE LIMIT:
 *   Firestore üzerinden user başına 100 çağrı/dakika kotası (basit). Premium
 *   olmayanlara da bu sınır uygulanır. Quota dolarsa 429 döner.
 */

import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

// Firebase Secret Manager'dan oku — kodda hardcode YOK.
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const GEMINI_API_KEY_FALLBACK = defineSecret("GEMINI_API_KEY_FALLBACK");

const RATE_LIMIT_PER_MIN = 100;

interface GeminiRequest {
  model?: string;
  contents?: unknown;
  generationConfig?: unknown;
  systemInstruction?: unknown;
  safetySettings?: unknown;
  tools?: unknown;
}

export const geminiProxy = onRequest(
  {
    cors: true,
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "512MiB",
    secrets: [GEMINI_API_KEY, GEMINI_API_KEY_FALLBACK],
    maxInstances: 50,
  },
  async (req, res) => {
    // ── 1) HTTP method kontrolü ────────────────────────────────────────────
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed. Use POST." });
      return;
    }

    // ── 2) Bearer token doğrulama ─────────────────────────────────────────
    const authHeader = req.headers.authorization ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header." });
      return;
    }
    const idToken = authHeader.substring("Bearer ".length).trim();
    let uid: string;
    try {
      const decoded = await getAuth().verifyIdToken(idToken);
      uid = decoded.uid;
    } catch (e) {
      res.status(401).json({ error: "Invalid Firebase ID token." });
      return;
    }

    // ── 3) Rate limit (Firestore atomic counter) ──────────────────────────
    const now = new Date();
    const minuteBucket = `${now.getUTCFullYear()}-${now.getUTCMonth()}-${now.getUTCDate()}-${now.getUTCHours()}-${now.getUTCMinutes()}`;
    const rateDoc = getFirestore()
      .collection("rate_limits")
      .doc(`${uid}__${minuteBucket}`);
    try {
      await getFirestore().runTransaction(async (tx) => {
        const snap = await tx.get(rateDoc);
        const count = (snap.data()?.count as number) ?? 0;
        if (count >= RATE_LIMIT_PER_MIN) {
          throw new Error("rate-limit");
        }
        tx.set(
          rateDoc,
          {
            count: FieldValue.increment(1),
            uid,
            expiresAt: new Date(now.getTime() + 5 * 60 * 1000),
          },
          { merge: true }
        );
      });
    } catch (e) {
      if ((e as Error).message === "rate-limit") {
        res.status(429).json({
          error: "Rate limit exceeded. Lütfen birkaç dakika sonra dene.",
        });
        return;
      }
      // Diğer hatalar — fail-open (rate limit kritik değil)
      console.warn("Rate limit check failed:", e);
    }

    // ── 4) Request body parse ─────────────────────────────────────────────
    const body = req.body as GeminiRequest;
    if (!body || !body.contents) {
      res.status(400).json({ error: "Missing 'contents' in request body." });
      return;
    }
    const model = body.model || "gemini-2.5-flash";

    // ── 5) Gemini API'ye proxy ───────────────────────────────────────────
    const keysToTry = [GEMINI_API_KEY.value(), GEMINI_API_KEY_FALLBACK.value()]
      .filter((k) => k && k.length > 0);

    if (keysToTry.length === 0) {
      res.status(500).json({
        error:
          "Sunucuda Gemini anahtarı ayarlanmamış. Yöneticiyle iletişime geç.",
      });
      return;
    }

    const payload: Record<string, unknown> = {
      contents: body.contents,
    };
    if (body.generationConfig) payload.generationConfig = body.generationConfig;
    if (body.systemInstruction) payload.systemInstruction = body.systemInstruction;
    if (body.safetySettings) payload.safetySettings = body.safetySettings;
    if (body.tools) payload.tools = body.tools;

    let lastError: { status: number; body: string } | null = null;

    for (const apiKey of keysToTry) {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
        model
      )}:generateContent?key=${apiKey}`;
      try {
        const upstream = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });

        const text = await upstream.text();

        if (upstream.ok) {
          // ── 6) Başarılı yanıtı geri döndür ────────────────────────────
          // Gemini'nin orijinal JSON yanıtını aynen geçiriyoruz; Flutter
          // tarafı zaten bu schema'yı parse ediyor.
          res.status(200).type("application/json").send(text);
          return;
        }

        lastError = { status: upstream.status, body: text };
        // 401/403/429 → bir sonraki key'i dene; diğer hatalarda kır.
        if (
          upstream.status !== 401 &&
          upstream.status !== 403 &&
          upstream.status !== 429
        ) {
          break;
        }
      } catch (e) {
        lastError = { status: 502, body: String(e) };
      }
    }

    // ── 7) Tüm key'ler başarısız ─────────────────────────────────────────
    const status = lastError?.status ?? 502;
    res.status(status).json({
      error: "Upstream Gemini API hatası.",
      upstreamStatus: status,
      details: lastError?.body?.slice(0, 500) ?? null,
    });
  }
);
