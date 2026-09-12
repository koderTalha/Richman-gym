import 'dart:math' as math;

/// Anchored, contiguous billing cycles.
///
/// A cycle is `[start, end)`. Its end is the start plus the plan's length in
/// months, with the day pinned to the membership's **anchor day** — the day of
/// the month the member is billed on — and clamped to the last day of a month
/// too short to hold it.
///
/// The next cycle begins exactly where the previous one ended, which means
/// contiguity and the anchor are the same fact. Nothing here takes a payment
/// date, and that is the point: no payment can shorten a member's cycle and no
/// lateness can lengthen one, so twelve monthly cycles a year stay twelve.
///
/// The anchor is *carried*, never read back off the previous boundary. That is
/// what stops February permanently demoting a member billed on the 31st:
/// 31 Jan → 28 Feb → **31** Mar, rather than sliding to the 28th for good.
///
/// Every boundary is a UTC midnight, matching how `MembershipPeriods` stores
/// them and what `dates.dart` documents about calendar days. Nothing in here
/// reads the clock — callers pass the day in.

/// The highest day a month can have, and so the highest meaningful anchor.
const int maxAnchorDay = 31;

/// How far either side of the natural end a re-anchored cycle will look. One
/// month each way is enough to find the nearest occurrence of any anchor day.
const int _anchorSearchMonths = 1;

/// One billing cycle: start inclusive, end exclusive.
class BillingCycle {
  const BillingCycle({
    required this.start,
    required this.end,
    this.isTransition = false,
  });

  /// UTC midnight, inclusive.
  final DateTime start;

  /// UTC midnight, exclusive. A cycle ending 6 Nov covers up to and including
  /// 5 Nov.
  final DateTime end;

  /// True when this cycle exists to move the member onto a new anchor day, so
  /// it is deliberately not a whole number of months. The UI says so before
  /// the owner confirms a change of billing day.
  final bool isTransition;

  /// The day the money is owed.
  ///
  /// A cycle's own start: the gym is paid in advance, so the fee for
  /// 6 Oct – 6 Nov falls due on 6 October. "When is this member next due" is
  /// therefore the start of their first unsettled cycle.
  DateTime get dueDate => start;

  int get lengthInDays => end.difference(start).inDays;

  bool contains(DateTime at) {
    final on = at.toUtc();
    return !start.isAfter(on) && on.isBefore(end);
  }

  @override
  String toString() => 'BillingCycle($start → $end)';

  @override
  bool operator ==(Object other) =>
      other is BillingCycle &&
      other.start == start &&
      other.end == end &&
      other.isTransition == isTransition;

  @override
  int get hashCode => Object.hash(start, end, isTransition);
}

/// [from] plus [months], with the day pinned to [anchorDay] and clamped to the
/// last day of the target month when that month cannot hold it.
DateTime addMonthsClamped(
  DateTime from,
  int months, {
  required int anchorDay,
}) {
  final at = from.toUtc();
  // Month arithmetic through the constructor, which normalises overflow, so
  // December + 1 is January of the next year without a special case.
  final target = DateTime.utc(at.year, at.month + months, 1);
  return _anchorIn(target.year, target.month, anchorDay);
}

/// The next cycle for a membership whose previous cycle ended at [previousEnd].
///
/// When that boundary already sits on [anchorDay] this is a plain roll forward.
/// When it does not — because the owner has changed the member's billing day —
/// the cycle returned is a one-off transition onto the new anchor.
BillingCycle cycleAfter({
  required DateTime previousEnd,
  required int durationMonths,
  required int anchorDay,
}) {
  final start = _dayStart(previousEnd);
  final anchor = _clampAnchor(anchorDay);

  if (_isOnAnchor(start, anchor)) {
    return BillingCycle(
      start: start,
      end: addMonthsClamped(start, durationMonths, anchorDay: anchor),
    );
  }

  return _transitionFrom(
    start: start,
    durationMonths: durationMonths,
    anchorDay: anchor,
  );
}

/// The cycle that contains [today], anchored on [anchorDay], with no
/// reference to any history.
///
/// Used the one time a member's *first-ever* cycle has to be conjured with
/// nothing to build on — [BillingMaintenance] filling a gap for a member who
/// has never had a cycle recorded at all. Deliberately rooted in today's
/// calendar month rather than walked forward from the day the member joined:
/// a monthly or quarterly plan left untouched for years must not backfill
/// every missed cycle since joining, which is debt the owner never recorded.
/// Reconstructing real history, when there is any, is what [cycleAfter] is
/// for.
///
/// Rooting it in the calendar month means backing up to the anchor's previous
/// occurrence whenever today falls earlier in the month than the anchor —
/// correct for somebody on the books for years, and wrong for somebody who
/// joined this month. A member signed up on the 6th, in an app opened on the
/// 3rd, was handed a cycle for 6 Dec – 6 Jan: a month that ended the day they
/// walked in, unpaid, so they read DUE before they had been a member for an
/// hour. With `payDay == joinDay` it cost them a thirteenth cycle for the
/// twelve months they lived, and every payment after it landed a month behind
/// where the owner thought it was going.
///
/// [joiningDate] is therefore a floor: there was no membership to bill before
/// it, so a start earlier than it means this is the member's opening cycle and
/// [firstCycleFor] is what builds it.
BillingCycle cycleContaining({
  required DateTime today,
  required int anchorDay,
  required int durationMonths,
  required DateTime joiningDate,
}) {
  final at = _dayStart(today);
  final anchor = _clampAnchor(anchorDay);
  final joined = _dayStart(joiningDate);

  var start = _anchorIn(at.year, at.month, anchor);
  if (start.isAfter(at)) {
    start = _anchorIn(at.year, at.month - 1, anchor);
  }

  // Never bill time the member had not joined for.
  if (start.isBefore(joined)) {
    return firstCycleFor(
      joiningDate: joined,
      durationMonths: durationMonths,
      anchorDay: anchor,
    );
  }

  return BillingCycle(
    start: start,
    end: addMonthsClamped(start, durationMonths, anchorDay: anchor),
  );
}

