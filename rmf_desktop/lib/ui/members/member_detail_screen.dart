import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/member_detail_bloc.dart';
import '../../data/member_repository.dart';
import '../../data/payment_repository.dart';
import '../../domain/member_status.dart';
import '../../domain/money.dart';
import '../../services/billing_cycle_service.dart';
import '../../services/reminder_service.dart';
import '../../domain/phone.dart';
import '../../theme/app_theme.dart';
import '../payments/advance_payment_dialog.dart';
import '../payments/clear_payments_action.dart';
import '../payments/payment_history_table.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/status_badge.dart';
import 'billing_day_action.dart';
import 'member_form_screen.dart';
import 'restart_billing_action.dart';

class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final int memberId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MemberDetailBloc(
        memberRepository: context.read<MemberRepository>(),
        paymentRepository: context.read<PaymentRepository>(),
        memberId: memberId,
        actorId: context.read<AuthBloc>().state.user!.id,
        cycles: context.read<BillingCycleService>(),
      )..add(const MemberDetailRequested()),
      child: const _MemberDetailView(),
    );
  }
}

class _MemberDetailView extends StatelessWidget {
  const _MemberDetailView();

  Future<void> _confirmToggleActive(
    BuildContext context,
    MemberRow row,
  ) async {
    final bloc = context.read<MemberDetailBloc>();
    final deactivating = row.member.deactivatedAt == null;

    // A member coming back after a gap starts again from the day they came
    // back, so reactivating them asks for that day. One still inside time
    // they already paid for — deactivated by mistake, say — just comes back.
    if (!deactivating &&
        !await context.read<BillingCycleService>().isCoveredOn(row.id)) {
      if (!context.mounted) return;
      final choice = await showRestartBillingDialog(
        context,
        member: row,
        reactivate: true,
      );
      if (choice != null) {
        bloc.add(MemberActiveToggled(active: true, restartFrom: choice.from));
      }
      return;
    }
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.palette.surfaceRaised,
        title: Text(deactivating ? 'Deactivate member?' : 'Reactivate member?'),
        content: Text(
          deactivating
              ? '${row.member.fullName} will be marked inactive. '
                  'Their payment history and receipts are kept.'
              : '${row.member.fullName} will be active again.',
          style: mutedStyleOf(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(deactivating ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      bloc.add(MemberActiveToggled(active: deactivating ? false : true));
    }
  }

  Future<void> _confirmDelete(BuildContext context, MemberRow row) async {
    final bloc = context.read<MemberDetailBloc>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.palette.surfaceRaised,
        title: const Text('Delete this member?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently removes ${row.member.fullName} '
              '(#${row.member.memberCode}). It cannot be undone.',
              style: TextStyle(
                  fontSize: 13, color: dialogContext.palette.textPrimary),
            ),
            const SizedBox(height: 12),
            Text('What will be removed:',
                style: labelStyleOf(dialogContext)),
            const SizedBox(height: 6),
            Text(
              '• Their profile and contact details\n'
              '• Their plan enrolment history\n'
              '• Their billing cycles\n'
              '• Any notes kept against them',
              style: mutedStyleOf(dialogContext),
            ),
            const SizedBox(height: 12),
            Text(
              'No payments are recorded for this member, so no money or '
              'receipts are affected.',
              style: mutedStyleOf(dialogContext),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: keepButtonStyleOf(dialogContext),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: dangerButtonStyleOf(dialogContext),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete member'),
          ),
        ],
      ),
    );

