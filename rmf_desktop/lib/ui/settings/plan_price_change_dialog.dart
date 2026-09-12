import 'package:flutter/material.dart';

import '../../data/settings_repository.dart';
import '../../domain/money.dart';
import '../../theme/app_theme.dart';

/// Asked before a plan price edit is allowed to reach the roster.
///
/// This is the furthest-reaching button in the app: it re-prices the open,
/// unpaid bill of every active member on the plan who has no fee of their own.
/// The price field gave no hint of that, so an owner correcting a typo in a
/// price and an owner putting the gym's fees up pressed the same button with
/// the same information — none.
///
/// The counts come from [SettingsRepository.planPricingImpact], which asks the
/// same question `repriceOpenCyclesForPlan` acts on, so the number promised
/// here is the number that moves.
class PlanPriceChangeDialog extends StatelessWidget {
  const PlanPriceChangeDialog({
    super.key,
    required this.planName,
    required this.previousPriceMinor,
    required this.newPriceMinor,
    required this.impact,
  });

  final String planName;
  final int previousPriceMinor;
  final int newPriceMinor;
  final PlanPricingImpact impact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;

    final following = impact.followingPlanPrice;
    final custom = impact.onCustomFee;

    return AlertDialog(
      backgroundColor: palette.surfaceRaised,
      title: Text('Change $planName price?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatMinorUnits(previousPriceMinor)} → '
              '${formatMinorUnits(newPriceMinor)}',
              style: text.titleMedium?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            if (impact.isEmpty)
              Text(
                'No members are on this plan, so nobody\'s bill changes.',
                style: text.bodyMedium?.copyWith(color: palette.textSecondary),
              )
            else ...[
              _Line(
                text: following == 1
                    ? '1 member follows this price. Their current unpaid bill '
                        'and any later one change to '
                        '${formatMinorUnits(newPriceMinor)}.'
                    : '$following members follow this price. Their current '
                        'unpaid bill and any later one change to '
                        '${formatMinorUnits(newPriceMinor)}.',
                color: palette.textPrimary,
              ),
              if (custom > 0) ...[
                const SizedBox(height: 8),
                _Line(
                  text: custom == 1
                      ? '1 member is on a custom fee and is not affected.'
                      : '$custom members are on a custom fee and are not '
                          'affected.',
                  color: palette.textSecondary,
                ),
              ],
            ],
            const SizedBox(height: 12),
            Text(
              'Months already paid, or part-paid, keep the price that was '
              'charged at the time.',
              style: text.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Change price'),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
      );
}
