import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/cycle_pricing_log.dart';
import '../data/database.dart';
import '../data/membership_history.dart';
import '../data/membership_queries.dart';
import '../domain/dates.dart';
import '../domain/money.dart';

final _log = Logger('billing');

/// Months that ended while carrying a price the member had already been moved
/// off, and the owner-approved way to put one right.
///
/// `cycle_repricing.dart` will not touch a cycle that has ended, and that guard
/// is correct: arrears were incurred at the price in force at the time, and a
/// member who genuinely owes August must still owe August's fee. But it also
/// catches the case the guard was never aimed at. A member moved onto a
/// cheaper plan part way through August, whose August cycle had already opened
/// at the dearer one, ends the month owing a difference that was never a real
/// bill — and the guard seals it for ever.
///
/// **The two are identical in the database.** Scenario A — the member really
/// did owe 4,000 and paid 2,500 — and scenario B — they were only ever meant
/// to be charged 2,500 and the cycle opened under the wrong plan — leave the
/// same rows. Nothing here pretends otherwise:
///
///   * It produces **candidates**, never corrections. Every change goes
///     through [applyBillingCorrection], and only after the owner has said so
///     on screen.
///   * It asks for **evidence**, not a coincidence. A cycle priced above
///     today's fee is not enough on its own; there must be a recorded move to
///     a cheaper fee that was meant to apply from on or before that cycle
///     began. That is the one thing scenario B leaves behind and scenario A
///     does not.
///   * A decision, either way, is **recorded and final**. A cycle the owner has
///     ruled on is not offered again — see `periodsAlreadyReviewed`.
///
/// Nothing here reads the clock — callers pass [now] in, the same bargain
/// `BillingMaintenance` and `billing_reconciliation.dart` make.

/// One ended, unsettled cycle worth asking the owner about.
class HistoricalPricingCandidate {
  const HistoricalPricingCandidate({
    required this.member,
    required this.period,
    required this.billedMinor,
    required this.collectedMinor,
    required this.currentFeeMinor,
    required this.currentPlanName,
    required this.evidence,
    this.originalBilledMinor,
  });

  final Member member;
  final MembershipPeriod period;

  /// What the cycle is asking for now.
  final int billedMinor;

  /// What has actually been allocated against it.
  final int collectedMinor;

  /// What the member is billed today — the figure a correction would move it
  /// to. Never above [billedMinor]: a review may only ever reduce a bill.
  final int currentFeeMinor;

  final String currentPlanName;

  /// Why this cycle is being asked about, in the owner's language. Shown on
  /// screen and copied into the audit trail, so a decision taken today is
  /// still explainable next year.
  final List<String> evidence;

  /// What the cycle was first opened at, where that is recorded. Null for
  /// every cycle predating the pricing history — which is all of them on the
  /// day this ships, and why nothing here depends on it.
  final int? originalBilledMinor;

  /// What the app currently says is owed.
  int get outstandingMinor => math.max(0, billedMinor - collectedMinor);

  /// What would still be owed after a correction. Not always zero: a member
  /// who paid 2,200 against a corrected fee of 2,500 genuinely owes 300, and
  /// the review must not quietly forgive it.
  int get outstandingAfterMinor =>
      math.max(0, currentFeeMinor - collectedMinor);

  /// How much the bill would fall by.
  int get reductionMinor => math.max(0, billedMinor - currentFeeMinor);

  String get periodLabel => '${formatDayMonthYear(period.periodStart)} to '
      '${formatDayMonthYear(period.periodEnd)}';
}

