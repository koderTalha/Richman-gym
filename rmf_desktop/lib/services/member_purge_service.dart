import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/database.dart';
import '../data/settings_repository.dart';
import '../domain/money.dart';
import 'receipt_storage.dart';

final _log = Logger('members');

/// How much member data there is, table by table.
///
/// Read before the purge to show the owner what they are about to lose, and
/// again in the audit row afterwards to say what went. The same figures serve
/// both, so the dialog can never quote one number and the log another.
class MemberDataCounts {
  const MemberDataCounts({
    required this.members,
    required this.memberships,
    required this.billingCycles,
    required this.payments,
    required this.paymentTotalMinor,
    required this.receipts,
    required this.whatsAppMessages,
    required this.reminders,
    required this.notes,
    required this.pricingRecords,
    required this.membershipChanges,
    required this.paymentAllocations,
  });

  final int members;
  final int memberships;
  final int billingCycles;
  final int payments;

  /// Everything those payments add up to. The one figure in this class that is
  /// money rather than a row count, and the one the owner should read twice.
  final int paymentTotalMinor;

  final int receipts;
  final int whatsAppMessages;
  final int reminders;
  final int notes;
  final int pricingRecords;
  final int membershipChanges;
  final int paymentAllocations;

  /// True when there is nothing belonging to a member anywhere in the database.
  ///
  /// Every table below links to a member through a non-null column, so no row
  /// in any of them can outlive the members: if there are no members there is
  /// nothing else either, and this is the whole of the "already empty" test.
  bool get isEmpty =>
      members == 0 &&
      memberships == 0 &&
      billingCycles == 0 &&
      payments == 0 &&
      receipts == 0 &&
      whatsAppMessages == 0 &&
      reminders == 0 &&
      notes == 0 &&
      pricingRecords == 0 &&
      membershipChanges == 0 &&
      paymentAllocations == 0;
}

sealed class MemberPurgeResult {
  const MemberPurgeResult();
}

class MemberDataPurged extends MemberPurgeResult {
  const MemberDataPurged({
    required this.counts,
    required this.orphanedFiles,
  });

  /// What was there immediately before the delete, and therefore what went.
  final MemberDataCounts counts;

  /// Receipt images and PDFs that could not be removed from disk. The database
  /// rows are gone regardless; these are unreferenced files, not lost records.
  final List<String> orphanedFiles;

  bool get hasOrphanedFiles => orphanedFiles.isNotEmpty;
}

class MemberPurgeRefused extends MemberPurgeResult {
  const MemberPurgeRefused(this.message);
  final String message;
}

/// Deletes every member and everything that exists only because of one.
///
/// The gym's route out of a dataset that has to be started again — a botched
/// import, a test run on the real machine, a handover to a new owner. It is
/// the most destructive action in the application, so it is the only one that
/// asks for a typed phrase rather than a name.
///
/// Scoped by a property of the schema rather than by a judgement made here:
/// every table it empties links to a member through a NOT NULL column, so each
/// of their rows exists only because a member does and there is no row in them
/// to spare. Anything shared with the rest of the app — the owner's account and
/// session, the gym's settings, the membership plans, the receipt number
/// counter and the audit log — is left exactly as it is, and the tests in
/// `test/member_purge_test.dart` name each one.
class MemberPurgeService {
  MemberPurgeService({
    required this.db,
    required this.storage,
    required this.audit,
    SettingsRepository? settings,
  }) : _settings = settings ?? SettingsRepository(db);

  final AppDatabase db;
  final ReceiptStorage storage;
  final AuditRepository audit;
  final SettingsRepository _settings;

  Future<MemberDataCounts> counts() async {
    Future<int> rows(String table) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM $table')
          .getSingle();
      return row.read<int>('c');
    }

    final total = (await db
            .customSelect('SELECT COALESCE(SUM(amount_minor), 0) AS t '
                'FROM payments')
            .getSingle())
        .read<int>('t');

