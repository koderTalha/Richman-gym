import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

final _log = Logger('update');

/// Asks Windows itself what proxy, if any, applies to a URL.
///
/// The problem this exists for: Dart's `HttpClient` does not read the
/// Windows system proxy configuration. A browser on the same machine goes
/// through Control Panel → Internet Options — which is also where "Automatic
/// detect settings" (WPAD) and "Use setup script" (a PAC file) live — and this
/// app, left to its own devices, goes direct. On a network that requires the
/// proxy, that is the entire difference between "the browser works, the app
/// does not" and nothing else.
///
/// The fix is not to parse PAC JavaScript ourselves — Windows already has an
/// engine for that — but to ask **WinHTTP**, the Win32 networking stack, to
/// do the resolution and hand back an answer. This file is a narrow FFI
/// wrapper around exactly two WinHTTP calls:
///
///   * `WinHttpGetIEProxyConfigForCurrentUser` — reads the configuration
///     itself: is proxy auto-detection on, is a PAC URL configured, or is
///     there a manual proxy.
///   * `WinHttpGetProxyForUrl` — when auto-detection or a PAC URL applies,
///     asks Windows to actually run WPAD/the PAC script for the one URL we
///     care about (`api.github.com`) and return the proxy it decided on.
///
/// Both are the same calls a browser or `curl --proxy-auto-detect` would make
/// on Windows; nothing here reimplements proxy logic, it only calls into it.
///
/// **Fails open.** Every failure path here — WinHTTP missing, a call
/// returning an error, a struct that cannot be read — resolves to `'DIRECT'`,
/// the same behaviour this app already had. A bug in this file must degrade
/// to "no proxy support", never to "cannot reach GitHub at all", which is the
/// same non-blocking bargain the rest of the updater makes — see
/// [UpdateService.check].
///
/// Not unit-testable end to end: it calls into `winhttp.dll`, which exists
/// only on Windows. [parseWinHttpProxyList] — the one part with real logic to
/// get wrong — is separated out so it can be, and is covered by
/// `test/windows_proxy_resolver_test.dart`. The FFI calls themselves need a
/// real Windows machine; see the manual test matrix in the engineering report.

/// The proxy Windows resolves for [url], in the format `HttpClient.findProxy`
/// expects — `'PROXY host:port'`, a `'; '`-joined list of those for a
/// fallback chain, or `'DIRECT'`.
///
/// Never throws. Called once per update check, not per request, so the cost
/// of asking Windows again is one WinHTTP round trip a day at most — see
/// [UpdateService.isDueForCheck].
String resolveWindowsProxyForUrl(Uri url) {
  if (!Platform.isWindows) return 'DIRECT';

  try {
    return _resolve(url);
  } catch (error, stack) {
    _log.warning('Windows proxy resolution failed; connecting directly',
        error, stack);
    return 'DIRECT';
  }
}

String _resolve(Uri url) {
  final config = _readIeProxyConfig();
  if (config == null) return 'DIRECT';

  if (config.autoDetect || config.autoConfigUrl != null) {
    final resolved = _resolveViaWinHttp(
      url,
      autoDetect: config.autoDetect,
      autoConfigUrl: config.autoConfigUrl,
    );
    if (resolved != null) return resolved;
    // WPAD found nothing and there was no manual fallback configured
    // alongside it — Windows itself falls back to direct in that case.
    if (config.manualProxy == null) return 'DIRECT';
  }

  final manual = config.manualProxy;
  if (manual != null) {
    return parseWinHttpProxyList(manual, scheme: url.scheme);
  }

  return 'DIRECT';
}

/// What `WinHttpGetIEProxyConfigForCurrentUser` reported.
class _IeProxyConfig {
  const _IeProxyConfig({
    required this.autoDetect,
    this.autoConfigUrl,
    this.manualProxy,
  });
  final bool autoDetect;
  final String? autoConfigUrl;
  final String? manualProxy;
}

_IeProxyConfig? _readIeProxyConfig() {
  final bindings = _WinHttp.instance;
  if (bindings == null) return null;

  final out = calloc<_WinHttpCurrentUserIeProxyConfig>();
  try {
    if (bindings.getIeProxyConfigForCurrentUser(out) == 0) {
      return null;
    }
    final ref = out.ref;
    return _IeProxyConfig(
      autoDetect: ref.fAutoDetect != 0,
      autoConfigUrl: _takeString(ref.lpszAutoConfigUrl),
      manualProxy: _takeString(ref.lpszProxy),
    );
  } finally {
    // lpszProxyBypass is read by nobody here, but WinHTTP still allocated it
    // and it must still be freed, or every check leaks a little heap memory
    // for the life of the process.
    _freeIfSet(out.ref.lpszAutoConfigUrl);
    _freeIfSet(out.ref.lpszProxy);
    _freeIfSet(out.ref.lpszProxyBypass);
    calloc.free(out);
  }
}

