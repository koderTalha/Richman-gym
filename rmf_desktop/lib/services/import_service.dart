import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/membership_queries.dart';
import '../domain/name.dart';
import 'ledger_import.dart';

class ImportSummary {
  const ImportSummary({
    required this.membersCreated,
    required this.membersMatched,
    required this.membersMergedByName,
    required this.membersAddedAsInactive,
    required this.paymentsCreated,
    required this.paymentsSkipped,
    required this.rowsNeedingAttention,
  });

  final int membersCreated;
  final int membersMatched;

  /// Rows recognised on name alone, because they carry neither a phone number
  /// nor an enrolment number. Two different people with the same name and no
  /// other detail are indistinguishable, so these are reported separately for
  /// the owner to check rather than folded into [membersMatched].
  final int membersMergedByName;

  final int paymentsCreated;

  /// Cycles that already had a payment — re-importing the same sheet is safe.
  final int paymentsSkipped;
  final int rowsNeedingAttention;

  /// Members created from a ledger for a year that has already ended, and so
  /// added as inactive. See [ImportService.commit].
  final int membersAddedAsInactive;
}

/// A member already on file, held in memory for the length of one import.
///
/// The importer used to issue a `SELECT ... WHERE phone = ?` for every row,
/// which on a thousand-row sheet against a thousand-member gym meant a million
/// row comparisons inside a single write transaction, with the window frozen
/// throughout. Loading the roster once and indexing it costs one query.
class _Roster {
  _Roster(List<Member> members) {
    for (final member in members) {
      _add(member.id, member.phone, member.fullName, member.memberCode);
    }
  }

  final _byPhone = <String, List<_Candidate>>{};
  final _takenCodes = <int>{};
  final _phonelessByCode = <int, _Candidate>{};

  /// First writer wins, so re-importing a sheet keeps resolving each name to
  /// the member it created the first time.
  final _phonelessByName = <String, _Candidate>{};
  var _highestCode = 0;

  void _add(int id, String phone, String fullName, int memberCode) {
    final candidate = _Candidate(id, fullName, memberCode);
    if (phone.isEmpty) {
      _phonelessByName.putIfAbsent(normalizeName(fullName), () => candidate);
      _phonelessByCode[memberCode] = candidate;
    } else {
      _byPhone.putIfAbsent(phone, () => []).add(candidate);
    }
    _takenCodes.add(memberCode);
    if (memberCode > _highestCode) _highestCode = memberCode;
  }

  /// Records a member created during this import, so later rows in the same
  /// sheet — and the next import of it — recognise them.
  void remember({
    required int id,
    required String phone,
    required String fullName,
    required int memberCode,
  }) =>
      _add(id, phone, fullName, memberCode);

  List<_Candidate> onPhone(String phone) => _byPhone[phone] ?? const [];

  bool codeIsTaken(int code) => _takenCodes.contains(code);

  _Candidate? phonelessWithCode(int code) => _phonelessByCode[code];

  _Candidate? phonelessNamed(String fullName) =>
      _phonelessByName[normalizeName(fullName)];

  int nextCode() => ++_highestCode;
}

class _Candidate {
  const _Candidate(this.id, this.fullName, this.memberCode);
  final int id;
  final String fullName;
  final int memberCode;
}

/// How a ledger row was recognised as somebody already on file.
enum _MatchKind {
  /// On a key the sheet actually carries: phone plus name, or an enrolment
  /// number. Trustworthy enough to pass over in the summary.
  matched,

