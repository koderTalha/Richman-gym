import 'package:drift/drift.dart';

import '../data/cycle_pricing_log.dart';
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
    this.membersLapsed = 0,
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

  /// Members the sheet shows having stopped coming, brought in deactivated for
  /// the owner to reinstate if they are wrong. Counted inside
  /// [membersAddedAsInactive], which is every member who arrived inactive
  /// whatever the reason.
  final int membersLapsed;
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

/// One enrolment written for a ledger row, and the month it takes over from.
class _Enrolment {
  const _Enrolment({required this.fromMonth, required this.membership});
  final int fromMonth;
  final Membership membership;
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
  /// [planId] is the plan chosen in the wizard. It applies to every row the
  /// sheet does not name a plan for; a row that names one is enrolled on that
  /// plan instead — see [ParsedMemberRow.planId]. A member already on file
  /// keeps the enrolment they are on either way, because a sheet recording what
  /// somebody paid in 2024 is not an instruction to move them off the plan they
  /// train on now.
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
    var membersLapsed = 0;
    var paymentsCreated = 0;
    var paymentsSkipped = 0;

    final at = (now ?? DateTime.now()).toUtc();
    final isHistoricalLedger = ledger.year < at.year;

    // Dated to the end of the year the sheet covers, so the record says when
    // they were last known to be a member rather than when the file was read.
    final leftAt =
        isHistoricalLedger ? DateTime.utc(ledger.year, 12, 31) : null;

    // Every plan rather than just the wizard's: with a "Plan" column each row
    // can name its own, and the fee a ### month falls back to is the price of
    // the plan that row actually names.
    final plansById = {
      for (final plan in await db.select(db.membershipPlans).get())
        plan.id: plan
    };

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

          // A member whose sheet ends in a run of unpaid months stopped coming,
          // and is brought in deactivated rather than billed from next month
          // like somebody who still trains here. Dated to the end of the last
          // month they paid for, so the record says when they were last known
          // to be a member. The owner reinstates anyone this is wrong about —
          // a cheap mistake to correct, and a much cheaper one to make than
          // chasing three hundred people who left.
          final lapsedAt =
              leftAt ?? (row.hasLapsed ? _lastMonthPaidFor(row, ledger.year) : null);

          memberId = await db.into(db.members).insert(
                MembersCompanion.insert(
                  memberCode: code,
                  fullName: row.name,
                  phone: phone,
                  phoneRaw: Value(row.rawPhone),
                  joiningDate: joiningDate,
                  deactivatedAt: Value(lapsedAt),
                ),
              );
          membersCreated++;
          if (lapsedAt != null) membersAddedAsInactive++;
          if (leftAt == null && row.hasLapsed) membersLapsed++;
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

        final namedPlan = plansById[row.planId ?? planId]!;

        // Reuse the open enrolment if there is one, so re-importing another
        // year's sheet does not create a second membership. This is also why a
        // "Plan" column cannot move an existing member: their enrolment already
        // says which plan they are on, and only the owner changes that.
        final existing = await openMembershipFor(db, memberId);
        final enrolments = existing != null
            ? [_Enrolment(fromMonth: 1, membership: existing)]
            : await _enrolmentsFor(
                memberId: memberId,
                row: row,
                year: ledger.year,
                namedPlan: namedPlan,
                plansById: plansById,
              );

        // The enrolment billing carries on under, which is the last one the
        // sheet leaves the member on.
        final openEnrolment = enrolments.last.membership;

