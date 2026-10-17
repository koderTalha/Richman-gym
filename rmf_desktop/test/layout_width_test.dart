import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/bloc/branding_cubit.dart';
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
import 'package:rich_man_fitness/services/startup_maintenance.dart';
import 'package:rich_man_fitness/services/update/update_service.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:rich_man_fitness/ui/app_shell.dart';

import 'support/still_motion.dart';

/// The handoff's layout promise: nothing overflows at the smallest window the
/// owner uses (1024×700) or at full HD, on any redesigned screen. Flutter
/// reports an overflow as an error, so visiting each screen with real rows on
/// it is the whole test.
void main() {
  late AppDatabase db;
  late MemberRepository members;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
  });

  tearDown(() async => db.close());

  /// A member who joined two months ago and has paid nothing, with their
  /// cycles opened the way launching the app opens them.
  Future<int> addDueMember(String name, String phone) async {
    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.name.equals('Monthly')))
        .getSingle();
    final id = await members.create(
      fullName: name,
      phone: phone,
      planId: plan.id,
      joiningDate: DateTime.now().toUtc().subtract(const Duration(days: 60)),
    );
    await runStartupMaintenance(db);
    return id;
  }

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final admin = await db.select(db.users).getSingle();
    final audit = AuditRepository(db);

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<MemberRepository>.value(value: members),
        RepositoryProvider<PaymentRepository>(
            create: (_) => PaymentRepository(db)),
        RepositoryProvider<ReceiptRepository>(
            create: (_) => ReceiptRepository(db)),
        RepositoryProvider<SettingsRepository>(
            create: (_) => SettingsRepository(db, audit: audit)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
              create: (_) => AuthBloc(db, restored: admin)),
          BlocProvider<ThemeCubit>(
              create: (_) => ThemeCubit(SettingsRepository(db))),
          BlocProvider<BrandingCubit>(
            create: (_) => BrandingCubit(SettingsRepository(db),
                initial: const BrandingConfig()),
          ),
          BlocProvider<UpdateBloc>(
            create: (_) => UpdateBloc(UpdateService(
              db: db,
              currentVersion: AppVersion.unknown,
              audit: audit,
            )),
          ),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          builder: stillMotion,
          home: const AppShell(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(1024, 700), Size(1920, 1080)]) {
    final label = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('every redesigned screen fits at $label', (tester) async {
      // Long names and both kinds of row: overdue and paid up.
      await addDueMember('Test Member With A Long Name', '+923000000103');
      await addDueMember('Test Member (Night)', '+923000000104');
      await pumpShell(tester, size);

      for (final screen in [
        'Members',
        'Payments',
        // Reminders is left out: it is not one of the redesigned screens and
        // needs the reminder service, which this harness does not build.
        'Appearance',
        'Settings',
        'Dashboard',
      ]) {
        await tester.tap(find.text(screen).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$screen at $label');
      }

      // Each Settings tab lays out its own cards.
      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();
      for (final tab in ['Account', 'WhatsApp', 'Data', 'Gym details']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'Settings › $tab at $label');
      }
    });
  }
}
