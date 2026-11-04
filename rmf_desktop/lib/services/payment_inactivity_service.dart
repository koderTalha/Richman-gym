import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/cycle_pricing_log.dart';
import '../data/database.dart';
import '../data/member_deactivations.dart';
import '../data/membership_queries.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
import '../domain/payment_inactivity.dart';
import 'billing_cycle_service.dart';

final _log = Logger('inactivity');

/// The `reason` a missed-payment deactivation is stored under.
const paymentInactivityReason = 'payment_inactivity';

/// One member the rule has something to say about.
class InactivityCase {
  const InactivityCase({required this.member, required this.verdict});

  final Member member;

  /// [PaymentInactivityLapsed] or [PaymentInactivityReview], or
  /// [PaymentInactivityGrace] for a member on the "deactivating soon" list.
  final PaymentInactivity verdict;
}

/// What the rule would do today, without doing it.
class InactivityPreview {
  const InactivityPreview({
    required this.graceDays,
    required this.lapsed,
    required this.review,
    required this.upcoming,
  });

  final int graceDays;

  /// Would be deactivated, and their lapse written off.
  final List<InactivityCase> lapsed;

  /// Past the deadline, but left for the owner to decide.
  final List<InactivityCase> review;

  /// Will be deactivated within [inactivityWarningDays] unless they pay,
  /// soonest first.
  final List<InactivityCase> upcoming;

  int get waivedMinor => lapsed.fold(
      0,
      (sum, c) => sum + (c.verdict as PaymentInactivityLapsed).waivedMinor);
}

/// One missed-payment deactivation, with the bills it wrote off.
class DeactivationEpisode {
  const DeactivationEpisode({required this.row, required this.waivers});

  final MemberDeactivation row;
  final List<InactivityWaiver> waivers;

  bool get isOpen => row.reactivatedAt == null;
}

/// The answer to "they kept coming — take the write-off back".
sealed class ReinstateResult {
  const ReinstateResult();
}

class MemberReinstated extends ReinstateResult {
  const MemberReinstated({required this.restoredMinor});

  /// What is owed again.
  final int restoredMinor;
}

class ReinstateRefused extends ReinstateResult {
  const ReinstateRefused(this.reason);
  final String reason;
}

/// Deactivates members who have stopped paying, and writes off what their
/// lapse billed.
///
/// The rule is `assessPaymentInactivity`; this is the half that touches the
/// database. A member is deactivated through the same [Members.deactivatedAt]
/// the member screen uses, so everything that already leaves an inactive
/// member alone — the monthly roll, the reminder queue, the dashboard — leaves
/// these members alone too, with no change of its own.
///
/// **The write-off.** Each bill of the lapse is re-priced to nothing and
/// closed: the shape the ledger import's free months already have, which every
/// balance, status and reminder in the app reads as "nothing owed" without
/// knowing write-offs exist. What it was is kept three ways: an
/// [InactivityWaivers] row with the bill's original dates and amount, a
/// `cycle_pricings` row whose previous amount is the original bill, and the
/// audit event. Payments are never touched.
///
/// **Billing stops on the day.** The month running when the member is
/// deactivated is cut short at that day, so a member who returns a week later
/// can be restarted from the day they came back — `restartBilling` refuses to
/// start inside free days. A bill that only starts on or after the day is
/// removed, its copy kept in [InactivityWaivers].
///
/// **The app cannot see who is training.** There is no attendance, only
/// payments, so a member who kept coming but could not pay looks exactly like
/// one who left. The owner tells them apart when the member next pays: either
/// they came back after a gap — the write-off stands and billing restarts — or
/// they never left, and [reinstate] takes the write-off back.
///
/// **Safe to run any number of times.** Each member is re-read and re-judged
/// inside their own transaction, so a payment recorded a moment earlier is
/// seen, a member already deactivated is skipped, and SQLite refuses a second
/// write-off of the same bill. One member failing is logged and does not stop
/// the rest.
class PaymentInactivityService {
  PaymentInactivityService(
    this.db, {
    BillingCycleService? cycles,
    AuditRepository? audit,
  })  : _audit = audit ?? AuditRepository(db),
        _cycles = cycles ?? BillingCycleService(db, audit: audit);

