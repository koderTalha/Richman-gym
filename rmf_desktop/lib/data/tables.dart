import 'package:drift/drift.dart';

/// Money is stored as integer minor units (paisa) throughout — never floating
/// point — so amounts cannot drift through rounding.

enum UserRole { admin, staff }

enum PaymentMethod { cash, bankTransfer, easypaisa, jazzcash, card, other }

/// `imported` marks rows backfilled from the owner's Excel ledger. Those never
/// trigger a WhatsApp send — nobody wants a receipt for a 2024 cash payment.
enum PaymentSource { manual, imported }

enum WhatsAppStatus { queued, sent, delivered, read, failed }

enum WhatsAppProviderKind { manual, mock, meta }

/// What became of one scheduled payment reminder.
///
/// `skipped` is not a failure. It is a reminder whose moment passed while the
/// app was closed and which a later one has already superseded — recorded so
/// it can never arrive out of order days after the fact. See
/// `domain/reminder_schedule.dart`.
enum ReminderSendStatus { sent, failed, skipped }

/// What an audit event is about, so the Logs screen can group and filter
/// without parsing [AuditEvents.action] apart.
///
/// Appended to rather than reordered: drift stores the name, so a new value is
/// readable by older rows and vice versa.
enum AuditCategory { member, payment, receipt, whatsapp, billing, update, reminder }

