import 'package:drift/drift.dart';

import '../domain/billing_period.dart';
import 'database.dart';

/// A receipt joined with everything needed to display or resend it.
class ReceiptRow {
  const ReceiptRow({
    required this.receipt,
    required this.payment,
    required this.member,
    required this.periodLabel,
    required this.latestMessage,
  });

  final Receipt receipt;
  final Payment payment;
  final Member member;
  final String periodLabel;
  final WhatsAppMessage? latestMessage;

  WhatsAppStatus? get whatsAppStatus => latestMessage?.status;
}

class WhatsAppMessageRow {
  const WhatsAppMessageRow({
    required this.message,
    required this.member,
    required this.receipt,
  });

  final WhatsAppMessage message;
  final Member member;
  final Receipt receipt;
}

class ReceiptRepository {
  ReceiptRepository(this.db);

  final AppDatabase db;

  Future<List<ReceiptRow>> list({String? search, int limit = 300}) async {
    final receipts = await (db.select(db.receipts)
          ..orderBy([
            (r) => OrderingTerm(expression: r.id, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .get();
    if (receipts.isEmpty) return const [];

    final paymentIds = receipts.map((r) => r.paymentId).toList();
    final payments = {
      for (final p in await (db.select(db.payments)
            ..where((p) => p.id.isIn(paymentIds)))
          .get())
        p.id: p,
    };

    final memberIds = payments.values.map((p) => p.memberId).toSet().toList();
    final members = {
      for (final m in await (db.select(db.members)
            ..where((m) => m.id.isIn(memberIds)))
          .get())
        m.id: m,
    };

    final latest = await _latestMessages(receipts.map((r) => r.id).toList());
    final periodLabels = await _periodLabels(payments.values.toList());

    final rows = <ReceiptRow>[];
    for (final receipt in receipts) {
      final payment = payments[receipt.paymentId];
      if (payment == null) continue;
      final member = members[payment.memberId];
      if (member == null) continue;

      rows.add(ReceiptRow(
        receipt: receipt,
        payment: payment,
        member: member,
        periodLabel: periodLabels[payment.id] ?? '—',
        latestMessage: latest[receipt.id],
      ));
    }

    final term = search?.trim().toLowerCase();
    if (term == null || term.isEmpty) return rows;

    return rows
        .where((r) =>
            r.receipt.receiptNumber.toLowerCase().contains(term) ||
            r.member.fullName.toLowerCase().contains(term) ||
            r.member.phone.contains(term))
        .toList();
  }

  Future<List<WhatsAppMessageRow>> messages({
    WhatsAppStatus? status,
    int limit = 300,
  }) async {
    var query = db.select(db.whatsAppMessages)
      ..orderBy([
        (m) => OrderingTerm(expression: m.id, mode: OrderingMode.desc)
      ])
      ..limit(limit);

    if (status != null) {
      query = query..where((m) => m.status.equalsValue(status));
    }

    final messages = await query.get();
    if (messages.isEmpty) return const [];

    final memberIds = messages.map((m) => m.memberId).toSet().toList();
    final members = {
      for (final m in await (db.select(db.members)
            ..where((m) => m.id.isIn(memberIds)))
          .get())
        m.id: m,
    };

    final receiptIds = messages.map((m) => m.receiptId).toSet().toList();
    final receipts = {
      for (final r in await (db.select(db.receipts)
            ..where((r) => r.id.isIn(receiptIds)))
          .get())
        r.id: r,
    };

    return messages
        .where((m) =>
            members.containsKey(m.memberId) && receipts.containsKey(m.receiptId))
        .map((m) => WhatsAppMessageRow(
              message: m,
              member: members[m.memberId]!,
              receipt: receipts[m.receiptId]!,
            ))
        .toList();
  }

  Future<int> failedCount() async {
    final rows = await (db.select(db.whatsAppMessages)
          ..where((m) => m.status.equalsValue(WhatsAppStatus.failed)))
        .get();

    // A receipt counts as failed only if its most recent attempt failed;
    // a later successful retry clears it.
    final latest = await _latestMessages(
        rows.map((m) => m.receiptId).toSet().toList());
    return latest.values
        .where((m) => m.status == WhatsAppStatus.failed)
        .length;
  }

  Future<Receipt?> byId(int id) =>
      (db.select(db.receipts)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  Future<Map<int, WhatsAppMessage>> _latestMessages(List<int> receiptIds) async {
    if (receiptIds.isEmpty) return {};
    final all = await (db.select(db.whatsAppMessages)
          ..where((m) => m.receiptId.isIn(receiptIds))
          ..orderBy([(m) => OrderingTerm(expression: m.attemptNumber)]))
        .get();

    // Ascending order means the last write per receipt wins.
    return {for (final m in all) m.receiptId: m};
  }

  Future<Map<int, String>> _periodLabels(List<Payment> payments) async {
    final periodIds =
        payments.map((p) => p.membershipPeriodId).whereType<int>().toSet().toList();
    if (periodIds.isEmpty) return {};

    final periods = {
      for (final p in await (db.select(db.membershipPeriods)
            ..where((p) => p.id.isIn(periodIds)))
          .get())
        p.id: p,
    };
    final membershipIds =
        periods.values.map((p) => p.membershipId).toSet().toList();
    final memberships = {
      for (final m in await (db.select(db.memberships)
            ..where((m) => m.id.isIn(membershipIds)))
          .get())
        m.id: m,
    };
    final plans = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };

    return {
      for (final payment in payments)
        if (payment.membershipPeriodId != null &&
            periods[payment.membershipPeriodId] != null)
          payment.id: formatBillingPeriod(
            periods[payment.membershipPeriodId]!.periodStart,
            plans[memberships[periods[payment.membershipPeriodId]!.membershipId]
                        ?.planId]
                    ?.durationMonths ??
                1,
          ),
    };
  }
}
