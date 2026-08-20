import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/database.dart';
import '../data/membership_queries.dart';
import '../data/settings_repository.dart';
import '../domain/billing_month_check.dart';
import '../domain/billing_period.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
import '../domain/payment_changes.dart';
import '../domain/payment_method.dart';
import '../domain/phone.dart';
import 'billing_month_checker.dart';
import 'receipt_renderer.dart';
import 'receipt_storage.dart';
import 'record_payment_service.dart';

final _log = Logger('payments');

/// A correction to a payment that was already recorded.
class EditPaymentInput {
  const EditPaymentInput({
    required this.paymentId,
    required this.amountMinor,
    required this.method,
    required this.paymentDate,
    required this.billingMonth,
    required this.editedById,
    this.referenceNumber,
    this.notes,
    this.sendWhatsApp = false,
    this.acknowledgedIssues = const [],
  });

  final int paymentId;
  final int amountMinor;
  final PaymentMethod method;
  final DateTime paymentDate;

  /// "YYYY-MM".
  final String billingMonth;
  final int editedById;
  final String? referenceNumber;
  final String? notes;

  /// The corrected receipt goes out only when the owner asks for it. An edit is
  /// usually fixing a typo nobody but the gym ever saw.
  final bool sendWhatsApp;

  /// Warnings the owner was shown and chose to continue past, recorded so the
  /// log says the decision was made rather than that the check never ran.
  final List<BillingMonthIssue> acknowledgedIssues;
}

/// Why an edit was declined. Typed so the UI never parses a message.
enum EditRefusalReason { notFound, noPlan, monthBlocked, cycleTaken }

/// What became of the receipt files after a successful edit.
sealed class ReceiptUpdate {
  const ReceiptUpdate();
}

/// There was no receipt to update — an imported ledger payment. Editing one
/// deliberately does not mint a receipt: a 2024 cash row corrected today would
/// otherwise take a number out of this year's sequence.
class ReceiptNotApplicable extends ReceiptUpdate {
  const ReceiptNotApplicable();
}

class ReceiptRewritten extends ReceiptUpdate {
  const ReceiptRewritten(this.receiptNumber);
  final String receiptNumber;
}

/// The payment is correct and committed; its receipt on disk is not.
class ReceiptRewriteFailed extends ReceiptUpdate {
  const ReceiptRewriteFailed(this.message);

  /// Written for the owner, e.g. "the receipt file is open in another
  /// program". Never a stack trace.
  final String message;
}

sealed class EditPaymentResult {
  const EditPaymentResult();
}

class PaymentEdited extends EditPaymentResult {
  const PaymentEdited({
    required this.paymentId,
    required this.changes,
    required this.receipt,
    required this.whatsApp,
    this.receiptNumber,
  });

  final int paymentId;
  final String? receiptNumber;

  /// Human-readable "before → after" lines. Empty when the owner saved without
  /// changing anything.
  final List<String> changes;

  final ReceiptUpdate receipt;
  final WhatsAppOutcome whatsApp;

  bool get changedNothing => changes.isEmpty;
}

class PaymentEditRefused extends EditPaymentResult {
  const PaymentEditRefused(this.reason, this.message);
  final EditRefusalReason reason;
  final String message;
}

sealed class DeletePaymentResult {
  const DeletePaymentResult();
}

class PaymentDeleted extends DeletePaymentResult {
  const PaymentDeleted({
    required this.memberName,
    required this.amountMinor,
    required this.periodLabel,
    this.receiptNumber,
    this.orphanedFiles = const [],
  });

  final String memberName;
  final int amountMinor;
  final String periodLabel;
  final String? receiptNumber;

  /// Receipt files the database no longer references but which could not be
  /// removed — on Windows, usually because a PDF preview still has them open.
  /// The deletion itself succeeded; these are litter, not a failure.
  final List<String> orphanedFiles;

  bool get hasOrphanedFiles => orphanedFiles.isNotEmpty;
}

class PaymentDeleteRefused extends DeletePaymentResult {
  const PaymentDeleteRefused(this.message);
  final String message;
}

