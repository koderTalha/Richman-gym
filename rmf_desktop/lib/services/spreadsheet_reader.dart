import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show Archive, ZipDecoder;
import 'package:excel/excel.dart'
    show
        CellValue,
        DateCellValue,
        DateTimeCellValue,
        Excel,
        FormulaCellValue,
        TimeCellValue;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Reads a ledger file into plain rows of text, one entry per sheet.
///
/// Deliberately returns nothing but `String?` in nested lists: the result
/// crosses an isolate boundary, and primitives are the only thing that can make
/// that trip cheaply. It also means the parsing in `ledger_import.dart` never
/// has to know which file format the rows came out of.

/// Stands in for a formula cell whose result the file does not carry.
///
/// Excel saves every formula with the value it last worked out, and that
/// value is what the owner saw on screen. A file written by something that
/// never calculates — a script, some online converters — saves the formula
/// alone, and there is no reading "=D2" as money without a spreadsheet engine
/// to evaluate it. The cell cannot be dropped either: a blank month reads as
/// unpaid. So it travels through as this marker, which nothing else in a sheet
/// can begin with, and `parseLedger` turns it into a problem on the row.
///
/// A plain string rather than a type because the rows cross an isolate
/// boundary as `String?` and nothing else; see the comment above.
const formulaWithoutValueMarker = '\u0000formula:';

/// Whether [cell] is a formula the file holds no result for.
bool isFormulaWithoutValue(String? cell) =>
    cell != null && cell.startsWith(formulaWithoutValueMarker);

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

    // Only opened when a sheet holds a cell the `excel` package misreads, so
    // a ledger of plain typed figures is read exactly as it always was.
    _RawWorkbook? raw;
    _RawWorkbook rawWorkbook() => raw ??= _RawWorkbook.read(source.bytes);

    for (final name in workbook.tables.keys) {
      final table = workbook.tables[name];
      if (table == null) continue;
      final rows = table.rows;
      sheets[name] = [
        for (var r = 0; r < rows.length; r++)
          [
            for (var c = 0; c < rows[r].length; c++)
              _cellText(rows[r][c]?.value,
                  () => rawWorkbook().cell(name, r, c)),
          ],
      ];
    }
    return sheets;
  } catch (error) {
    throw UnreadableSpreadsheet(
      'That file could not be read as a spreadsheet. Open it in Excel and '
      'use File → Save As to save it as .xlsx, then import that. ($error)',
    );
  }
}

/// The text of one workbook cell, as the owner sees it in Excel.
///
/// Two kinds of cell the `excel` package gets wrong, and both used to turn
/// into money:
///
///  - **Formulas.** The package hands back the formula and throws away the
///    result Excel saved beside it, so "=1500+1000" — showing 2,500 — kept
///    only its digits and imported as Rs 15,001,000, and "=D2" as Rs 2. The
///    saved result is read from the file instead. Where there is none, the
///    cell becomes [formulaWithoutValueMarker]: formula text must never reach
///    the parser, which would read digits out of it.
///  - **Currency formats taken for dates.** The package decides a custom
///    format is a date if it holds a "d", "m", "s"... anywhere outside quotes,
///    and "[$Rs-420]#,##0" — Excel's own Rupee format — has an "s" in the
///    brackets. 2,500 came out as 4 November 1906. A date whose format is not
///    really a date is read back as the number in the cell.
///
/// [raw] is only called for those two, and whatever it cannot answer falls on
/// the safe side: a formula is refused, a date is left a date.
String? _cellText(CellValue? value, _RawCell? Function() raw) {
  switch (value) {
    // Also what the package returns for any text or error result — "str" and
    // "e" cells — formula or not, which the raw cell reads the same way.
    case FormulaCellValue():
      return _tryRaw(raw)?.cachedText ??
          '$formulaWithoutValueMarker${value.formula}';
    case DateCellValue() || DateTimeCellValue() || TimeCellValue():
      final cell = _tryRaw(raw);
      if (cell != null && cell.isNumberNotDate) return cell.numberText;
      return value.toString();
    default:
      return value?.toString();
  }
}

/// The raw pass is a repair, never a reason to refuse a file the `excel`
/// package could read: a workbook it trips over is read as before, with every
/// formula refused.
_RawCell? _tryRaw(_RawCell? Function() raw) {
  try {
    return raw();
  } catch (_) {
    return null;
  }
}

