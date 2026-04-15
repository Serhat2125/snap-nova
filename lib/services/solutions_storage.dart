import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Veri modelleri
// ═══════════════════════════════════════════════════════════════════════════════

class QARecord {
  final String question;
  final String answer;
  const QARecord({required this.question, required this.answer});

  Map<String, dynamic> toJson() => {'q': question, 'a': answer};

  factory QARecord.fromJson(Map<String, dynamic> j) =>
      QARecord(question: j['q'] as String, answer: j['a'] as String);
}

class SolutionRecord {
  final String id;
  final String imagePath;
  final String solutionType;
  final String modelName;
  final String result;
  final List<QARecord> qaList;
  final String subject;
  /// AI tarafından üretilen başlık (örn: "Fizik - Kuvvet ve Hareket").
  /// Eski kayıtlarda boş olabilir.
  final String aiTitle;
  final DateTime timestamp;
  final bool isFavorite;

  SolutionRecord({
    required this.id,
    required this.imagePath,
    required this.solutionType,
    this.modelName = 'QuAlsar',
    required this.result,
    required this.qaList,
    required this.subject,
    this.aiTitle = '',
    required this.timestamp,
    this.isFavorite = false,
  });

  SolutionRecord copyWith({bool? isFavorite, String? aiTitle}) => SolutionRecord(
        id: id,
        imagePath: imagePath,
        solutionType: solutionType,
        modelName: modelName,
        result: result,
        qaList: qaList,
        subject: subject,
        aiTitle: aiTitle ?? this.aiTitle,
        timestamp: timestamp,
        isFavorite: isFavorite ?? this.isFavorite,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'solutionType': solutionType,
        'modelName': modelName,
        'result': result,
        'qaList': qaList.map((q) => q.toJson()).toList(),
        'subject': subject,
        'aiTitle': aiTitle,
        'timestamp': timestamp.toIso8601String(),
        'isFavorite': isFavorite,
      };

