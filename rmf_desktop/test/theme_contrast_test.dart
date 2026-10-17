import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:rich_man_fitness/theme/theme_preset.dart';

/// Guards the palettes against a well-meaning colour tweak making text
/// unreadable. Both schemes are checked, because a pair that passes on the
/// dark surface says nothing about the light one.
void main() {
  /// WCAG 2.1 relative luminance.
  double luminance(Color c) {
    double channel(double v) {
      final s = v / 255.0;
      return s <= 0.04045
          ? s / 12.92
          : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(c.r * 255) +
        0.7152 * channel(c.g * 255) +
        0.0722 * channel(c.b * 255);
  }

  double contrast(Color fg, Color bg) {
    final a = luminance(fg);
    final b = luminance(bg);
    final hi = math.max(a, b);
    final lo = math.min(a, b);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// (label, foreground, background, minimum ratio)
  List<(String, Color, Color, double)> pairsFor(AppPalette p) => [
        ('body on scaffold', p.textPrimary, p.surfaceBase, 4.5),
        ('body on card', p.textPrimary, p.surfaceRaised, 4.5),
        ('secondary on card', p.textSecondary, p.surfaceRaised, 4.5),
        ('muted on card', p.textMuted, p.surfaceRaised, 4.5),
        ('muted on scaffold', p.textMuted, p.surfaceBase, 4.5),
        // Placeholders are the one text role allowed the large-text threshold.
        ('input placeholder', p.textHint, p.surfaceRaised, 3.0),
        ('text button on card', p.accentText, p.surfaceRaised, 4.5),
        ('text button on scaffold', p.accentText, p.surfaceBase, 4.5),
        // The sidebar became its own colour once presets started applying it,
        // so everything drawn in the nav is checked against it separately.
        ('active nav label on sidebar', p.textPrimary, p.sidebar, 4.5),
        ('nav label on sidebar', p.textSecondary, p.sidebar, 4.5),
        ('muted on sidebar', p.textMuted, p.sidebar, 4.5),
        // accentText, not accent: the raw brand on a white light-mode sidebar
        // is 2.24:1 for Black & Gold, too faint even for an icon.
        ('active nav icon on sidebar', p.accentText, p.sidebar, 3.0),
        // Was hardcoded as white-on-accent. Five of the seven brand presets
        // are too bright to carry white text, so each palette now declares the
        // colour that reads on its own accent and this checks whatever that is.
        ('label on primary button', p.onAccent, p.accent, 4.5),
        ('PAID badge', p.paid, p.paidBg, 4.5),
        ('DUE badge', p.due, p.dueBg, 4.5),
        ('EXPIRED badge', p.expired, p.expiredBg, 4.5),
        ('INACTIVE badge', p.inactive, p.inactiveBg, 4.5),
      ];

  for (final (name, palette) in [
    ('dark', AppPalette.dark),
    ('light', AppPalette.light),
  ]) {
    group('$name palette meets WCAG AA', () {
      for (final (label, fg, bg, minimum) in pairsFor(palette)) {
        test(label, () {
          final ratio = contrast(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(minimum),
            reason: '$label is ${ratio.toStringAsFixed(2)}:1, '
                'below the required $minimum:1',
          );
        });
      }
    });
  }

  /// The point of the whole preset design: a gym can rebrand the app to any of
  /// these without making its own text unreadable.
  ///
  /// Five of the seven brands fail white-on-accent outright — Black & Gold at
  /// 2.24:1, Emerald at 2.54:1, Power Orange at 2.80:1 — which is why
  /// `onAccent` is per preset rather than a constant. Without this group those
  /// failures would only be discovered by an owner squinting at a button.
  for (final preset in ThemePreset.all) {
    for (final (brightnessName, brightness) in [
      ('dark', Brightness.dark),
      ('light', Brightness.light),
    ]) {
      group('${preset.name} ($brightnessName) meets WCAG AA', () {
        final base = brightness == Brightness.dark
            ? AppPalette.dark
            : AppPalette.light;
        final palette = base.withPreset(preset, brightness);

        for (final (label, fg, bg, minimum) in pairsFor(palette)) {
          test(label, () {
            final ratio = contrast(fg, bg);
            expect(
              ratio,
              greaterThanOrEqualTo(minimum),
              reason: '${preset.name} $brightnessName: $label is '
                  '${ratio.toStringAsFixed(2)}:1, below $minimum:1',
            );
          });
        }
      });
    }
  }

  group('a custom theme stays readable', () {
    /// The owner can type any hex they like, so the label on a filled button is
    /// chosen at runtime rather than declared. These are the colours most
    /// likely to catch a naive white-on-brand implementation.
    for (final (name, hex) in [
      ('pure yellow', '#FFFF00'),
      ('pure white', '#FFFFFF'),
      ('pure black', '#000000'),
      ('mid grey', '#808080'),
      ('the brief\'s brighter red', '#FF334F'),
      ('gold', '#D4A72C'),
    ]) {
      test('$name gets a readable label', () {
        final colour = parseHexColor(hex)!;
        final label = readableOn(colour);
        expect(
          contrast(label, colour),
          greaterThanOrEqualTo(4.5),
          reason: '$name ($hex) would carry unreadable button text',
        );
      });
    }

    test('a custom primary flows through to the palette', () {
      const config = BrandingConfig(
        presetId: BrandingConfig.customId,
        custom: CustomColors(primary: Color(0xFFD4A72C)),
      );
      final palette =
          AppPalette.dark.withPreset(config.effectivePreset, Brightness.dark);

      expect(palette.accent, const Color(0xFFD4A72C));
      expect(contrast(palette.onAccent, palette.accent),
          greaterThanOrEqualTo(4.5),
          reason: 'a custom gold must not keep white button text');
    });

    test('an unset custom colour falls back rather than going black', () {
      // A half-filled custom theme is the normal state while the owner is
      // still choosing. Every unset role must inherit the default preset's
      // value, not default to a Color(0x00000000).
      const config = BrandingConfig(presetId: BrandingConfig.customId);
      final preset = config.effectivePreset;

      expect(preset.primary, ThemePreset.fallback.primary);
      expect(preset.backgroundDark, ThemePreset.fallback.backgroundDark);
      expect(preset.surfaceDark, ThemePreset.fallback.surfaceDark);
    });
  });

  test('the default preset id matches the default preset', () {
    // BrandingConfig cannot reference ThemePreset.richmanRed.id from a const
    // default, so the literal is pinned here instead.
    expect(BrandingConfig.defaultPresetId, ThemePreset.richmanRed.id);
    expect(const BrandingConfig().effectivePreset.primary,
        ThemePreset.richmanRed.primary);
  });

  test('an unknown preset id opens in the default rather than crashing', () {
    // The downgrade case: a settings row written by a newer build naming a
    // preset this one has never heard of.
    expect(ThemePreset.byId('someFuturePreset').id, ThemePreset.fallback.id);
    expect(ThemePreset.byId(null).id, ThemePreset.fallback.id);
  });

  test('the default branding reproduces the palette the gym already had', () {
    // The upgrade promise, asserted in colour rather than in the database: a
    // fresh BrandingConfig must paint exactly the crimson the app shipped with.
    final themed = buildDarkThemeFor(const BrandingConfig())
        .extension<AppPalette>()!;

    expect(themed.accent, AppPalette.dark.accent);
    expect(themed.surfaceBase, AppPalette.dark.surfaceBase);
    expect(themed.surfaceRaised, AppPalette.dark.surfaceRaised);
    expect(themed.textPrimary, AppPalette.dark.textPrimary);
  });

  test('status colours survive a rebrand', () {
    // PAID green and DUE amber mean something; the Emerald preset must not
    // turn the brand and the warning into the same green.
    for (final preset in ThemePreset.all) {
      final palette = AppPalette.dark.withPreset(preset, Brightness.dark);
      expect(palette.paid, AppPalette.dark.paid, reason: preset.name);
      expect(palette.due, AppPalette.dark.due, reason: preset.name);
      expect(palette.expired, AppPalette.dark.expired, reason: preset.name);
    }
  });

  test('the two schemes define every token differently where it matters', () {
    // A token accidentally left at its dark value would be invisible in light
    // mode; surfaces and text are the ones that would hurt most.
    expect(AppPalette.light.surfaceBase, isNot(AppPalette.dark.surfaceBase));
    expect(AppPalette.light.textPrimary, isNot(AppPalette.dark.textPrimary));
    expect(AppPalette.light.paidBg, isNot(AppPalette.dark.paidBg));
    expect(AppPalette.light.dueBg, isNot(AppPalette.dark.dueBg));
    expect(AppPalette.light.expiredBg, isNot(AppPalette.dark.expiredBg));
  });

  test('both themes expose the palette to widgets', () {
    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      expect(theme.extension<AppPalette>(), isNotNull);
    }
    expect(buildLightTheme().brightness, Brightness.light);
    expect(buildDarkTheme().brightness, Brightness.dark);
  });

  test('lerp stays within the two endpoints', () {
    final mid = AppPalette.dark.lerp(AppPalette.light, 0.5);
    expect(mid.surfaceBase, isNot(AppPalette.dark.surfaceBase));
    expect(mid.surfaceBase, isNot(AppPalette.light.surfaceBase));
    // t = 1 must land exactly on the far end, or a theme switch would settle
    // on a colour that is in neither scheme.
    expect(
      AppPalette.dark.lerp(AppPalette.light, 1.0).textPrimary,
      AppPalette.light.textPrimary,
    );
  });
}
