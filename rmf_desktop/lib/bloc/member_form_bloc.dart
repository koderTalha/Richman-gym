import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database.dart';
import '../data/member_repository.dart';
import '../domain/phone.dart';

sealed class MemberFormEvent extends Equatable {
  const MemberFormEvent();
  @override
  List<Object?> get props => const [];
}

class MemberFormLoaded extends MemberFormEvent {
  const MemberFormLoaded();
}

class MemberFormSubmitted extends MemberFormEvent {
  const MemberFormSubmitted({
    required this.fullName,
    required this.rawPhone,
    required this.planId,
    required this.joiningDate,
    this.email,
    this.gender,
    this.address,
    this.emergencyContact,
    this.feeOverrideMinor,
  });

  final String fullName;
  final String rawPhone;
  final int planId;
  final DateTime joiningDate;
  final String? email;
  final String? gender;
  final String? address;
  final String? emergencyContact;
  final int? feeOverrideMinor;

  @override
  List<Object?> get props => [fullName, rawPhone, planId, joiningDate];
}

enum MemberFormStatus { loading, ready, submitting, saved, failed }

class MemberFormState extends Equatable {
  const MemberFormState({
    this.status = MemberFormStatus.loading,
    this.plans = const [],
    this.existing,
    this.error,
  });

  final MemberFormStatus status;
  final List<MembershipPlan> plans;
  final MemberRow? existing;
  final String? error;

  MemberFormState copyWith({
    MemberFormStatus? status,
    List<MembershipPlan>? plans,
    MemberRow? existing,
    String? error,
  }) =>
      MemberFormState(
        status: status ?? this.status,
        plans: plans ?? this.plans,
        existing: existing ?? this.existing,
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, plans.length, existing?.id, error];
}

class MemberFormBloc extends Bloc<MemberFormEvent, MemberFormState> {
  MemberFormBloc({required MemberRepository repository, this.memberId})
      : _repository = repository,
        super(const MemberFormState()) {
    on<MemberFormLoaded>((_, emit) => _load(emit));
    on<MemberFormSubmitted>(_onSubmit);
  }

  final MemberRepository _repository;
  final int? memberId;

  bool get isEditing => memberId != null;

  Future<void> _load(Emitter<MemberFormState> emit) async {
    final plans = await _repository.plans();
    final existing = memberId == null ? null : await _repository.byId(memberId!);

    emit(state.copyWith(
      status: MemberFormStatus.ready,
      plans: plans,
      existing: existing,
    ));
  }

  Future<void> _onSubmit(
    MemberFormSubmitted event,
    Emitter<MemberFormState> emit,
  ) async {
    emit(state.copyWith(status: MemberFormStatus.submitting));

    final normalized = normalizePhone(event.rawPhone);
    if (normalized == null) {
      emit(state.copyWith(
        status: MemberFormStatus.failed,
        error: 'Enter a valid phone number.',
      ));
      return;
    }

    // A phone number identifies a member for WhatsApp, so it must be unique.
    final clash = await _repository.findByPhone(normalized);
    if (clash != null && clash.id != memberId) {
      emit(state.copyWith(
        status: MemberFormStatus.failed,
        error: '${clash.fullName} (#${clash.memberCode}) already uses this number.',
      ));
      return;
    }

    final joining = DateTime.utc(
      event.joiningDate.year,
      event.joiningDate.month,
      event.joiningDate.day,
    );

    try {
      if (isEditing) {
        await _repository.update(
          id: memberId!,
          fullName: event.fullName,
          phone: normalized,
          phoneRaw: event.rawPhone,
          email: event.email,
          gender: event.gender,
          address: event.address,
          emergencyContact: event.emergencyContact,
          planId: event.planId,
          feeOverrideMinor: event.feeOverrideMinor,
          joiningDate: joining,
        );
      } else {
        await _repository.create(
          fullName: event.fullName,
          phone: normalized,
          phoneRaw: event.rawPhone,
          email: event.email,
          gender: event.gender,
          address: event.address,
          emergencyContact: event.emergencyContact,
          planId: event.planId,
          feeOverrideMinor: event.feeOverrideMinor,
          joiningDate: joining,
        );
      }
      emit(state.copyWith(status: MemberFormStatus.saved));
    } catch (e) {
      emit(state.copyWith(
        status: MemberFormStatus.failed,
        error: 'Could not save: $e',
      ));
    }
  }
}
