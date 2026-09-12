import 'package:drift/drift.dart';

import 'database.dart';
import 'membership_queries.dart';

/// Carrying a fee change through to the bills that have not been issued yet.
///
/// A billing cycle snapshots its fee when it opens
/// ([MembershipPeriods.expectedAmountMinor]), which is what stops a price rise
/// from rewriting months the member has already paid for. That rule was
/// applied to *every* cycle, including ones nobody had put a rupee into, and
/// that is what produced the gym's "payment is always due" report:
///
/// A member's March cycle opened at 1500. The owner raised the fee to 2500 and
/// collected 2500. Only 1500 of it fitted into March, so the remaining 1000
/// spilled forward under the arrears-first allocation rule, opened April's
/// cycle early and part-paid it. A cycle row is a debt, so from that moment
/// the member had one more cycle open than they had been asked to pay for, and
/// every later payment cleared the previous shortfall while creating a new
/// one. They paid 2500 every month, in full and on time, and the app showed
/// them owing 1500 for ever.
///
/// An unpaid cycle is not history. It is a bill that has not been issued, and
/// it should carry whatever the member's fee is now.
///
/// Three things are deliberately left alone, because each would rewrite
/// something the member or the owner has already acted on:
///
///   * a **settled** cycle — reopening a closed debt,
///   * a cycle with **any money against it**, part-payment included: the
///     member paid that against the old price, and moving the price
///     afterwards backdates the rise,
///   * a cycle that has **already ended**: arrears were incurred at the price
///     in force at the time, and a member who owes January must still owe
///     January's fee, not today's.
///
/// Nothing here reads the clock — callers pass [now] in, the same bargain
/// `BillingMaintenance` and `ReminderService` make.

/// Re-prices [memberId]'s not-yet-issued cycles to their current fee.
///
/// Returns how many cycles changed, which is zero for the overwhelmingly
/// common case of a fee that has not moved.
Future<int> repriceOpenCycles(
  AppDatabase db, {
  required int memberId,
  DateTime? now,
}) async {
  final member = await (db.select(db.members)
        ..where((m) => m.id.equals(memberId)))
      .getSingleOrNull();
  // Somebody who has left the gym is not re-billed. The same call
  // `BillingMaintenance` makes before rolling anyone's cycle forward.
  if (member == null || member.deactivatedAt != null) return 0;

  final membership = await openMembershipFor(db, memberId);
  if (membership == null) return 0;

  final plan = await (db.select(db.membershipPlans)
        ..where((p) => p.id.equals(membership.planId)))
      .getSingleOrNull();
  if (plan == null) return 0;

  final feeMinor = membership.feeOverrideMinor ?? plan.priceMinor;

  final at = (now ?? DateTime.now()).toUtc();
  // Drift hands DateTimes back in local time, so normalise both sides before
  // comparing — in any negative-offset timezone a boundary stored as the 1st
  // reads as the last day of the month before.
  final today = DateTime.utc(at.year, at.month, at.day);

  final candidates = [
    for (final period in await periodsForMember(db, memberId))
      if (period.settledAt == null &&
          period.expectedAmountMinor != feeMinor &&
          period.periodEnd.toUtc().isAfter(today))
        period,
  ];
  if (candidates.isEmpty) return 0;

  final ids = [for (final period in candidates) period.id];
  final funded = await _periodsHoldingMoney(db, ids);

  var repriced = 0;
  for (final period in candidates) {
    if (funded.contains(period.id)) continue;
    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(period.id)))
        .write(MembershipPeriodsCompanion(
            expectedAmountMinor: Value(feeMinor)));
    repriced++;
  }

  return repriced;
}

/// Re-prices every active member enrolled on [planId].
///
/// Editing a plan's price in Settings changes what the whole roster is billed,
/// so the cycles they are currently in have to follow. Members on a per-member
/// fee override are skipped: the plan's price is not what they are charged, so
/// a change to it is not theirs to feel.
Future<int> repriceOpenCyclesForPlan(
  AppDatabase db, {
  required int planId,
  DateTime? now,
}) async {
  // A member on their own fee is not billed the plan's price, so a change to
  // it is not theirs to feel. Resolving the fee per member would still move
  // their cycle whenever it had drifted from their override for some unrelated
  // reason — a silent correction nobody asked for, on the one screen that
  // promises in as many words that these members are unaffected.
  final enrolled = await (db.select(db.memberships)
        ..where((m) =>
            m.planId.equals(planId) &
            m.endDate.isNull() &
            m.feeOverrideMinor.isNull()))
      .get();

  var repriced = 0;
  for (final membership in enrolled) {
    repriced +=
        await repriceOpenCycles(db, memberId: membership.memberId, now: now);
  }
  return repriced;
}

/// Which of [periodIds] already have money recorded against them.
///
/// Allocations are the current answer, but a database predating v10 — or a row
/// written straight to `payments` — can hold a payment with no allocation at
/// all, and that money still counts. The same fallback
/// `MemberRepository._buildRows` applies when deciding whether a cycle is
/// settled.
Future<Set<int>> _periodsHoldingMoney(
  AppDatabase db,
  List<int> periodIds,
) async {
  if (periodIds.isEmpty) return const {};

  final holding = <int>{...await periodsWithAnyAllocation(db, periodIds)};

  final rows = await (db.selectOnly(db.payments, distinct: true)
        ..addColumns([db.payments.membershipPeriodId])
        ..where(db.payments.membershipPeriodId.isIn(periodIds)))
      .get();
  for (final row in rows) {
    final id = row.read(db.payments.membershipPeriodId);
    if (id != null) holding.add(id);
  }

  return holding;
}
