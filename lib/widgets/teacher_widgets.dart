// ═══════════════════════════════════════════════════════════════════════════
//  Teacher Dashboard widget'ları
//
//  • FilterWizardBottomSheet  — Seviye + branş + müfredat seçici
//  • AiHomeworkGeneratorWidget — Soru tipleri + adet + bitiş → AI üretir
//  • StudentPerformanceList   — Sınıf öğrencilerinin ödev durumu
//  • ReminderStatusBadge      — Auto-reminder timer aktif mi
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/account_service.dart';
import '../services/class_service.dart';
import '../services/curriculum_service.dart';
import '../services/gemini_service.dart';
import '../services/homework_service.dart';
import '../services/locale_service.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';
import 'qualsar_logo_mark.dart';
import '../screens/teacher_homework_preview_screen.dart';
import '../screens/teacher_grade_submission_screen.dart';

// ─────────────────────────────────────────────────────────────────────────
// 1) FILTER WIZARD BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────
class FilterWizardBottomSheet extends StatefulWidget {
  final String initialLevel;
  final String initialSubject;
  final String initialCurriculum;
  final Function(String level, String subject, String curriculum, CurriculumTopic? topic) onSelected;
  const FilterWizardBottomSheet({
    super.key,
    this.initialLevel = 'Lise',
    this.initialSubject = 'Genel',
    this.initialCurriculum = 'tr-MEB',
    required this.onSelected,
  });

  @override
  State<FilterWizardBottomSheet> createState() => _FilterWizardBottomSheetState();
}

