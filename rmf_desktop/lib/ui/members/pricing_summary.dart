import 'package:flutter/material.dart';

import '../../domain/money.dart';
import '../../theme/app_theme.dart';

/// What this member is billed, and what a change to it is about to do.
///
/// The fee field is one number in a form of eleven, and until this existed
/// nothing on the screen said which of the plan price and the custom fee was
/// winning, or what saving would do to the bill already open. Two of the three
/// ways to change a member's fee are easy to make by accident: clearing the
/// field drops them to the plan price, and moving them to another plan does
/// nothing at all while an override is set.
///
/// The warning deliberately says **this month's bill**, not "future bills".
/// A cycle nobody has paid into is re-priced wherever it sits, the one the
/// member is standing in included — see `data/cycle_repricing.dart`. An owner
/// told only about future bills collects the old fee for the current month,
/// the leftover spills into a cycle opened early, and the member is in arrears
/// for ever. That sequence is the bug this whole area exists to have fixed.
class PricingSummary extends StatelessWidget {
  const PricingSummary({
    super.key,
    required this.planPriceMinor,
    this.customFeeMinor,
    this.billedNowMinor,
  });

  /// The price of the plan currently chosen in the form.
  final int planPriceMinor;

  /// The custom fee currently typed, or null when the field is blank.
  final int? customFeeMinor;

  /// What the member is billed today. Null for a member being created, who has
  /// no bill to move.
  final int? billedNowMinor;

  /// `member.customFee ?? plan.price` — the one rule, resolved here exactly as
  /// `repriceOpenCycles` resolves it, so the screen cannot promise a number
  /// the repository would not write.
  int get _effectiveFee => customFeeMinor ?? planPriceMinor;

  bool get _isChanging =>
      billedNowMinor != null && billedNowMinor != _effectiveFee;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: _isChanging ? palette.due : palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Billed each cycle: ${formatMinorUnits(_effectiveFee)}',
            style: text.titleSmall?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            customFeeMinor == null
                ? 'Follows the plan price of '
                    '${formatMinorUnits(planPriceMinor)}'
                : 'Custom fee, overriding the plan price of '
                    '${formatMinorUnits(planPriceMinor)}',
            style: text.bodySmall?.copyWith(color: palette.textMuted),
          ),
          if (_isChanging) ...[
            const SizedBox(height: 10),
            Text(
              'This month\'s bill and any later unpaid bill change from '
              '${formatMinorUnits(billedNowMinor!)} to '
              '${formatMinorUnits(_effectiveFee)} when you save.',
              style: text.bodySmall?.copyWith(
                color: palette.due,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Months already paid, or part-paid, keep the price that was '
              'charged at the time.',
              style: text.bodySmall?.copyWith(color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
