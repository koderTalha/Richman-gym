import '../domain/billing_period.dart';
import 'database.dart';

/// Which billing cycles a payment paid for, and how to name them.
///
/// `payments.membership_period_id` names only the *first* cycle a payment
/// touched. A payment of three months' fees is spread over three cycles by its
/// `payment_allocations` rows, so every label built from that one column read
/// "January 2026" for money that bought January, February and March — on the
/// payment history, the Receipts list, and the delete confirmation that warns
/// which months will read as due again.
///
/// These helpers read the allocations instead, and fall back to the column
/// only for a payment that has none: a database predating allocations, or a
/// raw row written straight to `payments`.

/// One cycle a payment paid towards, with the length of the plan it was
/// billed under — which is what the label's month range is measured in.
class PaidCycle {
  const PaidCycle({required this.period, required this.durationMonths});

  final MembershipPeriod period;

  /// Months the cycle's plan runs for. At least 1.
  final int durationMonths;
}

/// The cycles each of [payments] paid for, oldest first, keyed by payment id.
///
/// A payment with allocations is read from them alone; one without falls back
/// to its `membershipPeriodId`. A payment with neither — money taken against
/// no cycle at all — is absent from the map.
///
/// A handful of queries for the whole batch rather than a handful per
/// payment, so a page of history costs the same however many months each row
/// covers. Bounded by the caller's batch: pass a page, not the whole table.
Future<Map<int, List<PaidCycle>>> cyclesPaidBy(
  AppDatabase db,
  Iterable<Payment> payments,
) async {
  final list = payments.toList();
  if (list.isEmpty) return const {};

  final allocations = await (db.select(db.paymentAllocations)
        ..where((a) => a.paymentId.isIn([for (final p in list) p.id])))
      .get();

  final periodIdsByPayment = periodIdsPaidBy(list, allocations);
  final periodIds = {
    for (final ids in periodIdsByPayment.values) ...ids,
  }.toList();
  if (periodIds.isEmpty) return const {};

  final periods = await (db.select(db.membershipPeriods)
        ..where((p) => p.id.isIn(periodIds)))
      .get();
  final membershipIds = periods.map((p) => p.membershipId).toSet().toList();
  final memberships = await (db.select(db.memberships)
        ..where((m) => m.id.isIn(membershipIds)))
      .get();
  final plans = await db.select(db.membershipPlans).get();

  return paidCyclesFrom(
    periodIdsByPayment: periodIdsByPayment,
    periods: periods,
    memberships: memberships,
    plans: plans,
  );
}

/// Every cycle id each payment paid towards, from rows already in memory.
///
/// The rule [cyclesPaidBy] applies, split out so a caller that has loaded the
/// whole tables anyway — the Excel export — can apply it without a second
/// round of queries, and without an `IN` list as long as the payments table.
/// Payments with no cycle at all are left out.
Map<int, Set<int>> periodIdsPaidBy(
  Iterable<Payment> payments,
  Iterable<PaymentAllocation> allocations,
) {
  final byPayment = <int, Set<int>>{};
  for (final allocation in allocations) {
    byPayment
        .putIfAbsent(allocation.paymentId, () => <int>{})
        .add(allocation.membershipPeriodId);
  }

  final result = <int, Set<int>>{};
  for (final payment in payments) {
    final allocated = byPayment[payment.id];
    if (allocated != null && allocated.isNotEmpty) {
      result[payment.id] = allocated;
    } else if (payment.membershipPeriodId != null) {
      result[payment.id] = {payment.membershipPeriodId!};
    }
  }
  return result;
}

/// Joins [periodIdsByPayment] to the cycles and plan lengths it names, oldest
/// cycle first within each payment. Ids that name no loaded cycle are dropped,
/// and a payment left with none is absent from the result.
Map<int, List<PaidCycle>> paidCyclesFrom({
  required Map<int, Set<int>> periodIdsByPayment,
  required Iterable<MembershipPeriod> periods,
  required Iterable<Membership> memberships,
  required Iterable<MembershipPlan> plans,
}) {
  final periodById = {for (final p in periods) p.id: p};
  final planIdByMembership = {for (final m in memberships) m.id: m.planId};
  final durationByPlan = {for (final p in plans) p.id: p.durationMonths};

  final result = <int, List<PaidCycle>>{};
  periodIdsByPayment.forEach((paymentId, ids) {
    final cycles = <PaidCycle>[
      for (final id in ids)
        if (periodById[id] case final period?)
          PaidCycle(
            period: period,
            durationMonths:
                durationByPlan[planIdByMembership[period.membershipId]] ?? 1,
          ),
    ]..sort((a, b) => a.period.periodStart.compareTo(b.period.periodStart));
    if (cycles.isNotEmpty) result[paymentId] = cycles;
  });
  return result;
}

/// The months [cycles] cover, as the owner reads them: "January 2026", or
/// "January 2026 - March 2026" for a run of months, in the same wording
/// [formatBillingPeriod] gives a single multi-month cycle.
///
/// Each cycle covers its start month and the plan's further months; touching
/// or overlapping runs are joined into one span. A gap is kept as a gap —
/// "January 2026, April 2026" — because money allocated arrears-first can
/// clear an old month and a future one while skipping months already paid,
/// and one span across the gap would claim the payment bought those too.
///
/// For a payment covering one cycle this is exactly the label the app has
/// always shown. Null for no cycles.
String? formatPaidCycles(Iterable<PaidCycle> cycles) {
  // Months as a single running index (year * 12 + month - 1), so a span
  // crossing new year is plain arithmetic.
  final spans = <({int first, int last})>[
    for (final cycle in cycles)
      () {
        final start = cycle.period.periodStart.toUtc();
        final first = start.year * 12 + start.month - 1;
        final length = cycle.durationMonths < 1 ? 1 : cycle.durationMonths;
        return (first: first, last: first + length - 1);
      }(),
  ]..sort((a, b) => a.first.compareTo(b.first));
  if (spans.isEmpty) return null;

  final runs = <({int first, int last})>[spans.first];
  for (final span in spans.skip(1)) {
    final current = runs.last;
    if (span.first <= current.last + 1) {
      runs[runs.length - 1] = (
        first: current.first,
        last: span.last > current.last ? span.last : current.last,
      );
    } else {
      runs.add(span);
    }
  }

  return runs
      .map((run) => formatBillingPeriod(
            DateTime.utc(run.first ~/ 12, run.first % 12 + 1, 1),
            run.last - run.first + 1,
          ))
      .join(', ');
}

/// [formatPaidCycles] for each of [payments], keyed by payment id. A payment
/// that paid for no cycle is absent; callers show their own placeholder.
Future<Map<int, String>> paymentPeriodLabels(
  AppDatabase db,
  Iterable<Payment> payments,
) async {
  final cycles = await cyclesPaidBy(db, payments);
  return {
    for (final entry in cycles.entries)
      entry.key: ?formatPaidCycles(entry.value),
  };
}

/// [paymentPeriodLabels] for one payment, or null if it paid for no cycle.
///
/// Safe to call inside a transaction — drift routes the reads through it — so
/// a caller about to delete or re-send a payment can name the months it
/// covered from the same snapshot it is acting on. Read it *before* deleting:
/// the allocations go with the payment.
Future<String?> paymentPeriodLabel(AppDatabase db, Payment payment) async =>
    (await paymentPeriodLabels(db, [payment]))[payment.id];
