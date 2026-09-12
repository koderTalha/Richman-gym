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

    test('still checks off Windows, but will not install', () async {
      // Checking is an HTTPS GET against a public endpoint and works
      // anywhere. Only applying an Inno Setup .exe is Windows-only. Refusing
      // to even ask elsewhere left the owner pressing a button that did
      // nothing, and made the feature untestable off the gym's machine.
      final service = serviceWith(serving(), windows: false);

      expect(service.canCheck, isTrue);
      expect(service.canInstall, isFalse);
      expect(service.isSupported, isFalse,
          reason: 'the old name means "can apply an update", which is what '
              'every existing caller used it for');
      expect(await service.isDueForCheck(), isTrue);
      expect(await service.check(), isA<UpdateAvailable>());
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

  group('when GitHub cannot answer', () {
    /// A response with headers, which is what tells a rate limit apart from an
    /// ordinary refusal.
    MockClient answering(int status, {Map<String, String> headers = const {}, String body = '{}'}) =>
        MockClient((request) async => http.Response(body, status,
            headers: {'content-type': 'application/json', ...headers}));

    test('names the rate limit instead of calling it a server error', () async {
      final service = serviceWith(answering(403, headers: {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset':
            '${DateTime.utc(2026, 8, 20, 10).millisecondsSinceEpoch ~/ 1000}',
      }));

      final result = await service.check(now: DateTime(2026, 8, 20, 9));

      expect(result, isA<UpdateCheckFailed>());
      final failed = result as UpdateCheckFailed;
      expect(failed.kind, UpdateFailureKind.rateLimited);
      expect(failed.reason, contains('rate limit'));
    });

    test('says so when the repository has no releases', () async {
      final result = await serviceWith(answering(404)).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).kind,
          UpdateFailureKind.noReleases);
    });

    test('an answer that is not a release is not a crash', () async {
      final result = await serviceWith(
        answering(200, body: '<html>504 Gateway Timeout</html>'),
      ).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).kind,
          UpdateFailureKind.malformedResponse);
    });

    test('a JSON array where an object belongs is not a crash', () async {
      final result = await serviceWith(answering(200, body: '[]')).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).kind,
          UpdateFailureKind.malformedResponse);
    });

    /// The bug this group exists for: a minute of GitHub being unavailable used
    /// to count as the day's check, so the gym was told nothing until tomorrow.
    test('an error does not count as today\'s check', () async {
      final morning = DateTime(2026, 8, 20, 9);
      final service = serviceWith(answering(503));

      await service.check(now: morning);

      expect(
        await service.isDueForCheck(now: morning.add(const Duration(hours: 1))),
        isTrue,
        reason: 'nothing was learned, so there is still a question to ask',
      );
    });

    test('an offline machine does not count as today\'s check', () async {
      final morning = DateTime(2026, 8, 20, 9);
      final service = serviceWith(
        MockClient((_) async => throw const SocketException('no route')),
      );

      await service.check(now: morning);

      expect(
        await service.isDueForCheck(now: morning.add(const Duration(hours: 1))),
        isTrue,
      );
    });

    test('a failure is not retried on a loop within the same session',
        () async {
      final morning = DateTime(2026, 8, 20, 9);
      final service = serviceWith(answering(503));

      await service.check(now: morning);

      expect(
        await service
            .isDueForCheck(now: morning.add(const Duration(minutes: 1))),
        isFalse,
        reason: 'a rebuilt screen must not ask GitHub again immediately',
      );
    });
  });

  group('a release that must not be installed', () {
    MockClient serveRelease(Map<String, Object?> body) => MockClient(
        (_) async => http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'}));

    test('a draft is never offered', () async {
      final result = await serviceWith(serveRelease({
        'tag_name': 'v1.2.0',
        'draft': true,
        'assets': const [],
      })).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).reason, contains('draft'));
    });

    test('a pre-release is never offered', () async {
      final result = await serviceWith(serveRelease({
        'tag_name': 'v1.2.0',
        'prerelease': true,
        'assets': const [],
      })).check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).reason, contains('pre-release'));
    });

    test('nothing is offered when the installed version is unknown', () async {
      final service = UpdateService(
        db: db,
        currentVersion: AppVersion.unknown,
        audit: audit,
        httpClient: serving(),
        windows: true,
        settings: SettingsRepository(db),
        backups: BackupService(db, supportDirectory: () async => workspace),
        supportDirectory: () async => workspace,
        startProcess: (exe, args) async => throw UnimplementedError(),
      );

      expect(service.isSupported, isFalse);
      final result = await service.check();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).kind,
          UpdateFailureKind.unknownCurrentVersion,
          reason: 'every release looks newer than an unknown version');
    });
  });

  group('remembering the answer', () {
    /// Reopening the app the same day used to lose a waiting update entirely:
    /// the check was skipped as "already done today" and there was nothing left
    /// to show.
    test('a waiting update survives a restart without asking again', () async {
      await serviceWith(serving()).check(now: DateTime(2026, 8, 20, 9));

      final afterRestart = serviceWith(
        MockClient((_) async => fail('the network must not be touched')),
      );

      final remembered = await afterRestart.lastKnownResult();

      expect(remembered, isA<UpdateAvailable>());
      expect((remembered! as UpdateAvailable).version,
          const AppVersion(1, 2, 0));
    });

    test('nothing is remembered before the first check', () async {
      expect(await serviceWith(serving()).lastKnownResult(), isNull);
    });

    test('asks conditionally, and reuses the answer to a 304', () async {
      final sent = <http.BaseRequest>[];
      MockClient tagging({int status = 200}) => MockClient((request) async {
            sent.add(request);
            if (status == 304) return http.Response('', 304);
            return http.Response(release(), 200, headers: {
              'content-type': 'application/json',
              'etag': 'W/"abc123"',
            });
          });

      await serviceWith(tagging()).check(now: DateTime(2026, 8, 20, 9));
      expect(sent.single.headers.containsKey('If-None-Match'), isFalse,
          reason: 'nothing was cached yet');

      final result =
          await serviceWith(tagging(status: 304)).check(now: DateTime(2026, 8, 21, 9));

      expect(sent.last.headers['If-None-Match'], 'W/"abc123"',
          reason: 'a conditional request costs no rate limit when it is a 304');
      expect(result, isA<UpdateAvailable>(),
          reason: '304 means the cached release is still the latest one');
    });

    test('a stored answer that is only an older release reads as current',
        () async {
      await serviceWith(serving(), current: '1.1.0')
          .check(now: DateTime(2026, 8, 20, 9));

      // The same cache, read by a copy that has since been updated.
      final upgraded = serviceWith(
        MockClient((_) async => fail('the network must not be touched')),
        current: '1.2.0',
      );

      expect(await upgraded.lastKnownResult(), isA<AlreadyCurrent>());
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
