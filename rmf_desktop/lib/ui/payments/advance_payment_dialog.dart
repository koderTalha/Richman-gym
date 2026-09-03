import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/database.dart';
import '../../data/member_repository.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/payment_errors.dart';
import '../../domain/payment_method.dart';
import '../../domain/payment_settlement.dart' show allocate;
import '../../domain/payment_timing.dart';
import '../../domain/phone.dart';
import '../../services/billing_cycle_service.dart';
import '../../services/receipt_storage.dart';
import '../../services/record_payment_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'payment_history_table.dart' show formatShortDate;

/// The one dialog for taking a member's money.
///
/// There is no billing month to pick: the owner types an amount and the date
/// it was handed over, and the app works out which of the member's own cycles
/// it settles, arrears first, opening as many ahead as the money reaches.
///
/// The payment date and the billing cycle are deliberately independent. A
/// member who pays on the 29th for a cycle due on the 6th settles that cycle
/// at its own dates; the next one still falls due where it always would. See
/// `RecordPaymentService.recordAdvancePayment` and `domain/billing_cycle.dart`.
///
/// Resolves to true if a payment was recorded, so the caller can refresh.
Future<bool?> showAdvancePaymentDialog(
  BuildContext context, {
  required MemberRow member,
}) {
  final service = context.read<RecordPaymentService>();
  final cycles = context.read<BillingCycleService>();
  final userId = context.read<AuthBloc>().state.user!.id;

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AdvancePaymentDialog(
      member: member,
      service: service,
      cycles: cycles,
      recordedById: userId,
    ),
  );
}

class _AdvancePaymentDialog extends StatefulWidget {
  const _AdvancePaymentDialog({
    required this.member,
    required this.service,
    required this.cycles,
    required this.recordedById,
  });

  final MemberRow member;
  final RecordPaymentService service;
  final BillingCycleService cycles;
  final int recordedById;

  @override
  State<_AdvancePaymentDialog> createState() => _AdvancePaymentDialogState();
}

