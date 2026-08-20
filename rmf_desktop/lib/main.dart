import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'bloc/auth_bloc.dart';
import 'bloc/theme_cubit.dart';
import 'bloc/update_bloc.dart';
import 'data/audit_repository.dart';
import 'data/database.dart';
import 'data/member_repository.dart';
import 'data/payment_repository.dart';
import 'data/receipt_repository.dart';
import 'data/seed.dart';
import 'data/session_repository.dart';
import 'data/settings_repository.dart';
import 'services/backup_service.dart';
import 'services/billing_maintenance.dart';
import 'services/billing_month_checker.dart';
import 'services/payment_edit_service.dart';
import 'services/logging/app_logger.dart';
import 'domain/app_version.dart';
import 'services/receipt_renderer.dart';
import 'services/receipt_storage.dart';
import 'services/update/update_service.dart';
import 'services/record_payment_service.dart';
import 'theme/app_theme.dart';
import 'ui/app_shell.dart';
import 'ui/first_run_password_screen.dart';
import 'ui/login_screen.dart';
import 'ui/startup_failure_screen.dart';

final _log = Logger('startup');

// Everything runs inside runGuarded so that an error escaping startup or the
// widget tree lands in the log file rather than vanishing. The binding must be
// initialised inside the same zone as runApp, which is why it sits in here.
Future<void> main() => runGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();

      await initLogging();

      try {
        runApp(await _boot());
      } catch (error, stack) {
        // Startup is the one place where an unhandled error costs the owner
        // everything: runApp is never reached, so the window opens blank and
        // stays that way, with nothing on screen to say what went wrong or
        // where to look. A database that will not open — most often because
        // something was restored over it — has to say so.
        _log.severe('The app could not start', error, stack);
        runApp(StartupFailureApp(error: error));
      }
    });

/// Everything that has to happen before the first frame can be painted.
Future<Widget> _boot() async {
  // Must run before the database is opened: a staged restore replaces the very
  // file drift is about to hold a lock on.
  await BackupService.applyPendingRestore();

  final db = AppDatabase();

  // Idempotent: creates the admin account, settings and plans on first launch
  // and is a no-op afterwards. Also the first thing to touch the database, so
  // it is where an unreadable file surfaces.
  await seedDatabase(db);

  // Rolls each active membership into the current billing cycle, so members who
  // owe this month read DUE rather than looking like lapsed memberships.
  await BillingMaintenance(db).ensureCurrentPeriods();

  // Read before the first frame so the app opens in the owner's chosen theme
  // rather than flashing dark and correcting itself.
  final theme = ThemeCubit.parse((await SettingsRepository(db).get()).themeMode);

  // Likewise for the session: restoring here means the dashboard is the first
  // thing painted, with no login form flashing past on the way.
  final restored = await SessionRepository(db).restore();

  // Read from the executable rather than a constant, so the update check
  // compares against what is genuinely installed. Falls back to the version
  // this source was built from if the platform cannot say.
  final packageInfo = await PackageInfo.fromPlatform();
  final version = AppVersion.tryParse(packageInfo.version) ??
      const AppVersion(0, 0, 0);

  // Cheap insurance: one snapshot a day, seven kept. Deliberately not awaited —
  // it snapshots the database and builds a workbook out of the gym's whole
  // history, and making the owner wait behind that every morning is a poor
  // trade for a backup that is just as good taken a second later.
  unawaited(_autoBackup(db));

  return RichManFitnessApp(
    db: db,
    initialTheme: theme,
    restoredUser: restored,
    version: version,
  );
}

Future<void> _autoBackup(AppDatabase db) async {
  try {
    await BackupService(db).autoBackup();
  } catch (error, stack) {
    _log.severe('Automatic backup skipped', error, stack);
  }
}

class RichManFitnessApp extends StatelessWidget {
  const RichManFitnessApp({
    super.key,
    required this.db,
    this.initialTheme = ThemeMode.dark,
    this.restoredUser,
    this.version = const AppVersion(0, 0, 0),
  });

  final AppDatabase db;
  final ThemeMode initialTheme;

  /// The version this copy was built as, for the update check.
  final AppVersion version;

  /// Signed in on a previous run; null means show the login screen.
  final User? restoredUser;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsRepository(db);
    final storage = ReceiptStorage();
    final audit = AuditRepository(db);
    final renderer = ReceiptRenderer();

    // Rebuilt per send, so changing the provider in Settings takes effect
    // immediately without restarting the app.
    final recordPayments = RecordPaymentService(
      db: db,
      renderer: renderer,
      storage: storage,
      clientFactory: settings.buildClient,
      audit: audit,
    );

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<SettingsRepository>.value(value: settings),
        RepositoryProvider<ReceiptStorage>.value(value: storage),
        RepositoryProvider<AuditRepository>.value(value: audit),
        RepositoryProvider<BillingMonthChecker>(
          create: (_) => BillingMonthChecker(db, settings: settings),
        ),
        RepositoryProvider<MemberRepository>(
          create: (_) => MemberRepository(db, audit: audit),
        ),
        RepositoryProvider<PaymentRepository>(
          create: (_) => PaymentRepository(db),
        ),
        RepositoryProvider<ReceiptRepository>(
          create: (_) => ReceiptRepository(db),
        ),
        RepositoryProvider<RecordPaymentService>.value(value: recordPayments),
        RepositoryProvider<UpdateService>(
          create: (_) => UpdateService(
            db: db,
            currentVersion: version,
            audit: audit,
            settings: settings,
          ),
        ),
        RepositoryProvider<PaymentEditService>(
          create: (_) => PaymentEditService(
            db: db,
            renderer: renderer,
            storage: storage,
            audit: audit,
            payments: recordPayments,
            settings: settings,
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => AuthBloc(db, restored: restoredUser)),
          // Above MaterialApp so the login screen follows the theme too.
          BlocProvider(
            create: (_) => ThemeCubit(settings, initial: initialTheme),
          ),
          // Above MaterialApp so the banner in the shell and the card in
          // Settings read one state machine. Checks on open, at most once a
          // day; a failure is a log line, not something on screen.
          BlocProvider(
            create: (context) =>
                UpdateBloc(context.read<UpdateService>())
                  ..add(const UpdateCheckRequested()),
          ),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) => MaterialApp(
            title: 'Rich Man Fitness',
            debugShowCheckedModeBanner: false,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: themeMode,
            home: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                if (state.mustChangePassword) {
                  return const FirstRunPasswordScreen();
                }
                return state.isSignedIn ? const AppShell() : const LoginScreen();
              },
            ),
          ),
        ),
      ),
    );
  }
}

