import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/backup_service.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Two ways a restore used to go wrong without anybody being told (audit
/// SEC-002).
///
/// A backup whose data pages were damaged passed every check, because every
/// check read only the front of the file — and then replaced the gym's good
/// data at the next launch with something that would not open. And a restore
/// that did work left no trace at all: the audit trail it brought back is the
/// backup's, which stops the moment the backup was taken, so restoring an old
/// backup could quietly undo a password reset or a deleted payment.
void main() {
  late Directory workspace;
  late File liveDb;
  late AppDatabase db;
  late BackupService backups;

  Directory target() => Directory(p.join(workspace.path, 'backups'));

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-restore-audit');
    liveDb = File(p.join(workspace.path, 'live.sqlite'));
    db = AppDatabase.forTesting(NativeDatabase(liveDb));
    backups = BackupService(
      db,
      supportDirectory: () async => workspace,
      receiptsDirectory: () async =>
          Directory(p.join(workspace.path, 'receipts')),
    );

    await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Gym Owner',
        email: 'owner@rmf.local',
        passwordHash: BCrypt.hashpw('OwnersOwnSecret9', BCrypt.gensalt())));
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  /// What main() does on the next launch, against the test's own folders.
  Future<bool> relaunch() => BackupService.applyPendingRestore(
        supportDirectory: () async => workspace,
        liveDatabase: () async => liveDb,
      );

  group('a damaged backup', () {
    setUp(() async {
      // Enough members that the data runs well past the schema pages.
      await db.batch((b) {
        for (var i = 1; i <= 3000; i++) {
          b.insert(
              db.members,
              MembersCompanion.insert(
                memberCode: i,
                fullName: 'Member number $i with a reasonably long name',
                phone: '+9230000${i.toString().padLeft(5, '0')}',
                phoneRaw: Value('0300-00${i.toString().padLeft(5, '0')}'),
                joiningDate: DateTime.utc(2026, 1, 1),
              ));
        }
      });
    });

    /// Same length as a real snapshot, but a run of pages in the middle reads
    /// back as zeros — what a bad sector or an interrupted copy over an old
    /// file leaves.
    Future<File> damagedSnapshot() async {
      final snapshot = await backups.backupTo(target());
      final file = File(p.join(snapshot.folder.path, 'database.sqlite'));
      final bytes = await file.readAsBytes();

      final damaged = [...bytes];
      for (var i = bytes.length ~/ 2; i < bytes.length ~/ 2 + 64 * 1024; i++) {
        damaged[i] = 0;
      }
      await file.writeAsBytes(damaged);

      // Prove the file really is unusable: SQLite's own check says so. (It
      // either reports problems or throws "database disk image is
      // malformed".)
      final raw = sqlite.sqlite3.open(file.path);
      Object? check;
      try {
        check = raw.select('PRAGMA integrity_check').first.values.first;
      } on sqlite.SqliteException catch (e) {
        check = e.message;
      } finally {
        raw.close();
      }
      expect(check, isNot('ok'), reason: 'fixture must actually be damaged');
      return file;
    }

    test('is refused before it can replace the live data', () async {
      final verdict = await backups.validateBackup(await damagedSnapshot());

      expect(verdict, isNotNull,
          reason: 'a damaged database is not a backup that can be restored');
      expect(verdict, contains('damaged'));
    });

    test('is never staged, and the connection survives looking at it',
        () async {
      final file = await damagedSnapshot();

      expect(await backups.stageRestore(file), isNotNull);
      expect(await relaunch(), isFalse,
          reason: 'nothing may be left staged for the next launch to apply');

      // A candidate left attached, or a connection poisoned by the malformed
      // read, would break every query the app makes afterwards.
      expect(await db.select(db.members).get(), hasLength(3000));
      expect(await backups.validateBackup(file), isNotNull);
    });

    test('an undamaged snapshot of the same data still passes', () async {
      final snapshot = await backups.backupTo(target());
      expect(
          await backups.validateBackup(
              File(p.join(snapshot.folder.path, 'database.sqlite'))),
          isNull);
    });
  });

  group('a restore that is applied', () {
    test('is written into the restored database on its first launch',
        () async {
      final snapshot =
          await backups.backupTo(target(), now: DateTime(2026, 3, 14, 9, 30));
      final problem = await backups.stageRestore(
        File(p.join(snapshot.folder.path, 'database.sqlite')),
        stagedBy: 'Gym Owner',
        now: DateTime(2026, 10, 1, 18, 5),
      );
      expect(problem, isNull);

      await db.close();
      expect(await relaunch(), isTrue);

      final restored = AppDatabase.forTesting(NativeDatabase(liveDb));
      addTearDown(restored.close);
      expect(
          await BackupService.recordAppliedRestore(restored,
              supportDirectory: () async => workspace),
          isTrue);

      final event = (await restored.select(restored.auditEvents).get()).single;
      expect(event.action, AuditAction.backupRestored);
      expect(event.category, AuditCategory.update);
      expect(event.outcome, AuditOutcome.success);
      expect(event.summary, contains('14 Mar 2026, 09:30'),
          reason: 'which backup — by the date the owner sees it listed under');
      expect(event.actorName, 'Gym Owner');

      final kept = workspace
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .singleWhere((n) => n.startsWith('live.sqlite.replaced-'));
      expect(event.detail, contains(kept),
          reason: 'anything recorded since the backup was taken survives only '
              'in that copy, so the log has to say which file it is');
      expect(event.detail, contains('01 Oct 2026, 18:05'));
    });

    test('is recorded once, not at every launch', () async {
      final snapshot = await backups.backupTo(target());
      await backups.stageRestore(
          File(p.join(snapshot.folder.path, 'database.sqlite')));
      await db.close();
      await relaunch();

      final restored = AppDatabase.forTesting(NativeDatabase(liveDb));
      addTearDown(restored.close);
      Future<bool> record() => BackupService.recordAppliedRestore(restored,
          supportDirectory: () async => workspace);

      expect(await record(), isTrue);
      expect(await record(), isFalse);
      expect(await restored.select(restored.auditEvents).get(), hasLength(1));
    });

    test('is still recorded when the staging left no details behind',
        () async {
      // A restore staged by a release older than this one: just the file.
      final snapshot = await backups.backupTo(target());
      await backups.stageRestore(
          File(p.join(snapshot.folder.path, 'database.sqlite')));
      await File(p.join(workspace.path, 'pending-restore.json')).delete();
      await db.close();
      await relaunch();

      final restored = AppDatabase.forTesting(NativeDatabase(liveDb));
      addTearDown(restored.close);
      await BackupService.recordAppliedRestore(restored,
          supportDirectory: () async => workspace);

      final event = (await restored.select(restored.auditEvents).get()).single;
      expect(event.action, AuditAction.backupRestored);
      expect(event.detail, contains('live.sqlite.replaced-'));
    });

    test('never takes on the details of an earlier staging', () async {
      final first =
          await backups.backupTo(target(), now: DateTime(2026, 1, 2, 8, 0));
      await backups.stageRestore(
          File(p.join(first.folder.path, 'database.sqlite')),
          stagedBy: 'First Person');

      // A second choice, from a file outside any backup folder, replaces the
      // first before the app is restarted.
      final loose = File(p.join(workspace.path, 'loose-copy.sqlite'));
      await File(p.join(first.folder.path, 'database.sqlite')).copy(loose.path);
      await backups.stageRestore(loose, stagedBy: 'Second Person');

      await db.close();
      await relaunch();
      final restored = AppDatabase.forTesting(NativeDatabase(liveDb));
      addTearDown(restored.close);
      await BackupService.recordAppliedRestore(restored,
          supportDirectory: () async => workspace);

      final event = (await restored.select(restored.auditEvents).get()).single;
      expect(event.actorName, 'Second Person');
      expect(event.detail, contains('loose-copy.sqlite'));
      expect(event.summary, isNot(contains('02 Jan 2026')));
    });

    test('a launch with no restore records nothing', () async {
      expect(
          await BackupService.recordAppliedRestore(db,
              supportDirectory: () async => workspace),
          isFalse);
      expect(await db.select(db.auditEvents).get(), isEmpty);
    });
  });

  group('the password asked for before staging', () {
    late int ownerId;
    setUp(() async => ownerId = (await db.select(db.users).getSingle()).id);

    test('accepts only the signed-in account\'s own password', () async {
      expect(
          await backups.passwordMatches(
              userId: ownerId, password: 'OwnersOwnSecret9'),
          isTrue);
      expect(
          await backups.passwordMatches(userId: ownerId, password: 'guess'),
          isFalse);
      expect(await backups.passwordMatches(userId: ownerId, password: ''),
          isFalse);
      expect(
          await backups.passwordMatches(
              userId: ownerId + 99, password: 'OwnersOwnSecret9'),
          isFalse);
    });
  });
}