/// Ended, unsettled cycles priced above what the member is billed now, where
/// something in the record says the price should already have moved.
///
/// Read-only. Nothing in this function writes.
Future<List<HistoricalPricingCandidate>> detectHistoricalPricingAnomalies(
  AppDatabase db, {
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).toUtc();
  final today = DateTime.utc(at.year, at.month, at.day);

  // A member who has left the gym is not re-billed and is not reviewed either.
  // The same first question `repriceOpenCycles` asks.
  final members = await (db.select(db.members)
        ..where((m) => m.deactivatedAt.isNull()))
      .get();

  final plans = {
    for (final p in await db.select(db.membershipPlans).get()) p.id: p
  };

  final found = <HistoricalPricingCandidate>[];

  for (final member in members) {
    final membership = await openMembershipFor(db, member.id);
    if (membership == null) continue;

    final plan = plans[membership.planId];
    if (plan == null) continue;

    final currentFee = membership.feeOverrideMinor ?? plan.priceMinor;

    final ended = [
      for (final period in await periodsForMember(db, member.id))
        // Guard (c) territory: exactly the cycles ordinary re-pricing refuses,
        // which is why they need a human rather than a sweep.
        if (period.settledAt == null &&
            !period.periodEnd.toUtc().isAfter(today) &&
            period.expectedAmountMinor > currentFee)
          period,
    ];
    if (ended.isEmpty) continue;

    final ids = [for (final period in ended) period.id];
    final decided = await periodsAlreadyReviewed(db, ids);
    final collected = await collectedByPeriod(db, ids);
    final changes = await membershipChangesFor(db, member.id);

    for (final period in ended) {
      if (decided.contains(period.id)) continue;

      final evidence = await _evidenceFor(
        db,
        memberId: member.id,
        period: period,
        changes: changes,
        currentFee: currentFee,
        planName: plan.name,
      );
      // No evidence, no candidate. A cycle can sit above today's fee for
      // reasons that are nobody's mistake — a discount that has since ended, a
      // short month typed up from the paper ledger — and offering those for
      // "correction" would be the app inventing debt relief.
      if (evidence.isEmpty) continue;

      final original = await originalPricingFor(db, period.id);

      found.add(HistoricalPricingCandidate(
        member: member,
        period: period,
        billedMinor: period.expectedAmountMinor,
        collectedMinor: collected[period.id] ?? 0,
        currentFeeMinor: currentFee,
        currentPlanName: plan.name,
        evidence: evidence,
        originalBilledMinor: original?.amountMinor,
      ));
    }
  }

  found.sort((a, b) {
    final byDate = a.period.periodStart.compareTo(b.period.periodStart);
    return byDate != 0 ? byDate : a.member.memberCode.compareTo(b.member.memberCode);
  });
  return found;
}

/// What, in the record, suggests this cycle was priced under a plan the member
/// had already left.
///
/// Empty means nothing does, and the cycle is not offered for review.
Future<List<String>> _evidenceFor(
  AppDatabase db, {
  required int memberId,
  required MembershipPeriod period,
  required List<MembershipChange> changes,
  required int currentFee,
  required String planName,
}) async {
  final evidence = <String>[];
  final start = period.periodStart.toUtc();

  // --- 1. A recorded fee cut that was meant to apply by the time this cycle
  //        was billed. The strongest evidence there is, because it is the
  //        owner's own statement about when the new fee began.
  for (final cut in cutsCovering(changes, periodStart: start)) {
    final backdated = cut.recordedAt.toUtc().isAfter(
        DateTime.utc(cut.effectiveFrom.toUtc().year,
            cut.effectiveFrom.toUtc().month, cut.effectiveFrom.toUtc().day));

    evidence.add(
      '${formatMinorUnits(cut.previousFeeMinor!)} → '
      '${formatMinorUnits(cut.feeMinor!)} from '
      '${formatDayMonthYear(cut.effectiveFrom)}'
      '${cut.previousPlanName != null && cut.planName != null ? ' '
          '(${cut.previousPlanName} → ${cut.planName})' : ''}'
      '${backdated ? ', entered on '
          '${formatDayMonthYear(cut.recordedAt)}' : ''}'
      ' — this month was billed at ${formatMinorUnits(period.expectedAmountMinor)} '
      'after that date.',
    );
  }

  // --- 2. The enrolment the member was moved onto after this cycle opened.
  //        The only evidence available for the members already stranded: they
  //        were moved before any of this existed to record it, and all that
  //        survives is a newer enrolment on a cheaper plan.
  if (evidence.isEmpty) {
    final later = [
      for (final m in await allMembershipsFor(db, memberId))
        if (m.startDate.toUtc().isAfter(start)) m,
    ]..sort((a, b) => a.startDate.compareTo(b.startDate));

    for (final membership in later) {
      final plan = await (db.select(db.membershipPlans)
            ..where((p) => p.id.equals(membership.planId)))
          .getSingleOrNull();
      final fee = membership.feeOverrideMinor ?? plan?.priceMinor;
      if (fee == null || fee >= period.expectedAmountMinor) continue;

      evidence.add(
        'Moved onto ${plan?.name ?? 'another plan'} at '
        '${formatMinorUnits(fee)} on '
        '${formatDayMonthYear(membership.startDate)}, while this month was '
        'already open at ${formatMinorUnits(period.expectedAmountMinor)}.',
      );
      break;
    }
  }

  if (evidence.isEmpty) return const [];

  evidence.add('They are billed ${formatMinorUnits(currentFee)} today '
      '($planName).');
  return evidence;
}

