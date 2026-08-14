import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';

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
        ('white on primary button', Colors.white, p.accent, 4.5),
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
