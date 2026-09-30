import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database.dart';
import '../update/update_service.dart';
import '../update/windows_update_client.dart';
import 'developer_key.dart';
import 'diagnostics_crypto.dart';

final _log = Logger('diagnostics');

/// The Apps Script web app bundles are posted to. Supplied at build time —
/// `--dart-define=DIAGNOSTICS_UPLOAD_URL=…`, from a GitHub Actions secret —
/// because this repository is public and the address has no business in it.
/// A build made without it cannot send, and says so rather than failing
/// somewhere less obvious. See `docs/diagnostics/SETUP.md`.
const _configuredEndpoint = String.fromEnvironment('DIAGNOSTICS_UPLOAD_URL');

/// Everything past a ~20MB day of logs is a runaway error loop, and sending
/// it would only make the upload fail on a slow gym connection.
const _maxLogBytes = 20 * 1024 * 1024;

/// A few megabytes over a slow line. Generous, because the owner is waiting on
/// purpose here, not in the middle of taking a payment.
const _uploadTimeout = Duration(minutes: 2);
const _replyTimeout = Duration(seconds: 30);

/// Writes the database files to send into the scratch folder and returns them.
typedef DatabaseSnapshot = Future<List<File>> Function(Directory scratch);

/// The snapshot for a running app: `VACUUM INTO`, which gives a consistent
/// copy even while the database is open, exactly as a backup does.
DatabaseSnapshot vacuumSnapshot(AppDatabase db) => (scratch) async {
      final target = File(p.join(scratch.path, 'richmanfitness.sqlite'));
      final escaped = target.path.replaceAll("'", "''");
      await db.customStatement("VACUUM INTO '$escaped'");
      return [target];
    };

/// The snapshot for when the database would not open at all. There is no
/// connection to VACUUM through, so the files are copied as they lie — the
/// write-ahead log too, since SQLite replays it when the copy is opened beside
/// it and that is where the most recent writes may be.
DatabaseSnapshot rawFileSnapshot(File live) => (scratch) async {
      final copied = <File>[];
      for (final suffix in ['', '-wal']) {
        final source = File('${live.path}$suffix');
        if (!await source.exists()) continue;
        final target = File(p.join(scratch.path, p.basename(source.path)));
        // Bytes rather than File.copy, which carries the source's permissions.
        await target.writeAsBytes(await source.readAsBytes());
        copied.add(target);
      }
      return copied;
    };

sealed class DiagnosticsResult {
  const DiagnosticsResult();
}

class DiagnosticsSent extends DiagnosticsResult {
  const DiagnosticsSent({required this.reference, required this.bytes});

  /// What the owner reads out over the phone, and the name of the file in the
  /// developer's Drive, so both are talking about the same send.
  final String reference;
  final int bytes;
}

class DiagnosticsFailed extends DiagnosticsResult {
  const DiagnosticsFailed(this.message);

  /// For the owner, in plain words.
  final String message;
}

class _UploadRefused implements Exception {
  const _UploadRefused(this.message);
  final String message;
}

/// "Send to developer": a copy of the gym's data and the app's logs, sealed so
/// only the developer can read it, posted to a Google Apps Script that files
/// it in the developer's Drive and emails them.
///
/// It replaces driving to the gym to copy a backup off the machine by hand.
/// Nothing is kept on this computer afterwards: the snapshot is made in a
/// scratch folder that is removed whether or not the send worked.
class SendToDeveloper {
  SendToDeveloper({
    required DatabaseSnapshot snapshot,
    required Future<Directory> Function() supportDirectory,
    required Uri? endpoint,
    required List<int> developerPublicKey,
    required Future<String> Function() appVersion,
    required Future<String?> Function() gymName,
    http.Client? httpClient,
    DateTime Function()? clock,
  })  : _snapshot = snapshot,
        _supportDirectory = supportDirectory,
        _endpoint = endpoint,
        _developerPublicKey = developerPublicKey,
        _appVersion = appVersion,
        _gymName = gymName,
        _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  /// The one the app uses: this build's upload address, the developer's key
  /// and the same proxy-aware client the updater talks to GitHub through.
  factory SendToDeveloper.installed({
    required DatabaseSnapshot snapshot,
    required Future<String?> Function() gymName,
  }) =>
      SendToDeveloper(
        snapshot: snapshot,
        supportDirectory: getApplicationSupportDirectory,
        endpoint: configuredEndpoint,
        developerPublicKey: base64Decode(developerPublicKeyBase64),
        appVersion: () async => (await PackageInfo.fromPlatform()).version,
        gymName: gymName,
        httpClient: createUpdateHttpClient(),
      );

