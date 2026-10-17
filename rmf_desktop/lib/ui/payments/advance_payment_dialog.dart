import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../bloc/auth_bloc.dart';
import '../../data/database.dart';
import '../../data/member_repository.dart';
import '../../domain/billing_month_check.dart';
import '../../domain/billing_period.dart';
import '../../domain/dates.dart';
import '../../domain/member_status.dart';
import '../../domain/money.dart';
import '../../domain/payment_errors.dart';
import '../../domain/payment_method.dart';
import '../../domain/payment_settlement.dart' show SettleableCycle, allocate;
import '../../domain/payment_timing.dart';
import '../../domain/phone.dart';
import '../../services/billing_cycle_service.dart';
import '../../services/billing_month_checker.dart';
import '../../services/receipt_storage.dart';
import '../../services/record_payment_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/page_scaffold.dart' show AccentButton;
import '../widgets/status_badge.dart';
import 'billing_warnings_dialog.dart';
import 'payment_history_table.dart' show formatShortDate;

/// The one dialog for taking a member's money.
///
/// Two ways to say which cycle the money is for, and the default is to say
/// nothing at all:
///
///   * **Automatic** — the owner types an amount and the date it was handed
///     over, and the app works out which of the member's own cycles it
///     settles, arrears first, opening as many ahead as the money reaches.
///     This is the counter: somebody pays what they owe and nobody should have
///     to think about months.
///   * **A named billing period** — the owner is entering history the app was
///     not open for. The month is stated outright, its cycle is opened if it is
///     missing, and the payment settles that month and no other.
///
/// The second existed in the service and in Edit Payment from the start, but
/// not here, so recording a back-dated payment meant letting it land on the
/// wrong month and correcting it afterwards — writing a wrong row to the
/// ledger on the way to the right one.
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
  final checker = context.read<BillingMonthChecker>();
  final userId = context.read<AuthBloc>().state.user!.id;

  return showGeneralDialog<bool>(
    context: context,
    // Not dismissible by a stray click outside. The caller refreshes only when
    // this resolves to true, and a barrier tap resolves to null — so after a
    // payment was recorded, closing it that way would leave the member list
    // showing them as still owing. Escape and the close button both go
    // through _close, which answers correctly either way.
    barrierDismissible: false,
    barrierColor: context.palette.scrim,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => _AdvancePaymentDialog(
      member: member,
      service: service,
      cycles: cycles,
      checker: checker,
      recordedById: userId,
    ),
    // The handoff's entrance: the backdrop blurs, the panel fades in while
    // rising 12px and settling from 98% scale.
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 3 * animation.value,
          sigmaY: 3 * animation.value,
        ),
        child: FadeTransition(
          opacity: curved,
          child: AnimatedBuilder(
            animation: curved,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 12 * (1 - curved.value)),
              child: Transform.scale(
                scale: 0.98 + 0.02 * curved.value,
                child: child,
              ),
            ),
            child: child,
          ),
        ),
      );
    },
  );
}

class _AdvancePaymentDialog extends StatefulWidget {
  const _AdvancePaymentDialog({
    required this.member,
    required this.service,
    required this.cycles,
    required this.checker,
    required this.recordedById,
  });

  final MemberRow member;
  final RecordPaymentService service;
  final BillingCycleService cycles;

  /// Runs the billing-month rules when a month is named. The same checker Edit
  /// Payment uses, so both routes ask identical questions.
  final BillingMonthChecker checker;

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
  bool _checkingMonth = false;
  String? _error;

  /// Sticky within one submission, so fixing a validation error after
  /// confirming does not ask the same question twice. Cleared by
  /// [_recordAnother], because the answer belonged to that amount.
  bool _confirmedAdvance = false;
  RecordPaymentResult? _result;
  MemberBilling? _billing;
  late bool _sendWhatsApp;

  /// "YYYY-MM", or null for Automatic. Null is the counter's answer and the
  /// default; a value here means the owner is stating which month this money
  /// belongs to.
  String? _billingMonth;

  /// The rules' verdict on [_billingMonth], re-read whenever it changes. Also
  /// carries whether that month already has a cycle, which is what decides if
  /// the fee has to be asked for.
  BillingMonthCheck? _monthCheck;

  /// What the named month cost, asked only when its cycle has to be created.
  final _monthFee = TextEditingController();

