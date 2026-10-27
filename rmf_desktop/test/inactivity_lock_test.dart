import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/session_repository.dart';
import 'package:rich_man_fitness/domain/inactivity.dart';

/// A session whose row cannot be cleared — a locked or full disk.
class _StuckSessions extends SessionRepository {
  _StuckSessions(super.db);

  @override
  Future<void> clear() async => throw StateError('disk full');
}

/// The rules behind the two-minute lock, without any widgets: when the
/// deadline passes, what moves it, and what a restart is allowed to restore.
void main() {
  test('the limit is two minutes', () {
    expect(inactivityLockAfter, const Duration(milliseconds: 120000));
  });

  group('InactivityMonitor', () {
    late DateTime now;
    late int locks;
    late InactivityMonitor monitor;

    setUp(() {
      now = DateTime(2026, 10, 27, 9);
      locks = 0;
      monitor = InactivityMonitor(onExpired: () => locks++, clock: () => now);
    });

    test('locks once 120 seconds pass without activity', () {
      now = now.add(const Duration(seconds: 119));
      expect(monitor.check(), isFalse);

      now = now.add(const Duration(seconds: 1));
      expect(monitor.check(), isTrue);
      expect(locks, 1);
    });

    test('activity moves the deadline on', () {
      now = now.add(const Duration(seconds: 100));
      expect(monitor.recordActivity(), isTrue);

      now = now.add(const Duration(seconds: 100));
      expect(monitor.check(), isFalse,
          reason: '200s since sign-in, but only 100s since the last input');

      now = now.add(const Duration(seconds: 20));
      expect(monitor.check(), isTrue);
    });

    test('an owner who keeps working is never locked out', () {
      for (var minute = 0; minute < 60; minute++) {
        now = now.add(const Duration(seconds: 90));
        expect(monitor.recordActivity(), isTrue);
      }
      expect(locks, 0);
    });

    // The computer slept and no timer ran. The first click afterwards must
    // lock, not count as the activity that keeps the app open.
    test('input that arrives after the deadline locks instead of counting', () {
      now = now.add(const Duration(hours: 1));

      expect(monitor.recordActivity(), isFalse);
      expect(monitor.expired, isTrue);
      expect(locks, 1);
    });

    test('expiring is reported once, however often it is checked', () {
      now = now.add(const Duration(minutes: 5));
      monitor.check();
      monitor.check();
      monitor.recordActivity();

      expect(locks, 1);
    });

    test('starts from a given time, so a restart keeps its deadline', () {
      final restored = InactivityMonitor(
        onExpired: () => locks++,
        lastActivity: now.subtract(const Duration(seconds: 110)),
        clock: () => now,
      );

      now = now.add(const Duration(seconds: 10));
      expect(restored.check(), isTrue);
    });

    test('putting the clock back does not hold the lock off', () {
      now = now.subtract(const Duration(hours: 3));
      expect(monitor.check(), isFalse);

      now = now.add(inactivityLockAfter);
      expect(monitor.check(), isTrue,
          reason: 'the idle spell restarts from the new time, it does not '
              'wait three hours for the clock to catch up');
    });
  });

  group('the session across a restart', () {
    late AppDatabase db;
    late SessionRepository sessions;
    late User admin;
    final signedIn = DateTime(2026, 10, 27, 9);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedDatabase(db, adminPassword: 'owners-own-password');
      sessions = SessionRepository(db);
      admin = await db.select(db.users).getSingle();
    });

    tearDown(() async => db.close());

    test('restores within two minutes of the last activity', () async {
      await sessions.remember(admin.id, at: signedIn);
      await sessions.touch(admin.id,
          at: signedIn.add(const Duration(minutes: 30)));

      final restored = await sessions.restore(
          now: signedIn.add(const Duration(minutes: 31)));

      expect(restored?.id, admin.id);
      expect(await sessions.lastActiveAt(),
          signedIn.add(const Duration(minutes: 30)));
    });

    test('a restart after the deadline asks for the password', () async {
      await sessions.remember(admin.id, at: signedIn);

      expect(
          await sessions.restore(now: signedIn.add(inactivityLockAfter)),
          isNull);
    });

    test('a session saved before the lock existed is not restored', () async {
      await sessions.remember(admin.id, at: signedIn);
      await db.customStatement(
          'UPDATE app_sessions SET last_active_at = NULL');

      expect(await sessions.restore(now: signedIn), isNull);
    });

    // An activity write still in flight when the lock clears the row.
    test('a late activity write cannot bring a cleared session back',
        () async {
      await sessions.remember(admin.id, at: signedIn);
      await sessions.clear();
      await sessions.touch(admin.id, at: signedIn);

      expect(await sessions.restore(now: signedIn), isNull);
    });
  });

  group('AuthBloc', () {
    late AppDatabase db;
    late User admin;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seedDatabase(db, adminPassword: 'owners-own-password');
      admin = await db.select(db.users).getSingle();
    });

    tearDown(() async => db.close());

    test('locking signs out, clears the session and says why', () async {
      final sessions = SessionRepository(db);
      await sessions.remember(admin.id);
      final bloc = AuthBloc(db, sessions: sessions, restored: admin);
      addTearDown(bloc.close);

      bloc.add(const AuthLockedForInactivity());
      final state = await bloc.stream.first;

      expect(state.user, isNull);
      expect(state.isSignedIn, isFalse);
      expect(state.lockedForInactivity, isTrue);

      await pumpEventQueue();
      expect((await db.select(db.appSessions).getSingle()).userId, isNull);
    });

    test('a second lock does nothing', () async {
      final bloc = AuthBloc(db, restored: admin);
      addTearDown(bloc.close);
      final states = <AuthState>[];
      final sub = bloc.stream.listen(states.add);
      addTearDown(sub.cancel);

      bloc
        ..add(const AuthLockedForInactivity())
        ..add(const AuthLockedForInactivity());
      await pumpEventQueue();

      expect(states, hasLength(1));
    });

    test('the screens go even when the session row cannot be cleared',
        () async {
      final bloc = AuthBloc(db, sessions: _StuckSessions(db), restored: admin);
      addTearDown(bloc.close);

      bloc.add(const AuthLockedForInactivity());
      await pumpEventQueue();

      expect(bloc.state.user, isNull);
      expect(bloc.state.lockedForInactivity, isTrue);
    });

    test('signing in again opens the app and drops the notice', () async {
      final bloc = AuthBloc(db, restored: admin);
      addTearDown(bloc.close);
      bloc.add(const AuthLockedForInactivity());
      await pumpEventQueue();

      bloc.add(const AuthSignInRequested(
          email: defaultAdminEmail, password: 'owners-own-password'));
      final state = await bloc.stream.firstWhere((s) => s.isSignedIn);

      expect(state.lockedForInactivity, isFalse);
    });

    test('the restored deadline belongs to the restored session only',
        () async {
      final activeAt = DateTime(2026, 10, 27, 9);
      final bloc =
          AuthBloc(db, restored: admin, restoredActiveAt: activeAt);
      addTearDown(bloc.close);
      expect(bloc.restoredActiveAt, activeAt);

      bloc.add(const AuthLockedForInactivity());
      await pumpEventQueue();
      bloc.add(const AuthSignInRequested(
          email: defaultAdminEmail, password: 'owners-own-password'));
      await bloc.stream.firstWhere((s) => s.isSignedIn);

      expect(bloc.restoredActiveAt, isNull,
          reason: 'a fresh sign-in gets a fresh two minutes');
    });
  });
}
