import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/gemini_service.dart';
import 'latex_text.dart';
import 'qualsar_numeric_loader.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  StudySuiteSheet — "Bu Soruyla İlgili" — 3 sekme tabanlı içerik merkezi
//
//  Sekmeler:
//   📝 Benzer Soruları Çöz     — 5 genişleyebilir soru kartı (çoktan seçmeli)
//   💡 Bilgi Kartları          — 3 açılabilir bilgi kartı (formül ya da özet)
//   🧠 Eşleştirme Kartları     — 6 çiftli hafıza oyunu, panelde oynanır
// ═══════════════════════════════════════════════════════════════════════════════

// ── Veri modelleri ────────────────────────────────────────────────────────────
class _SimilarQ {
  final String question;
  final String solution;
  _SimilarQ({required this.question, required this.solution});
}

class _InfoCardItem {
  final String title;
  final String content;
  _InfoCardItem({required this.title, required this.content});
}

class _MatchPair {
  final String term;
  final String definition;
  _MatchPair({required this.term, required this.definition});
}

class _SuiteData {
  final List<_SimilarQ>     questions;
  final List<_InfoCardItem> infoCards;
  final List<_MatchPair>    matchPairs;
  _SuiteData({
    required this.questions,
    required this.infoCards,
    required this.matchPairs,
  });