/// Lowers one historical cycle to [correctedAmountMinor], with the owner's
/// approval and a trail back to what it was.
///
/// The one place in the app that may change an ended cycle's price. Everything
/// it does is deliberately narrow:
///
///   * It only ever goes **down**. A review that could raise a historical bill
///     would be a way to backdate a charge onto somebody who has already paid,
///     which is the thing guard (b) exists to prevent.
///   * It touches **no payment and no allocation**. The money the member
///     handed over is reported exactly as it was; only what the gym asked for
///     moves.
///   * It writes the reasoning to `cycle_pricings` **in the same transaction**,
///     so a corrected figure with no record of the original cannot exist.
///   * Settlement is recomputed from the allocations, so a cut that now covers
///     the cycle closes it and one that does not leaves the member owing the
///     remainder. Nothing is forgiven beyond the price change itself.
Future<BillingCorrectionResult> applyBillingCorrection(
  AppDatabase db, {
  required int periodId,
  required int correctedAmountMinor,
  required String reason,
  int? actorId,
  AuditRepository? audit,
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).toUtc();

  final period = await (db.select(db.membershipPeriods)
        ..where((p) => p.id.equals(periodId)))
      .getSingleOrNull();
  if (period == null) {
    return const BillingCorrectionRefused('That billing month no longer exists.');
  }
  if (correctedAmountMinor > period.expectedAmountMinor) {
    return const BillingCorrectionRefused(
      'A review can only lower a past bill, never raise it.',
    );
  }
  if (correctedAmountMinor < 0) {
    return const BillingCorrectionRefused('A bill cannot be negative.');
  }
  if (period.settledAt != null) {
    return const BillingCorrectionRefused(
      'That month is already settled, so there is nothing to correct.',
    );
  }

  final collected = (await collectedByPeriod(db, [periodId]))[periodId] ?? 0;
  final member = await _memberForPeriod(db, period);

  await db.transaction(() async {
    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(periodId)))
        .write(MembershipPeriodsCompanion(
          expectedAmountMinor: Value(correctedAmountMinor),
          // Recomputed in the same write, for the reason `repriceOpenCycles`
          // gives: a cut is often the very thing that closes the cycle, and a
          // stamp that disagreed with the money behind it is what
          // `refreshSettlement` exists to prevent everywhere else. The cycle
          // arrived unsettled, so this can only ever close one.
          settledAt: Value(collected >= correctedAmountMinor ? at : null),
        ));

    await recordCyclePricing(
      db,
      membershipPeriodId: periodId,
      amountMinor: correctedAmountMinor,
      previousAmountMinor: period.expectedAmountMinor,
      source: CyclePricingSource.correction,
      reason: reason,
      actorId: actorId,
      at: at,
    );
  });

  await (audit ?? AuditRepository(db)).record(
    category: AuditCategory.billing,
    action: AuditAction.billingHistoricalCorrection,
    outcome: AuditOutcome.success,
    actorId: actorId,
    memberId: member?.id,
    memberName: member?.fullName,
    amountMinor: correctedAmountMinor,
    periodLabel: '${formatDayMonthYear(period.periodStart)} to '
        '${formatDayMonthYear(period.periodEnd)}',
    summary: '${member?.fullName ?? 'A member'}: the bill for '
        '${formatDayMonthYear(period.periodStart)} was corrected from '
        '${formatMinorUnits(period.expectedAmountMinor)} to '
        '${formatMinorUnits(correctedAmountMinor)}',
    detail: [
      reason,
      'Collected against this month: ${formatMinorUnits(collected)}.',
      if (collected >= correctedAmountMinor)
        'The month is now settled.'
      else
        'Still owing: '
            '${formatMinorUnits(correctedAmountMinor - collected)}.',
      'No payment or allocation was changed. The original bill of '
          '${formatMinorUnits(period.expectedAmountMinor)} is kept in the '
          "cycle's pricing history.",
    ],
  );

  _log.info('Historical bill for cycle $periodId corrected from '
      '${period.expectedAmountMinor} to $correctedAmountMinor');

  return BillingCorrectionApplied(
    previousAmountMinor: period.expectedAmountMinor,
    correctedAmountMinor: correctedAmountMinor,
    settled: collected >= correctedAmountMinor,
  );
}

