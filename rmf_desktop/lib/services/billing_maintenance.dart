import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/cycle_pricing_log.dart';
import '../data/database.dart';
import '../domain/billing_cycle.dart';

/// Keeps billing cycles rolling forward.
///
/// Cycles are otherwise only created when a payment is recorded or a ledger is
/// imported, so an active member with no payment this month would have no cycle
/// covering today and read as EXPIRED — when what they actually are is DUE.
/// This creates the missing cycle so status stays truthful.
///
/// Since v10 the cycle it creates is anchored: it starts where the member's
/// last cycle ended and runs to their own billing day, rather than snapping to
/// the 1st of the calendar month. A member billed on the 6th therefore rolls
/// into 6 Oct – 6 Nov, and a member with no anchor — every membership that
/// predates v10 — resolves to the 1st and rolls exactly as before.
final _log = Logger('billing');

class BillingMaintenance {
  BillingMaintenance(this.db);

  final AppDatabase db;

  /// Bounded so a membership left untouched for years cannot spin here. Twenty
  /// years of monthly cycles.
  static const int _maxRollsPerMembership = 240;

  /// Ensures every active membership has a billing cycle covering [now].
  /// Idempotent: running it repeatedly creates nothing new.
  ///
  /// Whether somebody is still a member is the owner's call, made by
  /// deactivating them — never inferred here from how long it has been since
  /// they last paid. A member who has not paid since January is exactly the
  /// member the owner needs to see owing money, not one to quietly write off.
  Future<int> ensureCurrentPeriods({DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final today = DateTime.utc(at.year, at.month, at.day);

    // One enrolment per member: the newest open one, the same answer
    // `openMembershipFor` gives. A database that predates the one-open-
    // enrolment index can hold two for one person, and rolling both gave that
    // member the same cycle twice — which the one-cycle-per-member trigger
    // refused, taking the whole roll, and with it the app's startup, down.
    final newestOpen = <int, Membership>{};
    for (final m in await (db.select(db.memberships)
          ..where((m) => m.endDate.isNull())
          ..orderBy([(m) => OrderingTerm(expression: m.id)]))
        .get()) {
      newestOpen[m.memberId] = m;
    }
    final memberships = newestOpen.values.toList();
    if (memberships.isEmpty) return 0;

    // A member who has left the gym must stop accruing debt. Without this a
    // deactivated member silently collects an unpaid cycle every month and
    // shows up in "payments due" for a membership nobody expects them to pay.
    final activeMembers = {
      for (final m in await (db.select(db.members)
            ..where((m) => m.deactivatedAt.isNull()))
          .get())
        m.id: m,
    };

    final plans = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };

    // Cycles are read per *member*, not per enrolment: changing plan opens a
    // new enrolment, and the cycle the member already paid this month stays on
    // the old one. Looking only at the open enrolment would see no cycle and
    // roll a duplicate unpaid one for a month that is already settled.
    final memberByMembership = {
      for (final m in await db.select(db.memberships).get()) m.id: m.memberId,
    };

    final periodsByMember = <int, List<MembershipPeriod>>{};
    for (final period in await (db.select(db.membershipPeriods)
          ..orderBy([(p) => OrderingTerm(expression: p.periodStart)]))
        .get()) {
      final memberId = memberByMembership[period.membershipId];
      if (memberId == null) continue;
      periodsByMember.putIfAbsent(memberId, () => []).add(period);
    }

    var created = 0;

    await db.transaction(() async {
      for (final membership in memberships) {
        final member = activeMembers[membership.memberId];
        if (member == null) continue;

        // One member's bad row is logged and skipped, never allowed to stop
        // everyone else being rolled. SQLite aborts only the failing
        // statement, so the transaction carries on with the next member.
        try {
          if (await _rollOne(
            membership: membership,
            member: member,
            plan: plans[membership.planId],
            periodsByMember: periodsByMember,
            today: today,
            at: at,
          )) {
            created++;
          }
        } catch (error, stack) {
          _log.severe(
              'Could not roll the billing cycle for member ${member.id}',
              error,
              stack);
        }
      }
    });

    return created;
  }

