import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'lesson_3d_screen.dart';

/// Sürükle-bırak ile sıralanabilen, sırası kalıcı (SharedPreferences) kart listesi.
/// Karta dokun → açılır; basılı tutup sürükle → sırasını değiştir.
class _ReorderList extends StatefulWidget {
  final String storageKey;
  final EdgeInsets? padding;
  final List<Widget> children;
  const _ReorderList(
      {required this.storageKey, this.padding, required this.children});
  @override
  State<_ReorderList> createState() => _ReorderListState();
}

class _ReorderListState extends State<_ReorderList> {
  late final List<Widget> _cards =
      widget.children.where((w) => w is! SizedBox).toList();
  late List<int> _order = List.generate(_cards.length, (i) => i);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList('order_${widget.storageKey}');
    if (saved == null) return;
    final savedIdx = saved
        .map(int.tryParse)
        .whereType<int>()
        .where((i) => i >= 0 && i < _cards.length)
        .toList();
    final seen = savedIdx.toSet();
    final out = <int>[
      ...savedIdx,
      ...List.generate(_cards.length, (i) => i).where((i) => !seen.contains(i)),
    ];
    if (mounted) setState(() => _order = out);
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        'order_${widget.storageKey}', _order.map((e) => '$e').toList());
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      padding: widget.padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 16),
      onReorder: (oldI, newI) {
        setState(() {
          if (newI > oldI) newI--;
          final v = _order.removeAt(oldI);
          _order.insert(newI, v);
        });
        _save();
      },
      proxyDecorator: (child, index, anim) =>
          Material(color: Colors.transparent, elevation: 8, child: child),
      children: [
        for (final idx in _order)
          Padding(
            key: ValueKey('it_$idx'),
            padding: const EdgeInsets.only(bottom: 10),
            child: _cards[idx],
          ),
      ],
    );
  }
}

