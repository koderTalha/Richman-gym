import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart' show MembershipPlan;
import '../data/report_repository.dart';
import '../domain/monthly_report.dart';

final _log = Logger('reports');

sealed class ReportsEvent extends Equatable {
  const ReportsEvent();
  @override
  List<Object?> get props => const [];
}

/// Load (or reload) the month and filters already chosen.
class ReportsRequested extends ReportsEvent {
  const ReportsRequested();
}

class ReportsMonthChanged extends ReportsEvent {
  const ReportsMonthChanged(this.month);
  final ReportMonth month;
  @override
  List<Object?> get props => [month];
}

class ReportsFiltersChanged extends ReportsEvent {
  const ReportsFiltersChanged(this.filters);
  final ReportFilters filters;
  @override
  List<Object?> get props => [filters];
}

class ReportsFiltersReset extends ReportsEvent {
  const ReportsFiltersReset();
}

enum ReportsStatus { loading, ready, failed }

class ReportsState extends Equatable {
  const ReportsState({
    required this.month,
    required this.currentMonth,
    this.firstMonth,
    this.filters = const ReportFilters(),
    this.status = ReportsStatus.loading,
    this.report,
    this.plans = const [],
    this.error,
  });

  final ReportMonth month;

  /// The latest month there is anything to report: this one.
  final ReportMonth currentMonth;

  /// The earliest, or null for a gym with no records yet.
  final ReportMonth? firstMonth;
  final ReportFilters filters;
  final ReportsStatus status;

  /// The last report built. Kept while the next one loads, so changing a
  /// filter dims the page rather than blanking it.
  final MonthlyReport? report;
  final List<MembershipPlan> plans;
  final String? error;

  bool get canGoBack => firstMonth != null && month.isAfter(firstMonth!);
  bool get canGoForward => month.isBefore(currentMonth);

  ReportsState copyWith({
    ReportMonth? month,
    ReportMonth? Function()? firstMonth,
    ReportFilters? filters,
    ReportsStatus? status,
    MonthlyReport? report,
    List<MembershipPlan>? plans,
    String? Function()? error,
  }) =>
      ReportsState(
        month: month ?? this.month,
        currentMonth: currentMonth,
        firstMonth: firstMonth == null ? this.firstMonth : firstMonth(),
        filters: filters ?? this.filters,
        status: status ?? this.status,
        report: report ?? this.report,
        plans: plans ?? this.plans,
        error: error == null ? this.error : error(),
      );

  @override
  List<Object?> get props =>
      [month, firstMonth, filters, status, report, plans, error];
}

class ReportsBloc extends Bloc<ReportsEvent, ReportsState> {
  ReportsBloc(this._reports)
      : super(ReportsState(
          month: _reports.currentMonth,
          currentMonth: _reports.currentMonth,
        )) {
    on<ReportsRequested>((_, emit) => _load(emit));
    on<ReportsMonthChanged>((event, emit) {
      final month = event.month.isAfter(state.currentMonth)
          ? state.currentMonth
          : event.month;
      if (month == state.month) return Future.value();
      emit(state.copyWith(month: month));
      return _load(emit);
    });
    on<ReportsFiltersChanged>((event, emit) {
      if (event.filters == state.filters) return Future.value();
      emit(state.copyWith(filters: event.filters));
      return _load(emit);
    });
    on<ReportsFiltersReset>((_, emit) {
      if (state.filters.isEmpty) return Future.value();
      emit(state.copyWith(filters: const ReportFilters()));
      return _load(emit);
    });
  }

  final ReportRepository _reports;

  /// Bumped by every load. A month flicked through quickly starts several
  /// builds at once; only the newest is allowed to land, or a slow, stale one
  /// finishing last would leave the page showing a month nobody chose.
  int _generation = 0;

  Future<void> _load(Emitter<ReportsState> emit) async {
    final generation = ++_generation;
    final month = state.month;
    final filters = state.filters;
    emit(state.copyWith(status: ReportsStatus.loading, error: () => null));
    try {
      final plans = await _reports.plans();
      final first = await _reports.firstMonthOnRecord();
      final report = await _reports.build(month, filters: filters);
      if (generation != _generation) return;
      emit(state.copyWith(
        status: ReportsStatus.ready,
        report: report,
        plans: plans,
        firstMonth: () => first,
      ));
    } catch (e, s) {
      if (generation != _generation) return;
      _log.severe('Building the ${month.label} report failed', e, s);
      emit(state.copyWith(status: ReportsStatus.failed, error: () => '$e'));
    }
  }
}
