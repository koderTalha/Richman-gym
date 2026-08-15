import 'package:bcrypt/bcrypt.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../data/seed.dart';
import '../data/session_repository.dart';

final _log = Logger('auth');

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => const [];
}

class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];

  // Equatable builds toString() from props, so the admin's password would
  // otherwise be written verbatim anywhere this event is printed — a bloc
  // failure log, a debugger, a crash report. props itself is left alone so
  // equality still distinguishes two attempts with different passwords.
  @override
  String toString() => 'AuthSignInRequested(email: $email, password: •••)';
}

class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// The owner has chosen a password of their own; let them into the app.
class AuthPasswordChanged extends AuthEvent {
  const AuthPasswordChanged();
}

enum AuthStatus {
  signedOut,
  submitting,

  /// Signed in, but still using the password every copy of the app ships with.
  /// Nothing but the change-password screen is reachable from here.
  passwordChangeRequired,

  signedIn,
}

class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.signedOut, this.user, this.error});

  final AuthStatus status;
  final User? user;
  final String? error;

  bool get isSignedIn => status == AuthStatus.signedIn && user != null;

  bool get mustChangePassword =>
      status == AuthStatus.passwordChangeRequired && user != null;

  AuthState copyWith({AuthStatus? status, User? user, String? error}) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error,
      );

  @override
  List<Object?> get props => [status, user?.id, error];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  /// [restored] is the admin recovered from a previous run, so the app opens
  /// straight onto the dashboard instead of the login form.
  AuthBloc(this._db, {SessionRepository? sessions, User? restored})
      : _sessions = sessions ?? SessionRepository(_db),
        super(restored == null
            ? const AuthState()
            : AuthState(status: _statusFor(restored), user: restored)) {
    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignOutRequested>(_onSignOut);
    on<AuthPasswordChanged>((_, emit) {
      final user = state.user;
      if (user == null) return;
      emit(AuthState(status: AuthStatus.signedIn, user: user));
    });
  }

  /// A restored session is still a session — but not one that gets to skip
  /// past the default password, or leaving the app open would be the way to
  /// avoid ever changing it.
  static AuthStatus _statusFor(User user) =>
      isDefaultAdminPassword(user.passwordHash)
          ? AuthStatus.passwordChangeRequired
          : AuthStatus.signedIn;

  final AppDatabase _db;
  final SessionRepository _sessions;

  Future<void> _onSignIn(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthState(status: AuthStatus.submitting));

    final email = event.email.trim().toLowerCase();
    final user = await (_db.select(_db.users)..where((u) => u.email.equals(email)))
        .getSingleOrNull();

    // Deliberately the same message whether the email or the password was
    // wrong, so this cannot be used to discover which accounts exist.
    final ok = user != null && BCrypt.checkpw(event.password, user.passwordHash);

    if (!ok) {
      emit(const AuthState(error: 'Invalid email or password.'));
      return;
    }

    // Written before the state is emitted so a crash on the very first frame
    // cannot leave the owner signed in on screen but signed out on disk.
    try {
      await _sessions.remember(user.id);
    } catch (e, s) {
      // Worth staying signed in for this run even if the session cannot be
      // saved; the only cost is being asked again next time.
      _log.severe('Could not save the session', e, s);
    }

    emit(AuthState(status: _statusFor(user), user: user));
  }

  Future<void> _onSignOut(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Clear first: signing out must survive a restart as reliably as signing
    // in does, and a failure here has to be visible rather than silent.
    try {
      await _sessions.clear();
    } catch (e, s) {
      _log.severe('Could not clear the session', e, s);
    }
    emit(const AuthState());
  }
}
