import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../../bloc/reports_bloc.dart';
import '../../bloc/revenue_visibility_cubit.dart';
import '../../data/database.dart' show AppDatabase, PaymentMethod;
import '../../data/member_repository.dart';
import '../../data/report_repository.dart';
import '../../domain/dates.dart';
import '../../domain/member_status.dart';
import '../../domain/money.dart';
import '../../domain/monthly_report.dart';
import '../../domain/payment_method.dart';
import '../../theme/app_theme.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/revenue_visibility.dart';
import '../widgets/segmented_filter.dart';
import 'report_charts.dart';
import 'report_export.dart';
import 'report_tables.dart';

final _log = Logger('reports.screen');

/// Reports & Analytics: one month of money and membership, with the charts,
/// the detail behind them, and the same thing as a PDF.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, this.repository});

  /// For tests; the app builds one from the database it already has.
  final ReportRepository? repository;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ReportsBloc(
        repository ??
            ReportRepository(
              context.read<AppDatabase>(),
              members: context.read<MemberRepository>(),
            ),
      )..add(const ReportsRequested()),
      child: const _ReportsView(),
    );
  }
}

class _ReportsView extends StatefulWidget {
  const _ReportsView();

  @override
  State<_ReportsView> createState() => _ReportsViewState();
}

enum _DetailTab { payments, members }

class _ReportsViewState extends State<_ReportsView> {
  final _search = TextEditingController();
  Timer? _debounce;
  _DetailTab _tab = _DetailTab.payments;

  /// Export or print under way; both buttons wait for it.
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  ReportsBloc get _bloc => context.read<ReportsBloc>();

  /// Typing is let settle before the report is rebuilt, so a name typed at
  /// speed is one rebuild rather than one per letter.
  void _onSearch(String text, {bool now = false}) {
    _debounce?.cancel();
    void apply() => _bloc.add(
        ReportsFiltersChanged(_bloc.state.filters.copyWith(search: text)));
    if (now) {
      apply();
    } else {
      _debounce = Timer(const Duration(milliseconds: 350), apply);
    }
  }

  void _setFilters(ReportFilters filters) {
    if (filters.search != _search.text) _search.text = filters.search;
    _bloc.add(ReportsFiltersChanged(filters));
  }

  void _reset() {
    _debounce?.cancel();
    _search.clear();
    _bloc.add(const ReportsFiltersReset());
  }

