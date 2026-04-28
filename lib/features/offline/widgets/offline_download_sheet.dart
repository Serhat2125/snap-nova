// ═══════════════════════════════════════════════════════════════════════════════
//  OfflineDownloadSheet — kütüphaneden açılan konu üretme paneli
//
//  Yeni akış:
//   1. Tüm dersler ExpansionTile olarak listelenir.
//   2. Bir derse tıklayınca konu BAŞLIKLARI AI'dan getirilir, cache'lenir.
//   3. Her konunun yanında "Oluştur" butonu — tıklayınca o konunun ÖZETİ
//      AI tarafından üretilir, prefs'e kaydedilir.
//   4. Aylık limit: ders başına 3 konu / ay.
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/education_profile.dart';
import '../providers/offline_pack_provider.dart';

class OfflineDownloadSheet extends ConsumerWidget {
  final List<EduSubject> subjects;
  final EduProfile profile;

  const OfflineDownloadSheet({
    super.key,
    required this.subjects,
    required this.profile,
  });

  static Future<void> show(
    BuildContext context, {
    required List<EduSubject> subjects,
    required EduProfile profile,
  }) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => OfflineDownloadSheet(
          subjects: subjects,
          profile: profile,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(offlineGenerationProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.97,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F7FB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: Color(0xFF7C3AED), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Konu Özeti Oluştur',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded,
                            size: 20, color: Colors.black54),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${profile.displayLabel()} müfredatındaki bir derse tıkla → konu başlıkları gelir. Her ders için ayda en fazla $kMonthlyTopicLimit konunun özetini AI ile oluşturabilirsin.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.black.withValues(alpha: 0.62),
                  height: 1.45,
                ),
              ),
            ),
            if (status.errorMessage != null)
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Text(
                  status.errorMessage!,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF92400E),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                itemCount: subjects.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _SubjectExpandable(
                  subject: subjects[i],
                  profile: profile,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectExpandable extends ConsumerStatefulWidget {
  final EduSubject subject;
  final EduProfile profile;
  const _SubjectExpandable({required this.subject, required this.profile});

  @override
  ConsumerState<_SubjectExpandable> createState() =>
      _SubjectExpandableState();
}

class _SubjectExpandableState extends ConsumerState<_SubjectExpandable> {
  bool _expanded = false;
  bool _loadingTopics = false;
  List<String>? _topics;
  String? _loadError;
  int _monthlyUsed = 0;
  Set<String> _generated = {};

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {
      _expanded = true;
      _loadError = null;
    });
    if (_topics == null) {
      await _loadTopics();
    }
    await _refreshUsage();
  }

  Future<void> _loadTopics() async {
    final ctrl = ref.read(offlineGenerationProvider.notifier);
    setState(() => _loadingTopics = true);
    try {
      final names = await ctrl.ensureTopicNames(
        profile: widget.profile,
        subjectKey: widget.subject.key,
        subjectName: widget.subject.name,
      );
      if (!mounted) return;
      setState(() {
        _topics = names;
        _loadingTopics = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Konular yüklenemedi: $e';
        _loadingTopics = false;
      });
    }
  }

  Future<void> _refreshUsage() async {
    final ctrl = ref.read(offlineGenerationProvider.notifier);
    final used = await ctrl.monthlyUsage(
      profile: widget.profile,
      subjectKey: widget.subject.key,
    );
    final list = await ctrl.readGenerated(
      profile: widget.profile,
      subjectKey: widget.subject.key,
    );
    if (!mounted) return;
    setState(() {
      _monthlyUsed = used;
      _generated = list.map((g) => g.name).toSet();
    });
  }

  Future<void> _generateTopic(String topicName) async {
    final ctrl = ref.read(offlineGenerationProvider.notifier);
    final res = await ctrl.generateTopic(
      profile: widget.profile,
      subjectKey: widget.subject.key,
      subjectName: widget.subject.name,
      topicName: topicName,
    );
    await _refreshUsage();
    if (!mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF166534),
          content: Text('"$topicName" özeti oluşturuldu ✓'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (res.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text(res.errorMessage!),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(offlineGenerationProvider);
    final quotaFull = _monthlyUsed >= kMonthlyTopicLimit;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          // Header — Subject row
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                child: Row(
                  children: [
                    Text(widget.subject.emoji,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    if (_topics != null) ...[
                      Text(
                        '$_monthlyUsed/$kMonthlyTopicLimit',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: quotaFull
                              ? const Color(0xFFDC2626)
                              : Colors.black54,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Body — topics
          if (_expanded) ...[
            Container(
              height: 1,
              color: Colors.black.withValues(alpha: 0.05),
            ),
            if (_loadingTopics)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _loadError!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFFDC2626),
                  ),
                ),
              )
            else if (_topics != null && _topics!.isEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Bu ders için konu bulunamadı.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              )
            else if (_topics != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(
                  children: [
                    for (final t in _topics!)
                      _TopicRow(
                        topicName: t,
                        isGenerating: status.isGenerating(
                            widget.subject.key, t),
                        isGenerated: _generated.contains(t),
                        canGenerate: !quotaFull,
                        onGenerate: () => _generateTopic(t),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final String topicName;
  final bool isGenerating;
  final bool isGenerated;
  final bool canGenerate;
  final VoidCallback onGenerate;

  const _TopicRow({
    required this.topicName,
    required this.isGenerating,
    required this.isGenerated,
    required this.canGenerate,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              topicName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (isGenerated)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: const Color(0xFF22C55E)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_rounded,
                      size: 13, color: Color(0xFF166534)),
                  const SizedBox(width: 3),
                  Text(
                    'Hazır',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF166534),
                    ),
                  ),
                ],
              ),
            )
          else if (isGenerating)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: canGenerate
                    ? const Color(0xFF7C3AED)
                    : Colors.black12,
                foregroundColor: canGenerate ? Colors.white : Colors.black38,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
                textStyle: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: canGenerate ? onGenerate : null,
              child: const Text('Oluştur'),
            ),
        ],
      ),
    );
  }
}
