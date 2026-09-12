import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/bloc/theme_cubit.dart';
import 'package:rich_man_fitness/bloc/update_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/app_version.dart';
import 'package:rich_man_fitness/services/update/update_service.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/app_shell.dart';

/// The Reload button in the top bar.
///
/// It exists because a member added at the counter has no billing cycle until
/// the app next opens — which used to mean quitting and reopening it to see
/// them read DUE. Pressing Reload does the same work opening the app does,
/// then rebuilds whatever screen is showing.
///
/// Deliberately named apart from the per-screen Refresh buttons the Dashboard,
/// Logs and Reminders already carry: those re-read what is on screen, this one
/// re-runs the app's opening work first.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
  });

  tearDown(() async => db.close());

  Future<void> pumpShell(WidgetTester tester) async {
    final admin = await db.select(db.users).getSingle();
    final audit = AuditRepository(db);

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<MemberRepository>(create: (_) => MemberRepository(db)),
        RepositoryProvider<PaymentRepository>(
            create: (_) => PaymentRepository(db)),
        RepositoryProvider<ReceiptRepository>(
            create: (_) => ReceiptRepository(db)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
              create: (_) => AuthBloc(db, restored: admin)),
          BlocProvider<ThemeCubit>(
              create: (_) => ThemeCubit(SettingsRepository(db))),
          BlocProvider<UpdateBloc>(
            create: (_) => UpdateBloc(UpdateService(
              db: db,
              currentVersion: AppVersion.unknown,
              audit: audit,
            )),
          ),
        ],
        child: MaterialApp(theme: buildDarkTheme(), home: const AppShell()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder themeToggle() => find.byWidgetPredicate((widget) =>
      widget is Icon &&
      (widget.icon == Icons.light_mode_outlined ||
          widget.icon == Icons.dark_mode_outlined));

  // By key, not by icon: the Dashboard, Logs and Reminders screens each carry
  // their own refresh icon, so an icon finder matches whichever screen is up.
  Finder reload() => find.byKey(appShellReloadKey);

  testWidgets('sits in the top bar, immediately left of the theme toggle',
      (tester) async {
    await pumpShell(tester);

    expect(reload(), findsOneWidget);
    expect(
      tester.getCenter(reload()).dx,
      lessThan(tester.getCenter(themeToggle()).dx),
      reason: 'it leads into the bulb rather than following it',
    );
  });

  testWidgets('pressing it opens the billing cycle a member is owed',
      (tester) async {
    await MemberRepository(db).create(
      fullName: 'Added At The Counter',
      phone: '+923000000001',
      planId: (await (db.select(db.membershipPlans)
                ..where((p) => p.name.equals('Monthly')))
              .getSingle())
          .id,
      joiningDate: DateTime.now().toUtc(),
    );

    await pumpShell(tester);
    expect(await db.select(db.membershipPeriods).get(), isEmpty,
        reason: 'nothing has opened their cycle yet');

    await tester.tap(reload());
    await tester.pumpAndSettle();

    expect(await db.select(db.membershipPeriods).get(), hasLength(1),
        reason: 'Reload does the work opening the app does, not a repaint');
  });

  testWidgets('it says what it does', (tester) async {
    await pumpShell(tester);

    expect(tester.widget<IconButton>(reload()).tooltip, 'Reload');
  });
}
