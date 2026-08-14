import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/services/logging/app_logger.dart';
import 'package:rich_man_fitness/services/logging/log_file_sink.dart';

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-logging-test');
  });

  tearDown(() async {
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  Directory logsDir() => Directory(p.join(workspace.path, 'logs'));

  LogFileSink sinkAt(DateTime day, {int retainedDays = 7}) => LogFileSink(
        supportDirectory: () async => workspace,
        clock: () => day,
        retainedDays: retainedDays,
      );

  group('LogFileSink', () {
    test('writes lines into a file named for the day', () async {
      final sink = sinkAt(DateTime(2026, 8, 14, 10, 30));
      await sink.open();
      sink.write('hello');

      final file = File(p.join(logsDir().path, 'app-2026-08-14.log'));
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), 'hello\n');
    });

    test('rolls to a new file once the day changes', () async {
      var now = DateTime(2026, 8, 14, 23, 59);
      final sink = LogFileSink(
        supportDirectory: () async => workspace,
        clock: () => now,
      );
      await sink.open();
      sink.write('before midnight');

      now = DateTime(2026, 8, 15, 0, 1);
      sink.write('after midnight');

      expect(
        File(p.join(logsDir().path, 'app-2026-08-14.log')).readAsStringSync(),
        'before midnight\n',
      );
      expect(
        File(p.join(logsDir().path, 'app-2026-08-15.log')).readAsStringSync(),
        'after midnight\n',
      );
    });

    test('prunes files older than the retention window, keeping the rest',
        () async {
      await logsDir().create(recursive: true);
      for (final day in ['2026-08-01', '2026-08-07', '2026-08-08', '2026-08-14']) {
        File(p.join(logsDir().path, 'app-$day.log')).writeAsStringSync('x');
      }
      // Not ours; must survive.
      File(p.join(logsDir().path, 'notes.txt')).writeAsStringSync('keep me');

      // Seven days retained, counting today: 8 Aug is the oldest kept.
      await sinkAt(DateTime(2026, 8, 14)).open();

      final names = logsDir()
          .listSync()
          .map((e) => p.basename(e.path))
          .toList()
        ..sort();
      expect(names, [
        'app-2026-08-08.log',
        'app-2026-08-14.log',
        'notes.txt',
      ]);
    });

    test('stops writing once the size cap is reached', () async {
      final sink = LogFileSink(
        supportDirectory: () async => workspace,
        clock: () => DateTime(2026, 8, 14),
        maxFileBytes: 20,
      );
      await sink.open();
      sink.write('0123456789012345678901234567890');
      sink.write('this line must be dropped');

      final body = File(p.join(logsDir().path, 'app-2026-08-14.log'))
          .readAsStringSync();
      expect(body, contains('01234567890'));
      expect(body, isNot(contains('dropped')));
    });

    test('a write before open() is a no-op rather than a crash', () {
      expect(() => sinkAt(DateTime(2026, 8, 14)).write('x'), returnsNormally);
    });
  });

  group('formatRecord', () {
    test('includes the timestamp, level, logger name and message', () {
      final line = formatRecord(LogRecord(
        Level.SEVERE,
        'snapshot failed',
        'backup',
        null,
        null,
        null,
        // LogRecord stamps DateTime.now(); assert on the stable parts.
      ));
      expect(line, contains('SEVERE'));
      expect(line, contains('backup'));
      expect(line, contains('snapshot failed'));
    });

    test('indents the error and every stack frame beneath the message', () {
      final line = formatRecord(LogRecord(
        Level.SEVERE,
        'boom',
        'test',
        StateError('bad'),
        StackTrace.fromString('#0  first\n#1  second'),
      ));
      expect(line, contains('\n    Bad state: bad'));
      expect(line, contains('\n    #0  first'));
      expect(line, contains('\n    #1  second'));
    });
  });

  group('credential redaction', () {
    test('AuthSignInRequested never prints the password', () {
      const event = AuthSignInRequested(
        email: 'admin@richmanfitness.local',
        password: 'sup3r-s3cret',
      );

      expect(event.toString(), isNot(contains('sup3r-s3cret')));
      expect(event.toString(), contains('admin@richmanfitness.local'));
      expect(event.toString(), contains('•••'));
    });

    test('two attempts differing only by password remain unequal', () {
      // The redaction must not weaken Equatable's equality.
      const a = AuthSignInRequested(email: 'a@b.c', password: 'one');
      const b = AuthSignInRequested(email: 'a@b.c', password: 'two');
      expect(a, isNot(equals(b)));
    });
  });
}
