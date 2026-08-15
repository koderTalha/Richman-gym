import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/dashboard_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/billing_period.dart';

/// Which day and month a payment counts towards.
///
/// A payment is a moment in time; a billing cycle is a calendar month the app
/// deliberately anchors to UTC. Mixing the two — building "today" and "this
/// month" as UTC instants out of the *local* clock's calendar fields — shifted
/// every window by the machine's timezone offset. In Pakistan that put a
/// payment the owner dated the 1st into the month before, because the date
/// picker hands back local midnight and local midnight on the 1st is 7pm on
/// the 31st in UTC.
void main() {
  late AppDatabase db;
  late int memberId;
  late int adminId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;

    final planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    memberId = await MemberRepository(db).create(
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: planId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() async => db.close());

  /// Records a payment the way the Record Payment form does: the date comes
  /// out of a date picker, which returns local midnight.
  Future<void> pay({required DateTime on, int amountMinor = 300000}) =>
      db.into(db.payments).insert(PaymentsCompanion.insert(
            memberId: memberId,
            amountMinor: amountMinor,
            method: PaymentMethod.cash,
            paymentDate: on,
            recordedById: adminId,
            idempotencyKey: 'pay-${on.toIso8601String()}',
          ));

  Future<DashboardState> dashboardOn(DateTime now) async {
    final bloc = DashboardBloc(
      memberRepository: MemberRepository(db),
      paymentRepository: PaymentRepository(db),
      receiptRepository: ReceiptRepository(db),
      clock: () => now,
    );
    addTearDown(bloc.close);

    bloc.add(const DashboardRequested());
    return bloc.stream
        .firstWhere((s) => s.status != DashboardStatus.loading);
  }

  test('a payment dated the 1st counts towards that month', () async {
    await pay(on: DateTime(2026, 9, 1)); // local midnight, from the picker

    final state = await dashboardOn(DateTime(2026, 9, 15, 11));

    expect(state.revenueMonthMinor, 300000,
        reason: 'it was taken in September and belongs in September');
  });

  test('and not towards the month before', () async {
    await pay(on: DateTime(2026, 9, 1));

    final august = await dashboardOn(DateTime(2026, 8, 20, 11));
    expect(august.revenueMonthMinor, 0);
  });

  test('a payment dated today counts towards today', () async {
    await pay(on: DateTime(2026, 9, 10));

    final state = await dashboardOn(DateTime(2026, 9, 10, 18));

    expect(state.revenueTodayMinor, 300000);
    expect(state.paymentsToday, 1);
  });

  test('yesterday\'s payment is not in today\'s total', () async {
    await pay(on: DateTime(2026, 9, 9));

    final state = await dashboardOn(DateTime(2026, 9, 10, 18));

    expect(state.revenueTodayMinor, 0);
    expect(state.paymentsToday, 0);
  });

  test('a payment on the last day of the month stays in that month', () async {
    await pay(on: DateTime(2026, 9, 30, 22, 30));

    expect((await dashboardOn(DateTime(2026, 9, 30, 23))).revenueMonthMinor,
        300000);
    expect((await dashboardOn(DateTime(2026, 10, 1, 9))).revenueMonthMinor, 0);
  });

  test('the month total spans the whole month', () async {
    await pay(on: DateTime(2026, 9, 1), amountMinor: 100000);
    await pay(on: DateTime(2026, 9, 15), amountMinor: 200000);
    await pay(on: DateTime(2026, 9, 30), amountMinor: 300000);

    expect((await dashboardOn(DateTime(2026, 9, 20))).revenueMonthMinor,
        600000);
  });

  group('the billing month the form defaults to', () {
    test('is the month it currently is where the gym is', () {
      // Read as UTC first, the small hours of the 1st fell into the month
      // before — the form opened offering to bill a month already settled.
      expect(currentBillingMonth(DateTime(2026, 9, 1, 0, 30)), '2026-09');
    });

    test('is stable through the day', () {
      expect(currentBillingMonth(DateTime(2026, 9, 15, 23, 59)), '2026-09');
      expect(currentBillingMonth(DateTime(2026, 12, 31, 23, 0)), '2026-12');
    });
  });
}
