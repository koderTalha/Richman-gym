import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/dates.dart';
import '../domain/member_status.dart';
import '../domain/money.dart';
import '../domain/monthly_report.dart';
import '../domain/payment_method.dart';

/// The typeface the report is set in — Inter, the app's own, bundled with it.
///
/// Passed in as bytes rather than loaded here so [buildReportPdf] does no
/// asset IO and stays testable; the PDF's built-in Helvetica has no glyph for
/// the dashes and middots every label in this app uses.
class ReportFonts {
  ReportFonts({
    required ByteData regular,
    required ByteData medium,
    required ByteData bold,
  })  : regular = pw.Font.ttf(regular),
        medium = pw.Font.ttf(medium),
        bold = pw.Font.ttf(bold);

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;
}

/// What the PDF needs beyond the report itself.
class ReportPdfInput {
  const ReportPdfInput({
    required this.report,
    required this.gymName,
    required this.brand,
    required this.planNames,
    this.gymAddress,
    this.gymPhone,
    this.logoBytes,
  });

  final MonthlyReport report;
  final String gymName;
  final String? gymAddress;
  final String? gymPhone;
  final Uint8List? logoBytes;

  /// The gym's brand colour. Used for fills and rules only: on white paper
  /// several of the presets are too light to be read as text.
  final Color brand;

  /// For naming the plan filter.
  final Map<int, String> planNames;
}

/// "Gym_Report_October_2026.pdf".
String reportFileName(ReportMonth month) =>
    'Gym_Report_${month.name}_${month.year}.pdf';

// Paper colours. Fixed rather than taken from the app's theme: a printed
// report is read on white whichever theme the counter PC is in.
const _ink = PdfColor.fromInt(0xFF16161A);
const _secondary = PdfColor.fromInt(0xFF3A3A44);
const _muted = PdfColor.fromInt(0xFF63636E);
const _rule = PdfColor.fromInt(0xFFE4E4E8);
const _panel = PdfColor.fromInt(0xFFF7F7F8);
const _good = PdfColor.fromInt(0xFF146C34);
const _bad = PdfColor.fromInt(0xFFB91C1C);

const _statusColours = {
  MemberStatus.paid: PdfColor.fromInt(0xFF22A456),
  MemberStatus.due: PdfColor.fromInt(0xFFE0951A),
  MemberStatus.expired: PdfColor.fromInt(0xFFD93636),
  MemberStatus.inactive: PdfColor.fromInt(0xFF9A9AA6),
};

