import 'package:flutter/material.dart';

import '../screens/topic_3d_viewer_screen.dart';
import '../services/topic_3d_registry.dart';

/// "🧊 3D modelde gör" butonu — özet/çözüm ekranlarında konuya göre otomatik
/// görünür/gizlenir.
///
/// Konu adı veya serbest metin verilince [Topic3DRegistry.findByKeywords]
/// ile eşleşen bir model varsa buton render edilir; yoksa boş döner
/// (SizedBox.shrink).
///
/// Kullanım:
/// ```dart
/// Topic3DButton(topic: widget.summary.topic)
/// Topic3DButton(topic: solutionText)  // çözüm metninden keyword tarama
/// ```
class Topic3DButton extends StatelessWidget {
  final String topic;
  final EdgeInsetsGeometry padding;
  final bool compact;

  const Topic3DButton({
    super.key,
    required this.topic,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final model = Topic3DRegistry.findByKeywords(topic);
    if (model == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final btn = Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(context, Topic3DViewerScreen.route(model)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 6 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.view_in_ar,
                  color: theme.colorScheme.onPrimary, size: compact ? 14 : 18),
              const SizedBox(width: 6),
              Text(
                compact ? '3D' : '🧊 3D modelde gör',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 11.5 : 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (padding == EdgeInsets.zero) return btn;
    return Padding(padding: padding, child: btn);
  }
}
