// ═══════════════════════════════════════════════════════════════════════════
//  grading_config.dart — Ülke/müfredat bazlı DİNAMİK not sistemi.
//
//  Tek bir "Not Ekleme" ekranı, seçilen ülkenin CurriculumConfig'ine göre
//  şekillenir (skala, kategoriler, ağırlık modu, hesaplama türü). 173 ülke
//  için 173 ekran yerine: birkaç "not profili" (preset) + ülke→profil eşlemesi.
//
//  Tasarım notları (Claude önerisi):
//   • scoreInputType tek enum yerine PARAMETRELER: scaleMin/scaleMax/decimals/
//     higherIsBetter/passThreshold → Almanya (1=en iyi), Fransa 0–20, GPA 4.0,
//     Hollanda 0–10 gibi farklı yönleri ve skalaları tek modelde temsil eder.
//   • "Ağırlık" iki ayrı kavram: not-başına (Fransa katsayı) vs kategori-başına
//     (ABD: Sınav %50, Ödev %30…). weightMode bunu netleştirir.
//   • Hesaplama iş mantığı UI'dan ayrı: GradeCalculator (saf fonksiyonlar).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

/// Dönem sonu hesaplama türü.
enum CalcModel {
  arithmetic, // düz aritmetik ortalama (TR, RU…)
  weighted, // ağırlıklı (ABD kategori, FR katsayı…)
  totalPoints, // puan toplamı (bazı Asya sistemleri)
}

/// Ağırlığın nereden geldiği.
enum WeightMode {
  none, // ağırlık yok → eşit (aritmetik). Ekranda yüzde seçici GİZLİ.
  perNote, // her nota ayrı ağırlık (kullanıcı seçer) — FR katsayı, TR opsiyonel.
  perCategory, // ağırlık kategoriye sabit (ABD) — kullanıcı değiştirmez, Σ=100.
}

/// Notun görsel gösterim/giriş tipi.
enum DisplayType {
  numeric, // sayısal (0–100, 1–5, 0–20…)
  gpa, // ondalık puan (4.0 / 5.0 / 10.0) — harf eşlemesiyle gösterilir
  letter, // harf (A, B, C…) — letterMap ile puana çevrilir
}

/// Ders içi not kategorisi (dropdown'da listelenir).
class GradeCategory {
  /// Firestore'da `type` alanına yazılan kararlı anahtar (ör. 'yazili').
  final String key;

  /// Görünen ad (Türkçe baz; UI'da .tr() ile yerelleştirilir).
  final String label;

  /// Kısa emoji (görsel ipucu).
  final String emoji;

  /// perCategory modunda bu kategorinin sabit ağırlığı (% — toplam 100 olmalı).
  /// Diğer modlarda 0.
  final double defaultWeight;

  /// "1. Yazılı / 2. Yazılı" gibi sıra alt-sekmesi açılsın mı? (TR'ye özgü.)
  final bool orderable;

  const GradeCategory({
    required this.key,
    required this.label,
    this.emoji = '📝',
    this.defaultWeight = 0,
    this.orderable = false,
  });
}

/// Bir ülke/müfredatın tüm not kurallarını tutan yapı.
class CurriculumConfig {
  final String profileId; // preset kimliği
  final String countryCode; // ISO ülke kodu (ana eşleme anahtarı)
  final String label; // görünen ad ("Türkiye (MEB)")
  final String flag; // bayrak emoji
  final CalcModel calc;

  // ── Skala parametreleri ──
  final double scaleMin;
  final double scaleMax;
  final int decimals; // gösterim ondalık hanesi (TR 0, FR 1, GPA 2)
  final bool higherIsBetter; // Almanya'da false (1 = en iyi)
  final double passThreshold; // geçme sınırı (yöne göre yorumlanır)

  // ── Gösterim / giriş ──
  final DisplayType display;

  /// gpa/letter için harf→puan tablosu (ör. {'A':4.0,'B':3.0}).
  final Map<String, double>? letterMap;

  // ── Ağırlık ──
  final WeightMode weightMode;
  final List<GradeCategory> categories;

  /// Sonuç yuvarlama: 'none' | 'nearestInt' | 'oneDecimal'.
  final String rounding;

