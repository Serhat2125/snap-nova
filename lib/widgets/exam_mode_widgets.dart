// ═══════════════════════════════════════════════════════════════════════════════
//  EXAM MODE WIDGETS — "Sınav modu açmak ister misin?" kartı + Sınav → Ders →
//  Konu seçim akışı. lib/services/exam_catalog.dart'taki kExamCatalog verisini
//  kullanır (LGS/YKS/KPSS/SAT/Abitur/Gaokao vb.).
//
//  Bilgi Ligi'nde (bilgi_ligi_screen.dart) doğmuş; Bilgi Yarışı/Arena sayfası
//  (qualsar_arena_screen.dart) da AYNI görünüm+davranışla, AYNI veriden
//  (exam_catalog.dart) beslenmek üzere bu ortak dosyaya taşındı — iki sayfa da
//  bu widget'ları kullanır, kod tekilleşir, davranış hep birebir aynı kalır.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/curriculum_catalog.dart' show CurriculumSubject;
import '../services/exam_catalog.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const kExamModeAccent = Color(0xFF0F766E);
const kExamModeConfirmGreen = Color(0xFF10B981);

/// "Sınav modu açmak ister misin? (LGS, YKS, KPSS…)" kartı — [titleOverride]
/// verilirse (kaydedilmiş/kalıcı sınav varken) onun yerine gösterilir.
/// [compact] → Dünya Sıralaması varyantı: ikon yok, beyaz zemin, daha ince
/// gövde ve "Sınav Modu" kısa başlığı.
class ExamModeCard extends StatelessWidget {
  final VoidCallback onTap;
  final String? titleOverride;
  final bool compact;
  const ExamModeCard({
    super.key,
    required this.onTap,
    this.titleOverride,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 16, vertical: compact ? 12 : 14),
          decoration: BoxDecoration(
            color: compact
                ? Colors.white
                : kExamModeAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(compact ? 14 : 18),
            // Kompakt varyantta çizgi YEŞİL — hero çerçevesiyle uyumlu.
            border: Border.all(
                color: compact
                    ? const Color(0xFF16A34A)
                    : kExamModeAccent.withValues(alpha: 0.30),
                width: compact ? 1.4 : 1.2),
          ),
          child: Row(
            children: [
              if (!compact) ...[
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: kExamModeAccent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('🎯', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: compact && titleOverride == null
                    // Kompakt varyant: büyük başlık + altında parantez
                    // içinde sınav adları (ayrı satır).
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sınav Modunu Seçebilirsin'.tr(),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111111),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '(LGS, YKS, KPSS…)',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        titleOverride ??
                            '${'Sınav modu açmak ister misin?'.tr()} (LGS, YKS, KPSS…)',
                        style: GoogleFonts.inter(
                          fontSize: compact ? 15 : 13.5,
                          fontWeight: FontWeight.w800,
                          color: compact
                              ? const Color(0xFF111111)
                              : AppPalette.textPrimary(context),
                          height: 1.3,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: kExamModeAccent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Kalıcı (kaydedilmiş) sınav — SharedPreferences ──────────────────────────
// Kullanıcı bir sınavı "Kaydet" derse, o sınav ülke koduyla birlikte
// saklanır; bir sonraki gelişte doğrudan o sınavın kısayolu gösterilir,
// tüm sınavları yeniden taramak zorunda kalmaz.
class PinnedExamService {
  PinnedExamService._();
  static const _kCountryKey = 'exam_mode_pinned_country';
  static const _kExamKey = 'exam_mode_pinned_exam_key';

  static Future<ExamDefinition?> load(String? countryCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCountry = prefs.getString(_kCountryKey);
      final savedExamKey = prefs.getString(_kExamKey);
      if (savedCountry == null || savedExamKey == null) return null;
      if (savedCountry != (countryCode ?? '').toUpperCase()) return null;
      final groups = examGroupsFor(countryCode);
      if (groups == null) return null;
      for (final g in groups) {
        for (final v in g.variants) {
          if (v.key == savedExamKey) return v;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String? countryCode, ExamDefinition exam) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCountryKey, (countryCode ?? '').toUpperCase());
      await prefs.setString(_kExamKey, exam.key);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCountryKey);
      await prefs.remove(_kExamKey);
    } catch (_) {}
  }

  // ── Seçim sayacı — "kaydet?" sorusu SPAM olmasın ─────────────────────────
  // Soru ilk seçimde DEĞİL, aynı sınav [pinOfferThreshold]. kez seçildiğinde
  // sorulur. Kullanıcı "Kaydetme" derse sayaç sıfırlanır → bir sonraki eşikte
  // (6 seçim sonra) tekrar sorulur; "Kaydet" derse sınav kalıcı kısayol olur.
  static const int pinOfferThreshold = 6;
  static const _kPickCountPrefix = 'exam_mode_pick_count_';

  /// Sınav seçim sayacını 1 artırır, yeni değeri döner. Hata → 1.
  static Future<int> incrementPickCount(String examKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final k = '$_kPickCountPrefix$examKey';
      final next = (prefs.getInt(k) ?? 0) + 1;
      await prefs.setInt(k, next);
      return next;
    } catch (_) {
      return 1;
    }
  }

  static Future<void> resetPickCount(String examKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kPickCountPrefix$examKey');
    } catch (_) {}
  }
}

/// Sınav seçildikten sonra "bunu kaydedeyim mi?" onayı — kaydedilirse bir
/// sonraki gelişte bu sınav doğrudan kısayol olarak gösterilir.
///
/// İlk seçimlerde SORULMAZ: aynı sınav [PinnedExamService.pinOfferThreshold]
/// (6). kez seçildiğinde sorulur — kullanıcı davranışı zaten netleşmiştir.
/// "Kaydetme" derse sayaç sıfırlanır, 6 seçim sonra bir kez daha sorulur.
Future<void> _maybeOfferPin(
    BuildContext context, String? countryCode, ExamDefinition exam) async {
  final current = await PinnedExamService.load(countryCode);
  if (current?.key == exam.key) return; // zaten kayıtlı, tekrar sorma
  final picks = await PinnedExamService.incrementPickCount(exam.key);
  if (picks < PinnedExamService.pinOfferThreshold) return;
  if (!context.mounted) return;
  final save = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppPalette.card(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(exam.displayName,
          style: GoogleFonts.fraunces(
              fontSize: 17, fontWeight: FontWeight.w800,
              color: AppPalette.textPrimary(ctx))),
      content: Text(
        '${'Bundan sonra'.tr()} ${exam.displayName} ${'sınavıyla yarışmaya katılacaksınız. Bu sınavı kaydedebilirsiniz. Bunu kaydettiğinde artık bu sınav otomatik her seferinde gösterilecek.'.tr()}',
        style: GoogleFonts.inter(
            fontSize: 13, height: 1.4, color: AppPalette.textSecondary(ctx)),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Kaydetme'.tr(),
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary(ctx))),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: kExamModeConfirmGreen,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Kaydet'.tr(),
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      ],
    ),
  );
  // Her iki cevapta da sayaç sıfırlanır: "Kaydet" → artık sorulmaz (pinned);
  // "Kaydetme" → 6 seçim sonra tekrar sorulur, her seferinde değil.
  await PinnedExamService.resetPickCount(exam.key);
  if (save == true) {
    await PinnedExamService.save(countryCode, exam);
  }
}

