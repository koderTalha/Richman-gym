import 'payment_settlement.dart';

/// How long a month may go unpaid, counted from its due date, before the
/// member is taken to have stopped coming — unless the owner picks another of
/// [inactivityGraceDayChoices].
///
/// Calendar days from the day the cycle fell due — its start, since the gym is
/// paid in advance. A member due on 1 October is deactivated on 10 November.
const paymentInactivityGraceDays = 40;

/// The thresholds the owner can choose from.
///
/// Capped at 55 by the one-month lookback, not by taste. The month judged is
/// the most recent one that has ended, and its due date is never more than
/// about 59 days back — a January bill stops being judged on 1 March, when
/// February ends. A longer threshold would simply never be reached.
const inactivityGraceDayChoices = [35, 40, 45, 50, 55];

/// How far ahead the "deactivating soon" list looks.
const inactivityWarningDays = 7;

/// Pakistan Standard Time, which has no daylight saving.
///
/// Fixed rather than read off the computer's clock. Whether 40 days have passed
/// is a question about the gym's calendar, and a machine whose timezone was
/// set to something else would otherwise deactivate members a day early or
/// late.
const gymUtcOffset = Duration(hours: 5);

/// The gym's calendar day at [instant], as a UTC midnight — the same
/// convention cycle boundaries are stored in.
///
/// 19:00 UTC on 9 November is already 10 November in Lahore.
DateTime gymDateOf(DateTime instant) {
  final local = instant.toUtc().add(gymUtcOffset);
  return DateTime.utc(local.year, local.month, local.day);
}

/// Why a member past the deadline is left for the owner rather than
/// deactivated.
enum InactivityReviewReason {
  /// Something has been paid towards the unpaid month, or a later one. Money
  /// is still coming in, so the balance may yet be collected, and writing it
  /// off would be the app's guess.
  partPaid,

  /// The member has never paid for a single month. Nothing tells a member who
  /// left apart from one who never really started — or one imported from the
  /// ledger whose first bill under the app was this one.
  neverPaid,
}

extension InactivityReviewReasonLabel on InactivityReviewReason {
  String get label => switch (this) {
        InactivityReviewReason.partPaid => 'Part-paid',
        InactivityReviewReason.neverPaid => 'Has never paid',
      };
}

/// Where a member stands against the missed-payment rule.
sealed class PaymentInactivity {
  const PaymentInactivity();
}

/// Up to date, paid ahead, or with no month old enough to judge.
class PaymentInactivityNone extends PaymentInactivity {
  const PaymentInactivityNone();
}

/// A month is unpaid, and the 40 days have not run out yet.
class PaymentInactivityGrace extends PaymentInactivity {
  const PaymentInactivityGrace({
    required this.firstMissedDue,
    required this.deadline,
  });

  final DateTime firstMissedDue;

  /// The day the member is deactivated if nothing is paid before it.
  final DateTime deadline;
}

/// Past the deadline, but for a reason the owner has to look at.
class PaymentInactivityReview extends PaymentInactivity {
  const PaymentInactivityReview({
    required this.reason,
    required this.firstMissedDue,
    required this.deadline,
  });

  final InactivityReviewReason reason;
  final DateTime firstMissedDue;
  final DateTime deadline;
}

/// Past the deadline with nothing paid: deactivate, and write off [toWaive].
class PaymentInactivityLapsed extends PaymentInactivity {
  const PaymentInactivityLapsed({
    required this.firstMissedDue,
    required this.deadline,
    required this.lastPaidUntil,
    required this.toWaive,
    required this.olderArrearsMinor,
  });

  final DateTime firstMissedDue;
  final DateTime deadline;

  /// End of the last paid cycle before [firstMissedDue], if any.
  final DateTime? lastPaidUntil;

  /// The unpaid month and every unpaid bill after it, oldest first.
  final List<SettleableCycle> toWaive;

  /// Still owing on months before [firstMissedDue]. Left owing: those are
  /// arrears from before this lapse, not part of it.
  final int olderArrearsMinor;

  int get waivedMinor =>
      toWaive.fold(0, (sum, cycle) => sum + cycle.expectedMinor);
}

/// Judges one member's billing against the missed-payment rule on [today], a
/// day on the gym's calendar (see [gymDateOf]).
///
/// Only the member's most recent cycle that has **already ended** is judged.
/// In November that is October: if it is unpaid and 40 days have passed since
/// it fell due, the member has stopped coming. Older months are never looked
/// at to start the count — a member owing for March out of last year's ledger
/// is in arrears, which is a different thing and stays exactly as it is. This
/// is the owner's rule: the month just gone is as far back as it looks.
///
/// A member who has paid anything towards that month or a later one is still
/// paying, and is not judged on the older month they skipped.
///
/// [cycles] are the member's, oldest first, as `MemberBilling.cycles` has them.
/// Free cycles — the ledger import's cover, earlier write-offs — are neither a
/// bill nor a payment and are ignored.
PaymentInactivity assessPaymentInactivity({
  required List<SettleableCycle> cycles,
  required DateTime today,
  int graceDays = paymentInactivityGraceDays,
}) {
  final bills = [
    for (final c in cycles)
      if (c.expectedMinor > 0) c,
  ];

  SettleableCycle? judged;
  for (final c in bills) {
    if (c.end.isAfter(today)) continue;
    if (judged == null || c.end.isAfter(judged.end)) judged = c;
  }
  // Nothing has ended yet: a new member's first month, or one paid ahead.
  if (judged == null || judged.isSettled) return const PaymentInactivityNone();

  final missed = judged;
  final episode = [
    for (final c in bills)
      if (!c.start.isBefore(missed.start)) c,
  ];

  // Paid a later month while this one sits unpaid. They are still coming; the
  // gap is arrears.
  if (episode.any((c) => c != missed && c.collectedMinor > 0)) {
    return const PaymentInactivityNone();
  }

  final deadline = missed.start.add(Duration(days: graceDays));
  // Day arithmetic on UTC midnights: no daylight saving can shift it.
  if (today.isBefore(deadline)) {
    return PaymentInactivityGrace(
        firstMissedDue: missed.start, deadline: deadline);
  }

  if (missed.collectedMinor > 0) {
    return PaymentInactivityReview(
      reason: InactivityReviewReason.partPaid,
      firstMissedDue: missed.start,
      deadline: deadline,
    );
  }

  final earlier = [
    for (final c in bills)
      if (c.start.isBefore(missed.start)) c,
  ];
  final paidEarlier = earlier.where((c) => c.collectedMinor > 0).toList();
  if (paidEarlier.isEmpty) {
    return PaymentInactivityReview(
      reason: InactivityReviewReason.neverPaid,
      firstMissedDue: missed.start,
      deadline: deadline,
    );
  }

  DateTime? lastPaidUntil;
  for (final c in paidEarlier) {
    if (c.isSettled && (lastPaidUntil == null || c.end.isAfter(lastPaidUntil))) {
      lastPaidUntil = c.end;
    }
  }

  return PaymentInactivityLapsed(
    firstMissedDue: missed.start,
    deadline: deadline,
    lastPaidUntil: lastPaidUntil,
    toWaive: episode,
    olderArrearsMinor:
        earlier.fold(0, (sum, c) => sum + c.outstandingMinor),
  );
}
