import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/payment_edit_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// Renders a receipt whose bytes encode what it was asked to render, so a test
/// can tell a regenerated file from the original one.
class _RecordingRenderer extends ReceiptRenderer {
  final calls = <ReceiptData>[];

  @override
  Future<RenderedReceipt> render(ReceiptData data) async {
    calls.add(data);
    final marker = Uint8List.fromList('${data.amountLabel}|${data.billingPeriod}'
        .codeUnits);
    return RenderedReceipt(pdf: marker, png: marker);
  }
}

class _FailingRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      throw StateError('the rasteriser is unavailable');
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  /// Set to make saving fail the way a locked file on Windows does.
  bool failSaves = false;

  @override
  Future<Directory> root() async => _dir;

  @override
  Future<String> save(String relativePath, Uint8List bytes) {
    if (failSaves) {
      throw const FileSystemException('The process cannot access the file');
    }
    return super.save(relativePath, bytes);
  }
}

/// Sends nothing and answers immediately, so tests do not wait on the mock
/// provider's deliberate latency.
class _StubClient implements WhatsAppClient {
  _StubClient({this.failWith});

  final String? failWith;
  final sent = <WhatsAppSendInput>[];

  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.mock;

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async {
    sent.add(input);
    final failure = failWith;
    return failure == null
        ? const WhatsAppSendSuccess('stub.1')
        : WhatsAppSendFailure(failure);
  }
}

