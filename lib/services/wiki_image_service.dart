// Wikipedia REST API üzerinden konuyla ilgili görsel URL'sini çeker.
// Anahtarsız, ücretsiz, 290+ dil. Konu sayfasının ana thumbnail'ini döner.
//
// Kullanım:
//   final url = await WikiImageService.fetchImageUrl('Fotosentez', lang: 'tr');
//   if (url != null) Image.network(url);
//
// Endpoint: https://{lang}.wikipedia.org/api/rest_v1/page/summary/{topic}
// Yanıtın `thumbnail.source` alanı kullanılır (genellikle 320×… JPG).
//
// Çok katmanlı sorgu fallback'i:
//   1) Kullanıcı dilinde tam ifade
//   2) Decorator kelimeler atılmış sade ifade ("saf madde hal değişim grafiği"
//      → "hal değişim", "faz diyagramı")
//   3) TR/sözlük → EN bilimsel terim eşleştirmesi
//   4) İngilizce Wikipedia (sadece çevrilmiş terimle)
//   5) Wikipedia search API ile en yakın eşleşme

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WikiImageService {
  WikiImageService._();

  /// Process içi cache: '{lang}|{query}' → url ya da null (eşleşme yok).
  /// Aynı konu tekrar sorulduğunda ağa gitmez.
  static final Map<String, String?> _cache = {};

  /// Eğitim terimlerinde sık görülen "decorator" kelimeler. Sorgu Wikipedia'da
  /// bulunamazsa bu kelimeler atılarak çekirdek terim aranır.
  /// Örn: "saf madde hal değişim grafiği" → "hal değişim"
  static const List<String> _trDecorators = [
    'grafiği', 'grafik',
    'şeması', 'şema',
    'diyagramı', 'diyagram',
    'modeli', 'model',
    'tablosu', 'tablo',
    'haritası', 'harita',
    'formülü', 'formül',
    'denklemi', 'denklem',
    'yapısı', 'yapı',
    'kuralı', 'kural',
    'yasası', 'yasa',
    'kanunu', 'kanun',
    'ilkesi', 'ilke',
    'teorisi', 'teori',
    'döngüsü', 'döngü',
    'sistemi', 'sistem',
    'reaksiyonu', 'reaksiyon',
    'tepkimesi', 'tepkime',
    'olayı', 'olay',
    'süreci', 'süreç',
    'periyodu', 'periyod',
    'saf', 'temel', 'genel', 'tipik',
    've', 'ile', 'arası', 'arasındaki',
  ];

  /// İngilizce için decorator'lar.
  static const List<String> _enDecorators = [
    'diagram', 'graph', 'chart', 'scheme', 'schema',
    'formula', 'equation', 'cycle', 'theory', 'law',
    'principle', 'rule', 'process', 'reaction',
    'pure', 'simple', 'basic', 'general', 'typical',
    'and', 'with', 'between',
  ];

  /// Eğitim müfredatında sık geçen TR → EN bilimsel terim eşleştirmesi.
  /// Wikipedia İngilizce sayfa adıyla birebir uyumlu. Sorgu hem TR hem
  /// sade haliyle başarısız olursa burada aranır → varsa İngilizce
  /// Wikipedia'ya bu çevrilmiş haliyle gidilir.
  static const Map<String, String> _trToEnConcept = {
    // Kimya — fazlar, hal değişimi
    'hal değişim': 'Phase transition',
    'hal değişimi': 'Phase transition',
    'faz diyagramı': 'Phase diagram',
    'faz geçişi': 'Phase transition',
    'maddenin halleri': 'State of matter',
    'erime': 'Melting',
    'donma': 'Freezing',
    'kaynama': 'Boiling',
    'buharlaşma': 'Evaporation',
    'yoğunlaşma': 'Condensation',
    'süblimleşme': 'Sublimation',
    'kırağılaşma': 'Deposition',
    // Kimya — atom, bağ, reaksiyon
    'atom modeli': 'Bohr model',
    'bohr atom modeli': 'Bohr model',
    'periyodik tablo': 'Periodic table',
    'kovalent bağ': 'Covalent bond',
    'iyonik bağ': 'Ionic bond',
    'metalik bağ': 'Metallic bonding',
    'asit baz': 'Acid–base reaction',
    'redoks': 'Redox',
    'elektroliz': 'Electrolysis',
    // Fizik
    'kuvvet diyagramı': 'Free body diagram',
    'serbest cisim diyagramı': 'Free body diagram',
    'newton yasaları': "Newton's laws of motion",
    'kepler yasaları': "Kepler's laws of planetary motion",
    'ohm yasası': "Ohm's law",
    'elektrik devresi': 'Electrical network',
    'manyetik alan': 'Magnetic field',
    'elektromanyetik dalga': 'Electromagnetic radiation',
    'dalga': 'Wave',
    'doppler etkisi': 'Doppler effect',
    'yansıma': 'Reflection (physics)',
    'kırılma': 'Refraction',
    'mercek': 'Lens',
    // Biyoloji
    'hücre': 'Cell (biology)',
    'hayvan hücresi': 'Animal cell',
    'bitki hücresi': 'Plant cell',
    'mitokondri': 'Mitochondrion',
    'kloroplast': 'Chloroplast',
    'ribozom': 'Ribosome',
    'çekirdek': 'Cell nucleus',
    'mitoz': 'Mitosis',
    'mayoz': 'Meiosis',
    'fotosentez': 'Photosynthesis',
    'solunum': 'Cellular respiration',
    'dna': 'DNA',
    'rna': 'RNA',
    'protein sentezi': 'Protein biosynthesis',
    'ekosistem': 'Ecosystem',
    'besin zinciri': 'Food chain',
    'sinir sistemi': 'Nervous system',
    'dolaşım sistemi': 'Circulatory system',
    'sindirim sistemi': 'Human digestive system',
    'solunum sistemi': 'Respiratory system',
    'kalp': 'Heart',
    'beyin': 'Brain',
    'göz': 'Human eye',
    // Matematik
    'pisagor teoremi': 'Pythagorean theorem',
    'türev': 'Derivative',
    'integral': 'Integral',
    'limit': 'Limit (mathematics)',
    'fonksiyon': 'Function (mathematics)',
    'parabol': 'Parabola',
    'çember': 'Circle',
    'üçgen': 'Triangle',
    'matris': 'Matrix (mathematics)',
    'logaritma': 'Logarithm',
    'olasılık': 'Probability',
    // Coğrafya / Yer Bilimleri
    'levha tektoniği': 'Plate tectonics',
    'volkan': 'Volcano',
    'deprem': 'Earthquake',
    'su döngüsü': 'Water cycle',
    'iklim': 'Climate',
    'atmosfer': 'Atmosphere of Earth',
    'rüzgar': 'Wind',
    'okyanus akıntısı': 'Ocean current',
    // Tarih (örnek — birkaçı)
    'fransız ihtilali': 'French Revolution',
    'sanayi devrimi': 'Industrial Revolution',
  };

  /// Konuyla ilgili Wikipedia thumbnail görselini çeker.
  /// Sorgu doğrudan bulunamazsa decorator kelimeleri atıp sadeleştirir,
  /// sonra TR→EN bilimsel terim sözlüğünden çeviri ile İngilizce'yi dener,
  /// son çare olarak Wikipedia search API'sinden en yakın eşleşmeyi alır.
  /// Hata/boş sonuçta null → UI metin-only fallback gösterir.
  static Future<String?> fetchImageUrl(
    String query, {
    String lang = 'tr',
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final cleaned = _normalizeQuery(query);
    if (cleaned.isEmpty) return null;
    final cacheKey = '$lang|$cleaned';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    // 1) Tam sorgu — kullanıcı dilinde
    final primary = await _fetchOne(cleaned, lang, timeout);
    if (primary != null) {
      _cache[cacheKey] = primary;
      return primary;
    }

    // 2) Sadeleştirilmiş sorgu — decorator kelimeler atılmış
    final simplified = _simplify(cleaned, lang);
    if (simplified.isNotEmpty &&
        simplified.toLowerCase() != cleaned.toLowerCase()) {
      final s = await _fetchOne(simplified, lang, timeout);
      if (s != null) {
        _cache[cacheKey] = s;
        return s;
      }
    }

    // 3) TR→EN bilimsel terim sözlüğü (Türkçe sorgular için)
    if (lang == 'tr') {
      final mapped = _mapTurkishToEnglish(cleaned, simplified);
      if (mapped != null) {
        final m = await _fetchOne(mapped, 'en', timeout);
        if (m != null) {
          _cache[cacheKey] = m;
          return m;
        }
      }
    }

    // 4) İngilizce Wikipedia — orijinal sorguyla (yabancı isimler için)
    if (lang != 'en') {
      final enKey = 'en|$cleaned';
      if (_cache.containsKey(enKey)) {
        final v = _cache[enKey];
        _cache[cacheKey] = v;
        return v;
      }
      final en = await _fetchOne(cleaned, 'en', timeout);
      if (en != null) {
        _cache[enKey] = en;
        _cache[cacheKey] = en;
        return en;
      }
      // 4b) İngilizce + sadeleştirilmiş
      if (simplified.isNotEmpty &&
          simplified.toLowerCase() != cleaned.toLowerCase()) {
        final ens = await _fetchOne(simplified, 'en', timeout);
        if (ens != null) {
          _cache[cacheKey] = ens;
          return ens;
        }
      }
    }

    // 5) Son çare: Wikipedia search API → en yakın sayfayı bul, oradan al
    final searched = await _searchAndFetch(cleaned, lang, timeout);
    if (searched != null) {
      _cache[cacheKey] = searched;
      return searched;
    }
    if (lang != 'en' && simplified.isNotEmpty) {
      final searchedEn = await _searchAndFetch(simplified, 'en', timeout);
      if (searchedEn != null) {
        _cache[cacheKey] = searchedEn;
        return searchedEn;
      }
    }

    _cache[cacheKey] = null;
    return null;
  }

  static Future<String?> _fetchOne(
      String query, String lang, Duration timeout) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final uri =
          Uri.parse('https://$lang.wikipedia.org/api/rest_v1/page/summary/$encoded');
      final res = await http.get(uri, headers: {
        'accept': 'application/json',
        'user-agent': 'QuAlsar/1.0 (educational app)',
      }).timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes))
          as Map<String, dynamic>;
      // disambiguation veya not_found tipi yanıtlar — image yok kabul et.
      final type = body['type'] as String?;
      if (type == 'disambiguation' || type == 'no-extract') return null;
      // Daha büyük görsel için originalimage > thumbnail önceliği.
      final original = body['originalimage'] as Map<String, dynamic>?;
      final orig = original?['source'] as String?;
      if (orig != null && orig.isNotEmpty) return orig;
      final thumb = body['thumbnail'] as Map<String, dynamic>?;
      return thumb?['source'] as String?;
    } on TimeoutException {
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('WikiImageService($lang/$query): $e');
      return null;
    }
  }

  /// Wikipedia OpenSearch ile en yakın sayfa adını bulup onun thumbnail'ini al.
  /// Doğrudan eşleşmeyen, "saf madde hal değişim grafiği" gibi uzun ifadeler
  /// için son çare — Wikipedia'nın kendi tam metin araması en yakını döndürür.
  static Future<String?> _searchAndFetch(
      String query, String lang, Duration timeout) async {
    try {
      final encoded = Uri.encodeQueryComponent(query);
      final uri = Uri.parse(
          'https://$lang.wikipedia.org/w/api.php?action=opensearch&format=json&limit=1&search=$encoded');
      final res = await http.get(uri, headers: {
        'accept': 'application/json',
        'user-agent': 'QuAlsar/1.0 (educational app)',
      }).timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      // Yanıt: [query, [titles], [descs], [urls]]
      if (body is! List || body.length < 2) return null;
      final titles = body[1];
      if (titles is! List || titles.isEmpty) return null;
      final firstTitle = titles.first?.toString() ?? '';
      if (firstTitle.isEmpty) return null;
      // Ana fetch'e dön — bu sefer doğru sayfa adıyla.
      return await _fetchOne(firstTitle, lang, timeout);
    } on TimeoutException {
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('WikiSearch($lang/$query): $e');
      return null;
    }
  }

  /// Sorguyu Wikipedia'nın URL formatına uyumlu hale getir — fazla
  /// boşlukları temizle, baş/son noktalama at, "—" ve kapanış işaretlerini sök.
  static String _normalizeQuery(String q) {
    var t = q.trim();
    t = t.replaceAll(RegExp(r'^[\s\-—–:•▸*]+'), '');
    t = t.replaceAll(RegExp(r'[\s\-—–:•▸*]+$'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  /// Decorator kelimeleri atarak çekirdek terimi çıkar. Sonuç boşsa
  /// orijinali döner. Örn: "saf madde hal değişim grafiği" → "hal değişim".
  static String _simplify(String q, String lang) {
    final decorators = lang == 'tr' ? _trDecorators : _enDecorators;
    final decoratorSet = decorators.map((e) => e.toLowerCase()).toSet();
    final words = q.split(RegExp(r'\s+'));
    final kept = <String>[];
    for (final w in words) {
      final lower = w.toLowerCase();
      // Tam eşleşme veya kelime sonu eşleşmesi (Türkçede ekli haliyle de)
      if (decoratorSet.contains(lower)) continue;
      kept.add(w);
    }
    final out = kept.join(' ').trim();
    return out;
  }

  /// TR→EN sözlükten kavram çevirisi. Hem tam sorgu hem sadeleştirilmiş
  /// sorgu için arar — bulamazsa null.
  static String? _mapTurkishToEnglish(String full, String simplified) {
    final fLower = full.toLowerCase();
    if (_trToEnConcept.containsKey(fLower)) return _trToEnConcept[fLower];
    final sLower = simplified.toLowerCase();
    if (_trToEnConcept.containsKey(sLower)) return _trToEnConcept[sLower];
    // Kısmi eşleşme — sözlükteki anahtar tam sorgunun içinde geçiyorsa
    for (final entry in _trToEnConcept.entries) {
      if (fLower.contains(entry.key)) return entry.value;
    }
    return null;
  }
}
