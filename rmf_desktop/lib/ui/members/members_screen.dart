import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/members_bloc.dart';
import '../../data/member_repository.dart';
import '../../domain/member_status.dart';
import '../../domain/money.dart';
import '../../domain/phone.dart';
import '../../theme/app_theme.dart';
import '../payments/payment_history_table.dart' show formatCalendarDate;
import '../payments/advance_payment_dialog.dart';
import '../widgets/fade_rise.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/segmented_filter.dart';
import '../widgets/status_badge.dart';
import 'import_members_screen.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key, this.initialFilter});

  /// A filter to open with, when the owner arrived from a dashboard card
  /// rather than the sidebar.
  final MemberFilter? initialFilter;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final bloc = MembersBloc(context.read<MemberRepository>())
          ..add(const MembersRequested());
        if (initialFilter != null) {
          bloc.add(MembersFilterChanged(initialFilter!));
        }
        return bloc;
      },
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
    final recorded = await showAdvancePaymentDialog(context, member: member);
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
    return BlocBuilder<MembersBloc, MembersState>(
      builder: (context, state) {
        final counts = state.filterCounts;

        return PageScaffold(
          title: 'Members',
          subtitle: _MembersSummary(counts: counts),
          actions: [
            GhostButton(
              label: 'Import from Excel',
              icon: Icons.upload_file,
              onPressed: () => _openRoute(const ImportMembersScreen()),
            ),
            AccentButton(
              label: 'Add member',
              icon: Icons.add,
              onPressed: () => _openRoute(const MemberFormScreen()),
            ),
          ],
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search name, phone or #ID',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    // Live, as the handoff asks: the owner looking for one
                    // member should not have to press anything.
                    onChanged: (_) => _search(),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                SegmentedFilter<MemberFilter>(
                  selected: state.filter,
                  onSelect: (f) =>
                      context.read<MembersBloc>().add(MembersFilterChanged(f)),
                  options: [
                    for (final f in MemberFilter.values)
                      SegmentOption(
                          value: f, label: f.label, count: counts[f]),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (state.status == MembersStatus.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.status == MembersStatus.failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 64),
                child: Center(
                  child: Text('Could not load members: ${state.error}',
                      style: TextStyle(color: context.palette.expired)),
                ),
              )
            else if (state.rows.isEmpty)
              _EmptyState(
                onAdd: () => _openRoute(const MemberFormScreen()),
                onImport: () => _openRoute(const ImportMembersScreen()),
              )
            else ...[
              _MembersTable(
                rows: state.rows,
                onOpen: (id) => _openRoute(MemberDetailScreen(memberId: id)),
                onRecordPayment: _recordPayment,
              ),
              const SizedBox(height: 10),
              Text(
                'Showing ${state.rows.length} '
                'member${state.rows.length == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12, color: context.palette.textMuted),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// "697 total · 319 due · 49 expiring this week", with the due count in amber.
class _MembersSummary extends StatelessWidget {
  const _MembersSummary({required this.counts});

  final Map<MemberFilter, int> counts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = counts[MemberFilter.all];
    final due = counts[MemberFilter.due];
    final expiring = counts[MemberFilter.expiringSoon];

    // Before the first load there are no counts; a header of "null total"
    // would be worse than no header at all.
    if (total == null) return const SizedBox.shrink();

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$total total'),
          if (due != null && due > 0) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: '$due due',
              style:
                  TextStyle(color: palette.due, fontWeight: FontWeight.w500),
            ),
          ],
          if (expiring != null && expiring > 0) ...[
            const TextSpan(text: ' · '),
            TextSpan(text: '$expiring expiring this week'),
          ],
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

  // The handoff's columns. Phone, plan and paid-until flex; the fee, status
  // and action are fixed so the money and the pills line up down the page.
  static const _gap = SizedBox(width: 12);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final header = TextStyle(
        fontSize: 11, letterSpacing: 0.66, color: palette.textMuted);

    return LayoutBuilder(builder: (context, constraints) {
      // At the 1024px window the handoff targets, the content area is about
      // 740px and every column cannot fit at a readable width. Plan is the one
      // dropped: the member's own screen shows it, whereas a cut-off phone
      // number or date would be read wrong.
      final showPlan = constraints.maxWidth >= 900;

      return Container(
        decoration: BoxDecoration(
          color: palette.surfaceOverlay,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(flex: 22, child: Text('MEMBER', style: header)),
                  _gap,
                  Expanded(flex: 13, child: Text('PHONE', style: header)),
                  _gap,
                  if (showPlan) ...[
                    Expanded(flex: 11, child: Text('PLAN', style: header)),
                    _gap,
                  ],
                  SizedBox(width: 90, child: Text('FEE', style: header)),
                  _gap,
                  Expanded(flex: 10, child: Text('PAID UNTIL', style: header)),
                  _gap,
                  SizedBox(width: 100, child: Text('STATUS', style: header)),
                  _gap,
                  const SizedBox(width: 96),
                ],
              ),
            ),
            // Shrink-wrapped, not Expanded: the page itself scrolls now, so the
            // table has no bounded height to expand into — Expanded here threw
            // "non-zero flex but incoming height constraints are unbounded" and
            // the table failed to lay out at all.
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              itemBuilder: (context, i) => FadeRise(
                index: i,
                child: _MemberTableRow(
                  row: rows[i],
                  showPlan: showPlan,
                  onOpen: onOpen,
                  onRecordPayment: onRecordPayment,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _MemberTableRow extends StatefulWidget {
  const _MemberTableRow({
    required this.row,
    required this.showPlan,
    required this.onOpen,
    required this.onRecordPayment,
  });

  final MemberRow row;
  final bool showPlan;
  final ValueChanged<int> onOpen;
  final ValueChanged<MemberRow> onRecordPayment;

  @override
  State<_MemberTableRow> createState() => _MemberTableRowState();
}

class _MemberTableRowState extends State<_MemberTableRow> {
  bool _hovered = false;

  /// "6d overdue" under a past date, "in 3 days" under one this week —
  /// the handoff's hint, so the date says how urgent it is without arithmetic.
  String? _untilHint(DateTime? until) {
    if (until == null || widget.row.status == MemberStatus.inactive) {
      return null;
    }
    final today = DateTime.now().toUtc();
    final days = until.toUtc().difference(today).inDays;
    if (widget.row.status.isOwing && days < 0) return '${-days}d overdue';
    if (days >= 0 && days <= 7) {
      return days == 0 ? 'today' : 'in $days day${days == 1 ? '' : 's'}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final row = widget.row;
    final hint = _untilHint(row.paidUntil);
    const gap = _MembersTable._gap;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(row.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? palette.surfaceRaised : Colors.transparent,
            border: Border(top: BorderSide(color: palette.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Expanded(
                flex: 22,
                child: Row(
                  children: [
                    InitialsAvatar(name: row.member.fullName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.member.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: palette.textPrimary),
                          ),
                          Text('#${row.member.memberCode}',
                              style: TextStyle(
                                  fontSize: 11, color: palette.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              gap,
              Expanded(
                flex: 13,
                child: Text(formatPhoneForDisplay(row.member.phone),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ),
              gap,
              if (widget.showPlan) ...[
                Expanded(
                  flex: 11,
                  child: Text(row.plan?.name ?? '—',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: palette.textSecondary)),
                ),
                gap,
              ],
              SizedBox(
                width: 90,
                child: Text(
                  row.feeMinor == null ? '—' : formatMinorUnits(row.feeMinor!),
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              gap,
              Expanded(
                flex: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatCalendarDate(row.paidUntil),
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    if (hint != null)
                      Text(hint,
                          style: TextStyle(
                              fontSize: 11, color: palette.textMuted)),
                  ],
                ),
              ),
              gap,
              SizedBox(
                width: 100,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MemberStatusBadge(status: row.status),
                ),
              ),
              gap,
              SizedBox(
                width: 96,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _RecordButton(
                      onPressed: () => widget.onRecordPayment(row)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The row's "Record" action: quiet until hovered, then the brand colour.
/// Its own tap target, so it records rather than opening the profile.
class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.payments_outlined, size: 14),
      label: const Text('Record'),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered)
                ? palette.accentText
                : palette.textSecondary),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered)
                ? palette.accent.withValues(alpha: 0.14)
                : Colors.transparent),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.hovered)
                ? palette.accent
                : palette.borderStrong)),
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
