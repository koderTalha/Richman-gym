import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';
import 'package:rich_man_fitness/services/spreadsheet_reader.dart';

/// Reading the file the owner picks.
///
/// The picker used to offer .xlsx, .xls and .csv, and the parser could only
/// read the first — so two of the three ended in an error that read like the
/// ledger was corrupt when nothing was wrong with it.
void main() {
  SpreadsheetSource source(String name, String contents) => SpreadsheetSource(
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(contents)),
      );

  group('csv', () {
    test('is offered and can actually be read', () {
      expect(readableExtensions, contains('csv'));

      final sheets = readSpreadsheet(source(
        'ledger.csv',
        'Enroll.,Name,Contact Detail,Jan,Feb\n'
            '1,Ali Khan,0300-0000001,3000,3000\n',
      ));

      final rows = sheets.values.single;
      expect(rows, hasLength(2));
      expect(rows.last, ['1', 'Ali Khan', '0300-0000001', '3000', '3000']);
    });

    test('feeds the ledger parser the same as a workbook would', () {
      final sheets = readSpreadsheet(source(
        'Fee Detail 2026.csv',
        'Enroll.,Name,Contact Detail,Jan,Feb\n'
            '1,Ali Khan,0300-0000001,3000,-\n',
      ));

      final rows = sheets.values.single;
      final detected = detectMapping(rows)!;
      final ledger = parseLedger(
        rows: rows,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: 2026,
      );

      expect(ledger.valid.single.name, 'Ali Khan');
      expect(ledger.valid.single.payments.single.month, 1);
    });
  });

  group('the csv reader', () {
    test('keeps a comma inside a quoted field', () {
      final rows = parseCsv('Name,Address\n"Khan, Ali","12 Main Road, Lahore"');

      expect(rows.last, ['Khan, Ali', '12 Main Road, Lahore'],
          reason: 'splitting on every comma shifts every column after an '
              'address, silently pairing names with the wrong amounts');
    });

    test('handles a doubled quote inside a quoted field', () {
      expect(parseCsv('Name\n"Ali ""Bulldozer"" Khan"').last,
          ['Ali "Bulldozer" Khan']);
    });

    test('handles a newline inside a quoted field', () {
      final rows = parseCsv('Name,Address\n"Ali","12 Main Road\nLahore"');

      expect(rows, hasLength(2));
      expect(rows.last.last, '12 Main Road\nLahore');
    });

    test('reads CRLF line endings, which is what Excel writes', () {
      final rows = parseCsv('Name,Jan\r\nAli Khan,3000\r\n');

      expect(rows, hasLength(2));
      expect(rows.last, ['Ali Khan', '3000']);
    });

    test('reports an empty cell as null and an empty quoted cell as ""', () {
      expect(parseCsv('a,,""').single, ['a', null, '']);
    });

    test('ignores a trailing newline rather than inventing a row', () {
      expect(parseCsv('Name\nAli Khan\n'), hasLength(2));
    });
  });

  group('running on a background isolate', () {
    // The importer hands this to `compute`, so everything crossing the
    // boundary has to survive the trip — including the failure.
    test('returns the rows', () async {
      final sheets = await compute(
        readSpreadsheet,
        source('ledger.csv', 'Name,Jan\nAli Khan,3000\n'),
      );

      expect(sheets.values.single.last, ['Ali Khan', '3000']);
    });

    test('propagates a readable failure rather than a raw isolate error',
        () async {
      await expectLater(
        compute(readSpreadsheet, source('ledger.xls', 'anything')),
        throwsA(isA<UnreadableSpreadsheet>()),
      );
    });
  });

  group('formats that cannot be read', () {
    test('.xls is not offered in the picker', () {
      expect(readableExtensions, isNot(contains('xls')));
    });

    test('.xls says what to do about it', () {
      expect(
        () => readSpreadsheet(source('ledger.xls', 'anything')),
        throwsA(isA<UnreadableSpreadsheet>().having(
          (e) => e.message,
          'message',
          allOf(contains('Save As'), contains('.xlsx')),
        )),
      );
    });

    test('an unreadable xlsx explains itself in the owner\'s words', () {
      expect(
        () => readSpreadsheet(source('ledger.xlsx', 'not a zip archive')),
        throwsA(isA<UnreadableSpreadsheet>()),
      );
    });
  });
}
