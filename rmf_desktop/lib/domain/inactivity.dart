/// How long the app may sit untouched before it locks and asks for the
/// password again.
///
/// The gym's screen faces the floor, and the app holds every member's phone
/// number and every payment taken. Two minutes is long enough to take a
/// payment at the counter and short enough that walking away from the desk
/// does not leave it open to whoever walks up next.
const inactivityLockAfter = Duration(milliseconds: 120000);

/// Decides when the app has sat idle for too long.
///
/// Works from the wall-clock time of the last activity rather than a countdown,
/// because a countdown stops while the computer sleeps and a throttled timer
/// fires late: the owner closing the laptop for an hour must come back to the
/// login screen, not to a lock that still has a minute to run. Whoever owns
/// this calls [check] as often as it likes — on a ticker, when the window comes
/// back to the front — and [recordActivity] on genuine input. Nothing else
/// moves the deadline.
class InactivityMonitor {
  InactivityMonitor({
    required void Function() onExpired,
    this.timeout = inactivityLockAfter,
    DateTime? lastActivity,
    DateTime Function()? clock,
  })  : _onExpired = onExpired,
        _clock = clock ?? DateTime.now {
    _lastActivity = lastActivity ?? _clock();
  }

  final void Function() _onExpired;
  final Duration timeout;
  final DateTime Function() _clock;

  late DateTime _lastActivity;
  bool _expired = false;

  DateTime get lastActivity => _lastActivity;

  /// True once the deadline has passed. Never goes back to false: a fresh
  /// sign-in gets a fresh monitor.
  bool get expired => _expired;

  /// Moves the deadline on, unless it has already passed.
  ///
  /// Returns false when the input came too late to count — the first click
  /// after waking the computer, say. That click locks the app instead, so the
  /// button under it must not be allowed to act.
  bool recordActivity() {
    if (check()) return false;
    _lastActivity = _clock();
    return true;
  }

  /// Locks if the deadline has passed. Returns whether the app is locked.
  ///
  /// [onExpired] runs once, however many times this is called afterwards.
  bool check() {
    if (_expired) return true;

    final now = _clock();
    // The clock was put back. Measuring from a time in the future would hold
    // the lock off until the clock caught up, possibly for hours, so the idle
    // spell restarts from now instead.
    if (now.isBefore(_lastActivity)) _lastActivity = now;

    if (now.difference(_lastActivity) < timeout) return false;
    _expired = true;
    _onExpired();
    return true;
  }
}
