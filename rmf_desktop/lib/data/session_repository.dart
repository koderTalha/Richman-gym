import 'package:drift/drift.dart';

import '../domain/inactivity.dart';
import 'database.dart';

/// Remembers the signed-in admin between runs.
///
/// Deliberately stores nothing but the user id and timestamps: the point is
/// to skip the login form, not to hold a credential that could be lifted out
/// of the database file.
class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;

  /// The admin to restore at startup, or null when nobody is signed in.
  ///
  /// Also null when the app was last touched [idleLimit] or more before [now]:
  /// closing the app and opening it again must not be a way past the
  /// inactivity lock. A row with no activity recorded — written by a version
  /// from before the lock — counts as too old.
  ///
  /// Returns null rather than throwing if the row points at an account that no
  /// longer exists, so a deleted admin cannot wedge the app on a blank screen.
  Future<User?> restore({
    DateTime? now,
    Duration idleLimit = inactivityLockAfter,
  }) async {
    final session = await _db.select(_db.appSessions).getSingleOrNull();
    final userId = session?.userId;
    if (userId == null) return null;

    final lastActive = session!.lastActiveAt;
    if (lastActive == null ||
        (now ?? DateTime.now()).difference(lastActive) >= idleLimit) {
      return null;
    }

    return (_db.select(_db.users)..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
  }

  /// When the app was last touched, so a restored session keeps the deadline
  /// it had rather than starting a fresh two minutes.
  Future<DateTime?> lastActiveAt() async =>
      (await _db.select(_db.appSessions).getSingleOrNull())?.lastActiveAt;

  /// Records a successful sign-in. Upserts, because the table holds one row.
  Future<void> remember(int userId, {DateTime? at}) {
    final when = at ?? DateTime.now();
    return _db.into(_db.appSessions).insertOnConflictUpdate(
          AppSessionsCompanion.insert(
            id: const Value(1),
            userId: Value(userId),
            signedInAt: Value(when),
            lastActiveAt: Value(when),
          ),
        );
  }

  /// Records that [userId] is still at the keyboard.
  ///
  /// Only updates a session that is still [userId]'s: a write that lands after
  /// the app has locked finds the row cleared and changes nothing, so it can
  /// never bring the session back.
  Future<void> touch(int userId, {required DateTime at}) =>
      (_db.update(_db.appSessions)..where((s) => s.userId.equals(userId)))
          .write(AppSessionsCompanion(lastActiveAt: Value(at)));

  /// Ends the session. Signing out has to survive a restart just as reliably
  /// as signing in does.
  Future<void> clear() => _db.into(_db.appSessions).insertOnConflictUpdate(
        AppSessionsCompanion.insert(
          id: const Value(1),
          userId: const Value(null),
          signedInAt: const Value(null),
          lastActiveAt: const Value(null),
        ),
      );
}
