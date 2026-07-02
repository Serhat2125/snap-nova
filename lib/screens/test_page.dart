import 'dart:async';
import 'dart:convert';
import '../services/error_logger.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../services/activity_writer_service.dart';
import '../services/app_settings_service.dart';
import '../services/education_profile.dart';
import '../services/question_pool_service.dart';
import '../services/runtime_translator.dart';
import '../widgets/latex_text.dart';
import 'academic_planner.dart';

import '../theme/app_theme.dart';
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
  TestQuestion({
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
/// Aynı soruyu (q metni normalleştirildi) iki kez içeren cevaplarda dedupe
/// yapar — AI bazen "10 soru" istediğimizde aynı soruyu tekrar üretebiliyor.
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
      final all = decoded
          .whereType<Map>()
          .map((e) => TestQuestion.fromJson(Map<String, dynamic>.from(e)))
          .where((q) => q.q.isNotEmpty && q.opts.isNotEmpty)
          .toList();
      // Dedupe: q metni boşluk/case normalize edilip set ile filtrelenir.
      final seen = <String>{};
      final out = <TestQuestion>[];
      for (final q in all) {
        final key = q.q.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
        if (seen.add(key)) out.add(q);
      }
      return out;
    }
  } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'test_page'); }
  return const [];
}

// ═════════════════════════════════════════════════════════════════════════════

class TestPage extends StatefulWidget {
  final String rawContent;
  final String subjectName;
  final String topic;
  final Map<int, String?>? initialAnswers;
  // Önceki oturumdan kalan per-question timer state. Cheese koruması:
  // kullanıcı testten çıkıp tekrar girince timer sıfırlanmaz.
  final Map<int, int>? initialPerQuestionRemaining;
  final Future<void> Function(Map<int, String?> answers)? onFinish;
  // Cevap ya da timer her değiştiğinde çağrılır (debounce'lu) — uygulama
  // crash olursa ya da kullanıcı çıkarsa son durum kaybolmasın.
  // `remaining` parametresi: soru-bazlı kalan saniye (0 = relax modda boş).
  final Future<void> Function(
      Map<int, String?> answers, Map<int, int> remaining)? onAnswerChanged;
  // 0 = süresiz (relax). >0 = soru başına saniye (90 normal, 45 yarış).
  final int timeLimit;
  const TestPage({
    super.key,
    required this.rawContent,
    required this.subjectName,
    required this.topic,
    this.initialAnswers,
    this.initialPerQuestionRemaining,
    this.onFinish,
    this.onAnswerChanged,
    this.timeLimit = 0,
  });

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  late final List<TestQuestion> _questions;
  final Map<int, String?> _answers = {};
  // Her soru için kalan süre — geri-ileri yapınca cheese olmasın diye
  // her sorunun kendi sayacı vardır. timeLimit > 0 ise dolu, 0 ise boş.
  final Map<int, int> _perQuestionRemaining = {};
  int _idx = 0;
  bool _showHint = false;
  Timer? _ticker;
  // Auto-save debounce (cevap değişimi).
  Timer? _saveDebounce;
  late final DateTime _startedAt;
  bool _finishing = false;

  // ── Şüpheli işaretleri — sonra dönmek istenen sorular ──────────────────
  final Set<int> _flagged = {};
  // ── Şık eleme — soru başına çizgi çekilmiş şıklar (A/B/C/D/E) ──────────
  // Cevap olarak seçilemezler ama UI'da çizgili gösterilir.
  final Map<int, Set<String>> _eliminated = {};
  // ── Bildirilen sorular — kullanıcı "yanlış/saçma" dedi ─────────────────
  final Set<int> _reported = {};
  // ── Karalama notları (per-soru) ────────────────────────────────────────
  final Map<int, String> _scratchNotes = {};
  // ── Hesap makinesi state ───────────────────────────────────────────────
  bool _showCalc = false;
  String _calcExpr = '';
  String _calcResult = '';
  // ── Süre uyarısı — soru başına bir kez titrer/haptic verir ─────────────
  final Set<int> _lowTimeWarnedFor = {};

  // ── İpucu sayacı — test başına max 3 farklı soruda ipucu kullanılabilir ─
  static const int _kMaxHintsPerTest = 3;
  final Set<int> _hintShownFor = {};
  int get _remainingHints =>
      _kMaxHintsPerTest - _hintShownFor.length;

  // ── Rahat modda kronometre (geçen süre) ────────────────────────────────
  bool _stopwatchVisible = true;
  int _elapsedSec = 0;
  Timer? _stopwatchTimer;

  // ── Fosforlu kalem (highlight) — soru başına vurgulu kelime indeksleri ─
  // Map<soruIdx, Set<kelimeIdx>> — soru metni boşluklara bölünür, vurgulu
  // kelimelerin indeksi tutulur. Toggle ile aç/kapat.
  final Map<int, Set<int>> _highlights = {};
  // Vurgu modu açıkken kullanıcı kelimeye dokununca sarıya boyar.
  // Kapalıyken normal soru metni görünür.
  bool _highlightMode = false;

