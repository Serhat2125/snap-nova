import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.cyan,
          surface: AppColors.surface,
        ),
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
