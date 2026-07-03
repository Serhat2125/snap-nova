// ═══════════════════════════════════════════════════════════════════════════
//  HomeworkSolveScreen — Öğrencinin sınıf ödevini çözdüğü ekran.
//
//  Soru tipleri:
//    • mc   → çoktan seçmeli (radio butonlar)
//    • tf   → doğru/yanlış toggle
//    • fill → boşluk doldurma (text input)
//    • open → açık uçlu (multiline text)
//
//  Akış:
//    1. Sayfa açılınca HomeworkService.markInProgress (status = in_progress)
//    2. Kullanıcı tüm soruları cevaplar
//    3. "Teslim Et" → HomeworkService.submitAnswers(correct, wrong)
//    4. Skor + doğru cevaplar gösterilir
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/activity_writer_service.dart';
import '../services/ai_provider_service.dart';
import '../services/app_settings_service.dart';
import '../services/parent_preview.dart';
import '../services/homework_service.dart';
import '../services/locale_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class HomeworkSolveScreen extends StatefulWidget {
  final String classId;
  final HomeworkModel homework;
  /// Öğrencinin bu ödeve ait MEVCUT teslimi (varsa). Zaten teslim edilmişse
  /// ekran salt-okunur sonuç modunda açılır — tekrar çözme/teslim ve statü
  /// ezme engellenir.
  final HomeworkSubmissionModel? submission;
  const HomeworkSolveScreen({
    super.key, required this.classId, required this.homework, this.submission,
  });

  @override
  State<HomeworkSolveScreen> createState() => _HomeworkSolveScreenState();
}

