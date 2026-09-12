import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/startup_maintenance.dart';

/// The work the app does when it opens, in one place.
///
/// It used to live inline in `main()`, which meant the Refresh button in the
/// top bar had to restate it — and two copies of "what opening the app does"
/// drift apart the first time one of them gains a step.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int monthlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  test('opens the billing cycle a member is owed', () async {
    final memberId = await members.create(
      fullName: 'Newly Joined',
      phone: '+923000000001',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 3, 4),
    );

    expect(await db.select(db.membershipPeriods).get(), isEmpty,
        reason: 'a member has no cycle until the app next opens');

    await runStartupMaintenance(db, now: DateTime.utc(2026, 3, 20));

    final cycles = await (db.select(db.membershipPeriods)
          ..where((p) => p.membershipId.isNotNull()))
        .get();
    expect(cycles, hasLength(1));
    expect(cycles.single.periodStart.toUtc(), DateTime.utc(2026, 3, 4));
    expect(memberId, isNotNull);
  });

  test('is idempotent — running it twice opens nothing new', () async {
    await members.create(
      fullName: 'Newly Joined',
      phone: '+923000000002',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 3, 4),
    );

    await runStartupMaintenance(db, now: DateTime.utc(2026, 3, 20));
    await runStartupMaintenance(db, now: DateTime.utc(2026, 3, 20));

    expect(await db.select(db.membershipPeriods).get(), hasLength(1));
  });

  test('reports a member whose payments do not reconcile', () async {
    final memberId = await members.create(
      fullName: 'Stuck',
      phone: '+923000000003',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
    final membershipId = (await db.select(db.memberships).getSingle()).id;
    final adminId = (await db.select(db.users).getSingle()).id;

    // A settled month, then one opened early holding only part of its fee —
    // the shape the fee-rise treadmill leaves behind.
    await db.into(db.membershipPeriods).insert(
          MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: DateTime.utc(2026, 1, 1),
            periodEnd: DateTime.utc(2026, 2, 1),
            expectedAmountMinor: 150000,
            settledAt: Value(DateTime.utc(2026, 1, 5)),
          ),
        );
    final future = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: DateTime.utc(2026, 3, 1),
            periodEnd: DateTime.utc(2026, 4, 1),
            expectedAmountMinor: 250000,
          ),
        );
    final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            amountMinor: 250000,
            method: PaymentMethod.cash,
            paymentDate: DateTime.utc(2026, 1, 5),
            recordedById: adminId,
            idempotencyKey: 'stuck-1',
          ),
        );
    await db.into(db.paymentAllocations).insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            membershipPeriodId: future.id,
            amountMinor: 100000,
          ),
        );

    await runStartupMaintenance(db, now: DateTime.utc(2026, 2, 10));

    final flagged = await (db.select(db.auditEvents)
          ..where((e) => e.action.equals(AuditAction.billingDiscrepancyFound)))
        .get();
    expect(flagged, hasLength(1));
    expect(flagged.single.memberId, memberId);
  });
}
