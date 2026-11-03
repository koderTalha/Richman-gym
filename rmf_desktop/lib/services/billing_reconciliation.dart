import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/database.dart';
import '../domain/dates.dart';
import '../domain/money.dart';

final _log = Logger('billing');

/// Finding members an earlier release left permanently owing money.
///
/// Until `cycle_repricing.dart` existed, raising a member's fee left their
/// already-open cycle at the old price. The owner collected the new price, the
/// difference did not fit, and under arrears-first allocation it spilled
/// forward and opened the *next* cycle early, part-paid. A cycle row is a
/// debt, so from then on the member had one more cycle open than they had been
/// billed for, and every later payment cleared the previous shortfall while
/// creating an identical one. They paid in full every month and the app showed
/// them owing the difference for ever.
///
/// **Nothing here rewrites anything.** In the database a treadmilled payment
/// is indistinguishable from a genuine arrears payment — a member who really
/// did owe a cheaper month and cleared it while part-paying the current one
/// leaves exactly the same rows. Correcting one automatically would mean
/// rewriting the other, so the decision stays with the owner, who knows what
/// was actually agreed. This only points at the members worth looking at.
///
/// The test is the one contradiction that is safe to assert: the member has
/// handed over **at least as much as they have been billed for**, and the app
/// still shows them owing. Somebody genuinely behind has paid *less* than they
/// were billed and is never flagged; somebody simply paid up in advance owes
/// nothing and is never flagged either. It takes both halves to be wrong.

/// A member whose money does not agree with what the app says they owe.
class BillingDiscrepancy {
  const BillingDiscrepancy({
    required this.member,
    required this.paidMinor,
    required this.billedMinor,
    required this.outstandingMinor,
    required this.owingCycle,
  });

  final Member member;

  /// Every rupee the member has ever handed over.
  final int paidMinor;

  /// What they have been billed for cycles that have actually begun.
  ///
  /// Cycles that have not started yet are deliberately excluded: opening one
  /// early is the bug itself, and counting it would hide the very credit that
  /// gives the member away.
  final int billedMinor;

  /// What the app is currently telling the owner they owe.
  final int outstandingMinor;

  /// The cycle that outstanding balance sits on.
  final MembershipPeriod owingCycle;

  /// How far ahead the member actually is.
  int get creditMinor => paidMinor - billedMinor;

  String get summary => '${member.fullName} shows '
      '${formatMinorUnits(outstandingMinor)} due but has paid '
      '${formatMinorUnits(creditMinor)} more than they have been billed';
}

/// Every active member whose payments and outstanding balance contradict.
///
/// Nothing here reads the clock — callers pass [now] in, the same bargain
/// `BillingMaintenance` makes.
Future<List<BillingDiscrepancy>> findBillingDiscrepancies(
  AppDatabase db, {
  DateTime? now,
}) async {
  final at = (now ?? DateTime.now()).toUtc();
  final today = DateTime.utc(at.year, at.month, at.day);

  // Somebody who has left the gym stopped accruing cycles when they were
  // deactivated, so their books are expected not to balance.
  final members = await (db.select(db.members)
        ..where((m) => m.deactivatedAt.isNull()))
      .get();

  final found = <BillingDiscrepancy>[];
  if (members.isEmpty) return found;

  // Everything the per-member test needs, read once for the whole roster
  // rather than six queries a member: at launch this ran for every active
  // member, and was most of the second the gym waited for the window.
  final books = await _Books.load(db);

  for (final member in members) {
    final periods = books.periodsByMember[member.id] ?? const [];
    if (periods.isEmpty) continue;

    // The earliest cycle still owing, which is the one the members screen
    // reports — see `MemberRepository._buildRows`.
    final owing = periods.where((p) => !books.isSettled(p)).firstOrNull;
    if (owing == null) continue;

    final outstanding =
        owing.expectedAmountMinor - (books.collected[owing.id] ?? 0);
    if (outstanding <= 0) continue;

    final billed = periods
        .where((p) => !p.periodStart.toUtc().isAfter(today))
        .fold(0, (sum, p) => sum + p.expectedAmountMinor);
    final paid = books.paidByMember[member.id] ?? 0;

    if (paid < billed) continue;

    found.add(BillingDiscrepancy(
      member: member,
      paidMinor: paid,
      billedMinor: billed,
      outstandingMinor: outstanding,
      owingCycle: owing,
    ));
  }

  return found;
}

