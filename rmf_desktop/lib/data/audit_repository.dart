import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import 'database.dart';

final _log = Logger('audit');

/// The actions the audit log records, named once.
///
/// Strings rather than an enum on purpose: an enum stored in the database
/// cannot gain a value without a migration, and a log is exactly the place
/// where a release wants to start recording something new about old rows it
/// must still be able to read back.
abstract final class AuditAction {
  static const memberDeleted = 'member.deleted';
  static const memberDeleteRefused = 'member.delete_refused';
  static const memberDeactivated = 'member.deactivated';
  static const memberReactivated = 'member.reactivated';

  static const paymentEdited = 'payment.edited';
  static const paymentDeleted = 'payment.deleted';
  static const paymentEditRefused = 'payment.edit_refused';

  static const billingMonthBlocked = 'billing.month_blocked';
  static const billingMonthConfirmed = 'billing.month_confirmed';

  static const receiptResaveFailed = 'receipt.resave_failed';
  static const receiptRenderFailed = 'receipt.render_failed';
  static const receiptFilesOrphaned = 'receipt.files_orphaned';

  static const updateAvailable = 'update.available';
  static const updateInstalling = 'update.installing';
  static const updateVerifyFailed = 'update.verify_failed';
  static const updateBackupFailed = 'update.backup_failed';

  static const whatsAppResendRequested = 'whatsapp.resend_requested';
  static const whatsAppSent = 'whatsapp.sent';
  static const whatsAppFailed = 'whatsapp.failed';
}

/// Reads and writes the audit log the Logs screen shows.
///
/// Every write is mirrored into the file log first and inserted second. If the
/// insert fails there is still a line on disk describing what happened, which
/// is the whole reason the order is that way round.
class AuditRepository {
  AuditRepository(this.db);

  final AppDatabase db;

  /// Records one business mutation.
  ///
  /// Never throws. An audit write must not be able to fail an operation that
  /// has already happened — a payment that was edited stays edited even if the
  /// log cannot be written — but the failure is reported at severe level rather
  /// than swallowed.
  Future<void> record({
    required AuditCategory category,
    required String action,
    required AuditOutcome outcome,
    required String summary,
    int? actorId,
    String? actorName,
    int? memberId,
    String? memberName,
    int? paymentId,
    String? receiptNumber,
    int? amountMinor,
    String? periodLabel,
    List<String> detail = const [],
  }) async {
    final body = detail.where((line) => line.trim().isNotEmpty).toList();
    final line = [
      '$action · $summary',
      ...body.map((d) => '  $d'),
    ].join('\n');

    switch (outcome) {
      case AuditOutcome.success:
        _log.info(line);
      case AuditOutcome.refused:
        _log.warning(line);
      case AuditOutcome.failed:
        _log.severe(line);
    }

    try {
      final resolvedActor =
          actorName ?? (actorId == null ? null : await _userName(actorId));

      await db.into(db.auditEvents).insert(AuditEventsCompanion.insert(
            category: category,
            action: action,
            outcome: outcome,
            actorId: Value(actorId),
            actorName: Value(resolvedActor),
            memberId: Value(memberId),
            memberName: Value(memberName),
            paymentId: Value(paymentId),
            receiptNumber: Value(receiptNumber),
            amountMinor: Value(amountMinor),
            periodLabel: Value(periodLabel),
            summary: summary,
            detail: Value(body.isEmpty ? null : body.join('\n')),
          ));
    } catch (error, stack) {
      _log.severe('The audit event could not be stored: $action', error, stack);
    }
  }

  /// Newest first, always bounded.
  ///
  /// The Logs screen pages with [limit] and [offset] rather than reading the
  /// whole table: this grows for as long as the gym is open, and a list that
  /// has to be fully loaded before the tab paints is a list that eventually
  /// stops painting.
  Future<List<AuditEvent>> recent({
    AuditCategory? category,
    bool failuresOnly = false,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = db.select(db.auditEvents)
      ..orderBy([
        (e) => OrderingTerm(expression: e.createdAt, mode: OrderingMode.desc),
        (e) => OrderingTerm(expression: e.id, mode: OrderingMode.desc),
      ]);

    if (category != null) {
      query.where((e) => e.category.equalsValue(category));
    }
    if (failuresOnly) {
      query.where((e) => e.outcome.equalsValue(AuditOutcome.success).not());
    }

    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      final like = '%$term%';
      query.where((e) =>
          e.summary.like(like) |
          e.memberName.like(like) |
          e.receiptNumber.like(like) |
          e.actorName.like(like));
    }

    query.limit(limit, offset: offset);
    return query.get();
  }

  /// How many events match, so the Logs screen can say whether more remain
  /// without fetching them.
  Future<int> countMatching({
    AuditCategory? category,
    bool failuresOnly = false,
    String? search,
  }) async {
    final count = db.auditEvents.id.count();
    final query = db.selectOnly(db.auditEvents)..addColumns([count]);

    if (category != null) {
      query.where(db.auditEvents.category.equalsValue(category));
    }
    if (failuresOnly) {
      query.where(
          db.auditEvents.outcome.equalsValue(AuditOutcome.success).not());
    }
    final term = search?.trim();
    if (term != null && term.isNotEmpty) {
      final like = '%$term%';
      query.where(db.auditEvents.summary.like(like) |
          db.auditEvents.memberName.like(like) |
          db.auditEvents.receiptNumber.like(like) |
          db.auditEvents.actorName.like(like));
    }

    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<String?> _userName(int id) async {
    final user =
        await (db.select(db.users)..where((u) => u.id.equals(id)))
            .getSingleOrNull();
    return user?.name;
  }
}