/// The parts of an .xlsx the `excel` package does not keep: the value saved
/// beside each formula, and the number format each cell really carries.
///
/// Sheets are read lazily and only the first time one of their cells is
/// asked about.
class _RawWorkbook {
  _RawWorkbook._(this._archive, this._sheetPaths, this._styles);

  factory _RawWorkbook.read(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Sheet name -> relationship id -> the part holding its cells.
    final targets = <String, String>{};
    final rels = _xml(archive, 'xl/_rels/workbook.xml.rels');
    if (rels != null) {
      for (final rel in rels.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id == null || target == null) continue;
        // Relative to xl/ unless written absolute, which some writers do.
        targets[id] = target.startsWith('/')
            ? target.substring(1)
            : 'xl/$target';
      }
    }
    final sheetPaths = <String, String>{};
    final book = _xml(archive, 'xl/workbook.xml');
    if (book != null) {
      for (final sheet in book.findAllElements('sheet')) {
        final name = sheet.getAttribute('name');
        final id = sheet.attributes
            .where((a) => a.name.local == 'id')
            .map((a) => a.value)
            .firstOrNull;
        final path = targets[id];
        if (name != null && path != null) sheetPaths[name] = path;
      }
    }

    return _RawWorkbook._(archive, sheetPaths, _Styles.read(archive));
  }

  final Archive _archive;
  final Map<String, String> _sheetPaths;
  final _Styles _styles;
  final _sheets = <String, Map<(int, int), _RawCell>>{};

  /// The cell at zero-based [row] and [column] of [sheet], or null where the
  /// file has nothing there.
  _RawCell? cell(String sheet, int row, int column) =>
      _sheets.putIfAbsent(sheet, () => _readSheet(sheet))[(row, column)];

  Map<(int, int), _RawCell> _readSheet(String sheet) {
    final cells = <(int, int), _RawCell>{};
    final path = _sheetPaths[sheet];
    final document = path == null ? null : _xml(_archive, path);
    if (document == null) return cells;

    for (final c in document.findAllElements('c')) {
      final position = _position(c.getAttribute('r'));
      if (position == null) continue;
      final style = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      cells[position] = _RawCell(
        type: c.getAttribute('t'),
        isFormula: c.findElements('f').isNotEmpty,
        value: c.findElements('v').firstOrNull?.innerText,
        format: _styles.formatOf(style),
      );
    }
    return cells;
  }

  static XmlDocument? _xml(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return null;
    return XmlDocument.parse(
        utf8.decode(file.content as List<int>, allowMalformed: true));
  }

  /// "AB12" -> (11, 27), zero-based row then column.
  static (int, int)? _position(String? reference) {
    if (reference == null) return null;
    final match = _reference.firstMatch(reference);
    if (match == null) return null;
    var column = 0;
    for (final unit in match.group(1)!.toUpperCase().codeUnits) {
      column = column * 26 + (unit - 64);
    }
    return (int.parse(match.group(2)!) - 1, column - 1);
  }

  static final _reference = RegExp(r'^\$?([A-Za-z]{1,3})\$?(\d+)$');
}

/// One `<c>` element, as the file wrote it.
class _RawCell {
  const _RawCell({
    required this.type,
    required this.isFormula,
    required this.value,
    required this.format,
  });

  /// The `t` attribute: "str" for a formula giving text, "e" for one giving
  /// an error, "b" for a boolean, absent or "n" for a number.
  final String? type;
  final bool isFormula;

  /// The `<v>` text: for a formula, the result Excel saved beside it.
  final String? value;
  final _Format format;

  bool get _isNumber => type == null || type == 'n';

  /// The saved result of a formula, written the way the `excel` package
  /// writes the same value typed in, or null where the file saved none.
  String? get cachedText {
    final v = value;
    if (v == null || v.isEmpty) return null;
    return switch (type) {
      // Text, or an error such as "#REF!" — shown in Excel just like that,
      // and no more a payment here than it is there.
      'str' || 'e' => v,
      'b' => v == '1' ? 'true' : 'false',
      // An index into the shared strings, which a formula never writes.
      's' => null,
      _ => format.isDate ? _dateText(v) : numberText,
    };
  }

  /// A number cell whose format the `excel` package read as a date, wrongly.
  bool get isNumberNotDate =>
      !isFormula && _isNumber && value != null && format.isCustom &&
      !format.isDate && num.tryParse(value!) != null;

