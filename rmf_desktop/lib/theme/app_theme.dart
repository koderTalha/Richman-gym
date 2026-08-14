import 'package:flutter/material.dart';

/// "Crimson & Steel" in two brightnesses.
///
/// Colours are held here rather than as bare constants on a class so a widget
/// reads whichever scheme is currently active:
///
/// ```dart
/// color: context.palette.surfaceRaised
/// ```
///
/// Token names describe the *role*, not the shade, because a name like `ink900`
/// is a lie in light mode where the same role is near-white.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textHint,
    required this.accent,
    required this.accentHover,
    required this.accentText,
    required this.paid,
    required this.paidBg,
    required this.due,
    required this.dueBg,
    required this.expired,
    required this.expiredBg,
    required this.inactive,
    required this.inactiveBg,
  });

  /// The scaffold behind everything.
  final Color surfaceBase;

  /// Cards and panels sitting on [surfaceBase].
  final Color surfaceRaised;

  /// Dialogs and input fills.
  final Color surfaceOverlay;

  final Color border;
  final Color borderStrong;

  /// Body copy and headings.
  final Color textPrimary;

  /// Supporting copy that still needs to be read easily.
  final Color textSecondary;

  /// Labels and captions.
  final Color textMuted;

  /// Input placeholders. The weakest text that still has to be legible.
  final Color textHint;

  final Color accent;
  final Color accentHover;

  /// Crimson as *text* — lighter than [accent] on dark, darker on light, since
  /// the same red cannot clear 4.5:1 against both.
  final Color accentText;

  final Color paid;
  final Color paidBg;
  final Color due;
  final Color dueBg;
  final Color expired;
  final Color expiredBg;
  final Color inactive;
  final Color inactiveBg;

  /// Every foreground/background pair below is checked against WCAG AA: 4.5:1
  /// for text, 3:1 for placeholders. Changing one means re-checking its
  /// partner — see test/theme_contrast_test.dart, which fails if a pair drops
  /// below the threshold.
  static const dark = AppPalette(
    surfaceBase: Color(0xFF0B0B0D),
    surfaceRaised: Color(0xFF121215),
    surfaceOverlay: Color(0xFF17171B),
    // Lifted from the original 0xFF1A1A1F, which rendered at 1.08:1 against a
    // card and so was effectively invisible.
    border: Color(0xFF26262D),
    borderStrong: Color(0xFF34343D),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFD4D4DC),
    textMuted: Color(0xFF8B8B98),
    // Was 0xFF3A3A44 at 1.66:1 — placeholder text nobody could read.
    textHint: Color(0xFF6E6E7A),
    accent: Color(0xFFE11D2E),
    accentHover: Color(0xFFC2162A),
    accentText: Color(0xFFF04858),
    paid: Color(0xFF22C55E),
    paidBg: Color(0xFF14311F),
    due: Color(0xFFF5A623),
    dueBg: Color(0xFF33280F),
    // Was 0xFFEF4444 at 4.40:1, just under AA on its own badge.
    expired: Color(0xFFF15A5A),
    expiredBg: Color(0xFF331616),
    inactive: Color(0xFF8B8B98),
    inactiveBg: Color(0xFF232329),
  );

  static const light = AppPalette(
    surfaceBase: Color(0xFFF7F7F8),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceOverlay: Color(0xFFFFFFFF),
    border: Color(0xFFE4E4E8),
    borderStrong: Color(0xFFD0D0D6),
    textPrimary: Color(0xFF16161A),
    textSecondary: Color(0xFF3A3A44),
    textMuted: Color(0xFF63636E),
    textHint: Color(0xFF8A8A95),
    // Darker than the dark scheme's crimson: 0xFFE11D2E carries white text at
    // only 3.9:1, which fails on a light button.
    accent: Color(0xFFC2162A),
    accentHover: Color(0xFF9E1222),
    accentText: Color(0xFFB01324),
    // Status colours are re-picked rather than inverted. The dark backgrounds
    // are near-black tints that read as dirt on a white surface.
    paid: Color(0xFF146C34),
    paidBg: Color(0xFFE7F6EC),
    due: Color(0xFF8F5606),
    dueBg: Color(0xFFFDF0CE),
    expired: Color(0xFFB91C1C),
    expiredBg: Color(0xFFFDE8E8),
    inactive: Color(0xFF52525B),
    inactiveBg: Color(0xFFEFEFF1),
  );

  @override
  AppPalette copyWith({
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textHint,
    Color? accent,
    Color? accentHover,
    Color? accentText,
    Color? paid,
    Color? paidBg,
    Color? due,
    Color? dueBg,
    Color? expired,
    Color? expiredBg,
    Color? inactive,
    Color? inactiveBg,
  }) {
    return AppPalette(
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textHint: textHint ?? this.textHint,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentText: accentText ?? this.accentText,
      paid: paid ?? this.paid,
      paidBg: paidBg ?? this.paidBg,
      due: due ?? this.due,
      dueBg: dueBg ?? this.dueBg,
      expired: expired ?? this.expired,
      expiredBg: expiredBg ?? this.expiredBg,
      inactive: inactive ?? this.inactive,
      inactiveBg: inactiveBg ?? this.inactiveBg,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      surfaceBase: mix(surfaceBase, other.surfaceBase),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceOverlay: mix(surfaceOverlay, other.surfaceOverlay),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      textHint: mix(textHint, other.textHint),
      accent: mix(accent, other.accent),
      accentHover: mix(accentHover, other.accentHover),
      accentText: mix(accentText, other.accentText),
      paid: mix(paid, other.paid),
      paidBg: mix(paidBg, other.paidBg),
      due: mix(due, other.due),
      dueBg: mix(dueBg, other.dueBg),
      expired: mix(expired, other.expired),
      expiredBg: mix(expiredBg, other.expiredBg),
      inactive: mix(inactive, other.inactive),
      inactiveBg: mix(inactiveBg, other.inactiveBg),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The palette for whichever theme is active.
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

ThemeData buildDarkTheme() => _buildTheme(AppPalette.dark, Brightness.dark);

ThemeData buildLightTheme() => _buildTheme(AppPalette.light, Brightness.light);

ThemeData _buildTheme(AppPalette p, Brightness brightness) {
  final base = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: Colors.white,
    secondary: p.accentText,
    onSecondary: Colors.white,
    surface: p.surfaceRaised,
    onSurface: p.textPrimary,
    error: p.expired,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: base,
    extensions: [p],
    scaffoldBackgroundColor: p.surfaceBase,
    fontFamily: 'Inter',
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: p.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.dark ? p.surfaceBase : p.surfaceRaised,
      hintStyle: TextStyle(color: p.textHint),
      labelStyle: TextStyle(color: p.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.expired),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        side: BorderSide(color: p.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accentText),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surfaceOverlay,
      contentTextStyle: TextStyle(color: p.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Small helpers used across screens.
///
/// Functions rather than constants: a `const TextStyle` bakes in one theme's
/// colour and cannot follow a switch to the other.
TextStyle labelStyleOf(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.8,
      color: context.palette.textMuted,
    );

TextStyle mutedStyleOf(BuildContext context) =>
    TextStyle(fontSize: 12, color: context.palette.textMuted);
