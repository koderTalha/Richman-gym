import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_cycles.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

/// A payment is labelled by every month it paid for.
///
/// `payments.membership_period_id` names only the first cycle a payment
/// touched, so three months paid at once read "January 2026" on the payment
/// history and the Receipts list — and on the delete confirmation, which warns
/// that "the billing period will read as due again" when three months would.
/// Labels are now built from the payment's allocations. (Audit BUG-011.)
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

PaidCycle _cycle(DateTime start, {int months = 1, DateTime? end}) => PaidCycle(
      period: MembershipPeriod(
        id: start.millisecondsSinceEpoch,
        membershipId: 1,
        periodStart: start,
        periodEnd: end ?? DateTime.utc(start.year, start.month + months, start.day),
        expectedAmountMinor: 300000,
      ),
      durationMonths: months,
    );

void main() {
  group('formatPaidCycles', () {
    test('one monthly cycle reads as it always has', () {
      expect(formatPaidCycles([_cycle(DateTime.utc(2026, 1, 6))]),
          'January 2026');
    });

    test('one quarterly cycle reads as it always has', () {
      expect(formatPaidCycles([_cycle(DateTime.utc(2026, 1, 1), months: 3)]),
          'January 2026 - March 2026');
    });

    test('consecutive cycles read as one span, in any order', () {
      expect(
          formatPaidCycles([
            _cycle(DateTime.utc(2026, 3, 6)),
            _cycle(DateTime.utc(2026, 1, 6)),
            _cycle(DateTime.utc(2026, 2, 6)),
          ]),
          'January 2026 - March 2026');
    });

    test('a span can cross new year', () {
      expect(
          formatPaidCycles([
            _cycle(DateTime.utc(2025, 12, 1)),
            _cycle(DateTime.utc(2026, 1, 1)),
            _cycle(DateTime.utc(2026, 2, 1)),
          ]),
          'December 2025 - February 2026');
    });

    test('a gap is kept, so months already paid are not claimed again', () {
      // Arrears first: January's balance, then the next unpaid month, April.
      expect(
          formatPaidCycles([
            _cycle(DateTime.utc(2026, 1, 6)),
            _cycle(DateTime.utc(2026, 4, 6)),
          ]),
          'January 2026, April 2026');
    });

    test('a short transition cycle names its own month only', () {
      // A billing-day move leaves a cycle shorter than a month.
      expect(
          formatPaidCycles([
            _cycle(DateTime.utc(2026, 1, 1), end: DateTime.utc(2026, 1, 10)),
            _cycle(DateTime.utc(2026, 1, 10)),
          ]),
          'January 2026');
    });

    test('no cycles, no label', () {
      expect(formatPaidCycles(const []), isNull);
    });
  });

  group('payment history and Receipts labels', () {
    late Directory workspace;
    late AppDatabase db;
    late RecordPaymentService payments;
    late MemberRepository members;
    late int adminId;
    late int planId;
    var counter = 0;
    const fee = 300000;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('rmf-period-labels');
      db = AppDatabase.forTesting(NativeDatabase.memory());
      adminId = await db.into(db.users).insert(UsersCompanion.insert(
          name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
      await db.into(db.gymSettings).insert(const GymSettingsCompanion());
      planId = await db.into(db.membershipPlans).insert(
          MembershipPlansCompanion.insert(
              name: 'Monthly', durationMonths: 1, priceMinor: fee));
      members = MemberRepository(db);
      payments = RecordPaymentService(
        db: db,
        renderer: _FakeRenderer(),
        storage: _FakeStorage(Directory(p.join(workspace.path, 'receipts'))),
        clientFactory: () async => MockWhatsAppClient(),
        cycles: BillingCycleService(db),
      );
    });

    tearDown(() async {
      await db.close();
      if (await workspace.exists()) await workspace.delete(recursive: true);
    });

    Future<int> join(String name) => members.create(
        fullName: name,
        phone: '+92300000${(1000 + counter++).toString()}',
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 6));

    Future<void> pay(int memberId, int amount) =>
        payments.recordAdvancePayment(AdvancePaymentInput(
          memberId: memberId,
          amountMinor: amount,
          method: PaymentMethod.cash,
          paymentDate: DateTime.utc(2026, 1, 6),
          sendWhatsApp: false,
          recordedById: adminId,
          idempotencyKey: 'k-${counter++}',
          confirmedAdvance: true,
        ));

    test('three months paid at once read as the whole span', () async {
      final id = await join('Advance Payer');
      await pay(id, 3 * fee);

      final payment = await db.select(db.payments).getSingle();
      expect(
          await (db.select(db.paymentAllocations)
                ..where((a) => a.paymentId.equals(payment.id)))
              .get(),
          hasLength(3),
          reason: 'precondition: the payment is spread over three cycles');

      final history = await PaymentRepository(db).history();
      expect(history.single.periodLabel, 'January 2026 - March 2026');

      final profile = await PaymentRepository(db).history(memberId: id);
      expect(profile.single.periodLabel, 'January 2026 - March 2026');

      final receipts = await ReceiptRepository(db).list();
      expect(receipts.single.periodLabel, 'January 2026 - March 2026');

      expect(await paymentPeriodLabel(db, payment), 'January 2026 - March 2026');
    });

    test('the edit form still opens on the first cycle', () async {
      final id = await join('Advance Payer');
      await pay(id, 3 * fee);

      final row = (await PaymentRepository(db).history()).single;
      expect(row.periodStart, DateTime.utc(2026, 1, 6));
      expect(row.planDurationMonths, 1);
    });

    test('a one-month payment is labelled as before', () async {
      final id = await join('Monthly Payer');
      await pay(id, fee);

      expect((await PaymentRepository(db).history()).single.periodLabel,
          'January 2026');
      expect((await ReceiptRepository(db).list()).single.periodLabel,
          'January 2026');
    });

    test('a payment without allocations falls back to its own cycle',
        () async {
      final id = await join('Legacy Payer');
      final membership = await (db.select(db.memberships)
            ..where((m) => m.memberId.equals(id)))
          .getSingle();
      final periodId = await db.into(db.membershipPeriods).insert(
          MembershipPeriodsCompanion.insert(
              membershipId: membership.id,
              periodStart: DateTime.utc(2026, 3, 1),
              periodEnd: DateTime.utc(2026, 4, 1),
              expectedAmountMinor: fee));
      final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
              memberId: id,
              membershipPeriodId: Value(periodId),
              amountMinor: fee,
              method: PaymentMethod.cash,
              paymentDate: DateTime.utc(2026, 3, 4),
              recordedById: adminId,
              idempotencyKey: 'legacy'));
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
          receiptNumber: 'RMF-2026-000099',
          paymentId: paymentId,
          pngPath: 'legacy.png'));

      expect((await PaymentRepository(db).history()).single.periodLabel,
          'March 2026');
      expect((await ReceiptRepository(db).list()).single.periodLabel,
          'March 2026');
    });

    test('a payment against no cycle at all shows a dash', () async {
      final id = await join('No Cycle');
      final payment = await db.into(db.payments).insertReturning(
          PaymentsCompanion.insert(
              memberId: id,
              amountMinor: fee,
              method: PaymentMethod.cash,
              paymentDate: DateTime.utc(2026, 3, 4),
              recordedById: adminId,
              idempotencyKey: 'no-cycle'));

      expect((await PaymentRepository(db).history()).single.periodLabel, '—');
      expect(await paymentPeriodLabel(db, payment), isNull);
    });
  });
}
