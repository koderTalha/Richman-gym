import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/domain/billing_cycle.dart';

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
  ///
  /// Two structural details follow the real history: `sections` existed only
  /// until v4 removed it, and `app_sessions` only from v6 onwards. Getting
  /// those wrong would test an upgrade path no installation ever had.
  Future<void> buildOldDatabase(int version) async {
    final hasSections = version < 4;
    final hasSessions = version >= 6;
    final hasAuditTrail = version >= 7;
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
      // v5 remembered the theme. Omitting it left a v6- or v7-shaped database
      // that drift reads back as a null in a non-nullable column, which is a
      // fault in this builder rather than in any migration.
      if (version >= 5) "theme_mode TEXT NOT NULL DEFAULT 'dark'",
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
    if (hasSections) {
      await run('''
        CREATE TABLE sections (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          description TEXT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        )''');
    }

    if (hasSessions) {
      await run('''
        CREATE TABLE app_sessions (
          id INTEGER NOT NULL DEFAULT 1 PRIMARY KEY,
          user_id INTEGER NULL REFERENCES users (id) ON DELETE CASCADE,
          signed_in_at INTEGER NULL
        )''');
    }

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
        ${hasSections ? 'section_id INTEGER NULL REFERENCES sections (id),' : ''}
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
        ${hasAuditTrail ? 'updated_at INTEGER NULL, updated_by_id INTEGER NULL REFERENCES users (id),' : ''}
        idempotency_key TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )''');

    // The audit log arrived in v7. Deliberately without foreign keys to
    // members or payments — see the table's own documentation.
    if (hasAuditTrail) {
      await run('''
        CREATE TABLE audit_events (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL,
          action TEXT NOT NULL,
          outcome TEXT NOT NULL,
          actor_id INTEGER NULL,
          actor_name TEXT NULL,
          member_id INTEGER NULL,
          member_name TEXT NULL,
          payment_id INTEGER NULL,
          receipt_number TEXT NULL,
          amount_minor INTEGER NULL,
          period_label TEXT NULL,
          summary TEXT NOT NULL,
          detail TEXT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
        )''');
    }

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
    if (hasSections) {
      await run("INSERT INTO sections (id, name) VALUES (1, 'Boys')");
    }
    await run("INSERT INTO membership_plans (id, name, duration_months, "
        "price_minor) VALUES (1, 'Monthly', 1, 300000)");
    await run(hasSections
        ? "INSERT INTO members (id, member_code, full_name, phone, gender, "
            "joining_date, section_id) VALUES "
            "(1, 7, 'Legacy Member', '+923000000023', 'Male', 1767225600, 1)"
        : "INSERT INTO members (id, member_code, full_name, phone, gender, "
            "joining_date) VALUES "
            "(1, 7, 'Legacy Member', '+923000000023', 'Male', 1767225600)");
    if (hasSessions) {
      await run('INSERT INTO app_sessions (id, user_id, signed_in_at) '
          'VALUES (1, 1, 1767571200)');
    }
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
    if (hasAuditTrail) {
      await run("INSERT INTO audit_events (category, action, outcome, "
          "member_name, summary) VALUES ('payment', 'payment.edited', "
          "'success', 'Legacy Member', 'Payment edited for Legacy Member')");
    }

    await run('PRAGMA user_version = $version');
    await executor.executor.close();
  }

  /// Rewrites the seeded payment's amount in the *old* file, before any
  /// migration has run.
  ///
  /// The seed pays a 300,000 fee in full. Both the underpaid and overpaid
  /// cases are about what the v10 backfill does with a payment that does not
  /// match its cycle exactly, so they need the row changed while the database
  /// still looks the way the previous release left it.
  /// Goes straight at the file with sqlite3 rather than through drift.
  /// Opening it as a drift executor rewrites `user_version` to whatever the
  /// executor's user claims, which made the next open replay the v2 migration
  /// over columns that were already there.
  void setHistoricalPaymentAmount(int amountMinor) {
    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute(
        'UPDATE payments SET amount_minor = ? WHERE id = 1',
        [amountMinor],
      );
    } finally {
      raw.close();
    }
  }

  /// 100,000 against a 300,000 fee — the discount or short cash payment.
  void underpayTheHistoricalPayment() => setHistoricalPaymentAmount(100000);

  /// 500,000 against a 300,000 fee — a tip, or a ledger typo.
  void overpayTheHistoricalPayment() => setHistoricalPaymentAmount(500000);

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

      test('v7 leaves existing payments marked as never edited', () async {
        await buildOldDatabase(from);
        final db = await openWithCurrentCode();
        addTearDown(db.close);

        final payment = await db.select(db.payments).getSingle();
        expect(payment.updatedAt, isNull,
            reason: 'a payment nobody has corrected must not look corrected');
        expect(payment.updatedById, isNull);
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

  group('upgrading a v6 database', () {
    test('reaches the current schema version', () async {
      await buildOldDatabase(6);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();

      // Against the code, not a literal: this assertion should not need
      // editing every time a release adds a migration.
      expect(version, db.schemaVersion);
    });

    test('keeps the payment, its receipt and the numbering sequence', () async {
      await buildOldDatabase(6);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final payment = await db.select(db.payments).getSingle();
      expect(payment.amountMinor, 300000);
      expect(payment.idempotencyKey, 'legacy-payment-1');

      expect((await db.select(db.receipts).getSingle()).receiptNumber,
          'RMF-2026-000001');
      expect((await db.select(db.receiptCounters).getSingle()).lastNumber, 1);
    });

    test('keeps the owner signed in', () async {
      await buildOldDatabase(6);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final session = await db.select(db.appSessions).getSingle();
      expect(session.userId, 1,
          reason: 'an upgrade must not sign the owner out');
    });

    test('the new payment audit columns are writable', () async {
      await buildOldDatabase(6);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final editedAt = DateTime.utc(2026, 8, 20, 9, 30);
      await (db.update(db.payments)..where((p) => p.id.equals(1))).write(
        PaymentsCompanion(
          updatedAt: Value(editedAt),
          updatedById: const Value(1),
        ),
      );

      final payment = await db.select(db.payments).getSingle();
      // Timestamps go to SQLite as unix seconds and come back on the local
      // clock, so the instant is what matches, not the DateTime object.
      expect(payment.updatedAt!.isAtSameMomentAs(editedAt), isTrue);
      expect(payment.updatedById, 1);
    });

    test('the audit log table is created and accepts events', () async {
      await buildOldDatabase(6);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      await db.into(db.auditEvents).insert(AuditEventsCompanion.insert(
            category: AuditCategory.payment,
            action: 'payment.edited',
            outcome: AuditOutcome.success,
            summary: 'Payment edited for Legacy Member',
          ));

      final event = await db.select(db.auditEvents).getSingle();
      expect(event.action, 'payment.edited');
      expect(event.category, AuditCategory.payment);
    });

    test('an audit event outlives the payment it describes', () async {
      await buildOldDatabase(6);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      await db.into(db.auditEvents).insert(AuditEventsCompanion.insert(
            category: AuditCategory.payment,
            action: 'payment.deleted',
            outcome: AuditOutcome.success,
            memberId: const Value(1),
            memberName: const Value('Legacy Member'),
            paymentId: const Value(1),
            receiptNumber: const Value('RMF-2026-000001'),
            amountMinor: const Value(300000),
            summary: 'Payment deleted for Legacy Member',
          ));

      // Exactly the deletion the event records, foreign keys enforced.
      await db.customStatement('PRAGMA foreign_keys = ON');
      await (db.delete(db.receipts)..where((r) => r.paymentId.equals(1))).go();
      await (db.delete(db.payments)..where((p) => p.id.equals(1))).go();

      final event = await db.select(db.auditEvents).getSingle();
      expect(event.paymentId, 1,
          reason: 'the id is copied, not a foreign key, so it survives');
      expect(event.memberName, 'Legacy Member');
      expect(event.amountMinor, 300000);
      expect(event.receiptNumber, 'RMF-2026-000001',
          reason: 'the log has to stay readable once the payment is gone');
    });
  });

  group('upgrading a v7 database to the current schema', () {
    test('reaches the current schema version', () async {
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();

      expect(version, db.schemaVersion);
      expect(db.schemaVersion, 10);
    });

    test('keeps the members, payments and receipts', () async {
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      expect((await db.select(db.members).getSingle()).fullName,
          'Legacy Member');
      expect((await db.select(db.payments).getSingle()).amountMinor, 300000);
      expect((await db.select(db.receipts).getSingle()).receiptNumber,
          'RMF-2026-000001');
    });

    test('keeps the audit history written by the previous version', () async {
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final event = await db.select(db.auditEvents).getSingle();
      expect(event.action, 'payment.edited');
      expect(event.memberName, 'Legacy Member');
      expect(event.category, AuditCategory.payment);
    });

    test('the update-check columns start empty and are writable', () async {
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      var settings = await db.select(db.gymSettings).getSingle();
      expect(settings.lastUpdateCheckAt, isNull,
          reason: 'an upgraded install has never checked for a release');
      expect(settings.dismissedUpdateVersion, isNull);

      final checkedAt = DateTime.utc(2026, 8, 21, 8, 30);
      await (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
        GymSettingsCompanion(
          lastUpdateCheckAt: Value(checkedAt),
          dismissedUpdateVersion: const Value('1.2.0'),
        ),
      );

      settings = await db.select(db.gymSettings).getSingle();
      expect(settings.lastUpdateCheckAt!.isAtSameMomentAs(checkedAt), isTrue);
      expect(settings.dismissedUpdateVersion, '1.2.0');
    });

    test('the receipt template columns arrive already pointing at the '
        'approved template', () async {
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      var settings = await db.select(db.gymSettings).getSingle();
      // An upgraded install must be able to send without visiting Settings
      // first, so these default to the template the gym had approved rather
      // than to nothing.
      expect(settings.whatsappReceiptTemplate, 'payment_receipt');
      expect(settings.whatsappReceiptTemplateLanguage, 'en');

      // Both are editable, because a gym that registers its template under a
      // different name or under en_US must be able to say so.
      await (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
        const GymSettingsCompanion(
          whatsappReceiptTemplate: Value('gym_receipt_v2'),
          whatsappReceiptTemplateLanguage: Value('en_US'),
        ),
      );

      settings = await db.select(db.gymSettings).getSingle();
      expect(settings.whatsappReceiptTemplate, 'gym_receipt_v2');
      expect(settings.whatsappReceiptTemplateLanguage, 'en_US');
    });
  });

  /// The v10 upgrade is the one that changes how billing *means* something, so
  /// it gets the most attention: the whole promise is that a gym updating the
  /// app finds every member exactly where they left them.
  group('upgrading to anchored billing cycles', () {
    test('moves nobody onto a new billing day', () async {
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final membership = await db.select(db.memberships).getSingle();
      expect(membership.billingAnchorDay, isNull,
          reason: 'the upgrade writes no anchor, so no due date moves');

      // And a null anchor resolves to the 1st, because that is where every
      // cycle this app has ever written starts.
      final period = await db.select(db.membershipPeriods).getSingle();
      expect(
        resolveAnchorDay(
          billingAnchorDay: membership.billingAnchorDay,
          latestPeriodStart: period.periodStart,
          joiningDate: (await db.select(db.members).getSingle()).joiningDate,
        ),
        1,
      );
    });

    test('closes a cycle that already had a payment against it', () async {
      // Grandfathering. Under the new balance rule this cycle would be
      // recomputed from its allocations; stamping it settled is what stops the
      // gym's back catalogue reopening the moment they update.
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final period = await db.select(db.membershipPeriods).getSingle();
      expect(period.settledAt, isNotNull);
    });

    test('closes an underpaid historical cycle too, rather than reopening it',
        () async {
      // The case that motivated grandfathering: a month recorded for less than
      // the plan fee — a discount, a short cash payment, a ledger typo. Under
      // the balance rule alone it would read as owing money.
      await buildOldDatabase(7);
      underpayTheHistoricalPayment();

      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final period = await db.select(db.membershipPeriods).getSingle();
      expect(period.settledAt, isNotNull,
          reason: 'history is closed by the migration, not re-judged');
    });

    test('gives every existing payment an allocation for its cycle', () async {
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final allocation = await db.select(db.paymentAllocations).getSingle();
      final payment = await db.select(db.payments).getSingle();

      expect(allocation.paymentId, payment.id);
      expect(allocation.membershipPeriodId, payment.membershipPeriodId);
      expect(allocation.amountMinor, 300000);
    });

    test('caps a backfilled allocation at what the cycle expected', () async {
      // An overpayment must not spill credit into a month the member never
      // paid for. The payment row keeps saying what was really collected.
      await buildOldDatabase(7);
      overpayTheHistoricalPayment();

      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final period = await db.select(db.membershipPeriods).getSingle();
      final allocation = await db.select(db.paymentAllocations).getSingle();

      expect(allocation.amountMinor, period.expectedAmountMinor);
      expect((await db.select(db.payments).getSingle()).amountMinor, 500000,
          reason: 'the amount actually collected is never rewritten');
    });

    test('the reminder settings arrive off, with sensible defaults', () async {
      await buildOldDatabase(7);
      final db = await openWithCurrentCode();
      addTearDown(db.close);

      final settings = await db.select(db.gymSettings).getSingle();

      expect(settings.reminderAutoSend, isFalse,
          reason: 'updating the app must never start messaging members');
      expect(settings.reminderDaysBefore, '3');
      expect(settings.reminderDaysAfter, '3,7');
      expect(settings.reminderOnDueDate, isTrue);
      expect(settings.reminderSendFromHour, 9);
      expect(settings.reminderSendUntilHour, 21);
      expect(settings.reminderMaxPerRun, 25);
      expect(settings.whatsappReminderTemplate, isNull);
      expect(settings.paymentInstructions, isNull);
    });

    test('running the upgrade twice adds nothing a second time', () async {
      await buildOldDatabase(7);

      final first = await openWithCurrentCode();
      await first.close();

      final db = await openWithCurrentCode();
      addTearDown(db.close);

      expect((await db.select(db.paymentAllocations).get()), hasLength(1));
    });
  });

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
