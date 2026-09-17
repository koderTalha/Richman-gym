import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// The ledger's "Plan" column, which names the plan each member belongs on.
///
/// The gym runs twelve plans whose names were typed by the owner, not chosen
/// from a list: mixed case, hyphens, digits and multi-word names all appear.
/// The sheet only ever *names* a plan — it can never bring a new one into
/// existence, because the plans configured in the app are the source of truth.

/// Every plan the owner's gym actually has, in the spelling they use.
const _gymPlans = [
  'Basic',
  'Student Package',
  'Mature',
  'GOLD-PT',
  'PLATINUM',
  'Silver',
  'Monthly',
  'Quarterly',
  'Super PRO',
  '6 Months',
  'Champion',
  'Annual',
];

/// Seeding gives the four stock plans; the other eight are ones the owner added
/// on the Settings screen, so the fixture adds them the same way.
const _ownerAddedPlans = [
  ('Basic', 1, 300000),
  ('Student Package', 1, 250000),
  ('Mature', 1, 200000),
  ('GOLD-PT', 1, 1200000),
  ('PLATINUM', 1, 900000),
  ('Silver', 1, 400000),
  ('Super PRO', 3, 1000000),
  ('Champion', 6, 1800000),
];

/// One row per entry, in the shape of the owner's real sheet: a merged title
/// row, then headers, then members, with "Plan" sitting after "Status" exactly
/// as it does in their file.
List<List<String?>> _sheet(
  List<({int code, String name, String phone, String? plan})> members, {
  bool withPlanColumn = true,
}) =>
    [
      ['RICH MAN FITNESS GYM', null, null, null, null, null, null, null],
      [
        'Enroll.', 'Name', 'Contact Detail',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        'Status',
        if (withPlanColumn) 'Plan',
      ],
      for (final member in members)
        [
          '${member.code}', member.name, member.phone,
          '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-',
          'Cash Payment',
          if (withPlanColumn) member.plan,
        ],
    ];