  final AppDatabase db;
  final AuditRepository _audit;
  final BillingCycleService _cycles;

  Future<List<InactivityCase>>? _running;

  Future<bool> isEnabled() async {
    final settings = await db.select(db.gymSettings).getSingleOrNull();
    return settings?.autoDeactivateUnpaid ?? false;
  }

  /// The threshold in force. A stored figure outside the choices — written by
  /// hand, say — falls back to the default rather than switching the rule off
  /// by never being reached.
  Future<int> graceDays() async {
    final settings = await db.select(db.gymSettings).getSingleOrNull();
    final days = settings?.inactivityGraceDays;
    return days != null && inactivityGraceDayChoices.contains(days)
        ? days
        : paymentInactivityGraceDays;
  }

  /// Turns the rule on or off. Does not run it: the caller runs it after
  /// showing the owner what it would do.
  Future<void> setEnabled(bool enabled, {int? actorId}) async {
    if (await isEnabled() == enabled) return;
    await (db.update(db.gymSettings)..where((s) => s.id.equals(1)))
        .write(GymSettingsCompanion(autoDeactivateUnpaid: Value(enabled)));
    await _audit.record(
      category: AuditCategory.billing,
      action: AuditAction.autoDeactivationSwitched,
      outcome: AuditOutcome.success,
      actorId: actorId,
      summary: enabled
          ? 'Automatic deactivation for missed payments switched on'
          : 'Automatic deactivation for missed payments switched off',
    );
  }

  /// Changes the threshold. Like [setEnabled], does not run the rule.
  Future<void> setGraceDays(int days, {int? actorId}) async {
    if (!inactivityGraceDayChoices.contains(days)) {
      throw ArgumentError.value(days, 'days', 'not one of the choices');
    }
    final before = await graceDays();
    if (before == days) return;
    await (db.update(db.gymSettings)..where((s) => s.id.equals(1)))
        .write(GymSettingsCompanion(inactivityGraceDays: Value(days)));
    await _audit.record(
      category: AuditCategory.billing,
      action: AuditAction.inactivityThresholdChanged,
      outcome: AuditOutcome.success,
      actorId: actorId,
      summary: 'Missed-payment threshold changed to $days days',
      detail: ['Days: $before → $days'],
    );
  }

  /// Who the rule would deactivate today, who it would leave for review, and
  /// who it will deactivate within the week. Writes nothing.
  ///
  /// [graceDays] overrides the stored threshold, so the owner can see what a
  /// different one would do before choosing it.
  Future<InactivityPreview> preview({DateTime? now, int? graceDays}) async {
    final today = gymDateOf(now ?? DateTime.now());
    final grace = graceDays ?? await this.graceDays();
    final active = await (db.select(db.members)
          ..where((m) => m.deactivatedAt.isNull())
          ..orderBy([(m) => OrderingTerm(expression: m.memberCode)]))
        .get();
    // One read of each table for the whole roster, not one per member.
    final billing = await _cycles.forMembers(active);
    final reinstatedOn = await _reinstatedOnByMember();

    final lapsed = <InactivityCase>[];
    final review = <InactivityCase>[];
    final upcoming = <InactivityCase>[];
    for (final member in active) {
      final b = billing[member.id];
      if (b == null) continue;
      final verdict = _judge(b, today, grace, reinstatedOn[member.id]);
      switch (verdict) {
        case PaymentInactivityLapsed():
          lapsed.add(InactivityCase(member: member, verdict: verdict));
        case PaymentInactivityReview():
          review.add(InactivityCase(member: member, verdict: verdict));
        case PaymentInactivityGrace(:final deadline):
          if (deadline.difference(today).inDays > inactivityWarningDays) break;
          // Only those the rule will actually deactivate on the day — a
          // part-payer reaching the deadline goes to review, not here.
          final then = _judge(b, deadline, grace, reinstatedOn[member.id]);
          if (then is PaymentInactivityLapsed) {
            upcoming.add(InactivityCase(member: member, verdict: verdict));
          }
        case PaymentInactivityNone():
          break;
      }
    }
    upcoming.sort((a, b) => (a.verdict as PaymentInactivityGrace)
        .deadline
        .compareTo((b.verdict as PaymentInactivityGrace).deadline));
    return InactivityPreview(
      graceDays: grace,
      lapsed: lapsed,
      review: review,
      upcoming: upcoming,
    );
  }

