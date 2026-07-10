import 'package:flutter/material.dart';
import '../services/locale_service.dart';

import '../theme/app_theme.dart';
// ═══════════════════════════════════════════════════════════════════════════════
//  CameraBottomNav — 4 sekme: Sesli Komut · Tara · Akademik · Profil
//  Çözümlerim sekmesi Library içine taşındı. "Sesli Komut" sekmesi (index 0)
//  LiveAnalysisScreen'i açar — canlı sesli + opsiyonel kamera AI modu
//  (VoiceInputService/speech_to_text ile). Neon turkuaz kenarlık + gradient doku
// ═══════════════════════════════════════════════════════════════════════════════

class CameraBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const CameraBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  // Tüm sekme ikonları TEK ORTAK yeşil çizgiyle (kullanıcı isteği —
  // kırmızı/mor/pembe kaldırıldı, marka yeşili her sekmede).
  static const _navGreen = Color(0xFF34D399);

  static const _items = [
    // Sesli Komut → LiveAnalysisScreen (canlı sesli + kamera AI modu).
    _NavItem(
      icon: Icons.mic_none_rounded,
      activeIcon: Icons.mic_rounded,
      labelKey: 'voice_command',
      color: _navGreen,
    ),
    _NavItem(
      icon: Icons.qr_code_scanner_rounded,
      activeIcon: Icons.qr_code_scanner_rounded,
      labelKey: 'scan',
      color: _navGreen,
    ),
    _NavItem(
      // Kütüphane sekmesi: takvim yerine açık kitap (kullanıcı isteği).
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book_rounded,
      labelKey: 'academic_planner',
      color: _navGreen,
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      labelKey: 'profile',
      color: _navGreen,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        // Pill içi açık temada SAF BEYAZ (kullanıcı isteği); koyu temada
        // kart rengi.
        color: AppPalette.isDark(context)
            ? AppPalette.card(context)
            : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: Offset(0, 6),
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
    // İkon çizgileri her durumda sekmenin KENDİ renginde (kullanıcı isteği:
    // mic kırmızı, tara mor, kitap yeşil, profil pembe) — seçili tam ton,
    // pasifken hafif soluk. Yazılar temaya göre siyah/beyaz ve belirgin.
    final idleIconColor = item.color.withValues(alpha: 0.78);
    final labelColor = AppPalette.isDark(context)
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.black;

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
              duration: Duration(milliseconds: 220),
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
                color: isSelected ? color : idleIconColor,
              ),
            ),
            SizedBox(height: 2),
            // Etiket — seçiliyse renkli, değilse soluk
            if (label.isNotEmpty)
              AnimatedDefaultTextStyle(
                duration: Duration(milliseconds: 220),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight:
                      isSelected ? FontWeight.w800 : FontWeight.w700,
                  color: labelColor,
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
