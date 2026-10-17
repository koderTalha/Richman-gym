import 'package:flutter/material.dart';

/// Fades a widget in while it rises 8px, once, when it first appears.
///
/// The handoff's list entrance. Rows in a list each get a slightly later
/// [index], so they arrive one after another rather than all at once — which
/// is what makes a list read as having just loaded rather than having always
/// been there.
///
/// The stagger is part of the animation itself (an [Interval] over one longer
/// controller) rather than a timer that starts it later: a pending timer is
/// what a widget test cannot see the end of, and a row disposed before its
/// timer fired would need cancelling by hand.
class FadeRise extends StatefulWidget {
  const FadeRise({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDelay = Duration.zero,
  });

  final Widget child;

  /// Position in its list. Each step waits [_step] longer, up to [_maxSteps]
  /// — past that a long list would keep the last rows invisible for seconds.
  final int index;

  /// Added before the stagger, so a list below other content can wait for
  /// that content to land first.
  final Duration baseDelay;

  static const _step = Duration(milliseconds: 50);
  static const _maxSteps = 12;
  static const _duration = Duration(milliseconds: 400);

  @override
  State<FadeRise> createState() => _FadeRiseState();
}

class _FadeRiseState extends State<FadeRise>
    with SingleTickerProviderStateMixin {
  late final Duration _delay = widget.baseDelay +
      FadeRise._step * widget.index.clamp(0, FadeRise._maxSteps);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _delay + FadeRise._duration,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _delay.inMicroseconds / (_delay + FadeRise._duration).inMicroseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _progress.value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - _progress.value)),
          child: child,
        ),
      ),
    );
  }
}