class _HomeworkSolveScreenState extends State<HomeworkSolveScreen>
    with WidgetsBindingObserver {
  /// Soru index → kullanıcının cevabı
  final Map<int, String> _answers = {};
  /// Açık uçlu sorular için text controller'lar (sayfayı tekrar açtığında korumak için)
  final Map<int, TextEditingController> _openCtrls = {};
  bool _submitted = false;
  bool _submitting = false;
  int _correctCount = 0;
  int _wrongCount = 0;
  int _pendingOpen = 0; // öğretmen değerlendirmesi bekleyen açık uçlu sayısı

  // ── Zaman takibi ──────────────────────────────────────────────────────
  // Aktif: ekran önünde (resumed) geçen süre. Pasif: ödev açıkken uygulama
  // arka plana alınınca/kapanınca geçen süre. Teslimde Firestore'a yazılır.
  late final DateTime _startedAt;
  final Stopwatch _activeWatch = Stopwatch();
  int _passiveMs = 0;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Zaten teslim edilmişse → salt-okunur sonuç modu. markInProgress
    // ÇAĞRILMAZ (önceki teslimin statüsünü/skorunu bozmaz); süre sayacı
    // başlatılmaz, "Teslim Et" butonu gizli kalır → üzerine yazma imkânsız.
    final existing = widget.submission;
    if (existing != null && existing.isSubmitted) {
      _submitted = true;
      _correctCount = existing.correct ?? 0;
      _wrongCount = existing.wrong ?? 0;
      _pendingOpen = existing.answers.where((a) => a.isCorrect == null).length;
      _startedAt = existing.startedAt ?? DateTime.now();
      return;
    }
    _startedAt = DateTime.now();
    _activeWatch.start();
    // Status'u in_progress yap
    HomeworkService.markInProgress(widget.classId, widget.homework.id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pausedAt != null) {
        _passiveMs += DateTime.now().difference(_pausedAt!).inMilliseconds;
        _pausedAt = null;
      }
      _activeWatch.start();
    } else {
      // paused / inactive / hidden / detached → aktif sayacı durdur, pasifi başlat
      if (_activeWatch.isRunning) _activeWatch.stop();
      _pausedAt ??= DateTime.now();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _openCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isCorrect(Map<String, dynamic> q, String answer) {
    final correct = (q['answer'] ?? '').toString().trim().toLowerCase();
    final given = answer.trim().toLowerCase();
    if (correct.isEmpty) return false;
    // MC: "A" eşleşmesi veya tam metin
    final type = (q['type'] ?? '').toString();
    if (type == 'mc') {
      if (correct == given) return true;
      // Belki kullanıcı tam şıkı yapıştırdı: "A) Foo" — ilk harfi al
      if (given.isNotEmpty && given[0] == correct[0]) return true;
    }
    if (type == 'tf') {
      return correct == given;
    }
    if (type == 'fill') {
      // Boşluk doldurmada normalize karşılaştır
      return correct == given;
    }
    if (type == 'open') {
      // Açık uçluda kelime overlap heuristic — en az %50 anahtar kelime eşleşmeli
      final correctWords = correct.split(RegExp(r'\s+'))
          .where((w) => w.length > 3).toSet();
      final givenWords = given.split(RegExp(r'\s+'))
          .where((w) => w.length > 3).toSet();
      if (correctWords.isEmpty) return given.isNotEmpty;
      final overlap = correctWords.intersection(givenWords).length;
      return overlap / correctWords.length >= 0.5;
    }
    return false;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    // Ebeveyn önizlemesi: çocuğun adına ödev teslim edilemez.
    if (ParentPreview.guard(context)) return;
    final qs = widget.homework.questions;
    if (qs.isEmpty) return;
    int correct = 0;
    int wrong = 0;
    int pendingOpen = 0;
    final answersList = <Map<String, dynamic>>[];
    for (int i = 0; i < qs.length; i++) {
      final q = qs[i];
      final type = (q['type'] ?? 'mc').toString();
      final ans = _answers[i] ?? '';
      bool? isCorrect;
      if (type == 'open') {
        if (ans.trim().isEmpty) {
          isCorrect = false; // boş bırakılan açık uçlu = yanlış
          wrong++;
        } else {
          isCorrect = null; // dolu açık uçlu → öğretmen değerlendirecek
          pendingOpen++;
        }
      } else if (ans.trim().isEmpty) {
        isCorrect = false; // boş = teslim yapmadı sayılır
        wrong++;
      } else if (_isCorrect(q, ans)) {
        isCorrect = true;
        correct++;
      } else {
        isCorrect = false;
        wrong++;
      }
      answersList.add({
        'index': i,
        'type': type,
        'q': (q['q'] ?? '').toString(),
        'studentAnswer': ans,
        'isCorrect': isCorrect,
      });
    }
    setState(() {
      _submitting = true;
    });
    // Aktif/pasif süreyi sabitle (teslim anında pasif sayaç açıksa kapat).
    if (_pausedAt != null) {
      _passiveMs += DateTime.now().difference(_pausedAt!).inMilliseconds;
      _pausedAt = null;
    }
    final ok = await HomeworkService.submitAnswers(
      classId: widget.classId,
      homeworkId: widget.homework.id,
      correct: correct,
      wrong: wrong,
      answers: answersList,
      startedAt: _startedAt,
      activeMs: _activeWatch.elapsedMilliseconds,
      passiveMs: _passiveMs,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _submitted = ok;
      _correctCount = correct;
      _wrongCount = wrong;
      _pendingOpen = pendingOpen;
    });
    if (ok) {
      if (correct >= wrong) {
        AppSettingsService.instance.notifySuccess();
      } else {
        AppSettingsService.instance.notifyError();
      }
      // Aktivite log — ebeveyn dashboard
      unawaited(ActivityWriterService.recordTestCompleted(
        correct: correct,
        wrong: wrong,
        blank: 0,
        subject: widget.homework.subject,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final qs = widget.homework.questions;
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text(widget.homework.title,
            style: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w800, color: ink),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: _submitted
            ? _buildResult(context)
            : Column(
                children: [
                  // Öğretmenin ödev mesajı — ödevin en başında görünür.
                  if (widget.homework.teacherNote.trim().isNotEmpty)
                    _teacherNoteCard(context),
                  // Üst başlık kartı
                  Container(
                    margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: AppPalette.card(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppPalette.border(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${widget.homework.subject} · ${widget.homework.topic}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                    color: muted,
                                  )),
                              const SizedBox(height: 2),
                              Text('${qs.length} soru'.tr(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 13.5, fontWeight: FontWeight.w800,
                                    color: ink,
                                  )),
                            ],
                          ),
                        ),
                        Text(
                          '${_answers.length}/${qs.length} cevaplandı'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: const Color(0xFF7C3AED),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: qs.isEmpty
                        ? Center(child: Text('Bu ödevde soru yok.'.tr()))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
                            itemCount: qs.length,
                            itemBuilder: (ctx, i) => _buildQuestion(qs[i], i),
                          ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: _submitted ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Colors.white),
                  )
                : Text('Teslim Et'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: Colors.white,
                    )),
          ),
        ),
      ),
    );
  }

  /// Öğretmenin ödevle ilgili mesajı — ödevin başında (ve sonuç görünümünün
  /// üstünde) gösterilen bilgi kartı.
  Widget _teacherNoteCard(BuildContext context, {EdgeInsetsGeometry? margin}) {
    const blue = Color(0xFF0EA5E9);
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.campaign_rounded, size: 17, color: blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Öğretmenin mesajı'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, fontWeight: FontWeight.w800,
                      color: blue, letterSpacing: 0.3,
                    )),
                const SizedBox(height: 2),
                Text(widget.homework.teacherNote.trim(),
                    style: GoogleFonts.poppins(
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimary(context), height: 1.45,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(Map<String, dynamic> q, int index) {
    final ink = AppPalette.textPrimary(context);
    final type = (q['type'] ?? 'mc').toString();
    final qText = (q['q'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text('${index + 1}',
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: const Color(0xFF7C3AED),
                    )),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.bg(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(_typeLabel(type),
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      color: AppPalette.textSecondary(context),
                      letterSpacing: 0.5,
                    )),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(qText,
              style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w700, color: ink,
                height: 1.45,
              )),
          const SizedBox(height: 10),
          _buildAnswerInput(q, index, type),
        ],
      ),
    );
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'tf': return 'D/Y';
      case 'fill': return 'BOŞLUK DOLDURMA';
      case 'open': return 'AÇIK UÇLU';
      case 'mc':
      default: return 'ÇOKTAN SEÇMELİ';
    }
  }

  Widget _buildAnswerInput(Map<String, dynamic> q, int index, String type) {
    if (type == 'mc') {
      final choices = ((q['choices'] as List?) ?? const [])
          .map((c) => c.toString()).toList();
      return Column(
        children: choices.map((c) {
          final letter = c.isNotEmpty ? c[0].toUpperCase() : '?';
          final sel = _answers[index] == letter;
          return GestureDetector(
            onTap: () => setState(() => _answers[index] = letter),
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: sel
                    ? const Color(0xFF7C3AED).withValues(alpha: 0.10)
                    : AppPalette.bg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel
                      ? const Color(0xFF7C3AED)
                      : AppPalette.border(context),
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Text(c,
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: sel
                        ? const Color(0xFF7C3AED)
                        : AppPalette.textPrimary(context),
                  )),
            ),
          );
        }).toList(),
      );
    }
    if (type == 'tf') {
      return Row(
        children: [
          Expanded(
            child: _tfBtn(index, 'true', 'Doğru ✓'.tr(),
                const Color(0xFF10B981)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _tfBtn(index, 'false', 'Yanlış ✗'.tr(),
                const Color(0xFFEF4444)),
          ),
        ],
      );
    }
    // fill ve open için TextField
    final ctrl = _openCtrls.putIfAbsent(
      index, () => TextEditingController(text: _answers[index] ?? ''),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.bg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: ctrl,
        maxLines: type == 'open' ? 4 : 1,
        onChanged: (v) => _answers[index] = v,
        style: GoogleFonts.poppins(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: AppPalette.textPrimary(context),
        ),
        decoration: InputDecoration(
          hintText: type == 'fill'
              ? 'Doğru kelime/sayı'.tr()
              : 'Cevabını yaz...'.tr(),
          hintStyle: GoogleFonts.poppins(
            fontSize: 13, color: AppPalette.textSecondary(context),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _tfBtn(int index, String value, String label, Color color) {
    final sel = _answers[index] == value;
    return GestureDetector(
      onTap: () => setState(() => _answers[index] = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: sel ? color.withValues(alpha: 0.12) : AppPalette.bg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? color : AppPalette.border(context),
            width: sel ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w800,
              color: sel ? color : AppPalette.textPrimary(context),
            )),
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final total = _correctCount + _wrongCount;
    final pct = total > 0 ? (_correctCount * 100 / total).round() : 0;
    // Sınıf geneli paylaşım VEYA öğretmenin yalnız bu öğrenciye açtığı
    // öğrenci-bazlı paylaşım — ikisinden biri yeterli.
    final answersOpen = widget.homework.answersShared ||
        (widget.submission?.answersShared ?? false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        // Öğretmenin ödev mesajı — sonuç görünümünde de en üstte kalır.
        if (widget.homework.teacherNote.trim().isNotEmpty) ...[
          _teacherNoteCard(context, margin: EdgeInsets.zero),
          const SizedBox(height: 14),
        ],
        Center(
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: pct >= 70
                    ? const [Color(0xFF10B981), Color(0xFF06B6D4)]
                    : pct >= 40
                        ? const [Color(0xFFFBBF24), Color(0xFFFF6A00)]
                        : const [Color(0xFFEF4444), Color(0xFFEC4899)],
              ),
            ),
            alignment: Alignment.center,
            child: Text('%$pct',
                style: GoogleFonts.poppins(
                  fontSize: 32, fontWeight: FontWeight.w900,
                  color: Colors.white,
                )),
          ),
        ),
        const SizedBox(height: 18),
        Text('Ödev Teslim Edildi'.tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 18, fontWeight: FontWeight.w900,
              color: AppPalette.textPrimary(context),
            )),
        const SizedBox(height: 8),
        Text('✓ $_correctCount doğru · ✗ $_wrongCount yanlış',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13.5, color: AppPalette.textSecondary(context),
            )),
        if (_pendingOpen > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '📝 $_pendingOpen ${'açık uçlu soru öğretmenin değerlendirmesini '
                  'bekliyor. Notun güncellenecek.'.tr()}',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: const Color(0xFF7C3AED), height: 1.4,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        // ── Cevap anahtarı: öğretmen paylaştıysa soru-soru inceleme ──────
        if (answersOpen)
          _buildReviewSection(context)
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppPalette.card(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_clock_rounded,
                    size: 18, color: AppPalette.textSecondary(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cevaplar ve çözümler, öğretmenin cevap anahtarını '
                    'paylaşmasından sonra burada görünür.'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppPalette.textSecondary(context), height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 200,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Dön'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13.5, fontWeight: FontWeight.w700,
                  )),
            ),
          ),
        ),
      ],
    );
  }

  // ═══ CEVAP ANAHTARI İNCELEME (öğretmen paylaşınca) ═══════════════════════
  // Her soru: öğrencinin cevabı + doğru cevap; sağ altta "Çözümü Göster" —
  // dokununca sorunun çözümlü hali açılır (kayıtlı çözüm yoksa AI üretir,
  // o da olmazsa en azından doğru cevap gösterilir → düğme asla boş kalmaz).

  /// Soru index → açılmış çözüm metni (kayıtlı 'sol' ya da AI üretimi).
  final Map<int, String> _solutions = {};
  final Set<int> _solutionLoading = {};
  final Set<int> _solutionExpanded = {};

  static const _kGreen = Color(0xFF10B981);
  static const _kRed = Color(0xFFEF4444);
  static const _kAmber = Color(0xFFF59E0B);
  static const _kBrand = Color(0xFF7C3AED);

  /// Öğrencinin i. soruya verdiği cevap — kalıcı teslimden, yoksa bu
  /// oturumda az önce verilen cevaplardan.
  String _studentAnswerFor(int i) {
    final subAns = widget.submission?.answers;
    if (subAns != null && subAns.isNotEmpty) {
      for (final a in subAns) {
        if (a.index == i) return a.studentAnswer;
      }
      return '';
    }
    return _answers[i] ?? '';
  }

  /// i. sorunun doğruluk durumu (true/false/null=değerlendirilmedi).
  bool? _isCorrectFor(int i, Map<String, dynamic> q) {
    final subAns = widget.submission?.answers;
    if (subAns != null && subAns.isNotEmpty) {
      for (final a in subAns) {
        if (a.index == i) return a.isCorrect;
      }
    }
    final ans = _studentAnswerFor(i);
    final type = (q['type'] ?? 'mc').toString();
    if (type == 'open') return ans.trim().isEmpty ? false : null;
    if (ans.trim().isEmpty) return false;
    return _isCorrect(q, ans);
  }

  Widget _buildReviewSection(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final qs = widget.homework.questions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.key_rounded, size: 18, color: _kAmber),
            const SizedBox(width: 6),
            Text('Cevaplar ve Çözümler'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 14.5, fontWeight: FontWeight.w900, color: ink,
                )),
          ],
        ),
        const SizedBox(height: 4),
        Text('Öğretmenin cevap anahtarını paylaştı — kendi cevabını ve '
                'doğru cevapları incele.'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              color: AppPalette.textSecondary(context), height: 1.4,
            )),
        const SizedBox(height: 12),
        ...List.generate(qs.length, (i) => _reviewCard(context, i, qs[i])),
      ],
    );
  }

  Widget _reviewCard(BuildContext context, int i, Map<String, dynamic> q) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final type = (q['type'] ?? 'mc').toString();
    final qText = (q['q'] ?? '').toString();
    final isCorrect = _isCorrectFor(i, q);
    final expanded = _solutionExpanded.contains(i);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCorrect == true
              ? _kGreen.withValues(alpha: 0.35)
              : isCorrect == false
                  ? _kRed.withValues(alpha: 0.30)
                  : AppPalette.border(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: _kBrand.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: _kBrand,
                    )),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(qText,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5, fontWeight: FontWeight.w700,
                      color: ink, height: 1.4,
                    )),
              ),
              const SizedBox(width: 8),
              _reviewStatusBadge(isCorrect),
            ],
          ),
          const SizedBox(height: 10),
          ..._reviewAnswerArea(context, i, q, type, ink),
          // Sağ altta: Çözümü Göster / Gizle.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _toggleSolution(i, q),
              style: TextButton.styleFrom(
                foregroundColor: _kBrand,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.lightbulb_outline_rounded,
                  size: 17),
              label: Text(
                  expanded ? 'Çözümü Gizle'.tr() : 'Çözümü Göster'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w800,
                  )),
            ),
          ),
          if (expanded) _solutionPanel(context, i, q, ink, muted),
        ],
      ),
    );
  }

  Widget _reviewStatusBadge(bool? isCorrect) {
    final Color c;
    final IconData icon;
    final String label;
    if (isCorrect == true) {
      c = _kGreen; icon = Icons.check_rounded; label = 'Doğru'.tr();
    } else if (isCorrect == false) {
      c = _kRed; icon = Icons.close_rounded; label = 'Yanlış'.tr();
    } else {
      c = _kAmber; icon = Icons.hourglass_empty_rounded;
      label = 'Bekliyor'.tr();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 3),
          Text(label,
              style: GoogleFonts.poppins(
                fontSize: 9.5, fontWeight: FontWeight.w800, color: c,
              )),
        ],
      ),
    );
  }

  List<Widget> _reviewAnswerArea(BuildContext context, int i,
      Map<String, dynamic> q, String type, Color ink) {
    final answer = (q['answer'] ?? '').toString();
    final sa = _studentAnswerFor(i).trim();

    if (type == 'mc') {
      final choices = ((q['choices'] as List?) ?? const [])
          .map((c) => c.toString())
          .toList();
      return choices.map((c) {
        final letter = c.isNotEmpty ? c.trim()[0].toUpperCase() : '';
        final correct = letter == answer.trim().toUpperCase();
        final chosen =
            sa.isNotEmpty && (sa.toUpperCase() == letter || sa == c);
        final Color borderC = correct
            ? _kGreen
            : (chosen ? _kRed : AppPalette.border(context));
        final Color fillC = correct
            ? _kGreen.withValues(alpha: 0.10)
            : (chosen
                ? _kRed.withValues(alpha: 0.08)
                : AppPalette.bg(context));
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: fillC,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderC,
                width: (correct || chosen) ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(c,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: (correct || chosen)
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color:
                            correct ? _kGreen : (chosen ? _kRed : ink),
                      )),
                ),
                if (chosen && !correct)
                  Text('senin cevabın'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: _kRed,
                      ))
                else if (correct) ...[
                  if (chosen)
                    Text('senin cevabın'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 9, fontWeight: FontWeight.w700,
                          color: _kGreen,
                        )),
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle_rounded,
                      size: 16, color: _kGreen),
                ],
              ],
            ),
          ),
        );
      }).toList();
    }

    // tf / fill / open — kutu olarak: senin cevabın + doğru cevap.
    String fmt(String v) {
      if (type != 'tf' || v.isEmpty) return v;
      return v.toLowerCase() == 'true' ? 'Doğru'.tr() : 'Yanlış'.tr();
    }

    final isCorrect = _isCorrectFor(i, q);
    final Color mineC = isCorrect == true
        ? _kGreen
        : isCorrect == false
            ? _kRed
            : _kAmber;
    return [
      _reviewAnswerBox(context, 'Senin cevabın'.tr(),
          sa.isEmpty ? 'Boş bırakıldı'.tr() : fmt(sa), mineC, ink),
      const SizedBox(height: 6),
      _reviewAnswerBox(
          context,
          type == 'open' ? 'Örnek cevap'.tr() : 'Doğru cevap'.tr(),
          answer.isEmpty ? '—' : fmt(answer),
          _kGreen,
          ink),
    ];
  }

  Widget _reviewAnswerBox(BuildContext context, String label, String value,
      Color color, Color ink) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: color, letterSpacing: 0.3,
              )),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w700, color: ink,
              )),
        ],
      ),
    );
  }

  Future<void> _toggleSolution(int i, Map<String, dynamic> q) async {
    if (_solutionExpanded.contains(i)) {
      setState(() => _solutionExpanded.remove(i));
      return;
    }
    setState(() => _solutionExpanded.add(i));
    if (_solutions.containsKey(i) || _solutionLoading.contains(i)) return;
    // 1) Ödevle birlikte üretilmiş kayıtlı çözüm varsa direkt kullan.
    final stored = (q['sol'] ?? q['explanation'] ?? '').toString().trim();
    if (stored.isNotEmpty) {
      setState(() => _solutions[i] = stored);
      return;
    }
    // 2) Yoksa AI ile üret; o da olmazsa fallback (doğru cevap) — düğme
    //    her durumda MUTLAKA bir çözüm/cevap gösterir.
    setState(() => _solutionLoading.add(i));
    final text = await _generateSolution(q);
    if (!mounted) return;
    setState(() {
      _solutionLoading.remove(i);
      _solutions[i] = text;
    });
  }

  /// Sorunun çözümünü AI ile üretir; hata/boş durumda doğru cevabı içeren
  /// garanti bir metin döner (asla boş dönmez).
  Future<String> _generateSolution(Map<String, dynamic> q) async {
    final type = (q['type'] ?? 'mc').toString();
    final answer = (q['answer'] ?? '').toString();
    final choices = ((q['choices'] as List?) ?? const [])
        .map((c) => c.toString())
        .toList();
    final fallback = _fallbackSolution(type, answer, choices);
    try {
      final langCode = LocaleService.global?.localeCode ?? 'tr';
      final langLine = langCode == 'tr'
          ? 'Cevabı Türkçe yaz.'
          : 'Cevabı "$langCode" dil kodundaki dilde yaz.';
      final prompt = 'Soru (${widget.homework.subject} · '
          '${widget.homework.topic}, ${widget.homework.level}):\n'
          '${(q['q'] ?? '').toString()}\n'
          '${choices.isNotEmpty ? 'Şıklar:\n${choices.join('\n')}\n' : ''}'
          'Doğru cevap: $answer\n\n'
          'Bu sorunun ÇÖZÜMÜNÜ adım adım, kısa ve net yaz (en fazla 5-6 '
          'cümle). Doğru cevabın neden doğru olduğunu açıkla; işlem '
          'gerekiyorsa adımları göster. Son satıra "Sonuç: $answer" yaz. '
          'Markdown/LaTeX kullanma, düz metin yaz. $langLine';
      final text = await AiProviderService.ask(
        prompt: prompt,
        system: 'Sen sabırlı ve net anlatan deneyimli bir öğretmensin. '
            'Öğrencinin seviyesine uygun, adım adım çözüm yazarsın.',
        maxTokens: 400,
      );
      final t = text.trim();
      return t.isEmpty ? fallback : t;
    } catch (_) {
      return fallback;
    }
  }

  /// AI'sız garanti çözüm metni — en azından doğru cevap her zaman görünür.
  String _fallbackSolution(
      String type, String answer, List<String> choices) {
    String shown = answer;
    if (type == 'tf') {
      shown = answer.toLowerCase() == 'true' ? 'Doğru'.tr() : 'Yanlış'.tr();
    } else if (type == 'mc') {
      // "A" → tam şık metni
      for (final c in choices) {
        if (c.trim().toUpperCase().startsWith(answer.trim().toUpperCase())) {
          shown = c;
          break;
        }
      }
    }
    return '${'Doğru cevap'.tr()}: $shown';
  }

  Widget _solutionPanel(BuildContext context, int i, Map<String, dynamic> q,
      Color ink, Color muted) {
    final loading = _solutionLoading.contains(i);
    final text = _solutions[i];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _kBrand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBrand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_rounded, size: 15, color: _kBrand),
              const SizedBox(width: 5),
              Text('Çözüm'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: _kBrand,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          if (loading)
            Row(
              children: [
                const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('Çözüm hazırlanıyor…'.tr(),
                    style: GoogleFonts.poppins(fontSize: 12, color: muted)),
              ],
            )
          else
            Text(text ?? _fallbackSolutionFor(i, q),
                style: GoogleFonts.poppins(
                  fontSize: 12.5, color: ink, height: 1.5,
                )),
        ],
      ),
    );
  }

  String _fallbackSolutionFor(int i, Map<String, dynamic> q) {
    final type = (q['type'] ?? 'mc').toString();
    final answer = (q['answer'] ?? '').toString();
    final choices = ((q['choices'] as List?) ?? const [])
        .map((c) => c.toString())
        .toList();
    return _fallbackSolution(type, answer, choices);
  }
}

