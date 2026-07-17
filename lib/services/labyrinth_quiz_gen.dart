// ═══════════════════════════════════════════════════════════════════════════
//  LabyrinthQuizGen — Bilgi Labirenti oyunu için sınav-özel soru üretimi.
//
//  Kullanıcı oyunda bir SINAV (LGS/TYT/AYT/DGS/KPSS…) + ders + konu seçince,
//  uygulamanın AI motoruyla o seçime ÖZEL çoktan seçmeli sorular üretilir ve
//  oyuna (WebView) `window.__externalQuestions` olarak enjekte edilir. Oyunun
//  kendi soru formatı {q, opts[], a} ile birebir uyumlu üretilir.
//
//  Şık sayısı sınavın optionCount'una göre (LGS 4, TYT/AYT/DGS/KPSS 5).
//  Üretim başarısızsa (offline / premium değil / AI hata) boş liste döner;
//  bu durumda oyun kendi statik bankasıyla oynanır.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../widgets/exam_mode_widgets.dart' show ExamModeSelection;
import 'curriculum_catalog.dart' show CurriculumSubject;
import 'exam_catalog.dart' show ExamDefinition;
import 'gemini_service.dart';

class LabyrinthQuizGen {
  LabyrinthQuizGen._();

  /// OFFLINE (sınıf): assets/labirent_content dizinindeki `level-grade.json`.
  /// Lise'de alan (Sayısal/Sözel/Eşit Ağırlık) seçilmişse önce alana özel
  /// `lise-<grade>-<alan>.json` denenir (varsa 11/12), yoksa temel sınıfa düşer.
  static Future<Map<String, dynamic>?> loadBundled(String level, int grade,
      {String? track}) async {
    final suffix = _trackSuffix(track);
    if (suffix != null) {
      final t = await _loadBundledStem('$level-$grade-$suffix');
      if (t != null) return t;
    }
    return _loadBundledStem('$level-$grade');
  }

  /// Alan etiketi → dosya son eki (Türkiye lise alanları).
  static String? _trackSuffix(String? track) {
    switch (track) {
      case 'Sayısal':
        return 'sayisal';
      case 'Sözel':
        return 'sozel';
      case 'Eşit Ağırlık':
        return 'ea';
    }
    return null;
  }

  /// OFFLINE (sınav): assets/labirent_content dizinindeki `exam-<key>.json`
  /// (ör. exam-lgs, exam-ayt_sayisal, exam-kpss_lisans).
  static Future<Map<String, dynamic>?> loadBundledExam(String examKey) =>
      _loadBundledStem('exam-$examKey');

  /// Bake edilmiş bir içerik dosyasını (≥100 soru + ≥100 bilgi) yükler.
  /// Bulunursa `{questions, facts}` döner; yoksa null (o zaman AI'ya düşülür).
  static Future<Map<String, dynamic>?> _loadBundledStem(String stem) async {
    try {
      final raw =
          await rootBundle.loadString('assets/labirent_content/$stem.json');
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final qs = <Map<String, dynamic>>[];
      for (final e in (j['questions'] as List? ?? const [])) {
        if (e is! Map) continue;
        final opts =
            (e['opts'] as List? ?? const []).map((x) => x.toString()).toList();
        if (opts.length < 3) continue;
        var a = (e['a'] is int) ? e['a'] as int : int.tryParse('${e['a']}') ?? 0;
        if (a < 0 || a >= opts.length) a = 0;
        qs.add({
          'q': (e['q'] ?? '').toString(),
          'opts': opts,
          'a': a,
          'sol': (e['sol'] ?? '').toString(),
          'type': 'multi',
        });
      }
      final facts = (j['facts'] as List? ?? const [])
          .map((e) => e.toString())
          .where((f) => f.trim().isNotEmpty)
          .toList();
      if (qs.isEmpty) return null;
      return {'questions': qs, 'facts': facts};
    } catch (_) {
      return null;
    }
  }