class _FilterWizardBottomSheetState extends State<FilterWizardBottomSheet> {
  late String _level;
  late String _subject;
  late String _curriculum;
  CurriculumTopic? _topic;

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel;
    _subject = widget.initialSubject;
    _curriculum = widget.initialCurriculum;
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    final topics = CurriculumService.topicsFor(
      curriculumKey: _curriculum,
      level: _level,
      subject: _subject,
    );
    final levels = CurriculumService.levelsFor(_curriculum);
    return DraggableScrollableSheet(
      initialChildSize: 0.78, minChildSize: 0.5, maxChildSize: 0.95,
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Ödev Filtresi'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: ink,
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
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label(context, 'Müfredat'.tr()),
                    _dropdown(
                      context,
                      value: _curriculum,
                      items: CurriculumService.standards
                          .map((s) => (s.key, s.label)).toList(),
                      onChanged: (v) => setState(() {
                        _curriculum = v;
                        _topic = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    _label(context, 'Eğitim Seviyesi'.tr()),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: levels.map((l) {
                        final sel = l == _level;
                        return _chipBtn(context, l, sel, () => setState(() {
                          _level = l;
                          _topic = null;
                        }));
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _label(context, 'Branş'.tr()),
                    // Branş öğretmenin sabit branşıdır — sınıf bazında değişmez.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF7C3AED)
                                .withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.school_rounded,
                              size: 18, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_subject,
                                style: GoogleFonts.poppins(
                                  fontSize: 13.5, fontWeight: FontWeight.w800,
                                  color: ink,
                                )),
                          ),
                          Icon(Icons.lock_outline_rounded,
                              size: 15, color: muted),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _label(context, 'Kazanım / Konu (opsiyonel)'.tr()),
                    if (topics.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Bu seçim için müfredat kazanımı eklenmemiş — AI yine de seçilen konuya göre üretebilir.'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 11.5, color: muted, height: 1.4,
                          ),
                        ),
                      )
                    else
                      Column(
                        children: topics.map((t) {
                          final sel = _topic?.id == t.id;
                          return GestureDetector(
                            onTap: () => setState(() => _topic = t),
                            child: Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: sel
                                    ? const Color(0xFF7C3AED)
                                        .withValues(alpha: 0.10)
                                    : AppPalette.bg(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sel
                                      ? const Color(0xFF7C3AED)
                                      : AppPalette.border(context),
                                  width: sel ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text('${t.grade} · ${t.topic}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                              color: ink,
                                            )),
                                      ),
                                      if (sel)
                                        const Icon(Icons.check_circle_rounded,
                                            color: Color(0xFF7C3AED), size: 18),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ...t.outcomes.take(2).map((o) => Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text('• $o',
                                            style: GoogleFonts.poppins(
                                              fontSize: 11, color: muted,
                                              height: 1.4,
                                            )),
                                      )),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          widget.onSelected(_level, _subject, _curriculum, _topic);
                          Navigator.of(context).pop();
                        },
                        child: Text('Bu Filtreyle Devam Et'.tr(),
                            style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w800,
                              color: Colors.white,
                            )),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: AppPalette.textSecondary(c),
              letterSpacing: 0.7,
            )),
      );

  Widget _chipBtn(BuildContext c, String label, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel
              ? const Color(0xFF7C3AED).withValues(alpha: 0.10)
              : AppPalette.bg(c),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: sel
                ? const Color(0xFF7C3AED)
                : AppPalette.border(c),
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
              fontSize: 12.5, fontWeight: FontWeight.w700,
              color: sel
                  ? const Color(0xFF7C3AED)
                  : AppPalette.textPrimary(c),
            )),
      ),
    );
  }

  Widget _dropdown(BuildContext c, {
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppPalette.bg(c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(c)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded),
          items: items.map((p) => DropdownMenuItem(
            value: p.$1,
            child: Text(p.$2,
                style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary(c),
                )),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 2) AI HOMEWORK GENERATOR
// ─────────────────────────────────────────────────────────────────────────
class AiHomeworkGeneratorWidget extends StatefulWidget {
  final TeacherClass cls;
  const AiHomeworkGeneratorWidget({super.key, required this.cls});

  @override
  State<AiHomeworkGeneratorWidget> createState() => _AiHomeworkGeneratorWidgetState();
}

class _AiHomeworkGeneratorWidgetState extends State<AiHomeworkGeneratorWidget> {
  final _titleCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  late String _level;
  late String _subject;
  // Müfredat varsayılanı kullanıcının diline/ülkesine göre (öğrenci tarafıyla
  // aynı mantık) — initState'te locale'den belirlenir.
  String _curriculum = 'tr-MEB';
  CurriculumTopic? _selectedTopic;
  final Set<HomeworkQuestionType> _selectedTypes = {HomeworkQuestionType.multipleChoice};
  int _count = 10;
  DateTime _due = DateTime.now().add(const Duration(days: 7));
  /// Ödevin öğrencide görüneceği an. null = hemen yayınla.
  DateTime? _publishAt;
  bool _generating = false;
  String? _statusMsg;

  @override
  void initState() {
    super.initState();
    _level = widget.cls.level.isEmpty ? 'Lise' : widget.cls.level;
    _subject = widget.cls.subject.isEmpty
        ? (AccountService.instance.teacherBranch ?? 'Genel')
        : widget.cls.subject;
    // Müfredatı kullanıcının diline/ülkesine göre seç (öğrenci tarafı gibi).
    _curriculum = CurriculumService.defaultCurriculumKey(
        LocaleService.global?.localeCode ?? 'tr');
    _topicCtrl.text = '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilterWizard() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterWizardBottomSheet(
        initialLevel: _level,
        initialSubject: _subject,
        initialCurriculum: _curriculum,
        onSelected: (lvl, sub, cur, topic) {
          setState(() {
            _level = lvl;
            _subject = sub;
            _curriculum = cur;
            _selectedTopic = topic;
            if (topic != null) _topicCtrl.text = topic.topic;
          });
        },
      ),
    );
  }

  /// Bitiş tarihi — yalnızca gün (saat korunur).
  Future<void> _pickDueDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    setState(() =>
        _due = DateTime(d.year, d.month, d.day, _due.hour, _due.minute));
  }

  /// Bitiş saati — yalnızca saat (gün korunur).
  Future<void> _pickDueTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _due.hour, minute: _due.minute),
    );
    if (t == null || !mounted) return;
    setState(() =>
        _due = DateTime(_due.year, _due.month, _due.day, t.hour, t.minute));
  }

  /// "Zamanla" — gün + saat seç. Seçilen ana kadar ödev öğrencide görünmez.
  Future<void> _pickPublishDate() async {
    final base = _publishAt ?? DateTime.now().add(const Duration(hours: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (t == null || !mounted) return;
    setState(() {
      _publishAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _generateAndPreview() async {
    final topic = _topicCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    if (topic.isEmpty || title.isEmpty) {
      setState(() => _statusMsg = 'Başlık ve konu zorunludur.'.tr());
      return;
    }
    if (_selectedTypes.isEmpty) {
      setState(() => _statusMsg = 'En az bir soru tipi seç.'.tr());
      return;
    }
    setState(() {
      _generating = true;
      _statusMsg = 'AI ödev üretiyor...'.tr();
    });
    try {
      final outcome = _selectedTopic?.outcomes.join(' / ') ?? '';
      final questions = await GeminiService.generateHomeworkBatch(
        subject: _subject,
        topic: topic,
        level: _level,
        typeKeys: _selectedTypes.map((t) => t.key).toList(),
        count: _count,
        outcome: outcome.isEmpty ? null : outcome,
      );
      if (!mounted) return;
      setState(() {
        _generating = false;
        _statusMsg = null;
      });
      if (questions.isEmpty) {
        setState(() => _statusMsg = 'AI soru üretemedi. Tekrar dene.'.tr());
        return;
      }
      // Üretilen soruları doğrudan göndermek yerine önizleme/düzenleme
      // ekranına aktar — öğretmen soruları görüp düzenleyip gönderir.
      final sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => TeacherHomeworkPreviewScreen(
            classId: widget.cls.id,
            title: title,
            subject: _subject,
            topic: topic,
            level: _level,
            types: _selectedTypes.toList(),
            dueAt: _due,
            publishAt: _publishAt,
            questions: questions,
          ),
        ),
      );
      if (!mounted) return;
      if (sent == true) {
        setState(() {
          _statusMsg = '✅ Ödev sınıfa gönderildi.'.tr();
          _titleCtrl.clear();
          _topicCtrl.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _statusMsg = 'AI üretiminde hata: ${e.toString()}'.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10, offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Orijinal Qualsar logosu
              const SizedBox(
                width: 36, height: 36,
                child: QuAlsarLogoMark(size: 36, showCenterWord: false),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('AI Ödev Üreticisi'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w800,
                      color: ink,
                    )),
              ),
              const SizedBox(width: 8),
              // Sınıf adı en sağda
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(widget.cls.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: const Color(0xFF7C3AED),
                    )),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Önce konu, altında başlık
          _input(context, _topicCtrl, 'Konu (örn: Üslü Sayılar)'.tr()),
          const SizedBox(height: 8),
          _input(context, _titleCtrl, 'Ödev başlığı'.tr()),
          const SizedBox(height: 8),
          // Müfredat / seviye / branş seçim butonu
          GestureDetector(
            onTap: _openFilterWizard,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppPalette.bg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_level · $_subject',
                            style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: ink,
                            )),
                        if (_selectedTopic != null)
                          Text(_selectedTopic!.topic,
                              style: GoogleFonts.poppins(
                                fontSize: 11, color: muted,
                              )),
                      ],
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Soru tipleri
          Text('Soru tipleri'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: muted, letterSpacing: 0.6,
              )),
          const SizedBox(height: 6),
          // 4 soru tipi tek çerçeve içinde; çerçeve soluk beyaz,
          // her tipin alanı hafif beyaz.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppPalette.cardMuted(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.border(context)),
            ),
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: HomeworkQuestionType.values.map((t) {
                final sel = _selectedTypes.contains(t);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (sel) {
                      if (_selectedTypes.length > 1) _selectedTypes.remove(t);
                    } else {
                      _selectedTypes.add(t);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? const Color(0xFF7C3AED).withValues(alpha: 0.12)
                          : AppPalette.card(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFF7C3AED)
                            : AppPalette.border(context),
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 5),
                        Text(t.tr,
                            style: GoogleFonts.poppins(
                              fontSize: 11.5, fontWeight: FontWeight.w700,
                              color: sel
                                  ? const Color(0xFF7C3AED)
                                  : ink,
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Soru sayısı
          Text('Soru sayısı'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: muted, letterSpacing: 0.6,
              )),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: const Color(0xFF7C3AED),
                onPressed: _count > 3 ? () => setState(() => _count--) : null,
              ),
              Text('$_count',
                  style: GoogleFonts.poppins(
                    fontSize: 17, fontWeight: FontWeight.w900, color: ink,
                  )),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                color: const Color(0xFF7C3AED),
                onPressed: _count < 30 ? () => setState(() => _count++) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Bitiş tarihi: tarih ve saat ayrı kutular, aralarında mesafe,
          //    farklı tonda gri arka planlar ────────────────────────────
          Text('Bitiş tarihi'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: muted, letterSpacing: 0.6,
              )),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _dtBox(
                  context,
                  AppPalette.cardMuted(context),
                  Icons.calendar_today_rounded,
                  'Tarih'.tr(),
                  '${_due.day}.${_due.month}.${_due.year}',
                  _pickDueDate,
                ),
              ),
              const SizedBox(width: 12), // tarih ↔ saat mesafesi
              Expanded(
                flex: 2,
                child: _dtBox(
                  context,
                  AppPalette.border(context),
                  Icons.access_time_rounded,
                  'Saat'.tr(),
                  '${_due.hour.toString().padLeft(2, '0')}:'
                      '${_due.minute.toString().padLeft(2, '0')}',
                  _pickDueTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── Yayın zamanı: solda Hemen, sağda Zamanla ─────────────────
          Text('Bu ödev ne zaman yayınlansın?'.tr(),
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: muted, letterSpacing: 0.6,
              )),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _publishOption(
                  context,
                  icon: Icons.bolt_rounded,
                  label: 'Hemen yayınla'.tr(),
                  sub: null,
                  selected: _publishAt == null,
                  onTap: () => setState(() => _publishAt = null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _publishOption(
                  context,
                  icon: Icons.event_rounded,
                  label: 'Zamanla'.tr(),
                  sub: _publishAt == null
                      ? null
                      : '${_publishAt!.day}.${_publishAt!.month} '
                          '${_publishAt!.hour.toString().padLeft(2, '0')}:'
                          '${_publishAt!.minute.toString().padLeft(2, '0')}',
                  selected: _publishAt != null,
                  onTap: _pickPublishDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_statusMsg != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppPalette.bg(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppPalette.border(context)),
              ),
              child: Text(_statusMsg!,
                  style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary(context),
                  )),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _generating ? null : _generateAndPreview,
              child: _generating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                    )
                  : Text('AI Üret & Önizle'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: Colors.white,
                      )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(BuildContext c, TextEditingController ctrl, String hint,
      [IconData? icon]) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.bg(c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(c)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: ctrl,
        style: GoogleFonts.poppins(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: AppPalette.textPrimary(c),
        ),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: icon == null
              ? null
              : Icon(icon, size: 18, color: AppPalette.textSecondary(c)),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  /// Bitiş tarihi/saat kutusu — verilen gri arka planla.
  Widget _dtBox(BuildContext c, Color bg, IconData icon, String label,
      String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border(c)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF7C3AED)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 9.5, fontWeight: FontWeight.w600,
                          color: AppPalette.textSecondary(c))),
                  Text(value,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w800,
                          color: AppPalette.textPrimary(c))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Yayın seçeneği kutusu (Hemen / Zamanla).
  Widget _publishOption(BuildContext c,
      {required IconData icon,
      required String label,
      String? sub,
      required bool selected,
      required VoidCallback onTap}) {
    const brand = Color(0xFF7C3AED);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? brand.withValues(alpha: 0.12) : AppPalette.bg(c),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? brand : AppPalette.border(c),
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18,
                color: selected ? brand : AppPalette.textSecondary(c)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 12.5, fontWeight: FontWeight.w800,
                          color: selected
                              ? brand
                              : AppPalette.textPrimary(c))),
                  if (sub != null)
                    Text(sub,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 10, fontWeight: FontWeight.w600,
                            color: AppPalette.textSecondary(c))),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, size: 16, color: brand),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 3) STUDENT PERFORMANCE LIST — Sınıftaki ödev durumu
