import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/session_repository.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';

/// The owner restarts this app constantly — Windows updates, power cuts, an
/// accidental close mid-shift. Being asked for the password every time is the
/// complaint these tests exist to prevent regressing.
void main() {
  late AppDatabase db;
  late SessionRepository sessions;

  const email = defaultAdminEmail;

  // Deliberately not the password the app ships with. These tests are about
  // sessions surviving a restart; an account still on the shipped password is
  // held at the change-password screen instead, which is its own group below.
  const password = 'owners-own-password';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db, adminPassword: password);
    sessions = SessionRepository(db);
  });

  tearDown(() async => db.close());

  Future<User> seededAdmin() =>
      (db.select(db.users)..where((u) => u.email.equals(email))).getSingle();

  /// Waits for the bloc to settle on a signed-in or signed-out state.
  Future<AuthState> settle(AuthBloc bloc) =>
      bloc.stream.firstWhere((s) => s.status != AuthStatus.submitting);

  test('a fresh install has nobody signed in', () async {
    expect(await sessions.restore(), isNull);
  });

  test('signing in records the session', () async {
    final bloc = AuthBloc(db, sessions: sessions);
    addTearDown(bloc.close);

    bloc.add(const AuthSignInRequested(email: email, password: password));
    await settle(bloc);

    final restored = await sessions.restore();
    expect(restored, isNotNull);
    expect(restored!.email, email);
  });

  test('a failed sign-in records nothing', () async {
    final bloc = AuthBloc(db, sessions: sessions);
    addTearDown(bloc.close);

    bloc.add(const AuthSignInRequested(email: email, password: 'wrong'));
    await settle(bloc);

    expect(await sessions.restore(), isNull);
  });

  test('the admin is still signed in after a restart', () async {
    final first = AuthBloc(db, sessions: sessions);
    first.add(const AuthSignInRequested(email: email, password: password));
    await settle(first);
    await first.close();

    // What main() does on the next launch.
    final restored = await sessions.restore();
    final second = AuthBloc(db, sessions: sessions, restored: restored);
    addTearDown(second.close);

    expect(second.state.isSignedIn, isTrue);
    expect(second.state.user!.email, email);
  });

  test('signing out ends the session, and it stays ended', () async {
    final bloc = AuthBloc(db, sessions: sessions);
    bloc.add(const AuthSignInRequested(email: email, password: password));
    await settle(bloc);

    bloc.add(const AuthSignOutRequested());
    await bloc.stream.firstWhere((s) => !s.isSignedIn);
    await bloc.close();

    expect(await sessions.restore(), isNull);
    // The next launch must show the login form.
    expect(AuthBloc(db, sessions: sessions, restored: null).state.isSignedIn,
        isFalse);
  });

  test('no password or hash is written to the session row', () async {
    await sessions.remember((await seededAdmin()).id);

    final row = await db.select(db.appSessions).getSingle();
    final dump = row.toString();

    expect(dump, isNot(contains(password)));
    expect(dump, isNot(contains(r'$2'))); // a bcrypt hash prefix
    expect(row.userId, isNotNull);
  });

  test('a session pointing at a deleted admin does not restore', () async {
    final admin = await seededAdmin();
    await sessions.remember(admin.id);

    await (db.delete(db.users)..where((u) => u.id.equals(admin.id))).go();

    // Must fall back to the login screen rather than crashing on a missing
    // user or restoring a ghost.
    expect(await sessions.restore(), isNull);
  });

  test('remembering twice replaces the row rather than adding one', () async {
    final admin = await seededAdmin();
    await sessions.remember(admin.id, at: DateTime(2026, 8, 1));
    await sessions.remember(admin.id, at: DateTime(2026, 8, 15));

    final rows = await db.select(db.appSessions).get();
    expect(rows, hasLength(1));
    expect(rows.single.signedInAt, DateTime(2026, 8, 15));
  });

  /// The password the app is installed with is printed in its own source, and
  /// the app holds every payment the gym has ever taken. Signing in with it
  /// gets as far as choosing a real one, and no further.
  group('the password the app ships with', () {
    late AppDatabase fresh;
    late SessionRepository freshSessions;

    setUp(() async {
      fresh = AppDatabase.forTesting(NativeDatabase.memory());
      await seedDatabase(fresh); // shipped password, untouched
      freshSessions = SessionRepository(fresh);
    });

    tearDown(() async => fresh.close());

    Future<AuthState> signIn(AuthBloc bloc, String withPassword) {
      bloc.add(AuthSignInRequested(email: email, password: withPassword));
      return bloc.stream.firstWhere((s) => s.status != AuthStatus.submitting);
    }

    test('signing in with it does not open the app', () async {
      final bloc = AuthBloc(fresh, sessions: freshSessions);
      addTearDown(bloc.close);

      final state = await signIn(bloc, defaultAdminPassword);

      expect(state.status, AuthStatus.passwordChangeRequired);
      expect(state.isSignedIn, isFalse);
      expect(state.mustChangePassword, isTrue);
    });

    test('restarting does not get past it either', () async {
      final first = AuthBloc(fresh, sessions: freshSessions);
      await signIn(first, defaultAdminPassword);
      await first.close();

      // Leaving the app open overnight must not become the way to skip this.
      final restored = await freshSessions.restore();
      final second =
          AuthBloc(fresh, sessions: freshSessions, restored: restored);
      addTearDown(second.close);

      expect(second.state.mustChangePassword, isTrue);
      expect(second.state.isSignedIn, isFalse);
    });

    test('choosing a real password opens the app', () async {
      final bloc = AuthBloc(fresh, sessions: freshSessions);
      addTearDown(bloc.close);
      await signIn(bloc, defaultAdminPassword);

      final problem = await SettingsRepository(fresh).changePassword(
        userId: bloc.state.user!.id,
        currentPassword: defaultAdminPassword,
        newPassword: 'owners-own-password',
      );
      expect(problem, isNull);

      bloc.add(const AuthPasswordChanged());
      final state = await bloc.stream.firstWhere((s) => s.isSignedIn);
      expect(state.isSignedIn, isTrue);
    });

    test('the shipped password cannot be set as the new one', () async {
      final admin = await (fresh.select(fresh.users)
            ..where((u) => u.email.equals(email)))
          .getSingle();

      final problem = await SettingsRepository(fresh).changePassword(
        userId: admin.id,
        currentPassword: defaultAdminPassword,
        newPassword: defaultAdminPassword,
      );

      expect(problem, isNotNull,
          reason: 'otherwise the gate is satisfied by changing nothing');
    });

    test('an account with its own password is signed in as before', () async {
      final bloc = AuthBloc(db, sessions: sessions);
      addTearDown(bloc.close);

      final state = await signIn(bloc, password);

      expect(state.isSignedIn, isTrue);
      expect(state.mustChangePassword, isFalse);
    });
  });
}
