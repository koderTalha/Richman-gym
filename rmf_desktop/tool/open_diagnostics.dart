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
      return _fail('Refusing a bundle entry named "${entry.name}".');
    }
    final file = File('${out.path}/${entry.name}');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(entry.content as List<int>);
  }

  final infoFile = File('${out.path}/info.json');
  final info = await infoFile.exists()
      ? jsonDecode(await infoFile.readAsString()) as Map<String, dynamic>
      : const <String, dynamic>{};

  final note = (info['note'] as String?)?.trim() ?? '';
  stdout
    ..writeln('Opened ${info['reference'] ?? name} into ${out.path}')
    ..writeln('  Sent:     ${info['sentAt']}')
    ..writeln('  Gym:      ${info['gymName'] ?? 'unknown'}')
    ..writeln('  Version:  ${info['appVersion']}  (${info['os']})')
    ..writeln('  From:     ${info['source']}')
    ..writeln('  Note:     ${note.isEmpty ? '(none)' : note}');
  if (info['startupError'] != null) {
    stdout.writeln('  Startup error: ${info['startupError']}');
  }
  final leftOut = info['logsLeftOut'] as List? ?? const [];
  if (leftOut.isNotEmpty) {
    stdout.writeln('  Logs left out for size: ${leftOut.join(', ')}');
  }
}

void _fail(String message) {
  stderr.writeln(message);
  exitCode = 1;
}
