import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Pakistan is the initial market, but callers may override per member.
const defaultIsoCode = IsoCode.PK;

/// Converts a raw, human-entered number into E.164 form (+923000000022), which
/// is what the WhatsApp Cloud API requires.
///
/// Returns null when the input is missing or is not a valid number — the ledger
/// contains placeholders like "NILL" that must not become fake phone numbers.
String? normalizePhone(String? raw, {IsoCode isoCode = defaultIsoCode}) {
  if (raw == null) return null;

  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  try {
    final parsed = trimmed.startsWith('+')
        ? PhoneNumber.parse(trimmed)
        : PhoneNumber.parse(trimmed, callerCountry: isoCode);

    if (!parsed.isValid()) return null;
    return '+${parsed.countryCode}${parsed.nsn}';
  } catch (_) {
    return null;
  }
}

bool isValidPhone(String? raw, {IsoCode isoCode = defaultIsoCode}) =>
    normalizePhone(raw, isoCode: isoCode) != null;

/// Hides all but the last four digits, for the audit log.
///
/// The Logs screen is a browsing surface: it is read to answer "what happened
/// last Tuesday", not to place a call, and a full list of members' numbers is
/// not something it needs to put on screen. The `WhatsAppMessages` row keeps
/// the number in full, because that is the record of what was actually dialled
/// and is what a delivery problem has to be diagnosed against.
String maskPhone(String? phone) {
  if (phone == null) return '—';
  final trimmed = phone.trim();
  if (trimmed.length <= 4) return trimmed.isEmpty ? '—' : trimmed;
  return '••••${trimmed.substring(trimmed.length - 4)}';
}

/// A stored number as people read it: `+923000000102` → `+92 300 0000102`.
///
/// Only Pakistani mobile numbers in the stored E.164 form are regrouped — the
/// network code, then the subscriber number, as they are written on a card.
/// Anything else (a landline, a foreign number, something typed before
/// validation existed) is shown exactly as stored, because regrouping a
/// number in a pattern it does not follow is how a wrong number gets dialled.
String formatPhoneForDisplay(String? phone) {
  if (phone == null) return '—';
  final trimmed = phone.trim();
  final match = RegExp(r'^\+92(3\d{2})(\d{7})$').firstMatch(trimmed);
  if (match == null) return trimmed.isEmpty ? '—' : trimmed;
  return '+92 ${match.group(1)} ${match.group(2)}';
}
