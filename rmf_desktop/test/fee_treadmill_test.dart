import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/startup_maintenance.dart';
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

/// The fee rise that left the gym's members owing money for ever.
///
/// A cycle snapshots its fee when it opens. A cycle that opened at Rs. 1,500
/// and is then paid Rs. 2,500 settles, and the Rs. 1,000 over spills into the
/// next cycle under arrears-first allocation — opening it early and part-paying
/// it. A cycle row is a debt, so from that moment the member permanently
/// carries one more open cycle than they were billed for, and every later
/// payment clears the previous shortfall while creating an identical one. They
/// paid Rs. 2,500 in full every month and the app showed them Rs. 1,500 short
/// for ever, reporting "Overdue since 01 Sep 2026" on a member who owed
/// nothing.
///
/// `repriceOpenCycles` already refuses to touch a cycle holding money, so once
/// the spill has happened nothing can unpick it automatically. The fix is
/// therefore to make sure the stale price never survives long enough to be paid
/// into: startup maintenance re-prices open, unfunded, not-yet-ended cycles
/// before the owner can record anything against them.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late BillingCycleService cycles;
  late int adminId;
  late int studentPlanId;

  const oldFee = 150000; // Rs. 1,500
  const newFee = 250000; // Rs. 2,500

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    cycles = BillingCycleService(db);
    adminId = (await db.select(db.users).getSingle()).id;

    studentPlanId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                name: 'Student',
                durationMonths: 1,
                priceMinor: oldFee,
              ),
            ))
        .id;

    final workspace = await Directory.systemTemp.createTemp('rmf-treadmill');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
  });

  tearDown(() async => db.close());

  Future<void> payOn(int memberId, DateTime day, int amountMinor) =>
      payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: amountMinor,
        method: PaymentMethod.cash,
        paymentDate: day,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'pay-${day.toIso8601String()}-$amountMinor',
      ));

  Future<int> joinedInJanuary() => members.create(
        fullName: 'Abdul Qadir',
        phone: '+923254097472',
        planId: studentPlanId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

  /// Raises the plan price the way a release without re-pricing did: the column
  /// moves and the cycle the member is already in keeps the old figure.
  Future<void> raisePriceQuietly() =>
      (db.update(db.membershipPlans)..where((p) => p.id.equals(studentPlanId)))
          .write(const MembershipPlansCompanion(priceMinor: Value(newFee)));

  /// Jan-Apr billed and paid at Rs. 1,500, then the May cycle opens at the old
  /// fee and only afterwards does the price rise reach the member.
  Future<int> memberCaughtByTheRise() async {
    final memberId = await joinedInJanuary();

    for (var month = 1; month <= 4; month++) {
      final on = DateTime.utc(2026, month, 4);
      await BillingMaintenance(db).ensureCurrentPeriods(now: on);
      await payOn(memberId, on, oldFee);
    }

    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 5, 4));
    await raisePriceQuietly();
    return memberId;
  }

  test('a stale price on an unpaid cycle is corrected before it can be paid',
      () async {
    final memberId = await memberCaughtByTheRise();

    // The owner opens the app. Nothing has been paid into May yet, so its
    // price is a bill nobody has issued and it must follow the current fee.
    await runStartupMaintenance(db, now: DateTime.utc(2026, 5, 4));

    final may = (await periodsForMember(db, memberId)).firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 5, 1));
    expect(may.expectedAmountMinor, newFee);
  });

  test('paying the full fee every month leaves nothing owing', () async {
    final memberId = await memberCaughtByTheRise();

    for (final on in [
      DateTime.utc(2026, 5, 4),
      DateTime.utc(2026, 6, 4),
      DateTime.utc(2026, 7, 3),
      DateTime.utc(2026, 8, 4),
    ]) {
      await runStartupMaintenance(db, now: on);
      await payOn(memberId, on, newFee);
    }

    await runStartupMaintenance(db, now: DateTime.utc(2026, 9, 15));
    final row = await members.byId(memberId, now: DateTime.utc(2026, 9, 15));

    expect(row!.status, MemberStatus.due,
        reason: 'September is genuinely unpaid — that much is right');
    expect(row.outstandingMinor, newFee,
        reason: 'they owe one whole month, not a month plus a phantom 1,500');

    final billing = await cycles.forMember(memberId);
    expect(billing!.nextUnsettled!.collectedMinor, 0,
        reason: 'nothing spilled forward out of the previous payment');
  });

  test('no cycle is opened early by a leftover part of a payment', () async {
    final memberId = await memberCaughtByTheRise();

    for (final on in [
      DateTime.utc(2026, 5, 4),
      DateTime.utc(2026, 6, 4),
      DateTime.utc(2026, 7, 3),
      DateTime.utc(2026, 8, 4),
    ]) {
      await runStartupMaintenance(db, now: on);
      await payOn(memberId, on, newFee);
    }

    final all = await periodsForMember(db, memberId);
    expect(all.map((p) => p.periodStart.toUtc()).toList(), [
      for (var m = 1; m <= 8; m++) DateTime.utc(2026, m, 1),
    ], reason: 'eight months lived is eight cycles; a ninth is the phantom');
    expect(all.where((p) => p.settledAt == null), isEmpty,
        reason: 'every month they paid for is closed');
  });

  test('a month they owe from before the rise keeps the price of the day',
      () async {
    // Arrears are not a bill waiting to be issued: January was incurred at
    // Rs. 1,500 and must stay Rs. 1,500, whatever the fee is now.
    final memberId = await joinedInJanuary();
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 1, 4));
    await raisePriceQuietly();

    await runStartupMaintenance(db, now: DateTime.utc(2026, 3, 10));

    final january = (await periodsForMember(db, memberId)).firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 1, 1));
    expect(january.expectedAmountMinor, oldFee);
  });

  test('a part-paid cycle keeps the price the member paid against', () async {
    final memberId = await joinedInJanuary();
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 1, 4));
    await payOn(memberId, DateTime.utc(2026, 1, 4), 50000); // Rs. 500 on account
    await raisePriceQuietly();

    await runStartupMaintenance(db, now: DateTime.utc(2026, 1, 20));

    final january = (await periodsForMember(db, memberId)).firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 1, 1));
    expect(january.expectedAmountMinor, oldFee,
        reason: 'moving the price after they part-paid backdates the rise');
  });
}
