import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

/// Skips rasterising, which needs platform channels.
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

/// Raising a member's fee while their current cycle is still unpaid.
///
/// A cycle snapshots its fee when it opens, which is what keeps a price rise
/// from rewriting months the member has already paid. But a cycle nobody has
/// put a rupee into is not history — it is a bill that has not been issued
/// yet, and leaving it at the old price is what produced the gym's
/// "payment is always due" report:
///
/// The member's March cycle opened at 1500. The owner raised the fee to 2500
/// and collected 2500. Only 1500 of it fitted in March, so the remaining 1000
/// spilled forward, opened April's cycle early and part-paid it. From then on
/// every payment landed one cycle ahead of where the owner thought it was
/// going: the member paid 2500 every month, in full and on time, and the app
/// showed them owing 1500 for ever.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late SettingsRepository settings;
  late RecordPaymentService payments;
  late int adminId;
  late int monthlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    settings = SettingsRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    // The gym's monthly fee starts at 1500.
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(150000)));

    final workspace = await Directory.systemTemp.createTemp('rmf-reprice');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
  });

  tearDown(() async => db.close());

  Future<int> joinOn(DateTime joiningDate, {String phone = '+923000000001'}) =>
      members.create(
        fullName: 'Ali Khan',
        phone: phone,
        planId: monthlyId,
        joiningDate: joiningDate,
      );

  Future<void> openCycleOn(DateTime day) =>
      BillingMaintenance(db).ensureCurrentPeriods(now: day);

  Future<void> pay(int memberId, int rupees, DateTime on) =>
      payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: rupees * 100,
        method: PaymentMethod.cash,
        paymentDate: on,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'pay-${on.toIso8601String()}',
      ));

  Future<void> raisePlanPriceTo(int rupees, DateTime on) => settings.savePlan(
        id: monthlyId,
        name: 'Monthly',
        durationMonths: 1,
        priceMinor: rupees * 100,
        isActive: true,
        now: on,
      );

  Future<List<MembershipPeriod>> cyclesOf(int memberId) =>
      periodsForMember(db, memberId);

  Future<MembershipPeriod> cycleStarting(int memberId, DateTime start) async =>
      (await cyclesOf(memberId))
          .firstWhere((p) => p.periodStart.toUtc() == start);

  /// Sets, changes or — with null — removes the member's own fee, the way the
  /// Edit Member form does.
  Future<void> setFee(int memberId, int? feeMinor, {required DateTime on}) =>
      members.update(
        id: memberId,
        fullName: 'Ali Khan',
        phone: '+923000000001',
        planId: monthlyId,
        feeOverrideMinor: feeMinor,
        joiningDate: DateTime.utc(2026, 1, 6),
        now: on,
      );

  Future<int> planIdNamed(String name) async => (await (db
          .select(db.membershipPlans)
        ..where((p) => p.name.equals(name)))
      .getSingle())
      .id;

  test('the fee rise reaches a cycle nobody has paid into yet', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 1, 6));

    await raisePlanPriceTo(2500, DateTime.utc(2026, 1, 10));

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 250000,
        reason: 'an unpaid cycle is a bill not yet issued, not history');
  });

  test('a member paying the new fee every month never falls behind', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));

    // Two months at the old fee, paid in full.
    for (var month = 1; month <= 2; month++) {
      await openCycleOn(DateTime.utc(2026, month, 6));
      await pay(memberId, 1500, DateTime.utc(2026, month, 6));
    }

    // March's cycle opens at the old fee, and the owner raises the price
    // four days later — before the member has paid anything towards it.
    await openCycleOn(DateTime.utc(2026, 3, 6));
    await raisePlanPriceTo(2500, DateTime.utc(2026, 3, 10));

    // From here the member pays the new fee, in full, every month.
    for (var month = 3; month <= 8; month++) {
      await openCycleOn(DateTime.utc(2026, month, 10));
      await pay(memberId, 2500, DateTime.utc(2026, month, 10));
    }

    final row = await members.byId(memberId, now: DateTime.utc(2026, 8, 11));
    expect(row!.outstandingMinor, isNull,
        reason: 'they have paid every rupee asked of them — null is how a '
            'member with no unsettled cycle reads');
    expect(row.status, MemberStatus.paid);

    final cycles = await cyclesOf(memberId);
    expect(cycles.length, 8,
        reason: 'eight months lived is eight cycles — a ninth was the spill '
            'opening next month early and part-paying it');
    expect(cycles.where((c) => c.settledAt == null), isEmpty);
  });

  test('a cycle they have already paid keeps the price they paid', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 1, 6));
    await pay(memberId, 1500, DateTime.utc(2026, 1, 6));

    await raisePlanPriceTo(2500, DateTime.utc(2026, 1, 10));

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 150000,
        reason: 'rewriting a settled month would reopen a closed debt');
    expect(january.settledAt, isNotNull);
  });

  test('a part-paid cycle keeps its price', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 1, 6));
    await pay(memberId, 500, DateTime.utc(2026, 1, 6));

    await raisePlanPriceTo(2500, DateTime.utc(2026, 1, 10));

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 150000,
        reason: 'money against a cycle is the member acting on the old price; '
            'raising it afterwards would backdate the rise');
  });

  test('a month they never paid is not re-priced once it has passed',
      () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 1, 6));
    // February rolls round with January still unpaid.
    await openCycleOn(DateTime.utc(2026, 2, 6));

    await raisePlanPriceTo(2500, DateTime.utc(2026, 2, 10));

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 150000,
        reason: 'arrears were incurred at the old price and must stay there');

    final february = await cycleStarting(memberId, DateTime.utc(2026, 2, 6));
    expect(february.expectedAmountMinor, 250000,
        reason: 'the cycle they are actually in still re-prices');
  });

  test('moving the member onto a dearer plan re-prices the same way', () async {
    final dearId = await db.into(db.membershipPlans).insert(
          MembershipPlansCompanion.insert(
            name: 'Monthly 2500',
            durationMonths: 1,
            priceMinor: 250000,
          ),
        );

    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 1, 6));

    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: dearId,
      joiningDate: DateTime.utc(2026, 1, 6),
      now: DateTime.utc(2026, 1, 10),
    );

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 250000);
  });

  test('a per-member fee override re-prices the same way', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 1, 6));

    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: monthlyId,
      feeOverrideMinor: 250000,
      joiningDate: DateTime.utc(2026, 1, 6),
      now: DateTime.utc(2026, 1, 10),
    );

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 250000);
  });

  test('a fee cut reaches an unpaid cycle too', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 1, 6));

    await raisePlanPriceTo(1000, DateTime.utc(2026, 1, 10));

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 100000,
        reason: 'the member should not be billed more than the plan now costs');
  });

  test('a deactivated member is left alone', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 1, 6));
    await members.setActive(memberId, false);

    await raisePlanPriceTo(2500, DateTime.utc(2026, 1, 10));

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 150000,
        reason: 'somebody who has left the gym is not re-billed');
  });

  // --- Dropping an override, and carrying one across a plan change ---------
  //
  // Removing a custom fee is expressed by *clearing* a text field, which makes
  // it the easiest pricing change to make by accident and the one worth
  // pinning down hardest: blank means "bill them what the plan costs", not
  // "bill them nothing" and not "leave the old override in place".

  test('removing a custom fee returns the member to the plan price', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await setFee(memberId, 200000, on: DateTime.utc(2026, 1, 2));
    await openCycleOn(DateTime.utc(2026, 1, 6));

    expect((await cycleStarting(memberId, DateTime.utc(2026, 1, 6)))
        .expectedAmountMinor, 200000);

    await setFee(memberId, null, on: DateTime.utc(2026, 1, 10));

    final membership = await openMembershipFor(db, memberId);
    expect(membership!.feeOverrideMinor, isNull,
        reason: 'the override is dropped, not left sitting at its old value');

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 150000,
        reason: 'they are back on the plan price of 1500');
  });

  test('removing a custom fee leaves a month they already paid alone',
      () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await setFee(memberId, 200000, on: DateTime.utc(2026, 1, 2));
    await openCycleOn(DateTime.utc(2026, 1, 6));
    await pay(memberId, 2000, DateTime.utc(2026, 1, 6));

    await setFee(memberId, null, on: DateTime.utc(2026, 1, 10));

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 200000,
        reason: 'they paid 2000 for January — re-pricing it to 1500 would '
            'turn a settled month into a 500 credit nobody granted');
    expect(january.settledAt, isNotNull);
  });

  test('a custom fee still wins after the member changes plan', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await setFee(memberId, 180000, on: DateTime.utc(2026, 1, 2));
    await openCycleOn(DateTime.utc(2026, 1, 6));

    // Gold costs 3000; the member's own fee of 1800 is what they keep paying.
    await settings.savePlan(
      name: 'Gold',
      durationMonths: 1,
      priceMinor: 300000,
      isActive: true,
    );
    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: await planIdNamed('Gold'),
      feeOverrideMinor: 180000,
      joiningDate: DateTime.utc(2026, 1, 6),
      now: DateTime.utc(2026, 1, 10),
    );

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 180000,
        reason: 'an override outranks whichever plan they are on');
  });

  test('dropping the override on a plan change bills the new plan', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));
    await setFee(memberId, 180000, on: DateTime.utc(2026, 1, 2));
    await openCycleOn(DateTime.utc(2026, 1, 6));

    await settings.savePlan(
      name: 'Gold',
      durationMonths: 1,
      priceMinor: 300000,
      isActive: true,
    );
    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: await planIdNamed('Gold'),
      feeOverrideMinor: null,
      joiningDate: DateTime.utc(2026, 1, 6),
      now: DateTime.utc(2026, 1, 10),
    );

    final january = await cycleStarting(memberId, DateTime.utc(2026, 1, 6));
    expect(january.expectedAmountMinor, 300000,
        reason: 'no override left, so Gold\'s own price applies');
  });

  test('six months across a plan switch stays six cycles and settles',
      () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6));

    // Three months on Monthly at 1500, paid in full.
    for (var month = 1; month <= 3; month++) {
      await openCycleOn(DateTime.utc(2026, month, 6));
      await pay(memberId, 1500, DateTime.utc(2026, month, 6));
    }

    // April's cycle opens at 1500, then the member moves to Gold at 3000
    // before paying anything towards it.
    await openCycleOn(DateTime.utc(2026, 4, 6));
    await settings.savePlan(
      name: 'Gold',
      durationMonths: 1,
      priceMinor: 300000,
      isActive: true,
    );
    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: await planIdNamed('Gold'),
      joiningDate: DateTime.utc(2026, 1, 6),
      now: DateTime.utc(2026, 4, 8),
    );

    for (var month = 4; month <= 6; month++) {
      await openCycleOn(DateTime.utc(2026, month, 8));
      await pay(memberId, 3000, DateTime.utc(2026, month, 8));
    }

    final cycles = await cyclesOf(memberId);
    expect(cycles, hasLength(6),
        reason: 'six months lived is six cycles, plan change or not');
    expect(cycles.where((c) => c.settledAt == null), isEmpty);

    final row = await members.byId(memberId, now: DateTime.utc(2026, 6, 9));
    expect(row!.outstandingMinor, isNull);
    expect(row.status, MemberStatus.paid);

    // The three months before the switch keep the price that was charged.
    for (var month = 1; month <= 3; month++) {
      final cycle = await cycleStarting(memberId, DateTime.utc(2026, month, 6));
      expect(cycle.expectedAmountMinor, 150000,
          reason: 'moving to a dearer plan must not re-price paid history');
    }
  });
}
