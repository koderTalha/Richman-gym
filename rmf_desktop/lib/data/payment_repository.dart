import 'package:drift/drift.dart';

import '../domain/billing_period.dart';
import '../domain/payment_timing.dart';
import '../domain/reminder_schedule.dart';
import 'database.dart';

/// A payment joined with the context needed to display it.
class PaymentRow {
  const PaymentRow({
    required this.payment,
    required this.member,
    required this.periodLabel,
    required this.planDurationMonths,
    required this.periodStart,
    required this.receipt,
    required this.whatsAppStatus,
    required this.recordedByName,
    this.timing = PaymentTiming.onTime,
  });

  final Payment payment;
  final Member member;
  final String periodLabel;

  /// Length of the plan the cycle was billed under. Carried so the edit form
  /// can label the billing period correctly without looking the plan up again.
  final int planDurationMonths;

  /// UTC start of that cycle, or null for a payment with no cycle. The edit
  /// form opens on this month rather than on today's.
  final DateTime? periodStart;
  final Receipt? receipt;
  final WhatsAppStatus? whatsAppStatus;
  final String recordedByName;

  /// Where this payment's date fell relative to the cycle it bought.
  ///
  /// Computed here rather than stored, from two dates the row already holds.
  /// A column would be a second answer to the same question, and would go
  /// stale the moment a payment was edited onto a different cycle.
  final PaymentTiming timing;
}

class PaymentRepository {
  PaymentRepository(this.db);

  final AppDatabase db;

  /// Payment history, newest first. [memberId] scopes it to one member's profile.
  Future<List<PaymentRow>> history({
    int? memberId,
    String? search,
    PaymentMethod? method,
    int limit = 500,
  }) async {
    var query = db.select(db.payments)
      ..orderBy([
        (p) => OrderingTerm(expression: p.paymentDate, mode: OrderingMode.desc),
        (p) => OrderingTerm(expression: p.id, mode: OrderingMode.desc),
      ])
      ..limit(limit);

    if (memberId != null) {
      query = query..where((p) => p.memberId.equals(memberId));
    }
    if (method != null) {
      query = query..where((p) => p.method.equalsValue(method));
    }

    final payments = await query.get();
    if (payments.isEmpty) return const [];

    final memberIds = payments.map((p) => p.memberId).toSet().toList();
    final members = {
      for (final m in await (db.select(db.members)
            ..where((m) => m.id.isIn(memberIds)))
          .get())
        m.id: m,
    };

    final users = {for (final u in await db.select(db.users).get()) u.id: u};

    final paymentIds = payments.map((p) => p.id).toList();
    final receipts = {
      for (final r in await (db.select(db.receipts)
            ..where((r) => r.paymentId.isIn(paymentIds)))
          .get())
        r.paymentId: r,
    };

    // Latest WhatsApp attempt per receipt.
    final receiptIds = receipts.values.map((r) => r.id).toList();
    final latestStatus = <int, WhatsAppStatus>{};
    if (receiptIds.isNotEmpty) {
      final messages = await (db.select(db.whatsAppMessages)
            ..where((m) => m.receiptId.isIn(receiptIds))
            ..orderBy([(m) => OrderingTerm(expression: m.attemptNumber)]))
          .get();
      for (final message in messages) {
        latestStatus[message.receiptId] = message.status;
      }
    }

    final periodIds = payments
        .map((p) => p.membershipPeriodId)
        .whereType<int>()
        .toSet()
        .toList();
    final periods = {
      for (final p in periodIds.isEmpty
          ? <MembershipPeriod>[]
          : await (db.select(db.membershipPeriods)
                ..where((p) => p.id.isIn(periodIds)))
              .get())
        p.id: p,
    };

    final membershipIds =
        periods.values.map((p) => p.membershipId).toSet().toList();
    final memberships = {
      for (final m in membershipIds.isEmpty
          ? <Membership>[]
          : await (db.select(db.memberships)
                ..where((m) => m.id.isIn(membershipIds)))
              .get())
        m.id: m,
    };
    final plans = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };

    // One read for the whole page: the on-time window is a property of the
    // gym's reminder schedule, not of any individual payment.
    final settings = await (db.select(db.gymSettings)
          ..where((s) => s.id.equals(1)))
        .getSingleOrNull();
    final window = TimingWindow.fromReminderOffsets(
      daysBefore: parseOffsetDays(settings?.reminderDaysBefore),
      daysAfter: parseOffsetDays(settings?.reminderDaysAfter),
    );

    return payments.map((payment) {
      final period = payment.membershipPeriodId == null
          ? null
          : periods[payment.membershipPeriodId];
      final duration = period == null
          ? 1
          : (plans[memberships[period.membershipId]?.planId]?.durationMonths ?? 1);
      final receipt = receipts[payment.id];

      return PaymentRow(
        payment: payment,
        member: members[payment.memberId]!,
        planDurationMonths: duration,
        periodStart: period?.periodStart.toUtc(),
        // Classified against the payment date exactly as the table prints it,
        // so the badge and the date beside it can never tell different
        // stories. A payment with no cycle has nothing to be early or late
        // for.
        timing: period == null
            ? PaymentTiming.onTime
            : classifyTiming(
                paidAt: payment.paymentDate,
                periodStart: period.periodStart,
                window: window,
              ),
        periodLabel: period == null
            ? '—'
            : formatBillingPeriod(period.periodStart, duration),
        receipt: receipt,
        whatsAppStatus:
            receipt == null ? null : latestStatus[receipt.id],
        recordedByName: users[payment.recordedById]?.name ?? 'Unknown',
      );
    }).toList();
  }

  /// What the gym took in over `[from, to)`.
  ///
  /// Money carried in from the owner's spreadsheet counts. Their ledger holds
  /// real figures — Excel only draws "###" where the column is too narrow for
  /// the number, and the cell still stores it — so an imported month is money
  /// the gym genuinely collected, and a year that reads as empty until the day
  /// of the import would be the wrong answer.
  ///
  /// What the sheet does not know is the *day*. It keeps one column per month,
  /// so every imported payment is dated to the first of the month it covers:
  /// true about the month, a placeholder about the day. Pass
  /// [includeImported] as false for a window narrower than a month, where that
  /// placeholder would otherwise hand a single date a month's takings. See
  /// `DashboardBloc`, which is the one caller that does.
  Future<int> totalMinorBetween(DateTime from, DateTime to,
      {bool includeImported = true}) async {
    final result = await (db.selectOnly(db.payments)
          ..addColumns([db.payments.amountMinor.sum()])
          ..where(_window(from, to, includeImported: includeImported)))
        .getSingleOrNull();
    return result?.read(db.payments.amountMinor.sum()) ?? 0;
  }

  /// How many payments landed in `[from, to)`, on the same terms as
  /// [totalMinorBetween].
  Future<int> countBetween(DateTime from, DateTime to,
      {bool includeImported = true}) async {
    final rows = await (db.select(db.payments)
          ..where((_) => _window(from, to, includeImported: includeImported)))
        .get();
    return rows.length;
  }

  Expression<bool> _window(
    DateTime from,
    DateTime to, {
    required bool includeImported,
  }) {
    final within = db.payments.paymentDate.isBiggerOrEqualValue(from) &
        db.payments.paymentDate.isSmallerThanValue(to);
    return includeImported
        ? within
        : within & db.payments.source.equalsValue(PaymentSource.manual);
  }
}
