import 'package:drift/drift.dart';

import '../domain/name.dart';
import '../domain/phone.dart';
import 'database.dart';

/// SQL search conditions shared by the Payments and Receipts listings.
///
/// Both screens used to read the newest few hundred rows and only then filter
/// them in Dart, so anything older than the cap could not be found at all:
/// searching "Ali" for a July payment answered "No payments match" with the
/// payment sitting in the database. These conditions go into the query itself,
/// before its `LIMIT`, so the cap bounds what is *shown* and never what can be
/// *found*.

/// A `LIKE` pattern matching [term] anywhere, with SQLite's wildcards in the
/// term escaped — pair with `escapeChar: r'\'`. Lower-cased, for comparison
/// against a lower-cased column.
String containsPattern(String term) =>
    '%${escapeLikePattern(term.toLowerCase())}%';

/// Matches the members whose name or phone matches [term].
///
/// Phones are stored in E.164 (`+923001234567`), which is not how anyone at
/// the counter writes them: `03001234567`, `0300-1234567`, `+92 300 1234567`.
/// So a term that reads as a whole number is compared after
/// [normalizePhone], and a term made only of phone characters is also
/// compared on its digits — "0300-12" finds "+9230012…". The raw text is
/// still tried as typed, as it always was.
///
/// The digits are reduced by the same rule the Members screen's search uses
/// (`MemberRepository._phoneDigits`), so a number typed on either screen
/// finds the same people.
Expression<bool> memberMatches($MembersTable members, String term) {
  final pattern = containsPattern(term);
  var match = members.fullName.lower().like(pattern, escapeChar: r'\') |
      members.phone.like(pattern, escapeChar: r'\');

  final normalized = normalizePhone(term);
  if (normalized != null) match = match | members.phone.equals(normalized);

  if (_phoneShaped.hasMatch(term)) {
    final digits = phoneSearchDigits(term);
    if (digits.isNotEmpty) {
      // Digits only, so there is nothing in them to escape.
      match = match | members.phone.like('%$digits%');
    }
  }
  return match;
}

/// The digits of a phone number as typed, less the one prefix that exists
/// only in the way people write it: 0092 or 92 (the country code, which a
/// stored number does have, but after a "+" the typed one lacks), or the
/// trunk 0 a stored number never has at all.
///
/// One prefix, not every leading zero: these screens also search receipt
/// numbers, and stripping all the zeros from "000123" would have turned a
/// receipt lookup into a search for every phone containing "123".
String phoneSearchDigits(String term) {
  final digits = term.replaceAll(_nonDigit, '');
  for (final prefix in const ['0092', '92', '0']) {
    if (digits.startsWith(prefix)) return digits.substring(prefix.length);
  }
  return digits;
}

/// Only digits and the punctuation people put in phone numbers. A name with
/// a digit in it ("Ali 2") must not turn into a search for every phone
/// containing a 2.
final _phoneShaped = RegExp(r'^[\d\s+\-().]+$');
final _nonDigit = RegExp(r'\D');