    return MemberDataCounts(
      members: await rows('members'),
      memberships: await rows('memberships'),
      billingCycles: await rows('membership_periods'),
      payments: await rows('payments'),
      paymentTotalMinor: total,
      receipts: await rows('receipts'),
      whatsAppMessages: await rows('whats_app_messages'),
      reminders: await rows('payment_reminders'),
      notes: await rows('member_notes'),
      pricingRecords: await rows('cycle_pricings'),
      membershipChanges: await rows('membership_changes'),
      paymentAllocations: await rows('payment_allocations'),
    );
  }

  /// Empties every member-owned table, then removes the receipt files.
  ///
  /// Refuses rather than fails when there is nothing to delete, so pressing the
  /// button twice is harmless.
  Future<MemberPurgeResult> purgeAll({required int actorId}) async {
    // Counted inside the transaction, with the delete it describes. Read
    // beforehand, a payment taken between the count and the delete would go
    // with the rest and leave the log quietly one short — and the log is all
    // that is left afterwards.
    final purged = await db.transaction(() async {
      final before = await counts();
      if (before.isEmpty) return null;

      // These paths are needed after the transaction commits: a file that will
      // not delete must not roll back a database change that succeeded.
      final files = <String>[
        for (final receipt in await db.select(db.receipts).get()) ...[
          receipt.pngPath,
          if (receipt.pdfPath != null) receipt.pdfPath!,
        ],
      ];

      // Foreign keys are enforced on every connection, so this order is not a
      // preference. Children before parents, all the way down: messages name a
      // receipt, a receipt names a payment, a payment names a member and the
      // cycle it settled. The cascading tables are listed explicitly too —
      // they would go anyway, and naming them means a future change to a
      // cascade cannot silently leave rows behind.
      await db.delete(db.whatsAppMessages).go();
      await db.delete(db.receipts).go();
      await db.delete(db.paymentAllocations).go();
      await db.delete(db.payments).go();
      await db.delete(db.paymentReminders).go();
      await db.delete(db.cyclePricings).go();
      await db.delete(db.membershipPeriods).go();
      await db.delete(db.memberships).go();
      await db.delete(db.memberNotes).go();
      await db.delete(db.membershipChanges).go();
      await db.delete(db.members).go();

      return (before, files);
    });

    if (purged == null) {
      return const MemberPurgeRefused('There are no members to delete.');
    }
    final (before, files) = purged;

    final orphaned = <String>[];
    for (final path in files) {
      if (!await _deleteFile(path)) orphaned.add(path);
    }

    final settings = await _settings.get();

    // Counts and one total, and nothing else. No name, phone or receipt number
    // goes in here: the members are gone, and a log that quoted them would put
    // back on screen exactly what the owner asked to be rid of. What each
    // member was individually is already in the rows this log kept from when it
    // happened.
    await audit.record(
      category: AuditCategory.member,
      action: AuditAction.memberDataPurged,
      outcome: AuditOutcome.success,
      actorId: actorId,
      amountMinor: before.paymentTotalMinor,
      summary: 'All member data deleted — ${before.members} '
          '${before.members == 1 ? 'member' : 'members'}, '
          '${before.payments} '
          '${before.payments == 1 ? 'payment' : 'payments'} totalling '
          '${formatMinorUnits(before.paymentTotalMinor, settings.currency)}',
      detail: [
        'Billing cycles: ${before.billingCycles}',
        'Receipts: ${before.receipts}',
        'WhatsApp messages: ${before.whatsAppMessages}',
        'Reminders: ${before.reminders}',
        'Notes: ${before.notes}',
        'Plans, settings, the owner account and this log were kept.',
        if (orphaned.isNotEmpty)
          '${orphaned.length} receipt file(s) could not be removed from disk.',
      ],
    );

    if (orphaned.isNotEmpty) {
      // Reported, never raised — as when a single payment is deleted. The
      // records are gone either way, and calling the purge a failure over a
      // leftover image would be untrue.
      await audit.record(
        category: AuditCategory.receipt,
        action: AuditAction.receiptFilesOrphaned,
        outcome: AuditOutcome.failed,
        actorId: actorId,
        summary: '${orphaned.length} receipt file(s) could not be removed '
            'from disk',
        detail: [
          ...orphaned.take(20).map((f) => 'Left behind: $f'),
          if (orphaned.length > 20) '…and ${orphaned.length - 20} more.',
          'The records were deleted successfully. The files are unreferenced '
              'and can be removed by hand.',
        ],
      );
    }

    _log.warning('Purged all member data: ${before.members} member(s), '
        '${before.payments} payment(s), ${before.receipts} receipt(s)');

    return MemberDataPurged(counts: before, orphanedFiles: orphaned);
  }

  Future<bool> _deleteFile(String path) async {
    await storage.delete(path);
    try {
      return !await (await storage.resolve(path)).exists();
    } catch (_) {
      return false;
    }
  }
}
