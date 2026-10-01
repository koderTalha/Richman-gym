import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';
import 'package:rich_man_fitness/services/spreadsheet_reader.dart';

/// Ledger cells the importer used to misread, every one of them into money.
///
/// The `excel` package hands a formula back as its text and drops the value
/// Excel saved beside it, so "=1500+1000" — showing 2,500 — imported as
/// Rs 15,001,000. It also takes Excel's own Rupee format for a date. And the
/// month parser kept the dot of "Rs." as a decimal point, so "Rs. 3,000" was
/// thirty paisa.
void main() {
  ParsedLedger parseRows(List<List<String?>> rows, {int year = 2026}) {
    final detected = detectMapping(rows)!;
    return parseLedger(
        rows: rows,
        headerRow: detected.headerRow,
        mapping: detected.mapping,
        year: year);
  }

  ParsedLedger parseWorkbook(Uint8List bytes) =>
      parseRows(readSpreadsheet(
              SpreadsheetSource(fileName: 'ledger.xlsx', bytes: bytes))
          .values
          .first);

  group('a month cell with a currency prefix', () {
    test('"Rs. 3,000" reads as Rs 3,000', () {
      expect(classifyMonthCell('Rs. 3,000').amountMinor, 300000);
    });
    test('"Rs.2500" reads as Rs 2,500', () {
      expect(classifyMonthCell('Rs.2500').amountMinor, 250000);
    });
    test('"PKR 3,000/-" reads as Rs 3,000', () {
      expect(classifyMonthCell('PKR 3,000/-').amountMinor, 300000);
    });
    test('lakh grouping reads as the one number it is', () {
      expect(classifyMonthCell('1,50,000').amountMinor, 15000000);
    });
    test('a figure with paisa keeps them', () {
      expect(classifyMonthCell('Rs. 2,500.50').amountMinor, 250050);
    });
  });

  group('a month cell holding more than one figure', () {
    for (final text in ['2500+500', '3000 (2 months)', '2500,3000', '05/07']) {
      test('"$text" is refused rather than run together', () {
        final cell = classifyMonthCell(text);
        expect([cell.kind, cell.amountMinor], [MonthCell.unreadable, null]);
      });
    }

    test('holds the row back with the cell named, for the owner to fix', () {
      final ledger = parseRows([
        ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb', 'Mar', 'Apr',
         'May', 'Jun'],
        ['7', 'Ali Khan', '0300-0000001', '3000', '2500+500', '-', '-',
         '-', '-'],
      ]);

      expect(ledger.valid, isEmpty);
      expect(ledger.invalid.single.problems.single,
          allOf(contains('Feb'), contains('2500+500')));
    });
  });

  group('a workbook cell holding a formula', () {
    /// Builds a real .xlsx whose cells are written the way Excel writes a
    /// formula: the formula in <f>, its last computed value in <v>.
    Uint8List workbookWithFormulas() {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      sheet.appendRow([
        TextCellValue('Enroll.'), TextCellValue('Name'),
        TextCellValue('Contact Detail'),
        TextCellValue('Jan'), TextCellValue('Feb'), TextCellValue('Mar'),
        TextCellValue('Apr'), TextCellValue('May'), TextCellValue('Jun'),
      ]);
      sheet.appendRow([
        IntCellValue(41), TextCellValue('Formula Member'),
        TextCellValue('0300-0000201'),
        IntCellValue(2500), IntCellValue(2501), IntCellValue(2502),
        IntCellValue(2503), IntCellValue(2504), IntCellValue(2505),
      ]);
      final bytes = excel.encode()!;

      // Swap three plain numbers for formula cells carrying the same cached
      // value, exactly what Excel saves for "=A2+1", "=1500+1000" and "=D2".
      final archive = ZipDecoder().decodeBytes(bytes);
      final out = Archive();
      for (final file in archive.files) {
        var content = file.content as List<int>;
        if (file.name.startsWith('xl/worksheets/sheet')) {
          var xml = utf8.decode(content);
          xml = xml
              .replaceFirst('<v>41</v>', '<f>A1+40</f><v>41</v>')
              .replaceFirst('<v>2500</v>', '<f>1500+1000</f><v>2500</v>')
              .replaceFirst('<v>2501</v>', '<f>D2</f><v>2500</v>');
          content = utf8.encode(xml);
        }
        out.addFile(ArchiveFile(file.name, content.length, content));
      }
      return Uint8List.fromList(ZipEncoder().encode(out)!);
    }

    test('reads the value Excel shows, not the formula text', () {
      final row = parseWorkbook(workbookWithFormulas()).rows.single;

      // Enroll. =A1+40 shows 41; Jan =1500+1000 shows 2,500; Feb =D2 shows 2,500.
      expect(
        [
          row.memberCode,
          row.payments[0].amountMinor,
          row.payments[1].amountMinor,
        ],
        [41, 250000, 250000],
      );
    });

    test('a formula the file saved no value for holds the row back', () {
      // What a script or converter writes: the formula, never calculated.
      final ledger = parseWorkbook(_workbook(row2: [
        _number('A2', 9),
        _text('B2', 'Uncalculated Member'),
        _text('C2', '0300-0000202'),
        '<c r="D2"><f>1500+1000</f></c>',
        _number('E2', 2500),
      ]));

      expect(ledger.valid, isEmpty);
      expect(ledger.invalid.single.problems.single,
          allOf(contains('Jan'), contains('formula')));
    });

    test('formula text in a hand-made CSV is refused, not read for digits', () {
      final cell = classifyMonthCell('=1500+1000');
      expect([cell.kind, cell.amountMinor], [MonthCell.unreadable, null]);
    });

    test('a shared formula — blank formula text in the file — still reads '
        'the saved value', () {
      final row = parseWorkbook(_workbook(row2: [
        _number('A2', 10),
        _text('B2', 'Shared Formula'),
        _text('C2', '0300-0000203'),
        '<c r="D2"><f t="shared" ref="D2:E2" si="0">1500+1000</f>'
            '<v>2500</v></c>',
        '<c r="E2"><f t="shared" si="0"/><v>3000</v></c>',
      ])).rows.single;

      expect(row.payments.map((p) => p.amountMinor), [250000, 300000]);
    });

    test('a formula that gives text reads as that text', () {
      final row = parseWorkbook(_workbook(row2: [
        _number('A2', 11),
        '<c r="B2" t="str"><f>"Zain "&amp;"Ali"</f><v>Zain Ali</v></c>',
        _text('C2', '0300-0000204'),
        _number('D2', 3000),
      ])).rows.single;

      expect(row.name, 'Zain Ali');
    });
  });

  group('a cell formatted as Rupees', () {
    // The `excel` package calls any custom format with a "d", "m" or "s" in
    // it a date — and Excel's Rupee format has an "s" inside its brackets.
    test('is read as the number in it, not as a date in 1906', () {
      final row = parseWorkbook(_workbook(
        numFmts: '<numFmt numFmtId="164" formatCode="[\$Rs-420]#,##0"/>',
        row2: [
          _number('A2', 12),
          _text('B2', 'Rupee Format'),
          _text('C2', '0300-0000205'),
          '<c r="D2" s="1"><v>2500</v></c>',
        ],
      )).rows.single;

      expect(row.payments.single.amountMinor, 250000);
    });

    test('nor is a figure Excel shows in red', () {
      final row = parseWorkbook(_workbook(
        numFmts: '<numFmt numFmtId="164" formatCode="[Red]#,##0"/>',
        row2: [
          _number('A2', 15),
          _text('B2', 'Red Format'),
          _text('C2', '0300-0000208'),
          '<c r="D2" s="1"><v>2500</v></c>',
        ],
      )).rows.single;

      expect(row.payments.single.amountMinor, 250000);
    });

    test('a real date format is still a date', () {
      final row = parseWorkbook(_workbook(
        numFmts: '<numFmt numFmtId="164" formatCode="dd\\-mmm\\-yy"/>',
        feeSubmit: true,
        row2: [
          _number('A2', 13),
          _text('B2', 'Dated Member'),
          _text('C2', '0300-0000206'),
          // 46206 is 3 July 2026.
          '<c r="D2" s="1"><v>46206</v></c>',
          _number('E2', 3000),
        ],
      )).rows.single;

      expect(row.feeSubmit, DateTime.utc(2026, 7, 3));
    });

    test('a date worked out by a formula reads as that date', () {
      final row = parseWorkbook(_workbook(
        numFmts: '<numFmt numFmtId="164" formatCode="dd\\-mmm\\-yy"/>',
        feeSubmit: true,
        row2: [
          _number('A2', 14),
          _text('B2', 'Formula Date'),
          _text('C2', '0300-0000207'),
          '<c r="D2" s="1"><f>DATE(2026,7,3)</f><v>46206</v></c>',
          _number('E2', 3000),
        ],
      )).rows.single;

      expect(row.feeSubmit, DateTime.utc(2026, 7, 3));
    });
  });

  group('the Enroll. column', () {
    List<String?> header() =>
        ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb', 'Mar', 'Apr',
         'May', 'Jun'];
    List<String?> row(String code) =>
        [code, 'Ali Khan', '0300-0000001', '3000', '-', '-', '-', '-', '-'];

    test('a code stored as a decimal is the whole number it shows', () {
      expect(parseRows([header(), row('41.0')]).rows.single.memberCode, 41);
    });

    test('typed text gives up its one number', () {
      expect(parseRows([header(), row('RMF-041')]).rows.single.memberCode, 41);
    });

    test('two numbers are not run together into somebody else\'s code', () {
      final parsed = parseRows([header(), row('12/13')]).rows.single;
      expect(parsed.memberCode, isNull);
      expect(parsed.warnings, contains(contains('12/13')));
    });
  });
}