/// Whether the operation an audit event describes actually happened.
///
/// `refused` is not a failure: it is the app declining on purpose, e.g. a
/// member who cannot be deleted while their payments exist. Worth recording
/// separately, because a run of refusals is a sign the owner is trying to do
/// something the app is not letting them do.
enum AuditOutcome { success, refused, failed }

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get role => textEnum<UserRole>().withDefault(const Constant('admin'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Single row (id = 1) remembering who is signed in.
///
/// Closing the app used to sign the owner out, which on a gym counter machine
/// meant typing the password again every morning and after every Windows
/// update. The session is kept until sign-out is chosen explicitly — the same
/// bargain a desktop mail or chat client makes.
///
/// Only the user id is stored. No password or hash is written here, so this
/// row is useless to anyone who copies the database file.
class AppSessions extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();

  /// Null when signed out. Cascades so deleting the account ends the session
  /// rather than leaving a row pointing at a user who no longer exists.
  IntColumn get userId =>
      integer().nullable().references(Users, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get signedInAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single row (id = 1) holding configurable branding and receipt settings.
class GymSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get gymName => text().withDefault(const Constant('Rich Man Fitness'))();
  TextColumn get logoPath => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get whatsappPhone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get openingHours => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('PKR'))();
  TextColumn get receiptPrefix => text().withDefault(const Constant('RMF'))();
  TextColumn get receiptFooterMessage => text()
      .withDefault(const Constant('Thank you for choosing Rich Man Fitness.'))();

  /// WhatsApp credentials live in the database, not a .env file: the gym owner
  /// installs a packaged app and has no terminal to edit config files in.
  TextColumn get whatsappProvider => textEnum<WhatsAppProviderKind>()
      .withDefault(const Constant('mock'))();
  TextColumn get whatsappPhoneNumberId => text().nullable()();
  TextColumn get whatsappAccessToken => text().nullable()();

  /// Not needed to send, but kept so the owner can see which business account
  /// the credentials belong to when several people share a Meta setup.
  TextColumn get whatsappBusinessAccountId => text().nullable()();

  /// The number members see messages arrive from. Display only.
  TextColumn get whatsappBusinessNumber => text().nullable()();

  /// The approved template a receipt is sent as, and the language it was
  /// registered under.
  ///
  /// Editable rather than hard coded because both live in Meta's Business
  /// Manager, not here: the owner can register a differently named template, or
  /// register one under `en_US` instead of `en`, and a mismatch reads as
  /// "template does not exist" with nothing in the app to point at. Correcting
  /// a typo must not need a new release.
  TextColumn get whatsappReceiptTemplate =>
      text().withDefault(const Constant('payment_receipt'))();
  TextColumn get whatsappReceiptTemplateLanguage =>
      text().withDefault(const Constant('en'))();

  /// The approved template a new member's welcome message is sent as, if the
  /// gym has registered one.
  ///
  /// Null rather than defaulted like [whatsappReceiptTemplate]: a gym mid
  /// upgrade has not necessarily registered this template yet, and the
  /// welcome message still has a free-text fallback the receipt never had (see
  /// `MemberWelcomeService`). A gym that fills this in gets a message that
  /// reaches a brand new member even though they have never messaged the
  /// business first — free text cannot, since Meta only allows it inside the
  /// 24-hour window a member's own message opens, and a member has almost
  /// never messaged before they have even been welcomed.
  TextColumn get whatsappWelcomeTemplate => text().nullable()();
  TextColumn get whatsappWelcomeTemplateLanguage =>
      text().withDefault(const Constant('en'))();

  /// Makes the mock provider fail on demand, so the "WhatsApp failed / Retry"
  /// path can be exercised without breaking anything real.
  BoolColumn get whatsappMockFails =>
      boolean().withDefault(const Constant(false))();

  /// 'dark' or 'light'. Text rather than a boolean so adding a 'system' option
  /// later needs no migration. Dark is the default the gym has been using.
  TextColumn get themeMode => text().withDefault(const Constant('dark'))();

  /// When the app last asked GitHub whether a newer release exists. Null means
  /// never, which is what an install upgraded from an earlier version reads as.
  DateTimeColumn get lastUpdateCheckAt => dateTime().nullable()();

  /// A version the owner answered "Later" to, so the banner stops asking about
  /// that one and starts again at the next release.
  TextColumn get dismissedUpdateVersion => text().nullable()();

  // --- Payment reminders ---------------------------------------------------

  /// Whether reminders may leave the app without the owner pressing Send.
  ///
  /// Off by default, on every install and every upgrade. The Reminders screen
  /// works either way; this only decides whether an app being opened is also
  /// an app that starts messaging people.
  BoolColumn get reminderAutoSend =>
      boolean().withDefault(const Constant(false))();

  /// Days before the due date to nudge, and days after it to chase, as
  /// comma-separated lists ("3", "3,7").
  ///
  /// Text rather than a column per offset so the owner can have two overdue
  /// reminders, or none, without a migration each time — the same reason
  /// [themeMode] is text. Parsed by `parseOffsetDays`, which drops anything
  /// unreadable rather than throwing on a settings row.
  TextColumn get reminderDaysBefore =>
      text().withDefault(const Constant('3'))();
  TextColumn get reminderDaysAfter =>
      text().withDefault(const Constant('3,7'))();

  BoolColumn get reminderOnDueDate =>
      boolean().withDefault(const Constant(true))();

  /// The gym's own hours on the wall clock, 0-23. Nothing is sent outside
  /// them, so opening the app at half past six does not wake the membership.
  IntColumn get reminderSendFromHour =>
      integer().withDefault(const Constant(9))();
  IntColumn get reminderSendUntilHour =>
      integer().withDefault(const Constant(21))();

  /// A ceiling on one automatic run, so reopening the app after a fortnight
  /// shut does not fire off the whole roster at once.
  IntColumn get reminderMaxPerRun =>
      integer().withDefault(const Constant(25))();

  /// The approved template a reminder travels as, and its language.
  ///
  /// Separate from the receipt template because Meta approves each template
  /// individually and the two say different things. Null means reminders
  /// cannot be sent through Meta yet — reported on the Reminders screen rather
  /// than failing per member.
  TextColumn get whatsappReminderTemplate => text().nullable()();
  TextColumn get whatsappReminderTemplateLanguage =>
      text().withDefault(const Constant('en'))();

  /// How a member is meant to pay, in the owner's own words — "Pay at the
  /// counter, or Easypaisa to 0300-1234567". Goes into the reminder so the
  /// message tells the member what to actually do.
  ///
  /// Defaulted rather than left blank: an empty reminder line reads as
  /// unfinished, and cash-or-online is a true answer for every gym this app
  /// has shipped to so far.
  TextColumn get paymentInstructions =>
      text().nullable().withDefault(const Constant('Pay Cash/Online'))();

  @override
  Set<Column> get primaryKey => {id};
}

class MembershipPlans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get durationMonths => integer()();
  IntColumn get priceMinor => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class Members extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Human-friendly member ID, sourced from the ledger's "Enroll." column.
  IntColumn get memberCode => integer().unique()();
  TextColumn get fullName => text()();

  /// Normalized E.164, e.g. +923000000022.
  TextColumn get phone => text()();

  /// The number exactly as originally entered or imported.
  TextColumn get phoneRaw => text().nullable()();
  TextColumn get email => text().nullable()();

  /// "Male" or "Female". The gym separates members by gender, not by any
  /// notion of branches or shifts.
  TextColumn get gender => text().nullable()();
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get emergencyContact => text().nullable()();
  DateTimeColumn get joiningDate => dateTime()();

  /// Soft deactivation — members are never deleted, so financial history lives on.
  DateTimeColumn get deactivatedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// One row per plan enrolment. Changing plan closes the old row (endDate) and
/// opens a new one, so membership history is preserved rather than overwritten.
class Memberships extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();
  IntColumn get planId => integer().references(MembershipPlans, #id)();

  /// Custom per-member pricing; falls back to the plan price when null.
  IntColumn get feeOverrideMinor => integer().nullable()();
  DateTimeColumn get startDate => dateTime()();

  /// The day of the month this member is billed on, 1-31.
  ///
  /// Nullable, and that is deliberate rather than lazy: every billing cycle
  /// recorded before this column existed starts on the 1st of a month, so a
  /// membership with no anchor resolves to the 1st and its cycles keep landing
  /// exactly where they always have. The upgrade therefore writes no rows and
  /// moves nobody's due date. See `resolveAnchorDay` in domain/billing_cycle.
  ///
  /// A month too short to hold the day clamps to its last — 31 becomes 28 in
  /// February — without losing the anchor for the month after.
  IntColumn get billingAnchorDay => integer().nullable()();

  /// Null means this is the member's currently active enrolment.
  DateTimeColumn get endDate => dateTime().nullable()();
}

/// One billing cycle: `[periodStart, periodEnd)`.
///
/// Boundaries are UTC midnights. A cycle's fee falls due on its **start** — the
/// gym is paid in advance — so a member's next due date is the start of their
/// first unsettled cycle.
class MembershipPeriods extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get membershipId => integer().references(Memberships, #id)();
  DateTimeColumn get periodStart => dateTime()();

  /// Exclusive end of the cycle.
  DateTimeColumn get periodEnd => dateTime()();

  /// Fee snapshot at creation time, so later price changes don't rewrite history.
  IntColumn get expectedAmountMinor => integer()();

  /// When the cycle was closed, or null while it still owes money.
  ///
  /// Set once [PaymentAllocations] against the cycle reach
  /// [expectedAmountMinor]; a cycle holding less than that is part-paid, not
  /// paid. Settlement used to be inferred from the mere existence of a
  /// payment, which marked a 500-rupee instalment against a 3,000-rupee fee as
  /// a month fully settled.
  ///
  /// It is also how history is grandfathered. The v10 migration stamps every
  /// cycle that already had a payment against it, so the imported ledger stays
  /// closed under the new rule without a cutoff date being tested anywhere in
  /// the code.
  DateTimeColumn get settledAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {membershipId, periodStart},
      ];
}

