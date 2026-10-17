import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The handoff's motion art: five concentric dashed circles in the brand
/// colour, turning once a minute.
///
/// Shared by the sign-in panel and the dashboard hero so the two cannot drift
/// apart, and so the reduced-motion rule is honoured in one place rather than
/// remembered twice. Wrapped in an [IgnorePointer] and a [RepaintBoundary]: it
/// is decoration that must never swallow a click, and it repaints continuously,
/// which should not drag the panel it sits behind into every frame.
class RotatingRings extends StatefulWidget {
  const RotatingRings({super.key, required this.size, this.colour});

  final double size;

  /// Defaults to the gym's brand colour.
  final Color? colour;

  @override
  State<RotatingRings> createState() => _RotatingRingsState();
}

class _RotatingRingsState extends State<RotatingRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // 60s a turn, as the handoff specifies: slow enough to read as ambient
    // rather than as something asking to be looked at.
    duration: const Duration(seconds: 60),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour reduced motion rather than spinning regardless.
    //
    // Read from the ambient MediaQuery, not the platform dispatcher: the
    // dispatcher misses a window-level override, and — the reason this is not
    // a detail — `flutter_test` turns animations off through MediaQuery, so a
    // widget that consults only the dispatcher keeps turning forever under
    // test and hangs the first `pumpAndSettle` that renders it. An endless
    // animation is never what a test is waiting for.
    //
    // In didChangeDependencies rather than initState because MediaQuery is an
    // inherited dependency and the setting can change while the app is open.
    //
    // Guarded on isAnimating because `repeat` restarts the simulation from
    // zero: called on every dependency change it would snap the rings back to
    // their starting angle each time an ancestor rebuilt.
    final disabled = MediaQuery.of(context).disableAnimations;
    if (disabled) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: RotationTransition(
          turns: _controller,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _RingsPainter(
              colour: widget.colour ?? context.palette.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Five concentric dashed circles in the brand colour.
///
/// Radii, opacities and dash patterns follow the handoff's "motion art" note;
/// drawn with a painter rather than five nested widgets because it is one
/// rotating group, not five independent things.
class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.colour});

  final Color colour;

  static const _radii = [0.95, 0.78, 0.60, 0.42, 0.26];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final half = size.width / 2;

    for (var i = 0; i < _radii.length; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = colour.withValues(alpha: 0.08 + i * 0.07);
      _dashedCircle(
        canvas,
        centre,
        half * _radii[i],
        paint,
        // Alternating patterns, so the rings read as distinct rather than as
        // one thick band.
        i.isOdd ? const [2.0, 10.0] : const [60.0, 18.0],
      );
    }
  }

  void _dashedCircle(
    Canvas canvas,
    Offset centre,
    double radius,
    Paint paint,
    List<double> pattern,
  ) {
    final circumference = 2 * math.pi * radius;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    var distance = 0.0;
    var draw = true;
    var index = 0;

    while (distance < circumference) {
      final length = pattern[index % pattern.length];
      if (draw) {
        final start = distance / circumference * 2 * math.pi;
        final sweep = (length / circumference) * 2 * math.pi;
        canvas.drawArc(rect, start, sweep, false, paint);
      }
      distance += length;
      draw = !draw;
      index++;
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.colour != colour;
}
