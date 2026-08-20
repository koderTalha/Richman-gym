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

/// Whether any payment is already recorded against [period].
Future<Payment?> paymentForPeriod(AppDatabase db, int periodId) async {
  final rows = await (db.select(db.payments)
        ..where((p) => p.membershipPeriodId.equals(periodId))
        ..limit(1))
      .get();
  return rows.isEmpty ? null : rows.first;
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
