import 'dart:convert';
import 'dart:io';

import 'package:rich_man_fitness/services/diagnostics/diagnostics_crypto.dart';

/// Makes the developer's key pair for "Send to developer".
///
///     fvm dart run tool/diagnostics_keygen.dart
///
/// The private key goes to ~/.rich-man-fitness/diagnostics-private-key and
/// nowhere else — keep a copy somewhere safe, because without it no bundle
/// the gym sends can ever be opened. The public key is written into
/// lib/services/diagnostics/developer_key.dart, which is committed and built
/// into the app.
///
/// Refuses to replace an existing private key unless given --force: doing so
/// makes every bundle sealed for the old key unreadable, including any the
/// installed app sends before an update carrying the new key reaches it.
Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      (throw StateError('No home folder to keep the private key in.'));
  final keyFile = File('$home/.rich-man-fitness/diagnostics-private-key');

  if (await keyFile.exists() && !args.contains('--force')) {
    stderr.writeln('A private key already exists at ${keyFile.path}.\n'
        'Replacing it makes every bundle sealed for it unreadable. '
        'Pass --force if that is really what you want.');
    exitCode = 1;
    return;
  }

  final pair = await DiagnosticsKeyPair.generate();

  await keyFile.parent.create(recursive: true);
  await keyFile.writeAsString('${base64Encode(pair.privateKey)}\n');
  if (!Platform.isWindows) {
    await Process.run('chmod', ['600', keyFile.path]);
  }

  final public = base64Encode(pair.publicKey);
  final source = File('lib/services/diagnostics/developer_key.dart');
  await source.writeAsString('''
/// The developer's public key for "Send to developer" — see
/// `diagnostics_crypto.dart`. Public by design: it can seal a bundle but not
/// open one. The private half lives only on the developer's machine, at
/// ~/.rich-man-fitness/diagnostics-private-key.
///
/// Written by `tool/diagnostics_keygen.dart`; regenerate it there rather than
/// editing it by hand.
const developerPublicKeyBase64 = '$public';
''');

  stdout.writeln('Private key: ${keyFile.path}  (back this up)');
  stdout.writeln('Public key:  $public');
  stdout.writeln('Written to:  ${source.path}');
}