/// "Sınav Modu" bölümü — TAM widget: kaydedilmiş sınav yoksa genel kart +
/// "İstersen bu seçeneklerle de yarışabilirsin" başlığı; kaydedilmiş sınav
/// varsa doğrudan o sınavın kısayolu + "Aşağıdaki sınav moduyla devam
/// edebilirsin" başlığı. Tüm entegrasyon noktalarında (Bilgi Ligi, Bilgi
/// Yarışı/Arena, Sınav Soruları Oluştur) AYNI davranış için kullanılır.
class ExamModeSection extends StatefulWidget {
  final String? countryCode;
  final void Function(ExamModeSelection selection) onSelected;
  /// false → üstteki "İstersen bu seçeneklerle de yarışabilirsin" başlığı
  /// gizlenir (Dünya Sıralaması sade görünümü).
  final bool showHeader;
  /// true → kart kompakt varyantta çizilir (bkz. ExamModeCard.compact).
  final bool compact;
  const ExamModeSection({
    super.key,
    required this.countryCode,
    required this.onSelected,
    this.showHeader = true,
    this.compact = false,
  });

  @override
  State<ExamModeSection> createState() => _ExamModeSectionState();
}

class _ExamModeSectionState extends State<ExamModeSection> {
  ExamDefinition? _pinned;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ExamModeSection old) {
    super.didUpdateWidget(old);
    if (old.countryCode != widget.countryCode) _load();
  }

  Future<void> _load() async {
    final p = await PinnedExamService.load(widget.countryCode);
    if (mounted) {
      setState(() {
        _pinned = p;
        _loaded = true;
      });
    }
  }

  Future<void> _handleGeneric() async {
    final selection =
        await pickExamModeSelection(context, countryCode: widget.countryCode);
    if (selection == null) return;
    if (mounted) await _load(); // pin durumu değişmiş olabilir
    widget.onSelected(selection);
  }

  Future<void> _handlePinned(ExamDefinition exam) async {
    final selection =
        await pickExamModeSelectionForPinned(context, exam: exam);
    if (selection == null) return;
    widget.onSelected(selection);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final groups = examGroupsFor(widget.countryCode);
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();
    final pinned = _pinned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8, top: 2),
            child: Text(
              (pinned == null
                      ? 'İstersen bu seçeneklerle de yarışabilirsin'
                      : 'Aşağıdaki sınav moduyla devam edebilirsin')
                  .tr(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: AppPalette.textPrimary(context),
                letterSpacing: 0.4,
              ),
            ),
          ),
        pinned == null
            ? ExamModeCard(onTap: _handleGeneric, compact: widget.compact)
            : ExamModeCard(
                titleOverride: pinned.displayName,
                compact: widget.compact,
                onTap: () => _handlePinned(pinned),
              ),
      ],
    );
  }
}

