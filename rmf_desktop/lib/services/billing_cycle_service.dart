import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/cycle_pricing_log.dart';
import '../data/database.dart';
import '../data/membership_queries.dart';
import '../domain/billing_cycle.dart';
import '../domain/dates.dart';
import '../domain/payment_settlement.dart';

final _log = Logger('billing');

/// The database half of the billing-cycle model.
///
/// The arithmetic lives in `domain/billing_cycle.dart` and knows nothing about
/// SQLite; the settlement rules live in `domain/payment_settlement.dart`. This
/// is the one place that reads a member's cycles out and writes new ones back,
/// so recording a payment, rolling the month forward and building the reminder
/// queue all see the same timeline.
///
/// The single most important thing it does *not* do: create a cycle
/// speculatively. A cycle row is a debt, and a member must never be shown
/// owing money for a month nobody has billed them for. Future cycles are
/// computed and offered; they become rows only when money actually lands in
/// them.
class BillingCycleService {
  BillingCycleService(this.db, {AuditRepository? audit})
      : _audit = audit ?? AuditRepository(db);

  final AppDatabase db;
  final AuditRepository _audit;

  /// How many cycles ahead a single payment may reach.
  ///
  /// Two years on a monthly plan. Bounded because the amount is typed by hand:
  /// an extra zero must produce a refusal the owner can read, not two hundred
  /// billing cycles.
  static const int maxCyclesPerPayment = 24;

