import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/billing_cycle.dart';

/// The billing-cycle arithmetic, with no database and no real clock.
///
/// Two properties matter more than anything else here and are what most of
/// these tests exist to pin down:
///
///  1. **A short month must not permanently move a member's billing day.**
///     31 Jan + 1 month is 28 or 29 Feb, but the month after that is 31 March,
///     not the 28th. That only works because the anchor is carried rather than
///     read back off the previous boundary.
///  2. **Cycles are contiguous.** The next one starts exactly where the last
///     one ended, so no payment date can shorten a cycle and no lateness can
///     lengthen one.
void main() {
  group('addMonthsClamped', () {
    test('keeps the anchor day in a month long enough to hold it', () {
      expect(
        addMonthsClamped(DateTime.utc(2026, 3, 6), 1, anchorDay: 6),
        DateTime.utc(2026, 4, 6),
      );
    });

    test('clamps to the last day of a month too short for the anchor', () {
      expect(
        addMonthsClamped(DateTime.utc(2026, 1, 31), 1, anchorDay: 31),
        DateTime.utc(2026, 2, 28),
      );
    });

    test('clamps to 29 February in a leap year', () {
      expect(
        addMonthsClamped(DateTime.utc(2028, 1, 31), 1, anchorDay: 31),
        DateTime.utc(2028, 2, 29),
      );
    });

    test('restores the anchor after a short month rather than staying clamped',
        () {
      // The whole point of carrying the anchor. Walking forward from the
      // clamped 28 Feb without it would give 28 March and lose the member's
      // billing day for good.
      final february = addMonthsClamped(
        DateTime.utc(2026, 1, 31),
        1,
        anchorDay: 31,
      );
      expect(february, DateTime.utc(2026, 2, 28));

      expect(
        addMonthsClamped(february, 1, anchorDay: 31),
        DateTime.utc(2026, 3, 31),
      );
    });

    test('crosses a year boundary', () {
      expect(
        addMonthsClamped(DateTime.utc(2026, 12, 6), 1, anchorDay: 6),
        DateTime.utc(2027, 1, 6),
      );
    });

    test('handles a multi-month plan', () {
      expect(
        addMonthsClamped(DateTime.utc(2026, 11, 30), 3, anchorDay: 30),
        DateTime.utc(2027, 2, 28),
      );
    });
  });

  group('cycleAfter', () {
    test('starts exactly where the previous cycle ended', () {
      final cycle = cycleAfter(
        previousEnd: DateTime.utc(2026, 10, 6),
        durationMonths: 1,
        anchorDay: 6,
      );

      expect(cycle.start, DateTime.utc(2026, 10, 6));
      expect(cycle.end, DateTime.utc(2026, 11, 6));
    });

    test('is unaffected by when the member actually paid', () {
      // The heart of the model: the same cycle follows whether the member paid
      // early, on the day, or three weeks late.
      final cycle = cycleAfter(
        previousEnd: DateTime.utc(2026, 10, 6),
        durationMonths: 1,
        anchorDay: 6,
      );

      expect(cycle.end, DateTime.utc(2026, 11, 6));
    });

    test('rolls a quarterly plan a quarter forward', () {
      final cycle = cycleAfter(
        previousEnd: DateTime.utc(2026, 10, 6),
        durationMonths: 3,
        anchorDay: 6,
      );

      expect(cycle.end, DateTime.utc(2027, 1, 6));
    });

    test('treats a clamped boundary as still on the anchor', () {
      // A member anchored to the 31st whose last cycle ended 28 Feb is not
      // mid-transition — they are exactly where they should be, and the next
      // cycle must run to 31 March rather than being re-anchored to the 28th.
      final cycle = cycleAfter(
        previousEnd: DateTime.utc(2026, 2, 28),
        durationMonths: 1,
        anchorDay: 31,
      );

      expect(cycle.start, DateTime.utc(2026, 2, 28));
      expect(cycle.end, DateTime.utc(2026, 3, 31));
      expect(cycle.isTransition, isFalse);
    });

    group('when the anchor day has changed', () {
      test('ends on the new anchor nearest the natural end', () {
        // Was billing on the 1st, owner moves them to the 6th. The natural end
        // is 1 Nov; 6 Nov is five days away and 6 Oct is twenty-six, so the
        // transition cycle runs to 6 November.
        final cycle = cycleAfter(
          previousEnd: DateTime.utc(2026, 10, 1),
          durationMonths: 1,
          anchorDay: 6,
        );

        expect(cycle.start, DateTime.utc(2026, 10, 1));
        expect(cycle.end, DateTime.utc(2026, 11, 6));
        expect(cycle.isTransition, isTrue);
        expect(cycle.lengthInDays, 36);
      });

      test('ends short of the natural end when that anchor is nearer', () {
        // Was billing on the 20th, moved to the 18th. The natural end is
        // 20 Nov, and 18 Nov is two days short of it while 18 December is
        // twenty-eight days past — so the cycle ends a little early rather
        // than running most of an extra month.
        final cycle = cycleAfter(
          previousEnd: DateTime.utc(2026, 10, 20),
          durationMonths: 1,
          anchorDay: 18,
        );

        expect(cycle.end, DateTime.utc(2026, 11, 18));
        expect(cycle.lengthInDays, 29);
      });

      test('shortens rather than nearly doubling the cycle', () {
        // Anchor moved to the 28th from the 1st. Natural end 1 Nov: 28 Oct is
        // four days back and 28 Nov is twenty-seven days on, so it shortens.
        final cycle = cycleAfter(
          previousEnd: DateTime.utc(2026, 10, 1),
          durationMonths: 1,
          anchorDay: 28,
        );

        expect(cycle.end, DateTime.utc(2026, 10, 28));
        expect(cycle.lengthInDays, 27);
      });

      test('never produces a cycle that ends before it starts', () {
        // Anchor 2 from a boundary on the 1st. 2 October is only a day past
        // the start and would make a one-day cycle, so the nearest-to-natural
        // rule picks 2 November instead. Whatever it picks, it goes forward.
        final cycle = cycleAfter(
          previousEnd: DateTime.utc(2026, 10, 1),
          durationMonths: 1,
          anchorDay: 2,
        );

        expect(cycle.end, DateTime.utc(2026, 11, 2));
        expect(cycle.end.isAfter(cycle.start), isTrue);
      });

      test('a transition cycle stays within a fortnight of a normal one', () {
        // Property check across every anchor day, so no combination produces
        // the two-day or fifty-day cycle a naive "next occurrence" rule gives.
        for (var anchor = 1; anchor <= 28; anchor++) {
          final cycle = cycleAfter(
            previousEnd: DateTime.utc(2026, 10, 15),
            durationMonths: 1,
            anchorDay: anchor,
          );

          expect(cycle.end.isAfter(cycle.start), isTrue,
              reason: 'anchor $anchor went backwards');
          expect(cycle.lengthInDays, greaterThanOrEqualTo(16),
              reason: 'anchor $anchor produced a very short cycle');
          expect(cycle.lengthInDays, lessThanOrEqualTo(46),
              reason: 'anchor $anchor produced a very long cycle');
        }
      });
    });
  });

  group('cycleContaining', () {
    test('finds the cycle covering today when the anchor has passed', () {
      final cycle = cycleContaining(
        today: DateTime.utc(2026, 8, 15),
        anchorDay: 1,
        durationMonths: 1,
      );

      expect(cycle.start, DateTime.utc(2026, 8, 1));
      expect(cycle.end, DateTime.utc(2026, 9, 1));
    });

    test('steps back a month when this month\'s anchor is still ahead', () {
      final cycle = cycleContaining(
        today: DateTime.utc(2026, 8, 5),
        anchorDay: 20,
        durationMonths: 1,
      );

      expect(cycle.start, DateTime.utc(2026, 7, 20));
      expect(cycle.end, DateTime.utc(2026, 8, 20));
    });

    test('does not phase a quarterly cycle to any fixed quarter grid', () {
      // Rooted in today's month, not walked forward in three-month strides
      // from some earlier reference point.
      final cycle = cycleContaining(
        today: DateTime.utc(2026, 8, 15),
        anchorDay: 1,
        durationMonths: 3,
      );

      expect(cycle.start, DateTime.utc(2026, 8, 1));
      expect(cycle.end, DateTime.utc(2026, 11, 1));
    });

    test('is due on the anchor day even when today sits before it', () {
      final cycle = cycleContaining(
        today: DateTime.utc(2026, 8, 5),
        anchorDay: 20,
        durationMonths: 1,
      );

      expect(cycle.contains(DateTime.utc(2026, 8, 5)), isTrue);
    });
  });

  group('firstCycleFor', () {
    test('starts the day the member joined and anchors to that day', () {
      final cycle = firstCycleFor(
        joiningDate: DateTime.utc(2026, 9, 14),
        durationMonths: 1,
      );

      expect(cycle.start, DateTime.utc(2026, 9, 14));
      expect(cycle.end, DateTime.utc(2026, 10, 14));
    });

    test('drops the time of day so a cycle is a whole number of days', () {
      final cycle = firstCycleFor(
        joiningDate: DateTime.utc(2026, 9, 14, 17, 42),
        durationMonths: 1,
      );

      expect(cycle.start, DateTime.utc(2026, 9, 14));
    });

    test('honours an explicit anchor for a member who should bill elsewhere',
        () {
      final cycle = firstCycleFor(
        joiningDate: DateTime.utc(2026, 9, 14),
        durationMonths: 1,
        anchorDay: 1,
      );

      expect(cycle.start, DateTime.utc(2026, 9, 14));
      expect(cycle.end, DateTime.utc(2026, 10, 1));
      expect(cycle.isTransition, isTrue);
    });
  });

  group('resolveAnchorDay', () {
    test('uses the stored anchor when the membership has one', () {
      expect(
        resolveAnchorDay(
          billingAnchorDay: 6,
          latestPeriodStart: DateTime.utc(2026, 9, 1),
          joiningDate: DateTime.utc(2026, 1, 20),
        ),
        6,
      );
    });

    test('falls back to the latest cycle start, which upgrades to day 1', () {
      // Every cycle recorded before this release starts on the 1st, so a
      // membership with no anchor column reads as anchored to the 1st and its
      // cycles keep landing exactly where they do today. This is what makes
      // the upgrade a no-op.
      expect(
        resolveAnchorDay(
          billingAnchorDay: null,
          latestPeriodStart: DateTime.utc(2026, 9, 1),
          joiningDate: DateTime.utc(2026, 1, 20),
        ),
        1,
      );
    });

    test('falls back to the joining day for a member with no cycles yet', () {
      expect(
        resolveAnchorDay(
          billingAnchorDay: null,
          latestPeriodStart: null,
          joiningDate: DateTime.utc(2026, 1, 20),
        ),
        20,
      );
    });

    test('reads the joining day in UTC, not local time', () {
      // Drift hands DateTimes back in local time. Reading .day off a local
      // value lands on the day before in any negative-offset timezone, which
      // would anchor a member joining on the 1st to the last day of the month
      // before.
      expect(
        resolveAnchorDay(
          billingAnchorDay: null,
          latestPeriodStart: null,
          joiningDate: DateTime.utc(2026, 1, 20, 2),
        ),
        20,
      );
    });

    test('clamps a nonsense stored anchor rather than throwing', () {
      expect(
        resolveAnchorDay(
          billingAnchorDay: 45,
          latestPeriodStart: null,
          joiningDate: DateTime.utc(2026, 1, 20),
        ),
        31,
      );
      expect(
        resolveAnchorDay(
          billingAnchorDay: 0,
          latestPeriodStart: null,
          joiningDate: DateTime.utc(2026, 1, 20),
        ),
        1,
      );
    });
  });

  group('BillingCycle', () {
    final cycle = BillingCycle(
      start: DateTime.utc(2026, 10, 6),
      end: DateTime.utc(2026, 11, 6),
    );

    test('is due on the day it starts, because the gym is paid in advance', () {
      expect(cycle.dueDate, DateTime.utc(2026, 10, 6));
    });

    test('contains its first day and excludes its last', () {
      expect(cycle.contains(DateTime.utc(2026, 10, 6)), isTrue);
      expect(cycle.contains(DateTime.utc(2026, 11, 5, 23)), isTrue);
      expect(cycle.contains(DateTime.utc(2026, 11, 6)), isFalse);
      expect(cycle.contains(DateTime.utc(2026, 10, 5, 23)), isFalse);
    });

    test('sequences forward contiguously with no gaps or overlaps', () {
      var at = firstCycleFor(
        joiningDate: DateTime.utc(2026, 1, 31),
        durationMonths: 1,
      );
      final starts = <DateTime>[at.start];

      for (var i = 0; i < 13; i++) {
        final next = cycleAfter(
          previousEnd: at.end,
          durationMonths: 1,
          anchorDay: 31,
        );
        expect(next.start, at.end, reason: 'gap after ${at.end}');
        starts.add(next.start);
        at = next;
      }

      // Thirteen months on from 31 January is 28 February the following year,
      // and the anchor survived every short month in between.
      expect(starts.last, DateTime.utc(2027, 2, 28));
      expect(starts[2], DateTime.utc(2026, 3, 31));
    });
  });
}
