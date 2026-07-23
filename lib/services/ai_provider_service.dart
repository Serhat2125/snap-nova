import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'error_logger.dart';
import 'parent_preview.dart';

/// ════════════════════════════════════════════════════════════════════════
///  AiProviderService — Çoklu AI sağlayıcı (ChatGPT/OpenAI, Grok/xAI,
///  Claude/Anthropic, DeepSeek, Gemini) için tek giriş noktası.
///
///  Tüm çağrılar Firebase Cloud Function `aiProxy` üzerinden gider; sağlayıcı
///  anahtarları sunucuda (Secret Manager) tutulur, APK'ya gömülmez. İstemci
///  yalnızca Firebase Auth ID token ile çağırır.
///
///  Backend: functions/src/ai_proxy.ts
/// ════════════════════════════════════════════════════════════════════════

enum AiProvider { gemini, openai, claude, grok, deepseek }

class AiModel {
  final String id;
  final String label;
  const AiModel(this.id, this.label);
}

class AiProviderInfo {
  final AiProvider provider;
  final String wireName; // proxy'ye gönderilen "provider" değeri
  final String label; // UI'da görünen ad
  final String emoji;
  final List<AiModel> models; // ilk eleman varsayılan
  const AiProviderInfo(this.provider, this.wireName, this.label, this.emoji, this.models);

  AiModel get defaultModel => models.first;
}

/// Sağlayıcı ve model kataloğu.
/// MALİYET KURALI: her sağlayıcının İLK modeli = en ucuz (varsayılan).
/// Daha güçlü/pahalı seçenekler sonraki sıralarda. Yeni model: buraya ekle.
const List<AiProviderInfo> kAiProviders = [
  AiProviderInfo(AiProvider.gemini, 'gemini', 'Gemini', '✨', [
    // NOT: flash-lite Google tarafında sık sık 503 (high demand) + ~6sn
    // gecikme veriyordu; etkileşimli varsayılan flash'a alındı (~0.8sn, kararlı).
    // flash-lite hâlâ seçilebilir + arka plan batch işlerinde kullanılır.
    AiModel('gemini-2.5-flash', 'Gemini 2.5 Flash · hızlı'),
    AiModel('gemini-2.5-flash-lite', 'Gemini 2.5 Flash-Lite · en ucuz'),
  ]),
  AiProviderInfo(AiProvider.openai, 'openai', 'ChatGPT', '🟢', [
    AiModel('gpt-4o-mini', 'GPT-4o mini · en ucuz'),
    AiModel('gpt-4o', 'GPT-4o · pahalı'),
  ]),
  AiProviderInfo(AiProvider.claude, 'claude', 'Claude', '🟣', [
    AiModel('claude-haiku-4-5', 'Claude Haiku 4.5 · en ucuz'),
    AiModel('claude-sonnet-4-6', 'Claude Sonnet 4.6 · pahalı'),
  ]),
  AiProviderInfo(AiProvider.grok, 'grok', 'Grok', '⚡', [
    AiModel('grok-3-mini', 'Grok 3 mini · en ucuz'),
    AiModel('grok-3', 'Grok 3 · pahalı'),
  ]),
  AiProviderInfo(AiProvider.deepseek, 'deepseek', 'DeepSeek', '🐋', [
    AiModel('deepseek-chat', 'DeepSeek Chat · en ucuz'),
    AiModel('deepseek-reasoner', 'DeepSeek Reasoner · pahalı'),
  ]),
];

AiProviderInfo aiProviderInfo(AiProvider p) =>
    kAiProviders.firstWhere((e) => e.provider == p);

/// Uygulamadaki AI görev türleri. Her görev için kalite/maliyet dengesi ayrı.
enum AiTask {
  photoSolve, // fotoğraflı soru çözme — en güçlü vision (tüm sağlayıcılar)
  homeworkSolve, // metin tabanlı çözüm — yüksek doğruluk
  coach, // AI koç sohbet — Gemini + ChatGPT failover
  voice, // sesli mod — hız öncelikli
  cameraLive, // canlı kamera — Gemini + ChatGPT
  summary, // özet üretimi — KALİTELİ
  examGen, // sınav/soru üretimi — KALİTELİ
  factual, // formül/coğrafya gibi doğruluk-hassas üretim — orta seviye
  cheap, // başlık, sınıflandırma, konu adı vb. — en ucuz
}

