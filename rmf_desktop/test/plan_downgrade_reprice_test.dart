import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/cycle_pricing_log.dart';
import 'package:rich_man_fitness/data/cycle_repricing.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';

/// Moving a member onto a **cheaper** plan part way through a month.
///
/// A cycle holding money is normally left at the price it was billed at: the
/// member paid that against the old price, and moving it afterwards backdates
/// the change onto them. That is exactly right for a price **rise** — and
/// exactly wrong for a cut, where it is the gym that keeps asking for money the
/// owner has already agreed to stop charging.
///
/// This is what the gym hit. A member on Basic had September opened at
/// Rs. 4,000. The owner moved him to the Student Package at Rs. 2,500 on the
/// 3rd; he paid his Rs. 2,500 on the 5th. September still wanted Rs. 4,000, so
/// it read as part-paid and the member showed DUE for Rs. 1,500 — for ever,
/// because from the moment his money landed no re-pricing would touch the
/// cycle again. Forty-three members were in that state at once.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int basicId;
  late int studentId;

  const basicFee = 400000; // Rs. 4,000
  const studentFee = 250000; // Rs. 2,500

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);

    basicId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                name: 'Basic',
                durationMonths: 1,
                priceMinor: basicFee,
              ),
            ))
        .id;
    studentId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                name: 'Student Package',
                durationMonths: 1,
                priceMinor: studentFee,
              ),
            ))
        .id;
  });

  tearDown(() async => db.close());

  Future<int> memberOnBasic() => members.create(
        fullName: 'Abdul Qadir',
        phone: '+923254097472',
        planId: basicId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

  /// A cycle for [start], billed at [billedMinor], holding [paidMinor].
  Future<int> openCycle(
    int memberId, {
    required DateTime start,
    required DateTime end,
    required int billedMinor,
    int paidMinor = 0,
  }) async {
    final membership = (await openMembershipFor(db, memberId))!;
    final period = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: start,
            periodEnd: end,
            expectedAmountMinor: billedMinor,
          ),
        );
    if (paidMinor > 0) {
      final paymentId = await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              memberId: memberId,
              membershipPeriodId: Value(period.id),
              amountMinor: paidMinor,
              method: PaymentMethod.cash,
              paymentDate: start.add(const Duration(days: 4)),
              recordedById: (await db.select(db.users).getSingle()).id,
              idempotencyKey: 'seed-${period.id}',
            ),
          );
      await db.into(db.paymentAllocations).insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              membershipPeriodId: period.id,
              amountMinor: paidMinor,
            ),
          );
    }
    return period.id;
  }

  Future<MembershipPeriod> cycleAt(int memberId, DateTime start) async =>
      (await periodsForMember(db, memberId))
          .firstWhere((p) => p.periodStart.toUtc() == start);

  /// The owner moves the member onto the cheaper plan.
  Future<void> moveToStudent(int memberId, DateTime on) => members.update(
        id: memberId,
        fullName: 'Abdul Qadir',
        phone: '+923254097472',
        planId: studentId,
        joiningDate: DateTime.utc(2026, 1, 1),
        now: on,
      );

  test('a fee cut reaches the month they are standing in, even part-paid',
      () async {
    final memberId = await memberOnBasic();
    await openCycle(memberId,
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 10, 1),
        billedMinor: basicFee,
        paidMinor: studentFee);

    await moveToStudent(memberId, DateTime.utc(2026, 9, 3));

    final september = await cycleAt(memberId, DateTime.utc(2026, 9, 1));
    expect(september.expectedAmountMinor, studentFee,
        reason: 'the owner agreed to stop charging Rs. 4,000 for this month');
  });

  test('and the month settles, because the money in it now covers the fee',
      () async {
    final memberId = await memberOnBasic();
    await openCycle(memberId,
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 10, 1),
        billedMinor: basicFee,
        paidMinor: studentFee);

    await moveToStudent(memberId, DateTime.utc(2026, 9, 3));

    final september = await cycleAt(memberId, DateTime.utc(2026, 9, 1));
    expect(september.settledAt, isNotNull,
        reason: 're-pricing must not leave a stamp disagreeing with the money');
    expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!.status,
        MemberStatus.paid);
  });

  test('a member who has paid less than the new fee still owes the rest',
      () async {
    final memberId = await memberOnBasic();
    await openCycle(memberId,
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 10, 1),
        billedMinor: basicFee,
        paidMinor: 100000); // Rs. 1,000 only

    await moveToStudent(memberId, DateTime.utc(2026, 9, 3));

    final september = await cycleAt(memberId, DateTime.utc(2026, 9, 1));
    expect(september.expectedAmountMinor, studentFee);
    expect(september.settledAt, isNull);
    expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!
        .outstandingMinor, 150000,
        reason: 'Rs. 2,500 owed less the Rs. 1,000 already in it');
  });

  test('a fee RISE still cannot reach a part-paid cycle', () async {
    final memberId = await members.create(
      fullName: 'Bilal Ahmed',
      phone: '+923254097473',
      planId: studentId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
    await openCycle(memberId,
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 10, 1),
        billedMinor: studentFee,
        paidMinor: 100000);

    // Onto the dearer plan.
    await members.update(
      id: memberId,
      fullName: 'Bilal Ahmed',
      phone: '+923254097473',
      planId: basicId,
      joiningDate: DateTime.utc(2026, 1, 1),
      now: DateTime.utc(2026, 9, 3),
    );

    final september = await cycleAt(memberId, DateTime.utc(2026, 9, 1));
    expect(september.expectedAmountMinor, studentFee,
        reason: 'money against a cycle is the member acting on the old price; '
            'raising it afterwards would backdate the rise');
  });

  test('a cut does not reach a month that has already ended', () async {
    final memberId = await memberOnBasic();
    await openCycle(memberId,
        start: DateTime.utc(2026, 7, 1),
        end: DateTime.utc(2026, 8, 1),
        billedMinor: basicFee,
        paidMinor: studentFee);

    await moveToStudent(memberId, DateTime.utc(2026, 9, 3));

    final july = await cycleAt(memberId, DateTime.utc(2026, 7, 1));
    expect(july.expectedAmountMinor, basicFee,
        reason: 'arrears were incurred at the price of the day');
  });

  test('a cut does not reopen a settled month', () async {
    final memberId = await memberOnBasic();
    final periodId = await openCycle(memberId,
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 10, 1),
        billedMinor: basicFee,
        paidMinor: basicFee);
    await (db.update(db.membershipPeriods)..where((p) => p.id.equals(periodId)))
        .write(MembershipPeriodsCompanion(
            settledAt: Value(DateTime.utc(2026, 9, 2))));

    await moveToStudent(memberId, DateTime.utc(2026, 9, 3));

    final september = await cycleAt(memberId, DateTime.utc(2026, 9, 1));
    expect(september.expectedAmountMinor, basicFee,
        reason: 'a closed debt is not reopened, and they paid Rs. 4,000');
  });

  test('the startup sweep heals a member nobody has edited', () async {
    // Nothing about this member is saved again — the plan change happened on a
    // release that could not carry it through, and the sweep is what finds it.
    final memberId = await memberOnBasic();
    await openCycle(memberId,
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 10, 1),
        billedMinor: basicFee,
        paidMinor: studentFee);
    await (db.update(db.memberships)
          ..where((m) => m.memberId.equals(memberId)))
        .write(MembershipsCompanion(planId: Value(studentId)));

    final repriced =
        await repriceAllOpenCycles(db, now: DateTime.utc(2026, 9, 15));

    expect(repriced, 1);
    expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!.status,
        MemberStatus.paid);
  });

  group('edge cases the sweep must get right', () {
    test('an overpaid cycle stays settled and never goes negative', () async {
      final memberId = await memberOnBasic();
      await openCycle(memberId,
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 10, 1),
          billedMinor: basicFee,
          paidMinor: 300000); // Rs. 3,000 against a Rs. 4,000 bill — overpaid
                              // relative to the Rs. 2,500 it is about to become.

      await moveToStudent(memberId, DateTime.utc(2026, 9, 3));

      final september = await cycleAt(memberId, DateTime.utc(2026, 9, 1));
      expect(september.expectedAmountMinor, studentFee);
      expect(september.settledAt, isNotNull);
      // Settled means no cycle is left owing at all, so the member's
      // outstanding figure reads as "nothing owed" rather than a negative
      // credit — there is no such thing as owing less than zero.
      expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!
          .outstandingMinor, isNull,
          reason: 'an overpaid, now-settled cycle leaves nothing owing, never '
              'a negative balance');
      expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!
          .status, MemberStatus.paid);
    });

    test('sums every allocation against the cycle, not just the latest '
        'payment', () async {
      final memberId = await memberOnBasic();
      final periodId = await openCycle(memberId,
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 10, 1),
          billedMinor: basicFee,
          paidMinor: 100000); // First instalment: Rs. 1,000.

      // A second instalment, as its own payment and allocation — the shape a
      // member paying in two visits actually leaves.
      final secondPaymentId = await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              memberId: memberId,
              membershipPeriodId: Value(periodId),
              amountMinor: 100000,
              method: PaymentMethod.cash,
              paymentDate: DateTime.utc(2026, 9, 10),
              recordedById: (await db.select(db.users).getSingle()).id,
              idempotencyKey: 'second-instalment-$periodId',
            ),
          );
      await db.into(db.paymentAllocations).insert(
            PaymentAllocationsCompanion.insert(
              paymentId: secondPaymentId,
              membershipPeriodId: periodId,
              amountMinor: 100000,
            ),
          );

      await moveToStudent(memberId, DateTime.utc(2026, 9, 15));

      final september = await cycleAt(memberId, DateTime.utc(2026, 9, 1));
      expect(september.expectedAmountMinor, studentFee,
          reason: 'the cut must reach the cycle regardless of how many '
              'allocations it holds');
      expect(september.settledAt, isNull,
          reason: 'Rs. 2,000 collected across two allocations is still short '
              'of the Rs. 2,500 it now expects');
      expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 20)))!
          .outstandingMinor, 50000,
          reason: 'Rs. 2,500 less the Rs. 2,000 actually collected, summed '
              'across both allocations');
    });

    test('running the sweep twice changes nothing the first run did not',
        () async {
      final memberId = await memberOnBasic();
      await openCycle(memberId,
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 10, 1),
          billedMinor: basicFee,
          paidMinor: studentFee);
      await (db.update(db.memberships)
            ..where((m) => m.memberId.equals(memberId)))
          .write(MembershipsCompanion(planId: Value(studentId)));

      final first = await repriceAllOpenCycles(db, now: DateTime.utc(2026, 9, 15));
      expect(first, 1);

      final before = await cycleAt(memberId, DateTime.utc(2026, 9, 1));

      final second =
          await repriceAllOpenCycles(db, now: DateTime.utc(2026, 9, 16));
      expect(second, 0,
          reason: 'the fee has not moved since the first run; there is '
              'nothing left to re-price');

      final after = await cycleAt(memberId, DateTime.utc(2026, 9, 1));
      expect(after.expectedAmountMinor, before.expectedAmountMinor);
      expect(after.settledAt, before.settledAt,
          reason: 'a second run must not so much as re-stamp settlement');
    });

    test('re-pricing the same cycle twice at the same fee writes one '
        'provenance row, not two', () async {
      final memberId = await memberOnBasic();
      final periodId = await openCycle(memberId,
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 10, 1),
          billedMinor: basicFee,
          paidMinor: studentFee);

      await moveToStudent(memberId, DateTime.utc(2026, 9, 3));
      final afterFirst = await pricingHistoryFor(db, periodId);

      await repriceOpenCycles(db, memberId: memberId, now: DateTime.utc(2026, 9, 20));
      final afterSecond = await pricingHistoryFor(db, periodId);

      expect(afterSecond.length, afterFirst.length,
          reason: 'a call that changed nothing must record nothing');
    });
  });
}