  Map<int, String> _planNames(ReportsState state) =>
      {for (final p in state.plans) p.id: p.name};

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e, s) {
      _log.severe(failure, e, s);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$failure: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(ReportsState state) => _run(() async {
        final path = await exportReportPdf(context, state.report!,
            planNames: _planNames(state));
        if (path != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Saved $path')));
        }
      }, 'The PDF could not be saved');

  Future<void> _print(ReportsState state) => _run(
      () => printReport(context, state.report!, planNames: _planNames(state)),
      'The report could not be printed');

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReportsBloc, ReportsState>(
      builder: (context, state) {
        final report = state.report;
        final ready = report != null && !_busy;
        final actions = [
          const RevenueVisibilityButton(),
          GhostButton(
            label: 'Print',
            icon: Icons.print_outlined,
            onPressed: ready ? () => _print(state) : null,
          ),
          AccentButton(
            label: _busy ? 'Preparing…' : 'Export PDF',
            icon: Icons.picture_as_pdf_outlined,
            onPressed: ready ? () => _export(state) : null,
          ),
        ];
        return LayoutBuilder(builder: (context, constraints) {
          // Beside the title there is room for the actions only on a wide
          // window; on a narrow one they drop below it rather than pushing
          // the title off the edge, and Export stays in reach.
          final narrow = constraints.maxWidth < 760;
          return PageScaffold(
          title: 'Reports & Analytics',
          subtitle: const Text('Track your gym\'s financial performance, '
              'memberships, and business growth.'),
          actions: narrow ? const [] : actions,
          children: [
            if (narrow) ...[
              Wrap(spacing: 8, runSpacing: 8, children: actions),
              const SizedBox(height: 14),
            ],
            _PeriodBar(state: state),
            const SizedBox(height: 14),
            _FilterBar(
              state: state,
              search: _search,
              onSearch: _onSearch,
              onChanged: _setFilters,
              onReset: _reset,
            ),
            const SizedBox(height: 18),
            _body(state),
          ],
          );
        });
      },
    );
  }

  Widget _body(ReportsState state) {
    final report = state.report;
    if (report == null) {
      if (state.status == ReportsStatus.failed) {
        return _Failure(
          error: state.error,
          onRetry: () => _bloc.add(const ReportsRequested()),
        );
      }
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final loading = state.status == ReportsStatus.loading;
    final obscured = !context.watch<RevenueVisibilityCubit>().state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A thin bar rather than blanking the page: the last report stays
        // readable while the next is built.
        SizedBox(
          height: 2,
          child: loading ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        if (state.status == ReportsStatus.failed)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Failure(
              error: state.error,
              onRetry: () => _bloc.add(const ReportsRequested()),
              compact: true,
            ),
          ),
        const SizedBox(height: 10),
        AnimatedOpacity(
          opacity: loading ? 0.55 : 1,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(
            ignoring: loading,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KpiSection(report: report, obscured: obscured),
                const SizedBox(height: 22),
                _Charts(report: report, obscured: obscured),
                const SizedBox(height: 22),
                _Detail(
                  report: report,
                  obscured: obscured,
                  tab: _tab,
                  onTab: (t) => setState(() => _tab = t),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- Period --------------------------------------------------------------------

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.state});

  final ReportsState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bloc = context.read<ReportsBloc>();
    final report = state.report;

    final months = <ReportMonth>[];
    if (state.firstMonth != null) {
      for (var m = state.currentMonth;
          !m.isBefore(state.firstMonth!);
          m = m.previous) {
        months.add(m);
      }
    } else {
      months.add(state.currentMonth);
    }

    final picker = Container(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: state.canGoBack
                ? () => bloc.add(ReportsMonthChanged(state.month.previous))
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Flexible(
            child: PopupMenuButton<ReportMonth>(
            tooltip: 'Choose a month',
            initialValue: state.month,
            onSelected: (m) => bloc.add(ReportsMonthChanged(m)),
            constraints: const BoxConstraints(maxHeight: 420, minWidth: 200),
            itemBuilder: (_) => [
              for (final m in months)
                PopupMenuItem(value: m, height: 38, child: Text(m.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_outlined,
                      size: 17, color: palette.textMuted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      state.month.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: palette.textMuted),
                ],
              ),
            ),
          ),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: state.canGoForward
                ? () => bloc.add(ReportsMonthChanged(state.month.next))
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );

    final note = report == null
        ? null
        : report.isCurrentMonth
            ? 'Month in progress · figures to '
                '${formatDayMonthYear(report.snapshotAt)}, '
                '${TimeOfDay.fromDateTime(report.snapshotAt).format(context)}'
            : 'Closed month · members as they stood on '
                '${formatDayMonthYear(report.snapshotAt)}';

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        picker,
        if (state.month != state.currentMonth)
          GhostButton(
            label: 'This month',
            icon: Icons.today_outlined,
            compact: true,
            onPressed: () => bloc.add(ReportsMonthChanged(state.currentMonth)),
          ),
        if (note != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                report!.isCurrentMonth
                    ? Icons.timelapse_outlined
                    : Icons.lock_clock_outlined,
                size: 15,
                color: palette.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(note, style: mutedStyleOf(context))),
            ],
          ),
      ],
    );
  }
}

