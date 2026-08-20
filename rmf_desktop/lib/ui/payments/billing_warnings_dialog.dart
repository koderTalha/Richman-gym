import 'package:flutter/material.dart';

import '../../domain/billing_month_check.dart';
import '../../theme/app_theme.dart';

/// Shows every billing-month warning at once and asks whether to continue.
///
/// One dialog, however many findings there are: three warnings used to mean
/// three popups in a row, which is how a busy owner learns to dismiss them all
/// without reading any.
///
/// Returns true only on an explicit confirmation.
Future<bool> confirmBillingWarnings(
  BuildContext context,
  List<BillingMonthFinding> findings, {
  required String continueLabel,
}) async {
  if (findings.isEmpty) return true;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dialogContext.palette.surfaceRaised,
      title: Text(findings.length == 1
          ? 'Please confirm'
          : 'Please confirm the following'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final finding in findings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 16, color: dialogContext.palette.due),
                  ),
                  Expanded(
                    child: Text(finding.message,
                        style: TextStyle(
                            fontSize: 13,
                            color: dialogContext.palette.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(continueLabel),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
