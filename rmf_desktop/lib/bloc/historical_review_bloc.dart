import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/database.dart';
import '../domain/money.dart';
import '../services/historical_pricing_review.dart';

final _log = Logger('billing');

sealed class HistoricalReviewEvent extends Equatable {
  const HistoricalReviewEvent();
  @override
  List<Object?> get props => const [];
}

class HistoricalReviewRequested extends HistoricalReviewEvent {
  const HistoricalReviewRequested();
}

/// The owner approved lowering [periodId] to [correctedAmountMinor].
class HistoricalReviewCorrected extends HistoricalReviewEvent {
  const HistoricalReviewCorrected({
    required this.periodId,
    required this.correctedAmountMinor,
    required this.reason,
  });

  final int periodId;
  final int correctedAmountMinor;
  final String reason;

  @override
  List<Object?> get props => [periodId, correctedAmountMinor, reason];
}

/// The owner looked at [periodId] and decided the bill stands.
class HistoricalReviewKept extends HistoricalReviewEvent {
  const HistoricalReviewKept({required this.periodId, required this.reason});

  final int periodId;
  final String reason;

  @override
  List<Object?> get props => [periodId, reason];
}

/// The owner typed into the search box — matched against the member's name
/// and member code, the same two fields the Members screen searches.
class HistoricalReviewSearchChanged extends HistoricalReviewEvent {
  const HistoricalReviewSearchChanged(this.term);
  final String term;
  @override
  List<Object?> get props => [term];
}

/// The owner picked a plan chip, or "All" (null) to clear it.
class HistoricalReviewPlanFilterChanged extends HistoricalReviewEvent {
  const HistoricalReviewPlanFilterChanged(this.plan);
  final String? plan;
  @override
  List<Object?> get props => [plan];
}

enum HistoricalReviewStatus { loading, ready, failed }

class HistoricalReviewState extends Equatable {
  const HistoricalReviewState({
    this.status = HistoricalReviewStatus.loading,
    this.candidates = const [],
    this.searchTerm = '',
    this.planFilter,
    this.message,
    this.error,
  });

  final HistoricalReviewStatus status;

  /// Every candidate the detector found, unfiltered. Search and the plan
  /// filter only ever narrow what is *shown* — the underlying list a
  /// correction or a keep resolves against is always this one.
  final List<HistoricalPricingCandidate> candidates;

  final String searchTerm;

  /// The plan chip selected, or null for "All".
  final String? planFilter;

  /// What the last decision did, e.g. "August corrected for Ali Raza." Shown
  /// once as a snack bar; not part of comparing states meaningfully beyond
  /// that.
  final String? message;

  final String? error;

  /// The plans worth offering as chips — only the ones a candidate is
  /// actually on, so the row never lists a plan nobody here needs reviewing.
  List<String> get plansInCandidates =>
      candidates.map((c) => c.currentPlanName).toSet().toList()..sort();

  List<HistoricalPricingCandidate> get visibleCandidates {
    final term = searchTerm.trim().toLowerCase();
    return [
      for (final candidate in candidates)
        if ((planFilter == null || candidate.currentPlanName == planFilter) &&
            (term.isEmpty ||
                candidate.member.fullName.toLowerCase().contains(term) ||
                candidate.member.memberCode.toString().contains(term)))
          candidate,
    ];
  }

  bool get isEmpty =>
      status == HistoricalReviewStatus.ready && candidates.isEmpty;

  /// Every candidate is filtered out, but there were candidates to begin
  /// with — a different message from [isEmpty], because "nothing needs
  /// review" and "nothing matches what you typed" are not the same news.
  bool get noMatches =>
      status == HistoricalReviewStatus.ready &&
      candidates.isNotEmpty &&
      visibleCandidates.isEmpty;

