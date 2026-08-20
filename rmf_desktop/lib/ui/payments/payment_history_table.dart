import 'package:flutter/material.dart';

import '../../data/payment_repository.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/payment_method.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'delete_payment_action.dart';
import 'edit_payment_dialog.dart';

export '../../domain/payment_method.dart' show paymentMethodLabel;

/// For a real moment in time — when a payment was taken — shown on the gym's
/// own clock.
String formatShortDate(DateTime? date) =>
    date == null ? '—' : formatDayMonthYear(date.toLocal());

/// For dates the app anchors to UTC midnight on purpose: joining dates and
/// cycle boundaries. Reading those on the local clock lands on the day before
/// in any negative-offset timezone.
String formatCalendarDate(DateTime? date) =>
    date == null ? '—' : formatDayMonthYear(date.toUtc());



/// Shared payment history table — used both on a member's profile and on the
/// all-payments screen, which only differ by whether the member column shows.
class PaymentHistoryTable extends StatelessWidget {
  const PaymentHistoryTable({
    super.key,
    required this.rows,
    this.showMember = true,
    this.emptyMessage = 'No payments recorded yet.',
    this.onMutated,
  });

  final List<PaymentRow> rows;
  final bool showMember;
  final String emptyMessage;

  /// Called after a row was edited or deleted, so the screen showing this
  /// table can reload. Passing it in is what turns the actions column on: a
  /// table nobody can refresh must not offer actions that would leave it
  /// showing a payment that no longer exists.
  final VoidCallback? onMutated;

  bool get _showActions => onMutated != null;

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
                if (_showActions) const SizedBox(width: 40),
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
                    if (_showActions)
                      SizedBox(
                        width: 40,
                        child: _RowActions(
                          row: row,
                          onMutated: onMutated!,
                        ),
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

/// Edit and Delete for one payment.
///
/// Lives with the table rather than with each screen, so a payment behaves the
/// same way whether it is being looked at on the Payments screen or on the
/// member's own profile.
class _RowActions extends StatelessWidget {
  const _RowActions({required this.row, required this.onMutated});

  final PaymentRow row;
  final VoidCallback onMutated;

  Future<void> _edit(BuildContext context) async {
    final saved = await showEditPaymentDialog(context, row: row);
    if (saved == true) onMutated();
  }

  Future<void> _delete(BuildContext context) async {
    if (await confirmAndDeletePayment(context, row)) onMutated();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_RowAction>(
      tooltip: 'Payment actions',
      icon: Icon(Icons.more_horiz, size: 18, color: context.palette.textMuted),
      padding: EdgeInsets.zero,
      onSelected: (action) => switch (action) {
        _RowAction.edit => _edit(context),
        _RowAction.delete => _delete(context),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _RowAction.edit,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 10),
              Text('Edit payment'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _RowAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline,
                  size: 16, color: context.palette.expired),
              const SizedBox(width: 10),
              Text('Delete payment',
                  style: TextStyle(color: context.palette.expired)),
            ],
          ),
        ),
      ],
    );
  }
}

enum _RowAction { edit, delete }
