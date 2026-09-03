import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/domain/billing_cycle.dart';
import 'package:rich_man_fitness/domain/payment_settlement.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';

/// One member, one cycle starting on any given day — enforced by SQLite.
///
/// The table's own unique key is `(membership_id, period_start)`, which is not
/// the same promise. Changing a member's plan closes their enrolment and opens
/// a new one, so a member accumulates several `memberships` rows while
/// remaining one person with one continuous timeline. Two of those enrolments
/// could each hold a cycle starting 6 September, and the table would accept
/// both: two rows for one month, each able to take its own payment, and a
/// member who has paid twice for September with nothing anywhere saying so.
///
/// Every lookup in `membership_queries.dart` already resolves cycles *per
/// member* — collecting the member's enrolment ids and searching across all of
/// them. So the application has always treated `(member, period_start)` as the
/// key. This is the database agreeing.
void main() {
  late AppDatabase db;
  late int memberId;
  late int otherMemberId;
  late int planId;
  late int closedMembershipId;
  late int openMembershipId;
  late int otherMembershipId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());

    planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: 300000));

    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ali Khan',
          phone: '+923000000001',
          joiningDate: DateTime.utc(2026, 7, 6),
        ));

    otherMemberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 2,
          fullName: 'Bilal Ahmed',
          phone: '+923000000002',
          joiningDate: DateTime.utc(2026, 7, 6),
        ));

    // The member's history: a monthly enrolment they have since moved off.
    closedMembershipId = await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
          memberId: memberId,
          planId: planId,
          startDate: DateTime.utc(2026, 7, 6),
          endDate: const Value.absent(),
        ));

    // The plan change: the old enrolment closes, a new one opens.
    await (db.update(db.memberships)
          ..where((m) => m.id.equals(closedMembershipId)))
        .write(MembershipsCompanion(
            endDate: Value(DateTime.utc(2026, 9, 1))));

    openMembershipId = await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
          memberId: memberId,
          planId: planId,
          startDate: DateTime.utc(2026, 9, 1),
        ));

    otherMembershipId = await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
          memberId: otherMemberId,
          planId: planId,
          startDate: DateTime.utc(2026, 7, 6),
        ));
  });

  tearDown(() => db.close());

  Future<int> addCycle(int membershipId, DateTime start) =>
      db.into(db.membershipPeriods).insert(MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: start,
            periodEnd: DateTime.utc(start.year, start.month + 1, start.day),
            expectedAmountMinor: 300000,
          ));

  test('accepts one cycle per start date', () async {
    await addCycle(openMembershipId, DateTime.utc(2026, 9, 6));
    await addCycle(openMembershipId, DateTime.utc(2026, 10, 6));

    expect((await db.select(db.membershipPeriods).get()).length, 2);
  });

  test('refuses a duplicate cycle on the same enrolment', () async {
    await addCycle(openMembershipId, DateTime.utc(2026, 9, 6));

    await expectLater(
      addCycle(openMembershipId, DateTime.utc(2026, 9, 6)),
      throwsA(anything),
    );
  });

  test('refuses a duplicate cycle across a plan change', () async {
    // The gap this closes. Same member, same September cycle, two enrolments.
    await addCycle(closedMembershipId, DateTime.utc(2026, 9, 6));

    await expectLater(
      addCycle(openMembershipId, DateTime.utc(2026, 9, 6)),
      throwsA(predicate(
        (e) => e.toString().contains('billing cycle'),
        'a message naming the duplicate billing cycle',
      )),
    );
  });

  test('refuses moving a cycle onto an enrolment that already covers it',
      () async {
    // The same collision reached by update rather than insert — an owner
    // correcting which enrolment a cycle belongs to.
    await addCycle(closedMembershipId, DateTime.utc(2026, 9, 6));
    final octoberId = await addCycle(openMembershipId, DateTime.utc(2026, 10, 6));

    await expectLater(
      (db.update(db.membershipPeriods)..where((p) => p.id.equals(octoberId)))
          .write(MembershipPeriodsCompanion(
              periodStart: Value(DateTime.utc(2026, 9, 6)))),
      throwsA(anything),
    );
  });

  test('leaves a different member with the same start date alone', () async {
    // Every member on a monthly plan anchored to the 6th shares these dates.
    // The constraint is per member, not per date.
    await addCycle(openMembershipId, DateTime.utc(2026, 9, 6));
    await addCycle(otherMembershipId, DateTime.utc(2026, 9, 6));

    expect((await db.select(db.membershipPeriods).get()).length, 2);
  });

  test('leaves a legitimate second enrolment cycle alone', () async {
    // A plan change mid-timeline: the closed enrolment holds September, the
    // open one holds October. Different dates, both kept.
    await addCycle(closedMembershipId, DateTime.utc(2026, 9, 6));
    await addCycle(openMembershipId, DateTime.utc(2026, 10, 6));

    expect((await db.select(db.membershipPeriods).get()).length, 2);
  });

  group('materialising a cycle', () {
    test('adopts the row an earlier enrolment already holds', () async {
      // The cycle exists, but on the enrolment the member has since moved off.
      // Looking for it by enrolment finds nothing and inserts a second row for
      // the same month — which the trigger now refuses outright. Every other
      // lookup in membership_queries resolves per member; this must too.
      await addCycle(closedMembershipId, DateTime.utc(2026, 9, 6));

      final adopted = await BillingCycleService(db).materialise(
        membershipId: openMembershipId,
        cycle: SettleableCycle.fromCycle(
          BillingCycle(
            start: DateTime.utc(2026, 9, 6),
            end: DateTime.utc(2026, 10, 6),
          ),
          expectedMinor: 300000,
        ),
      );

      expect(adopted.membershipId, closedMembershipId,
          reason: 'the cycle stays where it was recorded');
      expect((await db.select(db.membershipPeriods).get()).length, 1);
    });

    test('still opens a cycle the member does not have yet', () async {
      final created = await BillingCycleService(db).materialise(
        membershipId: openMembershipId,
        cycle: SettleableCycle.fromCycle(
          BillingCycle(
            start: DateTime.utc(2026, 11, 6),
            end: DateTime.utc(2026, 12, 6),
          ),
          expectedMinor: 300000,
        ),
      );

      expect(created.membershipId, openMembershipId);
      expect(created.periodStart.toUtc(), DateTime.utc(2026, 11, 6));
    });
  });
}
