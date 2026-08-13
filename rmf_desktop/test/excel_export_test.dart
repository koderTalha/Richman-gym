import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart' show Excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/excel_export_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

void main() {
  late AppDatabase db;
  late ExcelExportService export;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    export = ExcelExportService(db);

    await db
        .into(db.gymSettings)
        .insert(GymSettingsCompanion.insert(id: const Value(1)));

    final userId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Gym Owner', email: 'owner@rmf.local', passwordHash: 'x'));

    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: 300000));

    // One member with a phone, one without — the real sheet has both.
    final withPhone = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ahmed Test One',
          phone: '+923000000030',
          gender: const Value('Male'),
          joiningDate: DateTime.utc(2026, 1, 1),
        ));
    await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 2,
          fullName: 'No Phone Member',
          phone: '',
          gender: const Value('Female'),
          joiningDate: DateTime.utc(2026, 1, 1),
        ));

    final membershipId = await db.into(db.memberships).insert(
        MembershipsCompanion.insert(
            memberId: withPhone,
            planId: planId,
            startDate: DateTime.utc(2026, 1, 1)));

    final periodId = await db.into(db.membershipPeriods).insert(
        MembershipPeriodsCompanion.insert(
            membershipId: membershipId,
            periodStart: DateTime.utc(2026, 3, 1),
            periodEnd: DateTime.utc(2026, 4, 1),
            expectedAmountMinor: 300000));

    final paymentId = await db.into(db.payments).insert(
        PaymentsCompanion.insert(
            memberId: withPhone,
            membershipPeriodId: Value(periodId),
            amountMinor: 300000,
            method: PaymentMethod.cash,
            paymentDate: DateTime.utc(2026, 3, 4),
            recordedById: userId,
            idempotencyKey: 'test-1'));

    await db.into(db.receipts).insert(ReceiptsCompanion.insert(
        receiptNumber: 'RMF-2026-000001',
        paymentId: paymentId,
        pngPath: 'RMF-2026-000001.png'));
  });

  tearDown(() => db.close());

  Future<Excel> decode() async =>
      Excel.decodeBytes(await export.build(now: DateTime.utc(2026, 8, 13)));

  List<String?> row(Excel excel, String sheet, int index) =>
      excel.tables[sheet]!.rows[index]
          .map((c) => c?.value?.toString())
          .toList();

  test('produces a readable workbook with the expected sheets', () async {
    final excel = await decode();

    expect(excel.tables.keys, containsAll(['Members', 'Payments', 'Plans']));
    // One ledger sheet per year that has billing periods.
    expect(excel.tables.keys, contains('Ledger 2026'));
    // The empty default sheet is removed.
    expect(excel.tables.keys, isNot(contains('Sheet1')));
  });

  test('members sheet lists every member, sorted by enrolment number',
      () async {
    final excel = await decode();
    final sheet = excel.tables['Members']!;

    expect(sheet.rows.length, 3); // header + 2 members
    expect(row(excel, 'Members', 1)[1], 'Ahmed Test One');
    expect(row(excel, 'Members', 2)[1], 'No Phone Member');
  });

  test('a member with no phone is written as "-", like the original sheet',
      () async {
    final excel = await decode();
    expect(row(excel, 'Members', 2)[2], '-');
  });

  test('gender replaces the old section column', () async {
    final excel = await decode();
    expect(row(excel, 'Members', 0)[3], 'Gender');
    expect(row(excel, 'Members', 1)[3], 'Male');
    expect(row(excel, 'Members', 2)[3], 'Female');
  });

  test('member status is exported, not left for the reader to work out',
      () async {
    final excel = await decode();
    // March was paid; by August nothing covers today, so the membership lapsed.
    expect(row(excel, 'Members', 1).last, 'EXPIRED');
  });

  test('payments sheet carries the receipt number and amount', () async {
    final excel = await decode();
    final payment = row(excel, 'Payments', 1);

    expect(payment[0], 'RMF-2026-000001');
    expect(payment[2], 'Ahmed Test One');
    expect(payment[5], 'Rs. 3,000');
    expect(payment[6], 'Cash Payment');
  });

  test('the ledger sheet reproduces the original wide month layout', () async {
    final excel = await decode();
    final header = row(excel, 'Ledger 2026', 0);

    expect(header.take(3), ['Enroll.', 'Name', 'Contact Detail']);
    expect(header.sublist(3, 15),
        ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']);
  });

  test('the ledger puts the amount under the month it was paid', () async {
    final excel = await decode();
    final ledgerRow = row(excel, 'Ledger 2026', 1);

    expect(ledgerRow[3], '-', reason: 'January unpaid');
    expect(ledgerRow[5], '3000', reason: 'March paid');
    expect(ledgerRow.last, '3000', reason: 'row total');
  });

  test('the exported ledger can be read back by our own importer', () async {
    final excel = await decode();

    final rows = excel.tables['Ledger 2026']!.rows
        .map((r) => r.map((c) => c?.value?.toString()).toList())
        .toList();

    // Round-trip: what we write must be something we can also ingest.
    final detected = detectMapping(rows);
    expect(detected, isNotNull);

    final parsed = parseLedger(
      rows: rows,
      headerRow: detected!.headerRow,
      mapping: detected.mapping,
      year: 2026,
    );

    expect(parsed.valid.map((r) => r.name),
        containsAll(['Ahmed Test One', 'No Phone Member']));

    final abubakar =
        parsed.valid.firstWhere((r) => r.name == 'Ahmed Test One');
    expect(abubakar.payments.single.month, 3);
    expect(abubakar.payments.single.amountMinor, 300000);
  });

  test('an empty database still produces a valid workbook', () async {
    final empty = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(empty.close);

    final bytes = await ExcelExportService(empty).build();
    expect(bytes.length, greaterThan(0));
    expect(Excel.decodeBytes(bytes).tables.keys, contains('Members'));
  });
}
