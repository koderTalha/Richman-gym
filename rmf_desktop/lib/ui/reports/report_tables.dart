import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../domain/member_status.dart';
import '../../domain/money.dart';
import '../../domain/monthly_report.dart';
import '../../domain/payment_method.dart';
import '../../theme/app_theme.dart';
import '../widgets/revenue_visibility.dart' show revenueMask;
import '../widgets/segmented_filter.dart';
import '../widgets/status_badge.dart';

/// One column of a [SortableTable].
class ReportColumn<T> {
  const ReportColumn({
    required this.label,
    required this.cell,
    this.flex = 2,
    this.numeric = false,
    this.sortKey,
  });

  final String label;
  final Widget Function(BuildContext context, T row) cell;
  final int flex;

  /// Right-aligned, as amounts are.
  final bool numeric;

  /// Null leaves the column unsortable.
  final Comparable<dynamic> Function(T row)? sortKey;
}

/// A table that sorts on any column with a key and pages through its rows.
///
/// Sorting and paging happen in memory. A month is at most a few hundred
/// rows already loaded for the totals above the table, so going back to the
/// database for each page would only add waiting.
class SortableTable<T> extends StatefulWidget {
  const SortableTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.emptyMessage,
    this.initialSort = 0,
    this.initialAscending = false,
    this.minWidth = 880,
    this.pageSize = 25,
  });

  final List<ReportColumn<T>> columns;
  final List<T> rows;
  final String emptyMessage;
  final int initialSort;
  final bool initialAscending;

  /// Below this the table scrolls sideways rather than squeezing columns
  /// until names and amounts wrap into each other.
  final double minWidth;
  final int pageSize;

  @override
  State<SortableTable<T>> createState() => _SortableTableState<T>();
}

class _SortableTableState<T> extends State<SortableTable<T>> {
  late int _sort = widget.initialSort;
  late bool _ascending = widget.initialAscending;
  int _page = 0;
  final _horizontal = ScrollController();

  @override
  void didUpdateWidget(SortableTable<T> old) {
    super.didUpdateWidget(old);
    // New rows — another month or filter — start again at the first page;
    // page 4 of a list that now has two would show nothing.
    if (!identical(old.rows, widget.rows)) _page = 0;
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  List<T> get _sorted {
    final key = widget.columns[_sort].sortKey;
    if (key == null) return widget.rows;
    final sorted = [...widget.rows]..sort((a, b) {
        final c = key(a).compareTo(key(b));
        return _ascending ? c : -c;
      });
    return sorted;
  }

  void _sortBy(int column) => setState(() {
        if (_sort == column) {
          _ascending = !_ascending;
        } else {
          _sort = column;
          // Text reads A–Z first; numbers and dates biggest or newest first.
          _ascending = !widget.columns[column].numeric &&
              widget.columns[column].sortKey?.call(widget.rows.first) is String;
        }
        _page = 0;
      });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (widget.rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        alignment: Alignment.center,
        child: Text(widget.emptyMessage,
            textAlign: TextAlign.center, style: mutedStyleOf(context)),
      );
    }

    final sorted = _sorted;
    final pages = (sorted.length / widget.pageSize).ceil();
    final page = _page.clamp(0, pages - 1);
    final from = page * widget.pageSize;
    final to = (from + widget.pageSize).clamp(0, sorted.length);
    final visible = sorted.sublist(from, to);

