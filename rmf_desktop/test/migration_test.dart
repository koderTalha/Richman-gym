import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';

/// Proves that installing a new version over an old one keeps the gym's data.
///
/// Every future release adds a migration step, and a mistake there quietly
/// destroys real member and payment history. These tests build a database in an
/// older shape, put real rows in it, then open it with the current code and
/// check that everything survived.
void main() {
  late Directory workspace;
  late File dbFile;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-migration');
    dbFile = File(p.join(workspace.path, 'old.sqlite'));
  });

  tearDown(() async {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  /// Builds a database that looks the way version [version] left it, with a
  /// member, a plan, a membership, a billing cycle, a payment and a receipt.
  Future<void> buildOldDatabase(int version) async {
    final db = NativeDatabase(dbFile);
    final executor = DatabaseConnection(db);

    // Columns added in v2 and v3 only exist at those versions and later.
    final settingsExtras = <String>[
      if (version >= 2) ...[
        'whatsapp_provider TEXT NOT NULL DEFAULT \'mock\'',
        'whatsapp_phone_number_id TEXT NULL',
        'whatsapp_access_token TEXT NULL',
        'whatsapp_mock_fails INTEGER NOT NULL DEFAULT 0',
      ],
      if (version >= 3) ...[
        'whatsapp_business_account_id TEXT NULL',
        'whatsapp_business_number TEXT NULL',
      ],
    ];

    Future<void> run(String sql) => executor.executor.runCustom(sql, const []);

    await executor.executor.ensureOpen(_NoopUser());

    await run('''
      CREATE TABLE users (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'admin',
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )''');

    await run('''
      CREATE TABLE gym_settings (
        id INTEGER NOT NULL DEFAULT 1 PRIMARY KEY,
        gym_name TEXT NOT NULL DEFAULT 'Rich Man Fitness',
        logo_path TEXT NULL,
        phone TEXT NULL,
        whatsapp_phone TEXT NULL,
        email TEXT NULL,
        address TEXT NULL,
        opening_hours TEXT NULL,
        currency TEXT NOT NULL DEFAULT 'PKR',
        receipt_prefix TEXT NOT NULL DEFAULT 'RMF',
        receipt_footer_message TEXT NOT NULL DEFAULT 'Thanks.'
        ${settingsExtras.isEmpty ? '' : ', ${settingsExtras.join(', ')}'}
      )''');

    // Sections existed until v4 removed them.
    await run('''
      CREATE TABLE sections (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )''');

    await run('''
      CREATE TABLE membership_plans (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT NULL,
        duration_months INTEGER NOT NULL,
        price_minor INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )''');

    await run('''
      CREATE TABLE members (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        member_code INTEGER NOT NULL UNIQUE,
        full_name TEXT NOT NULL,
        phone TEXT NOT NULL,
        phone_raw TEXT NULL,
        email TEXT NULL,
        gender TEXT NULL,
        date_of_birth INTEGER NULL,
        address TEXT NULL,
        emergency_contact TEXT NULL,
        joining_date INTEGER NOT NULL,
        section_id INTEGER NULL REFERENCES sections (id),
        deactivated_at INTEGER NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )''');

    await run('''
      CREATE TABLE memberships (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        member_id INTEGER NOT NULL REFERENCES members (id),
        plan_id INTEGER NOT NULL REFERENCES membership_plans (id),
        fee_override_minor INTEGER NULL,
        start_date INTEGER NOT NULL,
        end_date INTEGER NULL
      )''');

    await run('''
      CREATE TABLE membership_periods (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        membership_id INTEGER NOT NULL REFERENCES memberships (id),
        period_start INTEGER NOT NULL,
        period_end INTEGER NOT NULL,
        expected_amount_minor INTEGER NOT NULL,
        UNIQUE (membership_id, period_start)
      )''');

    await run('''
      CREATE TABLE payments (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        member_id INTEGER NOT NULL REFERENCES members (id),
        membership_period_id INTEGER NULL REFERENCES membership_periods (id),
        amount_minor INTEGER NOT NULL,
        method TEXT NOT NULL,
        reference_number TEXT NULL,
        payment_date INTEGER NOT NULL,
        notes TEXT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        recorded_by_id INTEGER NOT NULL REFERENCES users (id),
        idempotency_key TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )''');

    await run('''
      CREATE TABLE receipts (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        receipt_number TEXT NOT NULL UNIQUE,
        payment_id INTEGER NOT NULL UNIQUE REFERENCES payments (id),
        png_path TEXT NOT NULL,
        pdf_path TEXT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )''');

    await run('''
      CREATE TABLE receipt_counters (
        year INTEGER NOT NULL PRIMARY KEY,
        last_number INTEGER NOT NULL DEFAULT 0
      )''');

    await run('''
      CREATE TABLE whats_app_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL REFERENCES receipts (id),
        member_id INTEGER NOT NULL REFERENCES members (id),
        phone TEXT NOT NULL,
        provider TEXT NOT NULL,
        external_message_id TEXT NULL,
        status TEXT NOT NULL DEFAULT 'queued',
        error_message TEXT NULL,
        attempt_number INTEGER NOT NULL DEFAULT 1,
        sent_at INTEGER NULL,
        delivered_at INTEGER NULL,
        read_at INTEGER NULL,
        failed_at INTEGER NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )''');

    await run('''
      CREATE TABLE member_notes (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        member_id INTEGER NOT NULL REFERENCES members (id),
        body TEXT NOT NULL,
        created_by_id INTEGER NOT NULL REFERENCES users (id),
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )''');

    // --- The gym's real data, as it would exist before an upgrade ----------
    await run("INSERT INTO users (id, name, email, password_hash) "
        "VALUES (1, 'Gym Owner', 'admin@richmanfitness.local', 'hashed-secret')");
    await run("INSERT INTO gym_settings (id, gym_name, receipt_prefix, "
        "receipt_footer_message) VALUES (1, 'Rich Man Fitness', 'RMF', 'Thanks.')");
    await run("INSERT INTO sections (id, name) VALUES (1, 'Boys')");
    await run("INSERT INTO membership_plans (id, name, duration_months, "
        "price_minor) VALUES (1, 'Monthly', 1, 300000)");
    await run("INSERT INTO members (id, member_code, full_name, phone, gender, "
        "joining_date, section_id) VALUES "
        "(1, 7, 'Legacy Member', '+923000000023', 'Male', 1767225600, 1)");
    await run("INSERT INTO memberships (id, member_id, plan_id, start_date) "
        "VALUES (1, 1, 1, 1767225600)");
    await run("INSERT INTO membership_periods (id, membership_id, period_start, "
        "period_end, expected_amount_minor) "
        "VALUES (1, 1, 1767225600, 1769904000, 300000)");
    await run("INSERT INTO payments (id, member_id, membership_period_id, "
        "amount_minor, method, payment_date, recorded_by_id, idempotency_key) "
        "VALUES (1, 1, 1, 300000, 'cash', 1767571200, 1, 'legacy-payment-1')");
    await run("INSERT INTO receipts (id, receipt_number, payment_id, png_path) "
        "VALUES (1, 'RMF-2026-000001', 1, 'RMF-2026-000001.png')");
    await run("INSERT INTO receipt_counters (year, last_number) "
        "VALUES (2026, 1)");

    await run('PRAGMA user_version = $version');
    await executor.executor.close();
  }

  /// Opens the old file with the current code, forcing migrations to run.
  Future<AppDatabase> openWithCurrentCode() async {
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    // Any query forces the connection open and the migration to execute.
    await db.customSelect('SELECT 1').get();
    return db;
  }

  for (final from in [1, 2, 3]) {
    group('upgrading a v$from database', () {
      test('reaches the current schema version', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final version = await db
            .customSelect('PRAGMA user_version')
            .map((r) => r.read<int>('user_version'))
            .getSingle();

        expect(version, db.schemaVersion);
      });

      test('keeps the member', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final members = await db.select(db.members).get();
        expect(members.single.fullName, 'Legacy Member');
        expect(members.single.memberCode, 7);
        expect(members.single.phone, '+923000000023');
        expect(members.single.gender, 'Male');
      });

      test('keeps the payment and its receipt', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final payments = await db.select(db.payments).get();
        expect(payments.single.amountMinor, 300000);
        expect(payments.single.idempotencyKey, 'legacy-payment-1');

        final receipts = await db.select(db.receipts).get();
        expect(receipts.single.receiptNumber, 'RMF-2026-000001');
      });

      test('keeps the login intact', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final user = await db.select(db.users).getSingle();
        expect(user.email, 'admin@richmanfitness.local');
        expect(user.passwordHash, 'hashed-secret',
            reason: 'the owner must not be locked out by an upgrade');
      });

      test('keeps the receipt numbering sequence', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final counter = await db.select(db.receiptCounters).getSingle();
        expect(counter.lastNumber, 1,
            reason: 'the next receipt must not reuse RMF-2026-000001');
      });

      test('drops the sections table that v4 removed', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final tables = await db
            .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => r.read<String>('name'))
            .get();

        expect(tables, isNot(contains('sections')));
        expect(tables, contains('members'));
      });

      test('the settings singleton survives and is usable', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final settings = await db.select(db.gymSettings).getSingle();
        expect(settings.gymName, 'Rich Man Fitness');
        expect(settings.receiptPrefix, 'RMF');
        // Columns introduced by later versions take their defaults.
        expect(settings.whatsappProvider, WhatsAppProviderKind.mock);
        // v5. An upgraded install keeps the dark theme it has always had,
        // rather than switching to light on the owner without being asked.
        expect(settings.themeMode, 'dark');
      });

      test('new columns are writable after the upgrade', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        await (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
          const GymSettingsCompanion(
            whatsappBusinessAccountId: Value('123456789'),
          ),
        );

        final settings = await db.select(db.gymSettings).getSingle();
        expect(settings.whatsappBusinessAccountId, '123456789');
      });

      test('the upgraded database still accepts new records', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final id = await db.into(db.members).insert(MembersCompanion.insert(
              memberCode: 8,
              fullName: 'New Member',
              phone: '+923000000024',
              joiningDate: DateTime.utc(2026, 8, 1),
            ));

        expect(id, greaterThan(0));
        expect((await db.select(db.members).get()).length, 2,
            reason: 'old and new members coexist');
      });
    });
  }

  test('opening an already-current database changes nothing', () async {
    await buildOldDatabase(4);
    final db = await openWithCurrentCode();
    addTearDown(db.close);

    expect((await db.select(db.members).get()).single.fullName, 'Legacy Member');
    expect((await db.select(db.payments).get()).length, 1);
  });
}

/// drift requires a QueryExecutorUser when opening a raw executor.
class _NoopUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
