import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/cycle_pricing_log.dart';
import 'package:rich_man_fitness/data/cycle_repricing.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_history.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/historical_pricing_review.dart';

/// The ten members the re-pricing fix cannot reach.
///
/// Their August cycle opened at Basic's Rs. 4,000, the owner moved them onto a
/// cheaper plan during the month, they paid the cheaper fee — and then August
/// **ended**. Re-pricing refuses a cycle that has ended, and rightly: arrears
/// were incurred at the price in force at the time, and a member who genuinely
/// owes August must still owe August's fee.
///
/// The database cannot tell those two apart. This is the screen that asks a
/// human, and these are the rules it has to keep while doing so.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int basicId;
  late int studentId;
  late int adminId;

  const basicFee = 400000; // Rs. 4,000
  const midFee = 300000; // Rs. 3,000
  const studentFee = 250000; // Rs. 2,500

  /// Today, for every test here: August has ended, September has not.
  final today = DateTime.utc(2026, 9, 16);
  final augustStart = DateTime.utc(2026, 8, 1);
  final augustEnd = DateTime.utc(2026, 9, 1);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    adminId = (await db.select(db.users).getSingle()).id;

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

  Future<int> memberOnBasic({int code = 82}) => members.create(
        fullName: 'Member $code',
        phone: '+9232540974$code',
        planId: basicId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

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
              recordedById: adminId,
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

  Future<void> moveToStudent(int memberId, {required DateTime on}) async {
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(memberId)))
        .getSingle();
    await members.update(
      id: memberId,
      fullName: member.fullName,
      phone: member.phone,
      planId: studentId,
      joiningDate: DateTime.utc(2026, 1, 1),
      now: on,
      actorId: adminId,
    );
  }

  /// Drops Basic's own price, which lowers what its members are billed today
  /// without opening a newer enrolment. That keeps the enrolment-based evidence
  /// out of the way, so a test can ask what the recorded fee changes alone say.
  Future<void> cutPlanPriceTo(int priceMinor) async {
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(basicId)))
        .write(MembershipPlansCompanion(priceMinor: Value(priceMinor)));
  }

  /// The exact shape of the ten: August opened at Basic, the owner moved them
  /// to Student on 3 September, they had already paid Rs. 2,500 in August.
  ///
  /// September is created too, and left open at the Student fee. That is what
  /// the gym actually has — their September *was* correctly re-priced — and it
  /// matters here: a member with no cycle covering today reads EXPIRED, not
  /// DUE, and the point of these tests is what the owner is looking at.
  Future<({int memberId, int periodId})> strandedMember({
    int paidMinor = studentFee,
    int code = 82,
  }) async {
    final memberId = await memberOnBasic(code: code);
    final periodId = await openCycle(
      memberId,
      start: augustStart,
      end: augustEnd,
      billedMinor: basicFee,
      paidMinor: paidMinor,
    );
    await moveToStudent(memberId, on: DateTime.utc(2026, 9, 3));
    await openCycle(
      memberId,
      start: DateTime.utc(2026, 9, 1),
      end: DateTime.utc(2026, 10, 1),
      billedMinor: studentFee,
    );
    return (memberId: memberId, periodId: periodId);
  }

  group('detection', () {
    test('finds the stranded August cycle', () async {
      final stranded = await strandedMember();

      final found = await detectHistoricalPricingAnomalies(db, now: today);

      expect(found, hasLength(1));
      expect(found.single.period.id, stranded.periodId);
      expect(found.single.billedMinor, basicFee);
      expect(found.single.collectedMinor, studentFee);
      expect(found.single.currentFeeMinor, studentFee);
      expect(found.single.outstandingMinor, basicFee - studentFee);
      expect(found.single.evidence, isNotEmpty);
    });

    test('changes nothing — the cycle is exactly as it was', () async {
      final stranded = await strandedMember();

      await detectHistoricalPricingAnomalies(db, now: today);

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(stranded.periodId)))
          .getSingle();
      expect(period.expectedAmountMinor, basicFee);
      expect(period.settledAt, isNull);
      expect(await members.byId(stranded.memberId, now: today),
          isA<MemberRow>().having((r) => r.status, 'status', MemberStatus.due));
    });

    test('the startup sweep leaves it alone, so only the review can reach it',
        () async {
      final stranded = await strandedMember();

      await repriceAllOpenCycles(db, now: today);

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(stranded.periodId)))
          .getSingle();
      expect(period.expectedAmountMinor, basicFee,
          reason: 'guard (c) must still refuse a cycle that has ended');
    });

    test('a member in genuine arrears at the same price is not offered',
        () async {
      // Never moved plan: they owe August's fee because they did not pay it.
      final memberId = await memberOnBasic(code: 90);
      await openCycle(memberId,
          start: augustStart,
          end: augustEnd,
          billedMinor: basicFee,
          paidMinor: 100000);

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('a member moved onto a DEARER plan is not offered', () async {
      final memberId = await members.create(
        fullName: 'Upgrader',
        phone: '+923254097400',
        planId: studentId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );
      await openCycle(memberId,
          start: augustStart, end: augustEnd, billedMinor: studentFee);
      await members.update(
        id: memberId,
        fullName: 'Upgrader',
        phone: '+923254097400',
        planId: basicId,
        joiningDate: DateTime.utc(2026, 1, 1),
        now: DateTime.utc(2026, 9, 3),
      );

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('a month that has not ended is not offered — re-pricing owns it',
        () async {
      final memberId = await memberOnBasic(code: 91);
      await openCycle(memberId,
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 10, 1),
          billedMinor: basicFee,
          paidMinor: studentFee);
      await moveToStudent(memberId, on: DateTime.utc(2026, 9, 3));

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('a settled month is never offered', () async {
      final memberId = await memberOnBasic(code: 92);
      final periodId = await openCycle(memberId,
          start: augustStart,
          end: augustEnd,
          billedMinor: basicFee,
          paidMinor: basicFee);
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(periodId)))
          .write(MembershipPeriodsCompanion(
              settledAt: Value(DateTime.utc(2026, 8, 5))));
      await moveToStudent(memberId, on: DateTime.utc(2026, 9, 3));

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('a deactivated member is not offered', () async {
      final stranded = await strandedMember(code: 93);
      await members.setActive(stranded.memberId, false);

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('member 112, who paid less than the new fee, is still offered — and '
        'would still owe the shortfall', () async {
      // 2,200 paid against a corrected 2,500 leaves a real 300 owing.
      final stranded = await strandedMember(paidMinor: 220000, code: 112);

      final found = await detectHistoricalPricingAnomalies(db, now: today);

      expect(found, hasLength(1));
      expect(found.single.period.id, stranded.periodId);
      expect(found.single.outstandingMinor, basicFee - 220000);
      expect(found.single.outstandingAfterMinor, studentFee - 220000);
    });

    test('a cut the month was already billed at is not evidence', () async {
      // The owner cut this member from 4,000 to 3,000 from 1 July, and August
      // opened at exactly that new fee: the cut was honoured. August is above
      // today's fee only because the price moved again afterwards, so what it
      // asks for is arrears at the price in force at the time.
      final memberId = await memberOnBasic(code: 94);
      await recordMembershipChange(
        db,
        memberId: memberId,
        effectiveFrom: DateTime.utc(2026, 7, 1),
        previousFeeMinor: basicFee,
        feeMinor: midFee,
        recordedAt: DateTime.utc(2026, 7, 1),
      );
      await openCycle(memberId,
          start: augustStart, end: augustEnd, billedMinor: midFee);
      await cutPlanPriceTo(studentFee);

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('a cut a later rise superseded is not evidence', () async {
      // Cut to 2,500 from 1 June, then back up to 3,000 from 1 July. August
      // was billed 3,000 — the fee actually in force when it opened — so the
      // June cut says nothing about what August should have cost.
      final memberId = await memberOnBasic(code: 95);
      await recordMembershipChange(
        db,
        memberId: memberId,
        effectiveFrom: DateTime.utc(2026, 6, 1),
        previousFeeMinor: basicFee,
        feeMinor: studentFee,
        recordedAt: DateTime.utc(2026, 6, 1),
      );
      await recordMembershipChange(
        db,
        memberId: memberId,
        effectiveFrom: DateTime.utc(2026, 7, 1),
        previousFeeMinor: studentFee,
        feeMinor: midFee,
        recordedAt: DateTime.utc(2026, 7, 1),
      );
      await openCycle(memberId,
          start: augustStart, end: augustEnd, billedMinor: midFee);
      await cutPlanPriceTo(studentFee);

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('the latest cut still in force is evidence, superseding an earlier one',
        () async {
      // Two back-dated cuts, 4,000 → 3,000 from 1 June and 3,000 → 2,500 from
      // 1 July. August was billed 4,000, above both, so it is answerable — and
      // the reason shown is the cut that was actually in force.
      final memberId = await memberOnBasic(code: 96);
      await recordMembershipChange(
        db,
        memberId: memberId,
        effectiveFrom: DateTime.utc(2026, 6, 1),
        previousFeeMinor: basicFee,
        feeMinor: midFee,
        recordedAt: DateTime.utc(2026, 9, 10),
      );
      await recordMembershipChange(
        db,
        memberId: memberId,
        effectiveFrom: DateTime.utc(2026, 7, 1),
        previousFeeMinor: midFee,
        feeMinor: studentFee,
        recordedAt: DateTime.utc(2026, 9, 10),
      );
      await openCycle(memberId,
          start: augustStart, end: augustEnd, billedMinor: basicFee);
      await cutPlanPriceTo(studentFee);

      final found = await detectHistoricalPricingAnomalies(db, now: today);

      expect(found, hasLength(1));
      expect(found.single.evidence.first, contains('from 01 Jul 2026'));
      expect(
        found.single.evidence.where((line) => line.contains('01 Jun 2026')),
        isEmpty,
        reason: 'the June cut was replaced before August and explains nothing',
      );
    });
  });

  group('correcting', () {
    test('lowers the bill, settles the month and clears DUE', () async {
      final stranded = await strandedMember();

      final result = await applyBillingCorrection(
        db,
        periodId: stranded.periodId,
        correctedAmountMinor: studentFee,
        reason: 'Moved to the Student Package; August opened at the old price.',
        actorId: adminId,
        now: today,
      );

      expect(result, isA<BillingCorrectionApplied>());
      expect((result as BillingCorrectionApplied).settled, isTrue);

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(stranded.periodId)))
          .getSingle();
      expect(period.expectedAmountMinor, studentFee);
      expect(period.settledAt, isNotNull);

      // August stops being the month they owe. September is — legitimately,
      // because it is this month and nobody has paid it yet. The correction
      // clears the phantom debt without touching the real one.
      final row = await members.byId(stranded.memberId, now: today);
      expect(row!.outstandingMinor, studentFee,
          reason: 'September, at the current fee — not August\'s 1,500');
    });

    test('leaves a genuine shortfall owing rather than forgiving it', () async {
      final stranded = await strandedMember(paidMinor: 220000, code: 112);

      final result = await applyBillingCorrection(
        db,
        periodId: stranded.periodId,
        correctedAmountMinor: studentFee,
        reason: 'Moved to the Student Package.',
        actorId: adminId,
        now: today,
      );

      expect((result as BillingCorrectionApplied).settled, isFalse);

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(stranded.periodId)))
          .getSingle();
      expect(period.settledAt, isNull);
      expect(period.expectedAmountMinor - 220000, studentFee - 220000);
    });

    test('touches no payment and no allocation', () async {
      final stranded = await strandedMember();
      final paymentsBefore = await db.select(db.payments).get();
      final allocationsBefore = await db.select(db.paymentAllocations).get();

      await applyBillingCorrection(
        db,
        periodId: stranded.periodId,
        correctedAmountMinor: studentFee,
        reason: 'Moved to the Student Package.',
        now: today,
      );

      expect(
          (await db.select(db.payments).get()).map((p) => p.amountMinor),
          paymentsBefore.map((p) => p.amountMinor));
      expect(
          (await db.select(db.paymentAllocations).get())
              .map((a) => a.amountMinor),
          allocationsBefore.map((a) => a.amountMinor));
    });

    test('the original bill stays recoverable', () async {
      final stranded = await strandedMember();

      await applyBillingCorrection(
        db,
        periodId: stranded.periodId,
        correctedAmountMinor: studentFee,
        reason: 'Moved to the Student Package.',
        now: today,
      );

      final history = await pricingHistoryFor(db, stranded.periodId);
      final correction = history.last;
      expect(correction.source, CyclePricingSource.correction);
      expect(correction.previousAmountMinor, basicFee);
      expect(correction.amountMinor, studentFee);
      expect(correction.reason, contains('Student Package'));
    });

    test('refuses to raise a historical bill', () async {
      final stranded = await strandedMember();

      final result = await applyBillingCorrection(
        db,
        periodId: stranded.periodId,
        correctedAmountMinor: basicFee + 100000,
        reason: 'nope',
        now: today,
      );

      expect(result, isA<BillingCorrectionRefused>());
      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(stranded.periodId)))
          .getSingle();
      expect(period.expectedAmountMinor, basicFee);
    });

    test('refuses a settled month', () async {
      final stranded = await strandedMember();
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(stranded.periodId)))
          .write(MembershipPeriodsCompanion(settledAt: Value(today)));

      expect(
        await applyBillingCorrection(
          db,
          periodId: stranded.periodId,
          correctedAmountMinor: studentFee,
          reason: 'nope',
          now: today,
        ),
        isA<BillingCorrectionRefused>(),
      );
    });

    test('a corrected month is not offered for review again', () async {
      final stranded = await strandedMember();
      await applyBillingCorrection(
        db,
        periodId: stranded.periodId,
        correctedAmountMinor: studentFee,
        reason: 'Moved to the Student Package.',
        now: today,
      );

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('the owner can read what happened in the logs', () async {
      final stranded = await strandedMember();
      await applyBillingCorrection(
        db,
        periodId: stranded.periodId,
        correctedAmountMinor: studentFee,
        reason: 'Moved to the Student Package.',
        actorId: adminId,
        now: today,
      );

      final events = await (db.select(db.auditEvents)
            ..where((e) =>
                e.action.equals(AuditAction.billingHistoricalCorrection)))
          .get();
      expect(events, hasLength(1));
      expect(events.single.summary, contains('Rs. 4,000'));
      expect(events.single.summary, contains('Rs. 2,500'));
      expect(events.single.detail, contains('No payment or allocation'));
    });
  });

  group('keeping', () {
    test('changes no money at all', () async {
      final stranded = await strandedMember();

      await keepHistoricalPrice(
        db,
        periodId: stranded.periodId,
        reason: 'He really did owe the full Rs. 4,000 for August.',
        actorId: adminId,
        now: today,
      );

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(stranded.periodId)))
          .getSingle();
      expect(period.expectedAmountMinor, basicFee);
      expect(period.settledAt, isNull);
      expect((await members.byId(stranded.memberId, now: today))!.status,
          MemberStatus.due);
    });

    test('stops the month being offered again', () async {
      final stranded = await strandedMember();

      await keepHistoricalPrice(
        db,
        periodId: stranded.periodId,
        reason: 'He really did owe it.',
        now: today,
      );

      expect(await detectHistoricalPricingAnomalies(db, now: today), isEmpty);
    });

    test('and says so in the logs', () async {
      final stranded = await strandedMember();
      await keepHistoricalPrice(
        db,
        periodId: stranded.periodId,
        reason: 'He really did owe it.',
        now: today,
      );

      final events = await (db.select(db.auditEvents)
            ..where((e) => e.action.equals(AuditAction.billingHistoricalKept)))
          .get();
      expect(events, hasLength(1));
      expect(events.single.detail, contains('Nothing was changed.'));
    });
  });

  group('a back-dated plan change', () {
    test('does not rewrite the month it reaches back over', () async {
      final memberId = await memberOnBasic(code: 99);
      final periodId = await openCycle(memberId,
          start: augustStart,
          end: augustEnd,
          billedMinor: basicFee,
          paidMinor: studentFee);

      // "From 1 August", entered on 16 September.
      await members.update(
        id: memberId,
        fullName: 'Member 99',
        phone: '+923254097499',
        planId: studentId,
        joiningDate: DateTime.utc(2026, 1, 1),
        now: today,
        effectiveFrom: augustStart,
        actorId: adminId,
      );

      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(periodId)))
          .getSingle();
      expect(period.expectedAmountMinor, basicFee,
          reason: 'an ended cycle is never re-priced automatically, whatever '
              'date the owner chose');
    });

    test('but it does make the month answerable, with the date as evidence',
        () async {
      final memberId = await memberOnBasic(code: 98);
      await openCycle(memberId,
          start: augustStart,
          end: augustEnd,
          billedMinor: basicFee,
          paidMinor: studentFee);

      await members.update(
        id: memberId,
        fullName: 'Member 98',
        phone: '+923254097498',
        planId: studentId,
        joiningDate: DateTime.utc(2026, 1, 1),
        now: today,
        effectiveFrom: augustStart,
        actorId: adminId,
      );

      final found = await detectHistoricalPricingAnomalies(db, now: today);
      expect(found, hasLength(1));
      expect(found.single.evidence.first, contains('from 01 Aug 2026'));
      expect(found.single.evidence.first, contains('entered on 16 Sep 2026'));
    });

    test('cannot be dated before the enrolment it would close', () async {
      final memberId = await memberOnBasic(code: 97);

      // The active enrolment on Basic started 1 January; asking for the
      // change to Student to have applied from 2026 would close that
      // enrolment before it began.
      expect(
        () => members.update(
          id: memberId,
          fullName: 'Member 97',
          phone: '+923254097497',
          planId: studentId,
          joiningDate: DateTime.utc(2026, 1, 1),
          now: today,
          effectiveFrom: DateTime.utc(2025, 6, 1),
          actorId: adminId,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