String _text(String ref, String text) =>
    '<c r="$ref" t="inlineStr"><is><t>$text</t></is></c>';

String _number(String ref, num value) => '<c r="$ref"><v>$value</v></c>';

/// A hand-built .xlsx, for the cells `Excel.encode` cannot write: shared
/// formulas, formulas with no saved value, custom number formats. Row 1 is
/// the ledger header; [row2] are the raw `<c>` elements of the one member.
///
/// Style 1 points at numFmt 164 when [numFmts] defines one.
Uint8List _workbook({
  required List<String> row2,
  String numFmts = '',
  bool feeSubmit = false,
}) {
  final headers = feeSubmit
      ? ['Enroll.', 'Name', 'Contact Detail', 'Fee Submit', 'Jan', 'Feb',
         'Mar', 'Apr', 'May', 'Jun']
      : ['Enroll.', 'Name', 'Contact Detail', 'Jan', 'Feb', 'Mar', 'Apr',
         'May', 'Jun'];
  final headerCells = [
    for (var i = 0; i < headers.length; i++)
      _text('${String.fromCharCode(65 + i)}1', headers[i]),
  ].join();

  final files = {
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Fee Detail 2026" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '${numFmts.isEmpty ? '' : '<numFmts count="1">$numFmts</numFmts>'}'
        '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="${numFmts.isEmpty ? 0 : 164}" fontId="0" fillId="0" '
        'borderId="0" xfId="0" applyNumberFormat="1"/>'
        '</cellXfs>'
        '</styleSheet>',
    'xl/worksheets/sheet1.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>'
        '<row r="1">$headerCells</row>'
        '<row r="2">${row2.join()}</row>'
        '</sheetData>'
        '</worksheet>',
  };

  final archive = Archive();
  files.forEach((name, xml) {
    final content = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, content.length, content));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
