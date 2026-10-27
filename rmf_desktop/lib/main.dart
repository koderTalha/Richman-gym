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
import 'services/billing_cycle_service.dart';
import 'services/billing_month_checker.dart';
import 'services/payment_edit_service.dart';
import 'services/reminder_service.dart';
import 'services/whatsapp/member_welcome_service.dart';
import 'services/logging/app_logger.dart';
import 'domain/app_version.dart';
import 'services/receipt_renderer.dart';
import 'services/receipt_storage.dart';
import 'services/update/update_service.dart';
import 'services/record_payment_service.dart';
import 'services/startup_maintenance.dart';
import 'bloc/branding_cubit.dart';
import 'theme/app_theme.dart';
import 'theme/branding_config.dart';
import 'ui/app_shell.dart';
import 'ui/automatic_reminders.dart';
import 'ui/first_run_password_screen.dart';
import 'ui/idle_lock.dart';
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

  // A restore applied above gets its audit row now, written into the very
  // database it restored — whose own trail stops when the backup was taken,
  // so without this the restore would leave no trace. Never throws.
  await BackupService.recordAppliedRestore(db);

  // The billing roll and the reconciliation report. Shared with the Reload
  // button in the top bar, so pressing it does exactly what opening the app
  // does — see `services/startup_maintenance.dart`. Guarded: a failure in it
  // is logged and the app opens anyway.
  await runStartupMaintenanceGuarded(db);

  // Read before the first frame so the app opens in the owner's chosen theme
  // rather than flashing dark and correcting itself. One read serves both the
  // light/dark mode and the brand colours — two queries here would be two
  // chances to paint the wrong thing first.
  final settingsRow = await SettingsRepository(db).get();
  final theme = ThemeCubit.parse(settingsRow.themeMode);
  final branding = SettingsRepository.brandingFrom(settingsRow);

  // Likewise for the session: restoring here means the dashboard is the first
  // thing painted, with no login form flashing past on the way. Only within
  // the inactivity limit, and from the deadline it had — see
  // SessionRepository.restore.
  final sessions = SessionRepository(db);
  final restored = await sessions.restore();
  final restoredActiveAt =
      restored == null ? null : await sessions.lastActiveAt();

  // Read from the executable rather than a constant, so the update check
  // compares against what is genuinely installed.
  //
  // 0.0.0 means "the platform would not say". It is deliberately not treated
  // as a very old version: UpdateService refuses to offer anything against it,
  // because a comparison whose left-hand side is unknown would make every
  // release on GitHub look newer and hand the gym an installer on a guess.
  final packageInfo = await PackageInfo.fromPlatform();
  final version = AppVersion.tryParse(packageInfo.version) ?? () {
    _log.severe('The installed version could not be read from the executable '
        '(package_info reported "${packageInfo.version}"). '
        'Update checking is disabled until it can.');
    return AppVersion.unknown;
  }();

  // Cheap insurance: one snapshot a day, seven kept. Deliberately not awaited —
  // it snapshots the database and builds a workbook out of the gym's whole
  // history, and making the owner wait behind that every morning is a poor
  // trade for a backup that is just as good taken a second later.
  unawaited(_autoBackup(db));

  return RichManFitnessApp(
    db: db,
    initialTheme: theme,
    initialBranding: branding,
    restoredUser: restored,
    restoredActiveAt: restoredActiveAt,
    version: version,
  );
}

