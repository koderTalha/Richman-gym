import 'package:drift/drift.dart';

import '../data/database.dart';
import 'ledger_import.dart';

class ImportSummary {
  const ImportSummary({
    required this.membersCreated,
    required this.membersMatched,
    required this.paymentsCreated,
    required this.paymentsSkipped,
    required this.rowsNeedingAttention,
  });

  final int membersCreated;
  final int membersMatched;

  final int paymentsCreated;

  /// Cycles that already had a payment — re-importing the same sheet is safe.
  final int paymentsSkipped;
  final int rowsNeedingAttention;
}

class ImportService {
  ImportService(this.db);

  final AppDatabase db;

  /// Writes a parsed ledger into the database.
  ///
  /// Imported payments are marked `PaymentSource.imported`, which is what keeps
  /// the WhatsApp step from ever firing for historical rows — nobody wants a
  /// receipt for a cash payment collected two years ago.
  ///
  /// Re-running the same sheet does not duplicate anything: members are matched
  /// on phone number, and a billing cycle that already has a payment is skipped.
  Future<ImportSummary> commit({
    required ParsedLedger ledger,
    required int planId,
    required int recordedById,
  }) async {
    var membersCreated = 0;
    var membersMatched = 0;
    var paymentsCreated = 0;
    var paymentsSkipped = 0;

    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(planId)))
        .getSingle();

    await db.transaction(() async {
      for (final row in ledger.valid) {
        // Members with no recorded phone are imported too — they simply cannot
        // receive WhatsApp receipts. Empty string, never null, so the column
        // stays non-nullable and comparisons stay simple.
        final phone = row.normalizedPhone ?? '';

        // Matching on an empty phone would collapse every phoneless member into
        // one record, so fall back to the ledger's enrolment number instead.
        Member? member;
        if (phone.isNotEmpty) {
          member = await (db.select(db.members)
                ..where((m) => m.phone.equals(phone)))
              .getSingleOrNull();
        } else if (row.memberCode != null) {
          member = await (db.select(db.members)
                ..where((m) => m.memberCode.equals(row.memberCode!)))
              .getSingleOrNull();
        }

        int memberId;
        if (member != null) {
          memberId = member.id;
          membersMatched++;
        } else {
          // Keep the ledger's enrolment number when it is free, otherwise
          // continue from the highest existing one.
          var code = row.memberCode;
          if (code != null) {
            final clash = await (db.select(db.members)
                  ..where((m) => m.memberCode.equals(code!)))
                .getSingleOrNull();
            if (clash != null) code = null;
          }
          code ??= await _nextMemberCode();

          final joiningDate = _earliestPeriod(row, ledger.year);

          memberId = await db.into(db.members).insert(
                MembersCompanion.insert(
                  memberCode: code,
                  fullName: row.name,
                  phone: phone,
                  phoneRaw: Value(row.rawPhone),
                  joiningDate: joiningDate,
                ),
              );
          membersCreated++;

          if (row.notes != null && row.notes!.trim().isNotEmpty) {
            await db.into(db.memberNotes).insert(
                  MemberNotesCompanion.insert(
                    memberId: memberId,
                    body: row.notes!.trim(),
                    createdById: recordedById,
                  ),
                );
          }
        }

        // Reuse the active enrolment if there is one, so re-importing another
        // year's sheet does not create a second membership.
        var membership = await (db.select(db.memberships)
              ..where((m) => m.memberId.equals(memberId) & m.endDate.isNull()))
            .getSingleOrNull();

        membership ??= await db.into(db.memberships).insertReturning(
              MembershipsCompanion.insert(
                memberId: memberId,
                planId: planId,
                startDate: _earliestPeriod(row, ledger.year),
              ),
            );

        for (final payment in row.payments) {
          // A ### cell means the month was paid but the sheet did not show the
          // figure, so bill it at the member's own rate.
          final amountMinor = payment.amountMinor ??
              membership.feeOverrideMinor ??
              plan.priceMinor;

          final periodStart = DateTime.utc(ledger.year, payment.month, 1);
          final periodEnd = DateTime.utc(
              ledger.year, payment.month + plan.durationMonths, 1);

          var period = await (db.select(db.membershipPeriods)
                ..where((p) =>
                    p.membershipId.equals(membership!.id) &
                    p.periodStart.equals(periodStart)))
              .getSingleOrNull();

          period ??= await db.into(db.membershipPeriods).insertReturning(
                MembershipPeriodsCompanion.insert(
                  membershipId: membership.id,
                  periodStart: periodStart,
                  periodEnd: periodEnd,
                  expectedAmountMinor: amountMinor,
                ),
              );

          final existing = await (db.select(db.payments)
                ..where((p) => p.membershipPeriodId.equals(period!.id)))
              .getSingleOrNull();

          if (existing != null) {
            paymentsSkipped++;
            continue;
          }

          await db.into(db.payments).insert(
                PaymentsCompanion.insert(
                  memberId: memberId,
                  membershipPeriodId: Value(period.id),
                  amountMinor: amountMinor,
                  method: PaymentMethod.cash,
                  referenceNumber: Value(row.reference),
                  paymentDate: periodStart,
                  source: const Value(PaymentSource.imported),
                  recordedById: recordedById,
                  idempotencyKey:
                      'import-${ledger.year}-$memberId-${payment.month}',
                ),
              );
          paymentsCreated++;
        }
      }
    });

    return ImportSummary(
      membersCreated: membersCreated,
      membersMatched: membersMatched,
      paymentsCreated: paymentsCreated,
      paymentsSkipped: paymentsSkipped,
      rowsNeedingAttention: ledger.invalid.length,
    );
  }

  DateTime _earliestPeriod(ParsedMemberRow row, int year) {
    if (row.payments.isEmpty) return DateTime.utc(year, 1, 1);
    final month =
        row.payments.map((p) => p.month).reduce((a, b) => a < b ? a : b);
    return DateTime.utc(year, month, 1);
  }

  Future<int> _nextMemberCode() async {
    final result = await (db.selectOnly(db.members)
          ..addColumns([db.members.memberCode.max()]))
        .getSingleOrNull();
    return (result?.read(db.members.memberCode.max()) ?? 0) + 1;
  }
}
