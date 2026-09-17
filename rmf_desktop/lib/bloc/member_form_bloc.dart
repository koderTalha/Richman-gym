import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../data/member_repository.dart';
import '../domain/phone.dart';
import '../services/whatsapp/member_welcome_service.dart';

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
    this.actorId,
    this.effectiveFrom,
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

  /// When a fee change this save makes takes effect. Null means today — what
  /// every save meant before the owner could choose otherwise. See
  /// `_EffectiveFromPicker` and `MemberRepository.update`.
  final DateTime? effectiveFrom;

  /// Set once the operator has been shown who else is on this number and has
  /// said to go ahead anyway.
  final bool confirmSharedPhone;

  /// Who is signed in, so the welcome message is attributable in the log.
  final int? actorId;

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
    this.welcome,
  });

  final MemberFormStatus status;
  final List<MembershipPlan> plans;
  final MemberRow? existing;

  /// Members already registered on the number just entered.
  final List<Member> sharingPhone;

  final String? error;

  /// What happened to the new member's welcome message. Null when nothing was
  /// attempted — every edit, and any save that has not finished.
  final WelcomeOutcome? welcome;

  MemberFormState copyWith({
    MemberFormStatus? status,
    List<MembershipPlan>? plans,
    MemberRow? existing,
    List<Member>? sharingPhone,
    String? error,
    WelcomeOutcome? welcome,
  }) =>
      MemberFormState(
        status: status ?? this.status,
        plans: plans ?? this.plans,
        existing: existing ?? this.existing,
        sharingPhone: sharingPhone ?? const [],
        error: error,
        welcome: welcome,
      );

  @override
  List<Object?> get props => [
        status,
        plans.length,
        existing?.id,
        sharingPhone.length,
        error,
        welcome,
      ];
}

class MemberFormBloc extends Bloc<MemberFormEvent, MemberFormState> {
  MemberFormBloc({
    required MemberRepository repository,
    this.memberId,
    MemberWelcomeService? welcome,
  })  : _repository = repository,
        _welcome = welcome,
        super(const MemberFormState()) {
    on<MemberFormLoaded>((_, emit) => _load(emit));
    on<MemberFormSubmitted>(_onSubmit);
  }

  final MemberRepository _repository;
  final int? memberId;

  /// Null in the screens and tests that have no messaging wired up; a new
  /// member is then simply saved without a welcome message.
  final MemberWelcomeService? _welcome;

  /// True from the moment a submit is accepted until it has finished.
  ///
  /// A field rather than a look at [state]: bloc handles events concurrently,
  /// so the load that populates the plan list can — and does — emit `ready`
  /// over the `submitting` a submit already set, and the next submit would read
  /// that and go straight through. This is set before the first await and is
  /// nobody else's to change.
  bool _submitting = false;

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
    // Two taps on Save half a second apart would otherwise both get this far
    // and create the member twice — and send two welcome messages with them.
    // The button is disabled while this runs, but a keyboard repeat, a rebuilt
    // widget or a re-dispatched event is not the button.
    if (_submitting) {
      _log.info('Ignoring a repeat submit; the first one is still running');
      return;
    }
    _submitting = true;

    try {
      await _submit(event, emit);
    } finally {
      _submitting = false;
    }
  }

  Future<void> _submit(
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
          actorId: event.actorId,
          effectiveFrom: event.effectiveFrom,
        );
        emit(state.copyWith(status: MemberFormStatus.saved));
        return;
      }

      final newMemberId = await _repository.create(
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

      // --- Past this line the member is saved -----------------------------
      // Whatever happens to the message, the member stays. The send is awaited
      // rather than left running so the screen can say which of the two
      // happened, but its result never turns a saved member into a failure.
      final welcome = await _sendWelcome(newMemberId, actorId: event.actorId);

      // The form can be closed while a send is in flight. The member is saved
      // either way; there is just no longer a screen to tell.
      if (isClosed) return;

      emit(state.copyWith(
        status: MemberFormStatus.saved,
        welcome: welcome,
      ));
    } catch (e, s) {
      _log.severe('Saving member failed', e, s);
      if (isClosed) return;
      emit(state.copyWith(
        status: MemberFormStatus.failed,
        error: e is ArgumentError && e.name == 'effectiveFrom'
            ? "That date is before the member's current plan started. Choose "
                'a later date, or leave it as Today.'
            : 'Could not save: $e',
      ));
    }
  }

  /// Never throws and never rethrows: this runs after the member is committed.
  Future<WelcomeOutcome?> _sendWelcome(int memberId, {int? actorId}) async {
    final welcome = _welcome;
    if (welcome == null) return null;

    try {
      return await welcome.sendWelcome(memberId: memberId, actorId: actorId);
    } catch (e, s) {
      _log.severe('The welcome message could not be sent', e, s);
      return WelcomeFailed('$e');
    }
  }
}
