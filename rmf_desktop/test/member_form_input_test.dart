import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/whatsapp/member_welcome_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/members/member_form_screen.dart';

/// The Edit Member screen's own fields, as the owner types into them: the
/// custom fee (BUG-010's member-form part and BUG-029's "NaN") and the phone
/// of a member who has none (BUG-027), from the 1 Oct 2026 audit.
void main() {
  late AppDatabase db;
  late int monthlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  Future<void> pumpForm(WidgetTester tester, int memberId) async {
    // A desktop window: the form lays its fields out in rows.
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final admin = await db.select(db.users).getSingle();

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<MemberRepository>(
            create: (_) => MemberRepository(db)),
        RepositoryProvider<MemberWelcomeService>(
            create: (_) => MemberWelcomeService(
                  db: db,
                  clientFactory: () async => MockWhatsAppClient(),
                )),
      ],
      child: BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(db, restored: admin),
        child: MaterialApp(
          theme: buildDarkTheme(),
          // Pushed rather than made the home route, so a save has somewhere
          // to pop back to, as it does in the app.
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MemberFormScreen(memberId: memberId))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder feeField() =>
      find.widgetWithText(TextFormField, 'Custom fee (optional)');

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
  }

  Future<int> join({String phone = '+923000000001', int? feeOverrideMinor}) =>
      MemberRepository(db).create(
        fullName: 'Ali Khan',
        phone: phone,
        planId: monthlyId,
        feeOverrideMinor: feeOverrideMinor,
        joiningDate: DateTime.utc(2026, 1, 6),
      );

  Future<int?> feeOverride(int id) async =>
      (await openMembershipFor(db, id))!.feeOverrideMinor;

  Future<List<AuditEvent>> feeEvents() => (db.select(db.auditEvents)
        ..where((e) => e.action.equals(AuditAction.memberFeeChanged)))
      .get();

  testWidgets('a fee with paisa is prefilled exactly, and survives a save',
      (tester) async {
    final id = await join(feeOverrideMinor: 150050);
    await pumpForm(tester, id);

    expect(tester.widget<TextFormField>(feeField()).controller!.text,
        '1500.50');

    await save(tester);

    expect(find.text('Save Changes'), findsNothing, reason: 'it saved');
    expect(await feeOverride(id), 150050,
        reason: 'rounded to 1501 it would re-price the member for a change '
            'nobody made');
    expect(await feeEvents(), isEmpty);
  });

  testWidgets('"NaN" is refused with a message, not a silent failure',
      (tester) async {
    final id = await join();
    await pumpForm(tester, id);

    await tester.enterText(feeField(), 'NaN');
    await save(tester);

    expect(find.text('Enter an amount such as 1500 or 1,500.50'),
        findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget,
        reason: 'the form is still open');
    expect(await feeOverride(id), isNull);
  });

  testWidgets('a fee written with a comma is read as the owner meant',
      (tester) async {
    final id = await join();
    await pumpForm(tester, id);

    await tester.enterText(feeField(), '1,800');
    await save(tester);

    expect(await feeOverride(id), 180000);
  });

  testWidgets('more decimals than paisa are refused, not rounded',
      (tester) async {
    final id = await join();
    await pumpForm(tester, id);

    await tester.enterText(feeField(), '1500.555');
    await save(tester);

    expect(find.text('Enter an amount such as 1500 or 1,500.50'),
        findsOneWidget);
    expect(await feeOverride(id), isNull);
  });

  testWidgets('a member with no phone on file can be saved as they are',
      (tester) async {
    final id = await join(phone: '');
    await pumpForm(tester, id);

    expect(find.textContaining('No valid number on file'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Address'), 'Street 2');
    await save(tester);

    expect(find.text('Save Changes'), findsNothing, reason: 'it saved');
    final m = await (db.select(db.members)..where((m) => m.id.equals(id)))
        .getSingle();
    expect(m.phone, '');
    expect(m.address, 'Street 2');
  });

  testWidgets('a member with a phone still has to keep a valid one',
      (tester) async {
    final id = await join();
    await pumpForm(tester, id);

    await tester.enterText(find.widgetWithText(TextFormField, 'Phone *'), '');
    await save(tester);

    expect(find.text('Enter a valid phone number'), findsOneWidget);
  });
}
