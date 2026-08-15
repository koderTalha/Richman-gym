import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';
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

/// Moving a member onto a different plan.
///
/// It is an ordinary counter action — somebody upgrades from monthly to
/// quarterly — and it used to be quietly destructive. Changing plan closes the
/// member's enrolment and opens a new one, and every cycle they had ever paid
/// stayed attached to the closed one. Anything that asked "what has this member
/// paid?" by looking at their *open* enrolment therefore saw nothing:
///
///   * the members list flipped them from PAID to DUE with the money still in
///     the database,
///   * the "already paid this month" warning went quiet, so the owner charged
///     them a second time,
///   * and re-importing the year's ledger collided with the payment's unique
///     idempotency key and aborted the entire import.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late int adminId;
  late int monthlyId;
  late int quarterlyId;

  final sheet = <List<String?>>[
    ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
    ['1', 'Ali Khan', '0300-0000001', '3000', '3000'],
  ];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
    quarterlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Quarterly')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  ParsedLedger parse(List<List<String?>> rows, {int year = 2026}) {
    final detected = detectMapping(rows)!;
    return parseLedger(
      rows: rows,
      headerRow: detected.headerRow,
      mapping: detected.mapping,
      year: year,
    );
  }

  Future<void> importSheet() => ImportService(db).commit(
        ledger: parse(sheet),
        planId: monthlyId,
        recordedById: adminId,
        now: DateTime.utc(2026, 6, 1),
      );

  Future<void> switchToQuarterly(int memberId) => members.update(
        id: memberId,
        fullName: 'Ali Khan',
        phone: '+923000000001',
        planId: quarterlyId,
        joiningDate: DateTime.utc(2026, 1, 1),
      );

  Future<int> onlyMemberId() async =>
      (await db.select(db.members).getSingle()).id;

  test('the member keeps every payment they have made', () async {
    await importSheet();
    final memberId = await onlyMemberId();

    final before = await members.byId(memberId, now: DateTime.utc(2026, 1, 15));
    expect(before!.status, MemberStatus.paid);

    await switchToQuarterly(memberId);

    final after = await members.byId(memberId, now: DateTime.utc(2026, 1, 15));
    expect(after!.status, MemberStatus.paid,
        reason: 'the money did not go anywhere when the plan changed');
    expect(after.paidUntil, before.paidUntil);
    expect(after.plan?.id, quarterlyId, reason: 'but the plan did change');
  });

  test('their payment history is still on their profile', () async {
    await importSheet();
    final memberId = await onlyMemberId();
    await switchToQuarterly(memberId);

    final row = await members.byId(memberId, now: DateTime.utc(2026, 1, 15));
    expect(row!.paidUntil, isNotNull);
    expect((await db.select(db.payments).get()).length, 2);
  });

  test('the already-paid warning still fires for a month they paid', () async {
    await importSheet();
    final memberId = await onlyMemberId();
    await switchToQuarterly(memberId);

    final workspace = await Directory.systemTemp.createTemp('rmf-plan-change');
    addTearDown(() => workspace.delete(recursive: true));

    final service = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: MockWhatsAppClient.new,
    );

    final existing = await service.existingPaymentForPeriod(
      memberId: memberId,
      billingMonth: '2026-01',
    );

    expect(existing, isNotNull,
        reason: 'without this the owner is never warned and takes the money '
            'for January twice');
  });

  test('re-importing the same ledger neither throws nor duplicates', () async {
    await importSheet();
    final memberId = await onlyMemberId();
    await switchToQuarterly(memberId);

    // Used to abort with UNIQUE constraint failed: payments.idempotency_key,
    // rolling back the whole sheet.
    await importSheet();

    expect((await db.select(db.members).get()).length, 1);
    expect((await db.select(db.payments).get()).length, 2,
        reason: 'January and February, imported once');
  });

  test('billing maintenance does not re-bill a month already paid', () async {
    await importSheet();
    final memberId = await onlyMemberId();
    await switchToQuarterly(memberId);

    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 1, 20));

    final january = (await db.select(db.membershipPeriods).get())
        .where((p) => p.periodStart.toUtc() == DateTime.utc(2026, 1, 1));
    expect(january.length, 1,
        reason: 'a second January cycle on the new enrolment would show the '
            'member as owing a month they have already settled');
  });

  test('a member with two open enrolments still loads', () async {
    // Should be impossible — a unique index enforces it on new writes — but a
    // database that predates the index must not take the members screen down.
    final memberId = await members.create(
      fullName: 'Legacy Data',
      phone: '+923000000002',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    try {
      await db.into(db.memberships).insert(MembershipsCompanion.insert(
            memberId: memberId,
            planId: quarterlyId,
            startDate: DateTime.utc(2026, 2, 1),
          ));
    } catch (_) {
      // The index did its job on this build; nothing left to prove.
      return;
    }

    final row = await members.byId(memberId, now: DateTime.utc(2026, 2, 15));
    expect(row, isNotNull, reason: 'must not throw "Too many elements"');
  });

  test('a second open enrolment is refused at the write', () async {
    final memberId = await members.create(
      fullName: 'Guarded',
      phone: '+923000000003',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    expect(
      db.into(db.memberships).insert(MembershipsCompanion.insert(
            memberId: memberId,
            planId: quarterlyId,
            startDate: DateTime.utc(2026, 2, 1),
          )),
      throwsA(anything),
      reason: 'every "which plan is this member on?" lookup assumes one',
    );
  });

  test('changing the plan back and forth loses nothing', () async {
    await importSheet();
    final memberId = await onlyMemberId();

    await switchToQuarterly(memberId);
    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    final row = await members.byId(memberId, now: DateTime.utc(2026, 1, 15));
    expect(row!.status, MemberStatus.paid);
    expect(row.plan?.id, monthlyId);
    expect((await db.select(db.memberships).get()).length, 3,
        reason: 'each enrolment is kept as history rather than overwritten');
  });

  test('a fee-only edit does not open a new enrolment', () async {
    await importSheet();
    final memberId = await onlyMemberId();

    await members.update(
      id: memberId,
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: monthlyId,
      feeOverrideMinor: 250000,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    expect((await db.select(db.memberships).get()).length, 1);
    final row = await members.byId(memberId, now: DateTime.utc(2026, 1, 15));
    expect(row!.feeMinor, 250000);
  });

  test('deactivating after a plan change still reads INACTIVE', () async {
    await importSheet();
    final memberId = await onlyMemberId();
    await switchToQuarterly(memberId);
    await members.setActive(memberId, false);

    final row = await members.byId(memberId, now: DateTime.utc(2026, 1, 15));
    expect(row!.status, MemberStatus.inactive);
  });

  test('searching does not treat a wildcard as a wildcard', () async {
    await members.create(
      fullName: 'Ali Khan',
      phone: '+923000000004',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
    await members.create(
      fullName: 'Fifty % Discount',
      phone: '+923000000005',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    final found = await members.list(search: '%');
    expect(found.map((r) => r.member.fullName), ['Fifty % Discount'],
        reason: 'an unescaped LIKE pattern returned the whole roster');
  });

  test('an inactive plan is still offered to the member on it', () async {
    final memberId = await members.create(
      fullName: 'On A Retired Plan',
      phone: '+923000000006',
      planId: quarterlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(quarterlyId)))
        .write(const MembershipPlansCompanion(isActive: Value(false)));

    expect((await members.plansFor(memberId)).map((p) => p.id),
        contains(quarterlyId));
  });
}
