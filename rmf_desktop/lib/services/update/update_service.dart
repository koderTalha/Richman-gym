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

final _log = Logger('update');

/// Where releases are published. Public, so no token is involved and there is
/// no credential to leak in a desktop app the owner has on their own machine.
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
/// Deliberately not an error the owner is shown: a till that cannot reach
/// GitHub is a till that works perfectly well.
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.reason);
  final String reason;
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
        _http = httpClient ?? http.Client(),
        _settings = settings ?? SettingsRepository(db),
        _backups = backups ?? BackupService(db),
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _startProcess = startProcess ?? _detachedStart;

  final AppDatabase db;

  /// What is actually installed, read from the executable rather than a
  /// constant somebody has to remember to edit.
  final AppVersion currentVersion;

  final AuditRepository audit;
  final http.Client _http;
  final SettingsRepository _settings;
  final BackupService _backups;
  final Future<Directory> Function() _supportDirectory;
  final Future<Process> Function(String, List<String>) _startProcess;

  static Future<Process> _detachedStart(String exe, List<String> args) =>
      Process.start(exe, args, mode: ProcessStartMode.detached);

  /// Injectable so the rules can be tested from any machine; the tests run on
  /// whatever the developer has, and every path here would otherwise be dead
  /// code outside Windows.
  final bool _windows;

  /// Only updates on Windows. The gym runs Windows; the installer is an Inno
  /// Setup .exe, and offering an update it cannot apply would be worse than
  /// offering none.
  bool get isSupported => _windows;

  /// Whether enough time has passed to look again.
  ///
  /// Once a day, because the gym's computer is opened each morning: an update
  /// lands within a day of release without a working session ever being
  /// interrupted by a network call.
  Future<bool> isDueForCheck({DateTime? now}) async {
    if (!isSupported) return false;

    final settings = await _settings.get();
    final last = settings.lastUpdateCheckAt;
    if (last == null) return true;

    final at = now ?? DateTime.now();
    final lastLocal = last.toLocal();
    return !(lastLocal.year == at.year &&
        lastLocal.month == at.month &&
        lastLocal.day == at.day);
  }

  /// The version the owner chose to skip, if any.
  Future<AppVersion?> dismissedVersion() async =>
      AppVersion.tryParse((await _settings.get()).dismissedUpdateVersion);

  Future<void> dismiss(AppVersion version) => _settings.update(
        GymSettingsCompanion(dismissedUpdateVersion: Value(version.toString())),
      );

  /// Asks GitHub for the latest release. Never throws.
  Future<UpdateCheckResult> check({DateTime? now}) async {
    if (!isSupported) {
      return UpdateCheckFailed('Updates are only available on Windows.');
    }

    try {
      final response = await _http.get(
        Uri.parse(_releasesEndpoint),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 20));

      // Recorded even when nothing new is found, so the daily check does not
      // hammer GitHub after a failure loop.
      await _settings.update(GymSettingsCompanion(
        lastUpdateCheckAt: Value((now ?? DateTime.now()).toUtc()),
      ));

      if (response.statusCode != 200) {
        return UpdateCheckFailed(
            'GitHub answered HTTP ${response.statusCode}.');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final version = AppVersion.tryParse(body['tag_name'] as String?);
      if (version == null) {
        return UpdateCheckFailed(
            'The latest release is not tagged with a version this app '
            'recognises.');
      }

      if (!version.isNewerThan(currentVersion)) {
        return AlreadyCurrent(currentVersion);
      }

      final assets = (body['assets'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      final installer = _asset(assets, 'RichManFitness-Setup-$version.exe');
      final checksum = _asset(assets, 'RichManFitness-Setup-$version.exe.sha256');

      if (installer == null) {
        return UpdateCheckFailed(
            'Release $version has no installer attached yet.');
      }
      // No checksum, no update. Without one there is nothing to verify a
      // downloaded executable against, and this app will not run one blind.
      if (checksum == null) {
        return UpdateCheckFailed(
            'Release $version has no checksum published, so it cannot be '
            'verified.');
      }

      final installerUrl = _safeUri(installer['browser_download_url']);
      final checksumUrl = _safeUri(checksum['browser_download_url']);
      if (installerUrl == null || checksumUrl == null) {
        return UpdateCheckFailed(
            'Release $version points somewhere unexpected and was ignored.');
      }

      await audit.record(
        category: AuditCategory.update,
        action: AuditAction.updateAvailable,
        outcome: AuditOutcome.success,
        summary: 'Version $version is available '
            '(this copy is $currentVersion)',
      );

      return UpdateAvailable(
        current: currentVersion,
        version: version,
        installerUrl: installerUrl,
        checksumUrl: checksumUrl,
        sizeBytes: (installer['size'] as num?)?.toInt() ?? 0,
        notes: (body['body'] as String?)?.trim(),
      );
    } catch (error, stack) {
      // An offline till is not a broken till.
      _log.info('Update check could not be completed: $error');
      _log.finer('Update check stack', error, stack);
      return const UpdateCheckFailed(
          'Could not reach GitHub to check for updates.');
    }
  }

  /// Backs up, downloads, verifies, then starts the installer.
  Future<UpdateInstallResult> install(
    UpdateAvailable update, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!isSupported) {
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
    final response = await _http.send(request);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: update.installerUrl);
    }

    final total = response.contentLength ?? update.sizeBytes;
    final sink = file.openWrite();
    var received = 0;
    try {
      await response.stream.forEach((chunk) {
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
    final response = await _http.get(url).timeout(const Duration(seconds: 20));
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
