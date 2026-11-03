import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:printing/printing.dart';

import '../../bloc/revenue_visibility_cubit.dart';
import '../../data/settings_repository.dart';
import '../../domain/monthly_report.dart';
import '../../services/logo_storage.dart';
import '../../services/report_pdf.dart';

final _log = Logger('reports.export');

/// Renders [report] — the one on screen — as the PDF.
///
/// Reads the gym's name, logo and brand fresh from settings, so a logo
/// changed a minute ago is the one printed.
Future<Uint8List> renderReportPdf(
  BuildContext context,
  MonthlyReport report, {
  required Map<int, String> planNames,
}) async {
  final settings = context.read<SettingsRepository>();
  final gym = await settings.get();
  final branding = await settings.branding();
  Future<ByteData> font(String weight) =>
      rootBundle.load('assets/fonts/Inter-$weight.ttf');

  return buildReportPdf(
    ReportPdfInput(
      report: report,
      gymName: gym.gymName,
      gymAddress: gym.address,
      gymPhone: gym.phone,
      logoBytes: await LogoStorage.read(gym.logoPath),
      brand: branding.effectivePreset.primary,
      planNames: planNames,
    ),
    ReportFonts(
      regular: await font('Regular'),
      medium: await font('Medium'),
      bold: await font('Bold'),
    ),
  );
}

/// With the figures hidden on screen, says before going ahead that the paper
/// will show them anyway — the report is no use to anyone without them, and
/// the owner should not find out from the printer.
Future<bool> confirmRevenueOnPaper(BuildContext context, String action) async {
  if (context.read<RevenueVisibilityCubit>().state) return true;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.visibility_outlined),
      title: const Text('This report shows revenue'),
      content: const Text(
        'Revenue is hidden on screen, but the report includes every amount: '
        'revenue, payments and unpaid fees. Anyone who sees the paper or the '
        'file will see them.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// Asks where to save the PDF, then writes it there. Returns the path
/// written, or null if the owner cancelled.
Future<String?> exportReportPdf(
  BuildContext context,
  MonthlyReport report, {
  required Map<int, String> planNames,
}) async {
  if (!await confirmRevenueOnPaper(context, 'Export anyway')) return null;
  if (!context.mounted) return null;

  final location = await getSaveLocation(
    suggestedName: reportFileName(report.month),
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ],
  );
  if (location == null || !context.mounted) return null;

  final bytes = await renderReportPdf(context, report, planNames: planNames);
  var path = location.path;
  if (!path.toLowerCase().endsWith('.pdf')) path = '$path.pdf';
  await File(path).writeAsBytes(bytes);
  _log.info('Exported the ${report.month.label} report');
  return path;
}

/// Opens the system print dialog on the PDF — the same document Export
/// writes, so the page printed is the page saved. "Save as PDF" in that
/// dialog is a second way to the file.
Future<void> printReport(
  BuildContext context,
  MonthlyReport report, {
  required Map<int, String> planNames,
}) async {
  if (!await confirmRevenueOnPaper(context, 'Print anyway')) return;
  if (!context.mounted) return;

  final bytes = await renderReportPdf(context, report, planNames: planNames);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: reportFileName(report.month).replaceAll('.pdf', ''),
  );
}
