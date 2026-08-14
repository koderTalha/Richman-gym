import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../data/receipt_repository.dart';
import '../services/record_payment_service.dart';

final _log = Logger('receipts');

sealed class ReceiptsEvent extends Equatable {
  const ReceiptsEvent();
  @override
  List<Object?> get props => const [];
}

class ReceiptsRequested extends ReceiptsEvent {
  const ReceiptsRequested();
}

class ReceiptsSearchSubmitted extends ReceiptsEvent {
  const ReceiptsSearchSubmitted(this.term);
  final String term;
  @override
  List<Object?> get props => [term];
}

class ReceiptsFilterChanged extends ReceiptsEvent {
  const ReceiptsFilterChanged(this.filter);
  final ReceiptFilter filter;
  @override
  List<Object?> get props => [filter];
}

class ReceiptResendRequested extends ReceiptsEvent {
  const ReceiptResendRequested(this.receiptId);
  final int receiptId;
  @override
  List<Object?> get props => [receiptId];
}

enum ReceiptFilter { all, sent, failed, notSent }

extension ReceiptFilterLabel on ReceiptFilter {
  String get label => switch (this) {
        ReceiptFilter.all => 'All',
        ReceiptFilter.sent => 'WhatsApp sent',
        ReceiptFilter.failed => 'WhatsApp failed',
        ReceiptFilter.notSent => 'Not sent',
      };
}

enum ReceiptsStatus { loading, ready, failed }

class ReceiptsState extends Equatable {
  const ReceiptsState({
    this.status = ReceiptsStatus.loading,
    this.rows = const [],
    this.search = '',
    this.filter = ReceiptFilter.all,
    this.resendingId,
    this.message,
    this.error,
  });

  final ReceiptsStatus status;
  final List<ReceiptRow> rows;
  final String search;
  final ReceiptFilter filter;

  /// Receipt currently being resent, so only that row shows a spinner.
  final int? resendingId;
  final String? message;
  final String? error;

  ReceiptsState copyWith({
    ReceiptsStatus? status,
    List<ReceiptRow>? rows,
    String? search,
    ReceiptFilter? filter,
    int? resendingId,
    bool clearResending = false,
    String? message,
    String? error,
  }) =>
      ReceiptsState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        search: search ?? this.search,
        filter: filter ?? this.filter,
        resendingId: clearResending ? null : (resendingId ?? this.resendingId),
        message: message,
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, rows.length, search, filter, resendingId, message, error];
}

class ReceiptsBloc extends Bloc<ReceiptsEvent, ReceiptsState> {
  ReceiptsBloc({
    required ReceiptRepository repository,
    required RecordPaymentService service,
  })  : _repository = repository,
        _service = service,
        super(const ReceiptsState()) {
    on<ReceiptsRequested>((_, emit) => _load(emit));
    on<ReceiptsSearchSubmitted>((event, emit) {
      emit(state.copyWith(search: event.term));
      return _load(emit);
    });
    on<ReceiptsFilterChanged>((event, emit) {
      emit(state.copyWith(filter: event.filter));
      return _load(emit);
    });
    on<ReceiptResendRequested>(_onResend);
  }

  final ReceiptRepository _repository;
  final RecordPaymentService _service;

  Future<void> _load(Emitter<ReceiptsState> emit) async {
    emit(state.copyWith(status: ReceiptsStatus.loading));
    try {
      final all = await _repository.list(search: state.search);
      emit(state.copyWith(
        status: ReceiptsStatus.ready,
        rows: _applyFilter(all),
        clearResending: true,
      ));
    } catch (e, s) {
      _log.severe('Loading receipts failed', e, s);
      emit(state.copyWith(status: ReceiptsStatus.failed, error: '$e'));
    }
  }

  List<ReceiptRow> _applyFilter(List<ReceiptRow> rows) {
    return switch (state.filter) {
      ReceiptFilter.all => rows,
      ReceiptFilter.sent => rows
          .where((r) =>
              r.whatsAppStatus == WhatsAppStatus.sent ||
              r.whatsAppStatus == WhatsAppStatus.delivered ||
              r.whatsAppStatus == WhatsAppStatus.read)
          .toList(),
      ReceiptFilter.failed =>
        rows.where((r) => r.whatsAppStatus == WhatsAppStatus.failed).toList(),
      ReceiptFilter.notSent =>
        rows.where((r) => r.whatsAppStatus == null).toList(),
    };
  }

  Future<void> _onResend(
    ReceiptResendRequested event,
    Emitter<ReceiptsState> emit,
  ) async {
    emit(state.copyWith(resendingId: event.receiptId));

    final outcome = await _service.resend(event.receiptId);

    final message = switch (outcome) {
      WhatsAppSent() => 'Receipt sent on WhatsApp.',
      WhatsAppFailed(:final error) => 'Send failed: $error',
      WhatsAppNotRequested() => null,
    };

    emit(state.copyWith(message: message, clearResending: true));
    await _load(emit);
  }
}
