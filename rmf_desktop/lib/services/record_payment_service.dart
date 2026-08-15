import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../data/membership_queries.dart';
import '../domain/billing_period.dart';
import '../domain/money.dart';
import '../domain/phone.dart';
import '../domain/receipt_number.dart';
import 'receipt_renderer.dart';
import 'receipt_storage.dart';
import 'whatsapp/whatsapp_client.dart';

final _log = Logger('payments');

class RecordPaymentInput {
  const RecordPaymentInput({
    required this.memberId,
    required this.amountMinor,
    required this.method,
    required this.paymentDate,
    required this.billingMonth,
    required this.sendWhatsApp,
    required this.recordedById,
    required this.idempotencyKey,
    this.referenceNumber,
    this.notes,
  });

  final int memberId;
  final int amountMinor;
  final PaymentMethod method;
  final DateTime paymentDate;

  /// "YYYY-MM".
  final String billingMonth;
  final bool sendWhatsApp;
  final int recordedById;

  /// Generated once when the form opens, not per submit. That is what makes the
  /// unique index on Payment.idempotencyKey actually stop a double-click from
  /// recording the same money twice.
  final String idempotencyKey;
  final String? referenceNumber;
  final String? notes;
}

sealed class WhatsAppOutcome {
  const WhatsAppOutcome();
}

class WhatsAppNotRequested extends WhatsAppOutcome {
  const WhatsAppNotRequested();
}

class WhatsAppSent extends WhatsAppOutcome {
  const WhatsAppSent(this.messageId);
  final String messageId;
}

class WhatsAppFailed extends WhatsAppOutcome {
  const WhatsAppFailed(this.error);
  final String error;
}

class RecordPaymentResult {
  const RecordPaymentResult({
    required this.paymentId,
    required this.receiptId,
    required this.receiptNumber,
    required this.whatsApp,
  });

  final int paymentId;
  final int receiptId;
  final String receiptNumber;
  final WhatsAppOutcome whatsApp;
}

/// The core workflow of the whole application.
///
/// Runs in three steps, in this order for reasons that are worth keeping:
///
///  1. A short transaction allocates the receipt number, so two payments
///     confirmed at the same moment can never share one.
///  2. The receipt is rendered and written to disk with **no transaction
///     open**. Rasterising a PDF is a call out to the platform and the writes
///     are real disk I/O; holding the database's single connection across
///     either one meant a slow or wedged rasteriser froze every other query in
///     the app, not just this dialog.
///  3. A second short transaction writes the billing period, the payment and
///     the receipt row together, so a receipt can never exist without its
///     payment.
///
/// A failure in step 2 or 3 costs one receipt number — the sequence gets a gap.
/// That is a deliberate trade: gaps are harmless, a frozen till is not.
///
/// WhatsApp is attempted only after step 3 commits — a messaging failure must
/// never roll back money that was actually collected.
class RecordPaymentService {
  RecordPaymentService({
    required this.db,
    required this.renderer,
    required this.storage,
    required this.clientFactory,
  });

  final AppDatabase db;
  final ReceiptRenderer renderer;
  final ReceiptStorage storage;

  /// Resolved lazily so a provider/config change takes effect without a restart.
  final WhatsAppClient Function() clientFactory;

  /// An existing payment for the cycle the owner is about to bill, if any.
  ///
  /// Recording a second payment for the same month is legitimate (a top-up, a
  /// correction) but is far more often a mistake, so the UI asks first rather
  /// than quietly taking the money twice.
  Future<Payment?> existingPaymentForPeriod({
    required int memberId,
    required String billingMonth,
  }) async {
    // Scoped to the member, not to their open enrolment: changing plan leaves
    // the month they already paid on the closed enrolment, and missing it here
    // meant the warning went quiet exactly when it was most needed.
    final period = await periodForMemberStarting(
      db,
      memberId: memberId,
      periodStart: parseBillingMonth(billingMonth),
    );
    if (period == null) return null;

    return paymentForPeriod(db, period.id);
  }

