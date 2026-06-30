// ═══════════════════════════════════════════════════════════════════════════
//  Teacher Dashboard widget'ları
//
//  • FilterWizardBottomSheet  — Seviye + branş + müfredat seçici
//  • AiHomeworkGeneratorWidget — Soru tipleri + adet + bitiş → AI üretir
//  • StudentPerformanceList   — Sınıf öğrencilerinin ödev durumu
//  • ReminderStatusBadge      — Auto-reminder timer aktif mi
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/education_models.dart';
import '../services/account_service.dart';
import '../services/ai_provider_service.dart';
import '../services/class_service.dart';
import '../services/curriculum_service.dart';
import '../services/gemini_service.dart';
import '../services/homework_service.dart';
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
/// Model seçicinin döndürdüğü seçim. provider null → QuAlsar (otomatik zincir).
class _AiPick {
  final AiProvider? provider;
  final String? model;
  const _AiPick(this.provider, this.model);
}

/// Model seçici kartı için görsel + yönlendirme verisi.
class _HwAiModel {
  final String name;
  final String subtitle;
  final String badge;
  final Color color;
  final Widget logo;
  final AiProvider? provider; // null → QuAlsar otomatik
  final String? model;
  const _HwAiModel(this.name, this.subtitle, this.badge, this.color, this.logo,
      this.provider, this.model);
}

class AiHomeworkGeneratorWidget extends StatefulWidget {
  final TeacherClass cls;
  /// Ek hedef sınıf id'leri (çoklu seçim). Ödev [cls] + bunların hepsine gider.
  final List<String> additionalClassIds;
  const AiHomeworkGeneratorWidget(
      {super.key, required this.cls, this.additionalClassIds = const []});

  @override
  State<AiHomeworkGeneratorWidget> createState() => _AiHomeworkGeneratorWidgetState();
}

class _AiHomeworkGeneratorWidgetState extends State<AiHomeworkGeneratorWidget> {
  final _titleCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  late String _level;
  late String _subject;
  CurriculumTopic? _selectedTopic;
  final Set<HomeworkQuestionType> _selectedTypes = {HomeworkQuestionType.multipleChoice};
  int _count = 10;
  /// Ödevin başlama (öğrencide görünme) anı. Şimdi/geçmiş → hemen yayınla.
  DateTime _startAt = DateTime.now();
  DateTime _due = DateTime.now().add(const Duration(days: 7));
  bool _generating = false;
  String? _statusMsg;

