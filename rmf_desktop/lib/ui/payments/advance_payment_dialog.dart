import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/database.dart';
import '../../data/member_repository.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/payment_errors.dart';
import '../../domain/payment_method.dart';
import '../../domain/payment_settlement.dart' show allocate;
import '../../services/billing_cycle_service.dart';
import '../../services/record_payment_service.dart';
import '../../theme/app_theme.dart';
import 'payment_history_table.dart' show formatShortDate;

/// Records a payment with no billing month to pick — the flexible path.
///
/// The owner types an amount and a date; the app works out which of the
/// member's own cycles it settles, arrears first, and opens as many ahead as
/// the money reaches. This is what makes "pay on the 1st, the 15th, or the
/// 28th and the cycle looks after itself" a real button rather than a
/// principle in a design document — see
/// `RecordPaymentService.recordAdvancePayment`.
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
  late final String _idempotencyKey;

  DateTime _paymentDate = DateTime.now();
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;
  String? _error;
  RecordPaymentResult? _result;
  MemberBilling? _billing;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = _newKey();
    _amount = TextEditingController(
      text: widget.member.feeMinor == null
          ? ''
          : fromMinorUnits(widget.member.feeMinor!).toStringAsFixed(0),
    );
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await widget.service.recordAdvancePayment(
        AdvancePaymentInput(
          memberId: widget.member.id,
          amountMinor: toMinorUnits(double.parse(_amount.text.trim())),
          method: _method,
          paymentDate: _paymentDate,
          sendWhatsApp: false,
          recordedById: widget.recordedById,
          idempotencyKey: _idempotencyKey,
        ),
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error, stack) {
      if (!mounted) return;
      setState(() =>
          _error = describeSaveError(error, stack: stack, whileDoing: 'recording the payment'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              Text('Receipt: ${result.receiptNumber}', style: mutedStyleOf(context)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Done'),
        ),
      ],
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
