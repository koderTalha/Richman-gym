import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// Who a ledger row is, across year sheets and re-imports.
///
/// The ledger is one sheet per year, and the owner keeps correcting members
/// in the app between imports. Three ways that used to go wrong: importing
/// the years oldest first left everybody who appears in two of them
/// deactivated by the first one's year-end stamp; a phone corrected in the
/// app split the member in two on the next re-import, with every month
/// imported again; and a phoneless row merged into whoever held its
/// "Enroll." number, even when that number had been made up by the importer
/// for somebody else entirely.
void main() {
  late AppDatabase db;
  late int adminId;
  late int planId;
  final now = DateTime.utc(2026, 9, 2);

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

  ParsedLedger parse(List<List<String?>> sheet, int year) {
    final detected = detectMapping(sheet)!;
    return parseLedger(
        rows: sheet,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: year);
  }

  Future<ImportSummary> commit(ParsedLedger ledger) => ImportService(db)
      .commit(ledger: ledger, planId: planId, recordedById: adminId, now: now);

  const header = [
    'Enroll.', 'Name', 'Contact Detail',
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
    'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final paidAllYear = <List<String?>>[
    header,
    ['5', 'Ali Khan', '0300-0000001',
     '3000', '3000', '3000', '3000', '3000', '3000', '3000', '3000',
     '3000', '3000', '3000', '3000'],
  ];
  final paidToAugust = <List<String?>>[
    header,
    ['5', 'Ali Khan', '0300-0000001',
     '3000', '3000', '3000', '3000', '3000', '3000', '3000', '3000',
     '-', '-', '-', '-'],
  ];

  test('importing the year sheets oldest-first leaves a current member '
      'active, as importing newest-first does', () async {
    await commit(parse(paidAllYear, 2025));
    await commit(parse(paidToAugust, 2026));

    final member = await db.select(db.members).getSingle();
    await BillingMaintenance(db).ensureCurrentPeriods(now: now);
    final row = await MemberRepository(db).byId(member.id, now: now);

    // Newest-first gives deactivatedAt == null and status PAID (covered to
    // the first bill). Oldest-first should not differ.
    expect([member.deactivatedAt, row!.status], [null, MemberStatus.paid]);
  });

  test('a member whose phone the owner corrected is not duplicated when the '
      'sheet is imported again', () async {
    await commit(parse(paidToAugust, 2026));
    final paymentsBefore = (await db.select(db.payments).get()).length;

    // The owner fixes the number on the member screen.
    await (db.update(db.members)).write(
        const MembersCompanion(phone: Value('+923000000009')));

    await commit(parse(paidToAugust, 2026));

    final members = await db.select(db.members).get();
    final paymentsAfter = (await db.select(db.payments).get()).length;
    expect([members.length, paymentsAfter], [1, paymentsBefore],
        reason: 'same Enroll. 5, same name — one person; '
            'members: ${members.map((m) => '#${m.memberCode} ${m.fullName}').toList()}');
  });

  test('a phoneless row is not merged into a different phoneless person '
      'whose enrolment number the importer made up', () async {
    // 2026: Zara has no Enroll. value, so the importer assigns her the next
    // free code — 51 — which is Bilal's real enrolment number in 2025.
    await commit(parse(<List<String?>>[
      header,
      ['50', 'Asad Ali', '-', '3000', '-', '-', '-', '-', '-', '-', '-',
       '-', '-', '-', '-'],
      [null, 'Zara Bibi', '-', '3000', '-', '-', '-', '-', '-', '-', '-',
       '-', '-', '-', '-'],
    ], 2026));
    final zara = (await db.select(db.members).get())
        .firstWhere((m) => m.fullName == 'Zara Bibi');
    expect(zara.memberCode, 51);

    final summary = await commit(parse(<List<String?>>[
      header,
      ['51', 'Bilal Ahmed', '-', '-', '-', '-', '-', '3000', '3000', '-', '-',
       '-', '-', '-', '-'],
    ], 2025));

    final names = (await db.select(db.members).get()).map((m) => m.fullName);
    expect(names, contains('Bilal Ahmed'),
        reason: 'Bilal was folded into Zara (matched: ${summary.membersMatched}, '
            'merged-by-name: ${summary.membersMergedByName})');
  });

  group('a member an earlier sheet marked as having left', () {
    test('is reported as reactivated, and the log says the import did it',
        () async {
      await commit(parse(paidAllYear, 2025));
      final summary = await commit(parse(paidToAugust, 2026));

      expect(summary.membersReactivated, ['Ali Khan']);
      final events = await (db.select(db.auditEvents)
            ..where((e) => e.action.equals(AuditAction.memberReactivated)))
          .get();
      expect(events.single.summary, contains('ledger import'));
    });

    test('stays deactivated when the owner deactivated them by hand',
        () async {
      await commit(parse(paidAllYear, 2025));
      final member = await db.select(db.members).getSingle();

      // Reactivated, then deactivated again from the member screen: the
      // owner's decision now, whatever any sheet says.
      await MemberRepository(db).setActive(member.id, true, actorId: adminId);
      await MemberRepository(db).setActive(member.id, false, actorId: adminId);

      final summary = await commit(parse(paidToAugust, 2026));

      final after = await db.select(db.members).getSingle();
      expect(after.deactivatedAt, isNotNull);
      expect(summary.membersReactivated, isEmpty);
    });

    test('even when the owner\'s stamp happens to fall on a 1st at midnight',
        () async {
      await commit(parse(paidAllYear, 2025));
      final member = await db.select(db.members).getSingle();
      await MemberRepository(db).setActive(member.id, false, actorId: adminId);
      await (db.update(db.members)).write(
          MembersCompanion(deactivatedAt: Value(DateTime.utc(2026, 1, 1))));

      await commit(parse(paidToAugust, 2026));

      expect((await db.select(db.members).getSingle()).deactivatedAt,
          isNotNull,
          reason: 'the audit event is what marks a deactivation as the '
              "owner's, not the shape of its date");
    });

    test('stays deactivated, as of the later year, when that sheet is '
        'history too', () async {
      await commit(parse(paidAllYear, 2024));
      final summary = await commit(parse(paidAllYear, 2025));

      final member = await db.select(db.members).getSingle();
      expect(member.deactivatedAt?.toUtc(), DateTime.utc(2025, 12, 31));
      expect(summary.membersReactivated, isEmpty);
    });

    test('is not reactivated by importing the same sheet again', () async {
      // Paid to May and nothing since: this sheet itself has them leaving.
      final leftInMay = <List<String?>>[
        header,
        ['5', 'Ali Khan', '0300-0000001',
         '3000', '3000', '3000', '3000', '3000', '0', '0', '0',
         '-', '-', '-', '-'],
      ];
      await commit(parse(leftInMay, 2026));
      final summary = await commit(parse(leftInMay, 2026));

      expect((await db.select(db.members).getSingle()).deactivatedAt,
          isNotNull);
      expect(summary.membersReactivated, isEmpty);
    });

    test('a lapsed stamp is lifted when a newer copy of the sheet shows '
        'them paying again', () async {
      await commit(parse(<List<String?>>[
        header,
        ['5', 'Ali Khan', '0300-0000001',
         '3000', '3000', '3000', '3000', '3000', '0', '0', '0',
         '-', '-', '-', '-'],
      ], 2026));
      final summary = await commit(parse(paidToAugust, 2026));

      final member = await db.select(db.members).getSingle();
      await BillingMaintenance(db).ensureCurrentPeriods(now: now);
      final row = await MemberRepository(db).byId(member.id, now: now);
      expect([member.deactivatedAt, row!.status], [null, MemberStatus.paid]);
      expect(summary.membersReactivated, ['Ali Khan']);
    });
  });

  test('a match on enrolment number and name across a changed phone is '
      'reported for the owner to check', () async {
    await commit(parse(paidToAugust, 2026));
    await (db.update(db.members)).write(
        const MembersCompanion(phone: Value('+923000000009')));

    final summary = await commit(parse(paidToAugust, 2026));

    expect([summary.membersMatched, summary.membersMatchedOnCode], [1, 1]);
  });

  test('a phoneless row with the same enrolment number and name is still '
      'the same person', () async {
    final sheet = <List<String?>>[
      header,
      ['60', 'Phoneless Member', '-', '3000', '-', '-', '-', '-', '-', '-',
       '-', '-', '-', '-', '-'],
    ];
    await commit(parse(sheet, 2026));
    final summary = await commit(parse(sheet, 2026));

    expect((await db.select(db.members).get()).length, 1);
    expect([summary.membersMatched, summary.membersMatchedOnCode], [1, 0]);
  });

  group('a ledger enrolment number', () {
    test('already taken by somebody else is replaced, and the owner is told',
        () async {
      await commit(parse(<List<String?>>[
        header,
        ['5', 'Ali Khan', '0300-0000001', '3000', '-', '-', '-', '-', '-',
         '-', '-', '-', '-', '-', '-'],
      ], 2026));

      final summary = await commit(parse(<List<String?>>[
        header,
        ['5', 'Bilal Ahmed', '0300-0000002', '3000', '-', '-', '-', '-', '-',
         '-', '-', '-', '-', '-', '-'],
      ], 2026));

      final bilal = (await db.select(db.members).get())
          .firstWhere((m) => m.fullName == 'Bilal Ahmed');
      expect(bilal.memberCode, isNot(5));
      expect(summary.codesReassigned.single,
          allOf(contains('Bilal Ahmed'), contains('Ali Khan'),
              contains('#${bilal.memberCode}')));
    });

    test('is never handed to a row without one when the sheet uses it '
        'further down', () async {
      await commit(parse(<List<String?>>[
        header,
        ['50', 'Asad Ali', '-', '3000', '-', '-', '-', '-', '-', '-', '-',
         '-', '-', '-', '-'],
      ], 2026));

      // Zara has no code. 51 is the next one up — and Bilal's own.
      final summary = await commit(parse(<List<String?>>[
        header,
        [null, 'Zara Bibi', '-', '3000', '-', '-', '-', '-', '-', '-', '-',
         '-', '-', '-', '-'],
        ['51', 'Bilal Ahmed', '-', '3000', '-', '-', '-', '-', '-', '-', '-',
         '-', '-', '-', '-'],
      ], 2026));

      final members = {
        for (final m in await db.select(db.members).get())
          m.fullName: m.memberCode,
      };
      expect(members['Bilal Ahmed'], 51);
      expect(members['Zara Bibi'], isNot(51));
      expect(summary.codesReassigned, isEmpty);
    });
  });
}
