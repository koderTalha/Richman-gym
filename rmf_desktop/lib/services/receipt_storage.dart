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

  Future<Directory> root() async {
    if (_cachedRoot != null) return _cachedRoot!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'receipts'));
    await dir.create(recursive: true);
    _cachedRoot = dir;
    return dir;
  }

  Future<String> save(String relativePath, Uint8List bytes) async {
    final dir = await root();
    final file = File(p.join(dir.path, relativePath));
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
}
