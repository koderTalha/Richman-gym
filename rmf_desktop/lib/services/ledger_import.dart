import '../data/database.dart';
import '../domain/name.dart';
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

/// How many unpaid months in a row mean the member has stopped coming.
///
/// Three is the owner's own reading of their sheet. Two is a member who is
/// simply behind — on a ledger that runs to September, everybody who last paid
/// in July is two months down, and they have not all left.
const lapsedAfterUnpaidMonths = 3;

/// Cells saying the month was never this member's: they had not joined yet, or
/// it has not happened.
const _notApplicableMarkers = {'', '-', '--', 'null', 'n/a', 'na'};

/// Cells where the owner wrote down that no money came in.
///
/// Worth keeping apart from the markers above even though neither produces a
/// payment. A "0" against a month the member was here for is a month they did
/// not pay; a "-" is a month that was never theirs to pay. Three "0"s in a row
/// are the sheet's way of saying somebody stopped coming — see
/// [ParsedMemberRow.trailingUnpaidMonths] — and a dash says nothing of the
/// kind.
const _unpaidMarkers = {'0', 'nill'};

/// Values the ledger uses to mean "nothing here".
const _blankMarkers = {..._notApplicableMarkers, ..._unpaidMarkers};

bool isBlankCell(String? value) =>
    value == null || _blankMarkers.contains(value.trim().toLowerCase());

/// Whether the cell records a month that went unpaid, rather than one that
/// never applied.
bool isUnpaidCell(String? value) =>
    value != null && _unpaidMarkers.contains(value.trim().toLowerCase());

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
    this.plan,
    this.monthColumns = const {},
  });

  final int? memberCode;
  final int? name;
  final int? phone;
  final int? feeSubmit;
  final int? reference;
  final int? status;
  final int? extra;

  /// The "Plan" column, naming the membership plan each member belongs on.
  /// Absent from every sheet written before the app grew the column.
  final int? plan;

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
  int? memberCode, name, phone, feeSubmit, reference, status, extra, plan;
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

    // Before the name column: a header reading "Plan Name" names a plan.
    if (plan == null && raw.contains('plan')) {
      plan = c;
    } else if (name == null &&
        (raw.contains('name') || raw.contains('customer'))) {
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
    plan: plan,
    monthColumns: months,
  );
}

const _monthNumbers = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// "03-Jul-26", "3 July 2026" — a day, a month's name, a year.
final _namedMonthDate = RegExp(r'^(\d{1,2})[-/ ]([A-Za-z]{3,})[-/ ](\d{2}|\d{4})$');

/// "23/09/2026" — day first, as Pakistan writes it.
final _numericDate = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{2}|\d{4})$');

/// Reads the "Fee Submit" cell into a date.
///
/// The column reaches this function by two different routes, and they do not
/// agree on a format. A real workbook goes through the `excel` package, which
/// recognises the cell's date formatting and hands back an ISO timestamp. A CSV
/// carries whatever the owner typed — "03-Jul-26" in their sheets.
///
/// Anything it cannot read confidently becomes null rather than a guess. The
/// date's *day* decides which day of the month the member is billed on for as
/// long as they are a member, so a misread here would quietly move somebody's
/// due date; no date at all is the safer failure, and the member simply falls
/// back to the anchor they would have had anyway.
DateTime? parseLedgerDate(String? value) {
  if (isBlankCell(value)) return null;
  final trimmed = value!.trim();

  // Dates out of a workbook: 2026-09-03T00:00:00.000Z.
  final iso = DateTime.tryParse(trimmed);
  if (iso != null) return DateTime.utc(iso.year, iso.month, iso.day);

  final named = _namedMonthDate.firstMatch(trimmed);
  if (named != null) {
    final month = _monthNumbers[named.group(2)!.toLowerCase().substring(0, 3)];
    if (month == null) return null;
    return _ledgerDate(int.parse(named.group(1)!), month, named.group(3)!);
  }

  final numeric = _numericDate.firstMatch(trimmed);
  if (numeric != null) {
    return _ledgerDate(
      int.parse(numeric.group(1)!),
      int.parse(numeric.group(2)!),
      numeric.group(3)!,
    );
  }

  return null;
}

