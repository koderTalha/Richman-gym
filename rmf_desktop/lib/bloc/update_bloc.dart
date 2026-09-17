import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/app_version.dart';
import '../services/update/connection_diagnostics.dart';
import '../services/update/update_service.dart';

sealed class UpdateEvent extends Equatable {
  const UpdateEvent();
  @override
  List<Object?> get props => const [];
}

class UpdateCheckRequested extends UpdateEvent {
  const UpdateCheckRequested({this.force = false});

  /// True when the owner pressed "Check for updates" — that ignores the
  /// once-a-day rule, because being told "already checked today" is not an
  /// answer to a button press.
  final bool force;

  @override
  List<Object?> get props => [force];
}

class UpdateInstallRequested extends UpdateEvent {
  const UpdateInstallRequested();
}

/// "Later" — stop showing the banner for this version.
class UpdateDismissed extends UpdateEvent {
  const UpdateDismissed();
}

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,

  /// Backing up, downloading and verifying.
  installing,

  /// The installer is running; the app is about to close.
  launched,

  failed,
}

class UpdateState extends Equatable {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.available,
    this.error,
    this.failureKind,
    this.received = 0,
    this.total = 0,
    this.dismissed = false,
    this.canInstall = true,
    this.lastCheckedAt,
  });

  final UpdateStatus status;
  final UpdateAvailable? available;
  final String? error;

  /// Why the last check could not answer. Lets the card say what to do about
  /// it rather than only that something went wrong — a missing checksum and a
  /// dead connection need completely different things from the owner.
  final UpdateFailureKind? failureKind;

  final int received;
  final int total;

  /// False where an update can be found but not applied — anywhere that is not
  /// Windows. The card offers the download page instead of an Install button
  /// that could only fail.
  final bool canInstall;

  /// When GitHub last actually answered, for the diagnostics line.
  final DateTime? lastCheckedAt;

  /// The owner said "Later" to this version.
  final bool dismissed;

  /// Null until the size is known, so the bar can be indeterminate while
  /// backing up rather than sitting at zero.
  double? get progress =>
      total <= 0 ? null : (received / total).clamp(0.0, 1.0);

  /// The banner is for something actionable that has not been waved away.
  bool get showBanner => status == UpdateStatus.available && !dismissed;

  bool get busy =>
      status == UpdateStatus.checking ||
      status == UpdateStatus.installing ||
      status == UpdateStatus.launched;

  @override
  List<Object?> get props => [
        status,
        available?.version,
        error,
        failureKind,
        received,
        total,
        dismissed,
        canInstall,
        lastCheckedAt,
      ];
}

/// Drives the update banner and the Settings card from one state machine, so
/// the two can never disagree about what is happening.
class UpdateBloc extends Bloc<UpdateEvent, UpdateState> {
  UpdateBloc(this._service) : super(const UpdateState()) {
    on<UpdateCheckRequested>(_onCheck);
    on<UpdateInstallRequested>(_onInstall);
    on<UpdateDismissed>(_onDismiss);
  }

  final UpdateService _service;

  AppVersion get currentVersion => _service.currentVersion;

  /// The feed being watched, so the diagnostics panel can name it instead of
  /// leaving the owner to guess which repository this copy follows.
  String get releasesEndpoint => _service.releasesEndpoint;

  /// Runs the layered "Test Connection" diagnostic. A read-only side channel
  /// from the bloc's own state machine — it never emits — because its result
  /// belongs to whichever dialog asked for it, not to the update banner or
  /// the Settings card's everyday status line.
  Future<ConnectionTestReport> testConnection() => _service.testConnection();

  Future<void> _onCheck(
    UpdateCheckRequested event,
    Emitter<UpdateState> emit,
  ) async {
    if (state.busy) return;

    // Every path below this line emits. Returning quietly is what the gym
    // reported as "it doesn't connect to GitHub": the button was pressed, the
    // check never ran, and nothing on screen changed — which is exactly what a
    // dead connection looks like from the outside.
    //
    // Note this is `canCheck`, not `canInstall`. A machine that cannot apply
    // an installer can still be told one is waiting.
    if (!_service.canCheck) {
      emit(_failed(await _service.check()));
      return;
    }

    // The automatic check at startup only goes to the network once a day. What
    // it found, though, is still the answer: reopening the app an hour later
    // used to leave this bloc idle and a waiting update invisible until
    // tomorrow. A deliberate press always asks GitHub again.
    if (!event.force && !await _service.isDueForCheck()) {
      await _emitResult(await _service.lastKnownResult(), emit,
          quietFailures: true);
      return;
    }

    emit(UpdateState(
      status: UpdateStatus.checking,
      canInstall: _service.canInstall,
    ));

    await _emitResult(await _service.check(), emit);
  }

