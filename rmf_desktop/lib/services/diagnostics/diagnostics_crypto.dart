import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Sealing for the bundle the owner sends to the developer.
///
/// The bundle is the gym's whole database — six hundred members' phone numbers
/// and every payment they have made — and it travels over the internet and
/// then sits in somebody's Google Drive. So it is sealed on this machine with
/// the developer's *public* key, and only the matching private key, which
/// never leaves the developer's computer, can open it. Nothing built into the
/// app is enough to read a bundle, which matters because the installer is
/// published on a public GitHub release where anyone can take it apart.
///
/// Layout, all of it written by [sealDiagnostics]:
///
/// ```
/// "RMFDIAG1" | sender public key (32) | nonce (12) | tag (16) | ciphertext
/// ```
///
/// A fresh X25519 key pair is made for every send, the shared secret is run
/// through HKDF-SHA256, and the bundle is encrypted with AES-256-GCM, whose
/// tag means a file damaged in transit is refused instead of opened wrong.
///
/// Deliberately free of Flutter imports: `tool/open_diagnostics.dart` runs
/// this same code with plain `dart run` on the developer's machine.
const _magic = 'RMFDIAG1';
const _keyLength = 32;
const _nonceLength = 12;
const _tagLength = 16;
const _headerLength =
    _magic.length + _keyLength + _nonceLength + _tagLength;

/// Binds the derived key to this format, so a key derived here can never be
/// mistaken for one derived for anything else.
final _hkdfInfo = utf8.encode('rich-man-fitness diagnostics v1');

final _x25519 = X25519();
final _aes = AesGcm.with256bits();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

class DiagnosticsCryptoException implements Exception {
  const DiagnosticsCryptoException(this.message);
  final String message;

  @override
  String toString() => 'DiagnosticsCryptoException: $message';
}

/// The developer's key pair. Only [publicKey] is ever built into the app.
class DiagnosticsKeyPair {
  const DiagnosticsKeyPair._(this.privateKey, this.publicKey);

  final Uint8List privateKey;
  final Uint8List publicKey;

  static Future<DiagnosticsKeyPair> generate() async =>
      _from(await _x25519.newKeyPair());

  static Future<DiagnosticsKeyPair> fromPrivateKey(List<int> privateKey) async {
    if (privateKey.length != _keyLength) {
      throw const DiagnosticsCryptoException(
          'A private key is 32 bytes; that file is not one.');
    }
    return _from(await _x25519.newKeyPairFromSeed(privateKey));
  }

  static Future<DiagnosticsKeyPair> _from(SimpleKeyPair pair) async {
    final private = await pair.extractPrivateKeyBytes();
    final public = await pair.extractPublicKey();
    return DiagnosticsKeyPair._(
        Uint8List.fromList(private), Uint8List.fromList(public.bytes));
  }
}

/// Seals [plain] so that only the holder of [recipientPublicKey]'s private key
/// can read it.
Future<Uint8List> sealDiagnostics(
    List<int> plain, List<int> recipientPublicKey) async {
  if (recipientPublicKey.length != _keyLength) {
    throw const DiagnosticsCryptoException(
        'The developer key built into this app is not a valid key.');
  }

  final sender = await _x25519.newKeyPair();
  final senderPublic = (await sender.extractPublicKey()).bytes;
  final key = await _deriveKey(
    ownKeyPair: sender,
    otherPublicKey: recipientPublicKey,
    senderPublicKey: senderPublic,
    recipientPublicKey: recipientPublicKey,
  );

  final box = await _aes.encrypt(plain, secretKey: key);

  return Uint8List.fromList([
    ...ascii.encode(_magic),
    ...senderPublic,
    ...box.nonce,
    ...box.mac.bytes,
    ...box.cipherText,
  ]);
}

/// Opens a bundle sealed by [sealDiagnostics]. Throws
/// [DiagnosticsCryptoException] for anything that is not one, was sealed for a
/// different key, or was damaged on the way.
Future<Uint8List> openDiagnostics(List<int> sealed, List<int> privateKey) async {
  if (sealed.length < _headerLength ||
      ascii.decode(sealed.sublist(0, _magic.length), allowInvalid: true) !=
          _magic) {
    throw const DiagnosticsCryptoException(
        'That file is not a Rich Man Fitness diagnostics bundle.');
  }

  var at = _magic.length;
  List<int> take(int n) => sealed.sublist(at, at += n);
  final senderPublic = take(_keyLength);
  final nonce = take(_nonceLength);
  final tag = take(_tagLength);
  final cipherText = sealed.sublist(at);

  final own = await DiagnosticsKeyPair.fromPrivateKey(privateKey);
  final key = await _deriveKey(
    ownKeyPair: await _x25519.newKeyPairFromSeed(own.privateKey),
    otherPublicKey: senderPublic,
    senderPublicKey: senderPublic,
    recipientPublicKey: own.publicKey,
  );

  try {
    final plain = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
      secretKey: key,
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    throw const DiagnosticsCryptoException(
        'The bundle could not be opened: it was sealed for a different key, '
        'or it was damaged on the way.');
  }
}

/// Both public keys go into the salt, so the derived key belongs to exactly
/// this sender and this recipient.
Future<SecretKey> _deriveKey({
  required SimpleKeyPair ownKeyPair,
  required List<int> otherPublicKey,
  required List<int> senderPublicKey,
  required List<int> recipientPublicKey,
}) async {
  final shared = await _x25519.sharedSecretKey(
    keyPair: ownKeyPair,
    remotePublicKey:
        SimplePublicKey(otherPublicKey, type: KeyPairType.x25519),
  );
  return _hkdf.deriveKey(
    secretKey: shared,
    nonce: [...senderPublicKey, ...recipientPublicKey],
    info: _hkdfInfo,
  );
}
