import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/billing_period.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/payment_edit_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/startup_maintenance.dart';
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

/// Getting a member off the treadmill on the owner's own PC.
///
/// Each test is one thing the owner could actually do through the app, so the
/// instructions he is given are the ones that were proven here.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late PaymentEditService editor;
  late BillingCycleService cycles;
  late int adminId;
  late int planId;
  late int memberId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    cycles = BillingCycleService(db);
    adminId = (await db.select(db.users).getSingle()).id;

    planId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                name: 'Student',
                durationMonths: 1,
                priceMinor: treadmillOldFee,
              ),
            ))
        .id;

    final workspace = await Directory.systemTemp.createTemp('rmf-repair');
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

  Future<void> collect(int amountMinor, DateTime on, String key) =>
      payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: amountMinor,
        method: PaymentMethod.cash,
        paymentDate: on,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: key,
      ));

  Future<({MemberStatus status, int? owed, DateTime? from, int inIt})> look(
      DateTime at) async {
    final row = await members.byId(memberId, now: at);
    final owing = (await cycles.forMember(memberId))?.nextUnsettled;
    return (
      status: row!.status,
      owed: row.outstandingMinor,
      from: owing?.start,
      inIt: owing?.collectedMinor ?? 0,
    );
  }

  test('the fixture is the state the gym reported', () async {
    final now = await look(DateTime.utc(2026, 9, 15));

    expect(now.status, MemberStatus.due);
    expect(now.owed, 150000, reason: 'Rs. 1,500');
    expect(now.from, DateTime.utc(2026, 9, 1),
        reason: '"Overdue since 01 Sep 2026"');
    expect(now.inIt, 100000, reason: 'Rs. 1,000 already in September');
  });

  test('REPAIR A: collecting the amount shown ends it permanently', () async {
    // The owner takes Rs. 1,500 today — what the screen asks for — instead of
    // the full Rs. 2,500.
    await collect(150000, DateTime.utc(2026, 9, 15), 'repair-a-sep');

    expect((await look(DateTime.utc(2026, 9, 20))).status, MemberStatus.paid,
        reason: 'September closes and nothing spills into October');

    // October arrives as a whole, clean month.
    await runStartupMaintenance(db, now: DateTime.utc(2026, 10, 4));
    final october = await look(DateTime.utc(2026, 10, 4));
    expect(october.from, DateTime.utc(2026, 10, 1));
    expect(october.inIt, 0, reason: 'nothing carried over');
    expect(october.owed, 250000, reason: 'a whole month, not a fragment');

    // And the full fee settles it, the way it always should have.
    await collect(250000, DateTime.utc(2026, 10, 4), 'repair-a-oct');
    expect((await look(DateTime.utc(2026, 10, 20))).status, MemberStatus.paid);

    await runStartupMaintenance(db, now: DateTime.utc(2026, 11, 4));
    await collect(250000, DateTime.utc(2026, 11, 4), 'repair-a-nov');
    expect((await look(DateTime.utc(2026, 11, 20))).status, MemberStatus.paid,
        reason: 'the treadmill does not come back');
  });

  test('REPAIR A: the payment lands wholly on September, and says so',
      () async {
    // "Where does this money actually go, and what will the receipt say?"
    await collect(150000, DateTime.utc(2026, 9, 15), 'repair-a-where');

    final payment = (await (db.select(db.payments)
              ..where((p) => p.memberId.equals(memberId))
              ..orderBy([(p) => OrderingTerm(expression: p.id)]))
            .get())
        .last;

    final september = (await periodsForMember(db, memberId)).firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 9, 1));

    // One cycle, not two: the money exactly fills what September still owed,
    // so nothing reaches October and no cycle is opened early.
    final spread = await allocationsForPayment(db, payment.id);
    expect(spread, hasLength(1));
    expect(spread.single.membershipPeriodId, september.id);
    expect(spread.single.amountMinor, 150000);

    // The period the payment is filed under — what the history table and the
    // receipt both read.
    expect(payment.membershipPeriodId, september.id);
    expect(
        formatBillingPeriod(september.periodStart.toUtc(), 1), 'September 2026');

    expect(september.periodStart.toUtc(), DateTime.utc(2026, 9, 1));
    expect(september.periodEnd.toUtc(), DateTime.utc(2026, 10, 1));
  });

  test('REPAIR B: collecting the full fee just moves it on a month', () async {
    await collect(250000, DateTime.utc(2026, 9, 15), 'repair-b');

    final after = await look(DateTime.utc(2026, 9, 20));
    expect(after.from, DateTime.utc(2026, 10, 1),
        reason: 'the shortfall has walked into October');
    expect(after.inIt, 100000, reason: 'the same Rs. 1,000, one month on');
  });

  test('REPAIR C: deleting and re-recording at the full fee does not help',
      () async {
    final entangled = await (db.select(db.payments)
          ..where((p) =>
              p.memberId.equals(memberId) &
              p.paymentDate.isBiggerOrEqualValue(DateTime.utc(2026, 4, 1))))
        .get();
    for (final payment in entangled) {
      expect(await editor.delete(paymentId: payment.id, actorId: adminId),
          isA<PaymentDeleted>());
    }

    await runStartupMaintenance(db, now: DateTime.utc(2026, 9, 15));

    // April is unpaid again, but it has ended — and arrears keep the price
    // they were incurred at, so re-pricing leaves it at Rs. 1,500 on purpose.
    final april = (await periodsForMember(db, memberId))
        .firstWhere((p) => p.periodStart.toUtc() == DateTime.utc(2026, 4, 1));
    expect(april.expectedAmountMinor, 150000,
        reason: 'deleting payments cannot re-price a month that has ended');

    // So paying Rs. 2,500 into it spills Rs. 1,000 all over again.
    await collect(250000, DateTime.utc(2026, 4, 4), 'repair-c-apr');
    final may = (await periodsForMember(db, memberId))
        .firstWhere((p) => p.periodStart.toUtc() == DateTime.utc(2026, 5, 1));
    expect((await collectedByPeriod(db, [may.id]))[may.id], 100000,
        reason: 'the treadmill restarts from the same mis-priced month');
  });

  test('REPAIR D: delete, then pay each month what it was actually billed',
      () async {
    final entangled = await (db.select(db.payments)
          ..where((p) =>
              p.memberId.equals(memberId) &
              p.paymentDate.isBiggerOrEqualValue(DateTime.utc(2026, 4, 1))))
        .get();
    for (final payment in entangled) {
      await editor.delete(paymentId: payment.id, actorId: adminId);
    }

    // April was billed Rs. 1,500, so Rs. 1,500 closes it. Every month after it
    // was billed Rs. 2,500 and takes Rs. 2,500.
    await collect(150000, DateTime.utc(2026, 4, 4), 'repair-d-apr');
    for (final on in [
      DateTime.utc(2026, 5, 4),
      DateTime.utc(2026, 6, 4),
      DateTime.utc(2026, 7, 3),
      DateTime.utc(2026, 8, 4),
      DateTime.utc(2026, 9, 6),
    ]) {
      await runStartupMaintenance(db, now: on);
      await collect(250000, on, 'repair-d-${on.month}');
    }

    expect((await look(DateTime.utc(2026, 9, 15))).status, MemberStatus.paid);

    final all = await periodsForMember(db, memberId);
    expect(all.where((p) => p.settledAt == null), isEmpty,
        reason: 'every month closed by its own payment');
    expect(all.map((p) => p.periodStart.toUtc()).toList(), [
      for (var m = 1; m <= 9; m++) DateTime.utc(2026, m, 1),
    ], reason: 'nine months, nine cycles, no phantom tenth');
  });
}