/// Runs WPAD and/or a PAC script for [url] through WinHTTP, returning what it
/// decided, or null when neither found an answer (a genuine "nothing found",
/// distinct from an error, which is what makes the caller's manual-proxy
/// fallback correct rather than a failure being silently treated as direct).
String? _resolveViaWinHttp(
  Uri url, {
  required bool autoDetect,
  String? autoConfigUrl,
}) {
  final bindings = _WinHttp.instance;
  if (bindings == null) return null;

  final session = bindings.open(
    'RichManFitness'.toNativeUtf16(),
    _winHttpAccessTypeNoProxy,
    ffi.nullptr,
    ffi.nullptr,
    0,
  );
  if (session == ffi.nullptr) return null;

  try {
    final options = calloc<_WinHttpAutoproxyOptions>();
    final info = calloc<_WinHttpProxyInfo>();
    try {
      options.ref.dwFlags = (autoDetect ? _winHttpAutoproxyAutoDetect : 0) |
          (autoConfigUrl != null ? _winHttpAutoproxyConfigUrl : 0);
      options.ref.dwAutoDetectFlags = autoDetect
          ? (_winHttpAutoDetectTypeDhcp | _winHttpAutoDetectTypeDnsA)
          : 0;
      options.ref.lpszAutoConfigUrl =
          autoConfigUrl == null ? ffi.nullptr : autoConfigUrl.toNativeUtf16();
      options.ref.fAutoLogonIfChallenged = 0;

      final ok =
          bindings.getProxyForUrl(session, url.toString().toNativeUtf16(),
                  options, info) !=
              0;
      if (!ok) return null;

      final proxy = _takeString(info.ref.lpszProxy);
      _freeIfSet(info.ref.lpszProxy);
      _freeIfSet(info.ref.lpszProxyBypass);
      return proxy == null
          ? null
          : parseWinHttpProxyList(proxy, scheme: url.scheme);
    } finally {
      calloc.free(options);
      calloc.free(info);
    }
  } finally {
    bindings.closeHandle(session);
  }
}

String? _takeString(ffi.Pointer<Utf16> ptr) =>
    ptr == ffi.nullptr ? null : ptr.toDartString();

void _freeIfSet(ffi.Pointer<Utf16> ptr) {
  if (ptr != ffi.nullptr) _WinHttp.instance?.globalFree(ptr.cast());
}

/// Turns what WinHTTP returned into what `HttpClient.findProxy` understands.
///
/// WinHTTP hands back one of three shapes:
///
///   * a bare `host:port`, applying to every protocol;
///   * `protocol=host:port` pairs, semicolon-separated, from a manual proxy
///     configured per protocol (`http=proxy1:80;https=proxy2:8080`);
///   * a semicolon-separated fallback chain from a resolved PAC/WPAD answer
///     (`proxy1:8080;proxy2:8081`), already scoped to the URL that was asked
///     about and carrying no protocol prefix.
///
/// dart:io's `HttpClient` speaks a different, narrower dialect: entries of
/// `PROXY host:port` or `DIRECT`, semicolon-space-separated, tried in order.
/// It has no notion of a SOCKS proxy, so a `socks=` entry is dropped rather
/// than passed through malformed — a request through a SOCKS proxy this
/// client cannot use is exactly as unreachable as no proxy at all, and saying
/// so honestly is better than handing dart:io a string it cannot parse.
///
/// Visible for testing: this is the one part of proxy resolution with real
/// logic to get wrong, and the only part testable without a Windows machine.
String parseWinHttpProxyList(String raw, {required String scheme}) {
  final entries = raw
      .split(';')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (entries.isEmpty) return 'DIRECT';

  final matched = <String>[];
  for (final entry in entries) {
    final eq = entry.indexOf('=');
    if (eq == -1) {
      matched.add(entry);
      continue;
    }
    final protocol = entry.substring(0, eq).trim().toLowerCase();
    final target = entry.substring(eq + 1).trim();
    if (protocol == 'socks') continue; // dart:io cannot dial through SOCKS.
    if (protocol == scheme.toLowerCase()) matched.add(target);
  }

  // A per-protocol list naming schemes other than ours (`ftp=...` only, say)
  // is the same as no proxy being configured for this request.
  if (matched.isEmpty) return 'DIRECT';

  return matched.map((host) => 'PROXY $host').join('; ');
}

// --- FFI bindings ------------------------------------------------------
//
// Deliberately hand-written rather than pulled from a package: neither
// `package:win32` nor any actively maintained package on pub.dev exposes
// these two WinHTTP calls (checked before writing this). The surface below
// is exactly the two functions `resolveWindowsProxyForUrl` calls, plus the
// handful of structs and constants Microsoft's own documentation specifies
// for them — nothing broader. See the class doc for why this stays this
// narrow.

