import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'locale_service.dart';
import 'secrets.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  RUNTIME TRANSLATOR — otomatik kaçış vanası
//
//  Amaç: Kodda yazılmış binlerce Türkçe string'i manuel olarak tek tek
//  her 55 dile çevirmek yerine, uygulama çalışırken görülen kaynakları
//  TOPLU olarak Gemini'ye çevirtip KALICI cachelemek.
//
//  Akış:
//    1) `.tr()` extension'u her çağrıldığında kaynak string'i "görüldü"
//       listesine ekler.
//    2) LocaleService.setLocale(newLang) çağrıldığında `preloadAll(newLang)`
//       tetiklenir → görüldü listesindeki tüm kaynaklar batch halinde
//       Gemini'ye gönderilir, JSON yanıt parse edilir, cache'e yazılır.
//    3) `.tr()` senkron döner: cache'de varsa çeviriyi, yoksa kaynağı.
//       (İlk açılışta Türkçe görünebilir; preload bitince rebuild eder.)
//    4) Cache SharedPreferences'ta kalıcıdır; sonraki açılışlarda yeniden
//       çevirmez.
//
//  Maliyet: bir kullanıcı dil değiştirdiğinde ~1 Gemini çağrısı / 80 string.
//  5000 string × 50 dil = ~6000 çağrı ömür boyu (çok düşük).
// ═══════════════════════════════════════════════════════════════════════════════

class RuntimeTranslator extends ChangeNotifier {
  RuntimeTranslator._();
  static final RuntimeTranslator instance = RuntimeTranslator._();

  static const _tag = '🔤 [RuntimeTranslator]';
  static const _prefCachePrefix = 'rt_trans_cache_';
  static const _prefSeenKey = 'rt_trans_seen_v1';
  static const _sourceLang = 'tr'; // Uygulama kaynak dili Türkçe
  static const _batchSize = 60;
  static const _timeout = Duration(seconds: 45);