class AiHop {
  final AiProvider provider;
  final String model;
  const AiHop(this.provider, this.model);
}

class AiTaskConfig {
  final List<AiHop> hops; // sıralı failover
  final int maxTokens;
  final int perProviderTimeoutMs;
  const AiTaskConfig(this.hops, {this.maxTokens = 2048, this.perProviderTimeoutMs = 8000});
}

/// Günlük ücretsiz soru limiti.
const int kFreeQuotaPerDay = 3;

// ── ORTAK FAILOVER ZİNCİRLERİ ───────────────────────────────────────────────
// Kullanıcı isteği (2026-06):
//   • Fotoğraflı çözüm: (kullanıcının seçtiği model) → Gemini → OpenAI → Grok
//   • Diğer TÜM AI çağrıları: Gemini → OpenAI → DeepSeek → Grok → Claude
//     (Claude pahalı olduğu için her zaman en son yedek.)
//
// Fotoğraf zincirinin başına kullanıcı seçimi chatTask(useSelectedFirst:true)
// ile eklenir; aşağıdaki listeler seçim sonrası gelen sıralamadır.

// Sohbet/metin (hız öncelikli) — ücretsiz.
const List<AiHop> _hopsChatFree = [
  AiHop(AiProvider.gemini, 'gemini-2.5-flash'),
  AiHop(AiProvider.openai, 'gpt-4o-mini'),
  AiHop(AiProvider.deepseek, 'deepseek-chat'),
  AiHop(AiProvider.grok, 'grok-3-mini'),
  AiHop(AiProvider.claude, 'claude-sonnet-4-6'),
];
// Sayısal/çözüm (muhakeme öncelikli) — ücretsiz.
const List<AiHop> _hopsSolveFree = [
  AiHop(AiProvider.gemini, 'gemini-2.5-flash'),
  AiHop(AiProvider.openai, 'gpt-4o-mini'),
  // Failover'da deepseek-chat (hızlı); reasoner/R1 20-60sn sürüp timeout'a
  // takılıyordu → boşa bekleme. Kullanıcı isterse picker'dan reasoner seçebilir.
  AiHop(AiProvider.deepseek, 'deepseek-chat'),
  AiHop(AiProvider.grok, 'grok-3'),
  AiHop(AiProvider.claude, 'claude-sonnet-4-6'),
];
// Fotoğraflı çözüm (vision) — ücretsiz. Seçili model en başa eklenir.
const List<AiHop> _hopsPhotoFree = [
  AiHop(AiProvider.gemini, 'gemini-2.5-flash'),
  AiHop(AiProvider.openai, 'gpt-4o-mini'),
  // grok-2-vision-1212 xAI'da kaldırıldı ("Model not found"); grok-4.3
  // multimodal (text+vision) güncel model. Canlı testte görseli okuyup çözdü.
  AiHop(AiProvider.grok, 'grok-4.3'),
];
// Konu pekiştirme / özet (Study Suite) — kullanıcı isteği (2026-07-21):
// "Gemini kredisi yoksa ya da geç geliyorsa önce ChatGPT, sonra Grok, en sonda
// DeepSeek devreye girsin; kullanıcıyı bekletmesin."
// Claude bu zincirden çıkarıldı (pahalı ve en yavaş hop).
const List<AiHop> _hopsStudySuite = [
  AiHop(AiProvider.gemini, 'gemini-2.5-flash'),
  AiHop(AiProvider.openai, 'gpt-4o-mini'),
  AiHop(AiProvider.grok, 'grok-3-mini'),
  AiHop(AiProvider.deepseek, 'deepseek-chat'),
];

// Sınav/soru üretimi (test oluştur) — KISA zincir: Gemini → ChatGPT → Grok.
// Kullanıcı talebi: "Gemini cevap vermediğinde ChatGPT, o da vermezse Grok".
// DeepSeek/Claude kasıtlı olarak çıkarıldı (yavaşlık + maliyet).
const List<AiHop> _hopsExamGen = [
  AiHop(AiProvider.gemini, 'gemini-2.5-flash'),
  AiHop(AiProvider.openai, 'gpt-4o-mini'),
  AiHop(AiProvider.grok, 'grok-3-mini'),
];

