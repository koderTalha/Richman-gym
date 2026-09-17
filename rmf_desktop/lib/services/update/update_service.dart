import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/audit_repository.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../domain/app_version.dart';
import '../backup_service.dart';
import 'connection_diagnostics.dart';
import 'update_cache.dart';
import 'windows_update_client.dart';

final _log = Logger('update');

/// Where releases are published. Public, so no token is involved and there is
/// no credential to leak in a desktop app the owner has on their own machine.
///
/// `releases/latest` rather than the tag list on purpose: GitHub defines it as
/// the newest release that is neither a draft nor a pre-release, so a tag
/// pushed by mistake or a release still being written is never what the gym's
/// computer is offered. The payload is checked again below in case that ever
/// stops being true.
const _releasesEndpoint =
    'https://api.github.com/repos/koderTalha/Richman-gym/releases/latest';

/// The only hosts an installer may be fetched from. GitHub redirects asset
/// downloads to its object store, so both are needed — and nothing else is.
const _allowedHosts = {
  'api.github.com',
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

/// Long enough for a slow gym connection, short enough that the app is not
/// waiting on GitHub while somebody wants to take a payment.
const _requestTimeout = Duration(seconds: 20);

/// How long a stalled download is tolerated before it is abandoned. This is an
/// idle timeout between chunks, not a limit on the whole 14MB.
const _downloadStallTimeout = Duration(minutes: 2);

/// After a check that could not be completed, how long before trying again
/// within the same session. Held in memory rather than in the database: the
/// interesting retry is the next time the app opens, which is exactly when the
/// connection that failed is most likely to be back.
const _retryInterval = Duration(minutes: 30);

/// Why a check could not answer the question. The message is for the owner;
/// this is for the code and the log.
///
/// Everything from [dnsFailure] through [unknownNetworkError] used to be one
/// kind — [offline] — because the request either answered or it did not.
/// That is what left the owner reading "No internet connection" on a machine
/// whose browser worked perfectly: a stale certificate, an antivirus
/// intercepting TLS, and a genuinely dead connection all throw before
/// `package:http` ever gets a status code to report, and collapsing them into
/// one message sent the owner to reset a router that was never the problem.
/// See [classifyNetworkError].
enum UpdateFailureKind {
  /// Not Windows: there is no installer this app could apply.
  unsupported,

  /// The installed version could not be read, so there is nothing to compare
  /// a release against.
  unknownCurrentVersion,

  /// This computer could not resolve github.com to an address. Distinct from
  /// [offline]: a router with no DNS configured, or a network that blocks the
  /// domain by name, still has a working connection to everywhere else.
  dnsFailure,

  /// A connection to GitHub was attempted and it did not answer within the
  /// time this app allows it.
  connectionTimeout,

  /// Something between this computer and GitHub actively refused the
  /// connection — a firewall or a proxy answering on the port and saying no,
  /// rather than the request going unanswered.
  connectionRefused,

  /// A connection reached GitHub but a secure channel could not be built on
  /// top of it. The common causes are outside this app entirely: a stale
  /// Windows root certificate store, or antivirus software intercepting TLS.
  /// Never treated as a reason to skip verification — see
  /// [UpdateService.install].
  tlsFailure,

  /// This network appears to route through a proxy, and the connection
  /// through it failed. Raised only by a platform client that actually
  /// resolved a proxy and tried it — see `WindowsUpdateClient`.
  proxyFailure,

  /// The strongest evidence available: the operating system reports no route
  /// to anywhere, which is what "no internet connection" is allowed to mean.
  offline,

  /// A network failure this app can see happened but cannot name more
  /// precisely than that.
  unknownNetworkError,

  /// GitHub's unauthenticated hourly limit is used up.
  rateLimited,

  /// The repository has no published release.
  noReleases,

  /// GitHub answered, but with an error.
  serverError,

  /// GitHub answered with something that is not the JSON this expects.
  malformedResponse,

  /// A release was found but cannot be used: a draft, a pre-release, a tag
  /// that is not a version, or missing its installer or checksum.
  unusableRelease,
}

/// Raised by a platform networking client — currently only the Windows one —
/// when it resolved a system proxy and the connection made through it is what
/// failed, as opposed to a failure reaching GitHub directly. Wrapping the
/// original error rather than discarding it keeps the real cause in the log.
class ProxyConnectionException implements Exception {
  const ProxyConnectionException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'ProxyConnectionException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}

/// Turns whatever `package:http` threw into a [UpdateFailureKind], so the
/// owner reads a specific cause instead of "offline" for everything that is
/// not an HTTP status code.
///
/// Reading `SocketException.message` and `.osError` for a substring is
/// inherently platform-dependent — the OS, not this app, writes those
/// strings — so this errs toward [UpdateFailureKind.unknownNetworkError] over
/// guessing. A wrong guess would put a misleading, over-specific message in
/// front of a non-technical owner; "could not check for updates" is honest
/// where "your DNS is broken" would not be.
UpdateFailureKind classifyNetworkError(Object error) {
  if (error is ProxyConnectionException) {
    return UpdateFailureKind.proxyFailure;
  }
  if (error is TimeoutException) {
    return UpdateFailureKind.connectionTimeout;
  }
  if (error is HandshakeException || error is CertificateException) {
    return UpdateFailureKind.tlsFailure;
  }
  if (error is SocketException) {
    return _classifySocketException(error);
  }
  return UpdateFailureKind.unknownNetworkError;
}

UpdateFailureKind _classifySocketException(SocketException error) {
  final text =
      '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
  bool has(List<String> needles) => needles.any(text.contains);

  // DNS resolution failing is the one Dart names almost identically on every
  // platform, which is what makes it safe to match on text at all.
  if (has(const [
    'failed host lookup',
    'nodename nor servname',
    'no address associated with hostname',
    'temporary failure in name resolution',
    'name or service not known',
  ])) {
    return UpdateFailureKind.dnsFailure;
  }
  if (has(const ['connection refused', 'actively refused'])) {
    return UpdateFailureKind.connectionRefused;
  }
  if (has(const ['timed out', 'timeout'])) {
    return UpdateFailureKind.connectionTimeout;
  }
  // The one pattern strong enough to call genuinely offline: the operating
  // system itself has nowhere to send the packet.
  if (has(const [
    'no route to host',
    'network is unreachable',
    'no route',
    'network unreachable',
  ])) {
    return UpdateFailureKind.offline;
  }
  return UpdateFailureKind.unknownNetworkError;
}

/// The line written to [UpdateCheckFailed.reason] for a network failure.
/// Technical enough for the log and the Settings diagnostics panel; the
/// friendlier copy a non-technical owner reads lives in `update_card.dart`
/// and `connection_status.dart`, keyed off [kind] rather than this string.
String _networkFailureReason(UpdateFailureKind kind) => switch (kind) {
      UpdateFailureKind.dnsFailure =>
        'Could not reach GitHub: this computer could not resolve '
            'github.com to an address.',
      UpdateFailureKind.connectionTimeout =>
        'Could not reach GitHub: the connection timed out.',
      UpdateFailureKind.connectionRefused =>
        'Could not reach GitHub: the connection was refused.',
      UpdateFailureKind.tlsFailure =>
        'Could not reach GitHub: a secure connection could not be '
            'established.',
      UpdateFailureKind.proxyFailure =>
        'Could not reach GitHub through this network\'s proxy.',
      _ => 'Could not reach GitHub to check for updates.',
    };

sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class AlreadyCurrent extends UpdateCheckResult {
  const AlreadyCurrent(this.current);
  final AppVersion current;
}

class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({
    required this.current,
    required this.version,
    required this.installerUrl,
    required this.checksumUrl,
    required this.sizeBytes,
    this.notes,
  });

  final AppVersion current;
  final AppVersion version;
  final Uri installerUrl;
  final Uri checksumUrl;
  final int sizeBytes;
  final String? notes;
}

/// The check could not be completed — usually the gym's connection.
///
/// Deliberately not an error the owner is shown on the dashboard: a till that
/// cannot reach GitHub is a till that works perfectly well. It is surfaced in
/// Settings, where somebody went looking for it, and in the log file always.
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(
    this.reason, {
    this.kind = UpdateFailureKind.serverError,
  });

  final String reason;
  final UpdateFailureKind kind;
}