  const CurriculumConfig({
    required this.profileId,
    required this.countryCode,
    required this.label,
    required this.flag,
    required this.calc,
    required this.scaleMin,
    required this.scaleMax,
    this.decimals = 0,
    this.higherIsBetter = true,
    required this.passThreshold,
    this.display = DisplayType.numeric,
    this.letterMap,
    this.weightMode = WeightMode.none,
    required this.categories,
    this.rounding = 'oneDecimal',
  });

  bool get showPercentageSelector => weightMode == WeightMode.perNote;

  GradeCategory categoryByKey(String key) => categories.firstWhere(
        (c) => c.key == key,
        orElse: () => categories.first,
      );
}

/// Calculator'ın çalıştığı sade not kaydı (StudentGrade'den bağımsız).
class GradeEntry {
  final double score; // skala üzerindeki ham değer (gpa için puan)
  final int weightPercent; // perNote ağırlığı (%). 0 = belirtilmemiş.
  final String categoryKey;
  final int term;
  const GradeEntry({
    required this.score,
    required this.weightPercent,
    required this.categoryKey,
    required this.term,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  PROFİLLER (preset) + ÜLKE EŞLEMESİ
// ═══════════════════════════════════════════════════════════════════════════

const Map<String, double> _gpa4 = {
  'A': 4.0, 'A-': 3.7, 'B+': 3.3, 'B': 3.0, 'B-': 2.7,
  'C+': 2.3, 'C': 2.0, 'C-': 1.7, 'D+': 1.3, 'D': 1.0, 'F': 0.0,
};

/// Tüm desteklenen profiller. countryCode örnek/temsilîdir; asıl eşleme
/// [kCountryToProfile] üzerinden yapılır.
final Map<String, CurriculumConfig> kGradingProfiles = {
  // ── Türkiye: aritmetik, 0–100, yüzde GİZLİ, yazılı/sözlü sıralanabilir ──
  'tr': const CurriculumConfig(
    profileId: 'tr', countryCode: 'TR', label: 'Türkiye (MEB)', flag: '🇹🇷',
    calc: CalcModel.arithmetic, scaleMin: 0, scaleMax: 100, decimals: 0,
    passThreshold: 50, display: DisplayType.numeric,
    weightMode: WeightMode.none, rounding: 'nearestInt',
    categories: [
      GradeCategory(key: 'yazili', label: 'Yazılı Sınav', emoji: '📝', orderable: true),
      GradeCategory(key: 'sozlu', label: 'Sözlü (Katılım)', emoji: '🗣️', orderable: true),
      GradeCategory(key: 'proje', label: 'Proje Ödevi', emoji: '📐'),
    ],
  ),

  // ── ABD: ağırlıklı (kategori-bazlı, Σ=100), 0–100, yüzde kategoriden ──
  'us': const CurriculumConfig(
    profileId: 'us', countryCode: 'US', label: 'USA (Weighted)', flag: '🇺🇸',
    calc: CalcModel.weighted, scaleMin: 0, scaleMax: 100, decimals: 1,
    passThreshold: 60, display: DisplayType.numeric,
    weightMode: WeightMode.perCategory, rounding: 'oneDecimal',
    categories: [
      GradeCategory(key: 'exam', label: 'Exam', emoji: '🎯', defaultWeight: 50),
      GradeCategory(key: 'quiz', label: 'Quiz', emoji: '⚡', defaultWeight: 20),
      GradeCategory(key: 'homework', label: 'Homework', emoji: '📚', defaultWeight: 20),
      GradeCategory(key: 'project', label: 'Project', emoji: '📐', defaultWeight: 10),
    ],
  ),

  // ── GPA 4.0 (harf): ağırlıklı kategori, harf giriş/gösterim ──
  'gpa4': const CurriculumConfig(
    profileId: 'gpa4', countryCode: 'US', label: 'GPA 4.0 (Letter)', flag: '🎓',
    calc: CalcModel.weighted, scaleMin: 0, scaleMax: 4, decimals: 2,
    passThreshold: 1.0, display: DisplayType.gpa, letterMap: _gpa4,
    weightMode: WeightMode.perCategory, rounding: 'oneDecimal',
    categories: [
      GradeCategory(key: 'exam', label: 'Exam', emoji: '🎯', defaultWeight: 50),
      GradeCategory(key: 'quiz', label: 'Quiz', emoji: '⚡', defaultWeight: 20),
      GradeCategory(key: 'homework', label: 'Homework', emoji: '📚', defaultWeight: 30),
    ],
  ),

  // ── Rusya: aritmetik, 1–5 tamsayı, yüzde gizli ──
  'ru5': const CurriculumConfig(
    profileId: 'ru5', countryCode: 'RU', label: 'Россия (1–5)', flag: '🇷🇺',
    calc: CalcModel.arithmetic, scaleMin: 1, scaleMax: 5, decimals: 0,
    passThreshold: 3, display: DisplayType.numeric,
    weightMode: WeightMode.none, rounding: 'nearestInt',
    categories: [
      GradeCategory(key: 'exam', label: 'Контрольная', emoji: '📝'),
      GradeCategory(key: 'oral', label: 'Устный ответ', emoji: '🗣️'),
      GradeCategory(key: 'homework', label: 'Домашняя работа', emoji: '📚'),
    ],
  ),

  // ── Almanya: aritmetik, 1–6, 1 = EN İYİ (ters yön), geçme ≤ 4 ──
  'de6': const CurriculumConfig(
    profileId: 'de6', countryCode: 'DE', label: 'Deutschland (1–6)', flag: '🇩🇪',
    calc: CalcModel.arithmetic, scaleMin: 1, scaleMax: 6, decimals: 1,
    higherIsBetter: false, passThreshold: 4, display: DisplayType.numeric,
    weightMode: WeightMode.none, rounding: 'oneDecimal',
    categories: [
      GradeCategory(key: 'klausur', label: 'Klausur', emoji: '📝'),
      GradeCategory(key: 'muendlich', label: 'Mündlich', emoji: '🗣️'),
    ],
  ),

  // ── Fransa: ağırlıklı (not-başına katsayı), 0–20, geçme 10 ──
  'fr20': const CurriculumConfig(
    profileId: 'fr20', countryCode: 'FR', label: 'France (0–20)', flag: '🇫🇷',
    calc: CalcModel.weighted, scaleMin: 0, scaleMax: 20, decimals: 1,
    passThreshold: 10, display: DisplayType.numeric,
    weightMode: WeightMode.perNote, rounding: 'oneDecimal',
    categories: [
      GradeCategory(key: 'controle', label: 'Contrôle', emoji: '📝'),
      GradeCategory(key: 'devoir', label: 'Devoir', emoji: '📚'),
      GradeCategory(key: 'oral', label: 'Oral', emoji: '🗣️'),
    ],
  ),

  // ── Hollanda: aritmetik, 0–10 (1 ondalık), geçme 5.5 ──
  'nl10': const CurriculumConfig(
    profileId: 'nl10', countryCode: 'NL', label: 'Nederland (1–10)', flag: '🇳🇱',
    calc: CalcModel.arithmetic, scaleMin: 1, scaleMax: 10, decimals: 1,
    passThreshold: 5.5, display: DisplayType.numeric,
    weightMode: WeightMode.perNote, rounding: 'oneDecimal',
    categories: [
      GradeCategory(key: 'toets', label: 'Toets', emoji: '📝'),
      GradeCategory(key: 'so', label: 'Overhoring', emoji: '⚡'),
      GradeCategory(key: 'praktijk', label: 'Praktijk', emoji: '📐'),
    ],
  ),

  // ── Uluslararası/varsayılan: aritmetik, 0–100, geçme 50, not-başına ağırlık ──
  'generic100': const CurriculumConfig(
    profileId: 'generic100', countryCode: 'XX', label: 'Uluslararası (0–100)',
    flag: '🌍', calc: CalcModel.arithmetic, scaleMin: 0, scaleMax: 100,
    decimals: 1, passThreshold: 50, display: DisplayType.numeric,
    weightMode: WeightMode.perNote, rounding: 'oneDecimal',
    categories: [
      GradeCategory(key: 'exam', label: 'Sınav', emoji: '📝'),
      GradeCategory(key: 'quiz', label: 'Kısa Sınav', emoji: '⚡'),
      GradeCategory(key: 'homework', label: 'Ödev', emoji: '📚'),
      GradeCategory(key: 'project', label: 'Proje', emoji: '📐'),
    ],
  ),
};

/// Ülke kodu → profil kimliği. Listede olmayan ülke 'generic100'a düşer.
const Map<String, String> kCountryToProfile = {
  'TR': 'tr',
  'US': 'us', 'CA': 'us',
  'RU': 'ru5', 'UA': 'ru5', 'BY': 'ru5', 'KZ': 'ru5', 'KG': 'ru5', 'AM': 'ru5',
  'DE': 'de6', 'AT': 'de6', 'CH': 'de6',
  'FR': 'fr20', 'BE': 'fr20', 'LU': 'fr20', 'MA': 'fr20', 'TN': 'fr20', 'DZ': 'fr20',
  'NL': 'nl10',
  // Diğer tüm ülkeler → generic100 (0–100, aritmetik).
};

/// Aktif not konfigürasyonunu yöneten servis (AccountService.gradingCountry'den).
class GradingConfigService {
  GradingConfigService._();

  /// Bir ülke koduna karşılık gelen config (yoksa generic100).
  static CurriculumConfig forCountry(String? countryCode) {
    final cc = (countryCode ?? '').toUpperCase();
    final profileId = kCountryToProfile[cc] ?? 'generic100';
    final base = kGradingProfiles[profileId]!;
    // Ülke kodu profilden farklıysa (ör. CA→us) gerçek ülke kodunu koru.
    if (cc.isNotEmpty && cc != base.countryCode) {
      return CurriculumConfig(
        profileId: base.profileId, countryCode: cc, label: base.label,
        flag: base.flag, calc: base.calc, scaleMin: base.scaleMin,
        scaleMax: base.scaleMax, decimals: base.decimals,
        higherIsBetter: base.higherIsBetter, passThreshold: base.passThreshold,
        display: base.display, letterMap: base.letterMap,
        weightMode: base.weightMode, categories: base.categories,
        rounding: base.rounding,
      );
    }
    return base;
  }

  /// Bir profil kimliğine göre config (seçim ekranı listesi için).
  static CurriculumConfig byProfile(String profileId) =>
      kGradingProfiles[profileId] ?? kGradingProfiles['generic100']!;

  /// Seçim ekranında listelenecek profiller (sıralı).
  static List<CurriculumConfig> get pickerProfiles => const [
        'tr', 'us', 'gpa4', 'fr20', 'de6', 'ru5', 'nl10', 'generic100',
      ].map((id) => kGradingProfiles[id]!).toList();
}

// ═══════════════════════════════════════════════════════════════════════════
//  HESAPLAMA MOTORU (saf fonksiyonlar)
// ═══════════════════════════════════════════════════════════════════════════

class GradeCalculator {
  GradeCalculator._();

  /// Dönem sonu sonucu (skala üzerinde, yuvarlanmış).
  static double termResult(CurriculumConfig cfg, List<GradeEntry> grades) {
    if (grades.isEmpty) return 0;
    switch (cfg.calc) {
      case CalcModel.arithmetic:
        final raw =
            grades.map((g) => g.score).reduce((a, b) => a + b) / grades.length;
        return _round(cfg, raw);
      case CalcModel.totalPoints:
        final raw = grades.fold<double>(0, (s, g) => s + g.score);
        return _round(cfg, raw);
      case CalcModel.weighted:
        return _round(cfg, cfg.weightMode == WeightMode.perCategory
            ? _weightedByCategory(cfg, grades)
            : _weightedByNote(grades));
    }
  }

  /// Kategori-başına ağırlıklı (ABD). Her kategori kendi içinde ortalanır,
  /// kategori ağırlığıyla çarpılır; sadece NOTU OLAN kategorilerin ağırlıkları
  /// normalize edilir → kısmi dönemde de tutarlı.
  static double _weightedByCategory(
      CurriculumConfig cfg, List<GradeEntry> grades) {
    double weightedSum = 0, weightTotal = 0;
    for (final cat in cfg.categories) {
      final inCat = grades.where((g) => g.categoryKey == cat.key).toList();
      if (inCat.isEmpty) continue;
      final avg =
          inCat.map((g) => g.score).reduce((a, b) => a + b) / inCat.length;
      final w = cat.defaultWeight;
      if (w <= 0) continue;
      weightedSum += avg * w;
      weightTotal += w;
    }
    if (weightTotal <= 0) {
      // Ağırlıksız kategorilere düştü → düz ortalama.
      return grades.map((g) => g.score).reduce((a, b) => a + b) / grades.length;
    }
    return weightedSum / weightTotal;
  }

  /// Not-başına ağırlıklı (FR katsayı / opsiyonel). Σ(not×ağırlık)/Σ(ağırlık).
  /// Ağırlık girilmemiş notlara, girilenlerin ortalaması kadar pay verilir.
  static double _weightedByNote(List<GradeEntry> grades) {
    final nonZero = grades.where((g) => g.weightPercent > 0).toList();
    if (nonZero.isEmpty) {
      return grades.map((g) => g.score).reduce((a, b) => a + b) / grades.length;
    }
    final avgW =
        nonZero.fold<int>(0, (s, g) => s + g.weightPercent) / nonZero.length;
    double sum = 0, totalW = 0;
    for (final g in grades) {
      final w = g.weightPercent > 0 ? g.weightPercent.toDouble() : avgW;
      sum += g.score * w;
      totalW += w;
    }
    return totalW > 0 ? sum / totalW : 0;
  }

  /// Geçme kontrolü — skalanın yönünü dikkate alır.
  static bool isPass(CurriculumConfig cfg, double score) =>
      cfg.higherIsBetter ? score >= cfg.passThreshold : score <= cfg.passThreshold;

  static double _round(CurriculumConfig cfg, double v) {
    switch (cfg.rounding) {
      case 'nearestInt':
        return v.roundToDouble();
      case 'oneDecimal':
        return (v * 10).roundToDouble() / 10;
      default:
        return v;
    }
  }

  /// Tek bir skor değerini gösterime çevirir (harf/sayı). TR ondalık virgül.
  static String displayScore(CurriculumConfig cfg, double score) {
    if (cfg.display == DisplayType.letter ||
        (cfg.display == DisplayType.gpa && cfg.letterMap != null)) {
      final letter = _nearestLetter(cfg, score);
      if (cfg.display == DisplayType.letter) return letter;
      // gpa: hem puan hem harf ("3.7 · A-")
      return '${_fmt(score, cfg.decimals)} · $letter';
    }
    return _fmt(score, cfg.decimals);
  }

  /// Dönem sonucunu gösterime çevirir.
  static String displayResult(CurriculumConfig cfg, double result) =>
      displayScore(cfg, result);

  static String _fmt(double v, int decimals) {
    final s = v.toStringAsFixed(decimals);
    return s.replaceAll('.', ','); // TR ondalık virgül
  }

  /// Bir puana en yakın harf (gpa/letter gösterimi için).
  static String _nearestLetter(CurriculumConfig cfg, double score) {
    final map = cfg.letterMap;
    if (map == null || map.isEmpty) return _fmt(score, cfg.decimals);
    String best = map.keys.first;
    double bestDiff = double.infinity;
    map.forEach((label, pts) {
      final d = (pts - score).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = label;
      }
    });
    return best;
  }

  /// Skor giriş doğrulaması: skala içinde mi?
  static bool isScoreValid(CurriculumConfig cfg, double score) =>
      score >= cfg.scaleMin - 1e-9 && score <= cfg.scaleMax + 1e-9;

  /// Skala etiketi ("0–100", "1–5", "0–20").
  static String scaleLabel(CurriculumConfig cfg) {
    final lo = cfg.scaleMin == cfg.scaleMin.roundToDouble()
        ? cfg.scaleMin.toInt().toString()
        : cfg.scaleMin.toString();
    final hi = cfg.scaleMax == cfg.scaleMax.roundToDouble()
        ? cfg.scaleMax.toInt().toString()
        : cfg.scaleMax.toString();
    return '$lo–$hi';
  }

  /// Renklendirme için 0..1 başarı oranı (yönü dikkate alır).
  static double successRatio(CurriculumConfig cfg, double score) {
    final span = (cfg.scaleMax - cfg.scaleMin).abs();
    if (span <= 0) return 0;
    final r = (score - cfg.scaleMin) / span;
    final clamped = math.max(0.0, math.min(1.0, r));
    return cfg.higherIsBetter ? clamped : 1 - clamped;
  }
}