  /// A failure that never reached the network, shaped like every other one so
  /// the card has a single thing to render.
  UpdateState _failed(UpdateCheckResult result) => switch (result) {
        UpdateCheckFailed(:final reason, :final kind) => UpdateState(
            status: UpdateStatus.failed,
            error: reason,
            failureKind: kind,
            canInstall: _service.canInstall,
          ),
        _ => UpdateState(status: UpdateStatus.idle,
            canInstall: _service.canInstall),
      };

  /// Turns a check result into state.
  ///
  /// [quietFailures] is set when the result came from the cache rather than
  /// from a check the owner is waiting on: there is nothing new to report, and
  /// showing yesterday's error would be worse than showing nothing.
  Future<void> _emitResult(
    UpdateCheckResult? result,
    Emitter<UpdateState> emit, {
    bool quietFailures = false,
  }) async {
    switch (result) {
      case null:
        return;
      case UpdateAvailable():
        final dismissed = await _service.dismissedVersion();
        emit(UpdateState(
          status: UpdateStatus.available,
          available: result,
          total: result.sizeBytes,
          dismissed: dismissed == result.version,
          canInstall: _service.canInstall,
          lastCheckedAt: await _service.lastCheckedAt(),
        ));
      case AlreadyCurrent():
        emit(UpdateState(
          status: UpdateStatus.upToDate,
          canInstall: _service.canInstall,
          lastCheckedAt: await _service.lastCheckedAt(),
        ));
      case UpdateCheckFailed(:final reason, :final kind):
        if (quietFailures) return;
        // Only surfaced where the owner went looking for it. An offline gym is
        // not a problem the dashboard needs to announce.
        emit(UpdateState(
          status: UpdateStatus.failed,
          error: reason,
          failureKind: kind,
          canInstall: _service.canInstall,
          lastCheckedAt: await _service.lastCheckedAt(),
        ));
    }
  }

  Future<void> _onInstall(
    UpdateInstallRequested event,
    Emitter<UpdateState> emit,
  ) async {
    final update = state.available;
    if (update == null || state.status == UpdateStatus.installing) return;

    // Carried through every emit below. Neither is a fact about *this*
    // transition: one is what the machine can do, the other is when GitHub
    // last answered, and rebuilding the state without them silently restores
    // the `canInstall: true` default — putting an Install button that can only
    // fail back on a Mac, and "Never" on a diagnostics line that had just been
    // filled in.
    final canInstall = _service.canInstall;
    final checkedAt = state.lastCheckedAt;

    emit(UpdateState(
      status: UpdateStatus.installing,
      available: update,
      total: update.sizeBytes,
      canInstall: canInstall,
      lastCheckedAt: checkedAt,
    ));

    final result = await _service.install(
      update,
      onProgress: (received, total) {
        if (isClosed) return;
        emit(UpdateState(
          status: UpdateStatus.installing,
          available: update,
          received: received,
          total: total,
          canInstall: canInstall,
          lastCheckedAt: checkedAt,
        ));
      },
    );

    switch (result) {
      case UpdateLaunched():
        emit(UpdateState(
          status: UpdateStatus.launched,
          available: update,
          canInstall: canInstall,
          lastCheckedAt: checkedAt,
        ));
      case UpdateInstallFailed(:final message):
        emit(UpdateState(
          status: UpdateStatus.failed,
          available: update,
          error: message,
          canInstall: canInstall,
          lastCheckedAt: checkedAt,
        ));
    }
  }

  Future<void> _onDismiss(
    UpdateDismissed event,
    Emitter<UpdateState> emit,
  ) async {
    final update = state.available;
    if (update == null) return;

    await _service.dismiss(update.version);
    emit(UpdateState(
      status: UpdateStatus.available,
      available: update,
      total: update.sizeBytes,
      dismissed: true,
      canInstall: _service.canInstall,
      lastCheckedAt: state.lastCheckedAt,
    ));
  }
}
