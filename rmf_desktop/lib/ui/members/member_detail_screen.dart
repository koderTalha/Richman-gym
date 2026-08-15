import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MemberDetailBloc, MemberDetailState>(
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
              MemberDetailStatus.ready =>
                _Body(row: state.member!, payments: state.payments,
                    onToggleActive: () =>
                        _confirmToggleActive(context, state.member!)),
            },
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.row,
    required this.payments,
    required this.onToggleActive,
  });

  final MemberRow row;
  final List<PaymentRow> payments;
  final VoidCallback onToggleActive;

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
          const SizedBox(height: 24),
          Text('PAYMENT HISTORY', style: labelStyleOf(context)),
          const SizedBox(height: 10),
          PaymentHistoryTable(rows: payments, showMember: false),
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