/// Builds the date, refusing one whose parts do not survive the trip.
///
/// `DateTime.utc` rolls an impossible date forward rather than rejecting it —
/// the 45th of July becomes 14 August — so the only way to know the sheet held
/// a real date is to read the parts back out and check they are the ones that
/// went in.
DateTime? _ledgerDate(int day, int month, String yearText) {
  if (month < 1 || month > 12) return null;
  final year = yearText.length == 2
      ? 2000 + int.parse(yearText)
      : int.parse(yearText);

  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// One unbroken stretch of months the member paid the same fee for, and so one
/// enrolment.
class PlanSegment {
  const PlanSegment({required this.startMonth, this.planId});

  /// The first month (1–12) this enrolment covers.
  final int startMonth;

  /// The plan whose price these months match, or null to use the plan the row
  /// names. The final stretch is always null: the "Plan" column states what the
  /// member is on now, and an explicit column beats a fee that two plans might
  /// share.
  final int? planId;
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
    this.planName,
    this.planId,
    this.feeSubmit,
    this.trailingUnpaidMonths = 0,
    this.planSegments = const [],
    required this.payments,
    required this.problems,
    required this.warnings,
  });

  /// Unpaid months running from the member's last payment to the end of the
  /// ledger.
  final int trailingUnpaidMonths;

  /// Whether the sheet shows this member walking away.
  bool get hasLapsed => trailingUnpaidMonths >= lapsedAfterUnpaidMonths;

  /// The enrolments the member's fees imply, oldest first, and empty where the
  /// sheet records no payment at all.
  final List<PlanSegment> planSegments;

  /// The date in the "Fee Submit" column, or null where the sheet has none.
  final DateTime? feeSubmit;

  /// The day of the month this member is billed on.
  int? get anchorDay => feeSubmit?.day;

  final int sourceRow;
  final String name;
  final String? rawPhone;
  final String? normalizedPhone;
  final int? memberCode;
  final String? reference;
  final String? notes;

  /// The plan the sheet names for this member, exactly as written, or null
  /// where the sheet names none — which is also the default, so a row built by
  /// hand for a sheet that predates the column needs to say nothing about it.
  final String? planName;

  /// The configured plan [planName] resolved to. Null where the row names no
  /// plan, in which case the import falls back to the plan chosen in the
  /// wizard; a name that matches nothing configured is a problem, not a null.
  final int? planId;

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

  /// Members the sheet shows having stopped coming, in sheet order.
  List<ParsedMemberRow> get lapsed =>
      valid.where((r) => r.hasLapsed).toList();

  /// Whether this sheet carries a "Plan" column at all.
  bool get namesPlans => mapping.plan != null;

  /// Importable rows naming no plan, which take the plan chosen in the wizard.
  int get rowsUsingChosenPlan => valid.where((r) => r.planId == null).length;

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
///
/// [plans] are the plans the gym has configured, and they are the only plans a
/// sheet can name. A "Plan" cell is looked up among them; one that matches
/// nothing becomes a problem on that row, so the member is reported rather than
/// imported onto somebody else's fee, and no plan is ever created from a sheet.
/// Passing none turns the column off altogether, which is what every caller
/// reading a sheet written before the column existed wants.
ParsedLedger parseLedger({
  required List<List<String?>> rows,
  required int headerRow,
  required ColumnMapping mapping,
  required int year,
  List<MembershipPlan> plans = const [],
}) {
  // Oldest plan first, so two plans sharing a name always resolve to the same
  // one of them whatever order the caller's query returned.
  final plansByName = <String, int>{};
  for (final plan in [...plans]..sort((a, b) => a.id.compareTo(b.id))) {
    plansByName.putIfAbsent(normalizePlanName(plan.name), () => plan.id);
  }

  // Fees that name exactly one plan, which is the only kind worth reading a
  // plan out of. A price two plans share says nothing about which of them a
  // member moved onto, so it maps to null and leaves their run unbroken.
  final planByPrice = <int, int?>{};
  for (final plan in plans) {
    planByPrice.update(plan.priceMinor, (_) => null, ifAbsent: () => plan.id);
  }

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

    // A blank plan cell is not an error: it means this row says nothing about
    // which plan the member is on, and the plan chosen in the wizard stands.
    final planCell = cell(mapping.plan);
    final planName = isBlankCell(planCell) ? null : planCell;
    int? planId;
    if (planName != null && plansByName.isNotEmpty) {
      planId = plansByName[normalizePlanName(planName)];
      if (planId == null) {
        problems.add('No membership plan called "$planName"');
      }
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

    // Unpaid months running from the member's last payment to the end of the
    // ledger. Counted as one unbroken run, so a gap they came back from stops
    // counting the moment they pay again: Bilal is missing February to June and
    // pays in July, and he has not left — he is two months behind, like
    // everybody else on a sheet that stops at September.
    var trailingUnpaid = 0;
    if (payments.isNotEmpty) {
      for (var month = payments.last.month + 1; month <= 12; month++) {
        final column = mapping.monthColumns[month];
        if (column == null || !isUnpaidCell(cell(column))) break;
        trailingUnpaid++;
      }
    }

    // The enrolments the fees imply. The sheet names one plan — the one they
    // are on now — but the figures show what they were paying at the time, and
    // on the owner's real ledger most members have moved at least once. A new
    // stretch opens only where a month's fee names a plan outright and a
    // different one from the stretch running: an unrecognised figure, or one
    // two plans share, is not evidence enough to move somebody.
    final segments = <PlanSegment>[];
    int? runningPlanId;
    for (final payment in payments) {
      final planForFee =
          payment.amountMinor == null ? null : planByPrice[payment.amountMinor];

      if (segments.isEmpty) {
        segments.add(
            PlanSegment(startMonth: payment.month, planId: planForFee));
        runningPlanId = planForFee;
      } else if (planForFee != null && planForFee != runningPlanId) {
        segments.add(
            PlanSegment(startMonth: payment.month, planId: planForFee));
        runningPlanId = planForFee;
      }
    }

    // Whatever the last stretch cost, it is the one the member is on now, and
    // the "Plan" column says so outright. An explicit column beats a fee.
    if (segments.isNotEmpty) {
      segments[segments.length - 1] =
          PlanSegment(startMonth: segments.last.startMonth);
    }

    parsed.add(ParsedMemberRow(
      sourceRow: r + 1, // 1-based, matching what the user sees in Excel
      name: name ?? '',
      rawPhone: rawPhone,
      normalizedPhone: normalized,
      memberCode: memberCode,
      reference: cell(mapping.reference),
      notes: cell(mapping.extra),
      planName: planName,
      planId: planId,
      feeSubmit: parseLedgerDate(cell(mapping.feeSubmit)),
      trailingUnpaidMonths: trailingUnpaid,
      planSegments: segments,
      payments: payments,
      problems: problems,
      warnings: warnings,
    ));
  }

  return ParsedLedger(year: year, mapping: mapping, rows: parsed);
}
