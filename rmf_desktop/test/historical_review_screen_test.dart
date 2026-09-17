import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/settings/historical_review_screen.dart';

/// The screen a non-technical owner reads down the phone, or reads alone at
/// the counter, to decide the ten members the automatic re-pricing fix cannot
/// reach.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int basicId;
  late int studentId;

  const basicFee = 400000;
  const studentFee = 250000;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);

    basicId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                  name: 'Basic', durationMonths: 1, priceMinor: basicFee),
            ))
        .id;
    studentId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                  name: 'Student Package',
                  durationMonths: 1,
                  priceMinor: studentFee),
            ))
        .id;
  });

  tearDown(() async => db.close());

  Future<int> strandedMember({
    String fullName = 'Abdul Qadir',
    String phone = '+923254097482',
    int? toPlanId,
    int toFee = studentFee,
  }) async {
    final targetPlanId = toPlanId ?? studentId;
    final memberId = await members.create(
      fullName: fullName,
      phone: phone,
      planId: basicId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
    final membership = (await openMembershipFor(db, memberId))!;
    final adminId = (await db.select(db.users).getSingle()).id;

    final period = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: DateTime.utc(2026, 8, 1),
            periodEnd: DateTime.utc(2026, 9, 1),
            expectedAmountMinor: basicFee,
          ),
        );
    final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            membershipPeriodId: Value(period.id),
            amountMinor: toFee,
            method: PaymentMethod.cash,
            paymentDate: DateTime.utc(2026, 8, 5),
            recordedById: adminId,
            idempotencyKey: 'stranded-$memberId',
          ),
        );
    await db.into(db.paymentAllocations).insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            membershipPeriodId: period.id,
            amountMinor: toFee,
          ),
        );

    await members.update(
      id: memberId,
      fullName: fullName,
      phone: phone,
      planId: targetPlanId,
      joiningDate: DateTime.utc(2026, 1, 1),
      now: DateTime.utc(2026, 9, 3),
    );
    // September, correctly re-priced and open, so the member reads DUE for
    // September rather than EXPIRED — the shape the real gym data has.
    await db.into(db.membershipPeriods).insert(
          MembershipPeriodsCompanion.insert(
            membershipId:
                (await openMembershipFor(db, memberId))!.id,
            periodStart: DateTime.utc(2026, 9, 1),
            periodEnd: DateTime.utc(2026, 10, 1),
            expectedAmountMinor: toFee,
          ),
        );

    return memberId;
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final admin = await db.select(db.users).getSingle();

    await tester.pumpWidget(RepositoryProvider<AppDatabase>.value(
      value: db,
      child: BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(db, restored: admin),
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: const HistoricalReviewScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists a stranded cycle with the figures the owner needs',
      (tester) async {
    await strandedMember();
    await pump(tester);

    expect(find.textContaining('Abdul Qadir'), findsOneWidget);
    expect(find.textContaining('Rs. 4,000'), findsWidgets);
    expect(find.textContaining('Rs. 2,500'), findsWidgets);
    expect(find.textContaining('Rs. 1,500'), findsWidgets);
  });

  testWidgets('shows the empty state when nothing needs review',
      (tester) async {
    await pump(tester);

    expect(find.textContaining('Nothing needs review'), findsOneWidget);
  });

  testWidgets('Correct asks for a reason before doing anything',
      (tester) async {
    await strandedMember();
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Correct to Rs. 2,500'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Correct to Rs. 2,500?'), findsOneWidget);
  });

  testWidgets('confirming Correct removes the candidate and shows what happened',
      (tester) async {
    await strandedMember();
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Correct to Rs. 2,500'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Correct the bill'));
    await tester.pumpAndSettle();

    expect(find.textContaining('corrected to Rs. 2,500'), findsOneWidget);
    expect(find.textContaining('Nothing needs review'), findsOneWidget);
  });

  testWidgets('Keep asks for a reason and leaves the bill alone',
      (tester) async {
    await strandedMember();
    await pump(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Keep Rs. 4,000'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Keep it'));
    await tester.pumpAndSettle();

    expect(find.textContaining('kept at Rs. 4,000'), findsOneWidget);

    final period = await (db.select(db.membershipPeriods)
          ..where((p) => p.expectedAmountMinor.equals(basicFee)))
        .getSingle();
    expect(period.expectedAmountMinor, basicFee,
        reason: 'keeping the bill must change nothing');
  });

  testWidgets('a refused correction says so rather than doing nothing visible',
      (tester) async {
    await strandedMember();
    await pump(tester);

    // The month is settled behind the screen's back: a payment recorded in
    // another window, or the same cycle decided twice before a reload. The
    // owner is about to press a button that cannot work, and the one thing
    // the screen must not do is look like it did nothing.
    await (db.update(db.membershipPeriods)
          ..where((p) => p.expectedAmountMinor.equals(basicFee)))
        .write(MembershipPeriodsCompanion(
            settledAt: Value(DateTime.utc(2026, 9, 10))));

    await tester.tap(find.widgetWithText(FilledButton, 'Correct to Rs. 2,500'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Correct the bill'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already settled'), findsOneWidget);
  });

  testWidgets('cancelling the reason dialog leaves the candidate untouched',
      (tester) async {
    await strandedMember();
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Correct to Rs. 2,500'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Abdul Qadir'), findsOneWidget,
        reason: 'the candidate is still there — nothing was decided');
  });

  group('search', () {
    testWidgets('narrows the list to a matching name', (tester) async {
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await strandedMember(fullName: 'Bilal Ahmed', phone: '+923254097483');
      await pump(tester);

      expect(find.textContaining('Abdul Qadir'), findsOneWidget);
      expect(find.textContaining('Bilal Ahmed'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bilal');
      await tester.pumpAndSettle();

      expect(find.textContaining('Abdul Qadir'), findsNothing);
      expect(find.textContaining('Bilal Ahmed'), findsOneWidget);
    });

    testWidgets('matches on member code as well as name', (tester) async {
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await strandedMember(fullName: 'Bilal Ahmed', phone: '+923254097483');
      await pump(tester);

      final bilal = await (db.select(db.members)
            ..where((m) => m.fullName.equals('Bilal Ahmed')))
          .getSingle();

      await tester.enterText(
          find.byType(TextField), bilal.memberCode.toString());
      await tester.pumpAndSettle();

      expect(find.textContaining('Bilal Ahmed'), findsOneWidget);
      expect(find.textContaining('Abdul Qadir'), findsNothing);
    });

    testWidgets('is case-insensitive', (tester) async {
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'ABDUL');
      await tester.pumpAndSettle();

      expect(find.textContaining('Abdul Qadir'), findsOneWidget);
    });

    testWidgets('says plainly when nothing matches, without hiding the box',
        (tester) async {
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'nobody by this name');
      await tester.pumpAndSettle();

      expect(find.textContaining('No months match'), findsOneWidget);
      expect(find.textContaining('Abdul Qadir'), findsNothing);
      expect(find.byType(TextField), findsOneWidget,
          reason: 'clearing the search must still be reachable');
    });

    testWidgets('the clear button empties the box and restores the list',
        (tester) async {
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pumpAndSettle();
      expect(find.textContaining('Abdul Qadir'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.textContaining('Abdul Qadir'), findsOneWidget);
    });
  });

  group('plan filter', () {
    testWidgets('no chips are offered when every candidate is on one plan',
        (tester) async {
      await strandedMember();
      await pump(tester);

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('offers one chip per plan actually in the list, plus All',
        (tester) async {
      final matureId = (await db.into(db.membershipPlans).insertReturning(
                MembershipPlansCompanion.insert(
                    name: 'Mature', durationMonths: 1, priceMinor: 300000),
              ))
          .id;
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await strandedMember(
          fullName: 'Bilal Ahmed',
          phone: '+923254097483',
          toPlanId: matureId,
          toFee: 300000);
      await pump(tester);

      expect(find.widgetWithText(ChoiceChip, 'All plans'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Student Package'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Mature'), findsOneWidget);
    });

    testWidgets('selecting a plan chip narrows the list to that plan',
        (tester) async {
      final matureId = (await db.into(db.membershipPlans).insertReturning(
                MembershipPlansCompanion.insert(
                    name: 'Mature', durationMonths: 1, priceMinor: 300000),
              ))
          .id;
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await strandedMember(
          fullName: 'Bilal Ahmed',
          phone: '+923254097483',
          toPlanId: matureId,
          toFee: 300000);
      await pump(tester);

      await tester
          .tap(find.widgetWithText(ChoiceChip, 'Mature'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Bilal Ahmed'), findsOneWidget);
      expect(find.textContaining('Abdul Qadir'), findsNothing);
    });

    testWidgets('All plans clears the filter again', (tester) async {
      final matureId = (await db.into(db.membershipPlans).insertReturning(
                MembershipPlansCompanion.insert(
                    name: 'Mature', durationMonths: 1, priceMinor: 300000),
              ))
          .id;
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await strandedMember(
          fullName: 'Bilal Ahmed',
          phone: '+923254097483',
          toPlanId: matureId,
          toFee: 300000);
      await pump(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Mature'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'All plans'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Abdul Qadir'), findsOneWidget);
      expect(find.textContaining('Bilal Ahmed'), findsOneWidget);
    });

    testWidgets('search and the plan filter combine', (tester) async {
      final matureId = (await db.into(db.membershipPlans).insertReturning(
                MembershipPlansCompanion.insert(
                    name: 'Mature', durationMonths: 1, priceMinor: 300000),
              ))
          .id;
      await strandedMember(fullName: 'Abdul Qadir', phone: '+923254097482');
      await strandedMember(
          fullName: 'Bilal Qadir',
          phone: '+923254097483',
          toPlanId: matureId,
          toFee: 300000);
      await pump(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Mature'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Abdul');
      await tester.pumpAndSettle();

      // "Abdul" matches only the Student Package member; "Mature" is
      // selected, so the combination must match nobody.
      expect(find.textContaining('No months match'), findsOneWidget);
    });
  });
}