  /// Seçime göre oyun formatında sorular üretir: [{q, opts:[...], a, sol}].
  static Future<List<Map<String, dynamic>>> generate({
    required ExamModeSelection sel,
    int count = 24,
  }) async {
    final exam = sel.exam;
    final subject = sel.subject;
    final topic = sel.topic;
    final optCount = exam.optionCount.clamp(3, 5);
    final letters =
        List.generate(optCount, (i) => String.fromCharCode(65 + i)).join(', ');

    final prompt = '''
[SINAV SORU ÜRETİMİ — $count SORU · JSON]
Sınav: ${exam.displayName}
Ders: ${subject.displayName}
Konu: ${topic ?? 'Tüm konular'}

GÖREV: ${exam.displayName} sınavı formatında, yalnızca "${subject.displayName}"
dersinden TAM $count adet ÇOKTAN SEÇMELİ soru üret. Her soru $optCount şıklı.

SADECE geçerli bir JSON array döndür — başka metin/markdown/emoji başlık YOK:
[{"q":"soru kökü — net, kendi başına anlaşılır","opts":["şık1", ... $optCount adet],"a":0,"sol":"kısa adım adım çözüm"}]

KURALLAR:
• TAM $count soru; her birinde tam $optCount şık ($letters).
• "a": doğru şıkkın 0-tabanlı indeksi (0..${optCount - 1}).
• Tek tartışmasız doğru cevap; çeldiriciler tipik öğrenci hatalarından.
• Sorular ${exam.displayName} seviyesine ve müfredatına uygun, öğretici, kaliteli.
• MATEMATİK/KİMYA/FİZİK gösterimi DÜZ UNICODE: alt indis ₀-₉ (H₂O, CO₂),
  üst indis ²/³ (x²), ok →, çarpım ×, bölme ÷, ± ≤ ≥ ≠ π √. LaTeX YOK
  (\\text, \\(, \\), _2, ^2, \$ işareti YOK).
• TR ondalık virgül. Markdown yıldız (**) / başlık (#) YOK.
• Çıktın tek başına geçerli bir JSON array olmalı.
''';

    return _run(prompt, subject.displayName, optCount, count);
  }

  /// SINAV modu (çoklu ders): seçilen ders(ler) için — KONU seçilmez, seçilen
  /// dersin TÜM konularından — soru üretir. Tek ders de çoklu ders de olur.
  static Future<List<Map<String, dynamic>>> generateForExam({
    required ExamDefinition exam,
    required List<CurriculumSubject> subjects,
    int count = 24,
  }) async {
    if (subjects.isEmpty) return const [];
    final per = (count / subjects.length).ceil();
    final out = <Map<String, dynamic>>[];
    for (final s in subjects) {
      final qs = await generate(
        sel: ExamModeSelection(exam: exam, subject: s, topic: null),
        count: per,
      );
      out.addAll(qs);
    }
    return out.take(count).toList();
  }

