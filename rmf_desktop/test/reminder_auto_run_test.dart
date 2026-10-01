import 'package:drift/drift.dart' hide isNull;
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
import 'package:rich_man_fitness/services/reminder_service.dart';
import 'package:rich_man_fitness/services/update/update_service.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/app_shell.dart';

class _Client implements WhatsAppClient {
  final sent = <WhatsAppTemplateInput>[];

  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.mock;

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async =>
      const WhatsAppSendFailure('not used');

  @override
  Future<WhatsAppSendResult> sendText(WhatsAppTextInput input) async =>
      const WhatsAppSendFailure('not used');

  @override
  Future<WhatsAppSendResult> sendTemplate(WhatsAppTemplateInput input) async {
    sent.add(input);
    return WhatsAppSendSuccess('msg-${sent.length}');
  }
}

/// Automatic reminders while the app stays open.
///
/// They used to be attempted once per launch and never again: a launch
/// before sending hours sent nothing all day, and everything past the
/// per-run cap waited for the next launch. The shell now also runs them on
/// Reload and once an hour — each run still capped, hours-aware and
/// re-checked, so running more often cannot send anybody a second copy.
void main() {
  late AppDatabase db;
  late _Client client;
  late ReminderService reminders;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    client = _Client();
    reminders = ReminderService(db: db, clientFactory: () async => client);

    // Equal hours read as "any time", so the test does not depend on when it
    // happens to run.
    await (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
        const GymSettingsCompanion(
      whatsappReminderTemplate: Value('payment_reminder'),
      reminderAutoSend: Value(true),
      reminderSendFromHour: Value(0),
      reminderSendUntilHour: Value(0),
    ));

    // Falls due today, so the on-the-day reminder is owed.
    await MemberRepository(db).create(
      fullName: 'Added At The Counter',
      phone: '+923000000001',
      planId: (await (db.select(db.membershipPlans)
                ..where((p) => p.name.equals('Monthly')))
              .getSingle())
          .id,
      joiningDate: DateTime.now().toUtc(),
    );
  });

  tearDown(() async => db.close());

  Future<void> pumpShell(WidgetTester tester) async {
    final admin = await db.select(db.users).getSingle();
    final audit = AuditRepository(db);

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<SettingsRepository>.value(
            value: SettingsRepository(db)),
        RepositoryProvider<ReminderService>.value(value: reminders),
        RepositoryProvider<MemberRepository>(
            create: (_) => MemberRepository(db)),
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

  testWidgets('showing the shell alone sends nothing: launch does that',
      (tester) async {
    await pumpShell(tester);
    expect(client.sent, isEmpty);
  });

  testWidgets('Reload runs the automatic reminders after the billing roll',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(appShellReloadKey));
    await tester.pumpAndSettle();

    expect(client.sent, hasLength(1));

    // A second Reload finds the reminder already sent.
    await tester.tap(find.byKey(appShellReloadKey));
    await tester.pumpAndSettle();
    expect(client.sent, hasLength(1));
  });

  testWidgets('they run again every hour while the app is open',
      (tester) async {
    await pumpShell(tester);
    // The billing roll the launch would have done.
    await tester.tap(find.byKey(appShellReloadKey));
    await tester.pumpAndSettle();
    client.sent.clear();
    await (db.delete(db.paymentReminders)).go();

    await tester.pump(reminderRunInterval);
    await tester.pumpAndSettle();

    expect(client.sent, hasLength(1));
  });

  testWidgets('nothing is sent with automatic reminders switched off',
      (tester) async {
    await (db.update(db.gymSettings)..where((s) => s.id.equals(1)))
        .write(const GymSettingsCompanion(reminderAutoSend: Value(false)));
    await pumpShell(tester);

    await tester.tap(find.byKey(appShellReloadKey));
    await tester.pumpAndSettle();
    await tester.pump(reminderRunInterval);
    await tester.pumpAndSettle();

    expect(client.sent, isEmpty);
  });
}
