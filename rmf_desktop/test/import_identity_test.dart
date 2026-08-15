import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// How the importer decides whether a ledger row is somebody already on file.
///
/// Two situations from the owner's real sheet drive this:
///
///  * One phone number can cover several people — an elder brother asked to be
///    registered under his younger brother's number. They are two members.
///  * Some rows carry neither a phone number nor an enrolment number. They
///    still must not multiply every time the same sheet is imported again.
void main() {
  late AppDatabase db;
  late int adminId;
  late int planId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;
    planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
  });

  tearDown(() async => db.close());

  ParsedLedger parse(List<List<String?>> sheet, {int year = 2026}) {
    final detected = detectMapping(sheet)!;
    return parseLedger(
      rows: sheet,
      headerRow: detected.headerRow,
      mapping: detected.mapping,
      year: year,
    );
  }

  // The default `now` sits inside the ledger year the fixtures use, so these
  // members import as active. Historical sheets have their own group below.
  Future<ImportSummary> commit(ParsedLedger ledger, {DateTime? now}) =>
      ImportService(db).commit(
        ledger: ledger,
        planId: planId,
        recordedById: adminId,
        now: now ?? DateTime.utc(ledger.year, 6, 1),
      );

  group('one phone number shared by two people', () {
    final brothers = <List<String?>>[
      ['RICH MAN FITNESS GYM', null, null, null, null],
      ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
      ['1', 'Younger Brother', '0300-0000001', '3000', '3000'],
      ['2', 'Elder Brother', '0300-0000001', '3000', '3000'],
    ];

    test('imports as two members, not one', () async {
      final summary = await commit(parse(brothers));

      expect(summary.membersCreated, 2,
          reason: 'same number, different names — two people');
      expect(summary.membersMatched, 0);
      expect(summary.paymentsCreated, 4,
          reason: 'both brothers paid January and February');

      final members = await db.select(db.members).get();
      expect(members.map((m) => m.fullName),
          containsAll(['Younger Brother', 'Elder Brother']));
      expect(members.every((m) => m.phone == '+923000000001'), isTrue,
          reason: 'both keep the number they are reachable on');
    });

    test('re-importing matches both of them, not just the first', () async {
      await commit(parse(brothers));
      final second = await commit(parse(brothers));

      expect(second.membersCreated, 0);
      expect(second.membersMatched, 2);
      expect(second.paymentsCreated, 0);
      expect((await db.select(db.members).get()).length, 2);
      expect((await db.select(db.payments).get()).length, 4);
    });

    test('the same person on the same number is still only one member',
        () async {
      await commit(parse(brothers));
      final second = await commit(parse(<List<String?>>[
        ['RICH MAN FITNESS GYM', null, null, null, null],
        ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
        ['1', '  younger   BROTHER ', '0300-0000001', '3000', '3000'],
      ]));

      expect(second.membersCreated, 0,
          reason: 'casing and stray spaces are not a different person');
      expect(second.membersMatched, 1);
      expect((await db.select(db.members).get()).length, 2);
    });
  });

  group('a row with no phone and no enrolment number', () {
    final ghost = <List<String?>>[
      ['RICH MAN FITNESS GYM', null, null, null],
      ['Name', 'Contact Detail', 'Jan', 'Feb'],
      ['Ghost Member', '-', '3000', '-'],
    ];

    test('is not duplicated when the same sheet is imported again', () async {
      final first = await commit(parse(ghost));
      final second = await commit(parse(ghost));

      expect(first.membersCreated, 1);
      expect(second.membersCreated, 0,
          reason: 'the name is the only identity the row has');
      expect(second.membersMatched, 1);
      expect((await db.select(db.members).get()).length, 1);
      expect((await db.select(db.payments).get()).length, 1);
    });

    test('is matched despite casing and spacing changes in the sheet',
        () async {
      await commit(parse(ghost));
      final second = await commit(parse(<List<String?>>[
        ['RICH MAN FITNESS GYM', null, null, null],
        ['Name', 'Contact Detail', 'Jan', 'Feb'],
        ['  GHOST   MEMBER ', '-', '3000', '-'],
      ]));

      expect(second.membersCreated, 0);
      expect((await db.select(db.members).get()).length, 1);
    });

    test('still keeps genuinely different names apart', () async {
      final summary = await commit(parse(<List<String?>>[
        ['RICH MAN FITNESS GYM', null, null, null],
        ['Name', 'Contact Detail', 'Jan', 'Feb'],
        ['Ghost One', '-', '3000', '-'],
        ['Ghost Two', '-', '3000', '-'],
        ['Ghost Three', '', '-', '-'],
      ]));

      expect(summary.membersCreated, 3, reason: 'three distinct people');
    });

    test('does not attach itself to a member who has a phone number', () async {
      await commit(parse(<List<String?>>[
        ['RICH MAN FITNESS GYM', null, null, null],
        ['Name', 'Contact Detail', 'Jan', 'Feb'],
        ['Ghost Member', '0300-0000001', '3000', '-'],
      ]));
      final second = await commit(parse(ghost));

      expect(second.membersCreated, 1,
          reason: 'a phoneless row cannot claim someone who has a number');
      expect((await db.select(db.members).get()).length, 2);
    });

    test('nor when the row carries an enrolment number', () async {
      // The same guarantee, reached through the enrolment-number branch rather
      // than the name one. Without the "Enroll." column here the phoneless row
      // never gets that far, and the property looks proven when it is not.
      await commit(parse(<List<String?>>[
        ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
        ['7', 'Has A Phone', '0300-0000001', '3000', '-'],
      ]));

      final second = await commit(parse(<List<String?>>[
        ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
        ['7', 'Totally Different Person', '-', '-', '3000'],
      ]));

      expect(second.membersCreated, 1,
          reason: 'sharing an enrolment number is not being the same person '
              'when one of them has a number on file and the other does not');

      final members = await db.select(db.members).get();
      expect(members.map((m) => m.fullName),
          containsAll(['Has A Phone', 'Totally Different Person']));
    });

    test('two namesakes with different enrolment numbers stay two people',
        () async {
      final summary = await commit(parse(<List<String?>>[
        ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
        ['1', 'Muhammad Ali', '-', '3000', '-'],
        ['2', 'Muhammad Ali', '-', '-', '3000'],
      ]));

      expect(summary.membersCreated, 2,
          reason: 'the sheet gives them different Enroll. numbers, and its own '
              'key beats a coincidence of spelling');
      expect(summary.membersMergedByName, 0);
    });

    test('merging on name alone is reported, never silent', () async {
      // No Enroll. column and no numbers: a matching name is genuinely all
      // there is to go on, so these do merge — but the owner is told, because
      // only they can tell a repeat entry from a namesake.
      final summary = await commit(parse(<List<String?>>[
        ['Name', 'Contact Detail', 'Jan', 'Feb'],
        ['Muhammad Ali', '-', '3000', '-'],
        ['Muhammad Ali', '-', '-', '3000'],
      ]));

      expect(summary.membersCreated, 1);
      expect(summary.membersMergedByName, 1,
          reason: 'an invisible merge is one the owner can never correct');
    });
  });

  group('a member renamed in the app', () {
    final sheet = <List<String?>>[
      ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
      ['1', 'Ali Khaan', '0300-0000001', '3000', '3000'],
    ];

    test('is recognised on re-import by enrolment number', () async {
      await commit(parse(sheet));

      // The owner corrects the typo in the member form. The sheet still has it.
      final member = await db.select(db.members).getSingle();
      await (db.update(db.members)..where((m) => m.id.equals(member.id)))
          .write(const MembersCompanion(fullName: Value('Ali Khan')));

      final second = await commit(parse(sheet));

      expect(second.membersCreated, 0,
          reason: 'correcting a name in the app must not make the next import '
              'a second copy of the same person');
      expect(second.membersMatched, 1);
      expect((await db.select(db.payments).get()).length, 2,
          reason: 'and must not double-count the year');
    });

    test('punctuation alone is not a different person', () async {
      await commit(parse(<List<String?>>[
        ['Name', 'Contact Detail', 'Jan', 'Feb'],
        ['Md. Ali Khan', '-', '3000', '-'],
      ]));

      final second = await commit(parse(<List<String?>>[
        ['Name', 'Contact Detail', 'Jan', 'Feb'],
        ['Md Ali Khan', '-', '3000', '-'],
      ]));

      expect(second.membersCreated, 0);
      expect((await db.select(db.members).get()).length, 1);
    });
  });

  group('the billing cycles a ledger creates', () {
    test('are one month each, whatever plan the import is assigned to',
        () async {
      final quarterlyId = (await (db.select(db.membershipPlans)
                ..where((p) => p.name.equals('Quarterly')))
              .getSingle())
          .id;

      await ImportService(db).commit(
        ledger: parse(<List<String?>>[
          ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
          ['1', 'Ali Khan', '0300-0000001', '3000', '3000'],
        ]),
        planId: quarterlyId,
        recordedById: adminId,
        now: DateTime.utc(2026, 6, 1),
      );

      final cycles = await db.select(db.membershipPeriods).get();
      expect(cycles.length, 2);

      // Stretching each ledger column to the plan's length made January run to
      // April and February to May: two cycles covering the same days, after
      // which status, billing maintenance and the export all disagreed.
      final sorted = cycles.toList()
        ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
      expect(sorted.first.periodEnd.toUtc(), DateTime.utc(2026, 2, 1));
      expect(sorted.last.periodStart.toUtc(), DateTime.utc(2026, 2, 1));

      for (var i = 1; i < sorted.length; i++) {
        expect(
          sorted[i - 1].periodEnd.toUtc().isAfter(sorted[i].periodStart.toUtc()),
          isFalse,
          reason: 'cycles must not overlap',
        );
      }
    });
  });

  group('a ledger for a year that has ended', () {
    final sheet = <List<String?>>[
      ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb'],
      ['1', 'Ali Khan', '0300-0000001', '3000', '3000'],
    ];

    test('brings its members in as inactive', () async {
      final summary = await commit(parse(sheet, year: 2023),
          now: DateTime.utc(2026, 8, 15));

      expect(summary.membersAddedAsInactive, 1);

      final member = await db.select(db.members).getSingle();
      expect(member.deactivatedAt, isNotNull,
          reason: 'a 2023 sheet records who was a member in 2023, not who '
              'trains here now — and it has no column saying who left');
    });

    test('so they do not turn up owing this month', () async {
      await commit(parse(sheet, year: 2023), now: DateTime.utc(2026, 8, 15));
      await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 8, 15));

      final due = await MemberRepository(db)
          .list(filter: MemberFilter.due, now: DateTime.utc(2026, 8, 15));
      expect(due, isEmpty);
    });

    test('but the current year is left active', () async {
      final summary = await commit(parse(sheet, year: 2026),
          now: DateTime.utc(2026, 8, 15));

      expect(summary.membersAddedAsInactive, 0);
      expect((await db.select(db.members).getSingle()).deactivatedAt, isNull);
    });

    test('and an existing member is never deactivated by an old sheet',
        () async {
      await commit(parse(sheet, year: 2026), now: DateTime.utc(2026, 8, 15));
      await commit(parse(sheet, year: 2023), now: DateTime.utc(2026, 8, 15));

      expect((await db.select(db.members).getSingle()).deactivatedAt, isNull,
          reason: 'importing history must not retire somebody the owner has '
              'already said is current');
    });
  });
}
