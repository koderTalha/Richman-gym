import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rich_man_fitness/bloc/update_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/app_version.dart';
import 'package:rich_man_fitness/services/backup_service.dart';
import 'package:rich_man_fitness/services/update/update_service.dart';

/// Pressing "Check for updates" and being told something.
///
/// Two complaints from the gym, and one cause behind both:
///
///   * "It doesn't connect to GitHub." The button did nothing at all — no
///     spinner, no message, no change. `UpdateBloc` returned early whenever the
///     platform could not *install* an update, so the check never ran and
///     nothing was ever emitted. A button that does nothing reads as a broken
///     connection.
///   * "There is no notification when a new version is published." Same cause:
///     the check that would have found it never ran.
///
/// Checking and installing are separate questions and are now separated.
/// Asking GitHub what the latest release is works anywhere — it is an HTTPS
/// GET — and it is what makes this testable away from the gym's Windows
/// machine. Only applying the installer is Windows-only.
void main() {
  late AppDatabase db;
  late AuditRepository audit;
  late Directory workspace;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    audit = AuditRepository(db);
    workspace = await Directory.systemTemp.createTemp('rmf-update-feedback');
  });

  tearDown(() async {
    await db.close();
    await workspace.delete(recursive: true);
  });

  String release({String tag = 'v1.2.0'}) => jsonEncode({
        'tag_name': tag,
        'draft': false,
        'prerelease': false,
        'body': 'Fixes.',
        'assets': [
          {
            'name': 'RichManFitness-Setup-${tag.substring(1)}.exe',
            'size': 1024,
            'browser_download_url':
                'https://github.com/x/y/releases/download/$tag/installer.exe',
          },
          {
            'name': 'RichManFitness-Setup-${tag.substring(1)}.exe.sha256',
            'size': 64,
            'browser_download_url':
                'https://github.com/x/y/releases/download/$tag/installer.exe.sha256',
          },
        ],
      });

  UpdateService serviceWith({
    String current = '1.1.0',
    bool windows = true,
    http.Client? client,
  }) =>
      UpdateService(
        db: db,
        currentVersion: AppVersion.tryParse(current) ?? AppVersion.unknown,
        audit: audit,
        httpClient: client ??
            MockClient((_) async => http.Response(release(), 200)),
        windows: windows,
        settings: SettingsRepository(db),
        backups: BackupService(db, supportDirectory: () async => workspace),
        supportDirectory: () async => workspace,
        startProcess: (exe, args) async => Process.start('true', const []),
      );

  group('the service', () {
    test('a Mac can still see that a release is waiting', () async {
      final result = await serviceWith(windows: false).check();

      expect(result, isA<UpdateAvailable>(),
          reason: 'asking GitHub what it has published is an HTTPS GET and '
              'works anywhere — refusing to ask is what made this impossible '
              'to test off the gym machine');
      expect((result as UpdateAvailable).version, const AppVersion(1, 2, 0));
    });

    test('but it still refuses to install one', () async {
      final service = serviceWith(windows: false);
      final found = await service.check() as UpdateAvailable;

      expect(service.canCheck, isTrue);
      expect(service.canInstall, isFalse);
      expect(await service.install(found), isA<UpdateInstallFailed>());
    });

    test('checking is refused when the installed version is unknown',
        () async {
      final service = serviceWith(current: 'not-a-version');

      expect(service.canCheck, isFalse);
      final result = await service.check();
      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).kind,
          UpdateFailureKind.unknownCurrentVersion,
          reason: 'without a left-hand side every release looks newer, and '
              'this downloads and runs what it decides is newer');
    });
  });

  group('the bloc', () {
    test('answers a deliberate check even when it cannot install', () async {
      final bloc = UpdateBloc(serviceWith(windows: false));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.status, UpdateStatus.available,
          reason: 'the owner pressed a button and must be told something');
      expect(bloc.state.canInstall, isFalse,
          reason: 'so the card can offer the download page instead of an '
              'Install button that would fail');
    });

    test('pressing Later keeps what the card knows about this machine',
        () async {
      final bloc = UpdateBloc(serviceWith(windows: false));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);
      expect(bloc.state.canInstall, isFalse);
      final checkedAt = bloc.state.lastCheckedAt;
      expect(checkedAt, isNotNull);

      bloc.add(const UpdateDismissed());
      await bloc.stream.firstWhere((s) => s.dismissed);

      expect(bloc.state.canInstall, isFalse,
          reason: 'waving the banner away says nothing about whether this '
              'machine can apply an installer, and the card would go back to '
              'offering an Install button that can only fail');
      expect(bloc.state.lastCheckedAt, checkedAt,
          reason: 'the check that just succeeded did not un-happen, but the '
              'diagnostics line would read "Never"');
    });

    test('answers when the installed version cannot be read', () async {
      final bloc = UpdateBloc(serviceWith(current: 'not-a-version'));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.status, UpdateStatus.failed);
      expect(bloc.state.failureKind, UpdateFailureKind.unknownCurrentVersion);
      expect(bloc.state.error, isNotNull,
          reason: 'silence is what the owner reported as "it does not connect"');
    });

    test('an unreachable GitHub is reported, not swallowed', () async {
      final bloc = UpdateBloc(serviceWith(
        client: MockClient((_) async => throw const SocketException('down')),
      ));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.status, UpdateStatus.failed);
      // Not `offline`: a bare `SocketException('down')` carries none of the
      // evidence — "no route to host", "connection refused" and so on — that
      // would justify telling the owner this machine has no internet. See
      // `classifyNetworkError`.
      expect(bloc.state.failureKind, UpdateFailureKind.unknownNetworkError);
      expect(bloc.state.error, isNotNull);
    });

    test('a machine with no route anywhere is told plainly', () async {
      final bloc = UpdateBloc(serviceWith(
        client: MockClient(
            (_) async => throw const SocketException('no route to host')),
      ));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.status, UpdateStatus.failed);
      expect(bloc.state.failureKind, UpdateFailureKind.offline);
    });

    test('a DNS failure is named, not called offline', () async {
      final bloc = UpdateBloc(serviceWith(
        client: MockClient((_) async => throw const SocketException(
            "Failed host lookup: 'api.github.com'")),
      ));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.failureKind, UpdateFailureKind.dnsFailure);
    });

    test('a TLS handshake failure is named, not called offline', () async {
      final bloc = UpdateBloc(serviceWith(
        client: MockClient((_) async =>
            throw const HandshakeException('certificate verify failed')),
      ));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.failureKind, UpdateFailureKind.tlsFailure);
    });

    test('a connection timeout is named, not called offline', () async {
      final bloc = UpdateBloc(serviceWith(
        client: MockClient((_) async =>
            throw TimeoutException('The request took too long')),
      ));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.failureKind, UpdateFailureKind.connectionTimeout);
    });

    test('a refused connection is named, not called offline', () async {
      final bloc = UpdateBloc(serviceWith(
        client: MockClient((_) async =>
            throw const SocketException('Connection refused')),
      ));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.failureKind, UpdateFailureKind.connectionRefused);
    });

    test('a release with no checksum says so rather than "up to date"',
        () async {
      final bloc = UpdateBloc(serviceWith(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'tag_name': 'v1.2.0',
                'draft': false,
                'prerelease': false,
                'assets': [
                  {
                    'name': 'RichManFitness-Setup-1.2.0.exe',
                    'size': 1024,
                    'browser_download_url':
                        'https://github.com/x/y/releases/download/v1.2.0/i.exe',
                  },
                ],
              }),
              200,
            )),
      ));
      addTearDown(bloc.close);

      bloc.add(const UpdateCheckRequested(force: true));
      await bloc.stream.firstWhere((s) => !s.busy);

      expect(bloc.state.status, UpdateStatus.failed);
      expect(bloc.state.failureKind, UpdateFailureKind.unusableRelease,
          reason: 'a release published without its .sha256 is the one failure '
              'the owner can actually fix, so it must not look like silence');
    });
  });
}
