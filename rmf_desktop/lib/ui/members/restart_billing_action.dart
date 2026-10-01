import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/member_repository.dart';
import '../../domain/dates.dart';
import '../../services/billing_cycle_service.dart';
import '../../theme/app_theme.dart';

/// What the owner chose in [showRestartBillingDialog].
class RestartChoice {
  const RestartChoice(this.from);

  /// The day billing starts again, or null to reactivate without restarting.
  final DateTime? from;
}

/// Starts a returning member's billing again from the day they came back —
/// see `BillingCycleService.restartBilling`.
///
/// Two ways in. Reactivating a member who is not paid up today asks for the
/// day they came back ([reactivate] true) and hands the choice back for the
/// member screen's bloc to apply alongside the reactivation. The "Restart"
/// link beside the billing day applies it here directly, for a member who is
/// already active — which is how the owner straightens out somebody whose
/// return was recorded before this existed.
///
/// Returns null if the owner cancelled.
Future<RestartChoice?> showRestartBillingDialog(
  BuildContext context, {
  required MemberRow member,
  required bool reactivate,
}) async {
  final cycles = context.read<BillingCycleService>();
  final actorId = context.read<AuthBloc>().state.user!.id;
  final suggested = reactivate
      ? DateTime.now()
      : await cycles.suggestedRestartDay(member.id);
  if (!context.mounted) return null;

  return showDialog<RestartChoice>(
    context: context,
    builder: (_) => _RestartBillingDialog(
      member: member,
      reactivate: reactivate,
      initialDay: suggested,
      cycles: cycles,
      actorId: actorId,
    ),
  );
}

class _RestartBillingDialog extends StatefulWidget {
  const _RestartBillingDialog({
    required this.member,
    required this.reactivate,
    required this.initialDay,
    required this.cycles,
    required this.actorId,
  });

  final MemberRow member;
  final bool reactivate;
  final DateTime initialDay;
  final BillingCycleService cycles;
  final int actorId;

  @override
  State<_RestartBillingDialog> createState() => _RestartBillingDialogState();
}

class _RestartBillingDialogState extends State<_RestartBillingDialog> {
  /// A UTC midnight, the way cycle boundaries are stored.
  late DateTime _from = _utcDay(widget.initialDay);
  late Future<BillingRestart> _preview = _load();
  bool _busy = false;
  String? _error;

  static DateTime _utcDay(DateTime at) => DateTime.utc(at.year, at.month, at.day);

  Future<BillingRestart> _load() =>
      widget.cycles.previewRestart(memberId: widget.member.id, from: _from);

  Future<void> _pickDay() async {
    final today = DateTime.now();
    final joined = widget.member.member.joiningDate.toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_from.year, _from.month, _from.day),
      firstDate: DateTime(joined.year, joined.month, joined.day),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'Day they came back',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = _utcDay(picked);
      _preview = _load();
      _error = null;
    });
  }

  Future<void> _confirm() async {
    if (widget.reactivate) {
      Navigator.of(context).pop(RestartChoice(_from));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.cycles.restartBilling(
        memberId: widget.member.id,
        from: _from,
        actorId: widget.actorId,
      );
      if (!mounted) return;
      if (result is BillingRestartRefused) {
        setState(() => _error = result.reason);
      } else {
        Navigator.of(context).pop(RestartChoice(_from));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.member.member.fullName;

    return AlertDialog(
      backgroundColor: context.palette.surfaceRaised,
      title: Text(widget.reactivate ? 'Reactivate $name' : 'Restart billing'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<BillingRestart>(
          future: _preview,
          builder: (context, snapshot) {
            final preview = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Billing starts again from the day $name came back. The '
                  'months they were away are not charged.',
                  style: mutedStyleOf(context),
                ),
                const SizedBox(height: 14),
                Text('CAME BACK ON', style: labelStyleOf(context)),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickDay,
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: Text(formatDayMonthYear(_from)),
                ),
                const SizedBox(height: 14),
                if (preview == null)
                  const SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _Preview(preview: preview),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: context.palette.expired, fontSize: 12)),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FutureBuilder<BillingRestart>(
          future: _preview,
          builder: (context, snapshot) {
            final ready = snapshot.data is BillingRestartPlan;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A refusal must not leave a returning member impossible to
                // reactivate; the old cadence is still there to fall back on.
                if (widget.reactivate &&
                    snapshot.data is BillingRestartRefused) ...[
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(const RestartChoice(null)),
                    child: const Text('Reactivate only'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: (_busy || !ready) ? null : _confirm,
                  child: Text(_busy
                      ? 'Saving…'
                      : widget.reactivate
                          ? 'Reactivate'
                          : 'Restart billing'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// What will change, in the order the owner thinks about it: what the money
/// covers, what is no longer owed, and when they next pay.
class _Preview extends StatelessWidget {
  const _Preview({required this.preview});

  final BillingRestart preview;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final preview = this.preview;

    if (preview is BillingRestartRefused) {
      return _Box(
        background: palette.expiredBg,
        child: Text(preview.reason,
            style: TextStyle(color: palette.expired, fontSize: 12.5)),
      );
    }
    preview as BillingRestartPlan;

    String span(DateTime a, DateTime b) =>
        '${formatDayMonthYear(a)} to ${formatDayMonthYear(b)}';
    final first = preview.firstCycle;
    final lines = <String>[
      if (preview.moved != null)
        'The payment already taken covers ${span(first.start, first.end)}.'
      else
        'First month: ${span(first.start, first.end)}, to be paid.',
      for (final c in preview.dropped)
        c.expectedMinor == 0
            ? 'Free days ${span(c.start, c.end)} are now part of that month.'
            : 'No longer owed: ${span(c.start, c.end)}.',
      'Billing day becomes ${preview.anchorDay}'
          '${preview.anchorDay == preview.previousAnchorDay ? '' : ' (was ${preview.previousAnchorDay})'}.',
      'Next payment due: ${formatDayMonthYear(preview.nextDue)}.',
    ];

    return _Box(
      background: palette.surfaceBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $line', style: mutedStyleOf(context)),
            ),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.background, required this.child});

  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      );
}
