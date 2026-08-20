import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/edit_payment_bloc.dart';
import '../../data/payment_repository.dart';
import '../../domain/billing_month_check.dart';
import '../../domain/billing_period.dart';
import '../../domain/phone.dart';
import '../../services/billing_month_checker.dart';
import '../../services/payment_edit_service.dart';
import '../../services/record_payment_service.dart';
import '../../theme/app_theme.dart';
import 'billing_warnings_dialog.dart';
import 'payment_form_fields.dart';

/// Opens the Edit Payment flow. Resolves to true when something was saved, so
/// the list behind it can reload.
Future<bool?> showEditPaymentDialog(
  BuildContext context, {
  required PaymentRow row,
}) {
  final service = context.read<PaymentEditService>();
  final checker = context.read<BillingMonthChecker>();
  final userId = context.read<AuthBloc>().state.user!.id;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider(
      create: (_) => EditPaymentBloc(
        service: service,
        checker: checker,
        paymentId: row.payment.id,
        memberId: row.member.id,
        actorId: userId,
      ),
      child: _EditPaymentDialog(row: row),
    ),
  );
}

class _EditPaymentDialog extends StatefulWidget {
  const _EditPaymentDialog({required this.row});

  final PaymentRow row;

  @override
  State<_EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<_EditPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final PaymentFormController _form;

  bool _sendWhatsApp = false;
  bool _savedAnything = false;

  PaymentRow get _row => widget.row;

  /// An imported ledger payment has no receipt, and editing one deliberately
  /// does not create it: a 2024 cash row corrected today would otherwise take a
  /// number out of this year's receipt sequence.
  bool get _hasReceipt => _row.receipt != null;

  bool get _canSend => _hasReceipt && isValidPhone(_row.member.phone);

  @override
  void initState() {
    super.initState();
    final payment = _row.payment;
    final start = _row.periodStart;

    _form = PaymentFormController(
      // The month the payment already belongs to, not today's.
      billingMonth: start == null
          ? currentBillingMonth(payment.paymentDate)
          : '${start.year}-${start.month.toString().padLeft(2, '0')}',
      initialAmountMinor: payment.amountMinor,
      paymentDate: payment.paymentDate,
      method: payment.method,
      referenceNumber: payment.referenceNumber,
      notes: payment.notes,
    );
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    context.read<EditPaymentBloc>().add(EditPaymentSubmitted(
          amountMinor: _form.amountMinor,
          method: _form.method,
          paymentDate: _form.paymentDate,
          billingMonth: _form.billingMonth,
          sendWhatsApp: _sendWhatsApp,
          referenceNumber: _form.reference.text,
          notes: _form.notes.text,
        ));
  }

