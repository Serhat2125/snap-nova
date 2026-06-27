// ═══════════════════════════════════════════════════════════════════════════
//  TeacherHomeworkPreviewScreen — AI ödevini gönmeden önce önizle & düzenle.
//
//  Akış: AiHomeworkGeneratorWidget soruları üretir → buraya yönlendirir.
//  Öğretmen burada:
//    • Soruları görür (öğretmen AI'a %100 güvenmek istemez)
//    • Beğenmediği soruyu siler
//    • Soruyu düzenler (metin / şık / doğru cevap)
//    • "+ Manuel Soru Ekle" ile kendi sorusunu sıkıştırır
//    • "Sınıfa Gönder" → HomeworkService.assignToClass
//
//  Soru şeması (solve ekranıyla uyumlu):
//    mc   → {q, type:'mc', choices:['A) ...','B) ...'], answer:'A'}
//    tf   → {q, type:'tf', answer:'true'|'false'}
//    fill → {q, type:'fill', answer:'...'}
//    open → {q, type:'open', answer:'...'}
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/homework_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const _kBrand = Color(0xFF7C3AED);

class TeacherHomeworkPreviewScreen extends StatefulWidget {
  final String classId;
  final String title;
  final String subject;
  final String topic;
  final String level;
  final List<HomeworkQuestionType> types;
  final DateTime dueAt;
  /// Ödevin öğrencide görüneceği an. null = hemen yayınla.
  final DateTime? publishAt;
  final List<Map<String, dynamic>> questions;

  const TeacherHomeworkPreviewScreen({
    super.key,
    required this.classId,
    required this.title,
    required this.subject,
    required this.topic,
    required this.level,
    required this.types,
    required this.dueAt,
    this.publishAt,
    required this.questions,
  });

  @override
  State<TeacherHomeworkPreviewScreen> createState() =>
      _TeacherHomeworkPreviewScreenState();
}

class _TeacherHomeworkPreviewScreenState
    extends State<TeacherHomeworkPreviewScreen> {
  late final List<Map<String, dynamic>> _questions;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Düzenlenebilir derin kopya.
    _questions = widget.questions
        .map((q) => Map<String, dynamic>.from(q))
        .toList();
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('En az bir soru olmalı.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _sending = true);
    final hwId = await HomeworkService.assignToClass(
      classId: widget.classId,
      title: widget.title,
      subject: widget.subject,
      topic: widget.topic,
      level: widget.level,
      types: widget.types,
      questionCount: _questions.length,
      dueAt: widget.dueAt,
      publishAt: widget.publishAt,
      questions: _questions,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (hwId != null) {
      Navigator.of(context).pop(true); // gönderildi
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Ödev sınıfa gönderildi (${_questions.length} soru).'
            .tr()),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gönderilemedi. Tekrar dene.'.tr()),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _editQuestion(int? index) async {
    final initial = index == null ? null : _questions[index];
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuestionEditorSheet(initial: initial),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _questions.add(result);
      } else {
        _questions[index] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(context),
        elevation: 0,
        title: Text('Önizle & Düzenle'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Üst bilgi şeridi
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                        Text(widget.title,
                            style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${widget.subject} · ${widget.topic}',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5, color: muted,
                            )),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kBrand.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${_questions.length} ${'soru'.tr()}',
                        style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: _kBrand,
                        )),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                itemCount: _questions.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == _questions.length) {
                    return _addButton(context);
                  }
                  return _questionCard(context, i);
                },
              ),
            ),
            // Gönder
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 20, color: Colors.white),
                    label: Text(
                      _sending ? 'Gönderiliyor...'.tr() : 'Sınıfa Gönder'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: GoogleFonts.poppins(
                        fontSize: 16.5, fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: OutlinedButton.icon(
        onPressed: () => _editQuestion(null),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kBrand,
          side: const BorderSide(color: _kBrand),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('Manuel Soru Ekle'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 13.5, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _questionCard(BuildContext context, int i) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final q = _questions[i];
    final type = (q['type'] ?? 'mc').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
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
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.bg(context),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(_typeLabel(type),
                    style: GoogleFonts.poppins(
                      fontSize: 9.5, fontWeight: FontWeight.w800,
                      color: muted, letterSpacing: 0.5,
                    )),
              ),
              const Spacer(),
              // Kalem + "Düzenle" — öğretmen her AI sorusunu değiştirebilir.
              TextButton.icon(
                onPressed: () => _editQuestion(i),
                style: TextButton.styleFrom(
                  foregroundColor: _kBrand,
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text('Düzenle'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w800,
                    )),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: const Color(0xFFEF4444),
                tooltip: 'Sil'.tr(),
                onPressed: () => setState(() => _questions.removeAt(i)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text((q['q'] ?? '').toString(),
                style: GoogleFonts.poppins(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: ink,
                  height: 1.4,
                )),
          ),
          const SizedBox(height: 8),
          ..._answerPreview(context, q, type),
        ],
      ),
    );
  }

  List<Widget> _answerPreview(
      BuildContext c, Map<String, dynamic> q, String type) {
    final muted = AppPalette.textSecondary(c);
    final answer = (q['answer'] ?? '').toString();
    if (type == 'mc') {
      final choices = ((q['choices'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      return choices.map((ch) {
        final letter = ch.isNotEmpty ? ch[0].toUpperCase() : '?';
        final correct = letter == answer.toUpperCase();
        return Padding(
          padding: const EdgeInsets.only(bottom: 4, right: 8),
          child: Row(
            children: [
              Icon(
                correct
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 15,
                color: correct ? const Color(0xFF10B981) : muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(ch,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight:
                          correct ? FontWeight.w800 : FontWeight.w500,
                      color: correct
                          ? const Color(0xFF10B981)
                          : AppPalette.textPrimary(c),
                    )),
              ),
            ],
          ),
        );
      }).toList();
    }
    // tf / fill / open → tek satır "Doğru cevap: ..."
    String shown = answer;
    if (type == 'tf') {
      shown = answer.toLowerCase() == 'true' ? 'Doğru'.tr() : 'Yanlış'.tr();
    }
    return [
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 15,
                color: Color(0xFF10B981)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${'Cevap:'.tr()} $shown',
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: const Color(0xFF10B981),
                  )),
            ),
          ],
        ),
      ),
    ];
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'tf': return 'DOĞRU / YANLIŞ'.tr();
      case 'fill': return 'BOŞLUK DOLDURMA'.tr();
      case 'open': return 'AÇIK UÇLU'.tr();
      default: return 'ÇOKTAN SEÇMELİ'.tr();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Soru editörü — manuel ekleme + düzenleme. Map<String,dynamic> döndürür.
