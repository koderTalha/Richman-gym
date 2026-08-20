import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/database.dart';
import '../services/logging/log_file_reader.dart';

final _log = Logger('logs');

/// The four questions the Logs screen answers.
enum LogsTab {
  /// Everything that happened, newest first.
  activity,

  /// Receipt sends, complementing the attempt history on the WhatsApp screen.
  whatsapp,

  /// Only what went wrong or was refused.
  errors,

  /// The raw file log, for when the readable version is not enough.
  technical,
}

extension LogsTabLabel on LogsTab {
  String get label => switch (this) {
        LogsTab.activity => 'Activity',
        LogsTab.whatsapp => 'WhatsApp',
        LogsTab.errors => 'Problems',
        LogsTab.technical => 'Technical',
      };

  /// Which events the tab shows. Null means every category.
  AuditCategory? get category =>
      this == LogsTab.whatsapp ? AuditCategory.whatsapp : null;

  bool get failuresOnly => this == LogsTab.errors;

  bool get readsFile => this == LogsTab.technical;
}

sealed class LogsEvent extends Equatable {
  const LogsEvent();
  @override
  List<Object?> get props => const [];
}

class LogsRequested extends LogsEvent {
  const LogsRequested();
}

class LogsTabSelected extends LogsEvent {
  const LogsTabSelected(this.tab);
  final LogsTab tab;
  @override
  List<Object?> get props => [tab];
}

class LogsSearchSubmitted extends LogsEvent {
  const LogsSearchSubmitted(this.term);
  final String term;
  @override
  List<Object?> get props => [term];
}

/// Fetches the next page rather than growing the first query, so opening the
/// screen costs the same whether the gym has been running a month or a decade.
class LogsMoreRequested extends LogsEvent {
  const LogsMoreRequested();
}

enum LogsStatus { loading, ready, failed }

class LogsState extends Equatable {
  const LogsState({
    this.status = LogsStatus.loading,
    this.tab = LogsTab.activity,
    this.events = const [],
    this.lines = const [],
    this.search = '',
    this.total = 0,
    this.loadingMore = false,
    this.error,
  });

  final LogsStatus status;
  final LogsTab tab;

  /// Audit events, for every tab but [LogsTab.technical].
  final List<AuditEvent> events;

  /// Raw log lines, for [LogsTab.technical].
  final List<String> lines;

  final String search;

  /// How many events match, so the footer can say what is not shown.
  final int total;

  final bool loadingMore;
  final String? error;

  bool get hasMore => !tab.readsFile && events.length < total;

  LogsState copyWith({
    LogsStatus? status,
    LogsTab? tab,
    List<AuditEvent>? events,
    List<String>? lines,
    String? search,
    int? total,
    bool? loadingMore,
    String? error,
    bool clearError = false,
  }) =>
      LogsState(
        status: status ?? this.status,
        tab: tab ?? this.tab,
        events: events ?? this.events,
        lines: lines ?? this.lines,
        search: search ?? this.search,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props =>
      [status, tab, events.length, lines.length, search, total, loadingMore, error];
}

/// One page of history at a time.
const _pageSize = 100;

class LogsBloc extends Bloc<LogsEvent, LogsState> {
  LogsBloc({required AuditRepository audit, LogFileReader? files})
      : _audit = audit,
        _files = files ?? LogFileReader(),
        super(const LogsState()) {
    on<LogsRequested>((_, emit) => _load(emit));
    on<LogsTabSelected>((event, emit) {
      if (event.tab == state.tab) return null;
      emit(state.copyWith(tab: event.tab, events: const [], lines: const []));
      return _load(emit);
    });
    on<LogsSearchSubmitted>((event, emit) {
      emit(state.copyWith(search: event.term));
      return _load(emit);
    });
    on<LogsMoreRequested>(_onMore);
  }

  final AuditRepository _audit;
  final LogFileReader _files;

  Future<void> _load(Emitter<LogsState> emit) async {
    emit(state.copyWith(status: LogsStatus.loading, clearError: true));

    try {
      if (state.tab.readsFile) {
        final lines = await _files.latest();
        emit(state.copyWith(
          status: LogsStatus.ready,
          lines: lines.reversed.toList(),
          total: lines.length,
        ));
        return;
      }

      final events = await _audit.recent(
        category: state.tab.category,
        failuresOnly: state.tab.failuresOnly,
        search: state.search,
        limit: _pageSize,
      );
      final total = await _audit.countMatching(
        category: state.tab.category,
        failuresOnly: state.tab.failuresOnly,
        search: state.search,
      );

      emit(state.copyWith(
          status: LogsStatus.ready, events: events, total: total));
    } catch (error, stack) {
      _log.severe('Loading the logs failed', error, stack);
      emit(state.copyWith(
        status: LogsStatus.failed,
        error: 'The log could not be read.',
      ));
    }
  }

  Future<void> _onMore(
    LogsMoreRequested event,
    Emitter<LogsState> emit,
  ) async {
    if (state.loadingMore || !state.hasMore) return;
    emit(state.copyWith(loadingMore: true));

    try {
      final next = await _audit.recent(
        category: state.tab.category,
        failuresOnly: state.tab.failuresOnly,
        search: state.search,
        limit: _pageSize,
        offset: state.events.length,
      );

      emit(state.copyWith(
        events: [...state.events, ...next],
        loadingMore: false,
      ));
    } catch (error, stack) {
      _log.severe('Loading more log events failed', error, stack);
      emit(state.copyWith(loadingMore: false));
    }
  }

  /// The folder the technical logs live in, for the "open folder" action.
  Future<Directory> logDirectory() => _files.directory();
}
