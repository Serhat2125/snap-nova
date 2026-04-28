// ═══════════════════════════════════════════════════════════════════════════════
//  4 modülün CurriculumController'a bağlı canlı görünümleri
//
//   1) SummaryPanel    → Sol: ders listesi · Sağ: alt konular · "Özet Oluştur"
//   2) ExamCreator     → Ders seç + alt konuları işaretle + "Sınav Oluştur"
//   3) BilgiYarısı     → Aktif sınıfa özel sorular (level lock)
//   4) ArenaPrep       → Country/world matchmaking key görselleştirme
//
//  Hepsi `ref.watch(curriculumControllerProvider)` izliyor → profil değişince
//  Reset-First state empty olduğunda HEPSİ aynı anda boşalır, yeni profil
//  yüklendiğinde HEPSİ yeni veriyle dolar.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/curriculum_node.dart';
import '../providers/curriculum_controller.dart';
import '../providers/matchmaking_provider.dart';

// ────────────────────────────────────────────────────────────────────────────
// 1) SUMMARY PANEL — sol ders, sağ alt konular, "Özet Oluştur"
// ────────────────────────────────────────────────────────────────────────────

class CurriculumSummaryPanel extends ConsumerStatefulWidget {
  const CurriculumSummaryPanel({super.key});
  @override
  ConsumerState<CurriculumSummaryPanel> createState() =>
      _CurriculumSummaryPanelState();
}

class _CurriculumSummaryPanelState
    extends ConsumerState<CurriculumSummaryPanel> {
  String? _activeSubjectKey;
  CurriculumSubtopic? _activeSubtopic;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(curriculumControllerProvider);
    // Profil değişimi: aktif seçimleri sıfırla
    ref.listen(curriculumControllerProvider, (prev, next) {
      if (prev?.preference != next.preference) {
        setState(() {
          _activeSubjectKey = null;
          _activeSubtopic = null;
        });
      }
    });

    if (state.subjects.isEmpty) {
      return _emptyMsg('Profil seç → konu özeti modülü hazırlansın.');
    }
    final activeSubject = _activeSubjectKey == null
        ? null
        : state.subjects.firstWhere(
            (s) => s.key == _activeSubjectKey,
            orElse: () => state.subjects.first,
          );
    final allSubtopics = activeSubject?.flattenSubtopics() ?? const [];

    return Row(
      children: [
        // Sol: dersler
        SizedBox(
          width: 130,
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: state.subjects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final s = state.subjects[i];
              final selected = s.key == _activeSubjectKey;
              return GestureDetector(
                onTap: () => setState(() {
                  _activeSubjectKey = s.key;
                  _activeSubtopic = null;
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF7C3AED).withValues(alpha: 0.10)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF7C3AED)
                          : Colors.black12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(s.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? const Color(0xFF7C3AED)
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(width: 1, color: Colors.black.withValues(alpha: 0.08)),
        // Sağ: alt konular + Özet butonu
        Expanded(
          child: activeSubject == null
              ? _emptyMsg('Sol panelden bir ders seç.')
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: Text(
                        '${activeSubject.emoji}  ${activeSubject.name} · alt konular',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: allSubtopics.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final st = allSubtopics[i];
                          final selected = _activeSubtopic?.id == st.id;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _activeSubtopic = st),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF7C3AED)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF7C3AED)
                                      : Colors.black12,
                                ),
                              ),
                              child: Text(
                                st.name,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _activeSubtopic == null
                              ? null
                              : () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '"${_activeSubtopic!.name}" özeti AI tarafından üretiliyor (demo).',
                                      ),
                                    ),
                                  );
                                },
                          child: Text(
                            _activeSubtopic == null
                                ? 'Önce alt konu seç'
                                : 'Özet Oluştur',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 2) EXAM CREATOR — ders + alt konu checkbox seti
// ────────────────────────────────────────────────────────────────────────────

class CurriculumExamCreator extends ConsumerStatefulWidget {
  const CurriculumExamCreator({super.key});
  @override
  ConsumerState<CurriculumExamCreator> createState() =>
      _CurriculumExamCreatorState();
}