  static Uri? get configuredEndpoint => _configuredEndpoint.isEmpty
      ? null
      : Uri.tryParse(_configuredEndpoint.trim());

  final DatabaseSnapshot _snapshot;
  final Future<Directory> Function() _supportDirectory;
  final Uri? _endpoint;
  final List<int> _developerPublicKey;
  final Future<String> Function() _appVersion;
  final Future<String?> Function() _gymName;
  final http.Client _http;
  final DateTime Function() _clock;

  bool get isConfigured => _endpoint != null;

  /// Never throws: every failure comes back as a [DiagnosticsFailed] the
  /// owner can read, and the detail goes to the log.
  ///
  /// [source] and [startupError] tell the developer where it was sent from —
  /// Settings, or the screen shown when the database would not open.
  Future<DiagnosticsResult> send({
    required String note,
    String source = 'settings',
    String? startupError,
  }) async {
    final endpoint = _endpoint;
    if (endpoint == null) {
      return const DiagnosticsFailed(
          'This copy of the app was built without the developer\'s upload '
          'address, so it cannot send. Use "Back up now" and send the folder '
          'instead.');
    }

    final at = _clock();
    final reference = _reference(at);

    final Uint8List sealed;
    final String version;
    final String? gym;
    try {
      version = await _appVersion();
      gym = await _safeGymName();
      final bundle = await _buildBundle(
        reference: reference,
        at: at,
        version: version,
        gym: gym,
        note: note,
        source: source,
        startupError: startupError,
      );
      sealed = await sealDiagnostics(bundle, _developerPublicKey);
    } catch (error, stack) {
      _log.severe('The diagnostics bundle could not be prepared', error, stack);
      return DiagnosticsFailed('The copy could not be prepared: $error');
    }

    try {
      await _upload(
        endpoint,
        name: '$reference.rmfdiag',
        gym: gym ?? 'Unknown gym',
        version: version,
        sealed: sealed,
      );
    } on _UploadRefused catch (refused) {
      _log.severe('Diagnostics $reference not accepted: ${refused.message}');
      return DiagnosticsFailed(refused.message);
    } catch (error, stack) {
      _log.severe('Diagnostics $reference could not be sent', error, stack);
      return DiagnosticsFailed(_networkMessage(classifyNetworkError(error)));
    }

    _log.info('Diagnostics $reference sent (${sealed.length} bytes)');
    return DiagnosticsSent(reference: reference, bytes: sealed.length);
  }

  /// The gym's name comes out of the database, which is the thing that may be
  /// broken. Not knowing it must not stop the send.
  Future<String?> _safeGymName() async {
    try {
      return await _gymName();
    } catch (error) {
      _log.warning('Gym name unavailable for diagnostics', error);
      return null;
    }
  }

  Future<Uint8List> _buildBundle({
    required String reference,
    required DateTime at,
    required String version,
    required String? gym,
    required String note,
    required String source,
    required String? startupError,
  }) async {
    final support = await _supportDirectory();
    final scratch = await Directory(p.join(support.path, 'diagnostics-tmp'))
        .create(recursive: true);

    try {
      // A leftover from a send that died half way must not be packed again.
      await for (final stale in scratch.list()) {
        await stale.delete(recursive: true);
      }

      final archive = Archive();
      void add(String name, List<int> bytes) =>
          archive.addFile(ArchiveFile(name, bytes.length, bytes));

      final databaseFiles = <String>[];
      for (final file in await _snapshot(scratch)) {
        final name = 'database/${p.basename(file.path)}';
        add(name, await file.readAsBytes());
        databaseFiles.add(name);
      }

      final (logFiles, logsLeftOut) =
          await _addLogs(Directory(p.join(support.path, 'logs')), add);

      final info = <String, Object?>{
        'format': 'rmf-diagnostics-1',
        'reference': reference,
        'sentAt': at.toIso8601String(),
        'appVersion': version,
        'gymName': gym,
        'source': source,
        'note': note,
        'startupError': startupError,
        'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'databaseFiles': databaseFiles,
        'logFiles': logFiles,
        'logsLeftOut': logsLeftOut,
      };
      add('info.json',
          utf8.encode(const JsonEncoder.withIndent('  ').convert(info)));

      return Uint8List.fromList(ZipEncoder().encode(archive)!);
    } finally {
      try {
        await scratch.delete(recursive: true);
      } catch (error) {
        _log.warning('Diagnostics scratch folder not removed', error);
      }
    }
  }

