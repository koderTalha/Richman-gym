import 'package:drift/drift.dart';

import 'database.dart';
import 'listing_search.dart';
import 'payment_cycles.dart';

/// Which receipts the Receipts screen lists, by where their WhatsApp delivery
/// stands — judged on each receipt's *latest* attempt, as the dashboard's
/// Failed WhatsApp count is.
enum ReceiptFilter { all, sent, failed, notSent }

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

  /// The months the payment paid for, read from its allocations — see
  /// `payment_cycles.dart`.
  final String periodLabel;
  final WhatsAppMessage? latestMessage;

  WhatsAppStatus? get whatsAppStatus => latestMessage?.status;
}

/// One receipt's complete send history.
///
/// A retry appends an attempt rather than replacing the last one, so a receipt
/// the owner chased four times has five rows in `whats_app_messages`. Listing
/// those rows one per line put the same member and receipt on screen five times
/// over, with a Retry button beside each — five buttons for one thing to retry.
/// The receipt is the unit that gets sent, so it is the unit shown.
class WhatsAppThread {
  const WhatsAppThread({
    required this.member,
    required this.receipt,
    required this.attempts,
  });

  final Member member;
  final Receipt receipt;

  /// Newest attempt first. Never empty — a thread exists because an attempt
  /// was made.
  final List<WhatsAppMessage> attempts;

  WhatsAppMessage get latest => attempts.first;

  /// What the receipt's delivery actually stands at now, which is the latest
  /// attempt and not the worst one: six failures followed by a success is a
  /// receipt the member has.
  WhatsAppStatus get status => latest.status;

  int get attemptCount => attempts.length;

  /// Only the latest attempt is worth retrying, and only if it failed.
  bool get needsRetry => status == WhatsAppStatus.failed;

  /// How many attempts failed along the way, for the summary line.
  int get failedAttempts =>
      attempts.where((a) => a.status == WhatsAppStatus.failed).length;

  DateTime get lastActivityAt =>
      latest.sentAt ?? latest.failedAt ?? latest.createdAt;
}

class ReceiptRepository {
  ReceiptRepository(this.db);

  final AppDatabase db;

  /// Receipts, newest first.
  ///
  /// [search] (receipt number, member name or phone) and [filter] are applied
  /// in SQL *before* [limit]. They used to be applied in Dart to the newest
  /// 300, so an older receipt could not be found by its own number, and the
  /// "WhatsApp failed" filter showed nothing while the dashboard counted a
  /// failure further back. [count] answers how many match in all.
  Future<List<ReceiptRow>> list({
    String? search,
    ReceiptFilter filter = ReceiptFilter.all,
    int limit = 300,
  }) async {
    final query = db.select(db.receipts)
      ..orderBy([
        (r) => OrderingTerm(expression: r.id, mode: OrderingMode.desc)
      ])
      ..limit(limit);
    final where = _listFilter(search: search, filter: filter);
    if (where != null) query.where((_) => where);

    final receipts = await query.get();
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
    final periodLabels = await paymentPeriodLabels(db, payments.values);

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
    return rows;
  }

