import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/app_version.dart';
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
    this.received = 0,
    this.total = 0,
    this.dismissed = false,
  });

  final UpdateStatus status;
  final UpdateAvailable? available;
  final String? error;
  final int received;
  final int total;

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
  List<Object?> get props =>
      [status, available?.version, error, received, total, dismissed];
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

  Future<void> _onCheck(
    UpdateCheckRequested event,
    Emitter<UpdateState> emit,
  ) async {
    if (state.busy) return;
    if (!_service.isSupported) return;

    // The automatic check at startup is skipped if it already ran today; a
    // deliberate press is never skipped.
    if (!event.force && !await _service.isDueForCheck()) return;

    emit(const UpdateState(status: UpdateStatus.checking));

    final result = await _service.check();

    switch (result) {
      case UpdateAvailable():
        final dismissed = await _service.dismissedVersion();
        emit(UpdateState(
          status: UpdateStatus.available,
          available: result,
          total: result.sizeBytes,
          dismissed: dismissed == result.version,
        ));
      case AlreadyCurrent():
        emit(const UpdateState(status: UpdateStatus.upToDate));
      case UpdateCheckFailed(:final reason):
        // Only surfaced where the owner went looking for it. An offline gym is
        // not a problem the dashboard needs to announce.
        emit(UpdateState(status: UpdateStatus.failed, error: reason));
    }
  }

  Future<void> _onInstall(
    UpdateInstallRequested event,
    Emitter<UpdateState> emit,
  ) async {
    final update = state.available;
    if (update == null || state.status == UpdateStatus.installing) return;

    emit(UpdateState(
      status: UpdateStatus.installing,
      available: update,
      total: update.sizeBytes,
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
        ));
      },
    );

    switch (result) {
      case UpdateLaunched():
        emit(UpdateState(status: UpdateStatus.launched, available: update));
      case UpdateInstallFailed(:final message):
        emit(UpdateState(
          status: UpdateStatus.failed,
          available: update,
          error: message,
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
    ));
  }
}
