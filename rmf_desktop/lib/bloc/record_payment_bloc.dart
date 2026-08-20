import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database.dart';
import '../domain/billing_month_check.dart';
import '../domain/payment_errors.dart';
import '../services/billing_month_checker.dart';
import '../services/record_payment_service.dart';

sealed class RecordPaymentEvent extends Equatable {
  const RecordPaymentEvent();
  @override
  List<Object?> get props => const [];
}

class RecordPaymentSubmitted extends RecordPaymentEvent {
  const RecordPaymentSubmitted({
    required this.amountMinor,
    required this.method,
    required this.paymentDate,
    required this.billingMonth,
    required this.sendWhatsApp,
    this.referenceNumber,
    this.notes,
  });

  final int amountMinor;
  final PaymentMethod method;
  final DateTime paymentDate;
  final String billingMonth;
  final bool sendWhatsApp;
  final String? referenceNumber;
  final String? notes;

  @override
  List<Object?> get props =>
      [amountMinor, method, paymentDate, billingMonth, sendWhatsApp];
}

/// The owner read the billing-month warnings and chose to go ahead.
class RecordPaymentConfirmed extends RecordPaymentEvent {
  const RecordPaymentConfirmed();
}

/// The owner backed out of the warnings, so the form comes back untouched.
class RecordPaymentConfirmationDismissed extends RecordPaymentEvent {
  const RecordPaymentConfirmationDismissed();
}

/// Clears the success panel so another payment can be taken immediately.
class RecordPaymentReset extends RecordPaymentEvent {
  const RecordPaymentReset();
}

class RecordPaymentRetryWhatsApp extends RecordPaymentEvent {
  const RecordPaymentRetryWhatsApp();
}

enum RecordPaymentStatus {
  editing,

  /// Running the billing-month checks before anything is written.
  checking,

  /// Waiting on the owner to answer the one warnings dialog.
  awaitingConfirmation,

  submitting,
  success,
  failed,
}

class RecordPaymentState extends Equatable {
  const RecordPaymentState({
    this.status = RecordPaymentStatus.editing,
    this.result,
    this.error,
    this.retrying = false,
    this.findings = const [],
  });

  final RecordPaymentStatus status;
  final RecordPaymentResult? result;
  final String? error;
  final bool retrying;

  /// Blocking findings while editing, confirmable ones while awaiting an
  /// answer. Never both: a month that cannot be right is not offered as a
  /// choice.
  final List<BillingMonthFinding> findings;

  /// True while a save is in flight, so the form disables itself rather than
  /// letting a second Confirm through.
  bool get busy =>
      status == RecordPaymentStatus.checking ||
      status == RecordPaymentStatus.submitting;

  @override
  List<Object?> get props => [
        status,
        result?.receiptNumber,
        result?.whatsApp.runtimeType,
        error,
        retrying,
        findings.map((f) => f.issue).toList(),
      ];
}

String _newKey() {
  final random = Random();
  return 'pay-${DateTime.now().microsecondsSinceEpoch}-'
      '${random.nextInt(1 << 32).toRadixString(16)}';
}

class RecordPaymentBloc extends Bloc<RecordPaymentEvent, RecordPaymentState> {
  RecordPaymentBloc({
    required RecordPaymentService service,
    required BillingMonthChecker checker,
    required this.memberId,
    required this.memberName,
    required this.memberPhone,
    required this.recordedById,
  })  : _service = service,
        _checker = checker,
        super(const RecordPaymentState()) {
    on<RecordPaymentSubmitted>(_onSubmit);
    on<RecordPaymentConfirmed>(_onConfirmed);
    on<RecordPaymentConfirmationDismissed>(
        (_, emit) => emit(const RecordPaymentState()));
    on<RecordPaymentReset>((_, emit) {
      _idempotencyKey = _newKey();
      emit(const RecordPaymentState());
    });
    on<RecordPaymentRetryWhatsApp>(_onRetry);
  }

  final RecordPaymentService _service;
  final BillingMonthChecker _checker;

  /// The submission being checked, held while the owner answers the warnings.
  RecordPaymentSubmitted? _pending;

  /// One key per bloc, i.e. per opened form. Reset only when the owner
  /// deliberately starts another payment.
  String _idempotencyKey = _newKey();
  final int memberId;
  final String memberName;
  final String memberPhone;
  final int recordedById;

  Future<void> _onSubmit(
    RecordPaymentSubmitted event,
    Emitter<RecordPaymentState> emit,
  ) async {
    // A second Confirm while the first is still running would take the money
    // twice as far as the owner is concerned, even though the idempotency key
    // stops the database recording it twice.
    if (state.busy) return;

    emit(const RecordPaymentState(status: RecordPaymentStatus.checking));

    final BillingMonthCheck check;
    try {
      check = await _checker.check(
        memberId: memberId,
        billingMonth: event.billingMonth,
      );
    } catch (e, s) {
      emit(RecordPaymentState(
        status: RecordPaymentStatus.failed,
        error: describeSaveError(e,
            stack: s, whileDoing: 'checking the billing month'),
      ));
      return;
    }

    if (check.review.isBlocked) {
      emit(RecordPaymentState(findings: check.review.blocking));
      return;
    }

    if (check.review.needsConfirmation) {
      _pending = event;
      emit(RecordPaymentState(
        status: RecordPaymentStatus.awaitingConfirmation,
        findings: check.review.confirmations,
      ));
      return;
    }

    await _record(event, const [], emit);
  }

  Future<void> _onConfirmed(
    RecordPaymentConfirmed event,
    Emitter<RecordPaymentState> emit,
  ) async {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;

    await _record(
      pending,
      state.findings.map((f) => f.issue).toList(),
      emit,
    );
  }

  Future<void> _record(
    RecordPaymentSubmitted event,
    List<BillingMonthIssue> acknowledged,
    Emitter<RecordPaymentState> emit,
  ) async {
    emit(const RecordPaymentState(status: RecordPaymentStatus.submitting));

    try {
      final result = await _service.call(RecordPaymentInput(
        memberId: memberId,
        amountMinor: event.amountMinor,
        method: event.method,
        paymentDate: event.paymentDate,
        billingMonth: event.billingMonth,
        sendWhatsApp: event.sendWhatsApp,
        recordedById: recordedById,
        idempotencyKey: _idempotencyKey,
        referenceNumber: event.referenceNumber,
        notes: event.notes,
        acknowledgedIssues: acknowledged,
      ));

      emit(RecordPaymentState(
          status: RecordPaymentStatus.success, result: result));
    } catch (e, s) {
      emit(RecordPaymentState(
        status: RecordPaymentStatus.failed,
        error: describeSaveError(e,
            stack: s, whileDoing: 'recording the payment'),
      ));
    }
  }

  Future<void> _onRetry(
    RecordPaymentRetryWhatsApp event,
    Emitter<RecordPaymentState> emit,
  ) async {
    final current = state.result;
    if (current == null) return;

    emit(RecordPaymentState(
      status: RecordPaymentStatus.success,
      result: current,
      retrying: true,
    ));

    final outcome = await _service.resend(current.receiptId);

    emit(RecordPaymentState(
      status: RecordPaymentStatus.success,
      result: RecordPaymentResult(
        paymentId: current.paymentId,
        receiptId: current.receiptId,
        receiptNumber: current.receiptNumber,
        whatsApp: outcome,
      ),
    ));
  }
}
