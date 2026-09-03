/// When the money arrived, read against the cycle it bought.
///
/// A payment carries three dates that are routinely confused for one another:
/// the day cash changed hands, the day the cycle it paid for begins, and the
/// month that cycle belongs to. Only the first is a fact about the payment;
/// the other two are facts about the *cycle*, and neither may be derived from
/// the payment date. That separation is what stops an early payment dragging a
/// member's billing day forward — see `billing_cycle.dart`, which computes a
/// cycle without ever being shown a payment date at all.
///
/// What this file adds is the missing explanation. Once a payment's date and
/// its cycle are allowed to disagree, the ledger fills with rows that look
/// wrong: a receipt dated 1 September against a cycle running 6 Sep - 6 Oct,
/// filed under September. Nothing is wrong, but the owner has no way to see
/// that. A payment therefore gets a label saying *why* its date sits where it
/// does, and the label goes on the receipt as well as the screen.
///
/// Pure: no clock, no database. The caller passes both dates in.
library;

/// Where a payment's date falls relative to the cycle it bought.
enum PaymentTiming {
  /// Paid before the cycle began, early enough to be worth saying so.
  advance,

  /// Paid on the due day, or close enough either side that nobody would
  /// remark on it.
  onTime,

  /// Paid after the gym would already have chased for it.
  late,
}

extension PaymentTimingLabel on PaymentTiming {
  /// Shown on the payment row and the receipt. [PaymentTiming.onTime] is
  /// deliberately blank: the ordinary case needs no badge, and labelling every
  /// row would bury the two that matter.
  String get label => switch (this) {
        PaymentTiming.advance => 'ADVANCE',
        PaymentTiming.onTime => '',
        PaymentTiming.late => 'LATE',
      };

  bool get isNoteworthy => this != PaymentTiming.onTime;
}

/// How far either side of a cycle's start a payment still counts as on time.
///
/// Both halves are needed. A grace window *after* the due date is obvious. One
/// *before* it is just as necessary: without it, a member paying the day
/// before his due date is labelled ADVANCE, which is noise, and the badge
/// stops meaning anything the moment it appears on half the ledger.
class TimingWindow {
  const TimingWindow({required this.advanceDays, required this.graceDays});

  /// Used when the owner has switched reminders off entirely, so the windows
  /// have nothing to derive from. Three days either way matches the shipped
  /// reminder defaults.
  static const int defaultAdvanceDays = 3;
  static const int defaultGraceDays = 3;

  /// Days before the cycle start that are still on time. A payment earlier
  /// than this is [PaymentTiming.advance].
  final int advanceDays;

  /// Days after the cycle start that are still on time. A payment later than
  /// this is [PaymentTiming.late].
  final int graceDays;

  /// Derives the windows from the reminder offsets the owner already
  /// configured.
  ///
  /// The gym's own schedule is the only honest definition of early and late:
  /// a payment is early once it arrives before the gym would have nudged, and
  /// late once the gym would have chased. Deriving both from
  /// `reminderDaysBefore` / `reminderDaysAfter` means the labels cannot drift
  /// out of step with the messages the member is actually receiving, and the
  /// owner tunes them in one place.
  ///
  /// The *earliest* offset in each list is the one that counts — with
  /// "3,7" days after, the gym first chases on day 3, so day 3 is the last day
  /// nobody would call late.
  factory TimingWindow.fromReminderOffsets({
    required List<int> daysBefore,
    required List<int> daysAfter,
  }) {
    return TimingWindow(
      advanceDays: _earliestPositive(daysBefore) ?? defaultAdvanceDays,
      graceDays: _earliestPositive(daysAfter) ?? defaultGraceDays,
    );
  }

  /// Negative offsets are dropped rather than honoured: a settings row saying
  /// "-5 days before" would otherwise invert the window and label on-time
  /// payments late. Settings are text the owner types, so this takes the same
  /// forgiving line as `parseOffsetDays`.
  static int? _earliestPositive(List<int> offsets) {
    final usable = offsets.where((day) => day >= 0).toList()..sort();
    return usable.isEmpty ? null : usable.first;
  }