  factory _SuiteData.fromJson(Map<String, dynamic> j) {
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) fn) {
      final raw = j[key];
      if (raw is! List) return [];
      return raw.whereType<Map<String, dynamic>>().map(fn).toList();
    }
    return _SuiteData(
      questions: parse('similar_questions', (m) => _SimilarQ(
            question: m['question']?.toString() ?? '',
            solution: m['solution']?.toString() ?? '')),
      infoCards: parse('info_cards', (m) => _InfoCardItem(
            title:   m['title']?.toString()   ?? '',
            content: m['content']?.toString() ?? '')),
      matchPairs: parse('match_pairs', (m) => _MatchPair(
            term:       m['term']?.toString()       ?? '',
            definition: m['definition']?.toString() ?? '')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Giriş noktası
// ─────────────────────────────────────────────────────────────────────────────
class StudySuiteSheet {
  /// [cached] — daha önce üretilmiş JSON blob (varsa API çağrısı yapılmaz).
  /// [onFetched] — yeni üretildiğinde çağrılır; çağıran cache'e yazabilir.
  static void show(
    BuildContext context, {
    required String solution,
    required String subject,
    Map<String, dynamic>? cached,
    void Function(Map<String, dynamic> json)? onFetched,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      useSafeArea: true,
      builder: (_) => _StudySuiteContent(
        solution: solution,
        subject: subject,
        cached: cached,
        onFetched: onFetched,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Ana içerik widget'ı
// ─────────────────────────────────────────────────────────────────────────────
class _StudySuiteContent extends StatefulWidget {
  final String solution;
  final String subject;
  final Map<String, dynamic>? cached;
  final void Function(Map<String, dynamic>)? onFetched;
  const _StudySuiteContent({
    required this.solution,
    required this.subject,
    this.cached,
    this.onFetched,
  });

  @override
  State<_StudySuiteContent> createState() => _StudySuiteContentState();
}

class _StudySuiteContentState extends State<_StudySuiteContent> {
  _SuiteData? _data;
  bool    _loading = true;
  String? _error;

  // Hangi sekme paneli açık: null | 'questions' | 'videos' | 'notes'
  String? _activeSection;

  // Dersin sayısal/sözel oluşuna göre loader varyantı.
  QuAlsarLoaderVariant get _variant {
    final s = widget.subject.toLowerCase();
    final numeric = s.contains('matematik') ||
        s.contains('math') ||
        s.contains('geometri') || s.contains('geometry') ||
        s.contains('fizik') || s.contains('physics') ||
        s.contains('kimya') || s.contains('chem') ||
        s.contains('biyoloji') || s.contains('biolog') ||
        s.contains('istatistik') || s.contains('stats') ||
        s.contains('bilişim') || s.contains('informatics');
    return numeric
        ? QuAlsarLoaderVariant.numeric
        : QuAlsarLoaderVariant.verbal;
  }

  @override
  void initState() {
    super.initState();
    // Cache varsa anında göster, API çağrısı yapma.
    if (widget.cached != null) {
      _data = _SuiteData.fromJson(widget.cached!);
      _loading = false;
      return;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; _activeSection = null; });
    try {
      final json = await GeminiService.fetchStudySuite(
        solution: widget.solution,
        subject:  widget.subject,
      );
      // Yeni üretilen içeriği kalıcı saklaması için çağırana bildir.
      widget.onFetched?.call(json);
      if (mounted) setState(() { _data = _SuiteData.fromJson(json); _loading = false; });
    } on GeminiException catch (e) {
      if (mounted) setState(() { _error = e.userMessage.replaceAll('\n', ' '); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Veriler yüklenemedi.'; _loading = false; });
    }
  }

  void _toggleSection(String id) =>
      setState(() => _activeSection = _activeSection == id ? null : id);

  void _closeSection() =>
      setState(() => _activeSection = null);

  // ── Dış kabuk ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEEF1F6),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(
              color: Colors.black12,
              width: 1.2,
            ),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.97,
            minChildSize:     0.70,
            maxChildSize:     0.97,
            expand: false,
            builder: (_, scroll) => Column(
              children: [
                _buildHandle(),
                _buildHeader(),
                _divider(),
                Expanded(
                  child: _loading
                      ? _buildSkeleton()
                      : _error != null
                          ? _buildError()
                          : _buildContent(scroll),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Tutamaç ───────────────────────────────────────────────────────────────────
  Widget _buildHandle() => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Container(
      width: 38, height: 4,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  // ── Başlık satırı ─────────────────────────────────────────────────────────────
  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QuAlsarStaticBadge(size: 54, variant: _variant),
            const SizedBox(height: 8),
            const Text(
              'Konuyu Pekiştir',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: Icon(Icons.close_rounded,
                color: Colors.black.withValues(alpha: 0.55), size: 22),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    ),
  );

  Widget _divider() => Container(
    height: 1,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.12),
        Colors.transparent,
      ]),
    ),
  );

  // ── Yükleme — ders tipine göre sayısal/sözel dönen logo ─────────────────────
  Widget _buildSkeleton() {
    return QuAlsarNumericLoader(
      variant: _variant,
      primaryText: 'Konu Pekiştirme Hazırlanıyor',
      staticLabel: true,
    );
  }

  // ── Hata ──────────────────────────────────────────────────────────────────────
  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded,
              color: Colors.black.withValues(alpha: 0.40), size: 42),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Bir hata oluştu.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.black.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.5),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _fetch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.40)),
              ),
              child: const Text(
                'Tekrar Dene',
                style: TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ── 3 sekme + paneller ────────────────────────────────────────────────────────
  Widget _buildContent(ScrollController scroll) {
    final d = _data!;
    return ListView(
      controller: scroll,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
      children: [

        // ── SEKME 1: Benzer Sorular ───────────────────────────────────────────
        _SectionTab(
          icon:     Icons.quiz_rounded,
          color:    const Color(0xFF60A5FA),
          label:    'Benzer Soruları Çöz',
          count:    '${d.questions.length} soru',
          active:   _activeSection == 'questions',
          onTap:    () => _toggleSection('questions'),
        ),
        _SectionPanel(
          active:   _activeSection == 'questions',
          color:    const Color(0xFF60A5FA),
          title:    'Benzer Soruları Çöz',
          onClose:  _closeSection,
          child:    _buildQuestionsContent(d.questions),
        ),

        const SizedBox(height: 12),

        // ── SEKME 2: Bilgi Kartları ───────────────────────────────────────────
        _SectionTab(
          icon:   Icons.lightbulb_outline_rounded,
          color:  const Color(0xFFF59E0B),
          label:  'Bilgi Kartları',
          count:  '${d.infoCards.length} kart',
          active: _activeSection == 'info',
          onTap:  () => _toggleSection('info'),
        ),
        _SectionPanel(
          active:  _activeSection == 'info',
          color:   const Color(0xFFF59E0B),
          title:   'Bilgi Kartları',
          onClose: _closeSection,
          child:   _buildInfoCardsContent(d.infoCards),
        ),

        const SizedBox(height: 12),

        // ── SEKME 3: Eşleştirme Kartları 🧠 ──────────────────────────────────
        _SectionTab(
          icon:   Icons.style_rounded,
          color:  const Color(0xFF8B5CF6),
          label:  'Eşleştirme Kartları',
          count:  '${d.matchPairs.length} çift',
          active: _activeSection == 'match',
          onTap:  () => _toggleSection('match'),
        ),
        _SectionPanel(
          active:  _activeSection == 'match',
          color:   const Color(0xFF8B5CF6),
          title:   'Eşleştirme Kartları',
          onClose: _closeSection,
          child:   _MatchCardsPanel(
            key:   ValueKey(d.matchPairs.length),
            pairs: d.matchPairs,
          ),
        ),
      ],
    );
  }

  // ── Soru paneli içeriği ───────────────────────────────────────────────────────
  Widget _buildQuestionsContent(List<_SimilarQ> questions) {
    return Column(
      children: questions.asMap().entries.map((e) =>
        Padding(
          padding: EdgeInsets.only(bottom: e.key < questions.length - 1 ? 8 : 0),
          child: _SimilarQuestionCard(
            index:    e.key + 1,
            question: e.value.question,
            solution: e.value.solution,
          ),
        ),
      ).toList(),
    );
  }

  // ── Bilgi kartı paneli içeriği ────────────────────────────────────────────────
  Widget _buildInfoCardsContent(List<_InfoCardItem> cards) {
    return Column(
      children: cards.asMap().entries.map((e) =>
        Padding(
          padding: EdgeInsets.only(bottom: e.key < cards.length - 1 ? 8 : 0),
          child: _InfoCard(item: e.value),
        ),
      ).toList(),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
//  Sekme butonu
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTab extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   label;
  final String   count;
  final bool     active;
  final VoidCallback onTap;

  const _SectionTab({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: active
              ? const BorderRadius.vertical(top: Radius.circular(16))
              : BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? color.withValues(alpha: 0.60)
                : Colors.black.withValues(alpha: 0.14),
            width: active ? 1.4 : 1.0,
          ),
          boxShadow: active
              ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 12)]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: active ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? Colors.black : Colors.black.withValues(alpha: 0.78),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    count,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.80),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: active ? 0.25 : 0,
              duration: const Duration(milliseconds: 220),
              child: Icon(
                Icons.chevron_right_rounded,
                color: active ? color : Colors.black.withValues(alpha: 0.40),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sekme içerik paneli — animasyonlu, sağ üstte X butonu
// ─────────────────────────────────────────────────────────────────────────────
class _SectionPanel extends StatelessWidget {
  final bool     active;
  final Color    color;
  final String   title;
  final VoidCallback onClose;
  final Widget   child;

  const _SectionPanel({
    required this.active,
    required this.color,
    required this.title,
    required this.onClose,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: active
          ? AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: active ? 1.0 : 0.0,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 0),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                  border: Border(
                    left:   BorderSide(color: color.withValues(alpha: 0.50), width: 1.3),
                    right:  BorderSide(color: color.withValues(alpha: 0.50), width: 1.3),
                    bottom: BorderSide(color: color.withValues(alpha: 0.50), width: 1.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Panel başlık satırı — sağ üstte X
                    Row(
                      children: [
                        Icon(Icons.expand_less_rounded,
                            color: color.withValues(alpha: 0.60), size: 16),
                        const SizedBox(width: 5),
                        Text(
                          title,
                          style: TextStyle(
                            color: color.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const Spacer(),
                        // X butonu
                        GestureDetector(
                          onTap: onClose,
                          child: Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: color.withValues(alpha: 0.30), width: 1),
                            ),
                            child: Icon(Icons.close_rounded,
                                color: color.withValues(alpha: 0.80), size: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    child,
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Benzer Soru Kartı — tıklayınca çözüm açılır
// ─────────────────────────────────────────────────────────────────────────────
class _SimilarQuestionCard extends StatefulWidget {
  final int    index;
  final String question;
  final String solution;
  const _SimilarQuestionCard({
    required this.index,
    required this.question,
    required this.solution,
  });

  @override
  State<_SimilarQuestionCard> createState() => _SimilarQuestionCardState();
}

class _SimilarQuestionCardState extends State<_SimilarQuestionCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<double>   _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _fade   = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _rotate = Tween<double>(begin: 0.0, end: 0.5).animate(_fade);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  // "Soru\nA) ..\nB) ..." → ["Soru", ["A) ..", "B) ..", ...]]
  String get _questionStem {
    final idx = widget.question.indexOf('\n');
    return idx < 0 ? widget.question.trim() : widget.question.substring(0, idx).trim();
  }

  List<String> get _options {
    final idx = widget.question.indexOf('\n');
    if (idx < 0) return const [];
    return widget.question
        .substring(idx + 1)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF60A5FA);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _expanded
            ? accent.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _expanded
              ? accent.withValues(alpha: 0.50)
              : Colors.black.withValues(alpha: 0.14),
          width: _expanded ? 1.3 : 1.0,
        ),
        boxShadow: _expanded
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(14),
          splashColor: accent.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Numara
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '${widget.index}',
                          style: const TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Soru metni (ilk satır) + şıklar (sonraki satırlar)
                          Text(
                            _questionStem,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                          if (_options.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            for (final opt in _options)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  opt,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RotationTransition(
                          turns: _rotate,
                          child: Icon(
                            Icons.expand_more_rounded,
                            color: _expanded
                                ? accent
                                : Colors.black.withValues(alpha: 0.40),
                            size: 18,
                          ),
                        ),
                        if (!_expanded)
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Text(
                              'Çözümü Göster',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Çözüm — animasyonlu genişle
                SizeTransition(
                  sizeFactor: _fade,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: _fade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Container(height: 1, color: accent.withValues(alpha: 0.20)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.lightbulb_outline_rounded,
                                color: accent, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'Çözüm',
                              style: TextStyle(
                                color: accent.withValues(alpha: 0.80),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LatexText(widget.solution, fontSize: 13, lineHeight: 1.60),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bilgi Kartı — formül ya da özet; tıklayınca genişler, LaTeX render eder
// ─────────────────────────────────────────────────────────────────────────────
class _InfoCard extends StatefulWidget {
  final _InfoCardItem item;
  const _InfoCard({required this.item});

  @override
  State<_InfoCard> createState() => _InfoCardState();
}

class _InfoCardState extends State<_InfoCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF59E0B);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _expanded ? accent.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _expanded
              ? accent.withValues(alpha: 0.50)
              : Colors.black.withValues(alpha: 0.14),
          width: _expanded ? 1.3 : 1.0,
        ),
        boxShadow: _expanded
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.lightbulb_outline_rounded,
                          color: accent, size: 17),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.item.title,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: accent,
                      size: 20,
                    ),
                  ],
                ),
                SizeTransition(
                  sizeFactor: _fade,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: _fade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Container(height: 1, color: accent.withValues(alpha: 0.22)),
                        const SizedBox(height: 10),
                        // LatexText: formülleri render eder, • maddeleri düz gösterir
                        LatexText(widget.item.content, fontSize: 13, lineHeight: 1.6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shimmer yükleme efekti
// ─────────────────────────────────────────────────────────────────────────────
class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.50, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, child) => Opacity(opacity: _anim.value, child: child),
    child: widget.child,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Eşleştirme Kartları — panel içinde oynanan hafıza oyunu
// ═══════════════════════════════════════════════════════════════════════════════
enum _MatchKind { term, definition }

class _MatchCard {
  final int         pairId;
  final _MatchKind  kind;
  final String      text;
  final bool        selected;   // ilk tıklama → turuncu
  final bool        matched;    // doğru eşleşme → yeşil
  final int         matchOrder; // 0 = henüz yok, 1+ = kaçıncı doğru eşleşme

  const _MatchCard({
    required this.pairId,
    required this.kind,
    required this.text,
    this.selected   = false,
    this.matched    = false,
    this.matchOrder = 0,
  });

  _MatchCard copyWith({bool? selected, bool? matched, int? matchOrder}) =>
      _MatchCard(
        pairId:     pairId,
        kind:       kind,
        text:       text,
        selected:   selected   ?? this.selected,
        matched:    matched    ?? this.matched,
        matchOrder: matchOrder ?? this.matchOrder,
      );
}

class _MatchCardsPanel extends StatefulWidget {
  final List<_MatchPair> pairs;
  const _MatchCardsPanel({super.key, required this.pairs});

  @override
  State<_MatchCardsPanel> createState() => _MatchCardsPanelState();
}

class _MatchCardsPanelState extends State<_MatchCardsPanel> {
  late List<_MatchCard> _cards;
  int?   _firstIdx;
  int    _moves   = 0;
  int    _matched = 0;
  bool   _locked  = false;

  @override
  void initState() {
    super.initState();
    _setupCards();
  }

  void _setupCards() {
    final list = <_MatchCard>[];
    for (int i = 0; i < widget.pairs.length; i++) {
      final p = widget.pairs[i];
      if (p.term.isEmpty || p.definition.isEmpty) continue;
      list.add(_MatchCard(pairId: i, kind: _MatchKind.term,       text: p.term));
      list.add(_MatchCard(pairId: i, kind: _MatchKind.definition, text: p.definition));
    }
    list.shuffle(math.Random());
    _cards    = list;
    _firstIdx = null;
    _moves    = 0;
    _matched  = 0;
    _locked   = false;
  }

  void _restart() {
    setState(_setupCards);
  }

  void _onTap(int idx) {
    if (_locked) return;
    final card = _cards[idx];
    if (card.matched || card.selected) return;

    HapticFeedback.selectionClick();
    setState(() => _cards[idx] = card.copyWith(selected: true));

    if (_firstIdx == null) {
      _firstIdx = idx;
      return;
    }

    final first   = _cards[_firstIdx!];
    final second  = _cards[idx];
    final isMatch = first.pairId == second.pairId && _firstIdx != idx;
    setState(() => _moves++);

    if (isMatch) {
      HapticFeedback.mediumImpact();
      setState(() {
        _matched++;
        _cards[_firstIdx!] = first.copyWith(
          matched: true,
          selected: false,
          matchOrder: _matched,
        );
        _cards[idx] = second.copyWith(
          matched: true,
          selected: false,
          matchOrder: _matched,
        );
        _firstIdx = null;
      });
    } else {
      _locked = true;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _cards[_firstIdx!] = _cards[_firstIdx!].copyWith(selected: false);
          _cards[idx]        = _cards[idx].copyWith(selected: false);
          _firstIdx = null;
          _locked = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total     = widget.pairs.length;
    final completed = _matched >= total && total > 0;

    if (widget.pairs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'Bu soru için eşleştirme çifti bulunamadı.',
            style: GoogleFonts.inter(
              color: Colors.black.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── İstatistik satırı ───────────────────────────────────────────────
        Row(
          children: [
            _StatChip(
              icon:  Icons.swap_horiz_rounded,
              label: 'Hamle',
              value: '$_moves',
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(width: 8),
            _StatChip(
              icon:  Icons.check_circle_rounded,
              label: 'Eşleşme',
              value: '$_matched / $total',
              color: const Color(0xFF22C55E),
            ),
            const Spacer(),
            if (_moves > 0)
              GestureDetector(
                onTap: _restart,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.40),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.replay_rounded,
                          color: Color(0xFF8B5CF6), size: 13),
                      const SizedBox(width: 4),
                      Text(
                        'Sıfırla',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF8B5CF6),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Kazandın mesajı ────────────────────────────────────────────────
        if (completed)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF22C55E).withValues(alpha: 0.50),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    color: Color(0xFF22C55E), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tebrikler! Tüm çiftleri $_moves hamlede eşleştirdin 🎉',
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Kart ızgarası — yatayda 4 sütun, kartlar baştan açık. ─────────
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.78,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _cards.length,
          itemBuilder: (_, i) => _MatchCardTile(
            card:  _cards[i],
            onTap: () => _onTap(i),
          ),
        ),
      ],
    );
  }
}

// ─── Mikro istatistik çipi (panel içi) ──────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.black.withValues(alpha: 0.14), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.black54,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tek kart — flip animasyonlu ────────────────────────────────────────────
class _MatchCardTile extends StatelessWidget {
  final _MatchCard   card;
  final VoidCallback onTap;

  const _MatchCardTile({required this.card, required this.onTap});

  void _openExpandedDialog(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      barrierDismissible: true,
      barrierLabel: 'card',
      transitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => _ExpandedCardDialog(card: card),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTerm = card.kind == _MatchKind.term;
    // Renk durumları: matched > selected > idle.
    final Color bgColor;
    final Color borderCol;
    final List<BoxShadow> shadow;
    if (card.matched) {
      bgColor   = const Color(0xFFDCFCE7); // açık yeşil
      borderCol = const Color(0xFF22C55E);
      shadow = [
        BoxShadow(
          color: const Color(0xFF22C55E).withValues(alpha: 0.30),
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ];
    } else if (card.selected) {
      bgColor   = const Color(0xFFFFEDD5); // açık turuncu
      borderCol = const Color(0xFFF97316);
      shadow = [
        BoxShadow(
          color: const Color(0xFFF97316).withValues(alpha: 0.30),
          blurRadius: 10,
          spreadRadius: 1,
        ),
      ];
    } else {
      bgColor   = Colors.white;
      borderCol = Colors.black;
      shadow = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    }
    final labelCol = isTerm ? const Color(0xFF8B5CF6) : const Color(0xFF3B82F6);

    // Metin kart yüzüne sığmıyorsa tek tıkla da büyüt — kabaca uzunluk eşiği.
    final textOverflows = card.text.length > 28;
    return GestureDetector(
      onTap: () {
        onTap();
        if (textOverflows && !card.matched) {
          _openExpandedDialog(context);
        }
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _openExpandedDialog(context);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderCol,
                width: (card.matched || card.selected) ? 1.8 : 1.2,
              ),
              boxShadow: shadow,
            ),
            padding: const EdgeInsets.all(7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: labelCol.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    isTerm ? 'TERİM' : 'TANIM',
                    style: GoogleFonts.inter(
                      color: labelCol,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: Center(
                    child: Text(
                      card.text,
                      textAlign: TextAlign.center,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontSize: isTerm ? 11.5 : 10,
                        fontWeight:
                            isTerm ? FontWeight.w800 : FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Eşleşme sıra numarası rozeti — sağ üstte (sadece eşleşmiş kartlarda)
          if (card.matchOrder > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.6),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '${card.matchOrder}',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Büyütülmüş kart dialog'u — basılı tutunca veya uzun metinde tek
// tıkla açılır. Açılışta büyür, kapanışta küçülerek kaybolur.
class _ExpandedCardDialog extends StatefulWidget {
  final _MatchCard card;
  const _ExpandedCardDialog({required this.card});

  @override
  State<_ExpandedCardDialog> createState() => _ExpandedCardDialogState();
}

class _ExpandedCardDialogState extends State<_ExpandedCardDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scale = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _ctrl.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final isTerm = card.kind == _MatchKind.term;
    final labelCol = isTerm ? const Color(0xFF8B5CF6) : const Color(0xFF3B82F6);
    final Color bgColor;
    final Color borderCol;
    if (card.matched) {
      bgColor   = const Color(0xFFDCFCE7);
      borderCol = const Color(0xFF22C55E);
    } else if (card.selected) {
      bgColor   = const Color(0xFFFFEDD5);
      borderCol = const Color(0xFFF97316);
    } else {
      bgColor   = Colors.white;
      borderCol = Colors.black;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.center,
        child: FadeTransition(
          opacity: _ctrl,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Kart gövdesi
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderCol, width: 1.8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: labelCol.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Text(
                              isTerm ? 'TERİM' : 'TANIM',
                              style: GoogleFonts.inter(
                                color: labelCol,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            card.text,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: Colors.black,
                              fontSize: isTerm ? 22 : 16,
                              fontWeight: isTerm
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Sağ üst köşe — kapatma butonu (X)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _close,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
