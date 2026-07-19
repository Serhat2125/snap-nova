// ═══════════════════════════════════════════════════════════════════════════════
//  SCHOOL STRUCTURE — ülke başına okul kademesi yapısı (Bilgi Labirenti)
//
//  Her ülkenin ilkokul/ortaokul/lise kaç sınıf olduğunu ve lise alan
//  (track) sistemini STATİK olarak tanımlar — AI/ağ gerektirmez.
//
//  • Sınıf numaraları KÜMÜLATİF yıl olarak tutulur (curriculum_catalog
//    anahtarlarıyla aynı: ör. Kore lisesi = 10-12, "고1" değil).
//  • Track anahtarları curriculum_catalog'daki `<cc>_high_<g>_<track>`
//    son ekleriyle birebir aynıdır; böylece EduProfile.track olarak
//    geçirildiğinde konu/ders çözümlemesi doğrudan çalışır.
//  • Listede olmayan ülkeler en yaygın 6-3-3 (ISCED) düzenine düşer.
//
//  Kaynak: UNESCO IBE / WorldData Education Systems + ülke bakanlık
//  yapıları (Jan 2026). GLOBAL-FIRST: TR'ye özel hiçbir varsayım yok.
// ═══════════════════════════════════════════════════════════════════════════════

class TrackOption {
  /// curriculum_catalog `<cc>_high_<grade>_<key>` son ekiyle aynı anahtar.
  final String key;

  /// Endonim (ülkenin kendi dilinde) görünen ad.
  final String label;
  final String emoji;
  const TrackOption(this.key, this.label, this.emoji);
}

class SchoolStructure {
  final int primaryFrom, primaryTo;
  final int middleFrom, middleTo;
  final int highFrom, highTo;

  /// Lise alan sistemi (yoksa boş liste) ve hangi sınıftan itibaren geçerli.
  final List<TrackOption> tracks;
  final int trackFromGrade;

  const SchoolStructure({
    required this.primaryFrom,
    required this.primaryTo,
    required this.middleFrom,
    required this.middleTo,
    required this.highFrom,
    required this.highTo,
    this.tracks = const [],
    this.trackFromGrade = 99,
  });

  List<int> gradesOf(String level) {
    final (from, to) = switch (level) {
      'primary' => (primaryFrom, primaryTo),
      'middle' => (middleFrom, middleTo),
      _ => (highFrom, highTo),
    };
    return [for (int g = from; g <= to; g++) g];
  }

  bool tracksApply(int grade) => tracks.isNotEmpty && grade >= trackFromGrade;
}

/// En yaygın düzen: 6 yıl ilkokul, 3 yıl ortaokul, 3 yıl lise.
const _default633 = SchoolStructure(
  primaryFrom: 1, primaryTo: 6,
  middleFrom: 7, middleTo: 9,
  highFrom: 10, highTo: 12,
);


