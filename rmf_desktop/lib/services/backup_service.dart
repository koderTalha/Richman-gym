import 'dart:convert';
import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/audit_repository.dart';
import '../data/database.dart';
import '../domain/dates.dart';
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
  static const _receiptsFolderName = 'receipts';
  static const _pendingRestoreName = 'pending-restore.sqlite';
  static const _pendingReceiptsName = 'pending-restore-receipts';

  /// What is known about a staged restore — which backup, how old, who chose
  /// it — written beside it when it is staged. The restored database cannot
  /// carry that itself: its audit trail is the backup's, and stops at the
  /// moment the backup was taken.
  static const _pendingDetailsName = 'pending-restore.json';

  /// The same, plus the name of the copy the previous data was kept in,
  /// written when the restore is applied at launch and consumed once the
  /// restored database is open — see [recordAppliedRestore]. A file rather
  /// than a return value so that a launch which applies the restore and then
  /// fails to open the database still gets its audit row on the next one.
  static const _appliedDetailsName = 'restore-applied.json';

  /// How many superseded databases to keep after a restore. Enough to undo a
  /// mistake by hand; not so many that the folder grows without bound.
  static const _replacedCopiesKept = 3;

  /// The tables a file must have before it is believable as one of our
  /// backups. Not the full list — enough that a stranger's SQLite file, or a
  /// half-written one, is caught before it replaces the gym's records.
  static const _requiredTables = {
    'users',
    'members',
    'memberships',
    'membership_periods',
    'payments',
    'receipts',
    'gym_settings',
  };

  /// Where drift keeps the live database.
  static Future<File> liveDatabaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _databaseFileName));
  }

  Future<File> _pendingRestoreFile() async =>
      File(p.join((await _supportDirectory()).path, _pendingRestoreName));

  Future<Directory> _pendingReceiptsDirectory() async =>
      Directory(p.join((await _supportDirectory()).path, _pendingReceiptsName));

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
  ///
  /// The magic bytes alone are not enough. Anything SQLite ever wrote passes
  /// that test — another program's database, a `-wal` sidecar, a snapshot from
  /// a newer version of this app whose schema this one cannot read. Any of
  /// those replacing the gym's records leaves an app that will not start and
  /// no way to undo it from inside the app, so the file is opened and read
  /// before it is allowed anywhere near the live database.
  Future<String?> validateBackup(File file) async {
    if (!await file.exists()) return 'That file no longer exists.';

    final header = await file.openRead(0, 16).first;
    const magic = 'SQLite format 3';
    if (String.fromCharCodes(header.take(magic.length)) != magic) {
      return 'That file is not a database backup.';
    }

    return _inspect(file);
  }

  /// Reads the candidate through the open connection with ATTACH, which needs
  /// no second database handle and cannot disturb the live data.
  Future<String?> _inspect(File file) async {
    const alias = 'restore_candidate';

    try {
      await db.customStatement(
          "ATTACH DATABASE '${_escape(file.path)}' AS $alias");
    } catch (error) {
      _log.warning('Restore candidate would not attach: $file', error);
      return 'That file could not be opened as a database. It may be damaged.';
    }

    try {
      final tables = (await db
              .customSelect(
                  "SELECT name FROM $alias.sqlite_master WHERE type = 'table'")
              .get())
          .map((row) => row.read<String>('name'))
          .toSet();

      final missing = _requiredTables.difference(tables);
      if (missing.isNotEmpty) {
        return 'That database is not a Rich Man Fitness backup — '
            'it has no "${missing.first}" table.';
      }

      final version = (await db
              .customSelect('PRAGMA $alias.user_version')
              .getSingle())
          .read<int>('user_version');

      if (version > db.schemaVersion) {
        return 'That backup was made by a newer version of Rich Man Fitness '
            '(data format $version, this one reads up to ${db.schemaVersion}). '
            'Update the app before restoring it.';
      }

      return await _checkIntegrity(alias);
    } catch (error, stack) {
      _log.severe('Restore candidate could not be read', error, stack);
      return 'That file could not be read as a backup.';
    } finally {
      try {
        await db.customStatement('DETACH DATABASE $alias');
      } catch (_) {
        // Nothing left to detach; the connection is fine either way.
      }
    }
  }

  /// Reads every page of the attached candidate with `quick_check`.
  ///
  /// Everything above reads only the first page or two of the file, which is
  /// where the schema lives. A backup whose data pages were damaged — a bad
  /// sector on a USB stick, a copy interrupted over an older file of the same
  /// size — passes all of it, replaces the live database at the next launch,
  /// and leaves the owner on the startup-failure screen with the good data
  /// set aside. `quick_check` is the cheaper half of `integrity_check` (it
  /// skips cross-checking indexes against their tables), and takes well under
  /// a second on the gym's few-megabyte file.
  ///
  /// SQLite answers a single row reading `ok`, or rows describing what is
  /// wrong. Badly enough damaged, it refuses to read at all and throws
  /// "database disk image is malformed" instead; that is the same answer.
  Future<String?> _checkIntegrity(String alias) async {
    const damaged = 'That backup is damaged — some of the data inside it '
        'cannot be read — so it was not restored. Try another backup, such '
        'as one of the automatic ones listed below.';

    final List<String> findings;
    try {
      findings = (await db.customSelect('PRAGMA $alias.quick_check').get())
          .map((row) => '${row.data.values.first}')
          .toList();
    } catch (error) {
      _log.warning('Restore candidate failed its integrity check', error);
      return damaged;
    }

    if (findings.length == 1 && findings.single == 'ok') return null;

    _log.warning('Restore candidate failed its integrity check: '
        '${findings.take(5).join('; ')}');
    return damaged;
  }

  /// Whether [password] is the current password of the account [userId].
  ///
  /// Asked before a restore is staged. The session survives quitting the app,
  /// so "somebody is signed in" says only that the owner signed in once; a
  /// restore replaces every record and the audit trail with them, and is the
  /// one action worth stopping to ask who is at the keyboard.
  Future<bool> passwordMatches({
    required int userId,
    required String password,
  }) async {
    if (password.isEmpty) return false;
    final user = await (db.select(db.users)
          ..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    return user != null && BCrypt.checkpw(password, user.passwordHash);
  }

  /// Stages a restore to be applied on next launch.
  ///
  /// The live database is open and locked, so swapping it underneath a running
  /// app risks corruption. Writing it aside and applying it at startup, before
  /// anything opens the database, is the safe order.
  ///
  /// The receipt images beside the snapshot are staged too. Restoring only the
  /// database left every receipt row pointing at a file that was not there, so
  /// "View Receipt" did nothing and every resend failed — a restore that threw
  /// away exactly the paperwork the owner restored the backup to get back.
  ///
  /// [stagedBy] is who chose the restore, for the audit row the restored
  /// database gets on its first launch.
  Future<String?> stageRestore(
    File backupDatabase, {
    String? stagedBy,
    DateTime? now,
  }) async {
    final problem = await validateBackup(backupDatabase);
    if (problem != null) return problem;

    final pending = await _pendingRestoreFile();
    await pending.parent.create(recursive: true);

    // Cleared first: details left over from an earlier staging must never be
    // read back as describing this one.
    final details = File(p.join(pending.parent.path, _pendingDetailsName));
    if (await details.exists()) await details.delete();

    await backupDatabase.copy(pending.path);

    await _stageReceipts(
      Directory(p.join(backupDatabase.parent.path, _receiptsFolderName)),
    );

    // Best-effort. Without it the restore still happens and is still logged,
    // just without saying which backup it was.
    try {
      final takenAt =
          _parseFolderName(p.basename(backupDatabase.parent.path));
      await details.writeAsString(jsonEncode({
        'source': backupDatabase.path,
        'backupTakenAt': takenAt?.toIso8601String(),
        'fileModifiedAt':
            (await backupDatabase.lastModified()).toIso8601String(),
        'stagedAt': (now ?? DateTime.now()).toIso8601String(),
        'stagedBy': stagedBy,
      }));
    } catch (error, stack) {
      _log.warning('The staged restore\'s details were not written',
          error, stack);
    }
    return null;
  }

  Future<void> _stageReceipts(Directory source) async {
    final staged = await _pendingReceiptsDirectory();
    if (await staged.exists()) await staged.delete(recursive: true);
    if (!await source.exists()) return;

    await staged.create(recursive: true);
    await for (final entity in source.list()) {
      if (entity is! File) continue;
      await entity.copy(p.join(staged.path, p.basename(entity.path)));
    }
  }

  /// Applies a staged restore. Call this in main() *before* opening the
  /// database. Returns true if a restore was applied.
  ///
  /// Directories are injectable so the whole staging-and-applying round trip
  /// can be tested; production passes nothing and gets the real folders.
  static Future<bool> applyPendingRestore({
    Future<Directory> Function()? supportDirectory,
    Future<File> Function()? liveDatabase,
  }) async {
    final support = await (supportDirectory ?? getApplicationSupportDirectory)();
    final pending = File(p.join(support.path, _pendingRestoreName));
    if (!await pending.exists()) return false;

    final live = await (liveDatabase ?? liveDatabaseFile)();
    await live.parent.create(recursive: true);

    // Keep the replaced database alongside, so a mistaken restore is not fatal.
    String? replacedCopy;
    if (await live.exists()) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final copy = await live.copy('${live.path}.replaced-$stamp');
      replacedCopy = p.basename(copy.path);
    }

    await pending.copy(live.path);
    await pending.delete();

    // Drift's WAL and shared-memory files belong to the old database.
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('${live.path}$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }

    await _applyStagedReceipts(support);
    await _pruneReplacedCopies(live);
    await _noteAppliedRestore(support, replacedCopy: replacedCopy);

    return true;
  }

  /// Hands what is known about the restore just applied to
  /// [recordAppliedRestore], which runs once the database is open.
  ///
  /// Never throws: by this point the restore has happened, and failing the
  /// launch over its paperwork would be the worse outcome. The log line is
  /// the fallback record.
  static Future<void> _noteAppliedRestore(
    Directory support, {
    required String? replacedCopy,
  }) async {
    final staged = File(p.join(support.path, _pendingDetailsName));
    var details = <String, Object?>{};
    try {
      if (await staged.exists()) {
        final decoded = jsonDecode(await staged.readAsString());
        if (decoded is Map<String, dynamic>) details = decoded;
        await staged.delete();
      }
    } catch (error) {
      _log.warning('The staged restore\'s details could not be read', error);
    }

    details['replacedCopy'] = replacedCopy;
    details['appliedAt'] = DateTime.now().toIso8601String();
    _log.warning('A staged restore was applied: ${jsonEncode(details)}');

    try {
      await File(p.join(support.path, _appliedDetailsName))
          .writeAsString(jsonEncode(details));
    } catch (error, stack) {
      _log.severe('The applied restore could not be noted for the audit log',
          error, stack);
    }
  }

  /// Writes the audit row for a restore applied at this launch, into the
  /// database it restored. Call once the database is open. Returns whether
  /// there was one to record.
  ///
  /// Without this a restore was invisible inside the app: the restored audit
  /// trail is the backup's, and ends the moment the backup was taken. That
  /// made "restore an old backup" a way to undo a password reset or a deleted
  /// payment and leave no trace of having done it. The row names the backup's
  /// date and the `.replaced-*` file the previous data was kept in, which is
  /// where anything recorded since the backup still is.
  ///
  /// Never throws — see [_noteAppliedRestore] — and consumes the note only
  /// once the row has been offered to the audit log.
  static Future<bool> recordAppliedRestore(
    AppDatabase db, {
    Future<Directory> Function()? supportDirectory,
  }) async {
    try {
      final support =
          await (supportDirectory ?? getApplicationSupportDirectory)();
      final note = File(p.join(support.path, _appliedDetailsName));
      if (!await note.exists()) return false;

      var details = const <String, dynamic>{};
      try {
        final decoded = jsonDecode(await note.readAsString());
        if (decoded is Map<String, dynamic>) details = decoded;
      } catch (error) {
        _log.warning('The applied restore\'s details could not be read', error);
      }

      DateTime? at(String key) {
        final value = details[key];
        return value is String ? DateTime.tryParse(value) : null;
      }

      String? text(String key) {
        final value = details[key];
        return value is String && value.isNotEmpty ? value : null;
      }

      final takenAt = at('backupTakenAt');
      final modifiedAt = at('fileModifiedAt');
      final stagedAt = at('stagedAt');
      final stagedBy = text('stagedBy');
      final source = text('source');
      final replaced = text('replacedCopy');

      await AuditRepository(db).record(
        category: AuditCategory.update,
        action: AuditAction.backupRestored,
        outcome: AuditOutcome.success,
        summary: takenAt == null
            ? 'Data restored from a backup'
            : 'Data restored from the backup taken ${_readable(takenAt)}',
        actorName: stagedBy,
        detail: [
          if (source != null) 'Backup file: $source',
          if (takenAt == null && modifiedAt != null)
            'Backup date unknown; the file was last changed '
                '${_readable(modifiedAt)}',
          if (stagedAt != null) 'Restore chosen ${_readable(stagedAt)}',
          replaced == null
              ? 'There was no previous database to keep'
              : 'The data it replaced was kept as $replaced',
          'Entries below this one come from the backup. Anything recorded '
              'after the backup was taken is only in the kept copy.',
        ],
      );

      await note.delete();
      return true;
    } catch (error, stack) {
      _log.severe('The applied restore was not recorded in the audit log',
          error, stack);
      return false;
    }
  }

  static String _readable(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${formatDayMonthYear(local)}, '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// Copies the backup's receipt images into the live receipts folder.
  ///
  /// Merged rather than swapped: a file already there belongs to a payment
  /// that may well still exist in the restored database, and deleting it would
  /// lose paperwork the restore was never asked to touch.
  static Future<void> _applyStagedReceipts(Directory support) async {
    final staged = Directory(p.join(support.path, _pendingReceiptsName));
    if (!await staged.exists()) return;

    final live = Directory(p.join(support.path, _receiptsFolderName));
    await live.create(recursive: true);

    await for (final entity in staged.list()) {
      if (entity is! File) continue;
      await entity.copy(p.join(live.path, p.basename(entity.path)));
    }
    await staged.delete(recursive: true);
  }

  /// Keeps the newest few superseded databases and deletes the rest, so
  /// repeated restores cannot quietly fill the disk with old copies.
  static Future<void> _pruneReplacedCopies(File live) async {
    final prefix = '${p.basename(live.path)}.replaced-';
    final copies = <File>[];

    await for (final entity in live.parent.list()) {
      if (entity is File && p.basename(entity.path).startsWith(prefix)) {
        copies.add(entity);
      }
    }

    if (copies.length <= _replacedCopiesKept) return;

    int stampOf(File f) =>
        int.tryParse(p.basename(f.path).substring(prefix.length)) ?? 0;
    copies.sort((a, b) => stampOf(b).compareTo(stampOf(a))); // newest first

    for (final old in copies.skip(_replacedCopiesKept)) {
      try {
        await old.delete();
      } catch (error) {
        _log.warning('Could not remove an old database copy: ${old.path}', error);
      }
    }
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
