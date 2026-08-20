import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

/// The whole dataset is one SQLite file in the user's application-support
/// directory, so "back up the gym's data" means copying a single file.
@DriftDatabase(
  tables: [
    Users,
    AppSessions,
    GymSettings,
    MembershipPlans,
    Members,
    Memberships,
    MembershipPeriods,
    Payments,
    Receipts,
    ReceiptCounters,
    WhatsAppMessages,
    MemberNotes,
    AuditEvents,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// For tests: an isolated in-memory database.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2 moved WhatsApp credentials into settings so they can be edited
          // from the app instead of a config file.
          if (from < 2) {
            await m.addColumn(gymSettings, gymSettings.whatsappProvider);
            await m.addColumn(gymSettings, gymSettings.whatsappPhoneNumberId);
            await m.addColumn(gymSettings, gymSettings.whatsappAccessToken);
            await m.addColumn(gymSettings, gymSettings.whatsappMockFails);
          }
          // v3 records which Meta business account the credentials belong to.
          if (from < 3) {
            await m.addColumn(
                gymSettings, gymSettings.whatsappBusinessAccountId);
            await m.addColumn(
                gymSettings, gymSettings.whatsappBusinessNumber);
          }
          // v4 removed Sections entirely: the gym separates members by gender,
          // and never had the branches or shifts this modelled.
          if (from < 4) {
            await m.alterTable(TableMigration(members));
            await m.deleteTable('sections');
          }
          // v5 remembers whether the owner prefers the light or dark theme.
          if (from < 5) {
            await m.addColumn(gymSettings, gymSettings.themeMode);
          }
          // v6 keeps the owner signed in across restarts. The table starts
          // empty, so an upgraded install signs in once more and then stops
          // asking.
          if (from < 6) {
            await m.createTable(appSessions);
          }
          // v7 makes corrections traceable: two columns recording who last
          // edited a payment, and the audit log the Logs screen reads. Both
          // columns are nullable, so every payment recorded before this
          // release reads as never edited rather than as edited by nobody.
          if (from < 7) {
            await m.addColumn(payments, payments.updatedAt);
            await m.addColumn(payments, payments.updatedById);
            await m.createTable(auditEvents);
          }
          // v8 lets the app update itself: it remembers when it last checked
          // for a release and which one the owner said "Later" to.
          if (from < 8) {
            await m.addColumn(gymSettings, gymSettings.lastUpdateCheckAt);
            await m.addColumn(gymSettings, gymSettings.dismissedUpdateVersion);
          }
        },
        beforeOpen: (details) async {
          // Enforce the foreign keys declared in tables.dart; SQLite ignores
          // them unless this pragma is set on every connection.
          await customStatement('PRAGMA foreign_keys = ON');
          await _createIndexes();
        },
      );

  /// Indexes live here rather than in a numbered migration.
  ///
  /// `IF NOT EXISTS` makes each one idempotent, so a fresh install and an
  /// install upgraded from any earlier version end up identical without
  /// spending a schema version on something that changes no data. Every one of
  /// these backs a lookup the app does in a loop — the importer resolving a
  /// row to a member, the members screen deriving status, the receipts screen
  /// finding the latest send attempt.
  Future<void> _createIndexes() async {
    const indexes = [
      'CREATE INDEX IF NOT EXISTS idx_members_phone ON members (phone)',
      'CREATE INDEX IF NOT EXISTS idx_memberships_member ON memberships (member_id)',
      'CREATE INDEX IF NOT EXISTS idx_periods_membership ON membership_periods (membership_id)',
      'CREATE INDEX IF NOT EXISTS idx_payments_member ON payments (member_id)',
      'CREATE INDEX IF NOT EXISTS idx_payments_period ON payments (membership_period_id)',
      'CREATE INDEX IF NOT EXISTS idx_messages_receipt ON whats_app_messages (receipt_id)',
      // The Logs screen always reads newest-first, and pages with a limit.
      'CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_events (created_at)',
    ];
    for (final statement in indexes) {
      await customStatement(statement);
    }

    // A member is meant to have at most one open enrolment: every lookup of
    // "their current plan" uses getSingleOrNull, which throws outright on a
    // second row. Enforcing it in SQLite means a bug that would otherwise
    // wedge the member and payment screens fails at the write instead.
    //
    // Deliberately best-effort: an existing database that already holds a
    // duplicate must still open, or the owner is locked out of the very screen
    // that would let them fix it.
    try {
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_memberships_one_open '
        'ON memberships (member_id) WHERE end_date IS NULL',
      );
    } catch (_) {
      // Already-duplicated data. MemberRepository copes at read time.
    }
  }

  static QueryExecutor _open() {
    return driftDatabase(name: 'richmanfitness');
  }
}
