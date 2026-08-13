import 'package:drift/drift.dart';

import '../data/database.dart';
import '../domain/billing_period.dart';
import '../domain/money.dart';
import '../domain/phone.dart';
import '../domain/receipt_number.dart';
import 'receipt_renderer.dart';
import 'receipt_storage.dart';
import 'whatsapp/whatsapp_client.dart';

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
/// Payment, billing period, receipt number and receipt row are written in a
/// single database transaction, so a receipt can never exist without its
/// payment. WhatsApp is attempted only *after* that transaction commits — a
/// messaging failure must never roll back money that was actually collected.
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
    final membership = await (db.select(db.memberships)
          ..where((m) => m.memberId.equals(memberId) & m.endDate.isNull()))
        .getSingleOrNull();
    if (membership == null) return null;

    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(membership.planId)))
        .getSingleOrNull();
    if (plan == null) return null;

    final bounds = periodBounds(billingMonth, plan.durationMonths);

    final period = await (db.select(db.membershipPeriods)
          ..where((p) =>
              p.membershipId.equals(membership.id) &
              p.periodStart.equals(bounds.periodStart)))
        .getSingleOrNull();
    if (period == null) return null;

    return (db.select(db.payments)
          ..where((p) => p.membershipPeriodId.equals(period.id))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<RecordPaymentResult> call(RecordPaymentInput input) async {
    // A repeat submit with the same key is not an error: hand back what was
    // recorded the first time.
    final existing = await (db.select(db.payments)
          ..where((p) => p.idempotencyKey.equals(input.idempotencyKey)))
        .getSingleOrNull();
    if (existing != null) {
      final receipt = await (db.select(db.receipts)
            ..where((r) => r.paymentId.equals(existing.id)))
          .getSingleOrNull();
      if (receipt != null) {
        return RecordPaymentResult(
          paymentId: existing.id,
          receiptId: receipt.id,
          receiptNumber: receipt.receiptNumber,
          whatsApp: const WhatsAppNotRequested(),
        );
      }
    }

    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(input.memberId)))
        .getSingle();

    final membership = await (db.select(db.memberships)
          ..where((m) => m.memberId.equals(input.memberId) & m.endDate.isNull()))
        .getSingleOrNull();

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

    // --- Everything below commits together, or not at all -------------------
    final committed = await db.transaction(() async {
      var period = await (db.select(db.membershipPeriods)
            ..where((p) =>
                p.membershipId.equals(membership.id) &
                p.periodStart.equals(bounds.periodStart)))
          .getSingleOrNull();

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

      // Allocating the sequence inside the transaction is what stops two
      // payments confirmed at the same moment sharing a receipt number.
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

      final receiptNumber =
          formatReceiptNumber(settings.receiptPrefix, receiptYear, next);

      final rendered = await renderer.render(ReceiptData(
        gymName: settings.gymName,
        receiptNumber: receiptNumber,
        paymentDate: _formatDate(input.paymentDate),
        memberName: member.fullName,
        memberCode: member.memberCode,
        membershipLabel: plan.name,
        billingPeriod:
            formatBillingPeriod(bounds.periodStart, plan.durationMonths),
        paymentMethod: _methodLabel(input.method),
        referenceNumber: input.referenceNumber,
        amountLabel: formatMinorUnits(input.amountMinor, settings.currency),
        footerMessage: settings.receiptFooterMessage,
        gymPhone: settings.phone,
        gymAddress: settings.address,
      ));

      final pngPath = await storage.save(
          '$receiptNumber.png', rendered.png);
      final pdfPath = await storage.save(
          '$receiptNumber.pdf', rendered.pdf);

      final receiptId = await db.into(db.receipts).insert(
            ReceiptsCompanion.insert(
              receiptNumber: receiptNumber,
              paymentId: paymentId,
              pngPath: pngPath,
              pdfPath: Value(pdfPath),
            ),
          );

      return (
        paymentId: paymentId,
        receiptId: receiptId,
        receiptNumber: receiptNumber,
        png: rendered.png,
        periodLabel:
            formatBillingPeriod(bounds.periodStart, plan.durationMonths),
        amountLabel: formatMinorUnits(input.amountMinor, settings.currency),
      );
    });

    // --- Past this line the money is safely recorded ------------------------
    if (!input.sendWhatsApp) {
      return RecordPaymentResult(
        paymentId: committed.paymentId,
        receiptId: committed.receiptId,
        receiptNumber: committed.receiptNumber,
        whatsApp: const WhatsAppNotRequested(),
      );
    }

    final sendResult = await sendReceipt(
      receiptId: committed.receiptId,
      receiptNumber: committed.receiptNumber,
      memberId: member.id,
      memberName: member.fullName,
      phone: member.phone,
      gymName: settings.gymName,
      amountLabel: committed.amountLabel,
      periodLabel: committed.periodLabel,
      pngBytes: committed.png,
    );

    return RecordPaymentResult(
      paymentId: committed.paymentId,
      receiptId: committed.receiptId,
      receiptNumber: committed.receiptNumber,
      whatsApp: sendResult,
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
    } catch (e) {
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
