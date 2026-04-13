import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ═══════════════════════════════════════════════════════════════════════════════
//  GeminiService — OpenRouter API (google/gemini-flash-1.5)
// ═══════════════════════════════════════════════════════════════════════════════

class GeminiService {
  static const _apiKey  = 'AIzaSyADUEj_oR9aVbG5ulgJkWz4YM2TGTof410';
  static const _model   = 'gemini-2.0-flash';
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';
  static const _tag     = '🤖 [GeminiService]';

  static void _log(String msg) {
    if (kDebugMode) debugPrint('$_tag $msg');
  }

  // ── Google AI API çağrısı (metin) ──────────────────────────────────────────
  static Future<String> _callGemini({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 2048,
    double temperature = 0.3,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final url = '$_baseUrl/$_model:generateContent?key=$_apiKey';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [{'text': '$systemPrompt\n\n$userMessage'}],
          },
        ],
        'generationConfig': {
          'maxOutputTokens': maxTokens,
          'temperature': temperature,
        },
      }),
    ).timeout(timeout);

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text == null || text.trim().isEmpty) throw GeminiException.blurryImage();
      return text;
    }

    _handleError(response);
  }

  // ── Google AI API çağrısı (görsel) ─────────────────────────────────────────
  static Future<String> _callGeminiWithImage({
    required String prompt,
    required String base64Image,
    required String mimeType,
    int maxTokens = 2048,
    double temperature = 0.3,
  }) async {
    final url = '$_baseUrl/$_model:generateContent?key=$_apiKey';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {
                'inlineData': {
                  'mimeType': mimeType,
                  'data': base64Image,
                },
              },
            ],
          },
        ],
        'generationConfig': {
          'maxOutputTokens': maxTokens,
          'temperature': temperature,
        },
      }),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text == null || text.trim().isEmpty) throw GeminiException.blurryImage();
      return text;
    }

    _handleError(response);
  }

  // ── Hata yönetimi ──────────────────────────────────────────────────────────
  static Never _handleError(http.Response response) {
    final raw = response.body;
    final s = raw.toLowerCase();
    _log('HATA yanıtı: HTTP ${response.statusCode} — $raw');

    if (response.statusCode == 429 || s.contains('quota') || s.contains('rate') || s.contains('resource_exhausted')) {
      throw GeminiException._quotaExceeded(raw);
    }
    if (response.statusCode == 400 && (s.contains('api_key') || s.contains('api key'))) {
      throw GeminiException._invalidKey(raw);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw GeminiException._invalidKey(raw);
    }
    if (response.statusCode == 413 || s.contains('too large')) {
      throw GeminiException._imageTooLarge(raw);
    }
    if (response.statusCode >= 500) {
      throw GeminiException._serverTimeout(raw);
    }
    throw GeminiException.unknown(raw);
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Görsel analiz — tüm çözüm tipleri buradan geçer
  // ══════════════════════════════════════════════════════════════════════════════
  static Future<String> analyzeImage(
    String imagePath,
    String solutionType, {
    bool isMulti = false,
  }) async {
    _log('══════════════════════════════════════════');
    _log('analyzeImage() BAŞLADI');
    _log('Çözüm tipi : "$solutionType"');
    _log('Dosya yolu : $imagePath');

    // ── 1. İnternet kontrolü ──────────────────────────────────────────────────
    _log('[1/5] İnternet kontrolü...');
    try {
      final dns = await InternetAddress.lookup('generativelanguage.googleapis.com')
          .timeout(const Duration(seconds: 10));
      if (dns.isEmpty || dns[0].rawAddress.isEmpty) {
        throw GeminiException.noInternet();
      }
      _log('[1/5] OK');
    } on SocketException {
      _log('[1/5] HATA: SocketException');
      throw GeminiException.noInternet();
    } on TimeoutException {
      _log('[1/5] HATA: DNS timeout');
      throw GeminiException.noInternet();
    }

    // ── 2. Dosya okuma ────────────────────────────────────────────────────────
    _log('[2/5] Dosya okunuyor...');
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      _log('[2/5] HATA: Dosya yok');
      throw GeminiException.blurryImage();
    }
    final imageBytes = await imageFile.readAsBytes();
    if (imageBytes.isEmpty) {
      _log('[2/5] HATA: 0 byte');
      throw GeminiException.blurryImage();
    }
    final sizeMb = imageBytes.lengthInBytes / (1024 * 1024);
    _log('[2/5] OK: ${sizeMb.toStringAsFixed(2)} MB');
    if (sizeMb > 14) throw GeminiException.imageTooLarge();

    // ── 3. Base64 encode ──────────────────────────────────────────────────────
    _log('[3/5] Base64 encode...');
    final base64Image = base64Encode(imageBytes);
    final mime = _mimeOf(imagePath);
    _log('[3/5] OK: mime=$mime');

    // ── 4. Prompt ─────────────────────────────────────────────────────────────
    _log('[4/5] Prompt oluşturuluyor...');
    final prompt = _buildPrompt(solutionType, isMulti: isMulti);
    _log('[4/5] OK: ${prompt.substring(0, prompt.length.clamp(0, 60))}...');

    // ── 5. Google AI HTTP POST ─────────────────────────────────────────────
    _log('[5/5] Google AI isteği gönderiliyor... (timeout: 60 sn)');
    try {
      final sw = Stopwatch()..start();

      final text = await _callGeminiWithImage(
        prompt: prompt,
        base64Image: base64Image,
        mimeType: mime,
      );

      sw.stop();
      _log('[5/5] OK: ${text.length} karakter — ${sw.elapsedMilliseconds} ms');
      _log('analyzeImage() BAŞARILI ✅');
      _log('══════════════════════════════════════════');
      return text;

    } on GeminiException {
      rethrow;
    } on TimeoutException {
      _log('[5/5] HATA: 60 sn timeout');
      throw GeminiException.serverTimeout();
    } on SocketException catch (e) {
      _log('[5/5] HATA: SocketException — $e');
      throw GeminiException.noInternet();
    } catch (e) {
      _log('[5/5] HATA: ${e.runtimeType} — $e');
      throw GeminiException.unknown(e.toString());
    }
  }

  // ── Yardımcılar ───────────────────────────────────────────────────────────────

  static String _mimeOf(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png'))                    return 'image/png';
    if (p.endsWith('.webp'))                   return 'image/webp';
    if (p.endsWith('.gif'))                    return 'image/gif';
    if (p.endsWith('.heic') || p.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Study Suite — JSON: 5 benzer soru + 3 video + 3 ders notu
  // ══════════════════════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> fetchStudySuite({
    required String solution,
    required String subject,
  }) async {
    _log('fetchStudySuite() — ders: "$subject"');

    try {
      final dns = await InternetAddress.lookup('generativelanguage.googleapis.com')
          .timeout(const Duration(seconds: 10));
      if (dns.isEmpty || dns[0].rawAddress.isEmpty) throw GeminiException.noInternet();
    } on SocketException { throw GeminiException.noInternet(); }
     on TimeoutException { throw GeminiException.noInternet(); }

    final systemPrompt = '''Sen bir eğitim içerik üreticisisin. Aşağıda bir öğrencinin sorduğu soruya ait çözüm verilmiştir. Bu çözümden sorunun konusunu, türünü ve kavramlarını analiz et. Tüm içeriği YALNIZCA bu soru ve bu sorunun gerektirdiği kavramlara göre üret — genel konu değil, bu soruya özel ol.

KURAL: Yalnızca geçerli JSON döndür. Markdown kullanma, açıklama yazma, hiçbir şey ekleme. Sadece JSON.
Ders / alan: $subject

BENZER SORULAR KURALLARI:
- Üretilen 5 soru, aşağıdaki çözümdeki soruyla AYNI kavram ve zorluk seviyesinde olmalı.
- Her soru bu sorudan farklı sayılar/değişkenler kullanarak özgün olmalı.
- HER soru ÇOKTAN SEÇMELİ olmalı; tam olarak 4 şık (A, B, C, D) içermeli.
- "question" alanına önce soru metni, sonra yeni satırda her şık ayrı satırda yazılacak.
  Format TAM OLARAK şöyle:
    "Soru metni burada.\\nA) birinci şık\\nB) ikinci şık\\nC) üçüncü şık\\nD) dördüncü şık"
- "solution" alanında doğru şıkkı açıkla ve adım adım çöz.

BİLGİ KARTI KURALLARI:
- 3 adet kısa bilgi kartı üret. Her kart bu sorunun konusuyla doğrudan ilgili olmalı.
- Sayısal ders (Matematik/Fizik/Kimya/Biyoloji hesap): kartın "content" alanına bu konunun
  KULLANIŞLI FORMÜLLERİNİ yaz (LaTeX formatında, her formül ayrı satırda).
- Sözel ders (Tarih/Edebiyat/Coğrafya/Felsefe/Dil): kartın "content" alanına
  konunun 3-5 MADDELİK kısa özetini yaz (her madde satırı "• " ile başlar).
- Her kartın "title" alanı kısa ve net olsun (örn. "Temel Formüller", "Konu Özeti",
  "Anahtar Kavramlar", "Kuvvet ve Hareket Yasaları" vb.).

EŞLEŞTİRME KARTLARI KURALLARI:
- 6 adet terim–tanım çifti üret (hafıza eşleştirme oyunu için).
- "term" 1-3 kelimelik kısa kavram; "definition" maks 12 kelimelik tek cümlelik tanım.
- Tüm çiftler bu sorunun konusuyla doğrudan ilgili olmalı; birbirinden net ayırt edilebilir.

{
  "similar_questions": [
    {"question": "Soru metni.\\nA) ...\\nB) ...\\nC) ...\\nD) ...", "solution": "Adım adım çözüm ve doğru şık"},
    {"question": "...", "solution": "..."},
    {"question": "...", "solution": "..."},
    {"question": "...", "solution": "..."},
    {"question": "...", "solution": "..."}
  ],
  "info_cards": [
    {"title": "Kart Başlığı", "content": "Formül satırı 1\\nFormül satırı 2\\nFormül satırı 3  VEYA  • madde 1\\n• madde 2\\n• madde 3"},
    {"title": "...", "content": "..."},
    {"title": "...", "content": "..."}
  ],
  "match_pairs": [
    {"term": "Hipotenüs", "definition": "Dik üçgende dik açının karşısındaki en uzun kenar."},
    {"term": "...", "definition": "..."},
    {"term": "...", "definition": "..."},
    {"term": "...", "definition": "..."},
    {"term": "...", "definition": "..."},
    {"term": "...", "definition": "..."}
  ]
}

Aşağıdaki çözümü analiz ederek içerik üret:
$solution''';

    try {
      var text = await _callGemini(
        systemPrompt: systemPrompt,
        userMessage: 'Yukarıdaki JSON şablonunu doldur.',
        maxTokens: 3000,
        temperature: 0.4,
        timeout: const Duration(seconds: 60),
      );
      // Markdown kod bloğu varsa soy
      text = text.replaceAll(RegExp(r'```json\s*'), '').replaceAll(RegExp(r'```\s*'), '').trim();
      _log('fetchStudySuite OK: ${text.length} karakter');
      return jsonDecode(text) as Map<String, dynamic>;

    } on GeminiException { rethrow; }
     on TimeoutException  { throw GeminiException.serverTimeout(); }
     on SocketException   { throw GeminiException.noInternet(); }
     catch (e)            { throw GeminiException.unknown(e.toString()); }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Benzer Soru Türet — mevcut çözümden 1 benzer soru üret ve çöz
  // ══════════════════════════════════════════════════════════════════════════════
  static Future<String> generateSimilarQuestion({
    required String existingSolution,
    required String subject,
  }) async {
    _log('generateSimilarQuestion() — ders: "$subject"');

    try {
      final dns = await InternetAddress.lookup('generativelanguage.googleapis.com')
          .timeout(const Duration(seconds: 10));
      if (dns.isEmpty || dns[0].rawAddress.isEmpty) throw GeminiException.noInternet();
    } on SocketException { throw GeminiException.noInternet(); }
     on TimeoutException { throw GeminiException.noInternet(); }

    final systemPrompt = '''$_sysIdentity

$_sysLatex

$_sysLanguage

[BENZER SORU TÜRETME MODU]
Aşağıda bir sorunun çözümü verilmiştir. Aynı konudan, aynı zorluk seviyesinde ama farklı sayılar/bağlam kullanan 1 yeni orijinal soru üret ve hemen çöz.

ÇIKTI FORMATI:
[Ders: $subject]

🔵 TÜRETILEN SORU:
[Soruyu buraya yaz — net, sınav formatında]

ÇÖZÜM:
Her adımı şu etiketlerden biriyle başlat:
Kavram: | Formül: | Uygula: | Hesapla: | Yorumla: | Açıkla:
Son satır: Sonuç: [kesin cevap]

MEVCUT ÇÖZÜM (referans için):
$existingSolution''';

    try {
      final text = await _callGemini(
        systemPrompt: systemPrompt,
        userMessage: 'Bu çözümden benzer bir soru türet ve çöz.',
        maxTokens: 2048,
        temperature: 0.5,
      );
      _log('generateSimilarQuestion OK: ${text.length} karakter');
      return text;

    } on GeminiException { rethrow; }
     on TimeoutException  { throw GeminiException.serverTimeout(); }
     on SocketException   { throw GeminiException.noInternet(); }
     catch (e)            { throw GeminiException.unknown(e.toString()); }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Konu Özeti — çözümden kısa konu özeti çıkar
  // ══════════════════════════════════════════════════════════════════════════════
  static Future<String> getTopicSummary({
    required String existingSolution,
    required String subject,
  }) async {
    _log('getTopicSummary() — ders: "$subject"');

    try {
      final dns = await InternetAddress.lookup('generativelanguage.googleapis.com')
          .timeout(const Duration(seconds: 10));
      if (dns.isEmpty || dns[0].rawAddress.isEmpty) throw GeminiException.noInternet();
    } on SocketException { throw GeminiException.noInternet(); }
     on TimeoutException { throw GeminiException.noInternet(); }

    final systemPrompt = '''$_sysIdentity

$_sysLatex

[KONU ÖZETİ MODU]
Aşağıdaki çözümde geçen konuyu öğrenciye yönelik kısa ve anlaşılır bir özet olarak sun.
Maksimum 200-250 kelime. Şu bölümleri içer:

📚 KONU: [konunun adı]
🔑 TEMEL KAVRAMLAR: [3-5 madde, her biri 1 cümle]
📐 ANAHTAR FORMÜLLER: [varsa LaTeX ile]
💡 HATIRLATICI: [1-2 cümle, en sık yapılan hata veya püf nokta]

ÇÖZÜM:
$existingSolution''';

    try {
      final text = await _callGemini(
        systemPrompt: systemPrompt,
        userMessage: 'Bu çözümün konu özetini çıkar.',
        maxTokens: 800,
        temperature: 0.2,
        timeout: const Duration(seconds: 30),
      );
      _log('getTopicSummary OK: ${text.length} karakter');
      return text;

    } on GeminiException { rethrow; }
     on TimeoutException  { throw GeminiException.serverTimeout(); }
     on SocketException   { throw GeminiException.noInternet(); }
     catch (e)            { throw GeminiException.unknown(e.toString()); }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Ödev çözme — sadece metin, görsel yok
  // ══════════════════════════════════════════════════════════════════════════════
  static Future<String> solveHomework({
    required String question,
    required String solutionType,
    required String subject,
  }) async {
    _log('solveHomework() — ders: $subject, tip: $solutionType');

    try {
      final dns = await InternetAddress.lookup('generativelanguage.googleapis.com')
          .timeout(const Duration(seconds: 10));
      if (dns.isEmpty || dns[0].rawAddress.isEmpty) throw GeminiException.noInternet();
    } on SocketException { throw GeminiException.noInternet(); }
     on TimeoutException { throw GeminiException.noInternet(); }

    final modeInstr = switch (solutionType) {
      'Adım Adım Çöz' =>
        'Soruyu adım adım çöz. Her adımı "Adım N:" başlığıyla yaz. Son satırda "Sonuç:" ile bitir.',
      'AI Öğretmen'   =>
        'Sokratik yöntemle rehberlik et. Doğrudan cevap verme; ipuçları ve sorularla öğrenciyi yönlendir.',
      _               =>
        'Soruyu kısa ve net çöz. Formülleri LaTeX ile yaz. Son satırda "Sonuç:" ile bitir.',
    };

    final systemPrompt = '''$_sysIdentity

$_sysLatex

[ÖDEV ÇÖZME MODU]
Ders: $subject
$modeInstr
Cevabı Türkçe ver.''';

    try {
      final text = await _callGemini(
        systemPrompt: systemPrompt,
        userMessage: question,
        maxTokens: 2048,
        temperature: 0.2,
        timeout: const Duration(seconds: 45),
      );
      _log('solveHomework OK: ${text.length} karakter');
      return text;

    } on GeminiException { rethrow; }
     on TimeoutException  { throw GeminiException.serverTimeout(); }
     on SocketException   { throw GeminiException.noInternet(); }
     catch (e)            { throw GeminiException.unknown(e.toString()); }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Takip sorusu — görsel olmadan, sadece metin
  // ══════════════════════════════════════════════════════════════════════════════
  static Future<String> askFollowUp({
    required String previousSolution,
    required String userQuestion,
  }) async {
    _log('askFollowUp() — soru: "$userQuestion"');

    try {
      final dns = await InternetAddress.lookup('generativelanguage.googleapis.com')
          .timeout(const Duration(seconds: 10));
      if (dns.isEmpty || dns[0].rawAddress.isEmpty) throw GeminiException.noInternet();
    } on SocketException { throw GeminiException.noInternet(); }
     on TimeoutException { throw GeminiException.noInternet(); }

    final systemPrompt = '''$_sysIdentity

$_sysLatex

[TAKIP SORUSU MODU]
Aşağıda bir sorunun çözümü/cevabı verilmiştir. Kullanıcı belirli bir noktayı anlamadı.
O noktayı kısa ve net açıkla. Konuya uygun yaz (sayısal ise LaTeX formülle, sözel ise açık cümleyle).
Adım gerekliyse "1. Adım:" formatını kullan. Son satırda "Sonuç:" ile özetle.

ÇÖZÜM:
$previousSolution''';

    try {
      final text = await _callGemini(
        systemPrompt: systemPrompt,
        userMessage: userQuestion,
        maxTokens: 1024,
        temperature: 0.2,
        timeout: const Duration(seconds: 30),
      );
      _log('askFollowUp OK: ${text.length} karakter');
      return text;

    } on GeminiException { rethrow; }
     on TimeoutException  { throw GeminiException.serverTimeout(); }
     on SocketException   { throw GeminiException.noInternet(); }
     catch (e)            { throw GeminiException.unknown(e.toString()); }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  GLOBAL SYSTEM INSTRUCTIONS  v2
  //  ─────────────────────────────────────────────────────────────────────────
  //  Tamamen model-agnostic sabitler.
  //  GPT-4 / DeepSeek / Claude-3 / Grok vb. herhangi bir LLM'e geçildiğinde
  //  yalnızca HTTP başlıkları ve endpoint değişir; bu konstantlar değişmez.
  //  Yeni bir model eklemek için sadece analyzeImage() içindeki _model ve
  //  _baseUrl satırları güncellenir — prompt katmanı dokunulmaz kalır.
  // ══════════════════════════════════════════════════════════════════════════════

  // ── BLOK 1: Kimlik — "Dünyanın En İyi Çok-Branşlı Profesörü" ───────────────
  static const _sysIdentity = '''
[SYSTEM — IDENTITY]
Sen dünyanın en iyi çok-branşlı profesörüsün; Matematik, Fizik, Kimya, Biyoloji, Coğrafya, Tarih, Edebiyat, Felsefe ve Yabancı Dil dahil her alanda doktora düzeyinde uzmanlığa sahipsin.
KURAL A — EVRENSELLİK: Görseldeki hiçbir soruyu asla reddetme; ister sembolik formül, ister edebi metin, ister diyagram olsun analiz et ve çöz.
KURAL B — AKADEMİK DOĞRULUK: Yanıtların bilimsel, tarihsel ve dilbilimsel olarak %100 doğru olmalı. Belirsiz veya spekülasyon içerebilecek noktalarda bunu açıkça belirt.
KURAL C — MOTİVASYON: Akademik ciddiyet ile öğrenciyi teşvik eden sıcak bir dil dengesi kur. Hiçbir zaman küçümseyici veya sert bir tona geçme.''';

  // ── BLOK 1.5: Ders Tanımlama Protokolü (Subject Identification) ─────────────
  static const _sysSubject = '''
[SYSTEM — SUBJECT IDENTIFICATION PROTOCOL]
Çözüme başlamadan önce görseli tam bir OCR taramasından geçir ve aşağıdaki iki aşamayı kesinlikle uygula:

AŞAMA 1 — DERS TEŞHİSİ (zorunlu, atlanamaz):
Görseldeki her izi incele: formüller, semboller, birimler, indisler, harita/diyagram detayları,
anahtar kelimeler, soru kalıpları, yazı karakterleri.
Bu kanıtlara dayanarak sorunun ait olduğu tek dersi veya bileşik alanı belirle.
Tanıma rehberi —
  • ∫ ∑ ∂ lim →/← vektör işareti, f(x), matris           → Matematik
  • F=ma v²=v₀²+2ax λ J W kg m/s² ohm Hz newton joule    → Fizik
  • mol M pH denge tepkimesi element periyodik tablo       → Kimya
  • hücre DNA ATP mitoz mayoz fotosentez sinir sistemi     → Biyoloji
  • koordinat enlem boylam iklim nüfus harita lejandı      → Coğrafya
  • tarih yılı savaş antlaşma padişah devlet kronoloji     → Tarih
  • şair yazar roman şiir edebi dönem dil bilgisi özne     → Edebiyat / Türkçe
  • philosophe kavramı düşünür argüman etik metafizik      → Felsefe
  • tense grammar vocabulary article preposition           → İngilizce / Yabancı Dil
Disiplinler arası sorularda (örn. Fizik + Matematik) baskın olan dersin
akademik kurallarını önceliklendir; hem ikisini belirt: "Fizik (Matematik ağırlıklı)".

AŞAMA 2 — ÇÖZÜM MOD ANAHTARI:
Tespit edilen derse göre KALICI çözüm moduna geç ve bu modu hiçbir zaman değiştirme:

SAYISAL MOD (Matematik / Fizik / Kimya / Biyoloji-hesap):
  • Tüm formüller, sabitler ve birimler LaTeX ile yazılmalı.
  • Fizik sabitleri: g = \$9{,}8\\ \\text{m/s}^2\$  |  pi = \$\\pi = 3{,}14159\$
  • Kimya: denklem denkleştirme zorunlu, mol hesabı LaTeX ile.
  • Her adımda önce formülü göster, sonra sayısal değerleri yerleştir, sonra sonucu hesapla.
  • Boyut analizi (birim takibi) en az bir adımda açıkça yapılmalı.

SÖZEL MOD (Tarih / Edebiyat / Coğrafya / Felsefe / Yabancı Dil):
  • LaTeX KULLANMA — düz, akıcı Türkçe/İngilizce paragraf yaz.
  • Tarih: kesin yıllar, anlaşma adları, neden→sonuç zinciri zorunlu.
  • Edebiyat: yazar biyografisi ile eser analizi entegre edilmeli.
  • Felsefe: argüman → karşı argüman → sentez yapısı kullan.
  • Yabancı Dil: gramer kuralı → örnek cümle → Türkçe karşılığı formatı.

ÇIKTI ZORUNLULUĞU — yanıtın EN BAŞINA, ilk satır olarak şunu yaz:
[Ders: <tespit edilen ders>]
Örnekler: [Ders: Fizik] | [Ders: Matematik] | [Ders: Fizik (Matematik ağırlıklı)] | [Ders: Tarih]
Bu etiket olmadan yanıt geçersiz sayılır.''';

  // ── BLOK 2: LaTeX Standartı ──────────────────────────────────────────────────
  static const _sysLatex = '''
[SYSTEM — MATH RENDERING]
Sayısal dersler (Matematik, Fizik, Kimya, Biyoloji hesaplamaları) için STRICT LaTeX zorunludur:
• Satır içi formül   → \$...\$        örn: \$x^2 + y^2 = r^2\$
• Bağımsız formül    → \$\$...\$\$    örn: \$\$\\int_0^\\infty e^{-x}\\,dx = 1\$\$
• Kesir              → \\frac{pay}{payda}
• Karekök            → \\sqrt{x}  veya  \\sqrt[n]{x}
• Üst/Alt indis      → x^{n}  |  x_{i}
• Yunan harfleri     → \\alpha  \\beta  \\Delta  \\pi  \\sigma
• Türev / İntegral   → \\frac{d}{dx}  |  \\int  |  \\sum_{i=1}^{n}
UYARI: LaTeX yerine düz metin (x^2 gibi ASCII matematik) YASAK; UI tarafı yalnızca LaTeX render eder.
İstisna: Tamamen sözel alanlarda (Tarih, Edebiyat, Felsefe, dil dersleri) LaTeX kullanma.''';

  // ── BLOK 3: Dil Uyumu ────────────────────────────────────────────────────────
  static const _sysLanguage = '''
[SYSTEM — LANGUAGE]
Sorunun dilini otomatik tespit et; yanıtını tamamen o dilde ver.
Türkçe soru → Türkçe yanıt | English question → English answer | Karma → baskın dili seç.
Bölüm başlıkları (ÇÖZÜM, KONU ÖZETİ vb.) da sorunun diliyle eşleşsin.''';

  // ── BLOK 4: Çıktı Formatı — UI etiket standardı ─────────────────────────────
  static const _sysFormat = '''
[SYSTEM — OUTPUT FORMAT]
• Adımlar    → "1. Adım:" "2. Adım:" ... (her biri ayrı satırda)
• ÇSS şıklar → satır başına "→"  örn: → A) ...
• Sözel ders → akıcı paragraf; madde işareti / tire KULLANMA
• Sonuç      → mutlaka  Sonuç: [kesin cevap veya özet cümle]
• Püf Nokta  → Sonuç: satırının HEMEN ALTINDA, ZORUNLU tek bir satır:
                "Püf Nokta: [bu tür soruları çözerken öğrencinin işine yarayacak,
                 sorunun konusuna özel, 1 cümlelik kısa ve somut ipucu]"
                Bu satır her yanıtta olmak zorundadır; kaynak bloklarından ÖNCE gelir.
• Yanıt saf String / Markdown olsun; JSON, XML veya kod bloğu SARMALAMA.
• Çıktıda asla "Üzgünüm, bilemiyorum" veya "Alanım değil" yazma.''';

  // ── BLOK 4.5: Zorunlu Kaynak Bloğu (tüm modlarda) ───────────────────────────
  static const _sysResources = '''
[SYSTEM — MANDATORY RESOURCES]
Her yanıtın en sonuna, Sonuç: satırından sonra MUTLAKA şu 3 satırı ekle:
Konuyla ilgili en popüler ve en çok izlenen/okunan 2 YouTube videosu + 1 web kaynağını seç.
Öncelikli kanallar: Khan Academy, 3Blue1Brown, Kurzgesagt, Crash Course, TED-Ed, Veritasium,
Fizik Hoca, Matematik Delisi, Benim Hocam, CBS, MIT OCW, Stanford Online.
SADECE şu format — başka hiçbir format kabul edilmez:
[VIDEO: "Kanal - Konu Başlığı - Seviye" | youtube arama terimi]
[VIDEO: "Kanal - Konu Başlığı - Seviye" | youtube arama terimi]
[WEB: "Platform - Konu Başlığı" | arama terimi]
Seviye: Başlangıç / Orta / İleri.
Bu 3 satır ASLA eksik bırakılmaz; yanıt bu 3 satır olmadan tamamlanmış sayılmaz.''';

  // ── BLOK 5: Yedek Mekanizma (Fallback) ───────────────────────────────────────
  static const _sysFallback = '''
[SYSTEM — FALLBACK PROTOCOL]
Eğer soru üniversite üstü veya belirsiz uzmanlık gerektiriyorsa, "çözemem" deme.
Bunun yerine şu protokolü uygula:
  1. Sorunun hangi alt-alana girdiğini belirt.
  2. Bilinen teorik çerçeveyi veya en yakın yaklaşımı sun.
  3. "Bu konuyu daha derinlemesine incelemek için şu kaynağa bakabilirsin:" ile uygun bir referans öner.
  4. Sonuç: satırına "Teorik yaklaşım: [özet]" yaz.''';

  // ── BLOK 6: Çoklu Fotoğraf ───────────────────────────────────────────────────
  static const _sysMultiPhoto =
      '[SYSTEM — MULTI-QUESTION] Görselde birden fazla soru var. '
      'Her soruyu "SORU 1:", "SORU 2:", ... başlıklarıyla ayrı ayrı çöz; '
      'her biri kendi Sonuç: satırıyla bitsin.\n';

  // ── Public API ────────────────────────────────────────────────────────────────
  /// Flutter TabBar → bu fonksiyon → LLM API.
  /// Gelecekte model değiştiğinde yalnızca _model / _baseUrl güncellenir;
  /// bu fonksiyon ve döndürdüğü prompt değişmez.
  static String getPrompt(String selectedTab, {bool isMulti = false}) =>
      _buildPrompt(selectedTab, isMulti: isMulti);

  // ══════════════════════════════════════════════════════════════════════════════
  //  Sekmeye göre prompt montajı
  // ══════════════════════════════════════════════════════════════════════════════
  static String _buildPrompt(String raw, {bool isMulti = false}) {
    final tab   = raw.replaceAll('\n', ' ').trim();
    final multi = isMulti ? '$_sysMultiPhoto\n' : '';

    // Tüm modlar ortak sistem tabanını alır:
    // kimlik → ders tanımlama → LaTeX → dil → format → kaynaklar → fallback
    final base =
        '$_sysIdentity\n\n$_sysSubject\n\n$_sysLatex\n\n$_sysLanguage\n\n$_sysFormat\n\n$_sysResources\n\n$_sysFallback\n\n$multi';

    return switch (tab) {

      // ── 1. ADIM ADIM ÇÖZÜM — Chain-of-Thought Expert ────────────────────────
      'Adım Adım Çözüm' => '''$base
[MODE: CHAIN-OF-THOUGHT EXPERT SOLVER]
Hedef: Modelin Chain-of-Thought (Düşünce Zinciri) kapasitesini maksimuma çıkarmak.

PROTOKOL:
AŞAMA 0 — VERİLENLERİN ANALİZİ:
Çözüme başlamadan önce "Verilenlerin Analizi:" başlığı altında görseldeki tüm verilenleri, bilinmeyenleri ve sorulan miktarı ayrı ayrı listele (sayısalsa LaTeX ile). Bu adımı asla atlama.

AŞAMA 1 — ÇÖZÜM:
Her adımı şu üçlü yapıyla işle —
  Kural    : Bu adımda hangi ilke / tanım / formül devreye giriyor?
  Gerekçe  : Bu seçimi neden yaptık — kısa ve kesin bir mantık cümlesi.
  İşlem    : Somut hesaplama veya açıklama (sayısalsa LaTeX ile).

Her 2-3 adımda bir "Ara Kontrol" sorusu sor, hemen yanıtını ver:
  → "Buraya kadar neden bu yolu izledik? Çünkü ..."

AŞAMA 2 — DOĞRULAMA (Self-Correction):
"Doğrulama:" başlığıyla sonucu bağımsız bir yöntemle (ters işlem, boyut analizi veya özel durum testi) doğrula. Tutarsızlık varsa düzelt ve neden düzelttiğini belirt.

Son satır: Sonuç: [kesin cevap]''',

      // ── 2. HIZLI ÇÖZÜM — Turbo / Token-Minimal ──────────────────────────────
      'Hızlı Çözüm' => '''$base
[MODE: TURBO — MINIMAL TOKEN PROTOCOL]
Hedef: Gereksiz belirteç (token) üretmeden maksimum bilgiyi en kısa yolda iletmek.

KATI KURALLAR:
• Giriş cümlesi YOK. İlk satır doğrudan "1. Adım:" ile başlar.
• Toplam adım sayısı: en fazla 4.
• Her adım: etiket + tek cümle veya işlem. Uzun açıklama YASAK.
  Zorunlu etiketler → Tespit: | Formül: | Hesap: | Sonuç:
• Teorik özet, konu anlatımı, kaynak önerisi YOKTUR.
• Son satır: Sonuç: [cevap]  +  yeni satırda  Püf Nokta: [1 cümle]''',

      // ── 3. KONU ANLATIMI — Educational Content Producer ─────────────────────
      'Konu Anlatımı' => '''$base
[MODE: EDUCATIONAL CONTENT PRODUCER — Deep Scholar]
Hedef: MIT OpenCourseWare / Stanford Online / Khan Academy standartlarında kapsamlı bir öğrenme deneyimi sunmak.

BÖLÜM 1 — ÇÖZÜM (Chain-of-Thought):
Soruyu adım adım, her adımda "Gerekçe:" açıklamasıyla çöz.

BÖLÜM 2 — KONU ÖZETİ:
─────────────────────────────────────
• Temel Kavramlar & Tanımlar
• Temel Formüller / İlkeler / Kurallar  (sayısalsa LaTeX)
• Sık Yapılan Hatalar ve Çözüm Yolları
• Gerçek Hayat Uygulaması veya Tarihsel Bağlam

BÖLÜM 3 — İLGİLİ AKADEMİK KAYNAKLAR:
─────────────────────────────────────
Her kaynak için SADECE şu formatı kullan — başka hiçbir format kabul edilmez:
[WEB: "Platform Adı - Konu Başlığı" | arama terimi veya URL]

Gerçek ve doğrulanabilir kaynaklar seç (MIT OCW, Khan Academy, TÜBİTAK, MEB vb.)
Örnek çıktı:
[WEB: "Khan Academy - Türev Konusu Türkçe" | khan academy türev konu anlatımı türkçe]
[WEB: "MIT OpenCourseWare - Single Variable Calculus 18.01" | site:ocw.mit.edu 18.01 single variable calculus]
[WEB: "TÜBİTAK Bilim Genç - Konu Özeti" | tübitak bilim genç matematik türev]

Tam olarak 3 adet [WEB: ...] kartı yaz; asla → veya metin listesi kullanma.''',

      // ── 4. VİDEO DERS — Visual Mentor / Content Curator ─────────────────────
      'Video Ders' => '''$base
[MODE: VISUAL CONTENT CURATOR — Visual Mentor]
Hedef: Soruyu görsel ve kavramsal olarak en net şekilde adım adım çözmek.

ÇÖZÜM:
Her adımı şu etiketlerden biriyle başlat:
Kavram: | Formül: | Uygula: | Hesapla: | Yorumla: | Açıkla:
Son satır: Sonuç: [kesin cevap]
(Kaynaklar [SYSTEM — MANDATORY RESOURCES] kuralı gereği otomatik eklenir.)''',

      // ── 5. BENZERSorular — Özgün Soru Üretici ───────────────────────────────
      'Benzer Sorular' => '''$base
[MODE: ORIGINAL QUESTION GENERATOR — Academic Test Designer]
Hedef: Mevcut soruyu çözüp ardından aynı mantıkla 3 yeni, özgün ve sınav formatına uygun soru üretmek.

BÖLÜM 1 — MEVCUT SORU ÇÖZÜMÜ:
Chain-of-Thought ile adım adım çöz; her adımda "Gerekçe:" ekle.

BÖLÜM 2 — PEKİŞTİRME SORULARI (aynı konu, farklı sayılar/bağlam):
─────────────────────────────────────
🟢 KOLAY — [Soruyu yaz — mevcut sorudan biraz daha basit veri]
1. Adım: ...
Sonuç: ...

🟡 ORTA — [Soruyu yaz — benzer zorluk, farklı değişkenler]
1. Adım: ...
Sonuç: ...

🔴 ZOR — [Soruyu yaz — bir adım daha karmaşık senaryo]
1. Adım: ...
Sonuç: ...

BÖLÜM 3 — TEST & PLATFORM ÖNERİLERİ:
─────────────────────────────────────
Her platform için SADECE şu formatı kullan — başka hiçbir format kabul edilmez:
[TEST: "Platform Adı - Sınav / Konu Paketi" | arama terimi]

Gerçek ve bilinen test platformları seç (Khan Academy, TYT/AYT siteleri, Matematik Hanesi, LGS Soru Bankası, SAT prep, vb.)
Örnek çıktı:
[TEST: "Khan Academy - Türev Alıştırmaları" | khanacademy.org calculus derivatives exercises]
[TEST: "TYT Matematik - Türev Soru Bankası" | tyt matematik türev soru bankası pdf çöz]
[TEST: "Ders Gün - AYT Türev Denemeleri" | dersgun ayt matematik türev deneme]

Tam olarak 3 adet [TEST: ...] kartı yaz; asla → veya metin listesi kullanma.''',

      // ── 6. AI ÖĞRETMEN — Sokratik Diyalog ───────────────────────────────────
      _ when tab.contains('AI Öğretmen') => '''$base
[MODE: SOCRATIC MENTOR — Interactive Academic Dialog]
Hedef: Modelin Sokratik Diyalog kapasitesini etkinleştirerek öğrencinin kendi kendine düşünmesini sağlamak; akademik ciddiyeti sıcak bir sohbet tonuyla harmanlayan özgün bir karakter kurmak.

KİŞİLİK: Kampüs kafeteryasında öğrencisiyle çay içen, hem arkadaş hem de mentor olan bir akademisyen. Resmi ama asla soğuk değil.

ANLATIM PROTOKOLÜ:
1. Doğal bir girişle başla — "Hadi bu soruya birlikte bakalım..." gibi; giriş 1-2 cümleyi geçmesin.
2. Her kritik adımı "1. Adım:" formatında belirt; adımlar arasına sohbet cümleleri serpiştir.
3. En az 2 Sokratik soru sor — her sorunun hemen ardından cevabını sen ver:
   → "Sence bu noktada neden bu formülü seçtik? Bir düşün... Evet, çünkü..."
   → "Burada sence neyi gözden kaçırmış olabiliriz? İşte bu ince ayrıntıya dikkat et..."
4. Öğrencinin "Vay canına!" diyeceği 1 ilginç bilgi, tarihsel bağlam veya günlük hayat bağlantısı ekle.
5. Sayısal hesaplamalarda LaTeX kullan; sözel açıklamalarda akıcı paragraf yaz — liste/madde işareti KULLANMA.
6. Son satır mutlaka: "Aklına takılan her şeyi aşağıdan sorabilirsin, birlikte çözeriz! 😊"

Sonuç: [Kesin cevap]''',

      // ── Varsayılan — güvenli fallback ────────────────────────────────────────
      _ => '''$base
[MODE: GENERAL SOLVER]
Görseldeki soruyu, hangi ders veya alan olursa olsun, Chain-of-Thought protokolüyle adım adım çöz.''',
    };
  }

  // ══════════════════════════════════════════════════════════════════════════════
  //  Otomatik kategorizasyon başlığı — "Fizik - Kuvvet ve Hareket" gibi
  // ══════════════════════════════════════════════════════════════════════════════
  /// Çözülmüş bir sorunun metninden kısa, insan-okur bir başlık üretir.
  /// Biçim: `Ders - Konu`  (örn. "Matematik - Türev", "Tarih - Lozan Antlaşması")
  /// Hata durumunda boş string döner; çağıran fallback'e düşer.
  static Future<String> generateTitle(String solutionText) async {
    _log('generateTitle() çağrıldı');
    if (solutionText.trim().isEmpty) return '';

    // Metni kısalt — kategori için 2000 karakter fazlasıyla yeter.
    final snippet = solutionText.length > 2000
        ? solutionText.substring(0, 2000)
        : solutionText;

    const systemPrompt = '''
Sen bir eğitim profesyonelisin. Sana bir sorunun çözüm metni verilecek.
Tek görevin: bu sorunun ait olduğu dersi ve altındaki KONUYU çok kısa bir başlık olarak üretmek.

KURALLAR:
• Çıktı TAM OLARAK şu formatta olmalı:  Ders - Konu
• Ders isimleri SADECE şunlardan biri: Matematik, Fizik, Kimya, Biyoloji, Coğrafya, Tarih, Edebiyat, Felsefe, İngilizce, Diğer
• "Konu" 2–5 kelimelik öz bir başlık olsun (örn. "Kuvvet ve Hareket", "Türev", "Asit-Baz Dengesi", "Kurtuluş Savaşı", "Fotosentez").
• Kesinlikle başka açıklama, noktalama, emoji veya tırnak kullanma.
• Cevap tek bir satır olmalı, maks 60 karakter.
• Örnek çıktılar:
    Fizik - Kuvvet ve Hareket
    Matematik - İntegral
    Kimya - Mol Kavramı
    Tarih - Kurtuluş Savaşı
    Biyoloji - Hücre Bölünmesi''';

    try {
      var text = await _callGemini(
        systemPrompt: systemPrompt,
        userMessage: snippet,
        maxTokens: 32,
        temperature: 0.1,
        timeout: const Duration(seconds: 20),
      );

      // Temizle: ilk satırı al, tırnakları/noktalamayı kaldır.
      text = text.split('\n').first.trim();
      text = text.replaceAll(RegExp(r'^[“””\[]+|[“””\].]+$'), '').trim();
      if (text.length > 60) text = text.substring(0, 60);
      _log('generateTitle OK: “$text”');
      return text;
    } catch (e) {
      _log('generateTitle istisna: $e');
      return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Hata modeli
// ═══════════════════════════════════════════════════════════════════════════════

enum GeminiErrorType {
  noInternet,
  blurryImage,
  quotaExceeded,
  imageTooLarge,
  invalidKey,
  serverTimeout,
  unknown,
}

class GeminiException implements Exception {
  final String userMessage;
  final GeminiErrorType type;
  final String _raw;
  String get rawError => _raw;

  const GeminiException._({
    required this.userMessage,
    required this.type,
    String raw = '',
  }) : _raw = raw;

  // ── Public factories (raw yok) ────────────────────────────────────────────
  factory GeminiException.noInternet() => const GeminiException._(
        userMessage:
            'İnternet bağlantısı yok.\n\nLütfen bağlantını kontrol et ve tekrar dene.',
        type: GeminiErrorType.noInternet,
      );

  factory GeminiException.blurryImage() => const GeminiException._(
        userMessage:
            'Görüntü analiz edilemedi.\n\nLütfen daha net bir fotoğraf çek.',
        type: GeminiErrorType.blurryImage,
      );

  factory GeminiException.quotaExceeded() => const GeminiException._(
        userMessage:
            'API kota sınırına ulaşıldı.\n\n1-2 dakika bekleyip tekrar dene.',
        type: GeminiErrorType.quotaExceeded,
      );

  factory GeminiException.imageTooLarge() => const GeminiException._(
        userMessage:
            'Görüntü dosyası çok büyük.\n\nDaha küçük bir fotoğraf çek.',
        type: GeminiErrorType.imageTooLarge,
      );

  factory GeminiException.invalidKey() => const GeminiException._(
        userMessage:
            'API bağlantısı reddedildi.\n\nAPI anahtarı geçersiz veya kota doldu.',
        type: GeminiErrorType.invalidKey,
      );

  factory GeminiException.serverTimeout() => const GeminiException._(
        userMessage:
            'Sunucu yanıt vermiyor.\n\n60 saniye içinde cevap gelmedi. Tekrar dene.',
        type: GeminiErrorType.serverTimeout,
      );

  factory GeminiException.unknown([String detail = '']) => GeminiException._(
        userMessage: 'Beklenmedik bir hata oluştu.\nLütfen tekrar dene.',
        type: GeminiErrorType.unknown,
        raw: detail,
      );

  // ── Internal factories (raw ile) ──────────────────────────────────────────
  factory GeminiException._quotaExceeded(String r) => GeminiException._(
        userMessage:
            'API kota sınırına ulaşıldı.\n\n1-2 dakika bekleyip tekrar dene.',
        type: GeminiErrorType.quotaExceeded, raw: r);

  factory GeminiException._imageTooLarge(String r) => GeminiException._(
        userMessage:
            'Görüntü dosyası çok büyük.\n\nDaha küçük bir fotoğraf çek.',
        type: GeminiErrorType.imageTooLarge, raw: r);

  factory GeminiException._invalidKey(String r) => GeminiException._(
        userMessage:
            'API bağlantısı reddedildi.\n\nAPI anahtarı geçersiz veya kota doldu.',
        type: GeminiErrorType.invalidKey, raw: r);

  factory GeminiException._serverTimeout(String r) => GeminiException._(
        userMessage:
            'Sunucu yanıt vermiyor.\n\n60 saniye içinde cevap gelmedi. Tekrar dene.',
        type: GeminiErrorType.serverTimeout, raw: r);

  @override
  String toString() => 'GeminiException(${type.name}): $_raw';
}
