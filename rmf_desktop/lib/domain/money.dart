import 'package:intl/intl.dart';

const defaultCurrency = 'PKR';

/// Currencies whose default rendering we override. PKR would otherwise show as
/// "PKR 3,000.00"; the gym writes "Rs. 3,000".
const _symbolOverrides = {'PKR': 'Rs.'};

/// Formats a monetary amount for display. Currency is a parameter rather than a
/// constant so other currencies can be added from settings without code changes.
String formatCurrency(num amount, [String currency = defaultCurrency]) {
  final symbol = _symbolOverrides[currency];

  if (symbol != null) {
    final isWhole = amount == amount.roundToDouble();
    final pattern = isWhole ? '#,##0' : '#,##0.00';
    return '$symbol ${NumberFormat(pattern, 'en_US').format(amount)}';
  }

  return NumberFormat.currency(locale: 'en_US', name: currency).format(amount);
}

/// Money is stored as integer minor units (paisa) so no rounding drift can
/// accumulate in the database.
int toMinorUnits(num major) => (major * 100).round();

double fromMinorUnits(int minor) => minor / 100;

String formatMinorUnits(int minor, [String currency = defaultCurrency]) =>
    formatCurrency(fromMinorUnits(minor), currency);