sealed class UpdateInstallResult {
  const UpdateInstallResult();
}

/// The installer is verified and running; the app is about to close.
class UpdateLaunched extends UpdateInstallResult {
  const UpdateLaunched({required this.version, required this.installerPath});
  final AppVersion version;
  final String installerPath;
}

class UpdateInstallFailed extends UpdateInstallResult {
  const UpdateInstallFailed(this.message, {this.keptInstallerAt});

  /// Written for the owner.
  final String message;

  /// Set when a verified installer is on disk but could not be started, so the
  /// owner can run it by hand instead of being stuck.
  final String? keptInstallerAt;
}

/// Checks for, verifies and starts a new version of the app.
///
/// The order in [install] is the important part of this class:
///
///  1. Take a backup, and stop if it fails. The migration in a new release runs
///     before the app's own daily snapshot does, so this is the only copy that
///     predates it.
///  2. Download, then verify against the SHA-256 published with the release.
///     Nothing unverified is ever executed.
///  3. Start the installer detached and let the app exit. The installer is
///     per-user, so no administrator prompt appears on a machine where nobody
///     knows the administrator password.
///
/// Checking has one rule worth stating separately: **a check counts as done
/// only when GitHub actually answered the question.** An error, a rate limit or
/// a dropped connection leaves the once-a-day marker alone, so a bad minute
/// cannot silence the updater for the rest of the day.
class UpdateService {
  UpdateService({
    required this.db,
    required this.currentVersion,
    required this.audit,
    http.Client? httpClient,
    SettingsRepository? settings,
    BackupService? backups,
    Future<Directory> Function()? supportDirectory,
    Future<Process> Function(String executable, List<String> arguments)?
        startProcess,
    bool? windows,
  })  : _windows = windows ?? Platform.isWindows,
        // Windows routes through whatever proxy WinHTTP resolves for the
        // machine; every other platform is untouched. See
        // `windows_update_client.dart`.
        _http = httpClient ?? createUpdateHttpClient(),
        _settings = settings ?? SettingsRepository(db),
        _backups = backups ?? BackupService(db),
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _startProcess = startProcess ?? _detachedStart,
        _cache = UpdateCache(
          supportDirectory: supportDirectory ?? getApplicationSupportDirectory,
        );