class _AdvancePaymentDialogState extends State<_AdvancePaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  /// Reassigned by [_recordAnother]: one key belongs to one saved payment.
  late String _idempotencyKey;

  DateTime _paymentDate = DateTime.now();
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;
  bool _retrying = false;
  String? _error;

  /// Sticky within one submission, so fixing a validation error after
  /// confirming does not ask the same question twice. Cleared by
  /// [_recordAnother], because the answer belonged to that amount.
  bool _confirmedAdvance = false;
  RecordPaymentResult? _result;
  MemberBilling? _billing;
  late bool _sendWhatsApp;

  bool get _phoneUsable => isValidPhone(widget.member.member.phone);

  @override
  void initState() {
    super.initState();
    _idempotencyKey = _newKey();
    _amount = TextEditingController(
      text: widget.member.feeMinor == null
          ? ''
          : fromMinorUnits(widget.member.feeMinor!).toStringAsFixed(0),
    );
    _sendWhatsApp = _phoneUsable;
    _loadBilling();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadBilling() async {
    final billing = await widget.cycles.forMember(widget.member.id);
    if (mounted) setState(() => _billing = billing);
  }

  Future<void> _pickDate() async {
    // Bounded by the period the money buys, not by today. A member paying on
    // the 3rd for a cycle that starts on the 8th should get a receipt the
    // owner can date the 8th — see `latestPaymentDate`.
    final bound = latestPaymentDate(
      coveredEnd: _coveredEnd,
      today: DateTime.now(),
    );
    // Back to a local calendar day: the picker works in local time, and
    // handing it a UTC midnight mixes two clocks in one comparison.
    final lastDate = DateTime(bound.year, bound.month, bound.day);

    // Reducing the amount after choosing a date can pull the bound back
    // behind it, and showDatePicker asserts rather than clamping.
    final initialDate =
        _paymentDate.isAfter(lastDate) ? lastDate : _paymentDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: lastDate,
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  /// The exclusive end of the span the amount currently typed would settle, or
  /// null when there is not yet enough to say.
  ///
  /// Falls back to one cycle's fee before the owner has typed anything, so
  /// opening the picker first still offers the current cycle's own dates
  /// rather than only today.
  DateTime? get _coveredEnd {
    final billing = _billing;
    if (billing == null) return null;

    final parsed = double.tryParse(_amount.text.trim());
    final amountMinor = (parsed == null || parsed <= 0)
        ? billing.feeMinor
        : toMinorUnits(parsed);
    if (amountMinor <= 0) return null;

    final offered =
        widget.cycles.settleableFor(billing: billing, amountMinor: amountMinor);
    return allocate(amountMinor: amountMinor, cycles: offered).coveredSpan?.end;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await _record(confirmedAdvance: _confirmedAdvance);
      if (!mounted) return;
      setState(() => _result = result);
    } on AdvanceConfirmationRequired catch (question) {
      // Not a failure: the payment reaches further ahead than this records
      // unasked. Nothing has been written, so the answer simply decides
      // whether the same submission runs again.
      if (!mounted) return;
      setState(() => _busy = false);

      final confirmed = await _askToConfirmAdvance(question);
      if (!mounted || !confirmed) return;

      setState(() {
        _busy = true;
        _confirmedAdvance = true;
      });

      try {
        final result = await _record(confirmedAdvance: true);
        if (!mounted) return;
        setState(() => _result = result);
      } catch (error, stack) {
        if (!mounted) return;
        setState(() => _error = describeSaveError(error,
            stack: stack, whileDoing: 'recording the payment'));
      }
    } catch (error, stack) {
      if (!mounted) return;
      setState(() =>
          _error = describeSaveError(error, stack: stack, whileDoing: 'recording the payment'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The submission itself. The idempotency key is deliberately unchanged
  /// between the unconfirmed attempt and the confirmed one: they are the same
  /// payment, and a second key would let a double answer record it twice.
  Future<RecordPaymentResult> _record({required bool confirmedAdvance}) =>
      widget.service.recordAdvancePayment(
        AdvancePaymentInput(
          memberId: widget.member.id,
          amountMinor: toMinorUnits(double.parse(_amount.text.trim())),
          method: _method,
          paymentDate: _paymentDate,
          sendWhatsApp: _sendWhatsApp,
          recordedById: widget.recordedById,
          idempotencyKey: _idempotencyKey,
          confirmedAdvance: confirmedAdvance,
        ),
      );

  /// Asks before booking several cycles at once.
  ///
  /// The question names the number of cycles and the date cover runs to,
  /// because that is what tells a deliberate year upfront apart from an extra
  /// zero in the amount.
  Future<bool> _askToConfirmAdvance(AdvanceConfirmationRequired question) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record several cycles at once?'),
        content: Text(question.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Record ${question.futureCyclesCovered + 1} cycles'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// Sends the receipt again for a payment that is already saved.
  ///
  /// The money and the receipt are never at stake here — only the message —
  /// so this replaces the outcome on screen and touches nothing else.
  Future<void> _retryWhatsApp() async {
    final result = _result;
    if (result == null) return;

    setState(() => _retrying = true);
    final outcome = await widget.service.resend(result.receiptId);
    if (!mounted) return;

    setState(() {
      _retrying = false;
      _result = RecordPaymentResult(
        paymentId: result.paymentId,
        receiptId: result.receiptId,
        receiptNumber: result.receiptNumber,
        whatsApp: outcome,
        timing: result.timing,
      );
    });
  }

  /// Back to an empty form for the next member in the queue, with a new
  /// idempotency key: the one just used is now spoken for by a saved payment.
  void _recordAnother() {
    setState(() {
      _result = null;
      _error = null;
      _idempotencyKey = _newKey();
      // A fresh payment must ask again. The answer belonged to the amount the
      // owner had just confirmed, not to the dialog being open.
      _confirmedAdvance = false;
      _paymentDate = DateTime.now();
      _sendWhatsApp = _phoneUsable;
      _amount.text = widget.member.feeMinor == null
          ? ''
          : fromMinorUnits(widget.member.feeMinor!).toStringAsFixed(0);
    });
    _loadBilling();
  }

  Future<void> _openReceipt(String receiptNumber) async {
    final storage = context.read<ReceiptStorage>();
    final bytes = await storage.read('$receiptNumber.png');
    if (bytes == null || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(child: Image.memory(bytes)),
      ),
    );
  }

  Future<void> _printReceipt(String receiptNumber) async {
    final storage = context.read<ReceiptStorage>();
    final bytes = await storage.read('$receiptNumber.pdf');
    if (bytes == null) return;

    // Gives the owner the OS print dialog, which also offers "Save as PDF".
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: receiptNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.palette.surfaceRaised,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _result != null ? _successBody(context) : _formBody(),
              ),
            ),
          ],
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
                  Text('Record Payment',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: context.palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(widget.member.member.fullName, style: mutedStyleOf(context)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(context).pop(_result != null),
            ),
          ],
        ),
      );

  Widget _formBody() {
    final billing = _billing;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (billing != null) _WhatThisSettles(billing: billing),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amount,
            enabled: !_busy,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Amount received *', isDense: true),
            keyboardType: TextInputType.number,
            validator: (v) {
              final parsed = double.tryParse((v ?? '').trim());
              if (parsed == null || parsed <= 0) {
                return 'Enter an amount greater than zero';
              }
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _busy ? null : _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Payment date', isDense: true),
                    child: Text(formatShortDate(_paymentDate)),
                  ),
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
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _method = v ?? _method),
                ),
              ),
            ],
          ),
          if (billing != null) ...[
            const SizedBox(height: 14),
            _AllocationPreview(
              cycles: widget.cycles,
              billing: billing,
              amountText: _amount.text,
            ),
          ],
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: context.palette.surfaceBase,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.border),
            ),
            child: CheckboxListTile(
              value: _sendWhatsApp,
              onChanged: _phoneUsable && !_busy
                  ? (v) => setState(() => _sendWhatsApp = v ?? false)
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: context.palette.accent,
              dense: true,
              title: Text('Send receipt on WhatsApp',
                  style: TextStyle(
                      fontSize: 13, color: context.palette.textPrimary)),
              subtitle: Text(
                _phoneUsable
                    ? 'Sends the receipt image to '
                        '${widget.member.member.phone}'
                    : 'Disabled — this member has no valid WhatsApp number',
                style: mutedStyleOf(context),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.expiredBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style: TextStyle(color: context.palette.expired, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Recording…' : 'Confirm Payment'),
          ),
        ],
      ),
    );
  }

  Widget _successBody(BuildContext context) {
    final result = _result!;
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
              Text('Payment recorded',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Receipt: ${result.receiptNumber}',
                      style: mutedStyleOf(context)),
                  if (result.timing.isNoteworthy) ...[
                    const SizedBox(width: 8),
                    PaymentTimingBadge(timing: result.timing),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              const _Step(ok: true, label: 'Payment saved'),
              const _Step(ok: true, label: 'Receipt generated'),
              switch (whatsApp) {
                WhatsAppNotRequested() =>
                  const _Step(ok: null, label: 'WhatsApp not requested'),
                WhatsAppSent() => const _Step(ok: true, label: 'WhatsApp sent'),
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
                  onPressed: _retrying ? null : _retryWhatsApp,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(_retrying ? 'Retrying…' : 'Retry WhatsApp'),
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
                onPressed: () => _openReceipt(result.receiptNumber),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('View Receipt'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _printReceipt(result.receiptNumber),
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
                onPressed: _recordAnother,
                child: const Text('Record Another'),
              ),
            ),
          ],
        ),
      ],
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
            child: Text(label, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Where the money is about to go, read before a single digit is typed.
class _WhatThisSettles extends StatelessWidget {
  const _WhatThisSettles({required this.billing});

  final MemberBilling billing;

  @override
  Widget build(BuildContext context) {
    final unsettled = billing.nextUnsettled;
    final overdue = billing.isOverdueAt(DateTime.now().toUtc());

    final label = unsettled == null
        ? 'Next due: ${formatDayMonthYear(billing.nextDueDate)}'
        : (overdue
            ? 'Overdue since ${formatDayMonthYear(unsettled.start)}'
            : 'Due ${formatDayMonthYear(unsettled.start)}');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surfaceBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Icon(
            overdue ? Icons.warning_amber_outlined : Icons.info_outline,
            size: 16,
            color: overdue ? context.palette.expired : context.palette.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13, color: context.palette.textPrimary)),
          ),
          if (billing.outstandingMinor > 0)
            Text(formatMinorUnits(billing.outstandingMinor),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textPrimary)),
        ],
      ),
    );
  }
}

