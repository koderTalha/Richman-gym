import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/reminder_service.dart';

/// How often the automatic reminder run is tried again while the app stays
/// open.
///
/// It used to be tried once per launch, and only then: a launch before sending
/// hours sent nothing all day, and on the 1st — when most legacy members fall
/// due at once — everything past the per-run cap waited for the next launch
/// and was by then superseded. Hourly is often enough that a morning launch
/// still sends once the gym opens, and rare enough that the per-run cap still
/// means something. Every run is hours-aware, capped and single-flight; see
/// `ReminderService.runAutoSend`.
const reminderRunInterval = Duration(hours: 1);

/// Runs the automatic reminders every [reminderRunInterval] while the app is
/// open, whether or not anybody is signed in.
///
/// Sits above the sign-in switch rather than inside the shell. The inactivity
/// lock tears the shell down after two idle minutes, and a timer living there
/// would leave the gym's reminders unsent for as long as the desk sat quiet —
/// most of the day. The launch run already happens before anyone signs in, so
/// this is the same rule kept for the rest of the day.
class AutomaticReminders extends StatefulWidget {
  const AutomaticReminders({super.key, required this.child});

  final Widget child;

  @override
  State<AutomaticReminders> createState() => _AutomaticRemindersState();
}

class _AutomaticRemindersState extends State<AutomaticReminders> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(reminderRunInterval, (_) => _run());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Not awaited: a run is up to a full per-run cap of WhatsApp calls. Read as
  /// nullable so a tree built without the service — in a test — simply has no
  /// automatic run.
  void _run() {
    if (!mounted) return;
    final reminders = context.read<ReminderService?>();
    if (reminders == null) return;
    unawaited(reminders.runAutoSend());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
