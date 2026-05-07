import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/theme_service.dart';

/// Theme-aware color tokens — Akıllı Karanlık Mod spec'i.
class AppPalette {
  static bool isDark(BuildContext context) {
    final mode = ThemeInherited.of(context).themeMode;
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  static Color bg(BuildContext c) =>
      isDark(c) ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
  static Color card(BuildContext c) =>
      isDark(c) ? const Color(0xFF1E1E1E) : Colors.white;
  static Color cardMuted(BuildContext c) =>
      isDark(c) ? const Color(0xFF2A2A2A) : const Color(0xFFF3F4F6);
  static Color textPrimary(BuildContext c) =>
      isDark(c) ? const Color(0xFFE0E0E0) : const Color(0xFF111111);
  static Color textSecondary(BuildContext c) =>
      isDark(c) ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);
  static Color border(BuildContext c) =>
      isDark(c) ? const Color(0xFF2E2E2E) : const Color(0xFFE5E7EB);
  static Color shadow(BuildContext c) =>
      isDark(c) ? Colors.black.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.06);
  static Color frostedOverlay(BuildContext c) => isDark(c)
      ? Colors.black.withValues(alpha: 0.60)
      : Colors.white.withValues(alpha: 0.70);

  // Renk Seç (Theme Customization) — kullanıcı seçimi her iki modda öncelikli.
  static Color resolvePageBg(BuildContext c, Color? userOverride) {
    return userOverride ?? bg(c);
  }
  static Color resolveCardBg(BuildContext c, Color? userOverride) {
    return userOverride ?? card(c);
  }
  static Color resolveInnerBg(BuildContext c, Color? userOverride) {
    if (userOverride != null) return userOverride;
    return isDark(c) ? cardMuted(c) : card(c);
  }

  // Blackout — kullanıcı override yoksa koyu modda saf siyah, aydınlıkta
  // beyaz. "Konu Özeti / Sınav Soruları" sayfalarında tam karartma için.
  static Color resolveBlackoutBg(BuildContext c, Color? userOverride) {
    if (userOverride != null) return userOverride;
    return isDark(c) ? Colors.black : Colors.white;
  }
}

class AppColors {
  static const Color background = Color(0xFF08080F);
  static const Color surface = Color(0xFF111119);
  static const Color surfaceElevated = Color(0xFF1A1A26);
  static const Color surfaceHighlight = Color(0xFF22223A);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color cyanDim = Color(0xFF00B4CC);
  static const Color cyanGlow = Color(0x3300E5FF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9A9AB0);
  static const Color textMuted = Color(0xFF5A5A78);
  static const Color border = Color(0xFF2A2A3E);
  static const Color borderCyan = Color(0x5500E5FF);
  static const Color overlayDark = Color(0xBB000000);
  static const Color white = Colors.white;
}

class AppTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        colorScheme: const ColorScheme.light(
          primary: AppColors.cyan,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.cyan,
          surface: Color(0xFF1E1E1E),
          onSurface: Color(0xFFE0E0E0),
        ),
        // Default Text widget color (style.color belirtilmediğinde) — beyaz tonu.
        primaryTextTheme: Typography.whiteMountainView,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
          titleLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
          labelSmall: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            letterSpacing: 0.3,
          ),
        ),
      );
}
