import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/phone.dart';

/// Numbers are stored as E.164 and shown the way the gym writes them. The
/// formatter must regroup only what it is sure of: a regrouped landline or
/// foreign number reads as a different number.
void main() {
  test('a Pakistani mobile is grouped as network code and subscriber', () {
    expect(formatPhoneForDisplay('+923000000102'), '+92 300 0000102');
    expect(formatPhoneForDisplay('+923450000105'), '+92 345 0000105');
  });

  test('surrounding whitespace is ignored', () {
    expect(formatPhoneForDisplay('  +923000000102 '), '+92 300 0000102');
  });

  group('anything else is shown exactly as stored', () {
    test('a Lahore landline', () {
      expect(formatPhoneForDisplay('+924235761234'), '+924235761234');
    });

    test('a foreign number', () {
      expect(formatPhoneForDisplay('+447700900123'), '+447700900123');
    });

    test('a number typed before validation existed', () {
      expect(formatPhoneForDisplay('0300-0000102'), '0300-0000102');
    });

    test('a mobile with a digit missing', () {
      expect(formatPhoneForDisplay('+92300000010'), '+92300000010');
    });
  });

  test('no number reads as a dash, not a blank', () {
    expect(formatPhoneForDisplay(null), '—');
    expect(formatPhoneForDisplay('   '), '—');
  });
}
