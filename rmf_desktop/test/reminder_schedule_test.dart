import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/reminder_schedule.dart';

/// When a reminder is owed.
///
/// The behaviour worth protecting hardest is supersession: the gym shuts for a
/// week, the app is reopened, and the member gets *one* message rather than
/// the three that came due while nobody was looking.
void main() {
  const settings = ReminderSettings(
    daysBefore: [3],
    onDueDate: true,
    daysAfter: [3, 7],
  );

  final due = DateTime.utc(2026, 10, 6);

  ReminderDecision decide(DateTime today, {Set<ReminderKey> handled = const {}}) =>
      decideReminder(
        settings: settings,
        dueDate: due,
        today: today,
        alreadyHandled: handled,
      );

  group('decideReminder', () {
    test('owes nothing well before the first nudge', () {
      expect(decide(DateTime.utc(2026, 10, 1)).hasWork, isFalse);
    });

    test('nudges three days before the due date', () {
      final decision = decide(DateTime.utc(2026, 10, 3));

      expect(decision.send!.stage, ReminderStage.beforeDue);
      expect(decision.send!.offsetDays, 3);
      expect(decision.superseded, isEmpty);
    });

    test('sends the due-date reminder on the day', () {
      final decision = decide(
        DateTime.utc(2026, 10, 6),
        handled: {const ReminderKey(ReminderStage.beforeDue, 3)},
      );

      expect(decision.send!.stage, ReminderStage.onDue);
      expect(decision.superseded, isEmpty);
    });

    test('chases three days after the due date', () {
      final decision = decide(
        DateTime.utc(2026, 10, 9),
        handled: {
          const ReminderKey(ReminderStage.beforeDue, 3),
          const ReminderKey(ReminderStage.onDue, 0),
        },
      );

      expect(decision.send!.stage, ReminderStage.overdue);
      expect(decision.send!.offsetDays, 3);
    });

    test('offers nothing once every stage has been handled', () {
      final decision = decide(
        DateTime.utc(2026, 10, 20),
        handled: {
          const ReminderKey(ReminderStage.beforeDue, 3),
          const ReminderKey(ReminderStage.onDue, 0),
          const ReminderKey(ReminderStage.overdue, 3),
          const ReminderKey(ReminderStage.overdue, 7),
        },
      );

      expect(decision.hasWork, isFalse);
    });

    group('when the app was closed and several came due', () {
      test('sends only the most recent and supersedes the rest', () {
        // Gym shut from 2 October, reopened on the 10th. The nudge, the
        // due-date note and the three-day chase all came due in between.
        final decision = decide(DateTime.utc(2026, 10, 10));

        expect(decision.send!.stage, ReminderStage.overdue);
        expect(decision.send!.offsetDays, 3);

        expect(decision.superseded.map((s) => s.key.toString()), [
          'beforeDue+3',
          'onDue+0',
        ]);
      });

      test('supersedes everything earlier when reopened very late', () {
        final decision = decide(DateTime.utc(2026, 11, 20));

        expect(decision.send!.stage, ReminderStage.overdue);
        expect(decision.send!.offsetDays, 7);
        expect(decision.superseded, hasLength(3));
      });

      test('never sends more than one message for one cycle in one run', () {
        for (var day = 1; day <= 30; day++) {
          final decision = decide(DateTime.utc(2026, 10, day));
          // send is a single reminder by construction; this pins the contract
          // so a future refactor cannot quietly turn it into a list.
          expect(decision.send == null || decision.send is ScheduledReminder,
              isTrue);
        }
      });
    });

    test('a later stage wins a tie on the same day', () {
      // Nudge configured for the due date itself, alongside the due-date
      // reminder. Both fall on the 6th; the due-date message is the right one.
      final decision = decideReminder(
        settings: const ReminderSettings(
          daysBefore: [],
          onDueDate: true,
          daysAfter: [0],
        ),
        dueDate: due,
        today: due,
      );

      expect(decision.send!.stage, ReminderStage.onDue);
    });

    test('ignores nonsense offsets rather than scheduling on the due date', () {
      final decision = decideReminder(
        settings: const ReminderSettings(
          daysBefore: [0, -5],
          onDueDate: false,
          daysAfter: [0, -1],
        ),
        dueDate: due,
        today: DateTime.utc(2026, 10, 20),
      );

      expect(decision.hasWork, isFalse);
    });

    test('sends nothing when the owner has turned every stage off', () {
      final decision = decideReminder(
        settings: const ReminderSettings(
          daysBefore: [],
          onDueDate: false,
          daysAfter: [],
        ),
        dueDate: due,
        today: DateTime.utc(2026, 10, 20),
      );

      expect(decision.hasWork, isFalse);
    });

    test('reads the day on the calendar, not on the hour', () {
      // A due date stored as UTC midnight and a "today" carrying a time of day
      // must still compare as the same calendar day.
      final decision = decide(DateTime.utc(2026, 10, 3, 23, 59));

      expect(decision.send!.stage, ReminderStage.beforeDue);
    });
  });

  group('withinSendingWindow', () {
    const gymHours = ReminderSettings(sendFromHour: 9, sendUntilHour: 21);

    test('allows a mid-morning send', () {
      expect(withinSendingWindow(DateTime(2026, 10, 6, 10), gymHours), isTrue);
    });

    test('refuses the early hours', () {
      expect(withinSendingWindow(DateTime(2026, 10, 6, 6, 30), gymHours),
          isFalse);
    });

    test('refuses late at night', () {
      expect(withinSendingWindow(DateTime(2026, 10, 6, 22), gymHours), isFalse);
    });

    test('includes the opening hour and excludes the closing one', () {
      expect(withinSendingWindow(DateTime(2026, 10, 6, 9), gymHours), isTrue);
      expect(withinSendingWindow(DateTime(2026, 10, 6, 21), gymHours), isFalse);
    });

    test('handles a window that wraps past midnight', () {
      const overnight = ReminderSettings(sendFromHour: 22, sendUntilHour: 6);

      expect(withinSendingWindow(DateTime(2026, 10, 6, 23), overnight), isTrue);
      expect(withinSendingWindow(DateTime(2026, 10, 6, 3), overnight), isTrue);
      expect(withinSendingWindow(DateTime(2026, 10, 6, 12), overnight), isFalse);
    });

    test('treats an empty window as any time, not as never', () {
      // A misconfigured pair must not be able to silence every reminder for
      // good with nothing on screen to explain why.
      const same = ReminderSettings(sendFromHour: 9, sendUntilHour: 9);

      expect(withinSendingWindow(DateTime(2026, 10, 6, 3), same), isTrue);
    });
  });

  group('parseOffsetDays', () {
    test('parses a stored list', () {
      expect(parseOffsetDays('3,7'), [3, 7]);
    });

    test('sorts, de-duplicates and trims', () {
      expect(parseOffsetDays(' 7 , 3,7 '), [3, 7]);
    });

    test('drops junk, blanks, zero and negatives', () {
      expect(parseOffsetDays('3,,x,-2,0,7'), [3, 7]);
    });

    test('reads an empty or missing setting as no reminders', () {
      expect(parseOffsetDays(''), isEmpty);
      expect(parseOffsetDays('   '), isEmpty);
      expect(parseOffsetDays(null), isEmpty);
    });

    test('round-trips through formatOffsetDays', () {
      expect(parseOffsetDays(formatOffsetDays([7, 3, 3])), [3, 7]);
      expect(formatOffsetDays(const []), '');
    });
  });
}
