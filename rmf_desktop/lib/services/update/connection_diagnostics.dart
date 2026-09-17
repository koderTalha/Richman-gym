import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'update_service.dart';
import 'windows_proxy_resolver.dart';

final _log = Logger('update');

/// One layer of the path a request to GitHub actually travels:
///
/// ```
/// Network adapter → DNS → Secure connection (TCP + TLS) → Proxy → GitHub API
/// ```
///
/// The everyday update check only ever reports one of these — whichever one
/// failed, as an [UpdateFailureKind] — because asking "which layer" on every
/// app launch would be slower than the launch itself needs to be. This
/// enumerates them separately for the moment somebody presses "Test
/// Connection" specifically because the everyday check is not enough: the
/// owner, or whoever is on the phone with them, needs to read down a list
/// rather than guess from one sentence.
enum ConnectivityLayer { adapter, dns, secureConnection, proxy, githubService }

/// What one layer found.
class LayerResult {
  const LayerResult({
    required this.layer,
    required this.label,
    required this.passed,
    this.applicable = true,
    this.detail,
  });

  final ConnectivityLayer layer;

  /// Owner-facing, e.g. "Secure connection" — never the exception text.
  final String label;
  final bool passed;

  /// False for a layer this platform does not have — the proxy check
  /// everywhere but Windows. Neither a pass nor a failure: shown as neither a
  /// ✓ nor a ✗, because reporting "no proxy" on a Mac would read as news
  /// about a thing that was never being checked.
  final bool applicable;

  /// Technical detail for "Copy Details" only. Never shown as the primary
  /// line — see the class comment on [ConnectionTestReport.summary].
  final String? detail;
}

/// The result of pressing "Test Connection".
class ConnectionTestReport {
  const ConnectionTestReport({
    required this.at,
    required this.layers,
    required this.summary,
  });

  final DateTime at;
  final List<LayerResult> layers;

  /// One sentence for the owner, chosen from the first layer that failed.
  /// Never a raw exception — see `UpdateFailureKind` and
  /// `windows_proxy_resolver.dart` for why.
  final String summary;

  bool get allPassed =>
      layers.where((l) => l.applicable).every((l) => l.passed);

  /// A plain-text dump for "Copy Details" — safe to paste into a message to
  /// whoever is helping the owner, because it holds nothing more sensitive
  /// than what layer failed and the OS's own error text. No token, password
  /// or credential ever reaches this file; there is none to check inputs
  /// through diagnostics that talk only to a public GitHub endpoint.
  String toClipboardText() {
    final buffer = StringBuffer('Connection test — ${at.toLocal()}\n');
    for (final layer in layers) {
      final mark = !layer.applicable ? '—' : (layer.passed ? '✓' : '✗');
      buffer.writeln('$mark ${layer.label}'
          '${layer.detail == null ? '' : ': ${layer.detail}'}');
    }
    return buffer.toString();
  }
}

/// Runs the layered check a "Test Connection" button asks for.
///
/// Each layer is checked in order and, once one fails, the layers below it
/// are still attempted — a dead DNS server does not stop this from also
/// reporting whether the network adapter is up — because the point is to
/// show the owner (or whoever they are reading this to down the phone)
/// exactly where the chain breaks, not to stop at the first bad news.
///
/// Deliberately not part of the every-launch update check: this makes a real
/// TCP connection and a real TLS handshake in addition to the HTTP request
/// [UpdateService.check] already makes, which is worth the extra second only
/// when a human is actively waiting for a diagnosis. See
/// [UpdateService.testConnection].
class ConnectionDiagnostics {
  ConnectionDiagnostics({
    required http.Client httpClient,
    required Uri endpoint,
    this.timeout = const Duration(seconds: 8),
    // Injectable so the layered logic is testable without a real network —
    // dns/tls/adapter checks talk directly to dart:io otherwise, which
    // `httpClient` never could stand in for. Each defaults to the genuine
    // system call; only tests supply anything else.
    Future<List<NetworkInterface>> Function()? listInterfaces,
    Future<List<InternetAddress>> Function(String host)? lookupHost,
    Future<SecureSocket> Function(String host, int port, Duration timeout)?
        connectSecure,
  })  : _http = httpClient,
        _endpoint = endpoint,
        _listInterfaces =
            listInterfaces ?? (() => NetworkInterface.list(includeLoopback: false)),
        _lookupHost = lookupHost ?? ((host) => InternetAddress.lookup(host)),
        _connectSecure = connectSecure ??
            ((host, port, t) => SecureSocket.connect(host, port, timeout: t));

  final http.Client _http;
  final Uri _endpoint;
  final Future<List<NetworkInterface>> Function() _listInterfaces;
  final Future<List<InternetAddress>> Function(String host) _lookupHost;
  final Future<SecureSocket> Function(String host, int port, Duration timeout)
      _connectSecure;

  /// Per-layer timeout. Short enough that a dead layer does not leave the
  /// owner watching a spinner for the length of the whole chain.
  final Duration timeout;

