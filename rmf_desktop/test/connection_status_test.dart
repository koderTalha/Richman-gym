import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/widgets/connection_status.dart';

/// The little icon in the top bar saying whether this computer is reaching
/// GitHub, and whether a release is waiting.
///
/// The gym asked for it after a week of not knowing whether "no update" meant
/// "you are up to date" or "this thing never connects". Both looked identical:
/// silence.
///
/// It reports the **last check**, not a live ping — nothing here opens a socket
/// of its own. Tapping it runs a fresh check, which is what makes it an answer
/// rather than a decoration.
///
/// The distinction that earns its keep: being rate-limited or getting an error
/// from GitHub means the connection is fine and GitHub is not. Showing that as
/// "offline" would send the owner to reset a router that was never the problem.
void main() {
  late AppDatabase db;
  late Directory workspace;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    workspace = await Directory.systemTemp.createTemp('rmf-conn');
  });

  tearDown(() async {
    await db.close();
    await workspace.delete(recursive: true);
  });

  UpdateService service() => UpdateService(
        db: db,
        currentVersion: const AppVersion(1, 1, 0),
        audit: AuditRepository(db),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        windows: true,
        settings: SettingsRepository(db),
        backups: BackupService(db, supportDirectory: () async => workspace),
        supportDirectory: () async => workspace,
        startProcess: (exe, args) async => Process.start('true', const []),
      );

  Future<_StubUpdateBloc> pumpIcon(
    WidgetTester tester,
    UpdateState state,
  ) async {
    final bloc = _StubUpdateBloc(service())..put(state);
    addTearDown(bloc.close);

    await tester.pumpWidget(BlocProvider<UpdateBloc>.value(
      value: bloc,
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(body: Center(child: ConnectionStatusIcon())),
      ),
    ));
    await tester.pump();
    return bloc;
  }

  String tooltipText(WidgetTester tester) =>
      tester.widget<Tooltip>(find.byType(Tooltip)).message ?? '';

  IconData iconShown(WidgetTester tester) =>
      tester.widget<Icon>(find.byType(Icon)).icon!;

  UpdateAvailable waiting() => UpdateAvailable(
        current: const AppVersion(1, 1, 0),
        version: const AppVersion(1, 2, 0),
        installerUrl: Uri.parse('https://github.com/x/y/i.exe'),
        checksumUrl: Uri.parse('https://github.com/x/y/i.exe.sha256'),
        sizeBytes: 1024,
      );

  testWidgets('connected, and nothing new to report', (tester) async {
    await pumpIcon(
      tester,
      UpdateState(
        status: UpdateStatus.upToDate,
        lastCheckedAt: DateTime(2026, 9, 12, 9, 30),
      ),
    );

    expect(iconShown(tester), Icons.wifi);
    expect(tooltipText(tester), contains('Connected'));
    expect(tooltipText(tester), contains('latest version'));
    expect(tooltipText(tester), contains('09:30'),
        reason: 'the icon reports the last check, so it has to say when');
  });

  testWidgets('connected, with a release waiting', (tester) async {
    await pumpIcon(
      tester,
      UpdateState(
        status: UpdateStatus.available,
        available: waiting(),
        lastCheckedAt: DateTime(2026, 9, 12, 9, 30),
      ),
    );

    expect(tooltipText(tester), contains('Connected'));
    expect(tooltipText(tester), contains('1.2.0'));
    expect(find.byKey(connectionUpdateDotKey), findsOneWidget,
        reason: 'a release waiting is the one thing worth catching the eye');
  });

  testWidgets('no dot when there is nothing waiting', (tester) async {
    await pumpIcon(tester, const UpdateState(status: UpdateStatus.upToDate));

    expect(find.byKey(connectionUpdateDotKey), findsNothing);
  });

  testWidgets('offline says so plainly', (tester) async {
    await pumpIcon(
      tester,
      const UpdateState(
        status: UpdateStatus.failed,
        failureKind: UpdateFailureKind.offline,
        error: 'Could not reach GitHub to check for updates.',
      ),
    );

    expect(iconShown(tester), Icons.wifi_off);
    expect(tooltipText(tester).toLowerCase(), contains('no internet'));
  });

  testWidgets('a rate limit is not called an outage of the connection',
      (tester) async {
    await pumpIcon(
      tester,
      const UpdateState(
        status: UpdateStatus.failed,
        failureKind: UpdateFailureKind.rateLimited,
        error: 'GitHub is rate limiting update checks from this network.',
      ),
    );

    expect(iconShown(tester), isNot(Icons.wifi_off),
        reason: 'the connection is fine and GitHub is not — showing this as '
            'offline sends the owner to reset a working router');
    expect(tooltipText(tester), contains('Connected'));
  });

  testWidgets('a release published without its checksum is named as such',
      (tester) async {
    await pumpIcon(
      tester,
      const UpdateState(
        status: UpdateStatus.failed,
        failureKind: UpdateFailureKind.unusableRelease,
        error: 'Release 1.2.0 has no checksum published.',
      ),
    );

    expect(tooltipText(tester), contains('Connected'));
    expect(tooltipText(tester), contains('checksum'));
  });

  testWidgets('says when it has never managed to check', (tester) async {
    await pumpIcon(tester, const UpdateState());

    expect(tooltipText(tester).toLowerCase(), contains('not checked yet'));
  });

  testWidgets('tapping it asks GitHub again', (tester) async {
    final bloc = await pumpIcon(
      tester,
      const UpdateState(
        status: UpdateStatus.failed,
        failureKind: UpdateFailureKind.offline,
      ),
    );

    await tester.tap(find.byKey(appShellConnectionKey));
    await tester.pump();

    expect(bloc.received.whereType<UpdateCheckRequested>().single.force, isTrue,
        reason: 'a deliberate press must ask now, not report this morning\'s '
            'answer back');
  });
}

/// Lets a test put the icon into a state without running a check, and records
/// what the icon asked for.
class _StubUpdateBloc extends UpdateBloc {
  _StubUpdateBloc(super.service);

  final received = <UpdateEvent>[];

  void put(UpdateState state) => emit(state);

  @override
  void add(UpdateEvent event) => received.add(event);
}