class _CurriculumExamCreatorState
    extends ConsumerState<CurriculumExamCreator> {
  String? _subjectKey;
  final Set<String> _checkedIds = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(curriculumControllerProvider);
    ref.listen(curriculumControllerProvider, (prev, next) {
      if (prev?.preference != next.preference) {
        setState(() {
          _subjectKey = null;
          _checkedIds.clear();
        });
      }
    });

    if (state.subjects.isEmpty) {
      return _emptyMsg('Profil seç → sınav oluşturucu hazırlansın.');
    }

    final activeSubject = _subjectKey == null
        ? null
        : state.subjects.firstWhere((s) => s.key == _subjectKey,
            orElse: () => state.subjects.first);
    final allSubtopics = activeSubject?.flattenSubtopics() ?? const [];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _subjectKey,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              hintText: 'Ders seç',
            ),
            items: state.subjects
                .map((s) => DropdownMenuItem(
                      value: s.key,
                      child: Text('${s.emoji}  ${s.name}'),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              _subjectKey = v;
              _checkedIds.clear();
            }),
          ),
          const SizedBox(height: 10),
          if (activeSubject != null) ...[
            Text(
              'Konuları işaretle:',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                children: [
                  for (final st in allSubtopics)
                    CheckboxListTile(
                      title: Text(
                        st.name,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      value: _checkedIds.contains(st.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _checkedIds.add(st.id);
                        } else {
                          _checkedIds.remove(st.id);
                        }
                      }),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
              ),
              onPressed: _checkedIds.isEmpty
                  ? null
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Sınav: ${_checkedIds.length} alt konu üzerinden AI ile üretiliyor (demo).',
                          ),
                        ),
                      );
                    },
              child: Text(
                _checkedIds.isEmpty
                    ? 'En az 1 konu seç'
                    : '${_checkedIds.length} konuluk Sınav Oluştur',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 3) BİLGİ YARIŞI — sadece aktif sınıfın konularından soru
// ────────────────────────────────────────────────────────────────────────────

class CurriculumQuizModule extends ConsumerWidget {
  const CurriculumQuizModule({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pref = ref.watch(activePreferenceProvider);
    final subjects = ref.watch(activeSubjectsProvider);
    if (pref == null || subjects.isEmpty) {
      return _emptyMsg('Profil seç → quiz havuzu yüklensin.');
    }

    final allTopics = <String>[];
    for (final s in subjects) {
      for (final t in s.topics) {
        allTopics.add('${s.name} · ${t.name}');
      }
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFB800)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 18, color: Color(0xFF92400E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bilgi Yarışı seviye-kilitli — sadece "${pref.levelKey} ${pref.gradeKey}" düzeyindeki sorular gelir.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Quiz havuzu (${allTopics.length} konu)',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              itemCount: allTopics.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (_, i) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                ),
                child: Text(
                  allTopics[i],
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 4) ARENA PREP — matchmaking key'leri
// ────────────────────────────────────────────────────────────────────────────

class CurriculumArenaPrep extends ConsumerWidget {
  const CurriculumArenaPrep({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pref = ref.watch(activePreferenceProvider);
    final countryKey = ref.watch(countryMatchKeyProvider);
    final worldKey = ref.watch(worldMatchKeyProvider);
    if (pref == null) {
      return _emptyMsg('Profil seç → arena eşleşme havuzu hazırlansın.');
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _matchCard(
            title: 'Ülke İçi Eşleşme',
            subtitle:
                'Sadece aynı ülke + sınıf + bölüm. Firestore: where("countryMatchKey", isEqualTo: ...)',
            keyValue: countryKey ?? '—',
            color: const Color(0xFF22C55E),
          ),
          const SizedBox(height: 10),
          _matchCard(
            title: 'Dünya Eşdeğer',
            subtitle:
                'Aynı seviye + sınıf, farklı ülkeler. Sınava hazırlık modunda devre dışı.',
            keyValue: worldKey ?? '— (sınav modu)',
            color: const Color(0xFF3B82F6),
          ),
          const SizedBox(height: 14),
          Text(
            'Bu anahtarlar Firebase Firestore matchmaking koleksiyonunda where() filter olarak kullanılır.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchCard({
    required String title,
    required String subtitle,
    required String keyValue,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: GoogleFonts.inter(
                fontSize: 10.5, color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              keyValue,
              style: GoogleFonts.firaCode(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Yardımcı: boş durum mesajı
// ────────────────────────────────────────────────────────────────────────────

Widget _emptyMsg(String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          color: Colors.black54,
          height: 1.5,
        ),
      ),
    ),
  );
}
