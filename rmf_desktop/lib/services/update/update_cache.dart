import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _log = Logger('update');

/// The last answer GitHub gave, kept on disk beside the app's other data.
///
/// It exists for two reasons, both of which are about not asking GitHub again:
///
///  * **The banner has to survive a restart.** Checking once a day used to mean
///    the result was known for exactly one launch: reopen the app an hour later
///    and the check was skipped as "already done today", the state fell back to
///    idle, and a waiting update simply vanished until tomorrow.
///  * **A conditional request is free.** Sending the stored ETag back as
///    `If-None-Match` gets a 304 when nothing has been released, and GitHub
///    does not count a 304 against the hourly rate limit.
///
/// Every failure here is swallowed and logged. A cache that cannot be read or
/// written must cost nothing more than an extra request.
class UpdateCache {
  UpdateCache({required Future<Directory> Function() supportDirectory})
      : _supportDirectory = supportDirectory;

  final Future<Directory> Function() _supportDirectory;

  static const _fileName = 'update_check.json';

  Future<File> _file() async =>
      File(p.join((await _supportDirectory()).path, _fileName));

  Future<CachedRelease?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;

      final stored = jsonDecode(await file.readAsString());
      if (stored is! Map<String, dynamic>) return null;

      final body = stored['body'];
      if (body is! String || body.isEmpty) return null;

      return CachedRelease(
        body: body,
        etag: stored['etag'] as String?,
        storedAt: DateTime.tryParse(stored['storedAt'] as String? ?? ''),
      );
    } catch (error, stack) {
      _log.info('The cached release could not be read: $error');
      _log.finer('Update cache read', error, stack);
      return null;
    }
  }

  Future<void> write({required String body, String? etag, DateTime? at}) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'etag': etag,
        'storedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
        'body': body,
      }));
    } catch (error, stack) {
      _log.info('The release could not be cached: $error');
      _log.finer('Update cache write', error, stack);
    }
  }
}

class CachedRelease {
  const CachedRelease({required this.body, this.etag, this.storedAt});

  /// The `releases/latest` payload exactly as GitHub sent it, so it is read
  /// back through the same parsing the live response goes through.
  final String body;
  final String? etag;
  final DateTime? storedAt;
}
