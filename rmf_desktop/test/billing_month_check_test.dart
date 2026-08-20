import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/billing_month_check.dart';
import 'package:rich_man_fitness/domain/billing_period.dart';
import 'package:rich_man_fitness/services/billing_month_checker.dart';

/// The rules that stop money being recorded against the wrong month.
///
/// The owner types a month into a form dozens of times a week; the failure this
/// guards against is not exotic, it is picking September while thinking August.
void main() {
  // --- The rules themselves, no database involved --------------------------
  group('reviewBillingMonth', () {
    BillingMonthFacts facts({
      DateTime? selected,
      int durationMonths = 1,
      DateTime? joined,
      DateTime? today,
      List<UnpaidCycle> unpaid = const [],
      ExistingCyclePayment? existing,
    }) =>
        BillingMonthFacts(
          memberName: 'Ali Raza',
          cycleStart: selected ?? DateTime.utc(2026, 8, 1),
          durationMonths: durationMonths,
          joiningDate: joined ?? DateTime.utc(2026, 1, 1),
          today: today ?? DateTime(2026, 8, 20),
          unpaidEarlierCycles: unpaid,
          existingPayment: existing,
        );

    test('a normal current month raises nothing', () {
      final review = reviewBillingMonth(facts());

      expect(review.isClean, isTrue);
      expect(review.isBlocked, isFalse);
      expect(review.needsConfirmation, isFalse);
    });

    test('a month before the member joined is blocked, not confirmable', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2025, 11, 1),
        joined: DateTime.utc(2026, 1, 15),
      ));

      expect(review.isBlocked, isTrue);
      expect(review.blocking.single.issue, BillingMonthIssue.beforeJoining);
      expect(review.blocking.single.message,
          'Ali Raza joined in January 2026, so November 2025 is before their '
          'membership started.');
    });

    test('the joining month itself is allowed', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 1, 1),
        joined: DateTime.utc(2026, 1, 20),
      ));

      expect(review.isClean, isTrue,
          reason: 'joining mid-month still owes that month');
    });

    test('one unpaid earlier cycle reads in the singular', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 9, 1),
        unpaid: [
          UnpaidCycle(
              periodStart: DateTime.utc(2026, 8, 1), durationMonths: 1),
        ],
      ));

      expect(review.needsConfirmation, isTrue);
      expect(review.confirmations.single.message,
          'August 2026 is still unpaid.');
    });

    test('two unpaid cycles are joined with "and"', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 10, 1),
        today: DateTime(2026, 10, 5),
        unpaid: [
          UnpaidCycle(
              periodStart: DateTime.utc(2026, 9, 1), durationMonths: 1),
          UnpaidCycle(
              periodStart: DateTime.utc(2026, 8, 1), durationMonths: 1),
        ],
      ));

      expect(review.confirmations.single.message,
          'August 2026 and September 2026 are still unpaid.',
          reason: 'named oldest first regardless of the order read');
    });

    test('more than three unpaid cycles are summarised', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 8, 1),
        joined: DateTime.utc(2026, 1, 1),
        unpaid: [
          for (var month = 2; month <= 7; month++)
            UnpaidCycle(
                periodStart: DateTime.utc(2026, month, 1), durationMonths: 1),
        ],
      ));

      expect(
        review.confirmations.single.message,
        'February 2026, March 2026 and April 2026 (and 3 earlier cycles) are '
        'still unpaid.',
      );
    });

    test('an unpaid cycle after the selected month is not mentioned', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 8, 1),
        unpaid: [
          UnpaidCycle(
              periodStart: DateTime.utc(2026, 9, 1), durationMonths: 1),
        ],
      ));

      expect(review.isClean, isTrue,
          reason: 'paying August while September is open is not a mistake');
    });

    test('one month in advance is normal on a monthly plan', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 9, 1),
        today: DateTime(2026, 8, 20),
      ));

      expect(review.isClean, isTrue);
    });

    test('two months ahead asks for confirmation on a monthly plan', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 10, 1),
        today: DateTime(2026, 8, 20),
      ));

      expect(review.confirmations.single.issue, BillingMonthIssue.farFuture);
      expect(review.confirmations.single.message,
          'October 2026 is more than one billing cycle ahead of August 2026.');
    });

    test('the far-future rule stretches with the plan length', () {
      // November is three months out, which is exactly one cycle for a
      // quarterly member and therefore unremarkable.
      final quarterly = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 11, 1),
        durationMonths: 3,
        today: DateTime(2026, 8, 20),
      ));
      expect(quarterly.isClean, isTrue);

      final monthly = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 11, 1),
        today: DateTime(2026, 8, 20),
      ));
      expect(monthly.issues, contains(BillingMonthIssue.farFuture));
    });

    test('money already on the cycle asks for confirmation', () {
      final review = reviewBillingMonth(facts(
        existing: ExistingCyclePayment(
          amountMinor: 500000,
          paymentDate: DateTime(2026, 8, 3),
        ),
      ));

      expect(review.confirmations.single.issue,
          BillingMonthIssue.duplicatePayment);
      expect(review.confirmations.single.message,
          'A payment of Rs. 5,000 is already recorded for August 2026.');
    });

    test('several confirmations arrive together, not one at a time', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2026, 12, 1),
        today: DateTime(2026, 8, 20),
        unpaid: [
          UnpaidCycle(
              periodStart: DateTime.utc(2026, 8, 1), durationMonths: 1),
        ],
        existing: ExistingCyclePayment(
          amountMinor: 300000,
          paymentDate: DateTime(2026, 12, 1),
        ),
      ));

      expect(review.confirmations.length, 3);
      expect(
        review.issues,
        containsAll([
          BillingMonthIssue.unpaidEarlierCycles,
          BillingMonthIssue.farFuture,
          BillingMonthIssue.duplicatePayment,
        ]),
      );
    });

    test('a blocked month does not also queue a confirmation dialog', () {
      final review = reviewBillingMonth(facts(
        selected: DateTime.utc(2025, 1, 1),
        joined: DateTime.utc(2026, 1, 1),
        existing: ExistingCyclePayment(
          amountMinor: 300000,
          paymentDate: DateTime(2025, 1, 1),
        ),
      ));

      expect(review.isBlocked, isTrue);
      expect(review.confirmations, isNotEmpty,
          reason: 'the finding is still recorded for the audit trail');
      expect(review.needsConfirmation, isFalse,
          reason: 'but the owner is never asked to confirm an impossible month');
    });
  });

  // --- Plan-length labels, the bug behind "August 2026" on a 3-month plan ---
  group('billing period labels', () {
    final august = DateTime.utc(2026, 8, 1);

    test('a one-month cycle names one month', () {
      expect(formatBillingPeriod(august, 1), 'August 2026');
    });

    test('a three-month cycle names both ends', () {
      expect(formatBillingPeriod(august, 3), 'August 2026 - October 2026');
    });

    test('a six-month cycle crosses into the next year correctly', () {
      expect(formatBillingPeriod(august, 6), 'August 2026 - January 2027');
    });

    test('a twelve-month cycle ends the month before, a year on', () {
      expect(formatBillingPeriod(august, 12), 'August 2026 - July 2027');
    });
  });

  // --- The same rules against real data -----------------------------------
  group('BillingMonthChecker', () {
    late AppDatabase db;
    late BillingMonthChecker checker;
    late int adminId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedDatabase(db);
      checker = BillingMonthChecker(db);
      adminId = (await db.select(db.users).getSingle()).id;
    });

    tearDown(() => db.close());

    Future<int> planNamed(String name) async =>
        (await (db.select(db.membershipPlans)..where((p) => p.name.equals(name)))
                .getSingle())
            .id;

    Future<int> newMember({
      required String plan,
      DateTime? joined,
      String phone = '+923000000001',
    }) async =>
        MemberRepository(db).create(
          fullName: 'Ali Raza',
          phone: phone,
          planId: await planNamed(plan),
          joiningDate: joined ?? DateTime.utc(2026, 1, 1),
        );

    /// Inserts a cycle and, optionally, money against it — the shape the
    /// database is in after a payment has been recorded.
    Future<int> addCycle(
      int memberId, {
      required DateTime start,
      required int durationMonths,
      int? paidMinor,
      String idempotencyKey = 'seeded-1',
    }) async {
      final membership = await (db.select(db.memberships)
            ..where((m) => m.memberId.equals(memberId)))
          .getSingle();

      final period = await db.into(db.membershipPeriods).insertReturning(
            MembershipPeriodsCompanion.insert(
              membershipId: membership.id,
              periodStart: start,
              periodEnd: DateTime.utc(
                  start.year, start.month + durationMonths, 1),
              expectedAmountMinor: 300000,
            ),
          );

      if (paidMinor != null) {
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              memberId: memberId,
              membershipPeriodId: Value(period.id),
              amountMinor: paidMinor,
              method: PaymentMethod.cash,
              paymentDate: start,
              recordedById: adminId,
              idempotencyKey: idempotencyKey,
            ));
      }
      return period.id;
    }

    test('a fresh month on a member in good standing is clean', () async {
      final memberId = await newMember(plan: 'Monthly');
      await addCycle(memberId,
          start: DateTime.utc(2026, 7, 1), durationMonths: 1, paidMinor: 300000);

      final check = await checker.check(
        memberId: memberId,
        billingMonth: '2026-08',
        now: DateTime(2026, 8, 20),
      );

      expect(check.review.isClean, isTrue);
      expect(check.hasPlan, isTrue);
      expect(check.durationMonths, 1);
      expect(check.period, isNull, reason: 'August has no cycle yet');
    });

    test('a month before the joining date is blocked', () async {
      final memberId =
          await newMember(plan: 'Monthly', joined: DateTime.utc(2026, 6, 10));

      final check = await checker.check(
        memberId: memberId,
        billingMonth: '2026-04',
        now: DateTime(2026, 8, 20),
      );

      expect(check.review.isBlocked, isTrue);
      expect(check.review.blocking.single.issue,
          BillingMonthIssue.beforeJoining);
    });

    test('unpaid earlier cycles are found across the whole history', () async {
      final memberId = await newMember(plan: 'Monthly');
      await addCycle(memberId,
          start: DateTime.utc(2026, 6, 1), durationMonths: 1);
      await addCycle(memberId,
          start: DateTime.utc(2026, 7, 1), durationMonths: 1);

      final check = await checker.check(
        memberId: memberId,
        billingMonth: '2026-08',
        now: DateTime(2026, 8, 20),
      );

      expect(check.review.issues,
          contains(BillingMonthIssue.unpaidEarlierCycles));
      expect(check.review.confirmations.single.message,
          'June 2026 and July 2026 are still unpaid.');
    });

    test('an already-paid month is caught as a duplicate', () async {
      final memberId = await newMember(plan: 'Monthly');
      await addCycle(memberId,
          start: DateTime.utc(2026, 8, 1), durationMonths: 1, paidMinor: 450000);

      final check = await checker.check(
        memberId: memberId,
        billingMonth: '2026-08',
        now: DateTime(2026, 8, 20),
      );

      expect(check.review.issues,
          contains(BillingMonthIssue.duplicatePayment));
      expect(check.period, isNotNull);
    });

    test('a mid-cycle month on a quarterly plan is caught as a duplicate',
        () async {
      // The bug this exists for: nothing *starts* in September, so a lookup by
      // start month found no cycle, said nothing, and took the money twice for
      // a quarter that was already settled.
      final memberId = await newMember(plan: 'Quarterly');
      await addCycle(memberId,
          start: DateTime.utc(2026, 8, 1), durationMonths: 3, paidMinor: 800000);

      final check = await checker.check(
        memberId: memberId,
        billingMonth: '2026-09',
        now: DateTime(2026, 9, 5),
      );

      expect(check.review.issues, contains(BillingMonthIssue.duplicatePayment));
      expect(check.period, isNotNull,
          reason: 'September resolves to the August-October cycle');
      expect(check.durationMonths, 3);
      expect(check.review.confirmations.first.message,
          contains('August 2026 - October 2026'));
    });

    test('excludePaymentId stops a payment being its own duplicate', () async {
      final memberId = await newMember(plan: 'Monthly');
      await addCycle(memberId,
          start: DateTime.utc(2026, 8, 1), durationMonths: 1, paidMinor: 300000);

      final payment = await db.select(db.payments).getSingle();

      final withoutExclusion = await checker.check(
        memberId: memberId,
        billingMonth: '2026-08',
        now: DateTime(2026, 8, 20),
      );
      expect(withoutExclusion.review.issues,
          contains(BillingMonthIssue.duplicatePayment));

      final editing = await checker.check(
        memberId: memberId,
        billingMonth: '2026-08',
        excludePaymentId: payment.id,
        now: DateTime(2026, 8, 20),
      );

      expect(editing.review.isClean, isTrue,
          reason: 'editing a payment in place is not a duplicate of itself');
    });

    test('excluding a payment also clears it from the unpaid list', () async {
      final memberId = await newMember(plan: 'Monthly');
      await addCycle(memberId,
          start: DateTime.utc(2026, 7, 1), durationMonths: 1, paidMinor: 300000);

      final payment = await db.select(db.payments).getSingle();

      // Moving July's payment to August: July is about to become unpaid, and
      // saying so would be technically true but useless noise.
      final check = await checker.check(
        memberId: memberId,
        billingMonth: '2026-08',
        excludePaymentId: payment.id,
        now: DateTime(2026, 8, 20),
      );

      expect(check.review.issues,
          contains(BillingMonthIssue.unpaidEarlierCycles),
          reason: 'the cycle it is leaving genuinely does become unpaid');
    });

    test('a member with no enrolment reports no plan rather than guessing',
        () async {
      final memberId = await newMember(plan: 'Monthly');
      await (db.delete(db.memberships)
            ..where((m) => m.memberId.equals(memberId)))
          .go();

      final check = await checker.check(
        memberId: memberId,
        billingMonth: '2026-08',
        now: DateTime(2026, 8, 20),
      );

      expect(check.hasPlan, isFalse);
      expect(check.review.isClean, isTrue,
          reason: 'no plan means the rules cannot run, not that all is well');
    });
  });
}
