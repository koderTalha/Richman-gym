import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';

/// AUDIT REPRO (billing): `repriceOpenCycles` copies the *new plan's price*
/// onto an unpaid, not-yet-ended cycle without looking at the cycle's
/// *length*. Changing plan between plans of different durations therefore
/// bills a one-month cycle at a three-month price (Monthly → Quarterly), or a
/// three-month cycle at a one-month price (Quarterly → Monthly). The same
/// sweep runs at every launch (`repriceAllOpenCycles`), so it is not limited
/// to the moment of the plan change.
///
/// Seeded prices: Monthly Rs 3,000 (1 month), Quarterly Rs 8,000 (3 months).
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int monthlyId;
  late int quarterlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    Future<int> plan(String name) async => (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals(name)))
            .getSingle())
        .id;
    monthlyId = await plan('Monthly');
    quarterlyId = await plan('Quarterly');
  });

  tearDown(() => db.close());

  Future<void> changePlan(int id, int planId) => members.update(
        id: id,
        fullName: 'Plan Changer',
        phone: '+923005550000',
        planId: planId,
        joiningDate: DateTime.utc(2026, 8, 1),
        now: DateTime.utc(2026, 9, 15, 6),
      );

  test('moving to Quarterly mid-month does not bill the one-month September '
      'cycle at the three-month price', () async {
    final id = await members.create(
      fullName: 'Plan Changer',
      phone: '+923005550000',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 8, 1),
    );
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 9, 2, 6));

    await changePlan(id, quarterlyId);

    final september = (await periodsForMember(db, id)).single;
    expect(september.periodEnd.toUtc(), DateTime.utc(2026, 10, 1),
        reason: 'precondition: a one-month cycle');
    expect(september.expectedAmountMinor, isNot(800000),
        reason: 'Rs 8,000 is three months of access; this cycle is one');

    final billing = await BillingCycleService(db).forMember(id);
    expect(billing!.outstandingMinor, lessThan(800000));
  });

  test('moving to Monthly mid-quarter does not bill the three-month quarter '
      'at the one-month price', () async {
    final id = await members.create(
      fullName: 'Plan Changer',
      phone: '+923005550000',
      planId: quarterlyId,
      joiningDate: DateTime.utc(2026, 9, 1),
    );
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 9, 2, 6));

    await changePlan(id, monthlyId);

    final quarter = (await periodsForMember(db, id)).single;
    expect(quarter.periodEnd.toUtc(), DateTime.utc(2026, 12, 1),
        reason: 'precondition: a three-month cycle');
    expect(quarter.expectedAmountMinor, isNot(300000),
        reason: 'Rs 3,000 buys one month; this cycle covers September to '
            'November');
  });
}
