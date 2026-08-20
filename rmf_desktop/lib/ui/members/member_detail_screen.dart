import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/member_detail_bloc.dart';
import '../../data/member_repository.dart';
import '../../data/payment_repository.dart';
import '../../domain/money.dart';
import '../../theme/app_theme.dart';
import '../payments/payment_history_table.dart';
import '../payments/record_payment_dialog.dart';
import '../widgets/status_badge.dart';
import 'member_form_screen.dart';

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
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.palette.expired,
            ),
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
              backgroundColor: context.palette.surfaceRaised,
              title: const Text('Member'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(state.changed),
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
                  onPaymentsChanged: () => context
                      .read<MemberDetailBloc>()
                      .add(const MemberDetailRequested()),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          row.member.fullName,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: context.palette.textPrimary),
                        ),
                        const SizedBox(width: 12),
                        MemberStatusBadge(status: row.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#${row.member.memberCode} · ${row.member.phone}'
                      '${row.member.gender != null ? ' · ${row.member.gender}' : ''}',
                      style: mutedStyleOf(context),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onToggleActive,
                icon: Icon(
                  row.member.deactivatedAt == null
                      ? Icons.person_off_outlined
                      : Icons.person_outline,
                  size: 16,
                ),
                label: Text(row.member.deactivatedAt == null
                    ? 'Deactivate'
                    : 'Reactivate'),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: canDelete
                    ? 'Permanently remove this member'
                    : _deleteBlockedReason,
                child: OutlinedButton.icon(
                  onPressed: canDelete ? onDelete : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.expired,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 10),
              Builder(
                builder: (context) => OutlinedButton.icon(
                  onPressed: () async {
                    final bloc = context.read<MemberDetailBloc>();
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => MemberFormScreen(memberId: row.id),
                      ),
                    );
                    if (saved == true) {
                      bloc.add(const MemberDetailRequested());
                    }
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 10),
              Builder(
                builder: (context) => FilledButton.icon(
                  onPressed: () async {
                    final bloc = context.read<MemberDetailBloc>();
                    final recorded =
                        await showRecordPaymentDialog(context, member: row);
                    if (recorded == true) {
                      bloc.add(const MemberDetailRequested());
                    }
                  },
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Record Payment'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _Detail(label: 'Plan', value: row.plan?.name ?? 'No plan'),
              _Detail(
                label: 'Fee',
                value: row.feeMinor == null
                    ? '—'
                    : formatMinorUnits(row.feeMinor!),
              ),
              _Detail(
                  label: 'Joined',
                  value: formatCalendarDate(row.member.joiningDate)),
              _Detail(
                  label: 'Paid until',
                  value: formatCalendarDate(row.paidUntil)),
            ],
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
          Text('PAYMENT HISTORY', style: labelStyleOf(context)),
          const SizedBox(height: 10),
          PaymentHistoryTable(
            rows: payments,
            showMember: false,
            onMutated: onPaymentsChanged,
          ),
        ],
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
    return Expanded(
      child: Container(
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
            Text(label.toUpperCase(), style: labelStyleOf(context)),
            const SizedBox(height: 6),
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