/// Ülke kodu (küçük harf ISO) → okul yapısı. Yalnızca 6-3-3'ten SAPAN
/// veya alan sistemi olan ülkeler listelenir.
const Map<String, SchoolStructure> _structures = {
  // ── Türkiye: 4+4+4, lise alanları 10. sınıftan ──
  'tr': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 8,
    highFrom: 9, highTo: 12,
    trackFromGrade: 10,
    tracks: [
      TrackOption('sayisal', 'Sayısal', '🔬'),
      TrackOption('sozel', 'Sözel', '📚'),
      TrackOption('esit_agirlik', 'Eşit Ağırlık', '⚖️'),
    ],
  ),
  // ── Amerika: Elementary 1-5, Middle 6-8, High 9-12 ──
  'us': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  // ── Almanya: Grundschule 1-4, Sek I 5-9/10, Sek II (G8) 10-12 ──
  'de': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 12,
  ),
  'at': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  'ch': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
  ),
  // ── Rusya ve BDT: 1-4 / 5-9 / 10-11 ──
  'ru': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 11,
  ),
  'kz': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 11,
  ),
  'by': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 11,
  ),
  'ua': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 11,
  ),
  'kg': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 11,
  ),
  'tj': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 11,
  ),
  // ── Birleşik Krallık: Primary Y1-6, Secondary 7-11 (GCSE), Sixth Form 12-13 ──
  'uk': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 11,
    highFrom: 12, highTo: 13,
    trackFromGrade: 12,
    tracks: [
      TrackOption('sciences', 'Sciences (A-Level)', '🔬'),
      TrackOption('humanities', 'Humanities (A-Level)', '📚'),
    ],
  ),
  // ── Fransa: élémentaire CP-CM2 (1-5), collège (6-9), lycée (10-12) ──
  'fr': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 9,
    highFrom: 10, highTo: 12,
  ),
  // ── İtalya: primaria 1-5, media 6-8, superiore 9-13 ──
  'it': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 8,
    highFrom: 9, highTo: 13,
    trackFromGrade: 9,
    tracks: [
      TrackOption('scientifico', 'Liceo Scientifico', '🔬'),
      TrackOption('classico', 'Liceo Classico', '🏛️'),
    ],
  ),
  // ── İspanya: primaria 1-6, ESO 7-10, bachillerato 11-12 ──
  'es': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 10,
    highFrom: 11, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('ciencias', 'Ciencias', '🔬'),
      TrackOption('humanidades', 'Humanidades y CC.SS.', '📚'),
    ],
  ),
  // ── Portekiz: 1º-2º-3º ciclo (1-9), secundário 10-12 ──
  'pt': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 12,
    trackFromGrade: 10,
    tracks: [
      TrackOption('cientifico', 'Ciências e Tecnologias', '🔬'),
      TrackOption('humanistico', 'Línguas e Humanidades', '📚'),
    ],
  ),
  // ── Polonya: podstawowa 1-8, liceum 9-12 ──
  'pl': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  // ── İskandinavya ──
  'se': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
  ),
  'no': SchoolStructure(
    primaryFrom: 1, primaryTo: 7,
    middleFrom: 8, middleTo: 10,
    highFrom: 11, highTo: 13,
  ),
  'is': SchoolStructure(
    primaryFrom: 1, primaryTo: 7,
    middleFrom: 8, middleTo: 10,
    highFrom: 11, highTo: 13,
  ),
  // ── Orta Avrupa ──
  'hu': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  'cz': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 9,
    highFrom: 10, highTo: 13,
  ),
  'sk': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 9,
    highFrom: 10, highTo: 13,
  ),
  'ro': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  'bg': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 7,
    highFrom: 8, highTo: 12,
  ),
  // ── Balkanlar: 8 yıl temel + 4 yıl lise ──
  'rs': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  'hr': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  'si': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 9,
    highFrom: 10, highTo: 13,
  ),
  'ba': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 13,
  ),
  'mk': SchoolStructure(
    primaryFrom: 1, primaryTo: 4,
    middleFrom: 5, middleTo: 9,
    highFrom: 10, highTo: 13,
  ),
  // ── Güney Asya ──
  'in': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 8,
    highFrom: 9, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('science', 'Science (PCM/PCB)', '🔬'),
      TrackOption('commerce', 'Commerce', '💼'),
      TrackOption('arts', 'Arts / Humanities', '🎭'),
    ],
  ),
  'pk': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 8,
    highFrom: 9, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('pre_eng', 'Pre-Engineering', '🛠️'),
      TrackOption('pre_med', 'Pre-Medical', '🩺'),
      TrackOption('commerce', 'Commerce', '💼'),
      TrackOption('humanities', 'Humanities', '📚'),
    ],
  ),
  'bd': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 8,
    highFrom: 9, highTo: 12,
    trackFromGrade: 9,
    tracks: [
      TrackOption('science', 'Science', '🔬'),
      TrackOption('business', 'Business Studies', '💼'),
      TrackOption('humanities', 'Humanities', '📚'),
    ],
  ),
  // ── Doğu Asya: 6-3-3 + alanlar ──
  'kr': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('jayeon', '자연계 (Fen)', '🔬'),
      TrackOption('insa', '인문계 (Sosyal)', '📚'),
    ],
  ),
  'cn': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('physics', '物理类 (Fizik)', '🔬'),
      TrackOption('history', '历史类 (Tarih)', '📚'),
    ],
  ),
  // ── Güneydoğu Asya ──
  'id': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('ipa', 'IPA (Sains)', '🔬'),
      TrackOption('ips', 'IPS (Sosial)', '📚'),
      TrackOption('bahasa', 'Bahasa', '✒️'),
    ],
  ),
  'ph': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 10,
    highFrom: 11, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('stem', 'STEM', '🔬'),
      TrackOption('humss', 'HUMSS', '📚'),
      TrackOption('abm', 'ABM', '💼'),
    ],
  ),
  'my': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 11,
  ),
  'vn': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 9,
    highFrom: 10, highTo: 12,
  ),
  // ── Orta Doğu ──
  'ir': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
    trackFromGrade: 10,
    tracks: [
      TrackOption('riyazi', 'ریاضی فیزیک', '🛠️'),
      TrackOption('tajrobi', 'علوم تجربی', '🩺'),
      TrackOption('ensani', 'علوم انسانی', '📚'),
    ],
  ),
  // ── Yunanistan ──
  'gr': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('thetiki', 'Θετικές Σπουδές', '🔬'),
      TrackOption('anthropistiki', 'Ανθρωπιστικές', '📚'),
      TrackOption('oikonomiki', 'Οικονομίας & Πληρ.', '💼'),
    ],
  ),
  // ── Amerika kıtası ──
  'br': SchoolStructure(
    primaryFrom: 1, primaryTo: 5,
    middleFrom: 6, middleTo: 9,
    highFrom: 10, highTo: 12,
  ),
  'mx': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('ciencias', 'Ciencias', '🔬'),
      TrackOption('humanidades', 'Humanidades', '📚'),
    ],
  ),
  'ar': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
    trackFromGrade: 11,
    tracks: [
      TrackOption('ciencias', 'Ciencias', '🔬'),
      TrackOption('humanidades', 'Humanidades', '📚'),
    ],
  ),
  'cl': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  'ca': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 8,
    highFrom: 9, highTo: 12,
  ),
  // ── Okyanusya ──
  'au': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 10,
    highFrom: 11, highTo: 12,
  ),
  'nz': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 10,
    highFrom: 11, highTo: 13,
  ),
  // ── Afrika ──
  'za': SchoolStructure(
    primaryFrom: 1, primaryTo: 7,
    middleFrom: 8, middleTo: 9,
    highFrom: 10, highTo: 12,
  ),
  'ng': SchoolStructure(
    primaryFrom: 1, primaryTo: 6,
    middleFrom: 7, middleTo: 9,
    highFrom: 10, highTo: 12,
  ),
};

/// Ülkenin okul yapısı — bilinmiyorsa en yaygın 6-3-3 düzeni.
SchoolStructure schoolStructureFor(String? countryCode) {
  final cc = (countryCode ?? '').toLowerCase();
  return _structures[cc] ?? _default633;
}
