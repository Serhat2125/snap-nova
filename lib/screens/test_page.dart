import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../services/education_profile.dart';
import '../services/runtime_translator.dart';
import '../widgets/latex_text.dart';
import 'academic_planner.dart';

// Primary CTA color for the test flow (matches _orange in academic_planner.dart).
const _testOrange = Color(0xFFFF6A00);

// ═════════════════════════════════════════════════════════════════════════════
//  Test akışı — Questions mode'da özet yerine interaktif test.
//  1) TestPage: 10 soru tek listede, kullanıcı her biri için şık seçer.
//  2) Testi Bitir → TestResultPage: doğru/yanlış/boş + yanlış soruların çözümü.
// ═════════════════════════════════════════════════════════════════════════════

class TestQuestion {
  final String q;
  final Map<String, String> opts;
  final String ans;
  final String hint;
  final String sol;
  final String d;
  const TestQuestion({
    required this.q,
    required this.opts,
    required this.ans,
    required this.hint,
    required this.sol,
    required this.d,
  });

  factory TestQuestion.fromJson(Map<String, dynamic> j) {
    final rawOpts = j["opts"];
    final opts = <String, String>{};
    if (rawOpts is Map) {
      rawOpts.forEach((k, v) {
        if (v != null) opts[k.toString()] = v.toString();
      });
    }
    return TestQuestion(
      q: (j["q"] ?? "").toString().trim(),
      opts: opts,
      ans: (j["ans"] ?? "").toString().trim().toUpperCase(),
      hint: (j["hint"] ?? "").toString().trim(),
      sol: (j["sol"] ?? "").toString().trim(),
      d: (j["d"] ?? "medium").toString().trim(),
    );
  }
}