/// Sınav Modu seçimi sonucu — hangi sınav/varyant + ders + (varsa) konu.
class ExamModeSelection {
  final ExamDefinition exam;
  final CurriculumSubject subject;
  final String? topic;
  const ExamModeSelection({required this.exam, required this.subject, this.topic});
}

/// Tek CTA → Sınav grubu (LGS/TYT/AYT/DGS/KPSS, varyantlıysa açılır alt
/// liste) → ("bunu kaydet?" onayı) → Ders → Konu, hepsini zincirleme sorar.
/// Herhangi bir adımda vazgeçilirse null döner. [countryCode]
/// EduProfile.country (küçük harf ISO-2, örn. 'tr') — kExamCatalog bu koda
/// göre filtrelenir.
Future<ExamModeSelection?> pickExamModeSelection(
  BuildContext context, {
  required String? countryCode,
}) async {
  final groups = examGroupsFor(countryCode);
  if (groups == null || groups.isEmpty) return null;

  final exam = await showDialog<ExamDefinition>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ExamGroupPickerDialog(groups: groups),
  );
  if (exam == null || !context.mounted) return null;

  await _maybeOfferPin(context, countryCode, exam);
  if (!context.mounted) return null;

  return _pickSubjectAndTopic(context, exam);
}

/// Kaydedilmiş (kalıcı) sınav için — Sınav Grubu adımı ve "kaydet?" onayı
/// ATLANIR, doğrudan Ders → Konu seçimine geçilir.
Future<ExamModeSelection?> pickExamModeSelectionForPinned(
  BuildContext context, {
  required ExamDefinition exam,
}) {
  return _pickSubjectAndTopic(context, exam);
}

Future<ExamModeSelection?> _pickSubjectAndTopic(
    BuildContext context, ExamDefinition exam) async {
  final subject = await showDialog<CurriculumSubject>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ExamSubjectPickerDialog(
      title: '${exam.displayName} ${'sınavından hangi dersten test çözmek istersin?'.tr()}',
      items: [
        for (final s in exam.subjects)
          ExamSubjectPickerItem(emoji: s.emoji, label: s.displayName, value: s),
      ],
    ),
  );
  if (subject == null || !context.mounted) return null;

  final topicEntries = <ExamTopicEntry>[
    ExamTopicEntry(label: 'Tüm Konular'.tr(), value: '__ALL__', highlighted: true),
    for (final t in subject.topics) ExamTopicEntry(label: t, value: t),
  ];
  final pickedTopic = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => ExamTopicPickerSheet(
      subjectEmoji: subject.emoji,
      subjectName: '${exam.displayName} · ${subject.displayName}',
      topics: topicEntries,
    ),
  );
  if (pickedTopic == null || !context.mounted) return null;
  final topic = pickedTopic == '__ALL__' ? null : pickedTopic;

  return ExamModeSelection(exam: exam, subject: subject, topic: topic);
}

/// (sınav, ders) ikilisine özgü senkron/sınav puanı anahtarı+etiketi —
/// normal müfredat derslerinden AYRI bir "ders" olarak lig/sıralamaya girer.
CurriculumSubject examSyntheticSubject(ExamDefinition exam, CurriculumSubject subject) {
  return CurriculumSubject(
    key: '${exam.key}_${subject.key}',
    displayName: '${exam.displayName} · ${subject.displayName}',
    emoji: subject.emoji,
    topics: subject.topics,
  );
}