  /// Opens [membership]'s cycle covering [today] if it has none. True when a
  /// cycle was opened.
  ///
  /// [periodsByMember] is the roll's snapshot, and the cycle opened here is
  /// added to it, so nothing later in the same run can see the member as
  /// uncovered and open it again.
  Future<bool> _rollOne({
    required Membership membership,
    required Member member,
    required MembershipPlan? plan,
    required Map<int, List<MembershipPeriod>> periodsByMember,
    required DateTime today,
    required DateTime at,
  }) async {
    final duration = plan?.durationMonths ?? 1;
    final periods = periodsByMember[membership.memberId] ?? const [];

    // Drift hands DateTimes back in local time. The instant is right, but
    // reading .month off a local value lands on the wrong month in any
    // negative-offset timezone, so normalise before doing calendar maths.
    final covered = periods.any((p) =>
        !p.periodStart.toUtc().isAfter(today) &&
        today.isBefore(p.periodEnd.toUtc()));
    if (covered) return false;

    final anchorDay = resolveAnchorDay(
      billingAnchorDay: membership.billingAnchorDay,
      latestPeriodStart: periods.isEmpty ? null : periods.last.periodStart,
      joiningDate: member.joiningDate,
    );

    final cycle = _cycleCovering(
      periods: periods,
      joiningDate: member.joiningDate,
      anchorDay: anchorDay,
      duration: duration,
      today: today,
    );
    if (cycle == null) return false;

    final fee = membership.feeOverrideMinor ?? plan?.priceMinor ?? 0;
    // A transition onto a new billing day runs anywhere from about 15 to 46
    // days, and used to be charged one full month whatever its length. Charged
    // for its own days instead — see `feeForCycle`.
    final expected = feeForCycle(
          feeMinor: fee,
          start: cycle.start,
          end: cycle.end,
          durationMonths: duration,
        ) ??
        fee;
    final opened = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: cycle.start,
            periodEnd: cycle.end,
            expectedAmountMinor: expected,
          ),
        );
    // Why this cycle carries this figure, recorded beside the figure itself.
    // See `data/cycle_pricing_log.dart`.
    await recordCycleOpened(
      db,
      membershipPeriodId: opened.id,
      amountMinor: expected,
      membership: membership,
      plan: plan,
      reason: 'Opened by the startup roll to cover today.',
      at: at,
    );
    periodsByMember.putIfAbsent(membership.memberId, () => []).add(opened);
    return true;
  }

  /// The cycle containing [today], continuing the member's own cadence.
  ///
  /// Only that one cycle is returned. Back-filling every month missed since
  /// the member last paid would invent debt the owner never recorded — which
  /// is a different decision from the one this method exists to make, and the
  /// owner's to take on the Reminders screen rather than this method's to take
  /// silently at startup.
  ///
  /// Null when the member's cycles are already in the future, which happens
  /// legitimately after they pay several months in advance.
  BillingCycle? _cycleCovering({
    required List<MembershipPeriod> periods,
    required DateTime joiningDate,
    required int anchorDay,
    required int duration,
    required DateTime today,
  }) {
    if (periods.isEmpty) {
      // Nothing recorded at all. Rooted in today's calendar month rather than
      // walked forward from the day the member joined — see cycleContaining.
      return cycleContaining(
        today: today,
        anchorDay: anchorDay,
        durationMonths: duration,
        joiningDate: joiningDate,
      );
    }

    final latestEnd = periods
        .map((p) => p.periodEnd.toUtc())
        .reduce((a, b) => a.isAfter(b) ? a : b);

    // Paid ahead: no cycle to open, and opening one would bill them twice.
    if (latestEnd.isAfter(today)) return null;

    return _rollTo(
      cycleAfter(
        previousEnd: latestEnd,
        durationMonths: duration,
        anchorDay: anchorDay,
      ),
      duration: duration,
      anchorDay: anchorDay,
      today: today,
    );
  }

  /// Walks [cycle] forward in whole cycles until it contains [today].
  BillingCycle? _rollTo(
    BillingCycle cycle, {
    required int duration,
    required int anchorDay,
    required DateTime today,
  }) {
    var at = cycle;
    for (var i = 0; i < _maxRollsPerMembership; i++) {
      if (at.contains(today)) return at;
      if (at.start.isAfter(today)) return null;
      at = cycleAfter(
        previousEnd: at.end,
        durationMonths: duration,
        anchorDay: anchorDay,
      );
    }
    return null;
  }
}
