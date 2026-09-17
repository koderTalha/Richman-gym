import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import 'database.dart';

final _log = Logger('billing');

/// What a member used to be billed, and from when the new figure applies.
///
/// `memberships` already keeps enrolment history by closing one row and
/// opening another, and that was enough while the only question asked of it
/// was "which plan are they on". It cannot answer the two questions that
/// actually mattered when forty-three members were found stranded:
///
///   * **what were they billed before?** The closed enrolment names a plan,
///     and the plan's price has since moved, so the figure the member was
///     genuinely charged is no longer readable from it.
///   * **from when was the new fee meant to apply?** `startDate` is when the
///     row was written, which is the same thing only when nobody is correcting
///     anything.
///
/// Both are recorded here, and [MembershipChanges.effectiveFrom] is kept apart
/// from [MembershipChanges.recordedAt] precisely so the second question has an
/// answer. Equal, they describe an ordinary plan change made on the day. Apart,
/// they describe the owner saying the new fee was always meant to apply from
/// earlier — and that statement is the evidence that separates a bill priced
/// under a superseded plan from a debt the member genuinely ran up.
///
/// Nothing here re-prices anything. A back-dated change never rewrites a cycle
/// that has already ended; it makes that cycle answerable on the historical
/// review screen. See `services/historical_pricing_review.dart`.

/// Records one change to what [memberId] is billed.
///
/// Never throws, for the same reason [AuditRepository.record] does not: the
/// money has already moved by the time this is called, and a history row that
/// could not be written must not undo it.
Future<void> recordMembershipChange(
  AppDatabase db, {
  required int memberId,
  required DateTime effectiveFrom,
  int? previousMembershipId,
  int? membershipId,
  int? previousPlanId,
  String? previousPlanName,
  int? planId,
  String? planName,
  int? previousFeeMinor,
  int? feeMinor,
  String? reason,
  int? actorId,
  DateTime? recordedAt,
}) async {
  try {
    await db.into(db.membershipChanges).insert(MembershipChangesCompanion.insert(
          memberId: memberId,
          previousMembershipId: Value(previousMembershipId),
          membershipId: Value(membershipId),
          previousPlanId: Value(previousPlanId),
          previousPlanName: Value(previousPlanName),
          planId: Value(planId),
          planName: Value(planName),
          previousFeeMinor: Value(previousFeeMinor),
          feeMinor: Value(feeMinor),
          effectiveFrom: _midnight(effectiveFrom),
          recordedAt: Value((recordedAt ?? DateTime.now()).toUtc()),
          reason: Value(reason),
          actorId: Value(actorId),
        ));
  } catch (error, stack) {
    _log.severe(
      'The membership change for member $memberId could not be stored. '
      'The change itself is unaffected.',
      error,
      stack,
    );
  }
}

/// Every recorded change for [memberId], newest first.
Future<List<MembershipChange>> membershipChangesFor(
  AppDatabase db,
  int memberId,
) =>
    (db.select(db.membershipChanges)
          ..where((c) => c.memberId.equals(memberId))
          ..orderBy([
            (c) => OrderingTerm(
                expression: c.effectiveFrom, mode: OrderingMode.desc),
            (c) => OrderingTerm(expression: c.id, mode: OrderingMode.desc),
          ]))
        .get();

/// The recorded fee cuts that cover a cycle starting on [periodStart].
///
/// A change covers the cycle when it was meant to apply from on or before the
/// cycle's start — the cycle was therefore billed after the new, lower fee was
/// supposedly already in force — and when it actually lowered the fee.
///
/// This is the evidence the historical review reads. A cut recorded *after*
/// the cycle it covers had already been billed is the fingerprint of a cycle
/// opened under a superseded price; a cut recorded before it is an ordinary
/// change the cycle should already have followed.
List<MembershipChange> cutsCovering(
  List<MembershipChange> changes, {
  required DateTime periodStart,
}) {
  final start = _midnight(periodStart);
  return [
    for (final change in changes)
      if (change.previousFeeMinor != null &&
          change.feeMinor != null &&
          change.feeMinor! < change.previousFeeMinor! &&
          !_midnight(change.effectiveFrom).isAfter(start))
        change,
  ];
}

DateTime _midnight(DateTime at) {
  final utc = at.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
