import 'dart:math' as math;

import 'billing_cycle.dart';

/// How one payment is spread across billing cycles.
///
/// A cycle is settled when the money recorded against it reaches the fee it
/// expects — not merely because some payment exists. That distinction is what
/// makes a part-payment visible, and what lets a member hand over three
/// months' fees in one go and get one receipt for all three cycles.
///
/// Everything here is pure integer arithmetic on minor units. No rounding, no
/// floating point, and no clock: the caller reads the cycles out of the
/// database and this decides where the money goes.

/// A cycle the allocator may put money into.
class SettleableCycle {
  const SettleableCycle({
    this.periodId,
    required this.start,
    required this.end,
    required this.expectedMinor,
    this.collectedMinor = 0,
    this.isTransition = false,
  });

  /// Builds one from a computed cycle that has no database row yet.
  SettleableCycle.fromCycle(
    BillingCycle cycle, {
    required this.expectedMinor,
  })  : periodId = null,
        start = cycle.start,
        end = cycle.end,
        collectedMinor = 0,
        isTransition = cycle.isTransition;

  /// Null for a cycle that does not exist yet — the caller inserts it only if
  /// the plan actually puts money into it, so nobody accrues debt for a month
  /// they were merely offered.
  final int? periodId;

  final DateTime start;
  final DateTime end;

  /// The fee this cycle expects, snapshotted when it was opened.
  final int expectedMinor;

  /// Already recorded against it by earlier payments.
  final int collectedMinor;

  final bool isTransition;

  /// Never negative: an overpaid cycle owes nothing rather than owing a
  /// negative amount that would silently fund the next one.
  int get outstandingMinor => math.max(0, expectedMinor - collectedMinor);

  bool get isSettled => outstandingMinor == 0;

  bool get isPartial => collectedMinor > 0 && !isSettled;

  BillingCycle get cycle =>
      BillingCycle(start: start, end: end, isTransition: isTransition);

  SettleableCycle copyWith({int? periodId, int? collectedMinor}) =>
      SettleableCycle(
        periodId: periodId ?? this.periodId,
        start: start,
        end: end,
        expectedMinor: expectedMinor,
        collectedMinor: collectedMinor ?? this.collectedMinor,
        isTransition: isTransition,
      );
}

/// Money going into one cycle.
class CycleAllocation {
  const CycleAllocation({required this.cycle, required this.amountMinor});

  final SettleableCycle cycle;
  final int amountMinor;

  /// Whether this allocation closes the cycle, rather than only reducing what
  /// it still owes.
  bool get settles => amountMinor >= cycle.outstandingMinor;
}

/// Where a payment's money goes, and what is left over.
class AllocationPlan {
  const AllocationPlan({
    required this.allocations,
    required this.unallocatedMinor,
  });

  final List<CycleAllocation> allocations;

  /// Money that fitted nowhere, because every cycle offered was already full.
  ///
  /// Reported rather than absorbed: the caller decides whether to offer more
  /// cycles or refuse the payment. Money quietly vanishing into a rounding
  /// remainder is the one outcome this class exists to prevent.
  final int unallocatedMinor;

  bool get isEmpty => allocations.isEmpty;

  int get allocatedMinor =>
      allocations.fold(0, (sum, a) => sum + a.amountMinor);

  /// The cycles this plan closes, oldest first.
  List<CycleAllocation> get settling =>
      allocations.where((a) => a.settles).toList();

  /// The cycle left part-paid, if the money ran out partway through one.
  CycleAllocation? get partial {
    if (allocations.isEmpty) return null;
    final last = allocations.last;
    return last.settles ? null : last;
  }

  /// The span the money covers, for the receipt and the audit line. Null when
  /// nothing was allocated.
  BillingCycle? get coveredSpan {
    if (allocations.isEmpty) return null;
    return BillingCycle(
      start: allocations.first.cycle.start,
      end: allocations.last.cycle.end,
    );
  }
}

/// Spreads [amountMinor] over [cycles] in the order given, filling each cycle's
/// outstanding balance before moving on to the next.
///
/// Oldest first is the caller's job, and is what makes an arrears payment land
/// on the month actually owed rather than on the current one. Cycles already
/// settled are skipped rather than allocated zero, so a plan never contains a
/// row that changes nothing.
AllocationPlan allocate({
  required int amountMinor,
  required List<SettleableCycle> cycles,
}) {
  if (amountMinor <= 0) {
    return AllocationPlan(
      allocations: const [],
      unallocatedMinor: math.max(0, amountMinor),
    );
  }

  final allocations = <CycleAllocation>[];
  var remaining = amountMinor;

  for (final cycle in cycles) {
    if (remaining <= 0) break;
    if (cycle.isSettled) continue;

    final into = math.min(remaining, cycle.outstandingMinor);
    allocations.add(CycleAllocation(cycle: cycle, amountMinor: into));
    remaining -= into;
  }

  return AllocationPlan(
    allocations: allocations,
    unallocatedMinor: remaining,
  );
}

/// What a cycle has collected against what it expects.
class Settlement {
  const Settlement({
    required this.expectedMinor,
    required this.collectedMinor,
  });

  final int expectedMinor;
  final int collectedMinor;

  int get outstandingMinor => math.max(0, expectedMinor - collectedMinor);

  /// A cycle expecting nothing is settled: a free month is not a debt.
  bool get isSettled => outstandingMinor == 0;

  bool get isPartial => collectedMinor > 0 && !isSettled;
}