  /// Deactivates everyone the rule says has lapsed. Does nothing while the
  /// rule is switched off, unless [force].
  ///
  /// Never overlaps itself: a second call while one is running gets the first
  /// one's answer. Returns the members it deactivated.
  Future<List<InactivityCase>> run({DateTime? now, bool force = false}) {
    final inFlight = _running;
    if (inFlight != null) return inFlight;
    final run = _run(now: now, force: force);
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<List<InactivityCase>> _run({DateTime? now, required bool force}) async {
    final at = (now ?? DateTime.now()).toUtc();
    // Never throws: the hourly tick runs this unawaited, and startup must not
    // fail over it.
    final List<InactivityCase> candidates;
    try {
      if (!force && !await isEnabled()) return const [];
      candidates = (await preview(now: at)).lapsed;
    } catch (error, stack) {
      _log.severe('Could not check for missed payments', error, stack);
      return const [];
    }

    final done = <InactivityCase>[];
    for (final candidate in candidates) {
      try {
        final result = await _deactivate(candidate.member.id, at);
        if (result != null) done.add(result);
      } catch (error, stack) {
        _log.severe(
            'Could not deactivate member ${candidate.member.id} for missed '
            'payments',
            error,
            stack);
      }
    }
    if (done.isNotEmpty) {
      _log.info('Deactivated ${done.length} member(s) for missed payments');
    }
    return done;
  }

  /// Deactivates one member, if they still qualify once re-read.
  Future<InactivityCase?> _deactivate(int memberId, DateTime at) {
    final today = gymDateOf(at);

    return db.transaction(() async {
      final member = await (db.select(db.members)
            ..where((m) => m.id.equals(memberId)))
          .getSingleOrNull();
      if (member == null || member.deactivatedAt != null) return null;

      // Judged again here, inside the transaction: a payment recorded since
      // the preview was read must keep the member active.
      final billing = await _cycles.forMember(memberId);
      if (billing == null) return null;
      final grace = await graceDays();
      final verdict = _judge(billing, today, grace,
          (await _reinstatedOnByMember(memberId: memberId))[memberId]);
      if (verdict is! PaymentInactivityLapsed) return null;

      final episodeId = await db.into(db.memberDeactivations).insert(
            MemberDeactivationsCompanion.insert(
              memberId: memberId,
              reason: paymentInactivityReason,
              deactivatedAt: at,
              deactivatedOn: today,
              firstMissedDue: verdict.firstMissedDue,
              lastPaidUntil: Value(verdict.lastPaidUntil),
              waivedMinor: verdict.waivedMinor,
              olderArrearsMinor: Value(verdict.olderArrearsMinor),
              graceDays: Value(grace),
            ),
          );

      final reason = 'Written off: ${member.fullName} was deactivated on '
          '${formatDayMonthYear(today)} after the bill due '
          '${formatDayMonthYear(verdict.firstMissedDue)} went $grace days '
          'unpaid.';

      final rows = {
        for (final p in await (db.select(db.membershipPeriods)
              ..where((p) =>
                  p.id.isIn(verdict.toWaive.map((c) => c.periodId!))))
            .get())
          p.id: p,
      };

      for (final cycle in verdict.toWaive) {
        final periodId = cycle.periodId!;
        await db.into(db.inactivityWaivers).insert(
              InactivityWaiversCompanion.insert(
                deactivationId: episodeId,
                memberId: memberId,
                membershipPeriodId: periodId,
                membershipId: rows[periodId]!.membershipId,
                periodStart: cycle.start,
                periodEnd: cycle.end,
                amountMinor: cycle.expectedMinor,
              ),
            );

        // Starts on or after the day: billing has stopped, so the days it
        // would have billed are not billed at all.
        if (!cycle.start.isBefore(today)) {
          await (db.delete(db.membershipPeriods)
                ..where((p) => p.id.equals(periodId)))
              .go();
          continue;
        }

        await (db.update(db.membershipPeriods)
              ..where((p) => p.id.equals(periodId)))
            .write(MembershipPeriodsCompanion(
          expectedAmountMinor: const Value(0),
          settledAt: Value(at),
          // The month running today ends today.
          periodEnd:
              cycle.end.isAfter(today) ? Value(today) : const Value.absent(),
        ));
        await recordCyclePricing(
          db,
          membershipPeriodId: periodId,
          amountMinor: 0,
          previousAmountMinor: cycle.expectedMinor,
          source: CyclePricingSource.inactivityWaiver,
          reason: reason,
          at: at,
        );
      }

      await (db.update(db.members)..where((m) => m.id.equals(memberId)))
          .write(MembersCompanion(deactivatedAt: Value(at)));

      await _audit.record(
        category: AuditCategory.member,
        action: AuditAction.memberDeactivatedForMissedPayments,
        outcome: AuditOutcome.success,
        memberId: memberId,
        memberName: member.fullName,
        amountMinor: verdict.waivedMinor,
        summary: '${member.fullName} deactivated for missed payments',
        detail: [
          'First unpaid bill due ${formatDayMonthYear(verdict.firstMissedDue)}; '
              'nothing paid for $grace days.',
          if (verdict.lastPaidUntil != null)
            'Last paid until ${formatDayMonthYear(verdict.lastPaidUntil!)}.',
          for (final cycle in verdict.toWaive)
            'Written off: ${formatDayMonthYear(cycle.start)} to '
                '${formatDayMonthYear(cycle.end)}, '
                '${formatMinorUnits(cycle.expectedMinor)}.',
          if (verdict.olderArrearsMinor > 0)
            'Older months still owing, not written off: '
                '${formatMinorUnits(verdict.olderArrearsMinor)}.',
          'Payments and receipts are unchanged.',
        ],
      );

      return InactivityCase(member: member, verdict: verdict);
    });
  }

  /// Takes back [memberId]'s open missed-payment deactivation: the owner says
  /// they kept coming all along and could not pay, so they never left.
  ///
  /// Every bill it wrote off is owed again, at its original amount over its
  /// original days — a removed one is put back — and the member is active.
  /// The payment the owner is about to take then settles those months in the
  /// usual order, oldest first. The month that started the lapse is excused
  /// from the rule from now on: having been told the member is still here,
  /// the rule does not deactivate them a second time for the same bill.
  ///
  /// Refused, with nothing changed, if anything has been billed over those
  /// days since — a payment taken while they were inactive that opened later
  /// months. Undoing that is a payment correction, and the owner's to make.
  Future<ReinstateResult> reinstate({
    required int memberId,
    int? actorId,
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final episode = await openDeactivationFor(db, memberId);
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(memberId)))
        .getSingleOrNull();
    if (episode == null || member == null || member.deactivatedAt == null) {
      return const ReinstateRefused(
          'This member is not deactivated for missed payments.');
    }

    final result = await db.transaction<ReinstateResult>(() async {
      final waivers = await (db.select(db.inactivityWaivers)
            ..where((w) => w.deactivationId.equals(episode.id))
            ..orderBy([(w) => OrderingTerm(expression: w.periodStart)]))
          .get();
      final restoring = {for (final w in waivers) w.membershipPeriodId};
      final others = [
        for (final p in await periodsForMember(db, memberId))
          if (!restoring.contains(p.id)) p,
      ];

      for (final w in waivers) {
        final start = w.periodStart.toUtc();
        final end = w.periodEnd.toUtc();
        for (final p in others) {
          if (p.periodStart.toUtc().isBefore(end) &&
              start.isBefore(p.periodEnd.toUtc())) {
            return ReinstateRefused('${member.fullName} has been billed for '
                '${formatDayMonthYear(p.periodStart.toUtc())} to '
                '${formatDayMonthYear(p.periodEnd.toUtc())} since being '
                'deactivated, which overlaps the months to restore. Correct '
                'that payment first, or start them afresh instead.');
          }
        }
      }

      var restored = 0;
      final reason = 'Restored: the owner said ${member.fullName} kept coming '
          'while deactivated for missed payments.';
      for (final w in waivers) {
        final row = await (db.select(db.membershipPeriods)
              ..where((p) => p.id.equals(w.membershipPeriodId)))
            .getSingleOrNull();
        int periodId;
        if (row == null && w.membershipId == 0) {
          // Written off under v16, which did not record the enrolment, and
          // the cycle is gone: there is nowhere to put it back.
          continue;
        } else if (row == null) {
          periodId = await db.into(db.membershipPeriods).insert(
                MembershipPeriodsCompanion.insert(
                  membershipId: w.membershipId,
                  periodStart: w.periodStart.toUtc(),
                  periodEnd: w.periodEnd.toUtc(),
                  expectedAmountMinor: w.amountMinor,
                ),
              );
        } else if (row.expectedAmountMinor == 0 && row.settledAt != null) {
          periodId = row.id;
          await (db.update(db.membershipPeriods)
                ..where((p) => p.id.equals(row.id)))
              .write(MembershipPeriodsCompanion(
            expectedAmountMinor: Value(w.amountMinor),
            settledAt: const Value(null),
            periodEnd: Value(w.periodEnd.toUtc()),
          ));
        } else {
          // Billed again already — the owner named that month on a payment.
          // It is a bill as it stands; nothing to restore.
          continue;
        }
        await recordCyclePricing(
          db,
          membershipPeriodId: periodId,
          amountMinor: w.amountMinor,
          previousAmountMinor: row == null ? null : 0,
          source: CyclePricingSource.inactivityRestored,
          reason: reason,
          actorId: actorId,
          at: at,
        );
        restored += w.amountMinor;
      }

      await (db.update(db.members)..where((m) => m.id.equals(memberId)))
          .write(const MembersCompanion(deactivatedAt: Value(null)));
      await (db.update(db.memberDeactivations)
            ..where((d) => d.id.equals(episode.id)))
          .write(MemberDeactivationsCompanion(
        reactivatedAt: Value(at),
        reactivatedById: Value(actorId),
        reinstated: const Value(true),
      ));

      await _audit.record(
        category: AuditCategory.member,
        action: AuditAction.memberReinstated,
        outcome: AuditOutcome.success,
        actorId: actorId,
        memberId: memberId,
        memberName: member.fullName,
        amountMinor: restored,
        summary: '${member.fullName} reinstated: kept coming while unpaid',
        detail: [
          'Deactivated on ${formatDayMonthYear(episode.deactivatedOn.toUtc())} '
              'for the bill due '
              '${formatDayMonthYear(episode.firstMissedDue.toUtc())}.',
          for (final w in waivers)
            'Owed again: ${formatDayMonthYear(w.periodStart.toUtc())} to '
                '${formatDayMonthYear(w.periodEnd.toUtc())}, '
                '${formatMinorUnits(w.amountMinor)}.',
          'That bill will not deactivate them again.',
        ],
      );
      return MemberReinstated(restoredMinor: restored);
    });
    return result;
  }

