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

/// Clearing a member's whole payment history in one action.
///
/// The owner's route out of a member whose history has to be typed up again
/// from the paper ledger. It is the most destructive thing in the app — every
/// receipt the member was ever given stops existing — so it goes through the
/// same per-payment delete as the single-row button, leaves a summary in the
/// log, and refuses quietly when there is nothing to remove.
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

    final workspace = await Directory.systemTemp.createTemp('rmf-clear');
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

  Future<List<AuditEvent>> auditFor(String action) =>
      (db.select(db.auditEvents)..where((e) => e.action.equals(action))).get();

  test('removes every payment the member has', () async {
    final before = await (db.select(db.payments)
          ..where((p) => p.memberId.equals(memberId)))
        .get();
    expect(before, hasLength(8), reason: 'Jan-Mar at 1,500, Apr-Aug at 2,500');

    final result =
        await editor.deleteAllForMember(memberId: memberId, actorId: adminId);

    expect(result, isA<AllPaymentsDeleted>());
    result as AllPaymentsDeleted;
    expect(result.deletedCount, 8);
    expect(result.totalMinor, 1700000, reason: 'Rs. 17,000 removed');
    expect(result.memberName, 'Abdul Qadir');

    expect(
        await (db.select(db.payments)..where((p) => p.memberId.equals(memberId)))
            .get(),
        isEmpty);
  });

  test('every billing cycle reads as unpaid again', () async {
    await editor.deleteAllForMember(memberId: memberId, actorId: adminId);

    final cycles = await periodsForMember(db, memberId);
    expect(cycles, isNotEmpty, reason: 'the cycles themselves are not removed');
    expect(cycles.every((c) => c.settledAt == null), isTrue);

    final money = await collectedByPeriod(db, [for (final c in cycles) c.id]);
    expect(money, isEmpty, reason: 'no allocation survives the delete');

    expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!.status,
        MemberStatus.due);
  });

  test('receipts and their send history go with the payments', () async {
    await editor.deleteAllForMember(memberId: memberId, actorId: adminId);

    expect(await db.select(db.receipts).get(), isEmpty);
    expect(await db.select(db.whatsAppMessages).get(), isEmpty);
  });

  test('the log says what was cleared, once, on top of the per-payment rows',
      () async {
    await editor.deleteAllForMember(memberId: memberId, actorId: adminId);

    expect(await auditFor(AuditAction.paymentDeleted), hasLength(8),
        reason: 'the existing per-payment trail is kept');

    final summary = await auditFor(AuditAction.paymentsCleared);
    expect(summary, hasLength(1));
    expect(summary.single.memberId, memberId);
    expect(summary.single.amountMinor, 1700000);
    expect(summary.single.summary, contains('Abdul Qadir'));
    expect(summary.single.summary, contains('8'));
  });

  test('a member with no payments is refused rather than logged', () async {
    final empty = await members.create(
      fullName: 'Bilal Ahmed',
      phone: '+923254097473',
      planId: planId,
      joiningDate: DateTime.utc(2026, 9, 1),
    );

    final result =
        await editor.deleteAllForMember(memberId: empty, actorId: adminId);

    expect(result, isA<ClearPaymentsRefused>());
    expect(await auditFor(AuditAction.paymentsCleared), isEmpty);
  });

  test('a member who no longer exists is refused', () async {
    final result =
        await editor.deleteAllForMember(memberId: 9999, actorId: adminId);

    expect(result, isA<ClearPaymentsRefused>());
  });

  test('the history can be typed up again straight afterwards', () async {
    await editor.deleteAllForMember(memberId: memberId, actorId: adminId);

    // Each month named explicitly, at what that month was actually billed.
    for (var month = 1; month <= 9; month++) {
      await payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: month <= 4 ? treadmillOldFee : treadmillNewFee,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, month, 4),
        billingMonth: '2026-${month.toString().padLeft(2, '0')}',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'retype-$month',
      ));
    }

    expect((await members.byId(memberId, now: DateTime.utc(2026, 9, 15)))!.status,
        MemberStatus.paid);
    final cycles = await periodsForMember(db, memberId);
    expect(cycles, hasLength(9));
    expect(cycles.every((c) => c.settledAt != null), isTrue);
  });
}
