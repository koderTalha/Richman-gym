import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/session_repository.dart';

/// The owner restarts this app constantly — Windows updates, power cuts, an
/// accidental close mid-shift. Being asked for the password every time is the
/// complaint these tests exist to prevent regressing.
void main() {
  late AppDatabase db;
  late SessionRepository sessions;

  const email = 'admin@richmanfitness.local';
  // Matches seedDatabase's default; a wrong value here silently turns every
  // sign-in below into a failed one.
  const password = 'RichMan#2026';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
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
}