/// Correcting and removing payments that are already recorded.
///
/// Separate from [RecordPaymentService] — which is already the longest workflow
/// in the app — but follows the same discipline: nothing expensive happens
/// inside a transaction, the database commits before any file is touched, and a
/// messaging failure can never undo money.
class PaymentEditService {
  PaymentEditService({
    required this.db,
    required this.renderer,
    required this.storage,
    required this.audit,
    required this.payments,
    BillingMonthChecker? checker,
    SettingsRepository? settings,
  })  : _checker = checker ?? BillingMonthChecker(db),
        _settings = settings ?? SettingsRepository(db);

  final AppDatabase db;
  final ReceiptRenderer renderer;
  final ReceiptStorage storage;
  final AuditRepository audit;

  /// Borrowed for [RecordPaymentService.sendReceipt], which owns the
  /// attempt-history bookkeeping. Re-implementing that here is exactly the
  /// second copy of a rule that must not exist.
  final RecordPaymentService payments;

  final BillingMonthChecker _checker;
  final SettingsRepository _settings;

  // --- Editing -------------------------------------------------------------

  Future<EditPaymentResult> edit(EditPaymentInput input) async {
    final payment = await _paymentOrNull(input.paymentId);
    if (payment == null) {
      return const PaymentEditRefused(
        EditRefusalReason.notFound,
        'That payment no longer exists. It may have been deleted from another '
        'window.',
      );
    }

    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(payment.memberId)))
        .getSingle();
    final receipt = await _receiptForPayment(payment.id);
    final settings = await _settings.get();

    final check = await _checker.check(
      memberId: payment.memberId,
      billingMonth: input.billingMonth,
      excludePaymentId: payment.id,
    );

    if (!check.hasPlan) {
      return PaymentEditRefused(
        EditRefusalReason.noPlan,
        '${member.fullName} has no active plan, so '
        '${formatBillingPeriod(parseBillingMonth(input.billingMonth), 1)} has '
        'no billing cycle to move this payment to. Assign a plan first.',
      );
    }

    if (check.review.isBlocked) {
      final message = check.review.blocking.map((f) => f.message).join(' ');
      await audit.record(
        category: AuditCategory.billing,
        action: AuditAction.billingMonthBlocked,
        outcome: AuditOutcome.refused,
        actorId: input.editedById,
        memberId: member.id,
        memberName: member.fullName,
        paymentId: payment.id,
        receiptNumber: receipt?.receiptNumber,
        summary: 'Edit blocked: ${input.billingMonth} is not a valid billing '
            'month for ${member.fullName}',
        detail: check.review.blocking.map((f) => f.message).toList(),
      );
      return PaymentEditRefused(EditRefusalReason.monthBlocked, message);
    }

    // Moving onto a cycle that already holds someone's money is refused rather
    // than confirmed. Recording a second payment for a month is a legitimate
    // top-up; *moving* a payment on top of another one is not something the
    // owner can have meant.
    final target = check.period;
    final movingCycle = target?.id != payment.membershipPeriodId;
    if (target != null && movingCycle) {
      final occupant = await paymentForPeriod(db, target.id);
      if (occupant != null && occupant.id != payment.id) {
        final label =
            formatBillingPeriod(target.periodStart.toUtc(), check.durationMonths);
        return PaymentEditRefused(
          EditRefusalReason.cycleTaken,
          '$label already has a payment of '
          '${formatMinorUnits(occupant.amountMinor, settings.currency)} '
          'recorded against it. Edit or delete that payment first.',
        );
      }
    }

    // --- What is actually changing ---------------------------------------
    final beforeLabel = await _labelForPeriodId(payment.membershipPeriodId);
    final targetStart =
        target?.periodStart.toUtc() ?? parseBillingMonth(input.billingMonth);
    final afterLabel =
        formatBillingPeriod(targetStart, check.durationMonths);

    final before = PaymentSnapshot(
      amountMinor: payment.amountMinor,
      method: payment.method,
      paymentDate: payment.paymentDate,
      periodLabel: beforeLabel,
      referenceNumber: payment.referenceNumber,
      notes: payment.notes,
    );
    final after = PaymentSnapshot(
      amountMinor: input.amountMinor,
      method: input.method,
      paymentDate: input.paymentDate,
      periodLabel: afterLabel,
      referenceNumber: input.referenceNumber,
      notes: input.notes,
    );

    final changes =
        describePaymentChanges(before, after, currency: settings.currency);

    // Saving a form nobody edited must not re-render a receipt, write an audit
    // event, or stamp updatedAt on a payment that is unchanged.
    if (changes.isEmpty) {
      return PaymentEdited(
        paymentId: payment.id,
        receiptNumber: receipt?.receiptNumber,
        changes: const [],
        receipt: const ReceiptNotApplicable(),
        whatsApp: const WhatsAppNotRequested(),
      );
    }

    await _logAcknowledgedWarnings(input, member, payment, receipt);

    // --- Render first, with no lock held ---------------------------------
    RenderedReceipt? rendered;
    String? renderFailure;
    if (receipt != null) {
      try {
        rendered = await renderer.render(ReceiptData(
          gymName: settings.gymName,
          receiptNumber: receipt.receiptNumber,
          paymentDate: formatDayMonthYear(input.paymentDate),
          memberName: member.fullName,
          memberCode: member.memberCode,
          membershipLabel: check.plan!.name,
          billingPeriod: afterLabel,
          paymentMethod: paymentMethodLabel(input.method),
          referenceNumber: input.referenceNumber,
          amountLabel:
              formatMinorUnits(input.amountMinor, settings.currency),
          footerMessage: settings.receiptFooterMessage,
          gymPhone: settings.phone,
          gymAddress: settings.address,
        ));
      } catch (error, stack) {
        // Not fatal to the correction: the money is what matters and the
        // receipt can be regenerated by saving again.
        renderFailure = 'The corrected receipt could not be generated, so '
            '${receipt.receiptNumber} still shows the old details.';
        _log.severe('Re-rendering ${receipt.receiptNumber} failed', error, stack);
        await audit.record(
          category: AuditCategory.receipt,
          action: AuditAction.receiptRenderFailed,
          outcome: AuditOutcome.failed,
          actorId: input.editedById,
          memberId: member.id,
          memberName: member.fullName,
          paymentId: payment.id,
          receiptNumber: receipt.receiptNumber,
          summary: 'Could not re-render ${receipt.receiptNumber}',
          detail: ['Error: ${_short(error)}'],
        );
      }
    }

    // --- One short transaction, then the files ---------------------------
    await db.transaction(() async {
      // Resolved again in here: between the check above and now, another
      // window could have opened the cycle this payment is moving to.
      var period = await periodForMemberContaining(
        db,
        memberId: member.id,
        month: parseBillingMonth(input.billingMonth),
      );

      if (period == null) {
        final open = await openMembershipFor(db, member.id);
        if (open == null) {
          // hasPlan was true, so a cycle existed a moment ago and has since
          // gone. Abort rather than invent an enrolment.
          throw StateError('No enrolment to open a billing cycle under');
        }
        final bounds =
            periodBounds(input.billingMonth, check.durationMonths);
        period = await db.into(db.membershipPeriods).insertReturning(
              MembershipPeriodsCompanion.insert(
                membershipId: open.id,
                periodStart: bounds.periodStart,
                periodEnd: bounds.periodEnd,
                expectedAmountMinor:
                    open.feeOverrideMinor ?? check.plan!.priceMinor,
              ),
            );
      }

      await (db.update(db.payments)..where((p) => p.id.equals(payment.id)))
          .write(PaymentsCompanion(
        membershipPeriodId: Value(period.id),
        amountMinor: Value(input.amountMinor),
        method: Value(input.method),
        referenceNumber: Value(_blankToNull(input.referenceNumber)),
        paymentDate: Value(input.paymentDate),
        notes: Value(_blankToNull(input.notes)),
        updatedAt: Value(DateTime.now().toUtc()),
        updatedById: Value(input.editedById),
      ));
    });

    // Past this line the correction is committed. Nothing below may report it
    // as having failed.
    final receiptOutcome = await _writeReceiptFiles(
      receipt: receipt,
      rendered: rendered,
      renderFailure: renderFailure,
      input: input,
      member: member,
    );

    await audit.record(
      category: AuditCategory.payment,
      action: AuditAction.paymentEdited,
      outcome: AuditOutcome.success,
      actorId: input.editedById,
      memberId: member.id,
      memberName: member.fullName,
      paymentId: payment.id,
      receiptNumber: receipt?.receiptNumber,
      amountMinor: input.amountMinor,
      periodLabel: afterLabel,
      summary: 'Payment edited for ${member.fullName}'
          '${receipt == null ? '' : ' (${receipt.receiptNumber})'}',
      detail: changes,
    );

    final whatsApp = await _maybeResend(
      input: input,
      member: member,
      receipt: receipt,
      receiptOutcome: receiptOutcome,
      amountLabel: formatMinorUnits(input.amountMinor, settings.currency),
      periodLabel: afterLabel,
      gymName: settings.gymName,
      rendered: rendered,
    );

    return PaymentEdited(
      paymentId: payment.id,
      receiptNumber: receipt?.receiptNumber,
      changes: changes,
      receipt: receiptOutcome,
      whatsApp: whatsApp,
    );
  }

  // --- Deleting ------------------------------------------------------------

  Future<DeletePaymentResult> delete({
    required int paymentId,
    required int actorId,
  }) async {
    final payment = await _paymentOrNull(paymentId);
    if (payment == null) {
      return const PaymentDeleteRefused(
        'That payment has already been deleted.',
      );
    }

    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(payment.memberId)))
        .getSingle();
    final receipt = await _receiptForPayment(payment.id);
    final periodLabel = await _labelForPeriodId(payment.membershipPeriodId);
    final settings = await _settings.get();

    // Foreign keys are on, so the order is forced: attempts reference the
    // receipt, the receipt references the payment.
    await db.transaction(() async {
      if (receipt != null) {
        await (db.delete(db.whatsAppMessages)
              ..where((m) => m.receiptId.equals(receipt.id)))
            .go();
        await (db.delete(db.receipts)..where((r) => r.id.equals(receipt.id)))
            .go();
      }
      await (db.delete(db.payments)..where((p) => p.id.equals(payment.id))).go();
    });

    // The receipt number is not returned to the counter. A gap in the sequence
    // is harmless; reusing a number that a member already has a copy of is not.
    await audit.record(
      category: AuditCategory.payment,
      action: AuditAction.paymentDeleted,
      outcome: AuditOutcome.success,
      actorId: actorId,
      memberId: member.id,
      memberName: member.fullName,
      paymentId: payment.id,
      receiptNumber: receipt?.receiptNumber,
      amountMinor: payment.amountMinor,
      periodLabel: periodLabel,
      summary: 'Payment of '
          '${formatMinorUnits(payment.amountMinor, settings.currency)} deleted '
          'for ${member.fullName} ($periodLabel)',
      detail: [
        'Recorded on ${formatDayMonthYear(payment.paymentDate.toLocal())}',
        'Method: ${paymentMethodLabel(payment.method)}',
        if (receipt != null) 'Receipt: ${receipt.receiptNumber}',
        'The billing cycle reads as due again.',
      ],
    );

    final orphaned = <String>[];
    if (receipt != null) {
      for (final path in [receipt.pngPath, receipt.pdfPath]) {
        if (path == null) continue;
        if (!await _deleteFile(path)) orphaned.add(path);
      }
    }

    if (orphaned.isNotEmpty) {
      // Reported, never raised: the payment is gone either way, and telling the
      // owner the deletion failed would be a lie.
      await audit.record(
        category: AuditCategory.receipt,
        action: AuditAction.receiptFilesOrphaned,
        outcome: AuditOutcome.failed,
        actorId: actorId,
        memberId: member.id,
        memberName: member.fullName,
        paymentId: payment.id,
        receiptNumber: receipt?.receiptNumber,
        summary: 'Receipt files for ${receipt?.receiptNumber} could not be '
            'removed from disk',
        detail: [
          ...orphaned.map((f) => 'Left behind: $f'),
          'The payment was deleted successfully. The files are unreferenced '
              'and can be removed by hand.',
        ],
      );
    }

    return PaymentDeleted(
      memberName: member.fullName,
      amountMinor: payment.amountMinor,
      periodLabel: periodLabel,
      receiptNumber: receipt?.receiptNumber,
      orphanedFiles: orphaned,
    );
  }

  // --- Helpers -------------------------------------------------------------

  Future<ReceiptUpdate> _writeReceiptFiles({
    required Receipt? receipt,
    required RenderedReceipt? rendered,
    required String? renderFailure,
    required EditPaymentInput input,
    required Member member,
  }) async {
    if (receipt == null) return const ReceiptNotApplicable();
    if (renderFailure != null) return ReceiptRewriteFailed(renderFailure);
    if (rendered == null) return const ReceiptNotApplicable();

    try {
      await storage.save(receipt.pngPath, rendered.png);
      final pdfPath = receipt.pdfPath;
      if (pdfPath != null) await storage.save(pdfPath, rendered.pdf);
      return ReceiptRewritten(receipt.receiptNumber);
    } catch (error, stack) {
      _log.severe('Saving corrected ${receipt.receiptNumber} failed',
          error, stack);
      await audit.record(
        category: AuditCategory.receipt,
        action: AuditAction.receiptResaveFailed,
        outcome: AuditOutcome.failed,
        actorId: input.editedById,
        memberId: member.id,
        memberName: member.fullName,
        paymentId: input.paymentId,
        receiptNumber: receipt.receiptNumber,
        summary: 'Could not save the corrected ${receipt.receiptNumber}',
        detail: [
          'Error: ${_short(error)}',
          'The payment was corrected successfully. Saving the payment again '
              'will retry the receipt.',
        ],
      );
      return ReceiptRewriteFailed(
        'The payment was corrected, but its receipt file could not be '
        'rewritten. Close the receipt if it is open elsewhere and save again.',
      );
    }
  }

  Future<WhatsAppOutcome> _maybeResend({
    required EditPaymentInput input,
    required Member member,
    required Receipt? receipt,
    required ReceiptUpdate receiptOutcome,
    required String amountLabel,
    required String periodLabel,
    required String gymName,
    required RenderedReceipt? rendered,
  }) async {
    if (!input.sendWhatsApp) return const WhatsAppNotRequested();

    if (receipt == null) {
      return const WhatsAppFailed(
        'This payment has no receipt to send. Imported ledger payments are '
        'recorded without one.',
      );
    }

    // Sending the old image over a corrected payment would be worse than not
    // sending at all.
    if (receiptOutcome is ReceiptRewriteFailed) {
      return const WhatsAppFailed(
        'The corrected receipt was not saved, so it was not sent. Save again '
        'and then resend.',
      );
    }

    await audit.record(
      category: AuditCategory.whatsapp,
      action: AuditAction.whatsAppResendRequested,
      outcome: AuditOutcome.success,
      actorId: input.editedById,
      memberId: member.id,
      memberName: member.fullName,
      paymentId: input.paymentId,
      receiptNumber: receipt.receiptNumber,
      summary: 'Corrected ${receipt.receiptNumber} queued for '
          '${member.fullName}',
      detail: ['To: ${maskPhone(member.phone)}'],
    );

    final outcome = await payments.sendReceipt(
      receiptId: receipt.id,
      receiptNumber: receipt.receiptNumber,
      memberId: member.id,
      memberName: member.fullName,
      phone: member.phone,
      gymName: gymName,
      amountLabel: amountLabel,
      periodLabel: periodLabel,
      pngBytes: rendered?.png,
    );

    await _logSendOutcome(
      outcome: outcome,
      actorId: input.editedById,
      member: member,
      paymentId: input.paymentId,
      receiptNumber: receipt.receiptNumber,
    );

    return outcome;
  }

  Future<void> _logSendOutcome({
    required WhatsAppOutcome outcome,
    required int actorId,
    required Member member,
    required int paymentId,
    required String receiptNumber,
  }) async {
    switch (outcome) {
      case WhatsAppSent(:final messageId):
        await audit.record(
          category: AuditCategory.whatsapp,
          action: AuditAction.whatsAppSent,
          outcome: AuditOutcome.success,
          actorId: actorId,
          memberId: member.id,
          memberName: member.fullName,
          paymentId: paymentId,
          receiptNumber: receiptNumber,
          summary: 'Corrected $receiptNumber sent to ${member.fullName}',
          detail: [
            'To: ${maskPhone(member.phone)}',
            'Provider message id: $messageId',
          ],
        );
      case WhatsAppFailed(:final error):
        await audit.record(
          category: AuditCategory.whatsapp,
          action: AuditAction.whatsAppFailed,
          outcome: AuditOutcome.failed,
          actorId: actorId,
          memberId: member.id,
          memberName: member.fullName,
          paymentId: paymentId,
          receiptNumber: receiptNumber,
          summary: 'Corrected $receiptNumber could not be sent to '
              '${member.fullName}',
          // The client already reduces a Graph error to its message; no
          // headers, tokens or response bodies reach this line.
          detail: [
            'To: ${maskPhone(member.phone)}',
            'Reason: ${_short(error)}',
          ],
        );
      case WhatsAppNotRequested():
        break;
    }
  }

  Future<void> _logAcknowledgedWarnings(
    EditPaymentInput input,
    Member member,
    Payment payment,
    Receipt? receipt,
  ) async {
    if (input.acknowledgedIssues.isEmpty) return;

    await audit.record(
      category: AuditCategory.billing,
      action: AuditAction.billingMonthConfirmed,
      outcome: AuditOutcome.success,
      actorId: input.editedById,
      memberId: member.id,
      memberName: member.fullName,
      paymentId: payment.id,
      receiptNumber: receipt?.receiptNumber,
      summary: 'Billing-month warnings confirmed for ${member.fullName} '
          '(${input.billingMonth})',
      detail: input.acknowledgedIssues.map((i) => i.name).toList(),
    );
  }

  Future<Payment?> _paymentOrNull(int id) =>
      (db.select(db.payments)..where((p) => p.id.equals(id)))
          .getSingleOrNull();

  Future<Receipt?> _receiptForPayment(int paymentId) =>
      (db.select(db.receipts)..where((r) => r.paymentId.equals(paymentId)))
          .getSingleOrNull();

  /// The label of the cycle a payment currently sits on, "—" when it sits on
  /// none — which is how imported rows with no cycle read everywhere else.
  Future<String> _labelForPeriodId(int? periodId) async {
    if (periodId == null) return '—';

    final period = await (db.select(db.membershipPeriods)
          ..where((p) => p.id.equals(periodId)))
        .getSingleOrNull();
    if (period == null) return '—';

    final membership = await (db.select(db.memberships)
          ..where((m) => m.id.equals(period.membershipId)))
        .getSingleOrNull();
    final plan = membership == null
        ? null
        : await (db.select(db.membershipPlans)
              ..where((p) => p.id.equals(membership.planId)))
            .getSingleOrNull();

    return formatBillingPeriod(
        period.periodStart.toUtc(), plan?.durationMonths ?? 1);
  }

  /// True when the file is gone afterwards, however that came about.
  ///
  /// [ReceiptStorage.delete] is best-effort and reports nothing, so the check
  /// is whether the file still exists — which on Windows it will if a PDF
  /// viewer still has it open.
  Future<bool> _deleteFile(String path) async {
    await storage.delete(path);
    try {
      return !await (await storage.resolve(path)).exists();
    } catch (_) {
      return false;
    }
  }

  /// One line, for a log the owner might read. Never a stack trace.
  static String _short(Object error) {
    final text = error.toString().trim().split('\n').first;
    return text.length <= 200 ? text : '${text.substring(0, 197)}…';
  }

  static String? _blankToNull(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value.trim();
}
