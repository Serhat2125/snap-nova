// ═══════════════════════════════════════════════════════════════════════════════
//  Grade — bir kademedeki sınıf veya eşdeğer (9. Sınıf, 10. Klasse, vb.)
//
//  Üniversitede "1. Sınıf, 2. Sınıf" yerine "Bölüm" + "1. Yıl" olabilir;
//  sınava hazırlıkta tek bir Grade vardır (sınav adı), faculty alanı boş.
// ═══════════════════════════════════════════════════════════════════════════════

class Grade {
  /// Level içinde unique kısa anahtar ('9', '10_sayisal', 'tip_3y', 'YKS').
  final String key;

  /// Endonim ad — UI'de gösterilen.
  /// Ör. "9. Sınıf", "10. Klasse", "Grade 9", "Première", "Tıp 3. Sınıf".
  final String displayName;

  /// (Opsiyonel) lise alanı: 'sayisal'/'sozel'/'esit_agirlik'/'dil',
  /// veya US/UK için 'honors'/'AP'/'IB' vb.
  final String? track;

  /// (Opsiyonel) bölüm/fakülte adı — yalnızca üniversite/lisansüstü için.
  final String? faculty;

  const Grade({
    required this.key,
    required this.displayName,
    this.track,
    this.faculty,
  });
}