/// Records that the owner looked at a historical bill and left it alone.
///
/// Not a no-op. "This bill was checked and it stands" is an answer, and
/// writing it down is what stops the same ten months being offered every
/// morning until the owner stops reading the screen. No money moves.
Future<void> keepHistoricalPrice(
  AppDatabase db, {
  required int periodId,
  required String reason,
  int? actorId,
  AuditRepository? audit,
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).toUtc();

  final period = await (db.select(db.membershipPeriods)
        ..where((p) => p.id.equals(periodId)))
      .getSingleOrNull();
  if (period == null) return;

  final member = await _memberForPeriod(db, period);

  await recordCyclePricing(
    db,
    membershipPeriodId: periodId,
    amountMinor: period.expectedAmountMinor,
    previousAmountMinor: period.expectedAmountMinor,
    source: CyclePricingSource.reviewConfirmed,
    reason: reason,
    actorId: actorId,
    at: at,
  );

  await (audit ?? AuditRepository(db)).record(
    category: AuditCategory.billing,
    action: AuditAction.billingHistoricalKept,
    outcome: AuditOutcome.success,
    actorId: actorId,
    memberId: member?.id,
    memberName: member?.fullName,
    amountMinor: period.expectedAmountMinor,
    periodLabel: '${formatDayMonthYear(period.periodStart)} to '
        '${formatDayMonthYear(period.periodEnd)}',
    summary: '${member?.fullName ?? 'A member'}: the bill for '
        '${formatDayMonthYear(period.periodStart)} was reviewed and left at '
        '${formatMinorUnits(period.expectedAmountMinor)}',
    detail: [reason, 'Nothing was changed.'],
  );
}

sealed class BillingCorrectionResult {
  const BillingCorrectionResult();
}

class BillingCorrectionApplied extends BillingCorrectionResult {
  const BillingCorrectionApplied({
    required this.previousAmountMinor,
    required this.correctedAmountMinor,
    required this.settled,
  });

  final int previousAmountMinor;
  final int correctedAmountMinor;

  /// Whether the money already collected now covers the corrected bill.
  final bool settled;
}

class BillingCorrectionRefused extends BillingCorrectionResult {
  const BillingCorrectionRefused(this.reason);
  final String reason;
}

Future<Member?> _memberForPeriod(AppDatabase db, MembershipPeriod period) async {
  final membership = await (db.select(db.memberships)
        ..where((m) => m.id.equals(period.membershipId)))
      .getSingleOrNull();
  if (membership == null) return null;
  return (db.select(db.members)
        ..where((m) => m.id.equals(membership.memberId)))
      .getSingleOrNull();
}