/// Records what [findBillingDiscrepancies] found, so the owner meets it in the
/// Logs screen rather than having to be told to go looking.
///
/// A member already reported is not reported again: the log is opened to be
/// read, and the same handful of members repeated every morning would push
/// everything else off it.
Future<int> reportBillingDiscrepancies(
  AppDatabase db, {
  DateTime? now,
  AuditRepository? audit,
}) async {
  final found = await findBillingDiscrepancies(db, now: now);
  if (found.isEmpty) return 0;

  final repository = audit ?? AuditRepository(db);
  final alreadyReported = await _membersAlreadyReported(db);

  var recorded = 0;
  for (final discrepancy in found) {
    if (alreadyReported.contains(discrepancy.member.id)) continue;

    await repository.record(
      category: AuditCategory.billing,
      action: AuditAction.billingDiscrepancyFound,
      // Not a failure: the app is declining to guess which of two identical
      // sets of rows it is looking at, which is the same thing `refused`
      // records everywhere else.
      outcome: AuditOutcome.refused,
      memberId: discrepancy.member.id,
      memberName: discrepancy.member.fullName,
      amountMinor: discrepancy.outstandingMinor,
      summary: discrepancy.summary,
      detail: [
        'Paid in total: ${formatMinorUnits(discrepancy.paidMinor)}.',
        'Billed for cycles that have begun: '
            '${formatMinorUnits(discrepancy.billedMinor)}.',
        'Still shown as owing: '
            '${formatMinorUnits(discrepancy.outstandingMinor)} on the cycle '
            'starting '
            '${formatDayMonthYear(discrepancy.owingCycle.periodStart)}.',
        'This is the shape a fee rise left behind before the fee reached the '
            'cycle the member was already in. Check their payment history: if '
            'the money is right, correct the billing month on the payment that '
            'covers two cycles.',
        'Nothing has been changed automatically — a genuine arrears payment '
            'looks identical.',
      ],
    );
    recorded++;
  }

  if (recorded > 0) {
    _log.warning('$recorded member(s) have payments that do not reconcile');
  }
  return recorded;
}

/// The roster's cycles and money, loaded together for
/// [findBillingDiscrepancies].
class _Books {
  _Books._(this.periodsByMember, this._allocated, this._linked,
      this.collected, this.paidByMember);

  /// Every member's cycles across all their enrolments, oldest first — what
  /// `periodsForMember` returns, for everyone at once.
  final Map<int, List<MembershipPeriod>> periodsByMember;

  /// Cycles with an allocation against them.
  final Set<int> _allocated;

  /// Cycles a payment names in its own column.
  final Set<int> _linked;

  /// Money allocated to each cycle.
  final Map<int, int> collected;

  /// Everything each member has ever paid.
  final Map<int, int> paidByMember;

  /// Closed by its stamp, or — for history with no allocations at all — by
  /// a payment naming it. The same rule `MemberRepository._buildRows` applies.
  bool isSettled(MembershipPeriod period) =>
      period.settledAt != null ||
      (!_allocated.contains(period.id) && _linked.contains(period.id));

  static Future<_Books> load(AppDatabase db) async {
    final memberOf = {
      for (final m in await db.select(db.memberships).get()) m.id: m.memberId,
    };

    final periodsByMember = <int, List<MembershipPeriod>>{};
    for (final period in await (db.select(db.membershipPeriods)
          ..orderBy([
            (p) => OrderingTerm(expression: p.periodStart),
            (p) => OrderingTerm(expression: p.id),
          ]))
        .get()) {
      final memberId = memberOf[period.membershipId];
      if (memberId == null) continue;
      periodsByMember.putIfAbsent(memberId, () => []).add(period);
    }

    final allocated = {
      for (final row in await (db.selectOnly(db.paymentAllocations,
                  distinct: true)
                ..addColumns([db.paymentAllocations.membershipPeriodId]))
              .get())
        row.read(db.paymentAllocations.membershipPeriodId)!,
    };

    final linked = <int>{
      for (final row in await (db.selectOnly(db.payments, distinct: true)
                ..addColumns([db.payments.membershipPeriodId])
                ..where(db.payments.membershipPeriodId.isNotNull()))
              .get())
        row.read(db.payments.membershipPeriodId)!,
    };

    final allocatedSum = db.paymentAllocations.amountMinor.sum();
    final collected = {
      for (final row in await (db.selectOnly(db.paymentAllocations)
                ..addColumns(
                    [db.paymentAllocations.membershipPeriodId, allocatedSum])
                ..groupBy([db.paymentAllocations.membershipPeriodId]))
              .get())
        row.read(db.paymentAllocations.membershipPeriodId)!:
            row.read(allocatedSum) ?? 0,
    };

    final paidSum = db.payments.amountMinor.sum();
    final paidByMember = {
      for (final row in await (db.selectOnly(db.payments)
                ..addColumns([db.payments.memberId, paidSum])
                ..groupBy([db.payments.memberId]))
              .get())
        row.read(db.payments.memberId)!: row.read(paidSum) ?? 0,
    };

    return _Books._(periodsByMember, allocated, linked, collected, paidByMember);
  }
}

Future<Set<int>> _membersAlreadyReported(AppDatabase db) async {
  final rows = await (db.selectOnly(db.auditEvents, distinct: true)
        ..addColumns([db.auditEvents.memberId])
        ..where(
            db.auditEvents.action.equals(AuditAction.billingDiscrepancyFound)))
      .get();

  return rows
      .map((row) => row.read(db.auditEvents.memberId))
      .whereType<int>()
      .toSet();
}
