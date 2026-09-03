/// When a payment reminder is owed, and whether now is a reasonable moment to
/// send it.
///
/// This app has no server and no cron: nothing runs while it is closed. So
/// "automatic" can only mean "the next time the counter machine has the app
/// open", and the schedule has to cope with being asked days late. Two rules
/// come out of that and are the reason this file exists:
///
///  1. **Only the most recent owed reminder is sent.** If the gym was shut for
///     a week, a member does not deserve the three-days-before note, the
///     on-the-day note and the overdue note arriving together. The earlier ones
///     are recorded as superseded so they can never fire late.
///  2. **Nothing is sent outside the gym's own hours.** The owner opening the
///     app at half past six in the morning must not wake the membership.
///
/// Pure: the caller passes the day and the clock in.
library;

enum ReminderStage {
  /// Before the money falls due — a nudge, not a chase.
  beforeDue,

  /// On the day itself.
  onDue,

  /// After the due date passed with the cycle still unsettled.
  overdue,
}

extension ReminderStageLabel on ReminderStage {
  String get label => switch (this) {
        ReminderStage.beforeDue => 'Upcoming',
        ReminderStage.onDue => 'Due today',
        ReminderStage.overdue => 'Overdue',
      };
}

/// Identifies one scheduled reminder for one cycle.
///
/// The stage alone is not enough: "three days overdue" and "seven days
/// overdue" are two separate messages, and the pair is what the unique index on
/// `PaymentReminders` is built from.
class ReminderKey {
  const ReminderKey(this.stage, this.offsetDays);

  final ReminderStage stage;

  /// Days away from the due date. Always non-negative — which side of the due
  /// date it falls on is carried by [stage].
  final int offsetDays;

  @override
  bool operator ==(Object other) =>
      other is ReminderKey &&
      other.stage == stage &&
      other.offsetDays == offsetDays;

  @override
  int get hashCode => Object.hash(stage, offsetDays);

  @override
  String toString() => '${stage.name}+$offsetDays';
}

/// A reminder and the calendar day it became owed.
class ScheduledReminder {
  const ScheduledReminder({required this.key, required this.on});

  final ReminderKey key;

  /// UTC midnight of the day this reminder was meant to go out.
  final DateTime on;

  ReminderStage get stage => key.stage;
  int get offsetDays => key.offsetDays;
}

/// What to do about one cycle right now.
class ReminderDecision {
  const ReminderDecision({this.send, this.superseded = const []});

  const ReminderDecision.nothing() : send = null, superseded = const [];

  /// The one reminder to send, or null when none is owed.
  final ScheduledReminder? send;

  /// Reminders whose moment passed unsent while the app was closed. Recorded
  /// as skipped so they never arrive out of order later.
  final List<ScheduledReminder> superseded;

  bool get hasWork => send != null || superseded.isNotEmpty;
}

/// The owner's reminder configuration.
class ReminderSettings {
  const ReminderSettings({
    this.daysBefore = const [3],
    this.onDueDate = true,
    this.daysAfter = const [3, 7],
    this.autoSend = false,
    this.sendFromHour = 9,
    this.sendUntilHour = 21,
    this.maxPerRun = 25,
  });

  /// How many days before the due date to nudge. Empty means never.
  final List<int> daysBefore;

  final bool onDueDate;

  /// How many days after the due date to chase, for a cycle still unsettled.
  final List<int> daysAfter;

  /// Off by default. Nothing leaves this app unattended until the owner says
  /// so in Settings.
  final bool autoSend;

  /// The gym's own hours, on the wall clock, in 0–23.
  final int sendFromHour;
  final int sendUntilHour;

  /// A ceiling on one automatic run, so reopening the app after a fortnight
  /// shut does not fire off the whole roster in one burst.
  final int maxPerRun;

  bool get sendsAnything =>
      daysBefore.isNotEmpty || onDueDate || daysAfter.isNotEmpty;
}

/// Which reminder, if any, is owed for a cycle due on [dueDate] as of [today].
///
/// [alreadyHandled] is every key already sent, skipped or failed for this
/// cycle, so nothing is offered twice.
ReminderDecision decideReminder({
  required ReminderSettings settings,
  required DateTime dueDate,
  required DateTime today,
  Set<ReminderKey> alreadyHandled = const {},
}) {
  final due = _dayStart(dueDate);
  final on = _dayStart(today);

  final owed = <ScheduledReminder>[];

  void consider(ReminderKey key, DateTime when) {
    if (alreadyHandled.contains(key)) return;
    // Owed once its day has arrived; a moment still in the future is not.
    if (when.isAfter(on)) return;
    owed.add(ScheduledReminder(key: key, on: when));
  }

  for (final days in settings.daysBefore) {
    if (days <= 0) continue;
    consider(
      ReminderKey(ReminderStage.beforeDue, days),
      due.subtract(Duration(days: days)),
    );
  }

  if (settings.onDueDate) {
    consider(const ReminderKey(ReminderStage.onDue, 0), due);
  }

  for (final days in settings.daysAfter) {
    if (days <= 0) continue;
    consider(
      ReminderKey(ReminderStage.overdue, days),
      due.add(Duration(days: days)),
    );
  }

  if (owed.isEmpty) return const ReminderDecision.nothing();

  // Latest moment wins. Ties break towards the later stage, so a due-date
  // reminder beats a nudge scheduled for the same day.
  owed.sort((a, b) {
    final byDay = a.on.compareTo(b.on);
    if (byDay != 0) return byDay;
    return a.stage.index.compareTo(b.stage.index);
  });

  return ReminderDecision(
    send: owed.last,
    superseded: owed.sublist(0, owed.length - 1),
  );
}

/// Whether [localNow] falls inside the gym's sending hours.
///
/// Read on the wall clock deliberately: whether it is a civil hour to message
/// somebody is a question about the clock on the gym's wall, not about UTC.
bool withinSendingWindow(DateTime localNow, ReminderSettings settings) {
  final from = settings.sendFromHour;
  final until = settings.sendUntilHour;

  // An empty or full window is read as "any time" rather than "never": a
  // misconfigured pair must not silently stop every reminder for good.
  if (from == until) return true;

  final hour = localNow.hour;
  if (from < until) return hour >= from && hour < until;

  // Wraps past midnight, e.g. 22:00 to 06:00.
  return hour >= from || hour < until;
}

/// Parses a stored offset list such as "3,7".
///
/// Stored as text rather than as columns so the owner can have two overdue
/// reminders, or none, without a schema migration each time — the same reason
/// `themeMode` is text. Junk, blanks, negatives and duplicates are dropped
/// rather than throwing: this parses a settings row, and a bad row must not be
/// able to stop the app opening.
List<int> parseOffsetDays(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];

  final days = <int>{};
  for (final part in raw.split(',')) {
    final parsed = int.tryParse(part.trim());
    if (parsed == null || parsed <= 0) continue;
    days.add(parsed);
  }

  return days.toList()..sort();
}

/// Renders an offset list back for storage.
String formatOffsetDays(List<int> days) =>
    (days.where((d) => d > 0).toSet().toList()..sort()).join(',');

DateTime _dayStart(DateTime at) {
  final on = at.toUtc();
  return DateTime.utc(on.year, on.month, on.day);
}