// ── ÜCRETSİZ kullanıcı task config ──────────────────────────────────────────
const Map<AiTask, AiTaskConfig> kAiTaskConfigFree = {
  AiTask.photoSolve:
      AiTaskConfig(_hopsPhotoFree, maxTokens: 2048, perProviderTimeoutMs: 12000),
  AiTask.homeworkSolve:
      AiTaskConfig(_hopsSolveFree, maxTokens: 2048, perProviderTimeoutMs: 10000),
  AiTask.coach:
      AiTaskConfig(_hopsChatFree, maxTokens: 1536, perProviderTimeoutMs: 8000),
  AiTask.voice:
      AiTaskConfig(_hopsChatFree, maxTokens: 1024, perProviderTimeoutMs: 6000),
  AiTask.cameraLive:
      AiTaskConfig(_hopsChatFree, maxTokens: 1536, perProviderTimeoutMs: 8000),
  // Konu pekiştirme: istenen sıra (Gemini → ChatGPT → Grok → DeepSeek).
  // DİKKAT: Bu görev 5 soru + 3 kart + 6 çift içeren BÜYÜK bir JSON üretir;
  // hiçbir sağlayıcı bunu 7 sn'de bitiremez. 7000 ms'lik eski değer 4 hop'un
  // TAMAMINI iptal ettirip zinciri her seferinde boşa düşürüyordu (Gemini
  // kredisi bitince kullanıcı direkt 429 hatası görüyordu). Kredisi biten
  // sağlayıcı zaten <1 sn'de hata dönüp sıradakine geçer; bu süre yalnızca
  // gerçekten üretim yapan sağlayıcıya tanınan payı belirler.
  AiTask.summary:
      AiTaskConfig(_hopsStudySuite, maxTokens: 2048, perProviderTimeoutMs: 35000),
  AiTask.examGen:
      AiTaskConfig(_hopsExamGen, maxTokens: 4096, perProviderTimeoutMs: 18000),
  AiTask.factual:
      AiTaskConfig(_hopsChatFree, maxTokens: 1536, perProviderTimeoutMs: 8000),
  AiTask.cheap:
      AiTaskConfig(_hopsChatFree, maxTokens: 1024, perProviderTimeoutMs: 6000),
};

// ── PREMİUM ortak zincirler ──────────────────────────────────────────────────
// Aynı sağlayıcı sırası, daha güçlü modeller (Pro / 4o / reasoner).
// Sohbet/metin — premium.
const List<AiHop> _hopsChatPremium = [
  AiHop(AiProvider.gemini, 'gemini-2.5-flash'),
  AiHop(AiProvider.openai, 'gpt-4o-mini'),
  AiHop(AiProvider.deepseek, 'deepseek-chat'),
  AiHop(AiProvider.grok, 'grok-3-mini'),
  AiHop(AiProvider.claude, 'claude-sonnet-4-6'),
];
// Sayısal/çözüm — premium (Pro + 4o + R1).
const List<AiHop> _hopsSolvePremium = [
  AiHop(AiProvider.gemini, 'gemini-2.5-flash'),
  // ChatGPT her zaman en ucuz gpt-4o-mini (multimodal: metin+vision). Eskiden
  // premium zincirler pahalı gpt-4o kullanıyordu; kullanıcı isteği: en ucuz.
  AiHop(AiProvider.openai, 'gpt-4o-mini'),
  // Failover'da deepseek-chat (hızlı); reasoner/R1 20-60sn sürüp timeout'a
  // takılıyordu → boşa bekleme. Kullanıcı isterse picker'dan reasoner seçebilir.
  AiHop(AiProvider.deepseek, 'deepseek-chat'),
  AiHop(AiProvider.grok, 'grok-3'),
  AiHop(AiProvider.claude, 'claude-sonnet-4-6'),
];
// Fotoğraflı çözüm (vision) — premium. Seçili model en başa eklenir.
const List<AiHop> _hopsPhotoPremium = [
  AiHop(AiProvider.gemini, 'gemini-2.5-flash'),
  // ChatGPT her zaman en ucuz gpt-4o-mini (multimodal: metin+vision). Eskiden
  // premium zincirler pahalı gpt-4o kullanıyordu; kullanıcı isteği: en ucuz.
  AiHop(AiProvider.openai, 'gpt-4o-mini'),
  // grok-2-vision-1212 xAI'da kaldırıldı ("Model not found"); grok-4.3
  // multimodal (text+vision) güncel model. Canlı testte görseli okuyup çözdü.
  AiHop(AiProvider.grok, 'grok-4.3'),
];

