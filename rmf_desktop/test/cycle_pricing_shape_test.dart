import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/billing_cycle.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  group('cycleShapeFor', () {
    test('a plain month is whole', () {
      expect(
          cycleShapeFor(
              start: d(2026, 9, 1), end: d(2026, 10, 1), durationMonths: 1),
          CycleShape.whole);
    });

    test('a month clamped by February is still whole, either side of it', () {
      expect(
          cycleShapeFor(
              start: d(2027, 1, 31), end: d(2027, 2, 28), durationMonths: 1),
          CycleShape.whole);
      // Started on a clamped 28 Feb, anchored to the 31st.
      expect(
          cycleShapeFor(
              start: d(2027, 2, 28), end: d(2027, 3, 31), durationMonths: 1),
          CycleShape.whole);
    });

    test('a quarter is whole on a quarterly plan, and the wrong length on a '
        'monthly one', () {
      expect(
          cycleShapeFor(
              start: d(2026, 9, 1), end: d(2026, 12, 1), durationMonths: 3),
          CycleShape.whole);
      expect(
          cycleShapeFor(
              start: d(2026, 9, 1), end: d(2026, 12, 1), durationMonths: 1),
          CycleShape.otherLength);
      expect(
          cycleShapeFor(
              start: d(2026, 9, 1), end: d(2026, 10, 1), durationMonths: 3),
          CycleShape.otherLength);
    });

    test('the transitions the gym actually saw are transitions', () {
      // #39: 10 Nov to 25 Nov, 15 days.
      expect(
          cycleShapeFor(
              start: d(2026, 11, 10), end: d(2026, 11, 25), durationMonths: 1),
          CycleShape.transition);
      // #465 and #531: 42 and 46 days.
      expect(
          cycleShapeFor(
              start: d(2026, 10, 1), end: d(2026, 11, 12), durationMonths: 1),
          CycleShape.transition);
      expect(
          cycleShapeFor(
              start: d(2026, 10, 1), end: d(2026, 11, 16), durationMonths: 1),
          CycleShape.transition);
    });

    test('every transition nearestAnchorTo can produce reads as one', () {
      for (var anchor = 1; anchor <= 31; anchor++) {
        for (var day = 1; day <= 28; day++) {
          final start = d(2026, 10, day);
          final cycle = cycleAfter(
              previousEnd: start, durationMonths: 1, anchorDay: anchor);
          final shape = cycleShapeFor(
              start: cycle.start, end: cycle.end, durationMonths: 1);
          expect(shape, isNot(CycleShape.otherLength),
              reason: 'anchor $anchor from day $day: $cycle');
          if (!cycle.isTransition) expect(shape, CycleShape.whole);
        }
      }
    });
  });

  group('feeForCycle', () {
    test('a whole cycle costs the fee', () {
      expect(
          feeForCycle(
              feeMinor: 350000,
              start: d(2026, 9, 1),
              end: d(2026, 10, 1),
              durationMonths: 1),
          350000);
    });

    test('a transition costs its share of the month, to the rupee', () {
      // 15 of the 30 days 10 Nov to 10 Dec would have run.
      expect(
          feeForCycle(
              feeMinor: 250000,
              start: d(2026, 11, 10),
              end: d(2026, 11, 25),
              durationMonths: 1),
          125000);
      // 42 of the 31 days 1 Oct to 1 Nov would have run.
      expect(
          feeForCycle(
              feeMinor: 350000,
              start: d(2026, 10, 1),
              end: d(2026, 11, 12),
              durationMonths: 1),
          474200);
    });

    test('a cycle of the wrong length has no price', () {
      expect(
          feeForCycle(
              feeMinor: 800000,
              start: d(2026, 9, 1),
              end: d(2026, 10, 1),
              durationMonths: 3),
          isNull);
    });
  });
}
