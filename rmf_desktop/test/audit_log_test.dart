import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/logging/log_file_reader.dart';

/// The log is what the owner has instead of a developer looking at the
/// database. It has to be readable, bounded, and impossible to break the app
/// with.
void main() {
  group('AuditRepository', () {
    late AppDatabase db;
    late AuditRepository audit;
    late int adminId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedDatabase(db);
      audit = AuditRepository(db);
      adminId = (await db.select(db.users).getSingle()).id;
    });

    tearDown(() => db.close());

    Future<void> add({
      required String action,
      AuditCategory category = AuditCategory.payment,
      AuditOutcome outcome = AuditOutcome.success,
      String summary = 'Something happened',
      String? memberName,
      String? receiptNumber,
      int? actorId,
    }) =>
        audit.record(
          category: category,
          action: action,
          outcome: outcome,
          summary: summary,
          memberName: memberName,
          receiptNumber: receiptNumber,
          actorId: actorId,
        );

    test('reads back newest first', () async {
      await add(action: 'a.one', summary: 'First');
      await add(action: 'a.two', summary: 'Second');
      await add(action: 'a.three', summary: 'Third');

      final events = await audit.recent();

      expect(events.map((e) => e.summary), ['Third', 'Second', 'First']);
    });

    test('resolves the actor name from the signed-in user', () async {
      await add(action: 'a.one', actorId: adminId);

      final event = (await audit.recent()).single;
      expect(event.actorId, adminId);
      expect(event.actorName, isNotNull);
      expect(event.actorName, (await db.select(db.users).getSingle()).name);
    });

    test('filters by category', () async {
      await add(action: 'p.one', category: AuditCategory.payment);
      await add(action: 'w.one', category: AuditCategory.whatsapp);

      final whatsapp = await audit.recent(category: AuditCategory.whatsapp);
      expect(whatsapp.single.action, 'w.one');
      expect(await audit.countMatching(category: AuditCategory.whatsapp), 1);
    });

    test('filters to only what went wrong or was refused', () async {
      await add(action: 'ok', outcome: AuditOutcome.success);
      await add(action: 'refused', outcome: AuditOutcome.refused);
      await add(action: 'failed', outcome: AuditOutcome.failed);

      final problems = await audit.recent(failuresOnly: true);

      expect(problems.map((e) => e.action), ['failed', 'refused']);
      expect(await audit.countMatching(failuresOnly: true), 2);
    });

    test('searches summary, member, receipt and actor', () async {
      await add(
          action: 'p.one', summary: 'Payment edited', memberName: 'Ali Raza');
      await add(
          action: 'p.two',
          summary: 'Payment deleted',
          receiptNumber: 'RMF-2026-000042');
      await add(action: 'p.three', summary: 'Unrelated');

      expect((await audit.recent(search: 'Ali')).single.action, 'p.one');
      expect((await audit.recent(search: '000042')).single.action, 'p.two');
      expect((await audit.recent(search: 'deleted')).single.action, 'p.two');
      expect(await audit.recent(search: 'nothing here'), isEmpty);
    });

    test('pages without repeating or skipping an entry', () async {
      for (var i = 0; i < 25; i++) {
        await add(action: 'a.$i', summary: 'Entry $i');
      }

      final first = await audit.recent(limit: 10);
      final second = await audit.recent(limit: 10, offset: 10);
      final third = await audit.recent(limit: 10, offset: 20);

      expect(first, hasLength(10));
      expect(second, hasLength(10));
      expect(third, hasLength(5));

      final ids = [...first, ...second, ...third].map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(25), reason: 'no entry appears twice');
      expect(await audit.countMatching(), 25);
    });

    test('drops blank detail lines rather than storing empty ones', () async {
      await audit.record(
        category: AuditCategory.payment,
        action: 'p.one',
        outcome: AuditOutcome.success,
        summary: 'Payment edited',
        detail: const ['Amount: Rs. 1 → Rs. 2', '', '   '],
      );

      expect((await audit.recent()).single.detail, 'Amount: Rs. 1 → Rs. 2');
    });

    test('stores no detail at all when there is none', () async {
      await add(action: 'p.one');
      expect((await audit.recent()).single.detail, isNull);
    });

    test('mirrors every entry into the file log', () async {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      await add(action: 'p.one', summary: 'Payment edited');
      await add(
          action: 'p.two', summary: 'Receipt failed', outcome: AuditOutcome.failed);

      final ours = records.where((r) => r.loggerName == 'audit').toList();
      expect(ours, hasLength(2));
      expect(ours.first.message, contains('p.one · Payment edited'));
      expect(ours.first.level, Level.INFO);
      expect(ours.last.level, Level.SEVERE,
          reason: 'a failure must not be filed away at info level');
    });

    test('a log that cannot be written never breaks the operation', () async {
      await db.close();

      // The point: this is called after money has already changed hands.
      await expectLater(
        audit.record(
          category: AuditCategory.payment,
          action: AuditAction.paymentEdited,
          outcome: AuditOutcome.success,
          summary: 'Payment edited after the database went away',
        ),
        completes,
      );
    });
  });

  group('LogFileReader', () {
    late Directory workspace;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('rmf-log-reader');
    });

    tearDown(() async {
      if (await workspace.exists()) await workspace.delete(recursive: true);
    });

    LogFileReader readerAt() =>
        LogFileReader(supportDirectory: () async => workspace);

    Future<File> writeLog(String day, String contents) async {
      final dir = Directory(p.join(workspace.path, 'logs'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'app-$day.log'));
      await file.writeAsString(contents);
      return file;
    }

    test('finds nothing before the first line is written', () async {
      expect(await readerAt().files(), isEmpty);
      expect(await readerAt().latest(), isEmpty);
    });

    test('lists log files newest day first', () async {
      await writeLog('2026-08-18', 'older\n');
      await writeLog('2026-08-20', 'newer\n');
      await writeLog('2026-08-19', 'middle\n');

      final files = await readerAt().files();

      expect(files.map((f) => p.basename(f.path)), [
        'app-2026-08-20.log',
        'app-2026-08-19.log',
        'app-2026-08-18.log',
      ]);
    });

    test('reads the newest day, not the first one it finds', () async {
      await writeLog('2026-08-18', 'older\n');
      await writeLog('2026-08-20', 'newer\n');

      expect(await readerAt().latest(), ['newer']);
    });

    test('returns only the last lines of a long file', () async {
      final lines = [for (var i = 0; i < 900; i++) 'line $i'];
      await writeLog('2026-08-20', '${lines.join('\n')}\n');

      final tail = await readerAt().latest(maxLines: 100);

      expect(tail, hasLength(100));
      expect(tail.first, 'line 800');
      expect(tail.last, 'line 899',
          reason: 'the end of the file is the interesting part');
    });

    test('a file bigger than the read window still ends correctly', () async {
      // Comfortably past the 256 KB tail window.
      final padding = 'x' * 600;
      final lines = [for (var i = 0; i < 900; i++) 'line $i $padding'];
      await writeLog('2026-08-20', '${lines.join('\n')}\n');

      final tail = await readerAt().latest(maxLines: 50);

      expect(tail, hasLength(50));
      expect(tail.last, endsWith(padding));
      expect(tail.last, startsWith('line 899'));
      for (final line in tail) {
        expect(line, startsWith('line '),
            reason: 'a half-read first line must be discarded, not shown');
      }
    });

    test('a missing file reads as empty rather than throwing', () async {
      final file = await writeLog('2026-08-20', 'gone soon\n');
      await file.delete();

      expect(await readerAt().tail(file), isEmpty);
    });
  });
}