// ── PREMİUM kullanıcı task config ────────────────────────────────────────────
const Map<AiTask, AiTaskConfig> kAiTaskConfigPremium = {
  AiTask.photoSolve:
      AiTaskConfig(_hopsPhotoPremium, maxTokens: 4096, perProviderTimeoutMs: 14000),
  AiTask.homeworkSolve:
      AiTaskConfig(_hopsSolvePremium, maxTokens: 4096, perProviderTimeoutMs: 12000),
  AiTask.examGen:
      AiTaskConfig(_hopsExamGen, maxTokens: 4096, perProviderTimeoutMs: 18000),
  AiTask.coach:
      AiTaskConfig(_hopsChatPremium, maxTokens: 2048, perProviderTimeoutMs: 6000),
  AiTask.voice:
      AiTaskConfig(_hopsChatPremium, maxTokens: 1536, perProviderTimeoutMs: 5000),
  AiTask.cameraLive:
      AiTaskConfig(_hopsPhotoPremium, maxTokens: 2048, perProviderTimeoutMs: 6000),
  // Konu pekiştirme — büyük JSON üretimi; 7 sn tüm zinciri iptal ettiriyordu
  // (free config'deki nota bak).
  AiTask.summary:
      AiTaskConfig(_hopsStudySuite, maxTokens: 3072, perProviderTimeoutMs: 35000),
  AiTask.factual:
      AiTaskConfig(_hopsChatPremium, maxTokens: 2048, perProviderTimeoutMs: 8000),
  AiTask.cheap:
      AiTaskConfig(_hopsChatPremium, maxTokens: 1024, perProviderTimeoutMs: 6000),
};

class AiChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  const AiChatMessage(this.role, this.content);
  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// Vision görseli — son user mesajına eklenir. base64 (data: öneki olmadan).
class AiImageInput {
  final String mimeType; // örn. 'image/jpeg'
  final String base64;
  const AiImageInput({required this.mimeType, required this.base64});
  Map<String, String> toJson() => {'mimeType': mimeType, 'data': base64};
}

class AiProviderService {
  // ── ANA AÇMA/KAPAMA BAYRAĞI ─────────────────────────────────────────────
  // aiProxy DEPLOY edilip anahtarlar (OPENAI/XAI/ANTHROPIC/DEEPSEEK) Secret
  // Manager'a eklendikten SONRA bunu `true` yap. false iken çağrı yerleri
  // mevcut Gemini yolunu (geminiProxy) kullanmaya devam eder → hiçbir şey
  // bozulmaz. true olunca tüm AI özellikleri çoklu-sağlayıcı + failover'a geçer.
  static const bool kEnabled = true;

  // Gen2 onRequest — cloudfunctions.net formu sabittir.
  static const String _proxyUrl =
      'https://us-central1-qualsar2-640f0.cloudfunctions.net/aiProxy';
  static const String _tag = '🤖 [AiProviderService]';

  static final http.Client _http = http.Client();

  static void _log(String m) {
    if (kDebugMode) debugPrint('$_tag $m');
  }

  // ── Seçili sağlayıcı/model (kalıcı) ─────────────────────────────────────
  // Varsayılan: en ucuz genel seçenek (Gemini Flash-Lite). Kullanıcı ayarlardan
  // değiştirebilir; AI çağrıları provider verilmezse bu seçimi kullanır.
  static const _kProviderKey = 'ai_selected_provider';
  static const _kModelKey = 'ai_selected_model';
  static AiProvider _selectedProvider = AiProvider.gemini;
  static String? _selectedModel;

