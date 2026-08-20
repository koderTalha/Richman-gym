import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Reads back what [LogFileSink] wrote, for the Logs screen's technical tab.
///
/// Deliberately reads the *end* of a file rather than the file: the sink lets a
/// day's log reach 5 MB, and loading that into a string to show the last screen
/// of it would stall the UI for no benefit.
class LogFileReader {
  LogFileReader({Future<Directory> Function()? supportDirectory})
      : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  /// How much of the end of the file to read. Comfortably more than the number
  /// of lines shown, and small enough to be instant.
  static const _tailBytes = 256 * 1024;

  static final RegExp _logName = RegExp(r'^app-(\d{4}-\d{2}-\d{2})\.log$');

  Future<Directory> directory() async {
    final support = await _supportDirectory();
    return Directory(p.join(support.path, 'logs'));
  }

  /// The available log files, newest day first.
  Future<List<File>> files() async {
    final dir = await directory();
    if (!await dir.exists()) return const [];

    final logs = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && _logName.hasMatch(p.basename(entity.path))) {
        logs.add(entity);
      }
    }
    logs.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return logs;
  }

  /// The last [maxLines] lines of [file], newest last.
  ///
  /// Returns an empty list rather than throwing: a Logs screen that cannot show
  /// the log is a nuisance, one that crashes on opening is a second fault to
  /// diagnose on top of the first.
  Future<List<String>> tail(File file, {int maxLines = 500}) async {
    try {
      if (!await file.exists()) return const [];

      final length = await file.length();
      final start = length > _tailBytes ? length - _tailBytes : 0;

      final handle = await file.open();
      try {
        await handle.setPosition(start);
        final bytes = await handle.read(length - start);
        var text = const Utf8Decoder(allowMalformed: true).convert(bytes);

        // The first line is probably cut in half by where we started reading.
        if (start > 0) {
          final firstBreak = text.indexOf('\n');
          text = firstBreak == -1 ? '' : text.substring(firstBreak + 1);
        }

        final lines =
            text.split('\n').where((l) => l.trimRight().isNotEmpty).toList();
        return lines.length <= maxLines
            ? lines
            : lines.sublist(lines.length - maxLines);
      } finally {
        await handle.close();
      }
    } on FileSystemException {
      return const [];
    }
  }

  /// The newest day's log, tailed. Empty when nothing has been written yet.
  Future<List<String>> latest({int maxLines = 500}) async {
    final logs = await files();
    if (logs.isEmpty) return const [];
    return tail(logs.first, maxLines: maxLines);
  }
}
