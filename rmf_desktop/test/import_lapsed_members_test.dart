import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// Members the ledger shows walking away, and the proposal to let them go.
///
/// The import forgives everything before it, so a member who paid once in
/// January and never again arrives looking exactly like one who is paid up —
/// and on the owner's real sheet there are hundreds of them. Left active they
/// fill the payments-due list and the reminder queue with people who stopped
/// coming months ago, and bury the members who really are behind.
///
/// The signal is a run of unpaid months that reaches the end of the ledger: the
/// member stopped paying and never came back. A gap they *did* come back from
/// is history, not a departure — Bilal is gone from February to June and pays
/// again in July, and he is still a member. Nothing here deactivates anybody on
/// its own; it decides who the owner is asked about.
void main() {
  late AppDatabase db;
  late int adminId;
  late int basicId;

  final importedOn = DateTime.utc(2026, 9, 18);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;
    basicId = await db.into(db.membershipPlans).insert(
          MembershipPlansCompanion.insert(
            name: 'Basic',
            durationMonths: 1,
            priceMinor: 400000,
          ),
        );
  });

  tearDown(() async => db.close());

  List<List<String?>> sheet(
          List<({String name, String phone, List<String> months})> members) =>
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
            '${index + 1}', member.name, member.phone, '15-Sep-2026',
            ...member.months,
            'Cash Payment', 'Basic',
          ],
      ];

  ParsedLedger parse(List<List<String?>> rows) {
    final detected = detectMapping(rows)!;
    return parseLedger(
      rows: rows,
      headerRow: detected.headerRow,
      mapping: detected.mapping,
      year: 2026,
    );
  }

  ParsedMemberRow rowFor(List<String> months) => parse(sheet([
        (name: 'Member', phone: '0300-4144369', months: months),
      ])).rows.single;

  const trailing = ['-', '-', '-'];

  group('unpaid months running to the end of the ledger', () {
    test('are counted from the last month the member paid', () {
      final row = rowFor([
        '###', '0', '0', '0', '0', '0', '0', '0', '0', ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 8);
    });

    test('start again from a later payment', () {
      final row = rowFor([
        '###', '###', '###', '0', '0', '0', '0', '0', '0', ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 6);
    });

    test('are none for a member paid up to the end', () {
      final row = rowFor([
        '###', '###', '###', '###', '###', '###',
        '###', '###', '###', ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 0);
    });

    test('stop at a gap the member came back from', () {
      // Bilal: away February to June, paying again in July.
      final row = rowFor([
        '###', '0', '0', '0', '0', '0', '###', '0', '0', ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 2);
    });

    test('are none where the member never paid at all', () {
      final row = rowFor([
        '0', '0', '0', '0', '0', '0', '0', '0', '0', ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 0);
    });
  });

  group('the proposal', () {
    test('is made after three unpaid months', () {
      final row = rowFor([
        '###', '###', '###', '###', '###', '###', '0', '0', '0', ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 3);
      expect(row.hasLapsed, isTrue);
    });

    test('is not made after two', () {
      final row = rowFor([
        '###', '###', '###', '###', '###', '###', '###', '0', '0',
        ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 2);
      expect(row.hasLapsed, isFalse);
    });

    test('is not made for scattered unpaid months', () {
      // Fakhar Jutt pays every other month and is plainly still a member.
      final row = rowFor([
        '###', '0', '###', '0', '###', '0', '###', '###', '###', ...trailing,
      ]);

      expect(row.hasLapsed, isFalse);
    });

    test('is not made for a gap the member came back from', () {
      final row = rowFor([
        '###', '0', '0', '0', '0', '0', '###', '0', '0', ...trailing,
      ]);

      expect(row.hasLapsed, isFalse);
    });

    test('names every member it applies to', () {
      final ledger = parse(sheet([
        (
          name: 'Shahiq',
          phone: '0300-4144369',
          months: ['###', '0', '0', '0', '0', '0', '0', '0', '0', ...trailing],
        ),
        (
          name: 'Bilal',
          phone: '0320-4354434',
          months: ['###', '0', '0', '0', '0', '0', '###', '0', '0',
              ...trailing],
        ),
        (
          name: 'Hammad Malik',
          phone: '0321-4757427',
          months: ['###', '###', '###', '0', '0', '0', '0', '0', '0',
              ...trailing],
        ),
      ]));

      expect(
        ledger.lapsed.map((r) => r.name),
        ['Shahiq', 'Hammad Malik'],
      );
    });
  });

  group('a ledger that shows its amounts', () {
    // What the owner's real sheet holds. Their columns are too narrow for the
    // figures, so Excel draws "###" — but the cell still stores the number, and
    // the workbook reader hands back the number rather than the rendering. A
    // retyped copy carrying literal "###" text is the unusual case, not this.
    test('reads the figure rather than falling back to the plan fee', () {
      final row = rowFor([
        '10000', '10000', '0', '0', '0', '0', '0', '0', '0', ...trailing,
      ]);

      expect(row.payments.map((p) => p.amountMinor), [1000000, 1000000]);
      expect(row.paymentsWithoutAmount, 0);
    });

    test('still sees the member walking away', () {
      final row = rowFor([
        '10000', '10000', '0', '0', '0', '0', '0', '0', '0', ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 7);
      expect(row.hasLapsed, isTrue);
    });

    test('still sees a member who came back', () {
      final row = rowFor([
        '10000', '0', '0', '0', '0', '0', '10000', '0', '0', ...trailing,
      ]);

      expect(row.trailingUnpaidMonths, 2);
      expect(row.hasLapsed, isFalse);
    });

    test('bills nobody for the months in it', () async {
      final rows = sheet([
        (
          name: 'Paid In Figures',
          phone: '0300-4144369',
          months: [
            '10000', '10000', '10000', '10000', '10000', '10000',
            '10000', '10000', '10000', ...trailing,
          ],
        ),
      ]);
      await ImportService(db).commit(
        ledger: parse(rows),
        planId: basicId,
        recordedById: adminId,
        now: importedOn,
      );

      final member = await (db.select(db.members)
            ..where((m) => m.fullName.equals('Paid In Figures')))
          .getSingle();
      final billing = await BillingCycleService(db).forMember(member.id);

      expect(billing!.outstandingMinor, 0);
      expect(billing.nextDueDate, DateTime.utc(2026, 10, 15));
    });
  });

  group('importing them', () {
    Future<ImportSummary> import(List<List<String?>> rows) =>
        ImportService(db).commit(
          ledger: parse(rows),
          planId: basicId,
          recordedById: adminId,
          now: importedOn,
        );

    final lapsedSheet = sheet([
      (
        name: 'Shahiq',
        phone: '0300-4144369',
        months: ['###', '0', '0', '0', '0', '0', '0', '0', '0', ...trailing],
      ),
      (
        name: 'Bilal',
        phone: '0320-4354434',
        months: ['###', '0', '0', '0', '0', '0', '###', '0', '0', ...trailing],
      ),
    ]);

    Future<Member> memberNamed(String name) => (db.select(db.members)
          ..where((m) => m.fullName.equals(name)))
        .getSingle();

    test('brings the lapsed member in deactivated', () async {
      await import(lapsedSheet);

      expect((await memberNamed('Shahiq')).deactivatedAt, isNotNull);
    });

    test('dates it to the end of the last month they paid for', () async {
      await import(lapsedSheet);

      expect((await memberNamed('Shahiq')).deactivatedAt?.toUtc(),
          DateTime.utc(2026, 2, 1));
    });

    test('leaves a member who came back active', () async {
      await import(lapsedSheet);

      expect((await memberNamed('Bilal')).deactivatedAt, isNull);
    });

    test('counts them for the owner', () async {
      final summary = await import(lapsedSheet);

      expect(summary.membersLapsed, 1);
    });

    test('keeps their payment history all the same', () async {
      await import(lapsedSheet);

      final shahiq = await memberNamed('Shahiq');
      final payments = await (db.select(db.payments)
            ..where((p) => p.memberId.equals(shahiq.id)))
          .get();

      expect(payments, hasLength(1));
    });

    test('does not bill them for a month they will not be here', () async {
      await import(lapsedSheet);

      final shahiq = await memberNamed('Shahiq');
      final billing = await BillingCycleService(db).forMember(shahiq.id);

      expect(billing!.outstandingMinor, 0);
    });
  });
}
