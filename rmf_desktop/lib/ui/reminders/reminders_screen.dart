import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/database.dart';
import '../../data/settings_repository.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/phone.dart';
import '../../domain/reminder_schedule.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';

final _log = Logger('reminders');

/// Who is due, who is overdue, and one place to send to all of them.
///
/// There is no cron in a desktop app with no server: this screen — and the
/// opt-in automatic run behind Settings — is what "automatic reminders" can
/// mean here. See `ReminderService` for the reasoning.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<ReminderCandidate> _queue = const [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _sending = false;
  String? _currency;

  /// Set when the queue could not be built. Shown in place of the list, with
  /// a way to try again: a spinner that never stops reads as "still
  /// working", and the owner would wait on it indefinitely.
  String? _error;

  /// The Mock provider records every reminder as sent — and a sent reminder
  /// is never offered again — while nothing actually leaves the machine. Said
  /// here as well as on the WhatsApp screen, because this is where the owner
  /// presses Send.
  bool _mockProvider = false;

  ReminderService get _service => context.read<ReminderService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Read before the first await: the context must not be used across an
    // async gap.
    final settingsRepository = context.read<SettingsRepository>();
    final service = _service;

    try {
      final settings = await settingsRepository.get();
      final queue = await service.buildQueue();
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _currency = settings.currency;
        _mockProvider = settings.whatsappProvider != WhatsAppProviderKind.meta;
        _selected
          ..clear()
          ..addAll(queue.map((c) => c.member.id));
        _loading = false;
      });
    } catch (error, stack) {
      _log.severe('The reminder queue could not be built', error, stack);
      if (!mounted) return;
      setState(() {
        _queue = const [];
        _selected.clear();
        _error = 'The reminders could not be loaded. Try again, or see the '
            'Logs screen.';
        _loading = false;
      });
    }
  }

  Future<void> _sendSelected() async {
    final actorId = context.read<AuthBloc>().state.user!.id;
    final toSend =
        _queue.where((c) => _selected.contains(c.member.id)).toList();
    if (toSend.isEmpty) return;

    setState(() => _sending = true);

    final service = _service;
    var sent = 0;
    var failed = 0;
    // Paid, already sent by the automatic run, or being sent by it right now
    // — see `ReminderService.send`. Not a failure, so not counted as one.
    var notNeeded = 0;
    for (final candidate in toSend) {
      final outcome = await service.send(candidate, actorId: actorId);
      switch (outcome) {
        case ReminderSent():
          sent++;
        case ReminderNotNeeded():
          notNeeded++;
        case ReminderFailed():
          failed++;
      }
    }

    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text([
        failed == 0
            ? 'Sent $sent reminder${sent == 1 ? '' : 's'}.'
            : 'Sent $sent, $failed could not be sent — see the Logs screen.',
        if (notNeeded > 0)
          '$notNeeded no longer needed: paid or already reminded since the '
              'list was loaded.',
      ].join(' ')),
    ));
    await _load();
  }

  /// Clears the whole queue without messaging anybody.
  ///
  /// The counter deals with most of these in person — the member pays on the
  /// way in, or is chased on the phone — and the queue is then a list of
  /// people who must not be sent a template. Confirmed first, because it is
  /// the whole screen at once and each one is somebody the gym is owed by.
  Future<void> _clearAll() async {
    final count = _queue.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.palette.surfaceRaised,
        title: Text('Clear $count reminder${count == 1 ? '' : 's'}?'),
        content: Text(
          'Nothing is sent. These members drop off this screen and will not '
          'be messaged about the payment they owe now. Each one comes back '
          'here when their next payment falls due.',
          style: mutedStyleOf(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final actorId = context.read<AuthBloc>().state.user!.id;
    final service = _service;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);

    var cleared = 0;
    try {
      for (final candidate in _queue) {
        await service.dismiss(candidate, actorId: actorId);
        cleared++;
      }
      messenger.showSnackBar(SnackBar(
        content: Text('Cleared $count reminder${count == 1 ? '' : 's'} '
            'without sending.'),
      ));
    } catch (error, stack) {
      _log.severe('Clearing the reminder queue failed', error, stack);
      messenger.showSnackBar(SnackBar(
        content: Text('Cleared $cleared of $count, then something went '
            'wrong — see the Logs screen.'),
      ));
    }

    if (!mounted) return;
    setState(() => _sending = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Reminders',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary)),
              const SizedBox(width: 12),
              if (_queue.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.palette.dueBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${_queue.length} need attention',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.palette.due)),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          if (_mockProvider) ...[
            const SizedBox(height: 16),
            const _MockProviderWarning(),
          ],
          const SizedBox(height: 20),
          if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.palette.expired)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_queue.isEmpty)
            Expanded(
              child: Center(
                child: Text('Nobody is due or overdue right now.',
                    style: mutedStyleOf(context)),
              ),
            )
          else ...[
            Expanded(
              child: ListView.separated(
                itemCount: _queue.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) =>
                    _ReminderTile(
                  candidate: _queue[i],
                  currency: _currency,
                  selected: _selected.contains(_queue[i].member.id),
                  onToggle: (v) => setState(() {
                    if (v) {
                      _selected.add(_queue[i].member.id);
                    } else {
                      _selected.remove(_queue[i].member.id);
                    }
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _sending ? null : _clearAll,
                  icon: const Icon(Icons.done_all, size: 16),
                  label: Text('Clear all (${_queue.length})'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed:
                      (_sending || _selected.isEmpty) ? null : _sendSelected,
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: Text(_sending
                      ? 'Sending…'
                      : 'Send selected (${_selected.length})'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Key on the Mock-provider warning, for tests.
const remindersMockWarningKey = Key('reminders-mock-warning');

class _MockProviderWarning extends StatelessWidget {
  const _MockProviderWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: remindersMockWarningKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.dueBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: context.palette.due),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'WhatsApp is in Mock mode: nothing sent from here reaches '
              'anybody, yet each reminder is recorded as sent and will not '
              'be offered again. Switch to Meta in Settings before sending.',
              style: TextStyle(fontSize: 12, color: context.palette.due),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.candidate,
    required this.currency,
    required this.selected,
    required this.onToggle,
  });

  final ReminderCandidate candidate;
  final String? currency;
  final bool selected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final stageLabel = switch (candidate.stage) {
      ReminderStage.beforeDue =>
        'Due ${formatDayMonthYear(candidate.dueDate)}',
      ReminderStage.onDue => 'Due today',
      ReminderStage.overdue =>
        'Overdue ${candidate.offsetDays} day${candidate.offsetDays == 1 ? '' : 's'}',
    };
    final (fg, bg) = switch (candidate.stage) {
      ReminderStage.beforeDue => (context.palette.due, context.palette.dueBg),
      ReminderStage.onDue => (context.palette.due, context.palette.dueBg),
      ReminderStage.overdue =>
        (context.palette.expired, context.palette.expiredBg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (v) => onToggle(v ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.member.fullName,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.palette.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  candidate.retry
                      ? '${maskPhone(candidate.member.phone)} · '
                          'last attempt could not be sent'
                      : maskPhone(candidate.member.phone),
                  style: mutedStyleOf(context),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(stageLabel,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 90,
            child: Text(
              formatMinorUnits(candidate.amountDueMinor, currency ?? 'PKR'),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
