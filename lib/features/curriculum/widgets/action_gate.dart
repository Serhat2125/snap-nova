// ═══════════════════════════════════════════════════════════════════════════════
//  ActionGate — Subtopic-zorunlu Action butonu sarmalı
//
//  KURAL: "Özet Oluştur" / "Sınav Hazırla" / "Yarışmaya Katıl" butonları
//  ancak Subject + Topic + Subtopic seçilmiş olduğunda aktif olur.
//
//  Kullanım:
//   ActionGate(
//     subjectID: 'matematik',
//     topicID: 'turev',
//     subtopicID: selectedSub?.id,
//     label: 'Özet Oluştur',
//     onTriggered: () => generateSummary(...),
//   )
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/curriculum_manager.dart';

class ActionGate extends ConsumerWidget {
  final String? subjectID;
  final String? topicID;
  final String? subtopicID;
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback onTriggered;
  final String? hintWhenDisabled;

  const ActionGate({
    super.key,
    required this.subjectID,
    required this.topicID,
    required this.subtopicID,
    required this.label,
    required this.color,
    required this.onTriggered,
    this.icon,
    this.hintWhenDisabled,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(curriculumManagerProvider);
    final canFire = manager.canTriggerAction(
      subjectID: subjectID,
      topicID: topicID,
      subtopicID: subtopicID,
    );
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: canFire ? color : Colors.black12,
          foregroundColor: canFire ? Colors.white : Colors.black38,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(
          canFire ? (icon ?? Icons.bolt_rounded) : Icons.lock_outline_rounded,
          size: 18,
        ),
        onPressed: canFire ? onTriggered : null,
        label: Text(
          canFire
              ? label
              : (hintWhenDisabled ?? 'Önce alt konu seçmelisin'),
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
