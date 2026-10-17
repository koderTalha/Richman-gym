import 'package:flutter/material.dart';

import 'branding_config.dart';
import 'theme_preset.dart';

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
    required this.sidebar,
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
    required this.onAccent,
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

  /// The navigation rail down the left. Each preset declares its own — a
  /// shade darker than its surfaces, so the nav reads as frame rather than
  /// content — and the owner can override it in a custom theme.
  final Color sidebar;

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

  /// Text and icons drawn *on* [accent] — a filled button's label.
  ///
  /// Not `Colors.white`: of the seven brands the gym can choose, five are
  /// bright enough that white on them fails WCAG AA, so each preset declares
  /// what reads on it. See [ThemePreset.onAccent].
  final Color onAccent;

  final Color paid;
  final Color paidBg;
  final Color due;
  final Color dueBg;
  final Color expired;
  final Color expiredBg;
  final Color inactive;
  final Color inactiveBg;

  /// The wash behind a modal dialog.
  ///
  /// Derived rather than declared, so every preset and the owner's custom
  /// theme get one without a new colour to choose: a dark scheme dims towards
  /// its own base at 62%, a light one greys towards its text colour at 35% —
  /// the two scrims the handoff specifies.
  Color get scrim => surfaceBase.computeLuminance() < 0.5
      ? surfaceBase.withValues(alpha: 0.62)
      : textPrimary.withValues(alpha: 0.35);

  /// Every foreground/background pair below is checked against WCAG AA: 4.5:1
  /// for text, 3:1 for placeholders. Changing one means re-checking its
  /// partner — see test/theme_contrast_test.dart, which fails if a pair drops
  /// below the threshold.
  static const dark = AppPalette(
    surfaceBase: Color(0xFF0B0B0D),
    surfaceRaised: Color(0xFF121215),
    sidebar: Color(0xFF09090B),
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
    onAccent: Colors.white,
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
    sidebar: Color(0xFFFFFFFF),
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
    onAccent: Colors.white,
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
    Color? sidebar,
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
    Color? onAccent,
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
      sidebar: sidebar ?? this.sidebar,
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
      onAccent: onAccent ?? this.onAccent,
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
      sidebar: mix(sidebar, other.sidebar),
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
      onAccent: mix(onAccent, other.onAccent),
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

  /// Re-skins a palette for [preset], keeping everything the brand does not
  /// own.
  ///
  /// Only the brand colours and the surfaces they sit on move. Status colours
  /// are deliberately left alone: PAID is green and DUE is amber in every
  /// theme, because the owner reads those as *meaning*, not decoration, and a
  /// gym on the Emerald preset would otherwise have a green brand and a green
  /// warning that look alike. Borders and muted text are likewise shared — they
  /// are tuned against the surfaces, not the brand.
  AppPalette withPreset(ThemePreset preset, Brightness brightness) {
    if (brightness == Brightness.light) {
      // Light mode keeps its near-white surfaces whatever the brand: tinting
      // them per preset made the lighter brands look washed out, and the
      // contrast pairs are already tuned against white.
      return copyWith(
        accent: preset.primary,
        accentHover: Color.lerp(preset.primary, Colors.black, 0.18),
        // On a white surface the preset's own accentText (picked for dark
        // backgrounds) is far too light. Darkening by a fixed amount is not
        // enough either: a 22% shift leaves gold at 3.36:1 and emerald at
        // 3.76:1 as link text. So the brand is darkened until it actually
        // clears AA against the *scaffold*, which is the harsher of the two
        // light surfaces.
        accentText: _darkenUntilReadable(preset.primary, surfaceBase),
        onAccent: preset.onAccent,
      );
    }
    return copyWith(
      surfaceBase: preset.backgroundDark,
      surfaceRaised: preset.surfaceDark,
      sidebar: preset.sidebarDark,
      surfaceOverlay: Color.lerp(preset.surfaceDark, Colors.white, 0.04),
      accent: preset.primary,
      accentHover: Color.lerp(preset.primary, Colors.black, 0.18),
      accentText: preset.accentText,
      onAccent: preset.onAccent,
    );
  }
}

