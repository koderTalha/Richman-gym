import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'windows_proxy_resolver.dart';

/// The HTTP client [UpdateService] talks to GitHub through, chosen per
/// platform so Windows-specific networking stays in exactly one place.
///
/// ```
/// UpdateService
///     ↓
/// createUpdateHttpClient()
///     ├─ Windows → an HttpClient wired to WinHTTP's proxy resolution
///     └─ elsewhere → the plain http.Client() this app has always used
/// ```
///
/// Everywhere but Windows this changes nothing: `http.Client()` behaves
/// exactly as it did before this file existed. On Windows, the client's
/// `findProxy` callback is wired to [resolveWindowsProxyForUrl], so a request
/// that Windows itself would route through a proxy — manual, auto-detected,
/// or a PAC script — is routed the same way here. TLS verification is
/// untouched either way: this changes which door the request leaves through,
/// never whether the certificate on the other end is checked. See
/// `windows_proxy_resolver.dart` for why a proxy needs Windows involved at
/// all, and [UpdateService.install] for where certificate verification would
/// be bypassed if it ever were, which it is not.
http.Client createUpdateHttpClient() {
  if (!Platform.isWindows) return http.Client();

  final inner = HttpClient()
    ..findProxy = (uri) => resolveWindowsProxyForUrl(uri);
  return IOClient(inner);
}
