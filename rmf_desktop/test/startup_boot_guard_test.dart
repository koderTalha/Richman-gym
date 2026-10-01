import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/main.dart';

/// Opening the app must not depend on the billing roll succeeding (audit
/// BUG-009). Any exception out of it used to reach main()'s catch, so one bad
/// member row put the owner on the startup-failure screen at every launch —
/// with a database that had opened perfectly well.
void main() {
  late AppDatabase db;
  final records = <LogRecord>[];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    records.clear();
    Logger.root.level = Level.ALL;
  });

  tearDown(() => db.close());

  test('a maintenance failure is logged and boot carries on', () async {
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    final finished = await runStartupMaintenanceGuarded(
      db,
      maintenance: (_) async =>
          throw StateError('duplicate billing cycle for this member'),
    );

    expect(finished, isFalse);
    final severe = records.where((r) => r.level == Level.SEVERE).toList();
    expect(severe, hasLength(1),
        reason: 'the failure must still be visible in the log');
    expect(severe.single.error, isA<StateError>());

    // The connection is still good for everything boot does next.
    expect(await db.select(db.gymSettings).get(), hasLength(1));
  });

  test('the real maintenance runs and reports success', () async {
    expect(await runStartupMaintenanceGuarded(db), isTrue);
  });
}
