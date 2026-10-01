import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/startup_maintenance.dart';

/// The startup roll must survive bad data rather than stop the app opening.
///
/// A database that predates the one-open-enrolment index can hold two open
/// enrolments for one member, and the roll used to give that member the same
/// cycle twice; the one-cycle-per-member trigger refused the second, the
/// whole roll rolled back for everyone, and `_boot` showed the failure screen
/// at every launch.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
  });

  tearDown(() => db.close());

  test('startup survives a legacy member with two open enrolments and rolls '
      'one cycle for them', () async {
    final members = MemberRepository(db);
    final plan = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle());

    final legacy = await members.create(
      fullName: 'Legacy Duplicate',
      phone: '+923001110000',
      planId: plan.id,
      joiningDate: DateTime.utc(2026, 9, 1),
    );
    final healthy = await members.create(
      fullName: 'Healthy Member',
      phone: '+923001110001',
      planId: plan.id,
      joiningDate: DateTime.utc(2026, 9, 1),
    );

    // The shape the best-effort unique index exists to tolerate: a file that
    // already held the duplicate, so the index could never be created.
    await db.customStatement('DROP INDEX IF EXISTS idx_memberships_one_open');
    await db.into(db.memberships).insert(MembershipsCompanion.insert(
          memberId: legacy,
          planId: plan.id,
          startDate: DateTime.utc(2026, 9, 1),
        ));

    await expectLater(
      runStartupMaintenance(db, now: DateTime.utc(2026, 10, 1, 6)),
      completes,
    );

    expect((await periodsForMember(db, healthy)).length, 1,
        reason: 'one bad member must not stop everyone else being rolled');
    expect((await periodsForMember(db, legacy)).length, 1);
  });

  test('a member whose cycle cannot be written is skipped, and everyone '
      'else is still rolled', () async {
    final members = MemberRepository(db);
    final plan = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle());

    final broken = await members.create(
      fullName: 'Broken Row',
      phone: '+923001110002',
      planId: plan.id,
      joiningDate: DateTime.utc(2026, 9, 1),
    );
    final healthy = await members.create(
      fullName: 'Healthy Member',
      phone: '+923001110003',
      planId: plan.id,
      joiningDate: DateTime.utc(2026, 9, 1),
    );
    final brokenEnrolment = (await openMembershipFor(db, broken))!.id;

    // Any failure at all on one member's insert.
    await db.customStatement(
      'CREATE TEMP TRIGGER refuse_one BEFORE INSERT ON membership_periods '
      'WHEN NEW.membership_id = $brokenEnrolment '
      "BEGIN SELECT RAISE(ABORT, 'simulated bad row'); END",
    );

    await expectLater(
      runStartupMaintenance(db, now: DateTime.utc(2026, 10, 1, 6)),
      completes,
    );

    expect(await periodsForMember(db, broken), isEmpty);
    expect(await periodsForMember(db, healthy), hasLength(1));
  });
}