/// A new membership's opening cycle.
///
/// It starts the day the member joined, and unless told otherwise that day
/// becomes their anchor — a member who signs up on the 14th is billed on the
/// 14th. Passing [anchorDay] bills them elsewhere instead, which makes the
/// opening cycle a transition onto that day.
BillingCycle firstCycleFor({
  required DateTime joiningDate,
  required int durationMonths,
  int? anchorDay,
}) {
  final start = _dayStart(joiningDate);
  final anchor = _clampAnchor(anchorDay ?? start.day);

  if (_isOnAnchor(start, anchor)) {
    return BillingCycle(
      start: start,
      end: addMonthsClamped(start, durationMonths, anchorDay: anchor),
    );
  }

  return _transitionFrom(
    start: start,
    durationMonths: durationMonths,
    anchorDay: anchor,
  );
}

/// A membership's anchor day.
///
/// The stored column when it is set; otherwise the day the membership's latest
/// cycle starts; otherwise the day the member joined.
///
/// That middle fallback is what makes this release a no-op on upgrade. Every
/// cycle recorded before it starts on the 1st of a month, so a membership with
/// no anchor column reads as anchored to the 1st and its cycles keep landing
/// exactly where they land today — with no rows written and no member's due
/// date moving underneath them.
int resolveAnchorDay({
  required int? billingAnchorDay,
  required DateTime? latestPeriodStart,
  required DateTime joiningDate,
}) {
  if (billingAnchorDay != null) return _clampAnchor(billingAnchorDay);
  // UTC before reading .day: drift hands DateTimes back in local time, and in
  // any negative-offset timezone a boundary stored as the 1st reads as the last
  // day of the month before.
  if (latestPeriodStart != null) return latestPeriodStart.toUtc().day;
  return joiningDate.toUtc().day;
}

/// The occurrence of [anchorDay] nearest to [naturalEnd] that still falls
/// after [after].
///
/// Used when a cycle has to land on a new anchor. Simply taking the next
/// occurrence can add most of a month, and taking the previous one can leave a
/// cycle a couple of days long; choosing whichever is nearer to where the cycle
/// would naturally have ended keeps a transition within about a fortnight of a
/// normal cycle in either direction.
DateTime nearestAnchorTo(
  DateTime naturalEnd, {
  required int anchorDay,
  required DateTime after,
}) {
  final natural = _dayStart(naturalEnd);
  final floor = _dayStart(after);
  final anchor = _clampAnchor(anchorDay);

  final candidates = <DateTime>[
    for (var offset = -_anchorSearchMonths;
        offset <= _anchorSearchMonths;
        offset++)
      _anchorIn(natural.year, natural.month + offset, anchor),
  ].where((candidate) => candidate.isAfter(floor)).toList();

  // Cannot happen for any anchor in 1..31, because the occurrence a month past
  // the natural end is always past it. Keeping the natural end rather than
  // throwing means a corrupt anchor cannot wedge the billing roll.
  if (candidates.isEmpty) return natural;

  candidates.sort((a, b) {
    final byDistance = (a.difference(natural)).abs().compareTo(
          (b.difference(natural)).abs(),
        );
    // Ties go to the earlier date, so the answer is stable rather than
    // depending on the order the candidates happened to be built in.
    return byDistance != 0 ? byDistance : a.compareTo(b);
  });

  return candidates.first;
}

BillingCycle _transitionFrom({
  required DateTime start,
  required int durationMonths,
  required int anchorDay,
}) {
  // Where the cycle would have ended if the anchor had not moved, which is
  // what "nearest" is measured against.
  final natural = addMonthsClamped(start, durationMonths, anchorDay: start.day);

  return BillingCycle(
    start: start,
    end: nearestAnchorTo(natural, anchorDay: anchorDay, after: start),
    isTransition: true,
  );
}

/// Whether [at] already sits on [anchorDay].
///
/// A boundary clamped by a short month counts: a member anchored to the 31st
/// whose cycle ended 28 February is exactly where they should be, not
/// mid-transition, and their next cycle must run to 31 March.
bool _isOnAnchor(DateTime at, int anchorDay) {
  if (at.day == anchorDay) return true;
  final lastDay = _daysInMonth(at.year, at.month);
  return anchorDay > lastDay && at.day == lastDay;
}

/// [anchorDay] in the given month, clamped to that month's last day. The month
/// may be out of range; the constructor normalises it.
DateTime _anchorIn(int year, int month, int anchorDay) {
  final normalised = DateTime.utc(year, month, 1);
  final lastDay = _daysInMonth(normalised.year, normalised.month);
  return DateTime.utc(
    normalised.year,
    normalised.month,
    math.min(anchorDay, lastDay),
  );
}

/// Day zero of the following month is the last day of this one.
int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

int _clampAnchor(int day) => day.clamp(1, maxAnchorDay);

/// UTC midnight on the same calendar day, so a cycle is always a whole number
/// of days and two boundaries built from different times compare equal.
DateTime _dayStart(DateTime at) {
  final on = at.toUtc();
  return DateTime.utc(on.year, on.month, on.day);
}
