import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/payment_timing.dart';

/// Reading a payment's date against the cycle it bought, with no database and
/// no clock.
///
/// The case this file exists for: a member anchored to the 6th hands over cash
/// on 1 September for the cycle beginning 6 September. The money buys
/// 6 Sep - 6 Oct and the billing month is September, but the receipt is dated
/// 1 September, and the owner reading the ledger a month later has no way to
/// tell that from a mistake. Labelling it ADVANCE is the whole point.
///
/// The windows are not arbitrary. A payment is "advance" only once it arrives
/// before the gym would even have nudged the member, and "late" only once the
/// gym would have chased them — so the labels line up with what the owner has
/// already configured under reminders rather than inventing a second opinion.
void main() {
  // The shipped defaults: nudge 3 days before, chase 3 days after.
  const window = TimingWindow(advanceDays: 3, graceDays: 3);

  group('classifyTiming', () {
    test('labels the 1 September payment for a 6 September cycle as advance',
        () {
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 1),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.advance,
      );
    });

    test('paying on the first day of the cycle is on time', () {
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 6),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.onTime,
      );
    });

    test('paying a day early is on time, not advance', () {
      // The owner does not think of a member who pays the day before as having
      // paid in advance, and a label saying so would be the same noise this
      // module exists to remove.
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 5),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.onTime,
      );
    });

    test('the advance boundary is inclusive: exactly 3 days early is on time',
        () {
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 3),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.onTime,
      );
    });

    test('one day past the advance window is advance', () {
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 2),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.advance,
      );
    });

    test('paying weeks ahead is advance', () {
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 8, 20),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.advance,
      );
    });

    test('the grace boundary is inclusive: exactly 3 days late is on time', () {
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 9),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.onTime,
      );
    });

    test('one day past the grace window is late', () {
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 10),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.late,
      );
    });

    test('reads the calendar day and ignores the time of day', () {
      // A payment taken at five to midnight on the due date is on time, not
      // late by a fraction of a day.
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 6, 23, 55),
          periodStart: DateTime.utc(2026, 9, 6),
          window: window,
        ),
        PaymentTiming.onTime,
      );
    });

    test('a zero-width window makes the due day itself the only on-time day',
        () {
      const strict = TimingWindow(advanceDays: 0, graceDays: 0);
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 6),
          periodStart: DateTime.utc(2026, 9, 6),
          window: strict,
        ),
        PaymentTiming.onTime,
      );
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 5),
          periodStart: DateTime.utc(2026, 9, 6),
          window: strict,
        ),
        PaymentTiming.advance,
      );
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 9, 7),
          periodStart: DateTime.utc(2026, 9, 6),
          window: strict,
        ),
        PaymentTiming.late,
      );
    });

    test('a cycle whose boundary was clamped by a short month still reads on '
        'time', () {
      // The 31 January member. February clamps his cycle to the 28th; paying
      // on the 28th is paying on his due date, not three days early.
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2026, 2, 28),
          periodStart: DateTime.utc(2026, 2, 28),
          window: window,
        ),
        PaymentTiming.onTime,
      );
    });

    test('crosses a year boundary', () {
      expect(
        classifyTiming(
          paidAt: DateTime.utc(2025, 12, 20),
          periodStart: DateTime.utc(2026, 1, 6),
          window: window,
        ),
        PaymentTiming.advance,
      );
    });
  });

  group('TimingWindow.fromReminderOffsets', () {
    test('takes the earliest nudge and the earliest chase', () {
      // "3,7" days after means the gym first chases on day 3, so day 3 is the
      // last on-time day.
      final built = TimingWindow.fromReminderOffsets(
        daysBefore: const [3],
        daysAfter: const [3, 7],
      );
      expect(built.advanceDays, 3);
      expect(built.graceDays, 3);
    });

    test('falls back to a sane window when the owner configured no reminders',
        () {
      final built = TimingWindow.fromReminderOffsets(
        daysBefore: const [],
        daysAfter: const [],
      );
      expect(built.advanceDays, TimingWindow.defaultAdvanceDays);
      expect(built.graceDays, TimingWindow.defaultGraceDays);
    });

    test('ignores negative offsets rather than inverting the window', () {
      final built = TimingWindow.fromReminderOffsets(
        daysBefore: const [-5, 2],
        daysAfter: const [-1, 4],
      );
      expect(built.advanceDays, 2);
      expect(built.graceDays, 4);
    });
  });

  group('classifyAdvanceReach', () {
    test('the current cycle alone needs no confirmation', () {
      expect(classifyAdvanceReach(0), AdvanceAllowance.allowed);
    });

    test('one cycle ahead is normal and needs no confirmation', () {
      // Paying next month's fee when you come in is ordinary gym behaviour.
      expect(classifyAdvanceReach(1), AdvanceAllowance.allowed);
    });

    test('three months upfront asks the owner to confirm', () {
      // Legitimate, and common, but also exactly what a mistyped amount looks
      // like. Worth one question before it books a quarter of revenue.
      expect(classifyAdvanceReach(3), AdvanceAllowance.needsConfirmation);
    });

    test('a year ahead still only needs confirmation', () {
      expect(classifyAdvanceReach(12), AdvanceAllowance.needsConfirmation);
    });

    test('beyond the ceiling is refused outright', () {
      // A cash gym should not book three years of revenue because someone
      // typed an extra zero.
      expect(classifyAdvanceReach(13), AdvanceAllowance.refused);
    });
  });

  group('latestPaymentDate', () {
    test('lets the owner date a receipt anywhere inside the cycle bought', () {
      // A member hands over September's fee on the 3rd for a cycle running
      // 8 Sep - 8 Oct. The owner wants to issue the receipt dated the 8th,
      // his actual billing day, so it reads like every other September
      // receipt.
      expect(
        latestPaymentDate(
          coveredEnd: DateTime.utc(2026, 10, 8),
          today: DateTime.utc(2026, 9, 3),
        ),
        DateTime.utc(2026, 10, 7),
      );
    });

    test('stops at the last day the money actually covers', () {
      // 8 October belongs to the *next* cycle. Dating a receipt there would
      // put it against a period this payment did not buy.
      final bound = latestPaymentDate(
        coveredEnd: DateTime.utc(2026, 10, 8),
        today: DateTime.utc(2026, 9, 3),
      );
      expect(bound.isBefore(DateTime.utc(2026, 10, 8)), isTrue);
    });

    test('extends across a payment covering several cycles', () {
      expect(
        latestPaymentDate(
          coveredEnd: DateTime.utc(2026, 12, 8),
          today: DateTime.utc(2026, 9, 3),
        ),
        DateTime.utc(2026, 12, 7),
      );
    });

    test('never tightens below tomorrow when clearing arrears', () {
      // The span a backlog payment covers ended in the past. The owner must
      // still be able to date it today, or the picker would refuse the only
      // date that makes sense.
      expect(
        latestPaymentDate(
          coveredEnd: DateTime.utc(2026, 8, 8),
          today: DateTime.utc(2026, 9, 3),
        ),
        DateTime.utc(2026, 9, 4),
      );
    });

    test('falls back to tomorrow before an amount has been entered', () {
      expect(
        latestPaymentDate(coveredEnd: null, today: DateTime.utc(2026, 9, 3)),
        DateTime.utc(2026, 9, 4),
      );
    });

    test('ignores the time of day on both sides', () {
      expect(
        latestPaymentDate(
          coveredEnd: DateTime.utc(2026, 10, 8, 17, 30),
          today: DateTime.utc(2026, 9, 3, 23, 59),
        ),
        DateTime.utc(2026, 10, 7),
      );
    });
  });
}
