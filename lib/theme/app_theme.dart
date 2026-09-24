import 'package:flutter/material.dart';

// Mirrors the web app's CSS tokens (src/index.css --lp-* / --sem-*), so the
// mobile shell reads as the same product instead of a reskin.
class AppColors {
  static const primary = Color(0xFF2563EB);
  static const primaryInk = Color(0xFF1D4ED8);
  static const accent = Color(0xFF0891B2);

  static const bg = Color(0xFF0B1220);
  static const surface = Color(0xFF121A2B);
  static const surface2 = Color(0xFF0F1625);
  static const border = Color(0xFF243147);

  static const ink = Color(0xFFEEF2F9);
  static const inkMuted = Color(0xFF9AA8C2);
  static const inkSubtle = Color(0xFF6B7996);

  static const green = Color(0xFF4ADE80);
  static const greenBg = Color(0xFF0F2418);
  static const amber = Color(0xFFFBBF24);
  static const amberBg = Color(0xFF2A2008);
  static const red = Color(0xFFF87171);
  static const redBg = Color(0xFF2A1212);
  static const blueBg = Color(0xFF0F1E35);
  static const cyan = Color(0xFF2DD4D4);
  static const cyanBg = Color(0xFF0A2323);
}

const semaphoreColors = <String, Color>{
  'blue': AppColors.cyan,
  'green': AppColors.green,
  'amber': AppColors.amber,
  'red': AppColors.red,
};

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
    ),
    cardColor: AppColors.surface,
    dividerColor: AppColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primaryInk,
      unselectedItemColor: AppColors.inkSubtle,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.ink),
      bodySmall: TextStyle(color: AppColors.inkMuted),
    ),
  );
}
