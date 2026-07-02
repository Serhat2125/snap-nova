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

import '../services/curriculum_catalog.dart' show CurriculumSubject;
import '../services/exam_catalog.dart';
import '../services/runtime_translator.dart';
import '../theme/app_theme.dart';

const kExamModeAccent = Color(0xFF0F766E);

/// "Sınav modu açmak ister misin? (LGS, YKS, KPSS…)" kartı.
class ExamModeCard extends StatelessWidget {
  final VoidCallback onTap;
  const ExamModeCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: kExamModeAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: kExamModeAccent.withValues(alpha: 0.30), width: 1.2),
          ),
          child: Row(
            children: [
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
              Expanded(
                child: Text(
                  '${'Sınav modu açmak ister misin?'.tr()} (LGS, YKS, KPSS…)',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimary(context),
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

/// Sınav Modu seçimi sonucu — hangi sınav/varyant + ders + (varsa) konu.
class ExamModeSelection {
  final ExamDefinition exam;
  final CurriculumSubject subject;
  final String? topic;
  const ExamModeSelection({required this.exam, required this.subject, this.topic});
}

/// Tek CTA → Sınav grubu (LGS/TYT/AYT/DGS/KPSS, varyantlıysa açılır alt
/// liste) → Ders → Konu, hepsini zincirleme sorar. Herhangi bir adımda
/// vazgeçilirse null döner. [countryCode] EduProfile.country (küçük harf
/// ISO-2, örn. 'tr') — kExamCatalog bu koda göre filtrelenir.
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
