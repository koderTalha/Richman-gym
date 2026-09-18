import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// Reading a member's plan history out of what they paid each month.
///
/// The ledger has one "Plan" column, and it names the plan the member is on
/// *now* — but the monthly figures show they have not always been on it. On the
/// owner's real sheet fourteen of twenty-three members change fee part way
/// through the year: H. Abubakar Bhatti pays 4,000 from January and 10,000 from
/// June, which is Basic until June and Platinum after it.
///
/// Recorded as one Platinum enrolment, his January would read as a Platinum
/// month that somehow cost 4,000. Split at the change, each month sits under
/// the plan that was actually in force.
///
/// The fee is only evidence, so it is used only where it is unambiguous: a
/// figure matching exactly one plan. Anything else leaves the run unbroken
/// rather than moving somebody onto a plan the sheet never mentioned.
const _student = MembershipPlan(
    id: 1, name: 'Student Package', durationMonths: 1, priceMinor: 250000,
    isActive: true);
const _basic = MembershipPlan(
    id: 2, name: 'Basic', durationMonths: 1, priceMinor: 400000,
    isActive: true);
const _platinum = MembershipPlan(
    id: 3, name: 'Platinum', durationMonths: 1, priceMinor: 1000000,
    isActive: true);

const _plans = [_student, _basic, _platinum];

List<List<String?>> _sheet(List<String> months, {String plan = 'Platinum'}) => [
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

ParsedMemberRow _row(List<String> months,
    {String plan = 'Platinum', List<MembershipPlan> plans = _plans}) {
  final sheet = _sheet(months, plan: plan);
  final detected = detectMapping(sheet)!;
  return parseLedger(
    rows: sheet,
    headerRow: detected.headerRow,
    mapping: detected.mapping,
    year: 2026,
    plans: plans,
  ).rows.single;
}

void main() {
  group('a member who paid the same all year', () {
    test('has a single stretch', () {
      final row = _row([
        '10000', '10000', '10000', '10000', '10000', '10000',
        '10000', '10000', '10000', '-', '-', '-',
      ]);

      expect(row.planSegments, hasLength(1));
      expect(row.planSegments.single.startMonth, 1);
    });

    test('takes the plan the sheet names for it', () {
      final row = _row([
        '10000', '10000', '10000', '10000', '10000', '10000',
        '10000', '10000', '10000', '-', '-', '-',
      ]);

      expect(row.planSegments.single.planId, isNull,
          reason: 'null means the plan named in the "Plan" column');
    });
  });

  group('a member whose fee changed', () {
    // Abubakar: Basic until June, Platinum from June.
    final abubakar = [
      '4000', '4000', '4000', '4000', '4000', '10000',
      '10000', '10000', '10000', '-', '-', '-',
    ];

    test('is split at the month the fee moved', () {
      expect(_row(abubakar).planSegments.map((s) => s.startMonth), [1, 6]);
    });

    test('puts the earlier months on the plan matching what they cost', () {
      expect(_row(abubakar).planSegments.first.planId, _basic.id);
    });

    test('leaves the last stretch on the plan the sheet names', () {
      expect(_row(abubakar).planSegments.last.planId, isNull);
    });

    test('handles a move to a cheaper plan just the same', () {
      // Sibghatullah Rauf: Platinum, then Basic from March.
      final row = _row([
        '10000', '10000', '4000', '4000', '4000', '4000',
        '4000', '0', '0', '-', '-', '-',
      ], plan: 'Basic');

      expect(row.planSegments.map((s) => s.startMonth), [1, 3]);
      expect(row.planSegments.first.planId, _platinum.id);
    });

    test('splits more than once where the sheet does', () {
      final row = _row([
        '2500', '2500', '4000', '4000', '10000', '10000',
        '10000', '-', '-', '-', '-', '-',
      ]);

      expect(row.planSegments.map((s) => s.startMonth), [1, 3, 5]);
      expect(row.planSegments.map((s) => s.planId),
          [_student.id, _basic.id, null]);
    });

    test('ignores unpaid months between two stretches', () {
      // Bilal: Basic in January, away, Student Package from July.
      final row = _row([
        '4000', '0', '0', '0', '0', '0',
        '2500', '0', '0', '-', '-', '-',
      ], plan: 'Student Package');

      expect(row.planSegments.map((s) => s.startMonth), [1, 7]);
      expect(row.planSegments.first.planId, _basic.id);
    });
  });

  group('a fee the plans cannot explain', () {
    test('does not split the run', () {
      // 7,000 is nobody's price — a one-off, or a member on their own fee.
      final row = _row([
        '4000', '4000', '7000', '7000', '4000', '4000',
        '4000', '-', '-', '-', '-', '-',
      ], plan: 'Basic');

      expect(row.planSegments, hasLength(1));
    });

    test('nor does a month whose amount the sheet never showed', () {
      // "###" text: paid, figure lost. It cannot name a plan, so it carries on
      // with whichever one the member was already on.
      final row = _row([
        '4000', '4000', '###', '###', '4000', '4000',
        '4000', '-', '-', '-', '-', '-',
      ], plan: 'Basic');

      expect(row.planSegments, hasLength(1));
    });

    test('nor does a price two plans share', () {
      const twin = MembershipPlan(
          id: 4, name: 'Morning Basic', durationMonths: 1, priceMinor: 400000,
          isActive: true);

      final row = _row([
        '10000', '10000', '4000', '4000', '4000', '-',
        '-', '-', '-', '-', '-', '-',
      ], plan: 'Basic', plans: [..._plans, twin]);

      expect(row.planSegments, hasLength(1),
          reason: '4,000 is both Basic and Morning Basic, so it is no evidence '
              'of which one the member moved to');
    });
  });

  group('a member with nothing paid', () {
    test('has no stretches at all', () {
      final row = _row([
        '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-',
      ]);

      expect(row.planSegments, isEmpty);
    });
  });
}
