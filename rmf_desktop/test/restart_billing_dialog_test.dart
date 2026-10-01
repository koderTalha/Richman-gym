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
import 'package:rich_man_fitness/domain/billing_cycle.dart';
import 'package:rich_man_fitness/domain/dates.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/members/restart_billing_action.dart';

/// The dialog the owner uses to straighten out a member whose return was
/// recorded before restarts existed, and the one reactivation opens.
///
/// Dates are built around today, because the dialog suggests the day of the
/// latest payment only when it was recent.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int memberId;
  late DateTime paidOn;
  late int unpaidId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    final admin = await db.select(db.users).getSingle();
    final monthly = await (db.select(db.membershipPlans)
          ..where((p) => p.name.equals('Monthly')))
        .getSingle();

    final now = DateTime.now();
    paidOn = DateTime.utc(now.year, now.month, now.day)
        .subtract(const Duration(days: 3));
    memberId = await members.create(
      fullName: 'Test Returner',
      phone: '+923000000039',
      planId: monthly.id,
      joiningDate: paidOn.subtract(const Duration(days: 200)),
    );
    final membership = (await openMembershipFor(db, memberId))!;

    // The payment the owner took when he came back, on a cycle that started
    // weeks before it, followed by an unpaid one from the old cadence.
    final paidCycle = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: paidOn.subtract(const Duration(days: 20)),
            periodEnd: paidOn.add(const Duration(days: 10)),
            expectedAmountMinor: monthly.priceMinor,
            settledAt: Value(paidOn),
          ),
        );
    final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            membershipPeriodId: Value(paidCycle.id),
            amountMinor: monthly.priceMinor,
            method: PaymentMethod.jazzcash,
            paymentDate: DateTime(paidOn.year, paidOn.month, paidOn.day, 18),
            recordedById: admin.id,
            idempotencyKey: 'return',
          ),
        );
    await db.into(db.paymentAllocations).insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            membershipPeriodId: paidCycle.id,
            amountMinor: monthly.priceMinor,
          ),
        );
    unpaidId = (await db.into(db.membershipPeriods).insertReturning(
              MembershipPeriodsCompanion.insert(
                membershipId: membership.id,
                periodStart: paidOn.add(const Duration(days: 10)),
                periodEnd: paidOn.add(const Duration(days: 40)),
                expectedAmountMinor: monthly.priceMinor,
              ),
            ))
        .id;
  });

  tearDown(() async => db.close());

  /// What the dialog returns once it closes. Held here rather than returned
  /// from [open], which would make awaiting [open] wait for the dialog itself.
  late Future<RestartChoice?> dialogResult;

  Future<void> open(WidgetTester tester, {required bool reactivate}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final admin = await db.select(db.users).getSingle();
    final row = (await members.byId(memberId))!;

    await tester.pumpWidget(RepositoryProvider<BillingCycleService>(
      create: (_) => BillingCycleService(db),
      child: BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(db, restored: admin),
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => dialogResult = showRestartBillingDialog(
                      context,
                      member: row,
                      reactivate: reactivate),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('suggests the day he paid, and shows what will change',
      (tester) async {
    await open(tester, reactivate: false);

    final end = addMonthsClamped(paidOn, 1, anchorDay: paidOn.day);
    expect(find.text(formatDayMonthYear(paidOn)), findsOneWidget,
        reason: 'the latest payment was three days ago');
    expect(
        find.textContaining('The payment already taken covers '
            '${formatDayMonthYear(paidOn)} to ${formatDayMonthYear(end)}'),
        findsOneWidget);
    expect(find.textContaining('No longer owed'), findsOneWidget);
    expect(find.textContaining('Billing day becomes ${paidOn.day}'),
        findsOneWidget);
  });

  testWidgets('Restart billing applies it', (tester) async {
    await open(tester, reactivate: false);

    await tester.tap(find.widgetWithText(FilledButton, 'Restart billing'));
    await tester.pumpAndSettle();

    expect((await dialogResult)?.from, paidOn);
    final periods = await periodsForMember(db, memberId);
    expect(periods.map((p) => p.id), isNot(contains(unpaidId)));
    expect(periods.single.periodStart.toUtc(), paidOn);
  });

  testWidgets('reactivating hands back the day without writing anything',
      (tester) async {
    await open(tester, reactivate: true);

    final now = DateTime.now();
    expect(find.text('Reactivate Test Returner'), findsOneWidget);
    expect(find.text(formatDayMonthYear(DateTime(now.year, now.month, now.day))),
        findsOneWidget,
        reason: 'reactivation defaults to today, the day they walked in');

    // Today is inside the cycle he already paid, so the restart is refused
    // and the owner is offered a plain reactivation instead of a dead end.
    expect(find.text('Reactivate only'), findsOneWidget);
    await tester.tap(find.text('Reactivate only'));
    await tester.pumpAndSettle();

    final picked = await dialogResult;
    expect(picked, isNotNull);
    expect(picked!.from, isNull);
    expect(await periodsForMember(db, memberId), hasLength(2),
        reason: 'the bloc applies a reactivation, not the dialog');
  });
}
