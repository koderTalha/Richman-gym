// AUDIT REPRO — payments area: side effects of PaymentEditService.edit.
//
// 1. An edit that changes only notes/method still deletes and re-inserts the
//    payment's allocation and calls refreshSettlement, which clears the
//    settled stamp of any cycle whose allocations are below its expected fee
//    — exactly the shape of every cycle the v10 migration grandfathered as
//    settled (allocation = MIN(amount, expected)) and of ledger rows imported
//    into an already-existing cycle.
//
// 2. The edit dialog derives billingMonth from the payment's cycle start
//    ("YYYY-MM"), and the service resolves that back with cycleToBillFor,
//    which picks the EARLIEST real cycle starting in that calendar month. When
//    a re-anchor produced a transition cycle in the same month, any edit moves
//    the payment off its own cycle onto the transition one.
//
// These tests assert the CORRECT behaviour and fail while the bugs exist.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/payment_edit_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

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
  late PaymentEditService editor;
  late int memberId;
  late int membershipId;
  late int adminId;

  const fee = 300000;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-audit-edit');
    db = AppDatabase.forTesting(NativeDatabase.memory());

    adminId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(const GymSettingsCompanion());
    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: fee));
    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ali Raza',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2025, 1, 1),
        ));
    membershipId = await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
            memberId: memberId,
            planId: planId,
            startDate: DateTime.utc(2025, 1, 1)));

    final storage = _FakeStorage(workspace);
    final recorder = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: storage,
      clientFactory: () async => MockWhatsAppClient(),
    );
    editor = PaymentEditService(
      db: db,
      renderer: _FakeRenderer(),
      storage: storage,
      audit: AuditRepository(db),
      payments: recorder,
    );
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  Future<int> cycle(DateTime start, DateTime end,
          {required int expected, DateTime? settledAt}) =>
      db.into(db.membershipPeriods).insert(MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: start,
            periodEnd: end,
            expectedAmountMinor: expected,
            settledAt: Value(settledAt),
          ));

  Future<int> payment(int periodId, int amount, DateTime on, String key) async {
    final id = await db.into(db.payments).insert(PaymentsCompanion.insert(
          memberId: memberId,
          membershipPeriodId: Value(periodId),
          amountMinor: amount,
          method: PaymentMethod.cash,
          paymentDate: on,
          recordedById: adminId,
          idempotencyKey: key,
        ));
    await db.into(db.paymentAllocations).insert(
        PaymentAllocationsCompanion.insert(
            paymentId: id, membershipPeriodId: periodId, amountMinor: amount));
    return id;
  }

  Future<MembershipPeriod> periodById(int id) =>
      (db.select(db.membershipPeriods)..where((p) => p.id.equals(id)))
          .getSingle();

  test(
      'changing only the notes of a grandfathered discounted payment keeps '
      'its month settled', () async {
    // Exactly what the v10 migration leaves behind for a month the owner
    // discounted: fee 3,000, collected 2,500, allocation capped at 2,500,
    // cycle stamped settled.
    final march = await cycle(DateTime.utc(2025, 3, 1), DateTime.utc(2025, 4, 1),
        expected: fee, settledAt: DateTime.utc(2025, 3, 2));
    final paid = await payment(march, 250000, DateTime.utc(2025, 3, 2), 'g-1');

    final result = await editor.edit(EditPaymentInput(
      paymentId: paid,
      amountMinor: 250000,
      method: PaymentMethod.cash,
      paymentDate: DateTime.utc(2025, 3, 2),
      billingMonth: '2025-03',
      editedById: adminId,
      notes: 'discount agreed at the counter',
    ));
    expect(result, isA<PaymentEdited>());
    expect((result as PaymentEdited).changes, hasLength(1),
        reason: 'only the notes changed');

    expect((await periodById(march)).settledAt, isNotNull,
        reason: 'editing a note must not re-open a month that has been '
            'closed for over a year and make the member read as owing 500');
  });

  test(
      'editing a payment on the second cycle starting in a month leaves it on '
      'that cycle', () async {
    // Anchor moved from the 1st to the 15th: August on the old anchor, a
    // 1-15 September transition cycle (unpaid), then the regular 15 Sep cycle.
    await cycle(DateTime.utc(2026, 8, 1), DateTime.utc(2026, 9, 1),
        expected: fee, settledAt: DateTime.utc(2026, 8, 1));
    final transition = await cycle(
        DateTime.utc(2026, 9, 1), DateTime.utc(2026, 9, 15),
        expected: 140000);
    final regular = await cycle(
        DateTime.utc(2026, 9, 15), DateTime.utc(2026, 10, 15),
        expected: fee, settledAt: DateTime.utc(2026, 9, 15));
    final paid = await payment(regular, fee, DateTime.utc(2026, 9, 15), 'r-1');

    // What EditPaymentDialog sends: billingMonth is periodStart's YYYY-MM.
    await editor.edit(EditPaymentInput(
      paymentId: paid,
      amountMinor: fee,
      method: PaymentMethod.cash,
      paymentDate: DateTime.utc(2026, 9, 15),
      billingMonth: '2026-09',
      editedById: adminId,
      notes: 'paid by brother',
    ));

    final after = await (db.select(db.payments)
          ..where((p) => p.id.equals(paid)))
        .getSingle();
    expect(after.membershipPeriodId, regular,
        reason: 'a notes-only edit must not move the money onto the '
            '1-15 September transition cycle');
    expect((await periodById(regular)).settledAt, isNotNull);
    expect((await periodById(transition)).settledAt, isNull);
  });
}
