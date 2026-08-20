import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/payment_repository.dart';
import '../../domain/money.dart';
import '../../domain/payment_errors.dart';
import '../../services/payment_edit_service.dart';
import '../../theme/app_theme.dart';
import 'payment_history_table.dart';

/// Confirms, then deletes a payment. Returns true when one was deleted.
///
/// One implementation, called from wherever the payment table is shown, so the
/// wording and the guard rails cannot differ between the Payments screen and a
/// member's profile.
Future<bool> confirmAndDeletePayment(
  BuildContext context,
  PaymentRow row,
) async {
  final confirmed = await _confirm(context, row);
  if (!confirmed || !context.mounted) return false;

  // Captured before the await: the table row this was called from may well be
  // gone by the time it returns.
  final service = context.read<PaymentEditService>();
  final actorId = context.read<AuthBloc>().state.user!.id;
  final messenger = ScaffoldMessenger.of(context);

  final DeletePaymentResult result;
  try {
    result = await service.delete(paymentId: row.payment.id, actorId: actorId);
  } catch (error) {
    messenger.showSnackBar(SnackBar(
      content: Text(describeSaveError(error, whileDoing: 'deleting the payment')),
    ));
    return false;
  }

  switch (result) {
    case PaymentDeleted(:final memberName, :final periodLabel):
      messenger.showSnackBar(SnackBar(
        content: Text(result.hasOrphanedFiles
            // The database part worked. Saying otherwise would be a lie, and
            // the leftover files are recorded in the Logs screen.
            ? 'Payment deleted for $memberName. Its receipt files could not '
                'be removed — see the Logs screen.'
            : 'Payment deleted for $memberName ($periodLabel).'),
      ));
      return true;
    case PaymentDeleteRefused(:final message):
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return false;
  }
}

Future<bool> _confirm(BuildContext context, PaymentRow row) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dialogContext.palette.surfaceRaised,
      title: const Text('Delete this payment?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This removes the payment and its receipt for good. The billing '
            'period will read as due again.',
            style: mutedStyleOf(dialogContext),
          ),
          const SizedBox(height: 14),
          _Detail(label: 'Member', value: row.member.fullName),
          _Detail(
              label: 'Amount',
              value: formatMinorUnits(row.payment.amountMinor)),
          _Detail(label: 'Billing period', value: row.periodLabel),
          _Detail(
              label: 'Receipt',
              value: row.receipt?.receiptNumber ?? 'none (imported)'),
          _Detail(
              label: 'Recorded',
              value: formatShortDate(row.payment.paymentDate)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: dialogContext.palette.expired,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete payment'),
        ),
      ],
    ),
  );

  return answer ?? false;
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: mutedStyleOf(context)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}