  final AppDatabase db;

  /// What is actually installed, read from the executable rather than a
  /// constant somebody has to remember to edit. [AppVersion.unknown] when the
  /// platform would not say, which disables checking outright.
  final AppVersion currentVersion;

  final AuditRepository audit;
  final http.Client _http;
  final SettingsRepository _settings;
  final BackupService _backups;
  final Future<Directory> Function() _supportDirectory;
  final Future<Process> Function(String, List<String>) _startProcess;
  final UpdateCache _cache;

  /// When a check was last attempted in this process, successful or not. Only
  /// used to keep [isDueForCheck] from retrying a failure in a tight loop.
  DateTime? _lastAttemptAt;

  static Future<Process> _detachedStart(String exe, List<String> args) =>
      Process.start(exe, args, mode: ProcessStartMode.detached);

  /// Injectable so the rules can be tested from any machine; the tests run on
  /// whatever the developer has, and every path here would otherwise be dead
  /// code outside Windows.
  final bool _windows;

  /// Whether this copy can ask GitHub what has been released.
  ///
  /// Any platform can: it is an HTTPS GET against a public endpoint. Refusing
  /// to ask anywhere but Windows is what left the owner pressing a button that
  /// did nothing, and what made the whole feature impossible to try out
  /// anywhere except the gym's own machine.
  ///
  /// Still off when the installed version is unknown. There is no safe answer
  /// to "is this release newer" without a left-hand side, and this decides
  /// what to download and execute.
  bool get canCheck => currentVersion.isKnown;

  /// Whether an update found here could actually be applied.
  ///
  /// Windows only: the installer is an Inno Setup .exe. Elsewhere the release
  /// is still reported — knowing one is waiting is useful even where the app
  /// cannot install it — but [install] refuses.
  bool get canInstall => _windows && currentVersion.isKnown;