  Future<ConnectionTestReport> run({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final layers = <LayerResult>[];

    final adapter = await _checkAdapter();
    layers.add(adapter);

    final dns = await _checkDns();
    layers.add(dns);

    final secure = await _checkSecureConnection();
    layers.add(secure);

    layers.add(_checkProxy());

    final github = await _checkGithub();
    layers.add(github);

    return ConnectionTestReport(
      at: at,
      layers: layers,
      summary: _summarise(layers),
    );
  }

  Future<LayerResult> _checkAdapter() async {
    try {
      final interfaces = await _listInterfaces().timeout(timeout);
      final up = interfaces.any((i) => i.addresses.isNotEmpty);
      return LayerResult(
        layer: ConnectivityLayer.adapter,
        label: 'Internet connection',
        passed: up,
        detail: up
            ? '${interfaces.length} active network '
                '${interfaces.length == 1 ? 'interface' : 'interfaces'}'
            : 'No active network interface found',
      );
    } catch (error) {
      return LayerResult(
        layer: ConnectivityLayer.adapter,
        label: 'Internet connection',
        passed: false,
        detail: 'Could not read network interfaces: $error',
      );
    }
  }

  Future<LayerResult> _checkDns() async {
    try {
      final addresses = await _lookupHost(_endpoint.host).timeout(timeout);
      return LayerResult(
        layer: ConnectivityLayer.dns,
        label: 'DNS',
        passed: addresses.isNotEmpty,
        detail: addresses.isEmpty
            ? 'Lookup returned no addresses'
            : '${_endpoint.host} → ${addresses.first.address}',
      );
    } catch (error) {
      return LayerResult(
        layer: ConnectivityLayer.dns,
        label: 'DNS',
        passed: false,
        detail: 'Could not resolve ${_endpoint.host}: $error',
      );
    }
  }

  Future<LayerResult> _checkSecureConnection() async {
    SecureSocket? socket;
    try {
      socket = await _connectSecure(_endpoint.host, 443, timeout);
      return LayerResult(
        layer: ConnectivityLayer.secureConnection,
        label: 'Secure connection',
        passed: true,
        detail: 'TLS ${socket.selectedProtocol ?? ''}'.trim(),
      );
    } catch (error) {
      final kind = classifyNetworkError(error);
      return LayerResult(
        layer: ConnectivityLayer.secureConnection,
        label: 'Secure connection',
        passed: false,
        detail: '($kind) $error',
      );
    } finally {
      socket?.destroy();
    }
  }

  /// Not a pass/fail layer off Windows — see [LayerResult.applicable].
  /// `resolveWindowsProxyForUrl` already no-ops there, so this simply reports
  /// that rather than pretending to have checked something.
  LayerResult _checkProxy() {
    if (!Platform.isWindows) {
      return const LayerResult(
        layer: ConnectivityLayer.proxy,
        label: 'Proxy',
        passed: true,
        applicable: false,
        detail: 'Not applicable outside Windows',
      );
    }

    final resolved = resolveWindowsProxyForUrl(_endpoint);
    return LayerResult(
      layer: ConnectivityLayer.proxy,
      label: 'Proxy',
      passed: true, // Informational: a proxy being configured is not itself
      // a failure. A failure to connect *through* one shows up
      // as the GitHub-service layer below, and its detail says so.
      detail: resolved == 'DIRECT'
          ? 'No proxy in use'
          : 'Routed through: $resolved',
    );
  }

  Future<LayerResult> _checkGithub() async {
    final started = DateTime.now();
    try {
      final response = await _http.get(_endpoint).timeout(timeout);
      final ok = response.statusCode == 200 || response.statusCode == 304;
      return LayerResult(
        layer: ConnectivityLayer.githubService,
        label: 'GitHub update service',
        passed: ok,
        detail: ok
            ? 'HTTP ${response.statusCode} in '
                '${DateTime.now().difference(started).inMilliseconds}ms'
            : 'HTTP ${response.statusCode}',
      );
    } catch (error) {
      final kind = classifyNetworkError(error);
      _log.info('Connection test: GitHub layer failed ($kind): $error');
      return LayerResult(
        layer: ConnectivityLayer.githubService,
        label: 'GitHub update service',
        passed: false,
        detail: '($kind) $error',
      );
    }
  }

  String _summarise(List<LayerResult> layers) {
    final failed = layers
        .where((l) => l.applicable && !l.passed)
        .map((l) => l.layer)
        .toSet();

    if (failed.isEmpty) {
      return 'This computer can reach GitHub normally.';
    }
    if (failed.contains(ConnectivityLayer.adapter)) {
      return 'This computer has no active network connection.';
    }
    if (failed.contains(ConnectivityLayer.dns)) {
      return "We couldn't find the update service. Your internet appears to "
          'be working, but this computer could not locate GitHub.';
    }
    if (failed.contains(ConnectivityLayer.secureConnection)) {
      return 'We reached the update service, but this computer could not '
          'establish a secure connection. This can be caused by antivirus '
          'software, Windows certificates, or network security settings.';
    }
    // Only the GitHub-service layer failed: adapter, DNS and TLS all passed.
    return 'GitHub could not be reached from this computer.';
  }
}