    if (confirmed == true) bloc.add(const MemberDeleteRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MemberDetailBloc, MemberDetailState>(
      listenWhen: (a, b) =>
          a.status != b.status && b.status == MemberDetailStatus.deleted,
      // The member no longer exists, so neither should the screen showing them.
      listener: (context, state) => Navigator.of(context).pop(true),
      child: BlocBuilder<MemberDetailBloc, MemberDetailState>(
      builder: (context, state) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) Navigator.of(context).pop(state.changed);
          },
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: context.palette.surfaceBase,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleSpacing: 0,
              // "← Members", as the handoff's back control reads: it says
              // where it goes, not what you are looking at.
              leadingWidth: 44,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                color: context.palette.textMuted,
                onPressed: () => Navigator.of(context).pop(state.changed),
              ),
              title: Text(
                'Members',
                style: TextStyle(
                    fontSize: 13, color: context.palette.textMuted),
              ),
            ),
            body: switch (state.status) {
              MemberDetailStatus.loading =>
                const Center(child: CircularProgressIndicator()),
              MemberDetailStatus.notFound =>
                const Center(child: Text('Member not found.')),
              MemberDetailStatus.deleting =>
                const Center(child: CircularProgressIndicator()),
              MemberDetailStatus.deleted => const SizedBox.shrink(),
              MemberDetailStatus.ready => _Body(
                  row: state.member!,
                  payments: state.payments,
                  canDelete: state.canDelete,
                  error: state.error,
                  onToggleActive: () =>
                      _confirmToggleActive(context, state.member!),
                  onDelete: () => _confirmDelete(context, state.member!),
                  // Every mutation on this screen reloads through here or
                  // the two buttons below — payments edited, deleted or
                  // cleared, the billing day moved, billing restarted — and
                  // each says so, or the Members list behind would go on
                  // showing a member who just paid as DUE.
                  onPaymentsChanged: () => context
                      .read<MemberDetailBloc>()
                      .add(const MemberDetailRequested(afterChange: true)),
                ),
            },
          ),
        );
      },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.row,
    required this.payments,
    required this.canDelete,
    required this.error,
    required this.onToggleActive,
    required this.onDelete,
    required this.onPaymentsChanged,
  });

  final MemberRow row;
  final List<PaymentRow> payments;
  final bool canDelete;
  final String? error;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;
  final VoidCallback onPaymentsChanged;

  /// Why Delete is unavailable, said before it is pressed rather than after.
  String get _deleteBlockedReason =>
      '${payments.length} payment${payments.length == 1 ? '' : 's'} recorded — '
      'deactivate instead, or delete the payments first';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 48),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
        width: double.infinity,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No inline "← Members" button: the Scaffold's AppBar already has
          // one, and it is the one that carries `state.changed` back to the
          // list so an edit made here shows up there. A second back affordance
          // would be both a duplicate and the one that silently skips the
          // refresh.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InitialsAvatar(
                  name: row.member.fullName, size: 56, onAccent: true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.member.fullName,
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.5,
                                color: palette.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        MemberStatusBadge(status: row.status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${row.member.memberCode} · ${formatPhoneForDisplay(row.member.phone)}'
                      '${row.member.gender != null ? ' · ${row.member.gender}' : ''}',
                      style: TextStyle(fontSize: 13, color: palette.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Reactivate is only offered where it applies; deactivating is a
              // destructive-ish action and lives in the overflow with Delete.
              if (row.member.deactivatedAt != null) ...[
                GhostButton(
                  label: 'Reactivate',
                  icon: Icons.person_outline,
                  onPressed: onToggleActive,
                ),
                const SizedBox(width: 8),
              ],
              Builder(
                builder: (context) => GhostButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onPressed: () async {
                    final bloc = context.read<MemberDetailBloc>();
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => MemberFormScreen(memberId: row.id),
                      ),
                    );
                    if (saved == true) {
                      bloc.add(const MemberDetailRequested(afterChange: true));
                    }
                  },
                ),
              ),
              // Only where the member actually owes something, and read from
              // the same status as the badge beside their name — so the button
              // can never sit next to one reading PAID.
              if (row.status.isOwing) ...[
                const SizedBox(width: 8),
                _SendReminderButton(row: row),
              ],
              const SizedBox(width: 8),
              Builder(
                builder: (context) => AccentButton(
                  label: 'Record payment',
                  icon: Icons.payments_outlined,
                  onPressed: () async {
                    final bloc = context.read<MemberDetailBloc>();
                    final recorded =
                        await showAdvancePaymentDialog(context, member: row);
                    if (recorded == true) {
                      bloc.add(const MemberDetailRequested(afterChange: true));
                    }
                  },
                ),
              ),
              // Destructive actions move out of the main row, as the handoff
              // asks: Delete used to sit between Reactivate and Edit, one
              // mis-click from the button the owner actually wanted.
              _OverflowMenu(
                row: row,
                payments: payments,
                canDelete: canDelete,
                deleteBlockedReason: _deleteBlockedReason,
                onDelete: onDelete,
                onToggleActive: onToggleActive,
                onPaymentsChanged: onPaymentsChanged,
              ),
            ],
          ),
          if (row.status.isOwing) ...[
            const SizedBox(height: 18),
            _DueBanner(row: row),
          ],
          const SizedBox(height: 18),
          // One bordered strip with hairline dividers, rather than five
          // free-floating columns.
          Container(
            decoration: BoxDecoration(
              color: palette.surfaceOverlay,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Detail(label: 'Plan', value: row.plan?.name ?? 'No plan'),
                  _StripDivider(),
                  _Detail(
                    label: 'Fee',
                    value: row.feeMinor == null
                        ? '—'
                        : formatMinorUnits(row.feeMinor!),
                  ),
                  _StripDivider(),
                  _Detail(
                      label: 'Joined',
                      value: formatCalendarDate(row.member.joiningDate)),
                  _StripDivider(),
                  _Detail(
                      label: 'Paid until',
                      value: formatCalendarDate(row.paidUntil)),
                  _StripDivider(),
                  _BillingDayDetail(row: row, onChanged: onPaymentsChanged),
                ],
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.expiredBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(error!,
                  style: TextStyle(
                      color: context.palette.expired, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Payment history',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.palette.textPrimary,
                ),
              ),
              const Spacer(),
              // "Delete all payments" moved into the ⋯ menu beside the other
              // destructive actions, so it is not sitting above the table it
              // would empty.
              if (payments.isNotEmpty)
                Text(
                  '${payments.length} '
                  'payment${payments.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 12, color: context.palette.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _HighlightNewPayments(
            payments: payments,
            builder: (fresh) => PaymentHistoryTable(
              rows: payments,
              showMember: false,
              onMutated: onPaymentsChanged,
              highlightIds: fresh,
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}

/// Sends this member their payment reminder, there and then.
///
/// The Reminders screen sends to everybody the schedule has picked out; this is
/// for the owner who has turned the automatic run off and would rather decide
/// member by member. It therefore does not ask the schedule whether a reminder
/// is owed — with auto-send off nothing ever is, and the button would be dead
/// in exactly the setup it exists for.
///
/// Stateful for one reason: a template message costs money and cannot be
/// recalled, and a send that takes a second over a slow connection is long
/// enough to be clicked twice.
class _SendReminderButton extends StatefulWidget {
  const _SendReminderButton({required this.row});

  final MemberRow row;

  @override
  State<_SendReminderButton> createState() => _SendReminderButtonState();
}

class _SendReminderButtonState extends State<_SendReminderButton> {
  bool _sending = false;

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final actorId = context.read<AuthBloc>().state.user!.id;
    final service = context.read<ReminderService>();
    final name = widget.row.member.fullName;

    setState(() => _sending = true);
    final candidate = await service.candidateForMember(widget.row.id);

    if (candidate == null) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('This member has nothing outstanding to remind them '
            'about.'),
      ));
      return;
    }

    final outcome = await service.send(candidate, actorId: actorId);
    if (!mounted) return;
    setState(() => _sending = false);

    messenger.showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        ReminderSent() => 'Payment reminder sent to $name.',
        ReminderFailed(:final error) => 'Could not send to $name: $error',
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _sending ? null : _send,
      icon: _sending
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.notifications_active_outlined, size: 16),
      label: Text(_sending ? 'Sending…' : 'Send reminder'),
    );
  }
}

