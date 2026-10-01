import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/logs_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';

/// Paging and searching the Logs screen while the app keeps writing to it.
///
/// "Load more" used to ask for the next page by offset. The automatic
/// reminder run writes audit rows as it goes, and every row written while
/// the screen was open pushed the rows already shown down by one, so the next
/// page started with entries the owner had already seen. And the search box
/// treated "%" and "_" as wildcards, unlike the Members search.
void main() {
  late AppDatabase db;
  late AuditRepository audit;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    audit = AuditRepository(db);
  });

  tearDown(() => db.close());

  Future<void> add(String summary, {String? memberName}) => audit.record(
        category: AuditCategory.reminder,
        action: AuditAction.reminderSent,
        outcome: AuditOutcome.success,
        summary: summary,
        memberName: memberName,
      );

  group('the next page', () {
    test('starts after the last event shown, whatever was written since',
        () async {
      for (var i = 0; i < 25; i++) {
        await add('Entry $i');
      }

      final first = await audit.recent(limit: 10);
      // Written while the screen is open.
      for (var i = 0; i < 3; i++) {
        await add('Late $i');
      }
      final second = await audit.recent(limit: 10, after: first.last);
      final third = await audit.recent(limit: 10, after: second.last);

      final ids = [...first, ...second, ...third].map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'no entry twice');
      expect(ids, hasLength(25), reason: 'and none skipped');
      expect([...second, ...third].map((e) => e.summary),
          isNot(contains(startsWith('Late'))));
    });

    test('keeps the newest-first order across events from the same second',
        () async {
      // Created times are stored to the second, so these all tie on time.
      for (var i = 0; i < 6; i++) {
        await add('Entry $i');
      }
      final first = await audit.recent(limit: 3);
      final rest = await audit.recent(limit: 3, after: first.last);

      expect([...first, ...rest].map((e) => e.summary), [
        'Entry 5',
        'Entry 4',
        'Entry 3',
        'Entry 2',
        'Entry 1',
        'Entry 0',
      ]);
    });

    test('through the Logs screen, repeats nothing', () async {
      for (var i = 0; i < 150; i++) {
        await add('Entry $i');
      }

      final bloc = LogsBloc(audit: audit);
      addTearDown(bloc.close);
      bloc.add(const LogsRequested());
      await bloc.stream.firstWhere((s) => s.status == LogsStatus.ready);
      expect(bloc.state.events, hasLength(100));

      for (var i = 0; i < 5; i++) {
        await add('Late $i');
      }
      bloc.add(const LogsMoreRequested());
      await bloc.stream
          .firstWhere((s) => !s.loadingMore && s.events.length > 100);

      final ids = bloc.state.events.map((e) => e.id).toList();
      expect(ids, hasLength(150));
      expect(ids.toSet(), hasLength(150));
      expect(bloc.state.hasMore, isFalse);
    });
  });

  group('the search', () {
    setUp(() async {
      await add('Fee rise of 50% applied');
      await add('Reminder sent', memberName: 'Ali_Raza');
      await add('Reminder sent', memberName: 'AliXRaza');
      await add(r'Path C:\gym\backup restored');
    });

    test('matches a percent sign literally', () async {
      final found = await audit.recent(search: '50%');
      expect(found.map((e) => e.summary), ['Fee rise of 50% applied']);
      expect(await audit.countMatching(search: '%'), 1,
          reason: 'one event has a percent sign, not every event');
    });

    test('matches an underscore literally', () async {
      final found = await audit.recent(search: 'Ali_');
      expect(found.map((e) => e.memberName), ['Ali_Raza']);
      expect(await audit.countMatching(search: '_'), 1);
    });

    test('matches a backslash literally', () async {
      expect(await audit.recent(search: r'C:\gym'), hasLength(1));
    });

    test('still finds ordinary text, in any case', () async {
      expect(await audit.countMatching(search: 'reminder'), 2);
    });
  });
}
