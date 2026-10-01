import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';

/// AUDIT REPRO (billing): a member added through the app on the 29th, 30th or
/// 31st has no stored `billingAnchorDay` (MemberRepository.create never writes
/// it), so `resolveAnchorDay` falls back to the day the *latest cycle starts*.
/// After a short month that start is the clamped day (30 Sep, 28 Feb), so the
/// anchor is read back off a clamped boundary — exactly the demotion
/// `billing_cycle.dart` promises cannot happen ("31 Jan → 28 Feb → 31 Mar").
///
/// The cycles stay contiguous, but the billing day wobbles between 28/30/31
/// and the member detail screen's "Day N" changes month to month.
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

  tearDown(() => db.close());

  int lastDay(int y, int m) => DateTime.utc(y, m + 1, 0).day;

  test('a member who joined on the 31st is billed on the 31st (or the last '
      'day of a shorter month) a year later', () async {
    final id = await members.create(
      fullName: 'Late Month Joiner',
      phone: '+923001112233',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 8, 31),
    );

    // The app opened every day for a year: the startup roll on each.
    final roll = BillingMaintenance(db);
    for (var day = DateTime.utc(2026, 8, 31);
        day.isBefore(DateTime.utc(2027, 9, 1));
        day = day.add(const Duration(days: 1))) {
      await roll.ensureCurrentPeriods(now: day.add(const Duration(hours: 6)));
    }

    final starts = [
      for (final p in await periodsForMember(db, id)) p.periodStart.toUtc()
    ];
    final offAnchor = [
      for (final s in starts)
        if (s.day != (31 < lastDay(s.year, s.month) ? 31 : lastDay(s.year, s.month)))
          '${s.year}-${s.month}-${s.day}',
    ];

    expect(offAnchor, isEmpty,
        reason: 'cycle starts: ${starts.map((s) => '${s.month}/${s.day}').join(', ')}');

    final billing = await BillingCycleService(db).forMember(id);
    expect(billing!.anchorDay, 31,
        reason: 'the member screen shows "Day ${billing.anchorDay}"');
  });
}
