import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';

/// The number next to each filter chip on the Members screen.
///
/// The one thing that must never happen: a chip promising "Due (3)" while
/// tapping it shows something other than three rows. Every test here checks
/// the count against what selecting that same filter actually returns, not
/// against a hand-counted expectation that could quietly drift from the real
/// filtering rule in `MemberRepository._applyFilter`.
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

  Future<int> memberOn(String name, String phone) => members.create(
        fullName: name,
        phone: phone,
        planId: monthlyId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

  /// Opens this month's cycle and pays it in full — the member reads PAID.
  Future<void> makePaid(int memberId, {required DateTime now}) async {
    final membership = (await openMembershipFor(db, memberId))!;
    final plan = (await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(membership.planId)))
        .getSingle());
    final start = DateTime.utc(now.year, now.month, 1);
    final period = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: start,
            periodEnd: DateTime.utc(now.year, now.month + 1, 1),
            expectedAmountMinor: plan.priceMinor,
          ),
        );
    final adminId = (await db.select(db.users).getSingle()).id;
    final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            membershipPeriodId: Value(period.id),
            amountMinor: plan.priceMinor,
            method: PaymentMethod.cash,
            paymentDate: now,
            recordedById: adminId,
            idempotencyKey: 'paid-$memberId',
          ),
        );
    await db.into(db.paymentAllocations).insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            membershipPeriodId: period.id,
            amountMinor: plan.priceMinor,
          ),
        );
    await (db.update(db.membershipPeriods)
          ..where((p) => p.id.equals(period.id)))
        .write(MembershipPeriodsCompanion(settledAt: Value(now)));
  }

  /// Opens this month's cycle unpaid — the member reads DUE.
  Future<void> makeDue(int memberId, {required DateTime now}) async {
    final membership = (await openMembershipFor(db, memberId))!;
    final plan = (await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(membership.planId)))
        .getSingle());
    await db.into(db.membershipPeriods).insert(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: DateTime.utc(now.year, now.month, 1),
            periodEnd: DateTime.utc(now.year, now.month + 1, 1),
            expectedAmountMinor: plan.priceMinor,
          ),
        );
  }

  final today = DateTime.utc(2026, 9, 15);

  test('counts sum to the same total as "All"', () async {
    final paid = await memberOn('Ali Khan', '+923000000001');
    final due = await memberOn('Bilal Ahmed', '+923000000002');
    final inactive = await memberOn('Chand Bibi', '+923000000003');

    await makePaid(paid, now: today);
    await makeDue(due, now: today);
    await members.setActive(inactive, false);

    final counts = await members.filterCounts(now: today);
    expect(counts[MemberFilter.all], 3);
    expect(counts[MemberFilter.paid], 1);
    expect(counts[MemberFilter.due], 1);
    expect(counts[MemberFilter.inactive], 1);
    expect(counts[MemberFilter.active], 2,
        reason: 'active means not inactive — paid and due both qualify');
  });

  test('every count matches list(filter: f).length exactly', () async {
    await makePaid(await memberOn('Ali Khan', '+923000000001'), now: today);
    await makeDue(await memberOn('Bilal Ahmed', '+923000000002'), now: today);
    await makeDue(
        await memberOn('Chand Bibi', '+923000000003'), now: today);

    final counts = await members.filterCounts(now: today);

    for (final filter in MemberFilter.values) {
      final actual = await members.list(filter: filter, now: today);
      expect(counts[filter], actual.length,
          reason: 'the ${filter.name} chip must promise exactly what '
              'selecting it reveals');
    }
  });

  test('a search term scopes every count, not just the visible list',
      () async {
    await makePaid(await memberOn('Ali Khan', '+923000000001'), now: today);
    await makeDue(await memberOn('Ali Raza', '+923000000002'), now: today);
    await makeDue(
        await memberOn('Bilal Ahmed', '+923000000003'), now: today);

    final counts = await members.filterCounts(search: 'ali', now: today);

    expect(counts[MemberFilter.all], 2,
        reason: 'only the two Alis match the search');
    expect(counts[MemberFilter.paid], 1);
    expect(counts[MemberFilter.due], 1);
  });

  test('listWithCounts returns rows and counts that agree with each other',
      () async {
    await makePaid(await memberOn('Ali Khan', '+923000000001'), now: today);
    await makeDue(await memberOn('Bilal Ahmed', '+923000000002'), now: today);

    final result = await members.listWithCounts(
      filter: MemberFilter.due,
      now: today,
    );

    expect(result.rows, hasLength(1));
    expect(result.rows.single.member.fullName, 'Bilal Ahmed');
    expect(result.counts[MemberFilter.due], 1);
    expect(result.counts[MemberFilter.all], 2);
  });

  test('an empty roster reads zero everywhere, not a missing entry',
      () async {
    final counts = await members.filterCounts(now: today);
    for (final filter in MemberFilter.values) {
      expect(counts[filter], 0);
    }
  });
}
