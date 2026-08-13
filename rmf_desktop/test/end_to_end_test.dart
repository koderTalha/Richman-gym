import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// A renderer that skips rasterising, which needs platform channels.
class _FakeRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async {
    final pdf = await buildPdf(data);
    return RenderedReceipt(pdf: pdf, png: Uint8List.fromList([1, 2, 3]));
  }
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  @override
  Future<Directory> root() async => _dir;
}

/// Counts sends so a duplicate submit can be proven not to message twice.
class _CountingClient implements WhatsAppClient {
  _CountingClient({this.failing = false});

  final bool failing;
  int sends = 0;

  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.mock;

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async {
    sends++;
    return failing
        ? const WhatsAppSendFailure('simulated outage')
        : MockWhatsAppClient().send(input);
  }
}

void main() {
  late Directory workspace;
  late AppDatabase db;
  late RecordPaymentService payments;
  late MemberRepository memberRepo;
  late PaymentRepository paymentRepo;
  late ReceiptRepository receiptRepo;
  late _CountingClient client;
  late int adminId;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-e2e');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);

    client = _CountingClient();
    memberRepo = MemberRepository(db);
    paymentRepo = PaymentRepository(db);
    receiptRepo = ReceiptRepository(db);
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(Directory(p.join(workspace.path, 'receipts'))),
      clientFactory: () => client,
    );

    adminId = (await db.select(db.users).getSingle()).id;
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  Future<int> addMember(String name, String phone) async {
    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.name.equals('Monthly')))
        .getSingle();
    return memberRepo.create(
      fullName: name,
      phone: phone,
      planId: plan.id,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
  }

  RecordPaymentInput input(int memberId, String key) => RecordPaymentInput(
        memberId: memberId,
        amountMinor: 300000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, 8, 13),
        billingMonth: '2026-08',
        sendWhatsApp: true,
        recordedById: adminId,
        idempotencyKey: key,
      );

  group('a clean install', () {
    test('starts with no members and no payments', () async {
      expect(await db.select(db.members).get(), isEmpty);
      expect(await db.select(db.payments).get(), isEmpty);
    });

    test('still has the admin, settings and plans ready to use', () async {
      expect((await db.select(db.users).get()).length, 1);
      expect(await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
          .getSingleOrNull(), isNotNull);
      expect((await db.select(db.membershipPlans).get()).length, 4);
    });

    test('seeding twice does not duplicate anything', () async {
      await seedDatabase(db);
      await seedDatabase(db);

      expect((await db.select(db.users).get()).length, 1);
      expect((await db.select(db.membershipPlans).get()).length, 4);
    });
  });

  group('no duplicate payments', () {
    test('submitting twice with the same key records one payment', () async {
      final memberId = await addMember('Member One', '+923000000022');

      final first = await payments.call(input(memberId, 'submit-1'));
      final second = await payments.call(input(memberId, 'submit-1'));

      expect((await db.select(db.payments).get()).length, 1);
      expect(second.paymentId, first.paymentId);
      expect(second.receiptNumber, first.receiptNumber);
    });

    test('a duplicate submit does not send a second WhatsApp message',
        () async {
      final memberId = await addMember('Member One', '+923000000022');

      await payments.call(input(memberId, 'submit-1'));
      await payments.call(input(memberId, 'submit-1'));

      expect(client.sends, 1, reason: 'the member must not be messaged twice');
    });

    test('a genuinely separate payment still goes through', () async {
      final memberId = await addMember('Member One', '+923000000022');

      await payments.call(input(memberId, 'submit-1'));
      await payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: 300000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, 9, 2),
        billingMonth: '2026-09',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'submit-2',
      ));

      expect((await db.select(db.payments).get()).length, 2);
    });

    test('receipt numbers never repeat', () async {
      final a = await addMember('Member Alpha', '+923000000022');
      final b = await addMember('Member Beta', '+923000000031');

      final first = await payments.call(input(a, 'k1'));
      final second = await payments.call(input(b, 'k2'));

      expect(first.receiptNumber, 'RMF-2026-000001');
      expect(second.receiptNumber, 'RMF-2026-000002');
    });

    test('re-importing the same sheet twice changes nothing the second time',
        () async {
      final sheet = [
        ['RICH MAN FITNESS GYM', null, null, null, null],
        ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
        ['1', 'Member One', '0300-0000001', '3000', '3000'],
        ['2', 'No Phone Member', '-', '3000', '-'],
      ];
      final detected = detectMapping(sheet)!;
      final ledger = parseLedger(
        rows: sheet,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: 2026,
      );
      final plan = await (db.select(db.membershipPlans)
            ..where((p) => p.name.equals('Monthly')))
          .getSingle();

      final service = ImportService(db);
      final first = await service.commit(
          ledger: ledger, planId: plan.id, recordedById: adminId);
      final second = await service.commit(
          ledger: ledger, planId: plan.id, recordedById: adminId);

      expect(first.membersCreated, 2);
      expect(first.paymentsCreated, 3);

      expect(second.membersCreated, 0, reason: 'members matched, not recreated');
      expect(second.paymentsCreated, 0, reason: 'payments already existed');
      expect((await db.select(db.members).get()).length, 2);
      expect((await db.select(db.payments).get()).length, 3);
    });

    test('a member without a phone is not merged with another', () async {
      final sheet = [
        ['RICH MAN FITNESS GYM', null, null, null],
        ['Enroll.', 'Name', 'Contact Detail', 'Jan'],
        ['1', 'No Phone Member', '-', '-'],
        ['2', 'No Phone Two', '-', '-'],
        ['3', 'No Phone Three', '', '-'],
      ];
      final detected = detectMapping(sheet)!;
      final ledger = parseLedger(
        rows: sheet,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: 2026,
      );
      final plan = await (db.select(db.membershipPlans)
            ..where((p) => p.name.equals('Monthly')))
          .getSingle();

      await ImportService(db)
          .commit(ledger: ledger, planId: plan.id, recordedById: adminId);

      final imported = await db.select(db.members).get();
      expect(imported.length, 3, reason: 'three distinct people');
      expect(imported.map((m) => m.fullName),
          containsAll(['No Phone Member', 'No Phone Two', 'No Phone Three']));
    });
  });

  group('warning before billing a month twice', () {
    test('reports the existing payment for an already-paid month', () async {
      final memberId = await addMember('Member One', '+923000000022');
      await payments.call(input(memberId, 'first'));

      final existing = await payments.existingPaymentForPeriod(
          memberId: memberId, billingMonth: '2026-08');

      expect(existing, isNotNull);
      expect(existing!.amountMinor, 300000);
    });

    test('says nothing for a month that has not been billed', () async {
      final memberId = await addMember('Member One', '+923000000022');
      await payments.call(input(memberId, 'first'));

      final existing = await payments.existingPaymentForPeriod(
          memberId: memberId, billingMonth: '2026-09');

      expect(existing, isNull, reason: 'September is untouched');
    });

    test('says nothing for a member with no payments at all', () async {
      final memberId = await addMember('No Phone Member', '+923000000031');

      expect(
        await payments.existingPaymentForPeriod(
            memberId: memberId, billingMonth: '2026-08'),
        isNull,
      );
    });

    test('does not block a deliberate second payment', () async {
      final memberId = await addMember('Member One', '+923000000022');
      await payments.call(input(memberId, 'first'));
      // The owner confirmed; a top-up is still allowed.
      await payments.call(input(memberId, 'second-on-purpose'));

      expect((await db.select(db.payments).get()).length, 2);
    });
  });

  group('money is never lost', () {
    test('a WhatsApp outage still records the payment and receipt', () async {
      final failing = _CountingClient(failing: true);
      final service = RecordPaymentService(
        db: db,
        renderer: _FakeRenderer(),
        storage: _FakeStorage(Directory(p.join(workspace.path, 'r2'))),
        clientFactory: () => failing,
      );

      final memberId = await addMember('Member One', '+923000000022');
      final result = await service.call(input(memberId, 'outage'));

      expect(result.whatsApp, isA<WhatsAppFailed>());
      expect((await db.select(db.payments).get()).length, 1);
      expect((await db.select(db.receipts).get()).length, 1);
      expect(result.receiptNumber, isNotEmpty);
    });

    test('a failed send can be retried and is recorded as a new attempt',
        () async {
      final memberId = await addMember('Member One', '+923000000022');
      final failing = _CountingClient(failing: true);
      var useFailing = true;

      final service = RecordPaymentService(
        db: db,
        renderer: _FakeRenderer(),
        storage: _FakeStorage(Directory(p.join(workspace.path, 'r3'))),
        clientFactory: () => useFailing ? failing : client,
      );

      final result = await service.call(input(memberId, 'retry-me'));
      expect(result.whatsApp, isA<WhatsAppFailed>());

      useFailing = false;
      final retry = await service.resend(result.receiptId);

      expect(retry, isA<WhatsAppSent>());
      final attempts = await db.select(db.whatsAppMessages).get();
      expect(attempts.length, 2, reason: 'the failure is kept, not overwritten');
      expect(attempts.map((a) => a.attemptNumber), [1, 2]);
    });

    test('the failed count clears once a retry succeeds', () async {
      final memberId = await addMember('Member One', '+923000000022');
      final failing = _CountingClient(failing: true);
      var useFailing = true;

      final service = RecordPaymentService(
        db: db,
        renderer: _FakeRenderer(),
        storage: _FakeStorage(Directory(p.join(workspace.path, 'r4'))),
        clientFactory: () => useFailing ? failing : client,
      );

      final result = await service.call(input(memberId, 'k'));
      expect(await receiptRepo.failedCount(), 1);

      useFailing = false;
      await service.resend(result.receiptId);

      expect(await receiptRepo.failedCount(), 0);
    });
  });

  group('the numbers the owner sees are right', () {
    test('a paid member reads PAID and appears in revenue', () async {
      final memberId = await addMember('Member One', '+923000000022');
      await payments.call(input(memberId, 'k'));

      final rows = await memberRepo.list();
      expect(rows.single.status, MemberStatus.paid);

      final total = await paymentRepo.totalMinorBetween(
          DateTime.utc(2026, 8, 1), DateTime.utc(2026, 9, 1));
      expect(total, 300000);
    });

    test('an unpaid member reads DUE once the cycle is rolled forward',
        () async {
      await addMember('No Phone Member', '+923000000022');
      await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 8, 13));

      final rows = await memberRepo.list();
      expect(rows.single.status, MemberStatus.due);
    });

    test('payment history shows the receipt and the billing period', () async {
      final memberId = await addMember('Member One', '+923000000022');
      await payments.call(input(memberId, 'k'));

      final history = await paymentRepo.history(memberId: memberId);
      expect(history.single.receipt, isNotNull);
      expect(history.single.periodLabel, 'August 2026');
      expect(history.single.whatsAppStatus, WhatsAppStatus.sent);
    });

    test('searching finds a member by name, phone and enrolment number',
        () async {
      await addMember('Member One', '+923000000022');

      // By name, case-insensitively.
      expect((await memberRepo.list(search: 'member one')).length, 1);
      // By part of the phone number.
      expect((await memberRepo.list(search: '0000022')).length, 1);
      // By enrolment number.
      expect((await memberRepo.list(search: '1')).length, 1);
      expect((await memberRepo.list(search: 'nobody')), isEmpty);
    });
  });

  group('the app refuses to do something wrong', () {
    test('recording a payment for a member with no plan explains itself',
        () async {
      final memberId = await db.into(db.members).insert(MembersCompanion.insert(
            memberCode: 99,
            fullName: 'No Plan',
            phone: '+923000000022',
            joiningDate: DateTime.utc(2026, 1, 1),
          ));

      expect(
        () => payments.call(input(memberId, 'k')),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('no active membership'))),
      );
    });

    test('a member with no phone never triggers a send attempt', () async {
      final plan = await (db.select(db.membershipPlans)
            ..where((p) => p.name.equals('Monthly')))
          .getSingle();
      final memberId = await memberRepo.create(
        fullName: 'No Phone Member',
        phone: '',
        planId: plan.id,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

      final result = await payments.call(input(memberId, 'k'));

      expect(result.whatsApp, isA<WhatsAppFailed>());
      expect(client.sends, 0, reason: 'no pointless call to the provider');
      // The payment itself is untouched by the messaging problem.
      expect((await db.select(db.payments).get()).length, 1);
    });
  });
}