  SharedPreferences? _prefs;
  // lang → (source → translated)
  final Map<String, Map<String, String>> _cache = {};
  // Tüm kodda `.tr()` çağrısıyla görülen kaynak string'ler
  final Set<String> _seen = {};
  bool _dirty = false;
  Timer? _flushTimer;
  // Aktif locale için preload işlemi devam ediyorsa
  final Map<String, Future<void>> _pendingPreloads = {};
  bool _isPreloading = false;
  bool get isPreloading => _isPreloading;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Görüldü setini yükle
    final seenRaw = _prefs!.getString(_prefSeenKey);
    if (seenRaw != null) {
      try {
        final list = jsonDecode(seenRaw) as List;
        _seen.addAll(list.map((e) => e.toString()));
      } catch (_) {}
    }
    // Desteklenen dillerin cachelerini yükle
    for (final lang in LocaleService.supportedLocales) {
      final raw = _prefs!.getString('$_prefCachePrefix$lang');
      if (raw == null) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _cache[lang] =
            map.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      } catch (_) {}
    }
    _log('init: ${_seen.length} seen · '
        '${_cache.entries.map((e) => "${e.key}:${e.value.length}").join(", ")}');
  }

  /// Bir kaynak string'i "görüldü" olarak işaretle (ileride preload eder).
  void register(String source) {
    if (source.trim().isEmpty) return;
    if (source.length > 500) return; // çok uzun = muhtemelen dinamik metin
    if (_seen.add(source)) {
      _dirty = true;
      _scheduleFlush();
      _scheduleAutoPreload();
    }
  }

  /// Yeni string'ler kaydedilince 2 sn debounce ile aktif locale için
  /// eksik çevirileri tetikle (kullanıcı bir ekranı ilk açtığında arka
  /// planda çeviri başlasın diye).
  Timer? _autoPreloadTimer;
  void _scheduleAutoPreload() {
    final lang = LocaleService.global?.localeCode ?? _sourceLang;
    if (lang == _sourceLang) return;
    _autoPreloadTimer?.cancel();
    _autoPreloadTimer = Timer(const Duration(seconds: 2), () {
      preloadAll(lang);
    });
  }

  /// Senkron arama — cache'de varsa çeviriyi, yoksa kaynağı döner.
  String lookup(String source) {
    final lang = LocaleService.global?.localeCode ?? _sourceLang;
    if (lang == _sourceLang) return source;
    final byLang = _cache[lang];
    if (byLang == null) return source;
    final hit = byLang[source];
    if (hit != null && hit.trim().isNotEmpty) return hit;
    return source;
  }

  /// Hedef dile geç + henüz çevrilmemiş tüm "seen" string'leri batch halinde
  /// Gemini'ye çevirt + cache'e yaz + UI'ı tetikle.
  Future<void> preloadAll(String targetLang) async {
    if (targetLang == _sourceLang) return;
    if (!LocaleService.supportedLocales.contains(targetLang)) return;
    // Aynı dil için aynı anda yalnızca 1 preload
    final existing = _pendingPreloads[targetLang];
    if (existing != null) return existing;
    final completer = Completer<void>();
    _pendingPreloads[targetLang] = completer.future;
    _isPreloading = true;
    notifyListeners();
    try {
      final byLang = _cache.putIfAbsent(targetLang, () => {});
      final todo =
          _seen.where((s) => !byLang.containsKey(s)).toList(growable: false);
      if (todo.isEmpty) {
        _log('preload: $targetLang zaten tam (${byLang.length} çeviri)');
        return;
      }
      _log('preload: $targetLang için ${todo.length} string çevriliyor…');
      // Chunk'lara böl, sırayla Gemini'ye gönder — 503/429 gibi geçici
      // hatalarda retry backoff ile tekrar dener; başarısız batch'leri
      // sonunda küçük chunk'lara bölerek ikinci turda tamamlar.
      final failedChunks = <List<String>>[];
      for (int i = 0; i < todo.length; i += _batchSize) {
        final end = (i + _batchSize).clamp(0, todo.length);
        final chunk = todo.sublist(i, end);
        final ok = await _processChunk(chunk, targetLang, byLang);
        if (!ok) failedChunks.add(chunk);
      }
      // Başarısız batch'leri yarı boyda tekrar dene.
      for (final failed in failedChunks) {
        for (int i = 0; i < failed.length; i += 20) {
          final sub = failed.sublist(i, (i + 20).clamp(0, failed.length));
          await _processChunk(sub, targetLang, byLang);
        }
      }
      _log('preload tamam: $targetLang (${byLang.length} total, '
          '${todo.length - byLang.length + (todo.length - byLang.length)} eksik)');
    } finally {
      _pendingPreloads.remove(targetLang);
      _isPreloading = _pendingPreloads.isNotEmpty;
      if (!completer.isCompleted) completer.complete();
      notifyListeners();
    }
  }

  /// Tek bir chunk'ı işle. Başarılı: cache'e ekler + persist + notify.
  /// Başarısız (boş döndü): false döner (üst katman retry için işaretler).
  Future<bool> _processChunk(
    List<String> chunk,
    String targetLang,
    Map<String, String> byLang,
  ) async {
    try {
      final translated = await _translateBatch(chunk, targetLang);
      if (translated.isEmpty) return false;
      byLang.addAll(translated);
      await _persistLang(targetLang);
      notifyListeners();
      return translated.length == chunk.length;
    } catch (e) {
      _log('chunk hatası: $e');
      return false;
    }
  }

  /// Cache'i dışarıdan temizleme (ayarlar sayfasından opsiyonel).
  Future<void> clearCache() async {
    _cache.clear();
    if (_prefs == null) return;
    for (final lang in LocaleService.supportedLocales) {
      await _prefs!.remove('$_prefCachePrefix$lang');
    }
    notifyListeners();
  }

  // ── Batch çeviri (Gemini) ─────────────────────────────────────────────────
  Future<Map<String, String>> _translateBatch(
      List<String> sources, String targetLang) async {
    // Hedef dilin İngilizce adını al (Gemini daha iyi anlasın)
    final langName = _langName(targetLang);
    final jsonInput = jsonEncode(sources);

    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text': '''You are a professional translator for an education app (QuAlsar).
Translate each string in the JSON array below from Turkish to $langName.
STRICT RULES:
- Output ONLY a JSON array with the same length and order as the input.
- Do NOT include any explanation, no markdown, no code fences.
- Preserve emojis, punctuation, placeholders like {n}, {name}, %s.
- Keep technical terms (math, physics, etc.) translated naturally.
- Each translated string must fit within a reasonable length of the source.
- For greetings, titles, and buttons — use the equivalent used in the target country's app UI.

Input:
$jsonInput

Output (JSON array only):'''
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.0,
        'topP': 0.1,
        'maxOutputTokens': 8192,
      }
    };

    final keys = _geminiKeys();
    // 503/UNAVAILABLE için backoff retry (paid tier'da da oluyor).
    const retryDelaysMs = [2000, 5000, 10000];
    for (int attempt = 0; attempt <= retryDelaysMs.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
            Duration(milliseconds: retryDelaysMs[attempt - 1]));
      }
      for (final key in keys) {
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/'
            'gemini-2.5-flash-lite:generateContent?key=$key');
        try {
          final resp = await http
              .post(
                url,
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(body),
              )
              .timeout(_timeout);
          if (resp.statusCode == 200) {
            final j = jsonDecode(utf8.decode(resp.bodyBytes))
                as Map<String, dynamic>;
            final text =
                (j['candidates']?[0]?['content']?['parts']?[0]?['text']
                        as String?)
                    ?.trim();
            if (text == null) break; // boş cevap → retry
            final parsed = _extractJsonArray(text);
            if (parsed == null || parsed.length != sources.length) {
              _log('mismatch: input=${sources.length} '
                  'output=${parsed?.length} (retry)');
              break; // retry
            }
            final out = <String, String>{};
            for (int i = 0; i < sources.length; i++) {
              final t = parsed[i].trim();
              if (t.isNotEmpty) out[sources[i]] = t;
            }
            return out;
          }
          if (resp.statusCode == 401 ||
              resp.statusCode == 403 ||
              resp.statusCode == 429) {
            _log('key hatası ${resp.statusCode}, sıradakini deniyor');
            continue; // bir sonraki key'i dene
          }
          if (resp.statusCode == 503 || resp.statusCode == 500) {
            _log('HTTP ${resp.statusCode} (geçici) — backoff retry');
            break; // retry loop'a geri dön
          }
          _log('HTTP ${resp.statusCode} — vazgeç');
          return {};
        } catch (e) {
          _log('çağrı hatası: $e');
          continue;
        }
      }
    }
    return {};
  }

  List<String>? _extractJsonArray(String raw) {
    // Markdown fence'leri temizle
    var s = raw.trim();
    if (s.startsWith('```')) {
      final end = s.lastIndexOf('```');
      if (end > 3) {
        s = s.substring(3, end);
        final nl = s.indexOf('\n');
        if (nl > -1) s = s.substring(nl + 1);
      }
    }
    s = s.trim();
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return null;
  }

  List<String> _geminiKeys() {
    final list = <String>[
      if (Secrets.gemini.isNotEmpty) Secrets.gemini,
      ...Secrets.geminiFallbacks.where((k) => k.isNotEmpty),
    ];
    return list;
  }

  String _langName(String code) {
    for (final t in LocaleService.languages) {
      if (t.$4 == code) return t.$3; // English name
    }
    return code;
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 3), _flushSeen);
  }

  Future<void> _flushSeen() async {
    if (!_dirty || _prefs == null) return;
    _dirty = false;
    try {
      await _prefs!.setString(_prefSeenKey, jsonEncode(_seen.toList()));
    } catch (_) {}
  }

  Future<void> _persistLang(String lang) async {
    if (_prefs == null) return;
    final map = _cache[lang];
    if (map == null) return;
    try {
      await _prefs!.setString(
          '$_prefCachePrefix$lang', jsonEncode(map));
    } catch (_) {}
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('$_tag $msg');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  .tr() EXTENSION — hardcoded string'i otomatik çeviri pipeline'ına sok
// ═══════════════════════════════════════════════════════════════════════════════

extension RuntimeTranslatable on String {
  /// Kodda yazılı hardcoded (Türkçe) string'i mevcut locale'e çevirir.
  /// İlk kullanımda kaynak döner + arkada preload zaten olmuşsa cache'den çekilir.
  /// Locale değişikliği sonrası yeni preload tamamlanınca UI rebuild olur.
  String tr() {
    RuntimeTranslator.instance.register(this);
    return RuntimeTranslator.instance.lookup(this);
  }
}
