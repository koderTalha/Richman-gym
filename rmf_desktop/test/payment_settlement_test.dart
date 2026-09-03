import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/billing_cycle.dart';
import 'package:rich_man_fitness/domain/payment_settlement.dart';

/// Where a payment's money goes.
///
/// The property that matters throughout: every paisa handed over is either
/// allocated to a cycle or reported as unallocated. Money must never be able
/// to disappear between the two.
void main() {
  SettleableCycle cycle({
    int? id,
    required int month,
    int expected = 300000,
    int collected = 0,
  }) =>
      SettleableCycle(
        periodId: id,
        start: DateTime.utc(2026, month, 6),
        end: DateTime.utc(2026, month + 1, 6),
        expectedMinor: expected,
        collectedMinor: collected,
      );

  group('allocate', () {
    test('settles a single cycle paid in full', () {
      final plan = allocate(
        amountMinor: 300000,
        cycles: [cycle(id: 1, month: 10)],
      );

      expect(plan.allocations, hasLength(1));
      expect(plan.allocations.single.amountMinor, 300000);
      expect(plan.allocations.single.settles, isTrue);
      expect(plan.unallocatedMinor, 0);
      expect(plan.partial, isNull);
    });

    test('leaves a cycle part-paid when the money runs short', () {
      final plan = allocate(
        amountMinor: 100000,
        cycles: [cycle(id: 1, month: 10)],
      );

      expect(plan.allocations.single.amountMinor, 100000);
      expect(plan.allocations.single.settles, isFalse);
      expect(plan.partial, isNotNull);
      expect(plan.unallocatedMinor, 0);
    });

    test('tops a part-paid cycle up to settled', () {
      final plan = allocate(
        amountMinor: 200000,
        cycles: [cycle(id: 1, month: 10, collected: 100000)],
      );

      expect(plan.allocations.single.amountMinor, 200000);
      expect(plan.allocations.single.settles, isTrue);
      expect(plan.unallocatedMinor, 0);
    });

    test('spreads three months of fees over three cycles', () {
      final plan = allocate(
        amountMinor: 900000,
        cycles: [
          cycle(id: 1, month: 10),
          cycle(id: 2, month: 11),
          cycle(month: 12),
        ],
      );

      expect(plan.allocations, hasLength(3));
      expect(plan.allocations.map((a) => a.amountMinor),
          [300000, 300000, 300000]);
      expect(plan.settling, hasLength(3));
      expect(plan.unallocatedMinor, 0);
      expect(plan.coveredSpan!.start, DateTime.utc(2026, 10, 6));
      expect(plan.coveredSpan!.end, DateTime.utc(2027, 1, 6));
    });

    test('carries a remainder into the next cycle rather than losing it', () {
      final plan = allocate(
        amountMinor: 750000,
        cycles: [
          cycle(id: 1, month: 10),
          cycle(id: 2, month: 11),
          cycle(month: 12),
        ],
      );

      expect(plan.allocations.map((a) => a.amountMinor),
          [300000, 300000, 150000]);
      expect(plan.settling, hasLength(2));
      expect(plan.partial!.amountMinor, 150000);
      expect(plan.unallocatedMinor, 0);
    });

    test('fills arrears before the current cycle', () {
      // Cycles arrive oldest first, which is what makes a member who owes
      // September and October settle September with the first rupee.
      final plan = allocate(
        amountMinor: 300000,
        cycles: [
          cycle(id: 1, month: 9),
          cycle(id: 2, month: 10),
        ],
      );

      expect(plan.allocations.single.cycle.periodId, 1);
      expect(plan.allocations.single.settles, isTrue);
    });

    test('skips a cycle that is already settled', () {
      final plan = allocate(
        amountMinor: 300000,
        cycles: [
          cycle(id: 1, month: 9, collected: 300000),
          cycle(id: 2, month: 10),
        ],
      );

      expect(plan.allocations, hasLength(1));
      expect(plan.allocations.single.cycle.periodId, 2);
    });

    test('reports money that fits nowhere instead of absorbing it', () {
      final plan = allocate(
        amountMinor: 500000,
        cycles: [cycle(id: 1, month: 10)],
      );

      expect(plan.allocations.single.amountMinor, 300000);
      expect(plan.unallocatedMinor, 200000);
    });

    test('allocates nothing when every cycle offered is full', () {
      final plan = allocate(
        amountMinor: 300000,
        cycles: [cycle(id: 1, month: 10, collected: 300000)],
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.unallocatedMinor, 300000);
      expect(plan.coveredSpan, isNull);
    });

    test('handles no cycles at all', () {
      final plan = allocate(amountMinor: 300000, cycles: const []);

      expect(plan.isEmpty, isTrue);
      expect(plan.unallocatedMinor, 300000);
    });

    test('refuses to invent money from a zero or negative amount', () {
      expect(allocate(amountMinor: 0, cycles: [cycle(id: 1, month: 10)]).isEmpty,
          isTrue);
      expect(
        allocate(amountMinor: -100, cycles: [cycle(id: 1, month: 10)])
            .unallocatedMinor,
        0,
      );
    });

    test('conserves every paisa across any split', () {
      // The invariant, checked over a range of awkward amounts: allocated plus
      // unallocated always equals what was handed over.
      for (final amount in [1, 99, 100000, 299999, 300001, 899999, 1234567]) {
        final plan = allocate(
          amountMinor: amount,
          cycles: [
            cycle(id: 1, month: 9),
            cycle(id: 2, month: 10),
            cycle(month: 11),
          ],
        );

        expect(plan.allocatedMinor + plan.unallocatedMinor, amount,
            reason: 'lost money allocating $amount');
      }
    });

    test('a cycle expecting nothing is settled, not a debt', () {
      final plan = allocate(
        amountMinor: 300000,
        cycles: [
          cycle(id: 1, month: 10, expected: 0),
          cycle(id: 2, month: 11),
        ],
      );

      expect(plan.allocations.single.cycle.periodId, 2);
    });

    test('an overpaid cycle owes nothing rather than a negative amount', () {
      final overpaid = cycle(id: 1, month: 10, collected: 400000);

      expect(overpaid.outstandingMinor, 0);
      expect(overpaid.isSettled, isTrue);
      expect(overpaid.isPartial, isFalse);
    });
  });

  group('SettleableCycle.fromCycle', () {
    test('carries the transition flag through from the computed cycle', () {
      final settleable = SettleableCycle.fromCycle(
        cycleAfter(
          previousEnd: DateTime.utc(2026, 10, 1),
          durationMonths: 1,
          anchorDay: 6,
        ),
        expectedMinor: 300000,
      );

      expect(settleable.periodId, isNull);
      expect(settleable.isTransition, isTrue);
      expect(settleable.start, DateTime.utc(2026, 10, 1));
      expect(settleable.end, DateTime.utc(2026, 11, 6));
    });
  });

  group('Settlement', () {
    test('reads settled, partial and due apart', () {
      expect(
        const Settlement(expectedMinor: 300000, collectedMinor: 300000)
            .isSettled,
        isTrue,
      );
      expect(
        const Settlement(expectedMinor: 300000, collectedMinor: 100000)
            .isPartial,
        isTrue,
      );

      const nothingPaid =
          Settlement(expectedMinor: 300000, collectedMinor: 0);
      expect(nothingPaid.isSettled, isFalse);
      expect(nothingPaid.isPartial, isFalse);
      expect(nothingPaid.outstandingMinor, 300000);
    });

    test('treats a free cycle as settled', () {
      expect(
        const Settlement(expectedMinor: 0, collectedMinor: 0).isSettled,
        isTrue,
      );
    });
  });
}
