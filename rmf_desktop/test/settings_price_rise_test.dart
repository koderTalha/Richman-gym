import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
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

/// The gym's actual sequence: a Student plan sold at Rs. 1,500, a few months
/// collected at that price, then the price edited to Rs. 2,500 in Settings.
///
/// This is the path the owner says he took, so it is the path that has to be
/// proven safe — for a member on the plan price and for a member carrying their
/// own fee, which `repriceOpenCyclesForPlan` deliberately skips.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late SettingsRepository settings;
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
    settings = SettingsRepository(db);
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

    final workspace = await Directory.systemTemp.createTemp('rmf-settings');
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
        idempotencyKey: 'pay-$memberId-${day.toIso8601String()}',
      ));

  /// The owner edits the Student plan's price in Settings.
  Future<void> raisePriceInSettings(DateTime on) => settings.savePlan(
        id: studentPlanId,
        name: 'Student',
        durationMonths: 1,
        priceMinor: newFee,
        isActive: true,
        actorId: adminId,
        now: on,
      );

  /// Joined 1 Jan, paid Jan-Mar at Rs. 1,500, and is now sitting in an open
  /// April cycle priced at Rs. 1,500 when the owner goes into Settings.
  Future<int> memberPaidToMarch({int? feeOverrideMinor}) async {
    final memberId = await members.create(
      fullName: 'Abdul Qadir',
      phone: '+92325409747${feeOverrideMinor == null ? 1 : 2}',
      planId: studentPlanId,
      feeOverrideMinor: feeOverrideMinor,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    for (var month = 1; month <= 3; month++) {
      final on = DateTime.utc(2026, month, 4);
      await BillingMaintenance(db).ensureCurrentPeriods(now: on);
      await payOn(memberId, on, oldFee);
    }
    // April's cycle opens at the old price, the way it would have before the
    // owner sat down to change it.
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 4, 1));
    return memberId;
  }

  Future<int> aprilPrice(int memberId) async =>
      (await periodsForMember(db, memberId))
          .firstWhere((p) => p.periodStart.toUtc() == DateTime.utc(2026, 4, 1))
          .expectedAmountMinor;

  test('a member on the plan price has their open April re-priced', () async {
    final memberId = await memberPaidToMarch();

    await raisePriceInSettings(DateTime.utc(2026, 4, 2));

    expect(await aprilPrice(memberId), newFee,
        reason: 'the Settings edit carries through to the unpaid cycle');
  });

  test('a member on the plan price does not start the treadmill', () async {
    final memberId = await memberPaidToMarch();
    await raisePriceInSettings(DateTime.utc(2026, 4, 2));

    for (final on = DateTime.utc(2026, 4, 4);;) {
      for (final day in [
        on,
        DateTime.utc(2026, 5, 4),
        DateTime.utc(2026, 6, 4),
      ]) {
        await BillingMaintenance(db).ensureCurrentPeriods(now: day);
        await payOn(memberId, day, newFee);
      }
      break;
    }

    final billing = await cycles.forMember(memberId);
    expect(billing!.nextUnsettled?.collectedMinor ?? 0, 0,
        reason: 'no fragment of a payment spilled into the next cycle');
    expect((await members.byId(memberId, now: DateTime.utc(2026, 6, 20)))!.status,
        MemberStatus.paid);
  });

  test('a member carrying their own fee is skipped by the Settings edit',
      () async {
    // The plan dialog promises these members are unaffected, and they are.
    final memberId = await memberPaidToMarch(feeOverrideMinor: oldFee);

    await raisePriceInSettings(DateTime.utc(2026, 4, 2));

    expect(await aprilPrice(memberId), oldFee,
        reason: 'their fee is their own, so the plan price is not theirs to '
            'feel — and Rs. 1,500 is still what they are asked for');
  });
}
