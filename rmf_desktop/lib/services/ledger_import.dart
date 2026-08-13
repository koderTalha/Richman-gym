import '../domain/phone.dart';

/// Parsing for the owner's real ledger format.
///
/// The sheet is *wide*, not one-row-per-record: each row is a member, and the
/// Jan–Dec columns each hold the amount paid in that month. So a single row can
/// produce a dozen historical payments, which is why this pivots rather than
/// mapping fields one-to-one.

const monthNames = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

/// Values the ledger uses to mean "nothing here".
const _blankMarkers = {'', '-', '--', 'nill', 'null', 'n/a', 'na', '0'};

bool isBlankCell(String? value) =>
    value == null || _blankMarkers.contains(value.trim().toLowerCase());

/// Where each meaningful column sits in the sheet, resolved from the header row.
class ColumnMapping {
  const ColumnMapping({
    this.memberCode,
    this.name,
    this.phone,
    this.feeSubmit,
    this.reference,
    this.status,
    this.extra,
    this.monthColumns = const {},
  });

  final int? memberCode;
  final int? name;
  final int? phone;
  final int? feeSubmit;
  final int? reference;
  final int? status;
  final int? extra;

  /// Month number (1–12) -> column index.
  final Map<int, int> monthColumns;

  bool get isUsable => name != null;
}

/// Finds the header row and maps its columns. The real sheet has a merged title
/// row above the headers, so the header row is detected by content rather than
/// assumed to be row 0.
({int headerRow, ColumnMapping mapping})? detectMapping(
  List<List<String?>> rows, {
  int searchDepth = 10,
}) {
  for (var r = 0; r < rows.length && r < searchDepth; r++) {
    final mapping = _mapRow(rows[r]);
    if (mapping.isUsable && mapping.monthColumns.length >= 6) {
      return (headerRow: r, mapping: mapping);
    }
  }

  // Fall back to any row that at least has a name column.
  for (var r = 0; r < rows.length && r < searchDepth; r++) {
    final mapping = _mapRow(rows[r]);
    if (mapping.isUsable) return (headerRow: r, mapping: mapping);
  }
  return null;
}

ColumnMapping _mapRow(List<String?> header) {
  int? memberCode, name, phone, feeSubmit, reference, status, extra;
  final months = <int, int>{};

  for (var c = 0; c < header.length; c++) {
    final raw = header[c]?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) continue;

    // Month headers are matched first: a column literally called "Mar" must not
    // be mistaken for anything else.
    final monthIndex = monthNames.indexWhere((m) => raw == m || raw.startsWith(m));
    if (monthIndex != -1 && raw.length <= 9) {
      months[monthIndex + 1] = c;
      continue;
    }

    if (name == null && (raw.contains('name') || raw.contains('customer'))) {
      name = c;
    } else if (memberCode == null &&
        (raw.contains('enroll') || raw.contains('sr') || raw == 'id' ||
            raw.contains('member id'))) {
      memberCode = c;
    } else if (phone == null &&
        (raw.contains('contact') || raw.contains('mobile') ||
            raw.contains('phone') || raw.contains('cell'))) {
      phone = c;
    } else if (feeSubmit == null &&
        (raw.contains('fee submit') || raw.contains('submit'))) {
      feeSubmit = c;
    } else if (reference == null &&
        (raw.contains('ref') || raw.contains('transaction'))) {
      reference = c;
    } else if (status == null && raw.contains('status')) {
      status = c;
    } else if (extra == null &&
        (raw.contains('extra') || raw.contains('note') ||
            raw.contains('remark'))) {
      extra = c;
    }
  }

  return ColumnMapping(
    memberCode: memberCode,
    name: name,
    phone: phone,
    feeSubmit: feeSubmit,
    reference: reference,
    status: status,
    extra: extra,
    monthColumns: months,
  );
}

/// One month cell that resolved to a payment.
class ParsedMonthPayment {
  const ParsedMonthPayment({
    required this.month,
    this.amountMinor,
  });

  final int month;

  /// Null means "paid, but the sheet does not say how much" — the cell showed
  /// Excel's ### (column too narrow) rather than a readable figure. The import
  /// falls back to the member's own fee.
  final int? amountMinor;

  bool get hasAmount => amountMinor != null;
}

class ParsedMemberRow {
  ParsedMemberRow({
    required this.sourceRow,
    required this.name,
    required this.rawPhone,
    required this.normalizedPhone,
    required this.memberCode,
    required this.reference,
    required this.notes,
    required this.payments,
    required this.problems,
    required this.warnings,
  });

  final int sourceRow;
  final String name;
  final String? rawPhone;
  final String? normalizedPhone;
  final int? memberCode;
  final String? reference;
  final String? notes;
  final List<ParsedMonthPayment> payments;

  /// Non-empty means the row cannot be imported at all.
  final List<String> problems;

  /// Importable, but something is worth telling the owner about — most often a
  /// member with no phone number, who simply cannot receive WhatsApp receipts.
  final List<String> warnings;

  bool get isValid => problems.isEmpty;
  bool get hasPhone => normalizedPhone != null;
  int get totalMinor =>
      payments.fold(0, (sum, p) => sum + (p.amountMinor ?? 0));

