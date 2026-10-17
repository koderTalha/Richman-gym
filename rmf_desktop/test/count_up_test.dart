import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/ui/widgets/count_up.dart';

/// The dashboard's figures count up when they appear. The two things that
/// matter: the owner always ends up looking at the true number, and the
/// animation finishes — a figure still counting is a figure being misread.
void main() {
  Widget wrap(Widget child, {required bool disableAnimations}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      ),
    );
  }

  Widget counter(num value) => CountUp(
        value: value,
        builder: (context, animated) => Text('${animated.round()}'),
      );

  testWidgets('starts at zero and lands on the real figure', (tester) async {
    await tester.pumpWidget(wrap(counter(319), disableAnimations: false));

    expect(find.text('0'), findsOneWidget, reason: 'it counts up from zero');

    await tester.pumpAndSettle();

    expect(find.text('319'), findsOneWidget);
  });

  testWidgets('passes through intermediate values on the way', (tester) async {
    await tester.pumpWidget(wrap(counter(1000), disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 550));

    final shown = int.parse(
      (tester.widget<Text>(find.byType(Text)).data)!,
    );
    expect(shown, greaterThan(0));
    expect(shown, lessThan(1000));

    await tester.pumpAndSettle();
  });

  testWidgets('shows the figure at once under reduced motion', (tester) async {
    await tester.pumpWidget(wrap(counter(319), disableAnimations: true));

    // No pump needed: there is nothing to animate.
    expect(find.text('319'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('counts again when the figure changes', (tester) async {
    // Recording a payment drops the due count by one; that change is exactly
    // what the animation is meant to draw the eye to.
    await tester.pumpWidget(wrap(counter(319), disableAnimations: false));
    await tester.pumpAndSettle();
    expect(find.text('319'), findsOneWidget);

    await tester.pumpWidget(wrap(counter(318), disableAnimations: false));
    await tester.pumpAndSettle();

    expect(find.text('318'), findsOneWidget);
  });

  testWidgets('a zero figure needs no animation to be correct',
      (tester) async {
    await tester.pumpWidget(wrap(counter(0), disableAnimations: false));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
  });
}
