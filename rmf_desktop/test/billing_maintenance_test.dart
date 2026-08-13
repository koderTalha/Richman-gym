import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';

void main() {
  late AppDatabase db;
  late BillingMaintenance maintenance;
  late int monthlyPlanId;
  late int membershipId;

  final today = DateTime.utc(2026, 8, 15);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    maintenance = BillingMaintenance(db);

    final userId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));

    monthlyPlanId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: 300000));

    final memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Member One',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 1, 1),
        ));

    membershipId = await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
            memberId: memberId,
            planId: monthlyPlanId,
            startDate: DateTime.utc(2026, 1, 1)));

    // Silence the unused warning; the user exists so payments could be added.
    expect(userId, greaterThan(0));
  });

  tearDown(() => db.close());

  Future<List<MembershipPeriod>> periods() =>
      (db.select(db.membershipPeriods)
            ..orderBy([(p) => OrderingTerm(expression: p.periodStart)]))
          .get();

  test('creates the cycle covering today when none exists', () async {
    expect(await periods(), isEmpty);

    final created = await maintenance.ensureCurrentPeriods(now: today);

    expect(created, 1);
    final all = await periods();
    expect(all.single.periodStart.toUtc(), DateTime.utc(2026, 8, 1));
    expect(all.single.periodEnd.toUtc(), DateTime.utc(2026, 9, 1));
  });

  test('is idempotent — a second run creates nothing', () async {
    await maintenance.ensureCurrentPeriods(now: today);
    final created = await maintenance.ensureCurrentPeriods(now: today);

    expect(created, 0);
    expect((await periods()).length, 1);
  });

  test('leaves an existing covering cycle alone', () async {
    await db.into(db.membershipPeriods).insert(
        MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: DateTime.utc(2026, 8, 1),
            periodEnd: DateTime.utc(2026, 9, 1),
            expectedAmountMinor: 300000));

    expect(await maintenance.ensureCurrentPeriods(now: today), 0);
  });

  test('continues the cadence after a lapsed cycle', () async {
    await db.into(db.membershipPeriods).insert(
        MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: DateTime.utc(2026, 6, 1),
            periodEnd: DateTime.utc(2026, 7, 1),
            expectedAmountMinor: 300000));

    await maintenance.ensureCurrentPeriods(now: today);

    final all = await periods();
    expect(all.length, 2);
    expect(all.last.periodStart.toUtc(), DateTime.utc(2026, 8, 1));
  });

  test('does not back-fill every missed month', () async {
    await db.into(db.membershipPeriods).insert(
        MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: DateTime.utc(2026, 1, 1),
            periodEnd: DateTime.utc(2026, 2, 1),
            expectedAmountMinor: 300000));

    await maintenance.ensureCurrentPeriods(now: today);

    // One historical + one current, not seven months of invented debt.
    expect((await periods()).length, 2);
  });

  test('respects a quarterly plan length', () async {
    final quarterlyId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Quarterly', durationMonths: 3, priceMinor: 800000));
    await (db.update(db.memberships)..where((m) => m.id.equals(membershipId)))
        .write(MembershipsCompanion(planId: Value(quarterlyId)));

    await maintenance.ensureCurrentPeriods(now: today);

    final all = await periods();
    expect(all.single.periodStart.toUtc(), DateTime.utc(2026, 8, 1));
    expect(all.single.periodEnd.toUtc(), DateTime.utc(2026, 11, 1));
  });

  test('ignores memberships that have been closed', () async {
    await (db.update(db.memberships)..where((m) => m.id.equals(membershipId)))
        .write(MembershipsCompanion(endDate: Value(DateTime.utc(2026, 7, 1))));

    expect(await maintenance.ensureCurrentPeriods(now: today), 0);
  });

  test('the created cycle makes the member read DUE, not EXPIRED', () async {
    await db.into(db.membershipPeriods).insert(
        MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: DateTime.utc(2026, 6, 1),
            periodEnd: DateTime.utc(2026, 7, 1),
            expectedAmountMinor: 300000));

    // Before: nothing covers today, so the membership looks lapsed.
    expect(
      deriveMemberStatus(
        deactivatedAt: null,
        periods: [
          StatusPeriod(
            periodStart: DateTime.utc(2026, 6, 1),
            periodEnd: DateTime.utc(2026, 7, 1),
            isPaid: true,
          ),
        ],
        now: today,
      ),
      MemberStatus.expired,
    );

    await maintenance.ensureCurrentPeriods(now: today);

    final all = await periods();
    final status = deriveMemberStatus(
      deactivatedAt: null,
      periods: all
          .map((p) => StatusPeriod(
                periodStart: p.periodStart,
                periodEnd: p.periodEnd,
                isPaid: p.periodStart.toUtc() == DateTime.utc(2026, 6, 1),
              ))
          .toList(),
      now: today,
    );

    expect(status, MemberStatus.due);
  });
}
