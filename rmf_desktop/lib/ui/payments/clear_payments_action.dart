import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/member_repository.dart';
import '../../data/payment_repository.dart';
import '../../domain/money.dart';
import '../../domain/payment_errors.dart';
import '../../services/payment_edit_service.dart';
import '../../theme/app_theme.dart';

/// Confirms, then deletes every payment a member has. Returns true if any went.
///
/// The single-payment button asks a yes/no question, because one row is a
/// mistake the owner can see and put back by hand. This one cannot be put back
/// at all: it removes the whole of a member's money and every receipt they were
/// ever issued. So it asks the owner to type the member's name, which is the
/// difference between meaning it and hitting Enter twice.
Future<bool> confirmAndClearPayments(
  BuildContext context, {
  required MemberRow member,
  required List<PaymentRow> payments,
}) async {
  if (payments.isEmpty) return false;

  final confirmed = await _confirm(context, member: member, payments: payments);
  if (!confirmed || !context.mounted) return false;

  final service = context.read<PaymentEditService>();
  final actorId = context.read<AuthBloc>().state.user!.id;
  final messenger = ScaffoldMessenger.of(context);

  final ClearPaymentsResult result;
  try {
    result = await service.deleteAllForMember(
      memberId: member.id,
      actorId: actorId,
    );
  } catch (error) {
    messenger.showSnackBar(SnackBar(
      content: Text(
          describeSaveError(error, whileDoing: 'clearing the payment history')),
    ));
    return false;
  }

  switch (result) {
    case AllPaymentsDeleted(:final memberName, :final deletedCount):
      messenger.showSnackBar(SnackBar(
        content: Text(result.hasOrphanedFiles
            // The database part worked. Saying otherwise would be a lie, and
            // the leftover files are recorded in the Logs screen.
            ? '$deletedCount payment${deletedCount == 1 ? '' : 's'} deleted '
                'for $memberName. Some receipt files could not be removed — '
                'see the Logs screen.'
            : '$deletedCount payment${deletedCount == 1 ? '' : 's'} deleted '
                'for $memberName. Their billing months read as due again.'),
      ));
      return true;
    case ClearPaymentsRefused(:final message):
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return false;
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required MemberRow member,
  required List<PaymentRow> payments,
}) async {
  final total =
      payments.fold(0, (sum, row) => sum + row.payment.amountMinor);
  final receipts =
      payments.where((row) => row.receipt != null).length;

  final answer = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ClearPaymentsConfirmDialog(
      memberName: member.member.fullName,
      count: payments.length,
      totalMinor: total,
      receiptCount: receipts,
    ),
  );

  return answer ?? false;
}

/// The question itself, kept free of repositories and blocs so the guard that
/// makes it safe — the owner having to type the name — can be tested on its
/// own, without standing up half the app behind it.
class ClearPaymentsConfirmDialog extends StatefulWidget {
  const ClearPaymentsConfirmDialog({
    super.key,
    required this.memberName,
    required this.count,
    required this.totalMinor,
    required this.receiptCount,
  });

  final String memberName;
  final int count;
  final int totalMinor;
  final int receiptCount;

  @override
  State<ClearPaymentsConfirmDialog> createState() =>
      _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ClearPaymentsConfirmDialog> {
  final _typed = TextEditingController();

  /// Case and stray spacing are not the point — meaning it is.
  bool get _nameMatches =>
      _typed.text.trim().toLowerCase() ==
      widget.memberName.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.memberName;

    return AlertDialog(
      backgroundColor: context.palette.surfaceRaised,
      title: const Text('Delete all payments?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This deletes every payment $name has ever made, and the '
              'receipts with them. It cannot be undone.',
              style: mutedStyleOf(context),
            ),
            const SizedBox(height: 14),
            _Detail(label: 'Payments', value: '${widget.count}'),
            _Detail(
                label: 'Total', value: formatMinorUnits(widget.totalMinor)),
            _Detail(label: 'Receipts', value: '${widget.receiptCount}'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.expiredBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Their billing months are kept and will read as due again, '
                'ready to be entered from the ledger. Take a backup first.',
                style: TextStyle(
                    color: context.palette.expired, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 16),
            Text('Type $name to confirm', style: mutedStyleOf(context)),
            const SizedBox(height: 6),
            TextField(
              controller: _typed,
              autofocus: true,
              decoration: const InputDecoration(isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep them'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.expired,
          ),
          onPressed:
              _nameMatches ? () => Navigator.of(context).pop(true) : null,
          child: Text('Delete ${widget.count} payments'),
        ),
      ],
    );
  }
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
