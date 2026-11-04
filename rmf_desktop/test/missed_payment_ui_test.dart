import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/payment_inactivity.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/payment_inactivity_service.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/deactivating_soon_panel.dart';
import 'package:rich_man_fitness/ui/members/member_detail_screen.dart';
import 'package:rich_man_fitness/ui/members/missed_payment_panel.dart';
import 'package:rich_man_fitness/ui/payments/advance_payment_dialog.dart';
import 'package:rich_man_fitness/ui/settings/missed_payment_card.dart';

/// The screens around missed-payment deactivation, driven as the owner would.
///
/// The service reads the real clock, so every member here is built relative
/// to today on the gym's calendar rather than on fixed dates.
void main() {
  late AppDatabase db;
  late AuditRepository audit;
  late MemberRepository members;
  late BillingCycleService cycles;
  late PaymentInactivityService inactivity;
  late int monthlyId;
  var phones = 0;

  const fee = 250000;
  final today = gymDateOf(DateTime.now());
  DateTime daysAgo(int n) => today.subtract(Duration(days: n));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    audit = AuditRepository(db);
    members = MemberRepository(db, audit: audit);
    cycles = BillingCycleService(db, audit: audit);
    inactivity = PaymentInactivityService(db, cycles: cycles, audit: audit);
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  Future<void> cycle(int memberId, DateTime start, DateTime end,
      {bool paid = false}) async {
    final membership = (await openMembershipFor(db, memberId))!;
    final period = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: start,
            periodEnd: end,
            expectedAmountMinor: fee,
          ),
        );
    if (!paid) return;
    final userId = (await db.select(db.users).getSingle()).id;
    final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            membershipPeriodId: Value(period.id),
            amountMinor: fee,
            method: PaymentMethod.cash,
            paymentDate: start,
            recordedById: userId,
            idempotencyKey: 'k$memberId-${start.millisecondsSinceEpoch}',
          ),
        );
    await db.into(db.paymentAllocations).insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            membershipPeriodId: period.id,
            amountMinor: fee,
          ),
        );
    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(period.id)))
        .write(MembershipPeriodsCompanion(settledAt: Value(start)));
  }

  /// Paid the month before, then nothing since the bill due [missedDaysAgo]
  /// days ago; the current month is open.
  Future<int> behindBy(String name, int missedDaysAgo) async {
    final id = await members.create(
      fullName: name,
      phone: '+92300000${2000 + phones++}',
      planId: monthlyId,
      feeOverrideMinor: fee,
      joiningDate: daysAgo(missedDaysAgo + 30),
    );
    final due = daysAgo(missedDaysAgo);
    await cycle(id, due.subtract(const Duration(days: 30)), due, paid: true);
    await cycle(id, due, due.add(const Duration(days: 30)));
    await cycle(id, due.add(const Duration(days: 30)),
        due.add(const Duration(days: 60)));
    return id;
  }

  Future<Member> reload(int id) =>
      (db.select(db.members)..where((m) => m.id.equals(id))).getSingle();

  Future<void> pump(WidgetTester tester, Widget home,
      {Size size = const Size(1600, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final user = await db.select(db.users).getSingle();

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<AuditRepository>.value(value: audit),
        RepositoryProvider<MemberRepository>.value(value: members),
        RepositoryProvider<PaymentRepository>(
            create: (_) => PaymentRepository(db)),
        RepositoryProvider<BillingCycleService>.value(value: cycles),
        RepositoryProvider<PaymentInactivityService>.value(value: inactivity),
      ],
      child: BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(db, restored: user),
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: Scaffold(body: home),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Widget card({required String title, String? subtitle, required Widget child}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Text(title), child],
      );

  group('Settings', () {
    testWidgets('switching on shows who first, and does nothing on Cancel',
        (tester) async {
      final id = await behindBy('Lapsed Member', 45);
      await pump(tester,
          SingleChildScrollView(child: MissedPaymentCard(card: card)));

      expect(find.textContaining('would deactivate 1 member'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('#${(await reload(id)).memberCode} Lapsed Member'),
          findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await inactivity.isEnabled(), isFalse);
      expect((await reload(id)).deactivatedAt, isNull);
    });

    testWidgets('confirming switches on and deactivates them', (tester) async {
      final id = await behindBy('Lapsed Member', 45);
      await pump(tester,
          SingleChildScrollView(child: MissedPaymentCard(card: card)));

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch on and deactivate 1 member'));
      await tester.pumpAndSettle();

      expect(await inactivity.isEnabled(), isTrue);
      expect((await reload(id)).deactivatedAt, isNotNull);
      expect(find.textContaining('1 member deactivated'), findsOneWidget);
    });

    testWidgets('lists who is deactivating this week once switched on',
        (tester) async {
      await inactivity.setEnabled(true);
      await behindBy('Almost Lapsed', 36);
      await pump(tester,
          SingleChildScrollView(child: MissedPaymentCard(card: card)));

      expect(find.textContaining('Deactivating in the next 7 days'),
          findsOneWidget);
      expect(find.textContaining('Almost Lapsed'), findsOneWidget);
    });

    testWidgets('fits a phone-width window', (tester) async {
      await behindBy('Lapsed Member', 45);
      await pump(
          tester, SingleChildScrollView(child: MissedPaymentCard(card: card)),
          size: const Size(360, 800));
      expect(tester.takeException(), isNull);
    });
  });

  group('Member screen', () {
    testWidgets('shows why they are inactive, and "kept coming" restores them',
        (tester) async {
      final id = await behindBy('Kept Coming', 45);
      await inactivity.run(force: true);

      await pump(tester, MemberDetailScreen(memberId: id));
      expect(find.text('Inactive — missed payments'), findsOneWidget);
      expect(find.text('Rs. 5,000'), findsWidgets, reason: 'written off');

      // The panel's own Reactivate, not the header's.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reactivate'));
      await tester.pumpAndSettle();
      expect(find.text('Was Kept Coming still coming?'), findsOneWidget);

      await tester.tap(find.textContaining('Yes, kept coming'));
      await tester.pumpAndSettle();

      expect((await reload(id)).deactivatedAt, isNull);
      expect(find.text('Inactive — missed payments'), findsNothing);
      expect(find.textContaining('reinstated'), findsOneWidget);
    });

    testWidgets('cancelling the question changes nothing', (tester) async {
      final id = await behindBy('Undecided', 45);
      await inactivity.run(force: true);

      await pump(tester, MemberDetailScreen(memberId: id));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reactivate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect((await reload(id)).deactivatedAt, isNotNull);
      expect(find.text('Inactive — missed payments'), findsOneWidget);
    });

    testWidgets('the panel fits a phone-width window', (tester) async {
      final id = await behindBy('Narrow', 45);
      await inactivity.run(force: true);
      final member = await reload(id);

      await pump(
        tester,
        SingleChildScrollView(
          child: MissedPaymentPanel(member: member, onReactivate: () {}),
        ),
        size: const Size(360, 800),
      );
      expect(find.text('Inactive — missed payments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Record payment', () {
    testWidgets('asks first, and takes no money when cancelled',
        (tester) async {
      final id = await behindBy('Pays Late', 45);
      await inactivity.run(force: true);
      final row = (await members.byId(id))!;

      bool? result = false;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showAdvancePaymentDialog(context, member: row),
            child: const Text('Record'),
          ),
        ),
      );
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      expect(find.text('Was Pays Late still coming?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(await db.select(db.payments).get(), hasLength(1),
          reason: 'only the month paid before');
      expect((await reload(id)).deactivatedAt, isNotNull);
    });
  });

  group('Dashboard', () {
    testWidgets('names who is deactivating this week', (tester) async {
      await inactivity.setEnabled(true);
      await behindBy('Almost Lapsed', 36);
      await behindBy('Not Yet', 20);

      await pump(tester, const DeactivatingSoonPanel(refreshKey: 1));
      expect(find.text('Deactivating this week unless they pay'),
          findsOneWidget);
      expect(find.textContaining('Almost Lapsed'), findsOneWidget);
      expect(find.textContaining('Not Yet'), findsNothing);
    });

    testWidgets('shows nothing while the rule is off', (tester) async {
      await behindBy('Almost Lapsed', 36);
      await pump(tester, const DeactivatingSoonPanel(refreshKey: 1));
      expect(find.text('Deactivating this week unless they pay'),
          findsNothing);
    });
  });
}