/// The monthly report as an A4 business document: a summary page, the
/// charts, then every payment and the member detail, with page numbers, the
/// time it was made and the filters it was made under on every page.
///
/// Draws only from [ReportPdfInput.report] — the object the screen is showing
/// — so the paper and the screen agree to the rupee.
Future<Uint8List> buildReportPdf(ReportPdfInput input, ReportFonts fonts) async {
  final report = input.report;
  final brand = PdfColor.fromInt(input.brand.toARGB32());
  // Mixed with white rather than given alpha: a PDF fill ignores the colour's
  // alpha, which drew renewals in exactly the new-member colour.
  final brandSoft = PdfColor(
    1 - (1 - brand.red) * 0.4,
    1 - (1 - brand.green) * 0.4,
    1 - (1 - brand.blue) * 0.4,
  );
  final logo = input.logoBytes == null ? null : pw.MemoryImage(input.logoBytes!);
  final filters = report.filters.describe(input.planNames);
  final generated = _timestamp(report.generatedAt);

  final doc = pw.Document(
    title: '${input.gymName} — ${report.month.label} report',
    author: input.gymName,
    creator: 'Rich Man Fitness',
    theme: pw.ThemeData.withFont(
      base: fonts.regular,
      bold: fonts.bold,
      italic: fonts.regular,
      boldItalic: fonts.bold,
    ),
  );

  pw.TextStyle style(double size,
          {PdfColor color = _ink, pw.Font? font, double? letterSpacing}) =>
      pw.TextStyle(
        fontSize: size,
        color: color,
        font: font ?? fonts.regular,
        letterSpacing: letterSpacing,
      );

  pw.Widget heading(String text, {String? note}) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(text, style: style(14, font: fonts.bold)),
            if (note != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(note, style: style(8.5, color: _muted)),
            ],
          ],
        ),
      );

  final pageTheme = pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
  );

  pw.Widget footer(pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.6)),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                '${input.gymName} · ${report.month.label} report · '
                'Generated $generated'
                '${filters.isEmpty ? '' : ' · Filtered: ${filters.join(', ')}'}',
                style: style(7, color: _muted),
                maxLines: 2,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: style(7, color: _muted)),
          ],
        ),
      );

  pw.Widget runningHeader(pw.Context context) => context.pageNumber == 1
      ? pw.SizedBox()
      : pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 14),
          padding: const pw.EdgeInsets.only(bottom: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.6)),
          ),
          child: pw.Row(
            children: [
              pw.Container(width: 3, height: 10, color: brand),
              pw.SizedBox(width: 6),
              pw.Text(input.gymName,
                  style: style(8.5, font: fonts.medium, color: _secondary)),
              pw.Spacer(),
              pw.Text('Monthly report · ${report.month.label}',
                  style: style(8.5, color: _muted)),
            ],
          ),
        );

  // --- Page 1: the summary ---------------------------------------------------

  final cover = <pw.Widget>[
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) ...[
          pw.Container(
            width: 46,
            height: 46,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 14),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(input.gymName.toUpperCase(),
                  style: style(9, font: fonts.bold, color: _secondary,
                      letterSpacing: 1.2)),
              pw.SizedBox(height: 3),
              pw.Text('Monthly report', style: style(24, font: fonts.bold)),
              pw.Text(report.month.label,
                  style: style(13, font: fonts.medium, color: _secondary)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Generated', style: style(7.5, color: _muted)),
            pw.Text(generated, style: style(9, font: fonts.medium)),
            if (input.gymPhone != null && input.gymPhone!.trim().isNotEmpty)
              pw.Text(input.gymPhone!, style: style(8, color: _muted)),
          ],
        ),
      ],
    ),
    pw.SizedBox(height: 10),
    pw.Container(height: 3, color: brand),
    pw.SizedBox(height: 12),
    _notice(
      style: style(8.5, color: _secondary),
      lines: [
        report.isCurrentMonth
            ? 'The month is still running: figures are to '
                '${_timestamp(report.snapshotAt)} and will change.'
            : 'Member counts and statuses are as they stood at the end of '
                '${report.month.label}.',
        if (filters.isNotEmpty) 'Filtered — ${filters.join(' · ')}.',
        'Contains the gym\'s revenue figures. Treat as confidential.',
      ],
    ),
    pw.SizedBox(height: 16),
    heading('Money', note: _comparisonNote(report)),
    _tileGrid([
      _tile(fonts, 'Revenue this month', formatMinorUnits(report.revenue.value),
          '${report.paymentCount.value} payment'
              '${report.paymentCount.value == 1 ? '' : 's'}',
          trend: _trend(report.revenue, money: true)),
      _tile(fonts, 'Collected to date',
          formatMinorUnits(report.collectedToDateMinor),
          'Every payment to the end of ${report.month.name}'),
      _tile(fonts, 'Payments', '${report.paymentCount.value}',
          '${report.payingMembers} member${report.payingMembers == 1 ? '' : 's'} paid',
          trend: _trend(report.paymentCount)),
      _tile(
          fonts,
          'Average per paying member',
          report.averagePerPayingMemberMinor == null
              ? '—'
              : formatMinorUnits(report.averagePerPayingMemberMinor!),
          'Revenue ÷ members who paid'),
      _tile(fonts, 'Unpaid fees', formatMinorUnits(report.owed.value),
          '${report.owingMembers} member${report.owingMembers == 1 ? '' : 's'} owing',
          trend: _trend(report.owed, money: true, higherIsBetter: false)),
    ]),
    pw.SizedBox(height: 14),
    heading('Members',
        note: report.isCurrentMonth
            ? 'Counts as of now. Joined and renewed are for the month so far.'
            : 'Counts at the end of the month.'),
    _tileGrid([
      _tile(fonts, 'Total members', '${report.totalMembers.value}',
          'On the roster, inactive included',
          trend: _trend(report.totalMembers)),
      _tile(fonts, 'Active', '${report.activeMembers.value}',
          'Not deactivated', trend: _trend(report.activeMembers)),
      _tile(fonts, 'New members', '${report.newMembers.value}',
          'Joined in ${report.month.name}', trend: _trend(report.newMembers)),
      _tile(fonts, 'Renewals', '${report.renewals.value}',
          'Existing members who paid', trend: _trend(report.renewals)),
      _tile(fonts, 'Expired', '${report.expiredMembers.value}',
          'Lapsed, last cycle ended unpaid',
          trend: _trend(report.expiredMembers, higherIsBetter: false)),
    ]),
    pw.SizedBox(height: 16),
    heading('Overview'),
    pw.Text(_overview(report), style: style(10, color: _secondary)),
  ];

  // --- Analytics ---------------------------------------------------------------

  final analytics = <pw.Widget>[
    pw.NewPage(),
    heading('Revenue by day',
        note: report.importedRevenueMinor > 0
            ? '${formatMinorUnits(report.importedRevenueMinor)} came from the '
                'Excel ledger, which records the month but not the day, and is '
                'not plotted.'
            : 'Payments recorded in the app, by the day they were taken.'),
    _dailyChart(report, fonts, brand),
    pw.SizedBox(height: 22),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              heading('Membership status',
                  note: report.isCurrentMonth ? 'As of now' : 'At month end'),
              _statusChart(report, fonts),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              heading('Membership growth',
                  note: 'New members and renewals, by month'),
              _growthChart(report, fonts, brand, brandSoft),
            ],
          ),
        ),
      ],
    ),
    pw.SizedBox(height: 22),
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              heading('Revenue by payment method'),
              _breakdown(report.byMethod, report.revenue.value, fonts, brand),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              heading('Revenue by plan',
                  note: 'The plan of the month each payment paid for'),
              _breakdown(report.byPlan, report.revenue.value, fonts, brand),
            ],
          ),
        ),
      ],
    ),
  ];

  // --- Detail --------------------------------------------------------------------

  final newMembers = report.members.where((m) => m.isNew).toList();
  final owing = report.members.where((m) => m.arrearsMinor > 0).toList()
    ..sort((a, b) => b.arrearsMinor != a.arrearsMinor
        ? b.arrearsMinor.compareTo(a.arrearsMinor)
        : a.memberCode.compareTo(b.memberCode));

  final detail = <pw.Widget>[
    pw.NewPage(),
    heading('Payments',
        note: '${report.payments.length} payment'
            '${report.payments.length == 1 ? '' : 's'} in ${report.month.label}, '
            'newest first'),
    if (report.payments.isEmpty)
      pw.Text('No payments were recorded in ${report.month.label}.',
          style: style(9.5, color: _muted))
    else
      _table(
        fonts: fonts,
        headers: const ['Date', 'Receipt', 'Member', 'Plan', 'Method', 'Amount'],
        widths: const [1.3, 1.7, 2.6, 1.6, 1.3, 1.4],
        numeric: const {5},
        rows: [
          for (final p in report.payments)
            [
              p.imported
                  ? '${report.month.shortName} ${report.month.year}*'
                  : formatDayMonthYear(p.paidAt),
              p.receiptNumber ?? '—',
              '${p.memberName} (#${p.memberCode})',
              p.planName ?? '—',
              paymentMethodLabel(p.method),
              formatMinorUnits(p.amountMinor),
            ],
        ],
        total: ['Total', '', '', '', '', formatMinorUnits(report.revenue.value)],
      ),
    if (report.payments.any((p) => p.imported)) ...[
      pw.SizedBox(height: 4),
      pw.Text('* From the Excel ledger, which records the month and not the day.',
          style: style(7.5, color: _muted)),
    ],
    pw.SizedBox(height: 20),
    heading('Members who joined',
        note: '${newMembers.length} in ${report.month.label}'),
    if (newMembers.isEmpty)
      pw.Text('Nobody joined in ${report.month.label}.',
          style: style(9.5, color: _muted))
    else
      _table(
        fonts: fonts,
        headers: const ['Member', 'Plan', 'Joined', 'Paid this month', 'Status'],
        widths: const [2.8, 1.8, 1.4, 1.6, 1.1],
        numeric: const {3},
        rows: [
          for (final m in newMembers)
            [
              '${m.name} (#${m.memberCode})',
              m.planName ?? '—',
              formatDayMonthYear(m.joiningDate),
              formatMinorUnits(m.paidThisMonthMinor),
              memberStatusName(m.status),
            ],
        ],
      ),
    pw.SizedBox(height: 20),
    heading('Unpaid fees',
        note: owing.isEmpty
            ? null
            : '${owing.length} member${owing.length == 1 ? '' : 's'} owing '
                '${formatMinorUnits(report.owed.value)} '
                '${report.isCurrentMonth ? 'now' : 'at the end of the month'}, '
                'largest first'),
    if (owing.isEmpty)
      pw.Text('Nothing was owed.', style: style(9.5, color: _muted))
    else
      _table(
        fonts: fonts,
        headers: const ['Member', 'Plan', 'Paid until', 'Status', 'Owed'],
        widths: const [2.8, 1.8, 1.4, 1.1, 1.5],
        numeric: const {4},
        rows: [
          for (final m in owing)
            [
              '${m.name} (#${m.memberCode})',
              m.planName ?? '—',
              m.paidUntil == null ? '—' : formatDayMonthYear(m.paidUntil!),
              memberStatusName(m.status),
              formatMinorUnits(m.arrearsMinor),
            ],
        ],
        total: ['Total', '', '', '', formatMinorUnits(report.owed.value)],
      ),
  ];

  doc.addPage(pw.MultiPage(
    pageTheme: pageTheme,
    header: runningHeader,
    footer: footer,
    build: (_) => [...cover, ...analytics, ...detail],
  ));

  return doc.save();
}

