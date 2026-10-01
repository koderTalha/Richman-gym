import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';

/// Restarting a returning member's billing from the day they came back.
///
/// The owner's rule, in his words: a member who stopped coming and returns
/// starts again from the day they walk in. Paid on 25 September means covered
/// until 25 October, billed on the 25th from then on — not billed for the
/// calendar month, and not owing the months they were away.
void main() {
  late AppDatabase db;
  late BillingCycleService cycles;
  late MemberRepository members;
  late int adminId;
  late int monthlyId;
  var keys = 0;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    cycles = BillingCycleService(db);
    members = MemberRepository(db);
    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  Future<int> memberJoined(DateTime joined, {int? anchorDay}) async {
    final id = await members.create(
      fullName: 'Test Returner',
      phone: '+923000000039',
      planId: monthlyId,
      feeOverrideMinor: 250000,
      joiningDate: joined,
    );
    if (anchorDay != null) {
      await (db.update(db.memberships)..where((m) => m.memberId.equals(id)))
          .write(MembershipsCompanion(billingAnchorDay: Value(anchorDay)));
    }
    return id;
  }

  /// A cycle row, paid in full on [paidOn] (the gym's wall clock) if given.
  Future<int> cycle(
    int memberId,
    DateTime start,
    DateTime end, {
    DateTime? paidOn,
    int expected = 250000,
    int? paidMinor,
  }) async {
    final membership = (await openMembershipFor(db, memberId))!;
    final period = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: start,
            periodEnd: end,
            expectedAmountMinor: expected,
          ),
        );
    if (paidOn != null) {
      final amount = paidMinor ?? expected;
      final paymentId = await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              memberId: memberId,
              membershipPeriodId: Value(period.id),
              amountMinor: amount,
              method: PaymentMethod.cash,
              paymentDate: paidOn,
              recordedById: adminId,
              idempotencyKey: 'k${keys++}',
            ),
          );
      await db.into(db.paymentAllocations).insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              membershipPeriodId: period.id,
              amountMinor: amount,
            ),
          );
      if (amount >= expected) {
        await (db.update(db.membershipPeriods)
              ..where((p) => p.id.equals(period.id)))
            .write(MembershipPeriodsCompanion(settledAt: Value(paidOn)));
      }
    }
    return period.id;
  }

  Future<List<(DateTime, DateTime, bool)>> timeline(int memberId) async => [
        for (final p in await periodsForMember(db, memberId))
          (p.periodStart.toUtc(), p.periodEnd.toUtc(), p.settledAt != null),
      ];

  DateTime d(int month, int day) => DateTime.utc(2026, month, day);

  group('A returner, exactly as the gym recorded them', () {
    late int returner;
    late int septemberCycle;

    // Imported on the 1st of each month, billing day 10, away July and
    // August, back on 25 September and paid by JazzCash — which the payment
    // dialog put on 1 Sep – 1 Oct, followed by an unpaid 1 Oct – 10 Nov.
    setUp(() async {
      returner = await memberJoined(d(9, 25), anchorDay: 10);
      for (final m in [1, 2, 3, 4, 6]) {
        await cycle(returner, d(m, 1), d(m + 1, 1), paidOn: DateTime(2026, m, 1));
      }
      septemberCycle =
          await cycle(returner, d(9, 1), d(10, 1), paidOn: DateTime(2026, 9, 25));
      await cycle(returner, d(10, 1), d(11, 10));
    });

    test('the preview says what will move, and writes nothing', () async {
      final before = await timeline(returner);

      final plan = await cycles.previewRestart(
          memberId: returner, from: d(9, 25), today: d(10, 1));

      expect(plan, isA<BillingRestartPlan>());
      plan as BillingRestartPlan;
      expect(plan.firstCycle.start, d(9, 25));
      expect(plan.firstCycle.end, d(10, 25));
      expect(plan.anchorDay, 25);
      expect(plan.moved?.periodId, septemberCycle);
      expect(plan.dropped.map((c) => (c.start, c.end)), [(d(10, 1), d(11, 10))]);
      expect(await timeline(returner), before);
    });

    test('their September payment covers 25 Sep to 25 Oct', () async {
      final result = await cycles.restartBilling(
          memberId: returner, from: d(9, 25), today: d(10, 1), actorId: adminId);
      expect(result, isA<BillingRestartPlan>());

      expect(await timeline(returner), [
        (d(1, 1), d(2, 1), true),
        (d(2, 1), d(3, 1), true),
        (d(3, 1), d(4, 1), true),
        (d(4, 1), d(5, 1), true),
        (d(6, 1), d(7, 1), true),
        (d(9, 25), d(10, 25), true),
      ], reason: 'the paid history stays exactly as it was');

      final billing = (await cycles.forMember(returner))!;
      expect(billing.anchorDay, 25);
      expect(billing.nextUnsettled, null, reason: 'nothing is owed today');
      expect(billing.nextDueDate, d(10, 25));
    });

    test('the money stays on the same cycle, so the receipt still matches',
        () async {
      await cycles.restartBilling(
          memberId: returner, from: d(9, 25), today: d(10, 1));

      final allocation = await (db.select(db.paymentAllocations)
            ..where((a) => a.membershipPeriodId.equals(septemberCycle)))
          .getSingle();
      expect(allocation.amountMinor, 250000);
    });

    test('nothing is billed again until 25 October, then on the 25th',
        () async {
      await cycles.restartBilling(
          memberId: returner, from: d(9, 25), today: d(10, 1));
      final maintenance = BillingMaintenance(db);

      expect(await maintenance.ensureCurrentPeriods(now: d(10, 24)), 0);
      expect(await maintenance.ensureCurrentPeriods(now: d(10, 25)), 1);

      expect((await timeline(returner)).last, (d(10, 25), d(11, 25), false));
    });

    test('it is in the audit log in words the owner can check', () async {
      await cycles.restartBilling(
          memberId: returner, from: d(9, 25), today: d(10, 1), actorId: adminId);

      final event = await (db.select(db.auditEvents)
            ..where((e) => e.action.equals(AuditAction.billingRestarted)))
          .getSingle();
      expect(event.summary, contains('25 Sep 2026'));
      expect(event.detail, contains('25 Oct 2026'));
    });
  });

  group('a member who stopped coming and returns', () {
    late int member;

    setUp(() async {
      member = await memberJoined(d(1, 1));
      await cycle(member, d(1, 1), d(2, 1), paidOn: DateTime(2026, 1, 1));
      // The month they stopped coming: opened by the roll, never paid.
      await cycle(member, d(2, 1), d(3, 1));
      await members.setActive(member, false);
    });

    test('owes nothing for the months away and starts on the return day',
        () async {
      await members.setActive(member, true);
      await cycles.restartBilling(
          memberId: member, from: d(3, 20), today: d(3, 20));

      expect(await timeline(member), [
        (d(1, 1), d(2, 1), true),
        (d(3, 20), d(4, 20), false),
      ]);
      final billing = (await cycles.forMember(member))!;
      expect(billing.anchorDay, 20);
      expect(billing.outstandingMinor, 250000, reason: 'one month, not two');
    });

    test('the next payment taken settles the month they came back for',
        () async {
      await members.setActive(member, true);
      await cycles.restartBilling(
          memberId: member, from: d(3, 20), today: d(3, 20));

      final billing = (await cycles.forMember(member))!;
      final offered =
          cycles.settleableFor(billing: billing, amountMinor: 250000);
      expect(offered.first.start, d(3, 20));
    });

    test('a month owed from before they last paid is still owed', () async {
      // January unpaid, then they paid February, then stopped in March.
      final other = await memberJoined(d(1, 1));
      await cycle(other, d(1, 1), d(2, 1));
      await cycle(other, d(2, 1), d(3, 1), paidOn: DateTime(2026, 2, 1));
      await cycle(other, d(3, 1), d(4, 1));

      await cycles.restartBilling(memberId: other, from: d(4, 5), today: d(4, 5));

      expect(await timeline(other), [
        (d(1, 1), d(2, 1), false),
        (d(2, 1), d(3, 1), true),
        (d(4, 5), d(5, 5), false),
      ], reason: 'only the unpaid run since they last paid is dropped');
    });
  });

  group('refused, with the reason, rather than guessed at', () {
    late int member;

    setUp(() async {
      member = await memberJoined(d(1, 1));
      await cycle(member, d(1, 1), d(2, 1), paidOn: DateTime(2026, 1, 1));
      await cycle(member, d(2, 1), d(3, 1), paidOn: DateTime(2026, 2, 1));
    });

    Future<String> refusal(DateTime from, {DateTime? today}) async {
      final result = await cycles.previewRestart(
          memberId: member, from: from, today: today ?? d(3, 15));
      expect(result, isA<BillingRestartRefused>());
      return (result as BillingRestartRefused).reason;
    }

    test('a day that has not come yet', () async {
      expect(await refusal(d(3, 20), today: d(3, 15)), contains('yet'));
    });

    test('a day inside months already paid for', () async {
      expect(await refusal(d(1, 20)), contains('already paid until'));
    });

    test('two payments taken since the restart day', () async {
      expect(await refusal(d(1, 1)), contains('more than one'));
    });

    test('a day after the payment that would have to move', () async {
      expect(await refusal(d(2, 15)), contains('1 Feb 2026'));
    });

    test('a day before they joined', () async {
      final late = await memberJoined(d(3, 10));
      final result = await cycles.previewRestart(
          memberId: late, from: d(3, 5), today: d(3, 15));
      expect(result, isA<BillingRestartRefused>());
      expect((result as BillingRestartRefused).reason, contains('joined'));
    });

    test('free days from the ledger import are never billed again', () async {
      // A member's shape: paid through August, then the import's cover
      // until their first bill on 21 October — settled and worth nothing.
      final freeDays = await memberJoined(d(1, 1));
      await cycle(freeDays, d(7, 1), d(8, 1), paidOn: DateTime(2026, 7, 1));
      await cycle(freeDays, d(8, 1), d(9, 1), paidOn: DateTime(2026, 8, 21));
      final waiver = await cycle(freeDays, d(9, 1), d(10, 21), expected: 0);
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(waiver)))
          .write(MembershipPeriodsCompanion(settledAt: Value(d(9, 1))));
      final before = await timeline(freeDays);

      final result = await cycles.restartBilling(
          memberId: freeDays, from: d(8, 21), today: d(10, 1));

      expect(result, isA<BillingRestartRefused>());
      expect((result as BillingRestartRefused).reason, contains('21 Oct 2026'));
      expect(await timeline(freeDays), before);
    });

    test('a payment taken on the return day moves, whatever month it was '
        'booked to', () async {
      // A member's shape: paid on 1 October, booked to a September
      // that ended that same day, then an unpaid October.
      final bookedEarly = await memberJoined(d(7, 1));
      await cycle(bookedEarly, d(7, 1), d(8, 1), paidOn: DateTime(2026, 7, 1));
      await cycle(bookedEarly, d(9, 1), d(10, 1), paidOn: DateTime(2026, 10, 1));
      await cycle(bookedEarly, d(10, 1), d(11, 1));

      final result = await cycles.restartBilling(
          memberId: bookedEarly, from: d(10, 1), today: d(10, 1));

      expect(result, isA<BillingRestartPlan>());
      expect(await timeline(bookedEarly), [
        (d(7, 1), d(8, 1), true),
        (d(10, 1), d(11, 1), true),
      ]);
      expect((await cycles.forMember(bookedEarly))!.nextDueDate, d(11, 1));
    });

    test('free days inside the new first month become part of it', () async {
      // A member's shape: paid 18 Sep onto 1 Sep – 1 Oct, then six free
      // days a change of billing day left, then an unpaid month.
      final freeFold = await memberJoined(d(1, 1), anchorDay: 30);
      await cycle(freeFold, d(9, 1), d(10, 1), paidOn: DateTime(2026, 9, 18));
      final free = await cycle(freeFold, d(10, 1), d(10, 7), expected: 0);
      await (db.update(db.membershipPeriods)..where((p) => p.id.equals(free)))
          .write(MembershipPeriodsCompanion(settledAt: Value(d(10, 1))));
      await cycle(freeFold, d(10, 7), d(10, 30));

      final result = await cycles.restartBilling(
          memberId: freeFold, from: d(9, 18), today: d(10, 1));

      expect(result, isA<BillingRestartPlan>());
      expect(await timeline(freeFold), [(d(9, 18), d(10, 18), true)]);
    });

    test('free days are not folded into a month nobody has paid for',
        () async {
      // The same member again, restarted from today rather than their payment
      // day: the new month would be unpaid, so their free days must not
      // disappear in it.
      final freeDays = await memberJoined(d(1, 1));
      await cycle(freeDays, d(8, 1), d(9, 1), paidOn: DateTime(2026, 8, 21));
      final waiver = await cycle(freeDays, d(9, 1), d(10, 21), expected: 0);
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(waiver)))
          .write(MembershipPeriodsCompanion(settledAt: Value(d(9, 1))));

      final result = await cycles.previewRestart(
          memberId: freeDays, from: d(10, 1), today: d(10, 1));

      expect(result, isA<BillingRestartRefused>());
      expect((result as BillingRestartRefused).reason, contains('21 Oct 2026'));
    });

    test('free days that ended before the restart day stay as they were',
        () async {
      final member = await memberJoined(d(1, 1));
      await cycle(member, d(1, 1), d(2, 1), paidOn: DateTime(2026, 1, 1));
      final waiver = await cycle(member, d(2, 1), d(4, 1), expected: 0);
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(waiver)))
          .write(MembershipPeriodsCompanion(settledAt: Value(d(2, 1))));

      await cycles.restartBilling(
          memberId: member, from: d(5, 10), today: d(5, 10));

      expect(await timeline(member), [
        (d(1, 1), d(2, 1), true),
        (d(2, 1), d(4, 1), true),
        (d(5, 10), d(6, 10), false),
      ]);
    });

    test('a refusal changes nothing', () async {
      final before = await timeline(member);
      final result = await cycles.restartBilling(
          memberId: member, from: d(2, 15), today: d(3, 15));
      expect(result, isA<BillingRestartRefused>());
      expect(await timeline(member), before);
    });
  });
}
