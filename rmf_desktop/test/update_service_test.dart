import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/app_version.dart';
import 'package:rich_man_fitness/services/backup_service.dart';
import 'package:rich_man_fitness/services/update/update_service.dart';

/// This class decides whether the gym's computer downloads a file and executes
/// it. Most of what matters here is the cases where it must refuse.
void main() {
  late Directory workspace;
  late AppDatabase db;
  late AuditRepository audit;

  const installerBytes = 'pretend this is 14MB of installer';
  final installerDigest =
      sha256.convert(utf8.encode(installerBytes)).toString();

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-update');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    audit = AuditRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  /// A releases/latest payload shaped the way GitHub returns it.
  String release({
    String tag = 'v1.2.0',
    String? installerName = 'RichManFitness-Setup-1.2.0.exe',
    String? checksumName = 'RichManFitness-Setup-1.2.0.exe.sha256',
    String host = 'objects.githubusercontent.com',
    String scheme = 'https',
    String notes = 'Fixes the thing.',
  }) =>
      jsonEncode({
        'tag_name': tag,
        'body': notes,
        'assets': [
          if (installerName != null)
            {
              'name': installerName,
              'size': installerBytes.length,
              'browser_download_url': '$scheme://$host/installer.exe',
            },
          if (checksumName != null)
            {
              'name': checksumName,
              'size': 64,
              'browser_download_url': '$scheme://$host/installer.exe.sha256',
            },
        ],
      });

  /// Serves the release JSON, the installer and its checksum.
  MockClient serving({
    String? releaseJson,
    int releaseStatus = 200,
    String? payload,
    String? publishedDigest,
    int assetStatus = 200,
  }) =>
      MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(releaseJson ?? release(), releaseStatus);
        }
        if (request.url.path.endsWith('.sha256')) {
          return http.Response(
            '${publishedDigest ?? installerDigest}  installer.exe\n',
            assetStatus,
          );
        }
        return http.Response(payload ?? installerBytes, assetStatus);
      });

  final started = <(String, List<String>)>[];

  UpdateService serviceWith(
    http.Client client, {
    String current = '1.1.0',
    bool windows = true,
    BackupService? backups,
    Future<Process> Function(String, List<String>)? startProcess,
  }) {
    started.clear();
    return UpdateService(
      db: db,
      currentVersion: AppVersion.tryParse(current)!,
      audit: audit,
      httpClient: client,
      windows: windows,
      settings: SettingsRepository(db),
      backups: backups ??
          BackupService(db, supportDirectory: () async => workspace),
      supportDirectory: () async => workspace,
      startProcess: startProcess ??
          (exe, args) async {
            started.add((exe, args));
            // A process that exits immediately stands in for the installer.
            return Process.start('true', const []);
          },
    );
  }

  group('checking', () {
    test('offers a newer release', () async {
      final result = await serviceWith(serving()).check();

      expect(result, isA<UpdateAvailable>());
      final available = result as UpdateAvailable;
      expect(available.version, const AppVersion(1, 2, 0));
      expect(available.current, const AppVersion(1, 1, 0));
      expect(available.sizeBytes, installerBytes.length);
      expect(available.notes, 'Fixes the thing.');
      expect(available.installerUrl.host, 'objects.githubusercontent.com');
    });

    test('says nothing when the release is the installed version', () async {
      final result =
          await serviceWith(serving(), current: '1.2.0').check();

      expect(result, isA<AlreadyCurrent>());
    });

    test('never offers an older release as an update', () async {
      final result =
          await serviceWith(serving(), current: '2.0.0').check();

      expect(result, isA<AlreadyCurrent>(),
          reason: 'a downgrade must never be presented as an update');
    });

    test('refuses a release with no checksum published', () async {
      final result = await serviceWith(
        serving(releaseJson: release(checksumName: null)),
      ).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).reason, contains('verified'));
    });

    test('refuses a release with no installer attached', () async {
      final result = await serviceWith(
        serving(releaseJson: release(installerName: null)),
      ).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).reason, contains('no installer'));
    });

    test('ignores an asset hosted somewhere other than GitHub', () async {
      final result = await serviceWith(
        serving(releaseJson: release(host: 'installers.example.com')),
      ).check();

      expect(result, isA<UpdateCheckFailed>(),
          reason: 'this URL becomes an executable on the gym computer');
    });

    test('ignores an asset served over plain http', () async {
      final result = await serviceWith(
        serving(releaseJson: release(scheme: 'http')),
      ).check();

      expect(result, isA<UpdateCheckFailed>());
    });

    test('ignores a release tagged with something unparseable', () async {
      for (final tag in ['latest', 'v1.2.0-rc1', 'release-2']) {
        final result =
            await serviceWith(serving(releaseJson: release(tag: tag))).check();
        expect(result, isA<UpdateCheckFailed>(), reason: 'tag "$tag"');
      }
    });

    test('an offline machine reports a failure rather than throwing', () async {
      final result = await serviceWith(
        MockClient((_) async => throw const SocketException('no route')),
      ).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).reason, contains('Could not reach'));
    });

    test('a GitHub outage reports a failure', () async {
      final result =
          await serviceWith(serving(releaseStatus: 503)).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).reason, contains('503'));
    });

    test('records that it checked, so it does not ask again today', () async {
      final service = serviceWith(serving());
      expect(await service.isDueForCheck(), isTrue,
          reason: 'never checked before');

      await service.check(now: DateTime(2026, 8, 20, 9));

      expect(await service.isDueForCheck(now: DateTime(2026, 8, 20, 17)),
          isFalse);
      expect(await service.isDueForCheck(now: DateTime(2026, 8, 21, 9)), isTrue,
          reason: 'the gym opens again tomorrow');
    });

    test('does nothing at all off Windows', () async {
      final service = serviceWith(serving(), windows: false);

      expect(service.isSupported, isFalse);
      expect(await service.isDueForCheck(), isFalse);
      expect(await service.check(), isA<UpdateCheckFailed>());
    });
  });

  group('"Later"', () {
    test('remembers the version the owner skipped', () async {
      final service = serviceWith(serving());

      expect(await service.dismissedVersion(), isNull);
      await service.dismiss(const AppVersion(1, 2, 0));

      expect(await service.dismissedVersion(), const AppVersion(1, 2, 0));
    });
  });

  group('installing', () {
    Future<UpdateAvailable> availableUpdate(UpdateService service) async =>
        await service.check() as UpdateAvailable;

    test('takes a backup before anything is downloaded', () async {
      final service = serviceWith(serving());
      final result = await service.install(await availableUpdate(service));

      expect(result, isA<UpdateLaunched>());

      final backups = Directory(p.join(workspace.path, 'backups'));
      final snapshots = backups.listSync().whereType<Directory>().toList();
      expect(snapshots, hasLength(1),
          reason: 'the new version migrates the database before its own daily '
              'backup would run, so this is the only copy that predates it');
      expect(
        File(p.join(snapshots.single.path, 'database.sqlite')).existsSync(),
        isTrue,
      );
    });

    test('runs the installer silently once verified', () async {
      final service = serviceWith(serving());
      final result = await service.install(await availableUpdate(service));

      expect(result, isA<UpdateLaunched>());
      expect((result as UpdateLaunched).version, const AppVersion(1, 2, 0));

      expect(started, hasLength(1));
      final (exe, args) = started.single;
      expect(exe, endsWith('RichManFitness-Setup-1.2.0.exe'));
      expect(args, ['/VERYSILENT', '/NORESTART'],
          reason: 'no prompts, and no administrator password on a gym PC');
      expect(File(exe).existsSync(), isTrue);
    });

    test('refuses to run a download that fails its checksum', () async {
      final service = serviceWith(
        serving(publishedDigest: 'a' * 64),
      );
      final result = await service.install(await availableUpdate(service));

      expect(result, isA<UpdateInstallFailed>());
      expect((result as UpdateInstallFailed).message,
          contains('did not match its published checksum'));
      expect(started, isEmpty, reason: 'nothing unverified is ever executed');

      final updates = Directory(p.join(workspace.path, 'updates'));
      expect(updates.listSync(), isEmpty,
          reason: 'the rejected file is deleted, not left lying around');

      final events = (await db.select(db.auditEvents).get())
          .where((e) => e.action == AuditAction.updateVerifyFailed);
      expect(events, hasLength(1));
      expect(events.single.outcome, AuditOutcome.failed);
    });

    test('refuses a checksum file that is not a checksum', () async {
      final service = serviceWith(serving(publishedDigest: 'not-a-digest'));
      final result = await service.install(await availableUpdate(service));

      expect(result, isA<UpdateInstallFailed>());
      expect(started, isEmpty);
    });

    test('abandons the update if the backup fails', () async {
      final service = serviceWith(
        serving(),
        // A support directory that cannot be created stands in for a disk
        // that is full or a folder that is locked.
        backups: BackupService(
          db,
          supportDirectory: () async =>
              throw const FileSystemException('no space left on device'),
        ),
      );

      final result = await service.install(await availableUpdate(service));

      expect(result, isA<UpdateInstallFailed>());
      expect((result as UpdateInstallFailed).message,
          contains('backup could not be taken'));
      expect(started, isEmpty, reason: 'no backup, no update');

      final events = (await db.select(db.auditEvents).get())
          .where((e) => e.action == AuditAction.updateBackupFailed);
      expect(events.single.outcome, AuditOutcome.failed);
    });

    test('keeps the verified installer if it cannot be started', () async {
      final service = serviceWith(
        serving(),
        startProcess: (exe, args) async =>
            throw const ProcessException('setup.exe', [], 'Access is denied'),
      );

      final result = await service.install(await availableUpdate(service));

      expect(result, isA<UpdateInstallFailed>());
      final failed = result as UpdateInstallFailed;
      expect(failed.keptInstallerAt, isNotNull,
          reason: 'the owner can still run it by hand rather than being stuck');
      expect(File(failed.keptInstallerAt!).existsSync(), isTrue);
      expect(failed.message, contains('run by hand'));
    });

    test('a failed download changes nothing', () async {
      final service = serviceWith(serving(assetStatus: 404));
      final result = await service.install(await availableUpdate(service));

      expect(result, isA<UpdateInstallFailed>());
      expect(started, isEmpty);
    });

    test('replaces a stale half-finished download', () async {
      final updates = Directory(p.join(workspace.path, 'updates'));
      await updates.create(recursive: true);
      final stale =
          File(p.join(updates.path, 'RichManFitness-Setup-1.2.0.exe'));
      await stale.writeAsString('half a download from last week');

      final service = serviceWith(serving());
      final result = await service.install(await availableUpdate(service));

      expect(result, isA<UpdateLaunched>(),
          reason: 'the stale file must not be what gets verified or run');
      expect(await stale.readAsString(), installerBytes);
    });

    test('reports progress as it downloads', () async {
      final service = serviceWith(serving());
      final seen = <int>[];

      await service.install(
        await availableUpdate(service),
        onProgress: (received, total) => seen.add(received),
      );

      expect(seen, isNotEmpty);
      expect(seen.last, installerBytes.length);
    });

    test('will not install off Windows', () async {
      final onWindows = serviceWith(serving());
      final update = await availableUpdate(onWindows);

      final result = await serviceWith(serving(), windows: false)
          .install(update);

      expect(result, isA<UpdateInstallFailed>());
      expect(started, isEmpty);
    });
  });

  group('the audit trail', () {
    test('records an available update and the install that follows', () async {
      final service = serviceWith(serving());
      await service.install(await service.check() as UpdateAvailable);

      final actions = (await db.select(db.auditEvents).get())
          .map((e) => e.action)
          .toList();

      expect(
        actions,
        containsAllInOrder(
            [AuditAction.updateAvailable, AuditAction.updateInstalling]),
      );

      final installing = (await db.select(db.auditEvents).get())
          .firstWhere((e) => e.action == AuditAction.updateInstalling);
      expect(installing.category, AuditCategory.update);
      expect(installing.summary, contains('1.2.0'));
      expect(installing.detail, contains(installerDigest));
    });
  });
}
