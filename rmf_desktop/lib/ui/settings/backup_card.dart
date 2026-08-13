import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../services/backup_service.dart';
import '../../services/excel_export_service.dart';
import '../../theme/app_theme.dart';

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
  List<BackupEntry> _automatic = const [];
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
    } catch (e) {
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.ink900,
        title: const Text('Replace all current data?'),
        content: const Text(
          'Restoring replaces every member, payment and receipt record with '
          'the contents of the backup. The current database is kept alongside '
          'as a copy, and the app must be restarted to finish.',
          style: kMutedStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    final problem = await _service.stageRestore(File(file.path));

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
    } catch (e) {
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
                color: AppColors.dueBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.due.withValues(alpha: .4)),
              ),
              child: const Text(
                'Restore ready. Quit and reopen Rich Man Fitness to apply it — '
                'the database cannot be replaced while the app is running.',
                style: TextStyle(fontSize: 12, color: AppColors.due),
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
                color: _messageIsError ? AppColors.expired : AppColors.paid,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text('AUTOMATIC BACKUPS', style: kLabelStyle),
          const SizedBox(height: 6),
          Text(
            _automatic.isEmpty
                ? 'One is taken automatically each time you open the app, at '
                    'most once a day. The seven most recent are kept.'
                : 'Taken automatically, at most once a day. The seven most '
                    'recent are kept.',
            style: kMutedStyle,
          ),
          const SizedBox(height: 10),
          if (_automatic.isNotEmpty)
            ..._automatic.take(7).map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined,
                            size: 14, color: AppColors.ink600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_readableDate(entry.takenAt),
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.ink200)),
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
