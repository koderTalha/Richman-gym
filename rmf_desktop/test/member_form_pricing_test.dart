import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/whatsapp/member_welcome_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/members/member_form_screen.dart';
import 'package:rich_man_fitness/ui/members/pricing_summary.dart';

/// The pricing summary as the owner actually meets it, on the real Edit Member
/// screen rather than in isolation.
///
/// `PricingSummary` is tested on its own elsewhere; what these guard is the
/// wiring — that it is on the screen at all, that it is handed the member's
/// real fee rather than a default, and that it follows the fee field as it is
/// typed. A summary fed the wrong number is worse than no summary, because the
/// owner would believe it.
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
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(150000)));
  });

  tearDown(() async => db.close());

  Future<void> pumpForm(WidgetTester tester, {int? memberId}) async {
    // A desktop window, not the 800x600 the test binding defaults to: the
    // form lays its fields out in rows and the plan dropdown does not fit in
    // half a laptop screen. Nothing to do with pricing — it just has to be
    // given the room the real app runs in.
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<MemberRepository>(
            create: (_) => MemberRepository(db)),
        // Unused on the edit path, but the screen reads it to build its bloc.
        RepositoryProvider<MemberWelcomeService>(
            create: (_) => MemberWelcomeService(
                  db: db,
                  clientFactory: () async => MockWhatsAppClient(),
                )),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: MemberFormScreen(memberId: memberId),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String renderedText(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
        of: find.byType(PricingSummary),
        matching: find.byType(Text),
      ))
      .map((t) => t.data ?? '')
      .join(' ');

  Future<int> join({int? feeOverrideMinor}) => MemberRepository(db).create(
        fullName: 'Ali Khan',
        phone: '+923000000001',
        planId: monthlyId,
        feeOverrideMinor: feeOverrideMinor,
        joiningDate: DateTime.utc(2026, 1, 6),
      );

  testWidgets('a member on the plan price sees the plan price', (tester) async {
    await pumpForm(tester, memberId: await join());

    expect(find.byType(PricingSummary), findsOneWidget);
    expect(renderedText(tester), contains('Rs. 1,500'));
    expect(renderedText(tester), contains('Follows the plan price'));
  });

  testWidgets('a member on a custom fee sees the custom fee', (tester) async {
    await pumpForm(tester, memberId: await join(feeOverrideMinor: 180000));

    final text = renderedText(tester);
    expect(text, contains('Billed each cycle: Rs. 1,800'));
    expect(text, contains('Custom fee'),
        reason: 'which of the two numbers is winning has to be visible');
  });

  testWidgets('typing a new fee warns before anything is saved',
      (tester) async {
    await pumpForm(tester, memberId: await join());
    expect(renderedText(tester), isNot(contains('change')));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Custom fee (optional)'), '2000');
    await tester.pump();

    final text = renderedText(tester);
    expect(text, contains('Rs. 1,500'));
    expect(text, contains('Rs. 2,000'));
    expect(text.toLowerCase(), contains('this month'));
    expect(text.toLowerCase(), contains('already paid'));
  });

  testWidgets('clearing the fee warns they drop to the plan price',
      (tester) async {
    await pumpForm(tester, memberId: await join(feeOverrideMinor: 200000));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Custom fee (optional)'), '');
    await tester.pump();

    final text = renderedText(tester);
    expect(text, contains('Billed each cycle: Rs. 1,500'));
    expect(text, contains('Rs. 2,000'),
        reason: 'the fee they are leaving is half of what makes it readable');
  });

  testWidgets('a member being created is warned about nothing', (tester) async {
    await pumpForm(tester);

    expect(find.byType(PricingSummary), findsOneWidget);
    expect(renderedText(tester), isNot(contains('change')),
        reason: 'there is no open bill to move for somebody who does not '
            'exist yet');
  });
}
