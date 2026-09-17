import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/cycle_pricing_log.dart';
import '../data/database.dart';
import '../data/membership_queries.dart';
import '../domain/billing_month_check.dart';
import '../domain/billing_period.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
import '../domain/payment_errors.dart';
import '../domain/payment_method.dart';
import '../domain/payment_settlement.dart';
import '../domain/payment_timing.dart';
import '../domain/phone.dart';
import '../domain/receipt_number.dart';
import '../domain/reminder_schedule.dart';
import 'billing_cycle_service.dart';
import 'billing_month_checker.dart';
import 'receipt_renderer.dart';
import 'receipt_storage.dart';
import 'whatsapp/message_texts.dart';
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
    this.acknowledgedIssues = const [],
    this.expectedAmountMinor,
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

  /// Billing-month warnings the owner confirmed. Recorded so the log shows a
  /// decision was made rather than that the check never ran.
  final List<BillingMonthIssue> acknowledgedIssues;

  /// What the named month cost, when this payment has to open its cycle.
  ///
  /// Only consulted when [billingMonth] has no cycle yet — an existing cycle
  /// is settled history and its price is not a later caller's to move.
  ///
  /// Null means "whatever the member's fee is now", which is right for the
  /// month in front of the owner and wrong for back-entry: a gym typing up
  /// last year's ledger after a price rise would have every earlier month
  /// conjured at today's fee, paid in full, and left permanently short by the
  /// difference. Re-pricing cannot undo that, because a cycle holding money is
  /// never re-priced.
  final int? expectedAmountMinor;
}

/// A payment with no billing month attached — see
/// [RecordPaymentService.recordAdvancePayment].
///
/// Deliberately a separate shape from [RecordPaymentInput] rather than that
/// class with a nullable `billingMonth`: the two describe genuinely different
/// operations, and a shared shape would let a caller supply both or neither
/// and leave the ambiguity to be discovered at run time instead of at the call
/// site.
class AdvancePaymentInput {
  const AdvancePaymentInput({
    required this.memberId,
    required this.amountMinor,
    required this.method,
    required this.paymentDate,
    required this.sendWhatsApp,
    required this.recordedById,
    required this.idempotencyKey,
    this.referenceNumber,
    this.notes,
    this.confirmedAdvance = false,
  });

  final int memberId;
  final int amountMinor;
  final PaymentMethod method;
  final DateTime paymentDate;
  final bool sendWhatsApp;
  final int recordedById;

  /// The owner has seen how many cycles this payment would buy and said yes.
  ///
  /// Only consulted when the money reaches further ahead than
  /// [freeAdvanceCycles]; below that the question is never asked. Defaults to
  /// false so a caller that has not been through the prompt cannot skip it by
  /// omission.
  final bool confirmedAdvance;