String _timestamp(DateTime at) {
  final local = at.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${formatDayMonthYear(local)}, $hour:$minute '
      '${local.hour < 12 ? 'AM' : 'PM'}';
}

String? _comparisonNote(MonthlyReport report) => report.comparisonLabel == null
    ? 'No earlier month on record to compare with.'
    : 'Changes are against ${report.comparisonLabel}.';

/// A plain-words paragraph of the month, built only from figures on the page.
String _overview(MonthlyReport report) {
  final parts = <String>[];
  final payments = report.paymentCount.value;
  if (payments == 0) {
    parts.add('No payments were recorded in ${report.month.label}.');
  } else {
    final pct = percentChange(report.revenue);
    parts.add('${formatMinorUnits(report.revenue.value)} came in from '
        '$payments payment${payments == 1 ? '' : 's'} by '
        '${report.payingMembers} member${report.payingMembers == 1 ? '' : 's'}'
        '${pct == null ? '' : ', $pct on ${report.comparisonLabel}'}.');
  }
  parts.add('${report.newMembers.value} '
      '${report.newMembers.value == 1 ? 'member' : 'members'} joined and '
      '${report.renewals.value} renewed.');
  parts.add(report.owed.value == 0
      ? 'Nothing was owed ${report.isCurrentMonth ? 'as of now' : 'at the end of the month'}.'
      : '${formatMinorUnits(report.owed.value)} was owed by '
          '${report.owingMembers} member${report.owingMembers == 1 ? '' : 's'} '
          '${report.isCurrentMonth ? 'as of now' : 'at the end of the month'}, '
          'and ${report.expiredMembers.value} '
          '${report.expiredMembers.value == 1 ? 'membership had' : 'memberships had'} '
          'expired.');
  return parts.join(' ');
}

