import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' show Excel;
import 'package:path/path.dart' as p;

/// Reads a ledger file into plain rows of text, one entry per sheet.
///
/// Deliberately returns nothing but `String?` in nested lists: the result
/// crosses an isolate boundary, and primitives are the only thing that can make
/// that trip cheaply. It also means the parsing in `ledger_import.dart` never
/// has to know which file format the rows came out of.

/// Thrown when a file cannot be read, carrying wording aimed at the gym owner
/// rather than at a developer.
class UnreadableSpreadsheet implements Exception {
  const UnreadableSpreadsheet(this.message);
  final String message;

  @override
  String toString() => message;
}

class SpreadsheetSource {
  const SpreadsheetSource({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

/// The formats the importer can actually read.
///
/// `.xls` is deliberately absent. The old binary Excel format needs a
/// different parser altogether, and offering it in the file picker meant the
/// owner chose one and got an error that read like their file was corrupt.
const readableExtensions = ['xlsx', 'csv'];

/// Top-level so it can be handed to `compute`.
///
/// Decoding a workbook is pure computation over a few megabytes and used to
/// happen on the interface thread, freezing the window for the length of a
/// large ledger. It has no reason to be there.
Map<String, List<List<String?>>> readSpreadsheet(SpreadsheetSource source) {
  final extension =
      p.extension(source.fileName).toLowerCase().replaceFirst('.', '');

  if (extension == 'csv') {
    return {'Sheet1': parseCsv(utf8.decode(source.bytes, allowMalformed: true))};
  }

  if (extension == 'xls') {
    throw const UnreadableSpreadsheet(
      'This is an old-style .xls file, which cannot be read directly. '
      'Open it in Excel and use File → Save As to save it as .xlsx or .csv, '
      'then import that.',
    );
  }

  try {
    final workbook = Excel.decodeBytes(source.bytes);
    final sheets = <String, List<List<String?>>>{};

    for (final name in workbook.tables.keys) {
      final table = workbook.tables[name];
      if (table == null) continue;
      sheets[name] = table.rows
          .map((row) => row.map((cell) => cell?.value?.toString()).toList())
          .toList();
    }
    return sheets;
  } catch (error) {
    throw UnreadableSpreadsheet(
      'That file could not be read as a spreadsheet. Open it in Excel and '
      'use File → Save As to save it as .xlsx, then import that. ($error)',
    );
  }
}

/// A small RFC 4180 reader: quoted fields, doubled quotes inside them, and
/// newlines within quotes.
///
/// The gym's sheets are exported from Excel, which follows that convention,
/// and a member's address is exactly the field that will one day contain a
/// comma. Splitting on commas would quietly shift every column after it.
List<List<String?>> parseCsv(String input) {
  final rows = <List<String?>>[];
  var row = <String?>[];
  final field = StringBuffer();
  var quoted = false;
  var fieldWasQuoted = false;

  void endField() {
    final text = field.toString();
    row.add(text.isEmpty && !fieldWasQuoted ? null : text);
    field.clear();
    fieldWasQuoted = false;
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String?>[];
  }

  for (var i = 0; i < input.length; i++) {
    final char = input[i];

    if (quoted) {
      if (char != '"') {
        field.write(char);
      } else if (i + 1 < input.length && input[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = false;
      }
      continue;
    }

    switch (char) {
      case '"':
        quoted = true;
        fieldWasQuoted = true;
      case ',':
        endField();
      case '\r':
        // Consume CRLF as one break; a lone CR ends the row too.
        if (i + 1 < input.length && input[i + 1] == '\n') i++;
        endRow();
      case '\n':
        endRow();
      default:
        field.write(char);
    }
  }

  // A trailing newline leaves nothing worth adding; anything else is a row.
  if (field.isNotEmpty || fieldWasQuoted || row.isNotEmpty) endRow();

  return rows;
}
