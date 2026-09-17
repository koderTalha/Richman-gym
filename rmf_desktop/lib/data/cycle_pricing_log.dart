import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import 'database.dart';

final _log = Logger('billing');

/// Why a billing cycle carries the amount it does.
///
/// `membership_periods.expected_amount_minor` is the current answer and says
/// nothing about how it was arrived at. That gap is the whole of the gym's
/// second problem: forty-three cycles billed 4,000 with nothing to say whether
/// that was the plan the member was on, or the plan they had already been
/// moved off. Both leave the identical row, and once the distinction is gone
/// only a human can put it back.
///
/// So every write to a cycle's price is paired with a row here saying where the
/// figure came from. Append-only: the row that opened the cycle is never
/// altered, which is what keeps the original bill recoverable after a
/// correction.
///
/// Nothing in this file reads the clock — callers pass [at] in, the same
/// bargain `BillingMaintenance` and `cycle_repricing.dart` make.

/// Records one pricing decision about [membershipPeriodId].
///
/// Never throws. A cycle whose provenance could not be written is worse
/// documented than it should be; it is not worth failing the payment,
/// re-pricing or correction that was the actual point of the transaction. The
/// failure is logged at severe level rather than swallowed, the same bargain
/// [AuditRepository.record] makes.
Future<void> recordCyclePricing(
  AppDatabase db, {
  required int membershipPeriodId,
  required int amountMinor,
  required CyclePricingSource source,
  int? previousAmountMinor,
  int? planId,
  int? planPriceMinor,
  int? feeOverrideMinor,
  String? reason,
  int? actorId,
  DateTime? at,
}) async {
  try {
    await db.into(db.cyclePricings).insert(CyclePricingsCompanion.insert(
          membershipPeriodId: membershipPeriodId,
          amountMinor: amountMinor,
          previousAmountMinor: Value(previousAmountMinor),
          source: source,
          planId: Value(planId),
          planPriceMinor: Value(planPriceMinor),
          feeOverrideMinor: Value(feeOverrideMinor),
          reason: Value(reason),
          actorId: Value(actorId),
          recordedAt: Value((at ?? DateTime.now()).toUtc()),
        ));
  } catch (error, stack) {
    _log.severe(
      'The pricing reason for billing cycle $membershipPeriodId could not be '
      'stored. The cycle itself is unaffected.',
      error,
      stack,
    );
  }
}

/// Records the opening price of a cycle resolved from an enrolment.
///
/// The shape five of the six places that open a cycle need, so the
/// `feeOverrideMinor ?? plan.priceMinor` rule is not spelled out — and cannot
/// drift — once per call site.
///
/// [amountMinor] is passed explicitly rather than re-derived: a cycle opened
/// from the Record Payment form can carry a figure the owner typed for that
/// month specifically, and this must describe the number actually written.
Future<void> recordCycleOpened(
  AppDatabase db, {
  required int membershipPeriodId,
  required int amountMinor,
  required Membership membership,
  MembershipPlan? plan,
  CyclePricingSource? source,
  String? reason,
  int? actorId,
  DateTime? at,
}) =>
    recordCyclePricing(
      db,
      membershipPeriodId: membershipPeriodId,
      amountMinor: amountMinor,
      source: source ?? sourceFor(membership),
      planId: membership.planId,
      planPriceMinor: plan?.priceMinor,
      feeOverrideMinor: membership.feeOverrideMinor,
      reason: reason,
      actorId: actorId,
      at: at,
    );

/// Whether a member's fee comes from their own override or from their plan.
///
/// The same `feeOverrideMinor ?? plan.priceMinor` rule `repriceOpenCycles` and
/// `PricingSummary` resolve, expressed as the reason rather than the number.
CyclePricingSource sourceFor(Membership membership) =>
    membership.feeOverrideMinor != null
        ? CyclePricingSource.feeOverride
        : CyclePricingSource.plan;

/// Every pricing decision recorded for [periodId], oldest first.
Future<List<CyclePricing>> pricingHistoryFor(
  AppDatabase db,
  int periodId,
) =>
    (db.select(db.cyclePricings)
          ..where((c) => c.membershipPeriodId.equals(periodId))
          ..orderBy([
            (c) => OrderingTerm(expression: c.recordedAt),
            (c) => OrderingTerm(expression: c.id),
          ]))
        .get();

/// What [periodId] was originally billed, if that is recorded.
///
/// The row with no [CyclePricings.previousAmountMinor] is the one that opened
/// the cycle, whatever has happened to it since. Null for a cycle recorded
/// before v12, or one whose provenance write failed — callers fall back to the
/// cycle's current amount and say so rather than inventing a history.
Future<CyclePricing?> originalPricingFor(AppDatabase db, int periodId) async {
  final rows = await (db.select(db.cyclePricings)
        ..where((c) =>
            c.membershipPeriodId.equals(periodId) &
            c.previousAmountMinor.isNull())
        ..orderBy([(c) => OrderingTerm(expression: c.id)])
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.first;
}

/// Which of [periodIds] an owner has already ruled on.
///
/// A cycle corrected, or deliberately left alone, is a question that has been
/// answered. Asking it again every morning would make the review screen a list
/// the owner learns to ignore — the same reason
/// `reportBillingDiscrepancies` reports each member only once.
Future<Set<int>> periodsAlreadyReviewed(
  AppDatabase db,
  List<int> periodIds,
) async {
  if (periodIds.isEmpty) return const {};

  final rows = await (db.selectOnly(db.cyclePricings, distinct: true)
        ..addColumns([db.cyclePricings.membershipPeriodId])
        ..where(db.cyclePricings.membershipPeriodId.isIn(periodIds) &
            db.cyclePricings.source.isIn([
              CyclePricingSource.correction.name,
              CyclePricingSource.reviewConfirmed.name,
            ])))
      .get();

  return rows
      .map((row) => row.read(db.cyclePricings.membershipPeriodId))
      .whereType<int>()
      .toSet();
}