    Widget aligned(ReportColumn<T> column, Widget child) => Expanded(
          flex: column.flex,
          child: Align(
            alignment: column.numeric
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: child,
          ),
        );

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceOverlay,
        border: Border(
          top: BorderSide(color: palette.border),
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < widget.columns.length; i++)
            aligned(
              widget.columns[i],
              _HeaderCell(
                label: widget.columns[i].label,
                sortable: widget.columns[i].sortKey != null,
                active: i == _sort,
                ascending: _ascending,
                onTap: widget.columns[i].sortKey == null
                    ? null
                    : () => _sortBy(i),
              ),
            ),
        ],
      ),
    );

    final body = Column(
      children: [
        for (final row in visible)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                for (final column in widget.columns)
                  aligned(
                    column,
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: column.cell(context, row),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, body],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= widget.minWidth) return table;
          // Narrow window: the table keeps its width and scrolls, with the
          // scrollbar always drawn so it is clear there is more to the right.
          return Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(width: widget.minWidth, child: table),
            ),
          );
        }),
        _Pager(
          from: from + 1,
          to: to,
          total: sorted.length,
          page: page,
          pages: pages,
          onPage: (p) => setState(() => _page = p),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.sortable,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool sortable;
  final bool active;
  final bool ascending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = labelStyleOf(context).copyWith(
      color: active ? palette.textPrimary : null,
    );
    final text = Text(label.toUpperCase(),
        style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (!sortable) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8), child: text);
    }
    return Semantics(
      button: true,
      label: active
          ? 'Sorted by $label, ${ascending ? 'ascending' : 'descending'}'
          : 'Sort by $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: text),
              const SizedBox(width: 4),
              Icon(
                active
                    ? (ascending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.unfold_more,
                size: 13,
                color: active ? palette.accentText : palette.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.from,
    required this.to,
    required this.total,
    required this.page,
    required this.pages,
    required this.onPage,
  });

  final int from;
  final int to;
  final int total;
  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final muted = mutedStyleOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text('$from–$to of $total',
                style: muted.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (pages > 1) ...[
            IconButton(
              tooltip: 'Previous page',
              onPressed: page == 0 ? null : () => onPage(page - 1),
              icon: const Icon(Icons.chevron_left, size: 20),
            ),
            Text('Page ${page + 1} of $pages', style: muted),
            IconButton(
              tooltip: 'Next page',
              onPressed: page >= pages - 1 ? null : () => onPage(page + 1),
              icon: const Icon(Icons.chevron_right, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}

TextStyle _cell(BuildContext context, {bool strong = false, bool mono = false}) =>
    TextStyle(
      fontSize: 13,
      fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
      fontFamily: mono ? 'monospace' : null,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: strong ? context.palette.textPrimary : context.palette.textSecondary,
    );

Widget _text(BuildContext context, String value,
        {bool strong = false, bool mono = false}) =>
    Text(value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _cell(context, strong: strong, mono: mono));

/// Every payment in the month under the report's filters.
class ReportPaymentsTable extends StatelessWidget {
  const ReportPaymentsTable({
    super.key,
    required this.report,
    required this.obscured,
  });

  final MonthlyReport report;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    final month = report.month;
    return SortableTable<ReportPayment>(
      rows: report.payments,
      emptyMessage: report.filters.isEmpty
          ? 'No payments were recorded in ${month.label}.'
          : 'No payments in ${month.label} match these filters.',
      columns: [
        ReportColumn(
          label: 'Date',
          sortKey: (p) => p.paidAt,
          cell: (context, p) => p.imported
              ? Tooltip(
                  message: 'From the Excel ledger, which records the month '
                      'only',
                  child: _text(
                      context, '${month.shortName} ${month.year} · ledger'),
                )
              : _text(context, formatDayMonthYear(p.paidAt)),
        ),
        ReportColumn(
          label: 'Receipt',
          sortKey: (p) => p.receiptNumber ?? '',
          cell: (context, p) =>
              _text(context, p.receiptNumber ?? '—', mono: true),
        ),
        ReportColumn(
          label: 'Member',
          flex: 3,
          sortKey: (p) => p.memberName.toLowerCase(),
          cell: (context, p) => _text(context, '${p.memberName}  #${p.memberCode}',
              strong: true),
        ),
        ReportColumn(
          label: 'Plan',
          sortKey: (p) => (p.planName ?? '').toLowerCase(),
          cell: (context, p) => _text(context, p.planName ?? '—'),
        ),
        ReportColumn(
          label: 'Method',
          sortKey: (p) => paymentMethodLabel(p.method),
          cell: (context, p) => _text(context, paymentMethodLabel(p.method)),
        ),
        ReportColumn(
          label: 'Reference',
          cell: (context, p) => _text(context,
              (p.reference?.trim().isEmpty ?? true) ? '—' : p.reference!),
        ),
        ReportColumn(
          label: 'Amount',
          numeric: true,
          sortKey: (p) => p.amountMinor,
          cell: (context, p) => _text(
              context, obscured ? revenueMask : formatMinorUnits(p.amountMinor),
              strong: true),
        ),
      ],
    );
  }
}

enum MemberActivity { all, joined, renewed, notPaid, owing }

extension on MemberActivity {
  String get label => switch (this) {
        MemberActivity.all => 'All',
        MemberActivity.joined => 'Joined',
        MemberActivity.renewed => 'Renewed',
        MemberActivity.notPaid => 'Didn\'t pay',
        MemberActivity.owing => 'Owing',
      };

  bool test(ReportMember m) => switch (this) {
        MemberActivity.all => true,
        MemberActivity.joined => m.isNew,
        MemberActivity.renewed => m.renewed,
        MemberActivity.notPaid =>
          m.paidThisMonthMinor == 0 && m.status != MemberStatus.inactive,
        MemberActivity.owing => m.arrearsMinor > 0,
      };
}

/// The roster at the snapshot, with what each member did in the month.
class ReportMembersTable extends StatefulWidget {
  const ReportMembersTable({
    super.key,
    required this.report,
    required this.obscured,
  });

  final MonthlyReport report;
  final bool obscured;

  @override
  State<ReportMembersTable> createState() => _ReportMembersTableState();
}

class _ReportMembersTableState extends State<ReportMembersTable> {
  MemberActivity _activity = MemberActivity.all;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final rows = report.members.where(_activity.test).toList();
    String money(int minor) =>
        widget.obscured ? revenueMask : formatMinorUnits(minor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedFilter<MemberActivity>(
                options: [
                  for (final a in MemberActivity.values)
                    SegmentOption(
                      value: a,
                      label: a.label,
                      count: report.members.where(a.test).length,
                    ),
                ],
                selected: _activity,
                onSelect: (a) => setState(() => _activity = a),
              ),
            ),
          ),
        ),
        SortableTable<ReportMember>(
          key: ValueKey(_activity),
          rows: rows,
          initialSort: 0,
          initialAscending: true,
          minWidth: 980,
          emptyMessage: report.members.isEmpty
              ? 'Nobody was on the roster in ${report.month.label}.'
              : 'No members in this view.',
          columns: [
            ReportColumn(
              label: 'Member',
              flex: 3,
              sortKey: (m) => m.name.toLowerCase(),
              cell: (context, m) => Row(
                children: [
                  Flexible(
                      child: _text(context, '${m.name}  #${m.memberCode}',
                          strong: true)),
                  if (m.isNew) ...[
                    const SizedBox(width: 6),
                    StatusBadge(
                      label: 'NEW',
                      fg: context.palette.accentText,
                      bg: context.palette.accent.withValues(alpha: 0.14),
                    ),
                  ],
                ],
              ),
            ),
            ReportColumn(
              label: 'Plan',
              sortKey: (m) => (m.planName ?? '').toLowerCase(),
              cell: (context, m) => _text(context, m.planName ?? '—'),
            ),
            ReportColumn(
              label: 'Joined',
              sortKey: (m) => m.joiningDate,
              cell: (context, m) =>
                  _text(context, formatDayMonthYear(m.joiningDate)),
            ),
            ReportColumn(
              label: 'On plan since',
              sortKey: (m) => m.enrolmentStart ?? DateTime(0),
              cell: (context, m) => _text(
                  context,
                  m.enrolmentStart == null
                      ? '—'
                      : formatDayMonthYear(m.enrolmentStart!)),
            ),
            ReportColumn(
              label: 'Paid until',
              sortKey: (m) => m.paidUntil ?? DateTime(0),
              cell: (context, m) => _text(
                  context,
                  // Exclusive end: a cycle ending 1 Nov covers up to 31 Oct.
                  m.paidUntil == null
                      ? '—'
                      : formatDayMonthYear(
                          m.paidUntil!.subtract(const Duration(days: 1)))),
            ),
            ReportColumn(
              label: 'Paid in month',
              numeric: true,
              sortKey: (m) => m.paidThisMonthMinor,
              cell: (context, m) => _text(
                  context,
                  m.paidThisMonthMinor == 0
                      ? '—'
                      : money(m.paidThisMonthMinor)),
            ),
            ReportColumn(
              label: 'Owed',
              numeric: true,
              sortKey: (m) => m.arrearsMinor,
              cell: (context, m) => _text(
                  context, m.arrearsMinor == 0 ? '—' : money(m.arrearsMinor),
                  strong: m.arrearsMinor > 0),
            ),
            ReportColumn(
              label: 'Status',
              flex: 1,
              sortKey: (m) => m.status.index,
              cell: (context, m) => MemberStatusBadge(status: m.status),
            ),
          ],
        ),
      ],
    );
  }
}
