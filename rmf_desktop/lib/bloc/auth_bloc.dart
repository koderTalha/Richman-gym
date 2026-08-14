import 'package:bcrypt/bcrypt.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
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

enum AuthStatus { signedOut, submitting, signedIn }

class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.signedOut, this.user, this.error});

  final AuthStatus status;
  final User? user;
  final String? error;

  bool get isSignedIn => status == AuthStatus.signedIn && user != null;

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
            : AuthState(status: AuthStatus.signedIn, user: restored)) {
    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignOutRequested>(_onSignOut);
  }

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

    emit(AuthState(status: AuthStatus.signedIn, user: user));
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
