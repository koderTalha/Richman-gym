import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/domain/payment_inactivity.dart';
import 'package:rich_man_fitness/domain/payment_settlement.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/payment_inactivity_service.dart';
import 'package:rich_man_fitness/services/startup_maintenance.dart';

/// Deactivating a member whose last month has gone 40 days unpaid, and
/// writing off what that lapse billed.
///
/// The owner's example throughout: paid for September, due again on
/// 1 October, nothing paid — deactivated on 10 November, October and the days
/// of November written off, September untouched.
void main() {
  DateTime d(int month, int day, [int year = 2026]) =>
      DateTime.utc(year, month, day);

  const fee = 250000;

  SettleableCycle bill(DateTime start, DateTime end,
          {int paid = 0, int expected = fee}) =>
      SettleableCycle(
        periodId: start.millisecondsSinceEpoch,
        start: start,
        end: end,
        expectedMinor: expected,
        collectedMinor: paid,
      );

  SettleableCycle month(int m, {int paid = 0}) =>
      bill(d(m, 1), d(m + 1, 1), paid: paid);

  group('The rule', () {
    test('the gym calendar is Pakistan time, whatever the machine says', () {
      expect(gymDateOf(DateTime.utc(2026, 11, 9, 18, 59)), d(11, 9));
      expect(gymDateOf(DateTime.utc(2026, 11, 9, 19)), d(11, 10));
    });

    test('September paid, October unpaid: grace until 9 November, '
        'lapsed on the 10th', () {
      final cycles = [month(9, paid: fee), month(10), month(11)];

      final before =
          assessPaymentInactivity(cycles: cycles, today: d(11, 9));
      expect(before, isA<PaymentInactivityGrace>());
      expect((before as PaymentInactivityGrace).deadline, d(11, 10));

      final on = assessPaymentInactivity(cycles: cycles, today: d(11, 10));
      expect(on, isA<PaymentInactivityLapsed>());
      final lapsed = on as PaymentInactivityLapsed;
      expect(lapsed.firstMissedDue, d(10, 1));
      expect(lapsed.lastPaidUntil, d(10, 1));
      expect(lapsed.toWaive.map((c) => c.start), [d(10, 1), d(11, 1)]);
      expect(lapsed.waivedMinor, 2 * fee);
      expect(lapsed.olderArrearsMinor, 0);
    });

    test('October paid before the deadline: nothing to judge', () {
      final cycles = [month(9, paid: fee), month(10, paid: fee), month(11)];
      expect(assessPaymentInactivity(cycles: cycles, today: d(11, 10)),
          isA<PaymentInactivityNone>());
    });

    test('paid September to November in advance: nothing to judge', () {
      final cycles = [
        month(9, paid: fee),
        month(10, paid: fee),
        month(11, paid: fee),
      ];
      expect(assessPaymentInactivity(cycles: cycles, today: d(11, 10)),
          isA<PaymentInactivityNone>());
    });

    test('October part-paid: left for review, never written off', () {
      final cycles = [month(9, paid: fee), month(10, paid: 100000), month(11)];
      final verdict =
          assessPaymentInactivity(cycles: cycles, today: d(11, 10));
      expect(verdict, isA<PaymentInactivityReview>());
      expect((verdict as PaymentInactivityReview).reason,
          InactivityReviewReason.partPaid);
    });

    test('never paid a month: left for review', () {
      final cycles = [month(10), month(11)];
      final verdict =
          assessPaymentInactivity(cycles: cycles, today: d(11, 10));
      expect(verdict, isA<PaymentInactivityReview>());
      expect((verdict as PaymentInactivityReview).reason,
          InactivityReviewReason.neverPaid);
    });

    test('a new member whose first month has not ended: nothing to judge', () {
      expect(assessPaymentInactivity(cycles: [month(11)], today: d(11, 20)),
          isA<PaymentInactivityNone>());
      expect(assessPaymentInactivity(cycles: const [], today: d(11, 20)),
          isA<PaymentInactivityNone>());
    });

    test('paid November while owing October: arrears, not a lapse', () {
      final cycles = [month(9, paid: fee), month(10), month(11, paid: fee)];
      expect(assessPaymentInactivity(cycles: cycles, today: d(11, 20)),
          isA<PaymentInactivityNone>());
    });

    test('looks back one month only: September and October unpaid counts '
        'from October', () {
      final cycles = [month(8, paid: fee), month(9), month(10), month(11)];

      // September + 40 days was 11 October, long gone. October's deadline is
      // what matters.
      expect(assessPaymentInactivity(cycles: cycles, today: d(11, 9)),
          isA<PaymentInactivityGrace>());

      final verdict =
          assessPaymentInactivity(cycles: cycles, today: d(11, 10));
      final lapsed = verdict as PaymentInactivityLapsed;
      expect(lapsed.firstMissedDue, d(10, 1));
      expect(lapsed.toWaive.map((c) => c.start), [d(10, 1), d(11, 1)]);
      // September stays owing.
      expect(lapsed.olderArrearsMinor, fee);
    });

    test('free months are neither a bill nor a payment', () {
      final cycles = [
        month(7, paid: fee),
        // The ledger import's cover until the first bill.
        bill(d(8, 1), d(10, 1), expected: 0, paid: 0),
        month(10),
        month(11),
      ];
      final lapsed = assessPaymentInactivity(cycles: cycles, today: d(11, 10))
          as PaymentInactivityLapsed;
      expect(lapsed.toWaive.map((c) => c.start), [d(10, 1), d(11, 1)]);
      expect(lapsed.lastPaidUntil, d(8, 1));
    });

    test('a 55-day threshold: due 1 October, deactivated 25 November', () {
      final cycles = [month(9, paid: fee), month(10), month(11)];
      expect(
          assessPaymentInactivity(
              cycles: cycles, today: d(11, 24), graceDays: 55),
          isA<PaymentInactivityGrace>());
      expect(
          assessPaymentInactivity(
              cycles: cycles, today: d(11, 25), graceDays: 55),
          isA<PaymentInactivityLapsed>());
    });

    test('every threshold offered is reached even after February', () {
      // The tightest case: January's bill stops being judged on 1 March.
      final cycles = [
        bill(d(12, 1, 2026), d(1, 1, 2027), paid: fee),
        bill(d(1, 1, 2027), d(2, 1, 2027)),
        bill(d(2, 1, 2027), d(3, 1, 2027)),
      ];
      for (final days in inactivityGraceDayChoices) {
        final deadline = d(1, 1, 2027).add(Duration(days: days));
        expect(
            assessPaymentInactivity(
                cycles: cycles, today: deadline, graceDays: days),
            isA<PaymentInactivityLapsed>(),
            reason: '$days days');
      }
    });

    test('billed on the 25th: due 25 October, deactivated 4 December', () {
      final cycles = [
        bill(d(9, 25), d(10, 25), paid: fee),
        bill(d(10, 25), d(11, 25)),
        bill(d(11, 25), d(12, 25)),
      ];
      expect(assessPaymentInactivity(cycles: cycles, today: d(12, 3)),
          isA<PaymentInactivityGrace>());
      expect(assessPaymentInactivity(cycles: cycles, today: d(12, 4)),
          isA<PaymentInactivityLapsed>());
    });
  });

  group('The service', () {
    late AppDatabase db;
    late MemberRepository members;
    late PaymentInactivityService service;
    late int adminId;
    late int monthlyId;
    var keys = 0;
    var phones = 0;

    // 10 November 00:00 in Lahore, and the minute before it.
    final deadline = DateTime.utc(2026, 11, 9, 19);
    final justBefore = DateTime.utc(2026, 11, 9, 18, 59);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedDatabase(db);
      members = MemberRepository(db);
      service = PaymentInactivityService(db);
      adminId = (await db.select(db.users).getSingle()).id;
      monthlyId = (await (db.select(db.membershipPlans)
                ..where((p) => p.name.equals('Monthly')))
              .getSingle())
          .id;
      await service.setEnabled(true);
    });

    tearDown(() async => db.close());

    Future<int> member(String name) => members.create(
          fullName: name,
          phone: '+92300000${(1000 + phones++).toString()}',
          planId: monthlyId,
          feeOverrideMinor: fee,
          joiningDate: d(9, 1),
        );

    /// A cycle row, with [paid] allocated to it on [paidOn].
    Future<int> cycle(int memberId, DateTime start, DateTime end,
        {int paid = 0, DateTime? paidOn}) async {
      final membership = (await openMembershipFor(db, memberId))!;
      final period = await db.into(db.membershipPeriods).insertReturning(
            MembershipPeriodsCompanion.insert(
              membershipId: membership.id,
              periodStart: start,
              periodEnd: end,
              expectedAmountMinor: fee,
            ),
          );
      if (paid > 0) {
        final paymentId = await db.into(db.payments).insert(
              PaymentsCompanion.insert(
                memberId: memberId,
                membershipPeriodId: Value(period.id),
                amountMinor: paid,
                method: PaymentMethod.cash,
                paymentDate: paidOn ?? start,
                recordedById: adminId,
                idempotencyKey: 'k${keys++}',
              ),
            );
        await db.into(db.paymentAllocations).insert(
              PaymentAllocationsCompanion.insert(
                paymentId: paymentId,
                membershipPeriodId: period.id,
                amountMinor: paid,
              ),
            );
        if (paid >= fee) {
          await (db.update(db.membershipPeriods)
                ..where((p) => p.id.equals(period.id)))
              .write(MembershipPeriodsCompanion(settledAt: Value(start)));
        }
      }
      return period.id;
    }

    Future<MembershipPeriod?> period(int id) =>
        (db.select(db.membershipPeriods)..where((p) => p.id.equals(id)))
            .getSingleOrNull();

    Future<Member> reload(int id) =>
        (db.select(db.members)..where((m) => m.id.equals(id))).getSingle();

    /// Paid September, owes October, and the roll has opened November.
    Future<({int id, int sep, int oct})> lapsingMember(String name) async {
      final id = await member(name);
      final sep = await cycle(id, d(9, 1), d(10, 1), paid: fee);
      final oct = await cycle(id, d(10, 1), d(11, 1));
      return (id: id, sep: sep, oct: oct);
    }

    test('the owner\'s example, end to end', () async {
      final m = await lapsingMember('Ali Lapsed');
      final paymentsBefore = await db.select(db.payments).get();

      // The roll opens November on the 1st; the member stays active through
      // the grace period.
      await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
      await runStartupMaintenance(db, now: justBefore);
      expect((await reload(m.id)).deactivatedAt, isNull);
      final nov = (await periodsForMember(db, m.id)).last;
      expect(nov.periodStart.toUtc(), d(11, 1));

      await runStartupMaintenance(db, now: deadline);

      // 1. Inactive.
      expect((await reload(m.id)).deactivatedAt, isNotNull);

      // 2. Recorded as payment inactivity, with the dates kept apart.
      final episode = (await service.historyFor(m.id)).single;
      expect(episode.row.reason, paymentInactivityReason);
      expect(episode.row.firstMissedDue.toUtc(), d(10, 1));
      expect(episode.row.deactivatedOn.toUtc(), d(11, 10));
      expect(episode.row.lastPaidUntil!.toUtc(), d(10, 1));
      expect(episode.row.waivedMinor, 2 * fee);
      expect(episode.isOpen, isTrue);

      // 3. October written off, its original bill kept.
      final oct = (await period(m.oct))!;
      expect(oct.expectedAmountMinor, 0);
      expect(oct.settledAt, isNotNull);
      expect(episode.waivers.map((w) => w.amountMinor), [fee, fee]);
      expect(episode.waivers.first.periodStart.toUtc(), d(10, 1));
      final octPricing = await (db.select(db.cyclePricings)
            ..where((p) =>
                p.membershipPeriodId.equals(m.oct) &
                p.source.equalsValue(CyclePricingSource.inactivityWaiver)))
          .getSingle();
      expect(octPricing.previousAmountMinor, fee);

      // 4. November written off too, and cut short on the day.
      final novAfter = (await period(nov.id))!;
      expect(novAfter.expectedAmountMinor, 0);
      expect(novAfter.periodEnd.toUtc(), d(11, 10));
      expect(episode.waivers.last.periodEnd.toUtc(), d(12, 1));

      // 6. September and every payment untouched.
      final sep = (await period(m.sep))!;
      expect(sep.expectedAmountMinor, fee);
      expect(sep.settledAt, isNotNull);
      final paymentsAfter = await db.select(db.payments).get();
      expect(paymentsAfter.length, paymentsBefore.length);
      expect(paymentsAfter.map((p) => p.amountMinor),
          paymentsBefore.map((p) => p.amountMinor));

      // Nothing owed, and the list knows why they are inactive.
      final row = (await members.byId(m.id, now: deadline))!;
      expect(row.status, MemberStatus.inactive);
      expect(row.arrearsMinor, 0);
      expect(row.missedPaymentDeactivation, isNotNull);
      final counts = await members.filterCounts(now: deadline);
      expect(counts[MemberFilter.missedPayments], 1);

      final events = await (db.select(db.auditEvents)
            ..where((e) => e.action
                .equals(AuditAction.memberDeactivatedForMissedPayments)))
          .get();
      expect(events.single.amountMinor, 2 * fee);

      // 5. No more months accumulate while they are away.
      final cyclesBefore = (await periodsForMember(db, m.id)).length;
      await runStartupMaintenance(db, now: DateTime.utc(2026, 12, 15, 6));
      await runStartupMaintenance(db, now: DateTime.utc(2027, 1, 15, 6));
      expect((await periodsForMember(db, m.id)).length, cyclesBefore);
    });

    test('7. the owner reactivates them with a fresh start; nothing written '
        'off comes back', () async {
      final m = await lapsingMember('Bilal Returns');
      await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
      await runStartupMaintenance(db, now: deadline);

      await members.setActive(m.id, true, actorId: adminId);
      final restart = await BillingCycleService(db).restartBilling(
        memberId: m.id,
        from: d(12, 5),
        actorId: adminId,
        today: d(12, 5),
      );
      expect(restart, isA<BillingRestartPlan>());

      expect((await reload(m.id)).deactivatedAt, isNull);
      final episode = (await service.historyFor(m.id)).single;
      expect(episode.isOpen, isFalse);
      expect(episode.row.reactivatedById, adminId);

      // October stays written off; the only debt is the month they came back.
      expect((await period(m.oct))!.expectedAmountMinor, 0);
      final row = (await members.byId(m.id, now: d(12, 6)))!;
      expect(row.arrearsMinor, fee);
      expect(row.missedPaymentDeactivation, isNull);
      final last = (await periodsForMember(db, m.id)).last;
      expect(last.periodStart.toUtc(), d(12, 5));
      expect(last.periodEnd.toUtc(), d(1, 5, 2027));
    });

    test('a member back a week after being deactivated can restart that day',
        () async {
      final m = await lapsingMember('Back Soon');
      await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
      await runStartupMaintenance(db, now: deadline);

      await members.setActive(m.id, true, actorId: adminId);
      final restart = await BillingCycleService(db).restartBilling(
        memberId: m.id,
        from: d(11, 17),
        today: d(11, 17),
      );
      expect(restart, isA<BillingRestartPlan>());
    });

    test('switched off: deactivates nobody, but the preview names them',
        () async {
      await service.setEnabled(false);
      final m = await lapsingMember('Not Yet');

      await runStartupMaintenance(db, now: deadline);
      expect((await reload(m.id)).deactivatedAt, isNull);
      expect((await period(m.oct))!.expectedAmountMinor, fee);

      final preview = await service.preview(now: deadline);
      expect(preview.lapsed.map((c) => c.member.id), [m.id]);
      // October, and the November the roll has just opened.
      expect(preview.waivedMinor, 2 * fee);
    });

    test('2. paid before the deadline: stays active', () async {
      final id = await member('Paid Late');
      await cycle(id, d(9, 1), d(10, 1), paid: fee);
      await cycle(id, d(10, 1), d(11, 1), paid: fee, paidOn: d(11, 8));

      await service.run(now: deadline);
      expect((await reload(id)).deactivatedAt, isNull);
    });

    test('4. part-paid: stays active, listed for review', () async {
      final id = await member('Part Payer');
      await cycle(id, d(9, 1), d(10, 1), paid: fee);
      final oct = await cycle(id, d(10, 1), d(11, 1), paid: 100000);

      await service.run(now: deadline);
      expect((await reload(id)).deactivatedAt, isNull);
      expect((await period(oct))!.expectedAmountMinor, fee);

      final review = (await service.preview(now: deadline)).review.single;
      expect(review.member.id, id);
      expect((review.verdict as PaymentInactivityReview).reason,
          InactivityReviewReason.partPaid);
    });

    test('9. never paid: stays active, listed for review', () async {
      final id = await member('Never Paid');
      await cycle(id, d(10, 1), d(11, 1));

      await service.run(now: deadline);
      expect((await reload(id)).deactivatedAt, isNull);
      expect((await service.preview(now: deadline)).review.single.member.id,
          id);
    });

    test('5. a member the owner deactivated is left exactly as they were',
        () async {
      final m = await lapsingMember('Left By Hand');
      await members.setActive(m.id, false, actorId: adminId);
      final stamp = (await reload(m.id)).deactivatedAt;

      await service.run(now: deadline);
      expect((await reload(m.id)).deactivatedAt, stamp);
      expect(await service.historyFor(m.id), isEmpty);
      expect((await period(m.oct))!.expectedAmountMinor, fee);
    });

    test('7. running again, or twice at once, changes nothing more', () async {
      final m = await lapsingMember('Run Twice');

      final both = await Future.wait([
        service.run(now: deadline),
        service.run(now: deadline),
        // A second instance, as startup maintenance and the hourly tick are.
        PaymentInactivityService(db).run(now: deadline),
      ]);
      // The two calls on one instance share a single run and its answer; the
      // other instance finds the member already deactivated.
      expect(identical(both[0], both[1]), isTrue);
      expect(both[0].single.member.id, m.id);
      expect(both[2], isEmpty);

      await service.run(now: deadline.add(const Duration(days: 3)));
      expect((await service.historyFor(m.id)).length, 1);
      expect(await db.select(db.inactivityWaivers).get(), hasLength(1));
      final events = await (db.select(db.auditEvents)
            ..where((e) => e.action
                .equals(AuditAction.memberDeactivatedForMissedPayments)))
          .get();
      expect(events, hasLength(1));
    });

    test('a payment recorded after the preview keeps the member active',
        () async {
      final m = await lapsingMember('Pays In Time');
      final preview = await service.preview(now: deadline);
      expect(preview.lapsed, hasLength(1));

      // Paid between the preview being read and the run reaching them.
      final paymentId = await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              memberId: m.id,
              membershipPeriodId: Value(m.oct),
              amountMinor: fee,
              method: PaymentMethod.cash,
              paymentDate: deadline,
              recordedById: adminId,
              idempotencyKey: 'late',
            ),
          );
      await db.into(db.paymentAllocations).insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              membershipPeriodId: m.oct,
              amountMinor: fee,
            ),
          );

      await service.run(now: deadline);
      expect((await reload(m.id)).deactivatedAt, isNull);
    });

    test('8. a payment taken after the write-off is flagged, nothing undone',
        () async {
      final m = await lapsingMember('Pays After');
      await service.run(now: deadline);

      final paymentId = await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              memberId: m.id,
              amountMinor: fee,
              method: PaymentMethod.cash,
              paymentDate: deadline.add(const Duration(days: 2)),
              recordedById: adminId,
              idempotencyKey: 'after',
            ),
          );
      await flagPaymentAfterWaiver(db,
          memberId: m.id, paymentId: paymentId, amountMinor: fee);

      final flag = await (db.select(db.auditEvents)
            ..where((e) =>
                e.action.equals(AuditAction.paymentAfterMissedPaymentWaiver)))
          .getSingle();
      expect(flag.paymentId, paymentId);
      expect((await reload(m.id)).deactivatedAt, isNotNull);
      expect((await period(m.oct))!.expectedAmountMinor, 0);
    });

    test('a payment from an active member is never flagged', () async {
      final id = await member('Ordinary');
      await flagPaymentAfterWaiver(db,
          memberId: id, paymentId: 1, amountMinor: fee);
      expect(
          await (db.select(db.auditEvents)
                ..where((e) => e.action
                    .equals(AuditAction.paymentAfterMissedPaymentWaiver)))
              .get(),
          isEmpty);
    });

    /// Where [amount] taken today would go, oldest first.
    Future<List<(DateTime, DateTime, int)>> wouldSettle(
        int memberId, int amount) async {
      final cycles = BillingCycleService(db);
      final billing = (await cycles.forMember(memberId))!;
      final plan = allocate(
          amountMinor: amount,
          cycles: cycles.settleableFor(billing: billing, amountMinor: amount));
      return [
        for (final a in plan.allocations)
          (a.cycle.start, a.cycle.end, a.amountMinor),
      ];
    }

    group('kept coming, paid late', () {
      test('reinstating takes the write-off back so Oct + Nov settles Oct and '
          'Nov', () async {
        final m = await lapsingMember('Kept Coming');
        await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
        await runStartupMaintenance(db, now: deadline);
        expect((await reload(m.id)).deactivatedAt, isNotNull);

        final result = await service.reinstate(
            memberId: m.id,
            actorId: adminId,
            now: DateTime.utc(2026, 11, 12, 6));
        expect(result, isA<MemberReinstated>());
        expect((result as MemberReinstated).restoredMinor, 2 * fee);

        expect((await reload(m.id)).deactivatedAt, isNull);
        final oct = (await period(m.oct))!;
        expect(oct.expectedAmountMinor, fee);
        expect(oct.settledAt, isNull);
        final nov = (await periodsForMember(db, m.id)).last;
        expect(nov.periodStart.toUtc(), d(11, 1));
        expect(nov.periodEnd.toUtc(), d(12, 1), reason: 'no longer cut short');
        expect(nov.expectedAmountMinor, fee);

        // The owner's Rs 5,000 for October and November lands on them.
        expect(await wouldSettle(m.id, 2 * fee), [
          (d(10, 1), d(11, 1), fee),
          (d(11, 1), d(12, 1), fee),
        ]);

        final episode = (await service.historyFor(m.id)).single;
        expect(episode.isOpen, isFalse);
        expect(episode.row.reinstated, isTrue);
        expect(
            await (db.select(db.auditEvents)
                  ..where((e) => e.action.equals(AuditAction.memberReinstated)))
                .get(),
            hasLength(1));
        expect(
            (await members.byId(m.id, now: DateTime.utc(2026, 11, 12, 6)))!
                .arrearsMinor,
            2 * fee);
      });

      test('the same unpaid October never deactivates them a second time',
          () async {
        final m = await lapsingMember('Not Twice');
        await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
        await runStartupMaintenance(db, now: deadline);
        await service.reinstate(memberId: m.id, now: deadline);

        // The owner reinstated them and then did not take the money.
        await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 20, 6));
        expect((await reload(m.id)).deactivatedAt, isNull);
        expect((await service.preview(now: DateTime.utc(2026, 11, 20, 6)))
            .lapsed, isEmpty);
      });

      test('paying October only: November was put back with the '
          'reinstatement, so the next lapse counts from December', () async {
        final m = await lapsingMember('Pays October');
        await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
        await runStartupMaintenance(db, now: deadline);
        await service.reinstate(memberId: m.id, now: deadline);

        final paymentId = await db.into(db.payments).insert(
              PaymentsCompanion.insert(
                memberId: m.id,
                membershipPeriodId: Value(m.oct),
                amountMinor: fee,
                method: PaymentMethod.cash,
                paymentDate: d(11, 12),
                recordedById: adminId,
                idempotencyKey: 'oct',
              ),
            );
        await db.into(db.paymentAllocations).insert(
              PaymentAllocationsCompanion.insert(
                paymentId: paymentId,
                membershipPeriodId: m.oct,
                amountMinor: fee,
              ),
            );
        await BillingCycleService(db).refreshSettlement(m.oct);

        // 1 November + 40 days: November was due before the owner said the
        // member was here, so it does not count.
        await runStartupMaintenance(db, now: DateTime.utc(2026, 12, 10, 19));
        expect((await reload(m.id)).deactivatedAt, isNull);
        // 1 December + 40 days: the first bill due after coming back.
        await runStartupMaintenance(db, now: DateTime.utc(2027, 1, 9, 18));
        expect((await reload(m.id)).deactivatedAt, isNull);
        await runStartupMaintenance(db, now: DateTime.utc(2027, 1, 9, 19));
        expect((await reload(m.id)).deactivatedAt, isNotNull);
        final second = (await service.historyFor(m.id)).first;
        expect(second.row.firstMissedDue.toUtc(), d(12, 1));
        // November stays owing, as older arrears.
        expect(second.row.olderArrearsMinor, fee);
      });

      /// Pays [periodId] in full on [on].
      Future<void> pay(int memberId, int periodId, DateTime on) async {
        final paymentId = await db.into(db.payments).insert(
              PaymentsCompanion.insert(
                memberId: memberId,
                membershipPeriodId: Value(periodId),
                amountMinor: fee,
                method: PaymentMethod.cash,
                paymentDate: on,
                recordedById: adminId,
                idempotencyKey: 'p${keys++}',
              ),
            );
        await db.into(db.paymentAllocations).insert(
              PaymentAllocationsCompanion.insert(
                paymentId: paymentId,
                membershipPeriodId: periodId,
                amountMinor: fee,
              ),
            );
        await BillingCycleService(db).refreshSettlement(periodId);
      }

      test('reinstated weeks later and paying October only: November, put '
          'back with it, does not deactivate them again', () async {
        final m = await lapsingMember('Late Return');
        await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
        await runStartupMaintenance(db, now: deadline);

        final back = DateTime.utc(2026, 12, 20, 6);
        await service.reinstate(memberId: m.id, now: back);
        await pay(m.id, m.oct, d(12, 20));

        await runStartupMaintenance(db, now: back);
        await runStartupMaintenance(db, now: DateTime.utc(2026, 12, 21, 6));
        expect((await reload(m.id)).deactivatedAt, isNull);
        expect(await service.historyFor(m.id), hasLength(1));

        // The first bill due after coming back is judged as anyone's.
        await runStartupMaintenance(db, now: DateTime.utc(2027, 1, 5, 6));
        await runStartupMaintenance(db, now: DateTime.utc(2027, 2, 9, 18));
        expect((await reload(m.id)).deactivatedAt, isNull);
        await runStartupMaintenance(db, now: DateTime.utc(2027, 2, 9, 19));
        expect((await reload(m.id)).deactivatedAt, isNotNull);
        expect((await service.historyFor(m.id)).first.row.firstMissedDue.toUtc(),
            d(1, 1, 2027));
      });

      test('paid until moves on once the restored months are paid', () async {
        final m = await lapsingMember('Pays Both');
        await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
        await runStartupMaintenance(db, now: deadline);
        await service.reinstate(memberId: m.id, now: deadline);

        final nov = (await periodsForMember(db, m.id)).last;
        await pay(m.id, m.oct, d(11, 12));
        await pay(m.id, nov.id, d(11, 12));

        final row = (await members.byId(m.id, now: DateTime.utc(2026, 11, 12, 6)))!;
        expect(row.status, MemberStatus.paid);
        expect(row.paidUntil!.toUtc(), d(12, 1));
      });

      test('a month that has ended reads the same before and after a later '
          'write-off', () async {
        final m = await lapsingMember('Report Stable');
        await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
        final endOfOctober = DateTime.utc(2026, 10, 31, 18);

        MemberRow mine(List<MemberRow> rows) =>
            rows.firstWhere((r) => r.id == m.id);
        final before = mine(await members.listAsOf(endOfOctober));
        await runStartupMaintenance(db, now: deadline);
        final after = mine(await members.listAsOf(endOfOctober));

        expect(before.status, MemberStatus.due);
        expect(after.status, before.status);
        expect(after.arrearsMinor, before.arrearsMinor);
        expect(after.arrearsMinor, fee);

        // Today's view is the written-off one.
        expect((await members.byId(m.id, now: deadline))!.arrearsMinor, 0);
      });

      test('a bill the write-off removed is put back', () async {
        final id = await member('Removed Bill');
        await cycle(id, d(9, 1), d(10, 1), paid: fee);
        await cycle(id, d(10, 1), d(11, 10));
        // Starts on the deactivation day, so the write-off deletes it.
        await cycle(id, d(11, 10), d(12, 10));

        await service.run(now: deadline);
        expect(await periodsForMember(db, id), hasLength(2));

        expect(await service.reinstate(memberId: id, now: deadline),
            isA<MemberReinstated>());
        final restored = (await periodsForMember(db, id)).last;
        expect(restored.periodStart.toUtc(), d(11, 10));
        expect(restored.periodEnd.toUtc(), d(12, 10));
        expect(restored.expectedAmountMinor, fee);
      });

      test('refused, with nothing changed, when months were billed over the '
          'write-off since', () async {
        final m = await lapsingMember('Billed Since');
        await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
        await runStartupMaintenance(db, now: deadline);
        // A payment taken without asking opened 10 Nov – 1 Dec.
        await cycle(m.id, d(11, 10), d(12, 1), paid: fee);

        final result = await service.reinstate(memberId: m.id, now: deadline);
        expect(result, isA<ReinstateRefused>());
        expect((await reload(m.id)).deactivatedAt, isNotNull);
        expect((await period(m.oct))!.expectedAmountMinor, 0);
        expect((await service.historyFor(m.id)).single.isOpen, isTrue);
      });
    });

    group('threshold and warning list', () {
      test('a longer threshold holds the member back; an invalid one is '
          'refused', () async {
        final m = await lapsingMember('Longer Grace');
        await service.setGraceDays(55, actorId: adminId);

        await service.run(now: deadline);
        expect((await reload(m.id)).deactivatedAt, isNull);
        await service.run(now: DateTime.utc(2026, 11, 24, 19));
        final episode = (await service.historyFor(m.id)).single;
        expect(episode.row.graceDays, 55);
        expect(episode.row.deactivatedOn.toUtc(), d(11, 25));

        expect(() => service.setGraceDays(90), throwsArgumentError);
        expect(await service.graceDays(), 55);
      });

      test('the week before, they are on the deactivating-soon list',
          () async {
        final m = await lapsingMember('Soon');
        final partId = await member('Part Soon');
        await cycle(partId, d(9, 1), d(10, 1), paid: fee);
        await cycle(partId, d(10, 1), d(11, 1), paid: 100000);

        // 8 days out: not yet.
        expect((await service.preview(now: DateTime.utc(2026, 11, 2, 6)))
            .upcoming, isEmpty);

        final soon = await service.preview(now: DateTime.utc(2026, 11, 4, 6));
        // The part-payer goes to review on the day, so is not warned about.
        expect(soon.upcoming.map((c) => c.member.id), [m.id]);
        expect((soon.upcoming.single.verdict as PaymentInactivityGrace)
            .deadline, d(11, 10));
      });
    });

    test('one member who cannot be processed does not stop the rest',
        () async {
      final broken = await lapsingMember('Broken Row');
      final fine = await lapsingMember('Fine Row');
      // A payment pointing at November with nothing allocated: the bill
      // cannot be removed, so this member's whole write-off rolls back.
      await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 1, 6));
      await service.setEnabled(false);
      final nov = (await periodsForMember(db, broken.id)).last;
      await db.into(db.payments).insert(PaymentsCompanion.insert(
            memberId: broken.id,
            membershipPeriodId: Value(nov.id),
            amountMinor: fee,
            method: PaymentMethod.cash,
            paymentDate: d(11, 1),
            recordedById: adminId,
            idempotencyKey: 'stray',
          ));
      // Starts on the deadline day, so the run removes it rather than
      // narrowing it.
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(nov.id)))
          .write(MembershipPeriodsCompanion(
              periodStart: Value(d(11, 10)), periodEnd: Value(d(12, 10))));

      await service.run(now: deadline, force: true);

      expect((await reload(broken.id)).deactivatedAt, isNull);
      expect((await period(broken.oct))!.expectedAmountMinor, fee);
      expect(await service.historyFor(broken.id), isEmpty);
      expect((await reload(fine.id)).deactivatedAt, isNotNull);
    });
  });
}
