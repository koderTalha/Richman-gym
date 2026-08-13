import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database.dart';
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

/// Clears the success panel so another payment can be taken immediately.
class RecordPaymentReset extends RecordPaymentEvent {
  const RecordPaymentReset();
}

class RecordPaymentRetryWhatsApp extends RecordPaymentEvent {
  const RecordPaymentRetryWhatsApp();
}

enum RecordPaymentStatus { editing, submitting, success, failed }

class RecordPaymentState extends Equatable {
  const RecordPaymentState({
    this.status = RecordPaymentStatus.editing,
    this.result,
    this.error,
    this.retrying = false,
  });

  final RecordPaymentStatus status;
  final RecordPaymentResult? result;
  final String? error;
  final bool retrying;

  @override
  List<Object?> get props => [
        status,
        result?.receiptNumber,
        result?.whatsApp.runtimeType,
        error,
        retrying,
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
    required this.memberId,
    required this.memberName,
    required this.memberPhone,
    required this.recordedById,
  })  : _service = service,
        super(const RecordPaymentState()) {
    on<RecordPaymentSubmitted>(_onSubmit);
    on<RecordPaymentReset>((_, emit) {
      _idempotencyKey = _newKey();
      emit(const RecordPaymentState());
    });
    on<RecordPaymentRetryWhatsApp>(_onRetry);
  }

  final RecordPaymentService _service;

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
      ));

      emit(RecordPaymentState(
          status: RecordPaymentStatus.success, result: result));
    } catch (e) {
      emit(RecordPaymentState(
          status: RecordPaymentStatus.failed, error: '$e'));
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