  factory SolutionRecord.fromJson(Map<String, dynamic> j) => SolutionRecord(
        id: j['id'] as String,
        imagePath: j['imagePath'] as String,
        solutionType: j['solutionType'] as String,
        modelName: j['modelName'] as String? ?? 'QuAlsar',
        result: j['result'] as String,
        qaList: (j['qaList'] as List)
            .map((e) => QARecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        subject: j['subject'] as String,
        aiTitle: j['aiTitle'] as String? ?? '',
        timestamp: DateTime.parse(j['timestamp'] as String),
        isFavorite: j['isFavorite'] as bool? ?? false,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SolutionsStorage
// ═══════════════════════════════════════════════════════════════════════════════

class SolutionsStorage {
  static const _fileName = 'snap_nova_solutions.json';
  static const _imagesDir = 'snap_nova_images';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Geçici kamera/galeri fotoğrafını kalıcı uygulama klasörüne kopyalar.
  /// Zaten kalıcı klasördeyse olduğu gibi döner.
  static Future<String> persistImage(String srcPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dirPath = '${docs.path}/$_imagesDir';
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (srcPath.startsWith(dirPath)) return srcPath;
      final src = File(srcPath);
      if (!await src.exists()) return srcPath;
      final ext = srcPath.contains('.')
          ? srcPath.substring(srcPath.lastIndexOf('.'))
          : '.jpg';
      final dstPath =
          '$dirPath/${DateTime.now().millisecondsSinceEpoch}_${src.hashCode}$ext';
      await src.copy(dstPath);
      return dstPath;
    } catch (_) {
      return srcPath;
    }
  }

  static Future<List<SolutionRecord>> loadAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final raw = await f.readAsString();
      final list = jsonDecode(raw) as List;
      final records = list
          .map((e) => SolutionRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return records;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveOrUpdate(SolutionRecord record) async {
    try {
      final records = await loadAll();
      final idx = records.indexWhere((r) => r.id == record.id);
      if (idx >= 0) {
        records[idx] = record;
      } else {
        records.insert(0, record);
      }
      final f = await _file();
      await f.writeAsString(
          jsonEncode(records.map((r) => r.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> delete(String id) async {
    try {
      final records = await loadAll();
      final idx = records.indexWhere((r) => r.id == id);
      if (idx >= 0) {
        final rec = records[idx];
        try {
          final imgFile = File(rec.imagePath);
          if (await imgFile.exists()) await imgFile.delete();
        } catch (_) {}
        records.removeAt(idx);
      }
      final f = await _file();
      await f.writeAsString(
          jsonEncode(records.map((r) => r.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> toggleFavorite(String id) async {
    try {
      final records = await loadAll();
      final idx = records.indexWhere((r) => r.id == id);
      if (idx < 0) return;
      records[idx] = records[idx].copyWith(isFavorite: !records[idx].isFavorite);
      final f = await _file();
      await f.writeAsString(
          jsonEncode(records.map((r) => r.toJson()).toList()));
    } catch (_) {}
  }

  /// AI çıktısının en başındaki `[Ders: X]` etiketini yakala.
  /// Etiket yoksa boş string döner.
  static String extractDersTag(String text) {
    final match = RegExp(
      r'^\s*\[\s*Ders\s*:\s*([^\]\n]+)\s*\]',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return '';
    return match.group(1)?.trim() ?? '';
  }

  /// AI etiketindeki ders adını bilinen kategorilerden birine eşle.
  static String _normalizeSubject(String raw) {
    final t = raw.toLowerCase();
    if (t.contains('matemat'))  return 'Matematik';
    if (t.contains('fizik'))    return 'Fizik';
    if (t.contains('kimya'))    return 'Kimya';
    if (t.contains('biyolo'))   return 'Biyoloji';
    if (t.contains('coğraf') || t.contains('cograf')) return 'Coğrafya';
    if (t.contains('tarih'))    return 'Tarih';
    if (t.contains('edebiyat') || t.contains('türkçe') || t.contains('turkce')) {
      return 'Edebiyat';
    }
    if (t.contains('felsefe'))  return 'Felsefe';
    if (t.contains('ingiliz') || t.contains('english')) return 'İngilizce';
    return 'Diğer';
  }

  /// Çözüm metninden dersi belirle: önce `[Ders: ...]` etiketi, olmazsa
  /// anahtar kelimeyle fallback.
  static String detectSubjectSmart(String text) {
    final tag = extractDersTag(text);
    if (tag.isNotEmpty) return _normalizeSubject(tag);
    return detectSubject(text);
  }

  /// Çözüm metninden ders kategorisini tahmin et.
  static String detectSubject(String text) {
    final t = text.toLowerCase();
    int score(List<String> kw) => kw.where((k) => t.contains(k)).length;

    final scores = <String, int>{
      'Matematik': score([
        'sin', 'cos', 'tan', 'π', '√', '∫', 'lim', 'türev', 'integral',
        'denklem', 'logaritm', 'log', 'matris', 'vektör', 'kombinasyon',
        'permütasyon', 'olasılık', 'geometri', 'pisagor', 'trigonometri',
        'hipotenüs', 'karekök', 'faktöriyel', 'oran', 'kesir', 'sayı',
        'toplam', 'çarpım', 'bölüm', 'kesiştirme', 'fonksiyon', 'grafik',
        'eşitsizlik', 'mutlak değer', 'seri', 'dizisi',
      ]),
      'Fizik': score([
        'newton', 'hız', 'ivme', 'kuvvet', 'enerji', 'joule', 'watt',
        'volt', 'ampere', 'ohm', 'manyetik', 'elektrik', 'ışık', 'optik',
        'dalga', 'frekans', 'kütle', 'momentum', 'sürtünme', 'yerçekimi',
        'basınç', 'kinetik', 'potansiyel', 'atalet', 'm/s', 'yoğunluk',
        'kaldırma', 'akım', 'direnç', 'kondansatör', 'manyetizma',
      ]),
      'Kimya': score([
        'mol', 'atom', 'molekül', 'element', 'bileşik', 'reaksiyon',
        'asit', 'baz', 'ph', 'elektron', 'proton', 'nötron', 'periyodik',
        'denge', 'çözünürlük', 'hidroliz', 'oksidasyon', 'h₂', 'h2o',
        'kimyasal', 'madde', 'karışım', 'çözelti', 'konsantrasyon',
        'tuz', 'yanma', 'redoks', 'elektroliz',
      ]),
      'Biyoloji': score([
        'hücre', 'dna', 'rna', 'protein', 'gen', 'kromozom', 'fotosentez',
        'mitoz', 'mayoz', 'enzim', 'hormon', 'sinir', 'beyin', 'evrim',
        'metabolizma', 'organizma', 'canlı', 'bitki', 'hayvan', 'bakteri',
        'virüs', 'ekosistem', 'biyolojik', 'kalıtım', 'fenotip', 'genotip',
      ]),
      'Coğrafya': score([
        'iklim', 'harita', 'enlem', 'boylam', 'kıta', 'okyanus', 'dağ',
        'nehir', 'göl', 'ova', 'nüfus', 'yerleşim', 'toprak', 'erozyon',
        'deprem', 'volkan', 'coğrafya', 'bölge', 'yeryüzü', 'atmosfer',
        'türkiye', 'anadolu', 'akdeniz', 'karadeniz', 'ege', 'doğu',
        'batı', 'kuzey', 'güney', 'koordinat', 'meridyen', 'paralel',
        'rüzgar', 'yağış', 'sıcaklık', 'bitki örtüsü', 'orman', 'çöl',
        'step', 'tundra', 'taiga',
      ]),
      'Tarih': score([
        'osmanlı', 'cumhuriyet', 'atatürk', 'savaş', 'devlet', 'imparatorluk',
        'medeniyet', 'tarih', 'yüzyıl', 'dönem', 'hanedanlık', 'padişah',
        'sultan', 'antlaşma', 'anayasa', 'devrim', 'isyan', 'fetih',
        'rönesans', 'reform', 'aydınlanma', 'fransız', 'endüstri devrimi',
        'birinci dünya', 'ikinci dünya', 'soğuk savaş', 'inkılap',
        'kurtuluş savaşı', 'lozan', 'sevr', 'mondros', 'malazgirt',
        'selçuklu', 'bizans', 'roma', 'yunan', 'antik',
      ]),
      'Edebiyat': score([
        'şiir', 'roman', 'hikaye', 'hikâye', 'edebiyat', 'yazar', 'şair',
        'eser', 'divan', 'nazım', 'nesir', 'tür', 'vezin', 'uyak', 'kafiye',
        'aruz', 'hece', 'akım', 'realizm', 'romantizm', 'klasisizm',
        'tanzimat', 'servet-i fünun', 'milli edebiyat', 'cumhuriyet',
        'dil', 'anlam', 'mecaz', 'istiare', 'teşbih', 'tümce', 'cümle',
        'paragraf', 'metin', 'ek', 'fiil', 'özne', 'nesne', 'dilbilgisi',
        'türkçe', 'noktalama', 'yazım', 'imla',
      ]),
      'Felsefe': score([
        'felsefe', 'filozof', 'etik', 'ahlak', 'mantık', 'epistemoloji',
        'ontoloji', 'metafizik', 'varoluş', 'bilinç', 'özgür irade',
        'sokrates', 'platon', 'aristoteles', 'kant', 'hegel', 'nietzsche',
        'descartes', 'empirizm', 'rasyonalizm', 'idealizm', 'materyalizm',
        'felsefi', 'düşünce', 'bilgi', 'doğruluk', 'gerçeklik',
      ]),
      'İngilizce': score([
        'tense', 'grammar', 'verb', 'noun', 'adjective', 'adverb',
        'sentence', 'subject', 'object', 'clause', 'vocabulary',
        'present', 'past', 'future', 'perfect', 'continuous',
        'passive', 'active', 'modal', 'conditional', 'relative',
        'the', 'a ', ' an ', ' is ', ' are ', ' was ', ' were ',
        'english', 'ingilizce',
      ]),
    };

    final best = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value == 0 ? 'Diğer' : best.key;
  }
}
