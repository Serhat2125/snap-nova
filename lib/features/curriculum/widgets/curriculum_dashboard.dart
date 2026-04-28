// ═══════════════════════════════════════════════════════════════════════════════
//  CurriculumDashboard — örnek 3 katmanlı arayüz
//
//  Üst sırada profil değiştirme butonları (Lise 12-YKS / İnşaat Müh. 3)
//  • Ders listesi (Level 1) — tıklayınca aşağıda konuları açılır
//  • Konular (Level 2)      — tıklayınca alt konular açılır
//  • Alt konular (Level 3)  — sınav/özet üretiminin temel girdisi
//
//  Bu sayfa standalone çalışır — başka mevcut ekrana dokunmaz.
//  Riverpod-driven; profil değişince Reset-First otomatik tetiklenir.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/user_preference.dart';
import '../providers/curriculum_controller.dart';
import '../providers/curriculum_manager.dart';
import 'module_demos.dart';

class CurriculumDashboard extends ConsumerWidget {
  const CurriculumDashboard({super.key});

  static const _liseYks = UserPreference(
    country: 'tr',
    languageCode: 'tr',
    levelKey: 'exam_prep',
    gradeKey: 'YKS',
  );
  static const _insaat3 = UserPreference(
    country: 'tr',
    languageCode: 'tr',
    levelKey: 'university',
    gradeKey: '3',
    branchKey: 'insaat_muh',
  );
  // Almanya 11. Klasse → Almanca müfredat. Talimatın test senaryosu.
  static const _gymnasium11 = UserPreference(
    country: 'de',
    languageCode: 'de',
    levelKey: 'high',
    gradeKey: '11',
  );
  // Aynı dünya kategorisi (TR 10 ↔ DE 10) — matchmaking testi.
  static const _trLise10 = UserPreference(
    country: 'tr',
    languageCode: 'tr',
    levelKey: 'high',
    gradeKey: '10',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(curriculumControllerProvider);
    // Hard Reset protokolü → CurriculumManager üzerinden geç. Sadece state
    // değil, eski profile ait cache prefs de temizlenir.
    final manager = ref.read(curriculumManagerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Curriculum Dashboard',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w800,
            color: Colors.black,
            fontSize: 16,
          ),
        ),
      ),
      body: Column(
        children: [
          // Profil seçici (4 senaryo — Reset-First testi için)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ProfileButton(
                  label: 'TR · YKS',
                  color: const Color(0xFF7C3AED),
                  active: state.preference == _liseYks,
                  onTap: () => manager.onChangeLevel(_liseYks),
                ),
                _ProfileButton(
                  label: 'TR · İnşaat 3',
                  color: const Color(0xFFF59E0B),
                  active: state.preference == _insaat3,
                  onTap: () => manager.onChangeLevel(_insaat3),
                ),
                _ProfileButton(
                  label: 'TR · Lise 10',
                  color: const Color(0xFF22C55E),
                  active: state.preference == _trLise10,
                  onTap: () => manager.onChangeLevel(_trLise10),
                ),
                _ProfileButton(
                  label: 'DE · Klasse 11',
                  color: const Color(0xFF3B82F6),
                  active: state.preference == _gymnasium11,
                  onTap: () => manager.onChangeLevel(_gymnasium11),
                ),
              ],
            ),
          ),
          // Aktif profil etiketi (Reset-First görselleştirmesi) +
          // matchmaking eşleşme anahtarları + dil + Context Lock göstergesi.
          if (state.preference != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kvRow('Bağlam Kilidi',
                        state.preference!.signature, const Color(0xFF7C3AED)),
                    const SizedBox(height: 3),
                    _kvRow('Dil', state.preference!.languageCode,
                        const Color(0xFF22C55E)),
                    const SizedBox(height: 3),
                    _kvRow('Ülke İçi Eşleşme',
                        state.preference!.countryMatchKey, Colors.black54),
                    const SizedBox(height: 3),
                    _kvRow(
                      'Dünya Eşdeğer',
                      (state.preference!.levelKey == 'exam_prep' ||
                              state.preference!.levelKey == 'lgs_prep')
                          ? '— (sınava hazırlık ülke spesifik)'
                          : state.preference!.worldMatchKey,
                      Colors.black54,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          // 4 modül — tab'lı senkronize görünüm.
          const SizedBox(height: 8),
          Expanded(
            child: DefaultTabController(
              length: 5,
              child: Column(
                children: [
                  Material(
                    color: Colors.white,
                    child: TabBar(
                      isScrollable: true,
                      labelColor: const Color(0xFF7C3AED),
                      unselectedLabelColor: Colors.black54,
                      indicatorColor: const Color(0xFF7C3AED),
                      labelStyle: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                      tabs: const [
                        Tab(text: '📚 Ders Ağacı'),
                        Tab(text: '📝 Konu Özeti'),
                        Tab(text: '✅ Sınav'),
                        Tab(text: '🎮 Quiz'),
                        Tab(text: '⚔️ Arena'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: ders ağacı (mevcut görünüm)
                        state.subjects.isEmpty
                            ? Center(
                                child: Text(
                                  'Profil seç → ders ağacı yüklensin',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 24),
                                itemCount: state.subjects.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) => _SubjectCard(
                                    subject: state.subjects[i]),
                              ),
                        const CurriculumSummaryPanel(),
                        const CurriculumExamCreator(),
                        const CurriculumQuizModule(),
                        const CurriculumArenaPrep(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini key-value satırı — debug etiketleri için.
Widget _kvRow(String k, String v, Color valueColor) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 110,
        child: Text(
          '$k:',
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
      ),
      Expanded(
        child: Text(
          v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.firaCode(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ),
    ],
  );
}

class _ProfileButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _ProfileButton({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? color : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: active ? 0 : 1.4),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectCard extends ConsumerStatefulWidget {
  final dynamic subject; // CurriculumSubject — ChangeNotifier-style import gerek yok
  const _SubjectCard({required this.subject});

  @override
  ConsumerState<_SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends ConsumerState<_SubjectCard> {
  bool _expanded = false;
  String? _openTopicKey;

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          // Level 1: Ders satırı
          ListTile(
            leading: Text(s.emoji, style: const TextStyle(fontSize: 22)),
            title: Text(
              s.name,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            trailing: AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            onTap: () => setState(() {
              _expanded = !_expanded;
              if (!_expanded) _openTopicKey = null;
            }),
          ),
          // Level 2: Konular
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  for (final t in s.topics)
                    _TopicRow(
                      topic: t,
                      open: _openTopicKey == t.key,
                      onToggle: () => setState(
                        () => _openTopicKey =
                            _openTopicKey == t.key ? null : t.key,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final dynamic topic; // CurriculumTopic
  final bool open;
  final VoidCallback onToggle;

  const _TopicRow({
    required this.topic,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(
              '· ${topic.name}',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Icon(
              open
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20,
            ),
            onTap: onToggle,
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final st in topic.subtopics)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.40),
                        ),
                      ),
                      child: Text(
                        st.name,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF5B21B6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