// ═══════════════════════════════════════════════════════════════════════════
class _QuestionEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _QuestionEditorSheet({this.initial});

  @override
  State<_QuestionEditorSheet> createState() => _QuestionEditorSheetState();
}

class _QuestionEditorSheetState extends State<_QuestionEditorSheet> {
  final _qCtrl = TextEditingController();
  // mc için 4 şık
  final List<TextEditingController> _choiceCtrls =
      List.generate(4, (_) => TextEditingController());
  // tek-metin cevap (fill/open)
  final _answerCtrl = TextEditingController();

  String _type = 'mc';
  int _correctChoice = 0; // mc doğru şık indexi
  bool _tfAnswer = true;   // tf cevabı

  @override
  void initState() {
    super.initState();
    final q = widget.initial;
    if (q != null) {
      _qCtrl.text = (q['q'] ?? '').toString();
      _type = (q['type'] ?? 'mc').toString();
      final answer = (q['answer'] ?? '').toString();
      if (_type == 'mc') {
        final choices = ((q['choices'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        for (int i = 0; i < 4 && i < choices.length; i++) {
          // "A) metin" → "metin"
          _choiceCtrls[i].text = _stripPrefix(choices[i]);
        }
        final letter = answer.toUpperCase();
        _correctChoice = letter.isNotEmpty ? (letter.codeUnitAt(0) - 65) : 0;
        if (_correctChoice < 0 || _correctChoice > 3) _correctChoice = 0;
      } else if (_type == 'tf') {
        _tfAnswer = answer.toLowerCase() == 'true';
      } else {
        _answerCtrl.text = answer;
      }
    }
  }

  String _stripPrefix(String s) {
    // "A) foo" / "A. foo" / "A- foo" → "foo"
    final m = RegExp(r'^[A-Da-d]\s*[\).\-:]\s*').firstMatch(s);
    return m == null ? s : s.substring(m.end);
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    _answerCtrl.dispose();
    for (final c in _choiceCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final qText = _qCtrl.text.trim();
    if (qText.isEmpty) {
      _toast('Soru metni boş olamaz.'.tr());
      return;
    }
    final out = <String, dynamic>{'q': qText, 'type': _type};
    if (_type == 'mc') {
      final letters = ['A', 'B', 'C', 'D'];
      final choices = <String>[];
      for (int i = 0; i < 4; i++) {
        final t = _choiceCtrls[i].text.trim();
        if (t.isEmpty) {
          _toast('Tüm şıkları doldur.'.tr());
          return;
        }
        choices.add('${letters[i]}) $t');
      }
      out['choices'] = choices;
      out['answer'] = letters[_correctChoice];
    } else if (_type == 'tf') {
      out['answer'] = _tfAnswer ? 'true' : 'false';
    } else {
      final a = _answerCtrl.text.trim();
      if (a.isEmpty) {
        _toast('Doğru cevabı gir.'.tr());
        return;
      }
      out['answer'] = a;
    }
    Navigator.of(context).pop(out);
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: AppPalette.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        widget.initial == null
                            ? 'Yeni Soru'.tr()
                            : 'Soruyu Düzenle'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w800, color: ink,
                        )),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _label(muted, 'Soru metni'.tr()),
                  _box(child: TextField(
                    controller: _qCtrl,
                    maxLines: 3,
                    style: _fieldStyle(ink),
                    decoration: _dec('Soruyu yaz...'.tr(), muted),
                  )),
                  const SizedBox(height: 14),
                  // Soru tipi seçici kaldırıldı — soru üretildiği tipte
                  // kalır; öğretmen yalnızca metni/şıkları/cevabı düzenler.
                  ..._answerEditor(context, ink, muted),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBrand,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _save,
                    child: Text('Kaydet'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: Colors.white,
                        )),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _answerEditor(BuildContext c, Color ink, Color muted) {
    if (_type == 'mc') {
      return [
        _label(muted, 'Şıklar (doğru olanı işaretle)'.tr()),
        ...List.generate(4, (i) {
          final letter = ['A', 'B', 'C', 'D'][i];
          final sel = _correctChoice == i;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _correctChoice = i),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sel
                          ? const Color(0xFF10B981)
                          : AppPalette.bg(c),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFF10B981)
                            : AppPalette.border(c),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(letter,
                        style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: sel ? Colors.white : muted,
                        )),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _box(child: TextField(
                    controller: _choiceCtrls[i],
                    style: _fieldStyle(ink),
                    decoration: _dec('$letter şıkkı'.tr(), muted),
                  )),
                ),
              ],
            ),
          );
        }),
      ];
    }
    if (_type == 'tf') {
      return [
        _label(muted, 'Doğru cevap'.tr()),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tfAnswer = true),
                child: _tfChip('Doğru ✓'.tr(), _tfAnswer,
                    const Color(0xFF10B981), c),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tfAnswer = false),
                child: _tfChip('Yanlış ✗'.tr(), !_tfAnswer,
                    const Color(0xFFEF4444), c),
              ),
            ),
          ],
        ),
      ];
    }
    // fill / open
    return [
      _label(muted,
          _type == 'fill' ? 'Doğru kelime/sayı'.tr() : 'Örnek doğru cevap'.tr()),
      _box(child: TextField(
        controller: _answerCtrl,
        maxLines: _type == 'open' ? 3 : 1,
        style: _fieldStyle(ink),
        decoration: _dec(
          _type == 'fill'
              ? 'Boşluğa gelecek cevap'.tr()
              : 'Beklenen cevabın özü'.tr(),
          muted,
        ),
      )),
      if (_type == 'open')
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Not: Açık uçlu sorular şu an anahtar kelime eşleşmesiyle '
            'değerlendiriliyor.'.tr(),
            style: GoogleFonts.poppins(fontSize: 10.5, color: muted),
          ),
        ),
    ];
  }

  Widget _tfChip(String label, bool sel, Color color, BuildContext c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: sel ? color.withValues(alpha: 0.12) : AppPalette.bg(c),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sel ? color : AppPalette.border(c),
          width: sel ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w800,
            color: sel ? color : AppPalette.textPrimary(c),
          )),
    );
  }

  Widget _label(Color muted, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: muted, letterSpacing: 0.5,
            )),
      );

  Widget _box({required Widget child}) => Builder(
        builder: (c) => Container(
          decoration: BoxDecoration(
            color: AppPalette.bg(c),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(c)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: child,
        ),
      );

  TextStyle _fieldStyle(Color ink) => GoogleFonts.poppins(
      fontSize: 13, fontWeight: FontWeight.w600, color: ink);

  InputDecoration _dec(String hint, Color muted) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(fontSize: 12.5, color: muted),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
      );
}
