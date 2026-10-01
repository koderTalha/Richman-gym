// The payment form's amount handling: a stored amount with paisa comes back
// exactly as stored, and the validator takes what the owner actually types.
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/money.dart';
import 'package:rich_man_fitness/ui/payments/payment_form_fields.dart';

void main() {
  group('amount validator', () {
    test('accepts commas and paisa', () {
      expect(amountInputError('2,500'), isNull);
      expect(amountInputError('2500.50'), isNull);
    });

    test('says what is wrong rather than "greater than zero" for everything',
        () {
      expect(amountInputError(''), contains('greater than zero'));
      expect(amountInputError('0'), contains('greater than zero'));
      expect(amountInputError('-5'), contains('greater than zero'));
      for (final bad in ['abc', 'NaN', 'Infinity', '1e9', '1500.555']) {
        expect(amountInputError(bad), contains('Enter an amount in rupees'),
            reason: bad);
      }
      expect(amountInputError('99999999999'), contains('check the amount'));
    });
  });

  group('edit form amount round-trip', () {
    test('an untouched amount with paisa comes back unchanged', () {
      final form = PaymentFormController(
        initialAmountMinor: 150050, // Rs 1,500.50
        billingMonth: '2026-09',
      );
      addTearDown(form.dispose);

      expect(form.amountMinor, 150050,
          reason: 'saving the edit dialog without touching the amount must '
              'not change the money (field shows "${form.amount.text}")');
    });
  });
}
