import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rich_man_fitness/services/update/windows_update_client.dart';

/// Off Windows, [createUpdateHttpClient] must not go near
/// `windows_proxy_resolver.dart` at all.
///
/// There is no useful type check to make here: `package:http`'s own
/// `Client()` is backed by `IOClient` on every native platform, Windows
/// included, so "is it an `IOClient`?" is true either way and proves nothing.
/// What actually distinguishes the two branches is whether `findProxy` is
/// wired to WinHTTP — which is exercised directly by
/// `resolveWindowsProxyForUrl`'s own `!Platform.isWindows` guard in
/// `windows_proxy_resolver_test.dart`. This test only proves the factory
/// itself runs cleanly off Windows and hands back a working client.
void main() {
  test('off Windows, a plain client is produced without touching WinHTTP',
      () {
    expect(Platform.isWindows, isFalse,
        reason: "this suite runs on the CI/dev machine, not the gym's PC");

    final client = createUpdateHttpClient();
    addTearDown(client.close);

    expect(client, isA<http.Client>());
  });
}