// ── Sınav grubu seçim dialog'u ──────────────────────────────────────────────
class ExamGroupPickerDialog extends StatefulWidget {
  final List<ExamGroup> groups;
  const ExamGroupPickerDialog({super.key, required this.groups});

  @override
  State<ExamGroupPickerDialog> createState() => _ExamGroupPickerDialogState();
}

class _ExamGroupPickerDialogState extends State<ExamGroupPickerDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppPalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Hangi sınava hazırlanıyorsun?'.tr(),
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textPrimary(context),
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final g in widget.groups)
                      g.hasSingleVariant
                          ? ListTile(
                              leading: Text(g.emoji, style: const TextStyle(fontSize: 22)),
                              title: Text(g.displayName,
                                  style: GoogleFonts.inter(
                                      fontSize: 15, fontWeight: FontWeight.w800,
                                      color: AppPalette.textPrimary(context))),
                              subtitle: Text(g.description.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: AppPalette.textSecondary(context))),
                              trailing: const Icon(Icons.chevron_right_rounded, color: kExamModeAccent),
                              onTap: () => Navigator.of(context).pop(g.variants.first),
                            )
                          : ExpansionTile(
                              leading: Text(g.emoji, style: const TextStyle(fontSize: 22)),
                              title: Text(g.displayName,
                                  style: GoogleFonts.inter(
                                      fontSize: 15, fontWeight: FontWeight.w800,
                                      color: AppPalette.textPrimary(context))),
                              subtitle: Text(g.description.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: AppPalette.textSecondary(context))),
                              iconColor: kExamModeAccent,
                              collapsedIconColor: kExamModeAccent,
                              childrenPadding: const EdgeInsets.only(bottom: 6),
                              children: [
                                for (final v in g.variants)
                                  ListTile(
                                    contentPadding: const EdgeInsets.only(left: 46, right: 18),
                                    title: Text(v.displayName,
                                        style: GoogleFonts.inter(
                                            fontSize: 13.5, fontWeight: FontWeight.w700,
                                            color: AppPalette.textPrimary(context))),
                                    trailing: const Icon(Icons.chevron_right_rounded,
                                        color: kExamModeAccent, size: 18),
                                    onTap: () => Navigator.of(context).pop(v),
                                  ),
                              ],
                            ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'İptal'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ders seçim dialog'u — başlık + grid kartlar + iptal ─────────────────────
class ExamSubjectPickerItem<T> {
  final String emoji;
  final String label;
  final T value;
  const ExamSubjectPickerItem({required this.emoji, required this.label, required this.value});
}

class ExamSubjectPickerDialog<T> extends StatelessWidget {
  final String title;
  final List<ExamSubjectPickerItem<T>> items;
  const ExamSubjectPickerDialog({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppPalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.fraunces(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
                letterSpacing: -0.2,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final it in items)
                      Material(
                        color: AppPalette.cardMuted(context),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).pop(it.value),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(it.emoji, style: const TextStyle(fontSize: 26)),
                                const SizedBox(height: 6),
                                Text(
                                  it.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppPalette.textPrimary(context),
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'İptal'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Konu seçim dialog'u — "Hangi konudan yarışmak istersin?" ────────────────
class ExamTopicEntry {
  final String label;
  final String value;
  final bool highlighted;
  const ExamTopicEntry({required this.label, required this.value, this.highlighted = false});
}

class ExamTopicPickerSheet extends StatelessWidget {
  final String subjectEmoji;
  final String subjectName;
  final List<ExamTopicEntry> topics;
  const ExamTopicPickerSheet({
    super.key,
    required this.subjectEmoji,
    required this.subjectName,
    required this.topics,
  });

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6A00);
    return Dialog(
      backgroundColor: AppPalette.card(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(subjectEmoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subjectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondary(context),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Hangi konudan yarışmak istersin?'.tr(),
              style: GoogleFonts.fraunces(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary(context),
                letterSpacing: -0.3,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final t in topics) ...[
                      _ExamTopicPill(
                        entry: t,
                        accent: t.highlighted ? orange : kExamModeAccent,
                        onTap: () => Navigator.of(context).pop(t.value),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'İptal'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamTopicPill extends StatelessWidget {
  final ExamTopicEntry entry;
  final Color accent;
  final VoidCallback onTap;
  const _ExamTopicPill({required this.entry, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: entry.highlighted ? accent : accent.withValues(alpha: 0.25),
              width: entry.highlighted ? 1.8 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.10),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (entry.highlighted)
                const Text('🟢', style: TextStyle(fontSize: 14))
              else
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111111),
                    letterSpacing: -0.1,
                    height: 1.25,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