  /// Newest day first, so what is dropped under the cap is the oldest.
  Future<(List<String>, List<String>)> _addLogs(
      Directory logs, void Function(String, List<int>) add) async {
    final included = <String>[];
    final leftOut = <String>[];
    if (!await logs.exists()) return (included, leftOut);

    final files = await logs
        .list()
        .where((e) => e is File && RegExp(r'^app-.*\.log$')
            .hasMatch(p.basename(e.path)))
        .cast<File>()
        .toList();
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));

    var total = 0;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final name = 'logs/${p.basename(file.path)}';
      if (total + bytes.length > _maxLogBytes) {
        leftOut.add(name);
        continue;
      }
      total += bytes.length;
      add(name, bytes);
      included.add(name);
    }
    return (included, leftOut);
  }

  /// Posts the bundle and reads the script's answer.
  ///
  /// An Apps Script web app runs the POST, then answers it with a redirect to
  /// a second address holding the reply. `dart:io` will not follow a redirect
  /// from a POST, so it is followed here by hand — and it has to be, because
  /// the reply is the only proof the file was actually filed.
  Future<void> _upload(
    Uri endpoint, {
    required String name,
    required String gym,
    required String version,
    required Uint8List sealed,
  }) async {
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers['content-type'] = 'text/plain; charset=utf-8'
      // Base64 in JSON because an Apps Script only ever sees a POST body as
      // text; raw bytes would not survive the trip.
      ..body = jsonEncode({
        'format': 'rmf-diagnostics-1',
        'name': name,
        'gym': gym,
        'version': version,
        'data': base64Encode(sealed),
      });

    var response = await http.Response.fromStream(
        await _http.send(request).timeout(_uploadTimeout));

    if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
      final location = response.headers['location'];
      if (location == null) {
        throw const _UploadRefused(
            'Google answered without saying where the reply was.');
      }
      response =
          await _http.get(endpoint.resolve(location)).timeout(_replyTimeout);
    }

    if (response.statusCode != 200) {
      throw _UploadRefused('Google answered with an error '
          '(HTTP ${response.statusCode}). Try again in a few minutes.');
    }

    final Object? reply;
    try {
      reply = jsonDecode(response.body);
    } on FormatException {
      // A sign-in page, most often: the web app was deployed for the
      // developer's account only instead of for anyone with the link.
      throw const _UploadRefused(
          'The developer\'s upload page did not accept the file. Its '
          'deployment must give access to "Anyone".');
    }

    if (reply is! Map || reply['ok'] != true) {
      final reason = reply is Map ? reply['error'] : null;
      throw _UploadRefused('The developer\'s upload page refused the file'
          '${reason == null ? '.' : ': $reason'}');
    }
  }

  static String _reference(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'RMF-${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}';
  }

  static String _networkMessage(UpdateFailureKind kind) => switch (kind) {
        UpdateFailureKind.dnsFailure || UpdateFailureKind.offline =>
          'Could not reach Google. Check this computer is connected to the '
              'internet, then try again.',
        UpdateFailureKind.connectionTimeout =>
          'Google did not answer in time. The connection may be slow — try '
              'again in a minute.',
        UpdateFailureKind.tlsFailure =>
          'A secure connection to Google could not be made. Antivirus '
              'software, or a wrong date and time on this computer, is the '
              'usual cause.',
        UpdateFailureKind.proxyFailure =>
          'Could not reach Google through this network\'s proxy.',
        UpdateFailureKind.connectionRefused =>
          'The connection to Google was refused, probably by a firewall.',
        _ => 'Could not reach Google to send the file. Check the internet '
            'connection and try again.',
      };
}
