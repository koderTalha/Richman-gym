import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/report_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/domain/monthly_report.dart';

/// The Reports screen's figures, against rows written straight to the
/// database so each rule is pinned on its own.
///
/// "Today" throughout is 15 October 2026, midday on the gym's clock.
void main() {
  late AppDatabase db;
  late int adminId;
  late int monthlyPlanId;
  late int otherPlanId;
  var keys = 0;

  final today = DateTime(2026, 10, 15, 12);
  const fee = 300000;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;
    final plans = await db.select(db.membershipPlans).get();
    monthlyPlanId = plans.firstWhere((p) => p.name == 'Monthly').id;
    otherPlanId = plans.firstWhere((p) => p.id != monthlyPlanId).id;
  });

  tearDown(() async => db.close());

  ReportRepository reports() => ReportRepository(db, clock: () => today);

  /// A member with an open enrolment on [planId], billed from the 1st.
  Future<({int member, int membership})> member(
    String name, {
    required DateTime joined,
    int? planId,
    DateTime? deactivatedAt,
  }) async {
    final code = (await db.select(db.members).get()).length + 1;
    final memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: code,
          fullName: name,
          phone: '+92300000${code.toString().padLeft(4, '0')}',
          joiningDate: joined,
          deactivatedAt: Value(deactivatedAt),
        ));
    final membershipId =
        await db.into(db.memberships).insert(MembershipsCompanion.insert(
              memberId: memberId,
              planId: planId ?? monthlyPlanId,
              startDate: joined,
            ));
    return (member: memberId, membership: membershipId);
  }

  /// The month-long cycle starting the 1st of [month] (UTC), owing [fee].
  Future<int> cycle(int membershipId, int month, {int expected = fee}) =>
      db.into(db.membershipPeriods).insert(MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: DateTime.utc(2026, month, 1),
            periodEnd: DateTime.utc(2026, month + 1, 1),
            expectedAmountMinor: expected,
          ));

  /// A payment on [on], allocated in full to [periodId] if given, settling
  /// it when the money covers the fee — as the Record Payment form does.
  Future<int> pay(
    int memberId,
    DateTime on, {
    int amount = fee,
    int? periodId,
    PaymentMethod method = PaymentMethod.cash,
    PaymentSource source = PaymentSource.manual,
  }) async {
    final id = await db.into(db.payments).insert(PaymentsCompanion.insert(
          memberId: memberId,
          membershipPeriodId: Value(periodId),
          amountMinor: amount,
          method: method,
          paymentDate: on,
          source: Value(source),
          recordedById: adminId,
          idempotencyKey: 'k${keys++}',
        ));
    if (periodId != null) {
      await db.into(db.paymentAllocations).insert(
          PaymentAllocationsCompanion.insert(
              paymentId: id, membershipPeriodId: periodId, amountMinor: amount));
      if (amount >= fee) {
        await (db.update(db.membershipPeriods)
              ..where((p) => p.id.equals(periodId)))
            .write(MembershipPeriodsCompanion(settledAt: Value(on.toUtc())));
      }
    }
    return id;
  }

  const october = ReportMonth(2026, 10);
  const september = ReportMonth(2026, 9);

  group('money', () {
    test('counts the month\'s payments, imported ones included, and keeps '
        'ledger money off the daily chart', () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 1, 1));
      await pay(ali.member, DateTime(2026, 10, 3, 10), amount: 200000);
      await pay(ali.member, DateTime(2026, 10, 1),
          amount: 100000, source: PaymentSource.imported);
      await pay(ali.member, DateTime(2026, 9, 30, 23, 30), amount: 50000);

      final report = await reports().build(october);

      expect(report.revenue.value, 300000);
      expect(report.paymentCount.value, 2);
      expect(report.importedRevenueMinor, 100000);
      expect(report.dailyRevenueMinor[2], 200000);
      expect(report.dailyRevenueMinor.reduce((a, b) => a + b) +
          report.importedRevenueMinor, report.revenue.value,
          reason: 'the chart plus the ledger money is the whole month');
      expect(report.collectedToDateMinor, 350000);
    });

    test('every breakdown and the table add up to the headline', () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 1, 1));
      final sara = await member('Sara',
          joined: DateTime.utc(2026, 2, 1), planId: otherPlanId);
      final aliOct = await cycle(ali.membership, 10);
      final saraOct = await cycle(sara.membership, 10);
      await pay(ali.member, DateTime(2026, 10, 2), periodId: aliOct);
      await pay(sara.member, DateTime(2026, 10, 4),
          periodId: saraOct, method: PaymentMethod.easypaisa, amount: 150000);
      await pay(sara.member, DateTime(2026, 10, 5),
          method: PaymentMethod.easypaisa, amount: 150000);

      final report = await reports().build(october);
      int total(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);

      expect(report.revenue.value, 600000);
      expect(total(report.payments.map((p) => p.amountMinor)), 600000);
      expect(total(report.byMethod.map((s) => s.amountMinor)), 600000);
      expect(total(report.byPlan.map((s) => s.amountMinor)), 600000);
      expect(report.byMethod.first.label, 'Easypaisa',
          reason: 'largest first');
      expect(report.byPlan.map((s) => s.label), contains('No plan'),
          reason: 'a payment tied to no cycle has no plan to count under');
      expect(report.payingMembers, 2);
      expect(report.averagePerPayingMemberMinor, 300000);
    });

    test('the month in progress is compared with the same days of the last',
        () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 1, 1));
      await pay(ali.member, DateTime(2026, 9, 10), amount: 100000);
      await pay(ali.member, DateTime(2026, 9, 25), amount: 900000);
      await pay(ali.member, DateTime(2026, 10, 12), amount: 200000);

      final running = await reports().build(october);
      expect(running.isCurrentMonth, isTrue);
      expect(running.revenue.previous, 100000,
          reason: 'only 1-15 September is comparable with 1-15 October');
      expect(running.comparisonLabel, '1–15 September');

      final ended = await reports().build(september);
      expect(ended.isCurrentMonth, isFalse);
      expect(ended.revenue.value, 1000000);
      expect(ended.comparisonLabel, 'August 2026');
    });

    test('no comparison before the first month on record', () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 10, 2));
      await pay(ali.member, DateTime(2026, 10, 2));

      final report = await reports().build(october);
      expect(report.revenue.previous, isNull);
      expect(report.comparisonLabel, isNull);
      expect(report.previousDailyRevenueMinor, isNull);
      expect(report.growth, hasLength(1));
    });
  });

  group('members at the month\'s end', () {
    test('a cycle paid after the month ended was still owed at its end',
        () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 9, 1));
      final sep = await cycle(ali.membership, 9);
      final oct = await cycle(ali.membership, 10);
      await pay(ali.member, DateTime(2026, 10, 3), periodId: sep);
      await pay(ali.member, DateTime(2026, 10, 3, 1), periodId: oct);

      final sept = await reports().build(september);
      final row = sept.members.single;
      expect(row.status, MemberStatus.due);
      expect(row.arrearsMinor, fee);
      expect(sept.owed.value, fee);
      expect(sept.owingMembers, 1);

      final oct15 = await reports().build(october);
      expect(oct15.members.single.status, MemberStatus.paid);
      expect(oct15.owed.value, 0);
      expect(oct15.owed.previous, fee);
    });

    test('a member deactivated later was active then', () async {
      await member('Ali',
          joined: DateTime.utc(2026, 1, 1),
          deactivatedAt: DateTime.utc(2026, 10, 5));

      expect((await reports().build(september)).activeMembers.value, 1);
      final oct = await reports().build(october);
      expect(oct.activeMembers.value, 0);
      expect(oct.activeMembers.previous, 1);
      expect(oct.statusCounts[MemberStatus.inactive], 1);
    });

    test('someone who joined after the month is not on its roster', () async {
      await member('Ali', joined: DateTime.utc(2026, 9, 1));
      await member('Sara', joined: DateTime.utc(2026, 10, 2));

      expect((await reports().build(september)).totalMembers.value, 1);
      final oct = await reports().build(october);
      expect(oct.totalMembers.value, 2);
      expect(oct.totalMembers.previous, 1);
    });

    test('this month\'s statuses are the Members screen\'s', () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 8, 1));
      final sara = await member('Sara', joined: DateTime.utc(2026, 8, 1));
      await member('Omar', joined: DateTime.utc(2026, 8, 1));
      await pay(ali.member, DateTime(2026, 10, 1),
          periodId: await cycle(ali.membership, 10));
      await cycle(sara.membership, 8);
      await pay(sara.member, DateTime(2026, 8, 3),
          periodId: await cycle(sara.membership, 9));

      final report = await reports().build(october);
      final screen = await MemberRepository(db).list(now: today);
      expect(
        {for (final m in report.members) m.memberId: m.status},
        {for (final m in screen) m.id: m.status},
      );
    });

    test('owed is every begun month\'s balance, part-payments taken off, and '
        'not next month\'s bill', () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 8, 1));
      await cycle(ali.membership, 8);
      final sep = await cycle(ali.membership, 9);
      await cycle(ali.membership, 10);
      await cycle(ali.membership, 11);
      await pay(ali.member, DateTime(2026, 9, 20), amount: 100000, periodId: sep);

      final report = await reports().build(october);
      expect(report.owed.value, fee + (fee - 100000) + fee);
      expect(report.owed.previous, fee + (fee - 100000),
          reason: 'at the end of September, October had not begun');
    });
  });

  group('activity', () {
    test('new members and renewals, each counted once', () async {
      final old = await member('Ali', joined: DateTime.utc(2026, 3, 1));
      final fresh = await member('Sara', joined: DateTime.utc(2026, 10, 2));
      await pay(old.member, DateTime(2026, 10, 2), amount: 100000);
      await pay(old.member, DateTime(2026, 10, 9), amount: 200000);
      await pay(fresh.member, DateTime(2026, 10, 2));

      final report = await reports().build(october);
      expect(report.newMembers.value, 1);
      expect(report.renewals.value, 1,
          reason: 'two payments are still one member renewing, and a new '
              'member\'s first payment is not a renewal');
      final growthNow = report.growth.last;
      expect(growthNow.month, october);
      expect(growthNow.newMembers, 1);
      expect(growthNow.renewals, 1);
      expect(report.members.firstWhere((m) => m.name == 'Ali').renewed, isTrue);
      expect(report.members.firstWhere((m) => m.name == 'Sara').isNew, isTrue);
    });

    test('growth runs back at most twelve months', () async {
      final ali = await member('Ali', joined: DateTime.utc(2024, 1, 1));
      await pay(ali.member, DateTime(2024, 1, 5));

      final report = await reports().build(october);
      expect(report.growth, hasLength(12));
      expect(report.growth.first.month, const ReportMonth(2025, 11));
    });
  });

  group('filters', () {
    test('a payment method narrows the money and not the members', () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 1, 1));
      await pay(ali.member, DateTime(2026, 10, 2), amount: 100000);
      await pay(ali.member, DateTime(2026, 10, 3),
          amount: 250000, method: PaymentMethod.jazzcash);

      final report = await reports().build(october,
          filters: const ReportFilters(method: PaymentMethod.jazzcash));
      expect(report.revenue.value, 250000);
      expect(report.payments, hasLength(1));
      expect(report.totalMembers.value, 1);
    });

    test('a search narrows both, by name, phone or code', () async {
      final ali = await member('Test Searchable', joined: DateTime.utc(2026, 1, 1));
      final sara = await member('Sara', joined: DateTime.utc(2026, 1, 1));
      await pay(ali.member, DateTime(2026, 10, 2));
      await pay(sara.member, DateTime(2026, 10, 2), amount: 50000);

      for (final term in ['searchable', '0300-0000001', '1']) {
        final report = await reports()
            .build(october, filters: ReportFilters(search: term));
        expect(report.members.map((m) => m.name), ['Test Searchable'], reason: term);
        expect(report.revenue.value, fee, reason: term);
      }
    });

    test('a plan picks payments by the cycle they paid for', () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 1, 1));
      await pay(ali.member, DateTime(2026, 10, 2),
          periodId: await cycle(ali.membership, 10));
      await pay(ali.member, DateTime(2026, 10, 3), amount: 1000);

      final report = await reports()
          .build(october, filters: ReportFilters(planId: monthlyPlanId));
      expect(report.revenue.value, fee);
      expect(report.members, hasLength(1));
    });

    test('a status picks members as they stood at the snapshot', () async {
      final ali = await member('Ali', joined: DateTime.utc(2026, 8, 1));
      await member('Sara', joined: DateTime.utc(2026, 8, 1));
      await pay(ali.member, DateTime(2026, 10, 2),
          periodId: await cycle(ali.membership, 10));

      final report = await reports().build(october,
          filters: const ReportFilters(status: MemberStatus.paid));
      expect(report.members.map((m) => m.name), ['Ali']);
      expect(report.revenue.value, fee);
      expect(report.statusCounts[MemberStatus.due], 0);
    });
  });

  test('an empty database reports nothing rather than failing', () async {
    final report = await reports().build(october);
    expect(report.revenue.value, 0);
    expect(report.totalMembers.value, 0);
    expect(report.growth, isEmpty);
    expect(report.averagePerPayingMemberMinor, isNull);
  });
}
