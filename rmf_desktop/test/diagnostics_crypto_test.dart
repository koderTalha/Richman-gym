import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/diagnostics/diagnostics_crypto.dart';

void main() {
  late DiagnosticsKeyPair developer;

  setUp(() async {
    developer = await DiagnosticsKeyPair.generate();
  });

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  test('what is sealed with the public key opens with the private key',
      () async {
    final plain = bytes('six hundred members and their payments');

    final sealed = await sealDiagnostics(plain, developer.publicKey);
    final opened = await openDiagnostics(sealed, developer.privateKey);

    expect(opened, plain);
  });

  test('the sealed bytes do not contain the plain text', () async {
    final plain = bytes('+923000000022 Member One paid 3000');

    final sealed = await sealDiagnostics(plain, developer.publicKey);

    expect(latin1.decode(sealed, allowInvalid: true),
        isNot(contains('+923000000022')));
  });

  test('starts with a recognisable header so a stranger file is refused',
      () async {
    final sealed = await sealDiagnostics(bytes('x'), developer.publicKey);

    expect(ascii.decode(sealed.sublist(0, 8)), 'RMFDIAG1');
    await expectLater(
      openDiagnostics(bytes('not a diagnostics bundle at all'),
          developer.privateKey),
      throwsA(isA<DiagnosticsCryptoException>()),
    );
  });

  test('two sends of the same data look nothing alike', () async {
    final plain = bytes('same data');

    final a = await sealDiagnostics(plain, developer.publicKey);
    final b = await sealDiagnostics(plain, developer.publicKey);

    expect(a, isNot(b));
  });

  test('a different private key cannot open it', () async {
    final stranger = await DiagnosticsKeyPair.generate();
    final sealed = await sealDiagnostics(bytes('secret'), developer.publicKey);

    await expectLater(
      openDiagnostics(sealed, stranger.privateKey),
      throwsA(isA<DiagnosticsCryptoException>()),
    );
  });

  test('a file damaged on the way is refused rather than half-opened',
      () async {
    final sealed = await sealDiagnostics(bytes('payments'), developer.publicKey);
    sealed[sealed.length - 1] ^= 0x01;

    await expectLater(
      openDiagnostics(sealed, developer.privateKey),
      throwsA(isA<DiagnosticsCryptoException>()),
    );
  });

  test('keys survive the round trip through base64 text', () async {
    final restored = await DiagnosticsKeyPair.fromPrivateKey(
        base64Decode(base64Encode(developer.privateKey)));

    expect(restored.publicKey, developer.publicKey);
  });
}