/// AI çıktısını temizleyip JSON array olarak parse eder.
List<TestQuestion> parseTestQuestions(String raw) {
  var s = raw.trim();
  // Markdown fence'leri sök
  if (s.startsWith("```")) {
    final firstNl = s.indexOf("\n");
    if (firstNl > -1) s = s.substring(firstNl + 1);
    final lastFence = s.lastIndexOf("```");
    if (lastFence > -1) s = s.substring(0, lastFence);
    s = s.trim();
  }
  // İlk "[" ile son "]" arası — ek metni kırp
  final start = s.indexOf("[");
  final end = s.lastIndexOf("]");
  if (start >= 0 && end > start) {
    s = s.substring(start, end + 1);
  }
  try {
    final decoded = jsonDecode(s);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => TestQuestion.fromJson(Map<String, dynamic>.from(e)))
          .where((q) => q.q.isNotEmpty && q.opts.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return const [];
}

// ═════════════════════════════════════════════════════════════════════════════

class TestPage extends StatefulWidget {
  final String rawContent;
  final String subjectName;
  final String topic;
  final Map<int, String?>? initialAnswers;
  final Future<void> Function(Map<int, String?> answers)? onFinish;
  // 0 = süresiz (relax). >0 = soru başına saniye (90 normal, 45 yarış).
  final int timeLimit;
  const TestPage({
    super.key,
    required this.rawContent,
    required this.subjectName,
    required this.topic,
    this.initialAnswers,
    this.onFinish,
    this.timeLimit = 0,
  });

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  late final List<TestQuestion> _questions;
  final Map<int, String?> _answers = {};
  int _idx = 0;
  bool _showHint = false;
  int _remaining = 0;
  Timer? _ticker;
  late final DateTime _startedAt;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _questions = parseTestQuestions(widget.rawContent);
    for (var i = 0; i < _questions.length; i++) {
      _answers[i] = widget.initialAnswers?[i];
    }
    _startTimerForCurrent();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTimerForCurrent() {
    _ticker?.cancel();
    if (widget.timeLimit <= 0 || _questions.isEmpty) return;
    _remaining = widget.timeLimit;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        // Süre doldu → cevap verilmediyse boş bırak ve sonraki soruya/bitire geç.
        _timeExpired();
      } else {
        setState(() => _remaining -= 1);
      }
    });
  }

  void _timeExpired() {
    if (_idx >= _questions.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _idx += 1;
      _showHint = false;
    });
    _startTimerForCurrent();
  }

  void _pick(String letter) {
    setState(() {
      if (_answers[_idx] == letter) {
        _answers[_idx] = null;
      } else {
        _answers[_idx] = letter;
      }
    });
  }

  void _goPrev() {
    if (_idx <= 0) return;
    setState(() {
      _idx -= 1;
      _showHint = false;
    });
    _startTimerForCurrent();
  }

  void _goNext() {
    if (_idx >= _questions.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _idx += 1;
      _showHint = false;
    });
    _startTimerForCurrent();
  }

  void _skip() {
    if (_idx >= _questions.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _answers[_idx] = null;
      _idx += 1;
      _showHint = false;
    });
    _startTimerForCurrent();
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    final answersSnapshot = Map<int, String?>.from(_answers);
    final elapsed = DateTime.now().difference(_startedAt);
    if (widget.onFinish != null) {
      await widget.onFinish!(answersSnapshot);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => TestResultPage(
        questions: _questions,
        answers: answersSnapshot,
        subjectName: widget.subjectName,
        topic: widget.topic,
        elapsedSeconds: elapsed.inSeconds,
        rawContent: widget.rawContent,
        onFinish: widget.onFinish,
        timeLimit: widget.timeLimit,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    const pageBg = Color(0xFFE8EAEF);
    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: pageBg,
          elevation: 0,
          foregroundColor: Colors.black,
          title: Text(
            widget.topic,
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Test verisi okunamadı. Lütfen bu konu için testi yeniden oluştur."
                  .tr(),
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.poppins(fontSize: 13, color: Colors.black54),
            ),
          ),
        ),
      );
    }
    final q = _questions[_idx];
    final selected = _answers[_idx];
    final progress = (_idx + 1) / _questions.length;
    final isLast = _idx == _questions.length - 1;
    final hasTimer = widget.timeLimit > 0;
    final timerLow = hasTimer && _remaining <= 10;
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subjectName,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
            Text(
              widget.topic,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          if (hasTimer)
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: timerLow
                      ? const Color(0xFFDC2626)
                      : _testOrange,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_rounded,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      _formatSeconds(_remaining),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.black12,
                color: Colors.black,
                minHeight: 4,
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Soru kartı ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          "Soru ${_idx + 1} / ${_questions.length}".tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Text(
                        _difficultyLabel(q.d).tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LatexText(q.q, fontSize: 15, lineHeight: 1.45),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ── Şıklar ──────────────────────────────────────────────
            for (final entry in q.opts.entries)
              _optionTile(
                letter: entry.key,
                text: entry.value,
                selected: selected == entry.key,
              ),
            // ── İpucu (açıkken gösterilir) ──────────────────────────
            if (_showHint && q.hint.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFAE8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("💡", style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        q.hint,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Alt bar — sol: ipucu, orta: geri + atla, sağ: sonraki/bitir
              Row(
                children: [
                  // İpucu butonu (sol)
                  _chipButton(
                    icon: Icons.lightbulb_outline_rounded,
                    label: _showHint
                        ? 'İpucunu gizle'.tr()
                        : 'İpucu'.tr(),
                    onTap: q.hint.isEmpty
                        ? null
                        : () => setState(() => _showHint = !_showHint),
                    dense: true,
                  ),
                  const Spacer(),
                  _chipButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Geri'.tr(),
                    onTap: _idx == 0 ? null : _goPrev,
                    dense: true,
                  ),
                  const SizedBox(width: 6),
                  _chipButton(
                    icon: Icons.redo_rounded,
                    label: 'Atla'.tr(),
                    onTap: _skip,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Ana ilerleme butonu — şık seçilince turuncu, değilse soluk
              GestureDetector(
                onTap: selected == null ? null : _goNext,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: selected == null
                        ? _testOrange.withValues(alpha: 0.35)
                        : _testOrange,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: selected == null
                        ? null
                        : [
                            BoxShadow(
                              color: _testOrange.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isLast
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isLast
                            ? 'Testi Bitir'.tr()
                            : 'Sonraki Soru'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSeconds(int s) {
    if (s <= 0) return '0:00';
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  String _difficultyLabel(String d) {
    switch (d.toLowerCase()) {
      case 'easy':
        return 'Kolay';
      case 'medium':
        return 'Orta';
      case 'hard':
        return 'Zor';
      default:
        return '';
    }
  }

  Widget _chipButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool dense = false,
  }) {
    final disabled = onTap == null;
    return Material(
      color: disabled
          ? const Color(0xFFEFF1F6)
          : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: dense ? 12 : 14, vertical: dense ? 8 : 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: disabled ? Colors.black38 : Colors.black),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: disabled ? Colors.black38 : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionTile({
    required String letter,
    required String text,
    required bool selected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pick(letter),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    letter,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      height: 1.4,
                      color: selected ? Colors.white : Colors.black,
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

// ═════════════════════════════════════════════════════════════════════════════
//  Test sonuç sayfası — doğru/yanlış/boş + yanlış çözümleri
// ═════════════════════════════════════════════════════════════════════════════

class TestResultPage extends StatefulWidget {
  final List<TestQuestion> questions;
  final Map<int, String?> answers;
  final String subjectName;
  final String topic;
  final int elapsedSeconds;
  // "Aynı soruları yeniden çöz" akışı için orijinal raw içerik. Verilmediğinde
  // butondan re-take yapılırken parse edilmiş questions JSON'a serialize edilir.
  final String? rawContent;
  // Yeniden çözüm bittiğinde answers + completed durumunu güncelleyebilmek için.
  // (academic_planner'dan gelen `_TestAttempt`'a yazıyor.)
  final Future<void> Function(Map<int, String?> answers)? onFinish;
  // Süre modu — yeniden çözüm aynı süre koşullarıyla başlasın.
  final int timeLimit;
  const TestResultPage({
    super.key,
    required this.questions,
    required this.answers,
    required this.subjectName,
    required this.topic,
    this.elapsedSeconds = 0,
    this.rawContent,
    this.onFinish,
    this.timeLimit = 0,
  });

  @override
  State<TestResultPage> createState() => _TestResultPageState();
}

class _TestResultPageState extends State<TestResultPage> {
  bool _showWrong = false;
  String _userName = '';
  String _grade = '';
  String _eduLabel = ''; // "Lise 11. Sınıf" / "YKS Hazırlık" / "İlkokul 2. Sınıf"
  final GlobalKey _cardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _userName = (p.getString('profile_name') ?? '').trim();
        _grade = (p.getString('user_grade_level') ?? '').trim();
      });
    });
    // Eğitim profilinden okunabilir seviye etiketi üret.
    EduProfile.load().then((profile) {
      if (!mounted || profile == null) return;
      setState(() {
        _eduLabel = _humanizeEduLevel(profile);
      });
    });
  }

  // EduProfile → "Lise 11. Sınıf" / "YKS Hazırlık" / "Ortaokul 8. Sınıf"
  // gibi okunabilir etiket. Sınav adıysa direkt sınav adını döndür.
  String _humanizeEduLevel(EduProfile p) {
    final level = p.level;
    final grade = p.grade.trim();
    String levelText;
    switch (level) {
      case 'primary':
        levelText = 'İlkokul';
        break;
      case 'middle':
        levelText = 'Ortaokul';
        break;
      case 'high':
        levelText = 'Lise';
        break;
      case 'exam_prep':
        // Sınava hazırlık — grade sınav anahtarıdır (yks_tyt, msu, kpss_ortaogretim...).
        if (grade.isEmpty) return 'Sınava Hazırlık';
        // Bilinen TR sınav anahtarları için temiz etiketler. Bilinmiyorsa
        // ilk kelimeyi büyütüp "Hazırlık" ekleriz (eski davranış).
        const examLabels = {
          'yks_tyt': 'YKS · TYT',
          'yks_ayt': 'YKS · AYT',
          'yks': 'YKS',
          'lgs': 'LGS',
          'msu': 'MSÜ',
          'kpss': 'KPSS Lisans',
          'kpss_ortaogretim': 'KPSS Ortaöğretim',
          'dgs': 'DGS',
          'pmyo': 'PMYO',
          'ales': 'ALES',
          'yds': 'YDS / YÖKDİL',
          'ielts': 'IELTS',
          'toefl': 'TOEFL',
        };
        final label = examLabels[grade.toLowerCase()];
        if (label != null) return '$label Hazırlık';
        // Uzun değerlerden ("YKS (Yükseköğretim...)") ilk kelime + Hazırlık.
        final short = grade.split(RegExp(r'[\s(]')).first.toUpperCase();
        return '$short Hazırlık';
      case 'university':
        levelText = 'Üniversite';
        break;
      case 'masters':
        levelText = 'Yüksek Lisans';
        break;
      case 'doctorate':
        levelText = 'Doktora';
        break;
      default:
        return grade.isEmpty ? '' : grade;
    }
    if (grade.isEmpty) return levelText;
    // Grade içinde rakam varsa "N. Sınıf" formatına getir.
    final m = RegExp(r'(\d{1,2})').firstMatch(grade);
    if (m != null) {
      return '$levelText ${m.group(1)}. Sınıf';
    }
    return '$levelText $grade';
  }

  int get _correct {
    int c = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      final a = widget.answers[i];
      if (a != null && a == widget.questions[i].ans) c++;
    }
    return c;
  }

  int get _wrong {
    int c = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      final a = widget.answers[i];
      if (a != null && a != widget.questions[i].ans) c++;
    }
    return c;
  }

  int get _empty {
    int c = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      if (widget.answers[i] == null) c++;
    }
    return c;
  }

  // Çözülemeyen (yanlış + boş) sorular.
  int get _unsolved => _wrong + _empty;

  @override
  Widget build(BuildContext context) {
    const pageBg = Color(0xFFE8EAEF);
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: Colors.black,
        titleSpacing: 0,
        title: const SizedBox.shrink(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // ── Ana sonuç kartı (paylaşım hedefi) ─────────────────────
          RepaintBoundary(
            key: _cardKey,
            child: _ResultCard(
              subjectName: widget.subjectName,
              topic: widget.topic,
              userName: _userName,
              grade: _grade,
              eduLabel: _eduLabel,
              correct: _correct,
              wrong: _wrong,
              empty: _empty,
              total: widget.questions.length,
              elapsedSeconds: widget.elapsedSeconds,
              bgColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          // ══ TÜM SEKMELER TEK ÇERÇEVEDE ══════════════════════════════
          //   Etrafı + boşluklar soluk beyaz; her sekme (action row) tam
          //   beyaz. Sıra: Sosyal medya → Arkadaşına gönder → Özetine
          //   bakmak ister misin → Yanlış yaptığın sorulara bak.
          _groupedFrame(
            children: [
              _actionRow(
                icon: Icons.ios_share_rounded,
                label: "Sosyal medyada paylaş".tr(),
                color: Colors.white,
                fg: Colors.black,
                onTap: () => _openShareMode(onFriend: false),
              ),
              const SizedBox(height: 10),
              _actionRow(
                icon: Icons.send_rounded,
                label: "Arkadaşına gönder".tr(),
                color: Colors.white,
                fg: Colors.black,
                iconColor: const Color(0xFF22C55E), // canlı yeşil
                iconRotation: -math.pi / 4, // 45° CCW → +X & +Y (NE)
                onTap: () => _openShareMode(onFriend: true),
              ),
              const SizedBox(height: 10),
              _actionRow(
                icon: Icons.menu_book_rounded,
                iconColor: const Color(0xFF2563EB),
                label: 'Konunun özetine bak'.tr(),
                color: Colors.white,
                fg: Colors.black,
                onTap: _openShortReview,
              ),
              const SizedBox(height: 10),
              _actionRow(
                icon: _showWrong
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.auto_stories_rounded,
                label: _unsolved == 0
                    ? "Tüm soruları çözdün — tebrikler!".tr()
                    : _showWrong
                        ? "Çözümleri gizle".tr()
                        : "Yanlış yaptığın sorulara bak".tr(),
                color: _unsolved == 0
                    ? const Color(0xFFEFF1F6)
                    : Colors.white,
                fg: _unsolved == 0 ? Colors.black54 : Colors.black,
                iconColor: _unsolved == 0
                    ? Colors.black54
                    : _testOrange,
                trailing: _unsolved == 0
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _testOrange,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          "$_unsolved",
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                onTap: _unsolved == 0
                    ? null
                    : () => setState(() => _showWrong = !_showWrong),
              ),
              if (_showWrong && _unsolved > 0) ...[
                const SizedBox(height: 12),
                ..._unsolvedAnswerCards(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // İki butonu sarmalayan kart — varsayılan soluk beyaz, isteğe bağlı bg.
  // Yanlış cevapların açıldığı durumda zemin beyaz olur (kart-üstü-kart
  // yerine düz beyaz sayfa hissi); o zaman kartların kendi kenarlıkları
  // ayrımı sağlar.
  Widget _groupedFrame({required List<Widget> children, Color? bgColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor ?? const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  void _openShareMode({required bool onFriend}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ShareModePage(
        subjectName: widget.subjectName,
        topic: widget.topic,
        userName: _userName,
        grade: _grade,
        eduLabel: _eduLabel,
        correct: _correct,
        wrong: _wrong,
        empty: _empty,
        total: widget.questions.length,
        elapsedSeconds: widget.elapsedSeconds,
        friendMode: onFriend,
      ),
    ));
  }

  // "Kısa bir tekrar yapmak ister misin?" → konu özetine yönlendir.
  // Özet varsa otomatik açılır; yoksa o konunun özet üretim akışı başlar.
  void _openShortReview() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AcademicPlanner(
        mode: LibraryMode.summary,
        autoOpenSubject: widget.subjectName,
        autoOpenTopic: widget.topic,
      ),
    ));
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required Color color,
    required Color fg,
    Widget? trailing,
    VoidCallback? onTap,
    Color? borderColor,
    Color? iconColor,
    double iconRotation = 0, // radyan; örn. pi/2 = 90° saat yönünde
  }) {
    final ic = iconColor ?? fg;
    Widget iconWidget = Icon(icon, color: ic, size: 18);
    if (iconRotation != 0) {
      iconWidget = Transform.rotate(angle: iconRotation, child: iconWidget);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 1)
              : null,
        ),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  List<Widget> _unsolvedAnswerCards() {
    final cards = <Widget>[];
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final a = widget.answers[i];
      if (a != null && a == q.ans) continue;
      final isEmpty = a == null;
      final badgeColor =
          isEmpty ? const Color(0xFF6B7280) : const Color(0xFFDC2626);
      final badgeLabel = isEmpty ? "Boş".tr() : "Yanlış".tr();
      // Şıkları sabit harf sırasıyla diz (A, B, C, D, E) — q.opts Map<String,
      // String> olduğu için key sırası garantili değil; sıralayıp listeliyoruz.
      final optionKeys = q.opts.keys.toList()..sort();
      cards.add(Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "Soru ${i + 1} · $badgeLabel",
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (isEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: const Color(0xFFD1D5DB), width: 1),
                    ),
                    child: Text(
                      "Boş bıraktın".tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF374151),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Sorunun tamamı
            LatexText(q.q, fontSize: 13, lineHeight: 1.45),
            const SizedBox(height: 12),
            // TÜM ŞIKLAR — kullanıcının seçtiği kırmızı, doğru olan yeşil,
            // diğerleri nötr. Hem soru bütünü görünür hem hangi şıkkın
            // doğru/yanlış olduğu net.
            for (int j = 0; j < optionKeys.length; j++) ...[
              if (j > 0) const SizedBox(height: 6),
              _optionTile(
                letter: optionKeys[j],
                text: q.opts[optionKeys[j]] ?? '',
                isUser: !isEmpty && optionKeys[j] == a,
                isCorrect: optionKeys[j] == q.ans,
              ),
            ],
            const SizedBox(height: 12),
            Container(
                height: 1, color: Colors.black.withValues(alpha: 0.08)),
            const SizedBox(height: 10),
            Text(
              "Çözüm".tr(),
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.black54,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
            LatexText(q.sol, fontSize: 12.5, lineHeight: 1.5),
          ],
        ),
      ));
    }
    return cards;
  }

  // Soru şıkkı kutucuğu — tüm şıklar listelenir; kullanıcının seçimi
  // kırmızı + "Senin cevabın", doğru cevap yeşil + "Doğru" rozeti.
  Widget _optionTile({
    required String letter,
    required String text,
    required bool isUser,
    required bool isCorrect,
  }) {
    Color bg, border, letterBg, ink;
    String? badge;
    if (isCorrect) {
      bg = const Color(0xFFDCFCE7);
      border = const Color(0xFF86EFAC);
      letterBg = const Color(0xFF059669);
      ink = const Color(0xFF064E3B);
      badge = "Doğru".tr();
    } else if (isUser) {
      bg = const Color(0xFFFEE2E2);
      border = const Color(0xFFFCA5A5);
      letterBg = const Color(0xFFDC2626);
      ink = const Color(0xFF7F1D1D);
      badge = "Senin cevabın".tr();
    } else {
      bg = Colors.white;
      border = const Color(0xFFE5E7EB);
      letterBg = const Color(0xFFF3F4F6);
      ink = const Color(0xFF374151);
      badge = null;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: letterBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              letter,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: (isCorrect || isUser)
                    ? Colors.white
                    : const Color(0xFF374151),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: text.trim().isEmpty
                ? Text(
                    "—",
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  )
                : LatexText(text, fontSize: 12.5, lineHeight: 1.4),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: letterBg,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                badge,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

}

// ═════════════════════════════════════════════════════════════════════════════
//  _ResultCard — paylaşılabilir, renklendirilebilir sonuç kartı.
//  Başlık (ders+konu+kullanıcı) + 4 stat tile + motivasyon mesajı.
// ═════════════════════════════════════════════════════════════════════════════
class _ResultCard extends StatelessWidget {
  final String subjectName;
  final String topic;
  final String userName;
  final String grade;
  final String eduLabel; // "Lise 11. Sınıf" / "YKS Hazırlık" gibi okunabilir
  final int correct;
  final int wrong;
  final int empty;
  final int total;
  final int elapsedSeconds;
  final Color bgColor;
  // ── Share-mode renk override'ları (null → otomatik / varsayılan) ──
  final Color? donutFrameOverride; // donut+lejant çerçevesi zemini
  final Color? textOverride;       // başlık/ders/konu/yüzde yazı rengi
  final Color? motivationOverride; // motivasyon kutusu yazı rengi
  final String? customMotivation;  // kullanıcının yazdığı özel mesaj

  const _ResultCard({
    required this.subjectName,
    required this.topic,
    required this.userName,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.total,
    required this.bgColor,
    this.grade = '',
    this.eduLabel = '',
    this.elapsedSeconds = 0,
    this.donutFrameOverride,
    this.textOverride,
    this.motivationOverride,
    this.customMotivation,
  });

  int get pct => total == 0 ? 0 : ((correct * 100) / total).round();

  // Zemin koyuysa beyaz metin, açıksa siyah metin.
  bool get _dark {
    final c = bgColor;
    final lum = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    return lum < 0.6;
  }

  Color get _ink => textOverride ?? (_dark ? Colors.white : Colors.black);
  Color get _inkMute =>
      textOverride?.withValues(alpha: 0.7) ??
      (_dark ? Colors.white70 : Colors.black54);
  // Motivasyon yazısı için ayrı renk — yoksa varsayılan _ink.
  Color get _motivationInk =>
      motivationOverride ?? (_dark ? Colors.white : Colors.black);

  // Sonucun her seferinde farklı bir motivasyon mesajı vermesi için
  // pool'lardan seed-bazlı seçim yapılır. Seed = doğru/yanlış/boş/süre
  // kombinasyonu → her test farklı bir mesaj alır, aynı test rebuild'lerinde
  // sabit kalır (UI titremez).
  int get _msgSeed =>
      correct * 17 + wrong * 7 + empty * 13 + elapsedSeconds * 31 + total * 3;

  static const _openersStart = [
    "Hadi başlayalım — ",
    "Bir nefes al ve oku — ",
    "Sana özel not — ",
    "Şunu unutma — ",
    "Buraya bak — ",
    "Küçük bir not — ",
    "Önce şunu söyleyeyim — ",
    "Aramızda kalsın — ",
    "İçten söylüyorum — ",
    "Şu anı tut — ",
    "Bir adım geri çekil — ",
    "Bu testten kalan şu — ",
  ];

  static const _openersHigh = [
    "Görüyor musun bunu — ",
    "Bu doğal değil, emek senin — ",
    "Şuna bayıldım — ",
    "İşte form bu — ",
    "Devam et böyle — ",
    "Bunu kaydet — ",
    "Ayağın yere bassın — ",
  ];

  static const _openersLow = [
    "Sıkıntı yok — ",
    "Bunu duyman lazım — ",
    "Şunu hatırla — ",
    "Buradan dönülür — ",
    "Acelesi yok — ",
    "Yumuşak başlayalım — ",
    "Bir kenara not düş — ",
  ];

  static const _msgsStart = [
    "Teste başla ve ilerlemeni gör!",
    "İlk soru en zor olanıdır — sonrası akar.",
    "Hazırsan başla; veriler senin için konuşacak.",
    "Atılan ilk adım, en değerli olanıdır.",
  ];

  static const _msgs90 = [
    "Harikasın! Neredeyse hatasız — bu konu artık senin.",
    "Bu seviye şans değil; konu kontrol altında.",
    "Tekrar bile fazla. Sıradaki konuya geçebilirsin.",
    "Üst düzey performans. Bunu sürdürmek tek hedef.",
    "Hatasıza çok yakınsın — pürüzü temizle, kapanır.",
    "Bu skor disiplinin yansıması. Tebrikler.",
  ];

  static const _msgs75 = [
    "Çok iyi! Temelin sağlam, biraz daha tekrar yeter.",
    "Form yerinde — eksik kalan birkaç detay var sadece.",
    "Genel resim oturmuş, dar boğazları belirle.",
    "Buradan zirveye 2-3 tekrar mesafedesin.",
    "Yanlış yaptıklarına bakınca ‘ah, oydu’ diyeceksin.",
    "Konuyu biliyorsun; şimdi hız + dikkat zamanı.",
  ];

  static const _msgs50 = [
    "İyi gidiyorsun. Yanlışlarına odaklan, hızla yükselirsin.",
    "Yarısı senin. Diğer yarısı, az tekrarla gelecek.",
    "Eksiklerin dağınık değil — toplu çalışırsan hızlı kapanır.",
    "Doğru yoldasın; sadece tempo biraz artmalı.",
    "Bu skor başlangıç değil, ısınma. Devam.",
  ];

  static const _msgs25 = [
    "Her yanlış yeni bir fırsat — çözümlere bak, tekrar dene.",
    "Konunun iskeleti eksik. Önce temele dön, sonra soruya gel.",
    "Yanlışlar zayıflık değil, yol haritası — dinle onları.",
    "Bu skor öğrenmenin başlangıç çizgisi. Geri çekilme.",
    "Çözümleri tek tek oku; yarın aynı sorulara dönüp tekrar gör.",
  ];

  static const _msgs0 = [
    "Başlangıç zor, pes etme. Birkaç tekrar her şeyi değiştirir.",
    "Sıfırdan başlamak utanılacak şey değil; vazgeçmek olur.",
    "Konuyu birkaç dakika oku, soruya öyle dön. Fark hissedilir.",
    "Bu sayfa final değil, ön rapor. Senin sıran yarın.",
    "Önce 3 soru anla, sonra 30 soru çöz — sıralama önemli.",
  ];

  String _pick(List<String> pool) => pool[_msgSeed % pool.length];

  String get _motivationOpener {
    if (total == 0) return _pick(_openersStart);
    if (pct >= 75) return _pick(_openersHigh);
    if (pct >= 50) return _pick(_openersStart);
    return _pick(_openersLow);
  }

  String get _motivationLine {
    if (total == 0) return _pick(_msgsStart).tr();
    if (pct >= 90) return _pick(_msgs90).tr();
    if (pct >= 75) return _pick(_msgs75).tr();
    if (pct >= 50) return _pick(_msgs50).tr();
    if (pct >= 25) return _pick(_msgs25).tr();
    return _pick(_msgs0).tr();
  }

  String get _motivationFull {
    final opener = _motivationOpener.tr();
    final body = _motivationLine;
    return '$opener$body';
  }

  // Süreyi okunaklı, matematiksel forma çevirir:
  //   65   → "1 dakika 5 saniye"
  //   120  → "2 dakika"
  //   42   → "42 saniye"
  //   3725 → "1 saat 2 dakika 5 saniye"
  //   0/-  → "—"
  String _formatDurationLong(int seconds) {
    if (seconds <= 0) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final parts = <String>[];
    if (h > 0) parts.add('$h ${'saat'.tr()}');
    if (m > 0) parts.add('$m ${'dakika'.tr()}');
    if (s > 0 || parts.isEmpty) parts.add('$s ${'saniye'.tr()}');
    return parts.join(' ');
  }

  // Motivasyon kutusunun başındaki ikon — ders/konuya göre değişir
  // (sabit 💫 yerine konuya yakışan emoji). Bilinmeyen ders → 💫.
  String _subjectEmoji() {
    final s = '$subjectName $topic'.toLowerCase();
    bool has(List<String> ks) => ks.any((k) => s.contains(k));
    if (has(['matematik', 'math', 'cebir'])) return '🧮';
    if (has(['geometri', 'trigon'])) return '📐';
    if (has(['fizik', 'physic'])) return '⚛️';
    if (has(['kimya', 'chem'])) return '🧪';
    if (has(['biyoloji', 'bio', 'genetik', 'hücre', 'dna'])) return '🧬';
    if (has(['türkçe', 'turkish'])) return '📖';
    if (has(['edebiyat', 'literature', 'lit', 'şiir', 'roman'])) return '✒️';
    if (has(['tarih', 'history', 'inkilap', 'devrim', 'osmanl'])) return '🏛️';
    if (has(['coğrafya', 'geography', 'iklim', 'harita'])) return '🌍';
    if (has(['felsefe', 'philo', 'mantık'])) return '🤔';
    if (has(['ingilizce', 'english', 'almanca', 'fransızca', 'spanish'])) {
      return '🗣️';
    }
    if (has(['din', 'kuran', 'islam'])) return '📿';
    if (has(['sanat', 'müzik', 'muzik', 'resim'])) return '🎨';
    if (has(['beden', 'spor'])) return '⚽';
    if (has(['psikoloji', 'psych'])) return '🧠';
    if (has(['sosyoloji', 'socio'])) return '👥';
    if (has(['hukuk', 'law', 'anayasa', 'ceza'])) return '⚖️';
    if (has(['iktisat', 'ekonomi', 'econom', 'finans', 'muhasebe'])) {
      return '💰';
    }
    if (has(['mühendislik', 'engineer', 'devre', 'malzeme'])) return '⚙️';
    if (has(['mimari', 'architecture'])) return '🏗️';
    if (has(['tıp', 'anatomi', 'fizyoloji', 'biyokimya', 'cerrahi'])) {
      return '🩺';
    }
    if (has(['eczacılık', 'farma'])) return '💊';
    if (has(['bilgisayar', 'computer', 'algoritma', 'yazılım'])) return '💻';
    if (has(['astronomi', 'uzay', 'gezegen', 'yıldız'])) return '🔭';
    if (has(['tarım', 'ziraat', 'bitki'])) return '🌱';
    return '💫';
  }

  // Üst satırda kullanıcı adının yanında çıkan dinamik başlık.
  // Başarı oranına göre ton değişir; %50 altı için tebrik DEĞİL, motive
  // edici / teselli edici ifadeler kullanılır.
  // ignore: unused_element
  ({String emoji, String text}) get _headlineGreeting {
    if (total == 0) return (emoji: '✨', text: 'Hazır mısın');
    if (pct >= 90) return (emoji: '🏆', text: 'Mükemmelsin');
    if (pct >= 75) return (emoji: '🎯', text: 'Çok başarılısın');
    if (pct >= 50) return (emoji: '🎉', text: 'Tebrikler');
    if (pct >= 25) return (emoji: '💪', text: 'Az kaldı');
    return (emoji: '🌱', text: 'Pes etme');
  }

  // QuAlsar marka kırmızısı (al kırmızı).
  static const Color _alKirmizi = Color(0xFFC8102E);

  String get _firstName {
    if (userName.isEmpty) return 'Siz';
    return userName.split(' ').first;
  }

  String get _userHandle {
    final trimmed = userName.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(' ').first.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: _dark ? Colors.white24 : Colors.black, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ══ En üst: SOL eduLabel + ders/konu · SAĞ profil ═════════
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Eğitim seviyesi rozeti + uygun ikon —
                      // "🎯 YKS Hazırlık", "🎓 Lise 11. Sınıf",
                      // "📚 İlkokul 2. Sınıf" vb.
                      if (eduLabel.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _alKirmizi.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _alKirmizi.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${_eduIcon()} ',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                TextSpan(
                                  text: eduLabel,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _alKirmizi,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ] else if (grade.isNotEmpty) ...[
                        // Profil okunamadıysa eski grade rozetine düş.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _alKirmizi.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _alKirmizi.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            grade.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _alKirmizi,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      _labeledLine(
                        label: 'Ders'.tr(),
                        value: subjectName,
                        icon: _subjectIcon(),
                      ),
                      const SizedBox(height: 5),
                      _labeledLine(
                        label: 'Konu'.tr(),
                        value: topic,
                        icon: _topicIcon(),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 22),
                _centeredUserBlock(),
              ],
            ),
            const SizedBox(height: 14),
            // ══ Donut grafiği + sağda lejant ════════════════════════
            _donutStats(),
            const SizedBox(height: 10),
            // ══ Motivasyon kutusu — kullanıcı özel mesaj yazdıysa onu
            //    göster, yoksa varsayılan motivasyon. Yazı rengi override
            //    edilebilir.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_subjectEmoji(), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (customMotivation != null &&
                              customMotivation!.trim().isNotEmpty)
                          ? customMotivation!
                          : _motivationFull,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _motivationInk,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            // ══ Footer: SOL stacked marka, SAĞ QR + "Uygulamayı indir" ══
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Sol: iki satır, SATIR BAŞLARI AYNI HİZADA
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QuAlsar ile çözüldü'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'qualsar.app',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: _alKirmizi,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Sağ: QR biraz sola çekili, "Uygulamayı indir" QR'ı
                //      yatayda tam ortalayacak şekilde üstünde.
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Uygulamayı indir'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.black12, width: 1),
                        ),
                        child: QrImageView(
                          data: 'https://qualsar.app',
                          version: QrVersions.auto,
                          size: 56,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Kartın üstünde ortada duran kullanıcı profili bloğu.
  Widget _centeredUserBlock() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar — ilk harf, büyük
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _alKirmizi,
            border: Border.all(
              color: _dark ? Colors.white24 : Colors.black,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _alKirmizi.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            _firstName.isEmpty
                ? '?'
                : _firstName.substring(0, 1).toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          userName.isEmpty ? 'Siz'.tr() : userName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _ink,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _userHandle.isEmpty ? '@sen' : '@$_userHandle',
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _inkMute,
          ),
        ),
      ],
    );
  }

  Widget _labeledLine({
    required String label,
    required String value,
    String? icon, // başlığın hemen önünde küçük emoji ikon
    int maxLines = 1,
  }) {
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          if (icon != null && icon.isNotEmpty) ...[
            TextSpan(
              text: '$icon ',
              style: const TextStyle(fontSize: 14),
            ),
          ],
          TextSpan(
            text: '$label: ',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _alKirmizi,
            ),
          ),
          TextSpan(
            text: value,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ink,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // Eğitim seviyesi etiketi → uygun emoji ikon. Sınava hazırlık → 🎯,
  // İlkokul → 📚, Ortaokul → 🎒, Lise → 🎓, Üniversite → 🏛️ vb.
  String _eduIcon() {
    final l = eduLabel.toLowerCase();
    if (l.contains('hazırlık') ||
        l.contains('yks') ||
        l.contains('lgs') ||
        l.contains('msü') ||
        l.contains('kpss') ||
        l.contains('ales')) {
      return '🎯';
    }
    if (l.contains('ilkokul')) return '📚';
    if (l.contains('ortaokul')) return '🎒';
    if (l.contains('lise')) return '🎓';
    if (l.contains('üniversite')) return '🏛️';
    if (l.contains('yüksek lisans')) return '📘';
    if (l.contains('doktora')) return '🔬';
    return '🎓';
  }

  // Ders adından konuya uygun emoji çıkar.
  String _subjectIcon() {
    final s = subjectName.toLowerCase();
    bool has(List<String> needles) => needles.any(s.contains);
    if (has(['matematik', 'math'])) return '🧮';
    if (has(['geometri'])) return '📐';
    if (has(['fizik', 'physics'])) return '⚡';
    if (has(['kimya', 'chem'])) return '🧪';
    if (has(['biyoloji', 'biology'])) return '🧬';
    if (has(['tarih', 'history'])) return '🏛️';
    if (has(['coğraf', 'cografya', 'geograph'])) return '🌍';
    if (has(['edebiyat', 'türk dili', 'türkçe', 'literature'])) return '✒️';
    if (has(['felsefe', 'philosoph'])) return '🧠';
    if (has(['din', 'religion'])) return '📿';
    if (has(['mantık', 'logic'])) return '🧩';
    if (has(['ingiliz', 'english', 'yabancı dil'])) return '🇬🇧';
    if (has(['müzik', 'music'])) return '🎵';
    if (has(['beden', 'pe', 'spor'])) return '⚽';
    if (has(['sanat', 'resim'])) return '🎨';
    if (has(['bilg', 'comp', 'teknoloji'])) return '💻';
    if (has(['astronomi', 'uzay'])) return '🔭';
    if (has(['ekonomi'])) return '💰';
    if (has(['hukuk', 'law'])) return '⚖️';
    if (has(['tıp', 'anatomi'])) return '🩺';
    if (has(['psikoloji', 'psych'])) return '🧠';
    if (has(['sosyoloji'])) return '👥';
    return '📚';
  }

  // Konu metninden uygun emoji çıkar (anahtar kelime taraması).
  String _topicIcon() {
    final t = topic.toLowerCase();
    bool has(List<String> needles) => needles.any(t.contains);
    // Matematik
    if (has(['türev', 'integral', 'limit'])) return '∫';
    if (has(['trigonometri', 'sinüs', 'kosinüs'])) return '📐';
    if (has(['geometri', 'üçgen', 'daire', 'açı'])) return '🔺';
    if (has(['logaritma', 'üslü', 'köklü'])) return '🧮';
    if (has(['olasılık', 'istatistik'])) return '🎲';
    // Fizik
    if (has(['hareket', 'kinematik'])) return '🚀';
    if (has(['kuvvet', 'newton', 'dinamik'])) return '⚙️';
    if (has(['elektrik', 'akım'])) return '⚡';
    if (has(['manyet'])) return '🧲';
    if (has(['dalga', 'ses', 'optik', 'ışık'])) return '🌊';
    if (has(['enerji', 'iş'])) return '🔋';
    if (has(['basınç', 'akışkan'])) return '💧';
    if (has(['isı', 'sıcaklık', 'termodinamik'])) return '🌡️';
    if (has(['atom', 'çekirdek', 'modern fizik', 'foto'])) return '⚛️';
    // Kimya
    if (has(['asit', 'baz'])) return '⚗️';
    if (has(['mol', 'tepkime', 'reaksiyon'])) return '🧪';
    if (has(['organik', 'hidrokarbon'])) return '🧬';
    // Biyoloji
    if (has(['hücre', 'mikro'])) return '🔬';
    if (has(['genetik', 'dna', 'kalıtım'])) return '🧬';
    if (has(['sinir', 'beyin'])) return '🧠';
    if (has(['dolaşım', 'kalp'])) return '❤️';
    if (has(['solunum', 'akciğer'])) return '🫁';
    if (has(['bitki', 'fotosentez'])) return '🌿';
    if (has(['evrim'])) return '🐒';
    if (has(['eko', 'çevre'])) return '🌱';
    // Tarih
    if (has(['savaş', 'ihtilal', 'devrim'])) return '⚔️';
    if (has(['antlaşma', 'anlaşma', 'lozan', 'sevr'])) return '📜';
    if (has(['osmanlı', 'selçuk', 'atatürk', 'cumhuriyet', 'kurtuluş'])) {
      return '🏛️';
    }
    // Coğrafya
    if (has(['iklim', 'hava'])) return '☁️';
    if (has(['harita', 'koordinat'])) return '🗺️';
    if (has(['nüfus', 'göç'])) return '👥';
    if (has(['deprem', 'tektonik'])) return '🌋';
    if (has(['akarsu', 'göl'])) return '🏞️';
    // Edebiyat / dil
    if (has(['şiir', 'divan', 'koşma'])) return '📜';
    if (has(['roman', 'öykü', 'hikaye'])) return '📖';
    if (has(['cümle', 'paragraf', 'dilbilgisi'])) return '🔤';
    // Genel
    return '📌';
  }

  // ════ Donut chart + yan lejant ═══════════════════════════════════
  //  Dilimler: Doğru (yeşil) · Yanlış (kırmızı) · Boş (gri).
  //  Ortada büyük "%pct" · altında "Başarı" · dilimlerin üstünde sayı/oran.
  Widget _donutStats() {
    const green = Color(0xFF059669);
    const red = Color(0xFFDC2626);
    const gray = Color(0xFF6B7280);

    int pctOf(int n) =>
        total == 0 ? 0 : ((n * 100) / total).round();

    final sections = <PieChartSectionData>[];
    void addSlice(int v, Color c) {
      if (v <= 0) return;
      final sp = pctOf(v);
      sections.add(PieChartSectionData(
        value: v.toDouble(),
        color: c,
        radius: 28,
        title: '$v\n%$sp',
        titleStyle: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.1,
        ),
        titlePositionPercentageOffset: 0.6,
      ));
    }

    addSlice(correct, green);
    addSlice(wrong, red);
    addSlice(empty, gray);

    // Hiç veri yoksa tek gri dilim (placeholder) ile göster.
    if (sections.isEmpty) {
      sections.add(PieChartSectionData(
        value: 1,
        color: gray.withValues(alpha: 0.3),
        radius: 28,
        title: '',
      ));
    }

    final dfBg = donutFrameOverride ??
        (_dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.025));
    final dfBorder = donutFrameOverride != null
        ? donutFrameOverride!.withValues(alpha: 0.45)
        : (_dark ? Colors.white12 : Colors.black12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: dfBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dfBorder, width: 1),
      ),
      child: Row(
        children: [
          // ── Sol: donut + ortada %başarı ──────────────────────
          SizedBox(
            width: 118,
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 28,
                    sectionsSpace: 2,
                    startDegreeOffset: -90,
                  ),
                ),
                // Ortadaki büyük yüzde — donut center hole.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '%$pct',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Başarı'.tr().toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 6.5,
                        fontWeight: FontWeight.w800,
                        color: _inkMute,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Sağ: lejant (sayı + yüzde) ───────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Süre — Doğru'nun ÜSTÜNDE, lejant satırlarıyla aynı
                // hizada (sol: ikon + etiket, sağ: "X dakika Y saniye").
                Row(
                  children: [
                    Icon(Icons.timer_rounded,
                        size: 12, color: _inkMute),
                    const SizedBox(width: 5),
                    Text(
                      'Süre'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _inkMute,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDurationLong(elapsedSeconds),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 1,
                  color: (_dark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.12),
                ),
                const SizedBox(height: 8),
                _legendItem(
                    color: green,
                    label: 'Doğru'.tr(),
                    count: correct,
                    pct: pctOf(correct)),
                const SizedBox(height: 8),
                _legendItem(
                    color: red,
                    label: 'Yanlış'.tr(),
                    count: wrong,
                    pct: pctOf(wrong)),
                const SizedBox(height: 8),
                _legendItem(
                    color: gray,
                    label: 'Boş'.tr(),
                    count: empty,
                    pct: pctOf(empty)),
                const SizedBox(height: 8),
                Container(
                  height: 1,
                  color: (_dark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.quiz_rounded,
                        size: 12, color: _inkMute),
                    const SizedBox(width: 5),
                    Text(
                      'Toplam'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _inkMute,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$total',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem({
    required Color color,
    required String label,
    required int count,
    required int pct,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
        Text(
          '$count',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '%$pct',
            style: GoogleFonts.poppins(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  _ShareModePage — sadece kart + 6 renk swatch + "Paylaş" butonu.
//  Renk seçilince kart zemini değişir. Paylaş'a basınca kart PNG olarak
//  kaydedilip sistem paylaşım sheet'i açılır.
// ═════════════════════════════════════════════════════════════════════════════
class _ShareModePage extends StatefulWidget {
  final String subjectName;
  final String topic;
  final String userName;
  final String grade;
  final String eduLabel;
  final int correct;
  final int wrong;
  final int empty;
  final int total;
  final int elapsedSeconds;
  final bool friendMode;

  const _ShareModePage({
    required this.subjectName,
    required this.topic,
    required this.userName,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.total,
    required this.friendMode,
    this.grade = '',
    this.eduLabel = '',
    this.elapsedSeconds = 0,
  });

  @override
  State<_ShareModePage> createState() => _ShareModePageState();
}

class _ShareModePageState extends State<_ShareModePage> {
  // Geniş renk paleti (bottom sheet'te gösterilir). Hue grubuna göre sıralı.
  static const _palette = <Color>[
    // Nötr
    Colors.white,
    Color(0xFFF3F4F6),
    Color(0xFFD1D5DB),
    Color(0xFF9CA3AF),
    Color(0xFF4B5563),
    Color(0xFF0F172A),
    // Sıcak
    Color(0xFFFFEFD5), // şeftali
    Color(0xFFFFD1DC), // toz pembe
    Color(0xFFFCA5A5), // açık mercan
    Color(0xFFFF6A00), // turuncu
    Color(0xFFC8102E), // al kırmızı
    Color(0xFFDB2777), // pembe
    // Sarı/amber
    Color(0xFFFEF3C7), // açık amber
    Color(0xFFFBBF24), // altın
    Color(0xFFD97706), // bronz
    // Yeşil
    Color(0xFFDCFCE7), // mint
    Color(0xFF86EFAC), // pastel yeşil
    Color(0xFF10B981), // zümrüt
    Color(0xFF047857), // koyu orman
    // Camgöbeği/mavi
    Color(0xFFE0F2FE), // açık mavi
    Color(0xFF22D3EE), // cyan
    Color(0xFF2563EB), // mavi
    Color(0xFF1E40AF), // koyu mavi
    // Mor
    Color(0xFFE9D5FF), // lila
    Color(0xFFA855F7), // eflatun
    Color(0xFF7C3AED), // mor
    Color(0xFF4C1D95), // koyu indigo
    // Kahverengi/bej
    Color(0xFFF5F5DC), // bej
    Color(0xFFD4A373), // tan
    Color(0xFF92400E), // kahve
  ];

  // Renk override'ları — her hedef kendi rengine sahip; null=varsayılan.
  Color _bg = Colors.white; // arka plan
  Color? _donutFrame; // donut/lejant çerçevesi
  Color? _textColor; // başlık/ders/konu yazıları
  Color? _motivationColor; // motivasyon kutusu yazısı
  // Aktif hedef — palet tıklayınca buraya uygulanır.
  String _target = 'bg'; // 'bg' | 'donut' | 'text' | 'motivation'
  // Kullanıcının özel motivasyon mesajı (gelecekte editör eklenirse
  // _ResultCard'a veriliyor; şu an her zaman null = varsayılan motivasyon).
  final String? _customMotivation = null;
  // Renk paneli açık mı? Kapalıyken kompakt "Renk Seç" pill'i çıkar.
  bool _panelOpen = true;
  bool _sharing = false;
  final GlobalKey _shotKey = GlobalKey();

  void _applyColor(Color c) {
    setState(() {
      switch (_target) {
        case 'donut':
          _donutFrame = c;
          break;
        case 'text':
          _textColor = c;
          break;
        case 'motivation':
          _motivationColor = c;
          break;
        case 'bg':
        default:
          _bg = c;
      }
    });
  }

  void _resetColor() {
    setState(() {
      switch (_target) {
        case 'donut':
          _donutFrame = null;
          break;
        case 'text':
          _textColor = null;
          break;
        case 'motivation':
          _motivationColor = null;
          break;
        case 'bg':
        default:
          _bg = Colors.white;
      }
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    // iPad/tablet popover origin — async gap'ten önce yakala.
    Rect? origin;
    final pageBox = context.findRenderObject() as RenderBox?;
    if (pageBox != null) {
      origin = pageBox.localToGlobal(Offset.zero) & pageBox.size;
    }
    setState(() => _sharing = true);
    try {
      // 1) Capture'dan önce mevcut frame'in tamamlanmasını bekle.
      //    Tooltip/scroll değişiminden hemen sonra boundary'nin hazır
      //    olmaması görüntünün eksik çıkmasına yol açabiliyor.
      await WidgetsBinding.instance.endOfFrame;

      final boundary = _shotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Kart render edilmedi (boundary null).');
      }

      // 2) Henüz ilk paint yapılmadıysa needsPaint true olur; bir frame daha bekle.
      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('PNG byte dönüşümü başarısız.');
      }
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/qualsar_test_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes, flush: true);

      final msg = widget.friendMode
          ? '${widget.subjectName} · ${widget.topic}\n${widget.correct}/${widget.total} · %${((widget.correct * 100) / (widget.total == 0 ? 1 : widget.total)).round()}\n\nQuAlsar\'da sen de dene: https://qualsar.app'
          : 'QuAlsar ile çözdüğüm test — sen de dene: https://qualsar.app';

      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'qualsar_test.png')],
        text: msg,
        subject: 'QuAlsar Test Sonucu',
        sharePositionOrigin: origin,
      );

      // Kullanıcı iptal ederse silent geç.
      if (!mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Paylaşım uygulaması bulunamadı.'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e, st) {
      debugPrint('[TestShare] hata: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Paylaşılamadı: $e'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pageBg = Color(0xFFE8EAEF);
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          widget.friendMode
              ? 'Arkadaşına gönder'.tr()
              : 'Sosyal medyada paylaş'.tr(),
          style:
              GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    // Kart biraz daha dar: maksimum %85 genişlik
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.85,
                        ),
                        child: DragTarget<Color>(
                          onAcceptWithDetails: (d) => _applyColor(d.data),
                          builder: (ctx, cand, _) => Stack(
                            clipBehavior: Clip.none,
                            children: [
                              RepaintBoundary(
                                key: _shotKey,
                                child: _ResultCard(
                                  subjectName: widget.subjectName,
                                  topic: widget.topic,
                                  userName: widget.userName,
                                  grade: widget.grade,
                                  eduLabel: widget.eduLabel,
                                  correct: widget.correct,
                                  wrong: widget.wrong,
                                  empty: widget.empty,
                                  total: widget.total,
                                  elapsedSeconds: widget.elapsedSeconds,
                                  bgColor: _bg,
                                  donutFrameOverride: _donutFrame,
                                  textOverride: _textColor,
                                  motivationOverride: _motivationColor,
                                  customMotivation: _customMotivation,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Panel açıkken tam palet, kapalıyken küçük "Renk Seç" pill'i.
              if (_panelOpen) _colorPanel() else _colorOpenPill(),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _sharing ? null : _share,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _sharing ? Colors.black38 : _testOrange,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_sharing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(Icons.ios_share_rounded,
                            color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _sharing
                            ? 'Hazırlanıyor…'.tr()
                            : 'Paylaş'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══ Kompakt "Renk Seç" pill — paneli yeniden açar ══════════════════
  Widget _colorOpenPill() {
    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _panelOpen = true),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.palette_rounded,
                  size: 14, color: Colors.black87),
              const SizedBox(width: 6),
              Text(
                'Renk Seç'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded,
                  size: 16, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }

  // ══ İnline renk paneli — hedef chips + 2-sıra yatay scroll palet ══════
  Widget _colorPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              const SizedBox(width: 6),
              Text(
                'Renk Seç'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              // Kullanım ipucu — "Renk Seç"in hemen sağında küçük italik
              // metin: paletten bir rengi sürükleyip kart üzerinde
              // istenen alana bırakma davranışını anlatır.
              Flexible(
                child: Text(
                  'rengi sürükle → alana bırak'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const Spacer(),
              // Sıfırla — biraz solda dursun (sağ kenara dayanmasın)
              GestureDetector(
                onTap: _resetColor,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    'Sıfırla'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ✕ paneli kapat — Sıfırla ile aynı hizada
              GestureDetector(
                onTap: () => setState(() => _panelOpen = false),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12),
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 14, color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Hedef seçici (4 chip) ─────────────────────────────────
          Row(
            children: [
              _targetChip('bg', 'Arka Plan'.tr()),
              const SizedBox(width: 6),
              _targetChip('donut', 'Çerçeve'.tr()),
              const SizedBox(width: 6),
              _targetChip('text', 'Yazı'.tr()),
              const SizedBox(width: 6),
              _targetChip('motivation', 'Motivasyon'.tr()),
            ],
          ),
          const SizedBox(height: 10),
          // ── 2-sıra yatay scroll palet ─────────────────────────────
          SizedBox(
            height: 64,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemCount: _palette.length,
              itemBuilder: (_, i) {
                final c = _palette[i];
                final selected = _isCurrentTargetColor(c);
                return Draggable<Color>(
                  data: c,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.black, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: GestureDetector(
                    onTap: () => _applyColor(c),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFFF6A00)
                              : Colors.black38,
                          width: selected ? 2.4 : 1,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetChip(String id, String label) {
    final active = _target == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _target = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                active ? _testOrange.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? _testOrange : Colors.black26,
              width: active ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: active ? _testOrange : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  bool _isCurrentTargetColor(Color c) {
    switch (_target) {
      case 'donut':
        return _donutFrame == c;
      case 'text':
        return _textColor == c;
      case 'motivation':
        return _motivationColor == c;
      case 'bg':
      default:
        return _bg == c;
    }
  }

}