/// The member's billing day, resolved and shown alongside a way to change it.
///
/// Resolved rather than read off a raw column: most members have no
/// [Membership.billingAnchorDay] set at all, and the day they actually bill
/// on comes from `resolveAnchorDay`'s fallback — see
/// `BillingCycleService.forMember`.
class _BillingDayDetail extends StatelessWidget {
  const _BillingDayDetail({required this.row, required this.onChanged});

  final MemberRow row;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cycles = context.read<BillingCycleService>();

    return Expanded(
      child: FutureBuilder(
        future: cycles.forMember(row.id),
        builder: (context, snapshot) {
          final anchorDay = snapshot.data?.anchorDay;

          return Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.palette.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BILLING DAY', style: labelStyleOf(context)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        anchorDay == null ? '—' : 'Day $anchorDay',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.palette.textPrimary),
                      ),
                    ),
                    if (anchorDay != null &&
                        row.member.deactivatedAt == null) ...[
                      InkWell(
                        onTap: () async {
                          final choice = await showRestartBillingDialog(
                            context,
                            member: row,
                            reactivate: false,
                          );
                          if (choice != null) onChanged();
                        },
                        child: Tooltip(
                          message: 'Start billing again from the day this '
                              'member came back',
                          child: Text('Restart',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.palette.accent)),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (anchorDay != null)
                      InkWell(
                        onTap: () async {
                          final changed = await showBillingDayDialog(
                            context,
                            member: row,
                            currentAnchorDay: anchorDay,
                          );
                          if (changed) onChanged();
                        },
                        child: Text('Change',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.palette.accent)),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // A plain cell: the strip around it draws the border, so a card here
    // would nest one border inside another.
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: labelStyleOf(context)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.palette.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hairline between two cells of the summary strip.
class _StripDivider extends StatelessWidget {
  const _StripDivider();

  @override
  Widget build(BuildContext context) =>
      VerticalDivider(width: 1, thickness: 1, color: context.palette.border);
}

/// Says plainly what is owed and offers to settle it.
///
/// Shown only where the member actually owes money, reading the same status as
/// the badge beside their name. The handoff puts this above the summary strip
/// because it is the one thing on this screen that needs doing.
class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.row});

  final MemberRow row;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final until = row.paidUntil;
    final late = until == null
        ? null
        : DateTime.now().difference(until).inDays;
    final owed = row.outstandingMinor ?? row.feeMinor;

    return Container(
      decoration: BoxDecoration(
        color: palette.dueBg,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: palette.due),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
                children: [
                  if (owed != null) ...[
                    const TextSpan(text: 'Payment of '),
                    TextSpan(
                      text: formatMinorUnits(owed),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: ' was due'),
                  ] else
                    const TextSpan(text: 'Payment was due'),
                  if (until != null)
                    TextSpan(text: ' on ${formatCalendarDate(until)}'),
                  if (late != null && late > 0)
                    TextSpan(
                        text: ". That's $late day${late == 1 ? '' : 's'} late."),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final bloc = context.read<MemberDetailBloc>();
                final recorded =
                    await showAdvancePaymentDialog(context, member: row);
                if (recorded == true) {
                  bloc.add(const MemberDetailRequested(afterChange: true));
                }
              },
              style: TextButton.styleFrom(foregroundColor: palette.due),
              child: const Text('Record now →'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deactivate, Delete and Delete-all-payments, behind a ⋯ menu.
///
/// These used to sit in the main action row, where Delete was one slot away
/// from Edit. Moving them here keeps them reachable without putting an
/// irreversible action under the cursor on the way to a routine one; each still
/// confirms before doing anything.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.row,
    required this.payments,
    required this.canDelete,
    required this.deleteBlockedReason,
    required this.onDelete,
    required this.onToggleActive,
    required this.onPaymentsChanged,
  });

  final MemberRow row;
  final List<PaymentRow> payments;
  final bool canDelete;
  final String deleteBlockedReason;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;
  final VoidCallback onPaymentsChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = row.member.deactivatedAt == null;

    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_horiz, size: 20, color: palette.textMuted),
      color: palette.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: palette.border),
      ),
      itemBuilder: (context) => [
        if (active)
          PopupMenuItem(
            value: 'deactivate',
            child: Row(
              children: [
                Icon(Icons.person_off_outlined,
                    size: 16, color: palette.textSecondary),
                const SizedBox(width: 10),
                const Text('Deactivate member'),
              ],
            ),
          ),
        if (payments.isNotEmpty)
          PopupMenuItem(
            value: 'clear',
            child: Row(
              children: [
                Icon(Icons.delete_sweep_outlined,
                    size: 16, color: palette.expired),
                const SizedBox(width: 10),
                Text('Delete all payments',
                    style: TextStyle(color: palette.expired)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          enabled: canDelete,
          child: Tooltip(
            message: canDelete ? '' : deleteBlockedReason,
            child: Row(
              children: [
                Icon(Icons.delete_outline,
                    size: 16,
                    color: canDelete ? palette.expired : palette.textMuted),
                const SizedBox(width: 10),
                Text(
                  'Delete member',
                  style: TextStyle(
                      color: canDelete ? palette.expired : palette.textMuted),
                ),
              ],
            ),
          ),
        ),
      ],
      onSelected: (value) async {
        switch (value) {
          case 'deactivate':
            onToggleActive();
          case 'delete':
            onDelete();
          case 'clear':
            final cleared = await confirmAndClearPayments(
              context,
              member: row,
              payments: payments,
            );
            if (cleared) onPaymentsChanged();
        }
      },
    );
  }
}

