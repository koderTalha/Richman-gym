import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../data/payment_repository.dart';

final _log = Logger('payments');

sealed class PaymentsEvent extends Equatable {
  const PaymentsEvent();
  @override
  List<Object?> get props => const [];
}

class PaymentsRequested extends PaymentsEvent {
  const PaymentsRequested();
}

class PaymentsSearchSubmitted extends PaymentsEvent {
  const PaymentsSearchSubmitted(this.term);
  final String term;
  @override
  List<Object?> get props => [term];
}

class PaymentsMethodChanged extends PaymentsEvent {
  const PaymentsMethodChanged(this.method);
  final PaymentMethod? method;
  @override
  List<Object?> get props => [method];
}

enum PaymentsStatus { loading, ready, failed }

class PaymentsState extends Equatable {
  const PaymentsState({
    this.status = PaymentsStatus.loading,
    this.rows = const [],
    this.search = '',
    this.method,
    this.error,
  });

  final PaymentsStatus status;
  final List<PaymentRow> rows;
  final String search;
  final PaymentMethod? method;
  final String? error;

  int get totalMinor =>
      rows.fold(0, (sum, r) => sum + r.payment.amountMinor);

  PaymentsState copyWith({
    PaymentsStatus? status,
    List<PaymentRow>? rows,
    String? search,
    PaymentMethod? method,
    bool clearMethod = false,
    String? error,
  }) =>
      PaymentsState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        search: search ?? this.search,
        method: clearMethod ? null : (method ?? this.method),
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, rows.length, search, method, error];
}

class PaymentsBloc extends Bloc<PaymentsEvent, PaymentsState> {
  PaymentsBloc(this._repository) : super(const PaymentsState()) {
    on<PaymentsRequested>((_, emit) => _load(emit));
    on<PaymentsSearchSubmitted>((event, emit) {
      emit(state.copyWith(search: event.term));
      return _load(emit);
    });
    on<PaymentsMethodChanged>((event, emit) {
      emit(state.copyWith(
        method: event.method,
        clearMethod: event.method == null,
      ));
      return _load(emit);
    });
  }

  final PaymentRepository _repository;

  Future<void> _load(Emitter<PaymentsState> emit) async {
    emit(state.copyWith(status: PaymentsStatus.loading));
    try {
      final rows = await _repository.history(method: state.method);
      final term = state.search.trim().toLowerCase();

      // Filtering by member/receipt happens here rather than in SQL because it
      // spans joined tables and the result set is already capped.
      final filtered = term.isEmpty
          ? rows
          : rows
              .where((r) =>
                  r.member.fullName.toLowerCase().contains(term) ||
                  r.member.phone.contains(term) ||
                  (r.receipt?.receiptNumber.toLowerCase().contains(term) ??
                      false))
              .toList();

      emit(state.copyWith(status: PaymentsStatus.ready, rows: filtered));
    } catch (e, s) {
      _log.severe('Loading payments failed', e, s);
      emit(state.copyWith(status: PaymentsStatus.failed, error: '$e'));
    }
  }
}
