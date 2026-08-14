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
    this.error,
  });

  final MembersStatus status;
  final List<MemberRow> rows;
  final String search;
  final MemberFilter filter;
  final String? error;

  MembersState copyWith({
    MembersStatus? status,
    List<MemberRow>? rows,
    String? search,
    MemberFilter? filter,
    String? error,
  }) =>
      MembersState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        search: search ?? this.search,
        filter: filter ?? this.filter,
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, rows.map((r) => r.id).toList(), search, filter, error];
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
      final rows = await _repository.list(
        search: state.search,
        filter: state.filter,
      );
      emit(state.copyWith(status: MembersStatus.ready, rows: rows));
    } catch (e, s) {
      _log.severe('Loading members failed', e, s);
      emit(state.copyWith(status: MembersStatus.failed, error: '$e'));
    }
  }
}