        for (final payment in row.payments) {
          // The enrolment the member was on that month, which on a sheet
          // showing its figures is often not the one they are on now.
          final onPlan = _enrolmentCovering(enrolments, payment.month);
          final cyclePlan = plansById[onPlan.planId]!;

          // A ### cell means the month was paid but the sheet did not show the
          // figure, so bill it at the member's own rate.
          final amountMinor = payment.amountMinor ??
              onPlan.feeOverrideMinor ??
              cyclePlan.priceMinor;

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
          //
          // Matched by containment, so a ledger column falling inside a
          // multi-month cycle recorded through the app is recognised as
          // already billed instead of opening a second, overlapping cycle.
          var period = await periodForMemberContaining(
            db,
            memberId: memberId,
            month: periodStart,
          );

          if (period == null) {
            period = await db.into(db.membershipPeriods).insertReturning(
                  MembershipPeriodsCompanion.insert(
                    membershipId: onPlan.id,
                    periodStart: periodStart,
                    periodEnd: periodEnd,
                    expectedAmountMinor: amountMinor,
                  ),
                );
            // The ledger's own figure, which is what the member was actually
            // charged that month and is not derivable from any plan. Saying so
            // stops a later reader taking it for a plan price that has since
            // moved.
            await recordCycleOpened(
              db,
              membershipPeriodId: period.id,
              amountMinor: amountMinor,
              membership: onPlan,
              source: CyclePricingSource.ledgerImport,
              reason: "Read from the owner's spreadsheet ledger.",
            );
          }

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

          final paymentId = await db.into(db.payments).insert(
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

          // The ledger names no fee separate from what was actually paid — see
          // `expectedAmountMinor: amountMinor` above — so this always settles
          // the cycle outright; there is no such thing as an imported month
          // read as partly paid.
          await db.into(db.paymentAllocations).insert(
                PaymentAllocationsCompanion.insert(
                  paymentId: paymentId,
                  membershipPeriodId: period.id,
                  amountMinor: amountMinor,
                ),
              );
          final periodId = period.id;
          await (db.update(db.membershipPeriods)
                ..where((p) => p.id.equals(periodId)))
              .write(MembershipPeriodsCompanion(
                  settledAt: Value(periodStart)));

          paymentsCreated++;
        }

        // Nobody arrives owing anything. A member the ledger has just
        // introduced is covered up to their first real bill, so the months in
        // the sheet stay history and the app starts billing them fresh.
        // Members already on file are left alone: the app knows their state,
        // and a spreadsheet is not an instruction to forgive what it says.
        // Nobody deactivated is covered: they are not being billed at all, and
        // a cycle running to a bill they will never be sent reads as though
        // somebody still expects them.
        if (resolved == null && !isHistoricalLedger && !row.hasLapsed) {
          await _coverUntilFirstBill(
            membership: openEnrolment,
            memberId: memberId,
            anchorDay: row.anchorDay,
            at: at,
          );
        }
      }
    });

    return ImportSummary(
      membersCreated: membersCreated,
      membersMatched: membersMatched,
      membersMergedByName: membersMergedByName,
      membersAddedAsInactive: membersAddedAsInactive,
      membersLapsed: membersLapsed,
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

  /// Covers a newly imported member from where the ledger leaves them up to
  /// their first bill under the app, so the import itself owes nothing.
  ///
  /// The sheet cannot say who owed money. A "0" against March is both "he was
  /// a member and did not pay" and "he had already left", and the ledger has no
  /// column that tells the two apart — so reading debt out of it would invent
  /// receivables for hundreds of people who simply stopped coming. Instead
  /// everything up to the import is treated as closed, and the first month the
  /// app bills for is the first one it can actually vouch for.
  ///
  /// The cycle written here is zero-cost and stamped settled, which is what
  /// keeps `BillingMaintenance` from rolling anyone a bill for the month the
  /// import happened in: it rolls forward from the member's latest cycle end,
  /// and that end is now their first billing day. It is logged like any other
  /// cycle so the waiver is visible afterwards rather than implied.
  Future<void> _coverUntilFirstBill({
    required Membership membership,
    required int memberId,
    required int? anchorDay,
    required DateTime at,
  }) async {
    final periods = await periodsForMember(db, memberId);
    final coveredTo = periods.isEmpty
        ? null
        : periods
            .map((p) => p.periodEnd.toUtc())
            .reduce((a, b) => a.isAfter(b) ? a : b);

    final from = coveredTo ?? membership.startDate.toUtc();
    final firstBill = _firstBillAfter(at, anchorDay ?? from.day);

    // Already covered past their first billing day, which is what paying
    // several months ahead looks like. Nothing to bridge.
    if (!firstBill.isAfter(from)) return;

    final period = await db.into(db.membershipPeriods).insertReturning(
          MembershipPeriodsCompanion.insert(
            membershipId: membership.id,
            periodStart: from,
            periodEnd: firstBill,
            expectedAmountMinor: 0,
            settledAt: Value(from),
          ),
        );

    await recordCycleOpened(
      db,
      membershipPeriodId: period.id,
      amountMinor: 0,
      membership: membership,
      source: CyclePricingSource.ledgerImport,
      reason: 'Covered by the ledger import: months before the import are '
          'history, and billing starts on the first billing day after it.',
    );
  }

  /// The member's billing day in the month after [at].
  ///
  /// Clamped to the last day of a month too short to hold it, so an anchor of
  /// the 31st bills on the 30th in November without losing the 31st.
  DateTime _firstBillAfter(DateTime at, int anchorDay) {
    final month = DateTime.utc(at.year, at.month + 1, 1);
    final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
    return DateTime.utc(
      month.year,
      month.month,
      anchorDay < lastDay ? anchorDay : lastDay,
    );
  }

  Future<Payment?> _paymentWithKey(String key) async {
    final rows = await (db.select(db.payments)
          ..where((p) => p.idempotencyKey.equals(key))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Writes the enrolments a ledger row implies, oldest first.
  ///
  /// The sheet has one "Plan" column and it names the plan the member is on
  /// *now*, but the monthly figures show what they were paying at the time —
  /// and on the owner's real ledger most members have moved at least once.
  /// Recording the whole year against their current plan would leave months
  /// priced at a fee that plan never charged, so each stretch of months at one
  /// fee becomes its own enrolment, closed off where the fee moved.
  ///
  /// Only the last stays open, and only it carries the billing day: the earlier
  /// ones are history and will never be billed again. See
  /// [ParsedMemberRow.planSegments] for which fees are allowed to imply a plan
  /// in the first place.
  Future<List<_Enrolment>> _enrolmentsFor({
    required int memberId,
    required ParsedMemberRow row,
    required int year,
    required MembershipPlan namedPlan,
    required Map<int, MembershipPlan> plansById,
  }) async {
    final segments = row.planSegments;

    // No payments at all, so no fees to read a history out of.
    if (segments.isEmpty) {
      final only = await db.into(db.memberships).insertReturning(
            MembershipsCompanion.insert(
              memberId: memberId,
              planId: namedPlan.id,
              startDate: _earliestPeriod(row, year),
              billingAnchorDay: Value(row.anchorDay),
            ),
          );
      return [_Enrolment(fromMonth: 1, membership: only)];
    }

    final written = <_Enrolment>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isOpen = i == segments.length - 1;
      final plan =
          segment.planId == null ? namedPlan : plansById[segment.planId]!;

      final membership = await db.into(db.memberships).insertReturning(
            MembershipsCompanion.insert(
              memberId: memberId,
              planId: plan.id,
              startDate: DateTime.utc(year, segment.startMonth, 1),
              endDate: Value(isOpen
                  ? null
                  : DateTime.utc(year, segments[i + 1].startMonth, 1)),
              billingAnchorDay: Value(isOpen ? row.anchorDay : null),
            ),
          );
      written.add(
          _Enrolment(fromMonth: segment.startMonth, membership: membership));
    }
    return written;
  }

  /// The enrolment in force in [month], which is the latest one starting on or
  /// before it.
  Membership _enrolmentCovering(List<_Enrolment> enrolments, int month) {
    var covering = enrolments.first.membership;
    for (final enrolment in enrolments) {
      if (enrolment.fromMonth > month) break;
      covering = enrolment.membership;
    }
    return covering;
  }

  /// The end of the last month the member paid for, which is the last day they
  /// are known to have been a member.
  DateTime? _lastMonthPaidFor(ParsedMemberRow row, int year) {
    if (row.payments.isEmpty) return null;
    final month =
        row.payments.map((p) => p.month).reduce((a, b) => a > b ? a : b);
    return DateTime.utc(year, month + 1, 1);
  }

  DateTime _earliestPeriod(ParsedMemberRow row, int year) {
    if (row.payments.isEmpty) return DateTime.utc(year, 1, 1);
    final month =
        row.payments.map((p) => p.month).reduce((a, b) => a < b ? a : b);
    return DateTime.utc(year, month, 1);
  }
}
