import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/payment_edit_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

import 'support/treadmill_fixture.dart';

class _FakeRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      RenderedReceipt(pdf: await buildPdf(data), png: Uint8List(0));
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  @override
  Future<Directory> root() async => _dir;
}

/// "Can I just delete every payment and re-record January to September at
/// Rs. 2,500?"
///
/// It depends entirely on which Billing period the form is left on, because the
/// two paths put the money in different places:
///
///   * **Automatic** spreads one payment across cycles, oldest first, and
///     carries the remainder forward — which is what built the treadmill.
///   * **A named month** puts the whole amount into that one cycle, whatever
///     the cycle expected.
///
/// Deleting payments does not re-price anything: the Jan-Apr cycles stay at
/// Rs. 1,500, because a cycle that has ended keeps the price it was billed at.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late PaymentEditService editor;
  late int adminId;
  late int planId;
  late int memberId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    adminId = (await db.select(db.users).getSingle()).id;

    planId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                name: 'Student',
                durationMonths: 1,
                priceMinor: treadmillOldFee,
              ),
            ))
        .id;

    final workspace = await Directory.systemTemp.createTemp('rmf-rerecord');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
    editor = PaymentEditService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      audit: AuditRepository(db),
      payments: payments,
    );

    memberId = await buildTreadmilledMember(
      db: db,
      members: members,
      payments: payments,
      adminId: adminId,
      planId: planId,
    );
  });

  tearDown(() async => db.close());

  /// Deletes every payment the member has, the way the owner would from the
  /// payment history table.
  Future<void> deleteEveryPayment() async {
    for (final payment in await (db.select(db.payments)
          ..where((p) => p.memberId.equals(memberId)))
        .get()) {
      expect(await editor.delete(paymentId: payment.id, actorId: adminId),
          isA<PaymentDeleted>());
    }
    expect(
        await (db.select(db.payments)..where((p) => p.memberId.equals(memberId)))
            .get(),
        isEmpty);
  }

  Future<List<({DateTime start, int expected, int got, bool settled})>>
      cycleState() async {
    final periods = await periodsForMember(db, memberId);
    final money = await collectedByPeriod(db, [for (final p in periods) p.id]);
    return [
      for (final p in periods)
        (
          start: p.periodStart.toUtc(),
          expected: p.expectedAmountMinor,
          got: money[p.id] ?? 0,
          settled: p.settledAt != null,
        )
    ];
  }

  test('deleting every payment leaves Jan-Apr still priced at Rs. 1,500',
      () async {
    await deleteEveryPayment();

    final state = await cycleState();
    expect([for (final c in state) c.expected], [
      treadmillOldFee, treadmillOldFee, treadmillOldFee, treadmillOldFee,
      treadmillNewFee, treadmillNewFee, treadmillNewFee, treadmillNewFee,
      treadmillNewFee,
    ], reason: 'the four months billed before the rise keep the old price');
    expect(state.every((c) => c.got == 0), isTrue);
  });

  test('re-recording on Automatic overpays and opens phantom future cycles',
      () async {
    await deleteEveryPayment();

    for (var month = 1; month <= 9; month++) {
      await payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: treadmillNewFee,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, month, 4),
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'auto-$month',
        confirmedAdvance: true,
      ));
    }

    final state = await cycleState();
    // Nine payments of 2,500 = 22,500 against 18,500 of real bills, so the
    // extra 4,000 has to go somewhere: into months nobody has reached yet.
    expect(state.length, greaterThan(9),
        reason: 'the surplus opened cycles beyond September');
    expect(state.last.start.isAfter(DateTime.utc(2026, 9, 1)), isTrue);
  });

  test('re-recording against each named month settles every cycle exactly once',
      () async {
    await deleteEveryPayment();

    for (var month = 1; month <= 9; month++) {
      await payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: treadmillNewFee,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, month, 4),
        billingMonth: '2026-${month.toString().padLeft(2, '0')}',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'named-$month',
      ));
    }

    final state = await cycleState();
    expect(state, hasLength(9),
        reason: 'nine months, nine cycles — nothing spilled, nothing opened '
            'early');
    expect(state.every((c) => c.settled), isTrue,
        reason: 'each month closed by its own payment');
    expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!.status,
        MemberStatus.paid);

    // But the books now say more was collected than the cycles ever billed.
    final billed = state.fold(0, (sum, c) => sum + c.expected);
    final collected = state.fold(0, (sum, c) => sum + c.got);
    expect(billed, 1850000, reason: 'Rs. 18,500 actually billed');
    expect(collected, 2250000, reason: 'Rs. 22,500 now recorded as received');
    expect(collected - billed, 400000,
        reason: 'Rs. 4,000 of revenue that was never collected — the four '
            'months the member really paid Rs. 1,500 for');
  });

  test('re-recording each named month at what it was billed keeps the books '
      'honest', () async {
    await deleteEveryPayment();

    for (var month = 1; month <= 9; month++) {
      // Jan-Apr were billed Rs. 1,500 and that is what the member handed over.
      final amount = month <= 4 ? treadmillOldFee : treadmillNewFee;
      await payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: amount,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, month, 4),
        billingMonth: '2026-${month.toString().padLeft(2, '0')}',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'honest-$month',
      ));
    }

    final state = await cycleState();
    expect(state, hasLength(9));
    expect(state.every((c) => c.settled), isTrue);
    expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!.status,
        MemberStatus.paid);

    final billed = state.fold(0, (sum, c) => sum + c.expected);
    final collected = state.fold(0, (sum, c) => sum + c.got);
    expect(collected, billed,
        reason: 'every rupee recorded is a rupee that was billed');
  });
}
