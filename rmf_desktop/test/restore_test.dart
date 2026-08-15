import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/backup_service.dart';

/// Restoring a backup.
///
/// The two things that went wrong here were both silent. A restore put the
/// database back and left every receipt image behind, so the paperwork the
/// owner restored the backup to recover was exactly what they did not get. And
/// the only check on the chosen file was its first fifteen bytes, which any
/// SQLite file in the world passes — including one this version cannot read,
/// after which the app opened to a blank window with no way back.
void main() {
  late Directory workspace;
  late File liveDb;
  late AppDatabase db;
  late BackupService backups;

  Directory receipts() => Directory(p.join(workspace.path, 'receipts'));
  Directory target() => Directory(p.join(workspace.path, 'backups'));

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-restore-test');
    liveDb = File(p.join(workspace.path, 'live.sqlite'));

    db = AppDatabase.forTesting(NativeDatabase(liveDb));
    backups = BackupService(
      db,
      supportDirectory: () async => workspace,
      receiptsDirectory: () async => receipts(),
    );

    await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Gym Owner', email: 'owner@rmf.local', passwordHash: 'hash'));
    await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Member One',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 1, 1),
        ));

    await receipts().create(recursive: true);
    await File(p.join(receipts().path, 'RMF-2026-0001.png'))
        .writeAsString('receipt image');
  });

  tearDown(() async {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  /// What main() does on the next launch, against the test's own folders.
  Future<bool> relaunch() => BackupService.applyPendingRestore(
        supportDirectory: () async => workspace,
        liveDatabase: () async => liveDb,
      );

  test('brings back the receipt files, not just the database', () async {
    final snapshot = await backups.backupTo(target());

    // Time passes: a member is added and the receipt is lost.
    await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 2,
          fullName: 'Added Afterwards',
          phone: '+923000000023',
          joiningDate: DateTime.utc(2026, 2, 1),
        ));
    await File(p.join(receipts().path, 'RMF-2026-0001.png')).delete();

    final problem = await backups.stageRestore(
        File(p.join(snapshot.folder.path, 'database.sqlite')));
    expect(problem, isNull);

    await db.close();
    expect(await relaunch(), isTrue);

    final restored = AppDatabase.forTesting(NativeDatabase(liveDb));
    addTearDown(restored.close);

    expect((await restored.select(restored.members).get()).length, 1,
        reason: 'the database went back to the snapshot');

    final image = File(p.join(receipts().path, 'RMF-2026-0001.png'));
    expect(await image.exists(), isTrue,
        reason: 'a restored payment whose receipt image is missing cannot be '
            'viewed, printed or resent');
    expect(await image.readAsString(), 'receipt image');
  });

  test('leaves receipts the backup did not contain alone', () async {
    final snapshot = await backups.backupTo(target());

    await File(p.join(receipts().path, 'RMF-2026-0002.png'))
        .writeAsString('later receipt');

    await backups.stageRestore(
        File(p.join(snapshot.folder.path, 'database.sqlite')));
    await db.close();
    await relaunch();

    expect(
        await File(p.join(receipts().path, 'RMF-2026-0002.png')).exists(),
        isTrue,
        reason: 'merged, not swapped — deleting these would lose paperwork '
            'the restore was never asked to touch');
  });

  test('keeps the replaced database alongside', () async {
    final snapshot = await backups.backupTo(target());
    await backups.stageRestore(
        File(p.join(snapshot.folder.path, 'database.sqlite')));
    await db.close();
    await relaunch();

    final kept = workspace
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('live.sqlite.replaced-'));
    expect(kept, hasLength(1), reason: 'a mistaken restore must not be fatal');
  });

  test('does nothing when no restore is staged', () async {
    expect(await relaunch(), isFalse);
  });

  test('applying it once is enough', () async {
    final snapshot = await backups.backupTo(target());
    await backups.stageRestore(
        File(p.join(snapshot.folder.path, 'database.sqlite')));
    await db.close();

    expect(await relaunch(), isTrue);
    expect(await relaunch(), isFalse,
        reason: 'a restore that reapplied on every launch would undo every '
            'payment taken since');
  });

  group('validation', () {
    /// Builds a SQLite file through the open connection, which is the only
    /// handle these tests have.
    Future<File> makeDatabase(String name, List<String> statements) async {
      final file = File(p.join(workspace.path, name));
      await db.customStatement(
          "ATTACH DATABASE '${file.path}' AS candidate_build");
      try {
        for (final statement in statements) {
          await db.customStatement(statement);
        }
      } finally {
        await db.customStatement('DETACH DATABASE candidate_build');
      }
      return file;
    }

    test('rejects another program\'s database', () async {
      final foreign = await makeDatabase('photos.sqlite', [
        'CREATE TABLE candidate_build.photos (id INTEGER PRIMARY KEY)',
      ]);

      final problem = await backups.validateBackup(foreign);
      expect(problem, isNotNull);
      expect(problem, contains('not a Rich Man Fitness backup'),
          reason: 'it passes the magic-bytes check like any SQLite file, and '
              'restoring it leaves an app that will not start');
    });

    test('rejects a backup from a newer version of the app', () async {
      final snapshot = await backups.backupTo(target());
      final file = File(p.join(snapshot.folder.path, 'database.sqlite'));

      await db.customStatement("ATTACH DATABASE '${file.path}' AS newer");
      await db.customStatement(
          'PRAGMA newer.user_version = ${db.schemaVersion + 5}');
      await db.customStatement('DETACH DATABASE newer');

      final problem = await backups.validateBackup(file);
      expect(problem, contains('newer version'),
          reason: 'drift cannot migrate downwards, so this bricks startup');
    });

    test('rejects a truncated file', () async {
      // The real header, and then nothing that follows it — which is what a
      // copy interrupted halfway onto a USB stick looks like.
      final broken = File(p.join(workspace.path, 'half.sqlite'));
      await broken.writeAsBytes([
        ...utf8.encode('SQLite format 3'),
        0,
        ...List.filled(64, 0),
      ]);

      expect(await backups.validateBackup(broken), isNotNull);
    });

    test('accepts a real snapshot', () async {
      final snapshot = await backups.backupTo(target());
      expect(
        await backups.validateBackup(
            File(p.join(snapshot.folder.path, 'database.sqlite'))),
        isNull,
      );
    });

    test('a rejected file is never staged', () async {
      final foreign = await makeDatabase('other.sqlite', [
        'CREATE TABLE candidate_build.notes (id INTEGER PRIMARY KEY)',
      ]);

      expect(await backups.stageRestore(foreign), isNotNull);
      expect(await relaunch(), isFalse,
          reason: 'nothing may be left staged for the next launch to apply');
    });

    test('the connection still works after inspecting a candidate', () async {
      final foreign = await makeDatabase('another.sqlite', [
        'CREATE TABLE candidate_build.stuff (id INTEGER PRIMARY KEY)',
      ]);

      await backups.validateBackup(foreign);
      await backups.validateBackup(foreign);

      // A candidate left attached would break the next validation and, worse,
      // every query the app makes afterwards.
      expect((await db.select(db.members).get()).length, 1);
    });
  });
}
