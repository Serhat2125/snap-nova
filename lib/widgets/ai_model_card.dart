import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AiModel {
  final String name;
  final String subtitle;
  final String badge;       // Güçlü yan etiketi
  final Color accentColor;
  final Widget logo;

  const AiModel({
    required this.name,
    required this.subtitle,
    required this.accentColor,
    required this.logo,
    this.badge = '',
  });
}

class AiModelCard extends StatelessWidget {
  final AiModel model;
  final bool isSelected;
  final VoidCallback onTap;

  const AiModelCard({
    super.key,
    required this.model,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = model.accentColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.7) : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // Logo badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: color.withValues(alpha: isSelected ? 0.55 : 0.28),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: model.logo,
            ),
            const SizedBox(width: 14),
            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        model.name,
                        style: TextStyle(
                          color: isSelected ? color : AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (model.badge.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _Badge(label: model.badge, color: color),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    model.subtitle,
                    style: TextStyle(
                      color: isSelected
                          ? color.withValues(alpha: 0.75)
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Selection indicator
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isSelected
                  ? Icon(Icons.check_circle_rounded, color: color, size: 22)
                  : Icon(
                      Icons.radio_button_unchecked,
                      color: AppColors.border,
                      size: 22,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Badge ────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
