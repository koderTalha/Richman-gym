import 'package:bcrypt/bcrypt.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/database.dart';

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
  AuthBloc(this._db) : super(const AuthState()) {
    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignOutRequested>(_onSignOut);
  }

  final AppDatabase _db;

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

    emit(AuthState(status: AuthStatus.signedIn, user: user));
  }

  void _onSignOut(AuthSignOutRequested event, Emitter<AuthState> emit) {
    emit(const AuthState());
  }
}
