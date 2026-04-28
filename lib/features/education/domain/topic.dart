// ═══════════════════════════════════════════════════════════════════════════════
//  Topic — bir dersin alt-konu başlığı (Türev, Yapay Sinir Ağları, Lozan...)
//
//  Topic listesi runtime AI tarafından üretilir (fetchSubjectTopicPack).
//  Bu domain modeli, offline pack ve gelecek konu sayfaları için ortak
//  veri tipini temsil eder.
// ═══════════════════════════════════════════════════════════════════════════════

class Topic {
  final String name;
  /// Konunun 100-180 kelimelik özeti (ilk fetch sonrası dolar).
  final String? summary;
  const Topic({required this.name, this.summary});
}