  /// Gönderimde kullanılacak yayın anı: başlama ileri tarihliyse zamanla,
  /// değilse hemen yayınla (null).
  DateTime? get _publishAtToSend =>
      _startAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))
          ? _startAt
          : null;

  @override
  void initState() {
    super.initState();
    _level = widget.cls.level.isEmpty ? 'Lise' : widget.cls.level;
    _subject = widget.cls.subject.isEmpty
        ? (AccountService.instance.teacherBranch ?? 'Genel')
        : widget.cls.subject;
    _topicCtrl.text = '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
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

  /// Başlama tarihi — yalnızca gün (saat korunur).
  Future<void> _pickStartDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    setState(() => _startAt =
        DateTime(d.year, d.month, d.day, _startAt.hour, _startAt.minute));
  }

  /// Başlama saati — yalnızca saat (gün korunur).
  Future<void> _pickStartTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _startAt.hour, minute: _startAt.minute),
    );
    if (t == null || !mounted) return;
    setState(() => _startAt =
        DateTime(_startAt.year, _startAt.month, _startAt.day, t.hour, t.minute));
  }

  /// Öğretmenin branşına göre örnek konu (konu alanı ipucu). Branş Tarih ise
  /// tarihten, Matematik ise matematikten bir örnek gösterir.
  String _topicExampleForBranch() {
    final b = _subject.toLowerCase();
    bool has(String k) => b.contains(k);
    if (has('matematik')) return 'Üslü Sayılar';
    if (has('fizik')) return 'Newton Hareket Yasaları';
    if (has('kimya')) return 'Periyodik Sistem';
    if (has('biyoloji')) return 'Hücre ve Organeller';
    if (has('fen')) return 'Maddenin Halleri';
    if (has('tarih')) return 'Kurtuluş Savaşı';
    if (has('coğrafya') || has('cografya')) return 'İklim Tipleri';
    if (has('edebiyat')) return 'Edebi Akımlar';
    if (has('türkçe') || has('turkce')) return 'Cümlede Anlam';
    if (has('sosyal')) return 'Coğrafi Bölgeler';
    if (has('ingiliz')) return 'Present Perfect Tense';
    if (has('alman')) return 'Perfekt (Geçmiş Zaman)';
    if (has('fransız') || has('fransiz')) return 'Passé Composé';
    if (has('ispanyol')) return 'Pretérito Indefinido';
    if (has('arap')) return 'Fiil Çekimleri';
    if (has('rus')) return 'Hâl Ekleri (Падежи)';
    if (has('felsefe') || has('mantık') || has('psikoloji') || has('sosyoloji')) {
      return 'Bilgi Felsefesi';
    }
    if (has('din')) return 'İbadetler';
    if (has('bilişim') || has('yazılım') || has('kodlama') || has('robotik')) {
      return 'Döngüler ve Değişkenler';
    }
    if (has('tasarım')) return 'Tasarım Süreci';
    if (has('görsel') || has('resim')) return 'Renk Bilgisi';
    if (has('müzik')) return 'Nota ve Ritim';
    if (has('beden')) return 'Voleybol Kuralları';
    if (has('rehber') || has('pdr')) return 'Verimli Ders Çalışma';
    if (has('özel eğitim')) return 'Temel Yaşam Becerileri';
    if (has('okul öncesi')) return 'Renkleri Tanıma';
    if (has('sınıf öğretmen')) return 'Toplama ve Çıkarma';
    return 'Konu adı';
  }

  /// Girilen metin anlamlı bir ders konusu/başlığı mı? Kaba sezgisel kontrol:
  /// klavye ezmesi / sembol yığını / sesli harfsiz dizileri yakalar.
  bool _looksMeaningless(String raw) {
    final s = raw.trim();
    if (s.length < 2) return true;
    final compact = s.replaceAll(RegExp(r'\s+'), '');
    // Harf oranı düşükse (çoğunlukla sembol/rakam) → anlamsız.
    final letters =
        RegExp(r'[a-zçğıöşüâîû]', caseSensitive: false).allMatches(compact).length;
    if (letters < compact.length * 0.5) return true;
    // Hiç sesli harf yoksa (asdf, bcdfg, qwrt) → klavye ezmesi.
    if (!RegExp(r'[aeıioöuüâîû]', caseSensitive: false).hasMatch(compact)) {
      return true;
    }
    // Aynı karakterin 4+ tekrarı (aaaa, !!!!).
    if (RegExp(r'(.)\1{3,}').hasMatch(compact)) return true;
    // Bilinen klavye dizileri.
    const mash = ['qwerty', 'qwertz', 'asdfgh', 'zxcvbn', 'qazwsx'];
    final low = compact.toLowerCase();
    for (final m in mash) {
      if (low.contains(m)) return true;
    }
    return false;
  }

  // "AI Üret & Önizle"ye basınca: doğrudan üretmek yerine arka planı flulayan
  // küçük bir panel açar — öğrenci foto-çözüm ekranındaki 6 model kartının
  // aynısı. Seçilen model zincirin başına geçer; geç/başarısızsa otomatik
  // olarak sıradaki modele düşülür.
  Future<void> _openModelPicker() async {
    // Önce zorunlu alanları doğrula — boşsa paneli açma, uyarı göster.
    if (_topicCtrl.text.trim().isEmpty || _titleCtrl.text.trim().isEmpty) {
      setState(() => _statusMsg = 'Başlık ve konu zorunludur.'.tr());
      return;
    }
    // Anlamsız / eğitim-dışı giriş → uyar, üretme.
    if (_looksMeaningless(_topicCtrl.text) ||
        _looksMeaningless(_titleCtrl.text)) {
      setState(() => _statusMsg =
          'Lütfen geçerli bir ders konusu ve başlığı yaz. Bu uygulama yalnızca eğitim amaçlı hizmet verir.'
              .tr());
      return;
    }
    if (_selectedTypes.isEmpty) {
      setState(() => _statusMsg = 'En az bir soru tipi seç.'.tr());
      return;
    }

    final pick = await showGeneralDialog<_AiPick>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ai-model',
      barrierColor: Colors.black.withValues(alpha: 0.20),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 9 * t, sigmaY: 9 * t),
          child: Opacity(
            opacity: anim.value,
            child: Transform.scale(
              scale: 0.94 + 0.06 * t,
              child: Center(child: _modelPickerPanel(ctx)),
            ),
          ),
        );
      },
    );
    if (pick == null || !mounted) return;
    await _generateAndPreview(
        firstProvider: pick.provider, firstModel: pick.model);
  }

  /// "Hangi yapay zekâ ile üretelim?" panel içeriği (ortada, kompakt).
  Widget _modelPickerPanel(BuildContext ctx) {
    // Öğrenci foto-çözüm ekranıyla aynı 6 model + aynı tasarım dili.
    // provider null → QuAlsar (otomatik varsayılan zincir).
    final models = <_HwAiModel>[
      _HwAiModel(
        'QuAlsar', 'Hızlı ve genel'.tr(), 'Önerilen'.tr(),
        const Color(0xFF06B6D4),
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFF00E5FF), Color(0xFF6B21F2)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ).createShader(b),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 22),
        ),
        null, null,
      ),
      _HwAiModel('ChatGPT', 'Detaylı çözüm'.tr(), 'Aktif'.tr(),
          const Color(0xFF10A37F),
          const Icon(Icons.forum_rounded, color: Color(0xFF10A37F), size: 22),
          AiProvider.openai, 'gpt-4o-mini'),
      _HwAiModel('Gemini', 'Hızlı analiz'.tr(), 'Aktif'.tr(),
          const Color(0xFF4796E3),
          const Icon(Icons.bubble_chart_rounded,
              color: Color(0xFF4796E3), size: 22),
          AiProvider.gemini, 'gemini-2.5-flash'),
      _HwAiModel('Grok', 'Yaratıcı çözüm'.tr(), 'Aktif'.tr(),
          const Color(0xFF1D1D1D),
          const Icon(Icons.bolt_rounded, color: Color(0xFF1D1D1D), size: 22),
          AiProvider.grok, 'grok-3-mini'),
      _HwAiModel('Deepseek', 'Derin analiz'.tr(), 'Aktif'.tr(),
          const Color(0xFF4B8BF5),
          const Icon(Icons.psychology_rounded,
              color: Color(0xFF4B8BF5), size: 22),
          AiProvider.deepseek, 'deepseek-chat'),
      _HwAiModel('Claude', 'Mantık yürütme'.tr(), 'Aktif'.tr(),
          const Color(0xFFD97706),
          const Icon(Icons.lightbulb_rounded,
              color: Color(0xFFD97706), size: 22),
          AiProvider.claude, 'claude-sonnet-4-6'),
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 26),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: AppPalette.card(ctx),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 30, offset: const Offset(0, 12)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hangi yapay zekâ ile üretelim?'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w900,
                color: AppPalette.textPrimary(ctx),
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              // Daha uzun kart → 2 satırlık alt yazı + rozet dikeyde taşmaz.
              childAspectRatio: 0.78,
              children: [
                for (final m in models) _modelCard(ctx, m),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Tek AI model kartı (öğrenci ekranındaki kartla aynı düzen).
  Widget _modelCard(BuildContext ctx, _HwAiModel m) {
    return GestureDetector(
      onTap: () => Navigator.of(ctx).pop(_AiPick(m.provider, m.model)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppPalette.bg(ctx),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: m.color.withValues(alpha: 0.30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 22, height: 22, child: m.logo),
            const SizedBox(height: 4),
            Text(m.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w800, height: 1.05,
                  color: AppPalette.textPrimary(ctx),
                )),
            const SizedBox(height: 2),
            Text(m.subtitle,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 7.5, fontWeight: FontWeight.w500, height: 1.1,
                  color: AppPalette.textSecondary(ctx),
                )),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: m.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: m.color.withValues(alpha: 0.40),
                    width: 0.6),
              ),
              child: Text(m.badge,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 7, fontWeight: FontWeight.w700, height: 1.0,
                    color: AppPalette.textPrimary(ctx),
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAndPreview(
      {AiProvider? firstProvider, String? firstModel}) async {
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
        firstProvider: firstProvider,
        firstModel: firstModel,
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
            additionalClassIds: widget.additionalClassIds,
            title: title,
            subject: _subject,
            topic: topic,
            level: _level,
            types: _selectedTypes.toList(),
            dueAt: _due,
            publishAt: _publishAtToSend,
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

  /// Tek soru-tipi sekmesi (Expanded içinde kullanılır → eşit genişlik).
  Widget _typeChip(BuildContext context, HomeworkQuestionType t) {
    final ink = AppPalette.textPrimary(context);
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: sel
              ? const Color(0xFF7C3AED).withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? const Color(0xFF7C3AED) : AppPalette.border(context),
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(t.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(t.tr.tr(),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.05,
                    color: sel ? const Color(0xFF7C3AED) : ink,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  /// Soru sayısı sayacının − / + düğmesi.
  Widget _countBtn(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 20,
            color: onTap != null
                ? const Color(0xFF7C3AED)
                : const Color(0xFFCBD5E1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppPalette.textPrimary(context);
    final muted = AppPalette.textSecondary(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        // Panel arka planı soluk beyaz; içindeki alanlar/sekmeler beyaz.
        color: const Color(0xFFF3F4F6),
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
              // Sınıf adı en sağda (uzun adda taşmasın → Flexible + ellipsis).
              Flexible(
                child: Container(
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
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Önce konu, altında başlık
          _input(context, _topicCtrl,
              '${'Konu'.tr()} (${'örn'.tr()}: ${_topicExampleForBranch().tr()})'),
          const SizedBox(height: 8),
          _input(context, _titleCtrl, 'Ödev başlığı'.tr()),
          const SizedBox(height: 12),
          // NOT: Seviye/branş seçici kaldırıldı — öğretmen kayıt olurken branşı
          // belirliyor; seviye/branş sınıftan otomatik geliyor.
          // Soru tipi & soru sayısı (ikisi de aşağıdaki çerçevede)
          Text('${'Soru tipi'.tr()} & ${'Soru sayısı'.tr()}',
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.border(context)),
            ),
            // 4 tip 2×2 eşit boyutlu; altında soru sayısı sayacı.
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _typeChip(
                            context, HomeworkQuestionType.values[0])),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _typeChip(
                            context, HomeworkQuestionType.values[1])),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _typeChip(
                            context, HomeworkQuestionType.values[2])),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _typeChip(
                            context, HomeworkQuestionType.values[3])),
                  ],
                ),
                const SizedBox(height: 12),
                // Soru sayısı — solda etiket, sağda  −  N  +  sayacı.
                Row(
                  children: [
                    Text('Soru sayısı'.tr(),
                        style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: muted,
                        )),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppPalette.border(context)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _countBtn(Icons.remove_rounded,
                              _count > 3
                                  ? () => setState(() => _count--)
                                  : null),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            child: Text('$_count',
                                style: GoogleFonts.poppins(
                                  fontSize: 16, fontWeight: FontWeight.w900,
                                  color: ink,
                                )),
                          ),
                          _countBtn(Icons.add_rounded,
                              _count < 30
                                  ? () => setState(() => _count++)
                                  : null),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── Solda başlama, sağda bitiş tarihi — her biri ayrı sekme;
          //    içinde tarih + (azıcık boşluk) saat. ──────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _dateTimeTab(
                  context,
                  label: 'Başlama tarihi'.tr(),
                  dt: _startAt,
                  onPickDate: _pickStartDate,
                  onPickTime: _pickStartTime,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateTimeTab(
                  context,
                  label: 'Bitiş tarihi'.tr(),
                  dt: _due,
                  onPickDate: _pickDueDate,
                  onPickTime: _pickDueTime,
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
              onPressed: _generating ? null : _openModelPicker,
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
        color: Colors.white,
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
          // Soluk ipucu — kullanıcı alanın ne işe yaradığını anlasın.
          hintStyle: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w500,
            color: AppPalette.textSecondary(c).withValues(alpha: 0.6),
          ),
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

  /// Başlama/Bitiş sekmesi — başlıklı dış çerçeve; içinde tarih + saat kutusu.
  Widget _dateTimeTab(BuildContext c,
      {required String label,
      required DateTime dt,
      required VoidCallback onPickDate,
      required VoidCallback onPickTime}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border(c)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w800,
                  color: AppPalette.textSecondary(c))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _miniBox(
                    c, '${dt.day}.${dt.month}.${dt.year % 100}', onPickDate),
              ),
              const SizedBox(width: 6), // tarih ↔ saat azıcık mesafe
              _miniBox(
                  c,
                  '${dt.hour.toString().padLeft(2, '0')}:'
                      '${dt.minute.toString().padLeft(2, '0')}',
                  onPickTime),
            ],
          ),
        ],
      ),
    );
  }

  /// Sekme içindeki tek tarih/saat hücresi — ikonsuz, ortalı rakam.
  Widget _miniBox(BuildContext c, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppPalette.border(c)),
        ),
        child: Text(value,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 12.5, fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(c))),
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