  /// Everything about where a member stands, or null if they have no enrolment.
  Future<MemberBilling?> forMember(int memberId) async {
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(memberId)))
        .getSingleOrNull();
    if (member == null) return null;

    final membership = await openMembershipFor(db, memberId);
    if (membership == null) return null;

    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(membership.planId)))
        .getSingleOrNull();
    if (plan == null) return null;

    // Cycles come from every enrolment the member has ever had, not just the
    // open one: changing plan leaves the months they already paid on the
    // closed enrolment. Reading only the open one is what used to make a
    // fully-paid member read DUE the instant their plan changed.
    final periods = await periodsForMember(db, memberId);
    final collected = await collectedByPeriod(
      db,
      periods.map((p) => p.id).toList(),
    );

    final cycles = [
      for (final period in periods)
        SettleableCycle(
          periodId: period.id,
          start: period.periodStart.toUtc(),
          end: period.periodEnd.toUtc(),
          expectedMinor: period.expectedAmountMinor,
          // A cycle stamped settled by the v10 migration has no allocations
          // recomputed against it, so its stamp is honoured directly. That is
          // how the imported ledger stays closed under the balance rule.
          collectedMinor: period.settledAt != null
              ? period.expectedAmountMinor
              : (collected[period.id] ?? 0),
        ),
    ];

    return MemberBilling(
      member: member,
      membership: membership,
      plan: plan,
      anchorDay: resolveAnchorDay(
        billingAnchorDay: membership.billingAnchorDay,
        latestPeriodStart: periods.isEmpty ? null : periods.last.periodStart,
        joiningDate: member.joiningDate,
      ),
      feeMinor: membership.feeOverrideMinor ?? plan.priceMinor,
      cycles: cycles,
    );
  }

  /// The cycles a payment could go into, oldest first.
  ///
  /// Existing unsettled cycles come first, so an arrears payment lands on the
  /// month actually owed. Then as many computed future cycles as [amountMinor]
  /// can reach, which is what lets a member hand over three months at once.
  /// Cycles beyond what the money covers are not offered at all.
  List<SettleableCycle> settleableFor({
    required MemberBilling billing,
    required int amountMinor,
  }) {
    final offered = <SettleableCycle>[
      for (final cycle in billing.cycles)
        if (!cycle.isSettled) cycle,
    ];

    var covered = offered.fold(0, (sum, c) => sum + c.outstandingMinor);
    var boundary = billing.nextBoundary;

    // Grow the list only while the money would actually reach further. The
    // fee is snapshotted per cycle at the price in force now, matching what
    // opening a cycle would record.
    while (covered < amountMinor && offered.length < maxCyclesPerPayment) {
      final next = cycleAfter(
        previousEnd: boundary,
        durationMonths: billing.plan.durationMonths,
        anchorDay: billing.anchorDay,
      );

      offered.add(
        SettleableCycle.fromCycle(next, expectedMinor: billing.feeMinor),
      );
      covered += billing.feeMinor;
      boundary = next.end;

      // A free plan would otherwise spin here forever without ever covering
      // the amount.
      if (billing.feeMinor <= 0) break;
    }

    return offered;
  }

  /// Turns a computed cycle into a row, or finds the row already there.
  ///
  /// Called inside the payment transaction. Matching on the start rather than
  /// inserting blind is what makes two payments confirmed at the same instant
  /// settle one cycle instead of opening two.
  ///
  /// The match is per *member*, not per enrolment. A cycle recorded before a
  /// plan change belongs to the enrolment the member has since moved off, and
  /// searching only the current one would miss it and open a second row for
  /// the same month — the exact duplicate the one-cycle-per-member trigger in
  /// [AppDatabase] refuses. Found rows are returned as they are, on whichever
  /// enrolment recorded them: `periodsForMember` reads across all of them, so
  /// a cycle does not need to move to stay visible.
  Future<MembershipPeriod> materialise({
    required int membershipId,
    required SettleableCycle cycle,
  }) async {
    if (cycle.periodId != null) {
      return (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(cycle.periodId!)))
          .getSingle();
    }

    final membership = await (db.select(db.memberships)
          ..where((m) => m.id.equals(membershipId)))
        .getSingle();

    final existing = await periodForMemberStarting(
      db,
      memberId: membership.memberId,
      periodStart: cycle.start,
    );
    if (existing != null) return existing;

    final opened = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: cycle.start,
            periodEnd: cycle.end,
            expectedAmountMinor: cycle.expectedMinor,
          ),
        );

    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(membership.planId)))
        .getSingleOrNull();
    await recordCycleOpened(
      db,
      membershipPeriodId: opened.id,
      amountMinor: cycle.expectedMinor,
      membership: membership,
      plan: plan,
      reason: 'Opened by a payment that reached past the cycle before it.',
    );

    return opened;
  }

  /// Recomputes whether [periodId] is settled from the allocations against it.
  ///
  /// Called after money is added to a cycle and after a payment is deleted or
  /// edited, so `settledAt` can never drift away from the money behind it. A
  /// cycle grandfathered by the migration keeps its stamp: it has an
  /// allocation capped at what it expected, so recomputing agrees.
  Future<void> refreshSettlement(int periodId) async {
    final period = await (db.select(db.membershipPeriods)
          ..where((p) => p.id.equals(periodId)))
        .getSingleOrNull();
    if (period == null) return;

    final collected = (await collectedByPeriod(db, [periodId]))[periodId] ?? 0;
    final settlement = Settlement(
      expectedMinor: period.expectedAmountMinor,
      collectedMinor: collected,
    );

    if (settlement.isSettled && period.settledAt == null) {
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(periodId)))
          .write(MembershipPeriodsCompanion(
              settledAt: Value(DateTime.now().toUtc())));
      return;
    }

    if (!settlement.isSettled && period.settledAt != null) {
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(periodId)))
          .write(const MembershipPeriodsCompanion(settledAt: Value(null)));
    }
  }

  /// Moves a member onto a new billing day.
  ///
  /// Writes the column and nothing else. No cycle already recorded is touched,
  /// ever — the change takes effect at the next boundary, where `cycleAfter`
  /// produces a one-off transition cycle onto the new anchor. Editing a paid
  /// cycle to make the dates line up would either hand the member free days or
  /// take away days they had paid for.
  Future<void> setAnchorDay({
    required int memberId,
    required int anchorDay,
    int? actorId,
  }) async {
    if (anchorDay < 1 || anchorDay > maxAnchorDay) {
      throw ArgumentError.value(
          anchorDay, 'anchorDay', 'must be between 1 and $maxAnchorDay');
    }

    final billing = await forMember(memberId);
    if (billing == null) {
      throw StateError('Member $memberId has no active membership');
    }
    if (billing.anchorDay == anchorDay) return;

    final previous = billing.anchorDay;
    final transition = cycleAfter(
      previousEnd: billing.nextBoundary,
      durationMonths: billing.plan.durationMonths,
      anchorDay: anchorDay,
    );

    await (db.update(db.memberships)
          ..where((m) => m.id.equals(billing.membership.id)))
        .write(MembershipsCompanion(billingAnchorDay: Value(anchorDay)));

    await _audit.record(
      category: AuditCategory.billing,
      action: AuditAction.billingAnchorChanged,
      outcome: AuditOutcome.success,
      actorId: actorId,
      memberId: memberId,
      memberName: billing.member.fullName,
      summary: '${billing.member.fullName} now bills on day $anchorDay '
          '(was $previous)',
      detail: [
        'Cycles already recorded were not changed.',
        'Next cycle: ${formatDayMonthYear(transition.start)} to '
            '${formatDayMonthYear(transition.end)} '
            '(${transition.lengthInDays} days).',
      ],
    );

    _log.info('Member $memberId re-anchored from $previous to $anchorDay');
  }

  /// What the next cycle would look like if [anchorDay] were applied, without
  /// writing anything. The member screen shows this before the owner confirms.
  Future<BillingCycle?> previewAnchorChange({
    required int memberId,
    required int anchorDay,
  }) async {
    final billing = await forMember(memberId);
    if (billing == null) return null;

    return cycleAfter(
      previousEnd: billing.nextBoundary,
      durationMonths: billing.plan.durationMonths,
      anchorDay: anchorDay,
    );
  }
}

