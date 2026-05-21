import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'error_logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  /// "Bu soruyla ilgili konuyu pekiştir" — bir defa üretilip kalıcı saklanan
  /// Study Suite JSON blob'u (benzer sorular + bilgi kartları + eşleştirme).
  /// null: henüz üretilmemiş.
  final Map<String, dynamic>? studySuite;

  /// Paylaşım için bir kez OCR ile çıkarılan soru metni (hızlı tekrar paylaşım).
  /// Boş ise henüz üretilmemiş.
  final String cachedQuestionText;

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
    this.studySuite,
    this.cachedQuestionText = '',
  });

  SolutionRecord copyWith({
    bool? isFavorite,
    String? aiTitle,
    Map<String, dynamic>? studySuite,
    String? cachedQuestionText,
  }) =>
      SolutionRecord(
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
        studySuite: studySuite ?? this.studySuite,
        cachedQuestionText: cachedQuestionText ?? this.cachedQuestionText,
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
        if (studySuite != null) 'studySuite': studySuite,
        if (cachedQuestionText.isNotEmpty)
          'cachedQuestionText': cachedQuestionText,
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
        cachedQuestionText: j['cachedQuestionText'] as String? ?? '',
        studySuite: j['studySuite'] is Map
            ? (j['studySuite'] as Map).cast<String, dynamic>()
            : null,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SolutionsStorage
// ═══════════════════════════════════════════════════════════════════════════════

class SolutionsStorage {
  static const _fileName = 'snap_nova_solutions.json';
  static const _imagesDir = 'snap_nova_images';

  // Tüm read-modify-write işlemleri bu kuyruğa girer — concurrent
  // saveOrUpdate / toggleFavorite / delete çağrıları arasında race
  // condition oluşmasını engeller. Future zincirli.
  static Future<void> _writeLock = Future.value();
  static Future<T> _serialize<T>(Future<T> Function() task) {
    final prev = _writeLock;
    final c = Completer<T>();
    _writeLock = prev.then((_) async {
      try {
        final r = await task();
        c.complete(r);
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // Tek kaydı parse et — fail olursa null döner ki dış parser onu skip
  // edebilsin. Partial recovery için kritik: tek bozuk kayıt tüm history'yi
  // uçurmasın.
  static SolutionRecord? _parseOne(dynamic raw) {
    try {
      return SolutionRecord.fromJson(raw as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[SolutionsStorage] bozuk kayıt skip: $e');
      return null;
    }
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

  /// Tüm kayıtları yükler. JSON corrupt veya tek tek kayıt bozuk olursa
  /// PARTIAL RECOVERY uygular: geçerli kayıtları döndürür, bozuk olanları
  /// atlar — kullanıcı tek byte hatası yüzünden tüm history'yi kaybetmez.
  static Future<List<SolutionRecord>> loadAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return [];
      final dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (e) {
        debugPrint('[SolutionsStorage] JSON parse fail: $e — kayıtlar boş döner');
        return [];
      }
      if (decoded is! List) return [];
      // Tek tek parse — bozuk kayıtları atla.
      final records = <SolutionRecord>[];
      for (final raw in decoded) {
        final r = _parseOne(raw);
        if (r != null) records.add(r);
      }
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return records;
    } catch (e) {
      debugPrint('[SolutionsStorage] loadAll fatal: $e');
      return [];
    }
  }

  // Yardımcı: records listesini JSON'a serialize edip dosyaya yaz.
  static Future<void> _writeAll(List<SolutionRecord> records) async {
    final f = await _file();
    await f.writeAsString(
        jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  static Future<void> saveOrUpdate(SolutionRecord record) {
    return _serialize(() async {
      try {
        final records = await loadAll();
        final idx = records.indexWhere((r) => r.id == record.id);
        if (idx >= 0) {
          records[idx] = record;
        } else {
          records.insert(0, record);
        }
        await _writeAll(records);
      } catch (e) {
        debugPrint('[SolutionsStorage] saveOrUpdate fail: $e');
      }
      unawaited(_cloudUpsert(record));
    });
  }

  static Future<void> delete(String id) {
    return _serialize(() async {
      try {
        final records = await loadAll();
        final idx = records.indexWhere((r) => r.id == id);
        if (idx < 0) return;
        final rec = records[idx];
        // ÖNCE JSON'dan çıkar + yaz — bu kritik veri. JSON yazma başarısızsa
        // resmi de silme (rollback yok ama tutarsız kalmaz). Yazma başarılıysa
        // resmi sonra sil — orphan kalsa bile cleanOrphans toparlar.
        records.removeAt(idx);
        await _writeAll(records);
        try {
          final imgFile = File(rec.imagePath);
          if (await imgFile.exists()) await imgFile.delete();
        } catch (_) {/* orphan kalsa cleanOrphans toparlar */}
      } catch (e) {
        debugPrint('[SolutionsStorage] delete fail: $e');
      }
      unawaited(_cloudDelete(id));
    });
  }

  /// Toplu silme — tek bir read+write pass'inde N kayıt siler. Bulk operasyon
  /// için N kez delete() çağırmaktan ~N× hızlı.
  static Future<void> deleteMany(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return Future.value();
    return _serialize(() async {
      try {
        final records = await loadAll();
        final toRemove = <SolutionRecord>[];
        records.removeWhere((r) {
          if (idSet.contains(r.id)) {
            toRemove.add(r);
            return true;
          }
          return false;
        });
        await _writeAll(records);
        // Resimleri arka planda sil — yarısı fail etse orphan kalır, OK.
        for (final r in toRemove) {
          try {
            final f = File(r.imagePath);
            if (await f.exists()) await f.delete();
          } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'solutions_storage'); }
        }
      } catch (e) {
        debugPrint('[SolutionsStorage] deleteMany fail: $e');
      }
      unawaited(_cloudDeleteMany(idSet));
    });
  }

  static Future<void> toggleFavorite(String id) {
    return _serialize(() async {
      SolutionRecord? updated;
      try {
        final records = await loadAll();
        final idx = records.indexWhere((r) => r.id == id);
        if (idx < 0) return;
        records[idx] =
            records[idx].copyWith(isFavorite: !records[idx].isFavorite);
        updated = records[idx];
        await _writeAll(records);
      } catch (e) {
        debugPrint('[SolutionsStorage] toggleFavorite fail: $e');
      }
      if (updated != null) unawaited(_cloudUpsert(updated));
    });
  }

  /// OCR ile çıkarılan soru metnini kaydeder (paylaşımı hızlandırmak için).
  static Future<void> saveQuestionText(String id, String questionText) {
    return _serialize(() async {
      SolutionRecord? updated;
      try {
        final records = await loadAll();
        final idx = records.indexWhere((r) => r.id == id);
        if (idx < 0) return;
        records[idx] =
            records[idx].copyWith(cachedQuestionText: questionText);
        updated = records[idx];
        await _writeAll(records);
      } catch (e) {
        debugPrint('[SolutionsStorage] saveQuestionText fail: $e');
      }
      if (updated != null) unawaited(_cloudUpsert(updated));
    });
  }

  /// Belirli bir kayda Study Suite JSON'unu kalıcı olarak yaz.
  /// Kayıt yoksa sessizce atlar.
  static Future<void> saveStudySuite(
      String id, Map<String, dynamic> suite) {
    return _serialize(() async {
      SolutionRecord? updated;
      try {
        final records = await loadAll();
        final idx = records.indexWhere((r) => r.id == id);
        if (idx < 0) return;
        records[idx] = records[idx].copyWith(studySuite: suite);
        updated = records[idx];
        await _writeAll(records);
      } catch (e) {
        debugPrint('[SolutionsStorage] saveStudySuite fail: $e');
      }
      if (updated != null) unawaited(_cloudUpsert(updated));
    });
  }

  /// Disk'te tutulan resim klasörünü tarayıp JSON'daki kayıtlarla
  /// eşleşmeyen dosyaları siler. Cache clear, copy fail, eski sürümden
  /// kalan dosyalar gibi orphan'ları temizler. Düşük öncelik — uygulama
  /// açılışında ya da manuel "Önbelleği Temizle" akışında çağrılır.
  /// Döndürdüğü sayı silinen dosya adedi.
  static Future<int> cleanOrphans() async {
    return _serialize(() async {
      int removed = 0;
      try {
        final docs = await getApplicationDocumentsDirectory();
        final dirPath = '${docs.path}/$_imagesDir';
        final dir = Directory(dirPath);
        if (!await dir.exists()) return 0;
        final records = await loadAll();
        final referenced = records
            .map((r) => r.imagePath)
            .where((p) => p.isNotEmpty)
            .toSet();
        await for (final entity in dir.list()) {
          if (entity is File && !referenced.contains(entity.path)) {
            try {
              await entity.delete();
              removed++;
            } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'solutions_storage'); }
          }
        }
      } catch (e) {
        debugPrint('[SolutionsStorage] cleanOrphans fail: $e');
      }
      return removed;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  CLOUD SYNC — users/{uid}/solutions/{id} koleksiyonu.
  //
  //  ŞEMA: meta-only sync. Resim dosyası (imagePath) yerel/cihaza özel kalır;
  //  cloud doc'unda sadece "image" flag'i var. Yeni cihaza geçince çözüm
  //  metni + Q&A + studySuite geri yüklenir; resim "📷 cihazda yok" olarak
  //  gösterilir (kullanıcı çözüm metnine ulaşır ama eski fotoğraf görmez).
  //
  //  Auth yoksa veya offline → sessizce no-op. Yerel her zaman kaynak.
  // ═══════════════════════════════════════════════════════════════════════════

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static Future<void> _cloudUpsert(SolutionRecord r) async {
    try {
      final uid = _uid;
      if (uid == null) return;
      final payload = <String, dynamic>{
        ...r.toJson(),
        // Resim yolu cihaza özel — cloud'da sadece "var mı yok mu" flag.
        'hasImage': r.imagePath.isNotEmpty,
        'imagePath': '', // cihaz değişince geçersiz; boş yaz
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('solutions')
          .doc(r.id)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SolutionsStorage] cloud upsert fail: $e');
    }
  }

  static Future<void> _cloudDelete(String id) async {
    try {
      final uid = _uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('solutions')
          .doc(id)
          .delete();
    } catch (e) {
      debugPrint('[SolutionsStorage] cloud delete fail: $e');
    }
  }

  static Future<void> _cloudDeleteMany(Set<String> ids) async {
    try {
      final uid = _uid;
      if (uid == null || ids.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('solutions');
      for (final id in ids) {
        batch.delete(col.doc(id));
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[SolutionsStorage] cloud deleteMany fail: $e');
    }
  }

  /// Yerel JSON boşsa cloud'dan geri yükle — telefon değişti / uygulama
  /// silindi senaryosu. Resimler geri gelmez ama çözüm metinleri tam döner.
  /// Bootstrap'tan sonra çağrılır.
  ///
  /// Döndürdüğü değer: restore edilen kayıt sayısı (0 → restore yapılmadı).
  static Future<int> restoreFromCloudIfEmpty() async {
    return _serialize(() async {
      try {
        final local = await loadAll();
        if (local.isNotEmpty) return 0;
        final uid = _uid;
        if (uid == null) return 0;
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('solutions')
            .orderBy('timestamp', descending: true)
            .limit(500) // koruma — Firestore okuma maliyeti
            .get();
        if (snap.docs.isEmpty) return 0;
        final restored = <SolutionRecord>[];
        for (final d in snap.docs) {
          final m = d.data();
          // imagePath yerel/cihaza özel; cloud'da boş kalmış olabilir.
          // Boş bırakırsak UI "fotoğraf yok" gösterir, sorun değil.
          try {
            restored.add(SolutionRecord.fromJson(
              Map<String, dynamic>.from(m),
            ));
          } catch (e) {
            debugPrint('[SolutionsStorage] cloud parse fail: $e');
          }
        }
        if (restored.isEmpty) return 0;
        await _writeAll(restored);
        debugPrint(
            '[SolutionsStorage] cloud restore: ${restored.length} kayıt');
        return restored.length;
      } catch (e) {
        debugPrint('[SolutionsStorage] cloud restore fail: $e');
        return 0;
      }
    });
  }

  /// Belirli bir kayda kayıtlı Study Suite varsa getirir, yoksa null.
  static Future<Map<String, dynamic>?> loadStudySuite(String id) async {
    try {
      final records = await loadAll();
      final rec = records.firstWhere(
        (r) => r.id == id,
        orElse: () => SolutionRecord(
          id: '',
          imagePath: '',
          solutionType: '',
          result: '',
          qaList: const [],
          subject: '',
          timestamp: DateTime.now(),
        ),
      );
      if (rec.id.isEmpty) return null;
      return rec.studySuite;
    } catch (_) {
      return null;
    }
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
