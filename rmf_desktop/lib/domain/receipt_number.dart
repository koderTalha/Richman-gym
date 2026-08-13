const _sequencePad = 6;

/// Builds a display receipt number, e.g. RMF-2026-000184.
///
/// Uniqueness is enforced by the database (a unique index on receiptNumber) and
/// by allocating the sequence from the receipt counter inside the same
/// transaction that writes the payment.
String formatReceiptNumber(String prefix, int year, int sequence) {
  if (sequence < 1) {
    throw ArgumentError('Receipt sequence must be a positive integer');
  }
  final normalizedPrefix = prefix.trim().toUpperCase();
  return '$normalizedPrefix-$year-${sequence.toString().padLeft(_sequencePad, '0')}';
}
