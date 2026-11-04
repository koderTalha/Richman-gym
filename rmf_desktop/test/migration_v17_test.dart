// A database the first v16 build opened — the automatic deactivation tables
// without the threshold or reinstating — upgraded by the current code.
//
// Exactly what happened on the development machine: v16 grew two columns and a
// rebuilt table after a build had already stamped a real file 16, and that
// file then failed to open with "Null check operator used on a null value"
// reading the settings row. v17 is the step that catches such a file up.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/services/payment_inactivity_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late File file;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('rmf-v16');
    addTearDown(() => dir.delete(recursive: true));
    file = File(p.join(dir.path, 'gym.sqlite'));

    final current = AppDatabase.forTesting(NativeDatabase(file));
    await current.customSelect('SELECT 1').get();
    await current.close();

    // Back to the first v16's shape, with one write-off already made.
    final raw = sqlite3.open(file.path);
    raw.execute('ALTER TABLE gym_settings DROP COLUMN inactivity_grace_days');
    raw.execute('ALTER TABLE member_deactivations DROP COLUMN grace_days');
    raw.execute('ALTER TABLE member_deactivations DROP COLUMN reinstated');
    raw.execute('DROP TABLE inactivity_waivers');
    raw.execute('CREATE TABLE "inactivity_waivers" ('
        '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        '"deactivation_id" INTEGER NOT NULL REFERENCES member_deactivations '
        '(id) ON DELETE CASCADE, "member_id" INTEGER NOT NULL, '
        '"membership_period_id" INTEGER NOT NULL UNIQUE, '
        '"period_start" INTEGER NOT NULL, "period_end" INTEGER NOT NULL, '
        '"amount_minor" INTEGER NOT NULL)');
    raw.execute("INSERT INTO gym_settings (id, gym_name, receipt_prefix, "
        "theme_mode, auto_deactivate_unpaid) VALUES (1, 'Rich Man Fitness', "
        "'RMF', 'dark', 1)");
    raw.execute("INSERT INTO users (id, name, email, password_hash) "
        "VALUES (1, 'Owner', 'o@x', 'h')");
    raw.execute("INSERT INTO membership_plans (id, name, duration_months, "
        "price_minor) VALUES (1, 'Monthly', 1, 250000)");
    raw.execute("INSERT INTO members (id, member_code, full_name, phone, "
        "joining_date, deactivated_at) VALUES (1, 1, 'Lapsed', "
        "'+923000000001', 1788220800, 1794268800)");
    raw.execute("INSERT INTO memberships (id, member_id, plan_id, start_date) "
        "VALUES (7, 1, 1, 1788220800)");
    raw.execute("INSERT INTO membership_periods (id, membership_id, "
        "period_start, period_end, expected_amount_minor, settled_at) "
        "VALUES (30, 7, 1790812800, 1793491200, 0, 1794268800)");
    raw.execute("INSERT INTO member_deactivations (id, member_id, reason, "
        "deactivated_at, deactivated_on, first_missed_due, waived_minor) "
        "VALUES (1, 1, 'payment_inactivity', 1794268800, 1794268800, "
        "1790812800, 250000)");
    raw.execute("INSERT INTO inactivity_waivers (deactivation_id, member_id, "
        "membership_period_id, period_start, period_end, amount_minor) "
        "VALUES (1, 1, 30, 1790812800, 1793491200, 250000)");
    raw.execute('PRAGMA user_version = 16');
    raw.close();
  });

  test('opens, and the settings row reads again', () async {
    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final version = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(version, 17);

    final settings = await SettingsRepository(db).get();
    expect(settings.autoDeactivateUnpaid, isTrue, reason: 'kept as it was');
    expect(settings.inactivityGraceDays, 40);
  });

  test('a write-off made under v16 survives, and knows its enrolment',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final episode =
        (await PaymentInactivityService(db).historyFor(1)).single;
    expect(episode.row.graceDays, 40);
    expect(episode.row.reinstated, isFalse);
    expect(episode.waivers.single.membershipId, 7);
    expect(episode.waivers.single.amountMinor, 250000);
  });

  test('and can be reinstated', () async {
    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final result =
        await PaymentInactivityService(db).reinstate(memberId: 1);
    expect(result, isA<MemberReinstated>());
    final cycle = await (db.select(db.membershipPeriods)
          ..where((p) => p.id.equals(30)))
        .getSingle();
    expect(cycle.expectedAmountMinor, 250000);
    expect(cycle.settledAt, isNull);
  });
}