class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();
  IntColumn get membershipPeriodId =>
      integer().nullable().references(MembershipPeriods, #id)();
  IntColumn get amountMinor => integer()();
  TextColumn get method => textEnum<PaymentMethod>()();
  TextColumn get referenceNumber => text().nullable()();
  DateTimeColumn get paymentDate => dateTime()();
  TextColumn get notes => text().nullable()();
  TextColumn get source =>
      textEnum<PaymentSource>().withDefault(const Constant('manual'))();
  IntColumn get recordedById => integer().references(Users, #id)();

  /// Set when a recorded payment is corrected. The receipt is re-rendered in
  /// place under its original number, so without these two columns nothing on
  /// the row itself would show it had ever been touched. Null means never
  /// edited, which is what every row predating v7 reads as.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  IntColumn get updatedById => integer().nullable().references(Users, #id)();

  /// Unique per submission — the accidental double-click guard.
  TextColumn get idempotencyKey => text().unique()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// How much of one payment went to which billing cycle.
///
/// A payment used to point at a single cycle, which could not describe either
/// of the two things the gym actually does: paying part of a month now and the
/// rest later, and handing over three months' fees at once for one receipt.
/// Both are the same shape — money spread across cycles — so both go through
/// here.
///
/// [Payments.membershipPeriodId] is kept alongside this, pointing at the first
/// cycle the money touched. It is what the ledger importer, the payment editor
/// and every existing query still read, so this table adds a capability
/// without taking one away.
class PaymentAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Cascades: deleting a payment must release the cycles it was settling, or
  /// they would stay closed with no money behind them.
  IntColumn get paymentId =>
      integer().references(Payments, #id, onDelete: KeyAction.cascade)();

  IntColumn get membershipPeriodId =>
      integer().references(MembershipPeriods, #id, onDelete: KeyAction.cascade)();

  /// Minor units, matching [Payments.amountMinor]. The allocations for one
  /// payment always sum to no more than the payment itself.
  IntColumn get amountMinor => integer()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// One payment touches a given cycle at most once — a second contribution to
  /// the same cycle is a second payment, with its own receipt.
  @override
  List<Set<Column>> get uniqueKeys => [
        {paymentId, membershipPeriodId},
      ];
}

/// One row per scheduled payment reminder, sent or otherwise.
///
/// The unique key is the duplicate guard, and it is enforced by SQLite rather
/// than by reading before writing. That matters because reminders are computed
/// on app open: two windows opening at once, or an automatic run overlapping a
/// manual one, would both read "not sent yet" and both send. The same bargain
/// [Payments.idempotencyKey] makes about a double-clicked Save.
class PaymentReminders extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Null for a reminder about a cycle that has not been billed yet — a
  /// "before due" nudge fires days ahead of the cycle even existing as a row,
  /// deliberately: materialising one just to hang a reminder off it would mean
  /// a cycle nobody has been charged for reading as debt. See
  /// `BillingCycleService`'s note on not creating cycles speculatively. Set
  /// once a matching cycle exists, for the on-the-day and overdue stages.
  IntColumn get membershipPeriodId => integer()
      .nullable()
      .references(MembershipPeriods, #id, onDelete: KeyAction.cascade)();

  /// Copied alongside the cycle so the Reminders screen can list by member
  /// without joining through memberships.
  ///
  /// Cascades for the same reason [membershipPeriodId] does: a "before due"
  /// reminder can exist for a member with no billed cycle at all, so deleting
  /// a member cannot rely on cascading through membershipPeriods to reach it.
  IntColumn get memberId =>
      integer().references(Members, #id, onDelete: KeyAction.cascade)();

  /// `ReminderStage.name`, stored as text rather than as a `textEnum`.
  ///
  /// The stage lives in `domain/reminder_schedule.dart`, and a reminder log is
  /// exactly the place a later release wants to start recording a new kind of
  /// nudge without a migration — the same reasoning as [AuditEvents.action].
  TextColumn get stage => text()();

  /// Days from the due date. Zero for the reminder on the day itself. Paired
  /// with [stage] because "three days overdue" and "seven days overdue" are two
  /// different messages against one cycle.
  IntColumn get offsetDays => integer()();

  TextColumn get status => textEnum<ReminderSendStatus>()();

  /// The cycle's due date at the time the reminder was resolved, copied so the
  /// history stays readable if the cycle is later re-anchored. Part of the
  /// duplicate guard together with [memberId], [stage] and [offsetDays] —
  /// [membershipPeriodId] cannot serve that role since it is not always set.
  DateTimeColumn get dueDate => dateTime()();

  /// What was owed when the reminder went out. Minor units.
  IntColumn get amountMinor => integer()();

  TextColumn get externalMessageId => text().nullable()();
  TextColumn get errorMessage => text().nullable()();

  /// Retries update this row rather than inserting another, so the unique key
  /// can stay the duplicate guard. The count is kept for the owner to see.
  IntColumn get attempts => integer().withDefault(const Constant(1))();

  DateTimeColumn get sentAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {memberId, stage, offsetDays, dueDate},
      ];
}

class Receipts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get receiptNumber => text().unique()();
  IntColumn get paymentId => integer().unique().references(Payments, #id)();
  TextColumn get pngPath => text()();
  TextColumn get pdfPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Per-year sequence for receipt numbers, incremented inside the payment
/// transaction so two concurrent payments can never share a number.
class ReceiptCounters extends Table {
  IntColumn get year => integer()();
  IntColumn get lastNumber => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {year};
}

/// One row per send attempt. A retry inserts a new row (attemptNumber + 1)
/// rather than mutating the previous attempt, preserving the full history.
class WhatsAppMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get receiptId => integer().references(Receipts, #id)();
  IntColumn get memberId => integer().references(Members, #id)();
  TextColumn get phone => text()();
  TextColumn get provider => textEnum<WhatsAppProviderKind>()();
  TextColumn get externalMessageId => text().nullable()();
  TextColumn get status =>
      textEnum<WhatsAppStatus>().withDefault(const Constant('queued'))();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get attemptNumber => integer().withDefault(const Constant(1))();
  DateTimeColumn get sentAt => dateTime().nullable()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  DateTimeColumn get failedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class MemberNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get memberId => integer().references(Members, #id)();
  TextColumn get body => text()();
  IntColumn get createdById => integer().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// One row per meaningful business mutation, written for the owner to read.
///
/// Deliberately holds **no foreign keys** to members or payments. Foreign keys
/// are enforced on every connection, so a reference to the row being deleted
/// would either block the deletion this event exists to record, or be cascaded
/// away together with it. The member's name, the receipt number, the amount and
/// the period label are copied in instead — that copy is the whole point, and
/// is what keeps a deletion legible after its subject is gone.
class AuditEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => textEnum<AuditCategory>()();

  /// Dotted machine name, e.g. 'payment.edited'. Paired with [summary] rather
  /// than shown to the owner directly.
  TextColumn get action => text()();
  TextColumn get outcome => textEnum<AuditOutcome>()();

  /// Who did it. Copied, not referenced — see the class comment.
  IntColumn get actorId => integer().nullable()();
  TextColumn get actorName => text().nullable()();

  /// What it was done to. Also copied.
  IntColumn get memberId => integer().nullable()();
  TextColumn get memberName => text().nullable()();
  IntColumn get paymentId => integer().nullable()();
  TextColumn get receiptNumber => text().nullable()();

  /// Minor units, matching Payments.amountMinor.
  IntColumn get amountMinor => integer().nullable()();

  /// Already formatted, e.g. "August 2026 - October 2026". Stored rather than
  /// derived because the cycle it describes may no longer exist.
  TextColumn get periodLabel => text().nullable()();

  /// One readable line, e.g. "Payment edited for Ali Raza (RMF-2026-000012)".
  TextColumn get summary => text()();

  /// Supporting detail, one "Field: before → after" per line, or an error
  /// category. Never holds tokens, credentials or raw API response bodies.
  TextColumn get detail => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
