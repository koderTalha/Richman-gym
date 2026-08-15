import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../data/member_repository.dart';
import '../domain/phone.dart';

final _log = Logger('members');

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
    this.confirmSharedPhone = false,
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

  /// Set once the operator has been shown who else is on this number and has
  /// said to go ahead anyway.
  final bool confirmSharedPhone;

  @override
  List<Object?> get props =>
      [fullName, rawPhone, planId, joiningDate, confirmSharedPhone];
}

enum MemberFormStatus {
  loading,
  ready,
  submitting,

  /// The number belongs to somebody else already. Legitimate for relatives,
  /// far more often a typo, so the operator is shown who and asked.
  confirmSharedPhone,

  saved,
  failed,
}

class MemberFormState extends Equatable {
  const MemberFormState({
    this.status = MemberFormStatus.loading,
    this.plans = const [],
    this.existing,
    this.sharingPhone = const [],
    this.error,
  });

  final MemberFormStatus status;
  final List<MembershipPlan> plans;
  final MemberRow? existing;

  /// Members already registered on the number just entered.
  final List<Member> sharingPhone;

  final String? error;

  MemberFormState copyWith({
    MemberFormStatus? status,
    List<MembershipPlan>? plans,
    MemberRow? existing,
    List<Member>? sharingPhone,
    String? error,
  }) =>
      MemberFormState(
        status: status ?? this.status,
        plans: plans ?? this.plans,
        existing: existing ?? this.existing,
        sharingPhone: sharingPhone ?? const [],
        error: error,
      );

  @override
  List<Object?> get props =>
      [status, plans.length, existing?.id, sharingPhone.length, error];
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
    // plansFor, not plans: a member can be on a plan the gym has stopped
    // selling, and offering only the active ones left the form holding a plan
    // its own dropdown did not list — which made the member uneditable.
    final plans = await _repository.plansFor(memberId);
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

    final sharing =
        await _repository.membersOnPhone(normalized, excluding: memberId);

    // The same person on the same number is a duplicate, not a family: reject.
    final samePerson = matchByName(sharing, event.fullName);
    if (samePerson != null) {
      emit(state.copyWith(
        status: MemberFormStatus.failed,
        error: '${samePerson.fullName} (#${samePerson.memberCode}) is already '
            'registered on this number.',
      ));
      return;
    }

    // A different name on a number already in use is legitimate — one brother
    // asked to be registered under the other's phone — but a mistyped digit
    // looks exactly the same, and silently accepting it points somebody else's
    // WhatsApp receipts at the wrong handset for good. So the operator is
    // shown whose number it is and has to say yes.
    if (sharing.isNotEmpty && !event.confirmSharedPhone) {
      emit(state.copyWith(
        status: MemberFormStatus.confirmSharedPhone,
        sharingPhone: sharing,
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
    } catch (e, s) {
      _log.severe('Saving member failed', e, s);
      emit(state.copyWith(
        status: MemberFormStatus.failed,
        error: 'Could not save: $e',
      ));
    }
  }
}