  /// On a matching name and nothing else, because the row has neither a phone
  /// number nor an enrolment number. Reported separately: two people with the
  /// same name and no other detail are indistinguishable from here, and only
  /// the owner can say whether the merge was right.
  mergedByName,
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
  /// Re-running the same sheet does not duplicate anything: rows are resolved
  /// to members by the ladder in [_resolve], and a month the member has already
  /// been billed for is skipped whichever enrolment recorded it.
  ///
  /// A member who appears for the first time in a ledger for a year that has
  /// already ended is created **inactive**. A 2023 sheet is a record of who was
  /// a member in 2023, not of who trains here now, and the sheet has no column
  /// saying who left. Treating everyone in it as current puts a fresh unpaid
  /// month on hundreds of people who stopped coming years ago, and buries the
  /// members who really do owe money this month. The owner reactivates whoever
  /// is still turning up — a decision only they can make, made once, on a
  /// screen built for it. [now] exists so this is testable.
  Future<ImportSummary> commit({
    required ParsedLedger ledger,
    required int planId,
    required int recordedById,
    DateTime? now,
  }) async {
    var membersCreated = 0;
    var membersMatched = 0;
    var membersMergedByName = 0;
    var membersAddedAsInactive = 0;
    var paymentsCreated = 0;
    var paymentsSkipped = 0;

    final at = (now ?? DateTime.now()).toUtc();
    final isHistoricalLedger = ledger.year < at.year;

    // Dated to the end of the year the sheet covers, so the record says when
    // they were last known to be a member rather than when the file was read.
    final leftAt =
        isHistoricalLedger ? DateTime.utc(ledger.year, 12, 31) : null;

    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(planId)))
        .getSingle();

    await db.transaction(() async {
      final roster = _Roster(await db.select(db.members).get());

      for (final row in ledger.valid) {
        // Members with no recorded phone are imported too — they simply cannot
        // receive WhatsApp receipts. Empty string, never null, so the column
        // stays non-nullable and comparisons stay simple.
        final phone = row.normalizedPhone ?? '';
        final resolved = _resolve(roster, row: row, phone: phone);

        int memberId;
        if (resolved != null) {
          memberId = resolved.id;
          membersMatched++;
          if (resolved.kind == _MatchKind.mergedByName) membersMergedByName++;
        } else {
          // Keep the ledger's enrolment number when it is free, otherwise
          // continue from the highest existing one.
          var code = row.memberCode;
          if (code == null || roster.codeIsTaken(code)) code = roster.nextCode();

          final joiningDate = _earliestPeriod(row, ledger.year);

          memberId = await db.into(db.members).insert(
                MembersCompanion.insert(
                  memberCode: code,
                  fullName: row.name,
                  phone: phone,
                  phoneRaw: Value(row.rawPhone),
                  joiningDate: joiningDate,
                  deactivatedAt: Value(leftAt),
                ),
              );
          membersCreated++;
          if (leftAt != null) membersAddedAsInactive++;
          roster.remember(
            id: memberId,
            phone: phone,
            fullName: row.name,
            memberCode: code,
          );

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

        // Reuse the open enrolment if there is one, so re-importing another
        // year's sheet does not create a second membership.
        var membership = await openMembershipFor(db, memberId);

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

          // One ledger column is one month, whatever plan the import is
          // assigned to. Stretching each column to the plan's own length made
          // consecutive paid months overlap — a quarterly plan turned Jan and
          // Feb into Jan–Apr and Feb–May, two cycles covering the same days,
          // after which status, billing maintenance and the ledger export all
          // disagreed about which one counted.
          final periodEnd = DateTime.utc(ledger.year, payment.month + 1, 1);

          // Scoped to the member rather than to one enrolment: a plan change
          // opens a new enrolment, and the cycle this month was billed under
          // may well belong to the old one.
          var period = await periodForMemberStarting(
            db,
            memberId: memberId,
            periodStart: periodStart,
          );

          period ??= await db.into(db.membershipPeriods).insertReturning(
                MembershipPeriodsCompanion.insert(
                  membershipId: membership.id,
                  periodStart: periodStart,
                  periodEnd: periodEnd,
                  expectedAmountMinor: amountMinor,
                ),
              );

          if (await paymentForPeriod(db, period.id) != null) {
            paymentsSkipped++;
            continue;
          }

          // The key is unique across the whole table, so a row that was
          // imported once and whose cycle has since moved to another enrolment
          // would otherwise collide here and abort the entire import.
          final idempotencyKey =
              'import-${ledger.year}-$memberId-${payment.month}';
          if (await _paymentWithKey(idempotencyKey) != null) {
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
                  idempotencyKey: idempotencyKey,
                ),
              );
          paymentsCreated++;
        }
      }
    });

    return ImportSummary(
      membersCreated: membersCreated,
      membersMatched: membersMatched,
      membersMergedByName: membersMergedByName,
      membersAddedAsInactive: membersAddedAsInactive,
      paymentsCreated: paymentsCreated,
      paymentsSkipped: paymentsSkipped,
      rowsNeedingAttention: ledger.invalid.length,
    );
  }

  /// Decides whether a ledger row is somebody already on file.
  ///
  /// The ladder, strongest key first:
  ///
  ///  1. **Phone + name.** One number can cover a whole family — the gym's
  ///     members include an elder brother registered under his younger
  ///     brother's phone — so the number alone does not identify a person.
  ///  2. **Phone + enrolment number.** The same number, the same "Enroll."
  ///     value, a different spelling of the name: that is one person whose name
  ///     was corrected since the last import, not a new member. Without this
  ///     step, fixing a typo in the app made the next re-import duplicate them
  ///     and double-count the year's revenue.
  ///  3. **Enrolment number among phoneless members.** Scoped to members who
  ///     are themselves phoneless, so a row with no number cannot claim
  ///     somebody who has one on file.
  ///  4. **Name among phoneless members.** All a sheet with no "Enroll." column
  ///     offers. Reported separately in the summary, because two different
  ///     people recorded with the same name and nothing else are genuinely
  ///     indistinguishable here.
  ({int id, _MatchKind kind})? _resolve(
    _Roster roster, {
    required ParsedMemberRow row,
    required String phone,
  }) {
    if (phone.isNotEmpty) {
      final sharing = roster.onPhone(phone);

      for (final candidate in sharing) {
        if (namesMatch(candidate.fullName, row.name)) {
          return (id: candidate.id, kind: _MatchKind.matched);
        }
      }

      if (row.memberCode != null) {
        for (final candidate in sharing) {
          if (candidate.memberCode == row.memberCode) {
            return (id: candidate.id, kind: _MatchKind.matched);
          }
        }
      }
      return null;
    }

    // No phone number. Everything below is scoped to members who are themselves
    // phoneless, so a row with no number can never claim somebody who has one.
    if (row.memberCode != null) {
      final byCode = roster.phonelessWithCode(row.memberCode!);
      if (byCode != null) return (id: byCode.id, kind: _MatchKind.matched);
    }

    final byName = roster.phonelessNamed(row.name);
    if (byName == null) return null;

    // The sheet gives this row an enrolment number, and the namesake already on
    // file carries a different one: the sheet is telling us they are two
    // people, and its own key beats a coincidence of spelling.
    if (row.memberCode != null && byName.memberCode != row.memberCode) {
      return null;
    }

    return (id: byName.id, kind: _MatchKind.mergedByName);
  }

  Future<Payment?> _paymentWithKey(String key) async {
    final rows = await (db.select(db.payments)
          ..where((p) => p.idempotencyKey.equals(key))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  DateTime _earliestPeriod(ParsedMemberRow row, int year) {
    if (row.payments.isEmpty) return DateTime.utc(year, 1, 1);
    final month =
        row.payments.map((p) => p.month).reduce((a, b) => a < b ? a : b);
    return DateTime.utc(year, month, 1);
  }
}
