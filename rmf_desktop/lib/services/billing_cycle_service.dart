import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/cycle_pricing_log.dart';
import '../data/database.dart';
import '../data/membership_queries.dart';
import '../domain/billing_cycle.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
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

      // A transition onto a new billing day is charged for its own days, not
      // a whole month — see `feeForCycle`.
      final expected = feeForCycle(
            feeMinor: billing.feeMinor,
            start: next.start,
            end: next.end,
            durationMonths: billing.plan.durationMonths,
          ) ??
          billing.feeMinor;
      offered.add(SettleableCycle.fromCycle(next, expectedMinor: expected));
      covered += expected;
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
    if (billing.anchorDay == anchorDay) {
      // Nothing moves, but a day that is only *resolved* — read back off the
      // latest cycle because the column is empty — is not kept. After a short
      // month it resolves to the clamped day instead, and a member billed on
      // the 31st drifts to the 30th and the 28th. Storing it is what pins it.
      if (billing.membership.billingAnchorDay != anchorDay) {
        await (db.update(db.memberships)
              ..where((m) => m.id.equals(billing.membership.id)))
            .write(MembershipsCompanion(billingAnchorDay: Value(anchorDay)));
      }
      return;
    }

    final previous = billing.anchorDay;
    final transition = cycleAfter(
      previousEnd: billing.nextBoundary,
      durationMonths: billing.plan.durationMonths,
      anchorDay: anchorDay,
    );
    final transitionFee = feeForCycle(
          feeMinor: billing.feeMinor,
          start: transition.start,
          end: transition.end,
          durationMonths: billing.plan.durationMonths,
        ) ??
        billing.feeMinor;

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
            '(${transition.lengthInDays} days), '
            '${formatMinorUnits(transitionFee)}.',
      ],
    );

    _log.info('Member $memberId re-anchored from $previous to $anchorDay');
  }

  /// The day a restart most likely means: the day of the member's latest
  /// payment when that was within the last month — the owner took the money
  /// when they came back and is restarting afterwards — and otherwise today.
  Future<DateTime> suggestedRestartDay(int memberId, {DateTime? today}) async {
    final now = _gymToday(today);
    final latest = await (db.select(db.payments)
          ..where((p) => p.memberId.equals(memberId))
          ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)])
          ..limit(1))
        .getSingleOrNull();
    if (latest == null) return now;

    final local = latest.paymentDate.toLocal();
    final paidOn = DateTime.utc(local.year, local.month, local.day);
    final recent = !paidOn.isAfter(now) &&
        now.difference(paidOn) <= const Duration(days: 31);
    return recent ? paidOn : now;
  }

  /// True when a paid or free cycle covers [today], i.e. reactivating this
  /// member needs no restart: they are still inside time already settled.
  Future<bool> isCoveredOn(int memberId, {DateTime? today}) async {
    final billing = await forMember(memberId);
    if (billing == null) return false;
    final on = _gymToday(today);
    return billing.cycles.any((c) =>
        c.isSettled && !c.start.isAfter(on) && on.isBefore(c.end));
  }

  /// What restarting [memberId]'s billing on [from] would do, without writing
  /// anything. The dialog shows this before the owner confirms.
  ///
  /// [today] is injectable for tests; the app passes nothing.
  Future<BillingRestart> previewRestart({
    required int memberId,
    required DateTime from,
    DateTime? today,
  }) async {
    final billing = await forMember(memberId);
    if (billing == null) {
      return const BillingRestartRefused(
          'This member has no plan, so there is no billing to restart.');
    }
    return _planRestart(billing, _dayStart(from), _gymToday(today));
  }

  /// Starts a returning member's billing again on the day they came back.
  ///
  /// The gym's rule, and not the one this app first had: a member who stopped
  /// coming and returns starts afresh from the day they walk in. They do not
  /// owe the months they were away, and they are not billed for the calendar
  /// month they happen to return in — paid on 25 September is covered until
  /// 25 October, and billed on the 25th from then on. Before this existed a
  /// returning member was billed on their old cadence from wherever their last
  /// cycle ended, and naming the month by hand billed it 1st to 1st.
  ///
  /// What it does, in one transaction:
  ///
  /// - **Drops the unpaid run since they last paid.** Cycles with no money in
  ///   them that start after the member's last paid cycle — the months the
  ///   roll opened while they were away, or that came from the old cadence.
  ///   An unpaid month from *before* their last payment is real arrears and
  ///   stays.
  /// - **Moves at most one payment.** If money was already taken on or after
  ///   [from] — the owner recorded it before restarting, which is exactly what
  ///   happened with the members who prompted this — the one cycle holding it
  ///   is re-dated to start on [from]. The money and the receipt stay on the
  ///   same row; only its dates change, from days the member was not coming
  ///   to days they were.
  /// - **Otherwise opens the first cycle** from [from], unpaid, so the next
  ///   payment taken settles the month they came back for rather than one
  ///   from before they left.
  /// - **Moves the billing day** to [from]'s day of the month.
  ///
  /// Anything more tangled — two paid months past [from], or a payment dated
  /// before it — is refused with the reason rather than untangled by guessing,
  /// because a guess here moves somebody's money.
  Future<BillingRestart> restartBilling({
    required int memberId,
    required DateTime from,
    int? actorId,
    DateTime? today,
  }) async {
    final billing = await forMember(memberId);
    if (billing == null) {
      return const BillingRestartRefused(
          'This member has no plan, so there is no billing to restart.');
    }
    final plan = await _planRestart(
        billing, _dayStart(from), _gymToday(today));
    if (plan is! BillingRestartPlan) return plan;

    final at = DateTime.now().toUtc();
    await db.transaction(() async {
      // Dropped first: the cycle that replaces them may start on the same day,
      // and the unique key on (membership, start) would refuse it otherwise.
      // Their price history and reminder rows go with them by cascade.
      for (final cycle in plan.dropped) {
        await (db.delete(db.membershipPeriods)
              ..where((p) => p.id.equals(cycle.periodId!)))
            .go();
      }

      final moved = plan.moved;
      if (moved != null) {
        await (db.update(db.membershipPeriods)
              ..where((p) => p.id.equals(moved.periodId!)))
            .write(MembershipPeriodsCompanion(
          periodStart: Value(plan.firstCycle.start),
          periodEnd: Value(plan.firstCycle.end),
        ));
      } else {
        final opened = await db.into(db.membershipPeriods).insertReturning(
              MembershipPeriodsCompanion.insert(
                membershipId: billing.membership.id,
                periodStart: plan.firstCycle.start,
                periodEnd: plan.firstCycle.end,
                expectedAmountMinor: billing.feeMinor,
              ),
            );
        await recordCycleOpened(
          db,
          membershipPeriodId: opened.id,
          amountMinor: billing.feeMinor,
          membership: billing.membership,
          plan: billing.plan,
          reason: 'Opened by restarting billing from '
              '${formatDayMonthYear(plan.from)}.',
          actorId: actorId,
          at: at,
        );
      }

      await (db.update(db.memberships)
            ..where((m) => m.id.equals(billing.membership.id)))
          .write(MembershipsCompanion(billingAnchorDay: Value(plan.anchorDay)));
    });

    final name = billing.member.fullName;
    await _audit.record(
      category: AuditCategory.billing,
      action: AuditAction.billingRestarted,
      outcome: AuditOutcome.success,
      actorId: actorId,
      memberId: memberId,
      memberName: name,
      summary: '$name: billing restarted from ${formatDayMonthYear(plan.from)}',
      detail: [
        if (plan.moved != null)
          'The payment already taken now covers '
              '${_span(plan.firstCycle.start, plan.firstCycle.end)} '
              '(was ${_span(plan.moved!.start, plan.moved!.end)}).'
        else
          'First month: ${_span(plan.firstCycle.start, plan.firstCycle.end)}, '
              'unpaid.',
        for (final cycle in plan.dropped)
          cycle.expectedMinor == 0
              ? 'Free days now inside the new month: '
                  '${_span(cycle.start, cycle.end)}.'
              : 'Removed unpaid month: ${_span(cycle.start, cycle.end)}.',
        'Billing day is now ${plan.anchorDay} '
            '(was ${plan.previousAnchorDay}).',
        'Next due: ${formatDayMonthYear(plan.nextDue)}.',
      ],
    );
    _log.info('Member $memberId billing restarted from ${plan.from}: '
        'moved ${plan.moved?.periodId}, dropped '
        '${plan.dropped.map((c) => c.periodId).toList()}');

    return plan;
  }

  Future<BillingRestart> _planRestart(
    MemberBilling billing,
    DateTime from,
    DateTime today,
  ) async {
    final name = billing.member.fullName;

    if (from.isAfter(today)) {
      return const BillingRestartRefused(
          'Billing cannot restart on a day that has not come yet.');
    }
    final joined = _dayStart(billing.member.joiningDate.toUtc());
    if (from.isBefore(joined)) {
      return BillingRestartRefused('$name joined on '
          '${formatDayMonthYear(joined)}, so billing cannot restart before '
          'that day.');
    }

    // A waiver is settled but holds nothing; only real money pins a cycle.
    bool hasMoney(SettleableCycle c) => c.collectedMinor > 0;

    // Paid months split by *when the money was taken*, not by where their
    // dates fall. Money taken on or after [from] is what the member paid on
    // coming back, whatever month it was booked to — one returner paid on
    // 1 October and it went to a September ending that same day. Money taken
    // before it is history. A month marked paid with no payment to date it,
    // as the ledger import's are, is history too.
    final history = <SettleableCycle>[];
    final onReturn = <SettleableCycle>[];
    final paidOnOf = <SettleableCycle, DateTime>{};
    for (final c in billing.cycles) {
      if (!hasMoney(c)) continue;
      final days = c.periodId == null
          ? const <DateTime>[]
          : await _paymentDaysFor(c.periodId!);
      if (days.isEmpty) {
        history.add(c);
        continue;
      }
      final earliest = days.reduce((a, b) => a.isBefore(b) ? a : b);
      paidOnOf[c] = earliest;
      (earliest.isBefore(from) ? history : onReturn).add(c);
    }

    // History may not reach past the restart: those days are already paid.
    for (final c in history) {
      if (c.end.isAfter(from)) {
        final paidOn = paidOnOf[c];
        return BillingRestartRefused('$name has already paid until '
            '${formatDayMonthYear(c.end)}'
            '${paidOn == null ? '' : ' (paid on ${formatDayMonthYear(paidOn)})'}'
            '. Restart from ${formatDayMonthYear(c.end)} or later'
            '${paidOn == null ? '' : ', or from ${formatDayMonthYear(paidOn)} '
                'if that payment was for coming back'}.');
      }
    }

    if (onReturn.length > 1) {
      return BillingRestartRefused('$name has more than one payment taken on '
          'or after ${formatDayMonthYear(from)}. Restarting would have to move '
          'more than one of them, so pick a later day, or correct the payments '
          'first.');
    }
    final moved = onReturn.isEmpty ? null : onReturn.single;

    // Where the paid history the restart must leave alone ends.
    DateTime? paidUntil;
    for (final c in history) {
      if (paidUntil == null || c.end.isAfter(paidUntil)) paidUntil = c.end;
    }

    final anchor = from.day;
    final first = BillingCycle(
      start: from,
      end: addMonthsClamped(from, billing.plan.durationMonths,
          anchorDay: anchor),
    );

    // A free stretch — the ledger import's cover until a member's first bill,
    // or the few days a change of billing day left over — holds no money but
    // is not a debt either: it is the owner having said those days are not
    // billed. One that ended before [from] is history and stays. One that
    // ends inside a new first month the member has *already paid for* goes,
    // because that month now covers its days. Anything else running past
    // [from] is refused: dropping it would bill days the owner said were free
    // — a member free until 21 October would have owed from the 1st.
    bool isFree(SettleableCycle c) => c.expectedMinor == 0 && c.isSettled;
    final coveredUntil = moved != null ? first.end : from;
    for (final c in billing.cycles) {
      if (isFree(c) && c.end.isAfter(coveredUntil)) {
        return BillingRestartRefused('$name has free days recorded until '
            '${formatDayMonthYear(c.end)}, so billing already starts again '
            'then. Pick ${formatDayMonthYear(c.end)} or later to restart.');
      }
    }

    // Real debts with nothing paid towards them, and free days the new first
    // month now covers.
    final dropped = [
      for (final c in billing.cycles)
        if (!hasMoney(c) &&
            c.periodId != null &&
            (isFree(c)
                ? c.end.isAfter(from)
                : !c.isSettled &&
                    (paidUntil == null || !c.start.isBefore(paidUntil))))
          c,
    ];
    // Allocations are what "has money" reads. A payment pointing at a cycle
    // without one would be a row this app never writes, but a cycle a payment
    // still references cannot be deleted, so it is checked rather than
    // assumed and refused here instead of failing half way through.
    for (final c in dropped) {
      if ((await _paymentDaysFor(c.periodId!)).isNotEmpty) {
        return BillingRestartRefused('A payment is recorded against '
            '${_span(c.start, c.end)} without being counted towards it. '
            'Correct that payment first.');
      }
    }


    return BillingRestartPlan(
      from: from,
      firstCycle: first,
      anchorDay: anchor,
      previousAnchorDay: billing.anchorDay,
      moved: moved,
      dropped: dropped,
      // Paid in full when moved, so the member next owes on its end;
      // otherwise the first cycle itself is the one owed.
      nextDue: moved != null && moved.isSettled ? first.end : first.start,
    );
  }

  /// The days, on the gym's own clock, of every payment counted towards or
  /// pointing at [periodId].
  Future<List<DateTime>> _paymentDaysFor(int periodId) async {
    final allocated = db.select(db.payments).join([
      innerJoin(db.paymentAllocations,
          db.paymentAllocations.paymentId.equalsExp(db.payments.id)),
    ])
      ..where(db.paymentAllocations.membershipPeriodId.equals(periodId));
    final direct = db.select(db.payments)
      ..where((p) => p.membershipPeriodId.equals(periodId));

    final payments = {
      for (final row in await allocated.get())
        row.readTable(db.payments).id: row.readTable(db.payments),
      for (final p in await direct.get()) p.id: p,
    };
    // "Which day was this paid" is a question about the wall clock at the
    // counter, as in `classifyTiming`: stored 24 Sep 19:00 UTC is 25 Sep in
    // Lahore, and reading the UTC day would refuse the very payment this
    // exists to move.
    return [
      for (final p in payments.values)
        () {
          final local = p.paymentDate.toLocal();
          return DateTime.utc(local.year, local.month, local.day);
        }(),
    ];
  }

  static DateTime _dayStart(DateTime at) {
    final on = at.toUtc();
    return DateTime.utc(on.year, on.month, on.day);
  }

  /// Today on the gym's wall clock, as a UTC midnight. Reading the UTC date
  /// instead would put the first five hours of every day in Lahore on the day
  /// before, and refuse "today" as a day that has not come yet.
  static DateTime _gymToday(DateTime? today) {
    if (today != null) return _dayStart(today);
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// "25 Sep 2026 to 25 Oct 2026", the end read as the day the next begins.
  static String _span(DateTime start, DateTime end) =>
      '${formatDayMonthYear(start)} to ${formatDayMonthYear(end)}';

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

  /// [previewAnchorChange], with what that next cycle will be charged — so the
  /// owner sees a 15-day transition's smaller bill, or a 46-day one's larger
  /// bill, before confirming rather than finding it on the member later.
  Future<({BillingCycle cycle, int feeMinor})?> previewAnchorChangeWithFee({
    required int memberId,
    required int anchorDay,
  }) async {
    final billing = await forMember(memberId);
    if (billing == null) return null;

    final cycle = cycleAfter(
      previousEnd: billing.nextBoundary,
      durationMonths: billing.plan.durationMonths,
      anchorDay: anchorDay,
    );
    final fee = feeForCycle(
          feeMinor: billing.feeMinor,
          start: cycle.start,
          end: cycle.end,
          durationMonths: billing.plan.durationMonths,
        ) ??
        billing.feeMinor;
    return (cycle: cycle, feeMinor: fee);
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

/// The answer to "restart this member's billing from this day": what would
/// change, or why it will not.
sealed class BillingRestart {
  const BillingRestart();
}

/// Said in words the owner can act on, because the usual fix is simply a
/// different day.
class BillingRestartRefused extends BillingRestart {
  const BillingRestartRefused(this.reason);
  final String reason;
}

class BillingRestartPlan extends BillingRestart {
  const BillingRestartPlan({
    required this.from,
    required this.firstCycle,
    required this.anchorDay,
    required this.previousAnchorDay,
    required this.moved,
    required this.dropped,
    required this.nextDue,
  });

  /// The day billing starts again, as a UTC midnight.
  final DateTime from;

  /// The member's first cycle from [from], on the new billing day.
  final BillingCycle firstCycle;

  final int anchorDay;
  final int previousAnchorDay;

  /// The cycle whose payment is re-dated onto [firstCycle], when money was
  /// already taken for the month the member came back for.
  final SettleableCycle? moved;

  /// The unpaid months removed: every cycle with no money in it since the
  /// member's last paid one.
  final List<SettleableCycle> dropped;

  /// When the member next owes money once this is applied.
  final DateTime nextDue;
}
