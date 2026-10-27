import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import '../domain/inactivity.dart';

/// How often the deadline is looked at between inputs. Only bounds how late
/// past two minutes the lock lands; the deadline itself is a timestamp.
const _checkEvery = Duration(seconds: 1);

/// How often activity is written to the session row. Coarse on purpose — the
/// database is the gym's ledger, not a heartbeat log. The row can only lag
/// behind, so a restart errs towards asking for the password, never away.
const _recordEvery = Duration(seconds: 15);

/// Locks the app after [inactivityLockAfter] without input.
///
/// Sits in `MaterialApp.builder`, above the Navigator, so a click inside a
/// dialog or a pushed screen counts as much as one on the dashboard. Counts
/// clicks, taps, the scroll wheel, trackpad scrolling and key presses. Pointer
/// movement alone does not count: a mouse nudged by a passing elbow is not
/// somebody using the app. Background work — reminders, the update check,
/// database watchers — never comes through here, so it cannot hold the lock
/// off.
///
/// Inert while nobody is signed in, so the login form is never interrupted.
/// Built afresh for every sign-in (the app is keyed on the signed-in user), so
/// each session starts its own clock.
class IdleLock extends StatefulWidget {
  const IdleLock({super.key, required this.child, this.clock});

  final Widget child;

  /// For tests. Defaults to the wall clock.
  final DateTime Function()? clock;

  @override
  State<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends State<IdleLock> {
  InactivityMonitor? _monitor;
  Timer? _ticker;
  AppLifecycleListener? _lifecycle;
  DateTime? _recordedAt;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthBloc>();
    if (auth.state.user == null) return;

    _monitor = InactivityMonitor(
      onExpired: _lock,
      lastActivity: auth.restoredActiveAt,
      clock: _now,
    );
    _ticker = Timer.periodic(_checkEvery, (_) => _monitor?.check());
    // Focus coming back, or the window being restored, is the moment a
    // computer that slept is first looked at again.
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _monitor?.check());
    // Early, so it runs before the focused widget sees the key and a late
    // press can be swallowed rather than merely noticed.
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle?.dispose();
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    super.dispose();
  }

  void _lock() {
    _ticker?.cancel();
    if (mounted) context.read<AuthBloc>().add(const AuthLockedForInactivity());
  }

  /// False when the input arrived after the deadline and locked the app.
  bool _activity() {
    final monitor = _monitor;
    if (monitor == null) return true;
    if (!monitor.recordActivity()) return false;

    final now = monitor.lastActivity;
    final recorded = _recordedAt;
    if (recorded == null || now.difference(recorded) >= _recordEvery) {
      _recordedAt = now;
      unawaited(context.read<AuthBloc>().recordActivity(now));
    }
    return true;
  }

  void _onPointer(PointerEvent event) {
    if (_activity()) return;
    // Too late: the app is locking. Cancelling the pointer stops the tap
    // completing on release, so the button under it does not act on the way
    // out.
    GestureBinding.instance.cancelPointer(event.pointer);
  }

  /// A late key press is swallowed for the same reason: Enter must not
  /// confirm a dialog that is about to disappear.
  KeyEventResult _onKey(KeyEvent event) {
    if (event is KeyUpEvent || _activity()) return KeyEventResult.ignored;
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_monitor == null) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerSignal: _onPointer,
      onPointerPanZoomStart: _onPointer,
      child: widget.child,
    );
  }
}
