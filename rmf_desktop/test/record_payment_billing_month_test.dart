import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/domain/payment_timing.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

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

/// Entering months the app was never open for.
///
/// A gym that starts using the app in September still has a year of paid
/// months behind it, and a member who was billed 1500 until the fee rose in
/// April is owed a ledger that says so. The app records this through
/// `RecordPaymentService.call`, which takes the billing month explicitly and
/// opens that month's cycle if it is missing — the path Edit Payment already
/// uses and Record Payment did not offer.
///
/// The trap it has to avoid: a cycle conjured for January must be worth what
/// January cost, not what the plan costs today. Snapshotting the current fee
/// would leave every back-filled month before a price rise permanently short
/// by the difference, which is the artificial arrears the whole billing design
/// exists to prevent — and re-pricing cannot rescue it, because a cycle
/// holding money is never re-priced.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late SettingsRepository settings;
  late RecordPaymentService payments;
  late PaymentRepository paymentRepo;
  late int adminId;
  late int monthlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    settings = SettingsRepository(db);
    paymentRepo = PaymentRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    // The gym's monthly fee starts at 1500.
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(150000)));

    final workspace = await Directory.systemTemp.createTemp('rmf-backfill');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
  });

  tearDown(() async => db.close());

  Future<int> joinOn(DateTime joiningDate) => members.create(
        fullName: 'Talha',
        phone: '+923000000001',
        planId: monthlyId,
        joiningDate: joiningDate,
      );

  Future<RecordPaymentResult> payForMonth(
    int memberId, {
    required String month,
    required int rupees,
    required DateTime on,
    int? expectedRupees,
  }) =>
      payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: rupees * 100,
        method: PaymentMethod.cash,
        paymentDate: on,
        billingMonth: month,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'backfill-$month',
        expectedAmountMinor:
            expectedRupees == null ? null : expectedRupees * 100,
      ));

  Future<void> raisePlanPriceTo(int rupees) => settings.savePlan(
        id: monthlyId,
        name: 'Monthly',
        durationMonths: 1,
        priceMinor: rupees * 100,
        isActive: true,
      );

  Future<List<MembershipPeriod>> cyclesOf(int memberId) =>
      periodsForMember(db, memberId);

  test('a month with no cycle is opened and settled by the payment', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 1));

    await payForMonth(memberId,
        month: '2026-01', rupees: 1500, on: DateTime.utc(2026, 1, 1));

    final cycles = await cyclesOf(memberId);
    expect(cycles, hasLength(1));
    expect(cycles.single.periodStart.toUtc(), DateTime.utc(2026, 1, 1));
    expect(cycles.single.expectedAmountMinor, 150000);
    expect(cycles.single.settledAt, isNotNull);
  });

  test('the payment is not labelled ADVANCE when it matches its own month',
      () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 1));

    final result = await payForMonth(memberId,
        month: '2026-01', rupees: 1500, on: DateTime.utc(2026, 1, 1));

    expect(result.timing, PaymentTiming.onTime,
        reason: 'paid on the day the cycle it names begins — the ADVANCE badge '
            'was an artefact of the money landing on a later cycle');
  });

  test('a back-filled month is worth what it cost, not what the plan costs now',
      () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 1));
    // The gym is entering last year's ledger; the fee has since gone up.
    await raisePlanPriceTo(2500);

    await payForMonth(memberId,
        month: '2026-01',
        rupees: 1500,
        on: DateTime.utc(2026, 1, 1),
        expectedRupees: 1500);

    final january = (await cyclesOf(memberId)).single;
    expect(january.expectedAmountMinor, 150000,
        reason: 'January cost 1500 and was paid in full');
    expect(january.settledAt, isNotNull);

    final row = await members.byId(memberId, now: DateTime.utc(2026, 1, 15));
    expect(row!.outstandingMinor, isNull,
        reason: 'snapshotting the current 2500 would leave 1000 of arrears '
            'for a month that was paid in full');
  });

  test('without an override a new cycle still takes the current fee', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 1));
    await raisePlanPriceTo(2500);

    await payForMonth(memberId,
        month: '2026-04', rupees: 2500, on: DateTime.utc(2026, 4, 1));

    final april = (await cyclesOf(memberId)).single;
    expect(april.expectedAmountMinor, 250000);
    expect(april.settledAt, isNotNull);
  });

  test('the owner\'s year: 1500 to March, 2500 from April, nothing owed',
      () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 1));

    // January to March at the old fee.
    for (var month = 1; month <= 3; month++) {
      await payForMonth(memberId,
          month: '2026-0$month',
          rupees: 1500,
          on: DateTime.utc(2026, month, 1),
          expectedRupees: 1500);
    }

    // The owner raised the fee at the end of March.
    await raisePlanPriceTo(2500);

    // April to September at the new fee.
    for (var month = 4; month <= 9; month++) {
      await payForMonth(memberId,
          month: '2026-0$month',
          rupees: 2500,
          on: DateTime.utc(2026, month, 1));
    }

    final cycles = await cyclesOf(memberId);
    expect(cycles, hasLength(9), reason: 'nine months lived, nine cycles');
    expect(cycles.where((c) => c.settledAt == null), isEmpty);

    // The three months before the rise keep the price that was charged.
    for (final cycle in cycles.take(3)) {
      expect(cycle.expectedAmountMinor, 150000);
    }
    for (final cycle in cycles.skip(3)) {
      expect(cycle.expectedAmountMinor, 250000);
    }

    final row = await members.byId(memberId, now: DateTime.utc(2026, 9, 15));
    expect(row!.outstandingMinor, isNull);
    expect(row.status, MemberStatus.paid);

    // Revenue is the sum of what was actually collected, so it reads
    // 4500 + 2500x6 rather than nine months at either single fee.
    final collected = await paymentRepo.totalMinorBetween(
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 10, 1),
    );
    expect(collected, 450000 + 250000 * 6);
  });

  test('recording the same month twice does not open a second cycle',
      () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 1));

    await payForMonth(memberId,
        month: '2026-01', rupees: 1500, on: DateTime.utc(2026, 1, 1));
    await payForMonth(memberId,
        month: '2026-01', rupees: 1500, on: DateTime.utc(2026, 1, 1));

    expect(await cyclesOf(memberId), hasLength(1),
        reason: 'the idempotency key is the same submission, not a top-up');
  });

  test('an override is ignored when the month already has a cycle', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 1));
    await payForMonth(memberId,
        month: '2026-01', rupees: 1500, on: DateTime.utc(2026, 1, 1));

    // A second, different submission naming the same month. The cycle exists
    // and is settled history — its price is not the new caller's to move.
    await payments.call(RecordPaymentInput(
      memberId: memberId,
      amountMinor: 50000,
      method: PaymentMethod.cash,
      paymentDate: DateTime.utc(2026, 1, 20),
      billingMonth: '2026-01',
      sendWhatsApp: false,
      recordedById: adminId,
      idempotencyKey: 'top-up',
      expectedAmountMinor: 999900,
    ));

    final january = (await cyclesOf(memberId)).single;
    expect(january.expectedAmountMinor, 150000,
        reason: 're-pricing a settled month would reopen a closed debt');
  });
}