  /// How many receipts match [search] and [filter] in all, however many
  /// [list] was allowed to return.
  Future<int> count({
    String? search,
    ReceiptFilter filter = ReceiptFilter.all,
  }) async {
    final count = db.receipts.id.count();
    final query = db.selectOnly(db.receipts)..addColumns([count]);
    final where = _listFilter(search: search, filter: filter);
    if (where != null) query.where(where);
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// The WHERE clause [list] and [count] share. Null when nothing narrows
  /// the list.
  Expression<bool>? _listFilter({
    String? search,
    required ReceiptFilter filter,
  }) {
    final conditions = <Expression<bool>>[];

    final term = search?.trim() ?? '';
    if (term.isNotEmpty) {
      final members = db.selectOnly(db.members)
        ..addColumns([db.members.id])
        ..where(memberMatches(db.members, term));
      final payments = db.selectOnly(db.payments)
        ..addColumns([db.payments.id])
        ..where(db.payments.memberId.isInQuery(members));
      conditions.add(db.receipts.receiptNumber
              .lower()
              .like(containsPattern(term), escapeChar: r'\') |
          db.receipts.paymentId.isInQuery(payments));
    }

    final byStatus = switch (filter) {
      ReceiptFilter.all => null,
      ReceiptFilter.sent => _latestAttemptIs(const [
          WhatsAppStatus.sent,
          WhatsAppStatus.delivered,
          WhatsAppStatus.read,
        ]),
      ReceiptFilter.failed => _latestAttemptIs(const [WhatsAppStatus.failed]),
      // Never attempted at all: no message row for the receipt.
      ReceiptFilter.notSent => db.receipts.id.isNotInQuery(
          db.selectOnly(db.whatsAppMessages)
            ..addColumns([db.whatsAppMessages.receiptId])),
    };
    if (byStatus != null) conditions.add(byStatus);

    return conditions.isEmpty ? null : conditions.reduce((a, b) => a & b);
  }

  /// Receipts whose latest WhatsApp attempt has one of [statuses]. "Latest"
  /// is the highest message id per receipt — the rule [sendHistory],
  /// [failedCount] and [_latestMessages] all use, so a receipt the dashboard
  /// counts as failed is one this filter lists.
  Expression<bool> _latestAttemptIs(List<WhatsAppStatus> statuses) {
    final latestIds = db.selectOnly(db.whatsAppMessages)
      ..addColumns([db.whatsAppMessages.id.max()])
      ..groupBy([db.whatsAppMessages.receiptId]);
    final matching = db.selectOnly(db.whatsAppMessages)
      ..addColumns([db.whatsAppMessages.receiptId])
      ..where(db.whatsAppMessages.id.isInQuery(latestIds) &
          statuses
              .map((s) => db.whatsAppMessages.status.equalsValue(s))
              .reduce((a, b) => a | b));
    return db.receipts.id.isInQuery(matching);
  }

  /// Send history, one entry per receipt, newest activity first.
  ///
  /// [status] filters on each receipt's *latest* attempt, so filtering by
  /// Failed lists what still needs attention rather than every receipt that
  /// ever hiccuped.
  ///
  /// Bounded in SQL rather than in Dart: the latest attempt per receipt is
  /// picked, filtered, ordered and limited by the database, and only then are
  /// the attempts for that page of receipts read.
  Future<List<WhatsAppThread>> sendHistory({
    WhatsAppStatus? status,
    int limit = 200,
  }) async {
    // The highest id per receipt is its latest attempt: ids are handed out in
    // order, and a retry always inserts.
    final latestIds = db.selectOnly(db.whatsAppMessages)
      ..addColumns([db.whatsAppMessages.id.max()])
      ..groupBy([db.whatsAppMessages.receiptId]);

    final query = db.select(db.whatsAppMessages)
      ..where((m) => m.id.isInQuery(latestIds))
      ..orderBy([
        (m) => OrderingTerm(expression: m.id, mode: OrderingMode.desc),
      ])
      ..limit(limit);

    if (status != null) {
      query.where((m) => m.status.equalsValue(status));
    }

    final newest = await query.get();
    if (newest.isEmpty) return const [];

    final receiptIds = newest.map((m) => m.receiptId).toList();

    // Every attempt belonging to this page, newest first within each receipt.
    final attempts = <int, List<WhatsAppMessage>>{};
    for (final message in await (db.select(db.whatsAppMessages)
          ..where((m) => m.receiptId.isIn(receiptIds))
          ..orderBy([
            (m) => OrderingTerm(
                expression: m.attemptNumber, mode: OrderingMode.desc),
          ]))
        .get()) {
      attempts.putIfAbsent(message.receiptId, () => []).add(message);
    }

    final members = {
      for (final m in await (db.select(db.members)
            ..where((m) => m.id.isIn(
                newest.map((message) => message.memberId).toSet().toList())))
          .get())
        m.id: m,
    };
    final receipts = {
      for (final r in await (db.select(db.receipts)
            ..where((r) => r.id.isIn(receiptIds)))
          .get())
        r.id: r,
    };

    return [
      for (final message in newest)
        if (members[message.memberId] != null &&
            receipts[message.receiptId] != null)
          WhatsAppThread(
            member: members[message.memberId]!,
            receipt: receipts[message.receiptId]!,
            attempts: attempts[message.receiptId] ?? [message],
          ),
    ];
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

  /// Each receipt's latest attempt: the highest message id, as in
  /// [_latestAttemptIs]. A retry always inserts, so ids and attempt numbers
  /// rise together; reading both by id means the badge on a receipt and the
  /// filter that listed it cannot disagree about which attempt is latest.
  Future<Map<int, WhatsAppMessage>> _latestMessages(List<int> receiptIds) async {
    if (receiptIds.isEmpty) return {};
    final all = await (db.select(db.whatsAppMessages)
          ..where((m) => m.receiptId.isIn(receiptIds))
          ..orderBy([(m) => OrderingTerm(expression: m.id)]))
        .get();

    // Ascending order means the last write per receipt wins.
    return {for (final m in all) m.receiptId: m};
  }
}
