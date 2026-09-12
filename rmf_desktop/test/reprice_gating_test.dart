import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';

/// When re-pricing is allowed to run, and when it must keep its hands off.
///
/// `cycle_repricing.dart` carries a fee change through to bills that have not
/// been issued yet, and that is right — but it was wired to *every* save, not
/// to the saves that actually move money. Re-pricing then ran on edits the
/// owner never thought of as touching money at all, and because the audit row
/// is written only when the fee changed, the rewrite left no trace.
///
/// A cycle can carry a price that no longer matches the member's fee for
/// reasons that have nothing to do with this save — an import, a release that
/// predates re-pricing, a price change interrupted half way. Those members are
/// exactly the ones `billing_reconciliation.dart` exists to *report*, and the
/// house rule there is the one that applies here too: the rows are
/// indistinguishable from a genuine arrears position, so the correction is the
/// owner's to make, not the app's to make silently behind a phone-number edit.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late SettingsRepository settings;
  late int adminId;
  late int monthlyId;
  late int memberId;

  /// The member's open cycle, which is the only one these tests look at.
  Future<MembershipPeriod> openCycle() async {
    final periods = await periodsForMember(db, memberId);
    return periods.firstWhere((p) => p.settledAt == null);
  }

  /// Moves the plan's price without going through [SettingsRepository], so the
  /// member's open cycle is left stamped at the old price. This is the state
  /// an interrupted price change or an older release leaves behind.
  Future<void> strandCycleAtOldPrice(int newPriceMinor) async {
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(MembershipPlansCompanion(priceMinor: Value(newPriceMinor)));
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    settings = SettingsRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    // The gym's monthly fee starts at 1500.
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(150000)));

    memberId = await members.create(
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    // Open the member's cycle, stamped at 1500.
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 1, 10));
    expect((await openCycle()).expectedAmountMinor, 150000);
  });

  tearDown(() async => db.close());

  test('correcting a phone number leaves a stranded cycle at its own price',
      () async {
    await strandCycleAtOldPrice(250000);

    // The owner opens the member to fix a typo in the phone number. Nothing
    // about what this member is charged is on screen, let alone changed.
    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000002',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
      actorId: adminId,
      now: DateTime.utc(2026, 1, 20),
    );

    expect(
      (await openCycle()).expectedAmountMinor,
      150000,
      reason: 'a phone-number edit must not re-price the member',
    );
  });

  test('a save that does move the fee still re-prices, and says so', () async {
    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: monthlyId,
      feeOverrideMinor: 250000,
      joiningDate: DateTime.utc(2026, 1, 1),
      actorId: adminId,
      now: DateTime.utc(2026, 1, 20),
    );

    expect((await openCycle()).expectedAmountMinor, 250000);

    final logged = await AuditRepository(db).recent();
    final feeChange = logged
        .where((e) => e.action == AuditAction.memberFeeChanged)
        .toList();
    expect(feeChange, hasLength(1));
    expect(feeChange.single.detail, contains('re-priced'));
  });

  test('renaming a plan leaves stranded cycles at their own price', () async {
    await strandCycleAtOldPrice(250000);

    // Same price as the row already holds — this save is a rename, nothing
    // more, and the roster's bills are not its business.
    await settings.savePlan(
      id: monthlyId,
      name: 'Monthly (standard)',
      durationMonths: 1,
      priceMinor: 250000,
      isActive: true,
      actorId: adminId,
      now: DateTime.utc(2026, 1, 20),
    );

    expect(
      (await openCycle()).expectedAmountMinor,
      150000,
      reason: 'a rename must not re-price the roster',
    );
  });

  test('changing a plan price still re-prices the roster', () async {
    await settings.savePlan(
      id: monthlyId,
      name: 'Monthly',
      durationMonths: 1,
      priceMinor: 250000,
      isActive: true,
      actorId: adminId,
      now: DateTime.utc(2026, 1, 20),
    );

    expect((await openCycle()).expectedAmountMinor, 250000);

    final logged = await AuditRepository(db).recent();
    expect(
      logged.where((e) => e.action == AuditAction.planPriceChanged),
      hasLength(1),
    );
  });

  test('a plan price change leaves members on their own fee alone', () async {
    // This member negotiated their own rate, so the plan's price is not what
    // they are billed and a change to it is not their business. Their cycle is
    // stranded below their override, which the plan screen promises in as many
    // words it will not touch: "Members on their own custom fee are
    // unaffected".
    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: monthlyId,
      feeOverrideMinor: 200000,
      joiningDate: DateTime.utc(2026, 1, 1),
      actorId: adminId,
      now: DateTime.utc(2026, 1, 15),
    );
    final strandedId = (await openCycle()).id;
    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(strandedId)))
        .write(const MembershipPeriodsCompanion(
            expectedAmountMinor: Value(150000)));

    await settings.savePlan(
      id: monthlyId,
      name: 'Monthly',
      durationMonths: 1,
      priceMinor: 250000,
      isActive: true,
      actorId: adminId,
      now: DateTime.utc(2026, 1, 20),
    );

    expect(
      (await openCycle()).expectedAmountMinor,
      150000,
      reason: 'a plan price change must not reach a custom-fee member',
    );
  });

  test('a plan price change applies the price and the re-pricing together',
      () async {
    await settings.savePlan(
      id: monthlyId,
      name: 'Monthly',
      durationMonths: 1,
      priceMinor: 250000,
      isActive: true,
      actorId: adminId,
      now: DateTime.utc(2026, 1, 20),
    );

    // The two halves of the operation have to agree. A new price live against
    // a roster still carrying the old one is the split state re-pricing exists
    // to prevent, so they belong in one transaction.
    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(monthlyId)))
        .getSingle();
    expect(plan.priceMinor, 250000);
    expect((await openCycle()).expectedAmountMinor, plan.priceMinor);
  });
}
