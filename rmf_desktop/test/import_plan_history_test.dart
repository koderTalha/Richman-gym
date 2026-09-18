import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// Writing a member's plan history, not just their plan.
///
/// H. Abubakar Bhatti pays 4,000 a month from January and 10,000 from June. The
/// sheet's "Plan" column says Platinum, because that is what he is on now — but
/// recording the whole year against it would leave five Platinum months that
/// somehow cost 4,000 each. He was on Basic until June. The import writes both
/// enrolments and files each month under the one that was in force.
void main() {
  late AppDatabase db;
  late int adminId;
  late int basicId;
  late int platinumId;

  final importedOn = DateTime.utc(2026, 9, 18);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;

    Future<int> plan(String name, int priceMinor) =>
        db.into(db.membershipPlans).insert(
              MembershipPlansCompanion.insert(
                name: name,
                durationMonths: 1,
                priceMinor: priceMinor,
              ),
            );

    basicId = await plan('Basic', 400000);
    platinumId = await plan('Platinum', 1000000);
  });

  tearDown(() async => db.close());

  List<List<String?>> sheet(List<String> months, {String plan = 'Platinum'}) =>
      [
        ['RICH MAN FITNESS GYM', null, null, null, null, null, null, null],
        [
          'Enroll.', 'Name', 'Contact Detail', 'Fee Submit',
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
          'Status', 'Plan',
        ],
        [
          '1', 'H. Abubakar Bhatti', '0322-6363633', '03-Sep-2026',
          ...months,
          'Online Payment', plan,
        ],
      ];

  Future<void> import(List<List<String?>> rows) async {
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
      now: importedOn,
    );
  }

  /// Basic January to May, Platinum from June.
  const movedUp = [
    '4000', '4000', '4000', '4000', '4000', '10000',
    '10000', '10000', '10000', '-', '-', '-',
  ];

  Future<List<Membership>> enrolments() async {
    final member = await db.select(db.members).getSingle();
    return (db.select(db.memberships)
          ..where((m) => m.memberId.equals(member.id))
          ..orderBy([(m) => OrderingTerm(expression: m.startDate)]))
        .get();
  }

  group('a member who moved plan', () {
    test('gets one enrolment per plan they were on', () async {
      await import(sheet(movedUp));

      expect(await enrolments(), hasLength(2));
    });

    test('is on the plan the fee matched for the earlier months', () async {
      await import(sheet(movedUp));

      final first = (await enrolments()).first;
      expect(first.planId, basicId);
      expect(first.startDate.toUtc(), DateTime.utc(2026, 1, 1));
    });

    test('has that enrolment closed off where the fee moved', () async {
      await import(sheet(movedUp));

      expect((await enrolments()).first.endDate?.toUtc(),
          DateTime.utc(2026, 6, 1));
    });

    test('is on the plan the sheet names for the months since', () async {
      await import(sheet(movedUp));

      final last = (await enrolments()).last;
      expect(last.planId, platinumId);
      expect(last.startDate.toUtc(), DateTime.utc(2026, 6, 1));
      expect(last.endDate, isNull, reason: 'the current enrolment stays open');
    });

    test('is billed on the day they last paid, on the open enrolment',
        () async {
      await import(sheet(movedUp));

      expect((await enrolments()).last.billingAnchorDay, 3);
    });

    test('has each month filed under the enrolment in force then', () async {
      await import(sheet(movedUp));

      final all = await enrolments();
      final periods = await db.select(db.membershipPeriods).get();

      Set<int> monthsOf(int membershipId) => periods
          .where((p) => p.membershipId == membershipId)
          .where((p) => p.expectedAmountMinor > 0)
          .map((p) => p.periodStart.toUtc().month)
          .toSet();

      expect(monthsOf(all.first.id), {1, 2, 3, 4, 5});
      expect(monthsOf(all.last.id), {6, 7, 8, 9});
    });

    test('keeps every month at the fee the sheet recorded', () async {
      await import(sheet(movedUp));

      final periods = await db.select(db.membershipPeriods).get()
        ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
      final paid = periods.where((p) => p.expectedAmountMinor > 0).toList();

      expect(paid.map((p) => p.expectedAmountMinor),
          [400000, 400000, 400000, 400000, 400000,
           1000000, 1000000, 1000000, 1000000]);
    });

    test('still owes nothing when the import finishes', () async {
      await import(sheet(movedUp));

      final member = await db.select(db.members).getSingle();
      final open = await openMembershipFor(db, member.id);
      expect(open!.planId, platinumId,
          reason: 'the open enrolment is the one billing continues on');
    });
  });

  group('a member who never moved', () {
    test('gets a single enrolment, as before', () async {
      await import(sheet([
        '10000', '10000', '10000', '10000', '10000', '10000',
        '10000', '10000', '10000', '-', '-', '-',
      ]));

      final all = await enrolments();
      expect(all, hasLength(1));
      expect(all.single.planId, platinumId);
      expect(all.single.endDate, isNull);
    });
  });
}
