import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/payment_edit_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

class _StubRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async {
    final bytes = Uint8List.fromList(data.receiptNumber.codeUnits);
    return RenderedReceipt(pdf: bytes, png: bytes);
  }
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  /// Mimics a file another program still has open: the delete quietly does
  /// nothing, exactly as ReceiptStorage.delete does when the OS refuses.
  bool refuseDeletes = false;

  @override
  Future<Directory> root() async => _dir;

  @override
  Future<void> delete(String relativePath) async {
    if (refuseDeletes) return;
    return super.delete(relativePath);
  }
}

class _StubClient implements WhatsAppClient {
  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.mock;

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async =>
      const WhatsAppSendSuccess('stub.1');
}

/// Deleting a payment is the one operation here that destroys a financial
/// record on purpose. What has to survive it is the evidence that it happened.
void main() {
  late Directory workspace;
  late AppDatabase db;
  late _FakeStorage storage;
  late AuditRepository audit;
  late RecordPaymentService recorder;
  late PaymentEditService editor;
  late int adminId;
  late int memberId;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-payment-delete');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);

    storage = _FakeStorage(workspace);
    audit = AuditRepository(db);
    recorder = RecordPaymentService(
      db: db,
      renderer: _StubRenderer(),
      storage: storage,
      clientFactory: () async => _StubClient(),
    );
    editor = PaymentEditService(
      db: db,
      renderer: _StubRenderer(),
      storage: storage,
      audit: audit,
      payments: recorder,
    );

    adminId = (await db.select(db.users).getSingle()).id;
    memberId = await MemberRepository(db).create(
      fullName: 'Ali Raza',
      phone: '+923000000001',
      planId: (await (db.select(db.membershipPlans)
                ..where((p) => p.name.equals('Monthly')))
              .getSingle())
          .id,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  Future<RecordPaymentResult> record({
    String billingMonth = '2026-08',
    int amountMinor = 300000,
    bool sendWhatsApp = false,
    String key = 'pay-1',
  }) =>
      recorder.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: amountMinor,
        method: PaymentMethod.cash,
        paymentDate: DateTime(2026, 8, 15),
        billingMonth: billingMonth,
        sendWhatsApp: sendWhatsApp,
        recordedById: adminId,
        idempotencyKey: key,
      ));

  test('removes the payment, its receipt and its send attempts', () async {
    final recorded = await record(sendWhatsApp: true);
    expect(await db.select(db.whatsAppMessages).get(), hasLength(1));

    final result = await editor.delete(
        paymentId: recorded.paymentId, actorId: adminId);

    expect(result, isA<PaymentDeleted>());
    expect(await db.select(db.payments).get(), isEmpty);
    expect(await db.select(db.receipts).get(), isEmpty);
    expect(await db.select(db.whatsAppMessages).get(), isEmpty,
        reason: 'attempts reference the receipt and must go with it');
  });

  test('removes the receipt files from disk', () async {
    final recorded = await record();
    expect(await storage.read('${recorded.receiptNumber}.png'), isNotNull);

    final result = await editor.delete(
        paymentId: recorded.paymentId, actorId: adminId) as PaymentDeleted;

    expect(result.hasOrphanedFiles, isFalse);
    expect(await storage.read('${recorded.receiptNumber}.png'), isNull);
    expect(await storage.read('${recorded.receiptNumber}.pdf'), isNull);
  });

  test('leaves the billing cycle behind, reading DUE again', () async {
    final recorded = await record();
    final august = await db.select(db.membershipPeriods).getSingle();

    await editor.delete(paymentId: recorded.paymentId, actorId: adminId);

    final periods = await db.select(db.membershipPeriods).get();
    expect(periods, hasLength(1),
        reason: 'the month is still a month the member owes for');

    expect(
      deriveMemberStatus(
        deactivatedAt: null,
        periods: [
          StatusPeriod(
            periodStart: august.periodStart.toUtc(),
            periodEnd: august.periodEnd.toUtc(),
            isPaid: false,
          ),
        ],
        now: DateTime.utc(2026, 8, 20),
      ),
      MemberStatus.due,
    );
  });

  test('does not rewind the receipt counter', () async {
    final first = await record(key: 'pay-1');
    await editor.delete(paymentId: first.paymentId, actorId: adminId);

    final counter = await db.select(db.receiptCounters).getSingle();
    expect(counter.lastNumber, 1,
        reason: 'a gap is harmless; reissuing a number the member already '
            'holds a copy of is not');

    final second = await record(key: 'pay-2');
    expect(second.receiptNumber, isNot(first.receiptNumber));
  });

  test('the money leaves the revenue total', () async {
    final recorded = await record();
    final payments = PaymentRepository(db);

    final from = DateTime(2026, 8, 1);
    final to = DateTime(2026, 9, 1);
    expect(await payments.totalMinorBetween(from, to), 300000);

    await editor.delete(paymentId: recorded.paymentId, actorId: adminId);

    expect(await payments.totalMinorBetween(from, to), 0);
    expect(await payments.countBetween(from, to), 0);
  });

  group('the audit trail', () {
    test('outlives the payment it describes', () async {
      final recorded = await record();

      await editor.delete(paymentId: recorded.paymentId, actorId: adminId);

      final event = (await db.select(db.auditEvents).get())
          .firstWhere((e) => e.action == AuditAction.paymentDeleted);

      // Everything needed to answer "what was deleted" without the row.
      expect(event.memberName, 'Ali Raza');
      expect(event.memberId, memberId);
      expect(event.paymentId, recorded.paymentId);
      expect(event.receiptNumber, recorded.receiptNumber);
      expect(event.amountMinor, 300000);
      expect(event.periodLabel, 'August 2026');
      expect(event.actorName, isNotNull);
      expect(event.summary, contains('Rs. 3,000'));
      expect(event.summary, contains('Ali Raza'));
      expect(event.detail, contains('Method: Cash'));
    });

    test('describes a multi-month cycle by both its months', () async {
      // A quarterly member, so the log cannot fall back to naming one month.
      final quarterly = await MemberRepository(db).create(
        fullName: 'Bilal Ahmed',
        phone: '+923000000002',
        planId: (await (db.select(db.membershipPlans)
                  ..where((p) => p.name.equals('Quarterly')))
                .getSingle())
            .id,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

      final recorded = await recorder.call(RecordPaymentInput(
        memberId: quarterly,
        amountMinor: 800000,
        method: PaymentMethod.cash,
        paymentDate: DateTime(2026, 8, 15),
        billingMonth: '2026-08',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'pay-q',
      ));

      await editor.delete(paymentId: recorded.paymentId, actorId: adminId);

      final event = (await db.select(db.auditEvents).get())
          .firstWhere((e) => e.action == AuditAction.paymentDeleted);
      expect(event.periodLabel, 'August 2026 - October 2026');
    });
  });

  test('a file that cannot be removed does not undo the deletion', () async {
    final recorded = await record();
    storage.refuseDeletes = true;

    final result = await editor.delete(
        paymentId: recorded.paymentId, actorId: adminId) as PaymentDeleted;

    // The database part succeeded and is reported as such.
    expect(await db.select(db.payments).get(), isEmpty);
    expect(result.hasOrphanedFiles, isTrue);
    expect(result.orphanedFiles, hasLength(2));

    final orphanEvents = (await db.select(db.auditEvents).get())
        .where((e) => e.action == AuditAction.receiptFilesOrphaned);
    expect(orphanEvents, hasLength(1));
    expect(orphanEvents.single.outcome, AuditOutcome.failed);
    expect(orphanEvents.single.detail, contains('deleted successfully'));
  });

  test('an imported payment with no receipt deletes cleanly', () async {
    final membership = await (db.select(db.memberships)
          ..where((m) => m.memberId.equals(memberId)))
        .getSingle();
    final period = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: DateTime.utc(2026, 3, 1),
            periodEnd: DateTime.utc(2026, 4, 1),
            expectedAmountMinor: 300000,
          ),
        );
    final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            membershipPeriodId: Value(period.id),
            amountMinor: 250000,
            method: PaymentMethod.cash,
            paymentDate: DateTime.utc(2026, 3, 5),
            source: const Value(PaymentSource.imported),
            recordedById: adminId,
            idempotencyKey: 'import-2026-1-3',
          ),
        );

    final result =
        await editor.delete(paymentId: paymentId, actorId: adminId);

    expect(result, isA<PaymentDeleted>());
    expect((result as PaymentDeleted).receiptNumber, isNull);
    expect(result.hasOrphanedFiles, isFalse);
    expect(await db.select(db.payments).get(), isEmpty);
  });

  test('deleting the same payment twice is refused, not crashed on', () async {
    final recorded = await record();

    await editor.delete(paymentId: recorded.paymentId, actorId: adminId);
    final second = await editor.delete(
        paymentId: recorded.paymentId, actorId: adminId);

    expect(second, isA<PaymentDeleteRefused>());
    expect((second as PaymentDeleteRefused).message,
        'That payment has already been deleted.');
  });
}
