import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';

/// The Dashboard and Members screen load the whole roster at once, and each
/// bound one SQL variable per billing cycle in the gym. Past SQLite's limit of
/// 32,766 both stopped loading; 600 members at 56 monthly cycles (about four
/// and a half years) is enough to reach it.
void main() {
  test('the roster still loads once the gym has more than 32766 cycles',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: 300000));

    await db.batch((b) {
      for (var m = 1; m <= 600; m++) {
        b.insert(
            db.members,
            MembersCompanion.insert(
              id: Value(m),
              memberCode: m,
              fullName: 'Member $m',
              phone: '+92300${1000000 + m}',
              joiningDate: DateTime.utc(2022, 1, 1),
            ));
        b.insert(
            db.memberships,
            MembershipsCompanion.insert(
              id: Value(m),
              memberId: m,
              planId: planId,
              startDate: DateTime.utc(2022, 1, 1),
            ));
      }
    });
    // The per-member uniqueness trigger makes row-by-row inserts slow; the
    // rows themselves are ordinary monthly cycles.
    await db.customStatement('DROP TRIGGER IF EXISTS trg_periods_one_per_member_insert');
    await db.batch((b) {
      for (var m = 1; m <= 600; m++) {
        for (var i = 0; i < 56; i++) {
          b.insert(
              db.membershipPeriods,
              MembershipPeriodsCompanion.insert(
                membershipId: m,
                periodStart: DateTime.utc(2022, 1 + i, 1),
                periodEnd: DateTime.utc(2022, 2 + i, 1),
                expectedAmountMinor: 300000,
              ));
        }
      }
    });

    final rows = await MemberRepository(db).list(now: DateTime.utc(2026, 8, 15));
    expect(rows, hasLength(600));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
