import 'package:flutter_test/flutter_test.dart';

import '../tool/open_diagnostics.dart';

/// `tool/open_diagnostics.dart` prints fields from a bundle that anybody can
/// make — the key it is sealed with ships in the public installer — so none
/// of them may reach the developer's terminal as control sequences
/// (audit SEC-004).
void main() {
  test('strips terminal escape sequences down to their harmless text', () {
    // Clear the screen, set the window title, then a fake "all clear".
    const hostile = '\x1b[2J\x1b]0;pwned\x07Looks fine\x1b[0m';

    final shown = printable(hostile);
    expect(shown, isNot(contains('\x1b')));
    expect(shown, isNot(contains('\x07')));
    expect(shown, contains('Looks fine'));
  });

  test('removes C1 controls, DEL and invisible formatting characters', () {
    const hostile = 'Rich\u009b31m Man\u007f \u202eSSENTIF\u202c\u200b Gym';

    final shown = printable(hostile);
    for (final c in ['\u009b', '\u007f', '\u202e', '\u202c', '\u200b']) {
      expect(shown, isNot(contains(c)),
          reason: 'U+${c.codeUnitAt(0).toRadixString(16)}');
    }
  });

  test('a one-line field stays on one line', () {
    expect(printable('Rich Man\r\n  Gym: someone else'),
        'Rich Man   Gym: someone else');
    expect(printable('a\u2028b'), 'a b');
  });

  test('a note keeps its lines, each indented under the heading', () {
    final shown = printable('First line\n  Gym:      Fake heading\r\nLast',
        multiline: true);

    final lines = shown.split('\n');
    expect(lines, hasLength(3));
    expect(lines.skip(1).every((l) => l.startsWith('            ')), isTrue,
        reason: 'a note must not be able to print a line that reads like '
            'one of the tool\'s own headings');
  });

  test('is capped, and falls back when nothing printable is left', () {
    expect(printable('x' * 5000, maxLength: 100).length, 101);
    expect(printable('\x1b\x07', fallback: '(none)'), '(none)');
    expect(printable(null, fallback: 'unknown'), 'unknown');
  });

  test('ordinary text, Urdu included, passes through unchanged', () {
    expect(printable('Rich Man Fitness'), 'Rich Man Fitness');
    expect(printable('رچ مین فٹنس'), 'رچ مین فٹنس');
  });
}
