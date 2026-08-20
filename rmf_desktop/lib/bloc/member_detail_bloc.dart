import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/member_repository.dart';
import '../data/payment_repository.dart';

sealed class MemberDetailEvent extends Equatable {
  const MemberDetailEvent();
  @override
  List<Object?> get props => const [];
}

class MemberDetailRequested extends MemberDetailEvent {
  const MemberDetailRequested();
}

class MemberActiveToggled extends MemberDetailEvent {
  const MemberActiveToggled({required this.active});
  final bool active;
  @override
  List<Object?> get props => [active];
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

  @override
  List<Object?> get props =>
      [status, member?.id, member?.status, payments.length, changed, error];
}

class MemberDetailBloc extends Bloc<MemberDetailEvent, MemberDetailState> {
  MemberDetailBloc({
    required MemberRepository memberRepository,
    required PaymentRepository paymentRepository,
    required this.memberId,
    required this.actorId,
  })  : _members = memberRepository,
        _payments = paymentRepository,
        super(const MemberDetailState()) {
    on<MemberDetailRequested>((_, emit) => _load(emit));
    on<MemberActiveToggled>(_onToggleActive);
    on<MemberDeleteRequested>(_onDelete);
  }

  final MemberRepository _members;
  final PaymentRepository _payments;
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
    emit(state.copyWith(changed: true));
    await _load(emit);
  }
}
