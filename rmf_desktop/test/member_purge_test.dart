import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/member_purge_service.dart';
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

  @override
  Future<WhatsAppSendResult> sendText(WhatsAppTextInput input) async =>
      const WhatsAppSendSuccess('stub.text.1');

  @override
  Future<WhatsAppSendResult> sendTemplate(WhatsAppTemplateInput input) async =>
      const WhatsAppSendSuccess('stub.template.1');
}

/// Emptying the members domain from Settings.
///
/// The gym's route out of a dataset that has to be started again. It is the
/// only action in the app that deletes money the owner has not first singled
/// out, so the interesting half of this file is not what goes — it is the list
/// of things that must still be there afterwards: the owner's account and
/// their session, the gym's settings, the membership plans, the receipt number
/// counter, and the log saying all of this happened.
void main() {
  late Directory workspace;
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService recorder;
  late MemberPurgeService purge;
  late int adminId;
  late int planId;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-member-purge');
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
    purge = MemberPurgeService(db: db, storage: storage, audit: audit);

    adminId = (await db.select(db.users).getSingle()).id;
    planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  Future<int> addMember(String name, String phone) => members.create(
        fullName: name,
        phone: phone,
        planId: planId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

  Future<void> pay(
    int memberId, {
    required String month,
    required String key,
    bool whatsApp = false,
  }) =>
      recorder.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: 300000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, int.parse(month.split('-')[1]), 4),
        billingMonth: month,
        sendWhatsApp: whatsApp,
        recordedById: adminId,
        idempotencyKey: key,
      ));

  /// A gym with two members, money, receipts, a sent message, and one row in
  /// every remaining member-owned table.
  Future<(int, int)> buildGym() async {
    final ali = await addMember('Ali Raza', '+923000000001');
    final sana = await addMember('Sana Malik', '+923000000002');

    await pay(ali, month: '2026-07', key: 'ali-jul', whatsApp: true);
    await pay(ali, month: '2026-08', key: 'ali-aug');
    await pay(sana, month: '2026-08', key: 'sana-aug');

    await db.into(db.memberNotes).insert(MemberNotesCompanion.insert(
          memberId: ali,
          body: 'Prefers the evening shift',
          createdById: adminId,
        ));
    await db.into(db.paymentReminders).insert(PaymentRemindersCompanion.insert(
          memberId: sana,
          stage: 'before',
          offsetDays: 3,
          status: ReminderSendStatus.sent,
          dueDate: DateTime.utc(2026, 9, 1),
          amountMinor: 300000,
        ));
    await db.into(db.membershipChanges).insert(MembershipChangesCompanion.insert(
          memberId: sana,
          effectiveFrom: DateTime.utc(2026, 8, 1),
          feeMinor: const Value(300000),
        ));

    return (ali, sana);
  }

  Future<int> rows(String table) async => (await db
          .customSelect('SELECT COUNT(*) AS c FROM $table')
          .getSingle())
      .read<int>('c');

  group('counting what is there', () {
    test('reports every member-owned table and the money', () async {
      await buildGym();

      final counts = await purge.counts();

      expect(counts.members, 2);
      expect(counts.payments, 3);
      expect(counts.paymentTotalMinor, 900000);
      expect(counts.receipts, 3);
      expect(counts.billingCycles, 3);
      expect(counts.whatsAppMessages, 1);
      expect(counts.reminders, 1);
      expect(counts.notes, 1);
      expect(counts.membershipChanges, 1);
      expect(counts.paymentAllocations, 3);
      expect(counts.isEmpty, isFalse);
    });

    test('a database with no members reads as empty', () async {
      expect((await purge.counts()).isEmpty, isTrue);
    });
  });

  group('deleting everything', () {
    test('every member goes', () async {
      await buildGym();

      final result = await purge.purgeAll(actorId: adminId);

      expect(result, isA<MemberDataPurged>());
      expect((result as MemberDataPurged).counts.members, 2);
      expect(await db.select(db.members).get(), isEmpty);
    });

    test('their payments and allocations go', () async {
      await buildGym();

      await purge.purgeAll(actorId: adminId);

      expect(await db.select(db.payments).get(), isEmpty);
      expect(await db.select(db.paymentAllocations).get(), isEmpty);
    });

    test('their receipts go, records and files alike', () async {
      await buildGym();
      final files = (await db.select(db.receipts).get())
          .expand((r) => [r.pngPath, r.pdfPath!])
          .toList();
      expect(files, isNotEmpty);
      for (final path in files) {
        expect(await File('${workspace.path}/$path').exists(), isTrue);
      }

      await purge.purgeAll(actorId: adminId);

      expect(await db.select(db.receipts).get(), isEmpty);
      for (final path in files) {
        expect(await File('${workspace.path}/$path').exists(), isFalse,
            reason: 'a receipt image left on disk is the member data the '
                'owner asked to be rid of, still readable');
      }
    });

    test('every other member-owned table is emptied', () async {
      await buildGym();

      await purge.purgeAll(actorId: adminId);

      for (final table in [
        'memberships',
        'membership_periods',
        'cycle_pricings',
        'membership_changes',
        'payment_reminders',
        'whats_app_messages',
        'member_notes',
      ]) {
        expect(await rows(table), 0, reason: '$table still has rows');
      }
    });

    test('nothing is left pointing at a member who no longer exists',
        () async {
      await buildGym();

      await purge.purgeAll(actorId: adminId);

      final violations =
          await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violations, isEmpty);
    });

    test('the result says what went', () async {
      await buildGym();

      final result =
          await purge.purgeAll(actorId: adminId) as MemberDataPurged;

      expect(result.counts.payments, 3);
      expect(result.counts.paymentTotalMinor, 900000);
      expect(result.counts.receipts, 3);
      expect(result.hasOrphanedFiles, isFalse);
    });
  });

  group('what must survive', () {
    test('the owner account, their session and the gym settings', () async {
      await buildGym();
      await db.into(db.appSessions).insert(
            AppSessionsCompanion.insert(
              userId: Value(adminId),
              signedInAt: Value(DateTime.utc(2026, 9, 1)),
            ),
            mode: InsertMode.insertOrReplace,
          );

      await purge.purgeAll(actorId: adminId);

      expect(await db.select(db.users).get(), hasLength(1));
      expect(await db.select(db.appSessions).get(), hasLength(1));
      expect(await db.select(db.gymSettings).get(), hasLength(1));
    });

    test('the membership plans, which are the gym\'s products', () async {
      await buildGym();
      final before = await db.select(db.membershipPlans).get();

      await purge.purgeAll(actorId: adminId);

      final after = await db.select(db.membershipPlans).get();
      expect(after, hasLength(before.length));
      expect(after.map((p) => p.name), containsAll(before.map((p) => p.name)));
    });

    test('the receipt counter, so a number is never issued twice', () async {
      await buildGym();
      final before = await db.select(db.receiptCounters).get();
      expect(before, isNotEmpty);

      await purge.purgeAll(actorId: adminId);

      final after = await db.select(db.receiptCounters).get();
      expect(after.map((c) => (c.year, c.lastNumber)),
          before.map((c) => (c.year, c.lastNumber)));
    });

    test('the audit log, including what it recorded about the members',
        () async {
      final (ali, _) = await buildGym();
      // Something the log already remembers about a member by name, from
      // before the purge. Compliance is the reason it is kept, and a log that
      // forgot who it was about would not be one.
      await members.setActive(ali, false, actorId: adminId);
      final before = await db.select(db.auditEvents).get();
      expect(before, isNotEmpty);

      await purge.purgeAll(actorId: adminId);

      final after = await db.select(db.auditEvents).get();
      expect(after.length, greaterThan(before.length),
          reason: 'the purge adds to the log, it never prunes it');
      for (final event in before) {
        expect(after.map((e) => e.id), contains(event.id));
      }
      expect(after.map((e) => e.memberName), contains('Ali Raza'));
    });
  });

  group('the record it leaves', () {
    Future<List<AuditEvent>> events(String action) async =>
        (await db.select(db.auditEvents).get())
            .where((e) => e.action == action)
            .toList();

    test('one row, naming the owner who did it and the totals', () async {
      await buildGym();

      await purge.purgeAll(actorId: adminId);

      final logged = await events(AuditAction.memberDataPurged);
      expect(logged, hasLength(1));
      expect(logged.single.outcome, AuditOutcome.success);
      expect(logged.single.actorId, adminId);
      expect(logged.single.actorName, isNotNull);
      expect(logged.single.amountMinor, 900000);
      expect(logged.single.summary, contains('2 members'));
      expect(logged.single.summary, contains('3 payments'));
    });

    test('no member name or phone number is written into it', () async {
      await buildGym();

      await purge.purgeAll(actorId: adminId);

      final logged = (await events(AuditAction.memberDataPurged)).single;
      final text = '${logged.summary}\n${logged.detail}';
      expect(text, isNot(contains('Ali Raza')));
      expect(text, isNot(contains('Sana Malik')));
      expect(text, isNot(contains('+92300')));
      expect(logged.memberId, isNull);
      expect(logged.memberName, isNull);
    });
  });

  group('an empty dataset', () {
    test('is refused rather than logged as a deletion', () async {
      final result = await purge.purgeAll(actorId: adminId);

      expect(result, isA<MemberPurgeRefused>());
      expect((result as MemberPurgeRefused).message,
          'There are no members to delete.');
      expect(
        (await db.select(db.auditEvents).get())
            .where((e) => e.action == AuditAction.memberDataPurged),
        isEmpty,
      );
    });

    test('running it twice is harmless', () async {
      await buildGym();

      final first = await purge.purgeAll(actorId: adminId);
      final second = await purge.purgeAll(actorId: adminId);

      expect(first, isA<MemberDataPurged>());
      expect(second, isA<MemberPurgeRefused>());
      expect(await db.select(db.users).get(), hasLength(1));
    });
  });

  group('when it fails part way', () {
    /// Aborts the delete at `memberships` — past the receipts and payments,
    /// with three tables still to go. Whatever guards this has to offer, this
    /// is the moment they have to hold.
    Future<void> breakMembershipDelete() => db.customStatement(
          'CREATE TRIGGER purge_boom BEFORE DELETE ON memberships '
          "BEGIN SELECT RAISE(ABORT, 'disk gave out'); END",
        );

    test('the error reaches the caller', () async {
      await buildGym();
      await breakMembershipDelete();

      expect(purge.purgeAll(actorId: adminId), throwsA(anything));
    });

    test('nothing at all is deleted', () async {
      await buildGym();
      final before = await purge.counts();
      await breakMembershipDelete();

      await expectLater(purge.purgeAll(actorId: adminId), throwsA(anything));

      final after = await purge.counts();
      expect(after.members, before.members);
      expect(after.payments, before.payments);
      expect(after.receipts, before.receipts);
      expect(after.whatsAppMessages, before.whatsAppMessages);
      expect(after.billingCycles, before.billingCycles);
    });

    test('the receipt files are still on disk', () async {
      await buildGym();
      final paths = (await db.select(db.receipts).get())
          .map((r) => r.pngPath)
          .toList();
      await breakMembershipDelete();

      await expectLater(purge.purgeAll(actorId: adminId), throwsA(anything));

      for (final path in paths) {
        expect(await File('${workspace.path}/$path').exists(), isTrue,
            reason: 'the records survived, so their files must too');
      }
    });

    test('nothing is logged as having been purged', () async {
      await buildGym();
      await breakMembershipDelete();

      await expectLater(purge.purgeAll(actorId: adminId), throwsA(anything));

      expect(
        (await db.select(db.auditEvents).get())
            .where((e) => e.action == AuditAction.memberDataPurged),
        isEmpty,
      );
    });
  });

  group('when a receipt file will not delete', () {
    test('the records still go, and the leftovers are reported', () async {
      await buildGym();
      final stubborn = MemberPurgeService(
        db: db,
        storage: _UndeletableStorage(workspace),
        audit: AuditRepository(db),
      );

      final result = await stubborn.purgeAll(actorId: adminId) as MemberDataPurged;

      expect(result.hasOrphanedFiles, isTrue);
      expect(result.orphanedFiles, hasLength(6));
      expect(await db.select(db.members).get(), isEmpty);
      expect(await db.select(db.receipts).get(), isEmpty);

      final orphanLog = (await db.select(db.auditEvents).get())
          .where((e) => e.action == AuditAction.receiptFilesOrphaned);
      expect(orphanLog, hasLength(1));
      expect(orphanLog.single.outcome, AuditOutcome.failed);
    });
  });
}

/// Storage whose files refuse to go — a receipt open in a viewer on Windows.
class _UndeletableStorage extends _FakeStorage {
  _UndeletableStorage(super.dir);

  @override
  Future<void> delete(String relativePath) async {}
}
