import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/startup_maintenance.dart';

/// The "Effective from: Custom date" choice on the member form.
///
/// 1. A fee change saved as applying from 10 September leaves the cycle that
///    began on the 1st at its old price. The next launch (or Reload) used to
///    re-price that cycle anyway, because the startup sweep passed no date.
///
/// 2. The date picker returns a *local* midnight, which on the gym's UTC+5
///    clock is the evening before. Stored as given, every use of it landed on
///    the day before the one the owner picked. Only shows on a machine set to
///    Asia/Karachi, which is the gym's and the developer's.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int basicId;
  late int studentId;

  const basicFee = 400000;
  const studentFee = 250000;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    basicId = (await db.into(db.membershipPlans).insertReturning(
            MembershipPlansCompanion.insert(
                name: 'Basic', durationMonths: 1, priceMinor: basicFee)))
        .id;
    studentId = (await db.into(db.membershipPlans).insertReturning(
            MembershipPlansCompanion.insert(
                name: 'Student', durationMonths: 1, priceMinor: studentFee)))
        .id;
  });

  tearDown(() => db.close());

  Future<int> memberWithSeptemberCycle() async {
    final id = await members.create(
      fullName: 'Fee Change Member',
      phone: '+923001234000',
      planId: basicId,
      joiningDate: DateTime.utc(2026, 8, 1),
    );
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 9, 2, 6));
    return id;
  }

  Future<void> moveToStudent(int id, DateTime effectiveFrom) => members.update(
        id: id,
        fullName: 'Fee Change Member',
        phone: '+923001234000',
        planId: studentId,
        joiningDate: DateTime.utc(2026, 8, 1),
        now: DateTime.utc(2026, 9, 20, 6),
        // Exactly what showDatePicker returns: a local midnight.
        effectiveFrom: effectiveFrom,
      );

  Future<int> septemberExpected(int id) async => (await periodsForMember(db, id))
      .singleWhere((p) => p.periodStart.toUtc() == DateTime.utc(2026, 9, 1))
      .expectedAmountMinor;

  test('a cycle the owner said keeps the old fee still keeps it after the '
      'next launch', () async {
    final id = await memberWithSeptemberCycle();

    await moveToStudent(id, DateTime(2026, 9, 10));
    expect(await septemberExpected(id), basicFee,
        reason: 'precondition: the save itself honoured the date');

    await runStartupMaintenance(db, now: DateTime.utc(2026, 9, 21, 6));

    expect(await septemberExpected(id), basicFee,
        reason: 'September began before the 10 Sep effective date');
  });

  test('the effective date recorded is the day the owner picked', () async {
    final id = await memberWithSeptemberCycle();

    await moveToStudent(id, DateTime(2026, 9, 10));

    final change = await db.select(db.membershipChanges).getSingle();
    expect(change.effectiveFrom.toUtc(), DateTime.utc(2026, 9, 10),
        reason: 'local offset here: ${DateTime(2026, 9, 10).timeZoneOffset}');

    final audit = await (db.select(db.auditEvents)
          ..where((a) => a.action.equals(AuditAction.memberFeeChanged)))
        .getSingle();
    expect(audit.detail, contains('Applies from 10 Sep 2026'));

    final opened = (await openMembershipFor(db, id))!;
    expect(opened.startDate.toUtc(), DateTime.utc(2026, 9, 10));
  });
}