  HistoricalReviewState copyWith({
    HistoricalReviewStatus? status,
    List<HistoricalPricingCandidate>? candidates,
    String? searchTerm,
    String? planFilter,
    bool clearPlanFilter = false,
    String? message,
    String? error,
  }) =>
      HistoricalReviewState(
        status: status ?? this.status,
        candidates: candidates ?? this.candidates,
        searchTerm: searchTerm ?? this.searchTerm,
        planFilter: clearPlanFilter ? null : (planFilter ?? this.planFilter),
        message: message,
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, candidates.length, searchTerm, planFilter, message, error];
}

/// Drives the "Historical Billing Review" screen.
///
/// Every candidate here is a cycle `cycle_repricing.dart` deliberately would
/// not touch — it has already ended — and everything this bloc does to one is
/// explicit, reviewed and auditable. See `historical_pricing_review.dart` for
/// the rules a candidate has to meet before it is even offered, and for why
/// neither action here can ever raise a historical bill or forgive a genuine
/// shortfall.
class HistoricalReviewBloc
    extends Bloc<HistoricalReviewEvent, HistoricalReviewState> {
  HistoricalReviewBloc({
    required AppDatabase db,
    required this.actorId,
    AuditRepository? audit,
  })  : _db = db,
        _audit = audit ?? AuditRepository(db),
        super(const HistoricalReviewState()) {
    on<HistoricalReviewRequested>((_, emit) => _load(emit));
    on<HistoricalReviewCorrected>(_onCorrected);
    on<HistoricalReviewKept>(_onKept);
    on<HistoricalReviewSearchChanged>(
        (event, emit) => emit(state.copyWith(searchTerm: event.term)));
    on<HistoricalReviewPlanFilterChanged>((event, emit) => emit(
        state.copyWith(
            planFilter: event.plan, clearPlanFilter: event.plan == null)));
  }

  final AppDatabase _db;
  final AuditRepository _audit;

  /// Who is signed in, recorded against every decision this bloc makes.
  final int? actorId;

  Future<void> _load(Emitter<HistoricalReviewState> emit) async {
    try {
      final candidates = await detectHistoricalPricingAnomalies(_db);
      emit(state.copyWith(
        status: HistoricalReviewStatus.ready,
        candidates: candidates,
      ));
    } catch (error, stack) {
      _log.severe('Loading the historical billing review failed', error, stack);
      emit(state.copyWith(
        status: HistoricalReviewStatus.failed,
        error: 'Could not load the review. See the Logs screen.',
      ));
    }
  }

  Future<void> _onCorrected(
    HistoricalReviewCorrected event,
    Emitter<HistoricalReviewState> emit,
  ) async {
    final candidate = state.candidates
        .where((c) => c.period.id == event.periodId)
        .firstOrNull;

    final result = await applyBillingCorrection(
      _db,
      periodId: event.periodId,
      correctedAmountMinor: event.correctedAmountMinor,
      reason: event.reason,
      actorId: actorId,
      audit: _audit,
    );

    switch (result) {
      case BillingCorrectionApplied():
        await _load(emit);
        if (candidate != null) {
          emit(state.copyWith(
            message: '${candidate.member.fullName}: '
                '${candidate.periodLabel} corrected to '
                '${formatMinorUnits(event.correctedAmountMinor)}.',
          ));
        }
      case BillingCorrectionRefused(:final reason):
        emit(state.copyWith(error: reason));
    }
  }

  Future<void> _onKept(
    HistoricalReviewKept event,
    Emitter<HistoricalReviewState> emit,
  ) async {
    final candidate = state.candidates
        .where((c) => c.period.id == event.periodId)
        .firstOrNull;

    await keepHistoricalPrice(
      _db,
      periodId: event.periodId,
      reason: event.reason,
      actorId: actorId,
      audit: _audit,
    );

    await _load(emit);
    if (candidate != null) {
      emit(state.copyWith(
        message: '${candidate.member.fullName}: '
            '${candidate.periodLabel} kept at '
            '${formatMinorUnits(candidate.billedMinor)}.',
      ));
    }
  }
}