/// Runs the startup billing work without letting it stop the app opening.
///
/// Before this, any exception out of the roll reached main()'s catch and put
/// the owner on the startup-failure screen at every launch — one bad member
/// row anywhere was enough (audit BUG-009). That screen is for a database
/// that cannot be opened, and by this point it has been: seeding succeeded.
/// A roll that falls over leaves some cycles unopened, which the Reload button
/// can retry, and is far better than no way into the app at all to take the
/// day's payments. The failure is logged severe, so it is on the Logs
/// screen's Technical tab and in any "Send to developer" bundle.
///
/// Returns whether the maintenance finished. [maintenance] is injectable for
/// tests only.
@visibleForTesting
Future<bool> runStartupMaintenanceGuarded(
  AppDatabase db, {
  Future<void> Function(AppDatabase db) maintenance = runStartupMaintenance,
}) async {
  try {
    await maintenance(db);
    return true;
  } catch (error, stack) {
    _log.severe('Startup maintenance failed; opening the app without it. '
        'Some billing cycles may not have been opened or re-priced until it '
        'runs cleanly (the Reload button retries it).', error, stack);
    return false;
  }
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
    this.initialBranding = const BrandingConfig(),
    this.restoredUser,
    this.restoredActiveAt,
    this.version = AppVersion.unknown,
  });

  final AppDatabase db;
  final ThemeMode initialTheme;

  /// The brand the app opens in. Defaults to the original crimson, so a test or
  /// an embedder that does not supply one gets exactly what the app has always
  /// looked like.
  final BrandingConfig initialBranding;

  /// The version this copy was built as, for the update check.
  /// [AppVersion.unknown] disables checking rather than guessing.
  final AppVersion version;

  /// Signed in on a previous run; null means show the login screen.
  final User? restoredUser;

  /// When [restoredUser]'s session was last touched, so the inactivity lock
  /// keeps its deadline across the restart.
  final DateTime? restoredActiveAt;

  @override
  Widget build(BuildContext context) {
    final storage = ReceiptStorage();
    final audit = AuditRepository(db);
    final settings = SettingsRepository(db, audit: audit);
    final renderer = ReceiptRenderer();

    // One instance shared by every service that reads or moves a billing
    // cycle, so a payment recorded through one and a reminder built through
    // another are always looking at the same timeline.
    final cycles = BillingCycleService(db, audit: audit);

    // Rebuilt per send, so changing the provider in Settings takes effect
    // immediately without restarting the app.
    final recordPayments = RecordPaymentService(
      db: db,
      renderer: renderer,
      storage: storage,
      clientFactory: settings.buildClient,
      audit: audit,
      cycles: cycles,
    );

    // Shared by every Add Member screen rather than built per form: its
    // in-flight guard is what stops two forms open at once sending the same
    // member two welcome messages.
    final welcome = MemberWelcomeService(
      db: db,
      clientFactory: settings.buildClient,
      audit: audit,
    );

    final reminders = ReminderService(
      db: db,
      clientFactory: settings.buildClient,
      audit: audit,
      cycles: cycles,
    );

    // Off by default — see GymSettings.reminderAutoSend. A closed gym reopens
    // to at most one capped, hours-aware batch, never a silent backlog blast.
    // AppShell tries again on Reload and hourly; the run never throws and
    // never overlaps itself, so unawaited is safe.
    unawaited(reminders.runAutoSend());

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
        RepositoryProvider<BillingCycleService>.value(value: cycles),
        RepositoryProvider<ReminderService>.value(value: reminders),
        RepositoryProvider<MemberWelcomeService>.value(value: welcome),
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
          BlocProvider(
            create: (_) => AuthBloc(
              db,
              restored: restoredUser,
              restoredActiveAt: restoredActiveAt,
            ),
          ),
          // Above MaterialApp so the login screen follows the theme too.
          BlocProvider(
            create: (_) => ThemeCubit(settings, initial: initialTheme),
          ),
          // Likewise above MaterialApp: the Appearance screen previews a theme
          // by repainting the whole app, which only works if the brand lives
          // above the thing being repainted.
          BlocProvider(
            create: (_) => BrandingCubit(settings, initial: initialBranding),
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
        child: AutomaticReminders(
          child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) =>
              BlocBuilder<BrandingCubit, BrandingState>(
            // The draft, not the saved config: previewing a theme has to show
            // the owner their real screens in the new brand before they commit
            // to it.
            builder: (context, brandingState) =>
                BlocBuilder<AuthBloc, AuthState>(
              buildWhen: (a, b) => a.user?.id != b.user?.id,
              // Keyed on who is signed in, so every sign-in and sign-out builds
              // a new Navigator. Swapping `home` alone leaves pushed screens and
              // open dialogs standing on top of it: a member's details would
              // stay up over the login form after the inactivity lock, and
              // Back would return to them.
              builder: (context, auth) => MaterialApp(
              key: ValueKey(auth.user?.id),
              title: 'Rich Man Fitness',
              debugShowCheckedModeBanner: false,
              theme: buildLightThemeFor(brandingState.draft),
              darkTheme: buildDarkThemeFor(brandingState.draft),
              themeMode: themeMode,
              builder: (context, child) => IdleLock(child: child!),
              home: BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  if (state.mustChangePassword) {
                    return const FirstRunPasswordScreen();
                  }
                  return state.isSignedIn
                      ? const AppShell()
                      : const LoginScreen();
                },
              ),
            ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