/// A live preview of which cycles this amount would settle, updated as the
/// owner types — so a mis-typed amount is caught before it is submitted, not
/// after.
class _AllocationPreview extends StatelessWidget {
  const _AllocationPreview({
    required this.cycles,
    required this.billing,
    required this.amountText,
  });

  final BillingCycleService cycles;
  final MemberBilling billing;
  final String amountText;

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(amountText.trim());
    if (parsed == null || parsed <= 0) return const SizedBox.shrink();

    final amountMinor = toMinorUnits(parsed);
    final offered =
        cycles.settleableFor(billing: billing, amountMinor: amountMinor);
    if (offered.isEmpty) return const SizedBox.shrink();

    final plan = allocate(amountMinor: amountMinor, cycles: offered);
    if (plan.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surfaceBase,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This settles', style: labelStyleOf(context)),
          const SizedBox(height: 6),
          for (final allocation in plan.allocations)
            Text(
              '${formatDayMonthYear(allocation.cycle.start)} — '
              '${formatMinorUnits(allocation.amountMinor)}'
              '${allocation.settles ? '' : ' (partial)'}',
              style: mutedStyleOf(context),
            ),
          if (plan.unallocatedMinor > 0)
            Text(
              '${formatMinorUnits(plan.unallocatedMinor)} left over — reduce '
              'the amount or it will be refused.',
              style: TextStyle(color: context.palette.expired, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

String _newKey() {
  final random = Random();
  return 'advance-${DateTime.now().microsecondsSinceEpoch}-'
      '${random.nextInt(1 << 32).toRadixString(16)}';
}