  // race mode'da ipucu butonu gizli (sınav simülasyonu).
  bool get _hintAllowed => widget.timeLimit == 0 || widget.timeLimit >= 90;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _questions = parseTestQuestions(widget.rawContent);
    final savedPqr = widget.initialPerQuestionRemaining;
    for (var i = 0; i < _questions.length; i++) {
      _answers[i] = widget.initialAnswers?[i];
      if (widget.timeLimit > 0) {
        // Önceki oturumdan kalan süreyi yüklü tut; yoksa tam süre.
        final saved = savedPqr?[i];
        _perQuestionRemaining[i] = saved ?? widget.timeLimit;
      }
    }
    // Test sayfası süresi → "soru" kategorisinde StudySessionTracker'a yaz.
    StudySessionTracker.instance.start(
      subject: widget.subjectName,
      topic: widget.topic,
      type: 'soru',
    );
    _startTimerForCurrent();
    // Rahat modda (timeLimit == 0) ekrana toplam geçen süreyi yansıt.
    if (widget.timeLimit == 0) {
      _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedSec++);
      });
    }
  }

  @override
  void dispose() {
    StudySessionTracker.instance.end();
    _ticker?.cancel();
    _stopwatchTimer?.cancel();
    // Pending auto-save varsa flush et — user "A" cevabını seçip 200ms
    // sonra app'i kapatırsa 800ms debounce hiç fire etmez ve son cevap
    // kaybolur. Burada fire-and-forget ile son state'i (cevap + timer) kaydet.
    final hadPending = _saveDebounce?.isActive ?? false;
    _saveDebounce?.cancel();
    if (hadPending && !_finishing) {
      _saveNow();
    }
    super.dispose();
  }

  void _startTimerForCurrent() {
    _ticker?.cancel();
    if (widget.timeLimit <= 0 || _questions.isEmpty) return;
    // Per-question carry-over: kullanıcı bu soruda 30sn geçirdiyse geri
    // gelip tekrar tam süre alamaz.
    _perQuestionRemaining[_idx] ??= widget.timeLimit;
    if ((_perQuestionRemaining[_idx] ?? 0) <= 0) {
      // Bu sorunun süresi zaten bitmiş → sayaç tetiklemeye gerek yok.
      return;
    }
    int saveTickCounter = 0;
    _ticker = Timer.periodic(Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final cur = _perQuestionRemaining[_idx] ?? 0;
      if (cur <= 1) {
        _perQuestionRemaining[_idx] = 0;
        t.cancel();
        // Süre 0'a düştü → durumu hemen persist et + sonraki soruya geç.
        _saveNow();
        _timeExpired();
      } else {
        setState(() {
          _perQuestionRemaining[_idx] = cur - 1;
        });
        // 10 saniye uyarısı — soru başına bir kez titrer + haptic.
        if (cur - 1 == 10 && !_lowTimeWarnedFor.contains(_idx)) {
          _lowTimeWarnedFor.add(_idx);
          AppSettingsService.instance.hapticMedium(inTest: true);
        }
        // Her 5sn'de bir direct save (debounce yok — sürekli tick olduğu için
        // debounce hiçbir zaman fire etmez). Crash/exit'te en fazla 5sn kayıp.
        saveTickCounter++;
        if (saveTickCounter >= 5) {
          saveTickCounter = 0;
          _saveNow();
        }
      }
    });
  }

  // Debounce'suz direkt save — timer tick + navigation event'lerinde.
  void _saveNow() {
    final cb = widget.onAnswerChanged;
    if (cb == null) return;
    // ignore: discarded_futures
    cb(
      Map<int, String?>.from(_answers),
      Map<int, int>.from(_perQuestionRemaining),
    );
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
        if (letter == _questions[_idx].ans) {
          AppSettingsService.instance.notifySuccess();
        } else {
          AppSettingsService.instance.notifyError();
        }
      }
    });
    _scheduleAutoSave();
  }

  // Her cevap değişikliğinde / timer tick'inde 800ms debounce ile partial-save
  // callback'i tetikle. Uygulama crash / kullanıcı çıkışı durumunda son durum
  // kaybolmasın. Hem cevap haritası hem timer state'i iletilir.
  void _scheduleAutoSave() {
    final cb = widget.onAnswerChanged;
    if (cb == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      // ignore: discarded_futures
      cb(
        Map<int, String?>.from(_answers),
        Map<int, int>.from(_perQuestionRemaining),
      );
    });
  }

  void _goPrev() {
    if (_idx <= 0) return;
    setState(() {
      _idx -= 1;
      _showHint = false;
    });
    // Navigasyon → mevcut timer state'i persist (her ne kadar otomatik
    // 5sn save olsa da soru geçişi anında doğru state garantilenir).
    _saveNow();
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
    _saveNow();
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
    _saveNow();
    _startTimerForCurrent();
  }

  // Cevap haritasından bir soruya direkt atlama.
  void _jumpTo(int i) {
    if (i < 0 || i >= _questions.length || i == _idx) return;
    setState(() {
      _idx = i;
      _showHint = false;
    });
    _saveNow();
    _startTimerForCurrent();
  }

  // Geri tuşu / swipe-back → "emin misin?" diyaloğu.
  // Cevaplar zaten auto-save ile kaydedildi (her _pick'te debounce'lu).
  // Onaylanırsa son durum flush edilip Navigator.pop tetiklenir.
  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          'Testten çık?'.tr(),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Çıkarsan bu denemen kaydedilir, daha sonra kaldığın yerden devam edebilirsin.'
              .tr(),
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppPalette.textSecondary(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Vazgeç'.tr(),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Çık'.tr(),
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ── Şüpheli işareti aç/kapat ─────────────────────────────────────────
  void _toggleFlag() {
    setState(() {
      if (_flagged.contains(_idx)) {
        _flagged.remove(_idx);
      } else {
        _flagged.add(_idx);
      }
    });
  }

  // ── Şık eleme — uzun-bas ile çizgi çek/kaldır ───────────────────────
  void _toggleEliminate(String letter) {
    setState(() {
      final set = _eliminated.putIfAbsent(_idx, () => <String>{});
      if (set.contains(letter)) {
        set.remove(letter);
      } else {
        set.add(letter);
        // Eğer seçili cevap eleniyorsa cevabı da kaldır.
        if (_answers[_idx] == letter) {
          _answers[_idx] = null;
        }
      }
    });
    AppSettingsService.instance.hapticLight(inTest: true);
    _scheduleAutoSave();
  }

  // ── Soruyu raporla ───────────────────────────────────────────────────
  Future<void> _reportQuestion() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Bu sorunun nesi yanlış?'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined,
                    color: Color(0xFFDC2626)),
                title: Text('Cevap yanlış'.tr()),
                onTap: () => Navigator.of(ctx).pop('wrong_answer'),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline_rounded,
                    color: Color(0xFFD97706)),
                title: Text('Soru belirsiz / anlaşılmıyor'.tr()),
                onTap: () => Navigator.of(ctx).pop('ambiguous'),
              ),
              ListTile(
                leading: const Icon(Icons.copy_all_outlined,
                    color: Color(0xFF7C3AED)),
                title: Text('Birden fazla doğru cevap var'.tr()),
                onTap: () => Navigator.of(ctx).pop('multiple_correct'),
              ),
              ListTile(
                leading: const Icon(Icons.school_outlined,
                    color: Color(0xFF2563EB)),
                title: Text('Konuyla ilgisiz'.tr()),
                onTap: () => Navigator.of(ctx).pop('off_topic'),
              ),
            ],
          ),
        ),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _reported.add(_idx));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('🚩 ${'Geri bildirimin alındı.'.tr()}'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
    // Pool'a rapor — havuzdan gelen soruysa errorReports artar.
    // ID'yi pool'dan bilmiyoruz; ana arayüz attempt'i yüklerken
    // pool ID'sini tutmadığı için şimdilik sadece lokal işaretle.
    // Server tarafında istek atmıyoruz — gerekirse sonradan eklenir.
  }

  // ── Karalama notları — alt sayfada metin alanı ───────────────────────
  Future<void> _openScratchPad() async {
    final ctrl =
        TextEditingController(text: _scratchNotes[_idx] ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.textSecondary(context)
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded,
                      size: 20, color: Color(0xFFFF6A00)),
                  const SizedBox(width: 8),
                  Text(
                    'Karalama — Soru ${_idx + 1}'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 8,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppPalette.textPrimary(context),
                ),
                decoration: InputDecoration(
                  hintText: 'Hesap, not, çizim açıklaması…'.tr(),
                  filled: true,
                  fillColor: AppPalette.card(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: Text('Kaydet'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _testOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _scratchNotes[_idx] = ctrl.text;
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Hesap makinesi — basit dört işlem + parantez ────────────────────
  void _calcKey(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _calcExpr = '';
          _calcResult = '';
          break;
        case '⌫':
          if (_calcExpr.isNotEmpty) {
            _calcExpr = _calcExpr.substring(0, _calcExpr.length - 1);
          }
          break;
        case '=':
          _evaluateCalc();
          break;
        default:
          _calcExpr += key;
      }
    });
  }

  void _evaluateCalc() {
    try {
      // Basit eval — math_expressions paketi yerine inline parser.
      final expr = _calcExpr
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('−', '-');
      final result = _simpleEval(expr);
      _calcResult = result;
    } catch (_) {
      _calcResult = 'Hata';
    }
  }

  /// Şunting-yard mini eval — +, -, *, /, parantez. Negatif/üs yok (yeter).
  String _simpleEval(String s) {
    final out = <num>[];
    final ops = <String>[];
    int prec(String op) => (op == '+' || op == '-') ? 1 : 2;
    void apply() {
      if (out.length < 2 || ops.isEmpty) return;
      final b = out.removeLast();
      final a = out.removeLast();
      final op = ops.removeLast();
      switch (op) {
        case '+':
          out.add(a + b);
          break;
        case '-':
          out.add(a - b);
          break;
        case '*':
          out.add(a * b);
          break;
        case '/':
          out.add(b == 0 ? double.nan : a / b);
          break;
      }
    }

    int i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == ' ') {
        i++;
        continue;
      }
      if (RegExp(r'[0-9.]').hasMatch(c)) {
        final buf = StringBuffer();
        while (i < s.length && RegExp(r'[0-9.]').hasMatch(s[i])) {
          buf.write(s[i]);
          i++;
        }
        out.add(num.parse(buf.toString()));
        continue;
      }
      if (c == '(') {
        ops.add(c);
      } else if (c == ')') {
        while (ops.isNotEmpty && ops.last != '(') {
          apply();
        }
        if (ops.isNotEmpty) ops.removeLast();
      } else if ('+-*/'.contains(c)) {
        while (ops.isNotEmpty &&
            ops.last != '(' &&
            prec(ops.last) >= prec(c)) {
          apply();
        }
        ops.add(c);
      }
      i++;
    }
    while (ops.isNotEmpty) {
      apply();
    }
    if (out.isEmpty) return '';
    final v = out.last;
    if (v.isNaN || v.isInfinite) return 'Hata';
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  // ── Bitir onayı — boş/şüpheli soru varsa uyar ────────────────────────
  // Diyalog 3 sonuçtan birini döner:
  //   'finish'  → bitir
  //   'jump'    → ilk boş soruya / boş yoksa ilk şüpheliye atla
  //   null      → diyaloğu kapat, hiçbir şey yapma (geri butonu)
  Future<void> _confirmAndFinish() async {
    final unanswered = <int>[];
    for (var i = 0; i < _questions.length; i++) {
      if (_answers[i] == null) unanswered.add(i);
    }
    final flagged = _flagged.toList()..sort();
    // Hiç boş/şüpheli yoksa direkt bitir.
    if (unanswered.isEmpty && flagged.isEmpty) {
      await _finish();
      return;
    }
    final messages = <String>[];
    if (unanswered.isNotEmpty) {
      messages.add('${unanswered.length} ${'soru boş'.tr()}');
    }
    if (flagged.isNotEmpty) {
      messages.add('${flagged.length} ${'şüpheli işaretli'.tr()}');
    }
    // İlk boş soru veya yoksa ilk şüpheli — "Devam et" tıklanınca buna atla.
    final jumpTarget = unanswered.isNotEmpty
        ? unanswered.first
        : (flagged.isNotEmpty ? flagged.first : null);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Text('Emin misin?'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          '${messages.join(' · ')}\n${'Yine de testi bitirmek istiyor musun?'.tr()}',
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            color: AppPalette.textSecondary(context),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('jump'),
            child: Text('Devam et'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('finish'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _testOrange,
              foregroundColor: Colors.white,
            ),
            child: Text('Bitir'.tr()),
          ),
        ],
      ),
    );
    if (result == 'finish') {
      await _finish();
    } else if (result == 'jump' && jumpTarget != null) {
      _jumpTo(jumpTarget);
    }
  }

  Future<void> _finish() async {
    _finishing = true;
    _ticker?.cancel();
    _saveDebounce?.cancel();
    final answersSnapshot = Map<int, String?>.from(_answers);
    final elapsed = DateTime.now().difference(_startedAt);
    // Ebeveyn paneli / Gelişimim — test sonucu (doğru/yanlış/boş).
    int correct = 0, wrong = 0, blank = 0;
    for (var i = 0; i < _questions.length; i++) {
      final a = answersSnapshot[i];
      if (a == null) {
        blank++;
      } else if (a == _questions[i].ans) {
        correct++;
      } else {
        wrong++;
      }
    }
    unawaited(ActivityWriterService.recordTestCompleted(
      correct: correct,
      wrong: wrong,
      blank: blank,
      subject: widget.subjectName,
    ));
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
    final pageBg = AppPalette.bg(context);
    if (_questions.isEmpty) {
      // Eski bozuk JSON kaydı → kullanıcı yine de açmış olabilir.
      // Inline "Listeye Dön" pill + açıklama: list'te uzun basıp Yeniden
      // Oluştur ya da Sil yapabileceğini belirt.
      return Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: pageBg,
          elevation: 0,
          foregroundColor: AppPalette.textPrimary(context),
          title: Text(
            widget.topic,
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 48, color: AppPalette.textSecondary(context)),
                SizedBox(height: 12),
                Text(
                  "Test verisi okunamadı".tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "Listeden bu konuya uzun basıp Yeniden Oluştur veya Sil yapabilirsin."
                      .tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppPalette.textSecondary(context),
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 18),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "Listeye Dön".tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final q = _questions[_idx];
    final selected = _answers[_idx];
    final isLast = _idx == _questions.length - 1;
    final hasTimer = widget.timeLimit > 0;
    final remainingSec = _perQuestionRemaining[_idx] ?? 0;
    final timerLow = hasTimer && remainingSec <= 10;
    final hasAnyAnswer = _answers.values.any((v) => v != null);
    return PopScope(
      // Cevap girilmemişse veya zaten finishing ise direkt pop.
      canPop: !hasAnyAnswer || _finishing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Navigator'ı async gap'ten ÖNCE tutuyoruz ki sonradan ana
        // context'i kullanmamıza gerek kalmasın (lint susar).
        final nav = Navigator.of(context);
        final ok = await _confirmExit();
        if (!ok || !mounted) return;
        // Çıkmadan önce son hâli flush — debounce'u beklemeden.
        _saveDebounce?.cancel();
        final cb = widget.onAnswerChanged;
        if (cb != null) {
          try {
            await cb(
              Map<int, String?>.from(_answers),
              Map<int, int>.from(_perQuestionRemaining),
            );
          } catch (e, st) { ErrorLogger.instance.capture(e, st, context: 'test_page'); }
        }
        if (mounted) nav.pop();
      },
      child: Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subjectName,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppPalette.textSecondary(context),
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
          // Süre pill'i + altında küçük (?) yardım butonu — Column ile dikey
          // stack. (?) her zaman görünür, süre yokken bile.
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Yarış/Normal: soru başına kalan süre pill'i
                if (hasTimer)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          timerLow ? const Color(0xFFDC2626) : _testOrange,
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
                          _formatSeconds(remainingSec),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Rahat mod: geçen süre kronometresi + gizle/göster toggle.
                if (!hasTimer && _stopwatchVisible)
                  InkWell(
                    onTap: () =>
                        setState(() => _stopwatchVisible = false),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppPalette.textPrimary(context)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppPalette.border(context),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined,
                              color: AppPalette.textPrimary(context),
                              size: 12),
                          const SizedBox(width: 4),
                          Text(
                            _formatSeconds(_elapsedSec),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.close_rounded,
                              color: AppPalette.textSecondary(context),
                              size: 12),
                        ],
                      ),
                    ),
                  ),
                if (!hasTimer && !_stopwatchVisible)
                  IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 24),
                    icon: Icon(Icons.timer_outlined,
                        color: AppPalette.textSecondary(context),
                        size: 18),
                    tooltip: 'Süreyi göster'.tr(),
                    onPressed: () =>
                        setState(() => _stopwatchVisible = true),
                  ),
                const SizedBox(height: 4),
                // (?) Yardım butonu — süre sekmesinin tam altında, sağa hizalı.
                // Tıkla → "Bu sayfa nasıl çalışır?" detay sayfası.
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _TestPageHelpPage(),
                    ));
                  },
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppPalette.card(context),
                      border: Border.all(
                        color: AppPalette.textPrimary(context)
                            .withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '?',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.textPrimary(context),
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        toolbarHeight: 72,
        // ── Cevap haritası + araç ikonları (bayrak/karalama/kalem/raporla)
        //    Cevap haritası solda yatay scroll; ikonlar en sağda sırayla.
        //    İkonların hizası rakamlarla aynı çizgide.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: _AnswerMap(
                    count: _questions.length,
                    currentIndex: _idx,
                    isAnswered: (i) => _answers[i] != null,
                    isFlagged: (i) => _flagged.contains(i),
                    onTap: _jumpTo,
                  ),
                ),
                const SizedBox(width: 4),
                // Sırayla: bayrak → karalama → kalem → raporla.
                // En sağdan başlar (Row sağa hizalı bittiği için doğal sıra).
                _toolIconBtn(
                  icon: _flagged.contains(_idx)
                      ? Icons.flag_rounded
                      : Icons.flag_outlined,
                  active: _flagged.contains(_idx),
                  activeColor: const Color(0xFFD97706),
                  onTap: _toggleFlag,
                ),
                _toolIconBtn(
                  icon: (_scratchNotes[_idx]?.isNotEmpty ?? false)
                      ? Icons.edit_note_rounded
                      : Icons.edit_note_outlined,
                  active: _scratchNotes[_idx]?.isNotEmpty ?? false,
                  activeColor: const Color(0xFFFF6A00),
                  onTap: _openScratchPad,
                ),
                _toolIconBtn(
                  icon: Icons.brush_rounded,
                  active: _highlightMode,
                  activeColor: const Color(0xFFFBBF24),
                  onTap: () => setState(
                      () => _highlightMode = !_highlightMode),
                ),
                _toolIconBtn(
                  icon: _reported.contains(_idx)
                      ? Icons.report_rounded
                      : Icons.report_outlined,
                  active: _reported.contains(_idx),
                  activeColor: const Color(0xFFDC2626),
                  onTap: _reported.contains(_idx) ? null : _reportQuestion,
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Üst mini ilerleme bandı — cevaplanan/şüpheli/boş ─────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _statChip(
                        Icons.check_circle_outline_rounded,
                        const Color(0xFF10B981),
                        '${_answers.values.where((v) => v != null).length}',
                        'Cevaplanan'.tr(),
                      ),
                      const SizedBox(width: 10),
                      _statChip(
                        Icons.flag_outlined,
                        const Color(0xFFD97706),
                        '${_flagged.length}',
                        'Şüpheli'.tr(),
                      ),
                      const SizedBox(width: 10),
                      _statChip(
                        Icons.circle_outlined,
                        AppPalette.textSecondary(context),
                        '${_questions.length - _answers.values.where((v) => v != null).length}',
                        'Boş'.tr(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // ── Soru kartı ───────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  decoration: BoxDecoration(
                    color: AppPalette.card(context),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sadece soru numarası pill — bayrak/karalama/kalem/
                      // raporla ikonları AppBar'ın bottom satırına (cevap
                      // haritasının sağına) taşındı, kart içinde yer kapamasın.
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              "Soru ${_idx + 1} / ${_questions.length}"
                                  .tr(),
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14),
                      _buildQuestionStem(q.q),
                    ],
                  ),
                ),
                SizedBox(height: 14),
            // ── Şıklar ──────────────────────────────────────────────
            for (final entry in q.opts.entries)
              _optionTile(
                letter: entry.key,
                text: entry.value,
                selected: selected == entry.key,
              ),
            // ── İpucu (açıkken gösterilir) ──────────────────────────
            // race modunda (45s/soru) sınav simülasyonu için gizli.
            if (_hintAllowed && _showHint && q.hint.isNotEmpty) ...[
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Color(0xFFFFFAE8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("💡", style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Expanded(
                      // İpucu metninde formül/sembol olabilir → LatexText.
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          color: AppPalette.textPrimary(context),
                          fontWeight: FontWeight.w600,
                        ),
                        child: LatexText(
                          q.hint,
                          fontSize: 12.5,
                          lineHeight: 1.4,
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
          // ── Hesap makinesi yüzer butonu (sağ alt) ───────────────────
          Positioned(
            right: 14,
            bottom: 14,
            child: FloatingActionButton.small(
              heroTag: 'calc',
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              onPressed: () => setState(() => _showCalc = !_showCalc),
              child: Icon(_showCalc
                  ? Icons.close_rounded
                  : Icons.calculate_rounded),
            ),
          ),
          // ── Hesap makinesi paneli ────────────────────────────────────
          if (_showCalc)
            Positioned(
              right: 14,
              bottom: 70,
              child: _buildCalcPanel(),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Alt bar — sol: ipucu (yalnız hint allowed iken),
              // orta: geri + atla, sağ: sonraki/bitir
              Row(
                children: [
                  if (_hintAllowed)
                    _chipButton(
                      icon: Icons.lightbulb_outline_rounded,
                      // Etiket: kalan ipucu hakkını gösterir. Bu soruda
                      // zaten gösterildiyse "Gizle"ye döner.
                      label: _showHint
                          ? 'İpucunu gizle'.tr()
                          : '${'İpucu'.tr()} ($_remainingHints)',
                      onTap: q.hint.isEmpty
                          ? null
                          : () {
                              // Bu soruda zaten ipucu gösterildiyse aç/kapat.
                              if (_hintShownFor.contains(_idx)) {
                                setState(() => _showHint = !_showHint);
                                return;
                              }
                              // İlk kez gösteriliyor — hak kalmadıysa engelle.
                              if (_remainingHints <= 0) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(
                                      'Bu testteki ipucu hakların doldu.'
                                          .tr()),
                                  behavior:
                                      SnackBarBehavior.floating,
                                  duration:
                                      const Duration(seconds: 2),
                                ));
                                return;
                              }
                              // Hakkı tüket ve ipucunu göster.
                              setState(() {
                                _hintShownFor.add(_idx);
                                _showHint = true;
                              });
                            },
                      dense: true,
                    ),
                  Spacer(),
                  _chipButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Geri'.tr(),
                    onTap: _idx == 0 ? null : _goPrev,
                    dense: true,
                  ),
                  SizedBox(width: 6),
                  _chipButton(
                    icon: Icons.redo_rounded,
                    label: 'Atla'.tr(),
                    onTap: _skip,
                    dense: true,
                  ),
                ],
              ),
              SizedBox(height: 10),
              // Ana ilerleme butonu — son soruda "Bitir" onay dialog'u açar,
              // diğerlerinde direkt sonraki soruya geçer.
              GestureDetector(
                onTap: () {
                  if (isLast) {
                    _confirmAndFinish();
                  } else if (selected != null) {
                    _goNext();
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: (!isLast && selected == null)
                        ? _testOrange.withValues(alpha: 0.35)
                        : _testOrange,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: (!isLast && selected == null)
                        ? null
                        : [
                            BoxShadow(
                              color: _testOrange.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: Offset(0, 4),
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
                      SizedBox(width: 8),
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
      ),
    );
  }

  // ── Soru metni — fosforlu kalem destekli ──────────────────────────────
  // Eğer soru LaTeX içeriyorsa (formül var) → LatexText (vurgu kapalı).
  // Aksi halde kelime bazlı interaktif Text.rich:
  //   • _highlightMode kapalıyken → düz görünüm, vurgulu kelimeler sarı bg
  //   • _highlightMode açıkken → her kelime tıklanabilir, dokununca toggle
  Widget _buildQuestionStem(String text) {
    // LaTeX algıla — sayısal sorularda fosfor kapalı kalır.
    final hasLatex = text.contains(r'\(') ||
        text.contains(r'\[') ||
        text.contains(r'$');
    if (hasLatex) {
      return LatexText(text, fontSize: 15, lineHeight: 1.45);
    }
    // Kelime + ayraç olarak böl. RegExp ile boşluk + noktalama korunur.
    final tokens = _tokenize(text);
    final selectedSet =
        _highlights.putIfAbsent(_idx, () => <int>{});
    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(
          fontSize: 15,
          height: 1.45,
          color: AppPalette.textPrimary(context),
        ),
        children: [
          for (var i = 0; i < tokens.length; i++)
            if (tokens[i].isWord)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: GestureDetector(
                  onTap: !_highlightMode
                      ? null
                      : () {
                          setState(() {
                            if (selectedSet.contains(i)) {
                              selectedSet.remove(i);
                            } else {
                              selectedSet.add(i);
                            }
                          });
                        },
                  child: Container(
                    decoration: BoxDecoration(
                      color: selectedSet.contains(i)
                          ? const Color(0xFFFEF08A)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      tokens[i].text,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        height: 1.45,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                  ),
                ),
              )
            else
              TextSpan(text: tokens[i].text),
        ],
      ),
    );
  }

  /// Metni kelime ve ayraç token'larına böler. Kelime = harf+rakam dizisi.
  List<_QToken> _tokenize(String s) {
    final out = <_QToken>[];
    final buf = StringBuffer();
    bool curIsWord = false;
    void flush() {
      if (buf.isEmpty) return;
      out.add(_QToken(text: buf.toString(), isWord: curIsWord));
      buf.clear();
    }

    for (final c in s.runes) {
      // Harf, rakam, TR aksanlı, alt çizgi → kelime karakteri.
      final isLetter = (c >= 0x41 && c <= 0x5A) || // A-Z
          (c >= 0x61 && c <= 0x7A) || // a-z
          (c >= 0x30 && c <= 0x39) || // 0-9
          c == 0x5F || // _
          // TR
          c == 0xC7 || c == 0xE7 || // Çç
          c == 0x011E || c == 0x011F || // Ğğ
          c == 0x0130 || c == 0x0131 || // İı
          c == 0xD6 || c == 0xF6 || // Öö
          c == 0x015E || c == 0x015F || // Şş
          c == 0xDC || c == 0xFC; // Üü
      if (isLetter != curIsWord) {
        flush();
        curIsWord = isLetter;
      }
      buf.writeCharCode(c);
    }
    flush();
    return out;
  }

  // Üst ilerleme bandı için tek istatistik chip'i.
  /// AppBar bottom satırındaki araç ikonu — bayrak/karalama/kalem/raporla
  /// için. Cevap haritasındaki 22px daireler ile aynı boyut, aynı hiza.
  Widget _toolIconBtn({
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: active
                ? activeColor
                : AppPalette.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, Color tint, String value, String label) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: tint,
            ),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Hesap makinesi panel UI'ı.
  Widget _buildCalcPanel() {
    // Buton — Expanded ile esnek genişlik, panel boyutuna otomatik uyar.
    Widget btn(String label, {Color? bg, Color? fg, VoidCallback? on}) {
      return Expanded(
        child: SizedBox(
          height: 42,
          child: ElevatedButton(
            onPressed: on ?? () => _calcKey(label),
            style: ElevatedButton.styleFrom(
              backgroundColor: bg ?? Colors.white,
              foregroundColor: fg ?? Colors.black,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
              side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
            ),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    Widget btnRow(List<Widget> children) {
      final out = <Widget>[];
      for (int i = 0; i < children.length; i++) {
        if (i > 0) out.add(const SizedBox(width: 5));
        out.add(children[i]);
      }
      return Row(children: out);
    }

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        // Ekran genişliğine göre dinamik — küçük cihazlarda taşmaz.
        width: 248,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ekran
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _calcExpr.isEmpty ? '0' : _calcExpr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoMono(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  Text(
                    _calcResult,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoMono(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            btnRow([
              btn('C',
                  bg: const Color(0xFFFEF2F2), fg: const Color(0xFFDC2626)),
              btn('('),
              btn(')'),
              btn('⌫', bg: const Color(0xFFF3F4F6)),
            ]),
            const SizedBox(height: 5),
            btnRow([
              btn('7'),
              btn('8'),
              btn('9'),
              btn('÷', bg: const Color(0xFFFFF7ED), fg: _testOrange),
            ]),
            const SizedBox(height: 5),
            btnRow([
              btn('4'),
              btn('5'),
              btn('6'),
              btn('×', bg: const Color(0xFFFFF7ED), fg: _testOrange),
            ]),
            const SizedBox(height: 5),
            btnRow([
              btn('1'),
              btn('2'),
              btn('3'),
              btn('−', bg: const Color(0xFFFFF7ED), fg: _testOrange),
            ]),
            const SizedBox(height: 5),
            btnRow([
              btn('0'),
              btn('.'),
              btn('=', bg: Colors.black, fg: Colors.white),
              btn('+', bg: const Color(0xFFFFF7ED), fg: _testOrange),
            ]),
          ],
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

  Widget _chipButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool dense = false,
  }) {
    final disabled = onTap == null;
    return Material(
      color: disabled
          ? Color(0xFFEFF1F6)
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
              SizedBox(width: 5),
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
    final isDark = AppPalette.isDark(context);
    // Zemin her durumda nötr (light=beyaz / dark=card). Seçim sadece
    // turuncu çerçeve + harf dairesinin turuncu vurgusuyla belli olsun.
    final tileBg = isDark ? AppPalette.card(context) : Colors.white;
    final tileInk = AppPalette.textPrimary(context);
    final eliminated = (_eliminated[_idx]?.contains(letter)) ?? false;
    final disabled = eliminated;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tileBg,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _testOrange
                  : (eliminated
                      ? Colors.black.withValues(alpha: 0.18)
                      : AppPalette.border(context)),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _testOrange.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                  onTap: disabled ? null : () => _pick(letter),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
                    child: Opacity(
                      opacity: disabled ? 0.45 : 1.0,
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? _testOrange.withValues(alpha: 0.15)
                                  : (isDark
                                      ? AppPalette.bg(context)
                                      : const Color(0xFFF3F4F6)),
                              shape: BoxShape.circle,
                              border: selected
                                  ? Border.all(
                                      color: _testOrange, width: 1.2)
                                  : null,
                            ),
                            child: Text(
                              letter,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: selected ? _testOrange : tileInk,
                                decoration: eliminated
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                color: tileInk,
                                decoration: eliminated
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor:
                                    tileInk.withValues(alpha: 0.6),
                                decorationThickness: 2,
                              ),
                              child: LatexText(
                                text,
                                fontSize: 13.5,
                                lineHeight: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // ── Sağda küçük ✕ butonu — şıkkı ele/eleme aç-kapat ───────
              // Tek tıkla işlem yapılır, uzun-bas yok.
              InkWell(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                onTap: () => _toggleEliminate(letter),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: eliminated
                          ? const Color(0xFFDC2626).withValues(alpha: 0.12)
                          : AppPalette.border(context).withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      eliminated
                          ? Icons.close_rounded
                          : Icons.close_rounded,
                      size: 14,
                      color: eliminated
                          ? const Color(0xFFDC2626)
                          : AppPalette.textSecondary(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Cevap haritası — yatay scroll, 1..N noktalı satır.
//  Durumlar:
//    • Aktif (current): turuncu dolu
//    • Cevaplanmış: koyu dolu
//    • Boş: hafif border, içi şeffaf
//  Tıklayınca o soruya atlama.
// Soru metni token'ı (kelime veya boşluk/noktalama).
class _QToken {
  final String text;
  final bool isWord;
  const _QToken({required this.text, required this.isWord});
}

// ═════════════════════════════════════════════════════════════════════════════
// ═════════════════════════════════════════════════════════════════════════════
//  Test sayfası yardım ekranı — "Bu sayfa nasıl çalışır?"
//  Test çözerken kullanılabilen tüm özelliklerin sade görsel rehberi.
// ═════════════════════════════════════════════════════════════════════════════
class _TestPageHelpPage extends StatelessWidget {
  const _TestPageHelpPage();

  @override
  Widget build(BuildContext context) {
    final bg = AppPalette.bg(context);
    final ink = AppPalette.textPrimary(context);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        foregroundColor: ink,
        title: Text(
          'Bu Sayfa Nasıl Çalışır?'.tr(),
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          // ── Üst tanıtım ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFF6A00).withValues(alpha: 0.14),
                  const Color(0xFFDB2777).withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFFF6A00).withValues(alpha: 0.32),
                  width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.quiz_rounded,
                    size: 22, color: Color(0xFFFF6A00)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Soruyu oku, şıkları değerlendir, gerekirse şık ele veya soruyu işaretle.'
                        .tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ══════════ ÜST BAR ══════════
          _helpGroupHeader(context, '⏱ ÜST BAR'),
          _helpSection(
            context,
            icon: Icons.timer_rounded,
            iconColor: const Color(0xFFFF6A00),
            title: 'Zaman Göstergesi',
            body: 'Yarış / Normal modda soru başına kalan süre turuncu pill. '
                '10 saniye kala telefon hafifçe titrer, süre rengi kırmızıya '
                'döner. Süre dolunca otomatik sonraki soruya geçilir.',
          ),
          _helpSection(
            context,
            icon: Icons.timer_outlined,
            iconColor: const Color(0xFF2563EB),
            title: 'Kronometre (Rahat Modda)',
            body: 'Rahat modda süre yok, ama testte geçen toplam süre üstte '
                'görünür. Stres yapmasın diye X ile gizlenebilir → küçük '
                'saat ikonuyla tekrar açılır.',
          ),

          // ══════════ İSTATİSTİK BANDI ══════════
          _helpGroupHeader(context, '📊 İLERLEME ŞERİDİ'),
          _helpSection(
            context,
            icon: Icons.check_circle_outline_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Cevaplanan / Şüpheli / Boş',
            body: 'Üstte 3 sayaç: kaç soruyu cevapladın, kaçını şüpheli '
                'işaretledin, kaçı hâlâ boş. Bir bakışta nerede olduğunu '
                'görürsün.',
          ),

          // ══════════ SORU KARTI ══════════
          _helpGroupHeader(context, '❓ SORU KARTI'),
          _helpSection(
            context,
            icon: Icons.flag_outlined,
            iconColor: const Color(0xFFD97706),
            title: 'Şüpheli İşareti (Bayrak)',
            body: 'Emin değilsen soruyu bayrakla işaretle, önce diğerlerini '
                'çöz, sonra geri dön. Alt navigasyonda sarı bayrakla '
                'görünür → tek tıkla geri ulaşırsın.',
          ),
          _helpSection(
            context,
            icon: Icons.edit_note_rounded,
            iconColor: const Color(0xFFFF6A00),
            title: 'Karalama Notu',
            body: 'Her soru için ayrı not alanı. Çözüm yolunu, hatırlatmayı, '
                'hesap basamaklarını yaz — sayfa kapansa da geri dönünce '
                'notların duruyor.',
          ),
          _helpSection(
            context,
            icon: Icons.brush_rounded,
            iconColor: const Color(0xFFFBBF24),
            title: 'Fosforlu Kalem (Sözel)',
            body: 'Sözel sorularda soru metnindeki önemli kelimeleri sarıya '
                'boyamak için fırça ikonuna bas (sarı = aktif). Kelimeye '
                'dokun → boyar, tekrar dokun → kalkar. Matematik gibi '
                'formüllü sorularda otomatik kapalı.',
          ),
          _helpSection(
            context,
            icon: Icons.report_outlined,
            iconColor: const Color(0xFFDC2626),
            title: 'Soruyu Raporla',
            body: 'Soru yanlış / belirsiz / çift cevaplı görünüyorsa rapor '
                'ikonuna bas → neden seç. 3+ rapor alan sorular otomatik '
                'olarak havuzdan kaldırılır.',
          ),

          // ══════════ ŞIKLAR ══════════
          _helpGroupHeader(context, '🔤 ŞIKLAR'),
          _helpSection(
            context,
            icon: Icons.radio_button_checked,
            iconColor: const Color(0xFFFF6A00),
            title: 'Şık Seçme',
            body: 'Bir şıka tıkla → cevabın olarak seçilir, turuncu çerçeve '
                'belirir. Tekrar tıkla → cevap kaldırılır (boş bırakılır).',
          ),
          _helpSection(
            context,
            icon: Icons.close_rounded,
            iconColor: const Color(0xFFDC2626),
            title: 'Şık Eleme (✕ butonu)',
            body: 'Her şıkın sağında küçük ✕ ikonu var. Tıkla → o şık '
                'soluklaşır + üzeri çizilir ("bu olamaz" anlamında). '
                'Tekrar tıkla → geri alınır. Sınav stratejisi için altın.',
          ),

          // ══════════ ALT BAR ══════════
          _helpGroupHeader(context, '🎛 ALT BAR'),
          _helpSection(
            context,
            icon: Icons.lightbulb_outline_rounded,
            iconColor: const Color(0xFFFBBF24),
            title: 'İpucu',
            body: 'Test başına 3 ipucu hakkın var. Buton etiketinde kalan '
                'hak görünür (örn. "İpucu (2)"). Aynı soruyu açıp kapatmak '
                'hak harcamaz, sadece yeni soruda ilk açış sayar. Yarış '
                'modunda ipucu yoktur.',
          ),
          _helpSection(
            context,
            icon: Icons.arrow_back_rounded,
            iconColor: const Color(0xFF6B7280),
            title: 'Geri / Atla',
            body: '"Geri" önceki soruya, "Atla" cevabı boş bırakıp sonraki '
                'soruya geçer. Atlanan soruya alt nokta navigasyonundan '
                'tekrar dönebilirsin.',
          ),
          _helpSection(
            context,
            icon: Icons.arrow_forward_rounded,
            iconColor: const Color(0xFFFF6A00),
            title: 'Sonraki Soru / Testi Bitir',
            body: 'Şık seçilince turuncu olur, tıkla → bir sonraki soruya '
                'geç. Son soruda etiket "Testi Bitir"e döner. Boş veya '
                'şüpheli soru varsa onay dialog\'u çıkar; "Devam et" '
                'tıklarsan ilk boş soruya gönderir.',
          ),

          // ══════════ NOKTA NAVİGASYONU ══════════
          _helpGroupHeader(context, '🔵 NAVİGASYON'),
          _helpSection(
            context,
            icon: Icons.circle_outlined,
            iconColor: const Color(0xFF2563EB),
            title: 'Alt Nokta Şeridi',
            body: 'Üst barın hemen altında 1, 2, 3 ... küçük noktalar. '
                'Renk kodları: turuncu = mevcut soru, siyah dolu = '
                'cevaplanmış, sarı + bayrak = şüpheli, boş = henüz '
                'cevaplanmamış. Tıkla → o soruya atla.',
          ),

          // ══════════ YÜZER BUTONLAR ══════════
          _helpGroupHeader(context, '🎯 YÜZER BUTONLAR'),
          _helpSection(
            context,
            icon: Icons.calculate_rounded,
            iconColor: Colors.black,
            title: 'Hesap Makinesi',
            body: 'Sağ alttaki siyah yuvarlak buton → küçük hesap makinesi '
                'paneli açılır. Toplama, çıkarma, çarpma, bölme, parantez. '
                'Sayfadan çıkmadan hesap yap. Tekrar tıkla → kapanır.',
          ),

          const SizedBox(height: 12),
          Center(
            child: Text(
              'Başarılar! 🎯',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppPalette.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpGroupHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppPalette.textSecondary(context),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _helpSection(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    final ink = AppPalette.textPrimary(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppPalette.border(context).withValues(alpha: 0.6),
            width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ink,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body.tr(),
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: ink.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class _AnswerMap extends StatelessWidget {
  final int count;
  final int currentIndex;
  final bool Function(int) isAnswered;
  final bool Function(int)? isFlagged;
  final void Function(int) onTap;
  const _AnswerMap({
    required this.count,
    required this.currentIndex,
    required this.isAnswered,
    this.isFlagged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: count,
        itemBuilder: (ctx, i) {
          final isCur = i == currentIndex;
          final filled = isAnswered(i);
          final flagged = isFlagged?.call(i) ?? false;
          final Color bg;
          final Color fg;
          final Color border;
          if (isCur) {
            bg = _testOrange;
            fg = Colors.white;
            border = _testOrange;
          } else if (flagged) {
            // Şüpheli — sarı/turuncu çerçeve, içi boyalı vurgu.
            bg = const Color(0xFFFEF3C7);
            fg = const Color(0xFFD97706);
            border = const Color(0xFFD97706);
          } else if (filled) {
            bg = AppPalette.textPrimary(context);
            fg = AppPalette.bg(context);
            border = AppPalette.textPrimary(context);
          } else {
            bg = Colors.transparent;
            fg = AppPalette.textSecondary(context);
            border = AppPalette.border(context);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => onTap(i),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: border, width: flagged ? 1.5 : 1),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.poppins(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ),
                  if (flagged)
                    const Positioned(
                      right: -2,
                      top: -2,
                      child: Icon(
                        Icons.flag_rounded,
                        size: 10,
                        color: Color(0xFFD97706),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
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
  // Topluluk istatistiği — havuzdaki bu konu için.
  ({int attempts, int avgPct})? _communityStats;

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
    // Eğitim profilinden okunabilir seviye etiketi üret + havuz istatistik.
    EduProfile.load().then((profile) async {
      if (!mounted || profile == null) return;
      setState(() {
        _eduLabel = _humanizeEduLevel(profile);
      });
      // 1) Bu sonucu anonim olarak havuza işle — sonraki kullanıcılar
      //    karşılaştırma yapabilsin.
      unawaited(QuestionPoolService.recordAttempt(
        profile: profile,
        subject: widget.subjectName,
        topic: widget.topic,
        correct: _correct,
        total: widget.questions.length,
      ));
      // 2) Mevcut topluluk istatistiğini oku → UI'da kart göster.
      final stats = await QuestionPoolService.readCommunityStats(
        profile: profile,
        subject: widget.subjectName,
        topic: widget.topic,
      );
      if (!mounted) return;
      setState(() => _communityStats = stats);
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

  // Soru tipini sorulardan çıkar — sonuç kartında "Soru tipi: ..." satırı için.
  // tf  : opts'ta tam 2 şık (Doğru/Yanlış)
  // fill: soru metninde 5+ alt çizgi (boşluk doldurma)
  // mc  : diğerleri (klasik çoktan seçmeli, 5 şık)
  // Hepsi aynı tipse o tip, karışıksa "Karışık".
  String get _questionTypeLabel {
    if (widget.questions.isEmpty) return '';
    int tf = 0, fill = 0, mc = 0;
    for (final q in widget.questions) {
      if (q.opts.length == 2) {
        tf++;
      } else if (q.q.contains('____')) {
        fill++;
      } else {
        mc++;
      }
    }
    final n = tf + fill + mc;
    if (n == 0) return '';
    if (tf == n) return 'Doğru-Yanlış'.tr();
    if (fill == n) return 'Boşluk Doldurma'.tr();
    if (mc == n) return 'Çoktan Seçmeli'.tr();
    return 'Karışık'.tr();
  }

  @override
  Widget build(BuildContext context) {
    final pageBg = AppPalette.bg(context);
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
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
              questionTypeLabel: _questionTypeLabel,
              correct: _correct,
              wrong: _wrong,
              empty: _empty,
              total: widget.questions.length,
              elapsedSeconds: widget.elapsedSeconds,
              bgColor: Colors.white,
            ),
          ),
          SizedBox(height: 14),
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
              SizedBox(height: 10),
              _actionRow(
                icon: Icons.send_rounded,
                label: "Arkadaşına gönder".tr(),
                color: Colors.white,
                fg: Colors.black,
                iconColor: Color(0xFF22C55E), // canlı yeşil
                iconRotation: -math.pi / 4, // 45° CCW → +X & +Y (NE)
                onTap: () => _openShareMode(onFriend: true),
              ),
              SizedBox(height: 10),
              _actionRow(
                icon: Icons.menu_book_rounded,
                iconColor: Color(0xFF2563EB),
                label: 'Konunun özetine bak'.tr(),
                color: Colors.white,
                fg: Colors.black,
                onTap: _openShortReview,
              ),
              SizedBox(height: 10),
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
                    ? Color(0xFFEFF1F6)
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
                SizedBox(height: 12),
                ..._unsolvedAnswerCards(),
              ],
              // ── Topluluk kıyas kartı — yanlış sorular satırının altında ─
              // Veri en az 3 deneme + 10 soru toplanınca görünür (anlamlı
              // ortalama). Aksi halde gizli kalır.
              if (_communityStats != null) ...[
                SizedBox(height: 10),
                _communityCompareCard(),
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
        color: bgColor ?? AppPalette.bg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.border(context), width: 1),
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
        questionTypeLabel: _questionTypeLabel,
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
    // GestureDetector → InkWell + Material ile değiştirildi: tap'in
    // mutlaka kaydedilmesi (HitTestBehavior.opaque eşdeğeri) + dokunma
    // ripple geri bildirimi. Önceki haliyle bazı cihazlarda "Arkadaşına
    // gönder" satırının tıklaması düştü-düşmedi belirsizdi.
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: borderColor != null
                ? Border.all(color: borderColor, width: 1)
                : null,
          ),
          child: Row(
            children: [
              iconWidget,
              SizedBox(width: 10),
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
      ),
    );
  }

  // ── Topluluk kıyas kartı — bu konuda kaç öğrenci, ortalama %kaç ──────
  Widget _communityCompareCard() {
    final s = _communityStats;
    if (s == null) return const SizedBox.shrink();
    final userPct = widget.questions.isEmpty
        ? 0
        : ((_correct * 100) / widget.questions.length).round();
    final diff = userPct - s.avgPct;
    final isAbove = diff >= 0;
    final Color tint = isAbove
        ? const Color(0xFF10B981) // yeşil — ortalamadan yüksek
        : const Color(0xFFD97706); // amber — ortalamanın altı
    final String headline = isAbove
        ? 'Ortalamadan ${diff.abs()} puan yüksek 🎯'
        : 'Ortalamadan ${diff.abs()} puan düşük';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 18, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Topluluk Kıyaslaması'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${s.attempts} ${'öğrenci bu konuyu çözdü'.tr()}',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniStatBlock(
                  label: 'TOPLULUK ORT.'.tr(),
                  value: '%${s.avgPct}',
                  tint: Colors.black54,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStatBlock(
                  label: 'SEN'.tr(),
                  value: '%$userPct',
                  tint: tint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              headline.tr(),
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: tint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStatBlock({
    required String label,
    required String value,
    required Color tint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.black54,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: tint,
              height: 1.0,
            ),
          ),
        ],
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
          isEmpty ? Color(0xFF6B7280) : Color(0xFFDC2626);
      final badgeLabel = isEmpty ? "Boş".tr() : "Yanlış".tr();
      // Şıkları sabit harf sırasıyla diz (A, B, C, D, E) — q.opts Map<String,
      // String> olduğu için key sırası garantili değil; sıralayıp listeliyoruz.
      final optionKeys = q.opts.keys.toList()..sort();
      cards.add(Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
            color: AppPalette.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.border(context), width: 1),
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
                  SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppPalette.cardMuted(context),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: AppPalette.border(context), width: 1),
                    ),
                    child: Text(
                      "Boş bıraktın".tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 10),
            // Sorunun tamamı
            LatexText(q.q, fontSize: 13, lineHeight: 1.45),
            SizedBox(height: 12),
            // TÜM ŞIKLAR — kullanıcının seçtiği kırmızı, doğru olan yeşil,
            // diğerleri nötr. Hem soru bütünü görünür hem hangi şıkkın
            // doğru/yanlış olduğu net.
            for (int j = 0; j < optionKeys.length; j++) ...[
              if (j > 0) SizedBox(height: 6),
              _optionTile(
                letter: optionKeys[j],
                text: q.opts[optionKeys[j]] ?? '',
                isUser: !isEmpty && optionKeys[j] == a,
                isCorrect: optionKeys[j] == q.ans,
              ),
            ],
            SizedBox(height: 12),
            Container(
                height: 1, color: Colors.black.withValues(alpha: 0.08)),
            SizedBox(height: 10),
            Text(
              "Çözüm".tr(),
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppPalette.textSecondary(context),
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 4),
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
      bg = Color(0xFFDCFCE7);
      border = Color(0xFF86EFAC);
      letterBg = Color(0xFF059669);
      ink = Color(0xFF064E3B);
      badge = "Doğru".tr();
    } else if (isUser) {
      bg = Color(0xFFFEE2E2);
      border = Color(0xFFFCA5A5);
      letterBg = Color(0xFFDC2626);
      ink = Color(0xFF7F1D1D);
      badge = "Senin cevabın".tr();
    } else {
      bg = Colors.white;
      border = Color(0xFFE5E7EB);
      letterBg = Color(0xFFF3F4F6);
      ink = Color(0xFF374151);
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
                    : Color(0xFF374151),
              ),
            ),
          ),
          SizedBox(width: 8),
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
            SizedBox(width: 8),
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
  final String questionTypeLabel; // "Çoktan Seçmeli" / "Doğru-Yanlış" / "Boşluk Doldurma" / "Karışık"
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
    this.questionTypeLabel = '',
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
            offset: Offset(0, 8),
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
                      // Seviye satırı — eduLabel öncelikli, yoksa grade.
                      // "Seviye: 6. Sınıf" / "Seviye: Lise 10. Sınıf" /
                      // "Seviye: KPSS Hazırlık" şeklinde, Ders/Konu satırlarıyla
                      // tutarlı stilde.
                      if (eduLabel.isNotEmpty || grade.isNotEmpty) ...[
                        _labeledLine(
                          label: 'Seviye'.tr(),
                          value: eduLabel.isNotEmpty ? eduLabel : grade,
                          icon: _eduIcon(),
                        ),
                        SizedBox(height: 5),
                      ],
                      _labeledLine(
                        label: 'Ders'.tr(),
                        value: subjectName,
                        icon: _subjectIcon(),
                      ),
                      SizedBox(height: 5),
                      _labeledLine(
                        label: 'Konu'.tr(),
                        value: topic,
                        icon: _topicIcon(),
                        maxLines: 2,
                      ),
                      if (questionTypeLabel.isNotEmpty) ...[
                        SizedBox(height: 5),
                        _labeledLine(
                          label: 'Soru tipi'.tr(),
                          value: questionTypeLabel,
                          icon: '📝',
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 22),
                _centeredUserBlock(),
              ],
            ),
            SizedBox(height: 14),
            // ══ Donut grafiği + sağda lejant ════════════════════════
            _donutStats(),
            SizedBox(height: 10),
            // ══ Motivasyon kutusu — kullanıcı özel mesaj yazdıysa onu
            //    göster, yoksa varsayılan motivasyon. Yazı rengi override
            //    edilebilir.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
            color: AppPalette.card(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppPalette.border(context), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_subjectEmoji(), style: TextStyle(fontSize: 18)),
                  SizedBox(width: 10),
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
            SizedBox(height: 13),
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
                      SizedBox(height: 2),
                      Text(
                        'qualsar.app',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: _alKirmizi,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
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
                      SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
            color: AppPalette.card(context),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppPalette.border(context), width: 1),
                        ),
                        child: QrImageView(
                          data: 'https://qualsar.app',
                          version: QrVersions.auto,
                          size: 56,
                          backgroundColor: AppPalette.card(context),
                          eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppPalette.textPrimary(context),
                          ),
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppPalette.textPrimary(context),
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
                offset: Offset(0, 3),
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
        SizedBox(height: 6),
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
        SizedBox(height: 2),
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
              style: TextStyle(fontSize: 14),
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
                    SizedBox(height: 1),
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
          SizedBox(width: 8),
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
                    SizedBox(width: 5),
                    Text(
                      'Süre'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _inkMute,
                      ),
                    ),
                    Spacer(),
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
                SizedBox(height: 6),
                Container(
                  height: 1,
                  color: (_dark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.12),
                ),
                SizedBox(height: 8),
                _legendItem(
                    color: green,
                    label: 'Doğru'.tr(),
                    count: correct,
                    pct: pctOf(correct)),
                SizedBox(height: 8),
                _legendItem(
                    color: red,
                    label: 'Yanlış'.tr(),
                    count: wrong,
                    pct: pctOf(wrong)),
                SizedBox(height: 8),
                _legendItem(
                    color: gray,
                    label: 'Boş'.tr(),
                    count: empty,
                    pct: pctOf(empty)),
                SizedBox(height: 8),
                Container(
                  height: 1,
                  color: (_dark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.12),
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.quiz_rounded,
                        size: 12, color: _inkMute),
                    SizedBox(width: 5),
                    Text(
                      'Toplam'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _inkMute,
                      ),
                    ),
                    Spacer(),
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
        SizedBox(width: 7),
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
        SizedBox(width: 6),
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
  final String questionTypeLabel;
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
    this.questionTypeLabel = '',
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
    // Android'de bu değer kullanılmaz ama null geçmek güvenli.
    Rect? origin;
    try {
      final pageBox = context.findRenderObject() as RenderBox?;
      if (pageBox != null && pageBox.attached) {
        origin = pageBox.localToGlobal(Offset.zero) & pageBox.size;
      }
    } catch (_) {}
    setState(() => _sharing = true);
    final msg = widget.friendMode
        ? '${widget.subjectName} · ${widget.topic}\n${widget.correct}/${widget.total} · %${((widget.correct * 100) / (widget.total == 0 ? 1 : widget.total)).round()}\n\nQuAlsar\'da sen de dene: https://qualsar.app'
        : 'QuAlsar ile çözdüğüm test — sen de dene: https://qualsar.app';
    // Tüm yollar başarısız olursa kullanıcı en azından metni panodan
    // alabilsin — son çare clipboard fallback.
    bool sheetOpened = false;
    try {
      // 1) Capture'dan önce mevcut frame'in tamamlanmasını bekle.
      await WidgetsBinding.instance.endOfFrame;

      final boundary = _shotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      Uint8List? bytes;
      if (boundary != null && boundary.attached) {
        // 2) Henüz ilk paint yapılmadıysa needsPaint true olur.
        if (boundary.debugNeedsPaint) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        try {
          // pixelRatio 2.5 → 1.8: %50 daha az bellek, görüntü hâlâ HD.
          // Yüksek değerler düşük-RAM cihazlarda paylaşım sheet'i
          // açılırken uygulamayı çökertiyordu.
          final image = await boundary.toImage(pixelRatio: 1.8);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (byteData != null) {
            bytes = byteData.buffer.asUint8List();
          }
        } catch (e, st) {
          debugPrint('[TestShare] capture fail: $e\n$st');
        }
      }

      // 3) Image elde edildiyse dosyaya yazıp resimli paylaş; aksi halde
      //    görsel-yok fallback ile sadece metin paylaş (asla çökmesin).
      ShareResult? result;
      if (bytes != null) {
        try {
          final dir = await getTemporaryDirectory();
          final file = File(
              '${dir.path}/qualsar_test_${DateTime.now().millisecondsSinceEpoch}.png');
          await file.writeAsBytes(bytes, flush: true);
          result = await Share.shareXFiles(
            [
              XFile(file.path,
                  mimeType: 'image/png', name: 'qualsar_test.png')
            ],
            text: msg,
            subject: 'QuAlsar Test Sonucu',
            sharePositionOrigin: origin,
          );
          sheetOpened = true;
        } catch (e, st) {
          debugPrint('[TestShare] file share fail: $e\n$st');
          // File share çöktü → text-only fallback.
          result = null;
        }
      }
      // Görsel paylaşımı başarısızsa metin-only fallback.
      if (result == null) {
        try {
          result = await Share.share(msg, sharePositionOrigin: origin);
          sheetOpened = true;
        } catch (e, st) {
          debugPrint('[TestShare] text share fail: $e\n$st');
        }
      }

      if (!mounted) return;
      if (result != null && result.status == ShareResultStatus.unavailable) {
        // Sistem paylaşım sheet'i açıldı ama hiç hedef uygulama yok →
        // mesajı panoya kopyala ki kullanıcı manuel olarak yapıştırabilsin.
        await Clipboard.setData(ClipboardData(text: msg));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Paylaşım uygulaması bulunamadı — metin panoya kopyalandı.'
                  .tr()),
          behavior: SnackBarBehavior.floating,
        ));
      } else if (!sheetOpened) {
        // Ne görsel ne text — clipboard'a düş.
        await Clipboard.setData(ClipboardData(text: msg));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Paylaşım açılamadı — metin panoya kopyalandı.'.tr()),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e, st) {
      debugPrint('[TestShare] hata: $e\n$st');
      if (!mounted) return;
      // En son çare: clipboard.
      await Clipboard.setData(ClipboardData(text: msg));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${'Paylaşılamadı, metin panoya kopyalandı:'.tr()} $e'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageBg = AppPalette.bg(context);
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
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
                                  questionTypeLabel:
                                      widget.questionTypeLabel,
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
              SizedBox(height: 10),
              // Panel açıkken tam palet, kapalıyken küçük "Renk Seç" pill'i.
              if (_panelOpen) _colorPanel() else _colorOpenPill(),
              SizedBox(height: 12),
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
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        Icon(Icons.ios_share_rounded,
                            color: Colors.white, size: 18),
                      SizedBox(width: 8),
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
            color: AppPalette.card(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppPalette.textPrimary(context), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.palette_rounded,
                  size: 14, color: Colors.black87),
              SizedBox(width: 6),
              Text(
                'Renk Seç'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.expand_more_rounded,
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
            color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.textPrimary(context), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.palette_rounded,
                  size: 16, color: Colors.black),
              SizedBox(width: 6),
              Text(
                'Renk Seç'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 8),
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
                    color: AppPalette.textSecondary(context),
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              Spacer(),
              // Sıfırla — biraz solda dursun (sağ kenara dayanmasın)
              GestureDetector(
                onTap: _resetColor,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppPalette.cardMuted(context),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    'Sıfırla'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textSecondary(context),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              // ✕ paneli kapat — Sıfırla ile aynı hizada
              GestureDetector(
                onTap: () => setState(() => _panelOpen = false),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppPalette.cardMuted(context),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: Colors.black54),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          // ── Hedef seçici (4 chip) ─────────────────────────────────
          Row(
            children: [
              _targetChip('bg', 'Arka Plan'.tr()),
              SizedBox(width: 6),
              _targetChip('donut', 'Çerçeve'.tr()),
              SizedBox(width: 6),
              _targetChip('text', 'Yazı'.tr()),
              SizedBox(width: 6),
              _targetChip('motivation', 'Motivasyon'.tr()),
            ],
          ),
          SizedBox(height: 10),
          // ── 2-sıra yatay scroll palet ─────────────────────────────
          SizedBox(
            height: 64,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
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
                            Border.all(color: AppPalette.textPrimary(context), width: 1),
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
                              ? Color(0xFFFF6A00)
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
