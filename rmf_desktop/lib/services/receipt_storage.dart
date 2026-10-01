import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where generated receipt files live on disk.
///
/// Paths are stored in the database relative to this directory, so the whole
/// data folder can be copied to another machine without breaking the links.
class ReceiptStorage {
  Directory? _cachedRoot;

  /// Separators and characters a Windows file name cannot hold, plus control
  /// characters. `/` is left to [p.isWithin], which understands it here.
  static final _unsafeOnWindows = RegExp(r'[\\:*?"<>|\x00-\x1F]');

  Future<Directory> root() async {
    if (_cachedRoot != null) return _cachedRoot!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'receipts'));
    await dir.create(recursive: true);
    _cachedRoot = dir;
    return dir;
  }

  /// Writes [bytes] at [relativePath] inside [root], and refuses anywhere
  /// else.
  ///
  /// The path is built from the receipt number, and so from the receipt
  /// prefix the owner typed in Settings. Settings now refuses an unsafe one,
  /// but a prefix saved by an earlier release — or a database restored from
  /// one — never went through that check. A path that climbs out of the
  /// folder (`..\..\Desktop\X-2026-000001.png`) or names another drive
  /// would write a receipt where backups never look, so it throws instead,
  /// before anything is written; the payment that wanted it fails with a
  /// reason rather than recording against a file nobody will find.
  ///
  /// Two checks, because the path is judged on this computer's rules but
  /// written on the gym's: Windows treats `\` as a separator and `:` as a
  /// drive or a hidden alternate stream, where macOS (and the tests) see
  /// ordinary characters. Refusing those, and the other characters Windows
  /// will not have in a file name, makes the verdict the same everywhere;
  /// `isWithin` then catches `..` and absolute paths.
  Future<String> save(String relativePath, Uint8List bytes) async {
    final dir = await root();
    final target = p.normalize(p.join(dir.path, relativePath));
    if (_unsafeOnWindows.hasMatch(relativePath) ||
        !p.isWithin(p.normalize(dir.path), target)) {
      throw ArgumentError.value(relativePath, 'relativePath',
          'A receipt file must be inside the receipts folder');
    }
    final file = File(target);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return relativePath;
  }

  Future<File> resolve(String relativePath) async =>
      File(p.join((await root()).path, relativePath));

  Future<Uint8List?> read(String relativePath) async {
    final file = await resolve(relativePath);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Removes a file written for a receipt that was never committed.
  ///
  /// Best-effort: a leftover image is untidy, but failing to delete one must
  /// not turn into a second error on top of whatever went wrong first.
  Future<void> delete(String relativePath) async {
    try {
      final file = await resolve(relativePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing useful to do; the file is orphaned either way.
    }
  }
}