// --- Filters -------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.state,
    required this.search,
    required this.onSearch,
    required this.onChanged,
    required this.onReset,
  });

  final ReportsState state;
  final TextEditingController search;
  final void Function(String text, {bool now}) onSearch;
  final ValueChanged<ReportFilters> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final filters = state.filters;
    final planNames = {for (final p in state.plans) p.id: p.name};
    final active = filters.describe(planNames);

    Widget dropdown<T>({
      required String label,
      required double width,
      required T? value,
      required List<(T, String)> options,
      required String anyLabel,
      required ValueChanged<T?> onSelected,
    }) =>
        SizedBox(
          width: width,
          child: DropdownButtonFormField<T?>(
            // Keyed on the value so Reset, which changes it from outside,
            // redraws the field rather than leaving the old choice showing.
            key: ValueKey('$label:$value'),
            initialValue: value,
            isDense: true,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true),
            items: [
              DropdownMenuItem<T?>(value: null, child: Text(anyLabel)),
              for (final (v, text) in options)
                DropdownMenuItem<T?>(
                  value: v,
                  child: Text(text, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onSelected,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          // Every control takes the full row on a narrow window, rather than
          // a fixed width running off its edge.
          final narrow = constraints.maxWidth < 560;
          double w(double wide) => narrow ? constraints.maxWidth : wide;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: w(280),
                child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    hintText: 'Search member, phone, code or receipt…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: onSearch,
                  onSubmitted: (t) => onSearch(t, now: true),
                ),
              ),
              dropdown<int>(
                label: 'Plan',
                width: w(190),
                value: filters.planId,
                anyLabel: 'All plans',
                options: [for (final p in state.plans) (p.id, p.name)],
                onSelected: (v) => onChanged(filters.copyWith(planId: () => v)),
              ),
              dropdown<PaymentMethod>(
                label: 'Payment method',
                width: w(180),
                value: filters.method,
                anyLabel: 'All methods',
                options: [
                  for (final m in PaymentMethod.values) (m, paymentMethodLabel(m)),
                ],
                onSelected: (v) => onChanged(filters.copyWith(method: () => v)),
              ),
              dropdown<MemberStatus>(
                label: 'Member status',
                width: w(170),
                value: filters.status,
                anyLabel: 'Any status',
                options: [
                  for (final s in MemberStatus.values) (s, memberStatusName(s)),
                ],
                onSelected: (v) => onChanged(filters.copyWith(status: () => v)),
              ),
              GhostButton(
                label: 'Reset filters',
                icon: Icons.filter_alt_off_outlined,
                onPressed: filters.isEmpty ? null : onReset,
              ),
            ],
          );
        }),
        if (active.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Showing only', style: mutedStyleOf(context)),
              if (filters.search.trim().isNotEmpty)
                _FilterChip(
                  label: active.firstWhere((a) => a.startsWith('Search')),
                  onRemove: () => onChanged(filters.copyWith(search: '')),
                ),
              if (filters.planId != null)
                _FilterChip(
                  label: active.firstWhere((a) => a.startsWith('Plan')),
                  onRemove: () => onChanged(filters.copyWith(planId: () => null)),
                ),
              if (filters.method != null)
                _FilterChip(
                  label: active.firstWhere((a) => a.startsWith('Method')),
                  onRemove: () => onChanged(filters.copyWith(method: () => null)),
                ),
              if (filters.status != null)
                _FilterChip(
                  label: active.firstWhere((a) => a.startsWith('Status')),
                  onRemove: () => onChanged(filters.copyWith(status: () => null)),
                ),
            ],
          ),
          if (filters.method != null) ...[
            const SizedBox(height: 6),
            Text(
              'A payment method narrows the money. Member counts are '
              'unaffected, since a member is not paid by a method.',
              style: mutedStyleOf(context).copyWith(fontSize: 12),
            ),
          ],
        ],
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InputChip(
      label: Text(label),
      labelStyle: TextStyle(fontSize: 12.5, color: palette.textPrimary),
      backgroundColor: palette.accent.withValues(alpha: 0.10),
      side: BorderSide(color: palette.accent.withValues(alpha: 0.45)),
      deleteIcon: const Icon(Icons.close, size: 15),
      deleteButtonTooltipMessage: 'Remove filter',
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
    );
  }
}

// --- Key figures ----------------------------------------------------------------

class _Kpi {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.figure,
    this.money = false,
    this.higherIsBetter = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  /// The comparison, when there is a fair one.
  final Compared? figure;
  final bool money;
  final bool higherIsBetter;
}

class _KpiSection extends StatelessWidget {
  const _KpiSection({required this.report, required this.obscured});

