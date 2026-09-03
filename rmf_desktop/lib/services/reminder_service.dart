import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/database.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
import '../domain/phone.dart';
import '../domain/reminder_schedule.dart';
import 'billing_cycle_service.dart';
import 'whatsapp/message_texts.dart';
import 'whatsapp/whatsapp_client.dart';

final _log = Logger('reminders');

/// One member's reminder, ready to show or to send.
class ReminderCandidate {
  const ReminderCandidate({
    required this.member,
    required this.periodId,
    required this.dueDate,
    required this.amountDueMinor,
    required this.scheduled,
  });

  final Member member;

  /// The cycle this reminder is about, if one has been billed yet. Null for a
  /// "before due" nudge about a cycle that only exists as a projection —
  /// materialising one purely to attach a reminder to it would mean a cycle
  /// nobody has been charged for reading as debt. See
  /// `BillingCycleService`'s note on not creating cycles speculatively.
  final int? periodId;

  final DateTime dueDate;
  final int amountDueMinor;
  final ScheduledReminder scheduled;

  ReminderStage get stage => scheduled.stage;
  int get offsetDays => scheduled.offsetDays;
}

sealed class ReminderOutcome {
  const ReminderOutcome();
}

class ReminderSent extends ReminderOutcome {
  const ReminderSent(this.messageId);
  final String messageId;
}

class ReminderFailed extends ReminderOutcome {
  const ReminderFailed(this.error);
  final String error;
}

/// Detects who is due, who is overdue, and sends the message — the automated
/// half of the billing-cycle feature.
///
/// There is no cron here: this app has no server, and nothing runs while it is
/// closed. "Automatic" means "the next time the counter machine has the app
/// open", which is why [runAutoSend] exists as a distinct, capped, hours-aware
/// operation rather than every reminder simply going out the moment it is
/// found — see `domain/reminder_schedule.dart` for the reasoning.
class ReminderService {
  ReminderService({
    required this.db,
    required this.clientFactory,
    AuditRepository? audit,
    BillingCycleService? cycles,
  })  : _audit = audit ?? AuditRepository(db),
        _cycles = cycles ?? BillingCycleService(db, audit: audit);

  final AppDatabase db;
  final Future<WhatsAppClient> Function() clientFactory;
  final AuditRepository _audit;
  final BillingCycleService _cycles;

  Future<ReminderSettings> loadSettings() async {
    final row =
        await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
            .getSingle();
    return ReminderSettings(
      daysBefore: parseOffsetDays(row.reminderDaysBefore),
      onDueDate: row.reminderOnDueDate,
      daysAfter: parseOffsetDays(row.reminderDaysAfter),
      autoSend: row.reminderAutoSend,
      sendFromHour: row.reminderSendFromHour,
      sendUntilHour: row.reminderSendUntilHour,
      maxPerRun: row.reminderMaxPerRun,
    );
  }

  /// Every reminder owed right now, oldest due date first.
  ///
  /// This also settles the bookkeeping side of supersession: a reminder whose
  /// moment has passed while a later one for the same cycle came due is
  /// recorded `skipped` here, the moment it is found, so it can never surface
  /// again on a later call and can never fire out of order.
  Future<List<ReminderCandidate>> buildQueue({DateTime? now}) async {
    final settings = await loadSettings();
    if (!settings.sendsAnything) return const [];

    final at = (now ?? DateTime.now()).toUtc();
    final today = DateTime.utc(at.year, at.month, at.day);

    final members = await (db.select(db.members)
          ..where((m) => m.deactivatedAt.isNull()))
        .get();

    final candidates = <ReminderCandidate>[];

    for (final member in members) {
      final billing = await _cycles.forMember(member.id);
      if (billing == null) continue;

      final dueDate = billing.nextDueDate;
      final unsettled = billing.nextUnsettled;
      final amountDue = unsettled?.outstandingMinor ?? billing.feeMinor;
      if (amountDue <= 0) continue;

      final handled = await _handledKeys(memberId: member.id, dueDate: dueDate);
      final decision = decideReminder(
        settings: settings,
        dueDate: dueDate,
        today: today,
        alreadyHandled: handled,
      );

      for (final skipped in decision.superseded) {
        await _recordOutcome(
          member: member,
          periodId: unsettled?.periodId,
          cycleDueDate: dueDate,
          scheduled: skipped,
          amountDueMinor: amountDue,
          status: ReminderSendStatus.skipped,
        );
      }

      final toSend = decision.send;
      if (toSend == null) continue;

      candidates.add(ReminderCandidate(
        member: member,
        periodId: unsettled?.periodId,
        dueDate: dueDate,
        amountDueMinor: amountDue,
        scheduled: toSend,
      ));
    }

    candidates.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return candidates;
  }