pw.Widget _notice({required pw.TextStyle style, required List<String> lines}) =>
    pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _panel,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: _rule, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Text(line, style: style),
            ),
        ],
      ),
    );

class _Trend {
  const _Trend(this.text, this.good);
  final String text;

  /// Null for no change.
  final bool? good;
}

_Trend? _trend(Compared figure,
    {bool money = false, bool higherIsBetter = true}) {
  final change = figure.change;
  if (change == null) return null;
  if (change == 0) return const _Trend('No change', null);
  final pct = percentChange(figure);
  final text = money
      ? (pct ?? (change > 0 ? 'Up from nothing' : 'Down'))
      : '${change > 0 ? '+' : '−'}${change.abs()}${pct == null ? '' : ' ($pct)'}';
  return _Trend(text, (change > 0) == higherIsBetter);
}

pw.Widget _tileGrid(List<pw.Widget> tiles) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) pw.SizedBox(width: 6),
          pw.Expanded(child: tiles[i]),
        ],
      ],
    );

pw.Widget _tile(ReportFonts fonts, String label, String value, String caption,
    {_Trend? trend}) {
  return pw.Container(
    height: 84,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _rule, width: 0.6),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label.toUpperCase(),
            style: pw.TextStyle(
                font: fonts.medium, fontSize: 6.5, color: _muted,
                letterSpacing: 0.5),
            maxLines: 2),
        pw.SizedBox(height: 4),
        pw.Text(value,
            style: pw.TextStyle(font: fonts.bold, fontSize: 12.5, color: _ink),
            maxLines: 1),
        pw.SizedBox(height: 2),
        pw.Text(caption,
            style: pw.TextStyle(font: fonts.regular, fontSize: 7, color: _muted),
            maxLines: 2),
        pw.Spacer(),
        // The sign in the text carries the direction, so it survives a
        // black-and-white printer; the colour only adds to it.
        if (trend != null)
          pw.Text(
            trend.text,
            style: pw.TextStyle(
              font: fonts.medium,
              fontSize: 7,
              color: trend.good == null
                  ? _muted
                  : (trend.good! ? _good : _bad),
            ),
          ),
      ],
    ),
  );
}

