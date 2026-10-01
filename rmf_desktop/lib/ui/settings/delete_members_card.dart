import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../bloc/auth_bloc.dart';
import '../../data/audit_repository.dart';
import '../../data/database.dart';
import '../../domain/money.dart';
import '../../services/backup_service.dart';
import '../../services/member_purge_service.dart';
import '../../services/receipt_storage.dart';
import '../../theme/app_theme.dart';

final _log = Logger('members');

/// What the owner has to type before the button will do anything.
///
/// Not the gym's name or a member's, which are the two things already on the
/// screen and could be copied without reading. This phrase says what is about
/// to happen and exists nowhere else, so typing it is a sentence the owner
/// wrote themselves.
const deleteMembersConfirmPhrase = 'DELETE MEMBERS';

/// Finds the confirm button without matching a label that may be reworded.
const deleteMembersConfirmKey = Key('delete-members-confirm');
const deleteMembersOpenKey = Key('delete-members-open');

/// Deletes every member and everything belonging to one.
///
/// Its own widget with local state rather than a bloc, like [BackupCard]: it
/// owns nothing the rest of Settings reads, and the one figure it shows comes
/// straight from the same service that does the deleting.
class DeleteMembersCard extends StatefulWidget {
  const DeleteMembersCard({super.key, required this.card, this.takeBackup});

  /// The shared card chrome from the settings screen.
  final Widget Function({
    required String title,
    String? subtitle,
    required Widget child,
  }) card;

  /// Takes the backup that has to exist before anything is deleted. Null in
  /// the app, which writes it beside the automatic daily backups — where the
  /// Backup card lists it and a restore can pick it up. Injected by tests,
  /// which have no application-support folder to write into.
  final Future<BackupResult> Function()? takeBackup;

  @override
  State<DeleteMembersCard> createState() => _DeleteMembersCardState();
}