  final MonthlyReport report;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final month = report.month;
    final money = [
      _Kpi(
        icon: Icons.payments_outlined,
        label: 'Revenue this month',
        value: formatMinorUnits(report.revenue.value),
        caption: report.importedRevenueMinor > 0
            ? '${formatMinorUnits(report.importedRevenueMinor)} of it from the '
                'Excel ledger'
            : 'Collected in ${month.name}${report.isCurrentMonth ? ' so far' : ''}',
        figure: report.revenue,
        money: true,
      ),
      _Kpi(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Collected to date',
        value: formatMinorUnits(report.collectedToDateMinor),
        caption: 'All-time, to the end of ${month.name}',
        money: true,
      ),
      _Kpi(
        icon: Icons.receipt_long_outlined,
        label: 'Payments collected',
        value: '${report.paymentCount.value}',
        caption: '${plural(report.payingMembers, 'member', 'members')} paid',
        figure: report.paymentCount,
      ),
      _Kpi(
        icon: Icons.person_outline,
        label: 'Average per paying member',
        value: report.averagePerPayingMemberMinor == null
            ? '—'
            : formatMinorUnits(report.averagePerPayingMemberMinor!),
        caption: report.averagePerPayingMemberMinor == null
            ? 'Nobody paid this month'
            : 'Revenue ÷ members who paid',
        money: report.averagePerPayingMemberMinor != null,
      ),
      _Kpi(
        icon: Icons.pending_actions_outlined,
        label: 'Unpaid fees',
        value: formatMinorUnits(report.owed.value),
        caption: report.owed.value == 0
            ? 'Nothing owed ${report.isCurrentMonth ? 'right now' : 'at month end'}'
            : '${plural(report.owingMembers, 'member', 'members')} owing '
                '${report.isCurrentMonth ? 'now' : 'at month end'}',
        figure: report.owed,
        money: true,
        higherIsBetter: false,
      ),
    ];
    final members = [
      _Kpi(
        icon: Icons.groups_outlined,
        label: 'Total members',
        value: '${report.totalMembers.value}',
        caption: 'On the roster, inactive included',
        figure: report.totalMembers,
      ),
      _Kpi(
        icon: Icons.how_to_reg_outlined,
        label: 'Active members',
        value: '${report.activeMembers.value}',
        caption: 'Not deactivated',
        figure: report.activeMembers,
      ),
      _Kpi(
        icon: Icons.person_add_alt_outlined,
        label: 'New members',
        value: '${report.newMembers.value}',
        caption: 'Joined in ${month.name}',
        figure: report.newMembers,
      ),
      _Kpi(
        icon: Icons.autorenew,
        label: 'Renewals',
        value: '${report.renewals.value}',
        caption: 'Existing members who paid in ${month.name}',
        figure: report.renewals,
      ),
      _Kpi(
        icon: Icons.event_busy_outlined,
        label: 'Expired memberships',
        value: '${report.expiredMembers.value}',
        caption: 'Last cycle ended, nothing paid since',
        figure: report.expiredMembers,
        higherIsBetter: false,
      ),
    ];

    final comparison = report.comparisonLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: 'Money',
          note: comparison == null
              ? 'No earlier month on record to compare with'
              : 'Compared with $comparison',
        ),
        _KpiGrid(cards: money, obscured: obscured, comparison: comparison),
        const SizedBox(height: 22),
        _SectionHeading(
          title: 'Members',
          note: report.isCurrentMonth
              ? 'As of now · joining and renewals for the month so far'
              : 'As they stood at the end of ${month.label}',
        ),
        _KpiGrid(cards: members, obscured: obscured, comparison: comparison),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary)),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(note!,
                  style: TextStyle(fontSize: 12.5, color: palette.textMuted)),
            ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.cards,
    required this.obscured,
    required this.comparison,
  });

  final List<_Kpi> cards;
  final bool obscured;
  final String? comparison;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 12.0;
      final width = constraints.maxWidth;
      final columns = width >= 1150
          ? 5
          : width >= 860
              ? 3
              : width >= 480
                  ? 2
                  : 1;
      final cardWidth = (width - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards)
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                kpi: card,
                obscured: obscured && card.money,
                comparison: comparison,
              ),
            ),
        ],
      );
    });
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.kpi,
    required this.obscured,
    required this.comparison,
  });

  final _Kpi kpi;
  final bool obscured;
  final String? comparison;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 148,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(kpi.icon, size: 16, color: palette.accentText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kpi.label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w500,
                      color: palette.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ObscuredText(
              text: kpi.value,
              obscured: obscured,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(kpi.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.textMuted)),
          const Spacer(),
          _TrendLine(kpi: kpi, comparison: comparison),
        ],
      ),
    );
  }
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.kpi, required this.comparison});

  final _Kpi kpi;
  final String? comparison;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final figure = kpi.figure;
    final change = figure?.change;
    if (figure == null || change == null) {
      return const SizedBox(height: 16);
    }

    final pct = percentChange(figure);
    final String text;
    if (change == 0) {
      text = 'No change';
    } else if (kpi.money) {
      // A percentage, not the rupee difference: it says how the month went
      // without putting a second revenue figure on the card.
      text = pct ?? (change > 0 ? 'Up from nothing' : 'Down');
    } else {
      text = '${change > 0 ? '+' : '−'}${change.abs()}'
          '${pct == null ? '' : ' ($pct)'}';
    }

    final good = change == 0 ? null : (change > 0) == kpi.higherIsBetter;
    final colour = good == null
        ? palette.textMuted
        : (good ? palette.paid : palette.expired);
    final icon = change == 0
        ? Icons.remove
        : (change > 0 ? Icons.arrow_upward : Icons.arrow_downward);

    return Tooltip(
      message: kpi.money
          ? 'Against $comparison'
          : 'Against $comparison: ${figure.previous}',
      child: Row(
        children: [
          Icon(icon, size: 13, color: colour),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              comparison == null ? text : '$text vs $comparison',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w500, color: colour),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Charts ----------------------------------------------------------------------

class _Charts extends StatelessWidget {
  const _Charts({required this.report, required this.obscured});

  final MonthlyReport report;
  final bool obscured;

  /// What each panel in a row of two is at least, so a short legend beside a
  /// tall chart does not leave a ragged edge.
  static const _rowHeight = 360.0;

  @override
  Widget build(BuildContext context) {
    final revenue = ChartPanel(
      title: 'Revenue performance',
      subtitle: report.importedRevenueMinor > 0
          ? 'Daily · ${obscured ? revenueMask : formatMinorUnits(report.importedRevenueMinor)} '
              'from the Excel ledger has no day and isn\'t plotted'
          : 'Daily, as payments were taken',
      minHeight: _rowHeight,
      child: DailyRevenueChart(report: report, obscured: obscured),
    );
    final status = ChartPanel(
      title: 'Membership overview',
      subtitle: report.isCurrentMonth ? 'By status, as of now' : 'By status, at month end',
      minHeight: _rowHeight,
      child: StatusDoughnut(report: report),
    );
    final growth = ChartPanel(
      title: 'Membership growth',
      subtitle: report.growth.length <= 1
          ? 'New members and renewals'
          : 'New members and renewals, '
              '${report.growth.first.month.shortName} ${report.growth.first.month.year}'
              ' – ${report.month.shortName} ${report.month.year}',
      minHeight: _rowHeight,
      child: GrowthChart(report: report),
    );
    final breakdown = RevenueBreakdown(
        report: report, obscured: obscured, minHeight: _rowHeight);

    return LayoutBuilder(builder: (context, constraints) {
      const gap = 16.0;
      if (constraints.maxWidth < 1000) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            revenue,
            const SizedBox(height: gap),
            status,
            const SizedBox(height: gap),
            growth,
            const SizedBox(height: gap),
            breakdown,
          ],
        );
      }
      // Side by side, each pair at one height so the row reads as a row.
      Widget pair(Widget left, Widget right) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: left),
              const SizedBox(width: gap),
              Expanded(flex: 2, child: right),
            ],
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pair(revenue, status),
          const SizedBox(height: gap),
          pair(growth, breakdown),
        ],
      );
    });
  }
}

