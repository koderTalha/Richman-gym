import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_month_checker.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/payment_edit_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';
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

/// Billing a month the ledger import waived.
///
/// The import covers every member it brings in from their last paid ledger
/// month to their first billing day with a zero-cost, pre-settled cycle, so
/// nobody arrives owing money for months the sheet cannot vouch for. On the
/// owner's real import — 22 September, a sheet running to September — that
/// waiver swallowed September for 301 of 439 active members, and picking
/// September on the Record Payment form resolved by containment to the waiver's
/// own start month: "This settles August 2026", for a cycle worth nothing.
///
/// A waiver is not a bill. It is the absence of one, and the owner is the only
/// person who can say which of the months inside it a member actually owes —
/// "he did not come in August, so why should he pay; he rejoined in September
/// and I want to record September". Naming a month inside a waiver therefore
/// takes that month out of it and bills it, and leaves every other month the
/// waiver covers exactly as forgiven as it was.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late BillingMonthChecker checker;
  late int adminId;
  late int studentId;

  /// The day the owner imported their ledger.
  final importedOn = DateTime.utc(2026, 9, 22);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    checker = BillingMonthChecker(db);
    adminId = (await db.select(db.users).getSingle()).id;

    studentId = await db.into(db.membershipPlans).insert(
          MembershipPlansCompanion.insert(
            name: 'Student Package',
            durationMonths: 1,
            priceMinor: 250000,
          ),
        );

    final workspace = await Directory.systemTemp.createTemp('rmf-waived');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
  });

  tearDown(() async => db.close());

  /// Usama Umer, enrolment 311 on the owner's sheet: paid January, nothing in
  /// February or March, paid April to July at a fee that moved, then nothing.
  /// Billed on the 7th.
  List<List<String?>> sheet() => [
        ['RICH MAN FITNESS GYM', null, null, null, null, null, null, null],
        [
          'Enroll.', 'Name', 'Contact Detail', 'Fee Submit',
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
          'Status', 'Plan',
        ],
        [
          '311', 'Usama Umer (Night)', '0306-5161859', '07-Jul-2026',
          '2500', '-', '-', '3000', '3000', '2500',
          '2500', '-', '-', '-', '-', '-',
          'Cash Payment', 'Student Package',
        ],
      ];

  Future<int> importLedger() async {
    final rows = sheet();
    final detected = detectMapping(rows)!;
    await ImportService(db).commit(
      ledger: parseLedger(
        rows: rows,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: 2026,
        plans: await db.select(db.membershipPlans).get(),
      ),
      planId: studentId,
      recordedById: adminId,
      now: importedOn,
    );
    final member = await (db.select(db.members)
          ..where((m) => m.fullName.equals('Usama Umer (Night)')))
        .getSingle();
    return member.id;
  }

  Future<List<MembershipPeriod>> cyclesOf(int memberId) =>
      periodsForMember(db, memberId);

  /// Two cycles covering the same day is the failure billing a month out of a
  /// waiver could most easily cause, and the one nothing else in the app would
  /// notice: status, arrears and the reminder queue would each pick a different
  /// one and disagree.
  Future<void> expectNoOverlaps(int memberId) async {
    final cycles = await cyclesOf(memberId);
    for (var i = 1; i < cycles.length; i++) {
      expect(
        cycles[i].periodStart.toUtc().isBefore(cycles[i - 1].periodEnd.toUtc()),
        isFalse,
        reason: '${cycles[i - 1].periodStart} and ${cycles[i].periodStart} '
            'overlap',
      );
    }
  }

  Future<RecordPaymentResult> recordSeptember(int memberId) =>
      payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: 250000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, 9, 23),
        billingMonth: '2026-09',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'september-1',
        expectedAmountMinor: 250000,
      ));

  test('the import waives August and September up to the first billing day',
      () async {
    final memberId = await importLedger();

    final waiver = (await cyclesOf(memberId)).last;
    expect(waiver.periodStart.toUtc(), DateTime.utc(2026, 8, 1));
    expect(waiver.periodEnd.toUtc(), DateTime.utc(2026, 10, 7));
    expect(waiver.expectedAmountMinor, 0);
    expect(waiver.settledAt, isNotNull,
        reason: 'this is the state the owner is looking at, and the premise of '
            'every test below');
  });

  test('September has no billing cycle of its own, so the form asks its fee',
      () async {
    final memberId = await importLedger();

    final check = await checker.check(
      memberId: memberId,
      billingMonth: '2026-09',
      now: DateTime.utc(2026, 9, 23),
    );

    expect(check.period, isNull,
        reason: 'the waiver covering September is not a bill for September — '
            'resolving to it is what made the form say "This settles August"');
  });

  test('recording September bills September, not the waiver', () async {
    final memberId = await importLedger();

    await recordSeptember(memberId);

    final september = (await cyclesOf(memberId)).firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 9, 1));
    expect(september.periodEnd.toUtc(), DateTime.utc(2026, 10, 1));
    expect(september.expectedAmountMinor, 250000);
    expect(september.settledAt, isNotNull);

    final allocations = await (db.select(db.paymentAllocations)
          ..where((a) => a.membershipPeriodId.equals(september.id)))
        .get();
    expect(allocations.single.amountMinor, 250000);
  });

  test('the receipt names September, not August', () async {
    final memberId = await importLedger();

    final result = await recordSeptember(memberId);

    final receipt = await (db.select(db.receipts)
          ..where((r) => r.id.equals(result.receiptId)))
        .getSingle();
    expect(receipt.receiptNumber, isNotEmpty);

    final payment = await (db.select(db.payments)
          ..where((p) => p.id.equals(result.paymentId)))
        .getSingle();
    final cycle = await (db.select(db.membershipPeriods)
          ..where((p) => p.id.equals(payment.membershipPeriodId!)))
        .getSingle();
    expect(cycle.periodStart.toUtc(), DateTime.utc(2026, 9, 1),
        reason: 'the period label on the receipt is read off this cycle');
  });

  test('August stays forgiven — he did not come, so he is not billed for it',
      () async {
    final memberId = await importLedger();

    await recordSeptember(memberId);

    final august = (await cyclesOf(memberId)).firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 8, 1));
    expect(august.periodEnd.toUtc(), DateTime.utc(2026, 9, 1),
        reason: 'the waiver gives up September and keeps August');
    expect(august.expectedAmountMinor, 0);
    expect(august.settledAt, isNotNull);
  });

  test('the days between the month billed and the first billing day stay free',
      () async {
    final memberId = await importLedger();

    await recordSeptember(memberId);

    final tail = (await cyclesOf(memberId)).firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 10, 1));
    expect(tail.periodEnd.toUtc(), DateTime.utc(2026, 10, 7),
        reason: 'the import promised no bill before the 7th, and billing one '
            'month out of the waiver does not move that promise');
    expect(tail.expectedAmountMinor, 0);
    expect(tail.settledAt, isNotNull);
  });

  test('nothing is owed once September is paid', () async {
    final memberId = await importLedger();

    await recordSeptember(memberId);

    final row = await members.byId(memberId, now: DateTime.utc(2026, 9, 23));
    expect(row!.outstandingMinor, isNull);
  });

  test('the owner can bill August instead when that is the month owed',
      () async {
    final memberId = await importLedger();

    await payments.call(RecordPaymentInput(
      memberId: memberId,
      amountMinor: 250000,
      method: PaymentMethod.cash,
      paymentDate: DateTime.utc(2026, 9, 23),
      billingMonth: '2026-08',
      sendWhatsApp: false,
      recordedById: adminId,
      idempotencyKey: 'august-1',
      expectedAmountMinor: 250000,
    ));

    final cycles = await cyclesOf(memberId);
    final august = cycles.firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 8, 1));
    expect(august.periodEnd.toUtc(), DateTime.utc(2026, 9, 1));
    expect(august.expectedAmountMinor, 250000);
    expect(august.settledAt, isNotNull);

    final remainder = cycles.firstWhere(
        (p) => p.periodStart.toUtc() == DateTime.utc(2026, 9, 1));
    expect(remainder.periodEnd.toUtc(), DateTime.utc(2026, 10, 7),
        reason: 'September onwards is still waived until he says otherwise');
    expect(remainder.expectedAmountMinor, 0);
  });

  test('no two cycles ever cover the same day', () async {
    final memberId = await importLedger();

    await recordSeptember(memberId);

    await expectNoOverlaps(memberId);
  });

  /// The owner's import left 301 members with September inside a waiver, in
  /// three shapes: 113 who paid nothing all year, 78 who last paid in July, and
  /// 110 who last paid in August. Which shape a member is in decides what is
  /// left of their waiver once September comes out of it, and the fourth —
  /// where the waiver is exactly the month billed — falls out of a billing day
  /// on the 1st.
  group('every shape a waiver comes in', () {
    /// Four members, each billed on the 1st so the waiver ends where a calendar
    /// month does, except the first, who keeps the 7th.
    List<List<String?>> shapes() => [
          ['RICH MAN FITNESS GYM', null, null, null, null, null, null, null],
          [
            'Enroll.', 'Name', 'Contact Detail', 'Fee Submit',
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
            'Status', 'Plan',
          ],
          // Last paid August, billed on the 7th: the waiver starts with the
          // month being billed and has days left after it.
          [
            '1', 'Paid To August', '0300-0000001', '07-Aug-2026',
            '2500', '2500', '2500', '2500', '2500', '2500',
            '2500', '2500', '-', '-', '-', '-',
            'Cash Payment', 'Student Package',
          ],
          // Last paid August, billed on the 1st: the waiver *is* September.
          [
            '2', 'Exactly September', '0300-0000002', '01-Aug-2026',
            '2500', '2500', '2500', '2500', '2500', '2500',
            '2500', '2500', '-', '-', '-', '-',
            'Cash Payment', 'Student Package',
          ],
          // Last paid July, billed on the 1st: the waiver has August in front
          // of the month being billed and nothing after it.
          [
            '3', 'Paid To July', '0300-0000003', '01-Jul-2026',
            '2500', '2500', '2500', '2500', '2500', '2500',
            '2500', '-', '-', '-', '-', '-',
            'Cash Payment', 'Student Package',
          ],
          // Never paid at all: the waiver runs from the day they were put on
          // the sheet.
          [
            '4', 'Never Paid', '0300-0000004', '01-Sep-2026',
            '-', '-', '-', '-', '-', '-',
            '-', '-', '-', '-', '-', '-',
            'Cash Payment', 'Student Package',
          ],
        ];

    Future<Map<String, int>> importShapes() async {
      final rows = shapes();
      final detected = detectMapping(rows)!;
      await ImportService(db).commit(
        ledger: parseLedger(
          rows: rows,
          headerRow: detected.headerRow,
          mapping: detected.mapping,
          year: 2026,
          plans: await db.select(db.membershipPlans).get(),
        ),
        planId: studentId,
        recordedById: adminId,
        now: importedOn,
      );
      return {
        for (final m in await db.select(db.members).get()) m.fullName: m.id,
      };
    }

    Future<void> billSeptember(int memberId, {required String key}) =>
        payments.call(RecordPaymentInput(
          memberId: memberId,
          amountMinor: 250000,
          method: PaymentMethod.cash,
          paymentDate: DateTime.utc(2026, 9, 23),
          billingMonth: '2026-09',
          sendWhatsApp: false,
          recordedById: adminId,
          idempotencyKey: key,
          expectedAmountMinor: 250000,
        ));

    Future<MembershipPeriod> septemberOf(int memberId) async =>
        (await cyclesOf(memberId)).firstWhere(
            (p) => p.periodStart.toUtc() == DateTime.utc(2026, 9, 1));

    test('the waiver keeps the days after the month billed', () async {
      final ids = await importShapes();
      final memberId = ids['Paid To August']!;

      await billSeptember(memberId, key: 'shape-1');

      final september = await septemberOf(memberId);
      expect(september.periodEnd.toUtc(), DateTime.utc(2026, 10, 1));
      expect(september.expectedAmountMinor, 250000);
      expect(september.settledAt, isNotNull);

      final remainder = (await cyclesOf(memberId)).last;
      expect(remainder.periodStart.toUtc(), DateTime.utc(2026, 10, 1));
      expect(remainder.periodEnd.toUtc(), DateTime.utc(2026, 10, 7));
      expect(remainder.expectedAmountMinor, 0);
      await expectNoOverlaps(memberId);
    });

    test('a waiver that is exactly the month billed becomes that bill',
        () async {
      final ids = await importShapes();
      final memberId = ids['Exactly September']!;

      final before = await cyclesOf(memberId);
      final waiver = before.last;
      expect(waiver.periodStart.toUtc(), DateTime.utc(2026, 9, 1));
      expect(waiver.periodEnd.toUtc(), DateTime.utc(2026, 10, 1));

      await billSeptember(memberId, key: 'shape-2');

      final after = await cyclesOf(memberId);
      expect(after, hasLength(before.length),
          reason: 'nothing is left to forgive either side, so the waiver is '
              'the bill rather than being replaced by one');

      final september = await septemberOf(memberId);
      expect(september.id, waiver.id);
      expect(september.expectedAmountMinor, 250000);
      expect(september.settledAt, isNotNull);
      await expectNoOverlaps(memberId);
    });

    test('the waiver keeps the months before the one billed', () async {
      final ids = await importShapes();
      final memberId = ids['Paid To July']!;

      await billSeptember(memberId, key: 'shape-3');

      final august = (await cyclesOf(memberId)).firstWhere(
          (p) => p.periodStart.toUtc() == DateTime.utc(2026, 8, 1));
      expect(august.periodEnd.toUtc(), DateTime.utc(2026, 9, 1));
      expect(august.expectedAmountMinor, 0,
          reason: 'August was never billed and billing September does not bill '
              'it');

      final september = await septemberOf(memberId);
      expect(september.periodEnd.toUtc(), DateTime.utc(2026, 10, 1));
      expect(september.expectedAmountMinor, 250000);
      await expectNoOverlaps(memberId);
    });

    test('a member with no history at all can still be billed September',
        () async {
      final ids = await importShapes();
      final memberId = ids['Never Paid']!;

      await billSeptember(memberId, key: 'shape-4');

      final september = await septemberOf(memberId);
      expect(september.expectedAmountMinor, 250000);
      expect(september.settledAt, isNotNull);

      final row = await members.byId(memberId, now: DateTime.utc(2026, 9, 23));
      expect(row!.outstandingMinor, isNull);
      await expectNoOverlaps(memberId);
    });
  });

  /// Once the waiver's last days are all that is left of it, they are shorter
  /// than a month — and a cycle for the month they fall in would have to run
  /// past them, over whatever billing maintenance has already rolled where the
  /// waiver ends.
  group('a waiver too short to give up the month asked for', () {
    test('never leaves two cycles covering the same day', () async {
      final memberId = await importLedger();
      await recordSeptember(memberId);

      // October arrives and the member rolls onto their own billing day.
      await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 10, 20));
      expect(
        (await cyclesOf(memberId)).any(
            (p) => p.periodStart.toUtc() == DateTime.utc(2026, 10, 7)),
        isTrue,
        reason: 'the premise: 7 October to 7 November now exists, and the '
            'waiver has only 1–7 October left',
      );

      await payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: 250000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, 10, 20),
        billingMonth: '2026-10',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'october-1',
        expectedAmountMinor: 250000,
      ));

      await expectNoOverlaps(memberId);
    });

    test('October settles the cycle that starts in October', () async {
      final memberId = await importLedger();
      await recordSeptember(memberId);

      // October arrives: the member rolls onto their own billing day, 7 October
      // to 7 November, with the last six days of the waiver in front of it.
      await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 10, 20));

      final check = await checker.check(
        memberId: memberId,
        billingMonth: '2026-10',
        now: DateTime.utc(2026, 10, 20),
      );
      expect(check.period?.periodStart.toUtc(), DateTime.utc(2026, 10, 7),
          reason: '1 October falls in the waiver\'s last six days, but the '
              'month the owner picked is billed by the cycle that starts in '
              'it');

      await payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: 250000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, 10, 20),
        billingMonth: '2026-10',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'october-2',
        expectedAmountMinor: 250000,
      ));

      final row = await members.byId(memberId, now: DateTime.utc(2026, 10, 20));
      expect(row!.outstandingMinor, isNull,
          reason: 'the money settled the cycle that was actually owed, not the '
              'six free days before it');
      await expectNoOverlaps(memberId);
    });
  });

  group('editing a payment onto a waived month', () {
    test('bills that month instead of crediting the waiver', () async {
      final memberId = await importLedger();
      final recorded = await payments.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: 250000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, 9, 23),
        billingMonth: '2026-08',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'edit-source',
        expectedAmountMinor: 250000,
      ));

      final editor = PaymentEditService(
        db: db,
        renderer: _FakeRenderer(),
        storage: _FakeStorage(await Directory.systemTemp.createTemp('rmf-edit')),
        audit: AuditRepository(db),
        payments: payments,
      );

      // The owner picked August by mistake; it was September he came back in.
      final result = await editor.edit(EditPaymentInput(
        paymentId: recorded.paymentId,
        amountMinor: 250000,
        method: PaymentMethod.cash,
        paymentDate: DateTime.utc(2026, 9, 23),
        billingMonth: '2026-09',
        editedById: adminId,
      ));
      expect(result, isA<PaymentEdited>());

      final payment = await (db.select(db.payments)
            ..where((p) => p.id.equals(recorded.paymentId)))
          .getSingle();
      final cycle = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(payment.membershipPeriodId!)))
          .getSingle();
      expect(cycle.periodStart.toUtc(), DateTime.utc(2026, 9, 1));
      expect(cycle.periodEnd.toUtc(), DateTime.utc(2026, 10, 1));
      expect(cycle.expectedAmountMinor, 250000);
      await expectNoOverlaps(memberId);
    });
  });
}