  /// Months marked paid where the sheet did not show a figure.
  int get paymentsWithoutAmount =>
      payments.where((p) => !p.hasAmount).length;
}

class ParsedLedger {
  const ParsedLedger({
    required this.year,
    required this.mapping,
    required this.rows,
  });

  final int year;
  final ColumnMapping mapping;
  final List<ParsedMemberRow> rows;

  List<ParsedMemberRow> get valid => rows.where((r) => r.isValid).toList();
  List<ParsedMemberRow> get invalid => rows.where((r) => !r.isValid).toList();

  /// Importable rows that still deserve a mention in the preview.
  List<ParsedMemberRow> get withWarnings =>
      rows.where((r) => r.isValid && r.warnings.isNotEmpty).toList();

  int get withoutPhone => valid.where((r) => !r.hasPhone).length;
  int get totalPayments =>
      valid.fold(0, (sum, r) => sum + r.payments.length);

  /// Across the sheet, how many paid months will use the plan fee because the
  /// cell showed ### instead of a number.
  int get paymentsUsingPlanFee =>
      valid.fold(0, (sum, r) => sum + r.paymentsWithoutAmount);
}

/// Pulls a year out of a sheet name like "Fee Detail 2026".
int? yearFromSheetName(String sheetName) {
  final match = RegExp(r'(20\d{2})').firstMatch(sheetName);
  return match == null ? null : int.parse(match.group(1)!);
}

/// What a single month cell means.
enum MonthCell {
  /// No payment: blank, "-", "NILL", 0.
  empty,

  /// Paid, amount readable from the sheet.
  amount,

  /// Paid, but the amount is not readable. Excel renders ### when a column is
  /// too narrow for the number, and the owner's ledger is full of them. Reading
  /// that as "unpaid" would silently wipe out real payment history, so it counts
  /// as paid and the fee is taken from the member's plan instead.
  paidAmountUnknown,
}

final _hashOnly = RegExp(r'^#+$');

({MonthCell kind, int? amountMinor}) classifyMonthCell(String? value) {
  if (isBlankCell(value)) return (kind: MonthCell.empty, amountMinor: null);

  final trimmed = value!.trim();
  if (_hashOnly.hasMatch(trimmed)) {
    return (kind: MonthCell.paidAmountUnknown, amountMinor: null);
  }

  // Strip currency symbols, commas and spaces: "Rs. 3,000" -> 3000
  final cleaned = trimmed.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return (kind: MonthCell.empty, amountMinor: null);

  final parsed = double.tryParse(cleaned);
  if (parsed == null || parsed <= 0) {
    return (kind: MonthCell.empty, amountMinor: null);
  }
  return (kind: MonthCell.amount, amountMinor: (parsed * 100).round());
}

/// Turns raw sheet rows into member records with their historical payments.
ParsedLedger parseLedger({
  required List<List<String?>> rows,
  required int headerRow,
  required ColumnMapping mapping,
  required int year,
}) {
  final parsed = <ParsedMemberRow>[];

  for (var r = headerRow + 1; r < rows.length; r++) {
    final row = rows[r];
    String? cell(int? index) =>
        (index == null || index >= row.length) ? null : row[index]?.trim();

    final name = cell(mapping.name);
    // Skip entirely blank rows rather than reporting them as errors — real
    // sheets are full of spacer rows.
    final hasAnything = row.any((c) => c != null && c.trim().isNotEmpty);
    if (!hasAnything) continue;

    final problems = <String>[];
    final warnings = <String>[];

    // A row without a name is meaningless. Everything else is recoverable:
    // the real ledger has plenty of members with no phone number recorded, and
    // skipping them would silently lose real people.
    if (name == null || name.isEmpty) {
      problems.add('Missing name');
    }

    final rawPhone = cell(mapping.phone);
    final normalized = normalizePhone(rawPhone);
    if (isBlankCell(rawPhone)) {
      warnings.add('No phone number — cannot receive WhatsApp receipts');
    } else if (normalized == null) {
      warnings.add('Unusable phone "$rawPhone" — cannot receive WhatsApp');
    }

    final codeText = cell(mapping.memberCode);
    final memberCode =
        codeText == null ? null : int.tryParse(codeText.replaceAll(RegExp(r'[^0-9]'), ''));

    final payments = <ParsedMonthPayment>[];
    mapping.monthColumns.forEach((month, columnIndex) {
      final classified = classifyMonthCell(cell(columnIndex));
      switch (classified.kind) {
        case MonthCell.empty:
          break;
        case MonthCell.amount:
          payments.add(ParsedMonthPayment(
              month: month, amountMinor: classified.amountMinor));
        case MonthCell.paidAmountUnknown:
          payments.add(ParsedMonthPayment(month: month));
      }
    });
    payments.sort((a, b) => a.month.compareTo(b.month));

    parsed.add(ParsedMemberRow(
      sourceRow: r + 1, // 1-based, matching what the user sees in Excel
      name: name ?? '',
      rawPhone: rawPhone,
      normalizedPhone: normalized,
      memberCode: memberCode,
      reference: cell(mapping.reference),
      notes: cell(mapping.extra),
      payments: payments,
      problems: problems,
      warnings: warnings,
    ));
  }

  return ParsedLedger(year: year, mapping: mapping, rows: parsed);
}
