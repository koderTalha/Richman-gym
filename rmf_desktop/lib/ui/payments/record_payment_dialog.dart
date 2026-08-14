import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../bloc/auth_bloc.dart';
import '../../bloc/record_payment_bloc.dart';
import '../../data/database.dart';
import '../../data/member_repository.dart';
import '../../domain/billing_period.dart';
import '../../domain/money.dart';
import '../../domain/phone.dart';
import '../../services/receipt_storage.dart';
import '../../services/record_payment_service.dart';
import '../../theme/app_theme.dart';
import 'payment_history_table.dart';

/// Opens the Record Payment flow. Resolves to true if a payment was recorded,
/// so the caller can refresh.
Future<bool?> showRecordPaymentDialog(
  BuildContext context, {
  required MemberRow member,
}) {
  final service = context.read<RecordPaymentService>();
  final userId = context.read<AuthBloc>().state.user!.id;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider(
      create: (_) => RecordPaymentBloc(
        service: service,
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
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  PaymentMethod _method = PaymentMethod.cash;
  DateTime _paymentDate = DateTime.now();
  late String _billingMonth;
  late bool _sendWhatsApp;
  bool _recordedAnything = false;

  bool get _phoneUsable => isValidPhone(widget.member.member.phone);

  @override
  void initState() {
    super.initState();
    _billingMonth = currentBillingMonth();
    _sendWhatsApp = _phoneUsable;
    final fee = widget.member.feeMinor;
    if (fee != null) _amount.text = fromMinorUnits(fee).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Warn before billing a month that already has a payment: legitimate
    // occasionally, a costly mistake more often.
    final existing = await context
        .read<RecordPaymentService>()
        .existingPaymentForPeriod(
          memberId: widget.member.id,
          billingMonth: _billingMonth,
        );

    if (existing != null && mounted) {
      final periodLabel =
          formatBillingPeriod(parseBillingMonth(_billingMonth), 1);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: context.palette.surfaceRaised,
          title: const Text('Already paid'),
          content: Text(
            '$periodLabel is already recorded as paid — '
            '${formatMinorUnits(existing.amountMinor)} on '
            '${formatShortDate(existing.paymentDate)}.\n\n'
            'Record another payment for the same month?',
            style: mutedStyleOf(context),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Record anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;

    context.read<RecordPaymentBloc>().add(
          RecordPaymentSubmitted(
            amountMinor: toMinorUnits(double.parse(_amount.text.trim())),
            method: _method,
            paymentDate: _paymentDate,
            billingMonth: _billingMonth,
            sendWhatsApp: _sendWhatsApp,
            referenceNumber: _reference.text,
            notes: _notes.text,
          ),
        );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _pickBillingMonth() async {
    final parts = _billingMonth.split('-');
    final initial = DateTime(int.parse(parts[0]), int.parse(parts[1]));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select any day in the billing month',
    );
    if (picked != null) {
      setState(() => _billingMonth =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RecordPaymentBloc, RecordPaymentState>(
      listenWhen: (a, b) =>
          a.status != b.status && b.status == RecordPaymentStatus.success,
      listener: (context, state) => _recordedAnything = true,
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
                          : _form(state),
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

  Widget _form(RecordPaymentState state) {
    final submitting = state.status == RecordPaymentStatus.submitting;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(
                      labelText: 'Amount (PKR) *', isDense: true),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  validator: (v) {
                    final parsed = double.tryParse((v ?? '').trim());
                    if (parsed == null || parsed <= 0) {
                      return 'Enter an amount greater than zero';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<PaymentMethod>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                      labelText: 'Payment method', isDense: true),
                  items: PaymentMethod.values
                      .map((m) => DropdownMenuItem(
                          value: m, child: Text(paymentMethodLabel(m))))
                      .toList(),
                  onChanged: (v) => setState(() => _method = v ?? _method),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Payment date', isDense: true),
                    child: Text(formatShortDate(_paymentDate),
                        style: TextStyle(
                            fontSize: 14, color: context.palette.textPrimary)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: InkWell(
                  onTap: _pickBillingMonth,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Billing period', isDense: true),
                    child: Text(
                      formatBillingPeriod(parseBillingMonth(_billingMonth), 1),
                      style: TextStyle(
                          fontSize: 14, color: context.palette.textPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Transaction / reference no. (optional)',
              hintText: 'e.g. 114828',
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _notes,
            decoration: const InputDecoration(
                labelText: 'Notes (optional)', isDense: true),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: context.palette.surfaceBase,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.border),
            ),
            child: CheckboxListTile(
              value: _sendWhatsApp,
              onChanged: _phoneUsable
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
            onPressed: submitting ? null : _submit,
            child: Text(submitting ? 'Recording…' : 'Confirm Payment'),
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
