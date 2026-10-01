import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/receipt_repository.dart';
import '../services/record_payment_service.dart';

// The filter is applied in SQL by the repository, so it lives there; it is
// re-exported because the screen and its callers have always found it here.
export '../data/receipt_repository.dart' show ReceiptFilter;

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
    this.matchCount = 0,
    this.search = '',
    this.filter = ReceiptFilter.all,
    this.resendingId,
    this.message,
    this.error,
  });

  final ReceiptsStatus status;

  /// The newest matching receipts, up to the repository's page size.
  final List<ReceiptRow> rows;

  /// How many receipts match the search and filter in all, so the header can
  /// say when [rows] is only the newest part of them.
  final int matchCount;
  final String search;
  final ReceiptFilter filter;

  /// Receipt currently being resent, so only that row shows a spinner.
  final int? resendingId;
  final String? message;
  final String? error;

  /// Whether [rows] is only the newest part of what matched.
  bool get isCapped => matchCount > rows.length;

  ReceiptsState copyWith({
    ReceiptsStatus? status,
    List<ReceiptRow>? rows,
    int? matchCount,
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
        matchCount: matchCount ?? this.matchCount,
        search: search ?? this.search,
        filter: filter ?? this.filter,
        resendingId: clearResending ? null : (resendingId ?? this.resendingId),
        message: message,
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, rows.length, matchCount, search, filter, resendingId, message,
        error];
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
      // Search and filter both go to SQL, before the page limit. Applying the
      // filter here to the newest 300 hid every older failure the dashboard
      // was counting.
      final rows = await _repository.list(
          search: state.search, filter: state.filter);
      final matchCount = await _repository.count(
          search: state.search, filter: state.filter);
      emit(state.copyWith(
        status: ReceiptsStatus.ready,
        rows: rows,
        matchCount: matchCount,
        clearResending: true,
      ));
    } catch (e, s) {
      _log.severe('Loading receipts failed', e, s);
      emit(state.copyWith(status: ReceiptsStatus.failed, error: '$e'));
    }
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
