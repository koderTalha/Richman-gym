import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/record_payment_bloc.dart';
import '../../data/member_repository.dart';
import '../../domain/billing_month_check.dart';
import '../../domain/billing_period.dart';
import '../../domain/phone.dart';
import '../../services/receipt_storage.dart';
import '../../services/billing_month_checker.dart';
import '../../services/record_payment_service.dart';
import '../../theme/app_theme.dart';
import 'billing_warnings_dialog.dart';
import 'payment_form_fields.dart';

/// Opens the Record Payment flow. Resolves to true if a payment was recorded,
/// so the caller can refresh.
Future<bool?> showRecordPaymentDialog(
  BuildContext context, {
  required MemberRow member,
}) {
  final service = context.read<RecordPaymentService>();
  final checker = context.read<BillingMonthChecker>();
  final userId = context.read<AuthBloc>().state.user!.id;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider(
      create: (_) => RecordPaymentBloc(
        service: service,
        checker: checker,
        memberId: member.id,
        memberName: member.member.fullName,
        memberPhone: member.member.phone,
        recordedById: userId,
      ),
      child: _RecordPaymentDialog(member: member),
    ),
  );
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.member});

  final MemberRow member;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final PaymentFormController _form;

  late bool _sendWhatsApp;
  bool _recordedAnything = false;

  bool get _phoneUsable => isValidPhone(widget.member.member.phone);

  /// Drives the billing-period label, so a quarterly member does not read as
  /// paying for a single month.
  int get _planDuration => widget.member.plan?.durationMonths ?? 1;

  @override
  void initState() {
    super.initState();
    _form = PaymentFormController(
      billingMonth: currentBillingMonth(),
      initialAmountMinor: widget.member.feeMinor,
    );
    _sendWhatsApp = _phoneUsable;
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    // The billing-month rules run in the bloc, which is what lets Record and
    // Edit Payment share one implementation of them.
    context.read<RecordPaymentBloc>().add(
          RecordPaymentSubmitted(
            amountMinor: _form.amountMinor,
            method: _form.method,
            paymentDate: _form.paymentDate,
            billingMonth: _form.billingMonth,
            sendWhatsApp: _sendWhatsApp,
            referenceNumber: _form.reference.text,
            notes: _form.notes.text,
          ),
        );
  }

  /// Shows the one warnings dialog and hands the answer back to the bloc.
  Future<void> _askToConfirm(List<BillingMonthFinding> findings) async {
    final proceed = await confirmBillingWarnings(
      context,
      findings,
      continueLabel: 'Record anyway',
    );
    if (!mounted) return;

    final bloc = context.read<RecordPaymentBloc>();
    bloc.add(proceed
        ? const RecordPaymentConfirmed()
        : const RecordPaymentConfirmationDismissed());
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<RecordPaymentBloc, RecordPaymentState>(
          listenWhen: (a, b) =>
              a.status != b.status && b.status == RecordPaymentStatus.success,
          listener: (context, state) => _recordedAnything = true,
        ),
        BlocListener<RecordPaymentBloc, RecordPaymentState>(
          listenWhen: (a, b) =>
              a.status != b.status &&
              b.status == RecordPaymentStatus.awaitingConfirmation,
          listener: (context, state) => _askToConfirm(state.findings),
        ),
      ],
      child: Dialog(
        backgroundColor: context.palette.surfaceRaised,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
          child: BlocBuilder<RecordPaymentBloc, RecordPaymentState>(
            builder: (context, state) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(context, state),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: state.status == RecordPaymentStatus.success
                          ? _SuccessPanel(
                              state: state,
                              memberName: widget.member.member.fullName,
                            )
                          : _formBody(state),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, RecordPaymentState state) => Container(
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
                  Text('Record Payment',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: context.palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.member.member.fullName} · '
                    '${widget.member.member.phone}',
                    style: mutedStyleOf(context),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(context).pop(_recordedAnything),
            ),
          ],
        ),
      );

  Widget _formBody(RecordPaymentState state) {
    final busy = state.busy;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaymentFormFields(
            controller: _form,
            planDurationMonths: _planDuration,
            enabled: !busy,
          ),
          if (state.findings.isNotEmpty) ...[
            const SizedBox(height: 14),
            _BlockedBanner(findings: state.findings),
          ],
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: context.palette.surfaceBase,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.border),
            ),
            child: CheckboxListTile(
              value: _sendWhatsApp,
              onChanged: _phoneUsable && !state.busy
                  ? (v) => setState(() => _sendWhatsApp = v ?? false)
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: context.palette.accent,
              dense: true,
              title: Text('Send receipt on WhatsApp',
                  style: TextStyle(fontSize: 13, color: context.palette.textPrimary)),
              subtitle: Text(
                _phoneUsable
                    ? 'Sends the receipt image to ${widget.member.member.phone}'
                    : 'Disabled — this member has no valid WhatsApp number',
                style: mutedStyleOf(context),
              ),
            ),
          ),
          if (state.status == RecordPaymentStatus.failed) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.expiredBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(state.error ?? 'Could not record the payment.',
                  style: TextStyle(
                      color: context.palette.expired, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: Text(busy ? 'Recording…' : 'Confirm Payment'),
          ),
        ],
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel({required this.state, required this.memberName});

  final RecordPaymentState state;
  final String memberName;

  @override
  Widget build(BuildContext context) {
    final result = state.result!;
    final whatsApp = result.whatsApp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.palette.paidBg.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.paid.withValues(alpha: .3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment recorded successfully',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary)),
              const SizedBox(height: 4),
              Text('Receipt: ${result.receiptNumber}', style: mutedStyleOf(context)),
              const SizedBox(height: 14),
              const _Step(ok: true, label: 'Payment saved'),
              const _Step(ok: true, label: 'Receipt generated'),
              switch (whatsApp) {
                WhatsAppNotRequested() =>
                  const _Step(ok: null, label: 'WhatsApp not requested'),
                WhatsAppSent() =>
                  const _Step(ok: true, label: 'WhatsApp sent'),
                WhatsAppFailed(:final error) =>
                  _Step(ok: false, label: 'WhatsApp failed — $error'),
              },
              if (whatsApp is WhatsAppFailed) ...[
                const SizedBox(height: 12),
                Text(
                  'The payment and receipt are saved. You can retry the '
                  'WhatsApp send now or from the Receipts screen.',
                  style: mutedStyleOf(context),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: state.retrying
                      ? null
                      : () => context
                          .read<RecordPaymentBloc>()
                          .add(const RecordPaymentRetryWhatsApp()),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(state.retrying ? 'Retrying…' : 'Retry WhatsApp'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openReceipt(context, result.receiptNumber),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('View Receipt'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _printReceipt(context, result.receiptNumber),
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Print / Save PDF'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Done'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => context
                    .read<RecordPaymentBloc>()
                    .add(const RecordPaymentReset()),
                child: const Text('Record Another'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openReceipt(BuildContext context, String receiptNumber) async {
    final storage = context.read<ReceiptStorage>();
    final bytes = await storage.read('$receiptNumber.png');
    if (bytes == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }

  Future<void> _printReceipt(BuildContext context, String receiptNumber) async {
    final storage = context.read<ReceiptStorage>();
    final bytes = await storage.read('$receiptNumber.pdf');
    if (bytes == null) return;

    // Gives the owner the OS print dialog, which also offers "Save as PDF".
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: receiptNumber,
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.ok, required this.label});

  /// null means "not attempted".
  final bool? ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (mark, color) = switch (ok) {
      null => ('—', context.palette.textMuted),
      true => ('✓', context.palette.paid),
      false => ('✕', context.palette.expired),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mark, style: TextStyle(color: color, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Billing months that cannot be right, shown on the form rather than as a
/// dialog: there is nothing to confirm, only something to correct.
class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner({required this.findings});

  final List<BillingMonthFinding> findings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.expiredBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final finding in findings)
            Text(finding.message,
                style: TextStyle(color: context.palette.expired, fontSize: 13)),
        ],
      ),
    );
  }
}
