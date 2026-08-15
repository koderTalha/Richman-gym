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

/// For a real moment in time — when a payment was taken — shown on the gym's
/// own clock.
String formatShortDate(DateTime? date) =>
    date == null ? '—' : _format(date.toLocal());

/// For dates the app anchors to UTC midnight on purpose: joining dates and
/// cycle boundaries. Reading those on the local clock lands on the day before
/// in any negative-offset timezone.
String formatCalendarDate(DateTime? date) =>
    date == null ? '—' : _format(date.toUtc());

String _format(DateTime at) =>
    '${at.day.toString().padLeft(2, '0')} '
    '${_monthAbbr[at.month - 1]} ${at.year}';

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
          border: Border.all(color: context.palette.border, style: BorderStyle.solid),
        ),
        alignment: Alignment.center,
        child: Text(emptyMessage, style: mutedStyleOf(context)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.palette.border)),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('RECEIPT', style: labelStyleOf(context))),
                if (showMember)
                  Expanded(flex: 3, child: Text('MEMBER', style: labelStyleOf(context))),
                Expanded(flex: 2, child: Text('PERIOD', style: labelStyleOf(context))),
                Expanded(flex: 2, child: Text('AMOUNT', style: labelStyleOf(context))),
                Expanded(flex: 2, child: Text('METHOD', style: labelStyleOf(context))),
                Expanded(flex: 2, child: Text('DATE', style: labelStyleOf(context))),
                SizedBox(width: 100, child: Text('WHATSAPP', style: labelStyleOf(context))),
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
                              ? context.palette.textHint
                              : context.palette.accentText,
                        ),
                      ),
                    ),
                    if (showMember)
                      Expanded(
                        flex: 3,
                        child: Text(
                          row.member.fullName,
                          style: TextStyle(
                              fontSize: 13, color: context.palette.textPrimary),
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: Text(row.periodLabel,
                          style: TextStyle(
                              fontSize: 13, color: context.palette.textSecondary)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatMinorUnits(row.payment.amountMinor),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: context.palette.textPrimary),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(paymentMethodLabel(row.payment.method),
                          style: mutedStyleOf(context)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(formatShortDate(row.payment.paymentDate),
                          style: mutedStyleOf(context)),
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
