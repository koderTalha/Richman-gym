import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/member_repository.dart';
import '../data/payment_repository.dart';
import '../services/billing_cycle_service.dart';

sealed class MemberDetailEvent extends Equatable {
  const MemberDetailEvent();
  @override
  List<Object?> get props => const [];
}

class MemberDetailRequested extends MemberDetailEvent {
  const MemberDetailRequested({this.afterChange = false});

  /// True when this reload follows something the screen just changed — an
  /// edit saved, a payment recorded, edited, deleted or cleared, the billing
  /// day moved, billing restarted. It is what tells the Members list behind
  /// to refresh on the way back; see [MemberDetailState.changed].
  final bool afterChange;
  @override
  List<Object?> get props => [afterChange];
}

class MemberActiveToggled extends MemberDetailEvent {
  const MemberActiveToggled({required this.active, this.restartFrom});
  final bool active;

  /// When reactivating, the day the member came back: billing restarts from
  /// it — see `BillingCycleService.restartBilling`. Null leaves their billing
  /// on the cadence it was on.
  final DateTime? restartFrom;
  @override
  List<Object?> get props => [active, restartFrom];
}

/// Remove the member outright. Refused by the repository while any payment is
/// recorded against them.
class MemberDeleteRequested extends MemberDetailEvent {
  const MemberDeleteRequested();
}

enum MemberDetailStatus { loading, ready, notFound, deleting, deleted }

class MemberDetailState extends Equatable {
  const MemberDetailState({
    this.status = MemberDetailStatus.loading,
    this.member,
    this.payments = const [],
    this.changed = false,
    this.error,
  });

  final MemberDetailStatus status;
  final MemberRow? member;
  final List<PaymentRow> payments;

  /// True once something changed, so the list behind can refresh on pop.
  final bool changed;

  /// Owner-facing, e.g. why a deletion was refused.
  final String? error;

  /// Deleting is only offered while nothing financial points at the member.
  /// The repository enforces this too; this is what greys the button out and
  /// lets it explain itself before it is pressed.
  bool get canDelete =>
      status == MemberDetailStatus.ready && payments.isEmpty;

  bool get busy => status == MemberDetailStatus.deleting;

  MemberDetailState copyWith({
    MemberDetailStatus? status,
    MemberRow? member,
    List<PaymentRow>? payments,
    bool? changed,
    String? error,
    bool clearError = false,
  }) =>
      MemberDetailState(
        status: status ?? this.status,
        member: member ?? this.member,
        payments: payments ?? this.payments,
        changed: changed ?? this.changed,
        error: clearError ? null : (error ?? this.error),
      );

  /// The loaded row and payments themselves, not a summary of them. With only
  /// the member's id and status and the payment count here, a reload after an
  /// edit compared equal to the state before it — same member, same status,
  /// same number of payments — and bloc dropped it as a duplicate: a renamed
  /// member kept their old name on screen, and an edited amount its old
  /// figure, until the screen was left and opened again. Neither type defines
  /// equality, so every completed load counts as new, which is what a reload
  /// is for.
  @override
  List<Object?> get props => [status, member, payments, changed, error];
}

class MemberDetailBloc extends Bloc<MemberDetailEvent, MemberDetailState> {
  MemberDetailBloc({
    required MemberRepository memberRepository,
    required PaymentRepository paymentRepository,
    required this.memberId,
    required this.actorId,
    BillingCycleService? cycles,
  })  : _members = memberRepository,
        _payments = paymentRepository,
        _cycles = cycles ?? BillingCycleService(memberRepository.db),
        super(const MemberDetailState()) {
    on<MemberDetailRequested>((event, emit) {
      // Set before the reload rather than after it, so a pop while the reload
      // is still running already reports the change.
      if (event.afterChange) emit(state.copyWith(changed: true));
      return _load(emit);
    });
    on<MemberActiveToggled>(_onToggleActive);
    on<MemberDeleteRequested>(_onDelete);
  }

  final MemberRepository _members;
  final PaymentRepository _payments;
  final BillingCycleService _cycles;
  final int memberId;

  /// Who is signed in, recorded against everything this bloc does.
  final int actorId;

  Future<void> _load(Emitter<MemberDetailState> emit) async {
    final member = await _members.byId(memberId);
    if (member == null) {
      emit(state.copyWith(status: MemberDetailStatus.notFound));
      return;
    }
    final payments = await _payments.history(memberId: memberId);
    emit(state.copyWith(
      status: MemberDetailStatus.ready,
      member: member,
      payments: payments,
      clearError: true,
    ));
  }

  Future<void> _onDelete(
    MemberDeleteRequested event,
    Emitter<MemberDetailState> emit,
  ) async {
    if (state.busy) return;
    emit(state.copyWith(status: MemberDetailStatus.deleting, clearError: true));

    final result = await _members.deleteMember(id: memberId, actorId: actorId);

    switch (result) {
      case MemberDeleted():
        emit(state.copyWith(
            status: MemberDetailStatus.deleted, changed: true));
      case MemberDeleteRefused(:final message):
        // Reload first — the payments the refusal is about are worth showing —
        // then put the reason back, since the reload clears it.
        await _load(emit);
        emit(state.copyWith(error: message));
      case MemberDeleteNotFound():
        emit(state.copyWith(
            status: MemberDetailStatus.deleted, changed: true));
    }
  }

  Future<void> _onToggleActive(
    MemberActiveToggled event,
    Emitter<MemberDetailState> emit,
  ) async {
    await _members.setActive(memberId, event.active, actorId: actorId);

    // Applied after the reactivation, not instead of it: a restart refused
    // here (the dialog previewed it, so only a change made in between could
    // cause that) must still leave the member active, with the reason shown.
    String? refused;
    final from = event.restartFrom;
    if (event.active && from != null) {
      final result = await _cycles.restartBilling(
          memberId: memberId, from: from, actorId: actorId);
      if (result is BillingRestartRefused) refused = result.reason;
    }

    emit(state.copyWith(changed: true));
    await _load(emit);
    if (refused != null) emit(state.copyWith(error: refused));
  }
}