/// Where a member stands: their plan, their anchor and their whole cycle
/// timeline with the money already against each one.
class MemberBilling {
  const MemberBilling({
    required this.member,
    required this.membership,
    required this.plan,
    required this.anchorDay,
    required this.feeMinor,
    required this.cycles,
  });

  final Member member;
  final Membership membership;
  final MembershipPlan plan;

  /// The day of the month this member is billed on, resolved rather than read
  /// straight off the column — see `resolveAnchorDay`.
  final int anchorDay;

  /// The fee a new cycle would snapshot: the member's override, or the plan.
  final int feeMinor;

  /// Oldest first.
  final List<SettleableCycle> cycles;

  /// The first cycle still owing money, or null when everything is settled.
  SettleableCycle? get nextUnsettled {
    for (final cycle in cycles) {
      if (!cycle.isSettled) return cycle;
    }
    return null;
  }

  /// When money is next owed.
  ///
  /// The start of the first unsettled cycle when one exists — the gym is paid
  /// in advance, so a cycle falls due on the day it begins. Otherwise the day
  /// the next cycle will begin, which is where the paid-up run ends.
  DateTime get nextDueDate => nextUnsettled?.start ?? nextBoundary;

  /// Where the next cycle starts: the end of the member's latest cycle, or the
  /// day they joined if they have none yet.
  DateTime get nextBoundary {
    if (cycles.isEmpty) {
      return firstCycleFor(
        joiningDate: member.joiningDate,
        durationMonths: plan.durationMonths,
        anchorDay: membership.billingAnchorDay,
      ).start;
    }
    return cycles
        .map((c) => c.end)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Everything the member currently owes across all unsettled cycles.
  int get outstandingMinor =>
      cycles.fold(0, (sum, c) => sum + c.outstandingMinor);

  /// True when the member owes money for a cycle whose start has passed.
  bool isOverdueAt(DateTime now) {
    final unsettled = nextUnsettled;
    if (unsettled == null) return false;
    return unsettled.start.isBefore(_dayStart(now));
  }

  static DateTime _dayStart(DateTime at) {
    final on = at.toUtc();
    return DateTime.utc(on.year, on.month, on.day);
  }
}
