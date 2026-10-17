import 'package:flutter/material.dart';

/// A brand the owner can switch the whole app to.
///
/// A preset carries only the handful of colours that actually distinguish one
/// gym's branding from another — the brand colour, the surfaces it sits on, and
/// the text colour that reads on it. Everything else in [AppPalette] (status
/// greens and ambers, borders, muted text) is derived or shared, because a gym
/// that picks Ocean Teal still wants PAID to be green and DUE to be amber.
///
/// Presets are `const` data rather than rows in a table: they ship with the
/// release, and a gym cannot author one without also authoring the contrast
/// guarantees that go with it. The owner's own colours live in [BrandingConfig]
/// under the `custom` id instead.
@immutable
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.primary,
    required this.accentText,
    required this.onAccent,
    required this.backgroundDark,
    required this.surfaceDark,
    required this.sidebarDark,
  });

  /// Stored in the settings row. Never renamed: a stored id that no longer
  /// matches a preset falls back to the default rather than crashing, but a
  /// rename would silently reset every install that had chosen it.
  final String id;

  /// What the owner sees on the theme card.
  final String name;
  final String description;

  /// The brand colour: filled buttons, the active nav bar, progress fills.
  final Color primary;

  /// The brand colour as *text* on a dark surface. [primary] is frequently too
  /// dark or too saturated to clear 4.5:1 as small text, so a lighter sibling
  /// is declared rather than computed — a generated tint lands differently for
  /// a red than for a gold.
  final Color accentText;

  /// Text and icons drawn *on* [primary], which is the whole reason this field
  /// exists.
  ///
  /// White is only legible on a dark enough brand colour. Of the seven brands
  /// here, five are bright enough that white text fails WCAG AA against them
  /// (Black & Gold is 2.24:1 — effectively unreadable) while black clears it
  /// comfortably. Hardcoding `Colors.white` on a filled button, as the app did
  /// before presets existed, would have made those five inaccessible.
  final Color onAccent;

  /// The scaffold, cards and sidebar in dark mode. Light mode is shared across
  /// presets: a near-white surface is a near-white surface whatever the brand,
  /// and tinting it per preset made the lighter brands look washed out.
  final Color backgroundDark;
  final Color surfaceDark;
  final Color sidebarDark;

  /// The crimson this app has always used, and the default for any install that
  /// has never opened Appearance.
  ///
  /// Deliberately the *existing* `#E11D2E` rather than a brighter red: updating
  /// the app must not repaint the owner's gym on its own.
  static const richmanRed = ThemePreset(
    id: 'richmanRed',
    name: 'Richman Red',
    description: 'The original crimson.',
    primary: Color(0xFFE11D2E),
    accentText: Color(0xFFF04858),
    // 4.53:1 — the one brand here that carries white text on its own.
    onAccent: Colors.white,
    backgroundDark: Color(0xFF0B0B0D),
    surfaceDark: Color(0xFF121215),
    sidebarDark: Color(0xFF09090B),
  );

  static const electricBlue = ThemePreset(
    id: 'electricBlue',
    name: 'Electric Blue',
    description: 'Cool and corporate.',
    primary: Color(0xFF2563EB),
    accentText: Color(0xFF7CA5FB),
    // 5.17:1.
    onAccent: Colors.white,
    backgroundDark: Color(0xFF0F172A),
    surfaceDark: Color(0xFF16213C),
    sidebarDark: Color(0xFF0B1220),
  );

  static const emeraldPerformance = ThemePreset(
    id: 'emeraldPerformance',
    name: 'Emerald Performance',
    description: 'Fresh, athletic green.',
    primary: Color(0xFF10B981),
    accentText: Color(0xFF4ADEA8),
    // White is 2.54:1 against this green; black is 8.28:1.
    onAccent: Color(0xFF04231A),
    backgroundDark: Color(0xFF0B1512),
    surfaceDark: Color(0xFF11201B),
    sidebarDark: Color(0xFF07100D),
  );

  static const royalPurple = ThemePreset(
    id: 'royalPurple',
    name: 'Royal Purple',
    description: 'Premium and distinctive.',
    primary: Color(0xFF7C3AED),
    accentText: Color(0xFFB69CF9),
    // 5.70:1.
    onAccent: Colors.white,
    backgroundDark: Color(0xFF12101A),
    surfaceDark: Color(0xFF1B1726),
    sidebarDark: Color(0xFF0D0B14),
  );

  static const powerOrange = ThemePreset(
    id: 'powerOrange',
    name: 'Power Orange',
    description: 'High energy, high visibility.',
    primary: Color(0xFFF97316),
    accentText: Color(0xFFFBA55C),
    // White is 2.80:1; black is 7.49:1.
    onAccent: Color(0xFF2B1304),
    backgroundDark: Color(0xFF17120F),
    surfaceDark: Color(0xFF231A14),
    sidebarDark: Color(0xFF110D0A),
  );

  static const oceanTeal = ThemePreset(
    id: 'oceanTeal',
    name: 'Ocean Teal',
    description: 'Calm and clinical.',
    primary: Color(0xFF0891B2),
    accentText: Color(0xFF4CC2DD),
    // White is 3.68:1 — close, but short of AA; black is 5.70:1.
    onAccent: Color(0xFF02181E),
    backgroundDark: Color(0xFF0D1619),
    surfaceDark: Color(0xFF142227),
    sidebarDark: Color(0xFF091113),
  );

  static const blackGold = ThemePreset(
    id: 'blackGold',
    name: 'Black & Gold',
    description: 'Understated luxury.',
    primary: Color(0xFFD4A72C),
    accentText: Color(0xFFE3C05A),
    // The starkest case: white on this gold is 2.24:1, black is 9.36:1.
    onAccent: Color(0xFF241B03),
    backgroundDark: Color(0xFF101010),
    surfaceDark: Color(0xFF191919),
    sidebarDark: Color(0xFF0A0A0A),
  );

  /// Every preset, in the order the Appearance screen shows them. Richman Red
  /// leads because it is the default and the brand the gym actually trades as.
  static const all = <ThemePreset>[
    richmanRed,
    electricBlue,
    emeraldPerformance,
    royalPurple,
    powerOrange,
    oceanTeal,
    blackGold,
  ];

  static const fallback = richmanRed;

  /// Resolves a stored id, tolerating anything unrecognised.
  ///
  /// An id can be unknown two ways: a release removed a preset, or the owner
  /// downgraded after choosing one a newer build added. Either way the app must
  /// open in a sane theme rather than refuse to start, so this never throws.
  static ThemePreset byId(String? id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return fallback;
  }
}
