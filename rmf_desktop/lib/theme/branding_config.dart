import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme_preset.dart';

/// Which receipt layout new receipts are rendered with.
///
/// Stored as a string in the settings row for the same reason [ThemePreset.id]
/// is: an unrecognised value must open as the default, not crash the app that
/// the gym's whole billing runs through.
enum ReceiptTemplate {
  /// The layout every receipt in the gym's history was rendered with: centred
  /// header, stacked fields, amount in a panel.
  classic,

  /// Stronger branding — a filled header band carrying the logo and gym name.
  modern,

  /// Quiet typography and hairline rules, no filled blocks.
  minimal;

  static ReceiptTemplate parse(String? stored) {
    for (final template in values) {
      if (template.name == stored) return template;
    }
    return classic;
  }
}

/// Everything the owner can change about how the app and its receipts look.
///
/// This is the single source of truth the Appearance screen edits, the theme
/// builds from, and the receipt renderer reads — one object, persisted in the
/// existing `gym_settings` row. A second place to store a logo or a brand
/// colour is how a sidebar and a receipt end up disagreeing about the gym's
/// own branding, so there isn't one.
@immutable
class BrandingConfig {
  const BrandingConfig({
    this.presetId = defaultPresetId,
    this.custom = const CustomColors(),
    this.logoPath,
    this.loginPhotoPath,
    this.dashboardPhotoPath,
    this.receiptTemplate = ReceiptTemplate.classic,
  });

  /// The chosen preset's id, or `custom`.
  final String presetId;

  /// The owner's own colours. Only consulted when [isCustom].
  final CustomColors custom;

  /// Absolute path to the logo on disk, or null when none is configured. The
  /// sidebar and every receipt template read this same field.
  final String? logoPath;

  /// Absolute path to the photograph behind the sign-in panel, or null for the
  /// drawn brand artwork.
  ///
  /// Separate from [dashboardPhotoPath] rather than one "hero photo" for both:
  /// the two slots are different shapes and are seen by different people — the
  /// sign-in art is the first thing anyone walking past the front desk sees,
  /// while the dashboard band is only ever seen by the owner — and a gym that
  /// wants its frontage on one and its floor on the other should not have to
  /// choose.
  final String? loginPhotoPath;

  /// Absolute path to the photograph in the dashboard hero band, or null.
  final String? dashboardPhotoPath;

  final ReceiptTemplate receiptTemplate;

  static const customId = 'custom';

  /// Matches [ThemePreset.richmanRed]'s id. A literal rather than a reference
  /// because a const default cannot read a property off another const object;
  /// a test asserts the two stay in step.
  static const defaultPresetId = 'richmanRed';

  bool get isCustom => presetId == customId;

  /// The preset this configuration resolves to. A custom configuration still
  /// has one: it supplies any colour the owner left blank, so a half-filled
  /// custom theme degrades to the default's value for that role rather than to
  /// black.
  ThemePreset get basePreset =>
      isCustom ? ThemePreset.fallback : ThemePreset.byId(presetId);

  /// The preset actually used to build the palette, with the owner's overrides
  /// applied on top.
  ThemePreset get effectivePreset {
    if (!isCustom) return basePreset;
    final base = basePreset;
    final primary = custom.primary ?? base.primary;
    return ThemePreset(
      id: customId,
      name: 'Custom',
      description: 'Your own colours.',
      primary: primary,
      accentText: custom.accent ?? base.accentText,
      // Recomputed rather than inherited: the owner picks a brand colour, not a
      // label colour, and a preset's `onAccent` says nothing about whether
      // white reads on *their* red. See [readableOn].
      onAccent: readableOn(primary),
      backgroundDark: custom.background ?? base.backgroundDark,
      surfaceDark: custom.surface ?? base.surfaceDark,
      sidebarDark: custom.sidebar ?? base.sidebarDark,
    );
  }

  BrandingConfig copyWith({
    String? presetId,
    CustomColors? custom,
    String? logoPath,
    bool clearLogo = false,
    String? loginPhotoPath,
    bool clearLoginPhoto = false,
    String? dashboardPhotoPath,
    bool clearDashboardPhoto = false,
    ReceiptTemplate? receiptTemplate,
  }) {
    return BrandingConfig(
      presetId: presetId ?? this.presetId,
      custom: custom ?? this.custom,
      logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
      loginPhotoPath:
          clearLoginPhoto ? null : (loginPhotoPath ?? this.loginPhotoPath),
      dashboardPhotoPath: clearDashboardPhoto
          ? null
          : (dashboardPhotoPath ?? this.dashboardPhotoPath),
      receiptTemplate: receiptTemplate ?? this.receiptTemplate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrandingConfig &&
      other.presetId == presetId &&
      other.custom == custom &&
      other.logoPath == logoPath &&
      other.loginPhotoPath == loginPhotoPath &&
      other.dashboardPhotoPath == dashboardPhotoPath &&
      other.receiptTemplate == receiptTemplate;

  @override
  int get hashCode => Object.hash(presetId, custom, logoPath, loginPhotoPath,
      dashboardPhotoPath, receiptTemplate);
}

/// The six colours the owner may override, each null until they set it.
@immutable
class CustomColors {
  const CustomColors({
    this.primary,
    this.accent,
    this.background,
    this.sidebar,
    this.surface,
    this.textPrimary,
  });

  final Color? primary;
  final Color? accent;
  final Color? background;
  final Color? sidebar;
  final Color? surface;
  final Color? textPrimary;

  CustomColors copyWith({
    Color? primary,
    Color? accent,
    Color? background,
    Color? sidebar,
    Color? surface,
    Color? textPrimary,
  }) {
    return CustomColors(
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      sidebar: sidebar ?? this.sidebar,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CustomColors &&
      other.primary == primary &&
      other.accent == accent &&
      other.background == background &&
      other.sidebar == sidebar &&
      other.surface == surface &&
      other.textPrimary == textPrimary;

  @override
  int get hashCode =>
      Object.hash(primary, accent, background, sidebar, surface, textPrimary);
}

/// WCAG 2.1 relative luminance.
///
/// Duplicated from test/theme_contrast_test.dart deliberately: the test asserts
/// the shipped palettes are accessible, while this runs at runtime on colours
/// the owner types in, which no test can see in advance.
double relativeLuminance(Color c) {
  double channel(double component) {
    final s = component / 255.0;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

/// Contrast ratio between two opaque colours, 1.0 (identical) to 21.0
/// (black on white).
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Black or white, whichever reads better on [background].
///
/// This is what keeps a custom brand colour accessible: the owner picks any
/// colour they like and the label on top flips to whichever of black or white
/// clears the better ratio, instead of being stuck on white and vanishing.
Color readableOn(Color background) {
  return contrastRatio(Colors.white, background) >=
          contrastRatio(Colors.black, background)
      ? Colors.white
      : Colors.black;
}

/// Parses `#RRGGBB` (or `RRGGBB`, or `#AARRGGBB`) into a colour.
///
/// Returns null for anything malformed, which is how the Appearance screen
/// tells a half-typed hex from a finished one without throwing on every
/// keystroke.
Color? parseHexColor(String input) {
  var hex = input.trim().replaceFirst('#', '').toUpperCase();
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  if (!RegExp(r'^[0-9A-F]{8}$').hasMatch(hex)) return null;
  return Color(int.parse(hex, radix: 16));
}

/// Formats a colour back to the `#RRGGBB` the owner typed, dropping the alpha
/// channel the picker never exposes.
String formatHexColor(Color color) {
  final argb = color.toARGB32();
  return '#${(argb & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';
}
