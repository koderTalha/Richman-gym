import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/billing_reconciliation.dart';
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

/// Finding the members an earlier release left stuck.
///
/// Re-pricing unpaid cycles stops the "always due" treadmill from starting,
/// but it cannot rescue a member already on it: their money has been spread
/// across cycles in a way that looks, in the database, exactly like a genuine
/// arrears payment. Nothing here rewrites any of it. It reports the one
/// contradiction that is safe to assert — a member who has handed over at
/// least as much as they have been billed for, and whom the app still shows
/// owing money — and leaves the correction to the owner, who knows what was
/// actually agreed.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late int adminId;
  late int monthlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(150000)));

    final workspace = await Directory.systemTemp.createTemp('rmf-reconcile');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
  });

  tearDown(() async => db.close());

  Future<int> joinOn(DateTime joiningDate, {required String phone}) =>
      members.create(
        fullName: 'Member $phone',
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
        idempotencyKey: 'pay-$memberId-${on.toIso8601String()}',
        confirmedAdvance: true,
      ));

  /// Raises the fee the way the release that caused this did: straight onto
  /// the plan row, leaving every already-open cycle at the old price.
  Future<void> raisePriceLeavingOpenCyclesStale(int rupees) =>
      (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
          .write(MembershipPlansCompanion(priceMinor: Value(rupees * 100)));

  /// Puts a member on the treadmill: paid in full every month, still owing.
  Future<int> stuckMember({String phone = '+923000000001'}) async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6), phone: phone);

    for (var month = 1; month <= 2; month++) {
      await openCycleOn(DateTime.utc(2026, month, 6));
      await pay(memberId, 1500, DateTime.utc(2026, month, 6));
    }

    await openCycleOn(DateTime.utc(2026, 3, 6));
    await raisePriceLeavingOpenCyclesStale(2500);

    for (var month = 3; month <= 6; month++) {
      await openCycleOn(DateTime.utc(2026, month, 10));
      await pay(memberId, 2500, DateTime.utc(2026, month, 10));
    }
    return memberId;
  }

  test('the treadmill really is still reproducible from a stale price',
      () async {
    final memberId = await stuckMember();
    final row = await members.byId(memberId, now: DateTime.utc(2026, 6, 20));
    expect(row!.outstandingMinor, 150000,
        reason: 'this is the state the owner reported');
  });

  test('a member who has paid more than they were billed is reported',
      () async {
    final memberId = await stuckMember();

    final found = await findBillingDiscrepancies(
      db,
      now: DateTime.utc(2026, 6, 20),
    );

    expect(found.map((d) => d.member.id), [memberId]);
    final discrepancy = found.single;
    expect(discrepancy.outstandingMinor, 150000,
        reason: 'what the app is telling the owner they owe');
    expect(discrepancy.creditMinor, 100000,
        reason: 'and what they are actually ahead by');
  });

  test('a member in genuine arrears is not reported', () async {
    final memberId = await joinOn(DateTime.utc(2026, 1, 6),
        phone: '+923000000002');
    await openCycleOn(DateTime.utc(2026, 1, 6));
    await openCycleOn(DateTime.utc(2026, 2, 6));

    final found =
        await findBillingDiscrepancies(db, now: DateTime.utc(2026, 2, 20));

    expect(found, isEmpty,
        reason: 'they owe the money the app says they owe — nothing to '
            'second-guess, and flagging it would bury the real cases');
    expect(memberId, isNotNull);
  });

  test('a member who has paid everything and owes nothing is not reported',
      () async {
    await joinOn(DateTime.utc(2026, 1, 6), phone: '+923000000003')
        .then((id) async {
      await openCycleOn(DateTime.utc(2026, 1, 6));
      await pay(id, 1500, DateTime.utc(2026, 1, 6));
    });

    final found =
        await findBillingDiscrepancies(db, now: DateTime.utc(2026, 1, 20));

    expect(found, isEmpty);
  });

  test('a member who paid three months up front is not reported', () async {
    final memberId =
        await joinOn(DateTime.utc(2026, 1, 6), phone: '+923000000004');
    await openCycleOn(DateTime.utc(2026, 1, 6));
    await pay(memberId, 4500, DateTime.utc(2026, 1, 6));

    final found =
        await findBillingDiscrepancies(db, now: DateTime.utc(2026, 1, 20));

    expect(found, isEmpty,
        reason: 'being in credit is normal — it is being in credit *and* '
            'shown as owing that is the contradiction');
  });

  test('a deactivated member is not reported', () async {
    final memberId = await stuckMember();
    await members.setActive(memberId, false);

    final found =
        await findBillingDiscrepancies(db, now: DateTime.utc(2026, 6, 20));

    expect(found, isEmpty);
  });

  test('the owner can see it in the logs', () async {
    await stuckMember();

    await reportBillingDiscrepancies(db, now: DateTime.utc(2026, 6, 20));

    final events = await (db.select(db.auditEvents)
          ..where((e) => e.action.equals(AuditAction.billingDiscrepancyFound)))
        .get();

    expect(events, hasLength(1));
    expect(events.single.category, AuditCategory.billing);
    expect(events.single.outcome, AuditOutcome.refused,
        reason: 'the app declined to guess — this is not a failure');
    expect(events.single.summary, contains('1,500'),
        reason: 'the owner needs the number to recognise the member');
  });

  test('reporting twice does not log the same member twice', () async {
    await stuckMember();

    await reportBillingDiscrepancies(db, now: DateTime.utc(2026, 6, 20));
    await reportBillingDiscrepancies(db, now: DateTime.utc(2026, 6, 21));

    final events = await (db.select(db.auditEvents)
          ..where((e) => e.action.equals(AuditAction.billingDiscrepancyFound)))
        .get();

    expect(events, hasLength(1),
        reason: 'the log is opened to read, and one member repeated every '
            'morning would push everything else off the screen');
  });
}