/// Works out which payments on this profile have just appeared, so the history
/// can tint them.
///
/// "New" means a higher id than anything shown before the last reload — ids
/// only ever grow, so that is exactly the payment the owner just recorded.
/// Nothing is highlighted on the first build: opening a profile is not the
/// moment any of its payments arrived.
class _HighlightNewPayments extends StatefulWidget {
  const _HighlightNewPayments({required this.payments, required this.builder});

  final List<PaymentRow> payments;
  final Widget Function(Set<int> fresh) builder;

  @override
  State<_HighlightNewPayments> createState() => _HighlightNewPaymentsState();
}

class _HighlightNewPaymentsState extends State<_HighlightNewPayments> {
  late int _highestSeen = _highestIn(widget.payments);
  Set<int> _fresh = const {};

  static int _highestIn(List<PaymentRow> rows) =>
      rows.fold(0, (m, r) => r.payment.id > m ? r.payment.id : m);

  @override
  void didUpdateWidget(_HighlightNewPayments old) {
    super.didUpdateWidget(old);
    if (identical(old.payments, widget.payments)) return;
    final before = _highestSeen;
    _fresh = {
      for (final row in widget.payments)
        if (row.payment.id > before) row.payment.id,
    };
    _highestSeen = _highestIn(widget.payments) > before
        ? _highestIn(widget.payments)
        : before;
  }

  @override
  Widget build(BuildContext context) => widget.builder(_fresh);
}
