import 'package:drift/drift.dart';

import '../domain/billing_period.dart';
import 'cycle_pricing_log.dart';
import 'database.dart';
import 'membership_queries.dart';

/// Cycles that exist to say a stretch of months is *not* billed.
///
/// The ledger import writes one per member it brings in, running from the end
/// of their last paid ledger month to their first billing day, worth nothing
/// and stamped settled — see `ImportService._coverUntilFirstBill`. It is how
/// "nobody arrives owing money for months the sheet cannot vouch for" is
/// expressed in the same table as real bills.
///
/// Being a cycle is what makes it work: every lookup asking "is this member
/// covered?" finds it and answers yes, so status, billing maintenance and the
/// reminder queue all leave them alone. It is wrong for exactly one question —
/// the one the Record Payment form asks, which is "what am I billing?". A
/// waiver is the absence of a bill, and resolving a named month to it billed
/// the owner's money against a cycle worth nothing, under the waiver's own
/// start month: picking September on a waiver running 1 August to 7 October
/// read "This settles August 2026", and left September still unbilled.
///
/// The owner is the only person who can say which months inside a waiver a
/// member actually owes — *he did not come in August, so why should he pay; he
/// rejoined in September*. So naming a month takes that month out of the
/// waiver and bills it, and leaves every other month it covers as forgiven as
/// it was.
///
/// This predicate is the whole distinction: [period] is a waiver rather than a
/// bill.
///
/// Zero-cost *and* settled: a cycle genuinely worth nothing that somebody still
/// owes cannot exist, and requiring both means an ordinary cycle can never be
/// mistaken for one — including a cycle re-priced down to zero, which is left
/// unsettled until its balance is recomputed.
bool isWaivedCycle(MembershipPeriod period) =>
    period.expectedAmountMinor == 0 && period.settledAt != null;

/// The cycle a named month is billed as, or null when the month has no bill of
/// its own yet and one has to be opened for it.
///
/// This is what the billing-month rules, the Record Payment form and Edit
/// Payment ask, rather than [periodForMemberContaining] directly: a month
/// covered only by a waiver has no cycle of its own, and saying so is what
/// makes the form offer to open one at the fee the owner names.
///
/// [bounds] is the span that month would be billed over, and decides whether a
/// waiver covering it can give it up — see [waiverCanGiveUp]. A waiver too
/// short stays the answer, exactly as it was before waivers were told apart
/// from bills at all: the alternative is opening a cycle that runs past the
/// waiver's end, over whatever the member's real billing has already put there,
/// which the unique key on `membership_periods` refuses at the worst possible
/// moment — with the owner holding the member's money.
Future<MembershipPeriod?> cycleToBillFor(
  AppDatabase db, {
  required int memberId,
  required PeriodBounds bounds,
}) async {
  // A cycle that *begins* in the month named is that month's bill, whatever
  // else covers the 1st. Cycles are anchored to the member's own billing day,
  // so a member billed on the 7th runs 7 September to 7 October — and asking
  // only which cycle contains 1 September answers with August's, names it
  // "August 2026", and leaves the month the owner picked still owing.
  final starting = await _cycleStartingIn(db, memberId, bounds.periodStart);
  if (starting != null) return starting;

  // Nothing starts there, so the month sits inside a longer cycle: a quarter
  // for a member on a three-month plan, or a waiver. Containment is the right
  // answer for the first and the wrong one for the second.
  final containing = await periodForMemberContaining(
    db,
    memberId: memberId,
    month: bounds.periodStart,
  );
  if (containing == null) return null;
  if (!isWaivedCycle(containing)) return containing;
  return waiverCanGiveUp(containing, bounds) ? null : containing;
}

/// The member's earliest real cycle starting inside the calendar month
/// beginning at [monthStart].
///
/// Waivers are skipped: the few days of one left over between a billed month
/// and the member's first billing day start in that month too, and answering
/// with them would put the money in a cycle worth nothing.
Future<MembershipPeriod?> _cycleStartingIn(
  AppDatabase db,
  int memberId,
  DateTime monthStart,
) async {
  final membershipIds =
      (await allMembershipsFor(db, memberId)).map((m) => m.id).toList();
  if (membershipIds.isEmpty) return null;

  final from = monthStart.toUtc();
  final to = DateTime.utc(from.year, from.month + 1, 1);

  final rows = await (db.select(db.membershipPeriods)
        ..where((p) =>
            p.membershipId.isIn(membershipIds) &
            p.periodStart.isBiggerOrEqualValue(from) &
            p.periodStart.isSmallerThanValue(to))
        ..orderBy([(p) => OrderingTerm(expression: p.periodStart)]))
      .get();

  for (final row in rows) {
    if (!isWaivedCycle(row)) return row;
  }
  return null;
}

