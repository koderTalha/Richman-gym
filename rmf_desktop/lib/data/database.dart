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
    PaymentAllocations,
    PaymentReminders,
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
  int get schemaVersion => 10;

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
          // v9 sends receipts as an approved template instead of a free-form
          // image. Meta only accepts free-form messages inside the 24-hour
          // window a member's own message opens, and a receipt is sent when the
          // payment is recorded — almost never inside one. The template's name
          // and language are settings because both are chosen in Meta's
          // Business Manager and a mismatch is invisible from in here.
          if (from < 9) {
            await m.addColumn(gymSettings, gymSettings.whatsappReceiptTemplate);
            await m.addColumn(
                gymSettings, gymSettings.whatsappReceiptTemplateLanguage);
          }
          // v10 moves billing off the calendar month and onto a day the member
          // is anchored to, and adds the reminder machinery.
          //
          // Deliberately a no-op for existing data. `billingAnchorDay` is left
          // null on every membership, and `resolveAnchorDay` reads a null
          // anchor as the day the member's latest cycle starts — which, for
          // every cycle this app has ever written, is the 1st. So nobody's due
          // date moves on upgrade, and the owner re-anchors members one at a
          // time from the member screen.
          if (from < 10) {
            await m.addColumn(memberships, memberships.billingAnchorDay);
            await m.addColumn(membershipPeriods, membershipPeriods.settledAt);
            await m.createTable(paymentAllocations);
            await m.createTable(paymentReminders);

            for (final column in [
              gymSettings.reminderAutoSend,
              gymSettings.reminderDaysBefore,
              gymSettings.reminderDaysAfter,
              gymSettings.reminderOnDueDate,
              gymSettings.reminderSendFromHour,
              gymSettings.reminderSendUntilHour,
              gymSettings.reminderMaxPerRun,
              gymSettings.whatsappReminderTemplate,
              gymSettings.whatsappReminderTemplateLanguage,
              gymSettings.paymentInstructions,
            ]) {
              await m.addColumn(gymSettings, column);
            }

            await _grandfatherSettledPeriods();
            await _backfillPaymentAllocations();
          }
        },
        beforeOpen: (details) async {
          // Enforce the foreign keys declared in tables.dart; SQLite ignores
          // them unless this pragma is set on every connection.
          await customStatement('PRAGMA foreign_keys = ON');
          await _createIndexes();
        },
      );

  /// Closes every cycle that already had a payment against it.
  ///
  /// Settlement is now a question of money — a cycle is closed once the
  /// allocations against it reach the fee it expects. Applying that rule
  /// backwards would reopen any historical month recorded for less than the
  /// plan price: a discount the owner gave, a short cash payment, a typo in the
  /// 2024 ledger. The gym would open the app after updating and find months it
  /// considers long closed showing as owing money.
  ///
  /// So history is grandfathered here, in the data. Every pre-existing cycle
  /// with a payment against it is stamped settled, and from this point the
  /// balance rule governs. No cutoff date is tested anywhere in the code, and
  /// no reported amount is altered — `Payments.amountMinor` keeps saying
  /// exactly what was collected.
  Future<void> _grandfatherSettledPeriods() async {
    await customStatement(
      'UPDATE membership_periods SET settled_at = COALESCE('
      '  (SELECT MIN(p.payment_date) FROM payments p'
      '   WHERE p.membership_period_id = membership_periods.id),'
      // Drift stores a DateTime as unix *seconds*, so no millisecond factor
      // here. Only reached for a payment with no date at all.
      "  strftime('%s', 'now')"
      ') '
      'WHERE settled_at IS NULL AND EXISTS ('
      '  SELECT 1 FROM payments p'
      '  WHERE p.membership_period_id = membership_periods.id'
      ')',
    );
  }

  /// Gives every existing payment an allocation row for the cycle it names.
  ///
  /// Without this, a historical payment would read as money allocated nowhere,
  /// and the first correction to an old payment would recompute its cycle's
  /// balance from zero. The allocation records what the payment actually was,
  /// capped at what its cycle expected: a member who overpaid does not get
  /// credit spilling into a month they never paid for, and the true amount
  /// stays on the payment row either way.
  Future<void> _backfillPaymentAllocations() async {
    await customStatement(
      'INSERT INTO payment_allocations '
      '  (payment_id, membership_period_id, amount_minor, created_at) '
      'SELECT p.id, p.membership_period_id, '
      '  MIN(p.amount_minor, mp.expected_amount_minor), '
      "  strftime('%s', 'now') "
      'FROM payments p '
      'JOIN membership_periods mp ON mp.id = p.membership_period_id '
      'WHERE p.membership_period_id IS NOT NULL '
      '  AND NOT EXISTS ('
      '    SELECT 1 FROM payment_allocations a'
      '    WHERE a.payment_id = p.id'
      '      AND a.membership_period_id = p.membership_period_id'
      '  )',
    );
  }

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
      // Settlement reads every allocation for a cycle, and deleting a payment
      // reads every allocation it made.
      'CREATE INDEX IF NOT EXISTS idx_allocations_period '
          'ON payment_allocations (membership_period_id)',
      'CREATE INDEX IF NOT EXISTS idx_allocations_payment '
          'ON payment_allocations (payment_id)',
      // The reminder queue asks "what has already been handled for this
      // cycle?" once per member, every time it is built.
      'CREATE INDEX IF NOT EXISTS idx_reminders_period '
          'ON payment_reminders (membership_period_id)',
      'CREATE INDEX IF NOT EXISTS idx_reminders_member '
          'ON payment_reminders (member_id)',
      // Deriving status now reads open cycles by their settled flag.
      'CREATE INDEX IF NOT EXISTS idx_periods_settled '
          'ON membership_periods (settled_at)',
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