  /// Generated once when the form opens — see [RecordPaymentInput] for why.
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
    this.timing = PaymentTiming.onTime,
  });

  final int paymentId;
  final int receiptId;
  final String receiptNumber;
  final WhatsAppOutcome whatsApp;

  /// Where the payment date fell relative to the cycle the money bought.
  ///
  /// Derived, never stored: it is a reading of two dates the database already
  /// holds, and a column would be a second answer to the same question that
  /// could go stale the moment a payment is edited. See `payment_timing.dart`.
  final PaymentTiming timing;
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
    AuditRepository? audit,
    BillingMonthChecker? checker,
    BillingCycleService? cycles,
  })  : _audit = audit ?? AuditRepository(db),
        _checker = checker ?? BillingMonthChecker(db),
        _cycles = cycles ?? BillingCycleService(db, audit: audit);

  final AppDatabase db;
  final ReceiptRenderer renderer;
  final ReceiptStorage storage;
  final AuditRepository _audit;

  /// The same rules the dialog runs before submitting. Checked again here so a
  /// month that cannot be right is refused by the code that writes the money,
  /// not only by the form in front of it.
  final BillingMonthChecker _checker;

  /// Where cycles and settlement live. Shared with [recordAdvancePayment],
  /// which is built entirely on it.
  final BillingCycleService _cycles;

  /// Resolved per send, so a provider or credential change in Settings takes
  /// effect without a restart.
  ///
  /// Asynchronous because choosing the provider means reading the settings row.
  /// A synchronous factory could only ever hand back a wrapper that did not yet
  /// know which provider it was — which is how every attempt came to be
  /// recorded against `mock`, real Meta sends included.
  final Future<WhatsAppClient> Function() clientFactory;

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
    //
    // By containment rather than start month, so a quarterly member's
    // August-October cycle is found when the owner picks September.
    final period = await periodForMemberContaining(
      db,
      memberId: memberId,
      month: parseBillingMonth(billingMonth),
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
      throw PaymentRuleException(
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

    await _guardBillingMonth(input, member);

    final bounds = periodBounds(input.billingMonth, plan.durationMonths);
    final receiptYear = input.paymentDate.year;

    // Which cycle this month belongs to, if one already exists. Read before
    // rendering because the receipt has to name that cycle's own months: on a
    // three-month plan, a payment picked as September belongs to — and must
    // read as — August 2026 - October 2026.
    final existingCycle = await periodForMemberContaining(
      db,
      memberId: member.id,
      month: bounds.periodStart,
    );
    final cycleStart =
        existingCycle?.periodStart.toUtc() ?? bounds.periodStart;

    // The calendar-month path reads its timing the same way the flexible one
    // does, against the start of the cycle the month belongs to — so a payment
    // recorded through either route is described identically on the receipt.
    final timing = classifyTiming(
      paidAt: input.paymentDate,
      periodStart: cycleStart,
      window: _timingWindowFrom(settings),
    );

    final periodLabel = _labelWithTiming(
        formatBillingPeriod(cycleStart, plan.durationMonths), timing);
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
      paymentDate: formatDayMonthYear(input.paymentDate),
      memberName: member.fullName,
      memberCode: member.memberCode,
      membershipLabel: plan.name,
      billingPeriod: periodLabel,
      paymentMethod: paymentMethodLabel(input.method),
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
        // Resolved again inside the transaction: the read above was for the
        // receipt text, and between then and here another submit could have
        // opened the cycle.
        var period = await periodForMemberContaining(
          db,
          memberId: member.id,
          month: bounds.periodStart,
        );

        if (period == null) {
          // The caller's figure only when the cycle is being created here; a
          // month that already has one keeps the price it was billed at. See
          // [RecordPaymentInput.expectedAmountMinor].
          final typed = input.expectedAmountMinor;
          final expected =
              typed ?? (membership.feeOverrideMinor ?? plan.priceMinor);

          period = await db.into(db.membershipPeriods).insertReturning(
                MembershipPeriodsCompanion.insert(
                  membershipId: membership.id,
                  periodStart: bounds.periodStart,
                  periodEnd: bounds.periodEnd,
                  expectedAmountMinor: expected,
                ),
              );

          // A figure typed on the form is its own reason: it is not the plan's
          // price and not the member's standing fee, and a later reader must
          // not be left to assume it was either.
          await recordCycleOpened(
            db,
            membershipPeriodId: period.id,
            amountMinor: expected,
            membership: membership,
            plan: plan,
            source: typed == null ? null : CyclePricingSource.manual,
            reason: typed == null
                ? 'Opened by a payment recorded for this month.'
                : 'Amount entered on the Record Payment form.',
            actorId: input.recordedById,
            at: input.paymentDate,
          );
        }

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

        // The full amount is attributed to this one cycle, whatever it is
        // relative to the fee: a generous top-up is not left partly homeless,
        // and a short payment is exactly what `refreshSettlement` needs to see
        // to read the cycle as partly paid rather than settled.
        await db.into(db.paymentAllocations).insert(
              PaymentAllocationsCompanion.insert(
                paymentId: paymentId,
                membershipPeriodId: period.id,
                amountMinor: input.amountMinor,
              ),
            );
        await _cycles.refreshSettlement(period.id);

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

      if (_isDuplicateCycle(error)) {
        _log.warning(
            'Duplicate cycle refused for member ${member.id}', error, stack);
        throw PaymentRuleException(
          '${member.fullName} already has a billing cycle recorded for '
          'that month. Check their payment history before recording this '
          'again — it may already have been paid.',
        );
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
        timing: timing,
      );
    }

    final sendResult = await sendReceipt(
      receiptId: committed.receiptId,
      receiptNumber: receiptNumber,
      memberId: member.id,
      memberName: member.fullName,
      phone: member.phone,
      amountLabel: amountLabel,
      periodLabel: periodLabel,
      pngBytes: rendered.png,
    );

    return RecordPaymentResult(
      paymentId: committed.paymentId,
      receiptId: committed.receiptId,
      receiptNumber: receiptNumber,
      whatsApp: sendResult,
      timing: timing,
    );
  }

  /// Records a payment against the member's own next unsettled cycle, or as
  /// many of them as the amount reaches, with no billing month to pick at all.
  ///
  /// This is the flexible path: the owner types an amount and a date, and the
  /// system works out which cycle it settles from the member's own timeline —
  /// arrears first, oldest to newest, exactly like [allocate] guarantees. Pay
  /// three days early, three weeks late, or three months in advance, and the
  /// same call does the right thing, because nothing here reads a "billing
  /// month" the owner would otherwise have to get right by hand.
  ///
  /// One payment, one receipt, however many cycles the money reaches. The
  /// cycles it settles are materialised only as this money actually reaches
  /// them — a cycle a payment does not touch is never created and never reads
  /// as debt.
  Future<RecordPaymentResult> recordAdvancePayment(
    AdvancePaymentInput input,
  ) async {
    final alreadyRecorded = await _resultForKey(input.idempotencyKey);
    if (alreadyRecorded != null) return alreadyRecorded;

    if (input.amountMinor <= 0) {
      throw PaymentRuleException('Enter an amount greater than zero.');
    }

    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(input.memberId)))
        .getSingle();

    final billing = await _cycles.forMember(input.memberId);
    if (billing == null) {
      throw PaymentRuleException(
        '${member.fullName} has no active membership. '
        'Assign a plan before recording a payment.',
      );
    }

    final settings =
        await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
            .getSingle();

    final offered = _cycles.settleableFor(
      billing: billing,
      amountMinor: input.amountMinor,
    );
    final settlement = allocate(amountMinor: input.amountMinor, cycles: offered);

    if (settlement.isEmpty) {
      throw PaymentRuleException(
        '${member.fullName} has nothing due right now that this amount can '
        'be applied to.',
      );
    }
    if (settlement.unallocatedMinor > 0) {
      throw PaymentRuleException(
        '${formatMinorUnits(settlement.unallocatedMinor, settings.currency)} '
        'of this payment does not fit inside the '
        '${BillingCycleService.maxCyclesPerPayment} cycles this can be applied '
        'to at once. Record the rest as a separate payment.',
      );
    }

    final span = settlement.coveredSpan!;
    final spanMonths = (span.end.year - span.start.year) * 12 +
        (span.end.month - span.start.month);

    // Judged against the first cycle the money reaches, which under
    // arrears-first allocation is the oldest one still owing. A member
    // settling July's fee in September has paid July late — not September on
    // time, which is what comparing against the calendar would have said.
    final timing = classifyTiming(
      paidAt: input.paymentDate,
      periodStart: span.start,
      window: _timingWindowFrom(settings),
    );

    // How far beyond the member's current cycle this money reaches. Cycles
    // that had already begun by the payment date are arrears, and clearing a
    // backlog is never something to interrogate the owner about.
    final paidOn = DateTime.utc(input.paymentDate.year,
        input.paymentDate.month, input.paymentDate.day);
    final futureCycles = settlement.allocations
        .where((a) => a.cycle.start.isAfter(paidOn))
        .length;

    final plainPeriodLabel = formatBillingPeriod(span.start, spanMonths);
    final periodLabel = _labelWithTiming(plainPeriodLabel, timing);

    // Checked before a receipt number is drawn or a single row is written, so
    // a payment awaiting confirmation leaves nothing behind to clean up.
    switch (classifyAdvanceReach(futureCycles)) {
      case AdvanceAllowance.allowed:
        break;
      case AdvanceAllowance.needsConfirmation:
        if (!input.confirmedAdvance) {
          throw AdvanceConfirmationRequired(
            futureCyclesCovered: futureCycles,
            coveredPeriodLabel: periodLabel,
            message: '${formatMinorUnits(input.amountMinor, settings.currency)} '
                'covers ${settlement.allocations.length} billing cycles for '
                '${member.fullName}, through '
                '${formatDayMonthYear(span.end.subtract(const Duration(days: 1)))}. '
                'Confirm to record it.',
          );
        }
      case AdvanceAllowance.refused:
        throw PaymentRuleException(
          'This payment would cover $futureCycles cycles beyond '
          "${member.fullName}'s current one, past the $maxAdvanceCycles-cycle "
          'limit. Check the amount, or record it as separate payments.',
        );
    }
    final amountLabel = formatMinorUnits(input.amountMinor, settings.currency);
    final receiptYear = input.paymentDate.year;

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
      paymentDate: formatDayMonthYear(input.paymentDate),
      memberName: member.fullName,
      memberCode: member.memberCode,
      membershipLabel: billing.plan.name,
      billingPeriod: periodLabel,
      paymentMethod: paymentMethodLabel(input.method),
      referenceNumber: input.referenceNumber,
      amountLabel: amountLabel,
      footerMessage: settings.receiptFooterMessage,
      gymPhone: settings.phone,
      gymAddress: settings.address,
    ));

    final pngPath = await storage.save('$receiptNumber.png', rendered.png);
    final pdfPath = await storage.save('$receiptNumber.pdf', rendered.pdf);

    // --- 3. The money, its cycles and its receipt commit together ------------
    final ({int paymentId, int receiptId}) committed;
    try {
      committed = await db.transaction(() async {
        // Every cycle the money reaches is opened first, because a cycle
        // that has only been computed has no id yet — and the payment row
        // needs one. Writing the payment first meant
        // `allocations.first.cycle.periodId` was null for any cycle this
        // payment was itself opening, which is every first payment for a
        // cycle. The row then showed "—" for its period on the dashboard,
        // the payments screen and the member's profile, and the timing badge
        // vanished with it, since both are read through this link.
        //
        // Still only the cycles the money actually reaches: the set is
        // unchanged, only the order is.
        final opened = <MembershipPeriod>[
          for (final allocation in settlement.allocations)
            await _cycles.materialise(
              membershipId: billing.membership.id,
              cycle: allocation.cycle,
            ),
        ];

        final paymentId = await db.into(db.payments).insert(
              PaymentsCompanion.insert(
                memberId: member.id,
                // The first cycle the money touches, for every caller that
                // still reads a payment's period as a single value — the
                // importer, the editor, the payment history table.
                membershipPeriodId: Value(opened.first.id),
                amountMinor: input.amountMinor,
                method: input.method,
                referenceNumber: Value(_blankToNull(input.referenceNumber)),
                paymentDate: input.paymentDate,
                notes: Value(_blankToNull(input.notes)),
                recordedById: input.recordedById,
                idempotencyKey: input.idempotencyKey,
              ),
            );

        for (var i = 0; i < settlement.allocations.length; i++) {
          final period = opened[i];

          await db.into(db.paymentAllocations).insert(
                PaymentAllocationsCompanion.insert(
                  paymentId: paymentId,
                  membershipPeriodId: period.id,
                  amountMinor: settlement.allocations[i].amountMinor,
                ),
              );
          await _cycles.refreshSettlement(period.id);
        }

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
      await storage.delete(pngPath);
      await storage.delete(pdfPath);

      final winner = await _resultForKey(input.idempotencyKey);
      if (winner != null) {
        _log.info('Duplicate submit for ${input.idempotencyKey} ignored');
        return winner;
      }

      if (_isDuplicateCycle(error)) {
        // The one-cycle-per-member guard fired. Reached when two tills record
        // for the same member at once, or when a cycle already exists on an
        // enrolment the member has since moved off — the case the trigger was
        // added for. Either way the owner needs the member and the month, not
        // a SQLite constraint name.
        _log.warning(
            'Duplicate cycle refused for member ${member.id}', error, stack);
        throw PaymentRuleException(
          '${member.fullName} already has a billing cycle recorded for '
          '$plainPeriodLabel. Check their payment history before recording '
          'this again — that cycle may already have been paid.',
        );
      }

      _log.severe('Recording the advance payment failed', error, stack);
      rethrow;
    }

    if (!input.sendWhatsApp) {
      return RecordPaymentResult(
        paymentId: committed.paymentId,
        receiptId: committed.receiptId,
        receiptNumber: receiptNumber,
        whatsApp: const WhatsAppNotRequested(),
        timing: timing,
      );
    }

    final sendResult = await sendReceipt(
      receiptId: committed.receiptId,
      receiptNumber: receiptNumber,
      memberId: member.id,
      memberName: member.fullName,
      phone: member.phone,
      amountLabel: amountLabel,
      periodLabel: periodLabel,
      pngBytes: rendered.png,
    );

    return RecordPaymentResult(
      paymentId: committed.paymentId,
      receiptId: committed.receiptId,
      receiptNumber: receiptNumber,
      whatsApp: sendResult,
      timing: timing,
    );
  }

  /// Refuses a billing month that cannot be right, and records the warnings
  /// the owner chose to continue past.
  Future<void> _guardBillingMonth(
    RecordPaymentInput input,
    Member member,
  ) async {
    final check = await _checker.check(
      memberId: input.memberId,
      billingMonth: input.billingMonth,
    );

    if (check.review.isBlocked) {
      final message = check.review.blocking.map((f) => f.message).join(' ');
      await _audit.record(
        category: AuditCategory.billing,
        action: AuditAction.billingMonthBlocked,
        outcome: AuditOutcome.refused,
        actorId: input.recordedById,
        memberId: member.id,
        memberName: member.fullName,
        summary: 'Payment blocked: ${input.billingMonth} is not a valid '
            'billing month for ${member.fullName}',
        detail: check.review.blocking.map((f) => f.message).toList(),
      );
      throw PaymentRuleException(message);
    }

    if (input.acknowledgedIssues.isEmpty) return;

    await _audit.record(
      category: AuditCategory.billing,
      action: AuditAction.billingMonthConfirmed,
      outcome: AuditOutcome.success,
      actorId: input.recordedById,
      memberId: member.id,
      memberName: member.fullName,
      summary: 'Billing-month warnings confirmed for ${member.fullName} '
          '(${input.billingMonth})',
      detail: input.acknowledgedIssues.map((i) => i.name).toList(),
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
      client = await clientFactory();
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

    // Sent as a template, not as a free-form image with a caption. Meta only
    // accepts free-form messages inside the 24-hour window that opens when the
    // member last messaged the gym, and a receipt goes out the moment the
    // payment is recorded — which is almost never inside one. A template is
    // delivered either way, and costs nothing when a window happens to be open.
    final settings =
        await (db.select(db.gymSettings)..where((row) => row.id.equals(1)))
            .getSingle();

    final result = await client.sendTemplate(WhatsAppTemplateInput(
      to: phone,
      templateName: settings.whatsappReceiptTemplate,
      languageCode: settings.whatsappReceiptTemplateLanguage,
      bodyParams: receiptTemplateParams(
        memberName: memberName,
        amountLabel: amountLabel,
        periodLabel: periodLabel,
        receiptNumber: receiptNumber,
      ),
      headerImageBytes: bytes,
      headerImageFileName: '$receiptNumber.png',
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

  /// The window inside which a payment counts as on time, read from the
/// reminder schedule the owner has already configured.
///
/// Deriving it rather than adding a second setting means the badge on a
/// payment and the message the member received cannot disagree: a payment is
/// early once it beats the gym's own nudge, and late once the gym would have
/// chased it.
TimingWindow _timingWindowFrom(GymSetting settings) =>
    TimingWindow.fromReminderOffsets(
      daysBefore: parseOffsetDays(settings.reminderDaysBefore),
      daysAfter: parseOffsetDays(settings.reminderDaysAfter),
    );

/// The billing period with the payment's timing appended, when there is
/// anything worth saying about it.
///
/// This rides along inside the period label rather than as its own field
/// because the label is the one piece of free text that already reaches
/// everywhere the answer is needed: the rendered receipt, the WhatsApp
/// caption, and parameter 3 of the `payment_receipt` template. Meta approves
/// each template's parameter list individually, so adding a fifth parameter
/// would take the gym's receipts off the air until it was re-approved.
String _labelWithTiming(String periodLabel, PaymentTiming timing) =>
    switch (timing) {
      PaymentTiming.advance => '$periodLabel (paid in advance)',
      PaymentTiming.late => '$periodLabel (paid late)',
      PaymentTiming.onTime => periodLabel,
    };

/// Whether [error] is the one-cycle-per-member trigger firing.
///
/// Matched on the message the trigger raises, which is fixed in
/// `AppDatabase._createCycleUniquenessTriggers` — there is no error code to
/// match on, SQLite reports a RAISE(ABORT) as a generic constraint failure.
bool _isDuplicateCycle(Object error) =>
    error.toString().contains('duplicate billing cycle');

String? _blankToNull(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value.trim();

}
