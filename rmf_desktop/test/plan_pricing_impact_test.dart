import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';

/// Who a plan price change is actually going to reach.
///
/// The owner is about to move what every member on a plan is asked for next
/// month. "This will affect some members" is not a thing anybody can act on;
/// "23 members follow this price, 4 have their own fee and will not move" is.
/// The count has to come from the same question `repriceOpenCyclesForPlan`
/// answers — members on this plan, still active, with no fee of their own —
/// or the dialog promises one thing and the button does another.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late SettingsRepository settings;
  late int monthlyId;
  late int goldId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    settings = SettingsRepository(db);

    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(150000)));

    await settings.savePlan(
      name: 'Gold',
      durationMonths: 1,
      priceMinor: 300000,
      isActive: true,
    );
    goldId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Gold')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  var nextPhone = 0;
  Future<int> join({required int planId, int? feeOverrideMinor}) {
    nextPhone++;
    return members.create(
      fullName: 'Member $nextPhone',
      phone: '+92300000${nextPhone.toString().padLeft(4, '0')}',
      planId: planId,
      feeOverrideMinor: feeOverrideMinor,
      joiningDate: DateTime.utc(2026, 1, 6),
    );
  }

  test('counts who follows the price and who has their own fee', () async {
    await join(planId: monthlyId);
    await join(planId: monthlyId);
    await join(planId: monthlyId, feeOverrideMinor: 180000);
    await join(planId: goldId);

    final impact = await settings.planPricingImpact(monthlyId);

    expect(impact.followingPlanPrice, 2);
    expect(impact.onCustomFee, 1,
        reason: 'they keep their own fee, whatever the plan does');
  });

  test('a member who has left the gym is in neither count', () async {
    final leaver = await join(planId: monthlyId);
    await join(planId: monthlyId);
    await members.setActive(leaver, false);

    final impact = await settings.planPricingImpact(monthlyId);

    expect(impact.followingPlanPrice, 1,
        reason: 'somebody who has left the gym is not re-billed — matching '
            'repriceOpenCycles, which skips them');
    expect(impact.onCustomFee, 0);
  });

  test('a plan nobody is on reaches nobody', () async {
    final impact = await settings.planPricingImpact(goldId);

    expect(impact.followingPlanPrice, 0);
    expect(impact.onCustomFee, 0);
    expect(impact.isEmpty, isTrue);
  });
}
