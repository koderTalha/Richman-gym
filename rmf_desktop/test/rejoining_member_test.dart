import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';

/// The scenario the gym owner actually described: a member joins in January,
/// stops coming in February without paying, and returns in June.
void main() {
  late AppDatabase db;
  late BillingMaintenance maintenance;
  late MemberRepository members;
  late PaymentRepository payments;
  late int memberId;
  late int adminId;
  late int planId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    maintenance = BillingMaintenance(db);
    members = MemberRepository(db);
    payments = PaymentRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    memberId = await members.create(
      fullName: 'Rejoining Member',
      phone: '+923000000026',
      planId: planId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    // January: joined and paid.
    final membership = await (db.select(db.memberships)
          ..where((m) => m.memberId.equals(memberId)))
        .getSingle();
    final januaryId = await db.into(db.membershipPeriods).insert(
        MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: DateTime.utc(2026, 1, 1),
            periodEnd: DateTime.utc(2026, 2, 1),
            expectedAmountMinor: 300000));
    await db.into(db.payments).insert(PaymentsCompanion.insert(
        memberId: memberId,
        membershipPeriodId: Value(januaryId),
        amountMinor: 300000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, 1, 5),
        recordedById: adminId,
        idempotencyKey: 'january'));
  });

  tearDown(() => db.close());

  Future<int> cycleCount() async =>
      (await db.select(db.membershipPeriods).get()).length;

  Future<MemberStatus> statusOn(DateTime when) async {
    await maintenance.ensureCurrentPeriods(now: when);
    final row = await members.byId(memberId, now: when);
    return row!.status;
  }

  test('in February, unpaid, the member reads DUE', () async {
    expect(await statusOn(DateTime.utc(2026, 2, 10)), MemberStatus.due);
  });

  test('once marked as left, no further months are billed', () async {
    // The owner deactivates them when they stop coming.
    await members.setActive(memberId, false);

    final before = await cycleCount();
    for (final month in [3, 4, 5]) {
      await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, month, 10));
    }

    expect(await cycleCount(), before,
        reason: 'a member who left must not accrue debt');
  });

  test('while away they read INACTIVE, not DUE', () async {
    await members.setActive(memberId, false);
    await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, 4, 10));

    final row = await members.byId(memberId, now: DateTime.utc(2026, 4, 10));
    expect(row!.status, MemberStatus.inactive);
  });

  test('they do not appear in the payments-due list while away', () async {
    await members.setActive(memberId, false);
    await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, 4, 10));

    final due = await members.list(
        filter: MemberFilter.due, now: DateTime.utc(2026, 4, 10));
    expect(due, isEmpty);
  });

  test('rejoining in June bills June only, with no back-debt', () async {
    await members.setActive(memberId, false);
    for (final month in [3, 4, 5]) {
      await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, month, 10));
    }

    // June: the member comes back and the owner reactivates them.
    await members.setActive(memberId, true);
    await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, 6, 10));

    final cycles = await (db.select(db.membershipPeriods)
          ..orderBy([(p) => OrderingTerm(expression: p.periodStart)]))
        .get();

    expect(cycles.length, 2, reason: 'January and June, nothing in between');
    expect(cycles.first.periodStart.toUtc(), DateTime.utc(2026, 1, 1));
    expect(cycles.last.periodStart.toUtc(), DateTime.utc(2026, 6, 1));
  });

  test('after rejoining they read DUE for the current month', () async {
    await members.setActive(memberId, false);
    await members.setActive(memberId, true);

    expect(await statusOn(DateTime.utc(2026, 6, 10)), MemberStatus.due);
  });

  test('their January payment history survives the whole round trip',
      () async {
    await members.setActive(memberId, false);
    await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, 4, 10));
    await members.setActive(memberId, true);
    await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, 6, 10));

    final history = await payments.history(memberId: memberId);
    expect(history.length, 1);
    expect(history.single.periodLabel, 'January 2026');
    expect(history.single.payment.amountMinor, 300000);
  });

  test('a member left active while away does accrue the missed month',
      () async {
    // Not deactivated: the gym still considers them a member, so February is
    // genuinely owed. Only one cycle is opened, not one per month missed.
    await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, 6, 10));

    final cycles = await db.select(db.membershipPeriods).get();
    expect(cycles.length, 2, reason: 'January plus the current month');
  });
}
