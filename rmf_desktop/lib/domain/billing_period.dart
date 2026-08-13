const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

final _billingMonthPattern = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$');

/// Parses a "YYYY-MM" billing month into the UTC instant at the start of that
/// month. UTC throughout so a period never shifts a day depending on timezone.
DateTime parseBillingMonth(String value) {
  final match = _billingMonthPattern.firstMatch(value.trim());
  if (match == null) {
    throw ArgumentError('Billing period must be in YYYY-MM format');
  }
  return DateTime.utc(int.parse(match.group(1)!), int.parse(match.group(2)!), 1);
}

class PeriodBounds {
  const PeriodBounds(this.periodStart, this.periodEnd);
  final DateTime periodStart;

  /// Exclusive end of the cycle.
  final DateTime periodEnd;
}

/// Start (inclusive) and end (exclusive) of a cycle beginning at [billingMonth]
/// and running for [durationMonths].
PeriodBounds periodBounds(String billingMonth, int durationMonths) {
  final start = parseBillingMonth(billingMonth);
  final end = DateTime.utc(start.year, start.month + durationMonths, 1);
  return PeriodBounds(start, end);
}

/// Human label, e.g. "August 2026" or "August 2026 - October 2026".
String formatBillingPeriod(DateTime periodStart, int durationMonths) {
  final startLabel =
      '${_monthNames[periodStart.month - 1]} ${periodStart.year}';
  if (durationMonths <= 1) return startLabel;

  final last = DateTime.utc(
    periodStart.year,
    periodStart.month + durationMonths - 1,
    1,
  );
  return '$startLabel - ${_monthNames[last.month - 1]} ${last.year}';
}

/// The current month as "YYYY-MM", used to default the Record Payment form.
String currentBillingMonth([DateTime? now]) {
  final at = (now ?? DateTime.now()).toUtc();
  return '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}';
}
