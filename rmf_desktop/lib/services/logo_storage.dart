import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Why a logo was rejected, in words the owner can act on.
class LogoRejected implements Exception {
  const LogoRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What an image the owner supplies is going to be used for.
///
/// The two differ only in how large a file is reasonable and what the saved
/// file is called. A logo is a mark that gets drawn into a receipt header at a
/// couple of hundred pixels, so a multi-megabyte one is a mistake worth
/// refusing; a hero photograph fills half a 1240-wide panel and is read once at
/// startup, so the same 2MB ceiling would reject most photographs straight off
/// a phone.
enum ImageKind {
  logo(prefix: 'logo', maxBytes: 2 * 1024 * 1024, limitLabel: '2MB'),
  photo(prefix: 'photo', maxBytes: 8 * 1024 * 1024, limitLabel: '8MB');

  const ImageKind({
    required this.prefix,
    required this.maxBytes,
    required this.limitLabel,
  });

  /// Leading part of the saved filename, so the branding directory says what
  /// each file is for.
  final String prefix;

  final int maxBytes;

  /// The ceiling as the owner is told it, so the message and the check cannot
  /// drift apart.
  final String limitLabel;
}

/// Stores the images the owner supplies — the gym logo and the hero
/// photographs — and vets what is allowed to become one.
///
/// The file is copied into the app's own support directory rather than
/// referenced where the owner left it: a logo picked off the Desktop and later
/// moved would otherwise leave every receipt and the sidebar pointing at
/// nothing. One copy, one path in the settings row, used by everything that
/// draws it.
class LogoStorage {
  LogoStorage({Directory? root, this.kind = ImageKind.logo})
      : _overrideRoot = root;

  final Directory? _overrideRoot;
  Directory? _cachedRoot;

  /// What this instance is storing. Decides the size ceiling and the filename.
  final ImageKind kind;

  /// The logo ceiling, kept as a name because callers and tests refer to it.
  /// [ImageKind.maxBytes] is what the checks actually read.
  static const maxBytes = 2 * 1024 * 1024;

  /// Raster formats only, matched on the file's own magic bytes rather than its
  /// extension.
  ///
  /// SVG is deliberately absent. An SVG is a document that can carry script and
  /// external references, it is rendered by a different code path, and the
  /// receipt renderer cannot draw one anyway — accepting it would mean shipping
  /// an XML parser to handle untrusted markup for no benefit. A `.svg` renamed
  /// to `.png` is caught here too, because the signature check is what decides.
  static const _signatures = <String, List<int>>{
    'png': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    'jpg': [0xFF, 0xD8, 0xFF],
    'gif': [0x47, 0x49, 0x46, 0x38],
    // 'RIFF' .... 'WEBP' — the middle four bytes are the file size, so the
    // second half is checked separately in [_sniff].
    'webp': [0x52, 0x49, 0x46, 0x46],
  };

  Future<Directory> root() async {
    if (_overrideRoot != null) return _overrideRoot;
    if (_cachedRoot != null) return _cachedRoot!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'branding'));
    await dir.create(recursive: true);
    _cachedRoot = dir;
    return dir;
  }

  /// Identifies [bytes] by signature, or null when it is not an image this app
  /// will accept.
  static String? _sniff(Uint8List bytes) {
    for (final entry in _signatures.entries) {
      final magic = entry.value;
      if (bytes.length < magic.length) continue;
      var matches = true;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) {
          matches = false;
          break;
        }
      }
      if (!matches) continue;
      if (entry.key == 'webp') {
        // RIFF is also used by WAV and AVI; only the WEBP form is an image.
        if (bytes.length < 12) continue;
        final tag = String.fromCharCodes(bytes.sublist(8, 12));
        if (tag != 'WEBP') continue;
      }
      return entry.key;
    }
    return null;
  }

  /// Validates [bytes] and returns the extension they should be saved under.
  ///
  /// Separate from [save] so the checks can be unit tested without touching the
  /// filesystem. [kind] decides only the size ceiling; the format rules are the
  /// same for a logo and a photograph, because both end up decoded by the same
  /// image pipeline.
  static String validate(Uint8List bytes, {ImageKind kind = ImageKind.logo}) {
    if (bytes.isEmpty) {
      throw const LogoRejected('That file is empty.');
    }
    if (bytes.length > kind.maxBytes) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw LogoRejected(
          'That image is ${mb}MB. Please use one under ${kind.limitLabel}.');
    }
    final format = _sniff(bytes);
    if (format == null) {
      throw const LogoRejected(
          'That is not a PNG, JPEG, GIF or WebP image. '
          'SVG files are not supported.');
    }
    return format;
  }

  /// Copies a validated logo into the branding directory and returns its
  /// absolute path.
  ///
  /// The previous logo is deleted only after the new one is written, so a
  /// failed write leaves the gym with the logo it had rather than none.
  Future<String> save(Uint8List bytes, {String? replacing}) async {
    final extension = validate(bytes, kind: kind);
    final dir = await root();

    // A fresh name each time: writing over `logo.png` would be served from
    // Flutter's image cache and the sidebar would keep showing the old mark
    // until the app restarted.
    final name =
        '${kind.prefix}-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);

    if (replacing != null && replacing != file.path) {
      await _deleteQuietly(replacing);
    }
    return file.path;
  }

  /// Forgets the logo, removing the file if it is one of ours.
  Future<void> remove(String? path) => _deleteQuietly(path);

  /// Deleting a logo must never be able to fail the save that triggered it: the
  /// file may be gone already, or locked by a viewer the owner left open. The
  /// database is the record of whether a logo exists, not the directory.
  Future<void> _deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final dir = await root();
      // Only files this class wrote are removed. A logo_path that points
      // somewhere else (hand-edited, or restored from another machine) is
      // dropped from the settings row but left alone on disk — deleting an
      // arbitrary path because a column names it is not this class's business.
      if (!p.isWithin(dir.path, path)) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Intentionally swallowed, see above.
    }
  }

  /// Reads the logo for rendering, or null when there is none or the file has
  /// gone missing.
  ///
  /// Null rather than throwing: a receipt must still render for a gym whose
  /// logo file was deleted out from under it, and the sidebar must still draw.
  static Future<Uint8List?> read(
    String? path, {
    ImageKind kind = ImageKind.logo,
  }) async {
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      // Re-validated on read: the bytes go into a PDF and into the UI, and the
      // file may have been swapped since it was accepted.
      validate(bytes, kind: kind);
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