pw.Widget _axisLabel(String text, ReportFonts fonts) => pw.Text(text,
    style: pw.TextStyle(font: fonts.regular, fontSize: 6.5, color: _muted));

/// Daily revenue as an area with the previous month as a dashed line. Drawn
/// on the page's own canvas so it is vector, not a screenshot.
pw.Widget _dailyChart(MonthlyReport report, ReportFonts fonts, PdfColor brand) {
  const plotHeight = 160.0;
  const axisWidth = 34.0;
  const labelHeight = 8.0;
  final days = report.dailyRevenueMinor.sublist(0, report.daysElapsed);
  final slots = report.dailyRevenueMinor.length;
  final previous = report.previousDailyRevenueMinor;

  if (days.every((d) => d == 0)) {
    return pw.Container(
      height: 60,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _rule, width: 0.6),
          borderRadius: pw.BorderRadius.circular(4)),
      child: pw.Text('No payments were recorded in the app this month.',
          style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _muted)),
    );
  }

  final axis = niceAxis([...days, ...?previous].fold<int>(0, math.max));

  // Day d sits at the same x in both months, so the 10th is compared with
  // the 10th; the 31st of a longer previous month runs off the right edge
  // and is left out rather than squeezing this month's axis.
  double x(int dayIndex, double width) =>
      slots <= 1 ? width / 2 : width * dayIndex / (slots - 1);
  double y(int value) => plotHeight * value / axis.top;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        height: plotHeight + labelHeight + 6,
        child: pw.LayoutBuilder(builder: (context, constraints) {
          final width = (constraints?.maxWidth ?? 400) - axisWidth - 6;
          return pw.Stack(
            overflow: pw.Overflow.visible,
            children: [
              // Value labels, each centred on its gridline.
              for (var i = 0; i <= axis.ticks; i++)
                pw.Positioned(
                  left: 0,
                  top: plotHeight - plotHeight * i / axis.ticks - labelHeight / 2,
                  child: pw.SizedBox(
                    width: axisWidth,
                    child: pw.Text(formatCompactMinor(axis.step * i),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 6.5, color: _muted)),
                  ),
                ),
              pw.Positioned(
                left: axisWidth + 6,
                top: 0,
                child: pw.SizedBox(
                  width: width,
                  height: plotHeight,
                  child: pw.CustomPaint(
                    size: PdfPoint(width, plotHeight),
                    painter: (canvas, size) {
                      canvas
                        ..setStrokeColor(_rule)
                        ..setLineWidth(0.5);
                      for (var i = 0; i <= axis.ticks; i++) {
                        final gy = size.y * i / axis.ticks;
                        canvas
                          ..moveTo(0, gy)
                          ..lineTo(size.x, gy);
                      }
                      canvas.strokePath();

                      if (previous != null) {
                        canvas
                          ..setStrokeColor(_muted)
                          ..setLineWidth(0.9)
                          ..setLineDashPattern([3, 2]);
                        final n = math.min(previous.length, slots);
                        for (var i = 0; i < n; i++) {
                          if (i == 0) {
                            canvas.moveTo(x(i, size.x), y(previous[i]));
                          } else {
                            canvas.lineTo(x(i, size.x), y(previous[i]));
                          }
                        }
                        canvas
                          ..strokePath()
                          ..setLineDashPattern();
                      }

                      canvas
                        ..saveContext()
                        ..setGraphicState(const PdfGraphicState(opacity: 0.14))
                        ..setFillColor(brand)
                        ..moveTo(x(0, size.x), 0);
                      for (var i = 0; i < days.length; i++) {
                        canvas.lineTo(x(i, size.x), y(days[i]));
                      }
                      canvas
                        ..lineTo(x(days.length - 1, size.x), 0)
                        ..closePath()
                        ..fillPath()
                        ..restoreContext();

                      canvas
                        ..setStrokeColor(brand)
                        ..setLineWidth(1.6)
                        ..setLineJoin(PdfLineJoin.round);
                      for (var i = 0; i < days.length; i++) {
                        if (i == 0) {
                          canvas.moveTo(x(i, size.x), y(days[i]));
                        } else {
                          canvas.lineTo(x(i, size.x), y(days[i]));
                        }
                      }
                      canvas.strokePath();
                    },
                  ),
                ),
              ),
              // Day labels, each under its own day.
              for (final day in _dayTicks(slots))
                pw.Positioned(
                  // Centred under its day, but kept inside the plot at
                  // either end.
                  left: axisWidth + 6 +
                      (x(day - 1, width) - 20).clamp(-8.0, width - 32),
                  top: plotHeight + 5,
                  child: pw.SizedBox(
                    width: 40,
                    child: pw.Text('$day ${report.month.shortName}',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 6.5, color: _muted)),
                  ),
                ),
            ],
          );
        }),
      ),
      pw.SizedBox(height: 8),
      pw.Row(
        children: [
          _legendSwatch(brand),
          pw.SizedBox(width: 4),
          _axisLabel(
              report.isCurrentMonth
                  ? '${report.month.label}, to today'
                  : report.month.label,
              fonts),
          if (previous != null) ...[
            pw.SizedBox(width: 14),
            pw.Container(width: 10, height: 1, color: _muted),
            pw.SizedBox(width: 4),
            _axisLabel('${report.month.previous.label} (dashed)', fonts),
          ],
        ],
      ),
    ],
  );
}

