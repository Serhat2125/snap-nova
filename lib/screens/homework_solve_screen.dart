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
import '../services/app_settings_service.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

class HomeworkSolveScreen extends StatefulWidget {
  final String classId;
  final HomeworkModel homework;
  const HomeworkSolveScreen({
    super.key, required this.classId, required this.homework,
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
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
          const SizedBox(height: 18),
          Text('Ödev Teslim Edildi'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w900,
                color: AppPalette.textPrimary(context),
              )),
          const SizedBox(height: 8),
          Text('✓ $_correctCount doğru · ✗ $_wrongCount yanlış',
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
          const SizedBox(height: 28),
          SizedBox(
            width: 200,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Dön'.tr(),
                  style: GoogleFonts.poppins(
                    fontSize: 13.5, fontWeight: FontWeight.w700,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

