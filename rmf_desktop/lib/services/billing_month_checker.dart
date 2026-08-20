import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/membership_queries.dart';
import '../data/settings_repository.dart';
import '../domain/billing_month_check.dart';
import '../domain/billing_period.dart';

/// Gathers the facts the billing-month rules need, then applies them.
///
/// The rules themselves live in `domain/billing_month_check.dart` and know
/// nothing about the database. This is the half that does the reading, and it
/// is the single place both Record Payment and Edit Payment go through — there
/// is deliberately no second copy of these questions anywhere.
class BillingMonthChecker {
  BillingMonthChecker(this.db, {SettingsRepository? settings})
      : _settings = settings ?? SettingsRepository(db);

  final AppDatabase db;
  final SettingsRepository _settings;

  /// Checks [billingMonth] ("YYYY-MM") for [memberId].
  ///
  /// [excludePaymentId] is the payment being edited, so it is never treated as
  /// its own duplicate. [now] is injectable so the "too far ahead" rule can be
  /// tested without depending on the day the suite runs.
  Future<BillingMonthCheck> check({
    required int memberId,
    required String billingMonth,
    int? excludePaymentId,
    DateTime? now,
  }) async {
    final selectedStart = parseBillingMonth(billingMonth);

    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(memberId)))
        .getSingleOrNull();
    if (member == null) {
      throw StateError('Member $memberId no longer exists');
    }

    final memberships = await allMembershipsFor(db, memberId);
    final planById = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };
    final durationOfMembership = {
      for (final m in memberships)
        m.id: planById[m.planId]?.durationMonths ?? 1,
    };

    // The cycle covering the selected month, on any enrolment. Containment,
    // not start-of-month equality — see periodForMemberContaining.
    final containing = await periodForMemberContaining(
      db,
      memberId: memberId,
      month: selectedStart,
    );

    // Which plan governs the selected cycle: the one its cycle was opened
    // under if it exists, otherwise the plan the member is on now, because
    // that is what a new cycle would be created under.
    final open = await openMembershipFor(db, memberId);
    final governing = containing == null
        ? open
        : memberships.firstWhere(
            (m) => m.id == containing.membershipId,
            orElse: () => open ?? memberships.first,
          );
    final plan = governing == null ? null : planById[governing.planId];

    // No plan at all: nothing can say how long a cycle is, so the rules cannot
    // meaningfully run. Reported rather than guessed at.
    if (plan == null) {
      return BillingMonthCheck(
        review: const BillingMonthReview.clean(),
        period: containing,
        plan: null,
        durationMonths: 1,
        member: member,
      );
    }

    // Every rule is about the cycle, so a month falling inside an existing one
    // is judged as that cycle — not as a cycle that would start mid-quarter.
    final cycleStart = (containing?.periodStart ?? selectedStart).toUtc();

    final periods = await periodsForMember(db, memberId);
    final paidPeriodIds = await _paidPeriodIds(
      memberId: memberId,
      excludePaymentId: excludePaymentId,
    );

    final unpaidEarlier = [
      for (final period in periods)
        if (period.periodStart.toUtc().isBefore(cycleStart) &&
            !paidPeriodIds.contains(period.id))
          UnpaidCycle(
            periodStart: period.periodStart.toUtc(),
            durationMonths: durationOfMembership[period.membershipId] ?? 1,
          ),
    ];

    final existing = containing == null
        ? null
        : await _paymentOnPeriod(
            periodId: containing.id,
            excludePaymentId: excludePaymentId,
          );

    final settings = await _settings.get();

    final review = reviewBillingMonth(BillingMonthFacts(
      memberName: member.fullName,
      cycleStart: cycleStart,
      durationMonths: plan.durationMonths,
      joiningDate: member.joiningDate,
      today: now ?? DateTime.now(),
      unpaidEarlierCycles: unpaidEarlier,
      existingPayment: existing == null
          ? null
          : ExistingCyclePayment(
              amountMinor: existing.amountMinor,
              paymentDate: existing.paymentDate,
            ),
      currency: settings.currency,
    ));

    return BillingMonthCheck(
      review: review,
      period: containing,
      plan: plan,
      durationMonths: plan.durationMonths,
      member: member,
    );
  }

  Future<Set<int>> _paidPeriodIds({
    required int memberId,
    int? excludePaymentId,
  }) async {
    var query = db.select(db.payments)
      ..where((p) => p.memberId.equals(memberId) &
          p.membershipPeriodId.isNotNull());
    if (excludePaymentId != null) {
      query = query..where((p) => p.id.equals(excludePaymentId).not());
    }
    return (await query.get())
        .map((p) => p.membershipPeriodId)
        .whereType<int>()
        .toSet();
  }

  Future<Payment?> _paymentOnPeriod({
    required int periodId,
    int? excludePaymentId,
  }) async {
    var query = db.select(db.payments)
      ..where((p) => p.membershipPeriodId.equals(periodId));
    if (excludePaymentId != null) {
      query = query..where((p) => p.id.equals(excludePaymentId).not());
    }
    final rows = await (query..limit(1)).get();
    return rows.isEmpty ? null : rows.first;
  }
}

/// The review, plus the cycle and plan it was resolved against.
///
/// Both callers need those two anyway — the recorder to decide whether to open
/// a cycle, the editor to decide where the payment is moving to — and handing
/// them back here means the lookup happens once and cannot disagree with the
/// answer the rules were given.
class BillingMonthCheck {
  const BillingMonthCheck({
    required this.review,
    required this.period,
    required this.plan,
    required this.durationMonths,
    required this.member,
  });

  final BillingMonthReview review;

  /// The existing cycle containing the selected month, or null if the month is
  /// not covered by one yet.
  final MembershipPeriod? period;

  /// Null only when the member has no enrolment at all, in which case there is
  /// nothing to bill and the caller must refuse.
  final MembershipPlan? plan;

  final int durationMonths;
  final Member member;

  bool get hasPlan => plan != null;
}
