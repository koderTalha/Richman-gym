import 'package:drift/drift.dart';

import '../domain/billing_period.dart';
import 'database.dart';

/// A payment joined with the context needed to display it.
class PaymentRow {
  const PaymentRow({
    required this.payment,
    required this.member,
    required this.periodLabel,
    required this.receipt,
    required this.whatsAppStatus,
    required this.recordedByName,
  });

  final Payment payment;
  final Member member;
  final String periodLabel;
  final Receipt? receipt;
  final WhatsAppStatus? whatsAppStatus;
  final String recordedByName;
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

  Future<int> totalMinorBetween(DateTime from, DateTime to) async {
    final result = await (db.selectOnly(db.payments)
          ..addColumns([db.payments.amountMinor.sum()])
          ..where(db.payments.paymentDate.isBiggerOrEqualValue(from) &
              db.payments.paymentDate.isSmallerThanValue(to)))
        .getSingleOrNull();
    return result?.read(db.payments.amountMinor.sum()) ?? 0;
  }

  Future<int> countBetween(DateTime from, DateTime to) async {
    final rows = await (db.select(db.payments)
          ..where((p) =>
              p.paymentDate.isBiggerOrEqualValue(from) &
              p.paymentDate.isSmallerThanValue(to)))
        .get();
    return rows.length;
  }
}