  /// Sends [candidate]'s message and records what happened. Never throws: a
  /// reminder run must not be able to take the whole queue down over one bad
  /// number or a broken token.
  Future<ReminderOutcome> send(
    ReminderCandidate candidate, {
    int? actorId,
  }) async {
    final member = candidate.member;
    final settings =
        await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
            .getSingle();

    final template = settings.whatsappReminderTemplate;
    if (template == null || template.trim().isEmpty) {
      return _finish(
        candidate: candidate,
        outcome: const ReminderFailed(
          'No WhatsApp reminder template is configured yet. Set one in '
          'Settings.',
        ),
        actorId: actorId,
      );
    }

    final to = normalizePhone(member.phoneRaw ?? member.phone) ??
        normalizePhone(member.phone);
    if (to == null) {
      return _finish(
        candidate: candidate,
        outcome: const ReminderFailed(
          'This member has no number usable for WhatsApp.',
        ),
        actorId: actorId,
      );
    }

    final WhatsAppClient client;
    try {
      client = await clientFactory();
    } catch (error, stack) {
      _log.severe('WhatsApp client could not be built', error, stack);
      return _finish(
        candidate: candidate,
        outcome: ReminderFailed('$error'),
        actorId: actorId,
      );
    }

    final amountLabel =
        formatMinorUnits(candidate.amountDueMinor, settings.currency);

    final result = await client.sendTemplate(WhatsAppTemplateInput(
      to: to,
      templateName: template,
      languageCode: settings.whatsappReminderTemplateLanguage,
      bodyParams: reminderTemplateParams(
        memberName: member.fullName,
        amountLabel: amountLabel,
        dueDateLabel: formatDayMonthYear(candidate.dueDate),
        gymName: settings.gymName,
        paymentInstructions: settings.paymentInstructions,
      ),
    ));

    return switch (result) {
      WhatsAppSendSuccess(:final externalMessageId) => _finish(
          candidate: candidate,
          outcome: ReminderSent(externalMessageId),
          actorId: actorId,
        ),
      WhatsAppSendFailure(:final error) => _finish(
          candidate: candidate,
          outcome: ReminderFailed(error),
          actorId: actorId,
        ),
    };
  }

  /// Sends as many of [candidates] as the gym's own configuration allows right
  /// now: only inside sending hours, and never more than [maxPerRun] per call
  /// — a fortnight's backlog must not land on the membership in one burst.
  ///
  /// Returns the outcomes for whatever was actually attempted; a call outside
  /// sending hours or with auto-send off attempts nothing and returns empty.
  Future<List<ReminderOutcome>> runAutoSend({DateTime? now}) async {
    final settings = await loadSettings();
    if (!settings.autoSend) return const [];

    final at = now ?? DateTime.now();
    if (!withinSendingWindow(at, settings)) return const [];

    final queue = await buildQueue(now: at);
    final batch = queue.take(settings.maxPerRun);

    final outcomes = <ReminderOutcome>[];
    for (final candidate in batch) {
      outcomes.add(await send(candidate));
    }
    return outcomes;
  }