  /// Every missed-payment deactivation [memberId] has had, newest first.
  Future<List<DeactivationEpisode>> historyFor(int memberId) async {
    final rows = await (db.select(db.memberDeactivations)
          ..where((d) => d.memberId.equals(memberId))
          ..orderBy([(d) => OrderingTerm.desc(d.deactivatedAt)]))
        .get();
    if (rows.isEmpty) return const [];

    final waivers = await (db.select(db.inactivityWaivers)
          ..where((w) => w.deactivationId.isIn(rows.map((r) => r.id)))
          ..orderBy([(w) => OrderingTerm(expression: w.periodStart)]))
        .get();
    return [
      for (final row in rows)
        DeactivationEpisode(
          row: row,
          waivers: [
            for (final w in waivers)
              if (w.deactivationId == row.id) w,
          ],
        ),
    ];
  }

  /// The rule's verdict, less bills the owner has already excused.
  ///
  /// Reinstating says the member was here all along, for every bill it put
  /// back — the month that started the lapse and the one cut short with it —
  /// and for any month already running on the day. So a bill due before
  /// [reinstatedOn] never deactivates them again; the first bill to fall due
  /// after it is judged like anyone's.
  static PaymentInactivity _judge(
    MemberBilling billing,
    DateTime today,
    int graceDays,
    DateTime? reinstatedOn,
  ) {
    final verdict = assessPaymentInactivity(
        cycles: billing.cycles, today: today, graceDays: graceDays);
    if (reinstatedOn == null) return verdict;
    final due = switch (verdict) {
      PaymentInactivityLapsed(:final firstMissedDue) => firstMissedDue,
      PaymentInactivityReview(:final firstMissedDue) => firstMissedDue,
      PaymentInactivityGrace(:final firstMissedDue) => firstMissedDue,
      PaymentInactivityNone() => null,
    };
    return due != null && due.isBefore(reinstatedOn)
        ? const PaymentInactivityNone()
        : verdict;
  }