  bool get _phoneUsable => isValidPhone(widget.member.member.phone);

  @override
  void initState() {
    super.initState();
    _idempotencyKey = _newKey();
    _amount = TextEditingController(
      text: widget.member.feeMinor == null
          ? ''
          : formatAmountInput(widget.member.feeMinor!),
    );
    _sendWhatsApp = _phoneUsable;
    _loadBilling();
  }

  @override
  void dispose() {
    _amount.dispose();
    _monthFee.dispose();
    super.dispose();
  }

  /// Whether the owner has named a month rather than leaving it automatic.
  bool get _isBackEntry => _billingMonth != null;

  /// True when the named month has no cycle, so recording will open one and
  /// its price is the owner's to state.
  bool get _opensNewCycle => _isBackEntry && _monthCheck?.period == null;

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

  Future<void> _pickBillingMonth() async {
    final current = _billingMonth == null
        ? DateTime.now()
        : parseBillingMonth(_billingMonth!);

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select any day in the billing month',
    );
    if (picked == null) return;

    setState(() => _billingMonth =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}');
    await _runMonthCheck();
  }

  void _clearBillingMonth() {
    setState(() {
      _billingMonth = null;
      _monthCheck = null;
    });
  }

  /// Re-reads the rules for the named month.
  ///
  /// Runs on every change rather than only on submit, so the owner sees a
  /// month that needs a fee — or one the rules will refuse — while they can
  /// still do something about it.
  Future<void> _runMonthCheck() async {
    final month = _billingMonth;
    if (month == null) return;

    setState(() => _checkingMonth = true);
    try {
      final check = await widget.checker.check(
        memberId: widget.member.id,
        billingMonth: month,
      );
      if (!mounted) return;
      setState(() {
        _monthCheck = check;
        // A month with no cycle is about to get one, and it must be worth what
        // that month cost — see RecordPaymentInput.expectedAmountMinor.
        //
        // For the month in front of the owner today's fee is that answer. For
        // a month already gone it is the one answer that is certainly wrong,
        // and offering it is worse than offering nothing: a gym typing up last
        // year's register after a price rise accepts the suggestion once per
        // row, and every old month is conjured at the new price, marked paid
        // in full and left short by the difference. A cycle holding money is
        // never re-priced, so nothing afterwards can put it back. The field is
        // required, so leaving it empty asks the question instead.
        final past = parseBillingMonth(month)
            .isBefore(parseBillingMonth(currentBillingMonth()));
        if (check.period == null && !past && _monthFee.text.trim().isEmpty) {
          final fee = widget.member.feeMinor;
          if (fee != null) {
            _monthFee.text = formatAmountInput(fee);
          }
        }
      });
    } finally {
      if (mounted) setState(() => _checkingMonth = false);
    }
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

    final parsed = parseAmountMinor(_amount.text);
    final amountMinor =
        (parsed == null || parsed <= 0) ? billing.feeMinor : parsed;
    if (amountMinor <= 0) return null;

    final offered =
        widget.cycles.settleableFor(billing: billing, amountMinor: amountMinor);
    return allocate(amountMinor: amountMinor, cycles: offered).coveredSpan?.end;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // A named month goes through the billing-month rules and settles that
    // month alone. Nothing about the automatic path below changes.
    if (_isBackEntry) {
      await _submitForMonth();
      return;
    }

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
          amountMinor: parseAmountMinor(_amount.text)!,
          method: _method,
          paymentDate: _paymentDate,
          sendWhatsApp: _sendWhatsApp,
          recordedById: widget.recordedById,
          idempotencyKey: _idempotencyKey,
          confirmedAdvance: confirmedAdvance,
        ),
      );

  /// Records against the month the owner named.
  ///
  /// The rules are re-run here rather than trusted from the last check: the
  /// amount or the month may have moved since, and a duplicate payment that
  /// appeared in between must still be caught.
  Future<void> _submitForMonth() async {
    final month = _billingMonth;
    if (month == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final check = await widget.checker.check(
        memberId: widget.member.id,
        billingMonth: month,
      );
      if (!mounted) return;
      setState(() => _monthCheck = check);

      // Blocking findings are never negotiable — billing a month before the
      // member joined is wrong however it is confirmed.
      if (check.review.isBlocked) {
        setState(() {
          _busy = false;
          _error = check.review.blocking.first.message;
        });
        return;
      }

      if (check.review.needsConfirmation) {
        setState(() => _busy = false);
        final go = await confirmBillingWarnings(
          context,
          check.review.confirmations,
          continueLabel: 'Record payment',
        );
        if (!mounted || !go) return;
        setState(() => _busy = true);
      }

      final result = await widget.service.call(RecordPaymentInput(
        memberId: widget.member.id,
        amountMinor: parseAmountMinor(_amount.text)!,
        method: _method,
        paymentDate: _paymentDate,
        billingMonth: month,
        sendWhatsApp: _sendWhatsApp,
        recordedById: widget.recordedById,
        idempotencyKey: _idempotencyKey,
        acknowledgedIssues: check.review.issues,
        // Only meaningful when the cycle is being opened by this payment; the
        // service ignores it for a month that already has one.
        expectedAmountMinor: _opensNewCycleFee(),
      ));
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error, stack) {
      if (!mounted) return;
      setState(() => _error = describeSaveError(error,
          stack: stack, whileDoing: 'recording the payment'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The fee to stamp on a cycle this payment is about to open, or null when
  /// the month already has one.
  int? _opensNewCycleFee() {
    if (!_opensNewCycle) return null;
    final parsed = parseAmountMinor(_monthFee.text);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

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
      // Automatic again: the month belonged to the entry just saved.
      _billingMonth = null;
      _monthCheck = null;
      _monthFee.clear();
      _amount.text = widget.member.feeMinor == null
          ? ''
          : formatAmountInput(widget.member.feeMinor!);
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

  /// Closes the dialog, telling the caller whether anything was recorded so
  /// it knows to refresh. Refused while a payment is being saved: closing then
  /// would leave the owner unsure whether the money went in.
  void _close() {
    if (_busy) return;
    Navigator.of(context).pop(_result != null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Dialog(
        backgroundColor: palette.surfaceRaised,
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          // 460 per the handoff; taller than the mock because this form also
          // previews where the money lands and can name a back-dated month.
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_result == null) _header(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: _result == null
                      ? const EdgeInsets.fromLTRB(20, 0, 20, 20)
                      : const EdgeInsets.fromLTRB(24, 32, 24, 22),
                  child: _result != null
                      // The amount field held focus and has just gone, which
                      // would leave nothing in the dialog to hear Escape.
                      ? Focus(autofocus: true, child: _successBody(context))
                      : _formBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final palette = context.palette;
    final member = widget.member.member;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Record payment',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary)),
                const SizedBox(height: 2),
                Text('${member.fullName} · #${member.memberCode}',
                    style: TextStyle(fontSize: 12, color: palette.textMuted)),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              tooltip: 'Close',
              color: palette.textMuted,
              icon: const Icon(Icons.close),
              onPressed: _busy ? null : _close,
            ),
          ),
        ],
      ),
    );
  }

  String _confirmLabel() {
    final minor = parseAmountMinor(_amount.text);
    if (minor == null || minor <= 0) return 'Confirm payment';
    return 'Confirm ${formatMinorUnits(minor)}';
  }

  Widget _formBody() {
    final palette = context.palette;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Labelled(
            label: 'Amount received',
            child: TextFormField(
              key: const Key('payment-amount'),
              controller: _amount,
              enabled: !_busy,
              autofocus: true,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: palette.textPrimary,
              ),
              decoration: InputDecoration(
                prefixText: 'Rs.  ',
                prefixStyle: TextStyle(fontSize: 14, color: palette.textMuted),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              keyboardType: TextInputType.number,
              validator: (v) => amountInputError(v ?? ''),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),
          _MethodPicker(
            selected: _method,
            onSelect: _busy ? null : (m) => setState(() => _method = m),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Labelled(
                  label: 'Payment date',
                  child: _PickerField(
                    text: formatShortDate(_paymentDate),
                    icon: Icons.calendar_today_outlined,
                    onTap: _busy ? null : _pickDate,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Labelled(
                  label: 'Billing period',
                  child: _PickerField(
                    // The handoff's wording for Automatic: the money goes to
                    // the oldest cycle still owing, then forward.
                    text: _isBackEntry
                        ? labelForNamedMonth(_billingMonth!, _monthCheck)
                        : 'Oldest unpaid first',
                    icon: _isBackEntry ? Icons.close : Icons.expand_more,
                    iconTooltip: _isBackEntry ? 'Back to oldest unpaid' : null,
                    onIconTap: _isBackEntry && !_busy
                        ? _clearBillingMonth
                        : null,
                    onTap: _busy ? null : _pickBillingMonth,
                  ),
                ),
              ),
            ],
          ),
          if (_opensNewCycle) ...[
            const SizedBox(height: 14),
            _Labelled(
              label: 'Fee for this month',
              child: TextFormField(
                key: const Key('payment-month-fee'),
                controller: _monthFee,
                enabled: !_busy,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixText: 'Rs.  ',
                  helperText:
                      'No cycle exists for this month yet, so say what it cost',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (!_opensNewCycle) return null;
                  if ((v ?? '').trim().isEmpty) {
                    return 'What did this month cost?';
                  }
                  return amountInputError(v!);
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          _SettlementPreview(
            member: widget.member,
            billing: _billing,
            cycles: widget.cycles,
            amountText: _amount.text,
            billingMonth: _billingMonth,
            check: _monthCheck,
            checking: _checkingMonth,
            newCycleFeeMinor: _opensNewCycleFee(),
          ),
          const SizedBox(height: 14),
          _WhatsAppToggle(
            value: _sendWhatsApp,
            phone: widget.member.member.phone,
            onChanged: _phoneUsable && !_busy
                ? (v) => setState(() => _sendWhatsApp = v)
                : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.expiredBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style: TextStyle(color: palette.expired, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: FilledButton(
              key: const Key('confirm-payment'),
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // The amount in the label, so what the owner presses is a
                  // statement of what is about to be recorded.
                  Text(_busy ? 'Recording…' : _confirmLabel()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successBody(BuildContext context) {
    final palette = context.palette;
    final result = _result!;
    final whatsApp = result.whatsApp;
    final amountMinor = parseAmountMinor(_amount.text);
    final member = widget.member.member;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _DrawnCheck()),
        const SizedBox(height: 14),
        Text('Payment recorded',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: palette.textPrimary)),
        const SizedBox(height: 6),
        Text(
          [
            if (amountMinor != null)
              '${formatMinorUnits(amountMinor)} from ${member.fullName}'
            else
              member.fullName,
            result.receiptNumber,
          ].join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: palette.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (result.timing.isNoteworthy) ...[
          const SizedBox(height: 8),
          Center(child: PaymentTimingBadge(timing: result.timing)),
        ],
        const SizedBox(height: 6),
        Text(
          switch (whatsApp) {
            WhatsAppNotRequested() => 'No WhatsApp message sent',
            WhatsAppSent() =>
              'Receipt sent on WhatsApp to ${formatPhoneForDisplay(member.phone)}',
            WhatsAppFailed(:final error) => 'WhatsApp failed — $error',
          },
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: whatsApp is WhatsAppFailed ? palette.due : palette.textMuted,
          ),
        ),
        if (whatsApp is WhatsAppFailed) ...[
          const SizedBox(height: 10),
          Text(
            'The payment and receipt are saved. You can retry the '
            'WhatsApp send now or from the Receipts screen.',
            textAlign: TextAlign.center,
            style: mutedStyleOf(context),
          ),
          const SizedBox(height: 10),
          Center(
            child: OutlinedButton.icon(
              onPressed: _retrying ? null : _retryWhatsApp,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(_retrying ? 'Retrying…' : 'Retry WhatsApp'),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => _openReceipt(result.receiptNumber),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('View receipt'),
                style: TextButton.styleFrom(
                    foregroundColor: palette.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _printReceipt(result.receiptNumber),
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Print receipt'),
                style: TextButton.styleFrom(
                    foregroundColor: palette.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _recordAnother,
                style: TextButton.styleFrom(
                    foregroundColor: palette.textSecondary),
                child: const Text('Record another'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccentButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A green circle with a tick that draws itself in, per the handoff.
class _DrawnCheck extends StatefulWidget {
  const _DrawnCheck();

  @override
  State<_DrawnCheck> createState() => _DrawnCheckState();
}

class _DrawnCheckState extends State<_DrawnCheck>
    with SingleTickerProviderStateMixin {
  // 600ms: a 100ms pause then the handoff's 500ms draw, held as one
  // animation rather than a timer plus an animation — a pending timer is
  // exactly what a widget test cannot see the end of.
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Drawn complete at once under reduced motion — and, as everywhere else in
    // the app, an animation that runs once and stops.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else if (_controller.value == 0 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(64),
      painter: _CheckPainter(
        progress: CurvedAnimation(
          parent: _controller,
          curve: const Interval(1 / 6, 1, curve: Curves.easeOut),
        ),
        colour: context.palette.paid,
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.colour})
      : super(repaint: progress);

  final Animation<double> progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 64;
    canvas.drawCircle(
      size.center(Offset.zero),
      29 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = colour.withValues(alpha: 0.25),
    );

    // The handoff's path: M20 33 l8 8 l16 -18, drawn up to [progress].
    final tick = Path()
      ..moveTo(20 * scale, 33 * scale)
      ..relativeLineTo(8 * scale, 8 * scale)
      ..relativeLineTo(16 * scale, -18 * scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = colour;

    final drawn = Path();
    for (final metric in tick.computeMetrics()) {
      drawn.addPath(
          metric.extractPath(0, metric.length * progress.value), Offset.zero);
    }
    canvas.drawPath(drawn, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.colour != colour;
}

/// The span a named month actually settles.
///
/// Not the month the owner picked: `periodForMemberContaining` resolves by
/// containment, so on a quarterly plan every month of the quarter resolves to
/// the single cycle covering it. Counting the plan's duration forward from the
/// picked month therefore named a span that does not exist — "September 2026 -
/// November 2026" for money settling the August quarter, and on a non-1st
/// anchor "August" for a cycle running 6 July to 6 August.
///
/// Falls back to the picked month when no cycle exists yet, which is right:
/// there is nothing to contain it, and this payment is about to open one
/// starting there.
String labelForNamedMonth(String billingMonth, BillingMonthCheck? check) =>
    formatBillingPeriod(
      check?.period?.periodStart ?? parseBillingMonth(billingMonth),
      check?.durationMonths ?? 1,
    );

/// What this payment will do, in one box under the form — the handoff's
/// settlement preview: which cycle it covers, and how far it moves the
/// member's paid-until date.
///
/// Everything the dialog used to say in three separate boxes lands here, as
/// lines under those two rows: an amount too large to place, a named month
/// being overpaid, a month the billing rules refuse, a month that has no cycle
/// yet. None of it was dropped in the redesign; it was only gathered.
class _SettlementPreview extends StatelessWidget {
  const _SettlementPreview({
    required this.member,
    required this.billing,
    required this.cycles,
    required this.amountText,
    required this.billingMonth,
    required this.check,
    required this.checking,
    required this.newCycleFeeMinor,
  });

  final MemberRow member;
  final MemberBilling? billing;
  final BillingCycleService cycles;
  final String amountText;

  /// Null when the money goes to the oldest unpaid cycle first.
  final String? billingMonth;
  final BillingMonthCheck? check;
  final bool checking;

  /// The fee typed for a named month that has no cycle yet, once typed.
  final int? newCycleFeeMinor;

  int get _durationMonths => member.plan?.durationMonths ?? 1;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final named = billingMonth;
    final rows = <Widget>[];
    final notes = <Widget>[];

    Widget note(String text, Color colour, {IconData? icon}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: 13, color: colour),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(text, style: TextStyle(fontSize: 12, color: colour)),
              ),
            ],
          ),
        );

    if (named != null) {
      _namedMonth(named, rows, notes, note, palette);
    } else {
      _automatic(rows, notes, note, palette);
    }

    // Recording a payment does not undo a deactivation in this app — only
    // Reactivate (or Restart billing) on the profile does. The handoff's
    // prototype promised the opposite; saying so here would be untrue.
    if (member.status == MemberStatus.inactive) {
      notes.add(note(
        'This member is inactive. Recording a payment does not reactivate '
        'them — use Reactivate on their profile.',
        palette.due,
        icon: Icons.person_off_outlined,
      ));
    }

    if (rows.isEmpty && notes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.surfaceBase,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            rows[i],
          ],
          ...notes,
        ],
      ),
    );
  }

  /// The two-column line the handoff draws: a muted label, the value right.
  static Widget _row(BuildContext context, String label, Widget value) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: context.palette.textMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      );

  /// "~~25 Oct 2026~~ → 25 Nov 2026".
  Widget _paidUntil(BuildContext context, DateTime? before, DateTime after) {
    final palette = context.palette;
    return Text.rich(
      TextSpan(children: [
        if (before != null) ...[
          TextSpan(
            text: formatDayMonthYear(before),
            style: TextStyle(
              color: palette.textMuted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const TextSpan(text: ' → '),
        ],
        TextSpan(
          text: formatDayMonthYear(after),
          style: TextStyle(
              fontWeight: FontWeight.w600, color: palette.textPrimary),
        ),
      ]),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 13,
        color: palette.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Text _value(BuildContext context, String text) => Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(fontSize: 13, color: context.palette.textPrimary),
      );

  void _automatic(
    List<Widget> rows,
    List<Widget> notes,
    Widget Function(String, Color, {IconData? icon}) note,
    AppPalette palette,
  ) {
    final billing = this.billing;
    final amountMinor = parseAmountMinor(amountText);
    if (billing == null || amountMinor == null || amountMinor <= 0) return;

    final offered =
        cycles.settleableFor(billing: billing, amountMinor: amountMinor);
    if (offered.isEmpty) return;
    final plan = allocate(amountMinor: amountMinor, cycles: offered);
    if (plan.isEmpty) return;

    final first = plan.allocations.first.cycle;
    final count = plan.allocations.length;
    rows.add(Builder(
      builder: (context) => _row(
        context,
        'Covers',
        _value(
          context,
          '${formatBillingPeriod(first.start, _durationMonths * count)}'
          ' · from ${formatDayMonthYear(first.start)}',
        ),
      ),
    ));

    // Paid-until moves to the end of the last cycle this money settles in
    // full — the same rule the member list reads it by. A part payment moves
    // nothing, and that is said rather than shown as a date.
    DateTime? newUntil;
    for (final allocation in plan.allocations) {
      if (allocation.settles) newUntil = allocation.cycle.end;
    }
    final before = member.paidUntil;
    if (newUntil != null && (before == null || newUntil.isAfter(before))) {
      final until = newUntil;
      rows.add(Builder(
        builder: (context) =>
            _row(context, 'Paid until', _paidUntil(context, before, until)),
      ));
    }

    final last = plan.allocations.last;
    if (!last.settles) {
      notes.add(note(
        'Part payment: ${formatMinorUnits(last.cycle.outstandingMinor - last.amountMinor)} '
        'will still be owing on the cycle from '
        '${formatDayMonthYear(last.cycle.start)}.',
        palette.textMuted,
      ));
    }
    if (plan.unallocatedMinor > 0) {
      notes.add(note(
        '${formatMinorUnits(plan.unallocatedMinor)} left over — reduce the '
        'amount or it will be refused.',
        palette.expired,
        icon: Icons.error_outline,
      ));
    }
  }

  /// What the named month still owes, or null when that is not known yet.
  int? _owedMinor(BillingMonthCheck resolved) {
    final period = resolved.period;
    if (period == null) return newCycleFeeMinor ?? billing?.feeMinor;
    for (final cycle in billing?.cycles ?? const <SettleableCycle>[]) {
      if (cycle.periodId == period.id) return cycle.outstandingMinor;
    }
    return null;
  }

  void _namedMonth(
    String named,
    List<Widget> rows,
    List<Widget> notes,
    Widget Function(String, Color, {IconData? icon}) note,
    AppPalette palette,
  ) {
    final resolved = check;
    final label = labelForNamedMonth(named, resolved);
    final start = resolved?.period?.periodStart ?? parseBillingMonth(named);

    rows.add(Builder(
      builder: (context) => _row(
        context,
        'Covers',
        _value(
          context,
          checking
              ? '$label — checking…'
              : '$label · from ${formatDayMonthYear(start)}',
        ),
      ),
    ));

    if (resolved == null || checking) return;

    if (resolved.period == null) {
      notes.add(note(
        'No billing cycle exists for this period yet — recording this payment '
        'creates it.',
        palette.textMuted,
      ));
    }

    // A named month takes the whole amount, however much it is: the spread
    // across later months only happens with "Oldest unpaid first". Typing two
    // months' fees here used to leave next month reading as due with nothing
    // on the form to say why.
    final amount = parseAmountMinor(amountText);
    final owed = _owedMinor(resolved);
    if (amount != null && owed != null && amount > owed) {
      notes.add(note(
        'This is ${formatMinorUnits(amount - owed)} more than this month still '
        'owes, and all of it stays on this month. To pay months ahead, switch '
        'back to Oldest unpaid first.',
        palette.due,
      ));
    }

    for (final finding in [
      ...resolved.review.blocking,
      ...resolved.review.confirmations,
    ]) {
      final blocks = finding.severity == FindingSeverity.block;
      notes.add(note(
        finding.message,
        blocks ? palette.expired : palette.due,
        icon: blocks ? Icons.block : Icons.warning_amber_outlined,
      ));
    }
  }
}

/// A form field's label set above it, per the handoff, rather than floating
/// inside the box.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style:
                TextStyle(fontSize: 12, color: context.palette.textSecondary)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// A read-only field that opens a picker: the payment date and the billing
/// period. Looks like the text fields beside it, with its icon on the right.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.text,
    required this.icon,
    required this.onTap,
    this.onIconTap,
    this.iconTooltip,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  /// When set, the icon is its own button — the billing period's "back to
  /// oldest unpaid" cross.
  final VoidCallback? onIconTap;
  final String? iconTooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final iconWidget = Icon(icon, size: 16, color: palette.textMuted);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          isDense: true,
          enabled: onTap != null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 20),
          suffixIcon: onIconTap == null
              ? iconWidget
              : IconButton(
                  onPressed: onIconTap,
                  tooltip: iconTooltip,
                  icon: iconWidget,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(fontSize: 13, color: palette.textPrimary),
        ),
      ),
    );
  }
}

String _newKey() {
  final random = Random();
  return 'advance-${DateTime.now().microsecondsSinceEpoch}-'
      '${random.nextInt(1 << 32).toRadixString(16)}';
}

/// The payment methods as buttons, three to a row, instead of a dropdown.
///
/// The handoff's segmented method picker. A dropdown hides the choice behind
/// a click on the one field every payment touches; here the owner sees all of
/// them and taps the one in their hand. Selected is an accent ring on a tint,
/// never a solid fill.
class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.selected, required this.onSelect});

  final PaymentMethod selected;

  /// Null while the form is busy.
  final ValueChanged<PaymentMethod>? onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const perRow = 3;
    const methods = PaymentMethod.values;

    Widget button(PaymentMethod method) {
      final on = method == selected;
      return Semantics(
        selected: on,
        button: true,
        child: OutlinedButton(
          onPressed: onSelect == null ? null : () => onSelect!(method),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(36),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            foregroundColor: on ? palette.textPrimary : palette.textSecondary,
            backgroundColor: on ? palette.accent.withValues(alpha: 0.14) : null,
            side: BorderSide(color: on ? palette.accent : palette.borderStrong),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            textStyle: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
          child: Text(paymentMethodLabel(method),
              overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Method',
            style: TextStyle(fontSize: 12, color: palette.textSecondary)),
        const SizedBox(height: 6),
        for (var start = 0; start < methods.length; start += perRow) ...[
          if (start > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var i = start; i < start + perRow; i++) ...[
                if (i > start) const SizedBox(width: 6),
                Expanded(
                  child: i < methods.length
                      ? button(methods[i])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// "Send receipt on WhatsApp" as a switch with the number it will go to.
class _WhatsAppToggle extends StatelessWidget {
  const _WhatsAppToggle({
    required this.value,
    required this.phone,
    required this.onChanged,
  });

  final bool value;
  final String phone;

  /// Null when the member has no usable number, or while saving.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final usable = isValidPhone(phone);

    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Transform.scale(
              // Material's switch is larger than the handoff's 36×20; scaled
              // rather than rebuilt so it keeps its keyboard and screen-reader
              // behaviour.
              scale: 0.8,
              child: Switch(
                value: value && usable,
                onChanged: onChanged,
                activeTrackColor: palette.accent,
                inactiveTrackColor: palette.borderStrong,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send receipt on WhatsApp',
                      style: TextStyle(
                          fontSize: 13, color: palette.textPrimary)),
                  Text(
                    usable
                        ? 'To ${formatPhoneForDisplay(phone)}'
                        : 'Unavailable — this member has no valid WhatsApp '
                            'number',
                    style: TextStyle(fontSize: 11, color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
