import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// Importing the owner's ledger must not make anybody owe anything.
///
/// The sheet records what was collected, never who was enrolled, so a "0" in
/// March is both "he owed and did not pay" and "he had left by then" and there
/// is no third column that says which. Rather than guess at six hundred
/// members' worth of debt, the import draws a line: every month in the sheet is
/// history, nothing before the import is owed or earned, and each member's
/// first real bill falls on their own billing day in the month after the
/// import. That day comes from "Fee Submit" — the day they last handed money
/// over is the day they are billed on from now on.
void main() {
  late AppDatabase db;
  late int adminId;
  late int basicId;

  /// The gym's real September, the month the owner imports in.
  final importedOn = DateTime.utc(2026, 9, 18);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;

    Future<int> plan(String name, int priceMinor) async =>
        db.into(db.membershipPlans).insert(
              MembershipPlansCompanion.insert(
                name: name,
                durationMonths: 1,
                priceMinor: priceMinor,
              ),
            );

    basicId = await plan('Basic', 400000);
    await plan('Platinum', 1000000);
    await plan('Student Package', 250000);
  });

  tearDown(() async => db.close());

  /// The owner's sheet: merged title, headers, then one row per member.
  List<List<String?>> sheet(
    List<({String name, String phone, String feeSubmit, String plan,
        List<String> months})> members,
  ) =>
      [
        ['RICH MAN FITNESS GYM', null, null, null, null, null, null, null],
        [
          'Enroll.', 'Name', 'Contact Detail', 'Fee Submit',
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
          'Status', 'Plan',
        ],
        for (final (index, member) in members.indexed)
          [
            '${index + 1}', member.name, member.phone, member.feeSubmit,
            ...member.months,
            'Cash Payment', member.plan,
          ],
      ];

  Future<ImportSummary> import(List<List<String?>> rows) async {
    final detected = detectMapping(rows)!;
    final plans = await db.select(db.membershipPlans).get();
    return ImportService(db).commit(
      ledger: parseLedger(
        rows: rows,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: 2026,
        plans: plans,
      ),
      planId: basicId,
      recordedById: adminId,
      now: importedOn,
    );
  }

  Future<MemberBilling> billingFor(String name) async {
    final member = await (db.select(db.members)
          ..where((m) => m.fullName.equals(name)))
        .getSingle();
    return (await BillingCycleService(db).forMember(member.id))!;
  }

  /// Paid Jan–Jul, nothing since, last money in on 4 July.
  const lapsed = (
    name: 'Amir Riaz',
    phone: '0325-6851835',
    feeSubmit: '04-Jul-2026',
    plan: 'Platinum',
    months: [
      '###', '###', '0', '0', '###', '###',
      '###', '0', '0', '-', '-', '-',
    ],
  );

  /// Paid every month up to and including September, last money in on the 3rd.
  const current = (
    name: 'H. Abubakar Bhatti',
    phone: '0322-6363633',
    feeSubmit: '03-Sep-2026',
    plan: 'Platinum',
    months: [
      '###', '###', '###', '###', '###', '###',
      '###', '###', '###', '-', '-', '-',
    ],
  );

  group('the billing anchor', () {
    test('is the day of the month the member last paid', () async {
      await import(sheet([lapsed]));

      final member = await (db.select(db.members)
            ..where((m) => m.fullName.equals('Amir Riaz')))
          .getSingle();
      final membership = (await openMembershipFor(db, member.id))!;

      expect(membership.billingAnchorDay, 4);
    });

    test('is left unset when the sheet names no date', () async {
      await import(sheet([(
        name: 'No Date Member',
        phone: '0300-4144369',
        feeSubmit: '-',
        plan: 'Basic',
        months: [
          '###', '-', '-', '-', '-', '-',
          '-', '-', '-', '-', '-', '-',
        ],
      )]));

      final member = await (db.select(db.members)
            ..where((m) => m.fullName.equals('No Date Member')))
          .getSingle();
      final membership = (await openMembershipFor(db, member.id))!;

      expect(membership.billingAnchorDay, isNull);
    });
  });

  group('nothing is owed at import', () {
    test('a member who stopped paying in July owes nothing', () async {
      await import(sheet([lapsed]));

      expect((await billingFor('Amir Riaz')).outstandingMinor, 0);
    });

    test('a member who paid every month owes nothing', () async {
      await import(sheet([current]));

      expect((await billingFor('H. Abubakar Bhatti')).outstandingMinor, 0);
    });

    test('no cycle is left unsettled behind them', () async {
      await import(sheet([lapsed, current]));

      expect((await billingFor('Amir Riaz')).nextUnsettled, isNull);
      expect((await billingFor('H. Abubakar Bhatti')).nextUnsettled, isNull);
    });
  });

  group('the first bill', () {
    test('falls on the billing day in the month after the import', () async {
      await import(sheet([lapsed]));

      expect((await billingFor('Amir Riaz')).nextDueDate,
          DateTime.utc(2026, 10, 4));
    });

    test('does so even for a member paid up to the import month', () async {
      await import(sheet([current]));

      expect((await billingFor('H. Abubakar Bhatti')).nextDueDate,
          DateTime.utc(2026, 10, 3));
    });

    test('is next month even when the billing day is still to come', () async {
      // Imported on 18 September for a member billed on the 24th. The 24th of
      // this month has not passed, but it is not their bill either: the months
      // up to the import are closed, so the first one they are asked for is
      // 24 October.
      await import(sheet([(
        name: 'Late In The Month',
        phone: '0320-4354434',
        feeSubmit: '24-Sep-2026',
        plan: 'Student Package',
        months: [
          '###', '###', '###', '###', '###', '###',
          '###', '###', '###', '-', '-', '-',
        ],
      )]));

      expect((await billingFor('Late In The Month')).nextDueDate,
          DateTime.utc(2026, 10, 24));
    });

    test('clamps to the last day of a month too short to hold it', () async {
      final rows = sheet([(
        name: 'Month End Member',
        phone: '0300-4144369',
        feeSubmit: '31-Oct-2026',
        plan: 'Basic',
        months: [
          '-', '-', '-', '-', '-', '-',
          '-', '-', '-', '###', '-', '-',
        ],
      )]);
      final detected = detectMapping(rows)!;
      await ImportService(db).commit(
        ledger: parseLedger(
          rows: rows,
          headerRow: detected.headerRow,
          mapping: detected.mapping,
          year: 2026,
          plans: await db.select(db.membershipPlans).get(),
        ),
        planId: basicId,
        recordedById: adminId,
        // November has thirty days, so a member billed on the 31st is billed
        // on the 30th — without losing the 31st for December.
        now: DateTime.utc(2026, 10, 31),
      );

      expect((await billingFor('Month End Member')).nextDueDate,
          DateTime.utc(2026, 11, 30));
    });

    test('is for the plan fee and nothing more', () async {
      await import(sheet([lapsed]));
      await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 10, 4));

      final billing = await billingFor('Amir Riaz');
      expect(billing.outstandingMinor, 1000000);
      expect(billing.nextUnsettled!.start, DateTime.utc(2026, 10, 4));
    });
  });

  group('startup maintenance', () {
    test('opens no cycle between the import and the first bill', () async {
      await import(sheet([lapsed]));

      final opened = await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 9, 30));

      expect(opened, 0);
      expect((await billingFor('Amir Riaz')).outstandingMinor, 0);
    });
  });

  group('the months in the sheet', () {
    test('are kept as payment history', () async {
      final summary = await import(sheet([lapsed]));

      expect(summary.paymentsCreated, 5);
    });

    test('are all marked as imported, never as money taken today', () async {
      await import(sheet([lapsed]));

      final payments = await db.select(db.payments).get();
      expect(payments, isNotEmpty);
      expect(
        payments.every((p) => p.source == PaymentSource.imported),
        isTrue,
      );
    });
  });
}
