import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// The "Fee Submit" column, which the importer used to map and then throw away.
///
/// It is the date the member last handed money over, and its *day* is the day
/// of the month they are billed on: a member who paid on the 3rd falls due on
/// the 3rd of every month after. That day is the whole basis of the billing
/// anchor each imported member is put on, so it has to survive both routes into
/// the parser — a real workbook, where the `excel` package hands back an ISO
/// timestamp, and a CSV, where it arrives as the owner typed it.
List<List<String?>> _sheet(String? feeSubmit) => [
      ['RICH MAN FITNESS GYM', null, null, null, null, null, null, null],
      [
        'Enroll.', 'Name', 'Contact Detail', 'Fee Submit',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        'Status', 'Plan',
      ],
      [
        '1', 'H. Abubakar Bhatti', '0322-6363633', feeSubmit,
        '###', '###', '###', '###', '###', '###',
        '###', '###', '###', '-', '-', '-',
        'Online Payment', 'Platinum',
      ],
    ];

ParsedMemberRow _row(String? feeSubmit) {
  final sheet = _sheet(feeSubmit);
  final detected = detectMapping(sheet)!;
  return parseLedger(
    rows: sheet,
    headerRow: detected.headerRow,
    mapping: detected.mapping,
    year: 2026,
  ).rows.single;
}

void main() {
  group('parseLedgerDate', () {
    test('reads the ISO timestamp a workbook hands back', () {
      expect(
        parseLedgerDate('2026-09-03T00:00:00.000Z'),
        DateTime.utc(2026, 9, 3),
      );
    });

    test('reads the day-month-year the owner types', () {
      expect(parseLedgerDate('03-Jul-2026'), DateTime.utc(2026, 7, 3));
    });

    test('reads a two-digit year as this century', () {
      expect(parseLedgerDate('03-Jul-26'), DateTime.utc(2026, 7, 3));
    });

    test('reads a slash-separated date', () {
      expect(parseLedgerDate('23/09/2026'), DateTime.utc(2026, 9, 23));
    });

    test('treats the sheet\'s blank markers as no date', () {
      expect(parseLedgerDate('-'), isNull);
      expect(parseLedgerDate(''), isNull);
      expect(parseLedgerDate(null), isNull);
    });

    test('refuses anything it cannot read rather than guessing', () {
      expect(parseLedgerDate('sometime in July'), isNull);
      expect(parseLedgerDate('45-Xyz-26'), isNull);
    });
  });

  group('a parsed row', () {
    test('carries the fee submit date', () {
      expect(_row('2026-09-03T00:00:00.000Z').feeSubmit,
          DateTime.utc(2026, 9, 3));
    });

    test('bills on the day of the month the fee was submitted', () {
      expect(_row('2026-09-03T00:00:00.000Z').anchorDay, 3);
      expect(_row('23/09/2026').anchorDay, 23);
    });

    test('has no anchor day when the sheet names no date', () {
      expect(_row('-').feeSubmit, isNull);
      expect(_row('-').anchorDay, isNull);
    });

    test('is still importable without one', () {
      expect(_row('-').isValid, isTrue);
    });
  });
}
