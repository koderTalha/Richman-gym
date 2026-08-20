import '../data/database.dart';
import 'dates.dart';
import 'money.dart';
import 'payment_method.dart';

/// A recorded payment as the audit log describes it.
///
/// Only the fields the owner can actually edit. Taking a snapshot before and
/// after is what lets the log say "Amount: Rs. 5,000 → Rs. 6,000" instead of
/// the much less useful "payment edited".
class PaymentSnapshot {
  const PaymentSnapshot({
    required this.amountMinor,
    required this.method,
    required this.paymentDate,
    required this.periodLabel,
    this.referenceNumber,
    this.notes,
  });

  final int amountMinor;
  final PaymentMethod method;
  final DateTime paymentDate;

  /// Already formatted, e.g. "August 2026 - October 2026".
  final String periodLabel;

  final String? referenceNumber;
  final String? notes;
}

/// One line per field that actually changed, oldest value first.
///
/// Returns empty when nothing changed, which is how the caller knows to record
/// nothing at all rather than an event saying a payment was edited into exactly
/// what it already was.
List<String> describePaymentChanges(
  PaymentSnapshot before,
  PaymentSnapshot after, {
  String currency = defaultCurrency,
}) {
  final lines = <String>[];

  if (before.amountMinor != after.amountMinor) {
    lines.add('Amount: ${formatMinorUnits(before.amountMinor, currency)} → '
        '${formatMinorUnits(after.amountMinor, currency)}');
  }

  if (before.method != after.method) {
    lines.add('Method: ${paymentMethodLabel(before.method)} → '
        '${paymentMethodLabel(after.method)}');
  }

  // Compared as instants: the same moment read on two different clocks is not
  // an edit, and reporting it as one would fill the log with phantom changes.
  if (!before.paymentDate.isAtSameMomentAs(after.paymentDate)) {
    lines.add('Payment date: ${formatDayMonthYear(before.paymentDate.toLocal())}'
        ' → ${formatDayMonthYear(after.paymentDate.toLocal())}');
  }

  if (before.periodLabel != after.periodLabel) {
    lines.add('Billing period: ${before.periodLabel} → ${after.periodLabel}');
  }

  final referenceChange = _textChange(
    'Reference',
    before.referenceNumber,
    after.referenceNumber,
  );
  if (referenceChange != null) lines.add(referenceChange);

  // Notes are free text and can run to paragraphs, so the log records that they
  // changed rather than reproducing them. The payment itself holds the text.
  if (_normalise(before.notes) != _normalise(after.notes)) {
    lines.add('Notes: ${_changeVerb(before.notes, after.notes)}');
  }

  return lines;
}

/// Short text worth quoting in full.
String? _textChange(String label, String? before, String? after) {
  final from = _normalise(before);
  final to = _normalise(after);
  if (from == to) return null;
  if (from == null) return '$label: added "$to"';
  if (to == null) return '$label: cleared (was "$from")';
  return '$label: "$from" → "$to"';
}

String _changeVerb(String? before, String? after) {
  final from = _normalise(before);
  final to = _normalise(after);
  if (from == null) return 'added';
  if (to == null) return 'cleared';
  return 'changed';
}

String? _normalise(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
