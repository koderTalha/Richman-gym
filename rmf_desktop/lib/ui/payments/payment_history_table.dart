import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/payment_repository.dart';
import '../../domain/money.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_badge.dart';

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatShortDate(DateTime? date) {
  if (date == null) return '—';
  return '${date.day.toString().padLeft(2, '0')} '
      '${_monthAbbr[date.month - 1]} ${date.year}';
}

String paymentMethodLabel(PaymentMethod method) => switch (method) {
      PaymentMethod.cash => 'Cash',
      PaymentMethod.bankTransfer => 'Bank Transfer',
      PaymentMethod.easypaisa => 'Easypaisa',
      PaymentMethod.jazzcash => 'JazzCash',
      PaymentMethod.card => 'Card',
      PaymentMethod.other => 'Other',
    };

/// Shared payment history table — used both on a member's profile and on the
/// all-payments screen, which only differ by whether the member column shows.
class PaymentHistoryTable extends StatelessWidget {
  const PaymentHistoryTable({
    super.key,
    required this.rows,
    this.showMember = true,
    this.emptyMessage = 'No payments recorded yet.',
  });

  final List<PaymentRow> rows;
  final bool showMember;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ink800, style: BorderStyle.solid),
        ),
        alignment: Alignment.center,
        child: Text(emptyMessage, style: kMutedStyle),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink800),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.ink800)),
            ),
            child: Row(
              children: [
                const Expanded(flex: 2, child: Text('RECEIPT', style: kLabelStyle)),
                if (showMember)
                  const Expanded(flex: 3, child: Text('MEMBER', style: kLabelStyle)),
                const Expanded(flex: 2, child: Text('PERIOD', style: kLabelStyle)),
                const Expanded(flex: 2, child: Text('AMOUNT', style: kLabelStyle)),
                const Expanded(flex: 2, child: Text('METHOD', style: kLabelStyle)),
                const Expanded(flex: 2, child: Text('DATE', style: kLabelStyle)),
                const SizedBox(width: 100, child: Text('WHATSAPP', style: kLabelStyle)),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final row = rows[i];
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        row.receipt?.receiptNumber ?? '—',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: row.receipt == null
                              ? AppColors.ink600
                              : AppColors.crimson400,
                        ),
                      ),
                    ),
                    if (showMember)
                      Expanded(
                        flex: 3,
                        child: Text(
                          row.member.fullName,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.ink50),
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: Text(row.periodLabel,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.ink200)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatMinorUnits(row.payment.amountMinor),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.ink50),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(paymentMethodLabel(row.payment.method),
                          style: kMutedStyle),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(formatShortDate(row.payment.paymentDate),
                          style: kMutedStyle),
                    ),
                    SizedBox(
                      width: 100,
                      child: WhatsAppStatusBadge(status: row.whatsAppStatus),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
