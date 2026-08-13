import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';

/// Mirrors the owner's real "RICH MAN FITNESS GYM" sheet exactly:
/// a merged title row, then headers, then member rows where the phone column is
/// frequently "-" or blank and every Jan–Dec cell is "-".
List<List<String?>> get _realSheet => [
      ['RICH MAN FITNESS GYM', null, null, null, null, null, null, null, null],
      [
        'Enroll.', 'Name', 'Contact Detail', 'Fee Submit',
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        'Status',
      ],
      [
        '1', 'Ahmed Test One', '0300-0000027', '03-Jul-26',
        '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-',
        'Online Payment',
      ],
      // Phone recorded as a dash — a real member, just no number on file.
      [
        '2', 'No Phone Member', '-', '04-Jul-26',
        '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-',
        'Cash Payment',
      ],
      // Phone cell entirely empty.
      [
        '11', 'Blank Phone Member', null, '09-Jul-26',
        '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-',
        'Online Payment',
      ],
      // Enrolment numbers are not sequential or ordered in the real sheet.
      [
        '8', 'Member Two', '0300-0000002', '10-Jul-26',
        '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-', '-',
        'Cash Payment',
      ],
      // Trailing blank rows, of which the sheet has many.
      [null, null, null, null, null, null, null, null, null],
    ];

/// A sheet that does carry amounts, as the older year tabs do.
List<List<String?>> get _sheetWithAmounts => [
      ['RICH MAN FITNESS GYM', null, null, null, null, null, null],
      [
        'Enroll.', 'Name', 'Contact Detail', 'Fee Submit',
        'Jan', 'Feb', 'Mar', 'Status',
      ],
      [
        '2', 'Member One', '0300-0000001', '10-Jul-25',
        '3000', '3,000', 'NILL', 'Cash Payment',
      ],
    ];

ParsedLedger _parse(List<List<String?>> sheet, {int year = 2026}) {
  final detected = detectMapping(sheet)!;
  return parseLedger(
    rows: sheet,
    headerRow: detected.headerRow,
    mapping: detected.mapping,
    year: year,
  );
}

