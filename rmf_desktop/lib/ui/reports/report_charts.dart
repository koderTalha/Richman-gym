import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../domain/member_status.dart';
import '../../domain/money.dart';
import '../../domain/monthly_report.dart';
import '../../theme/app_theme.dart';
import '../widgets/revenue_visibility.dart' show revenueMask;
import '../widgets/segmented_filter.dart';

/// The status colours the app's badges already use, so a slice of the
/// doughnut is the colour of the badge it counts.
Color statusColour(AppPalette palette, MemberStatus status) => switch (status) {
      MemberStatus.paid => palette.paid,
      MemberStatus.due => palette.due,
      MemberStatus.expired => palette.expired,
      MemberStatus.inactive => palette.inactive,
    };

/// A chart's frame: a title, an optional line under it, and the plot.
class ChartPanel extends StatelessWidget {
  const ChartPanel({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.minHeight = 0,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
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
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style:
                              TextStyle(fontSize: 12, color: palette.textMuted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// What a chart shows when there is nothing to plot — said in words rather
/// than drawn as an empty axis that reads as "zero".
class ChartEmpty extends StatelessWidget {
  const ChartEmpty(this.message, {super.key, this.height = 180});

  final String message;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined,
                size: 22, color: context.palette.textHint),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: context.palette.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.colour, {this.dashed = false});

  final Color colour;
  final bool dashed;

  @override
  Widget build(BuildContext context) => dashed
      ? SizedBox(
          width: 14,
          height: 10,
          child: CustomPaint(painter: _DashPainter(colour)),
        )
      : Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: colour, borderRadius: BorderRadius.circular(3)),
        );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1.5;
    final y = size.height / 2;
    canvas
      ..drawLine(Offset(0, y), Offset(5, y), paint)
      ..drawLine(Offset(8, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.colour != colour;
}

class ChartLegendItem extends StatelessWidget {
  const ChartLegendItem({
    super.key,
    required this.colour,
    required this.label,
    this.dashed = false,
  });

  final Color colour;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Swatch(colour, dashed: dashed),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: context.palette.textSecondary)),
          ),
        ],
      );
}

/// A small floating card naming the value under the pointer.
class _ChartTooltip extends StatelessWidget {
  const _ChartTooltip({required this.title, required this.lines});