/// Darkens [brand] in small steps until it clears AA as text on [background].
///
/// Used for brand-coloured *text* in light mode, where a bright brand (gold,
/// emerald, orange) is unreadable at its own value. Stepping rather than
/// solving: the sRGB luminance curve makes a closed form awkward, and 24 steps
/// of 4% is both imperceptible per step and cheap enough to run on a theme
/// rebuild. If even black would not pass — impossible against a light surface,
/// but the loop should not depend on that — the darkest value is returned.
Color _darkenUntilReadable(Color brand, Color background, {double target = 4.5}) {
  var candidate = brand;
  for (var step = 0; step < 24; step++) {
    if (contrastRatio(candidate, background) >= target) return candidate;
    candidate = Color.lerp(brand, Colors.black, 0.04 * (step + 1))!;
  }
  return candidate;
}

extension AppPaletteContext on BuildContext {
  /// The palette for whichever theme is active.
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

ThemeData buildDarkTheme() => _buildTheme(AppPalette.dark, Brightness.dark);

ThemeData buildLightTheme() => _buildTheme(AppPalette.light, Brightness.light);

/// The dark theme for [branding] — what the app actually runs on.
ThemeData buildDarkThemeFor(BrandingConfig branding) => _buildTheme(
      AppPalette.dark.withPreset(branding.effectivePreset, Brightness.dark),
      Brightness.dark,
    );

ThemeData buildLightThemeFor(BrandingConfig branding) => _buildTheme(
      AppPalette.light.withPreset(branding.effectivePreset, Brightness.light),
      Brightness.light,
    );

ThemeData _buildTheme(AppPalette p, Brightness brightness) {
  final base = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
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
    // The handoff's rule: "primary actions are outlined (accent border,
    // transparent fill), never solid-filled". Applied here rather than by
    // rewriting the forty-odd FilledButton call sites, so every primary action
    // in the app follows it — including the ones in dialogs this redesign does
    // not otherwise touch.
    //
    // A tinted fill rather than fully transparent: a bare outline on a card
    // reads as secondary, and the 14% accent wash is what the handoff's own
    // Confirm and Save buttons use.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent.withValues(alpha: 0.14),
        foregroundColor: p.accentText,
        side: BorderSide(color: p.accent),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ).copyWith(
        // styleFrom bakes the disabled colours from the foreground/background
        // above, which would leave a disabled button looking active.
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? p.accent.withValues(alpha: 0.06)
                : p.accent.withValues(alpha: 0.14)),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? p.textMuted
                : p.accentText),
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

/// The style for a button that destroys something — Delete payment, Delete
/// member, Delete everything.
///
/// A red outline on a red tint with red text, rather than a solid red block.
/// The solid version took its label colour from the brand theme, which put
/// dark red text on bright red and left the most consequential button in the
/// app the hardest to read. These three colours are the EXPIRED badge's pair,
/// which test/theme_contrast_test.dart holds to WCAG AA in both themes.
ButtonStyle dangerButtonStyleOf(BuildContext context) {
  final p = context.palette;
  return FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
  ).copyWith(
    backgroundColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.disabled) ? p.inactiveBg : p.expiredBg),
    foregroundColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.disabled) ? p.textMuted : p.expired),
    iconColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.disabled) ? p.textMuted : p.expired),
    side: WidgetStateProperty.resolveWith((states) => BorderSide(
        color: states.contains(WidgetState.disabled) ? p.border : p.expired)),
    overlayColor: WidgetStatePropertyAll(p.expired.withValues(alpha: 0.12)),
  );
}

/// The style for the safe way out of a destructive dialog — Keep it, Cancel.
///
/// Neutral, so the only red in the dialog is the choice that deletes. In the
/// brand colour it looked like the primary action, and on the red preset it
/// was hard to tell which of the two buttons was the dangerous one.
ButtonStyle keepButtonStyleOf(BuildContext context) => TextButton.styleFrom(
      foregroundColor: context.palette.textSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
    );
