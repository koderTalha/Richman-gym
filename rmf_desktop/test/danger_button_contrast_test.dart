import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';

/// The Delete payment button once drew dark red text on a solid red fill:
/// it set its own background and inherited the brand's text colour. This
/// checks what the shared danger style actually resolves to, in both themes,
/// so no destructive button can end up unreadable that way again.
void main() {
  double luminance(Color c) {
    double channel(double v) {
      final s = v / 255;
      return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
    }

    return 0.2126 * channel(c.r * 255) +
        0.7152 * channel(c.g * 255) +
        0.0722 * channel(c.b * 255);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  for (final (name, theme) in [
    ('dark', buildDarkTheme()),
    ('light', buildLightTheme()),
  ]) {
    testWidgets('a destructive button is readable in the $name theme',
        (tester) async {
      late ButtonStyle danger;
      late ButtonStyle keep;
      late AppPalette palette;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (context) {
          danger = dangerButtonStyleOf(context);
          keep = keepButtonStyleOf(context);
          palette = context.palette;
          return const SizedBox();
        }),
      ));

      final label = danger.foregroundColor!.resolve({})!;
      final fill = danger.backgroundColor!.resolve({})!;
      expect(contrast(label, fill), greaterThanOrEqualTo(4.5),
          reason: 'Delete label on its fill is '
              '${contrast(label, fill).toStringAsFixed(2)}:1');

      // Readable against the dialog it sits in, too — the tint is light
      // enough that the label effectively sits on the dialog surface.
      expect(contrast(label, palette.surfaceRaised),
          greaterThanOrEqualTo(4.5));

      // The way out is not dressed in red: only the deleting choice is.
      final keepColour = keep.foregroundColor!.resolve({})!;
      expect(keepColour, isNot(palette.accentText));
      expect(contrast(keepColour, palette.surfaceRaised),
          greaterThanOrEqualTo(4.5));
    });
  }
}
