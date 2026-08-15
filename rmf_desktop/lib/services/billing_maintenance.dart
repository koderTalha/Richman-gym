import 'package:drift/drift.dart';

import '../data/database.dart';

/// Keeps billing cycles rolling forward.
///
/// Periods are otherwise only created when a payment is recorded or a ledger is
/// imported, so an active member with no payment this month would have no cycle
/// covering today and read as EXPIRED — when what they actually are is DUE for
/// the current month. This creates the missing cycle so status stays truthful.
class BillingMaintenance {
  BillingMaintenance(this.db);

  final AppDatabase db;

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

    final memberships = await (db.select(db.memberships)
          ..where((m) => m.endDate.isNull()))
        .get();
    if (memberships.isEmpty) return 0;

    // A member who has left the gym must stop accruing debt. Without this a
    // deactivated member silently collects an unpaid cycle every month and
    // shows up in "payments due" for a membership nobody expects them to pay.
    final activeMemberIds = (await (db.select(db.members)
              ..where((m) => m.deactivatedAt.isNull()))
            .get())
        .map((m) => m.id)
        .toSet();

    final plans = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };

    // Cycles are read per *member*, not per enrolment: changing plan opens a
    // new enrolment, and the cycle the member already paid this month stays on
    // the old one. Looking only at the open enrolment would see no cycle and
    // roll a duplicate unpaid one for a month that is already settled.
    final allMemberships = await db.select(db.memberships).get();
    final memberByMembership = {
      for (final m in allMemberships) m.id: m.memberId,
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
        if (!activeMemberIds.contains(membership.memberId)) continue;

        final duration = plans[membership.planId]?.durationMonths ?? 1;
        final periods = periodsByMember[membership.memberId] ?? const [];

        // Drift hands DateTimes back in local time. The instant is right, but
        // reading .month off a local value lands on the wrong month in any
        // negative-offset timezone, so normalise before doing calendar maths.
        final covered = periods.any((p) =>
            !p.periodStart.isAfter(today) && today.isBefore(p.periodEnd));
        if (covered) continue;

        // Continue the existing cadence where possible, so a quarterly member
        // keeps their own cycle boundaries rather than snapping to calendar
        // quarters. Only the cycle covering today is created — back-filling
        // every missed month would invent debt the owner never recorded.
        final start = _currentCycleStart(
          periods: periods,
          duration: duration,
          today: today,
        );

        await db.into(db.membershipPeriods).insert(
              MembershipPeriodsCompanion.insert(
                membershipId: membership.id,
                periodStart: start,
                periodEnd: DateTime.utc(start.year, start.month + duration, 1),
                expectedAmountMinor: membership.feeOverrideMinor ??
                    plans[membership.planId]?.priceMinor ??
                    0,
              ),
            );
        created++;
      }
    });

    return created;
  }

  DateTime _currentCycleStart({
    required List<MembershipPeriod> periods,
    required int duration,
    required DateTime today,
  }) {
    final monthStart = DateTime.utc(today.year, today.month, 1);
    if (periods.isEmpty) return monthStart;

    // Walk forward from the last cycle in steps of the plan length until the
    // cycle would contain today.
    var start = periods.last.periodStart.toUtc();
    if (start.isAfter(today)) return monthStart;

    // Bounded so a membership left untouched for years cannot spin here.
    for (var i = 0; i < 240; i++) {
      final end = DateTime.utc(start.year, start.month + duration, 1);
      if (today.isBefore(end)) return start;
      start = end;
    }
    return monthStart;
  }
}