void main() {
  late AppDatabase db;
  late int adminId;
  late int fallbackPlanId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;

    for (final (name, months, priceMinor) in _ownerAddedPlans) {
      await db.into(db.membershipPlans).insert(
            MembershipPlansCompanion.insert(
              name: name,
              durationMonths: months,
              priceMinor: priceMinor,
            ),
          );
    }

    fallbackPlanId = await _planId(db, 'Monthly');
  });

  tearDown(() async => db.close());

  Future<ParsedLedger> parse(List<List<String?>> sheet) async {
    final detected = detectMapping(sheet)!;
    return parseLedger(
      rows: sheet,
      headerRow: detected.headerRow,
      mapping: detected.mapping,
      year: 2026,
      plans: await db.select(db.membershipPlans).get(),
    );
  }

  Future<ImportSummary> commit(ParsedLedger ledger) => ImportService(db).commit(
        ledger: ledger,
        planId: fallbackPlanId,
        recordedById: adminId,
        now: DateTime.utc(2026, 6, 1),
      );

  group('every configured plan resolves to itself', () {
    test('all twelve names put the member on that exact plan', () async {
      final rows = [
        for (final (index, plan) in _gymPlans.indexed)
          (
            code: index + 1,
            name: 'Member ${index + 1}',
            phone: '0300-000${(index + 1).toString().padLeft(4, '0')}',
            plan: plan,
          ),
      ];

      final planCountBefore = (await db.select(db.membershipPlans).get()).length;
      final summary = await commit(await parse(_sheet(rows)));

      expect(summary.membersCreated, _gymPlans.length);
      expect(summary.rowsNeedingAttention, 0);

      for (final (index, planName) in _gymPlans.indexed) {
        final member = await _memberNamed(db, 'Member ${index + 1}');
        final membership = await openMembershipFor(db, member.id);

        expect(membership, isNotNull, reason: '$planName member has no enrolment');
        expect(membership!.planId, await _planId(db, planName),
            reason: '"$planName" must resolve to the plan of that name');
      }

      expect((await db.select(db.membershipPlans).get()).length, planCountBefore,
          reason: 'the sheet names plans, it never creates them');
    });
  });

  group('matching', () {
    test('ignores case and surrounding whitespace', () async {
      await commit(await parse(_sheet([
        (code: 1, name: 'Lower Case', phone: '0300-0000001', plan: 'platinum'),
        (code: 2, name: 'Padded', phone: '0300-0000002', plan: '  Basic  '),
        (code: 3, name: 'Shouted', phone: '0300-0000003', plan: 'ANNUAL'),
      ])));

      expect(await _planOf(db, 'Lower Case'), await _planId(db, 'PLATINUM'));
      expect(await _planOf(db, 'Padded'), await _planId(db, 'Basic'));
      expect(await _planOf(db, 'Shouted'), await _planId(db, 'Annual'));
    });

    test('collapses a doubled space inside a multi-word name', () async {
      await commit(await parse(_sheet([
        (code: 1, name: 'Typo Space', phone: '0300-0000001', plan: 'Student  Package'),
      ])));

      expect(await _planOf(db, 'Typo Space'), await _planId(db, 'Student Package'));
    });

    test('does not treat "Gold" as GOLD-PT', () async {
      final ledger = await parse(_sheet([
        (code: 1, name: 'Nearly Gold', phone: '0300-0000001', plan: 'Gold'),
      ]));

      expect(ledger.valid, isEmpty);
      expect(ledger.invalid.single.problems.single, contains('Gold'));
    });
  });

  group('a plan the app does not have', () {
    test('skips the row rather than inventing the plan', () async {
      final planCountBefore = (await db.select(db.membershipPlans).get()).length;

      final ledger = await parse(_sheet([
        (code: 1, name: 'Good Row', phone: '0300-0000001', plan: 'Silver'),
        (code: 2, name: 'Bad Row', phone: '0300-0000002', plan: 'Non Existing Plan'),
      ]));

      final bad = ledger.invalid.single;
      expect(bad.name, 'Bad Row');
      expect(bad.sourceRow, 4, reason: 'the row number the owner sees in Excel');
      expect(bad.problems.single, contains('Non Existing Plan'));

      final summary = await commit(ledger);

      expect(summary.membersCreated, 1, reason: 'only the good row imports');
      expect(summary.rowsNeedingAttention, 1);
      expect(await _memberOrNull(db, 'Bad Row'), isNull,
          reason: 'never imported onto some other plan instead');
      expect((await db.select(db.membershipPlans).get()).length, planCountBefore);
    });
  });

  group('a row that names no plan', () {
    test('falls back to the plan chosen in the wizard', () async {
      final ledger = await parse(_sheet([
        (code: 1, name: 'Blank Plan', phone: '0300-0000001', plan: ''),
        (code: 2, name: 'No Plan Cell', phone: '0300-0000002', plan: null),
      ]));

      expect(ledger.valid.length, 2, reason: 'a blank plan is not an error');
      await commit(ledger);

      expect(await _planOf(db, 'Blank Plan'), fallbackPlanId);
      expect(await _planOf(db, 'No Plan Cell'), fallbackPlanId);
    });
  });

  group('two plans sharing a name', () {
    test('keeps the older one rather than failing or guessing', () async {
      final firstBasic = await _planId(db, 'Basic');
      await db.into(db.membershipPlans).insert(
            MembershipPlansCompanion.insert(
              name: 'Basic',
              durationMonths: 1,
              priceMinor: 500000,
            ),
          );

      await commit(await parse(_sheet([
        (code: 1, name: 'Ambiguous', phone: '0300-0000001', plan: 'Basic'),
      ])));

      expect(await _planOf(db, 'Ambiguous'), firstBasic);
    });
  });

  group('a member already on file', () {
    test('keeps the plan they are enrolled on', () async {
      await commit(await parse(_sheet([
        (code: 1, name: 'Ali Khan', phone: '0300-0000001', plan: 'Silver'),
      ])));
      final silver = await _planId(db, 'Silver');
      expect(await _planOf(db, 'Ali Khan'), silver);

      await commit(await parse(_sheet([
        (code: 1, name: 'Ali Khan', phone: '0300-0000001', plan: 'PLATINUM'),
      ])));

      expect(await _planOf(db, 'Ali Khan'), silver,
          reason: 'a historical sheet does not move a live member off their plan');
      expect((await db.select(db.memberships).get()).length, 1,
          reason: 'and does not open a second enrolment');
    });
  });

  group('a sheet with no Plan column', () {
    test('puts everyone on the plan chosen in the wizard, as before', () async {
      final ledger = await parse(_sheet(
        [
          (code: 1, name: 'Old Format One', phone: '0300-0000001', plan: null),
          (code: 2, name: 'Old Format Two', phone: '0300-0000002', plan: null),
        ],
        withPlanColumn: false,
      ));

      expect(ledger.mapping.plan, isNull);
      expect(ledger.valid.length, 2);

      await commit(ledger);

      expect(await _planOf(db, 'Old Format One'), fallbackPlanId);
      expect(await _planOf(db, 'Old Format Two'), fallbackPlanId);
    });
  });

  group('the amount a plan implies', () {
    test('a ### month is billed at the named plan\'s price', () async {
      final sheet = _sheet([
        (code: 1, name: 'Hash Row', phone: '0300-0000001', plan: 'Champion'),
      ]);
      sheet[2][3] = '####'; // January, too narrow to read

      await commit(await parse(sheet));

      final champion = await (db.select(db.membershipPlans)
            ..where((p) => p.name.equals('Champion')))
          .getSingle();
      final payment = await (db.select(db.payments)).getSingle();

      expect(payment.amountMinor, champion.priceMinor,
          reason: 'not the price of the plan chosen in the wizard');
    });
  });
}

Future<int> _planId(AppDatabase db, String name) async {
  final rows = await (db.select(db.membershipPlans)
        ..where((p) => p.name.equals(name))
        ..orderBy([(p) => OrderingTerm(expression: p.id)]))
      .get();
  return rows.first.id;
}

Future<Member> _memberNamed(AppDatabase db, String name) async =>
    (db.select(db.members)..where((m) => m.fullName.equals(name))).getSingle();

Future<Member?> _memberOrNull(AppDatabase db, String name) async =>
    (db.select(db.members)..where((m) => m.fullName.equals(name)))
        .getSingleOrNull();

Future<int?> _planOf(AppDatabase db, String memberName) async {
  final member = await _memberNamed(db, memberName);
  return (await openMembershipFor(db, member.id))?.planId;
}
