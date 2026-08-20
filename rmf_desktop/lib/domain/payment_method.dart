import '../data/database.dart';

/// How a payment method is written for people to read.
///
/// One definition, because this string reaches the owner through four
/// independent surfaces — the payment table, the receipt, the Excel export and
/// now the audit log — and four copies of the same switch is four places for
/// them to drift apart.
String paymentMethodLabel(PaymentMethod method) => switch (method) {
      PaymentMethod.cash => 'Cash',
      PaymentMethod.bankTransfer => 'Bank Transfer',
      PaymentMethod.easypaisa => 'Easypaisa',
      PaymentMethod.jazzcash => 'JazzCash',
      PaymentMethod.card => 'Card',
      PaymentMethod.other => 'Other',
    };
