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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// For tests: an isolated in-memory database.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

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
        },
        beforeOpen: (details) async {
          // Enforce the foreign keys declared in tables.dart; SQLite ignores
          // them unless this pragma is set on every connection.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _open() {
    return driftDatabase(name: 'richmanfitness');
  }
}