  /// SINIF modu: seçilen seviye + sınıf (+ lise alanı) için o sınıfa uygun
  /// KARIŞIK derslerden sorular üretir. Şık sayısı seviyeye göre:
  /// ilkokul 3, ortaokul 4, lise ve üstü 5.
  ///  [level] 'ilkokul' | 'ortaokul' | 'lise'
  ///  [grade] 1..12
  ///  [track] lise için 'Sayısal' | 'Sözel' | 'Eşit Ağırlık' (yoksa null)
  static Future<List<Map<String, dynamic>>> generateForClass({
    required String level,
    required int grade,
    String? track,
    int count = 24,
  }) async {
    final optCount = level == 'ilkokul'
        ? 3
        : level == 'ortaokul'
            ? 4
            : 5;
    final letters =
        List.generate(optCount, (i) => String.fromCharCode(65 + i)).join(', ');
    final levelName = level == 'ilkokul'
        ? 'İlkokul'
        : level == 'ortaokul'
            ? 'Ortaokul'
            : 'Lise';
    final trackLine = (track != null && track.trim().isNotEmpty)
        ? '\nAlan: $track (bu alanın ağırlıklı derslerinden sor).'
        : '';
    // Alana göre ders vurgusu.
    final subjectsHint = () {
      if (level == 'ilkokul') {
        return 'Türkçe, Matematik, Hayat Bilgisi/Fen, temel Sosyal Bilgiler';
      }
      if (level == 'ortaokul') {
        return 'Matematik, Fen Bilimleri, Türkçe, Sosyal Bilgiler, İngilizce';
      }
      switch (track) {
        case 'Sayısal':
          return 'Matematik, Fizik, Kimya, Biyoloji';
        case 'Sözel':
          return 'Türk Dili ve Edebiyatı, Tarih, Coğrafya, Felsefe';
        case 'Eşit Ağırlık':
          return 'Matematik, Türk Dili ve Edebiyatı, Tarih, Coğrafya';
        default:
          return 'Matematik, Fizik, Kimya, Biyoloji, Edebiyat, Tarih, Coğrafya';
      }
    }();

    final prompt = '''
[SINIF SORU ÜRETİMİ — $count SORU · JSON]
Seviye: $levelName $grade. sınıf$trackLine
Dersler: $subjectsHint

GÖREV: $grade. sınıf seviyesine ve müfredatına uygun, yukarıdaki derslerden
KARIŞIK olarak TAM $count adet ÇOKTAN SEÇMELİ soru üret. Her soru $optCount şıklı.

SADECE geçerli bir JSON array döndür — başka metin/markdown/emoji başlık YOK:
[{"q":"soru kökü — net, kendi başına anlaşılır","opts":["şık1", ... $optCount adet],"a":0,"sol":"kısa çözüm"}]

KURALLAR:
• TAM $count soru; her birinde tam $optCount şık ($letters).
• "a": doğru şıkkın 0-tabanlı indeksi (0..${optCount - 1}).
• Sorular $grade. sınıf düzeyine uygun (ne çok kolay ne çok zor), tek doğru
  cevaplı, çeldiriciler tipik öğrenci hatalarından.
• MATEMATİK/KİMYA/FİZİK gösterimi DÜZ UNICODE (H₂O, x², →, ×, ÷, ≤, ≥, π, √).
  LaTeX YOK (\\text, \\(, \\), _2, ^2, \$ işareti YOK).
• TR ondalık virgül. Markdown yıldız (**) / başlık (#) YOK.
• Çıktın tek başına geçerli bir JSON array olmalı.
''';

    return _run(prompt, '$levelName $grade', optCount, count);
  }

  /// AI çağrısı + parse (exam & class ortak).
  static Future<List<Map<String, dynamic>>> _run(
      String prompt, String subjectLabel, int optCount, int count) async {
    try {
      final raw = await GeminiService.solveHomework(
        question: prompt,
        solutionType: 'TestSorulari',
        subject: subjectLabel,
      );
      return _parse(raw, optCount, count);
    } catch (e) {
      debugPrint('[LabyrinthQuizGen] üretim hatası: $e');
      return const [];
    }
  }

  static List<Map<String, dynamic>> _parse(
      String raw, int optCount, int count) {
    var s = raw.trim();
    // Markdown fence temizle
    if (s.startsWith('```')) {
      final nl = s.indexOf('\n');
      if (nl > -1) s = s.substring(nl + 1);
      final lf = s.lastIndexOf('```');
      if (lf > -1) s = s.substring(0, lf);
      s = s.trim();
    }
    final st = s.indexOf('[');
    final en = s.lastIndexOf(']');
    if (st < 0 || en <= st) return const [];
    try {
      final dec = jsonDecode(s.substring(st, en + 1));
      if (dec is! List) return const [];
      final out = <Map<String, dynamic>>[];
      for (final it in dec) {
        if (it is! Map) continue;
        final q = (it['q'] ?? '').toString().trim();
        final rawOpts = it['opts'];
        if (q.isEmpty || rawOpts is! List) continue;
        final opts = rawOpts.map((e) => e.toString()).toList();
        if (opts.length < 3) continue;
        var a = (it['a'] is int)
            ? it['a'] as int
            : int.tryParse('${it['a']}') ?? 0;
        if (a < 0 || a >= opts.length) a = 0;
        out.add({
          'q': q,
          'opts': opts,
          'a': a,
          'sol': (it['sol'] ?? '').toString(),
          'type': 'multi',
        });
      }
      return out.take(count).toList();
    } catch (e) {
      debugPrint('[LabyrinthQuizGen] JSON parse hatası: $e');
      return const [];
    }
  }
}