  /// For each reinstated member, the gym day of their latest reinstatement.
  Future<Map<int, DateTime>> _reinstatedOnByMember({int? memberId}) async {
    final query = db.select(db.memberDeactivations)
      ..where((d) =>
          d.reinstated.equals(true) &
          (memberId == null
              ? const Constant(true)
              : d.memberId.equals(memberId)))
      ..orderBy([(d) => OrderingTerm(expression: d.reactivatedAt)]);
    return {
      for (final row in await query.get())
        if (row.reactivatedAt case final at?) row.memberId: gymDateOf(at),
    };
  }
}

/// Notes a payment taken from a member who is deactivated for missed
/// payments, for the owner to check against what was written off.
///
/// The Record Payment dialog asks the owner to reinstate or restart such a
/// member before taking their money, so this is the safety net for any other
/// route. Changes nothing. Never throws — the payment has already been taken.
Future<void> flagPaymentAfterWaiver(
  AppDatabase db, {
  required int memberId,
  required int paymentId,
  required int amountMinor,
  String? receiptNumber,
  AuditRepository? audit,
}) async {
  try {
    final open = await openDeactivationFor(db, memberId);
    if (open == null) return;
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(memberId)))
        .getSingleOrNull();
    if (member == null || member.deactivatedAt == null) return;

    await (audit ?? AuditRepository(db)).record(
      category: AuditCategory.billing,
      action: AuditAction.paymentAfterMissedPaymentWaiver,
      outcome: AuditOutcome.success,
      memberId: memberId,
      memberName: member.fullName,
      paymentId: paymentId,
      receiptNumber: receiptNumber,
      amountMinor: amountMinor,
      summary: 'Payment taken from ${member.fullName} while deactivated for '
          'missed payments — check it',
      detail: [
        'Deactivated on ${formatDayMonthYear(open.deactivatedOn.toUtc())}; '
            '${formatMinorUnits(open.waivedMinor)} written off from the bill '
            'due ${formatDayMonthYear(open.firstMissedDue.toUtc())}.',
        'Nothing was undone and the member is still inactive. If they are '
            'back, reactivate them from their screen.',
      ],
    );
  } catch (error, stack) {
    _log.severe('Could not flag payment $paymentId', error, stack);
  }
}
