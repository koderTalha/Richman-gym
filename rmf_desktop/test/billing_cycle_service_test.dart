import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/domain/billing_cycle.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';

/// The database half of the billing-cycle model: reading a member's timeline,
/// offering cycles a payment can reach, and moving a member onto a new
/// billing day without touching what they have already paid.
void main() {
  late AppDatabase db;
  late BillingCycleService cycles;
  late int memberId;
  late int membershipId;

  const monthlyFee = 300000;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cycles = BillingCycleService(db, audit: AuditRepository(db));

    await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));

    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: monthlyFee));

    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ali Raza',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 1, 6),
        ));

    membershipId = await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
            memberId: memberId,
            planId: planId,
            startDate: DateTime.utc(2026, 1, 6)));
  });

  tearDown(() => db.close());

  group('forMember', () {
    test('returns null for a member with no membership', () async {
      final other = await db.into(db.members).insert(MembersCompanion.insert(
            memberCode: 2,
            fullName: 'No Plan',
            phone: '+923000000099',
            joiningDate: DateTime.utc(2026, 1, 1),
          ));

      expect(await cycles.forMember(other), isNull);
    });

    test('resolves the anchor day from the joining date with no cycles yet',
        () async {
      final billing = await cycles.forMember(memberId);
      expect(billing!.anchorDay, 6);
      expect(billing.nextBoundary, DateTime.utc(2026, 1, 6));
    });

    test('the whole timeline is empty and nothing is owed until a cycle '
        'exists', () async {
      final billing = await cycles.forMember(memberId);
      expect(billing!.cycles, isEmpty);
      expect(billing.nextUnsettled, isNull);
      expect(billing.outstandingMinor, 0);
    });
  });

  group('settleableFor', () {
    test('grows only as far as needed to cover the amount', () async {
      final billing = await cycles.forMember(memberId);
      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: 650000);

      // Two cycles (600,000) still leave money over, so a third is offered;
      // a fourth is not, since three (900,000) already cover it.
      expect(offered, hasLength(3));
      expect(offered[0].start, DateTime.utc(2026, 1, 6));
      expect(offered[1].start, DateTime.utc(2026, 2, 6));
      expect(offered[2].start, DateTime.utc(2026, 3, 6));
    });

    test('offers nothing when the amount is zero', () async {
      final billing = await cycles.forMember(memberId);
      expect(cycles.settleableFor(billing: billing!, amountMinor: 0), isEmpty);
    });

    test('is capped so a typo cannot open hundreds of cycles', () async {
      final billing = await cycles.forMember(memberId);
      final absurd = monthlyFee * 1000;

      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: absurd);
      expect(offered.length, BillingCycleService.maxCyclesPerPayment);
    });
  });

  group('materialise', () {
    test('creates a row for a cycle that does not exist yet', () async {
      final billing = await cycles.forMember(memberId);
      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: monthlyFee);

      final period = await cycles.materialise(
        membershipId: membershipId,
        cycle: offered.single,
      );

      expect(period.periodStart.toUtc(), DateTime.utc(2026, 1, 6));
      final all = await db.select(db.membershipPeriods).get();
      expect(all, hasLength(1));
    });

    test('two calls for the same cycle return the same row, not two',
        () async {
      final billing = await cycles.forMember(memberId);
      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: monthlyFee);

      final first = await cycles.materialise(
          membershipId: membershipId, cycle: offered.single);
      final second = await cycles.materialise(
          membershipId: membershipId, cycle: offered.single);

      expect(second.id, first.id);
      expect(await db.select(db.membershipPeriods).get(), hasLength(1));
    });
  });

  group('refreshSettlement', () {
    Future<int> openCycle() async {
      final billing = await cycles.forMember(memberId);
      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: monthlyFee);
      final period = await cycles.materialise(
          membershipId: membershipId, cycle: offered.single);
      return period.id;
    }

    Future<void> allocate(int periodId, int paymentId, int amountMinor) async {
      await db.into(db.paymentAllocations).insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              membershipPeriodId: periodId,
              amountMinor: amountMinor,
            ),
          );
    }

    Future<int> recordPayment(int amountMinor, String key) => db
        .into(db.payments)
        .insert(PaymentsCompanion.insert(
          memberId: memberId,
          amountMinor: amountMinor,
          method: PaymentMethod.cash,
          paymentDate: DateTime.utc(2026, 1, 6),
          recordedById: 1,
          idempotencyKey: key,
        ));

    test('marks a cycle settled once allocations reach the fee', () async {
      final periodId = await openCycle();
      final paymentId = await recordPayment(monthlyFee, 'p1');
      await allocate(periodId, paymentId, monthlyFee);

      await cycles.refreshSettlement(periodId);

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(periodId)))
          .getSingle();
      expect(period.settledAt, isNotNull);
    });

    test('leaves a cycle unsettled below the fee', () async {
      final periodId = await openCycle();
      final paymentId = await recordPayment(100000, 'p1');
      await allocate(periodId, paymentId, 100000);

      await cycles.refreshSettlement(periodId);

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(periodId)))
          .getSingle();
      expect(period.settledAt, isNull);
    });

    test('reopens a cycle whose allocation was removed', () async {
      final periodId = await openCycle();
      final paymentId = await recordPayment(monthlyFee, 'p1');
      await allocate(periodId, paymentId, monthlyFee);
      await cycles.refreshSettlement(periodId);

      await (db.delete(db.paymentAllocations)
            ..where((a) => a.paymentId.equals(paymentId)))
          .go();
      await cycles.refreshSettlement(periodId);

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(periodId)))
          .getSingle();
      expect(period.settledAt, isNull,
          reason: 'a deleted payment must release the cycle it settled');
    });

    test('is a no-op for a period that no longer exists', () async {
      await cycles.refreshSettlement(999999);
      // Reaching this line without throwing is the assertion.
    });
  });

  group('setAnchorDay', () {
    test('writes the column without touching any recorded cycle', () async {
      final billing = await cycles.forMember(memberId);
      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: monthlyFee);
      final period = await cycles.materialise(
          membershipId: membershipId, cycle: offered.single);
      await cycles.refreshSettlement(period.id);

      await cycles.setAnchorDay(memberId: memberId, anchorDay: 20);

      final unchanged = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(period.id)))
          .getSingle();
      expect(unchanged.periodStart, period.periodStart);
      expect(unchanged.periodEnd, period.periodEnd);

      final membership = await (db.select(db.memberships)
            ..where((m) => m.id.equals(membershipId)))
          .getSingle();
      expect(membership.billingAnchorDay, 20);
    });

    test('the next cycle after re-anchoring is a transition onto the new day',
        () async {
      final billing = await cycles.forMember(memberId);
      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: monthlyFee);
      await cycles.materialise(membershipId: membershipId, cycle: offered.single);

      await cycles.setAnchorDay(memberId: memberId, anchorDay: 20);

      final after = await cycles.forMember(memberId);
      // nextBoundary is where the next cycle *starts* — unaffected by
      // re-anchoring, since the transition changes where a cycle ends, not
      // where it begins. It must still be exactly the recorded cycle's end.
      expect(after!.nextBoundary, DateTime.utc(2026, 2, 6));

      final transition = cycleAfter(
        previousEnd: after.nextBoundary,
        durationMonths: after.plan.durationMonths,
        anchorDay: after.anchorDay,
      );
      expect(transition.isTransition, isTrue);
      // Natural end 6 Mar; the 20th falls 14 days either side of it, and ties
      // go to the earlier occurrence — 20 Feb.
      expect(transition.end, DateTime.utc(2026, 2, 20));
    });

    test('records an audit event naming the old and new day', () async {
      await cycles.setAnchorDay(memberId: memberId, anchorDay: 15, actorId: 1);

      final event = await db.select(db.auditEvents).getSingle();
      expect(event.action, 'billing.anchor_changed');
      expect(event.summary, contains('day 15'));
    });

    test('does nothing when the day is unchanged', () async {
      await cycles.setAnchorDay(memberId: memberId, anchorDay: 6);
      expect(await db.select(db.auditEvents).get(), isEmpty);
    });

    test('rejects a day outside 1-31', () async {
      await expectLater(
        cycles.setAnchorDay(memberId: memberId, anchorDay: 32),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        cycles.setAnchorDay(memberId: memberId, anchorDay: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('previewAnchorChange', () {
    test('shows what the next cycle would be without writing anything',
        () async {
      final preview = await cycles.previewAnchorChange(
        memberId: memberId,
        anchorDay: 20,
      );

      expect(preview!.isTransition, isTrue);

      final membership = await (db.select(db.memberships)
            ..where((m) => m.id.equals(membershipId)))
          .getSingle();
      expect(membership.billingAnchorDay, isNull,
          reason: 'a preview must never write the column it is previewing');
    });
  });
}