  /// Kept as the name the rest of the app already used for "can apply an
  /// update", which is what every existing caller meant by it.
  bool get isSupported => canInstall;

  /// Whether enough time has passed to look again.
  ///
  /// Once a day, because the gym's computer is opened each morning: an update
  /// lands within a day of release without a working session ever being
  /// interrupted by a network call. A check that failed does not count as a
  /// check — see [_recordChecked] — so the next launch tries again.
  Future<bool> isDueForCheck({DateTime? now}) async {
    if (!canCheck) return false;

    final at = now ?? DateTime.now();

    // A failure inside this session is not retried immediately. Without this, a
    // screen that rebuilds while GitHub is down would ask again on every build.
    final attempt = _lastAttemptAt;
    if (attempt != null && at.difference(attempt) < _retryInterval) {
      return false;
    }

    final settings = await _settings.get();
    final last = settings.lastUpdateCheckAt;
    if (last == null) return true;

    final lastLocal = last.toLocal();
    return !(lastLocal.year == at.year &&
        lastLocal.month == at.month &&
        lastLocal.day == at.day);
  }

  /// When GitHub last actually answered, on the local clock. Null when it
  /// never has — which is itself worth showing, since it separates "checked
  /// and found nothing" from "never managed to ask".
  Future<DateTime?> lastCheckedAt() async =>
      (await _settings.get()).lastUpdateCheckAt?.toLocal();

  /// The endpoint being asked, so the diagnostics panel can name it rather
  /// than leaving the owner guessing which repository this copy watches.
  String get releasesEndpoint => _releasesEndpoint;

  /// Runs the layered "Test Connection" diagnostic against the same host and
  /// the same HTTP client [check] uses — Windows proxy routing included — so
  /// a pass here is a genuine promise that [check] would also succeed.
  ///
  /// Unlike [check], this makes a real TCP connection and TLS handshake of
  /// its own to tell those two layers apart, which is worth the extra moment
  /// only because a human pressed a button and is waiting for the answer. See
  /// `connection_diagnostics.dart`.
  Future<ConnectionTestReport> testConnection() => ConnectionDiagnostics(
        httpClient: _http,
        endpoint: Uri.parse(_releasesEndpoint),
      ).run();

  /// The version the owner chose to skip, if any.
  Future<AppVersion?> dismissedVersion() async =>
      AppVersion.tryParse((await _settings.get()).dismissedUpdateVersion);

  Future<void> dismiss(AppVersion version) => _settings.update(
        GymSettingsCompanion(dismissedUpdateVersion: Value(version.toString())),
      );

  /// What the last completed check found, read from disk without touching the
  /// network. Null when nothing has ever been cached.
  ///
  /// This is what keeps a waiting update on screen across a restart: the daily
  /// interval stops the request, not the answer.
  Future<UpdateCheckResult?> lastKnownResult() async {
    if (!canCheck) return null;

    final cached = await _cache.read();
    if (cached == null) return null;

    final decoded = _decode(cached.body);
    if (decoded == null) return null;

    return _interpret(decoded, recordAudit: false);
  }

