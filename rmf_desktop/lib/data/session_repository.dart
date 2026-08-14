import 'package:drift/drift.dart';

import 'database.dart';

/// Remembers the signed-in admin between runs.
///
/// Deliberately stores nothing but the user id and a timestamp: the point is
/// to skip the login form, not to hold a credential that could be lifted out
/// of the database file.
class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;

  /// The admin to restore at startup, or null when nobody is signed in.
  ///
  /// Returns null rather than throwing if the row points at an account that no
  /// longer exists, so a deleted admin cannot wedge the app on a blank screen.
  Future<User?> restore() async {
    final session = await _db.select(_db.appSessions).getSingleOrNull();
    final userId = session?.userId;
    if (userId == null) return null;

    return (_db.select(_db.users)..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
  }

  /// Records a successful sign-in. Upserts, because the table holds one row.
  Future<void> remember(int userId, {DateTime? at}) =>
      _db.into(_db.appSessions).insertOnConflictUpdate(
            AppSessionsCompanion.insert(
              id: const Value(1),
              userId: Value(userId),
              signedInAt: Value(at ?? DateTime.now()),
            ),
          );

  /// Ends the session. Signing out has to survive a restart just as reliably
  /// as signing in does.
  Future<void> clear() => _db.into(_db.appSessions).insertOnConflictUpdate(
        AppSessionsCompanion.insert(
          id: const Value(1),
          userId: const Value(null),
          signedInAt: const Value(null),
        ),
      );
}
