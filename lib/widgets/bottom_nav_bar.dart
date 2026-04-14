import 'package:flutter/material.dart';
import '../services/locale_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  CameraBottomNav — 4 sekme: Çözümler · Tara · Ödevlerim · Profil
//  Neon turkuaz kalın kenarlık + cyan→mor→magenta gradient doku
// ═══════════════════════════════════════════════════════════════════════════════

class CameraBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const CameraBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  static const _items = [
    _NavItem(
      icon: Icons.check_circle_outline_rounded,
      activeIcon: Icons.check_circle_rounded,
      labelKey: 'solutions',
      color: Color(0xFF3B82F6),
    ),
    _NavItem(
      icon: Icons.center_focus_weak_rounded,
      activeIcon: Icons.center_focus_strong_rounded,
      labelKey: 'scan',
      color: Color(0xFFAA44FF),
    ),
    _NavItem(
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded,
      labelKey: 'academic_planner',
      color: Color(0xFF34D399),
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      labelKey: 'profile',
      color: Color(0xFFEC4899),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: List.generate(
          _items.length,
          (i) => Expanded(
            child: _NavButton(
              item: _items[i],
              isSelected: selectedIndex == i,
              onTap: () => onItemSelected(i),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tek nav butonu ────────────────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.color;
    final locale = LocaleInherited.of(context);
    final label = locale.tr(item.labelKey);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // İkon — seçiliyse pill arka plan
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 18 : 12,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                size: 22,
                color: isSelected
                    ? color
                    : Colors.black.withValues(alpha: 0.38),
              ),
            ),
            const SizedBox(height: 2),
            // Etiket — seçiliyse renkli, değilse soluk
            if (label.isNotEmpty)
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? color
                      : Colors.black.withValues(alpha: 0.38),
                  letterSpacing: 0.1,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Veri modeli ───────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;
  final Color color;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.labelKey,
    required this.color,
  });
}
