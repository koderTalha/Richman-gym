import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart' show Excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/excel_export_service.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

/// The Excel export against the app's own reading of who has paid.
///
/// The export used to decide PAID/DUE and "Paid Until" from
/// `payments.membership_period_id`, which names only the first cycle a
/// payment touched, and to keep one payment per cycle in the ledger sheet. It
/// ignored both `settled_at` and `payment_allocations` — what the app itself
/// reads — so 391 freshly imported members read DUE in the file while the app
/// said PAID, advance payers read DUE with the wrong Paid Until, and the first
/// of two part-payments vanished from the ledger. The owner treats this file
/// as their readable backup. (Audit BUG-018.)
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
  late RecordPaymentService payments;
  late MemberRepository members;
  late int adminId;
  late int planId;
  var counter = 0;
  const fee = 300000;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-export-alloc');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adminId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(const GymSettingsCompanion());
    planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: fee));
    members = MemberRepository(db);
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(Directory(p.join(workspace.path, 'receipts'))),
      clientFactory: () async => MockWhatsAppClient(),
      cycles: BillingCycleService(db),
    );
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  Future<void> pay(int memberId, int amount, DateTime on) =>
      payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: amount,
        method: PaymentMethod.cash,
        paymentDate: on,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'k-${counter++}',
        confirmedAdvance: true,
      ));

  Future<int> join(String name, String phone) => members.create(
      fullName: name,
      phone: phone,
      planId: planId,
      joiningDate: DateTime.utc(2026, 1, 6));

  Future<Excel> export(DateTime now) async =>
      Excel.decodeBytes(await ExcelExportService(db).build(now: now));

  List<String?> rowFor(Excel excel, String sheet, String name) => excel
      .tables[sheet]!.rows
      .map((r) => r.map((c) => c?.value?.toString()).toList())
      .firstWhere((r) => r.contains(name));

  // Members columns: Enroll., Name, Contact, Gender, Membership, Fee,
  // Joining, Paid Until (7), Status (8).
  // Ledger columns: Enroll., Name, Contact, Jan..Dec (3..14), Total (15),
  // Plan (16).

  test('a member who paid three months ahead reads Paid in the export, as in '
      'the app', () async {
    final id = await join('Advance Payer', '+923000000101');
    await pay(id, 3 * fee, DateTime.utc(2026, 1, 6)); // Jan 6 - Apr 6

    final now = DateTime.utc(2026, 3, 15);
    final app = await members.byId(id, now: now);
    expect(app!.status, MemberStatus.paid, reason: 'the app says Paid');

    final row = rowFor(await export(now), 'Members', 'Advance Payer');
    expect(row[8], app.status.label, reason: 'export status must match the app');
    expect(row[7], '06-Apr-26', reason: 'paid until the end of the third cycle');
  });

  test('a multi-month advance payment spreads across its months in the ledger',
      () async {
    final id = await join('Advance Payer', '+923000000101');
    await pay(id, 3 * fee, DateTime.utc(2026, 1, 6));

    final excel = await export(DateTime.utc(2026, 3, 15));
    final ledger = rowFor(excel, 'Ledger 2026', 'Advance Payer');
    expect(ledger.sublist(3, 6), ['3000', '3000', '3000'],
        reason: 'January, February and March each hold their share');
    expect(ledger[6], '-', reason: 'April was not paid for');
    expect(ledger[15], '9000', reason: 'the Total is all the money taken');

    // The Payments sheet names every month the payment bought, not just the
    // first.
    final payment = rowFor(excel, 'Payments', 'Advance Payer');
    expect(payment[4], 'January 2026 - March 2026');
  });

  test('two part-payments against one cycle both appear in the ledger sheet',
      () async {
    final id = await join('Part Payer', '+923000000102');
    await pay(id, 150000, DateTime.utc(2026, 1, 6));
    await pay(id, 150000, DateTime.utc(2026, 1, 20));

    final collected = (await db.select(db.payments).get())
        .fold<int>(0, (s, p) => s + p.amountMinor);
    expect(collected, fee);

    final row = rowFor(
        await export(DateTime.utc(2026, 1, 25)), 'Ledger 2026', 'Part Payer');
    expect(row[3], '3000', reason: 'January collected Rs 3,000 in two parts');
    expect(row[15], '3000', reason: 'the Total must include both payments');
  });

  test('a member who has paid only part of the cycle reads as the app reads '
      'them, with the part they paid in the ledger', () async {
    final id = await join('Half Payer', '+923000000104');
    await pay(id, 150000, DateTime.utc(2026, 1, 6));

    final now = DateTime.utc(2026, 1, 20);
    final app = await members.byId(id, now: now);
    expect(app!.status, isNot(MemberStatus.paid),
        reason: 'precondition: half a fee does not settle the cycle');

    final excel = await export(now);
    final member = rowFor(excel, 'Members', 'Half Payer');
    expect(member[8], app.status.label);
    expect(member[7], '-', reason: 'no cycle is paid up yet');

    final ledger = rowFor(excel, 'Ledger 2026', 'Half Payer');
    expect(ledger[3], '1500');
    expect(ledger[15], '1500');
  });

  test('a waived cycle that holds no money reads Paid, until its end, with no '
      'money in the ledger', () async {
    final id = await join('Waived Member', '+923000000105');
    final membership = await (db.select(db.memberships)
          ..where((m) => m.memberId.equals(id)))
        .getSingle();
    await db.into(db.membershipPeriods).insert(
        MembershipPeriodsCompanion.insert(
          membershipId: membership.id,
          periodStart: DateTime.utc(2026, 1, 6),
          periodEnd: DateTime.utc(2026, 4, 6),
          expectedAmountMinor: 0,
          settledAt: Value(DateTime.utc(2026, 1, 6)),
        ));

    final now = DateTime.utc(2026, 2, 10);
    final app = await members.byId(id, now: now);
    expect(app!.status, MemberStatus.paid,
        reason: 'precondition: settled_at is what the app reads');

    final excel = await export(now);
    final member = rowFor(excel, 'Members', 'Waived Member');
    expect(member[8], app.status.label);
    expect(member[7], '06-Apr-26');

    final ledger = rowFor(excel, 'Ledger 2026', 'Waived Member');
    expect(ledger.sublist(3, 15), everyElement('-'),
        reason: 'a waiver is not money collected');
    expect(ledger[15], '-');
  });

  test('a member who changed plan keeps the months paid under the old one',
      () async {
    final id = await join('Plan Changer', '+923000000106');
    await pay(id, 2 * fee, DateTime.utc(2026, 1, 6)); // Jan 6 - Mar 6

    final plusId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly Plus', durationMonths: 1, priceMinor: 350000));
    final before = (await members.byId(id))!.member;
    await members.update(
      id: id,
      fullName: before.fullName,
      phone: before.phone,
      planId: plusId,
      joiningDate: before.joiningDate,
      now: DateTime.utc(2026, 2, 1),
    );
    expect(
        await (db.select(db.memberships)..where((m) => m.memberId.equals(id)))
            .get(),
        hasLength(2),
        reason: 'precondition: the change closed one enrolment and opened '
            'another');

    final now = DateTime.utc(2026, 2, 10);
    final app = await members.byId(id, now: now);

    final excel = await export(now);
    final member = rowFor(excel, 'Members', 'Plan Changer');
    expect(member[4], 'Monthly Plus', reason: 'the plan they are on now');
    expect(member[8], app!.status.label);
    expect(member[7], '06-Mar-26',
        reason: 'the months bought under the old enrolment still count');

    final ledger = rowFor(excel, 'Ledger 2026', 'Plan Changer');
    expect(ledger.sublist(3, 5), ['3000', '3000']);
    expect(ledger[15], '6000');
  });

  test('a member just imported from the ledger reads the same status in the '
      'export as in the app', () async {
    final sheet = <List<String?>>[
      ['Enroll.', 'Name', 'Contact Detail', 'Fee Submit',
       'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
       'Sep', 'Oct', 'Nov', 'Dec'],
      ['7', 'Imported Member', '0300-0000103', '06-Jan-26',
       '3000', '3000', '3000', '3000', '3000', '3000', '3000', '3000',
       '-', '-', '-', '-'],
    ];
    final detected = detectMapping(sheet)!;
    final ledger = parseLedger(
        rows: sheet,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: 2026);
    final now = DateTime.utc(2026, 9, 2);
    await ImportService(db)
        .commit(ledger: ledger, planId: planId, recordedById: adminId, now: now);

    final id = (await db.select(db.members).getSingle()).id;
    final app = await members.byId(id, now: now);

    final excel = await export(now);
    final row = rowFor(excel, 'Members', 'Imported Member');
    expect(row[8], app!.status.label,
        reason: 'export status must match the app (app: ${app.status.label})');

    // The covered cycle is not money: the ledger holds the eight imported
    // months and nothing for September.
    final months = rowFor(excel, 'Ledger 2026', 'Imported Member');
    expect(months.sublist(3, 11), everyElement('3000'));
    expect(months[11], '-');
    expect(months[15], '24000');
  });
}
