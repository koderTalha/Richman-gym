import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import 'excel_export_service.dart';

final _log = Logger('backup');

class BackupResult {
  const BackupResult({
    required this.folder,
    required this.databaseBytes,
    required this.receiptsCopied,
    required this.workbookBytes,
  });

  final Directory folder;
  final int databaseBytes;
  final int receiptsCopied;

  /// Size of the .xlsx written beside the snapshot. Zero if it could not be
  /// produced, which must not fail the backup itself.
  final int workbookBytes;
}

class BackupEntry {
  const BackupEntry({required this.folder, required this.takenAt});

  final Directory folder;
  final DateTime takenAt;

  String get name => p.basename(folder.path);
}

/// Backup and restore for the gym's data.
///
/// A backup is a folder holding a consistent snapshot of the database plus the
/// generated receipt files, so the owner can copy it to a USB stick and have
/// everything. Restores are staged rather than applied immediately, because the
/// database file is open and locked while the app is running.
class BackupService {
  BackupService(
    this.db, {
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? receiptsDirectory,
  })  : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
        _receiptsDirectory = receiptsDirectory;

  final AppDatabase db;

  /// Injected so the service can be tested without platform channels;
  /// path_provider is unavailable in a plain unit test.
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function()? _receiptsDirectory;

  Future<Directory> _receipts() async =>
      _receiptsDirectory != null
          ? await _receiptsDirectory()
          : Directory(p.join((await _supportDirectory()).path, 'receipts'));

  static const _databaseFileName = 'richmanfitness.sqlite';
  static const _backupDatabaseName = 'database.sqlite';
  static const _pendingRestoreName = 'pending-restore.sqlite';

  /// Where drift keeps the live database.
  static Future<File> liveDatabaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _databaseFileName));
  }

  static Future<File> _pendingRestoreFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _pendingRestoreName));
  }

  Future<Directory> automaticBackupDirectory() async {
    final dir =
        Directory(p.join((await _supportDirectory()).path, 'backups'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Writes a snapshot into a new timestamped folder under [target].
  ///
  /// Uses SQLite's `VACUUM INTO`, which produces a consistent copy even while
  /// the database is in use — plainly copying the file risks capturing a
  /// half-written transaction or missing the write-ahead log.
  Future<BackupResult> backupTo(Directory target, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final folder = Directory(p.join(target.path, _folderName(at)));
    await folder.create(recursive: true);

    final databasePath = p.join(folder.path, _backupDatabaseName);
    // VACUUM INTO refuses to overwrite, so clear any leftover first.
    final databaseFile = File(databasePath);
    if (await databaseFile.exists()) await databaseFile.delete();

    await db.customStatement("VACUUM INTO '${_escape(databasePath)}'");

    final receiptsCopied = await _copyReceipts(folder);

    // The workbook is the copy the owner can actually read without this app.
    // A failure here must not cost them the database snapshot, which is the
    // part that can be restored.
    var workbookBytes = 0;
    try {
      final workbook = await ExcelExportService(db).build(now: at);
      final file = File(p.join(folder.path, _workbookName(at)));
      await file.writeAsBytes(workbook);
      workbookBytes = workbook.length;
    } catch (e, s) {
      _log.severe('Excel workbook omitted from the backup', e, s);
      workbookBytes = 0;
    }

    return BackupResult(
      folder: folder,
      databaseBytes: await databaseFile.length(),
      receiptsCopied: receiptsCopied,
      workbookBytes: workbookBytes,
    );
  }

  /// Takes at most one automatic backup per day and keeps the newest [keep].
  Future<BackupResult?> autoBackup({int keep = 7, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final dir = await automaticBackupDirectory();

    final existing = await listBackups(dir);
    final today = existing.any((b) =>
        b.takenAt.year == at.year &&
        b.takenAt.month == at.month &&
        b.takenAt.day == at.day);
    if (today) return null;

    final result = await backupTo(dir, now: at);

    // Prune oldest first, so the folder cannot grow without bound.
    final all = await listBackups(dir);
    if (all.length > keep) {
      for (final old in all.skip(keep)) {
        await old.folder.delete(recursive: true);
      }
    }
    return result;
  }

  /// Backups in [dir], newest first.
  Future<List<BackupEntry>> listBackups(Directory dir) async {
    if (!await dir.exists()) return const [];

    final entries = <BackupEntry>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final takenAt = _parseFolderName(p.basename(entity.path));
      if (takenAt == null) continue;
      entries.add(BackupEntry(folder: entity, takenAt: takenAt));
    }

    entries.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return entries;
  }

  /// Checks a file really is one of our backups before it is trusted.
  Future<String?> validateBackup(File file) async {
    if (!await file.exists()) return 'That file no longer exists.';

    final header = await file.openRead(0, 16).first;
    const magic = 'SQLite format 3';
    if (String.fromCharCodes(header.take(magic.length)) != magic) {
      return 'That file is not a database backup.';
    }

    return null;
  }

  /// Stages a restore to be applied on next launch.
  ///
  /// The live database is open and locked, so swapping it underneath a running
  /// app risks corruption. Writing it aside and applying it at startup, before
  /// anything opens the database, is the safe order.
  Future<String?> stageRestore(File backupDatabase) async {
    final problem = await validateBackup(backupDatabase);
    if (problem != null) return problem;

    final pending = await _pendingRestoreFile();
    await pending.parent.create(recursive: true);
    await backupDatabase.copy(pending.path);
    return null;
  }

  /// Applies a staged restore. Call this in main() *before* opening the
  /// database. Returns true if a restore was applied.
  static Future<bool> applyPendingRestore() async {
    final pending = await _pendingRestoreFile();
    if (!await pending.exists()) return false;

    final live = await liveDatabaseFile();

    // Keep the replaced database alongside, so a mistaken restore is not fatal.
    if (await live.exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await live.copy('${live.path}.replaced-$stamp');
    }

    await pending.copy(live.path);
    await pending.delete();

    // Drift's WAL and shared-memory files belong to the old database.
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('${live.path}$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }

    return true;
  }

  Future<int> _copyReceipts(Directory backupFolder) async {
    final source = await _receipts();
    if (!await source.exists()) return 0;

    final destination = Directory(p.join(backupFolder.path, 'receipts'));
    await destination.create(recursive: true);

    var copied = 0;
    await for (final entity in source.list()) {
      if (entity is! File) continue;
      await entity.copy(p.join(destination.path, p.basename(entity.path)));
      copied++;
    }
    return copied;
  }

  static String _workbookName(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'RichManFitness-${at.year}-${two(at.month)}-${two(at.day)}.xlsx';
  }

  static String _folderName(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'RichManFitness-Backup-${at.year}-${two(at.month)}-${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}';
  }

  static DateTime? _parseFolderName(String name) {
    final match = RegExp(
      r'^RichManFitness-Backup-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})$',
    ).firstMatch(name);
    if (match == null) return null;

    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );
  }

  /// SQLite string literals escape a quote by doubling it.
  static String _escape(String path) => path.replaceAll("'", "''");
}
