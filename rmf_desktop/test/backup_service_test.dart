import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/backup_service.dart';

void main() {
  late Directory workspace;
  late File liveDb;
  late AppDatabase db;
  late BackupService backups;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-backup-test');
    liveDb = File(p.join(workspace.path, 'live.sqlite'));

    // A real on-disk database, so VACUUM INTO has something to snapshot.
    db = AppDatabase.forTesting(NativeDatabase(liveDb));
    // Point the service at the temp workspace so no platform channels are hit.
    backups = BackupService(
      db,
      supportDirectory: () async => workspace,
      receiptsDirectory: () async =>
          Directory(p.join(workspace.path, 'receipts')),
    );

    await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Gym Owner', email: 'owner@rmf.local', passwordHash: 'hash'));
    await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Member One',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 1, 1),
        ));
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  Directory target() => Directory(p.join(workspace.path, 'backups'));

  test('writes a snapshot into a timestamped folder', () async {
    final result =
        await backups.backupTo(target(), now: DateTime(2026, 8, 13, 21, 45));

    expect(p.basename(result.folder.path),
        'RichManFitness-Backup-2026-08-13-2145');
    expect(result.databaseBytes, greaterThan(0));
    expect(
      await File(p.join(result.folder.path, 'database.sqlite')).exists(),
      isTrue,
    );
  });

  test('the snapshot is a readable database containing the same data',
      () async {
    final result = await backups.backupTo(target());

    // The real proof that a backup is worth anything: open it and read it back.
    final restored = AppDatabase.forTesting(
      NativeDatabase(File(p.join(result.folder.path, 'database.sqlite'))),
    );
    addTearDown(restored.close);

    final members = await restored.select(restored.members).get();
    expect(members.single.fullName, 'Member One');
    expect(members.single.phone, '+923000000022');

    final users = await restored.select(restored.users).get();
    expect(users.single.email, 'owner@rmf.local');
  });

  test('does not capture writes made after the snapshot', () async {
    final result = await backups.backupTo(target());

    await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 2,
          fullName: 'Added Afterwards',
          phone: '+923000000025',
          joiningDate: DateTime.utc(2026, 2, 1),
        ));

    final restored = AppDatabase.forTesting(
      NativeDatabase(File(p.join(result.folder.path, 'database.sqlite'))),
    );
    addTearDown(restored.close);

    expect((await restored.select(restored.members).get()).length, 1);
  });

  test('a second backup does not fail on the leftover file', () async {
    final at = DateTime(2026, 8, 13, 21, 45);
    await backups.backupTo(target(), now: at);

    // Same timestamp means the same folder — it must overwrite, not throw.
    final second = await backups.backupTo(target(), now: at);
    expect(second.databaseBytes, greaterThan(0));
  });

  test('lists backups newest first', () async {
    await backups.backupTo(target(), now: DateTime(2026, 8, 11, 9, 0));
    await backups.backupTo(target(), now: DateTime(2026, 8, 13, 9, 0));
    await backups.backupTo(target(), now: DateTime(2026, 8, 12, 9, 0));

    final listed = await backups.listBackups(target());
    expect(listed.map((b) => b.takenAt.day), [13, 12, 11]);
  });

  test('ignores unrelated folders when listing', () async {
    await backups.backupTo(target(), now: DateTime(2026, 8, 13, 9, 0));
    await Directory(p.join(target().path, 'holiday-photos')).create();

    expect((await backups.listBackups(target())).length, 1);
  });

  test('listing a directory that does not exist returns empty', () async {
    final listed =
        await backups.listBackups(Directory(p.join(workspace.path, 'nope')));
    expect(listed, isEmpty);
  });

  group('validation', () {
    test('rejects a file that is not a database', () async {
      final bogus = File(p.join(workspace.path, 'notes.txt'));
      await bogus.writeAsString('this is not a database');

      expect(await backups.validateBackup(bogus), contains('not a database'));
    });

    test('rejects a file that does not exist', () async {
      final missing = File(p.join(workspace.path, 'gone.sqlite'));
      expect(await backups.validateBackup(missing), contains('no longer'));
    });

    test('accepts a real snapshot', () async {
      final result = await backups.backupTo(target());
      final snapshot = File(p.join(result.folder.path, 'database.sqlite'));

      expect(await backups.validateBackup(snapshot), isNull);
    });

    test('staging refuses an invalid file', () async {
      final bogus = File(p.join(workspace.path, 'notes.txt'));
      await bogus.writeAsString('nope');

      expect(await backups.stageRestore(bogus), isNotNull);
    });
  });

  group('automatic backups', () {
    test('takes one per day and skips the rest', () async {
      final morning = DateTime(2026, 8, 13, 8, 0);
      final evening = DateTime(2026, 8, 13, 20, 0);

      expect(await backups.autoBackup(now: morning), isNotNull);
      expect(await backups.autoBackup(now: evening), isNull,
          reason: 'already backed up today');
    });

    test('takes another on a new day', () async {
      await backups.autoBackup(now: DateTime(2026, 8, 13, 8, 0));
      expect(await backups.autoBackup(now: DateTime(2026, 8, 14, 8, 0)),
          isNotNull);
    });

    test('keeps only the newest few', () async {
      for (var day = 1; day <= 6; day++) {
        await backups.autoBackup(now: DateTime(2026, 8, day, 8, 0), keep: 3);
      }

      final kept = await backups.listBackups(
          await backups.automaticBackupDirectory());
      expect(kept.length, 3);
      // The most recent days survive.
      expect(kept.map((b) => b.takenAt.day), [6, 5, 4]);
    });
  });
}
