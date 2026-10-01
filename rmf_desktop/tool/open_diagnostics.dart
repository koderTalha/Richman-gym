import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:rich_man_fitness/services/diagnostics/diagnostics_crypto.dart';

/// Opens a bundle the gym sent with "Send to developer".
///
///     fvm dart run tool/open_diagnostics.dart ~/Downloads/RMF-20261001-1432.rmfdiag
///
/// Unpacks it into a folder beside the file — `database/`, `logs/` and
/// `info.json` — and prints the owner's note. Reads the private key from
/// ~/.rich-man-fitness/diagnostics-private-key unless `--key <file>` says
/// otherwise.
///
/// The database it unpacks is the gym's real data. Point the tools in this
/// folder at it (`DB=… fvm flutter test tool/verify_on_owner_db.dart`); do not
/// copy it over the database the dev app opens, which is live too.
///
/// A bundle is untrusted until its reference matches one the owner read out.
/// The public key it is sealed with ships inside the public installer, so
/// anybody can make one, and the upload address is in that installer too.
/// Every field printed below is therefore passed through [printable] first:
/// a note carrying terminal escape sequences could otherwise rewrite what
/// this screen shows, or the terminal's title, or worse (audit SEC-004).
Future<void> main(List<String> args) async {
  final keyIndex = args.indexOf('--key');
  final keyPath = keyIndex >= 0 && keyIndex + 1 < args.length
      ? args[keyIndex + 1]
      : '${Platform.environment['HOME']}/.rich-man-fitness/diagnostics-private-key';
  final bundles = [
    for (var i = 0; i < args.length; i++)
      if (keyIndex < 0 || (i != keyIndex && i != keyIndex + 1)) args[i],
  ];

  if (bundles.length != 1) {
    stderr.writeln('Usage: fvm dart run tool/open_diagnostics.dart '
        '<bundle.rmfdiag> [--key <private-key-file>]');
    exitCode = 64;
    return;
  }

  final bundle = File(bundles.single);
  final keyFile = File(keyPath);
  if (!await bundle.exists()) return _fail('No file at ${bundle.path}.');
  if (!await keyFile.exists()) return _fail('No private key at ${keyFile.path}.');

  final List<int> zip;
  try {
    zip = await openDiagnostics(await bundle.readAsBytes(),
        base64Decode((await keyFile.readAsString()).trim()));
  } on DiagnosticsCryptoException catch (e) {
    return _fail(e.message);
  }

  final name = bundle.uri.pathSegments.last.replaceAll('.rmfdiag', '');
  final out = Directory('${bundle.parent.path}/$name');
  if (await out.exists()) {
    return _fail('${out.path} already exists; move it aside first.');
  }

  final archive = ZipDecoder().decodeBytes(zip);
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    // A bundle this app built never climbs out of its folder; refuse one that
    // tries rather than trust a name from a file off the internet.
    if (entry.name.contains('..') || entry.name.startsWith('/')) {
      return _fail(
          'Refusing a bundle entry named "${printable(entry.name)}".');
    }
    final file = File('${out.path}/${entry.name}');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(entry.content as List<int>);
  }

  final infoFile = File('${out.path}/info.json');
  final info = await infoFile.exists()
      ? jsonDecode(await infoFile.readAsString()) as Map<String, dynamic>
      : const <String, dynamic>{};

  String line(String key, {String fallback = ''}) =>
      printable(info[key], fallback: fallback, maxLength: 200);
  String block(String key) => printable(info[key],
      fallback: '(none)', multiline: true, maxLength: 4000);

  stdout
    ..writeln('Opened ${printable(info['reference'], fallback: name)} '
        'into ${out.path}')
    ..writeln('  Sent:     ${line('sentAt')}')
    ..writeln('  Gym:      ${line('gymName', fallback: 'unknown')}')
    ..writeln('  Version:  ${line('appVersion')}  (${line('os')})')
    ..writeln('  From:     ${line('source')}')
    ..writeln('  Note:     ${block('note')}');
  if (info['startupError'] != null) {
    stdout.writeln('  Startup error: ${block('startupError')}');
  }
  final leftOut = info['logsLeftOut'] as List? ?? const [];
  if (leftOut.isNotEmpty) {
    stdout.writeln('  Logs left out for size: '
        '${printable(leftOut.join(', '), maxLength: 400)}');
  }
  stdout.writeln('  Treat this as untrusted until its reference matches the '
      'one the owner read out.');
}

/// [value] made safe to print to a terminal.
///
/// Removes every control character — ESC above all, which starts the
/// sequences that move the cursor, recolour or clear the screen, set the
/// window title or, in some terminals, write to the clipboard — along with
/// the C1 controls, DEL, and the invisible Unicode formatting characters
/// (bidirectional overrides, zero-width spaces) that make text read
/// differently from what it is. A line break survives only in [multiline]
/// text, and every continuation line is indented, so a note cannot print a
/// line that looks like one of the headings above it. Capped at [maxLength].
String printable(
  Object? value, {
  String fallback = '',
  bool multiline = false,
  int maxLength = 200,
}) {
  if (value == null) return fallback;
  var text = '$value'
      .replaceAll(RegExp(r'\r\n?|[\u2028\u2029\u0085]'), '\n')
      .replaceAll('\t', ' ')
      .replaceAll(
          RegExp(r'[\x00-\x09\x0B-\x1F\x7F-\x9F'
              r'\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]'),
          '');
  text = multiline
      ? text.trim().split('\n').join('\n            ')
      : text.replaceAll('\n', ' ').trim();

  if (text.isEmpty) return fallback;
  return text.length > maxLength ? '${text.substring(0, maxLength)}…' : text;
}

void _fail(String message) {
  stderr.writeln(message);
  exitCode = 1;
}
