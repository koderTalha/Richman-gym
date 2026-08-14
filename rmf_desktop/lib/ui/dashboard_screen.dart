import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/dashboard_bloc.dart';
import '../data/member_repository.dart';
import '../data/payment_repository.dart';
import '../data/receipt_repository.dart';
import '../domain/money.dart';
import '../theme/app_theme.dart';
import 'payments/payment_history_table.dart';
import 'widgets/status_badge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DashboardBloc(
        memberRepository: context.read<MemberRepository>(),
        paymentRepository: context.read<PaymentRepository>(),
        receiptRepository: context.read<ReceiptRepository>(),
      )..add(const DashboardRequested()),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        if (state.status == DashboardStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == DashboardStatus.failed) {
          return Center(
            child: Text('Could not load the dashboard: ${state.error}',
                style: TextStyle(color: context.palette.expired)),
          );
        }

        final due = state.dueMembers;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Dashboard',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.palette.textPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => context
                        .read<DashboardBloc>()
                        .add(const DashboardRequested()),
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _StatCard(
                      label: 'Total members', value: '${state.members.length}'),
                  _StatCard(
                      label: 'Active members', value: '${state.activeCount}'),
                  _StatCard(
                    label: 'Payments due',
                    value: '${due.length}',
                    tone: due.isEmpty ? null : context.palette.due,
                  ),
                  _StatCard(
                      label: 'Revenue today',
                      value: formatMinorUnits(state.revenueTodayMinor)),
                  _StatCard(
                      label: 'Revenue this month',
                      value: formatMinorUnits(state.revenueMonthMinor)),
                  _StatCard(
                      label: 'Payments today',
                      value: '${state.paymentsToday}'),
                  _StatCard(
                    label: 'Failed WhatsApp',
                    value: '${state.failedWhatsApp}',
                    tone: state.failedWhatsApp == 0
                        ? null
                        : context.palette.expired,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('RECENT PAYMENTS', style: labelStyleOf(context)),
              const SizedBox(height: 10),
              PaymentHistoryTable(rows: state.recent),
              const SizedBox(height: 28),
              Text('MEMBERS WITH PAYMENTS DUE', style: labelStyleOf(context)),
              const SizedBox(height: 10),
              _DueList(rows: due.take(8).toList()),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: labelStyleOf(context)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: tone ?? context.palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DueList extends StatelessWidget {
  const _DueList({required this.rows});

  final List<MemberRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.palette.border),
        ),
        child: Text('Everyone is paid up.', style: mutedStyleOf(context)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i].member.fullName,
                            style: TextStyle(
                                fontSize: 13, color: context.palette.textPrimary)),
                        Text(
                          '#${rows[i].member.memberCode} · ${rows[i].member.phone}',
                          style: mutedStyleOf(context),
                        ),
                      ],
                    ),
                  ),
                  MemberStatusBadge(status: rows[i].status),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