// ─────────────────────────────────────────────────────────────────────────
class StudentPerformanceList extends StatelessWidget {
  final String classId;
  final HomeworkModel homework;
  const StudentPerformanceList({
    super.key, required this.classId, required this.homework,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppPalette.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('📋', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(homework.title,
                        style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      'Bitiş: ${homework.dueAt.day}.${homework.dueAt.month}.${homework.dueAt.year} '
                      '${homework.dueAt.hour.toString().padLeft(2, '0')}:'
                      '${homework.dueAt.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.poppins(
                        fontSize: 11, color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<HomeworkSubmissionModel>>(
            stream: HomeworkService.submissionsStream(classId, homework.id),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final subs = snap.data!;
              if (subs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Henüz teslim eden olmadı.'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 12, color: muted,
                      )),
                );
              }
              final submitted = subs.where((s) => s.isSubmitted).length;
              final pending = subs.where((s) => s.isPending).length;
              return Column(
                children: [
                  // Özet bar
                  Row(
                    children: [
                      _summaryBox(context, '✅', '$submitted',
                          'Teslim'.tr(), const Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      _summaryBox(context, '⏳', '$pending',
                          'Bekliyor'.tr(), const Color(0xFFFBBF24)),
                      const SizedBox(width: 8),
                      _summaryBox(context, '👥', '${subs.length}',
                          'Toplam'.tr(), const Color(0xFF7C3AED)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...subs.map((s) => _row(context, s)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(BuildContext c, String emoji, String val, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            Text(val,
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w900,
                  color: color,
                )),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondary(c),
                )),
          ],
        ),
      ),
    );
  }

  /// Süreyi kısa biçimde: "45sn", "12dk", "1s 5dk".
  String _fmtDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}sn';
    if (d.inHours < 1) return '${d.inMinutes}dk';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}s' : '${h}s ${m}dk';
  }

  Widget _row(BuildContext c, HomeworkSubmissionModel s) {
    Color statusColor;
    String statusLabel;
    switch (s.status) {
      case 'submitted': statusColor = const Color(0xFF10B981); statusLabel = 'Teslim'.tr(); break;
      case 'late':      statusColor = const Color(0xFFFB923C); statusLabel = 'Geç'.tr();    break;
      case 'in_progress': statusColor = const Color(0xFF06B6D4); statusLabel = 'Çözüyor'.tr(); break;
      default:          statusColor = const Color(0xFF94A3B8); statusLabel = 'Bekliyor'.tr(); break;
    }
    final needsReview = s.needsReview;
    final row = Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: needsReview
            ? const Color(0xFF7C3AED).withValues(alpha: 0.06)
            : AppPalette.bg(c),
        borderRadius: BorderRadius.circular(10),
        border: needsReview
            ? Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.30))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.studentDisplayName.isEmpty ? '@${s.studentUsername}'
                  : s.studentDisplayName,
              style: GoogleFonts.poppins(
                fontSize: 12.5, fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary(c),
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ),
          // Çözüm süresi — "30 sn'de %10" gibi sallama davranışını yakalar.
          if (s.solveDuration != null) ...[
            Icon(Icons.timer_outlined, size: 13,
                color: AppPalette.textSecondary(c)),
            const SizedBox(width: 2),
            Text(_fmtDuration(s.solveDuration!),
                style: GoogleFonts.poppins(
                  fontSize: 10.5, fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary(c),
                )),
            const SizedBox(width: 8),
          ],
          if (needsReview) ...[
            // Açık uçlu cevap öğretmen puanlaması bekliyor → tıkla, değerlendir.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('📝 ${'Değerlendir'.tr()}',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5, fontWeight: FontWeight.w800,
                    color: const Color(0xFF7C3AED),
                  )),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 16,
                color: AppPalette.textSecondary(c)),
          ] else ...[
            if (s.scorePercent != null) ...[
              Text('%${s.scorePercent!.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: AppPalette.textSecondary(c),
                  )),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(statusLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5, fontWeight: FontWeight.w800,
                    color: statusColor,
                  )),
            ),
          ],
        ],
      ),
    );
    if (!needsReview) return row;
    return GestureDetector(
      onTap: () => Navigator.of(c).push(MaterialPageRoute(
        builder: (_) => TeacherGradeSubmissionScreen(
          classId: classId,
          homeworkId: homework.id,
          homeworkTitle: homework.title,
          submission: s,
        ),
      )),
      child: row,
    );
  }
}
