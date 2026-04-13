import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum CameraMode { tekli, coklu }

class ModeToggleBar extends StatelessWidget {
  final CameraMode selectedMode;
  final ValueChanged<CameraMode> onModeChanged;

  const ModeToggleBar({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tab(
            label: 'Çoklu',
            icon: Icons.fullscreen_rounded,
            isSelected: selectedMode == CameraMode.coklu,
            onTap: () => onModeChanged(CameraMode.coklu),
          ),
          _Tab(
            label: 'Tekli',
            icon: Icons.crop_square_rounded,
            isSelected: selectedMode == CameraMode.tekli,
            onTap: () => onModeChanged(CameraMode.tekli),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.cyanGlow, blurRadius: 12)]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.background : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color:
                    isSelected ? AppColors.background : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