const int _winHttpAccessTypeNoProxy = 1;
const int _winHttpAutoproxyAutoDetect = 0x00000001;
const int _winHttpAutoproxyConfigUrl = 0x00000002;
const int _winHttpAutoDetectTypeDhcp = 0x00000001;
const int _winHttpAutoDetectTypeDnsA = 0x00000002;

final class _WinHttpCurrentUserIeProxyConfig extends ffi.Struct {
  @ffi.Int32()
  external int fAutoDetect;
  external ffi.Pointer<Utf16> lpszAutoConfigUrl;
  external ffi.Pointer<Utf16> lpszProxy;
  external ffi.Pointer<Utf16> lpszProxyBypass;
}

final class _WinHttpAutoproxyOptions extends ffi.Struct {
  @ffi.Uint32()
  external int dwFlags;
  @ffi.Uint32()
  external int dwAutoDetectFlags;
  external ffi.Pointer<Utf16> lpszAutoConfigUrl;
  external ffi.Pointer<ffi.Void> lpvReserved;
  @ffi.Uint32()
  external int dwReserved;
  @ffi.Int32()
  external int fAutoLogonIfChallenged;
}

final class _WinHttpProxyInfo extends ffi.Struct {
  @ffi.Uint32()
  external int dwAccessType;
  external ffi.Pointer<Utf16> lpszProxy;
  external ffi.Pointer<Utf16> lpszProxyBypass;
}

typedef _WinHttpOpenNative = ffi.Pointer Function(
    ffi.Pointer<Utf16>,
    ffi.Uint32,
    ffi.Pointer<Utf16>,
    ffi.Pointer<Utf16>,
    ffi.Uint32);
typedef _WinHttpOpenDart = ffi.Pointer Function(ffi.Pointer<Utf16>, int,
    ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, int);

typedef _WinHttpCloseHandleNative = ffi.Int32 Function(ffi.Pointer);
typedef _WinHttpCloseHandleDart = int Function(ffi.Pointer);

typedef _GetIeProxyConfigNative = ffi.Int32 Function(
    ffi.Pointer<_WinHttpCurrentUserIeProxyConfig>);
typedef _GetIeProxyConfigDart = int Function(
    ffi.Pointer<_WinHttpCurrentUserIeProxyConfig>);

typedef _GetProxyForUrlNative = ffi.Int32 Function(
    ffi.Pointer,
    ffi.Pointer<Utf16>,
    ffi.Pointer<_WinHttpAutoproxyOptions>,
    ffi.Pointer<_WinHttpProxyInfo>);
typedef _GetProxyForUrlDart = int Function(
    ffi.Pointer,
    ffi.Pointer<Utf16>,
    ffi.Pointer<_WinHttpAutoproxyOptions>,
    ffi.Pointer<_WinHttpProxyInfo>);

typedef _GlobalFreeNative = ffi.Pointer Function(ffi.Pointer);
typedef _GlobalFreeDart = ffi.Pointer Function(ffi.Pointer);

/// Loaded once, lazily, and never on a non-Windows platform.
class _WinHttp {
  _WinHttp._(ffi.DynamicLibrary winhttp, ffi.DynamicLibrary kernel32)
      : open = winhttp.lookupFunction<_WinHttpOpenNative, _WinHttpOpenDart>(
            'WinHttpOpen'),
        closeHandle = winhttp
            .lookupFunction<_WinHttpCloseHandleNative, _WinHttpCloseHandleDart>(
                'WinHttpCloseHandle'),
        getIeProxyConfigForCurrentUser = winhttp.lookupFunction<
                _GetIeProxyConfigNative, _GetIeProxyConfigDart>(
            'WinHttpGetIEProxyConfigForCurrentUser'),
        getProxyForUrl = winhttp
            .lookupFunction<_GetProxyForUrlNative, _GetProxyForUrlDart>(
                'WinHttpGetProxyForUrl'),
        globalFree = kernel32
            .lookupFunction<_GlobalFreeNative, _GlobalFreeDart>('GlobalFree');

  final _WinHttpOpenDart open;
  final _WinHttpCloseHandleDart closeHandle;
  final _GetIeProxyConfigDart getIeProxyConfigForCurrentUser;
  final _GetProxyForUrlDart getProxyForUrl;
  final _GlobalFreeDart globalFree;

  static _WinHttp? _instance;
  static bool _loadFailed = false;

  static _WinHttp? get instance {
    if (_loadFailed) return null;
    final existing = _instance;
    if (existing != null) return existing;
    try {
      final loaded = _WinHttp._(
        ffi.DynamicLibrary.open('winhttp.dll'),
        ffi.DynamicLibrary.open('kernel32.dll'),
      );
      _instance = loaded;
      return loaded;
    } catch (error, stack) {
      _loadFailed = true;
      _log.warning('winhttp.dll could not be loaded; connecting directly',
          error, stack);
      return null;
    }
  }
}
