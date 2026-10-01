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
    this.matchCount = 0,
    this.totalMinor = 0,
    this.search = '',
    this.method,
    this.error,
  });

  final PaymentsStatus status;

  /// The newest matching payments, up to the repository's page size.
  final List<PaymentRow> rows;

  /// How many payments match the search and method in all. More than
  /// `rows.length` when the page is capped, which the header says rather
  /// than presenting the page as the whole picture.
  final int matchCount;

  /// What every matching payment adds up to, computed in SQL over
  /// [matchCount] rows — not the sum of the shown page, which quietly
  /// understated the figure once there were more payments than fit on it.
  final int totalMinor;

  final String search;
  final PaymentMethod? method;
  final String? error;

  /// Whether [rows] is only the newest part of what matched.
  bool get isCapped => matchCount > rows.length;

  PaymentsState copyWith({
    PaymentsStatus? status,
    List<PaymentRow>? rows,
    int? matchCount,
    int? totalMinor,
    String? search,
    PaymentMethod? method,
    bool clearMethod = false,
    String? error,
  }) =>
      PaymentsState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        matchCount: matchCount ?? this.matchCount,
        totalMinor: totalMinor ?? this.totalMinor,
        search: search ?? this.search,
        method: clearMethod ? null : (method ?? this.method),
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, rows.length, matchCount, totalMinor, search, method, error];
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
      // Search and method are both applied in SQL, before the page limit:
      // filtering the capped page here made older payments unfindable. The
      // totals are a second query over the same filter, so the header speaks
      // for everything that matched and not only for what fits on screen.
      final rows = await _repository.history(
          search: state.search, method: state.method);
      final totals = await _repository.historyTotals(
          search: state.search, method: state.method);

      emit(state.copyWith(
        status: PaymentsStatus.ready,
        rows: rows,
        matchCount: totals.count,
        totalMinor: totals.totalMinor,
      ));
    } catch (e, s) {
      _log.severe('Loading payments failed', e, s);
      emit(state.copyWith(status: PaymentsStatus.failed, error: '$e'));
    }
  }
}
