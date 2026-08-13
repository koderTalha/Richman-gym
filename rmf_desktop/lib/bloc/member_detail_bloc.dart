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

enum MemberDetailStatus { loading, ready, notFound }

class MemberDetailState extends Equatable {
  const MemberDetailState({
    this.status = MemberDetailStatus.loading,
    this.member,
    this.payments = const [],
    this.changed = false,
  });

  final MemberDetailStatus status;
  final MemberRow? member;
  final List<PaymentRow> payments;

  /// True once something changed, so the list behind can refresh on pop.
  final bool changed;

  MemberDetailState copyWith({
    MemberDetailStatus? status,
    MemberRow? member,
    List<PaymentRow>? payments,
    bool? changed,
  }) =>
      MemberDetailState(
        status: status ?? this.status,
        member: member ?? this.member,
        payments: payments ?? this.payments,
        changed: changed ?? this.changed,
      );

  @override
  List<Object?> get props =>
      [status, member?.id, member?.status, payments.length, changed];
}

class MemberDetailBloc extends Bloc<MemberDetailEvent, MemberDetailState> {
  MemberDetailBloc({
    required MemberRepository memberRepository,
    required PaymentRepository paymentRepository,
    required this.memberId,
  })  : _members = memberRepository,
        _payments = paymentRepository,
        super(const MemberDetailState()) {
    on<MemberDetailRequested>((_, emit) => _load(emit));
    on<MemberActiveToggled>(_onToggleActive);
  }

  final MemberRepository _members;
  final PaymentRepository _payments;
  final int memberId;

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
    ));
  }

  Future<void> _onToggleActive(
    MemberActiveToggled event,
    Emitter<MemberDetailState> emit,
  ) async {
    await _members.setActive(memberId, event.active);
    emit(state.copyWith(changed: true));
    await _load(emit);
  }
}