  /// The number, without the ".0" the `excel` package also drops: "2500" for
  /// a whole number, so that an enrolment number stays a whole number.
  String? get numberText {
    final parsed = num.tryParse(value ?? '');
    if (parsed == null || !parsed.isFinite) return value;
    if (parsed == parsed.roundToDouble() && parsed.abs() < 1e15) {
      return parsed.toInt().toString();
    }
    return parsed.toDouble().toString();
  }

  /// A date the way the `excel` package writes one, which is what
  /// `parseLedgerDate` reads: days since 30 December 1899.
  static String? _dateText(String serial) {
    final days = num.tryParse(serial);
    if (days == null) return serial;
    final date = DateTime.utc(1899, 12, 30)
        .add(Duration(milliseconds: (days * 86400000).round()));
    return date.toIso8601String();
  }
}

/// The number format each cell style points at.
class _Styles {
  const _Styles(this._formatIdByStyle, this._customCodes);

  factory _Styles.read(Archive archive) {
    final document = _RawWorkbook._xml(archive, 'xl/styles.xml');
    if (document == null) return const _Styles([], {});

    final codes = <int, String>{};
    for (final format in document.findAllElements('numFmt')) {
      final id = int.tryParse(format.getAttribute('numFmtId') ?? '');
      final code = format.getAttribute('formatCode');
      if (id != null && code != null) codes[id] = code;
    }

    // Cell styles are the <xf> entries of <cellXfs>, in order; the `s` on a
    // cell is an index into them. <cellStyleXfs> holds <xf> too, and is not
    // what `s` counts.
    final ids = <int>[];
    final cellXfs = document.findAllElements('cellXfs').firstOrNull;
    for (final xf in cellXfs?.findElements('xf') ?? const <XmlElement>[]) {
      ids.add(int.tryParse(xf.getAttribute('numFmtId') ?? '') ?? 0);
    }
    return _Styles(ids, codes);
  }

  final List<int> _formatIdByStyle;
  final Map<int, String> _customCodes;

  _Format formatOf(int style) {
    final id = style < _formatIdByStyle.length ? _formatIdByStyle[style] : 0;
    final code = _customCodes[id];
    if (code != null) {
      return _Format(isCustom: true, isDate: _codeShowsADate(code));
    }
    return _Format(isCustom: false, isDate: _builtInDateFormats.contains(id));
  }

  /// Excel's built-in date and time formats, by id: the ones every locale
  /// has (14–22, 45–47) and the East Asian ones (27–36, 50–58).
  static const _builtInDateFormats = {
    14, 15, 16, 17, 18, 19, 20, 21, 22,
    27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
    45, 46, 47,
    50, 51, 52, 53, 54, 55, 56, 57, 58,
  };

  /// Whether a custom format code shows a date or a time.
  ///
  /// The same idea as the `excel` package's check — a "y", "m", "d", "h" or
  /// "s" outside quotes — but skipping what sits in square brackets, which is
  /// a currency and locale ("[$Rs-420]"), a colour ("[Red]") or a condition,
  /// never a date part. The one exception is elapsed time, "[h]:mm", which is
  /// a time all the same. Only the first section counts: the others are for
  /// negatives and zero.
  static bool _codeShowsADate(String code) {
    var i = 0;
    while (i < code.length) {
      final char = code[i];
      if (char == '\\' || char == '_' || char == '*') {
        // An escaped literal, or padding/fill by the character after it.
        i += 2;
      } else if (char == '"') {
        final end = code.indexOf('"', i + 1);
        if (end == -1) return false;
        i = end + 1;
      } else if (char == '[') {
        final end = code.indexOf(']', i + 1);
        if (end == -1) return false;
        if (_elapsed.hasMatch(code.substring(i + 1, end))) return true;
        i = end + 1;
      } else if (char == ';') {
        return false;
      } else if (_dateParts.contains(char.toLowerCase())) {
        return true;
      } else {
        i++;
      }
    }
    return false;
  }

  static final _elapsed = RegExp(r'^(h+|m+|s+)$', caseSensitive: false);
  static const _dateParts = {'y', 'm', 'd', 'h', 's'};
}

class _Format {
  const _Format({required this.isCustom, required this.isDate});

  /// Defined in the workbook's own styles, rather than one of Excel's
  /// built-in formats — the only kind the `excel` package can misjudge.
  final bool isCustom;
  final bool isDate;
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
