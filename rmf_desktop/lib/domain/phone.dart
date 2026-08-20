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
