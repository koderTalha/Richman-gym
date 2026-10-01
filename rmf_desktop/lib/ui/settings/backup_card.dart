import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/database.dart';
import '../../services/backup_service.dart';
import '../../services/excel_export_service.dart';
import '../../theme/app_theme.dart';

final _log = Logger('backup');

/// Backup and restore. Deliberately its own widget with local state rather than
/// a bloc: it touches the filesystem directly and has no shared state.
class BackupCard extends StatefulWidget {
  const BackupCard({super.key, required this.card});

  /// The shared card chrome from the settings screen.
  final Widget Function({
    required String title,
    String? subtitle,
    required Widget child,
  }) card;

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  List<BackupEntry> _automatic = [];
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  bool _restoreStaged = false;

  BackupService get _service => BackupService(context.read<AppDatabase>());

  @override
  void initState() {
    super.initState();
    _loadAutomatic();
  }

  Future<void> _loadAutomatic() async {
    final service = _service;
    final entries =
        await service.listBackups(await service.automaticBackupDirectory());
    if (!mounted) return;
    setState(() => _automatic = entries);
  }

  void _report(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _backupNow() async {
    final target = await getDirectoryPath(
        confirmButtonText: 'Back up here',
        initialDirectory: (await getDownloadsDirectory())?.path);
    if (target == null) return;

    setState(() => _busy = true);
    try {
      final result = await _service.backupTo(Directory(target));
      _report('Backed up to ${p.basename(result.folder.path)} — '
          'database ${_readableSize(result.databaseBytes)}, '
          '${result.receiptsCopied} receipts'
          '${result.workbookBytes > 0 ? ", plus an Excel workbook" : ""}.');
    } catch (e, s) {
      _log.severe('Manual backup failed', e, s);
      _report('Backup failed: $e', isError: true);
    }
  }

  Future<void> _restore() async {
    const typeGroup = XTypeGroup(label: 'Backup database', extensions: [
      'sqlite',
      'db',
    ]);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;

    // Read before the dialog's await, and checked: a restore is staged in the
    // name of whoever proved they know the password, so there has to be one.
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      _report('Sign in again before restoring a backup.', isError: true);
      return;
    }
    final service = _service;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => RestoreConfirmDialog(
        verify: (password) =>
            service.passwordMatches(userId: user.id, password: password),
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    final problem =
        await service.stageRestore(File(file.path), stagedBy: user.name);

    if (problem != null) {
      _report(problem, isError: true);
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _restoreStaged = true;
      _message = null;
    });
  }

  /// Writes just the workbook, for when the owner wants a file to look at
  /// rather than a full restorable backup.
  Future<void> _exportExcel() async {
    final at = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final suggested =
        'RichManFitness-${at.year}-${two(at.month)}-${two(at.day)}.xlsx';

    // Resolved before the await: reading from context afterwards is unsafe.
    final db = context.read<AppDatabase>();

    final location = await getSaveLocation(suggestedName: suggested);
    if (location == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await ExcelExportService(db).build();
      await File(location.path).writeAsBytes(bytes);
      _report('Exported ${p.basename(location.path)} '
          '(${_readableSize(bytes.length)}).');
    } catch (e, s) {
      _log.severe('Excel export failed', e, s);
      _report('Export failed: $e', isError: true);
    }
  }

  Future<void> _openFolder(Directory dir) async {
    await launchUrl(Uri.file(dir.path));
  }

  @override
  Widget build(BuildContext context) {
    return widget.card(
      title: 'Backup',
      subtitle: 'Every backup contains a database snapshot for restoring, plus '
          'an Excel workbook you can open on any computer.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_restoreStaged)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: context.palette.dueBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.palette.due.withValues(alpha: .4)),
              ),
              child: Text(
                'Restore ready. Quit and reopen Rich Man Fitness to apply it — '
                'the database cannot be replaced while the app is running.',
                style: TextStyle(fontSize: 12, color: context.palette.due),
              ),
            ),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _backupNow,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(_busy ? 'Working…' : 'Back up now'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _exportExcel,
                icon: const Icon(Icons.table_view_outlined, size: 16),
                label: const Text('Export to Excel'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restore…'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(
                fontSize: 12,
                color: _messageIsError ? context.palette.expired : context.palette.paid,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text('AUTOMATIC BACKUPS', style: labelStyleOf(context)),
          const SizedBox(height: 6),
          Text(
            _automatic.isEmpty
                ? 'One is taken automatically each time you open the app, at '
                    'most once a day. The seven most recent are kept.'
                : 'Taken automatically, at most once a day. The seven most '
                    'recent are kept.',
            style: mutedStyleOf(context),
          ),
          const SizedBox(height: 10),
          if (_automatic.isNotEmpty)
            ..._automatic.take(7).map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined,
                            size: 14, color: context.palette.textHint),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_readableDate(entry.takenAt),
                              style: TextStyle(
                                  fontSize: 12, color: context.palette.textSecondary)),
                        ),
                        TextButton(
                          onPressed: () => _openFolder(entry.folder),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Open',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  static String _readableSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _readableDate(DateTime at) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.day)} ${months[at.month - 1]} ${at.year}, '
        '${two(at.hour)}:${two(at.minute)}';
  }
}

/// Keys for tests.
const restorePasswordFieldKey = Key('restore-password-field');

/// "Replace all current data?", answered with the signed-in account's
/// password rather than one more click.
///
/// The session survives quitting the app, so being signed in proves only
/// that the owner signed in at some point. A restore replaces every record —
/// the audit trail and the password among them — and is the one action here
/// that could undo everything else the log would have shown, so it asks who
/// is at the keyboard (audit SEC-002). Pops true only once [verify] has
/// accepted the password; a wrong one keeps the dialog open with a reason.
class RestoreConfirmDialog extends StatefulWidget {
  const RestoreConfirmDialog({super.key, required this.verify});

  final Future<bool> Function(String password) verify;

  @override
  State<RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<RestoreConfirmDialog> {
  final _password = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    var ok = false;
    try {
      ok = await widget.verify(_password.text);
    } catch (e, s) {
      _log.severe('The password for a restore could not be checked', e, s);
    }
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _error = 'That is not the password for this account. '
          'Nothing has been restored.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.palette.surfaceRaised,
      title: const Text('Replace all current data?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Restoring replaces every member, payment and receipt record '
              'with the contents of the backup. The current database is kept '
              'alongside as a copy, and the app must be restarted to finish.',
              style: mutedStyleOf(context),
            ),
            const SizedBox(height: 16),
            TextField(
              key: restorePasswordFieldKey,
              controller: _password,
              obscureText: true,
              autofocus: true,
              enabled: !_checking,
              decoration: InputDecoration(
                labelText: 'Your password',
                helperText: 'The one you sign in with',
                errorText: _error,
                errorMaxLines: 2,
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: Text(_checking ? 'Checking…' : 'Restore'),
        ),
      ],
    );
  }
}
