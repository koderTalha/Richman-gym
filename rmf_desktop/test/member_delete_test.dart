import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
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

  @override
  Future<Directory> root() async => _dir;
}

class _StubClient implements WhatsAppClient {
  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.mock;

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async =>
      const WhatsAppSendSuccess('stub.1');
}

/// Deleting a member is offered for the mistake — the duplicate import, the
/// person entered twice. It must never become a way to erase money.
void main() {
  late Directory workspace;
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService recorder;
  late PaymentEditService editor;
  late int adminId;
  late int memberId;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-member-delete');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);

    final audit = AuditRepository(db);
    final storage = _FakeStorage(workspace);
    members = MemberRepository(db, audit: audit);
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
    memberId = await members.create(
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

  Future<RecordPaymentResult> record({String key = 'pay-1'}) =>
      recorder.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: 300000,
        method: PaymentMethod.cash,
        paymentDate: DateTime(2026, 8, 15),
        billingMonth: '2026-08',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: key,
      ));

  Future<List<AuditEvent>> events(String action) async =>
      (await db.select(db.auditEvents).get())
          .where((e) => e.action == action)
          .toList();

  group('while payments exist', () {
    test('deletion is refused and says how many', () async {
      await record(key: 'pay-1');
      await record(key: 'pay-2');

      final result = await members.deleteMember(id: memberId, actorId: adminId);

      expect(result, isA<MemberDeleteRefused>());
      final refused = result as MemberDeleteRefused;
      expect(refused.paymentCount, 2);
      expect(refused.memberName, 'Ali Raza');
      expect(refused.message,
          'Ali Raza has 2 payments recorded. Deactivate them instead, or '
          'delete the payments first.');
    });

    test('one payment reads in the singular', () async {
      await record();

      final result = await members.deleteMember(id: memberId, actorId: adminId);

      expect((result as MemberDeleteRefused).message,
          contains('has 1 payment recorded'));
    });

    test('the member, their payments and receipts are all untouched', () async {
      await record();

      await members.deleteMember(id: memberId, actorId: adminId);

      expect(await db.select(db.members).get(), hasLength(1));
      expect(await db.select(db.payments).get(), hasLength(1));
      expect(await db.select(db.receipts).get(), hasLength(1));
      expect(await db.select(db.memberships).get(), hasLength(1));
    });

    test('the refusal itself is recorded', () async {
      await record();

      await members.deleteMember(id: memberId, actorId: adminId);

      final refusals = await events(AuditAction.memberDeleteRefused);
      expect(refusals, hasLength(1));
      expect(refusals.single.outcome, AuditOutcome.refused);
      expect(refusals.single.memberName, 'Ali Raza');
      expect(refusals.single.summary, contains('1 payment recorded'));
    });
  });

  group('with no payments', () {
    test('the member is deleted', () async {
      final result = await members.deleteMember(id: memberId, actorId: adminId);

      expect(result, isA<MemberDeleted>());
      expect((result as MemberDeleted).memberName, 'Ali Raza');
      expect(await db.select(db.members).get(), isEmpty);
    });

    test('their notes, enrolments and billing cycles go with them', () async {
      final membership = await (db.select(db.memberships)
            ..where((m) => m.memberId.equals(memberId)))
          .getSingle();
      await db.into(db.membershipPeriods).insert(
            MembershipPeriodsCompanion.insert(
              membershipId: membership.id,
              periodStart: DateTime.utc(2026, 8, 1),
              periodEnd: DateTime.utc(2026, 9, 1),
              expectedAmountMinor: 300000,
            ),
          );
      await db.into(db.memberNotes).insert(MemberNotesCompanion.insert(
            memberId: memberId,
            body: 'Prefers the evening shift',
            createdById: adminId,
          ));

      await members.deleteMember(id: memberId, actorId: adminId);

      expect(await db.select(db.memberNotes).get(), isEmpty);
      expect(await db.select(db.membershipPeriods).get(), isEmpty);
      expect(await db.select(db.memberships).get(), isEmpty);
    });

    test('other members are left alone', () async {
      final keeper = await members.create(
        fullName: 'Bilal Ahmed',
        phone: '+923000000002',
        planId: (await (db.select(db.membershipPlans)
                  ..where((p) => p.name.equals('Monthly')))
                .getSingle())
            .id,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

      await members.deleteMember(id: memberId, actorId: adminId);

      final remaining = await db.select(db.members).get();
      expect(remaining.single.id, keeper);
      expect(await db.select(db.memberships).get(), hasLength(1));
    });

    test('the deletion is recorded with enough to identify who went', () async {
      final member = await (db.select(db.members)
            ..where((m) => m.id.equals(memberId)))
          .getSingle();

      await members.deleteMember(id: memberId, actorId: adminId);

      final deletions = await events(AuditAction.memberDeleted);
      expect(deletions, hasLength(1));
      expect(deletions.single.memberId, memberId,
          reason: 'copied, not a foreign key, so it survives the deletion');
      expect(deletions.single.memberName, 'Ali Raza');
      expect(deletions.single.summary,
          contains('member #${member.memberCode}'));
      expect(deletions.single.actorName, isNotNull);
    });
  });

  test('deleting the payments first makes the member deletable', () async {
    final recorded = await record();

    expect(await members.deleteMember(id: memberId, actorId: adminId),
        isA<MemberDeleteRefused>());

    await editor.delete(paymentId: recorded.paymentId, actorId: adminId);

    expect(await members.deleteMember(id: memberId, actorId: adminId),
        isA<MemberDeleted>());
    expect(await db.select(db.members).get(), isEmpty);

    // The whole story is still readable afterwards, in order.
    final trail = (await db.select(db.auditEvents).get())
        .map((e) => e.action)
        .toList();
    expect(
      trail,
      containsAllInOrder([
        AuditAction.memberDeleteRefused,
        AuditAction.paymentDeleted,
        AuditAction.memberDeleted,
      ]),
    );
  });

  test('a member who does not exist is reported, not crashed on', () async {
    final result = await members.deleteMember(id: 9999, actorId: adminId);

    expect(result, isA<MemberDeleteNotFound>());
    expect(await events(AuditAction.memberDeleted), isEmpty);
  });

  group('deactivation', () {
    test('is recorded, and keeps everything', () async {
      await record();

      await members.setActive(memberId, false, actorId: adminId);

      final member = await (db.select(db.members)
            ..where((m) => m.id.equals(memberId)))
          .getSingle();
      expect(member.deactivatedAt, isNotNull);
      expect(await db.select(db.payments).get(), hasLength(1));

      final logged = await events(AuditAction.memberDeactivated);
      expect(logged.single.summary, 'Ali Raza deactivated');
    });

    test('reactivating is recorded too', () async {
      await members.setActive(memberId, false, actorId: adminId);
      await members.setActive(memberId, true, actorId: adminId);

      expect((await events(AuditAction.memberReactivated)).single.summary,
          'Ali Raza reactivated');
    });
  });
}
