import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/widgets/rotating_rings.dart';

/// The decorative rings turn forever, which makes them the one widget in the
/// app that can hang a test: `pumpAndSettle` waits for the frame loop to go
/// quiet and an endless animation never does. They must therefore stop dead
/// when reduced motion is asked for — both because the handoff requires it and
/// because that is the switch every widget test covering the dashboard relies
/// on.
void main() {
  Widget wrap(Widget child, {required bool disableAnimations}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('turn when motion is allowed', (tester) async {
    await tester.pumpWidget(
      wrap(const RotatingRings(size: 120), disableAnimations: false),
    );
    // One frame only: pumpAndSettle would never return, which is the whole
    // point of the test below.
    await tester.pump();

    expect(
      tester.binding.transientCallbackCount,
      greaterThan(0),
      reason: 'a ticker should be running',
    );

    // Leaves the tree quiet so the test can finish.
    await tester.pumpWidget(
      wrap(const SizedBox.shrink(), disableAnimations: false),
    );
  });

  testWidgets('stand still when reduced motion is asked for', (tester) async {
    await tester.pumpWidget(
      wrap(const RotatingRings(size: 120), disableAnimations: true),
    );

    // The assertion is that this returns at all: an unguarded repeating
    // controller times out here.
    await tester.pumpAndSettle();

    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('stop when reduced motion is switched on while they turn',
      (tester) async {
    await tester.pumpWidget(
      wrap(const RotatingRings(size: 120), disableAnimations: false),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(
      wrap(const RotatingRings(size: 120), disableAnimations: true),
    );
    await tester.pumpAndSettle();

    expect(tester.binding.transientCallbackCount, 0);
  });
}
