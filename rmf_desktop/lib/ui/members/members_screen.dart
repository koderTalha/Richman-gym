import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/members_bloc.dart';
import '../../data/member_repository.dart';
import '../../domain/money.dart';
import '../../theme/app_theme.dart';
import '../payments/payment_history_table.dart' show formatShortDate;
import '../payments/record_payment_dialog.dart';
import '../widgets/status_badge.dart';
import 'import_members_screen.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MembersBloc(context.read<MemberRepository>())
        ..add(const MembersRequested()),
      child: const _MembersView(),
    );
  }
}

class _MembersView extends StatefulWidget {
  const _MembersView();

  @override
  State<_MembersView> createState() => _MembersViewState();
}

class _MembersViewState extends State<_MembersView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() => context
      .read<MembersBloc>()
      .add(MembersSearchSubmitted(_searchController.text));

  Future<void> _recordPayment(MemberRow member) async {
    final bloc = context.read<MembersBloc>();
    final recorded = await showRecordPaymentDialog(context, member: member);
    if (recorded == true) bloc.add(const MembersRequested());
  }

  /// Pushes a route and reloads the list if it reports that something changed.
  Future<void> _openRoute(Widget screen) async {
    final bloc = context.read<MembersBloc>();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (changed == true) bloc.add(const MembersRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Members',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: context.palette.textPrimary),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _openRoute(const ImportMembersScreen()),
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Import from Excel'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _openRoute(const MemberFormScreen()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Member'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          BlocBuilder<MembersBloc, MembersState>(
            buildWhen: (a, b) => a.filter != b.filter,
            builder: (context, state) => Row(
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search name, phone, or member ID…',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(onPressed: _search, child: const Text('Search')),
                const SizedBox(width: 20),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MemberFilter.values.map((f) {
                      final selected = f == state.filter;
                      return ChoiceChip(
                        label: Text(f.label),
                        selected: selected,
                        showCheckmark: false,
                        backgroundColor: Colors.transparent,
                        selectedColor:
                            context.palette.accent.withValues(alpha: .14),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected
                              ? context.palette.accentText
                              : context.palette.textMuted,
                        ),
                        side: BorderSide(
                          color:
                              selected ? Colors.transparent : context.palette.border,
                        ),
                        onSelected: (_) => context
                            .read<MembersBloc>()
                            .add(MembersFilterChanged(f)),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: BlocBuilder<MembersBloc, MembersState>(
              builder: (context, state) {
                if (state.status == MembersStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.status == MembersStatus.failed) {
                  return Center(
                    child: Text('Could not load members: ${state.error}',
                        style: TextStyle(color: context.palette.expired)),
                  );
                }
                if (state.rows.isEmpty) {
                  return _EmptyState(
                    onAdd: () => _openRoute(const MemberFormScreen()),
                    onImport: () => _openRoute(const ImportMembersScreen()),
                  );
                }
                return _MembersTable(
                  rows: state.rows,
                  onOpen: (id) => _openRoute(MemberDetailScreen(memberId: id)),
                  onRecordPayment: _recordPayment,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MembersTable extends StatelessWidget {
  const _MembersTable({
    required this.rows,
    required this.onOpen,
    required this.onRecordPayment,
  });

  final List<MemberRow> rows;
  final ValueChanged<int> onOpen;
  final ValueChanged<MemberRow> onRecordPayment;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.palette.border)),
            ),
            child: Row(
              children: [
                SizedBox(width: 56, child: Text('ID', style: labelStyleOf(context))),
                Expanded(flex: 3, child: Text('NAME', style: labelStyleOf(context))),
                Expanded(flex: 2, child: Text('PHONE', style: labelStyleOf(context))),
                Expanded(flex: 2, child: Text('MEMBERSHIP', style: labelStyleOf(context))),
                Expanded(flex: 2, child: Text('FEE', style: labelStyleOf(context))),
                Expanded(flex: 2, child: Text('PAID UNTIL', style: labelStyleOf(context))),
                SizedBox(width: 96, child: Text('STATUS', style: labelStyleOf(context))),
                const SizedBox(width: 130),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final row = rows[i];
                return InkWell(
                  onTap: () => onOpen(row.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text('#${row.member.memberCode}',
                              style: mutedStyleOf(context)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.member.fullName,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: context.palette.textPrimary),
                              ),
                              if (row.member.gender != null)
                                Text(row.member.gender!,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: context.palette.textHint)),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(row.member.phone, style: mutedStyleOf(context)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(row.plan?.name ?? '—',
                              style: TextStyle(
                                  fontSize: 13, color: context.palette.textSecondary)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row.feeMinor == null
                                ? '—'
                                : formatMinorUnits(row.feeMinor!),
                            style: TextStyle(
                                fontSize: 13, color: context.palette.textSecondary),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(formatShortDate(row.paidUntil),
                              style: mutedStyleOf(context)),
                        ),
                        SizedBox(
                          width: 96,
                          child: MemberStatusBadge(status: row.status),
                        ),
                        SizedBox(
                          width: 130,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => onRecordPayment(row),
                              child: const Text('Record Payment',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.onImport});

  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 40, color: context.palette.textHint),
          const SizedBox(height: 12),
          Text('No members match this view.', style: mutedStyleOf(context)),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                  onPressed: onImport, child: const Text('Import from Excel')),
              const SizedBox(width: 10),
              FilledButton(onPressed: onAdd, child: const Text('Add Member')),
            ],
          ),
        ],
      ),
    );
  }
}
