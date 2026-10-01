import 'dart:math' as math;

import 'package:drift/drift.dart';

import 'database.dart';

/// Enrolment and billing-cycle lookups, in one place.
///
/// Changing a member's plan closes their enrolment and opens a new one, so a
/// member accumulates several `Memberships` rows over time while remaining one
/// person with one continuous payment history. Every caller that asked "which
/// cycles has this member got?" by filtering on the *open* enrolment was
/// therefore reading only the history since their last plan change — which made
/// a paid member read DUE, and made the importer think an already-imported
/// month was new.
///
/// These helpers answer that question per *member*, which is the unit the
/// owner actually thinks in.

/// How many ids one `IN (...)` may carry.
///
/// SQLite refuses a statement binding more than 32,766 variables ("too many
/// SQL variables"), and a roster-wide query binds one per id. The gym's cycles
/// grow by a month per member per month, so a query that names every cycle
/// stops working at around 32,000 of them — and with it the Dashboard and the
/// Members screen, which load everyone at once. Well under the limit, and
/// large enough that a roster is a handful of round trips.
const idChunkSize = 900;

/// [ids] in pieces of at most [idChunkSize], for queries that name them.
Iterable<List<int>> idChunks(List<int> ids) sync* {
  for (var i = 0; i < ids.length; i += idChunkSize) {
    yield ids.sublist(i, math.min(i + idChunkSize, ids.length));
  }
}

