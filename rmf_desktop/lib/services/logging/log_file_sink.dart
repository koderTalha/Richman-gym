import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Appends log lines to a per-day file under the app's support folder, beside
/// `receipts/`.
///
/// The gym's computer is not one we can attach a debugger to, so the file is
/// the only evidence available when the owner reports that something went
/// wrong. It is written in both debug and release builds: a sink that only runs
/// in release is one that is never exercised until it fails on the one machine
/// nobody can reach.
///
/// Writes are synchronous and flushed. Log volume here is a handful of lines a
/// minute, so the cost is irrelevant, and it means a line describing a crash is
/// on disk before the process dies — which a buffered [IOSink] cannot promise.
class LogFileSink {
  LogFileSink({
    Future<Directory> Function()? supportDirectory,
    DateTime Function()? clock,
    this.retainedDays = 7,
    this.maxFileBytes = 5 * 1024 * 1024,
  })  : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _clock = clock ?? DateTime.now;

  /// Injectable so tests can point at a temp folder, mirroring BackupService.
  final Future<Directory> Function() _supportDirectory;
  final DateTime Function() _clock;

  /// Older files are deleted on open. Seven days is enough to cover "it broke
  /// sometime last week" without letting the folder grow forever.
  final int retainedDays;

  /// A runaway error loop could otherwise fill the owner's disk.
  final int maxFileBytes;

  Directory? _dir;
  File? _file;
  String? _fileDay;

  static final RegExp _logName = RegExp(r'^app-(\d{4}-\d{2}-\d{2})\.log$');

  Directory? get directory => _dir;
  File? get currentFile => _file;

  /// Resolves the folder, creates it if needed and prunes expired files.
  Future<void> open() async {
    final support = await _supportDirectory();
    final dir = Directory(p.join(support.path, 'logs'));
    await dir.create(recursive: true);
    _dir = dir;
    await _prune();
    _roll();
  }

  /// Appends one already-formatted line. Silently gives up on IO failure: a
  /// logging problem must never take down the app it is meant to diagnose.
  void write(String line) {
    if (_dir == null) return;
    try {
      _roll();
      final file = _file;
      if (file == null) return;
      if (file.existsSync() && file.lengthSync() >= maxFileBytes) return;
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Nothing sensible to do here — reporting it would need the logger.
    }
  }

  /// Points [_file] at today's file, creating a new one after midnight.
  void _roll() {
    final dir = _dir;
    if (dir == null) return;
    final day = _dayStamp(_clock());
    if (_fileDay == day && _file != null) return;
    _fileDay = day;
    _file = File(p.join(dir.path, 'app-$day.log'));
  }

  Future<void> _prune() async {
    final dir = _dir;
    if (dir == null) return;
    final cutoff = _dateOnly(_clock()).subtract(Duration(days: retainedDays - 1));
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = _logName.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      final stamp = DateTime.tryParse(match.group(1)!);
      if (stamp == null || !stamp.isBefore(cutoff)) continue;
      try {
        await entity.delete();
      } catch (_) {
        // A file held open by something else is not worth failing startup for.
      }
    }
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  static String _dayStamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