// --- Detail ------------------------------------------------------------------------

class _Detail extends StatelessWidget {
  const _Detail({
    required this.report,
    required this.obscured,
    required this.tab,
    required this.onTab,
  });

  final MonthlyReport report;
  final bool obscured;
  final _DetailTab tab;
  final ValueChanged<_DetailTab> onTab;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final summary = tab == _DetailTab.payments
        ? '${report.payments.length} '
            '${report.payments.length == 1 ? 'payment' : 'payments'} · '
        : '${report.members.length} '
            '${report.members.length == 1 ? 'member' : 'members'} · ';
    final amount = tab == _DetailTab.payments
        ? report.revenue.value
        : report.owed.value;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Detailed report',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Wrap(
                      children: [
                        Text(summary, style: mutedStyleOf(context)),
                        ObscuredText(
                          text: '${formatMinorUnits(amount)} '
                              '${tab == _DetailTab.payments ? 'collected' : 'owed'}',
                          obscured: obscured,
                          style: mutedStyleOf(context),
                        ),
                      ],
                    ),
                  ],
                ),
                SegmentedFilter<_DetailTab>(
                  options: [
                    SegmentOption(
                      value: _DetailTab.payments,
                      label: 'Financial',
                      icon: Icons.payments_outlined,
                      count: report.payments.length,
                    ),
                    SegmentOption(
                      value: _DetailTab.members,
                      label: 'Membership',
                      icon: Icons.people_outline,
                      count: report.members.length,
                    ),
                  ],
                  selected: tab,
                  onSelect: onTab,
                ),
              ],
            ),
          ),
          if (tab == _DetailTab.payments)
            ReportPaymentsTable(report: report, obscured: obscured)
          else
            ReportMembersTable(report: report, obscured: obscured),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry, this.compact = false});

  final String? error;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 24),
      decoration: BoxDecoration(
        color: palette.expiredBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: palette.expired),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'The report could not be built.'
              '${error == null ? '' : ' $error'}',
              style: TextStyle(color: palette.expired),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