void main() {
  late Directory workspace;
  late AppDatabase db;
  late _RecordingRenderer renderer;
  late _FakeStorage storage;
  late AuditRepository audit;
  late RecordPaymentService recorder;
  late PaymentEditService editor;
  late _StubClient client;
  late int adminId;
  late int memberId;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-payment-edit');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);

    renderer = _RecordingRenderer();
    storage = _FakeStorage(workspace);
    audit = AuditRepository(db);
    client = _StubClient();

    recorder = RecordPaymentService(
      db: db,
      renderer: renderer,
      storage: storage,
      clientFactory: () async => client,
    );
    editor = PaymentEditService(
      db: db,
      renderer: renderer,
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

  EditPaymentInput edit(
    int paymentId, {
    int amountMinor = 300000,
    PaymentMethod method = PaymentMethod.cash,
    DateTime? paymentDate,
    String billingMonth = '2026-08',
    String? referenceNumber,
    String? notes,
    bool sendWhatsApp = false,
  }) =>
      EditPaymentInput(
        paymentId: paymentId,
        amountMinor: amountMinor,
        method: method,
        paymentDate: paymentDate ?? DateTime(2026, 8, 15),
        billingMonth: billingMonth,
        editedById: adminId,
        referenceNumber: referenceNumber,
        notes: notes,
        sendWhatsApp: sendWhatsApp,
      );

  Future<Payment> paymentById(int id) =>
      (db.select(db.payments)..where((p) => p.id.equals(id))).getSingle();

  Future<List<AuditEvent>> auditEvents([String? action]) async {
    final all = await db.select(db.auditEvents).get();
    return action == null
        ? all
        : all.where((e) => e.action == action).toList();
  }

  group('editing the values on a payment', () {
    test('changes the amount and stamps who corrected it, when', () async {
      final recorded = await record();

      final result = await editor.edit(edit(recorded.paymentId,
          amountMinor: 450000, method: PaymentMethod.bankTransfer));

      expect(result, isA<PaymentEdited>());
      final edited = result as PaymentEdited;
      expect(edited.changes, contains('Amount: Rs. 3,000 → Rs. 4,500'));
      expect(edited.changes, contains('Method: Cash → Bank Transfer'));

      final payment = await paymentById(recorded.paymentId);
      expect(payment.amountMinor, 450000);
      expect(payment.method, PaymentMethod.bankTransfer);
      expect(payment.updatedById, adminId);
      expect(payment.updatedAt, isNotNull);
    });

    test('keeps the original receipt number and its files', () async {
      final recorded = await record();

      final result = await editor.edit(
          edit(recorded.paymentId, amountMinor: 450000)) as PaymentEdited;

      expect(result.receiptNumber, recorded.receiptNumber);
      expect(result.receipt, isA<ReceiptRewritten>());

      final receipt = await db.select(db.receipts).getSingle();
      expect(receipt.receiptNumber, recorded.receiptNumber,
          reason: 'a correction must not consume a new receipt number');

      // The counter is untouched, so the next real payment does not collide.
      final counter = await db.select(db.receiptCounters).getSingle();
      expect(counter.lastNumber, 1);
    });

    test('regenerates the receipt file with the corrected amount', () async {
      final recorded = await record();
      final original = await storage.read('${recorded.receiptNumber}.png');

      await editor.edit(edit(recorded.paymentId, amountMinor: 450000));

      final rewritten = await storage.read('${recorded.receiptNumber}.png');
      expect(rewritten, isNot(original));
      expect(String.fromCharCodes(rewritten!), contains('Rs. 4,500'));
      expect(renderer.calls.last.receiptNumber, recorded.receiptNumber);
    });

    test('reference and notes changes are described without dumping notes',
        () async {
      final recorded = await record();

      final result = await editor.edit(edit(
        recorded.paymentId,
        referenceNumber: 'TRX-99',
        notes: 'paid at the counter, receipt handed over',
      )) as PaymentEdited;

      expect(result.changes, contains('Reference: added "TRX-99"'));
      expect(result.changes, contains('Notes: added'));
      expect(result.changes.join('\n'), isNot(contains('counter')));
    });

    test('saving without changing anything does nothing at all', () async {
      final recorded = await record();
      final rendersAfterRecording = renderer.calls.length;

      final result =
          await editor.edit(edit(recorded.paymentId)) as PaymentEdited;

      expect(result.changedNothing, isTrue);
      expect(renderer.calls, hasLength(rendersAfterRecording),
          reason: 'no receipt is re-rendered for an unchanged form');
      expect((await paymentById(recorded.paymentId)).updatedAt, isNull,
          reason: 'an untouched payment must not look edited');
      expect(await auditEvents(), isEmpty,
          reason: 'a no-op edit is noise, not history');
    });
  });

  group('moving a payment to another billing cycle', () {
    test('moves it, and the cycle it left reads DUE again', () async {
      final recorded = await record(billingMonth: '2026-08');
      final august = await db.select(db.membershipPeriods).getSingle();

      final result = await editor
          .edit(edit(recorded.paymentId, billingMonth: '2026-09'));
      expect(result, isA<PaymentEdited>());
      expect((result as PaymentEdited).changes,
          contains('Billing period: August 2026 → September 2026'));

      final payment = await paymentById(recorded.paymentId);
      expect(payment.membershipPeriodId, isNot(august.id));

      // August still exists as a cycle — it is simply unpaid again.
      final periods = await db.select(db.membershipPeriods).get();
      expect(periods.map((p) => p.id), contains(august.id),
          reason: 'the vacated cycle is not deleted just because it emptied');

      final augustStatus = deriveMemberStatus(
        deactivatedAt: null,
        periods: [
          StatusPeriod(
            periodStart: august.periodStart.toUtc(),
            periodEnd: august.periodEnd.toUtc(),
            isPaid: false,
          ),
        ],
        now: DateTime.utc(2026, 8, 20),
      );
      expect(augustStatus, MemberStatus.due);
    });

    test('refuses to move onto a cycle that already holds a payment', () async {
      final august = await record(billingMonth: '2026-08', key: 'pay-aug');
      await record(
          billingMonth: '2026-09', amountMinor: 320000, key: 'pay-sep');

      final result =
          await editor.edit(edit(august.paymentId, billingMonth: '2026-09'));

      expect(result, isA<PaymentEditRefused>());
      final refused = result as PaymentEditRefused;
      expect(refused.reason, EditRefusalReason.cycleTaken);
      expect(refused.message, contains('September 2026'));
      expect(refused.message, contains('Rs. 3,200'));

      // Nothing moved, nothing was stamped.
      final payment = await paymentById(august.paymentId);
      expect(payment.updatedAt, isNull);
    });

    test('a month before the member joined is refused and logged', () async {
      final recorded = await record();

      final result =
          await editor.edit(edit(recorded.paymentId, billingMonth: '2025-11'));

      expect(result, isA<PaymentEditRefused>());
      expect((result as PaymentEditRefused).reason,
          EditRefusalReason.monthBlocked);

      final blocked = await auditEvents(AuditAction.billingMonthBlocked);
      expect(blocked, hasLength(1));
      expect(blocked.single.outcome, AuditOutcome.refused);
      expect(blocked.single.detail, contains('November 2025'));
    });

    test('creates the cycle when the target month has none', () async {
      final recorded = await record(billingMonth: '2026-08');

      await editor.edit(edit(recorded.paymentId, billingMonth: '2026-09'));

      final september = await db.select(db.membershipPeriods).get();
      expect(september, hasLength(2));
      expect(
        september.map((p) => p.periodStart.toUtc()),
        contains(DateTime.utc(2026, 9, 1)),
      );
    });
  });

  group('WhatsApp', () {
    test('an edit sends nothing unless the owner asks', () async {
      final recorded = await record();

      await editor.edit(edit(recorded.paymentId, amountMinor: 450000));

      expect(client.sent, isEmpty);
      expect(await db.select(db.whatsAppMessages).get(), isEmpty);
    });

    test('a requested resend is a new attempt, not a rewritten one', () async {
      final recorded = await record(sendWhatsApp: true);
      final first = await db.select(db.whatsAppMessages).getSingle();
      expect(first.attemptNumber, 1);

      final result = await editor.edit(
              edit(recorded.paymentId, amountMinor: 450000, sendWhatsApp: true))
          as PaymentEdited;

      expect(result.whatsApp, isA<WhatsAppSent>());

      final attempts = await db.select(db.whatsAppMessages).get();
      expect(attempts, hasLength(2));
      expect(attempts.map((a) => a.attemptNumber), containsAll([1, 2]));
      expect(attempts.first.id, first.id,
          reason: 'the earlier attempt is history and must not be mutated');

      // The corrected image is what goes out, not the one on disk from before.
      expect(String.fromCharCodes(client.sent.last.imageBytes),
          contains('Rs. 4,500'));
    });

    test('a send failure leaves the correction in place', () async {
      final recorded = await record();
      client = _StubClient(failWith: 'Simulated provider outage');

      final result = await editor.edit(
              edit(recorded.paymentId, amountMinor: 450000, sendWhatsApp: true))
          as PaymentEdited;

      expect(result.whatsApp, isA<WhatsAppFailed>());
      expect((await paymentById(recorded.paymentId)).amountMinor, 450000,
          reason: 'messaging must never undo money');

      final failures = await auditEvents(AuditAction.whatsAppFailed);
      expect(failures.single.outcome, AuditOutcome.failed);
    });

    test('never writes the access token into the log', () async {
      await SettingsRepository(db).update(const GymSettingsCompanion(
        whatsappProvider: Value(WhatsAppProviderKind.meta),
        whatsappPhoneNumberId: Value('1234567890'),
        whatsappAccessToken: Value('SUPER-SECRET-TOKEN'),
      ));
      final recorded = await record();
      client = _StubClient(
          failWith: 'Unsupported post request. Object does not exist.');

      await editor.edit(
          edit(recorded.paymentId, amountMinor: 450000, sendWhatsApp: true));

      final everything = (await db.select(db.auditEvents).get())
          .map((e) => '${e.summary}\n${e.detail}')
          .join('\n');
      expect(everything, isNot(contains('SUPER-SECRET-TOKEN')));
      expect(everything, isNot(contains('Authorization')));
      expect(everything, contains('Unsupported post request'),
          reason: 'the classified provider error is still useful to keep');
    });
  });

  group('when the receipt cannot be rewritten', () {
    test('the payment stays corrected and the failure is reported', () async {
      final recorded = await record();
      storage.failSaves = true;

      final result = await editor.edit(
          edit(recorded.paymentId, amountMinor: 450000)) as PaymentEdited;

      expect(result.receipt, isA<ReceiptRewriteFailed>());
      expect((result.receipt as ReceiptRewriteFailed).message,
          contains('could not be rewritten'));

      expect((await paymentById(recorded.paymentId)).amountMinor, 450000,
          reason: 'the database committed before any file was touched');

      final failures = await auditEvents(AuditAction.receiptResaveFailed);
      expect(failures.single.outcome, AuditOutcome.failed);
      expect(failures.single.receiptNumber, recorded.receiptNumber);
    });

    test('a corrected receipt that failed to save is not sent', () async {
      final recorded = await record();
      storage.failSaves = true;

      final result = await editor.edit(
              edit(recorded.paymentId, amountMinor: 450000, sendWhatsApp: true))
          as PaymentEdited;

      expect(result.whatsApp, isA<WhatsAppFailed>());
      expect(client.sent, isEmpty,
          reason: 'sending the stale image would be worse than not sending');
    });

    test('a render failure is logged and does not lose the correction',
        () async {
      final recorded = await record();
      final failing = PaymentEditService(
        db: db,
        renderer: _FailingRenderer(),
        storage: storage,
        audit: audit,
        payments: recorder,
      );

      final result = await failing
          .edit(edit(recorded.paymentId, amountMinor: 450000)) as PaymentEdited;

      expect(result.receipt, isA<ReceiptRewriteFailed>());
      expect((await paymentById(recorded.paymentId)).amountMinor, 450000);
      expect(await auditEvents(AuditAction.receiptRenderFailed), hasLength(1));
    });
  });

  group('imported ledger payments', () {
    /// A row the importer would have created: no receipt, and none is minted
    /// for it later.
    Future<int> importedPayment() async {
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

      return db.into(db.payments).insert(PaymentsCompanion.insert(
            memberId: memberId,
            membershipPeriodId: Value(period.id),
            amountMinor: 250000,
            method: PaymentMethod.cash,
            paymentDate: DateTime.utc(2026, 3, 5),
            source: const Value(PaymentSource.imported),
            recordedById: adminId,
            idempotencyKey: 'import-2026-1-3',
          ));
    }

    test('can be corrected without minting a receipt', () async {
      final paymentId = await importedPayment();

      final result = await editor.edit(edit(
        paymentId,
        amountMinor: 300000,
        billingMonth: '2026-03',
        paymentDate: DateTime.utc(2026, 3, 5),
      )) as PaymentEdited;

      expect(result.changes, contains('Amount: Rs. 2,500 → Rs. 3,000'));
      expect(result.receipt, isA<ReceiptNotApplicable>());
      expect(result.receiptNumber, isNull);

      expect(await db.select(db.receipts).get(), isEmpty,
          reason: 'a 2026 ledger correction must not take a receipt number');
      expect((await db.select(db.receiptCounters).get()), isEmpty);
    });

    test('cannot be sent on WhatsApp, and says why', () async {
      final paymentId = await importedPayment();

      final result = await editor.edit(edit(
        paymentId,
        amountMinor: 300000,
        billingMonth: '2026-03',
        paymentDate: DateTime.utc(2026, 3, 5),
        sendWhatsApp: true,
      )) as PaymentEdited;

      expect(result.whatsApp, isA<WhatsAppFailed>());
      expect((result.whatsApp as WhatsAppFailed).error,
          contains('no receipt to send'));
      expect(client.sent, isEmpty);
    });
  });

  group('the audit trail', () {
    test('records what changed, for whom, by whom', () async {
      final recorded = await record();

      await editor.edit(edit(recorded.paymentId,
          amountMinor: 450000, billingMonth: '2026-09'));

      final event = (await auditEvents(AuditAction.paymentEdited)).single;
      expect(event.category, AuditCategory.payment);
      expect(event.outcome, AuditOutcome.success);
      expect(event.memberName, 'Ali Raza');
      expect(event.actorName, isNotNull);
      expect(event.paymentId, recorded.paymentId);
      expect(event.receiptNumber, recorded.receiptNumber);
      expect(event.amountMinor, 450000);
      expect(event.periodLabel, 'September 2026');
      expect(event.detail, contains('Amount: Rs. 3,000 → Rs. 4,500'));
      expect(event.detail,
          contains('Billing period: August 2026 → September 2026'));
    });

    test('a payment that does not exist is refused, not crashed on', () async {
      final result = await editor.edit(edit(9999));

      expect(result, isA<PaymentEditRefused>());
      expect((result as PaymentEditRefused).reason, EditRefusalReason.notFound);
      expect(result.message, isNot(contains('Exception')));
    });
  });
}
