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

/// The most any single amount typed into the app may be: Rs. 10,00,000.
///
/// Far above a year paid in advance on the dearest plan, and far below the
/// figures a slipped key produces ("1e9", a pasted phone number), which would
/// otherwise be recorded as money the gym collected.
const maxAmountMinor = 100000000;

/// Reads an amount the owner typed, in rupees, as minor units.
///
/// Accepts what people actually write: "1500", "1,500", "1,500.50" and stray
/// spaces. Returns null for anything that is not a plain amount — more than
/// two decimal places (silently rounding "1500.555" would record a figure
/// nobody typed), exponents, "NaN" and "Infinity", which `double.tryParse`
/// accepts and `toMinorUnits` then throws on. Zero and negative amounts parse;
/// whether they are allowed is the caller's question, because a fee field and
/// a payment field answer it differently.
int? parseAmountMinor(String text) {
  final cleaned = text.replaceAll(',', '').replaceAll(' ', '').trim();
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;

  final rupees = int.parse(match.group(2)!);
  final paisa = int.parse((match.group(3) ?? '').padRight(2, '0'));
  final minor = rupees * 100 + paisa;
  return match.group(1) == '-' ? -minor : minor;
}

/// The text an amount field is pre-filled with, so saving the form unchanged
/// writes back exactly the stored figure. Whole rupees print without decimals,
/// as the owner types them; anything with paisa keeps both places.
String formatAmountInput(int minor) {
  final rupees = minor ~/ 100;
  final paisa = (minor % 100).abs();
  if (paisa == 0) return '$rupees';
  return '$rupees.${paisa.toString().padLeft(2, '0')}';
}

String formatMinorUnits(int minor, [String currency = defaultCurrency]) =>
    formatCurrency(fromMinorUnits(minor), currency);

/// Why [text] cannot be taken as a payment amount, or null when it can.
///
/// One wording for every amount field: "1,500" used to be refused as "Enter
/// an amount greater than zero", which it plainly is.
String? amountInputError(String text) {
  if (text.trim().isEmpty) return 'Enter an amount greater than zero';
  final minor = parseAmountMinor(text);
  if (minor == null) {
    return 'Enter an amount in rupees, like 2500 or 2,500.50';
  }
  if (minor <= 0) return 'Enter an amount greater than zero';
  if (minor > maxAmountMinor) {
    return 'That is more than ${formatMinorUnits(maxAmountMinor)} — '
        'check the amount';
  }
  return null;
}
