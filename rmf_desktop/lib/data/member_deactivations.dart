import 'package:drift/drift.dart';

import 'database.dart';

/// The member's missed-payment deactivation still in force, if any. See
/// `services/payment_inactivity_service.dart`.
Future<MemberDeactivation?> openDeactivationFor(
  AppDatabase db,
  int memberId,
) =>
    (db.select(db.memberDeactivations)
          ..where((d) => d.memberId.equals(memberId) & d.reactivatedAt.isNull())
          ..orderBy([(d) => OrderingTerm.desc(d.deactivatedAt)])
          ..limit(1))
        .getSingleOrNull();

/// Every open missed-payment deactivation, keyed by member — one read for the
/// whole member list.
Future<Map<int, MemberDeactivation>> openDeactivationsByMember(
    AppDatabase db) async {
  final rows = await (db.select(db.memberDeactivations)
        ..where((d) => d.reactivatedAt.isNull())
        ..orderBy([(d) => OrderingTerm(expression: d.deactivatedAt)]))
      .get();
  return {for (final row in rows) row.memberId: row};
}

/// One bill that is written off right now, and what it was before.
typedef WriteOff = ({int amountMinor, DateTime periodEnd, DateTime writtenOffAt});

/// The bills written off for missed payments that still are, by cycle id. A
/// short list: it grows by a month or two each time somebody lapses.
///
/// "Still" matters. A write-off the owner took back by reinstating the member
/// is a bill again, and so is one whose month the owner named on a payment —
/// the cycle keeps its id either way. Counting those would leave "paid until"
/// stuck before months the member has since paid.
Future<Map<int, WriteOff>> currentWriteOffs(AppDatabase db) async {
  final w = db.inactivityWaivers;
  final d = db.memberDeactivations;
  final p = db.membershipPeriods;
  final query = db.select(w).join([
    innerJoin(d, d.id.equalsExp(w.deactivationId)),
    innerJoin(p, p.id.equalsExp(w.membershipPeriodId)),
  ])
    ..where(d.reinstated.equals(false) &
        p.expectedAmountMinor.equals(0) &
        p.settledAt.isNotNull());
  return {
    for (final row in await query.get())
      row.readTable(w).membershipPeriodId: (
        amountMinor: row.readTable(w).amountMinor,
        periodEnd: row.readTable(w).periodEnd.toUtc(),
        writtenOffAt: row.readTable(d).deactivatedAt.toUtc(),
      ),
  };
}

/// Closes [memberId]'s open missed-payment deactivation, when they are
/// reactivated by any route. What it wrote off stays written off.
Future<void> closeDeactivationFor(
  AppDatabase db,
  int memberId, {
  int? actorId,
  DateTime? at,
}) async {
  await (db.update(db.memberDeactivations)
        ..where((d) => d.memberId.equals(memberId) & d.reactivatedAt.isNull()))
      .write(MemberDeactivationsCompanion(
    reactivatedAt: Value((at ?? DateTime.now()).toUtc()),
    reactivatedById: Value(actorId),
  ));
}
