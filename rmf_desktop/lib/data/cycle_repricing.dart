import 'package:drift/drift.dart';

import '../domain/billing_cycle.dart';
import 'cycle_pricing_log.dart';
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
///
/// [effectiveFrom] limits the change to cycles *starting* on or after that
/// day, which is what the owner is choosing on the member form when they say a
/// new plan applies "from today" rather than from the start of the month. A
/// cycle is billed on its start, so one that began before the new fee was
/// meant to apply keeps the figure it was billed at. Null means every cycle
/// the guards below allow. The startup sweep passes the member's latest
/// recorded change, so the choice survives the next launch.
///
/// A back-dated [effectiveFrom] does **not** widen what may be touched. Guard
/// (c) still refuses a cycle that has ended, whatever date is passed here, so
/// this can never become a way to rewrite history quietly — see
/// `services/historical_pricing_review.dart` for the reviewed path that can.
Future<int> repriceOpenCycles(
  AppDatabase db, {
  required int memberId,
  DateTime? now,
  DateTime? effectiveFrom,
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

  final from = effectiveFrom == null
      ? null
      : DateTime.utc(effectiveFrom.toUtc().year, effectiveFrom.toUtc().month,
          effectiveFrom.toUtc().day);

  // What each still-open cycle should cost now. Only a cycle the plan's own
  // length can price is a candidate: re-pricing used to copy the fee onto
  // whatever cycle was open, so moving a member from Monthly to Quarterly
  // billed their current month 8,000, moving them back billed a whole quarter
  // 3,000, and the startup sweep put the wrong figure back after every
  // correction. A cycle of another length keeps what it was billed at, and
  // the next cycle opens at the new plan's length and price.
  final open = [
    for (final period in await periodsForMember(db, memberId))
      if (period.settledAt == null &&
          period.periodEnd.toUtc().isAfter(today) &&
          (from == null || !period.periodStart.toUtc().isBefore(from)))
        period,
  ];
  if (open.isEmpty) return 0;

  final targets = <int, int>{};
  for (final period in open) {
    final target = await _targetFor(
      db,
      period: period,
      feeMinor: feeMinor,
      durationMonths: plan.durationMonths,
    );
    if (target != null && target != period.expectedAmountMinor) {
      targets[period.id] = target;
    }
  }
  final candidates = [
    for (final period in open)
      if (targets.containsKey(period.id)) period,
  ];
  if (candidates.isEmpty) return 0;

  final ids = [for (final period in candidates) period.id];
  final funded = await _periodsHoldingMoney(db, ids);
  final collected = await collectedByPeriod(db, ids);

  var repriced = 0;
  for (final period in candidates) {
    final target = targets[period.id]!;

    // Money against a cycle is the member acting on the price they were
    // quoted — so a **rise** must not reach it, or the increase is backdated
    // onto somebody who had already paid what was asked.
    //
    // A **cut** is the opposite case and the guard was wrong to catch it. It
    // can only ever reduce what the member owes, so there is no charge to
    // backdate; refusing it leaves the gym asking for money the owner has
    // already agreed to stop charging. That is what stranded forty-three
    // members at once: each was moved onto a cheaper plan part way through
    // the month, paid the new, lower fee, and the cycle went on wanting the
    // old one for ever — because from the moment their money landed nothing
    // would re-price it again.
    if (funded.contains(period.id) && target > period.expectedAmountMinor) {
      continue;
    }

    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(period.id)))
        .write(MembershipPeriodsCompanion(
          expectedAmountMinor: Value(target),
          // Recomputed here rather than left to a later caller: a cut can be
          // the very thing that closes the cycle, and a stamp that disagreed
          // with the money behind it is what `refreshSettlement` exists to
          // prevent everywhere else. Every candidate arrived unsettled, so
          // this only ever closes one — it cannot reopen anything.
          settledAt: Value(
              (collected[period.id] ?? 0) >= target ? at : null),
        ));

    // What moved the figure, recorded beside the figure. A cycle that has been
    // re-priced twice is otherwise indistinguishable from one opened at the
    // final number, and telling those apart is exactly what nobody could do
    // when forty-three members were found stranded.
    await recordCyclePricing(
      db,
      membershipPeriodId: period.id,
      amountMinor: target,
      previousAmountMinor: period.expectedAmountMinor,
      source: sourceFor(membership),
      planId: membership.planId,
      planPriceMinor: plan.priceMinor,
      feeOverrideMinor: membership.feeOverrideMinor,
      reason: target < period.expectedAmountMinor
          ? 'Re-priced down to the fee the member is on now.'
          : 'Re-priced to the fee the member is on now.',
      at: at,
    );
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

/// What [period] should cost at [feeMinor] on a plan of [durationMonths], or
/// null when it should be left alone.
///
/// A whole cycle costs the fee. A transition onto a new billing day is priced
/// in proportion to its days when it opens (see `feeForCycle`), but only from
/// 1 October 2026 — those opened before then were charged a full month, and
/// the owner chose to leave them as they are. So a transition is never
/// re-priced from its dates: it follows a fee change by the same ratio the
/// fee moved, measured from the fee its own pricing history says it was set
/// against. With no such history there is nothing to scale from, and the
/// cycle keeps its figure.
Future<int?> _targetFor(
  AppDatabase db, {
  required MembershipPeriod period,
  required int feeMinor,
  required int durationMonths,
}) async {
  switch (cycleShapeFor(
    start: period.periodStart,
    end: period.periodEnd,
    durationMonths: durationMonths,
  )) {
    case CycleShape.whole:
      return feeMinor;
    case CycleShape.otherLength:
      return null;
    case CycleShape.transition:
      final history = await pricingHistoryFor(db, period.id);
      if (history.isEmpty) return null;
      final latest = history.last;
      if (latest.source == CyclePricingSource.unknown) return null;
      final basis = latest.feeOverrideMinor ?? latest.planPriceMinor;
      if (basis == null || basis <= 0 || basis == feeMinor) return null;
      return (period.expectedAmountMinor * feeMinor / basis / 100).round() *
          100;
  }
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

/// Re-prices every active member's not-yet-issued cycles to their current fee.
///
/// The sweep `runStartupMaintenance` makes, and the thing that stops a stale
/// price surviving long enough to be paid into.
///
/// A fee change made through the app already re-prices as it happens — see
/// [repriceOpenCycles] from `MemberRepository.update`, and
/// [repriceOpenCyclesForPlan] from Settings. What neither of those can reach is
/// a price that moved before this code existed, or under a release that did not
/// carry it through. Those cycles sit at the old figure until somebody pays the
/// new one into them, at which point the difference spills forward, opens the
/// next cycle early and part-pays it — and from then on the member is
/// permanently one shortfall behind however faithfully they pay. Once that has
/// happened nothing here can undo it: [repriceOpenCycles] will not touch a
/// cycle holding money, precisely because a member who part-paid at the old
/// price must not have the rise backdated onto them. The only place to stop it
/// is before the money lands.
///
/// Every guard [repriceOpenCycles] makes still applies, so this leaves alone
/// settled cycles, cycles holding any money at all, and cycles that have
/// already ended — arrears stay at the price they were incurred at. So does
/// the member's most recent "applies from" date, where they have one.
Future<int> repriceAllOpenCycles(AppDatabase db, {DateTime? now}) async {
  final active = await (db.select(db.members)
        ..where((m) => m.deactivatedAt.isNull()))
      .get();

  // The owner's latest "applies from" answer for each member. A fee change
  // saved as applying from 10 September leaves the cycle that began on the 1st
  // at its old price — and the next launch used to re-price it anyway, because
  // this sweep passed no date and so undid the choice the save had honoured.
  final appliesFrom = <int, DateTime>{};
  for (final change in await (db.select(db.membershipChanges)
        ..orderBy([
          (c) => OrderingTerm(expression: c.recordedAt),
          (c) => OrderingTerm(expression: c.id),
        ]))
      .get()) {
    // A change saved as applying "today" carries its own timestamp as the
    // date, and its save re-priced without a cut-off; mirroring the save means
    // passing none here either. Only a date the owner actually picked limits
    // the sweep.
    final picked = change.effectiveFrom.toUtc() != change.recordedAt.toUtc();
    if (picked) {
      appliesFrom[change.memberId] = change.effectiveFrom;
    } else {
      appliesFrom.remove(change.memberId);
    }
  }

  var repriced = 0;
  for (final member in active) {
    repriced += await repriceOpenCycles(
      db,
      memberId: member.id,
      now: now,
      effectiveFrom: appliesFrom[member.id],
    );
  }
  return repriced;
}
