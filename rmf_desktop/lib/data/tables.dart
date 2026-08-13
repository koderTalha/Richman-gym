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

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get role => textEnum<UserRole>().withDefault(const Constant('admin'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
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

  /// Makes the mock provider fail on demand, so the "WhatsApp failed / Retry"
  /// path can be exercised without breaking anything real.
  BoolColumn get whatsappMockFails =>
      boolean().withDefault(const Constant(false))();

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

  /// Null means this is the member's currently active enrolment.
  DateTimeColumn get endDate => dateTime().nullable()();
}

/// One billing cycle — the equivalent of a single month column in the ledger.
/// Paid-vs-due is never stored here; it is derived from whether a Payment exists.
class MembershipPeriods extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get membershipId => integer().references(Memberships, #id)();
  DateTimeColumn get periodStart => dateTime()();

  /// Exclusive end of the cycle.
  DateTimeColumn get periodEnd => dateTime()();

  /// Fee snapshot at creation time, so later price changes don't rewrite history.
  IntColumn get expectedAmountMinor => integer()();

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

  /// Unique per submission — the accidental double-click guard.
  TextColumn get idempotencyKey => text().unique()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
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
