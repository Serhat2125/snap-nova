import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../services/runtime_translator.dart';
import '../widgets/latex_text.dart';

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
              correct: _correct,
              wrong: _wrong,
              empty: _empty,
              total: widget.questions.length,
              elapsedSeconds: widget.elapsedSeconds,
              bgColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          // ── Aynı soruları yeniden çöz ─────────────────────────────
          _actionRow(
            icon: Icons.replay_rounded,
            label: "Aynı soruları yeniden çöz".tr(),
            color: Colors.white,
            fg: Colors.black,
            borderColor: Colors.black,
            onTap: _retakeSameQuestions,
          ),
          const SizedBox(height: 10),
          // ── Yanlış yaptığın sorulara bak ──────────────────────────
          _actionRow(
            icon: _showWrong
                ? Icons.keyboard_arrow_up_rounded
                : Icons.auto_stories_rounded,
            label: _unsolved == 0
                ? "Tüm soruları çözdün — tebrikler!".tr()
                : _showWrong
                    ? "Çözümleri gizle".tr()
                    : "Yanlış yaptığın sorulara bak".tr(),
            color: _unsolved == 0 ? const Color(0xFFEFF1F6) : _testOrange,
            fg: _unsolved == 0 ? Colors.black54 : Colors.white,
            trailing: _unsolved == 0
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      "$_unsolved",
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _testOrange,
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
          const SizedBox(height: 12),
          // ── Sosyal medyada paylaş ─────────────────────────────────
          _actionRow(
            icon: Icons.ios_share_rounded,
            label: "Sosyal medyada paylaş".tr(),
            color: Colors.black,
            fg: Colors.white,
            onTap: () => _openShareMode(onFriend: false),
          ),
          const SizedBox(height: 10),
          // ── Arkadaşına gönder ────────────────────────────────────
          _actionRow(
            icon: Icons.send_rounded,
            label: "Arkadaşına gönder".tr(),
            color: Colors.white,
            fg: Colors.black,
            borderColor: Colors.black,
            onTap: () => _openShareMode(onFriend: true),
          ),
        ],
      ),
    );
  }

  // Aynı sorularla testi yeniden başlat. Önce eski cevaplar temizlenir,
  // ardından TestPage push edilir; biten test bittiğinde (TestPage finish)
  // yeniden TestResultPage'e dönülür.
  void _retakeSameQuestions() {
    final raw = widget.rawContent ?? jsonEncode([
      for (final q in widget.questions)
        {
          'q': q.q,
          'opts': q.opts,
          'ans': q.ans,
          'hint': q.hint,
          'sol': q.sol,
          'd': q.d,
        }
    ]);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => TestPage(
        rawContent: raw,
        subjectName: widget.subjectName,
        topic: widget.topic,
        timeLimit: widget.timeLimit,
        // Yeniden çözümde önceki cevapları sıfırlıyoruz (boş başla).
        initialAnswers: const {},
        onFinish: widget.onFinish,
      ),
    ));
  }

  void _openShareMode({required bool onFriend}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ShareModePage(
        subjectName: widget.subjectName,
        topic: widget.topic,
        userName: _userName,
        grade: _grade,
        correct: _correct,
        wrong: _wrong,
        empty: _empty,
        total: widget.questions.length,
        elapsedSeconds: widget.elapsedSeconds,
        friendMode: onFriend,
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
  }) {
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
            Icon(icon, color: fg, size: 18),
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
      // Atla: doğru cevaplananlar
      if (a != null && a == q.ans) continue;
      final isEmpty = a == null;
      final badgeColor =
          isEmpty ? const Color(0xFF6B7280) : const Color(0xFFDC2626);
      final caption = isEmpty
          ? "Boş · Doğru: ${q.ans}".tr()
          : "Senin: $a · Doğru: ${q.ans}";
      cards.add(Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
                    "Soru ${i + 1}",
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LatexText(q.q, fontSize: 13, lineHeight: 1.4),
            const SizedBox(height: 10),
            Container(
                height: 1,
                color: Colors.black.withValues(alpha: 0.08)),
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
  final int correct;
  final int wrong;
  final int empty;
  final int total;
  final int elapsedSeconds;
  final Color bgColor;

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
    this.elapsedSeconds = 0,
  });

  int get pct => total == 0 ? 0 : ((correct * 100) / total).round();

  // Zemin koyuysa beyaz metin, açıksa siyah metin.
  bool get _dark {
    final c = bgColor;
    final lum = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    return lum < 0.6;
  }

  Color get _ink => _dark ? Colors.white : Colors.black;
  Color get _inkMute => _dark ? Colors.white70 : Colors.black54;

  String get _motivationLine {
    if (total == 0) return "Teste başla ve ilerlemeni gör!".tr();
    if (pct >= 90) {
      return "Harikasın! Neredeyse hatasız — bu konu artık senin.".tr();
    }
    if (pct >= 75) {
      return "Çok iyi! Temelin sağlam, biraz daha tekrar yeter.".tr();
    }
    if (pct >= 50) {
      return "İyi gidiyorsun. Yanlışlarına odaklan, hızla yükselirsin."
          .tr();
    }
    if (pct >= 25) {
      return "Her yanlış yeni bir fırsat — çözümlere bak, tekrar dene."
          .tr();
    }
    return "Başlangıç zor, pes etme. Birkaç tekrar her şeyi değiştirir."
        .tr();
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
            // ══ En üst: SOL kupa (büyük) · profil (hafif sağda) ═════
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _trophyIcon(),
                Expanded(
                  child: Align(
                    // Tam ortadan biraz daha sağda.
                    alignment: const Alignment(0.3, 0),
                    child: _centeredUserBlock(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ══ Sınıf rozeti + Ders / Konu etiketli satırlar ═══════
            if (grade.isNotEmpty) ...[
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
            _labeledLine(label: 'Ders'.tr(), value: subjectName),
            const SizedBox(height: 5),
            _labeledLine(label: 'Konu'.tr(), value: topic, maxLines: 2),
            const SizedBox(height: 14),
            // ══ Donut grafiği + sağda lejant ════════════════════════
            _donutStats(),
            const SizedBox(height: 10),
            // ══ Tebrikler @kullanici (4'lü sekmenin altı) ══════════
            Row(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Tebrikler '.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        TextSpan(
                          text: _userHandle.isEmpty
                              ? '@sen'
                              : '@$_userHandle',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _alKirmizi,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ══ Motivasyon kutusu (beyaz çerçeveli) ════════════════
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
                  const Text('💫', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _motivationLine,
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
            const SizedBox(height: 8),
            // ══ Meydan Oku kartı (beyaz zemin, al kırmızı aksan) ════
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _alKirmizi, width: 1.2),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Arkadaşlarına meydan oku'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: _alKirmizi,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bu sonucu geçebilir misin?'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            height: 1.3,
                          ),
                        ),
                      ],
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

  // Sol üstte büyük kupa görseli.
  Widget _trophyIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFBBF24).withValues(alpha: _dark ? 0.35 : 0.22),
            const Color(0xFFF59E0B).withValues(alpha: _dark ? 0.45 : 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              const Color(0xFFD97706).withValues(alpha: _dark ? 0.7 : 0.5),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFFD97706).withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('🏆', style: TextStyle(fontSize: 28)),
    );
  }

  Widget _labeledLine({
    required String label,
    required String value,
    int maxLines = 1,
  }) {
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: _dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _dark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
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
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Başarı'.tr().toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: _inkMute,
                        letterSpacing: 1.4,
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

  Color _bg = Colors.white;
  bool _sharing = false;
  final GlobalKey _shotKey = GlobalKey();

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
                        child: RepaintBoundary(
                          key: _shotKey,
                          child: _ResultCard(
                            subjectName: widget.subjectName,
                            topic: widget.topic,
                            userName: widget.userName,
                            grade: widget.grade,
                            correct: widget.correct,
                            wrong: widget.wrong,
                            empty: widget.empty,
                            total: widget.total,
                            elapsedSeconds: widget.elapsedSeconds,
                            bgColor: _bg,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // "Kart Rengi" kavisli çerçeveli buton — basınca sheet açılır.
              Center(child: _colorPickerButton()),
              const SizedBox(height: 14),
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

  // ══ "Kart Rengi" butonu — kavisli çerçeve, sol mini swatch + yazı ══
  Widget _colorPickerButton() {
    return GestureDetector(
      onTap: _openColorSheet,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seçili rengin mini önizlemesi
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black26, width: 1),
              ),
            ),
            const SizedBox(width: 9),
            Icon(Icons.palette_rounded,
                size: 15, color: Colors.black87),
            const SizedBox(width: 6),
            Text(
              'Kart Rengini Seç'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_drop_down_rounded,
                size: 20, color: Colors.black87),
          ],
        ),
      ),
    );
  }

  // ══ Bottom sheet — tüm renkler ═════════════════════════════════════
  Future<void> _openColorSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tutacak
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.palette_rounded,
                      size: 18, color: Colors.black87),
                  const SizedBox(width: 8),
                  Text(
                    'Kart Rengini Seç'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
                children: [
                  for (final c in _palette)
                    _sheetSwatch(
                      c,
                      onPick: () {
                        setState(() => _bg = c);
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetSwatch(Color c, {required VoidCallback onPick}) {
    final selected = _bg == c;
    // Açık renk için koyu tik, koyu renk için beyaz tik.
    final lum = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b);
    final isDark = lum < 0.6;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _testOrange : Colors.black26,
            width: selected ? 3 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _testOrange.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: selected
            ? Center(
                child: Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: isDark ? Colors.white : Colors.black,
                ),
              )
            : null,
      ),
    );
  }
}