List<int> _dayTicks(int days) => [1, 8, 15, 22, days];

pw.Widget _legendSwatch(PdfColor color) => pw.Container(
      width: 8,
      height: 8,
      decoration: pw.BoxDecoration(
          color: color, borderRadius: pw.BorderRadius.circular(2)),
    );

pw.Widget _statusChart(MonthlyReport report, ReportFonts fonts) {
  final total = report.statusCounts.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) {
    return pw.Text('No members on the roster.',
        style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _muted));
  }
  final present = [
    for (final status in MemberStatus.values)
      if ((report.statusCounts[status] ?? 0) > 0) status,
  ];
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(
        width: 96,
        height: 96,
        child: pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            pw.Chart(
              grid: pw.PieGrid(),
              datasets: [
                for (final status in present)
                  pw.PieDataSet(
                    value: report.statusCounts[status]!,
                    color: _statusColours[status]!,
                    innerRadius: 30,
                    legendPosition: pw.PieLegendPosition.none,
                    drawBorder: true,
                    borderColor: PdfColors.white,
                    borderWidth: 1.2,
                  ),
              ],
            ),
            pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('$total',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 13)),
                _axisLabel('members', fonts),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(width: 14),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final status in MemberStatus.values)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                child: pw.Row(
                  children: [
                    _legendSwatch(_statusColours[status]!),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Text(memberStatusName(status),
                          style: pw.TextStyle(
                              font: fonts.regular, fontSize: 8.5)),
                    ),
                    pw.Text('${report.statusCounts[status] ?? 0}',
                        style:
                            pw.TextStyle(font: fonts.medium, fontSize: 8.5)),
                    pw.SizedBox(
                      width: 34,
                      child: pw.Text(
                        '${((report.statusCounts[status] ?? 0) / total * 100).round()}%',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 8.5, color: _muted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _growthChart(MonthlyReport report, ReportFonts fonts,
    PdfColor brand, PdfColor brandSoft) {
  final growth = report.growth;
  if (growth.isEmpty) {
    return pw.Text('Nothing on record yet.',
        style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _muted));
  }
  final peak = growth
      .map((g) => math.max(g.newMembers, g.renewals))
      .fold<int>(0, math.max);
  const plotHeight = 80.0;
  double bar(int v) => peak == 0 ? 0 : plotHeight * v / peak;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Highest month: $peak',
          style: pw.TextStyle(font: fonts.regular, fontSize: 6.5, color: _muted)),
      pw.SizedBox(height: 4),
      pw.SizedBox(
        height: plotHeight,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            for (final g in growth)
              pw.Expanded(
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(width: 5, height: bar(g.newMembers), color: brand),
                    pw.SizedBox(width: 1),
                    pw.Container(
                        width: 5, height: bar(g.renewals), color: brandSoft),
                  ],
                ),
              ),
          ],
        ),
      ),
      pw.Container(height: 0.6, color: _rule),
      pw.SizedBox(height: 3),
      pw.Row(
        children: [
          for (final g in growth)
            pw.Expanded(
              child: pw.Text(g.month.shortName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: fonts.regular, fontSize: 6.5, color: _muted)),
            ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          _legendSwatch(brand),
          pw.SizedBox(width: 4),
          _axisLabel('New members', fonts),
          pw.SizedBox(width: 12),
          _legendSwatch(brandSoft),
          pw.SizedBox(width: 4),
          _axisLabel('Renewals', fonts),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        '${growth.first.month.label} – ${growth.last.month.label}: '
        '${growth.fold<int>(0, (a, g) => a + g.newMembers)} joined, '
        '${growth.fold<int>(0, (a, g) => a + g.renewals)} renewals.',
        style: pw.TextStyle(font: fonts.regular, fontSize: 7.5, color: _muted),
      ),
    ],
  );
}