  @override
  bool operator ==(Object other) =>
      other is TimingWindow &&
      other.advanceDays == advanceDays &&
      other.graceDays == graceDays;

  @override
  int get hashCode => Object.hash(advanceDays, graceDays);
}

/// Reads [paidAt] against the start of the cycle it paid for.
///
/// Both dates are reduced to calendar days before being compared, so a payment
/// taken at five to midnight on the due date is on time rather than late by a
/// fraction of a day.
///
/// [paidAt] must be handed in on the gym's own clock, because "which day did
/// this payment happen on" is a question about the wall clock at the counter —
/// the same call `currentBillingMonth` makes. [periodStart] is a cycle
/// boundary and so is already a UTC midnight; it is normalised here anyway,
/// since drift hands DateTimes back in local time.
PaymentTiming classifyTiming({
  required DateTime paidAt,
  required DateTime periodStart,
  required TimingWindow window,
}) {
  final paidOn = _calendarDay(paidAt);
  final start = _calendarDay(periodStart.toUtc());

  // Negative is early, positive is late.
  final offsetDays = paidOn.difference(start).inDays;

  if (offsetDays < -window.advanceDays) return PaymentTiming.advance;
  if (offsetDays > window.graceDays) return PaymentTiming.late;
  return PaymentTiming.onTime;
}

/// How far ahead one payment may reach.
///
/// Paying a month ahead is ordinary. Paying a year ahead is legitimate but is
/// also exactly what a mistyped amount looks like, and the difference between
/// the two cannot be told apart from the number alone — so the owner is asked
/// rather than guessed at. Past the ceiling it is refused outright, because no
/// cash gym means to book that much revenue in one transaction and the
/// correction is far more painful than the question.
enum AdvanceAllowance {
  /// Record it without comment.
  allowed,

  /// Legitimate, but worth one confirmation before it is written.
  needsConfirmation,

  /// Beyond anything this gym does. Refused with an explanation.
  refused,
}

/// Cycles beyond the member's current one that a payment may cover before the
/// owner is asked to confirm.
const int freeAdvanceCycles = 1;

/// The hard ceiling on cycles one payment may reach.
const int maxAdvanceCycles = 12;

/// Classifies a payment by how many cycles *beyond the member's current one*
/// it reaches. Arrears do not count — clearing a backlog is never suspicious,
/// and a member paying off four missed months should not be interrogated.
AdvanceAllowance classifyAdvanceReach(int futureCyclesCovered) {
  if (futureCyclesCovered <= freeAdvanceCycles) return AdvanceAllowance.allowed;
  if (futureCyclesCovered <= maxAdvanceCycles) {
    return AdvanceAllowance.needsConfirmation;
  }
  return AdvanceAllowance.refused;
}

/// The furthest date a payment may be dated.
///
/// The owner is buying a *period*, and may date the receipt anywhere inside
/// it. A member who hands over September's fee on the 3rd, for a cycle that
/// starts on the 8th, gets a receipt the owner can date the 8th — his real
/// billing day — so it reads like every other September receipt instead of
/// looking like a payment for the wrong month.
///
/// Bounded by what the money actually buys rather than left open, so a
/// mistyped year cannot date a receipt years out and draw a receipt number
/// from a future year's sequence. [coveredEnd] is the exclusive end of the
/// span being settled, so the last date allowed is the day before it: 8
/// October belongs to the next cycle, not to the one running up to it.
///
/// Never tighter than tomorrow. A payment clearing a backlog covers a span
/// that ended in the past, and the owner must still be able to date it today —
/// a bound derived purely from the span would refuse the only sensible date.
DateTime latestPaymentDate({
  required DateTime? coveredEnd,
  required DateTime today,
}) {
  final tomorrow = _calendarDay(today).add(const Duration(days: 1));
  if (coveredEnd == null) return tomorrow;

  final lastCovered =
      _calendarDay(coveredEnd.toUtc()).subtract(const Duration(days: 1));
  return lastCovered.isAfter(tomorrow) ? lastCovered : tomorrow;
}

/// UTC midnight on the same calendar day, so two dates built from different
/// clocks compare as whole days.
DateTime _calendarDay(DateTime at) => DateTime.utc(at.year, at.month, at.day);
