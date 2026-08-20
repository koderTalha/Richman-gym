const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "15 Aug 2026" — the one date format the app shows the owner.
///
/// Callers decide whether to hand this a local or a UTC value, because that
/// choice is not the formatter's to make: a payment happened at a moment on the
/// gym's clock, while a joining date and a cycle boundary are calendar days
/// anchored to UTC midnight. Reading either on the wrong clock lands on the
/// day before in any negative-offset timezone.
String formatDayMonthYear(DateTime at) =>
    '${at.day.toString().padLeft(2, '0')} '
    '${_monthAbbr[at.month - 1]} ${at.year}';
