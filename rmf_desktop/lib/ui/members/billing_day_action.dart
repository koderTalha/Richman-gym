import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/member_repository.dart';
import '../../domain/dates.dart';
import '../../services/billing_cycle_service.dart';
import '../../theme/app_theme.dart';

/// Lets the owner move a member onto a different billing day.
///
/// Nothing already recorded ever moves: only the next cycle is affected, and
/// it runs as a one-off transition onto the new day rather than a normal
/// cycle — see `BillingCycleService.setAnchorDay`. The dialog shows that
/// transition before the owner confirms, so "the 6th becomes the 20th" is
/// never a surprise on the next bill.
///
/// Returns true if the day was changed, so the caller can refresh.
Future<bool> showBillingDayDialog(
  BuildContext context, {
  required MemberRow member,
  required int currentAnchorDay,
}) async {
  final cycles = context.read<BillingCycleService>();
  final actorId = context.read<AuthBloc>().state.user!.id;

  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _BillingDayDialog(
      member: member,
      currentAnchorDay: currentAnchorDay,
      cycles: cycles,
      actorId: actorId,
    ),
  );

  return changed ?? false;
}

class _BillingDayDialog extends StatefulWidget {
  const _BillingDayDialog({
    required this.member,
    required this.currentAnchorDay,
    required this.cycles,
    required this.actorId,
  });

  final MemberRow member;
  final int currentAnchorDay;
  final BillingCycleService cycles;
  final int actorId;

  @override
  State<_BillingDayDialog> createState() => _BillingDayDialogState();
}

class _BillingDayDialogState extends State<_BillingDayDialog> {
  late int _selectedDay = widget.currentAnchorDay;
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.cycles.setAnchorDay(
        memberId: widget.member.id,
        anchorDay: _selectedDay,
        actorId: widget.actorId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changed = _selectedDay != widget.currentAnchorDay;

    return AlertDialog(
      backgroundColor: context.palette.surfaceRaised,
      title: const Text('Change billing day'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.member.member.fullName} currently bills on day '
              '${widget.currentAnchorDay} of the month.',
              style: mutedStyleOf(context),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _selectedDay,
              decoration:
                  const InputDecoration(labelText: 'New billing day', isDense: true),
              items: [
                for (var day = 1; day <= 31; day++)
                  DropdownMenuItem(value: day, child: Text('$day')),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _selectedDay = v ?? _selectedDay),
            ),
            if (changed) ...[
              const SizedBox(height: 14),
              _TransitionPreview(
                cycles: widget.cycles,
                memberId: widget.member.id,
                anchorDay: _selectedDay,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: context.palette.expired, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_busy || !changed) ? null : _confirm,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

/// What the member's next cycle would look like with the new anchor,
/// computed without writing anything.
class _TransitionPreview extends StatelessWidget {
  const _TransitionPreview({
    required this.cycles,
    required this.memberId,
    required this.anchorDay,
  });

  final BillingCycleService cycles;
  final int memberId;
  final int anchorDay;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: cycles.previewAnchorChange(memberId: memberId, anchorDay: anchorDay),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        if (preview == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.palette.surfaceBase,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Nothing already paid changes. The next cycle runs '
            '${formatDayMonthYear(preview.start)} to '
            '${formatDayMonthYear(preview.end)} (${preview.lengthInDays} days) '
            'to move onto the new day.',
            style: mutedStyleOf(context),
          ),
        );
      },
    );
  }
}