  Future<ReminderOutcome> _finish({
    required ReminderCandidate candidate,
    required ReminderOutcome outcome,
    int? actorId,
  }) async {
    await _recordOutcome(
      member: candidate.member,
      periodId: candidate.periodId,
      cycleDueDate: candidate.dueDate,
      scheduled: candidate.scheduled,
      amountDueMinor: candidate.amountDueMinor,
      status: switch (outcome) {
        ReminderSent() => ReminderSendStatus.sent,
        ReminderFailed() => ReminderSendStatus.failed,
      },
      messageId: outcome is ReminderSent ? outcome.messageId : null,
      error: outcome is ReminderFailed ? outcome.error : null,
    );

    await _audit.record(
      category: AuditCategory.reminder,
      action: switch (outcome) {
        ReminderSent() => AuditAction.reminderSent,
        ReminderFailed() => AuditAction.reminderFailed,
      },
      outcome:
          outcome is ReminderSent ? AuditOutcome.success : AuditOutcome.failed,
      actorId: actorId,
      memberId: candidate.member.id,
      memberName: candidate.member.fullName,
      amountMinor: candidate.amountDueMinor,
      summary: switch (outcome) {
        ReminderSent() =>
          '${candidate.scheduled.stage.label} reminder sent to '
              '${candidate.member.fullName}',
        ReminderFailed() =>
          '${candidate.scheduled.stage.label} reminder to '
              '${candidate.member.fullName} could not be sent',
      },
      detail: [
        'To: ${maskPhone(candidate.member.phone)}',
        if (outcome is ReminderFailed) 'Reason: ${outcome.error}',
      ],
    );

    return outcome;
  }

  /// Writes or updates the one row a (member, stage, offset, due date)
  /// combination is allowed to have. Retrying a failed send updates that row
  /// rather than inserting another, so the unique key can still be the
  /// duplicate guard.
  /// [cycleDueDate] is the cycle's own due date — what a reminder is *about*
  /// — kept distinct from [scheduled]'s own `on` day: the two coincide for a
  /// due-date reminder but not for a before-due nudge or an overdue chase,
  /// and it is [cycleDueDate] that ties every stage for one cycle together so
  /// [_handledKeys] can ask "what has this cycle already had?" in one query.
  Future<void> _recordOutcome({
    required Member member,
    required int? periodId,
    required DateTime cycleDueDate,
    required ScheduledReminder scheduled,
    required int amountDueMinor,
    required ReminderSendStatus status,
    String? messageId,
    String? error,
  }) async {
    final existing = await (db.select(db.paymentReminders)
          ..where((r) =>
              r.memberId.equals(member.id) &
              r.stage.equals(scheduled.stage.name) &
              r.offsetDays.equals(scheduled.offsetDays) &
              r.dueDate.equals(cycleDueDate)))
        .getSingleOrNull();

    if (existing == null) {
      await db.into(db.paymentReminders).insert(
            PaymentRemindersCompanion.insert(
              membershipPeriodId: Value(periodId),
              memberId: member.id,
              stage: scheduled.stage.name,
              offsetDays: scheduled.offsetDays,
              status: status,
              dueDate: cycleDueDate,
              amountMinor: amountDueMinor,
              externalMessageId: Value(messageId),
              errorMessage: Value(error),
              sentAt: Value(
                  status == ReminderSendStatus.sent ? DateTime.now().toUtc() : null),
            ),
          );
      return;
    }

    await (db.update(db.paymentReminders)
          ..where((r) => r.id.equals(existing.id)))
        .write(PaymentRemindersCompanion(
      status: Value(status),
      membershipPeriodId: Value(periodId),
      amountMinor: Value(amountDueMinor),
      externalMessageId: Value(messageId),
      errorMessage: Value(error),
      attempts: Value(existing.attempts + 1),
      sentAt: Value(status == ReminderSendStatus.sent
          ? DateTime.now().toUtc()
          : existing.sentAt),
    ));
  }

  Future<Set<ReminderKey>> _handledKeys({
    required int memberId,
    required DateTime dueDate,
  }) async {
    final rows = await (db.select(db.paymentReminders)
          ..where((r) =>
              r.memberId.equals(memberId) & r.dueDate.equals(dueDate)))
        .get();

    return {
      for (final row in rows)
        ReminderKey(
          ReminderStage.values.byName(row.stage),
          row.offsetDays,
        ),
    };
  }
}
