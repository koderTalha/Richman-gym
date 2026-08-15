/// Hoisted rather than built per call: [normalizeName] runs once per existing
/// member and once per row inside the importer's loops.
final _dropped = RegExp(r"""[.,'’`"()\[\]]""");
final _separators = RegExp(r'[\s\-–—_/\\]+');

/// Collapses a member's name to a comparable form: lower case, without the
/// punctuation hand-typed sheets sprinkle around, and with runs of whitespace
/// reduced to a single space.
///
/// Ledger sheets are typed by hand, so the same person turns up as "Ali Khan",
/// "ALI  KHAN" and " ali khan " across years. Comparing the raw text would file
/// them as three different members.
///
/// Punctuation is folded for the same reason: "Md. Ali Khan" one year and
/// "Md Ali Khan" the next is one man, not two. Only characters that carry no
/// meaning on their own are removed — letters and digits are left alone, so
/// "Ali Khan" and "Ali Khani" stay different people.
String normalizeName(String value) => value
    .toLowerCase()
    .replaceAll(_dropped, '')
    .replaceAll(_separators, ' ')
    .trim();

/// Whether two written names are the same person.
///
/// The single definition of that question in the app: the Add Member form and
/// the ledger importer both go through here, so the two can never drift into
/// disagreeing about who is already on file.
bool namesMatch(String a, String b) => normalizeName(a) == normalizeName(b);

/// Escapes the wildcards SQLite's LIKE treats specially, so searching for "50%"
/// finds the member whose name contains it rather than matching everybody.
///
/// Pair with `ESCAPE '\'` in the query.
String escapeLikePattern(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