/// 3D Eğitim Modelleri — Ders seçim ekranı.
/// Kütüphane → 3D Eğitim Modelleri kartından açılır.
/// Buradan ders seçilince ilgili dersin konu listesine gidilir.
class Edu3DSubjectsScreen extends StatelessWidget {
  const Edu3DSubjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_in_ar_rounded,
                color: Color(0xFF06B6D4), size: 22),
            const SizedBox(width: 8),
            Text(
              '3D Eğitim Modelleri',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        // Sağ üstte ayarlar (çark) — tüm 3D modeller için ortak ayarlar
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            color: AppPalette.textPrimary(context),
            tooltip: 'Ayarlar',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/gecis-studyosu.html',
                  title: 'Ayarlar',
                ),
              ),
            ),
          ),
        ],
      ),
      body: _ReorderList(
        storageKey: 'subjects',
        children: [
          _SubjectCard(
            icon: Icons.public_rounded,
            title: 'Coğrafya',
            color: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DCografyaScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.calculate_rounded,
            title: 'Matematik',
            color: const Color(0xFFF97316),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DMatematikScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.category_rounded,
            title: 'Geometrik Cisimler',
            color: const Color(0xFFEAB308),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DGeometriScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.biotech_rounded,
            title: 'Biyoloji',
            color: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DBiyolojiScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.science_rounded,
            title: 'Fizik',
            color: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DFizikScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.science_outlined,
            title: 'Kimya',
            color: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DKimyaScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Coğrafya dersinin 3D konu listesi.
class Edu3DCografyaScreen extends StatelessWidget {
  const Edu3DCografyaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.public_rounded,
                color: Color(0xFF0EA5E9), size: 22),
            const SizedBox(width: 8),
            Text(
              'Coğrafya',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: _ReorderList(
        storageKey: "cografya",
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _TopicCard(
            emoji: '🌍',
            title: 'Dünyanın Şekli ve Hareketi',
            subtitle: 'Gece-gündüz, mevsimler, Güneş sistemi',
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/dunyanin-hareketleri.html',
                  title: 'Dünyanın Şekli ve Hareketi',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🗺️',
            title: 'Yer Şekilleri ve İzohipsler',
            subtitle: 'İzohips kuralları, eğim, profil, vadi/sırt, delta, plato/ova',
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/yer-sekilleri-izohipsler.html',
                  title: 'Yer Şekilleri ve İzohipsler',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌋',
            title: 'Yerin İç Yapısı ve Levha Tektoniği',
            subtitle: 'Katmanlar, kıvrım/kırık dağlar, volkanizma, levha sınırları, depremler',
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/yerin-ic-yapisi-levha-tektonigi.html',
                  title: 'Yerin İç Yapısı ve Levha Tektoniği',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌦️',
            title: 'Atmosfer ve İklim',
            subtitle: 'Atmosfer katmanları, basınç merkezleri, Coriolis, küresel rüzgarlar',
            tint: const Color(0xFF38BDF8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/atmosfer-iklim.html',
                  title: 'Atmosfer ve İklim',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌍',
            title: 'Dünya Coğrafyası',
            subtitle: 'İklim bölgeleri, kıtalar, dağlar, nehirler, boğazlar, kanallar, nüfus',
            tint: const Color(0xFF22C55E),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/dunya-cografyasi.html',
                  title: 'Dünya Coğrafyası',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Matematik dersinin 3D konu listesi. Yeni matematik dersleri buraya _TopicCard olarak eklenir.
class Edu3DMatematikScreen extends StatelessWidget {
  const Edu3DMatematikScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calculate_rounded,
                color: Color(0xFFF97316), size: 22),
            const SizedBox(width: 8),
            Text(
              'Matematik',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: _ReorderList(
        storageKey: "matematik",
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _TopicCard(
            emoji: '🔢',
            title: 'Üslü Sayılar',
            subtitle: 'Üs, taban, kuvvet kuralları, 3B görselleştirme',
            tint: const Color(0xFF6366F1),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/uslu-sayilar.html',
                  title: 'Üslü Sayılar',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🟰',
            title: 'Denklemler',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFF8B5CF6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/denklemler.html',
                  title: 'Denklemler',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧮',
            title: 'Problemler',
            subtitle: 'Sözel problemler, kurulum ve çözüm adımları',
            tint: const Color(0xFFEC4899),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/problemler.html',
                  title: 'Problemler',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔵',
            title: 'Kümeler',
            subtitle: 'Küme işlemleri, Venn şemaları, 3B görselleştirme',
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/kumeler.html',
                  title: 'Kümeler',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📈',
            title: 'Fonksiyonlar',
            subtitle: 'Fonksiyon kavramı, grafikler ve dönüşümler',
            tint: const Color(0xFF10B981),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/fonksiyonlar.html',
                  title: 'Fonksiyonlar',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔣',
            title: 'Polinomlar',
            subtitle: 'Polinom işlemleri, çarpanlara ayırma, 3B görselleştirme',
            tint: const Color(0xFFF59E0B),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/polinomlar.html',
                  title: 'Polinomlar',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧠',
            title: 'Mantık',
            subtitle: 'Önermeler, bağlaçlar, doğruluk tabloları',
            tint: const Color(0xFF8B5CF6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/mantik.html',
                  title: 'Mantık',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📚',
            title: 'Temel Kavramlar',
            subtitle: 'Sayılar, kümeler ve temel matematik kavramları',
            tint: const Color(0xFF14B8A6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/temel-kavramlar.html',
                  title: 'Temel Kavramlar',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '➗',
            title: 'Kesirler ve Rasyonel Sayılar',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFF14B8A6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/kesirler-rasyonel.html',
                  title: 'Kesirler ve Rasyonel Sayılar',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '➗',
            title: 'Bölme ve Bölünebilme',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFF6366F1),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/bolme-bolunebilme.html',
                  title: 'Bölme ve Bölünebilme',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '⚖️',
            title: 'Basit Eşitsizlikler',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFFEC4899),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/basit-esitsizlikler.html',
                  title: 'Basit Eşitsizlikler',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🔢',
            title: 'Sayı Basamakları',
            subtitle: 'Basamak değeri ve sayı çözümleme',
            tint: const Color(0xFFFFC857),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/sayi-basamaklari.html',
                  title: 'Sayı Basamakları',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '√',
            title: 'Köklü Sayılar',
            subtitle: 'Kök, üs ve rasyonel ifadeler — 3B sahneler',
            tint: const Color(0xFF22C55E),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/koklu-sayilar.html',
                  title: 'Köklü Sayılar',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '|x|',
            title: 'Mutlak Değer',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFFF59E0B),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/mutlak-deger.html',
                  title: 'Mutlak Değer',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔀',
            title: 'Permütasyon ve Kombinasyon',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFF14B8A6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/permutasyon-kombinasyon.html',
                  title: 'Permütasyon ve Kombinasyon',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📐',
            title: 'İkinci Dereceden Denklemler',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFFEF4444),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/ikinci-dereceden-denklemler.html',
                  title: 'İkinci Dereceden Denklemler',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🎲',
            title: 'Olasılık',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFF8B5CF6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/olasilik.html',
                  title: 'Olasılık',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📊',
            title: 'Veri ve İstatistik',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/veri-istatistik.html',
                  title: 'Veri ve İstatistik',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📐',
            title: 'Geometri',
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test',
            tint: const Color(0xFFEC4899),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/geometri.html',
                  title: 'Geometri',
                ),
              ),
            ),
          ),
          // ⬇️ YENİ MATEMATİK DERSLERİ BURAYA EKLENİR (gönderilen kod → assets/<ad>.html + pubspec + _TopicCard)
        ],
      ),
    );
  }
}

