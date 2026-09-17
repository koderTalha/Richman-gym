import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/member_repository.dart';

final _log = Logger('members');

sealed class MembersEvent extends Equatable {
  const MembersEvent();
  @override
  List<Object?> get props => const [];
}

class MembersRequested extends MembersEvent {
  const MembersRequested();
}

class MembersSearchSubmitted extends MembersEvent {
  const MembersSearchSubmitted(this.term);
  final String term;
  @override
  List<Object?> get props => [term];
}

class MembersFilterChanged extends MembersEvent {
  const MembersFilterChanged(this.filter);
  final MemberFilter filter;
  @override
  List<Object?> get props => [filter];
}

enum MembersStatus { loading, ready, failed }

class MembersState extends Equatable {
  const MembersState({
    this.status = MembersStatus.loading,
    this.rows = const [],
    this.search = '',
    this.filter = MemberFilter.all,
    this.filterCounts = const {},
    this.error,
  });

  final MembersStatus status;
  final List<MemberRow> rows;
  final String search;
  final MemberFilter filter;

  /// How many members each chip would show for the current search — see
  /// `MemberRepository.filterCounts`. Empty only before the first load
  /// completes; every chip reads 0 rather than showing nothing.
  final Map<MemberFilter, int> filterCounts;

  final String? error;

  MembersState copyWith({
    MembersStatus? status,
    List<MemberRow>? rows,
    String? search,
    MemberFilter? filter,
    Map<MemberFilter, int>? filterCounts,
    String? error,
  }) =>
      MembersState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        search: search ?? this.search,
        filter: filter ?? this.filter,
        filterCounts: filterCounts ?? this.filterCounts,
        error: error,
      );

  @override
  List<Object?> get props => [
        status,
        rows.map((r) => r.id).toList(),
        search,
        filter,
        filterCounts,
        error,
      ];
}

class MembersBloc extends Bloc<MembersEvent, MembersState> {
  MembersBloc(this._repository) : super(const MembersState()) {
    on<MembersRequested>((_, emit) => _load(emit));
    on<MembersSearchSubmitted>((event, emit) {
      emit(state.copyWith(search: event.term));
      return _load(emit);
    });
    on<MembersFilterChanged>((event, emit) {
      emit(state.copyWith(filter: event.filter));
      return _load(emit);
    });
  }

  final MemberRepository _repository;

  Future<void> _load(Emitter<MembersState> emit) async {
    emit(state.copyWith(status: MembersStatus.loading));
    try {
      // One fetch for both the visible rows and every chip's count — see
      // `MemberRepository.listWithCounts` — so a chip's number is never one
      // search behind the list underneath it, and a keystroke does not pay
      // for the same join twice.
      final result = await _repository.listWithCounts(
        search: state.search,
        filter: state.filter,
      );
      emit(state.copyWith(
        status: MembersStatus.ready,
        rows: result.rows,
        filterCounts: result.counts,
      ));
    } catch (e, s) {
      _log.severe('Loading members failed', e, s);
      emit(state.copyWith(status: MembersStatus.failed, error: '$e'));
    }
  }
}
