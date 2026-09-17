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

/// The recorded fee cut a cycle starting on [periodStart] was billed in breach
/// of, if there is one. Null means the record does not accuse this cycle of
/// anything.
///
/// This is the evidence the historical review reads, and it has to hold up as
/// evidence, because the only thing a member gets out of it is a bill they no
/// longer have to pay. Three things must all be true:
///
///   * The change was meant to apply **from on or before** the cycle's start,
///     so the cycle was billed after the new fee was supposedly in force.
///   * Nothing **replaced** it by then. The latest change effective by the
///     cycle's start is the fee that should have been charged; an earlier one
///     it superseded — including a cut later undone by a rise — says nothing
///     about what this cycle should have cost.
///   * The cycle was billed **above** the figure that change lowered to. A
///     cycle billed at exactly the new fee honoured the cut, and whatever it
///     asks above today's price is arrears at the price in force at the time,
///     not a mispricing. Forgiving those is the one mistake this screen must
///     never make.
MembershipChange? cutCovering(
  List<MembershipChange> changes, {
  required DateTime periodStart,
  required int billedMinor,
}) {
  final start = _midnight(periodStart);

  // The fee that should have been in force when the cycle opened: the latest
  // change effective by then, whether it raised or lowered. Found by comparison
  // rather than by position, so a caller's ordering cannot change the answer.
  MembershipChange? governing;
  for (final change in changes) {
    final effective = _midnight(change.effectiveFrom);
    if (effective.isAfter(start)) continue;
    if (governing == null) {
      governing = change;
      continue;
    }
    final incumbent = _midnight(governing.effectiveFrom);
    if (effective.isAfter(incumbent) ||
        (effective.isAtSameMomentAs(incumbent) && change.id > governing.id)) {
      governing = change;
    }
  }

  if (governing == null) return null;

  final previousFee = governing.previousFeeMinor;
  final fee = governing.feeMinor;
  if (previousFee == null || fee == null || fee >= previousFee) return null;
  if (billedMinor <= fee) return null;

  return governing;
}

DateTime _midnight(DateTime at) {
  final utc = at.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}
