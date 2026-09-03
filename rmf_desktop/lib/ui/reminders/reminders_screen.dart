import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/settings_repository.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/phone.dart';
import '../../domain/reminder_schedule.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';

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

  ReminderService get _service => context.read<ReminderService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await context.read<SettingsRepository>().get();
    final queue = await _service.buildQueue();
    if (!mounted) return;
    setState(() {
      _queue = queue;
      _currency = settings.currency;
      _selected
        ..clear()
        ..addAll(queue.map((c) => c.member.id));
      _loading = false;
    });
  }

  Future<void> _sendSelected() async {
    final actorId = context.read<AuthBloc>().state.user!.id;
    final toSend =
        _queue.where((c) => _selected.contains(c.member.id)).toList();
    if (toSend.isEmpty) return;

    setState(() => _sending = true);

    var sent = 0;
    var failed = 0;
    for (final candidate in toSend) {
      final outcome = await _service.send(candidate, actorId: actorId);
      if (outcome is ReminderSent) {
        sent++;
      } else {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0
          ? 'Sent $sent reminder${sent == 1 ? '' : 's'}.'
          : 'Sent $sent, $failed could not be sent — see the Logs screen.'),
    ));
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
          const SizedBox(height: 20),
          if (_queue.isEmpty)
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
            FilledButton.icon(
              onPressed: (_sending || _selected.isEmpty) ? null : _sendSelected,
              icon: const Icon(Icons.send_outlined, size: 16),
              label: Text(_sending
                  ? 'Sending…'
                  : 'Send selected (${_selected.length})'),
            ),
          ],
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
                Text(maskPhone(candidate.member.phone),
                    style: mutedStyleOf(context)),
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
