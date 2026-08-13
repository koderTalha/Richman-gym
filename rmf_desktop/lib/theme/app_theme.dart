import 'package:flutter/material.dart';

/// "Crimson & Steel" — near-black surfaces, crimson accent, white type.
class AppColors {
  static const ink950 = Color(0xFF0B0B0D);
  static const ink900 = Color(0xFF121215);
  static const ink850 = Color(0xFF17171B);
  static const ink800 = Color(0xFF1A1A1F);
  static const ink700 = Color(0xFF26262D);
  static const ink600 = Color(0xFF3A3A44);
  static const ink400 = Color(0xFF8B8B98);
  static const ink200 = Color(0xFFD4D4DC);
  static const ink50 = Color(0xFFF5F5F7);

  static const crimson400 = Color(0xFFF04858);
  static const crimson500 = Color(0xFFE11D2E);
  static const crimson600 = Color(0xFFC2162A);

  static const paid = Color(0xFF22C55E);
  static const paidBg = Color(0xFF14311F);
  static const due = Color(0xFFF5A623);
  static const dueBg = Color(0xFF33280F);
  static const expired = Color(0xFFEF4444);
  static const expiredBg = Color(0xFF331616);
  static const inactive = Color(0xFF8B8B98);
  static const inactiveBg = Color(0xFF232329);
}

ThemeData buildAppTheme() {
  const base = ColorScheme.dark(
    primary: AppColors.crimson500,
    onPrimary: Colors.white,
    secondary: AppColors.crimson400,
    surface: AppColors.ink900,
    onSurface: AppColors.ink50,
    error: AppColors.expired,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: AppColors.ink950,
    fontFamily: 'Inter',
    dividerTheme: const DividerThemeData(
      color: AppColors.ink800,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: AppColors.ink900,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.ink800),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.ink950,
      hintStyle: const TextStyle(color: AppColors.ink600),
      labelStyle: const TextStyle(color: AppColors.ink400),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.ink700),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.ink700),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.crimson500),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.expired),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.crimson500,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink50,
        side: const BorderSide(color: AppColors.ink700),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.crimson400),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink800,
      contentTextStyle: TextStyle(color: AppColors.ink50),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Small helpers used across screens.
const kLabelStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.8,
  color: AppColors.ink400,
);

const kMutedStyle = TextStyle(fontSize: 12, color: AppColors.ink400);