  Future<void> _askToConfirm(List<BillingMonthFinding> findings) async {
    final proceed = await confirmBillingWarnings(
      context,
      findings,
      continueLabel: 'Save anyway',
    );
    if (!mounted) return;

    final bloc = context.read<EditPaymentBloc>();
    bloc.add(proceed
        ? const EditPaymentConfirmed()
        : const EditPaymentConfirmationDismissed());
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<EditPaymentBloc, EditPaymentState>(
          listenWhen: (a, b) =>
              a.status != b.status && b.status == EditPaymentStatus.saved,
          listener: (context, state) => _savedAnything = true,
        ),
        BlocListener<EditPaymentBloc, EditPaymentState>(
          listenWhen: (a, b) =>
              a.status != b.status &&
              b.status == EditPaymentStatus.awaitingConfirmation,
          listener: (context, state) => _askToConfirm(state.findings),
        ),
      ],
      child: Dialog(
        backgroundColor: context.palette.surfaceRaised,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
          child: BlocBuilder<EditPaymentBloc, EditPaymentState>(
            builder: (context, state) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(context),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: state.status == EditPaymentStatus.saved
                        ? _SavedPanel(result: state.result!)
                        : _body(state),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edit Payment',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: context.palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _row.member.fullName,
                      _row.receipt?.receiptNumber ?? 'no receipt',
                    ].join(' · '),
                    style: mutedStyleOf(context),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(context).pop(_savedAnything),
            ),
          ],
        ),
      );

  Widget _body(EditPaymentState state) {
    final busy = state.busy;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaymentFormFields(
            controller: _form,
            planDurationMonths: _row.planDurationMonths,
            enabled: !busy,
          ),
          if (state.findings.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Banner(
              messages: state.findings.map((f) => f.message).toList(),
              tone: _BannerTone.error,
            ),
          ],
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: context.palette.surfaceBase,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.border),
            ),
            child: CheckboxListTile(
              value: _sendWhatsApp && _canSend,
              onChanged: _canSend && !busy
                  ? (v) => setState(() => _sendWhatsApp = v ?? false)
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: context.palette.accent,
              dense: true,
              title: Text('Send corrected receipt',
                  style: TextStyle(
                      fontSize: 13, color: context.palette.textPrimary)),
              subtitle: Text(
                switch ((_hasReceipt, _canSend)) {
                  (false, _) =>
                    'Unavailable — imported ledger payments have no receipt',
                  (true, false) =>
                    'Disabled — this member has no valid WhatsApp number',
                  _ => 'Sends the corrected receipt to ${_row.member.phone}',
                },
                style: mutedStyleOf(context),
              ),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _Banner(messages: [state.error!], tone: _BannerTone.error),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : _save,
            child: Text(busy ? 'Saving…' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}

/// What actually happened, once the correction is committed.
class _SavedPanel extends StatelessWidget {
  const _SavedPanel({required this.result});

  final PaymentEdited result;

  @override
  Widget build(BuildContext context) {
    if (result.changedNothing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nothing was changed',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.palette.textPrimary)),
          const SizedBox(height: 6),
          Text('The payment is exactly as it was, so nothing was saved.',
              style: mutedStyleOf(context)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final receipt = result.receipt;
    final whatsApp = result.whatsApp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.palette.paidBg.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: context.palette.paid.withValues(alpha: .3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment corrected',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary)),
              if (result.receiptNumber != null) ...[
                const SizedBox(height: 4),
                Text('Receipt: ${result.receiptNumber} (unchanged)',
                    style: mutedStyleOf(context)),
              ],
              const SizedBox(height: 14),
              for (final change in result.changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(change,
                      style: TextStyle(
                          fontSize: 13, color: context.palette.textPrimary)),
                ),
              const SizedBox(height: 10),
              switch (receipt) {
                ReceiptRewritten() =>
                  const _Step(ok: true, label: 'Receipt regenerated'),
                ReceiptNotApplicable() => const _Step(
                    ok: null, label: 'No receipt for this payment'),
                ReceiptRewriteFailed(:final message) =>
                  _Step(ok: false, label: message),
              },
              switch (whatsApp) {
                WhatsAppNotRequested() =>
                  const _Step(ok: null, label: 'Corrected receipt not sent'),
                WhatsAppSent() =>
                  const _Step(ok: true, label: 'Corrected receipt sent'),
                WhatsAppFailed(:final error) =>
                  _Step(ok: false, label: 'WhatsApp — $error'),
              },
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.ok, required this.label});

  /// Null for "did not apply", which is not a failure.
  final bool? ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (ok) {
      true => (Icons.check_circle, context.palette.paid),
      false => (Icons.error_outline, context.palette.expired),
      null => (Icons.remove_circle_outline, context.palette.textMuted),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 8),
            child: Icon(icon, size: 15, color: color),
          ),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: context.palette.textSecondary)),
          ),
        ],
      ),
    );
  }
}

enum _BannerTone { error }

class _Banner extends StatelessWidget {
  const _Banner({required this.messages, required this.tone});

  final List<String> messages;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _BannerTone.error => (context.palette.expiredBg, context.palette.expired),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final message in messages)
            Text(message, style: TextStyle(color: fg, fontSize: 13)),
        ],
      ),
    );
  }
}