/// Geometrik Cisimler dersinin 3D konu listesi (ayrı branş).
class Edu3DGeometriScreen extends StatelessWidget {
  const Edu3DGeometriScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.category_rounded,
                color: Color(0xFFEAB308), size: 22),
            const SizedBox(width: 8),
            Text(
              'Geometrik Cisimler',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: _ReorderList(
        storageKey: "geometri",
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _TopicCard(
            emoji: '📐',
            title: 'Geometrik Cisimler ve Hesaplamalar',
            subtitle: 'Küp, prizma, silindir, koni, küre — hacim & alan',
            tint: const Color(0xFFEAB308),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/geometrik-cisimler.html',
                  title: 'Geometrik Cisimler ve Hesaplamalar',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fizik dersinin 3D konu listesi.
class Edu3DFizikScreen extends StatelessWidget {
  const Edu3DFizikScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.science_rounded,
                color: Color(0xFF7C3AED), size: 22),
            const SizedBox(width: 8),
            Text(
              'Fizik',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: _ReorderList(
        storageKey: "fizik",
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _TopicCard(
            emoji: '⚛️',
            title: 'Maddenin Yapısı ve Özellikleri',
            subtitle: 'K-12 sınıf bazlı: İlkokul/Ortaokul/Lise — duyular, haller, tanecikler, atom, basınç, kuantum',
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/maddenin-yapisi.html',
                  title: 'Maddenin Yapısı',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔦',
            title: 'Gölge Oluşumu ve Işığın Yayılması',
            subtitle: 'Doğrusal yayılma, tam/yarı gölge, tutulmalar, iğne deliği kamerası',
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/golge-olusumu-isik-yayilmasi.html',
                  title: 'Gölge Oluşumu ve Işığın Yayılması',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧭',
            title: 'Bileşke Kuvvet ve Vektörler',
            subtitle: 'Vektörün bileşenleri, paralelkenar, dik/açılı kuvvetler, denge, eğik düzlem, bağıl hız',
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/bileske-kuvvet-vektorler.html',
                  title: 'Bileşke Kuvvet ve Vektörler',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '⚙️',
            title: 'Basit Makineler',
            subtitle: 'Kaldıraç, makara, palanga, eğik düzlem, vida, çıkrık, dişli — kuvvet kazancı ve verim',
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/basit-makineler.html',
                  title: 'Basit Makineler',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🌊',
            title: 'Dalgalar',
            subtitle: 'Temel kavramlar, dalga hızı, yansıma/kırılma/kırınım/girişim, ses/deprem dalgaları, Doppler, EM spektrum',
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/dalgalar.html',
                  title: 'Dalgalar',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔍',
            title: 'Işığın Kırılması ve Mercekler',
            subtitle: 'Kırılma, Snell, tam yansıma, prizma, mercekler, aynalar, göz, aydınlanma ve renk',
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/optik-mercekler.html',
                  title: 'Işığın Kırılması ve Mercekler',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '⚡',
            title: 'Elektrik',
            subtitle: 'Elektrostatik, yük, alan, potansiyel, devreler, Ohm, direnç, kondansatör, güç',
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/elektrik.html',
                  title: 'Elektrik',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🌊',
            title: 'Basınç ve Kaldırma Kuvveti',
            subtitle: 'Batma/yüzme, özkütle, Arşimet, katı/sıvı/açık hava basıncı, Pascal, bileşik kaplar, Bernoulli',
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/akiskanlar-mekanigi.html',
                  title: 'Basınç ve Kaldırma Kuvveti',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kimya dersinin 3D konu listesi.
class Edu3DKimyaScreen extends StatelessWidget {
  const Edu3DKimyaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.science_outlined,
                color: Color(0xFFE11D48), size: 22),
            const SizedBox(width: 8),
            Text(
              'Kimya',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: _ReorderList(
        storageKey: "kimya",
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          // ── KİMYA KONULARI ──
          _TopicCard(
            emoji: '⚛️',
            title: 'Atom Teorisi ve Kuantum Orbitalleri',
            subtitle: 'Atom yapısı, modeller (Dalton→Bohr→Modern), Rutherford, izotop, iyon, Bohr/spektrum, kuantum sayıları, s/p/d/f orbitalleri',
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/atom-teorisi-orbitaller.html',
                  title: 'Atom Teorisi ve Orbitaller',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🔗',
            title: 'Kimyasal Türler Arası Etkileşimler (Bağlar)',
            subtitle:
                'İyonik/kovalent/metalik bağ, polar-apolar, NaCl örgü, London/dipol/iyon-dipol, hidrojen bağı, su ve buz',
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/kimyasal-baglar.html',
                  title: 'Kimyasal Bağlar',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧪',
            title: 'Karışımlar ve Çözeltiler',
            subtitle:
                'Saf madde/karışım, homojen-heterojen, çözünme, ayırma teknikleri, Tyndall, derişim, koligatif, ozmos, çözünürlük dengesi',
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/karisimlar-cozeltiler.html',
                  title: 'Karışımlar ve Çözeltiler',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '⚗️',
            title: 'Kimyasal Tepkimeler ve Tepkime Hızı',
            subtitle:
                'Tepkime belirtileri, kütlenin korunumu, bağ enerjisi, sentez/analiz/yanma/nötrleşme, çarpışma teorisi, aktivasyon enerjisi, katalizör',
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/kimyasal-tepkimeler.html',
                  title: 'Kimyasal Tepkimeler',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '⚛️',
            title: 'Atom ve Periyodik Sistem',
            subtitle:
                'Atomun yapısı, atom modelleri (Dalton→Bohr), katman dizilimi, spektrum, yörünge/orbital, kuantum sayıları, elektron dizilimi, periyodik bloklar',
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/atom-periyodik.html',
                  title: 'Atom ve Periyodik Sistem',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧪',
            title: 'Organik Kimya',
            subtitle:
                'Karbon kimyası, hidrokarbonlar, alkan/alken/alkin, fonksiyonel gruplar, izomeri, kiralite, benzen, polimerler, biyomoleküller',
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/organik-kimya.html',
                  title: 'Organik Kimya',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🔷',
            title: 'Molekül Geometrisi (VSEPR)',
            subtitle:
                'Molekül şekilleri, elektron çiftleri, VSEPR, hibritleşme (sp/sp²/sp³), sigma/pi bağları, dipol momenti, polarite',
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/molekul-geometrisi.html',
                  title: 'Molekül Geometrisi',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧮',
            title: 'Mol ve Stokiyometri',
            subtitle:
                'Mol kavramı, Avogadro sayısı, molar kütle/hacim, denklem denkleştirme, mol oranları, sınırlayıcı bileşen, verim, kütle hesabı',
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/mol-stokiyometri.html',
                  title: 'Mol ve Stokiyometri',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Biyoloji dersinin 3D konu listesi.
class Edu3DBiyolojiScreen extends StatelessWidget {
  const Edu3DBiyolojiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.card(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.biotech_rounded,
                color: Color(0xFF16A34A), size: 22),
            const SizedBox(width: 8),
            Text(
              'Biyoloji',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: _ReorderList(
        storageKey: "biyoloji",
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _TopicCard(
            emoji: '🧠',
            title: 'Denetleyici ve Düzenleyici Sistem',
            subtitle: 'Sinir sistemi, hormonlar, refleks',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/denetleyici-duzenleyici-sistem.html',
                  title: 'Denetleyici ve Düzenleyici Sistem',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🦴',
            title: 'Destek ve Hareket Sistemi',
            subtitle: 'Kemikler, kaslar, eklemler',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/destek-hareket-sistemi.html',
                  title: 'Destek ve Hareket Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🍽️',
            title: 'Sindirim Sistemi',
            subtitle: 'Ağız, mide, bağırsaklar, sindirim',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/sindirim-sistemi.html',
                  title: 'Sindirim Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🫀',
            title: 'Dolaşım Sistemi',
            subtitle: 'Kalp, damarlar, kan, dolaşım',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/dolasim-sistemi.html',
                  title: 'Dolaşım Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🫘',
            title: 'Boşaltım Sistemi',
            subtitle: 'Böbrek, nefron, idrar, mesane',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/bosaltim-sistemi.html',
                  title: 'Boşaltım Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🌱',
            title: 'Üreme Sistemi ve Embriyonal Gelişim',
            subtitle: 'Erkek/kadın üreme, gametler, döllenme, gebelik',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/ureme-sistemi.html',
                  title: 'Üreme Sistemi',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔬',
            title: 'Hücre ve Organelleri',
            subtitle: 'Hayvan/bitki hücresi, çekirdek, mitokondri, organeller',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/hucre-organeller.html',
                  title: 'Hücre ve Organelleri',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧬',
            title: 'DNA Yapısı ve Replikasyon',
            subtitle: 'Çift sarmal, nükleotit, replikasyon, RNA, protein sentezi',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/dna-replikasyon.html',
                  title: 'DNA Yapısı ve Replikasyon',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔬',
            title: 'Mitoz ve Mayoz Bölünme',
            subtitle: 'Hücre döngüsü, mitoz/mayoz evreleri, krossing-over, gametler',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/mitoz-mayoz.html',
                  title: 'Mitoz ve Mayoz Bölünme',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌿',
            title: 'Bitki Anatomisi',
            subtitle: 'Bitkisel dokular, kök/gövde kesitleri, yaprak, stoma ve terleme',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/bitki-anatomisi.html',
                  title: 'Bitki Anatomisi',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌞',
            title: 'Fotosentez',
            subtitle: 'Kloroplast, ışık reaksiyonları, Calvin döngüsü, C3/C4/CAM',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/fotosentez.html',
                  title: 'Fotosentez',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌍',
            title: 'Ekosistem ve Besin Zinciri',
            subtitle: 'Üretici/tüketici/ayrıştırıcı, besin ağı, enerji piramidi, madde döngüleri',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/ekosistem-besin-zinciri.html',
                  title: 'Ekosistem ve Besin Zinciri',
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧬',
            title: 'Kalıtım, Genotip ve Fenotip',
            subtitle: 'DNA→kromozom, Mendel yasaları, çaprazlamalar, kan grupları, X\'e bağlı kalıtım',
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const Lesson3DScreen(
                  assetHtml: 'assets/kalitim-genotip-fenotip.html',
                  title: 'Kalıtım, Genotip ve Fenotip',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  const _TopicCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppPalette.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill,
                  color: Color(0xFFFFB627), size: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _SubjectCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.card(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppPalette.textSecondary(context)),
            ],
          ),
        ),
      ),
    );
  }
}