void main() {
  group('detectMapping on the real sheet', () {
    test('finds the header row beneath the merged title', () {
      expect(detectMapping(_realSheet)!.headerRow, 1);
    });

    test('maps the real column headers', () {
      final mapping = detectMapping(_realSheet)!.mapping;
      expect(mapping.memberCode, 0);
      expect(mapping.name, 1);
      expect(mapping.phone, 2);
      expect(mapping.feeSubmit, 3);
      expect(mapping.status, 16);
    });

    test('maps all twelve month columns', () {
      final mapping = detectMapping(_realSheet)!.mapping;
      expect(mapping.monthColumns.length, 12);
      expect(mapping.monthColumns[1], 4);
      expect(mapping.monthColumns[12], 15);
    });

    test('copes with the sheet having no Ref No or Extra columns', () {
      final mapping = detectMapping(_realSheet)!.mapping;
      expect(mapping.reference, isNull);
      expect(mapping.extra, isNull);
    });
  });

  group('members without a phone number', () {
    test('a dash in Contact Detail still imports the member', () {
      final row = _parse(_realSheet).rows.firstWhere((r) => r.name == 'No Phone Member');
      expect(row.isValid, isTrue, reason: 'must not be skipped');
      expect(row.hasPhone, isFalse);
      expect(row.warnings.single, contains('No phone number'));
    });

    test('an empty Contact Detail still imports the member', () {
      final row =
          _parse(_realSheet).rows.firstWhere((r) => r.name == 'Blank Phone Member');
      expect(row.isValid, isTrue);
      expect(row.hasPhone, isFalse);
    });

    test('every member on the real sheet is importable', () {
      final ledger = _parse(_realSheet);
      expect(ledger.valid.length, 4);
      expect(ledger.invalid, isEmpty);
    });

    test('counts how many lack a phone, for the preview', () {
      expect(_parse(_realSheet).withoutPhone, 2);
      expect(_parse(_realSheet).withWarnings.length, 2);
    });

    test('a member with a phone has it normalized to E.164', () {
      final row = _parse(_realSheet)
          .rows
          .firstWhere((r) => r.name == 'Ahmed Test One');
      expect(row.normalizedPhone, '+923000000027');
      expect(row.warnings, isEmpty);
    });
  });

  group('rows that genuinely cannot be imported', () {
    test('only a missing name blocks a row', () {
      final sheet = [
        ..._realSheet,
        ['99', '', '0300-0000028', '01-Jul-26', '-', 'Cash Payment'],
      ];
      final row = _parse(sheet).rows.firstWhere((r) => r.memberCode == 99);
      expect(row.isValid, isFalse);
      expect(row.problems.single, 'Missing name');
    });
  });

  group('month columns', () {
    test('a sheet of dashes produces no payments', () {
      final ledger = _parse(_realSheet);
      expect(ledger.totalPayments, 0);
      expect(ledger.rows.every((r) => r.payments.isEmpty), isTrue);
    });

    test('amounts are pivoted into one payment per month', () {
      final row = _parse(_sheetWithAmounts, year: 2025).rows.single;
      expect(row.payments.map((p) => p.month), [1, 2]);
      expect(row.payments.map((p) => p.amountMinor), [300000, 300000]);
    });

    test('NILL and 0 are treated as no payment', () {
      final row = _parse(_sheetWithAmounts, year: 2025).rows.single;
      expect(row.payments.any((p) => p.month == 3), isFalse);
    });
  });

  group('### cells (Excel column too narrow)', () {
    /// The owner's sheet shows ### for a paid month and - for an unpaid one.
    List<List<String?>> sheet() => [
          ['RICH MAN FITNESS GYM', null, null, null, null, null],
          ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb', 'Mar'],
          ['1', 'Ahmed Test One', '0300-0000027', '##', '###', '#####'],
          ['2', 'No Phone Member', '-', '-', '-', '-'],
          ['3', 'Rejoining Member', '0300-0000029', '3000', '###', '-'],
        ];

    test('### counts as a paid month, not an unpaid one', () {
      final row = _parse(sheet()).rows.first;
      expect(row.payments.map((p) => p.month), [1, 2, 3],
          reason: 'losing these would erase real payment history');
    });

    test('any run of hashes counts, whatever the column width', () {
      final row = _parse(sheet()).rows.first;
      expect(row.payments.length, 3);
      expect(row.payments.every((p) => !p.hasAmount), isTrue);
    });

    test('a dash is still unpaid', () {
      final row = _parse(sheet()).rows.firstWhere((r) => r.name == 'No Phone Member');
      expect(row.payments, isEmpty);
    });

    test('a readable figure keeps its amount', () {
      final row = _parse(sheet()).rows.firstWhere((r) => r.name == 'Rejoining Member');
      final january = row.payments.firstWhere((p) => p.month == 1);

      expect(january.hasAmount, isTrue);
      expect(january.amountMinor, 300000);
    });

    test('a mixed row keeps the figure and flags the ### month', () {
      final row = _parse(sheet()).rows.firstWhere((r) => r.name == 'Rejoining Member');
      final february = row.payments.firstWhere((p) => p.month == 2);

      expect(february.hasAmount, isFalse,
          reason: 'the amount comes from the plan fee at import time');
    });

    test('the ledger reports how many months need the plan fee', () {
      // Three from the first member, one from the third.
      expect(_parse(sheet()).paymentsUsingPlanFee, 4);
    });

    test('the total only counts amounts the sheet actually showed', () {
      final row = _parse(sheet()).rows.firstWhere((r) => r.name == 'Rejoining Member');
      expect(row.totalMinor, 300000);
    });
  });

  group('sheet housekeeping', () {
    test('skips entirely blank spacer rows', () {
      expect(_parse(_realSheet).rows.length, 4);
    });

    test('reports the row number as seen in Excel', () {
      final row = _parse(_realSheet)
          .rows
          .firstWhere((r) => r.name == 'Ahmed Test One');
      expect(row.sourceRow, 3);
    });

    test('keeps the ledger enrolment number even when out of order', () {
      final codes = _parse(_realSheet).rows.map((r) => r.memberCode);
      expect(codes, [1, 2, 11, 8]);
    });
  });

  group('yearFromSheetName', () {
    test('reads a year when the tab name carries one', () {
      expect(yearFromSheetName('Fee Detail 2026'), 2026);
      expect(yearFromSheetName('Members 2025'), 2025);
    });

    test('returns null when it does not', () {
      expect(yearFromSheetName('RICH MAN FITNESS GYM'), isNull);
    });
  });

  group('isBlankCell', () {
    test('treats the placeholders the real sheet uses as empty', () {
      for (final marker in ['', ' ', '-', '--', 'NILL', 'nill', '0', 'N/A']) {
        expect(isBlankCell(marker), isTrue, reason: '"$marker" should be blank');
      }
    });

    test('treats a real amount as present', () {
      expect(isBlankCell('3000'), isFalse);
    });
  });
}
