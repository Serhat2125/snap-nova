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
              '3D Eğitim Modelleri'.tr(),
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
            tooltip: 'Ayarlar'.tr(),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/gecis-studyosu.html',
                  title: 'Ayarlar'.tr(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _ReorderList(
        storageKey: 'subjects',
        children: [
          // DENEME (tasarım kararı): Coğrafya yeni sayfaya gitmez — konular
          // kartın altında akordeon olarak açılır/kapanır. Beğenilirse
          // diğer derslere de uygulanacak.
          _ExpandableSubjectCard(
            icon: Icons.public_rounded,
            title: 'Coğrafya'.tr(),
            color: const Color(0xFF0EA5E9),
          ),
          _SubjectCard(
            icon: Icons.calculate_rounded,
            title: 'Matematik'.tr(),
            color: const Color(0xFFF97316),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DMatematikScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.category_rounded,
            title: 'Geometrik Cisimler'.tr(),
            color: const Color(0xFFEAB308),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DGeometriScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.biotech_rounded,
            title: 'Biyoloji'.tr(),
            color: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DBiyolojiScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.science_rounded,
            title: 'Fizik'.tr(),
            color: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Edu3DFizikScreen()),
            ),
          ),
          _SubjectCard(
            icon: Icons.science_outlined,
            title: 'Kimya'.tr(),
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

/// Ders kartı + altında akordeon konu listesi (yeni sayfaya gitmeden).
/// İlk dokunuş konuları kartın altında açar, ikinci dokunuş kapatır.
/// Şimdilik yalnız Coğrafya'da kullanılıyor (tasarım denemesi).
class _ExpandableSubjectCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _ExpandableSubjectCard({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  State<_ExpandableSubjectCard> createState() => _ExpandableSubjectCardState();
}

class _ExpandableSubjectCardState extends State<_ExpandableSubjectCard> {
  bool _open = false;

  void _push(BuildContext context, String asset, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Lesson3DScreen(assetHtml: asset, title: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          children: [
            _SubjectCard(
              icon: widget.icon,
              title: widget.title,
              color: widget.color,
              onTap: () => setState(() => _open = !_open),
            ),
            // Açık/kapalı göstergesi — kartın sağında dönen ok.
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.chevron_right_rounded,
                      color: widget.color, size: 22),
                ),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
                  child: Column(
                    children: [
                      _TopicCard(
                        emoji: '🌍',
                        title: 'Dünyanın Şekli ve Hareketi'.tr(),
                        subtitle: 'Gece-gündüz, mevsimler, Güneş sistemi'.tr(),
                        tint: const Color(0xFF0EA5E9),
                        onTap: () => _push(context,
                            'assets/dunyanin-hareketleri.html',
                            'Dünyanın Şekli ve Hareketi'),
                      ),
                      const SizedBox(height: 8),
                      _TopicCard(
                        emoji: '🗺️',
                        title: 'Yer Şekilleri ve İzohipsler'.tr(),
                        subtitle:
                            'İzohips kuralları, eğim, profil, vadi/sırt, delta, plato/ova'.tr(),
                        tint: const Color(0xFF0EA5E9),
                        onTap: () => _push(context,
                            'assets/yer-sekilleri-izohipsler.html',
                            'Yer Şekilleri ve İzohipsler'),
                      ),
                      const SizedBox(height: 8),
                      _TopicCard(
                        emoji: '🌋',
                        title: 'Yerin İç Yapısı ve Levha Tektoniği'.tr(),
                        subtitle:
                            'Katmanlar, kıvrım/kırık dağlar, volkanizma, levha sınırları, depremler'.tr(),
                        tint: const Color(0xFF0EA5E9),
                        onTap: () => _push(context,
                            'assets/yerin-ic-yapisi-levha-tektonigi.html',
                            'Yerin İç Yapısı ve Levha Tektoniği'),
                      ),
                      const SizedBox(height: 8),
                      _TopicCard(
                        emoji: '🌦️',
                        title: 'Atmosfer ve İklim'.tr(),
                        subtitle:
                            'Atmosfer katmanları, basınç merkezleri, Coriolis, küresel rüzgarlar'.tr(),
                        tint: const Color(0xFF38BDF8),
                        onTap: () => _push(context, 'assets/atmosfer-iklim.html',
                            'Atmosfer ve İklim'),
                      ),
                      const SizedBox(height: 8),
                      _TopicCard(
                        emoji: '🌍',
                        title: 'Dünya Coğrafyası'.tr(),
                        subtitle:
                            'İklim bölgeleri, kıtalar, dağlar, nehirler, boğazlar, kanallar, nüfus'.tr(),
                        tint: const Color(0xFF22C55E),
                        onTap: () => _push(context,
                            'assets/dunya-cografyasi.html', 'Dünya Coğrafyası'),
                      ),
                    ],
                  ),
                ),
        ),
      ],
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
              'Coğrafya'.tr(),
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
            title: 'Dünyanın Şekli ve Hareketi'.tr(),
            subtitle: 'Gece-gündüz, mevsimler, Güneş sistemi'.tr(),
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/dunyanin-hareketleri.html',
                  title: 'Dünyanın Şekli ve Hareketi'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🗺️',
            title: 'Yer Şekilleri ve İzohipsler'.tr(),
            subtitle: 'İzohips kuralları, eğim, profil, vadi/sırt, delta, plato/ova'.tr(),
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/yer-sekilleri-izohipsler.html',
                  title: 'Yer Şekilleri ve İzohipsler'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌋',
            title: 'Yerin İç Yapısı ve Levha Tektoniği'.tr(),
            subtitle: 'Katmanlar, kıvrım/kırık dağlar, volkanizma, levha sınırları, depremler'.tr(),
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/yerin-ic-yapisi-levha-tektonigi.html',
                  title: 'Yerin İç Yapısı ve Levha Tektoniği'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌦️',
            title: 'Atmosfer ve İklim'.tr(),
            subtitle: 'Atmosfer katmanları, basınç merkezleri, Coriolis, küresel rüzgarlar'.tr(),
            tint: const Color(0xFF38BDF8),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/atmosfer-iklim.html',
                  title: 'Atmosfer ve İklim'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌍',
            title: 'Dünya Coğrafyası'.tr(),
            subtitle: 'İklim bölgeleri, kıtalar, dağlar, nehirler, boğazlar, kanallar, nüfus'.tr(),
            tint: const Color(0xFF22C55E),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/dunya-cografyasi.html',
                  title: 'Dünya Coğrafyası'.tr(),
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
              'Matematik'.tr(),
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
            title: 'Üslü Sayılar'.tr(),
            subtitle: 'Üs, taban, kuvvet kuralları, 3B görselleştirme'.tr(),
            tint: const Color(0xFF6366F1),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/uslu-sayilar.html',
                  title: 'Üslü Sayılar'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🟰',
            title: 'Denklemler'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFF8B5CF6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/denklemler.html',
                  title: 'Denklemler'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧮',
            title: 'Problemler'.tr(),
            subtitle: 'Sözel problemler, kurulum ve çözüm adımları'.tr(),
            tint: const Color(0xFFEC4899),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/problemler.html',
                  title: 'Problemler'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔵',
            title: 'Kümeler'.tr(),
            subtitle: 'Küme işlemleri, Venn şemaları, 3B görselleştirme'.tr(),
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/kumeler.html',
                  title: 'Kümeler'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📈',
            title: 'Fonksiyonlar'.tr(),
            subtitle: 'Fonksiyon kavramı, grafikler ve dönüşümler'.tr(),
            tint: const Color(0xFF10B981),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/fonksiyonlar.html',
                  title: 'Fonksiyonlar'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔣',
            title: 'Polinomlar'.tr(),
            subtitle: 'Polinom işlemleri, çarpanlara ayırma, 3B görselleştirme'.tr(),
            tint: const Color(0xFFF59E0B),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/polinomlar.html',
                  title: 'Polinomlar'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧠',
            title: 'Mantık'.tr(),
            subtitle: 'Önermeler, bağlaçlar, doğruluk tabloları'.tr(),
            tint: const Color(0xFF8B5CF6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/mantik.html',
                  title: 'Mantık'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📚',
            title: 'Temel Kavramlar'.tr(),
            subtitle: 'Sayılar, kümeler ve temel matematik kavramları'.tr(),
            tint: const Color(0xFF14B8A6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/temel-kavramlar.html',
                  title: 'Temel Kavramlar'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '➗',
            title: 'Kesirler ve Rasyonel Sayılar'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFF14B8A6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/kesirler-rasyonel.html',
                  title: 'Kesirler ve Rasyonel Sayılar'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '➗',
            title: 'Bölme ve Bölünebilme'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFF6366F1),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/bolme-bolunebilme.html',
                  title: 'Bölme ve Bölünebilme'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '⚖️',
            title: 'Basit Eşitsizlikler'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFFEC4899),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/basit-esitsizlikler.html',
                  title: 'Basit Eşitsizlikler'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🔢',
            title: 'Sayı Basamakları'.tr(),
            subtitle: 'Basamak değeri ve sayı çözümleme'.tr(),
            tint: const Color(0xFFFFC857),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/sayi-basamaklari.html',
                  title: 'Sayı Basamakları'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '√',
            title: 'Köklü Sayılar'.tr(),
            subtitle: 'Kök, üs ve rasyonel ifadeler — 3B sahneler'.tr(),
            tint: const Color(0xFF22C55E),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/koklu-sayilar.html',
                  title: 'Köklü Sayılar'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '|x|',
            title: 'Mutlak Değer'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFFF59E0B),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/mutlak-deger.html',
                  title: 'Mutlak Değer'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔀',
            title: 'Permütasyon ve Kombinasyon'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFF14B8A6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/permutasyon-kombinasyon.html',
                  title: 'Permütasyon ve Kombinasyon'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📐',
            title: 'İkinci Dereceden Denklemler'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFFEF4444),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/ikinci-dereceden-denklemler.html',
                  title: 'İkinci Dereceden Denklemler'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🎲',
            title: 'Olasılık'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFF8B5CF6),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/olasilik.html',
                  title: 'Olasılık'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📊',
            title: 'Veri ve İstatistik'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFF0EA5E9),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/veri-istatistik.html',
                  title: 'Veri ve İstatistik'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '📐',
            title: 'Geometri'.tr(),
            subtitle: '10 konu × 5 seviye, 3B sahneler, parametrik test'.tr(),
            tint: const Color(0xFFEC4899),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/geometri.html',
                  title: 'Geometri'.tr(),
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
              'Geometrik Cisimler'.tr(),
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
            title: 'Geometrik Cisimler ve Hesaplamalar'.tr(),
            subtitle: 'Küp, prizma, silindir, koni, küre — hacim & alan'.tr(),
            tint: const Color(0xFFEAB308),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/geometrik-cisimler.html',
                  title: 'Geometrik Cisimler ve Hesaplamalar'.tr(),
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
              'Fizik'.tr(),
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
            title: 'Maddenin Yapısı ve Özellikleri'.tr(),
            subtitle: 'K-12 sınıf bazlı: İlkokul/Ortaokul/Lise — duyular, haller, tanecikler, atom, basınç, kuantum'.tr(),
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/maddenin-yapisi.html',
                  title: 'Maddenin Yapısı'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔦',
            title: 'Gölge Oluşumu ve Işığın Yayılması'.tr(),
            subtitle: 'Doğrusal yayılma, tam/yarı gölge, tutulmalar, iğne deliği kamerası'.tr(),
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/golge-olusumu-isik-yayilmasi.html',
                  title: 'Gölge Oluşumu ve Işığın Yayılması'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧭',
            title: 'Bileşke Kuvvet ve Vektörler'.tr(),
            subtitle: 'Vektörün bileşenleri, paralelkenar, dik/açılı kuvvetler, denge, eğik düzlem, bağıl hız'.tr(),
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/bileske-kuvvet-vektorler.html',
                  title: 'Bileşke Kuvvet ve Vektörler'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '⚙️',
            title: 'Basit Makineler'.tr(),
            subtitle: 'Kaldıraç, makara, palanga, eğik düzlem, vida, çıkrık, dişli — kuvvet kazancı ve verim'.tr(),
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/basit-makineler.html',
                  title: 'Basit Makineler'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🌊',
            title: 'Dalgalar'.tr(),
            subtitle: 'Temel kavramlar, dalga hızı, yansıma/kırılma/kırınım/girişim, ses/deprem dalgaları, Doppler, EM spektrum'.tr(),
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/dalgalar.html',
                  title: 'Dalgalar'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔍',
            title: 'Işığın Kırılması ve Mercekler'.tr(),
            subtitle: 'Kırılma, Snell, tam yansıma, prizma, mercekler, aynalar, göz, aydınlanma ve renk'.tr(),
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/optik-mercekler.html',
                  title: 'Işığın Kırılması ve Mercekler'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '⚡',
            title: 'Elektrik'.tr(),
            subtitle: 'Elektrostatik, yük, alan, potansiyel, devreler, Ohm, direnç, kondansatör, güç'.tr(),
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/elektrik.html',
                  title: 'Elektrik'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🌊',
            title: 'Basınç ve Kaldırma Kuvveti'.tr(),
            subtitle: 'Batma/yüzme, özkütle, Arşimet, katı/sıvı/açık hava basıncı, Pascal, bileşik kaplar, Bernoulli'.tr(),
            tint: const Color(0xFF7C3AED),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/akiskanlar-mekanigi.html',
                  title: 'Basınç ve Kaldırma Kuvveti'.tr(),
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
              'Kimya'.tr(),
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
            title: 'Atom Teorisi ve Kuantum Orbitalleri'.tr(),
            subtitle: 'Atom yapısı, modeller (Dalton→Bohr→Modern), Rutherford, izotop, iyon, Bohr/spektrum, kuantum sayıları, s/p/d/f orbitalleri'.tr(),
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/atom-teorisi-orbitaller.html',
                  title: 'Atom Teorisi ve Orbitaller'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🔗',
            title: 'Kimyasal Türler Arası Etkileşimler (Bağlar)'.tr(),
            subtitle:
                'İyonik/kovalent/metalik bağ, polar-apolar, NaCl örgü, London/dipol/iyon-dipol, hidrojen bağı, su ve buz'.tr(),
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/kimyasal-baglar.html',
                  title: 'Kimyasal Bağlar'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧪',
            title: 'Karışımlar ve Çözeltiler'.tr(),
            subtitle:
                'Saf madde/karışım, homojen-heterojen, çözünme, ayırma teknikleri, Tyndall, derişim, koligatif, ozmos, çözünürlük dengesi'.tr(),
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/karisimlar-cozeltiler.html',
                  title: 'Karışımlar ve Çözeltiler'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '⚗️',
            title: 'Kimyasal Tepkimeler ve Tepkime Hızı'.tr(),
            subtitle:
                'Tepkime belirtileri, kütlenin korunumu, bağ enerjisi, sentez/analiz/yanma/nötrleşme, çarpışma teorisi, aktivasyon enerjisi, katalizör'.tr(),
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/kimyasal-tepkimeler.html',
                  title: 'Kimyasal Tepkimeler'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '⚛️',
            title: 'Atom ve Periyodik Sistem'.tr(),
            subtitle:
                'Atomun yapısı, atom modelleri (Dalton→Bohr), katman dizilimi, spektrum, yörünge/orbital, kuantum sayıları, elektron dizilimi, periyodik bloklar'.tr(),
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/atom-periyodik.html',
                  title: 'Atom ve Periyodik Sistem'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧪',
            title: 'Organik Kimya'.tr(),
            subtitle:
                'Karbon kimyası, hidrokarbonlar, alkan/alken/alkin, fonksiyonel gruplar, izomeri, kiralite, benzen, polimerler, biyomoleküller'.tr(),
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/organik-kimya.html',
                  title: 'Organik Kimya'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🔷',
            title: 'Molekül Geometrisi (VSEPR)'.tr(),
            subtitle:
                'Molekül şekilleri, elektron çiftleri, VSEPR, hibritleşme (sp/sp²/sp³), sigma/pi bağları, dipol momenti, polarite'.tr(),
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/molekul-geometrisi.html',
                  title: 'Molekül Geometrisi'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧮',
            title: 'Mol ve Stokiyometri'.tr(),
            subtitle:
                'Mol kavramı, Avogadro sayısı, molar kütle/hacim, denklem denkleştirme, mol oranları, sınırlayıcı bileşen, verim, kütle hesabı'.tr(),
            tint: const Color(0xFFE11D48),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/mol-stokiyometri.html',
                  title: 'Mol ve Stokiyometri'.tr(),
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
              'Biyoloji'.tr(),
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
            title: 'Denetleyici ve Düzenleyici Sistem'.tr(),
            subtitle: 'Sinir sistemi, hormonlar, refleks'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/denetleyici-duzenleyici-sistem.html',
                  title: 'Denetleyici ve Düzenleyici Sistem'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🦴',
            title: 'Destek ve Hareket Sistemi'.tr(),
            subtitle: 'Kemikler, kaslar, eklemler'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/destek-hareket-sistemi.html',
                  title: 'Destek ve Hareket Sistemi'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🍽️',
            title: 'Sindirim Sistemi'.tr(),
            subtitle: 'Ağız, mide, bağırsaklar, sindirim'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/sindirim-sistemi.html',
                  title: 'Sindirim Sistemi'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🫀',
            title: 'Dolaşım Sistemi'.tr(),
            subtitle: 'Kalp, damarlar, kan, dolaşım'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/dolasim-sistemi.html',
                  title: 'Dolaşım Sistemi'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🫘',
            title: 'Boşaltım Sistemi'.tr(),
            subtitle: 'Böbrek, nefron, idrar, mesane'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/bosaltim-sistemi.html',
                  title: 'Boşaltım Sistemi'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🌱',
            title: 'Üreme Sistemi ve Embriyonal Gelişim'.tr(),
            subtitle: 'Erkek/kadın üreme, gametler, döllenme, gebelik'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/ureme-sistemi.html',
                  title: 'Üreme Sistemi'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔬',
            title: 'Hücre ve Organelleri'.tr(),
            subtitle: 'Hayvan/bitki hücresi, çekirdek, mitokondri, organeller'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/hucre-organeller.html',
                  title: 'Hücre ve Organelleri'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🧬',
            title: 'DNA Yapısı ve Replikasyon'.tr(),
            subtitle: 'Çift sarmal, nükleotit, replikasyon, RNA, protein sentezi'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/dna-replikasyon.html',
                  title: 'DNA Yapısı ve Replikasyon'.tr(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _TopicCard(
            emoji: '🔬',
            title: 'Mitoz ve Mayoz Bölünme'.tr(),
            subtitle: 'Hücre döngüsü, mitoz/mayoz evreleri, krossing-over, gametler'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/mitoz-mayoz.html',
                  title: 'Mitoz ve Mayoz Bölünme'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌿',
            title: 'Bitki Anatomisi'.tr(),
            subtitle: 'Bitkisel dokular, kök/gövde kesitleri, yaprak, stoma ve terleme'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/bitki-anatomisi.html',
                  title: 'Bitki Anatomisi'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌞',
            title: 'Fotosentez'.tr(),
            subtitle: 'Kloroplast, ışık reaksiyonları, Calvin döngüsü, C3/C4/CAM'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/fotosentez.html',
                  title: 'Fotosentez'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🌍',
            title: 'Ekosistem ve Besin Zinciri'.tr(),
            subtitle: 'Üretici/tüketici/ayrıştırıcı, besin ağı, enerji piramidi, madde döngüleri'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/ekosistem-besin-zinciri.html',
                  title: 'Ekosistem ve Besin Zinciri'.tr(),
                ),
              ),
            ),
          ),
          _TopicCard(
            emoji: '🧬',
            title: 'Kalıtım, Genotip ve Fenotip'.tr(),
            subtitle: 'DNA→kromozom, Mendel yasaları, çaprazlamalar, kan grupları, X\'e bağlı kalıtım'.tr(),
            tint: const Color(0xFF16A34A),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Lesson3DScreen(
                  assetHtml: 'assets/kalitim-genotip-fenotip.html',
                  title: 'Kalıtım, Genotip ve Fenotip'.tr(),
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
                  title.tr(),
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