pw.Widget _breakdown(List<BreakdownSlice> slices, int total, ReportFonts fonts,
    PdfColor brand) {
  if (slices.isEmpty || total == 0) {
    return pw.Text('No payments to break down.',
        style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _muted));
  }
  final largest = slices.first.amountMinor;
  return pw.Column(
    children: [
      for (final s in slices)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(s.label,
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8.5),
                        maxLines: 1),
                  ),
                  pw.Text(formatMinorUnits(s.amountMinor),
                      style: pw.TextStyle(font: fonts.medium, fontSize: 8.5)),
                  pw.SizedBox(
                    width: 30,
                    child: pw.Text('${(s.amountMinor / total * 100).round()}%',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            font: fonts.regular, fontSize: 8, color: _muted)),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.LayoutBuilder(
                builder: (context, constraints) => pw.Container(
                  height: 4,
                  width: (constraints?.maxWidth ?? 100) *
                      (largest == 0 ? 0 : s.amountMinor / largest),
                  decoration: pw.BoxDecoration(
                      color: brand, borderRadius: pw.BorderRadius.circular(2)),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// A table that breaks across pages with its header row repeated on each.
pw.Widget _table({
  required ReportFonts fonts,
  required List<String> headers,
  required List<double> widths,
  required List<List<String>> rows,
  Set<int> numeric = const {},
  List<String>? total,
}) {
  pw.Widget cell(String text, int column,
          {bool header = false, bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(
          header ? text.toUpperCase() : text,
          textAlign: numeric.contains(column)
              ? pw.TextAlign.right
              : pw.TextAlign.left,
          maxLines: 2,
          style: pw.TextStyle(
            font: header || bold ? fonts.medium : fonts.regular,
            fontSize: header ? 6.5 : 8,
            letterSpacing: header ? 0.4 : null,
            color: header ? _muted : _ink,
          ),
        ),
      );

  return pw.Table(
    columnWidths: {
      for (var i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[i]),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _rule, width: 0.5),
      bottom: pw.BorderSide(color: _rule, width: 0.5),
    ),
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _panel),
        children: [
          for (var i = 0; i < headers.length; i++)
            cell(headers[i], i, header: true),
        ],
      ),
      for (final row in rows)
        pw.TableRow(
          children: [for (var i = 0; i < row.length; i++) cell(row[i], i)],
        ),
      if (total != null)
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _panel),
          children: [
            for (var i = 0; i < total.length; i++)
              cell(total[i], i, bold: true),
          ],
        ),
    ],
  );
}
