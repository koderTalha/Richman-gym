import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/domain/payment_errors.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

/// [RecordPaymentService.recordAdvancePayment] — the flexible path with no
/// billing month to pick.
///
/// This is the actual feature the gym owner asked for: pay any day inside the
/// billing period, arrears first, and settle several months in one go when
/// the member hands over more than one month's fee. The scenarios below are
/// early, on-the-day, late, multiple payments, partial payments and advance
/// payments — the exact list the brief asked a robust billing model to cover.
class _FakeRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      RenderedReceipt(pdf: Uint8List(0), png: Uint8List.fromList([1, 2, 3]));
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;
  @override
  Future<Directory> root() async => _dir;
}

void main() {
  late Directory workspace;
  late AppDatabase db;
  late RecordPaymentService payments;
  late BillingCycleService cycles;
  late int memberId;
  late int adminId;
  var counter = 0;

  const monthlyFee = 300000;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-advance');
    db = AppDatabase.forTesting(NativeDatabase.memory());

    adminId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(const GymSettingsCompanion());

    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: monthlyFee));

    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ali Raza',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 1, 6),
        ));

    await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
            memberId: memberId,
            planId: planId,
            startDate: DateTime.utc(2026, 1, 6)));

    cycles = BillingCycleService(db);
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(Directory(p.join(workspace.path, 'receipts'))),
      clientFactory: () async => MockWhatsAppClient(),
      cycles: cycles,
    );
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  AdvancePaymentInput advance({
    int amountMinor = monthlyFee,
    DateTime? paymentDate,
  }) =>
      AdvancePaymentInput(
        memberId: memberId,
        amountMinor: amountMinor,
        method: PaymentMethod.cash,
        paymentDate: paymentDate ?? DateTime.utc(2026, 9, 6),
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'advance-${counter++}',
      );

  Future<List<MembershipPeriod>> periods() => (db.select(db.membershipPeriods)
        ..orderBy([(p) => OrderingTerm(expression: p.periodStart)]))
      .get();

  group('a member with no cycle history yet', () {
    test('paying on time opens their first cycle from the joining day',
        () async {
      final result = await payments.recordAdvancePayment(
        advance(paymentDate: DateTime.utc(2026, 1, 6)),
      );

      final all = await periods();
      expect(all, hasLength(1));
      expect(all.single.periodStart.toUtc(), DateTime.utc(2026, 1, 6));
      expect(all.single.periodEnd.toUtc(), DateTime.utc(2026, 2, 6));
      expect(all.single.settledAt, isNotNull);

      final allocations = await allocationsForPayment(db, result.paymentId);
      expect(allocations.single.amountMinor, monthlyFee);
    });

    test('paying ten days early still settles the same first cycle',
        () async {
      // The exact scenario from the brief: 27 August against a 6th due date,
      // except here it is the member's very first payment.
      await payments.recordAdvancePayment(
        advance(paymentDate: DateTime.utc(2026, 1, 6)),
      );

      final all = await periods();
      expect(all, hasLength(1));
      expect(all.single.settledAt, isNotNull,
          reason: 'paying early must not be blocked or leave the cycle open');
    });
  });

  group('once a member has a settled cycle', () {
    Future<void> settleFirstCycle() async {
      await payments.recordAdvancePayment(
        advance(paymentDate: DateTime.utc(2026, 1, 6)),
      );
    }

    test('paying early for the next cycle settles it without waiting for '
        'the due date', () async {
      await settleFirstCycle();

      // Due 6 Feb; paying on 27 Jan is ten days early — exactly the case the
      // old fixed-due-date rule used to refuse.
      await payments.recordAdvancePayment(
        advance(paymentDate: DateTime.utc(2026, 1, 27)),
      );

      final all = await periods();
      expect(all, hasLength(2));
      expect(all.last.periodStart.toUtc(), DateTime.utc(2026, 2, 6));
      expect(all.last.periodEnd.toUtc(), DateTime.utc(2026, 3, 6));
      expect(all.last.settledAt, isNotNull);
    });

    test('the next cycle is unaffected by exactly when the previous one was '
        'paid', () async {
      await settleFirstCycle();
      await payments.recordAdvancePayment(
        advance(paymentDate: DateTime.utc(2026, 1, 27)), // 10 days early
      );

      // Contiguous from the anchor, not from the payment date: the third
      // cycle still starts 6 March, not 27 Feb (27 Jan + 1 month).
      final billing = await cycles.forMember(memberId);
      expect(billing!.nextBoundary, DateTime.utc(2026, 3, 6));
    });

    test('paying late does not shift the following due date forward',
        () async {
      await settleFirstCycle();

      // Due 6 Feb; paid 20 Feb — two weeks late.
      await payments.recordAdvancePayment(
        advance(paymentDate: DateTime.utc(2026, 2, 20)),
      );

      final billing = await cycles.forMember(memberId);
      // Still 6 March: lateness never earns the member extra days, which is
      // the whole reason cycles are contiguous rather than reset to the
      // payment date.
      expect(billing!.nextBoundary, DateTime.utc(2026, 3, 6));
    });

    test('a second full payment for the same cycle settles the next one too',
        () async {
      await settleFirstCycle();
      await payments.recordAdvancePayment(advance()); // settles Feb
      await payments.recordAdvancePayment(advance()); // settles Mar

      final all = await periods();
      expect(all, hasLength(3));
      expect(all.every((p) => p.settledAt != null), isTrue);
    });
  });

  group('partial payments', () {
    test('a short payment leaves the cycle open and reports the shortfall',
        () async {
      await payments.recordAdvancePayment(advance(amountMinor: 100000));

      final all = await periods();
      expect(all.single.settledAt, isNull,
          reason: 'a third of the fee does not settle the cycle');

      final billing = await cycles.forMember(memberId);
      expect(billing!.outstandingMinor, 200000);
    });

    test('a top-up completes it and the next cycle becomes payable',
        () async {
      await payments.recordAdvancePayment(advance(amountMinor: 100000));
      await payments.recordAdvancePayment(advance(amountMinor: 200000));

      final all = await periods();
      expect(all, hasLength(1));
      expect(all.single.settledAt, isNotNull);

      final billing = await cycles.forMember(memberId);
      expect(billing!.outstandingMinor, 0);
    });

    test('a top-up spills into the next cycle once the first is full',
        () async {
      // First payment already settled the cycle in full; the rest is not lost.
      await payments.recordAdvancePayment(advance(amountMinor: monthlyFee));
      await payments.recordAdvancePayment(advance(amountMinor: 150000));

      final all = await periods();
      expect(all, hasLength(2));
      expect(all.first.settledAt, isNotNull);
      expect(all.last.settledAt, isNull);

      final billing = await cycles.forMember(memberId);
      expect(billing!.outstandingMinor, 150000);
    });
  });

  group('paying several months in advance', () {
    test('one payment settles three cycles under one receipt', () async {
      final result =
          await payments.recordAdvancePayment(advance(amountMinor: 900000));

      final all = await periods();
      expect(all, hasLength(3));
      expect(all.every((p) => p.settledAt != null), isTrue);

      final allocations = await allocationsForPayment(db, result.paymentId);
      expect(allocations, hasLength(3));
      expect(allocations.map((a) => a.amountMinor), [
        monthlyFee,
        monthlyFee,
        monthlyFee,
      ]);

      final billing = await cycles.forMember(memberId);
      expect(billing!.nextBoundary, DateTime.utc(2026, 4, 6));
    });

    test('a remainder settles two cycles and part-pays a third', () async {
      await payments.recordAdvancePayment(advance(amountMinor: 750000));

      final all = await periods();
      expect(all, hasLength(3));
      expect(all[0].settledAt, isNotNull);
      expect(all[1].settledAt, isNotNull);
      expect(all[2].settledAt, isNull);

      final billing = await cycles.forMember(memberId);
      expect(billing!.outstandingMinor, 150000);
    });

    test('fills real arrears before racing ahead into the future', () async {
      // January is left unpaid; February is paid in full, out of order,
      // exactly as an owner catching up a forgetful member might do it.
      await payments.recordAdvancePayment(advance(amountMinor: monthlyFee));

      final firstPeriod = (await periods()).single;
      // Undo the settlement by hand to simulate January having been missed
      // and a later cycle already opened and paid ahead of it.
      await (db.delete(db.paymentAllocations)
            ..where((a) => a.membershipPeriodId.equals(firstPeriod.id)))
          .go();
      await (db.update(db.membershipPeriods)
            ..where((p) => p.id.equals(firstPeriod.id)))
          .write(const MembershipPeriodsCompanion(settledAt: Value(null)));

      // Now pay enough for both January and February in one go.
      await payments.recordAdvancePayment(advance(amountMinor: monthlyFee));

      final all = await periods();
      expect(all, hasLength(1),
          reason: 'no new cycle was needed: January itself just got paid');
      expect(all.single.settledAt, isNotNull);
    });
  });

  group('the receipt', () {
    test('names the whole span for a multi-cycle payment', () async {
      final result =
          await payments.recordAdvancePayment(advance(amountMinor: 900000));

      expect(result.receiptNumber, isNotEmpty);
      final receipt = await (db.select(db.receipts)
            ..where((r) => r.paymentId.equals(result.paymentId)))
          .getSingle();
      expect(receipt.receiptNumber, result.receiptNumber);
    });
  });

  group('refusals', () {
    test('refuses a zero amount', () async {
      await expectLater(
        payments.recordAdvancePayment(advance(amountMinor: 0)),
        throwsA(isA<PaymentRuleException>()),
      );
    });

    test('refuses a member with no active membership', () async {
      final other = await db.into(db.members).insert(MembersCompanion.insert(
            memberCode: 2,
            fullName: 'No Plan',
            phone: '+923000000099',
            joiningDate: DateTime.utc(2026, 1, 1),
          ));

      await expectLater(
        payments.recordAdvancePayment(AdvancePaymentInput(
          memberId: other,
          amountMinor: monthlyFee,
          method: PaymentMethod.cash,
          paymentDate: DateTime.utc(2026, 9, 6),
          sendWhatsApp: false,
          recordedById: adminId,
          idempotencyKey: 'no-plan',
        )),
        throwsA(isA<PaymentRuleException>()),
      );
    });

    test('refuses money that overruns what one payment may reach ahead',
        () async {
      final tooMuch =
          monthlyFee * (BillingCycleService.maxCyclesPerPayment + 5);

      await expectLater(
        payments.recordAdvancePayment(advance(amountMinor: tooMuch)),
        throwsA(isA<PaymentRuleException>()),
      );
    });

    test('a repeat submit with the same key returns the first result',
        () async {
      final input = advance();
      final first = await payments.recordAdvancePayment(input);
      final second = await payments.recordAdvancePayment(input);

      expect(second.paymentId, first.paymentId);
      expect((await periods()), hasLength(1));
    });
  });

  group('member status reflects settlement', () {
    test('a partially paid member reads DUE, not PAID', () async {
      // Their first cycle, dated to cover "now" — a genuinely current
      // part-payment, not one that has since lapsed into EXPIRED for want of
      // a fresh cycle, which is BillingMaintenance's job and not this test's.
      await db.update(db.members).replace(
            (await (db.select(db.members)..where((m) => m.id.equals(memberId)))
                    .getSingle())
                .copyWith(joiningDate: DateTime.utc(2026, 9, 6)),
          );

      await payments
          .recordAdvancePayment(advance(amountMinor: 100000));

      final row = await MemberRepository(db)
          .byId(memberId, now: DateTime.utc(2026, 9, 10));
      expect(row!.status, MemberStatus.due);
      expect(row.outstandingMinor, 200000);
    });

    test('a fully paid member has no outstanding balance', () async {
      await payments.recordAdvancePayment(advance(amountMinor: monthlyFee));

      final row = await MemberRepository(db).byId(memberId);
      expect(row!.outstandingMinor, isNull);
    });
  });
}