  Future<RecordPaymentResult> call(RecordPaymentInput input) async {
    // A repeat submit with the same key is not an error: hand back what was
    // recorded the first time.
    final alreadyRecorded = await _resultForKey(input.idempotencyKey);
    if (alreadyRecorded != null) return alreadyRecorded;

    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(input.memberId)))
        .getSingle();

    final membership = await openMembershipFor(db, input.memberId);

    if (membership == null) {
      throw StateError(
        '${member.fullName} has no active membership. '
        'Assign a plan before recording a payment.',
      );
    }

    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(membership.planId)))
        .getSingle();

    final settings =
        await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
            .getSingle();

    final bounds = periodBounds(input.billingMonth, plan.durationMonths);
    final receiptYear = input.paymentDate.year;

    final periodLabel =
        formatBillingPeriod(bounds.periodStart, plan.durationMonths);
    final amountLabel =
        formatMinorUnits(input.amountMinor, settings.currency);

    // --- 1. Reserve the receipt number --------------------------------------
    final receiptNumber = await db.transaction(() async {
      final counter = await (db.select(db.receiptCounters)
            ..where((c) => c.year.equals(receiptYear)))
          .getSingleOrNull();

      final next = (counter?.lastNumber ?? 0) + 1;
      if (counter == null) {
        await db.into(db.receiptCounters).insert(
            ReceiptCountersCompanion.insert(
                year: Value(receiptYear), lastNumber: Value(next)));
      } else {
        await (db.update(db.receiptCounters)
              ..where((c) => c.year.equals(receiptYear)))
            .write(ReceiptCountersCompanion(lastNumber: Value(next)));
      }

      return formatReceiptNumber(settings.receiptPrefix, receiptYear, next);
    });

    // --- 2. Render and write the files, holding no database lock -------------
    final rendered = await renderer.render(ReceiptData(
      gymName: settings.gymName,
      receiptNumber: receiptNumber,
      paymentDate: _formatDate(input.paymentDate),
      memberName: member.fullName,
      memberCode: member.memberCode,
      membershipLabel: plan.name,
      billingPeriod: periodLabel,
      paymentMethod: _methodLabel(input.method),
      referenceNumber: input.referenceNumber,
      amountLabel: amountLabel,
      footerMessage: settings.receiptFooterMessage,
      gymPhone: settings.phone,
      gymAddress: settings.address,
    ));

    final pngPath = await storage.save('$receiptNumber.png', rendered.png);
    final pdfPath = await storage.save('$receiptNumber.pdf', rendered.pdf);

    // --- 3. The money and its receipt commit together, or not at all ---------
    final ({int paymentId, int receiptId}) committed;
    try {
      committed = await db.transaction(() async {
        var period = await periodForMemberStarting(
          db,
          memberId: member.id,
          periodStart: bounds.periodStart,
        );

        period ??= await db.into(db.membershipPeriods).insertReturning(
              MembershipPeriodsCompanion.insert(
                membershipId: membership.id,
                periodStart: bounds.periodStart,
                periodEnd: bounds.periodEnd,
                expectedAmountMinor:
                    membership.feeOverrideMinor ?? plan.priceMinor,
              ),
            );

        final paymentId = await db.into(db.payments).insert(
              PaymentsCompanion.insert(
                memberId: member.id,
                membershipPeriodId: Value(period.id),
                amountMinor: input.amountMinor,
                method: input.method,
                referenceNumber: Value(_blankToNull(input.referenceNumber)),
                paymentDate: input.paymentDate,
                notes: Value(_blankToNull(input.notes)),
                recordedById: input.recordedById,
                idempotencyKey: input.idempotencyKey,
              ),
            );

        final receiptId = await db.into(db.receipts).insert(
              ReceiptsCompanion.insert(
                receiptNumber: receiptNumber,
                paymentId: paymentId,
                pngPath: pngPath,
                pdfPath: Value(pdfPath),
              ),
            );

        return (paymentId: paymentId, receiptId: receiptId);
      });
    } catch (error, stack) {
      // Nothing was committed, so the images belong to a receipt that does not
      // exist. Clear them before deciding what to tell the caller.
      await storage.delete(pngPath);
      await storage.delete(pdfPath);

      // Two submits of the same form raced each other: the unique index on the
      // idempotency key did its job, and the first one's result is the answer.
      final winner = await _resultForKey(input.idempotencyKey);
      if (winner != null) {
        _log.info('Duplicate submit for ${input.idempotencyKey} ignored');
        return winner;
      }

      _log.severe('Recording the payment failed', error, stack);
      rethrow;
    }

    // --- Past this line the money is safely recorded ------------------------
    if (!input.sendWhatsApp) {
      return RecordPaymentResult(
        paymentId: committed.paymentId,
        receiptId: committed.receiptId,
        receiptNumber: receiptNumber,
        whatsApp: const WhatsAppNotRequested(),
      );
    }

    final sendResult = await sendReceipt(
      receiptId: committed.receiptId,
      receiptNumber: receiptNumber,
      memberId: member.id,
      memberName: member.fullName,
      phone: member.phone,
      gymName: settings.gymName,
      amountLabel: amountLabel,
      periodLabel: periodLabel,
      pngBytes: rendered.png,
    );

    return RecordPaymentResult(
      paymentId: committed.paymentId,
      receiptId: committed.receiptId,
      receiptNumber: receiptNumber,
      whatsApp: sendResult,
    );
  }

  /// What was recorded for [idempotencyKey] on an earlier submit, if anything.
  Future<RecordPaymentResult?> _resultForKey(String idempotencyKey) async {
    final payment = await (db.select(db.payments)
          ..where((p) => p.idempotencyKey.equals(idempotencyKey))
          ..limit(1))
        .getSingleOrNull();
    if (payment == null) return null;

    final receipt = await (db.select(db.receipts)
          ..where((r) => r.paymentId.equals(payment.id)))
        .getSingleOrNull();
    if (receipt == null) return null;

    return RecordPaymentResult(
      paymentId: payment.id,
      receiptId: receipt.id,
      receiptNumber: receipt.receiptNumber,
      whatsApp: const WhatsAppNotRequested(),
    );
  }

  /// Sends a receipt and records the attempt.
  ///
  /// Every attempt — success or failure — writes a WhatsAppMessage row, so the
  /// WhatsApp screen shows a complete history and failures stay visible and
  /// retryable. This never throws: the caller must not be able to lose a
  /// recorded payment because messaging broke.
  Future<WhatsAppOutcome> sendReceipt({
    required int receiptId,
    required String receiptNumber,
    required int memberId,
    required String memberName,
    required String phone,
    required String gymName,
    required String amountLabel,
    required String periodLabel,
    Uint8List? pngBytes,
  }) async {
    final priorAttempts = await (db.select(db.whatsAppMessages)
          ..where((m) => m.receiptId.equals(receiptId)))
        .get();
    final attemptNumber = priorAttempts.length + 1;

    late final WhatsAppClient client;
    try {
      client = clientFactory();
    } catch (e, s) {
      _log.severe('WhatsApp client could not be built', e, s);
      return _recordFailure(
        receiptId: receiptId,
        memberId: memberId,
        phone: phone,
        kind: WhatsAppProviderKind.meta,
        attemptNumber: attemptNumber,
        error: '$e',
      );
    }

    // Validate before spending an API call on an unusable number.
    if (!isValidPhone(phone)) {
      return _recordFailure(
        receiptId: receiptId,
        memberId: memberId,
        phone: phone,
        kind: client.kind,
        attemptNumber: attemptNumber,
        error: 'Member phone number is not valid for WhatsApp: $phone',
      );
    }

    var bytes = pngBytes;
    if (bytes == null) {
      final receipt = await byIdOrNull(receiptId);
      bytes = receipt == null ? null : await storage.read(receipt.pngPath);
      if (bytes == null) {
        return _recordFailure(
          receiptId: receiptId,
          memberId: memberId,
          phone: phone,
          kind: client.kind,
          attemptNumber: attemptNumber,
          error: 'Receipt image is missing from storage',
        );
      }
    }

    final result = await client.send(WhatsAppSendInput(
      to: phone,
      caption: _caption(
        gymName: gymName,
        receiptNumber: receiptNumber,
        memberName: memberName,
        periodLabel: periodLabel,
        amountLabel: amountLabel,
      ),
      imageBytes: bytes,
      fileName: '$receiptNumber.png',
    ));

    return switch (result) {
      WhatsAppSendFailure(:final error) => _recordFailure(
          receiptId: receiptId,
          memberId: memberId,
          phone: phone,
          kind: client.kind,
          attemptNumber: attemptNumber,
          error: error,
        ),
      WhatsAppSendSuccess(:final externalMessageId) => _recordSuccess(
          receiptId: receiptId,
          memberId: memberId,
          phone: phone,
          kind: client.kind,
          attemptNumber: attemptNumber,
          messageId: externalMessageId,
        ),
    };
  }

  Future<Receipt?> byIdOrNull(int id) =>
      (db.select(db.receipts)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  /// Re-sends an existing receipt, rebuilding the caption from stored records
  /// so a retry carries the same details as the original send.
  Future<WhatsAppOutcome> resend(int receiptId) async {
    final receipt = await byIdOrNull(receiptId);
    if (receipt == null) {
      return const WhatsAppFailed('Receipt not found');
    }

    final payment = await (db.select(db.payments)
          ..where((p) => p.id.equals(receipt.paymentId)))
        .getSingle();
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(payment.memberId)))
        .getSingle();
    final settings =
        await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
            .getSingle();

    var periodLabel = '—';
    if (payment.membershipPeriodId != null) {
      final period = await (db.select(db.membershipPeriods)
            ..where((p) => p.id.equals(payment.membershipPeriodId!)))
          .getSingleOrNull();
      if (period != null) {
        final membership = await (db.select(db.memberships)
              ..where((m) => m.id.equals(period.membershipId)))
            .getSingleOrNull();
        final plan = membership == null
            ? null
            : await (db.select(db.membershipPlans)
                  ..where((p) => p.id.equals(membership.planId)))
                .getSingleOrNull();
        periodLabel = formatBillingPeriod(
            period.periodStart, plan?.durationMonths ?? 1);
      }
    }

    return sendReceipt(
      receiptId: receipt.id,
      receiptNumber: receipt.receiptNumber,
      memberId: member.id,
      memberName: member.fullName,
      phone: member.phone,
      gymName: settings.gymName,
      amountLabel: formatMinorUnits(payment.amountMinor, settings.currency),
      periodLabel: periodLabel,
    );
  }

  Future<WhatsAppOutcome> _recordFailure({
    required int receiptId,
    required int memberId,
    required String phone,
    required WhatsAppProviderKind kind,
    required int attemptNumber,
    required String error,
  }) async {
    await db.into(db.whatsAppMessages).insert(
          WhatsAppMessagesCompanion.insert(
            receiptId: receiptId,
            memberId: memberId,
            phone: phone,
            provider: kind,
            status: const Value(WhatsAppStatus.failed),
            errorMessage: Value(error),
            attemptNumber: Value(attemptNumber),
            failedAt: Value(DateTime.now()),
          ),
        );
    return WhatsAppFailed(error);
  }

  Future<WhatsAppOutcome> _recordSuccess({
    required int receiptId,
    required int memberId,
    required String phone,
    required WhatsAppProviderKind kind,
    required int attemptNumber,
    required String messageId,
  }) async {
    await db.into(db.whatsAppMessages).insert(
          WhatsAppMessagesCompanion.insert(
            receiptId: receiptId,
            memberId: memberId,
            phone: phone,
            provider: kind,
            externalMessageId: Value(messageId),
            status: const Value(WhatsAppStatus.sent),
            attemptNumber: Value(attemptNumber),
            sentAt: Value(DateTime.now()),
          ),
        );
    return WhatsAppSent(messageId);
  }

  String _caption({
    required String gymName,
    required String receiptNumber,
    required String memberName,
    required String periodLabel,
    required String amountLabel,
  }) =>
      [
        '*$gymName* — Payment Receipt',
        '',
        'Receipt: $receiptNumber',
        'Member: $memberName',
        'Period: $periodLabel',
        'Amount: $amountLabel',
        '',
        'Thank you for your payment.',
      ].join('\n');

  String? _blankToNull(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value.trim();

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} '
        '${months[date.month - 1]} ${date.year}';
  }

  static String _methodLabel(PaymentMethod method) => switch (method) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.bankTransfer => 'Bank Transfer',
        PaymentMethod.easypaisa => 'Easypaisa',
        PaymentMethod.jazzcash => 'JazzCash',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Other',
      };
}