  static AiProvider get selectedProvider => _selectedProvider;
  static String get selectedModel =>
      _selectedModel ?? aiProviderInfo(_selectedProvider).defaultModel.id;
  static AiProviderInfo get selectedInfo => aiProviderInfo(_selectedProvider);

  /// Uygulama açılışında çağır (main.dart) — kayıtlı seçimi yükler.
  static Future<void> loadSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pw = prefs.getString(_kProviderKey);
      if (pw != null) {
        final match = kAiProviders.where((e) => e.wireName == pw);
        if (match.isNotEmpty) _selectedProvider = match.first.provider;
      }
      final m = prefs.getString(_kModelKey);
      // Model hâlâ katalogda mı? Değilse en ucuza düş.
      final models = aiProviderInfo(_selectedProvider).models.map((e) => e.id);
      _selectedModel = (m != null && models.contains(m)) ? m : null;
    } catch (_) {/* varsayılanlar kalır */}
  }

  /// Kullanıcı ayarlardan seçince çağrılır — kalıcı kaydeder.
  static Future<void> setSelection(AiProvider provider, String modelId) async {
    _selectedProvider = provider;
    _selectedModel = modelId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProviderKey, aiProviderInfo(provider).wireName);
      await prefs.setString(_kModelKey, modelId);
    } catch (_) {}
  }

  /// Tek bir prompt için kısa yol. [provider] verilmezse kullanıcının seçtiği
  /// (en ucuz varsayılan) sağlayıcı kullanılır. [system] opsiyonel talimat.
  static Future<String> ask({
    AiProvider? provider,
    String? model,
    required String prompt,
    String? system,
    int maxTokens = 2048,
    Duration timeout = const Duration(seconds: 90),
  }) {
    return chat(
      provider: provider,
      model: model,
      messages: [AiChatMessage('user', prompt)],
      system: system,
      maxTokens: maxTokens,
      timeout: timeout,
    );
  }

  /// Çok turlu sohbet. Sağlayıcıya göre normalize işini proxy yapar.
  static Future<String> chat({
    AiProvider? provider,
    String? model,
    required List<AiChatMessage> messages,
    String? system,
    int maxTokens = 2048,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    // Standart "diğer AI çağrıları" zinciri:
    //   Gemini → OpenAI → DeepSeek → Grok → Claude (Claude en pahalı → en son).
    // Her sağlayıcı 6 sn içinde bağlanamaz/hata verirse otomatik sıradakine geçer.
    final hops = _hopsChatFree
        .map((h) => {'provider': aiProviderInfo(h.provider).wireName, 'model': h.model})
        .toList();

    // Caller açıkça bir sağlayıcı belirttiyse (ör. metin çözümde DeepSeek
    // reasoner) onu zincirin başına al; gerisi standart yedek olarak kalır.
    // provider verilmediyse global seçim DİKKATE ALINMAZ — arka plan çağrıları
    // her zaman ucuz/güvenilir Gemini ile başlar.
    if (provider != null) {
      final info = aiProviderInfo(provider);
      final modelId = (model != null && model.isNotEmpty) ? model : info.defaultModel.id;
      hops.removeWhere((h) => h['provider'] == info.wireName);
      hops.insert(0, {'provider': info.wireName, 'model': modelId});
    }

    final payload = <String, dynamic>{
      'providers': hops,
      'perProviderTimeoutMs': 6000,
      'messages': messages.map((m) => m.toJson()).toList(),
      'maxTokens': maxTokens,
      if (system != null && system.isNotEmpty) 'system': system,
    };
    final label = hops.map((h) => h['provider']).join('→');
    return _post(payload, timeout, 'chat [$label]');
  }

  /// Görev-bazlı çağrı: premium/ücretsiz config seçimi + sıralı failover.
  /// [isPremium] true → 5 sağlayıcı zinciri; false → Flash-Lite + DeepSeek.
  static Future<String> chatTask(
    AiTask task, {
    required List<AiChatMessage> messages,
    bool isPremium = false,
    String? system,
    int? maxTokens,
    AiImageInput? image,
    // true → kullanıcının seçtiği sağlayıcı zincirin EN BAŞINA eklenir.
    // Fotoğraflı çözümde kullanılır: (seçim) → Gemini → OpenAI → Grok.
    bool useSelectedFirst = false,
    // Açık sağlayıcı/model — global seçimi DEĞİŞTİRMEDEN bu çağrı için zincirin
    // en başına eklenir (ör. foto-çözüm karosel seçimi). Verilirse
    // useSelectedFirst'ten önce gelir.
    AiProvider? firstProvider,
    String? firstModel,
    Duration timeout = const Duration(seconds: 120),
  }) {
    final cfg = (isPremium ? kAiTaskConfigPremium : kAiTaskConfigFree)[task]!;

    // Zincir hop'larını {provider, model} listesine çevir.
    final hops = cfg.hops
        .map((h) => {'provider': aiProviderInfo(h.provider).wireName, 'model': h.model})
        .toList();

    if (firstProvider != null || useSelectedFirst) {
      final p = firstProvider ?? _selectedProvider;
      final selWire = aiProviderInfo(p).wireName;
      final selModel = firstModel ??
          (firstProvider != null ? aiProviderInfo(p).defaultModel.id : selectedModel);
      // Zincirde aynı sağlayıcı varsa çıkar, seçimi başa koy (çift çağrı yok).
      hops.removeWhere((h) => h['provider'] == selWire);
      hops.insert(0, {'provider': selWire, 'model': selModel});
    }

    final payload = <String, dynamic>{
      'providers': hops,
      'perProviderTimeoutMs': cfg.perProviderTimeoutMs,
      'messages': messages.map((m) => m.toJson()).toList(),
      'maxTokens': maxTokens ?? cfg.maxTokens,
      if (system != null && system.isNotEmpty) 'system': system,
      if (image != null) 'image': image.toJson(),
    };
    final label = hops.map((h) => h['provider']).join('→');
    return _post(payload, timeout, 'task:${task.name} [$label]');
  }

  /// Tek prompt için görev-bazlı kısa yol.
  static Future<String> askTask(
    AiTask task, {
    required String prompt,
    bool isPremium = false,
    String? system,
    int? maxTokens,
    AiImageInput? image,
    bool useSelectedFirst = false,
    AiProvider? firstProvider,
    String? firstModel,
    Duration timeout = const Duration(seconds: 120),
  }) =>
      chatTask(task,
          messages: [AiChatMessage('user', prompt)],
          isPremium: isPremium,
          system: system,
          maxTokens: maxTokens,
          image: image,
          useSelectedFirst: useSelectedFirst,
          firstProvider: firstProvider,
          firstModel: firstModel,
          timeout: timeout);

  // ── Ortak HTTP gönderim (auth token + proxy POST + normalize) ──────────
  static Future<String> _post(
      Map<String, dynamic> payload, Duration timeout, String label) async {
    // Ebeveyn önizlemesinde HİÇBİR AI çağrısı çıkamaz — kök engel.
    ParentPreview.blockAi();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('AI çağrısı için oturum açılmış olmalı.');
    }
    // Cache'li token kullan (zorla yenileme YOK). getIdToken(true) her çağrıda
    // Firebase Auth'a ağ round-trip'i yapıyordu (+200-800ms/çağrı). Token ~1sa
    // geçerli ve SDK süresi dolmadan otomatik yeniler → cache'li okuma anında.
    String? idToken;
    try {
      idToken = await user.getIdToken();
    } catch (_) {
      idToken = await user.getIdToken(true); // cache başarısızsa zorla yenile
    }

    _log('İstek → $label');
    final resp = await _http
        .post(
          Uri.parse(_proxyUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (resp.statusCode == 200) {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return (j['text'] as String?) ?? '';
    }

    String detail = '';
    try {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      detail = (j['error'] as String?) ?? (j['details'] as String?) ?? resp.body;
    } catch (_) {
      detail = resp.body;
    }
    _log('HATA ${resp.statusCode}: $detail');
    ErrorLogger.instance.capture(
      'aiProxy $label ${resp.statusCode}',
      StackTrace.current,
      context: 'ai_provider_service',
    );
    throw Exception('AI hatası (${resp.statusCode}): $detail');
  }
}