/// The member's current enrolment, or null if they have none.
///
/// Tolerant of a database that somehow holds two open enrolments for one
/// member: the newest wins rather than the lookup throwing and taking the
/// member's whole screen down with it. A unique index in [AppDatabase] stops
/// new ones appearing; this copes with any that predate it.
Future<Membership?> openMembershipFor(AppDatabase db, int memberId) async {
  final rows = await (db.select(db.memberships)
        ..where((m) => m.memberId.equals(memberId) & m.endDate.isNull())
        ..orderBy([(m) => OrderingTerm(expression: m.id, mode: OrderingMode.desc)])
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.first;
}

/// Every enrolment the member has ever had, open or closed.
Future<List<Membership>> allMembershipsFor(AppDatabase db, int memberId) =>
    (db.select(db.memberships)..where((m) => m.memberId.equals(memberId))).get();

/// The member's billing cycle starting at [periodStart], whichever enrolment it
/// was created under.
///
/// This is what stops a plan change from making an already-recorded month look
/// unbilled — which produced a duplicate payment on re-import and a duplicate
/// charge from the Record Payment form.
Future<MembershipPeriod?> periodForMemberStarting(
  AppDatabase db, {
  required int memberId,
  required DateTime periodStart,
}) async {
  final membershipIds =
      (await allMembershipsFor(db, memberId)).map((m) => m.id).toList();
  if (membershipIds.isEmpty) return null;

  final rows = await (db.select(db.membershipPeriods)
        ..where((p) =>
            p.membershipId.isIn(membershipIds) &
            p.periodStart.equals(periodStart))
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.first;
}

/// Whether any payment is already recorded against [periodId], leaving out
/// [excludingPaymentId] — the payment being corrected, which must not count
/// as already occupying the cycle it is on.
///
/// Read from the allocations as well as `payments.membership_period_id`. That
/// column names only the *first* cycle a payment touched, so a payment
/// covering January to March answered "no" here for February and March: the
/// duplicate warning stayed silent and the same month could be taken twice.
/// The column is still consulted for rows that predate allocations.
Future<Payment?> paymentForPeriod(
  AppDatabase db,
  int periodId, {
  int? excludingPaymentId,
}) async {
  final allocated = db.selectOnly(db.paymentAllocations)
    ..addColumns([db.paymentAllocations.paymentId])
    ..where(db.paymentAllocations.membershipPeriodId.equals(periodId));

  var query = db.select(db.payments)
    ..where((p) =>
        p.membershipPeriodId.equals(periodId) | p.id.isInQuery(allocated));
  if (excludingPaymentId != null) {
    query = query..where((p) => p.id.equals(excludingPaymentId).not());
  }
  final rows = await (query
        ..orderBy([(p) => OrderingTerm(expression: p.id)])
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.first;
}

/// Every cycle that any of [memberId]'s payments has money in, leaving out
/// [excludingPaymentId]. The same reading of "paid" as [paymentForPeriod], for
/// the whole member at once.
Future<Set<int>> periodIdsWithPaymentsFor(
  AppDatabase db,
  int memberId, {
  int? excludingPaymentId,
}) async {
  var payments = db.select(db.payments)
    ..where((p) => p.memberId.equals(memberId));
  if (excludingPaymentId != null) {
    payments = payments..where((p) => p.id.equals(excludingPaymentId).not());
  }
  final rows = await payments.get();
  if (rows.isEmpty) return const {};

  final allocated = await (db.select(db.paymentAllocations)
        ..where((a) => a.paymentId.isIn([for (final p in rows) p.id])))
      .get();

  return {
    for (final p in rows)
      if (p.membershipPeriodId != null) p.membershipPeriodId!,
    for (final a in allocated) a.membershipPeriodId,
  };
}

/// The member's billing cycle that *contains* [month], whichever enrolment it
/// belongs to.
///
/// Distinct from [periodForMemberStarting], and the reason a multi-month plan
/// cannot be billed twice for the same cycle: on a three-month plan there is no
/// cycle *starting* in September, but September sits squarely inside the
/// August-October one. A lookup matching only the start month found nothing
/// there, so the duplicate warning stayed silent and a second payment could be
/// taken for a cycle already settled.
///
/// Comparisons are against UTC-anchored boundaries, matching how cycles are
/// stored: start inclusive, end exclusive.
Future<MembershipPeriod?> periodForMemberContaining(
  AppDatabase db, {
  required int memberId,
  required DateTime month,
}) async {
  final membershipIds =
      (await allMembershipsFor(db, memberId)).map((m) => m.id).toList();
  if (membershipIds.isEmpty) return null;

  final at = month.toUtc();

  final rows = await (db.select(db.membershipPeriods)
        ..where((p) =>
            p.membershipId.isIn(membershipIds) &
            p.periodStart.isSmallerOrEqualValue(at) &
            p.periodEnd.isBiggerThanValue(at))
        ..orderBy([
          (p) => OrderingTerm(
              expression: p.periodStart, mode: OrderingMode.desc)
        ])
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.first;
}

/// Every billing cycle the member has, oldest first.
Future<List<MembershipPeriod>> periodsForMember(
  AppDatabase db,
  int memberId,
) async {
  final membershipIds =
      (await allMembershipsFor(db, memberId)).map((m) => m.id).toList();
  if (membershipIds.isEmpty) return const [];

  return (db.select(db.membershipPeriods)
        ..where((p) => p.membershipId.isIn(membershipIds))
        ..orderBy([(p) => OrderingTerm(expression: p.periodStart)]))
      .get();
}

/// How much has been allocated to each of [periodIds].
///
/// One grouped query rather than one per cycle: the members screen and the
/// reminder queue both ask this about the whole roster at once.
Future<Map<int, int>> collectedByPeriod(
  AppDatabase db,
  List<int> periodIds,
) async {
  if (periodIds.isEmpty) return const {};

  final total = db.paymentAllocations.amountMinor.sum();
  final collected = <int, int>{};
  for (final chunk in idChunks(periodIds)) {
    final rows = await (db.selectOnly(db.paymentAllocations)
          ..addColumns([db.paymentAllocations.membershipPeriodId, total])
          ..where(db.paymentAllocations.membershipPeriodId.isIn(chunk))
          ..groupBy([db.paymentAllocations.membershipPeriodId]))
        .get();
    for (final row in rows) {
      collected[row.read(db.paymentAllocations.membershipPeriodId)!] =
          row.read(total) ?? 0;
    }
  }
  return collected;
}

/// Every allocation belonging to [paymentId].
Future<List<PaymentAllocation>> allocationsForPayment(
  AppDatabase db,
  int paymentId,
) =>
    (db.select(db.paymentAllocations)
          ..where((a) => a.paymentId.equals(paymentId))
          ..orderBy([(a) => OrderingTerm(expression: a.membershipPeriodId)]))
        .get();

/// The member's latest cycle on any enrolment, or null if they have none.
///
/// This is where the next cycle begins, and — for a membership with no anchor
/// column — the day its anchor resolves to.
Future<MembershipPeriod?> latestPeriodForMember(
  AppDatabase db,
  int memberId,
) async {
  final membershipIds =
      (await allMembershipsFor(db, memberId)).map((m) => m.id).toList();
  if (membershipIds.isEmpty) return null;

  final rows = await (db.select(db.membershipPeriods)
        ..where((p) => p.membershipId.isIn(membershipIds))
        ..orderBy([
          (p) => OrderingTerm(
              expression: p.periodEnd, mode: OrderingMode.desc),
        ])
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.first;
}

/// Which of [periodIds] have at least one allocation recorded against them.
///
/// Used to tell a cycle settled under the balance rule apart from one whose
/// only evidence of payment is a raw historical row with no allocation at
/// all — the shape a database predating v10, or a test fixture that writes
/// straight to the payments table, leaves behind. See
/// `MemberRepository._buildRows`.
Future<Set<int>> periodsWithAnyAllocation(
  AppDatabase db,
  List<int> periodIds,
) async {
  if (periodIds.isEmpty) return const {};

  final found = <int>{};
  for (final chunk in idChunks(periodIds)) {
    final rows = await (db.selectOnly(db.paymentAllocations, distinct: true)
          ..addColumns([db.paymentAllocations.membershipPeriodId])
          ..where(db.paymentAllocations.membershipPeriodId.isIn(chunk)))
        .get();
    for (final row in rows) {
      final id = row.read(db.paymentAllocations.membershipPeriodId);
      if (id != null) found.add(id);
    }
  }
  return found;
}
