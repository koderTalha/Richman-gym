import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/update/update_service.dart';

/// Turning whatever `package:http` threw into a specific reason, so the owner
/// is never told "no internet connection" on a machine that has one.
///
/// Every case here is deliberately checked against the *text* dart:io writes
/// into `SocketException.message` and `.osError`, because that is genuinely
/// all there is to go on — Dart does not give this app a typed exception per
/// failure mode. That is also why the fallback is
/// [UpdateFailureKind.unknownNetworkError] rather than a guess: a wrong,
/// over-specific message in front of a non-technical owner is worse than an
/// honest "could not check".
void main() {
  group('classifyNetworkError', () {
    test('a bare socket exception with no evidence is unknown, not offline',
        () {
      expect(classifyNetworkError(const SocketException('down')),
          UpdateFailureKind.unknownNetworkError);
    });

    test('"no route to host" is offline — the strongest evidence there is',
        () {
      expect(
        classifyNetworkError(const SocketException('No route to host')),
        UpdateFailureKind.offline,
      );
    });

    test('"network is unreachable" is offline', () {
      expect(
        classifyNetworkError(
            const SocketException('Network is unreachable')),
        UpdateFailureKind.offline,
      );
    });

    test('a failed host lookup is a DNS failure, not offline', () {
      expect(
        classifyNetworkError(
            const SocketException("Failed host lookup: 'api.github.com'")),
        UpdateFailureKind.dnsFailure,
      );
    });

    test('"name or service not known" is a DNS failure', () {
      expect(
        classifyNetworkError(
            const SocketException('Name or service not known')),
        UpdateFailureKind.dnsFailure,
      );
    });

    test('a refused connection is named as such', () {
      expect(
        classifyNetworkError(const SocketException('Connection refused')),
        UpdateFailureKind.connectionRefused,
      );
    });

    test('a socket timeout is a connection timeout', () {
      expect(
        classifyNetworkError(
            const SocketException('Connection timed out')),
        UpdateFailureKind.connectionTimeout,
      );
    });

    test('a dart:async TimeoutException is a connection timeout', () {
      expect(
        classifyNetworkError(TimeoutException('too slow')),
        UpdateFailureKind.connectionTimeout,
      );
    });

    test('a TLS handshake failure is named, never treated as a reason to '
        'bypass verification', () {
      expect(
        classifyNetworkError(
            const HandshakeException('certificate verify failed')),
        UpdateFailureKind.tlsFailure,
      );
    });

    test('a bad-certificate exception is also a TLS failure', () {
      expect(
        classifyNetworkError(
            const CertificateException('certificate has expired')),
        UpdateFailureKind.tlsFailure,
      );
    });

    test('a ProxyConnectionException is named as a proxy failure', () {
      expect(
        classifyNetworkError(const ProxyConnectionException(
            'the resolved proxy refused the connection')),
        UpdateFailureKind.proxyFailure,
      );
    });

    test('something entirely unrecognised is unknown, not offline', () {
      expect(classifyNetworkError(StateError('unexpected')),
          UpdateFailureKind.unknownNetworkError);
    });

    test('matching is case-insensitive — the OS does not promise a case',
        () {
      expect(
        classifyNetworkError(const SocketException('CONNECTION REFUSED')),
        UpdateFailureKind.connectionRefused,
      );
    });
  });
}
