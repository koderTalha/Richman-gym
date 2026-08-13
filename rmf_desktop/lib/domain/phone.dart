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
