import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/domain/billing_period.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/domain/money.dart';
import 'package:rich_man_fitness/domain/name.dart';
import 'package:rich_man_fitness/domain/phone.dart';
import 'package:rich_man_fitness/domain/receipt_number.dart';

void main() {
  group('formatCurrency', () {
    test('formats PKR by default as Rs. with separators and no decimals', () {
      expect(formatCurrency(3000), 'Rs. 3,000');
    });

    test('shows two decimals only when fractional', () {
      expect(formatCurrency(3000.5, 'PKR'), 'Rs. 3,000.50');
    });

    test('formats zero', () => expect(formatCurrency(0, 'PKR'), 'Rs. 0'));

    test('groups large amounts', () {
      expect(formatCurrency(1234567, 'PKR'), 'Rs. 1,234,567');
    });

    test('falls back to Intl for other currencies', () {
      expect(formatCurrency(3000, 'USD'), contains('3,000'));
    });
  });

  group('minor units', () {
    test('round-trips whole rupees', () {
      expect(toMinorUnits(3000), 300000);
      expect(fromMinorUnits(300000), 3000);
    });

    test('avoids float drift on fractional amounts', () {
      expect(toMinorUnits(3000.5), 300050);
      expect(formatMinorUnits(300050), 'Rs. 3,000.50');
    });
  });

  group('normalizeName', () {
    test('ignores casing', () {
      expect(normalizeName('ALI KHAN'), normalizeName('Ali Khan'));
    });

    test('collapses repeated and surrounding whitespace', () {
      expect(normalizeName('  Ali   Khan '), 'ali khan');
    });

    test('keeps different people apart', () {
      // Compared as values rather than collapsed to a boolean first, so a
      // failure prints what the two names actually normalized to.
      expect(normalizeName('Ali Khan'), isNot(normalizeName('Ali Khani')));
    });

    // Hand-typed sheets vary in punctuation far more often than in casing:
    // "Md. Ali Khan" one year and "Md Ali Khan" the next is one man, and
    // comparing the raw text filed him as two members with two sets of
    // payments.
    test('folds punctuation that carries no meaning', () {
      expect(normalizeName('Md. Ali Khan'), normalizeName('Md Ali Khan'));
      expect(normalizeName("Ali O'Khan"), normalizeName('Ali OKhan'));
      expect(normalizeName('Ali-Raza Khan'), normalizeName('Ali Raza Khan'));
      expect(normalizeName('Khan, Ali'), normalizeName('Khan Ali'));
    });

    test('but not letters or digits', () {
      expect(normalizeName('Ali Khan 2'), isNot(normalizeName('Ali Khan')));
      expect(normalizeName('Muhammad Ali'), isNot(normalizeName('Muhammed Ali')));
    });

    test('namesMatch is the same rule, stated once', () {
      expect(namesMatch('  MD.  ALI   KHAN ', 'Md Ali Khan'), isTrue);
      expect(namesMatch('Ali Khan', 'Ali Khani'), isFalse);
    });
  });

  group('escapeLikePattern', () {
    test('neutralises the wildcards LIKE would otherwise expand', () {
      expect(escapeLikePattern('50%'), r'50\%');
      expect(escapeLikePattern('a_b'), r'a\_b');
    });

    test('escapes the escape character itself', () {
      expect(escapeLikePattern(r'a\b'), r'a\\b');
    });

    test('leaves ordinary search terms alone', () {
      expect(escapeLikePattern('Ali Khan'), 'Ali Khan');
    });
  });

  group('normalizePhone', () {
    test('normalizes hyphenated Pakistani mobile from the ledger', () {
      expect(normalizePhone('0300-0000001'), '+923000000001');
    });

    test('normalizes space-separated', () {
      expect(normalizePhone('0300 0000001'), '+923000000001');
    });

    test('normalizes unformatted', () {
      expect(normalizePhone('03000000001'), '+923000000001');
    });

    test('normalizes already-international', () {
      expect(normalizePhone('+92 300 0000001'), '+923000000001');
    });

    test('trims whitespace', () {
      expect(normalizePhone('  0300-0000001  '), '+923000000001');
    });

    test('returns null for empty or missing input', () {
      expect(normalizePhone(''), isNull);
      expect(normalizePhone(null), isNull);
    });

    test('returns null for the ledger NILL placeholder', () {
      expect(normalizePhone('NILL'), isNull);
    });

    test('returns null for something too short', () {
      expect(normalizePhone('12'), isNull);
    });

    test('honours an explicit international prefix', () {
      expect(normalizePhone('+1 415 555 2671'), '+14155552671');
    });

    test('isValidPhone reflects normalization', () {
      expect(isValidPhone('0300-0000001'), isTrue);
      expect(isValidPhone('NILL'), isFalse);
    });
  });

  group('formatReceiptNumber', () {
    test('pads the sequence to six digits', () {
      expect(formatReceiptNumber('RMF', 2026, 1), 'RMF-2026-000001');
    });

    test('formats the spec example', () {
      expect(formatReceiptNumber('RMF', 2026, 184), 'RMF-2026-000184');
    });

    test('does not truncate beyond six digits', () {
      expect(formatReceiptNumber('RMF', 2026, 1234567), 'RMF-2026-1234567');
    });

    test('uppercases and trims the prefix', () {
      expect(formatReceiptNumber('  rmf ', 2026, 7), 'RMF-2026-000007');
    });

    test('rejects a non-positive sequence', () {
      expect(() => formatReceiptNumber('RMF', 2026, 0), throwsArgumentError);
    });
  });

  group('billing periods', () {
    test('parses YYYY-MM into a UTC month start', () {
      expect(
        parseBillingMonth('2026-08').toIso8601String(),
        '2026-08-01T00:00:00.000Z',
      );
    });

    test('rejects a malformed value', () {
      expect(() => parseBillingMonth('Aug 2026'), throwsArgumentError);
    });

    test('rejects an out-of-range month', () {
      expect(() => parseBillingMonth('2026-13'), throwsArgumentError);
    });

    test('monthly cycle ends one month later, exclusive', () {
      final bounds = periodBounds('2026-08', 1);
      expect(bounds.periodStart.toIso8601String(), '2026-08-01T00:00:00.000Z');
      expect(bounds.periodEnd.toIso8601String(), '2026-09-01T00:00:00.000Z');
    });

    test('quarterly spans three months', () {
      expect(
        periodBounds('2026-08', 3).periodEnd.toIso8601String(),
        '2026-11-01T00:00:00.000Z',
      );
    });

    test('rolls over the year boundary', () {
      expect(
        periodBounds('2026-12', 1).periodEnd.toIso8601String(),
        '2027-01-01T00:00:00.000Z',
      );
    });

    test('annual spans a full year', () {
      expect(
        periodBounds('2026-03', 12).periodEnd.toIso8601String(),
        '2027-03-01T00:00:00.000Z',
      );
    });

    test('labels a single month', () {
      expect(formatBillingPeriod(parseBillingMonth('2026-08'), 1), 'August 2026');
    });

    test('labels a multi-month span as a range', () {
      expect(
        formatBillingPeriod(parseBillingMonth('2026-08'), 3),
        'August 2026 - October 2026',
      );
    });

    test('currentBillingMonth pads single-digit months', () {
      expect(currentBillingMonth(DateTime.utc(2026, 3, 15)), '2026-03');
    });
  });

  group('deriveMemberStatus', () {
    final now = DateTime.utc(2026, 8, 15);

    StatusPeriod period(String start, String end, bool isPaid) => StatusPeriod(
          periodStart: DateTime.parse(start),
          periodEnd: DateTime.parse(end),
          isPaid: isPaid,
        );

    test('inactive when deactivated, whatever the payments say', () {
      expect(
        deriveMemberStatus(
          deactivatedAt: DateTime.utc(2026, 7),
          periods: [period('2026-08-01T00:00:00Z', '2026-09-01T00:00:00Z', true)],
          now: now,
        ),
        MemberStatus.inactive,
      );
    });

    test('paid when the cycle covering today has a payment', () {
      expect(
        deriveMemberStatus(
          deactivatedAt: null,
          periods: [period('2026-08-01T00:00:00Z', '2026-09-01T00:00:00Z', true)],
          now: now,
        ),
        MemberStatus.paid,
      );
    });

    test('due when the cycle covering today is unpaid', () {
      expect(
        deriveMemberStatus(
          deactivatedAt: null,
          periods: [period('2026-08-01T00:00:00Z', '2026-09-01T00:00:00Z', false)],
          now: now,
        ),
        MemberStatus.due,
      );
    });

    test('expired when the last cycle ended before today', () {
      expect(
        deriveMemberStatus(
          deactivatedAt: null,
          periods: [period('2026-06-01T00:00:00Z', '2026-07-01T00:00:00Z', true)],
          now: now,
        ),
        MemberStatus.expired,
      );
    });

    test('due for a member with no cycles at all', () {
      expect(
        deriveMemberStatus(deactivatedAt: null, periods: [], now: now),
        MemberStatus.due,
      );
    });

    test('ignores older paid cycles when the current one is unpaid', () {
      expect(
        deriveMemberStatus(
          deactivatedAt: null,
          periods: [
            period('2026-06-01T00:00:00Z', '2026-07-01T00:00:00Z', true),
            period('2026-07-01T00:00:00Z', '2026-08-01T00:00:00Z', true),
            period('2026-08-01T00:00:00Z', '2026-09-01T00:00:00Z', false),
          ],
          now: now,
        ),
        MemberStatus.due,
      );
    });

    test('treats the cycle end as exclusive', () {
      expect(
        deriveMemberStatus(
          deactivatedAt: null,
          periods: [period('2026-07-01T00:00:00Z', '2026-08-15T00:00:00Z', true)],
          now: now,
        ),
        MemberStatus.expired,
      );
    });
  });
}
