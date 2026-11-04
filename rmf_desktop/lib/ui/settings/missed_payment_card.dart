import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../domain/money.dart';
import '../../domain/payment_inactivity.dart';
import '../../services/payment_inactivity_service.dart';
import '../../theme/app_theme.dart';
import '../members/member_detail_screen.dart';
import '../payments/payment_history_table.dart';

/// The switch for deactivating members who stop paying, and the list of
/// members the rule leaves for the owner.
///
/// Switching it on never happens blind: the owner is first shown exactly who
/// it would deactivate that day and how much it would write off, because on a
/// gym that has never had the rule that can be dozens of people at once.
class MissedPaymentCard extends StatefulWidget {
  const MissedPaymentCard({super.key, required this.card});

  /// The shared card chrome from the settings screen.
  final Widget Function({
    required String title,
    String? subtitle,
    required Widget child,
  }) card;

  @override
  State<MissedPaymentCard> createState() => _MissedPaymentCardState();
}

class _MissedPaymentCardState extends State<MissedPaymentCard> {
  /// Nullable so a Settings screen built without it — in a widget test —
  /// simply has no card.
  late final PaymentInactivityService? _maybeService =
      context.read<PaymentInactivityService?>();
  PaymentInactivityService get _service => _maybeService!;

  bool? _enabled;
  int? _grace;
  InactivityPreview? _preview;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_maybeService != null) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await _service.isEnabled();
    final grace = await _service.graceDays();
    final preview = await _service.preview();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _grace = grace;
      _preview = preview;
    });
  }

  /// A shorter limit can catch members at once, so while the rule is on the
  /// owner sees who before it is saved — the same promise switching on makes.
  Future<void> _changeGrace(int days) async {
    final actorId = context.read<AuthBloc>().state.user?.id;
    final messenger = ScaffoldMessenger.of(context);

    if (_enabled == true) {
      final preview = await _service.preview(graceDays: days);
      if (!mounted) return;
      if (preview.lapsed.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => _ConfirmDialog(
            preview: preview,
            title: 'Change to $days days?',
            action: 'Change and deactivate',
          ),
        );
        if (confirmed != true) return;
      }
    }

    setState(() => _busy = true);
    try {
      await _service.setGraceDays(days, actorId: actorId);
      if (_enabled == true) {
        final done = await _service.run();
        if (done.isNotEmpty) {
          messenger.showSnackBar(SnackBar(
            content: Text('${_members(done.length)} deactivated for missed '
                'payments.'),
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
  }

  Future<void> _toggle(bool on) async {
    final actorId = context.read<AuthBloc>().state.user?.id;
    final messenger = ScaffoldMessenger.of(context);

    if (on) {
      final preview = await _service.preview();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmDialog(preview: preview),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      await _service.setEnabled(on, actorId: actorId);
      if (on) {
        final done = await _service.run();
        messenger.showSnackBar(SnackBar(
          content: Text(done.isEmpty
              ? 'Switched on. Nobody needed deactivating today.'
              : 'Switched on. ${_members(done.length)} deactivated for missed '
                  'payments.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_maybeService == null) return const SizedBox.shrink();
    final palette = context.palette;
    final enabled = _enabled;
    final grace = _grace ?? paymentInactivityGraceDays;
    final preview = _preview;

    return widget.card(
      title: 'Missed payments',
      subtitle: 'A member whose last month goes $grace days unpaid from its '
          'due date is deactivated, and what that month and the days since '
          'billed is written off. Payments are never touched, and if they '
          'turn out to have kept coming, taking their next payment lets you '
          'restore it. Dates are Pakistan time.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: enabled ?? false,
            onChanged: enabled == null || _busy ? null : _toggle,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: palette.accent,
            title: Text('Deactivate automatically',
                style: TextStyle(fontSize: 13, color: palette.textPrimary)),
            subtitle: Text(
              enabled == true
                  ? 'On — checked when the app opens, on Reload, and every '
                      'hour.'
                  : 'Off — nobody is deactivated or written off.',
              style: mutedStyleOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Deactivate after',
                  style: TextStyle(fontSize: 13, color: palette.textPrimary)),
              DropdownButton<int>(
                value: grace,
                isDense: true,
                onChanged: _grace == null || _busy
                    ? null
                    : (v) {
                        if (v != null && v != grace) _changeGrace(v);
                      },
                items: [
                  for (final days in inactivityGraceDayChoices)
                    DropdownMenuItem(value: days, child: Text('$days days')),
                ],
              ),
              Text('unpaid',
                  style: TextStyle(fontSize: 13, color: palette.textPrimary)),
            ],
          ),
          Text(
            'At most ${inactivityGraceDayChoices.last}: only the month just '
            'ended is judged, so a longer limit would never be reached.',
            style: TextStyle(fontSize: 12, color: palette.textMuted),
          ),
          if (preview != null && enabled == true) ...[
            const SizedBox(height: 12),
            Text(
              preview.upcoming.isEmpty
                  ? 'Nobody is due to be deactivated in the next '
                      '$inactivityWarningDays days.'
                  : 'Deactivating in the next $inactivityWarningDays days '
                      'unless they pay (${preview.upcoming.length}):',
              style: labelStyleOf(context),
            ),
            if (preview.upcoming.isNotEmpty) ...[
              const SizedBox(height: 6),
              _CaseList(cases: preview.upcoming),
            ],
          ],
          if (preview != null && enabled != true && preview.lapsed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Switching on today would deactivate '
                '${_members(preview.lapsed.length)} and write off '
                '${formatMinorUnits(preview.waivedMinor)}.',
                style: TextStyle(fontSize: 13, color: palette.due),
              ),
            ),
          if (preview != null && preview.review.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Needs your decision (${preview.review.length}) — past the '
              '$grace days, but not deactivated automatically:',
              style: labelStyleOf(context),
            ),
            const SizedBox(height: 6),
            _CaseList(cases: preview.review),
          ],
        ],
      ),
    );
  }
}

String _members(int n) => '$n ${n == 1 ? 'member' : 'members'}';

String _reasonOf(PaymentInactivity verdict) => switch (verdict) {
      PaymentInactivityReview(:final reason) => reason.label,
      PaymentInactivityLapsed(:final waivedMinor) =>
        '${formatMinorUnits(waivedMinor)} written off',
      PaymentInactivityGrace(:final deadline) =>
        'deactivated on ${formatCalendarDate(deadline)}',
      PaymentInactivityNone() => '',
    };

DateTime? _dueOf(PaymentInactivity verdict) => switch (verdict) {
      PaymentInactivityReview(:final firstMissedDue) => firstMissedDue,
      PaymentInactivityLapsed(:final firstMissedDue) => firstMissedDue,
      PaymentInactivityGrace(:final firstMissedDue) => firstMissedDue,
      PaymentInactivityNone() => null,
    };

/// Members, one per line, each opening their own screen. Capped in height
/// and scrolled, so a long list never pushes the rest of Settings away.
class _CaseList extends StatelessWidget {
  const _CaseList({required this.cases, this.openable = true});

  final List<InactivityCase> cases;
  final bool openable;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceOverlay,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: cases.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: palette.border),
          itemBuilder: (context, i) {
            final c = cases[i];
            return ListTile(
              dense: true,
              onTap: openable
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            MemberDetailScreen(memberId: c.member.id),
                      ))
                  : null,
              title: Text(
                '#${c.member.memberCode} ${c.member.fullName}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
              ),
              subtitle: Text(
                'Due ${formatCalendarDate(_dueOf(c.verdict))} · '
                '${_reasonOf(c.verdict)}',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
              trailing: openable
                  ? Icon(Icons.chevron_right,
                      size: 18, color: palette.textMuted)
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.preview,
    this.title = 'Deactivate members who stop paying?',
    this.action = 'Switch on',
  });

  final InactivityPreview preview;
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = preview.lapsed.length;

    return AlertDialog(
      backgroundColor: palette.surfaceRaised,
      title: Text(title),
      // Bounded by the window, not a fixed width, so it fits a small screen.
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              count == 0
                  ? 'Nobody qualifies today. From now on, a member is '
                      'deactivated when the month they last owe goes '
                      '${preview.graceDays} days unpaid.'
                  : 'This deactivates ${_members(count)} now and writes off '
                      '${formatMinorUnits(preview.waivedMinor)} they were '
                      'billed for those months. Their payments and receipts '
                      'are kept. Each can be reactivated from their screen; '
                      'what is written off stays written off.',
              style: TextStyle(fontSize: 13, color: palette.textPrimary),
            ),
            if (count > 0) ...[
              const SizedBox(height: 12),
              Flexible(
                child: _CaseList(cases: preview.lapsed, openable: false),
              ),
            ],
            if (preview.review.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${_members(preview.review.length)} part-paid or never paid '
                'are left for you to decide.',
                style: mutedStyleOf(context),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          style: keepButtonStyleOf(context),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(count == 0
              ? action
              : action == 'Switch on'
                  ? 'Switch on and deactivate ${_members(count)}'
                  : '$action ${_members(count)}'),
        ),
      ],
    );
  }
}