/// The waiver covering [month], if the month is covered by one.
Future<MembershipPeriod?> waiverForMonth(
  AppDatabase db, {
  required int memberId,
  required DateTime month,
}) async {
  final containing =
      await periodForMemberContaining(db, memberId: memberId, month: month);
  if (containing == null || !isWaivedCycle(containing)) return null;
  return containing;
}

/// Whether [bounds] can be taken out of [waiver] without disturbing anything
/// beyond it.
///
/// A cycle longer than the waiver — a quarterly plan against a waiver of a few
/// weeks — would have to run past the waiver's end, which is where the member's
/// real billing begins. Refused rather than clamped: shortening a quarter to
/// make it fit would take three months' money for less than three months.
bool waiverCanGiveUp(MembershipPeriod waiver, PeriodBounds bounds) =>
    !bounds.periodStart.isBefore(waiver.periodStart.toUtc()) &&
    !bounds.periodEnd.isAfter(waiver.periodEnd.toUtc());

/// Takes [bounds] out of [waiver] and returns the cycle to bill for it.
///
/// The months the waiver covers either side of [bounds] stay waived, as
/// separate zero-cost settled cycles: the import promised no bill before the
/// member's first billing day, and billing one month out of the middle does not
/// move that promise. Where nothing is left either side, the waiver becomes the
/// bill rather than being replaced by one, so its own history stays attached to
/// it.
///
/// Call only when [waiverCanGiveUp] agrees, and inside the caller's
/// transaction: the waiver is narrowed before the new cycle is inserted, and
/// between those two writes the member is briefly uncovered.
Future<MembershipPeriod> billMonthOutOfWaiver(
  AppDatabase db, {
  required MembershipPeriod waiver,
  required PeriodBounds bounds,
  required Membership membership,
  required int expectedAmountMinor,
  MembershipPlan? plan,
  CyclePricingSource? source,
  String? reason,
  int? actorId,
  DateTime? at,
}) async {
  final waiverStart = waiver.periodStart.toUtc();
  final waiverEnd = waiver.periodEnd.toUtc();
  final start = bounds.periodStart;
  final end = bounds.periodEnd;

  final hasEarlierMonths = waiverStart.isBefore(start);
  final hasLaterDays = waiverEnd.isAfter(end);

  // Nothing is forgiven either side, so there is no waiver left to keep. The
  // row becomes the bill: re-priced from nothing to what the owner named, and
  // un-settled so the payment about to land has something to settle.
  if (!hasEarlierMonths && !hasLaterDays) {
    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(waiver.id)))
        .write(MembershipPeriodsCompanion(
      expectedAmountMinor: Value(expectedAmountMinor),
      settledAt: const Value(null),
    ));

    await recordCyclePricing(
      db,
      membershipPeriodId: waiver.id,
      amountMinor: expectedAmountMinor,
      previousAmountMinor: 0,
      source: source ?? sourceFor(membership),
      planId: membership.planId,
      planPriceMinor: plan?.priceMinor,
      feeOverrideMinor: membership.feeOverrideMinor,
      reason: reason,
      actorId: actorId,
      at: at,
    );

    return (db.select(db.membershipPeriods)
          ..where((p) => p.id.equals(waiver.id)))
        .getSingle();
  }

  // Narrowed before the new cycle goes in: the two can share a start date, and
  // `membership_periods` refuses two cycles starting on the same day under one
  // enrolment.
  if (hasEarlierMonths) {
    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(waiver.id)))
        .write(MembershipPeriodsCompanion(periodEnd: Value(start)));

    if (hasLaterDays) {
      final remainder = await db.into(db.membershipPeriods).insertReturning(
            MembershipPeriodsCompanion.insert(
              membershipId: waiver.membershipId,
              periodStart: end,
              periodEnd: waiverEnd,
              expectedAmountMinor: 0,
              settledAt: Value(end),
            ),
          );
      await recordCyclePricing(
        db,
        membershipPeriodId: remainder.id,
        amountMinor: 0,
        source: CyclePricingSource.ledgerImport,
        reason: 'Still covered by the ledger import: billing one month out of '
            'a waiver does not move the day the member is first billed.',
        actorId: actorId,
        at: at,
      );
    }
  } else {
    // The month billed is the waiver's own first, so the waiver simply starts
    // where it ends. Moving the row rather than replacing it keeps the import's
    // reason attached to the days still forgiven.
    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(waiver.id)))
        .write(MembershipPeriodsCompanion(periodStart: Value(end)));
  }

  final period = await db.into(db.membershipPeriods).insertReturning(
        MembershipPeriodsCompanion.insert(
          membershipId: membership.id,
          periodStart: start,
          periodEnd: end,
          expectedAmountMinor: expectedAmountMinor,
        ),
      );

  await recordCycleOpened(
    db,
    membershipPeriodId: period.id,
    amountMinor: expectedAmountMinor,
    membership: membership,
    plan: plan,
    source: source,
    reason: reason,
    actorId: actorId,
    at: at,
  );

  return period;
}
