import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../domain/billing_period.dart';
import '../../domain/money.dart';
import '../../theme/app_theme.dart';
import 'payment_history_table.dart';

/// The editable state of a payment, held by whichever dialog is showing it.
///
/// Recording a payment and correcting one ask for exactly the same six values,
/// so they share the fields rather than keeping two copies of the same form —
/// and with them, one set of validators, one date picker behaviour and one
/// month picker.
class PaymentFormController {
  PaymentFormController({
    int? initialAmountMinor,
    required this.billingMonth,
    DateTime? paymentDate,
    this.method = PaymentMethod.cash,
    String? referenceNumber,
    String? notes,
  })  : paymentDate = paymentDate ?? DateTime.now(),
        amount = TextEditingController(
          text: initialAmountMinor == null
              ? ''
              : fromMinorUnits(initialAmountMinor).toStringAsFixed(0),
        ),
        reference = TextEditingController(text: referenceNumber ?? ''),
        notes = TextEditingController(text: notes ?? '');

  final TextEditingController amount;
  final TextEditingController reference;
  final TextEditingController notes;

  PaymentMethod method;
  DateTime paymentDate;

  /// "YYYY-MM".
  String billingMonth;

  /// Only meaningful once the form validates.
  int get amountMinor => toMinorUnits(double.parse(amount.text.trim()));

  String? get referenceOrNull =>
      reference.text.trim().isEmpty ? null : reference.text.trim();

  String? get notesOrNull =>
      notes.text.trim().isEmpty ? null : notes.text.trim();

  void dispose() {
    amount.dispose();
    reference.dispose();
    notes.dispose();
  }
}

/// Amount, method, payment date, billing period, reference and notes.
class PaymentFormFields extends StatefulWidget {
  const PaymentFormFields({
    super.key,
    required this.controller,
    required this.planDurationMonths,
    this.enabled = true,
    this.autofocus = true,
    this.onChanged,
  });

  final PaymentFormController controller;

  /// Length of the member's plan, so a quarterly cycle reads
  /// "August 2026 - October 2026" rather than naming its first month only.
  final int planDurationMonths;

  /// False while a save is in flight, so nothing can be edited mid-submit.
  final bool enabled;

  final bool autofocus;

  /// Lets the parent react to a picker changing, e.g. to re-run the
  /// billing-month checks.
  final VoidCallback? onChanged;

  @override
  State<PaymentFormFields> createState() => _PaymentFormFieldsState();
}

class _PaymentFormFieldsState extends State<PaymentFormFields> {
  PaymentFormController get _form => widget.controller;

  void _changed(VoidCallback mutate) {
    setState(mutate);
    widget.onChanged?.call();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _form.paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) _changed(() => _form.paymentDate = picked);
  }

  Future<void> _pickBillingMonth() async {
    final parts = _form.billingMonth.split('-');
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
      _changed(() => _form.billingMonth =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _form.amount,
                enabled: enabled,
                decoration: const InputDecoration(
                    labelText: 'Amount (PKR) *', isDense: true),
                keyboardType: TextInputType.number,
                autofocus: widget.autofocus,
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
                initialValue: _form.method,
                decoration: const InputDecoration(
                    labelText: 'Payment method', isDense: true),
                items: PaymentMethod.values
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text(paymentMethodLabel(m))))
                    .toList(),
                onChanged: enabled
                    ? (v) => _changed(() => _form.method = v ?? _form.method)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _PickerField(
                label: 'Payment date',
                value: formatShortDate(_form.paymentDate),
                onTap: enabled ? _pickDate : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _PickerField(
                label: 'Billing period',
                value: formatBillingPeriod(
                  parseBillingMonth(_form.billingMonth),
                  widget.planDurationMonths,
                ),
                onTap: enabled ? _pickBillingMonth : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _form.reference,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'Transaction / reference no. (optional)',
            hintText: 'e.g. 114828',
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _form.notes,
          enabled: enabled,
          decoration: const InputDecoration(
              labelText: 'Notes (optional)', isDense: true),
          maxLines: 2,
        ),
      ],
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: onTap == null
                ? context.palette.textMuted
                : context.palette.textPrimary,
          ),
        ),
      ),
    );
  }
}
