// A transition onto a new billing day is charged for its own days — the
// owner's decision of 1 October 2026 — and the transitions charged a full
// month before then are left exactly as they are.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/cycle_pricing_log.dart';
import 'package:rich_man_fitness/data/cycle_repricing.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';

void main() {
  late AppDatabase db;
  late int planId;
  late int memberId;
  late Membership membership;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Silver', durationMonths: 1, priceMinor: 350000));
    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 465,
          fullName: 'Returning Member',
          phone: '+923000000465',
          joiningDate: DateTime.utc(2026, 5, 1),
        ));
    final membershipId = await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
          memberId: memberId,
          planId: planId,
          startDate: DateTime.utc(2026, 5, 1),
          // The shape the owner's database was in: billed on the 1st, with a
          // stored anchor of the 12th waiting for the next boundary.
          billingAnchorDay: const Value(12),
        ));
    membership = await (db.select(db.memberships)
          ..where((m) => m.id.equals(membershipId)))
        .getSingle();

    // September, paid.
    await db.into(db.membershipPeriods).insert(
        MembershipPeriodsCompanion.insert(
          membershipId: membershipId,
          periodStart: DateTime.utc(2026, 9, 1),
          periodEnd: DateTime.utc(2026, 10, 1),
          expectedAmountMinor: 350000,
          settledAt: Value(DateTime.utc(2026, 9, 1)),
        ));
  });

  tearDown(() => db.close());

  Future<MembershipPeriod> october() => (db.select(db.membershipPeriods)
        ..where((p) => p.periodStart.equals(DateTime.utc(2026, 10, 1))))
      .getSingle();

  test('the roll charges a 42-day transition for 42 days, not one month',
      () async {
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 10, 1));

    final cycle = await october();
    expect(cycle.periodEnd.toUtc(), DateTime.utc(2026, 11, 12));
    // 3,500 × 42 / 31, to the rupee.
    expect(cycle.expectedAmountMinor, 474200);
  });

  test('an advance payment prices the transition it reaches the same way',
      () async {
    final service = BillingCycleService(db);
    final billing = (await service.forMember(memberId))!;
    final offered =
        service.settleableFor(billing: billing, amountMinor: 1000000);

    final transition = offered.first;
    expect(transition.start, DateTime.utc(2026, 10, 1));
    expect(transition.end, DateTime.utc(2026, 11, 12));
    expect(transition.expectedMinor, 474200);
    // And whole months after it cost the fee.
    expect(offered[1].expectedMinor, 350000);
  });

  test('a transition already charged a full month is not re-priced to '
      'pro-rata by the startup sweep', () async {
    final opened = await db.into(db.membershipPeriods).insertReturning(
        MembershipPeriodsCompanion.insert(
          membershipId: membership.id,
          periodStart: DateTime.utc(2026, 10, 1),
          periodEnd: DateTime.utc(2026, 11, 12),
          expectedAmountMinor: 350000,
        ));
    await recordCycleOpened(
      db,
      membershipPeriodId: opened.id,
      amountMinor: 350000,
      membership: membership,
      plan: await (db.select(db.membershipPlans)
            ..where((p) => p.id.equals(planId)))
          .getSingle(),
      reason: 'Opened by the startup roll to cover today.',
    );

    await repriceAllOpenCycles(db, now: DateTime.utc(2026, 10, 2));

    expect((await october()).expectedAmountMinor, 350000);
  });

  test('a fee rise reaches an unpaid transition in proportion', () async {
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 10, 1));
    expect((await october()).expectedAmountMinor, 474200);

    // Silver goes from 3,500 to 4,000.
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(planId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(400000)));
    await repriceAllOpenCycles(db, now: DateTime.utc(2026, 10, 2));

    // 4,742 × 4,000 / 3,500 = 5,419.43, to the rupee.
    expect((await october()).expectedAmountMinor, 541900);
  });
}
