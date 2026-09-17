import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/update/windows_proxy_resolver.dart';

/// The one part of Windows proxy resolution testable without a Windows
/// machine: turning what WinHTTP hands back into what `HttpClient.findProxy`
/// understands.
///
/// The FFI calls that produce the raw string tested here — the real WPAD/PAC
/// resolution — can only be exercised on Windows itself; see the manual test
/// matrix in the engineering report.
void main() {
  group('parseWinHttpProxyList', () {
    test('empty input means no proxy', () {
      expect(parseWinHttpProxyList('', scheme: 'https'), 'DIRECT');
    });

    test('a bare host:port applies to every scheme', () {
      expect(
        parseWinHttpProxyList('proxy.gym.local:8080', scheme: 'https'),
        'PROXY proxy.gym.local:8080',
      );
    });

    test('a per-protocol list picks out the matching scheme', () {
      expect(
        parseWinHttpProxyList(
          'http=proxy1:80;https=proxy2:8080',
          scheme: 'https',
        ),
        'PROXY proxy2:8080',
      );
    });

    test('a per-protocol list with no match for our scheme is DIRECT', () {
      expect(
        parseWinHttpProxyList('ftp=proxy1:21', scheme: 'https'),
        'DIRECT',
      );
    });

    test('a resolved fallback chain from PAC/WPAD becomes a fallback chain',
        () {
      expect(
        parseWinHttpProxyList('proxy1:8080;proxy2:8081', scheme: 'https'),
        'PROXY proxy1:8080; PROXY proxy2:8081',
      );
    });

    test('a socks-only entry is dropped, not passed through malformed', () {
      expect(
        parseWinHttpProxyList('socks=proxy1:1080', scheme: 'https'),
        'DIRECT',
        reason: "dart:io's HttpClient cannot dial through a SOCKS proxy",
      );
    });

    test('a socks entry alongside a usable one keeps only the usable one',
        () {
      expect(
        parseWinHttpProxyList(
          'socks=proxy1:1080;https=proxy2:8080',
          scheme: 'https',
        ),
        'PROXY proxy2:8080',
      );
    });

    test('stray whitespace around entries is tolerated', () {
      expect(
        parseWinHttpProxyList(
          '  http=proxy1:80 ; https=proxy2:8080  ',
          scheme: 'https',
        ),
        'PROXY proxy2:8080',
      );
    });

    test('matching is case-insensitive on the protocol name', () {
      expect(
        parseWinHttpProxyList('HTTPS=proxy2:8080', scheme: 'https'),
        'PROXY proxy2:8080',
      );
    });
  });
}
