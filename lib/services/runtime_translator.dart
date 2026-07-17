import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'error_logger.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'locale_service.dart';
import 'secrets.dart';
import 'translations_generated.dart';

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

  // notifyListeners debounce — preload sırasında her chunk için ayrı ayrı
  // bildirim göndermek tüm uygulamayı (AnimatedBuilder MaterialApp'ı
  // sarıyor) rebuild ediyor. Çoklu bildirimleri tek bir frame'e topla.
  Timer? _notifyDebounce;
  void _scheduleNotify(
      {Duration delay = const Duration(milliseconds: 1500)}) {
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(delay, () {
      _notifyDebounce = null;
      notifyListeners();
    });
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // ANDROID ANR DÜZELTMESİ: seen listesi + dil cache'leri eskiden
    // SharedPreferences'taydı. Android'de TÜM prefs tek XML dosyasıdır;
    // cache büyüdükçe (dil başına ~5000 string) o XML birkaç MB oluyor,
    // soğuk açılışta ANA THREAD'de komple parse ediliyor ve her yazışta
    // komple yeniden yazılıyordu → "uygulama yanıt vermiyor" (ANR) +
    // "bazen geç açılıyor". Artık mobilde dosyada tutulur (aşağıdaki
    // _readBlob/_writeBlob); eski prefs anahtarları tek seferlik dosyaya
    // taşınıp prefs'ten SİLİNİR (XML kalıcı olarak küçülür). Web'de dosya
    // sistemi yok → prefs (localStorage) davranışı aynen sürer.
    await _migrateFromPrefs();
    // Görüldü setini yükle
    final seenRaw = await _readBlob(_seenBlob);
    if (seenRaw != null) {
      try {
        final list = jsonDecode(seenRaw) as List;
        _seen.addAll(list.map((e) => e.toString()));
      } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'runtime_translator'); }
    }
    // Sadece aktif dilin cache'i yüklenir (lazy); TR'de hiç yük yok.
    final active = LocaleService.global?.localeCode ?? _sourceLang;
    if (active != _sourceLang) {
      await _ensureLangLoadedAsync(active);
    }
    _log('init: ${_seen.length} seen · lazy lang load');
  }

  // ── Depolama katmanı: mobil/desktop = dosya, web = SharedPreferences ─────
  static const _seenBlob = 'seen_v1';
  String _langBlob(String lang) => 'cache_$lang';

  Directory? _dirCache;
  Future<Directory> _storageDir() async {
    final d = _dirCache;
    if (d != null) return d;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/rt_translations');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dirCache = dir;
    return dir;
  }

  // Web'de eski prefs anahtarları aynen kullanılır (davranış değişmez).
  String _webKey(String blob) =>
      blob == _seenBlob ? _prefSeenKey : '$_prefCachePrefix${blob.substring(6)}';

  Future<String?> _readBlob(String blob) async {
    try {
      if (kIsWeb) return _prefs?.getString(_webKey(blob));
      final f = File('${(await _storageDir()).path}/$blob.json');
      return await f.exists() ? await f.readAsString() : null;
    } catch (e) {
      _log('readBlob($blob) fail: $e');
      return null;
    }
  }

  Future<void> _writeBlob(String blob, String data) async {
    try {
      if (kIsWeb) {
        await _prefs?.setString(_webKey(blob), data);
        return;
      }
      await File('${(await _storageDir()).path}/$blob.json')
          .writeAsString(data);
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'runtime_translator');
    }
  }

  Future<void> _deleteBlob(String blob) async {
    try {
      if (kIsWeb) {
        await _prefs?.remove(_webKey(blob));
        return;
      }
      final f = File('${(await _storageDir()).path}/$blob.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Tek seferlik migrasyon: eski SharedPreferences anahtarlarını dosyaya
  /// taşı + prefs'ten sil. Web'de no-op (prefs zaten kalıcı depo).
  Future<void> _migrateFromPrefs() async {
    if (kIsWeb) return;
    final p = _prefs;
    if (p == null) return;
    try {
      final seenRaw = p.getString(_prefSeenKey);
      if (seenRaw != null) {
        if (await _readBlob(_seenBlob) == null) {
          await _writeBlob(_seenBlob, seenRaw);
        }
        await p.remove(_prefSeenKey);
        _log('migrasyon: seen prefs → dosya');
      }
      for (final lang in LocaleService.supportedLocales) {
        final key = '$_prefCachePrefix$lang';
        final raw = p.getString(key);
        if (raw == null) continue;
        if (await _readBlob(_langBlob(lang)) == null) {
          await _writeBlob(_langBlob(lang), raw);
        }
        await p.remove(key);
        _log('migrasyon: $lang cache prefs → dosya');
      }
    } catch (e, st) {
      ErrorLogger.instance.capture(e, st, context: 'runtime_translator');
    }
  }

  /// Belirtilen dilin cache'ini lazy yükler (senkron çağıranlar için).
  /// Bellekte hemen boş map oluşur — lookup'lar dosya gelene kadar baked
  /// çevirilere düşer; dosya yüklenince UI debounce'lu notify ile tazelenir.
  void _ensureLangLoaded(String lang) {
    unawaited(_ensureLangLoadedAsync(lang));
  }

  final Map<String, Future<void>> _langLoads = {};
  Future<void> _ensureLangLoadedAsync(String lang) {
    return _langLoads.putIfAbsent(lang, () async {
      final mem = _cache.putIfAbsent(lang, () => {});
      final raw = await _readBlob(_langBlob(lang));
      if (raw == null) return;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        // putIfAbsent: dosya okunurken API'den gelen taze çeviriler ezilmesin.
        var added = false;
        map.forEach((k, v) {
          if (!mem.containsKey(k)) {
            mem[k] = v?.toString() ?? '';
            added = true;
          }
        });
        if (added) _scheduleNotify(delay: const Duration(milliseconds: 50));
      } catch (_) {/* bozuk dosya → boş cache ile devam */}
    });
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

  /// Toplu kayıt — startup'ta 5000+ string register edildiğinde her birinde
  /// timer reset/restart yapılmasın diye. Tek seferde set'e ekler, son anda
  /// flush + autoPreload tetikler.
  void bulkRegister(Iterable<String> sources) {
    bool anyAdded = false;
    for (final source in sources) {
      if (source.trim().isEmpty) continue;
      if (source.length > 500) continue;
      if (_seen.add(source)) anyAdded = true;
    }
    if (anyAdded) {
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

  /// Senkron arama — önce SharedPreferences cache, sonra KODA GÖMÜLÜ (baked)
  /// generated çeviri, ikisi de yoksa kaynak Türkçe döner.
  String lookup(String source) {
    final lang = LocaleService.global?.localeCode ?? _sourceLang;
    if (lang == _sourceLang) return source;
    // 1) Lazy SharedPreferences cache (runtime'da üretilmiş, varsa).
    _ensureLangLoaded(lang);
    final hit = _cache[lang]?[source];
    if (hit != null && hit.trim().isNotEmpty) return hit;
    // 2) Build-time'da generator ile üretilip koda gömülü çeviri (offline,
    //    API çağrısı yok). `dart run tool/generate_translations.dart` bunu yazar.
    final baked = generatedTranslations[lang]?[source];
    if (baked != null && baked.isNotEmpty) return baked;
    // 3) Çeviri yok → kaynak Türkçe.
    return source;
  }

  /// Bir kaynak string'in koda gömülü (baked) çevirisi var mı? preloadAll
  /// gereksiz API çağrısı yapmasın diye kullanılır.
  bool _hasBaked(String lang, String source) {
    final b = generatedTranslations[lang]?[source];
    return b != null && b.isNotEmpty;
  }

  // ── DIŞ KAYNAK (WebView / HTML 3D ders) ÇEVİRİSİ ──────────────────────────
  // 3D ders HTML'leri içindeki Türkçe metinler bu pipeline'a buradan girer.
  // Akış: WebView görünür metinleri toplar → Flutter [translateStrings] çağırır
  // → cache + baked'den karşılanır, eksikler Gemini ile çevrilip kalıcı
  // cache'lenir → WebView'a geri enjekte edilir. İkinci açılışta tamamı
  // cache/baked'den gelir (offline, anında).

  /// SADECE elde hazır olan çevirileri (cache + baked) döndürür — API ÇAĞIRMAZ.
  /// İlk boyamada WebView'ı hızlıca güncellemek için kullanılır.
  Map<String, String> peekCached(List<String> sources, String lang) {
    final out = <String, String>{};
    if (lang == _sourceLang) return out;
    _ensureLangLoaded(lang);
    final byLang = _cache[lang];
    for (final raw in sources) {
      final src = raw.trim();
      if (src.isEmpty) continue;
      final c = byLang?[src];
      if (c != null && c.trim().isNotEmpty) {
        out[src] = c;
        continue;
      }
      final b = generatedTranslations[lang]?[src];
      if (b != null && b.isNotEmpty) out[src] = b;
    }
    return out;
  }

  /// Rastgele Türkçe string listesini hedef dile çevirir. Önce cache + baked'i
  /// kullanır; eksikleri batch halinde çevirip cache'e yazar ve kalıcılaştırır.
  /// Dönen map yalnızca çevirisi bulunan kaynakları içerir (kalanlar Türkçe
  /// kalır). String'ler ileride generator ile bake edilebilmesi için "seen"
  /// listesine de eklenir.
  Future<Map<String, String>> translateStrings(
      List<String> sources, String lang,
      {void Function(Map<String, String> batch)? onBatch}) async {
    final result = <String, String>{};
    if (lang == _sourceLang) return result;
    if (!LocaleService.supportedLocales.contains(lang)) return result;
    // Dosya cache'i tam yüklenmeden "missing" hesaplanırsa zaten çevrilmiş
    // string'ler API'ye tekrar gider — await ile garanti et.
    await _ensureLangLoadedAsync(lang);
    final byLang = _cache.putIfAbsent(lang, () => {});
    final missing = <String>[];
    final seenForBatch = <String>{};
    bool anySeenAdded = false;
    for (final raw in sources) {
      final src = raw.trim();
      if (src.isEmpty || src.length > 500) continue;
      if (_seen.add(src)) anySeenAdded = true;
      final cached = byLang[src];
      if (cached != null && cached.trim().isNotEmpty) {
        result[src] = cached;
        continue;
      }
      final baked = generatedTranslations[lang]?[src];
      if (baked != null && baked.isNotEmpty) {
        result[src] = baked;
        continue;
      }
      // Aynı string birden çok düğümde olabilir → batch'e bir kez koy.
      if (seenForBatch.add(src)) missing.add(src);
    }
    if (anySeenAdded) {
      _dirty = true;
      _scheduleFlush();
    }
    for (int i = 0; i < missing.length; i += _batchSize) {
      final end = (i + _batchSize).clamp(0, missing.length);
      final chunk = missing.sublist(i, end);
      final translated = await _translateBatch(chunk, lang);
      if (translated.isNotEmpty) {
        byLang.addAll(translated);
        result.addAll(translated);
        await _persistLang(lang);
        // Her batch hazır olunca çağıranı bilgilendir (artımlı UI güncelleme).
        if (onBatch != null) onBatch(translated);
      }
    }
    return result;
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
    // Preload başlangıcında küçük gecikmeli notify — anında rebuild yerine
    // bir sonraki frame'de.
    _scheduleNotify(delay: const Duration(milliseconds: 100));
    try {
      // Cache dosyası tam yüklenmeden todo hesaplanmasın (gereksiz API).
      await _ensureLangLoadedAsync(targetLang);
      final byLang = _cache.putIfAbsent(targetLang, () => {});
      // Cache'te VEYA koda gömülü (baked) olanları atla — baked olanlar zaten
      // offline çözülüyor, tekrar API'ye gitmeye gerek yok.
      final todo = _seen
          .where((s) =>
              !byLang.containsKey(s) && !_hasBaked(targetLang, s))
          .toList(growable: false);
      if (todo.isEmpty) {
        _log('preload: $targetLang zaten tam (baked + cache)');
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
      // Preload sonu — mevcut debounce'u iptal edip son rebuild'i hemen tetikle.
      _notifyDebounce?.cancel();
      _notifyDebounce = null;
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
      // Çoklu chunk biten her seferinde notifyListeners çağırmak yerine
      // 1.5sn'lik debounce ile birleştir — tek bir frame'de UI güncellenir.
      _scheduleNotify();
      return translated.length == chunk.length;
    } catch (e) {
      _log('chunk hatası: $e');
      return false;
    }
  }

  /// Cache'i dışarıdan temizleme (ayarlar sayfasından opsiyonel).
  Future<void> clearCache() async {
    _cache.clear();
    _langLoads.clear();
    for (final lang in LocaleService.supportedLocales) {
      await _deleteBlob(_langBlob(lang));
      // Eski (migrasyon öncesi) prefs anahtarı kalmışsa onu da temizle.
      await _prefs?.remove('$_prefCachePrefix$lang');
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
      // İlk denemeler ucuz flash-lite; SON denemede güvenilir flash'a düş
      // (flash-lite Google'da ~%60 503 "high demand" veriyor).
      final model = attempt >= retryDelaysMs.length
          ? 'gemini-2.5-flash'
          : 'gemini-2.5-flash-lite';
      for (final key in keys) {
        final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/'
            '$model:generateContent?key=$key');
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
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'runtime_translator'); }
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
    if (!_dirty) return;
    _dirty = false;
    try {
      await _writeBlob(_seenBlob, jsonEncode(_seen.toList()));
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'runtime_translator'); }
  }

  Future<void> _persistLang(String lang) async {
    final map = _cache[lang];
    if (map == null) return;
    try {
      await _writeBlob(_langBlob(lang), jsonEncode(map));
    } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'runtime_translator'); }
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
