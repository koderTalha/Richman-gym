import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:logging/logging.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

final _log = Logger('database');

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
    CyclePricings,
    MembershipChanges,
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
  int get schemaVersion => 12;

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

          // v11 lets a welcome message go out as an approved template instead
          // of always as free text. Left null on upgrade: the free-text path
          // this app has always used keeps working exactly as it does today
          // until the gym registers a template and fills this in — see
          // `MemberWelcomeService`.
          if (from < 11) {
            await m.addColumn(
                gymSettings, gymSettings.whatsappWelcomeTemplate);
            await m.addColumn(
                gymSettings, gymSettings.whatsappWelcomeTemplateLanguage);
          }

          // v12 records *why* a billing cycle was priced as it was, and what
          // a member was billed before a plan change — the two things the
          // database could not answer when forty-three cycles were found
          // stranded at a plan price the members had been moved off.
          //
          // Additive and non-destructive. No existing row is read, altered or
          // deleted: both tables start empty and every cycle already recorded
          // is backfilled with `unknown` rather than a guess. A cycle billed
          // 4,000 under a plan that today costs 2,500 could have been either
          // plan's price at the time, and there is nothing in this database
          // that distinguishes them — inventing the answer is how the gym got
          // here. `unknown` says so honestly, and the historical review screen
          // is where a human supplies what the data cannot.
          if (from < 12) {
            await m.createTable(cyclePricings);
            await m.createTable(membershipChanges);
            await _backfillUnknownCyclePricing();
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

  /// Gives every cycle recorded before v12 a pricing row saying `unknown`.
  ///
  /// The honest answer, and the only safe one. Reconstructing provenance would
  /// mean comparing each cycle's amount against today's plan prices and
  /// declaring a match to be the reason — which is exactly the reasoning that
  /// would have labelled forty-three stranded cycles as correctly priced under
  /// Basic. Nothing here reads a plan or a fee.
  ///
  /// Idempotent through the `NOT EXISTS` guard, so re-running it — on a
  /// restore, or a second upgrade over the same file — adds nothing.
  Future<void> _backfillUnknownCyclePricing() async {
    await customStatement(
      'INSERT INTO cycle_pricings '
      '  (membership_period_id, amount_minor, previous_amount_minor, '
      '   source, reason, recorded_at) '
      "SELECT mp.id, mp.expected_amount_minor, NULL, 'unknown', "
      "  'Recorded before the app kept pricing history.', "
      // Drift stores a DateTime as unix *seconds*, matching the helpers above.
      "  strftime('%s', 'now') "
      'FROM membership_periods mp '
      'WHERE NOT EXISTS ('
      '  SELECT 1 FROM cycle_pricings c'
      '  WHERE c.membership_period_id = mp.id'
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
      // The one-cycle-per-member-per-start guard below looks a start date up
      // on every cycle insert, so it wants an index to look it up in.
      'CREATE INDEX IF NOT EXISTS idx_periods_start '
          'ON membership_periods (period_start)',
      // The Logs screen always reads newest-first, and pages with a limit.
      'CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_events (created_at)',
      // The historical review asks "what has already been decided about this
      // cycle?" once per candidate, and the original bill is read back through
      // the same index.
      'CREATE INDEX IF NOT EXISTS idx_cycle_pricings_period '
          'ON cycle_pricings (membership_period_id)',
      'CREATE INDEX IF NOT EXISTS idx_membership_changes_member '
          'ON membership_changes (member_id)',
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

    await _createCycleUniquenessTriggers();
  }

  /// One member, one billing cycle starting on any given day.
  ///
  /// `MembershipPeriods` already carries a unique key on
  /// `(membership_id, period_start)`, which is a weaker promise than it looks.
  /// Changing a member's plan closes their enrolment and opens a new one, so
  /// one person accumulates several `memberships` rows while keeping a single
  /// continuous timeline. Two of those enrolments can each hold a cycle
  /// starting 6 September, and the table takes both — two rows for one month,
  /// each able to accept its own payment, and a member billed twice for
  /// September with nothing in the schema objecting.
  ///
  /// Every lookup in `membership_queries.dart` already resolves cycles per
  /// *member*, collecting the member's enrolment ids and searching across all
  /// of them. The application has therefore always treated
  /// `(member, period_start)` as the real key; this is SQLite agreeing.
  ///
  /// A trigger rather than a unique index, for two reasons. The key spans a
  /// join — the member is on `memberships`, not on the cycle — and SQLite
  /// cannot index across one. And unlike a unique index, a trigger cannot
  /// refuse to be created because the database it is being added to already
  /// holds a duplicate: existing rows are left exactly as they are, in the
  /// same spirit as the v10 settled-period grandfathering, and only new writes
  /// are held to the rule. An owner locked out by their own imported ledger
  /// would have no way back in.
  ///
  /// The message is deliberately readable: it reaches the owner through
  /// `RecordPaymentService`, which turns it into a sentence about the member
  /// and the month rather than a constraint name.
  Future<void> _createCycleUniquenessTriggers() async {
    // Cycles already recorded for the member this row would belong to,
    // starting on the same day. Shared by both triggers; the update variant
    // additionally excludes the row being updated from matching itself.
    const collides = 'SELECT 1 FROM membership_periods p '
        'JOIN memberships existing ON existing.id = p.membership_id '
        'JOIN memberships incoming ON incoming.id = NEW.membership_id '
        'WHERE existing.member_id = incoming.member_id '
        'AND p.period_start = NEW.period_start';

    const abort =
        "BEGIN SELECT RAISE(ABORT, 'duplicate billing cycle for this member'); END";

    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS trg_periods_one_per_member_insert '
      'BEFORE INSERT ON membership_periods FOR EACH ROW '
      'WHEN EXISTS ($collides) $abort',
    );

    // Scoped to the two columns that can move a cycle onto a date another
    // enrolment already covers. Settling a cycle writes `settled_at` and must
    // not pay for this check.
    await customStatement(
      'CREATE TRIGGER IF NOT EXISTS trg_periods_one_per_member_update '
      'BEFORE UPDATE OF period_start, membership_id ON membership_periods '
      'FOR EACH ROW '
      'WHEN EXISTS ($collides AND p.id <> NEW.id) $abort',
    );

    await _reportPreExistingDuplicateCycles();
  }

  /// Logs any duplicate cycle already in the database.
  ///
  /// The triggers above guard new writes and deliberately leave history alone,
  /// so a database that arrived here with duplicates keeps them. Silently is
  /// the wrong way to keep them: these are the rows where a member may have
  /// been charged twice for one month, and the owner cannot fix what nobody
  /// mentions. Reported once per open, to the log rather than the screen —
  /// there is nothing to do about it mid-launch, and the Logs screen is where
  /// this app puts things the owner may want to act on later.
  Future<void> _reportPreExistingDuplicateCycles() async {
    try {
      final rows = await customSelect(
        'SELECT m.member_id AS member_id, p.period_start AS period_start, '
        'COUNT(*) AS copies '
        'FROM membership_periods p '
        'JOIN memberships m ON m.id = p.membership_id '
        'GROUP BY m.member_id, p.period_start HAVING COUNT(*) > 1',
      ).get();

      if (rows.isEmpty) return;

      _log.warning(
        'Found ${rows.length} billing ${rows.length == 1 ? "cycle" : "cycles"} '
        'recorded more than once for the same member. These predate the '
        'one-cycle-per-member rule and were left as they are; check the '
        'affected members for a month paid twice.',
      );
    } catch (error, stack) {
      // A diagnostic must never be the reason the app will not open.
      _log.warning('Could not check for duplicate billing cycles', error, stack);
    }
  }

  static QueryExecutor _open() {
    return driftDatabase(name: 'richmanfitness');
  }
}
