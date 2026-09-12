import 'dart:convert';
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
import 'package:rich_man_fitness/ui/widgets/update_banner.dart';

/// The strip that tells the owner a new version has been published.
///
/// This is the "notification" half of the gym's report. The banner itself was
/// always here and always wired into the shell — what was missing was anything
/// ever putting the bloc into the state that shows it, because the check
/// returned early before it ran.
///
/// Deliberately a strip and not a dialog: the owner may be halfway through
/// taking a payment, and no release is urgent enough to interrupt that.
void main() {
  late AppDatabase db;
  late Directory workspace;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    workspace = await Directory.systemTemp.createTemp('rmf-banner');
  });

  tearDown(() async {
    await db.close();
    await workspace.delete(recursive: true);
  });

  String release() => jsonEncode({
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
          {
            'name': 'RichManFitness-Setup-1.2.0.exe.sha256',
            'size': 64,
            'browser_download_url':
                'https://github.com/x/y/releases/download/v1.2.0/i.exe.sha256',
          },
        ],
      });

  UpdateService serviceFor({required bool windows}) => UpdateService(
        db: db,
        currentVersion: const AppVersion(1, 1, 0),
        audit: AuditRepository(db),
        httpClient: MockClient((_) async => http.Response(release(), 200)),
        windows: windows,
        settings: SettingsRepository(db),
        backups: BackupService(db, supportDirectory: () async => workspace),
        supportDirectory: () async => workspace,
        startProcess: (exe, args) async => Process.start('true', const []),
      );

  Future<void> pumpBanner(WidgetTester tester, UpdateBloc bloc) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RepositoryProvider<AppDatabase>.value(
      value: db,
      child: BlocProvider<UpdateBloc>.value(
        value: bloc,
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: const Scaffold(body: UpdateBanner()),
        ),
      ),
    ));
    await tester.pump();
  }

  /// The state a completed check would have produced.
  ///
  /// Set directly rather than reached by running a real check: the banner's
  /// job is to render a state, and driving the service through the widget
  /// binding means real network and file work that the test clock will not
  /// advance — `pumpAndSettle` then simply waits out its ten-minute default.
  /// What the service puts in this state is covered in
  /// `update_check_feedback_test.dart`.
  UpdateState availableState({required bool canInstall}) => UpdateState(
        status: UpdateStatus.available,
        canInstall: canInstall,
        available: UpdateAvailable(
          current: const AppVersion(1, 1, 0),
          version: const AppVersion(1, 2, 0),
          installerUrl: Uri.parse(
              'https://github.com/x/y/releases/download/v1.2.0/i.exe'),
          checksumUrl: Uri.parse(
              'https://github.com/x/y/releases/download/v1.2.0/i.exe.sha256'),
          sizeBytes: 1024,
        ),
      );

  testWidgets('announces a published version, naming both versions',
      (tester) async {
    final bloc = _StubUpdateBloc(serviceFor(windows: true))
      ..put(availableState(canInstall: true));
    addTearDown(bloc.close);
    await pumpBanner(tester, bloc);

    expect(
      find.textContaining('Version 1.2.0 is available'),
      findsOneWidget,
      reason: 'this is the notification the gym said never appeared',
    );
    expect(find.textContaining('this copy is 1.1.0'), findsOneWidget);
    expect(find.text('Install now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('offers a download where it cannot install', (tester) async {
    final bloc = _StubUpdateBloc(serviceFor(windows: false))
      ..put(availableState(canInstall: false));
    addTearDown(bloc.close);
    await pumpBanner(tester, bloc);

    expect(find.textContaining('Version 1.2.0 is available'), findsOneWidget,
        reason: 'knowing a release is waiting is useful even where this app '
            'cannot apply it');
    expect(find.text('Install now'), findsNothing,
        reason: 'a button whose only possible outcome is an error');
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('stays quiet for a version the owner waved away', (tester) async {
    final bloc = _StubUpdateBloc(serviceFor(windows: true))
      ..put(availableState(canInstall: true).copyDismissed());
    addTearDown(bloc.close);
    await pumpBanner(tester, bloc);

    expect(find.textContaining('is available'), findsNothing,
        reason: '"Later" means later, including across a restart — the '
            'dismissed version is remembered in settings');
  });

  testWidgets('shows nothing when the app is already current',
      (tester) async {
    final bloc = _StubUpdateBloc(serviceFor(windows: true))
      ..put(const UpdateState(status: UpdateStatus.upToDate));
    addTearDown(bloc.close);
    await pumpBanner(tester, bloc);

    expect(find.textContaining('is available'), findsNothing);
  });
}

/// Lets a test put the banner into a state without running a check.
class _StubUpdateBloc extends UpdateBloc {
  _StubUpdateBloc(super.service);

  void put(UpdateState state) => emit(state);
}

extension on UpdateState {
  /// The state after the owner presses "Later".
  UpdateState copyDismissed() => UpdateState(
        status: status,
        available: available,
        canInstall: canInstall,
        total: total,
        dismissed: true,
      );
}
