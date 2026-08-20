import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database.dart';
import '../domain/billing_month_check.dart';
import '../domain/payment_errors.dart';
import '../services/billing_month_checker.dart';
import '../services/payment_edit_service.dart';

sealed class EditPaymentEvent extends Equatable {
  const EditPaymentEvent();
  @override
  List<Object?> get props => const [];
}

class EditPaymentSubmitted extends EditPaymentEvent {
  const EditPaymentSubmitted({
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

/// The owner read the warnings and chose to save anyway.
class EditPaymentConfirmed extends EditPaymentEvent {
  const EditPaymentConfirmed();
}

class EditPaymentConfirmationDismissed extends EditPaymentEvent {
  const EditPaymentConfirmationDismissed();
}

enum EditPaymentStatus {
  editing,

  /// Running the shared billing-month checks.
  checking,

  awaitingConfirmation,
  saving,
  saved,

  /// The save was declined for a reason the owner can act on.
  refused,

  failed,
}

class EditPaymentState extends Equatable {
  const EditPaymentState({
    this.status = EditPaymentStatus.editing,
    this.findings = const [],
    this.result,
    this.error,
  });

  final EditPaymentStatus status;

  /// Blocking findings while editing, confirmable ones while awaiting an
  /// answer — never both at once.
  final List<BillingMonthFinding> findings;

  final PaymentEdited? result;

  /// Owner-facing. Never an exception's toString.
  final String? error;

  bool get busy =>
      status == EditPaymentStatus.checking ||
      status == EditPaymentStatus.saving;

  @override
  List<Object?> get props => [
        status,
        findings.map((f) => f.issue).toList(),
        result?.changes,
        result?.receipt.runtimeType,
        result?.whatsApp.runtimeType,
        error,
      ];
}

/// Drives the Edit Payment dialog.
///
/// Deliberately the same shape as [RecordPaymentBloc]: check, maybe ask, then
/// save. The rules it checks against are literally the same object, so the two
/// forms cannot drift apart.
class EditPaymentBloc extends Bloc<EditPaymentEvent, EditPaymentState> {
  EditPaymentBloc({
    required PaymentEditService service,
    required BillingMonthChecker checker,
    required this.paymentId,
    required this.memberId,
    required this.actorId,
  })  : _service = service,
        _checker = checker,
        super(const EditPaymentState()) {
    on<EditPaymentSubmitted>(_onSubmit);
    on<EditPaymentConfirmed>(_onConfirmed);
    on<EditPaymentConfirmationDismissed>(
        (_, emit) => emit(const EditPaymentState()));
  }

  final PaymentEditService _service;
  final BillingMonthChecker _checker;
  final int paymentId;
  final int memberId;
  final int actorId;

  EditPaymentSubmitted? _pending;

  Future<void> _onSubmit(
    EditPaymentSubmitted event,
    Emitter<EditPaymentState> emit,
  ) async {
    if (state.busy) return;

    emit(const EditPaymentState(status: EditPaymentStatus.checking));

    final BillingMonthCheck check;
    try {
      // The payment being edited is excluded, so it is never reported as its
      // own duplicate or as leaving its own cycle unpaid.
      check = await _checker.check(
        memberId: memberId,
        billingMonth: event.billingMonth,
        excludePaymentId: paymentId,
      );
    } catch (e, s) {
      emit(EditPaymentState(
        status: EditPaymentStatus.failed,
        error: describeSaveError(e,
            stack: s, whileDoing: 'checking the billing month'),
      ));
      return;
    }

    if (check.review.isBlocked) {
      emit(EditPaymentState(findings: check.review.blocking));
      return;
    }

    if (check.review.needsConfirmation) {
      _pending = event;
      emit(EditPaymentState(
        status: EditPaymentStatus.awaitingConfirmation,
        findings: check.review.confirmations,
      ));
      return;
    }

    await _save(event, const [], emit);
  }

  Future<void> _onConfirmed(
    EditPaymentConfirmed event,
    Emitter<EditPaymentState> emit,
  ) async {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;

    await _save(pending, state.findings.map((f) => f.issue).toList(), emit);
  }

  Future<void> _save(
    EditPaymentSubmitted event,
    List<BillingMonthIssue> acknowledged,
    Emitter<EditPaymentState> emit,
  ) async {
    emit(const EditPaymentState(status: EditPaymentStatus.saving));

    try {
      final result = await _service.edit(EditPaymentInput(
        paymentId: paymentId,
        amountMinor: event.amountMinor,
        method: event.method,
        paymentDate: event.paymentDate,
        billingMonth: event.billingMonth,
        editedById: actorId,
        referenceNumber: event.referenceNumber,
        notes: event.notes,
        sendWhatsApp: event.sendWhatsApp,
        acknowledgedIssues: acknowledged,
      ));

      switch (result) {
        case PaymentEdited():
          emit(EditPaymentState(
              status: EditPaymentStatus.saved, result: result));
        case PaymentEditRefused(:final message):
          emit(EditPaymentState(
              status: EditPaymentStatus.refused, error: message));
      }
    } catch (e, s) {
      emit(EditPaymentState(
        status: EditPaymentStatus.failed,
        error: describeSaveError(e,
            stack: s, whileDoing: 'saving the correction'),
      ));
    }
  }
}
