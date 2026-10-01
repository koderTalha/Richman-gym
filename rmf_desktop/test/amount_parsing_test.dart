import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/money.dart';

void main() {
  group('parseAmountMinor', () {
    test('reads the amounts the owner actually types', () {
      expect(parseAmountMinor('1500'), 150000);
      expect(parseAmountMinor('1,500'), 150000);
      expect(parseAmountMinor(' 1,500.50 '), 150050);
      expect(parseAmountMinor('1500.5'), 150050);
      expect(parseAmountMinor('0'), 0);
      expect(parseAmountMinor('-200'), -20000);
    });

    test('refuses anything that is not a plain amount', () {
      for (final text in [
        '',
        'abc',
        '1500.555',
        '1e9',
        'NaN',
        'Infinity',
        '1.2.3',
        'Rs. 1500',
      ]) {
        expect(parseAmountMinor(text), isNull, reason: text);
      }
    });
  });

  group('formatAmountInput', () {
    test('round-trips through parseAmountMinor without moving a paisa', () {
      for (final minor in [0, 100, 150000, 150050, 150001, 99]) {
        expect(parseAmountMinor(formatAmountInput(minor)), minor,
            reason: '$minor');
      }
    });

    test('whole rupees print as the owner types them', () {
      expect(formatAmountInput(250000), '2500');
      expect(formatAmountInput(250050), '2500.50');
    });
  });
}
