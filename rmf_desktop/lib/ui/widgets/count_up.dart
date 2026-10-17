import 'package:flutter/material.dart';

/// A number that counts up from zero when it first appears.
///
/// The handoff asks for the dashboard's figures to animate in over 1100ms on
/// easeOutCubic. It is not decoration for its own sake: the count draws the
/// owner's eye to the figures that changed since they last looked, which on
/// this screen is the whole point.
///
/// Honours reduced motion by rendering the final value immediately — and
/// because [TweenAnimationBuilder] runs once and stops, this never leaves a
/// ticker running the way the rings would.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 1100),
  });

  /// The figure to land on.
  final num value;

  /// Draws the number. Called with the intermediate value on each frame, so
  /// the caller decides the formatting — money, a plain count, a percentage.
  final Widget Function(BuildContext context, num value) builder;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return builder(context, value);
    }

    return TweenAnimationBuilder<double>(
      // From zero every time the value changes, which is what makes a figure
      // that moved look like it moved.
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => builder(context, animated),
    );
  }
}
