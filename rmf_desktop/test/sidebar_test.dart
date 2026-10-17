import 'package:drift/drift.dart' show Value;
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

/// The sidebar's two live readings: how many members are due, beside
/// Reminders, and which WhatsApp provider messages are going out through.
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

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
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

  Finder badge() => find.byKey(const Key('reminders-due-badge'));

  String badgeText(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: badge(), matching: find.byType(Text)))
      .data!;

  testWidgets('no badge when nobody is due', (tester) async {
    await pumpShell(tester);
    expect(badge(), findsNothing,
        reason: 'a zero is not worth the owner\'s attention');
  });

  testWidgets('Reminders shows how many members are due', (tester) async {
    await addDueMember('Test Overdue', '+923000000101');
    await addDueMember('Test Payer', '+923000000102');
    await pumpShell(tester);

    expect(badge(), findsOneWidget);
    expect(badgeText(tester), '2');
  });

  testWidgets('the count follows the database without a Reload',
      (tester) async {
    final overdue = await addDueMember('Test Overdue', '+923000000101');
    await addDueMember('Test Payer', '+923000000102');
    await pumpShell(tester);
    expect(badgeText(tester), '2');

    // Deactivating takes a member off the due list; the badge must notice
    // without anybody pressing Reload.
    await tester.runAsync(() => members.setActive(overdue, false));
    await tester.pumpAndSettle();

    expect(badgeText(tester), '1');
  });

  testWidgets('mock mode is flagged, Meta is not', (tester) async {
    await (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
        const GymSettingsCompanion(
            whatsappProvider: Value(WhatsAppProviderKind.mock)));
    await pumpShell(tester);
    expect(find.text('WhatsApp in mock mode'), findsOneWidget);

    await tester.runAsync(() =>
        (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
            const GymSettingsCompanion(
                whatsappProvider: Value(WhatsAppProviderKind.meta))));
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp in mock mode'), findsNothing);
    expect(find.text('WhatsApp via Meta'), findsOneWidget,
        reason: 'switching provider in Settings shows here straight away');
  });

  testWidgets('Reports is marked as not here yet', (tester) async {
    await pumpShell(tester);
    expect(find.text('SOON'), findsOneWidget);
  });
}