  final String title;
  final List<(Color?, String)> lines;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surfaceOverlay,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.borderStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary)),
          for (final (colour, text) in lines) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (colour != null) ...[
                  _Swatch(colour),
                  const SizedBox(width: 6),
                ],
                Text(text,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: palette.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- Revenue by day ---------------------------------------------------------

/// Daily revenue as an area, with last month as a dashed line behind it.
///
/// A crosshair follows the pointer and names the day and both months'
/// amounts. With revenue hidden the shape stays — it says nothing in rupees —
/// but the axis and the tooltip show the mask.
class DailyRevenueChart extends StatefulWidget {
  const DailyRevenueChart({
    super.key,
    required this.report,
    required this.obscured,
    this.height = 220,
  });

  final MonthlyReport report;
  final bool obscured;
  final double height;

  @override
  State<DailyRevenueChart> createState() => _DailyRevenueChartState();
}

class _DailyRevenueChartState extends State<DailyRevenueChart> {
  int? _hover;

  static const _axisWidth = 46.0;
  static const _bottom = 22.0;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final palette = context.palette;
    final days = report.dailyRevenueMinor.sublist(0, report.daysElapsed);
    final previous = report.previousDailyRevenueMinor;

    if (days.every((d) => d == 0)) {
      return ChartEmpty(
        report.importedRevenueMinor > 0
            ? 'Every payment this month came from the Excel ledger,\n'
                'which records the month but not the day.'
            : 'No payments recorded in ${report.month.label}.',
        height: widget.height,
      );
    }

    final axis = niceAxis([...days, ...?previous].fold<int>(0, math.max));
    final slots = report.dailyRevenueMinor.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(builder: (context, constraints) {
            final plotWidth = constraints.maxWidth - _axisWidth;
            final plotHeight = widget.height - _bottom;
            double xOf(int i) =>
                slots <= 1 ? plotWidth / 2 : plotWidth * i / (slots - 1);

            void track(Offset local) {
              final dx = local.dx - _axisWidth;
              final i = slots <= 1
                  ? 0
                  : (dx / plotWidth * (slots - 1)).round().clamp(0, slots - 1);
              final within = i < days.length ? i : null;
              if (within != _hover) setState(() => _hover = within);
            }

            final hover = _hover;
            return MouseRegion(
              onHover: (e) => track(e.localPosition),
              onExit: (_) => setState(() => _hover = null),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var t = 0; t <= axis.ticks; t++)
                    Positioned(
                      left: 0,
                      width: _axisWidth - 8,
                      top: plotHeight - plotHeight * t / axis.ticks - 7,
                      child: Text(
                        widget.obscured && t > 0
                            ? '•••'
                            : formatCompactMinor(axis.step * t),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: palette.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  Positioned(
                    left: _axisWidth,
                    top: 0,
                    width: plotWidth,
                    height: plotHeight,
                    child: CustomPaint(
                      painter: _AreaPainter(
                        days: days,
                        previous: previous,
                        slots: slots,
                        top: axis.top,
                        ticks: axis.ticks,
                        hover: hover,
                        line: palette.accent,
                        grid: palette.border,
                        comparison: palette.textMuted,
                        surface: palette.surfaceRaised,
                      ),
                    ),
                  ),
                  for (final day in const [1, 8, 15, 22, 0])
                    Builder(builder: (context) {
                      final d = day == 0 ? slots : day;
                      return Positioned(
                        left: _axisWidth +
                            (xOf(d - 1) - 24).clamp(-10.0, plotWidth - 38),
                        width: 48,
                        top: plotHeight + 6,
                        child: Text('$d ${report.month.shortName}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10.5, color: palette.textMuted)),
                      );
                    }),
                  if (hover != null)
                    Positioned(
                      left: (_axisWidth + xOf(hover) + 12)
                          .clamp(0.0, math.max(0.0, constraints.maxWidth - 190)),
                      top: 4,
                      child: IgnorePointer(
                        child: _ChartTooltip(
                          title: formatDayMonthYear(DateTime(
                              report.month.year, report.month.month, hover + 1)),
                          lines: [
                            (
                              palette.accent,
                              '${report.month.name}: ${_money(days[hover])}'
                            ),
                            if (previous != null && hover < previous.length)
                              (
                                palette.textMuted,
                                '${report.month.previous.name}: '
                                    '${_money(previous[hover])}'
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            ChartLegendItem(
                colour: palette.accent,
                label: report.isCurrentMonth
                    ? '${report.month.label}, to today'
                    : report.month.label),
            if (previous != null)
              ChartLegendItem(
                  colour: palette.textMuted,
                  dashed: true,
                  label: report.month.previous.label),
          ],
        ),
      ],
    );
  }

  String _money(int minor) =>
      widget.obscured ? revenueMask : formatMinorUnits(minor);
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.days,
    required this.previous,
    required this.slots,
    required this.top,
    required this.ticks,
    required this.hover,
    required this.line,
    required this.grid,
    required this.comparison,
    required this.surface,
  });

  final List<int> days;
  final List<int>? previous;
  final int slots;
  final int top;
  final int ticks;
  final int? hover;
  final Color line;
  final Color grid;
  final Color comparison;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int i) => slots <= 1 ? size.width / 2 : size.width * i / (slots - 1);
    double y(int v) => size.height - size.height * v / top;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var t = 0; t <= ticks; t++) {
      final gy = size.height - size.height * t / ticks;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    final prev = previous;
    if (prev != null) {
      final paint = Paint()
        ..color = comparison
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final n = math.min(prev.length, slots);
      for (var i = 1; i < n; i++) {
        _dashed(canvas, Offset(x(i - 1), y(prev[i - 1])),
            Offset(x(i), y(prev[i])), paint);
      }
    }

    final path = Path()..moveTo(x(0), y(days[0]));
    for (var i = 1; i < days.length; i++) {
      path.lineTo(x(i), y(days[i]));
    }
    final area = Path.from(path)
      ..lineTo(x(days.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.24), line.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final h = hover;
    if (h != null && h < days.length) {
      final at = Offset(x(h), y(days[h]));
      canvas.drawLine(Offset(at.dx, 0), Offset(at.dx, size.height),
          Paint()
            ..color = comparison.withValues(alpha: 0.5)
            ..strokeWidth = 1);
      canvas
        ..drawCircle(at, 6, Paint()..color = surface)
        ..drawCircle(at, 4, Paint()..color = line);
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 3.0;
    final length = (b - a).distance;
    if (length == 0) return;
    final dir = (b - a) / length;
    for (var d = 0.0; d < length; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, length), paint);
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.days != days ||
      old.previous != previous ||
      old.hover != hover ||
      old.line != line ||
      old.grid != grid;
}

// --- Membership status --------------------------------------------------------

/// The roster split by status, as a ring with a legend that carries the
/// counts and shares. Pointing at a slice names it in the middle.
class StatusDoughnut extends StatefulWidget {
  const StatusDoughnut({super.key, required this.report});

  final MonthlyReport report;

  @override
  State<StatusDoughnut> createState() => _StatusDoughnutState();
}

class _StatusDoughnutState extends State<StatusDoughnut> {
  MemberStatus? _hover;

  static const _size = 168.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final counts = widget.report.statusCounts;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return const ChartEmpty('No members on the roster.', height: _size);
    }

    final slices = [
      for (final s in MemberStatus.values)
        if ((counts[s] ?? 0) > 0) (s, counts[s]!),
    ];

    MemberStatus? hit(Offset local) {
      final centre = const Offset(_size / 2, _size / 2);
      final v = local - centre;
      final r = v.distance;
      if (r < _size / 2 - 26 || r > _size / 2) return null;
      var angle = math.atan2(v.dy, v.dx) + math.pi / 2;
      if (angle < 0) angle += 2 * math.pi;
      var start = 0.0;
      for (final (status, count) in slices) {
        final sweep = 2 * math.pi * count / total;
        if (angle >= start && angle < start + sweep) return status;
        start += sweep;
      }
      return null;
    }

    final focus = _hover;
    final ring = MouseRegion(
      onHover: (e) {
        final s = hit(e.localPosition);
        if (s != _hover) setState(() => _hover = s);
      },
      onExit: (_) => setState(() => _hover = null),
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size.square(_size),
              painter: _RingPainter(
                slices: [
                  for (final (s, c) in slices) (statusColour(palette, s), c, s == focus),
                ],
                gap: palette.surfaceRaised,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${focus == null ? total : counts[focus]}',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                Text(
                  focus == null
                      ? 'members'
                      : '${memberStatusName(focus).toLowerCase()} · '
                          '${_pct(counts[focus]!, total)}',
                  style: TextStyle(fontSize: 11.5, color: palette.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final status in MemberStatus.values)
          MouseRegion(
            onEnter: (_) => setState(() => _hover = status),
            onExit: (_) => setState(() => _hover = null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: focus == status
                    ? palette.surfaceOverlay
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  _Swatch(statusColour(palette, status)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(memberStatusName(status),
                        style: TextStyle(
                            fontSize: 12.5, color: palette.textSecondary)),
                  ),
                  Text('${counts[status] ?? 0}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  SizedBox(
                    width: 48,
                    child: Text(_pct(counts[status] ?? 0, total),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12,
                            color: palette.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 420) {
        return Column(
          children: [ring, const SizedBox(height: 14), legend],
        );
      }
      return Row(
        children: [
          ring,
          const SizedBox(width: 24),
          Expanded(child: legend),
        ],
      );
    });
  }

  static String _pct(int count, int total) =>
      '${(count / total * 100).toStringAsFixed(count == total || count == 0 ? 0 : 1)}%';
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.slices, required this.gap});

  final List<(Color, int, bool)> slices;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (a, s) => a + s.$2);
    if (total == 0) return;
    const thickness = 22.0;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.width / 2 - thickness / 2 - 3);
    var start = -math.pi / 2;
    // A 2px gap between slices, in the surface colour, so neighbours read as
    // separate even where their colours are close.
    final gapAngle = slices.length > 1 ? 2 / rect.width * 2 : 0.0;
    for (final (colour, count, focused) in slices) {
      final sweep = 2 * math.pi * count / total;
      canvas.drawArc(
        focused ? rect.inflate(2) : rect,
        start + gapAngle / 2,
        math.max(0.0, sweep - gapAngle),
        false,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = focused ? thickness + 5 : thickness,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}

// --- Membership growth --------------------------------------------------------

/// New members and renewals per month, side by side, for up to a year.
class GrowthChart extends StatelessWidget {
  const GrowthChart({super.key, required this.report, this.height = 200});

  final MonthlyReport report;
  final double height;

  static const _axisWidth = 30.0;
  static const _bottom = 22.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final growth = report.growth;
    if (growth.isEmpty ||
        growth.every((g) => g.newMembers == 0 && g.renewals == 0)) {
      return ChartEmpty('No joining or renewals on record yet.', height: height);
    }
    final axis = niceAxis(
      growth.map((g) => math.max(g.newMembers, g.renewals)).fold(0, math.max),
    );
    final plotHeight = height - _bottom;
    final soft = palette.accent.withValues(alpha: 0.38);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: Stack(
            // The top tick's label sits half above the plot.
            clipBehavior: Clip.none,
            children: [
              for (var t = 0; t <= axis.ticks; t++) ...[
                Positioned(
                  left: 0,
                  width: _axisWidth - 8,
                  top: plotHeight - plotHeight * t / axis.ticks - 7,
                  child: Text('${axis.step * t}',
                      textAlign: TextAlign.right,
                      style:
                          TextStyle(fontSize: 10.5, color: palette.textMuted)),
                ),
                Positioned(
                  left: _axisWidth,
                  right: 0,
                  top: plotHeight - plotHeight * t / axis.ticks,
                  child: Container(height: 1, color: palette.border),
                ),
              ],
              Positioned(
                left: _axisWidth,
                right: 0,
                top: 0,
                bottom: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final g in growth)
                      Expanded(
                        child: Tooltip(
                          message: '${g.month.label}\n'
                              '${g.newMembers} new '
                              '${g.newMembers == 1 ? 'member' : 'members'}\n'
                              '${g.renewals} '
                              '${g.renewals == 1 ? 'renewal' : 'renewals'}',
                          waitDuration: Duration.zero,
                          child: _GrowthColumn(
                            point: g,
                            top: axis.top,
                            plotHeight: plotHeight,
                            strong: palette.accent,
                            soft: soft,
                            selected: g.month == report.month,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            ChartLegendItem(colour: palette.accent, label: 'New members'),
            ChartLegendItem(colour: soft, label: 'Renewals'),
          ],
        ),
      ],
    );
  }
}

class _GrowthColumn extends StatefulWidget {
  const _GrowthColumn({
    required this.point,
    required this.top,
    required this.plotHeight,
    required this.strong,
    required this.soft,
    required this.selected,
  });

  final GrowthPoint point;
  final int top;
  final double plotHeight;
  final Color strong;
  final Color soft;
  final bool selected;

  @override
  State<_GrowthColumn> createState() => _GrowthColumnState();
}

class _GrowthColumnState extends State<_GrowthColumn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    double h(int v) => widget.top == 0 ? 0 : widget.plotHeight * v / widget.top;

    Widget bar(int value, Color colour) => Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 14),
            child: Container(
              height: math.max(value == 0 ? 0 : 2, h(value)),
              decoration: BoxDecoration(
                color: colour,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ),
        );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        color: _hover ? palette.surfaceOverlay : Colors.transparent,
        child: Column(
          children: [
            SizedBox(
              height: widget.plotHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    bar(widget.point.newMembers, widget.strong),
                    const SizedBox(width: 2),
                    bar(widget.point.renewals, widget.soft),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.point.month.shortName,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                color: widget.selected
                    ? palette.textPrimary
                    : palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Revenue breakdown ----------------------------------------------------------

enum BreakdownBy { method, plan }

/// The month's revenue split by payment method or by plan, as bars sorted
/// largest first. One hue throughout: the bars compare sizes, and the label
/// beside each says what it is.
class RevenueBreakdown extends StatefulWidget {
  const RevenueBreakdown({
    super.key,
    required this.report,
    required this.obscured,
    this.minHeight = 0,
  });

  final MonthlyReport report;
  final bool obscured;
  final double minHeight;

  @override
  State<RevenueBreakdown> createState() => _RevenueBreakdownState();
}

class _RevenueBreakdownState extends State<RevenueBreakdown> {
  BreakdownBy _by = BreakdownBy.method;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final report = widget.report;
    final slices =
        _by == BreakdownBy.method ? report.byMethod : report.byPlan;
    final total = report.revenue.value;

    final toggle = SegmentedFilter<BreakdownBy>(
      options: const [
        SegmentOption(value: BreakdownBy.method, label: 'Method'),
        SegmentOption(value: BreakdownBy.plan, label: 'Plan'),
      ],
      selected: _by,
      onSelect: (v) => setState(() => _by = v),
    );

    final body = slices.isEmpty || total == 0
        ? ChartEmpty('No payments recorded in ${report.month.label}.',
            height: 140)
        : Column(
            children: [
              for (final s in slices)
                Tooltip(
                  message: '${s.label}: ${s.count} '
                      '${s.count == 1 ? 'payment' : 'payments'}',
                  waitDuration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(s.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: palette.textSecondary)),
                            ),
                            Text(
                              widget.obscured
                                  ? revenueMask
                                  : formatMinorUnits(s.amountMinor),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ]),
                            ),
                            SizedBox(
                              width: 46,
                              child: Text(
                                '${(s.amountMinor / total * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 12, color: palette.textMuted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            children: [
                              Container(height: 8, color: palette.surfaceOverlay),
                              FractionallySizedBox(
                                widthFactor: slices.first.amountMinor == 0
                                    ? 0
                                    : s.amountMinor / slices.first.amountMinor,
                                child: Container(
                                    height: 8, color: palette.accent),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );

    return ChartPanel(
      title: 'Revenue breakdown',
      subtitle: _by == BreakdownBy.method
          ? 'By how members paid'
          : 'By the plan of the month each payment paid for',
      trailing: toggle,
      minHeight: widget.minHeight,
      child: body,
    );
  }
}