  /// Asks GitHub for the latest release. Never throws.
  Future<UpdateCheckResult> check({DateTime? now}) async {
    // Deliberately not gated on Windows. Finding out what has been released is
    // useful everywhere, and [install] is where the platform actually matters.
    if (!currentVersion.isKnown) {
      _log.severe('Update check skipped: the installed version is unknown, so '
          'there is nothing to compare a release against.');
      return const UpdateCheckFailed(
        'The installed version could not be read, so updates cannot be '
        'checked.',
        kind: UpdateFailureKind.unknownCurrentVersion,
      );
    }

    final at = now ?? DateTime.now();
    _lastAttemptAt = at;

    // The ETag is only sent when the payload it belongs to can still be read.
    // Otherwise a cache file that went bad would answer 304 forever and there
    // would be nothing to interpret; asking unconditionally replaces it.
    final cached = await _cache.read();
    final cachedRelease = cached == null ? null : _decode(cached.body);
    final etag = cachedRelease == null ? null : cached!.etag;

    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse(_releasesEndpoint),
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          // Costs nothing and, when it answers 304, costs no rate limit
          // either — GitHub does not charge a conditional request that found
          // nothing new. Omitted entirely when there is no ETag to send.
          'If-None-Match': ?etag,
        },
      ).timeout(_requestTimeout);
    } catch (error, stack) {
      // An offline till is not a broken till — and, as often as not, it is
      // not even offline. See [classifyNetworkError].
      final kind = classifyNetworkError(error);
      _log.info('Update check could not be completed ($kind): $error');
      _log.finer('Update check stack', error, stack);
      return UpdateCheckFailed(_networkFailureReason(kind), kind: kind);
    }

    // Nothing has been released since the copy already on disk.
    if (response.statusCode == 304 && cachedRelease != null) {
      _log.fine('GitHub reports no new release since the cached one.');
      await _recordChecked(at);
      return _interpret(cachedRelease, recordAudit: true);
    }

    if (response.statusCode != 200) {
      return _failureFor(response);
    }

    final decoded = _decode(response.body);
    if (decoded == null) {
      _log.warning('GitHub answered with something that is not a release: '
          '${_snippet(response.body)}');
      return const UpdateCheckFailed(
        'GitHub answered with something this app could not read.',
        kind: UpdateFailureKind.malformedResponse,
      );
    }

    // Only a genuine answer is cached and only a genuine answer counts as
    // today's check.
    await _cache.write(
      body: response.body,
      etag: response.headers['etag'],
      at: at,
    );
    await _recordChecked(at);

    return _interpret(decoded, recordAudit: true);
  }

  /// Turns a `releases/latest` payload into an answer.
  ///
  /// Every refusal here is a release that exists but must not be installed, and
  /// each one says which so the log can be read afterwards.
  Future<UpdateCheckResult> _interpret(
    Map<String, dynamic> body, {
    required bool recordAudit,
  }) async {
    // The endpoint already excludes these; checked anyway because the cost of
    // being wrong is running a half-finished build on the gym's computer.
    if (body['draft'] == true) {
      _log.info('The latest release on GitHub is still a draft; ignoring it.');
      return const UpdateCheckFailed(
        'The newest release on GitHub is still a draft.',
        kind: UpdateFailureKind.unusableRelease,
      );
    }
    if (body['prerelease'] == true) {
      _log.info('The latest release on GitHub is a pre-release; ignoring it.');
      return const UpdateCheckFailed(
        'The newest release on GitHub is a pre-release, so it was not '
        'offered.',
        kind: UpdateFailureKind.unusableRelease,
      );
    }

    final tag = body['tag_name'];
    final version = AppVersion.tryParse(tag is String ? tag : null);
    if (version == null) {
      _log.warning('Release tag "$tag" is not a version this app recognises.');
      return const UpdateCheckFailed(
        'The latest release is not tagged with a version this app recognises.',
        kind: UpdateFailureKind.unusableRelease,
      );
    }

    if (!version.isNewerThan(currentVersion)) {
      _log.fine('Up to date: installed $currentVersion, latest $version.');
      return AlreadyCurrent(currentVersion);
    }

    final assets = (body['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final installer = _asset(assets, 'RichManFitness-Setup-$version.exe');
    final checksum = _asset(assets, 'RichManFitness-Setup-$version.exe.sha256');

    if (installer == null) {
      _log.warning('Release $version has no installer attached; '
          'assets are ${assets.map((a) => a['name']).toList()}');
      return UpdateCheckFailed(
        'Release $version has no installer attached yet.',
        kind: UpdateFailureKind.unusableRelease,
      );
    }
    // No checksum, no update. Without one there is nothing to verify a
    // downloaded executable against, and this app will not run one blind.
    if (checksum == null) {
      _log.warning('Release $version has no checksum published; '
          'it will not be offered.');
      return UpdateCheckFailed(
        'Release $version has no checksum published, so it cannot be '
        'verified.',
        kind: UpdateFailureKind.unusableRelease,
      );
    }

    final installerUrl = _safeUri(installer['browser_download_url']);
    final checksumUrl = _safeUri(checksum['browser_download_url']);
    if (installerUrl == null || checksumUrl == null) {
      _log.severe('Release $version points somewhere this app will not follow; '
          'nothing was downloaded.');
      return UpdateCheckFailed(
        'Release $version points somewhere unexpected and was ignored.',
        kind: UpdateFailureKind.unusableRelease,
      );
    }

    _log.info('Version $version is available (this copy is $currentVersion).');

    if (recordAudit) {
      await audit.record(
        category: AuditCategory.update,
        action: AuditAction.updateAvailable,
        outcome: AuditOutcome.success,
        summary: 'Version $version is available '
            '(this copy is $currentVersion)',
      );
    }

    return UpdateAvailable(
      current: currentVersion,
      version: version,
      installerUrl: installerUrl,
      checksumUrl: checksumUrl,
      sizeBytes: (installer['size'] as num?)?.toInt() ?? 0,
      notes: (body['body'] as String?)?.trim(),
    );
  }

  /// Reads a non-200 answer, separating the cases that mean different things.
  ///
  /// None of these record today's check: the question was never answered, and
  /// marking it as asked would mean waiting until tomorrow to find out.
  UpdateCheckFailed _failureFor(http.Response response) {
    final code = response.statusCode;
    final remaining = response.headers['x-ratelimit-remaining'];

    if ((code == 403 || code == 429) && remaining == '0') {
      final resets = _rateLimitReset(response);
      _log.warning('GitHub rate limit reached (HTTP $code)'
          '${resets == null ? '' : ', resets at ${resets.toLocal()}'}. '
          'No token is used, so the limit is per network address.');
      return UpdateCheckFailed(
        'GitHub is rate limiting update checks from this network'
        '${resets == null ? '' : ' until ${_clock(resets.toLocal())}'}. '
        'The app will try again later.',
        kind: UpdateFailureKind.rateLimited,
      );
    }

    if (code == 404) {
      _log.warning('GitHub has no published release to compare against '
          '(HTTP 404 from $_releasesEndpoint).');
      return const UpdateCheckFailed(
        'GitHub has no published release for this app yet (HTTP 404).',
        kind: UpdateFailureKind.noReleases,
      );
    }

    _log.warning('GitHub answered HTTP $code when asked for the latest '
        'release: ${_snippet(response.body)}');
    return UpdateCheckFailed(
      'GitHub answered HTTP $code.',
      kind: UpdateFailureKind.serverError,
    );
  }

  /// Marks today as checked. Only ever called when GitHub answered.
  Future<void> _recordChecked(DateTime at) =>
      _settings.update(GymSettingsCompanion(
        lastUpdateCheckAt: Value(at.toUtc()),
      ));

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static DateTime? _rateLimitReset(http.Response response) {
    final seconds = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  /// A short, safe excerpt of a response body for the log. GitHub's error
  /// bodies are public JSON, but truncating keeps a stray HTML error page from
  /// filling the owner's log file.
  static String _snippet(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 200 ? flat : '${flat.substring(0, 200)}…';
  }

  /// Backs up, downloads, verifies, then starts the installer.
  Future<UpdateInstallResult> install(
    UpdateAvailable update, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!canInstall) {
      return const UpdateInstallFailed(
        'Updates can only be installed on Windows.',
      );
    }

    // --- 1. A copy that predates the new version's migration --------------
    try {
      final result =
          await _backups.backupTo(await _backups.automaticBackupDirectory());
      _log.info('Pre-update backup written to ${result.folder.path}');
    } catch (error, stack) {
      _log.severe('Pre-update backup failed; update abandoned', error, stack);
      await audit.record(
        category: AuditCategory.update,
        action: AuditAction.updateBackupFailed,
        outcome: AuditOutcome.failed,
        summary: 'Update to ${update.version} stopped: the backup failed',
        detail: ['Nothing was installed. The current version is untouched.'],
      );
      return const UpdateInstallFailed(
        'A backup could not be taken, so the update was not installed. '
        'Nothing has changed.',
      );
    }

    // --- 2. Download and verify -------------------------------------------
    final File file;
    try {
      file = await _download(update, onProgress: onProgress);
    } catch (error, stack) {
      _log.severe('Downloading the update failed', error, stack);
      return const UpdateInstallFailed(
        'The update could not be downloaded. Check the connection and try '
        'again.',
      );
    }

    final String expected;
    try {
      expected = await _expectedChecksum(update.checksumUrl);
    } catch (error, stack) {
      _log.severe('Fetching the update checksum failed', error, stack);
      await file.delete();
      return const UpdateInstallFailed(
        'The update could not be verified, so it was not installed.',
      );
    }

    final actual = sha256.convert(await file.readAsBytes()).toString();
    if (actual.toLowerCase() != expected.toLowerCase()) {
      await file.delete();
      _log.severe('Update checksum mismatch: expected $expected, got $actual');
      await audit.record(
        category: AuditCategory.update,
        action: AuditAction.updateVerifyFailed,
        outcome: AuditOutcome.failed,
        summary: 'Update to ${update.version} refused: the download did not '
            'match its checksum',
        detail: const [
          'The downloaded file was deleted and nothing was installed.',
        ],
      );
      return const UpdateInstallFailed(
        'The downloaded update did not match its published checksum, so it '
        'was discarded. Nothing has changed.',
      );
    }

    // --- 3. Hand over to the installer ------------------------------------
    await audit.record(
      category: AuditCategory.update,
      action: AuditAction.updateInstalling,
      outcome: AuditOutcome.success,
      summary: 'Installing version ${update.version}',
      detail: [
        'Verified SHA-256 $actual',
        'The app will close and reopen on the new version.',
      ],
    );

    try {
      // Silent, no reboot, and per-user — so nothing prompts for an
      // administrator password on the gym's machine.
      await _startProcess(file.path, const ['/VERYSILENT', '/NORESTART']);
    } catch (error, stack) {
      _log.severe('The installer could not be started', error, stack);
      return UpdateInstallFailed(
        'The update was downloaded and verified but could not be started. '
        'It can be run by hand from ${file.path}.',
        keptInstallerAt: file.path,
      );
    }

    return UpdateLaunched(version: update.version, installerPath: file.path);
  }

  Future<File> _download(
    UpdateAvailable update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = Directory(p.join((await _supportDirectory()).path, 'updates'));
    await dir.create(recursive: true);

    // One file per version, replaced rather than accumulated: a half-finished
    // download from last week must never be the thing that gets run.
    final file = File(p.join(dir.path, 'RichManFitness-Setup-${update.version}.exe'));
    if (await file.exists()) await file.delete();

    final request = http.Request('GET', update.installerUrl);
    final response = await _http.send(request).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: update.installerUrl);
    }

    final total = response.contentLength ?? update.sizeBytes;
    final sink = file.openWrite();
    var received = 0;
    try {
      // An idle timeout, not a deadline: a 14MB installer on a slow line is
      // fine, a connection that stops sending is not.
      await response.stream.timeout(_downloadStallTimeout).forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      });
    } finally {
      await sink.close();
    }

    return file;
  }

  Future<String> _expectedChecksum(Uri url) async {
    final response = await _http.get(url).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    // Accepts both a bare digest and the "<digest>  <filename>" form sha256sum
    // and PowerShell produce.
    final first = response.body.trim().split(RegExp(r'\s+')).first;
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(first)) {
      throw const FormatException('The published checksum is not a SHA-256');
    }
    return first;
  }

  static Map<String, dynamic>? _asset(
    List<Map<String, dynamic>> assets,
    String name,
  ) {
    for (final asset in assets) {
      if (asset['name'] == name) return asset;
    }
    return null;
  }

  /// HTTPS, and a host on the allow-list. This URL becomes an executable that
  /// runs on the gym's computer, so a release edited to point elsewhere must
  /// not be followed.
  static Uri? _safeUri(Object? raw) {
    if (raw is! String) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.scheme != 'https') return null;
    if (!_allowedHosts.contains(uri.host)) return null;
    return uri;
  }
}