class _DeleteMembersCardState extends State<DeleteMembersCard> {
  MemberDataCounts? _counts;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  MemberPurgeService get _service => MemberPurgeService(
        db: context.read<AppDatabase>(),
        storage: context.read<ReceiptStorage>(),
        audit: context.read<AuditRepository>(),
      );

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await _service.counts();
      if (!mounted) return;
      setState(() => _counts = counts);
    } catch (error, stack) {
      _log.severe('Counting member data failed', error, stack);
      if (mounted) setState(() => _counts = null);
    }
  }

  /// The default for [DeleteMembersCard.takeBackup]: a full backup — the
  /// database, the receipt files and the workbook — into the automatic
  /// backups folder. Not `autoBackup`, which skips a day that already has one:
  /// this has to capture the data as it is at this moment, not as it was at
  /// this morning's launch.
  Future<BackupResult> _backupBeside() async {
    final backups = BackupService(context.read<AppDatabase>());
    return backups.backupTo(await backups.automaticBackupDirectory());
  }

  Future<void> _delete() async {
    // Counted again now, not taken from when the card loaded: Settings can sit
    // open for an afternoon of payments, and the dialog is the owner's last
    // look at what they are about to lose.
    MemberDataCounts counts;
    try {
      counts = await _service.counts();
    } catch (error, stack) {
      _log.severe('Counting member data failed', error, stack);
      return;
    }
    if (!mounted) return;
    setState(() => _counts = counts);
    if (counts.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteMembersConfirmDialog(counts: counts),
    );
    if (confirmed != true || !mounted) return;

    final actorId = context.read<AuthBloc>().state.user!.id;
    final service = _service;
    final takeBackup = widget.takeBackup ?? _backupBeside;
    setState(() {
      _busy = true;
      _message = null;
    });

    // Before the delete, and a hard precondition of it. The dialog told the
    // owner a backup is the only way back; taking one for them means a slip of
    // the keyboard on this card is recoverable rather than final. If it cannot
    // be written, nothing is deleted — a purge with no way back is not one to
    // perform on the owner's behalf.
    final String backupName;
    try {
      final backup = await takeBackup();
      backupName = p.basename(backup.folder.path);
    } catch (error, stack) {
      _log.severe('Backup before deleting all member data failed', error,
          stack);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Nothing was deleted — a backup could not be taken first, '
            'and without one there would be no way back. ($error)';
        _messageIsError = true;
      });
      return;
    }
    if (!mounted) return;

    MemberPurgeResult result;
    try {
      result = await service.purgeAll(actorId: actorId);
    } catch (error, stack) {
      // The delete runs in one transaction, so a failure here left the data
      // exactly as it was. Saying so matters: the owner's next move otherwise
      // is to press the button again on a database they think is half emptied.
      _log.severe('Deleting all member data failed', error, stack);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Nothing was deleted — the operation failed and every '
            'record is still there. See the Logs screen.';
        _messageIsError = true;
      });
      return;
    }

    await _loadCounts();
    if (!mounted) return;

    setState(() {
      _busy = false;
      switch (result) {
        case MemberDataPurged(:final counts, :final orphanedFiles):
          _messageIsError = false;
          _message = '${counts.members} '
              '${counts.members == 1 ? 'member' : 'members'} and all their '
              'records were deleted — ${counts.payments} '
              '${counts.payments == 1 ? 'payment' : 'payments'}, '
              '${counts.receipts} '
              '${counts.receipts == 1 ? 'receipt' : 'receipts'} and '
              '${counts.billingCycles} billing '
              '${counts.billingCycles == 1 ? 'cycle' : 'cycles'}. Plans, '
              'settings and the activity log were kept. A backup taken just '
              'before is in $backupName.'
              '${orphanedFiles.isEmpty ? '' : ' Some receipt files could not '
                  'be removed from disk — see the Logs screen.'}';
        case MemberPurgeRefused(:final message):
          _messageIsError = false;
          _message = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    final palette = context.palette;
    final nothingToDelete = counts == null || counts.isEmpty;

    return widget.card(
      title: 'Delete all members data',
      subtitle: 'Removes every member from this computer, permanently.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.expiredBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.expired.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This deletes every member together with their payments, '
                  'receipts, billing history, reminders, notes and WhatsApp '
                  'records. It cannot be undone, and there is no way back '
                  'without a backup.',
                  style: TextStyle(color: palette.expired, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Membership plans, gym settings, your account and the '
                  'activity log are kept.',
                  style: TextStyle(
                      color: palette.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (counts != null) _Summary(counts: counts),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(
                fontSize: 12.5,
                color: _messageIsError ? palette.expired : palette.paid,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: deleteMembersOpenKey,
              style: FilledButton.styleFrom(
                backgroundColor: palette.expired,
                disabledBackgroundColor: palette.inactiveBg,
              ),
              onPressed: _busy || nothingToDelete ? null : _delete,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_forever, size: 18),
              label: Text(nothingToDelete && !_busy
                  ? 'No member data to delete'
                  : 'Delete all members data'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.counts});

  final MemberDataCounts counts;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Line(label: 'Members', value: '${counts.members}'),
        _Line(
          label: 'Payments',
          value: '${counts.payments} · '
              '${formatMinorUnits(counts.paymentTotalMinor)}',
        ),
        _Line(label: 'Receipts', value: '${counts.receipts}'),
        _Line(label: 'Billing cycles', value: '${counts.billingCycles}'),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: mutedStyleOf(context)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// The question itself, kept free of repositories and services so the guard
/// that makes it safe — the owner having to type the phrase — can be tested on
/// its own, as `ClearPaymentsConfirmDialog` is.
class DeleteMembersConfirmDialog extends StatefulWidget {
  const DeleteMembersConfirmDialog({super.key, required this.counts});

  final MemberDataCounts counts;

  @override
  State<DeleteMembersConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<DeleteMembersConfirmDialog> {
  final _typed = TextEditingController();

  /// Exact, unlike the member-name prompt on the payments screen. Stray spaces
  /// are forgiven because they are invisible; the capitals are not, because
  /// they are the whole of what makes this harder to type than "yes".
  bool get _phraseMatches =>
      _typed.text.trim() == deleteMembersConfirmPhrase;

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counts = widget.counts;

    return AlertDialog(
      backgroundColor: context.palette.surfaceRaised,
      title: const Text('Delete all members data?'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Every member on this computer will be deleted, along with '
                'everything recorded about them. This cannot be undone.',
                style: mutedStyleOf(context),
              ),
              const SizedBox(height: 14),
              _Line(label: 'Members', value: '${counts.members}'),
              _Line(
                label: 'Payments',
                value: '${counts.payments} · '
                    '${formatMinorUnits(counts.paymentTotalMinor)}',
              ),
              _Line(label: 'Receipts', value: '${counts.receipts}'),
              _Line(label: 'Billing cycles', value: '${counts.billingCycles}'),
              _Line(label: 'Reminders', value: '${counts.reminders}'),
              _Line(label: 'Notes', value: '${counts.notes}'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.palette.expiredBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Receipt files are removed from disk with the records. A '
                  'backup is taken automatically before anything is deleted — '
                  'it is the only way any of this comes back.',
                  style: TextStyle(
                      color: context.palette.expired, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 16),
              Text('Type $deleteMembersConfirmPhrase to confirm',
                  style: mutedStyleOf(context)),
              const SizedBox(height: 6),
              TextField(
                controller: _typed,
                autofocus: true,
                decoration: const InputDecoration(isDense: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep everything'),
        ),
        FilledButton(
          key: deleteMembersConfirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.expired,
          ),
          onPressed:
              _phraseMatches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}
