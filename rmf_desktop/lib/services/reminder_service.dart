import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../data/audit_repository.dart';
import '../data/database.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
import '../domain/payment_settlement.dart';
import '../domain/phone.dart';
import '../domain/reminder_schedule.dart';
import 'billing_cycle_service.dart';
import 'whatsapp/message_texts.dart';
import 'whatsapp/whatsapp_client.dart';

final _log = Logger('reminders');

/// How many sends in a row may fail before an automatic run gives up.
///
/// A broken token, a missing template or a dead connection fails every member
/// the same way, and ploughing on through the whole per-run cap only writes
/// the same failure into the log twenty-five times an hour. Stopping early is
/// not a retry policy: whatever was not attempted is simply still in the
/// queue for the next run, exactly as if the cap had been reached.
const _maxConsecutiveAutoFailures = 3;

/// One member's reminder, ready to show or to send.
class ReminderCandidate {
  const ReminderCandidate({
    required this.member,
    required this.periodId,
    required this.dueDate,
    required this.amountDueMinor,
    required this.scheduled,
    this.asOf,
    this.byHand = false,
    this.retry = false,
  });

  final Member member;

  /// The cycle this reminder is about, if one has been billed yet. Null for a
  /// "before due" nudge about a cycle that only exists as a projection —
  /// materialising one purely to attach a reminder to it would mean a cycle
  /// nobody has been charged for reading as debt. See
  /// `BillingCycleService`'s note on not creating cycles speculatively.
  final int? periodId;

  /// The due date of the cycle the reminder is keyed by: for a member behind
  /// by more than one cycle, the newest one that has started — see
  /// [ReminderService]'s note on members in arrears.
  final DateTime dueDate;

  /// Everything owed up to and including the cycle due on [dueDate].
  final int amountDueMinor;

  final ScheduledReminder scheduled;

  /// The UTC day this candidate was worked out for. [ReminderService.send]
  /// re-checks the member's billing as of this same day, so a queue built for
  /// a given day is judged against that day rather than against whatever the
  /// clock says by the time the owner presses Send. Null reads as the day the
  /// reminder itself was scheduled for.
  final DateTime? asOf;

  /// Raised from the member's own screen rather than by the schedule.
  ///
  /// The owner pressing the button while looking at the member is entitled to
  /// chase twice in one day, so a reminder already recorded for this stage
  /// does not stop it. It is still refused if the member has paid since, or
  /// if another send to them is in flight.
  final bool byHand;

  /// An earlier attempt at this same reminder failed. Shown on the Reminders
  /// screen, and sent after the never-tried ones in an automatic run so a few
  /// bad numbers at the head of the queue cannot crowd everybody else out.
  final bool retry;

  ReminderStage get stage => scheduled.stage;
  int get offsetDays => scheduled.offsetDays;

  ReminderCandidate _refreshed({
    required Member member,
    required int? periodId,
    required int amountDueMinor,
  }) =>
      ReminderCandidate(
        member: member,
        periodId: periodId,
        dueDate: dueDate,
        amountDueMinor: amountDueMinor,
        scheduled: scheduled,
        asOf: asOf,
        byHand: byHand,
        retry: retry,
      );
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

/// Not sent, because by the time it came to go out it was no longer wanted:
/// the member paid, left, was already reminded, or is being messaged by
/// another send at this very moment.
///
/// A kind of [ReminderFailed] so every two-way switch over the outcome still
/// compiles and still tells the owner nothing went out, but distinct so a
/// screen can say "no longer needed" rather than "could not be sent". Nothing
/// is recorded against the reminder for it: the reminder did not fail.
class ReminderNotNeeded extends ReminderFailed {
  const ReminderNotNeeded(super.error);
}

/// What a member's reminder is about as of one day: which cycle's due date it
/// is keyed by, and how much to ask for.
class _ReminderTarget {
  const _ReminderTarget({
    required this.dueDate,
    required this.periodId,
    required this.amountMinor,
  });

  final DateTime dueDate;
  final int? periodId;
  final int amountMinor;
}

/// Detects who is due, who is overdue, and sends the message — the automated
/// half of the billing-cycle feature.
///
/// There is no cron here: this app has no server, and nothing runs while it is
/// closed. "Automatic" means "whenever the counter machine has the app open" —
/// at launch, on Reload and once an hour from `AppShell` — which is why
/// [runAutoSend] exists as a distinct, capped, hours-aware operation rather
/// than every reminder simply going out the moment it is found — see
/// `domain/reminder_schedule.dart` for the reasoning.
///
/// **Members in arrears.** A member who owes more than one cycle is reminded
/// about the newest one that has started, quoting everything owed up to it.
/// Keying by the oldest unpaid cycle, as this once did, meant that once its
/// stages had all fired the member furthest behind was never chased again,
/// and a manual reminder asked for one month when two were owed.
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

  /// Members a send is currently in flight for.
  ///
  /// The row that stops a reminder going out twice is only written once the
  /// provider has answered, and the automatic run and the Reminders screen
  /// both send through this one instance (see `main.dart`). Without this, the
  /// owner pressing Send while the automatic run was mid-flight messaged the
  /// same member twice. Per member rather than per reminder: nobody should
  /// receive two reminders at once, whichever stages they are for. The same
  /// guard `MemberWelcomeService` uses.
  final Set<int> _inFlight = <int>{};

  /// The automatic run in progress, so the launch, Reload and the hourly timer
  /// cannot start a second one on top of it.
  Future<List<ReminderOutcome>>? _autoRun;

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
  ///
  /// A reminder that failed to send is offered again — it was never
  /// delivered — unless the member still has no number WhatsApp could use,
  /// which no amount of retrying fixes. Correct the number and it comes back.
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
      // Being messaged right now by another send; offering it here is how the
      // screen used to hand the owner a second copy to send.
      if (_inFlight.contains(member.id)) continue;

      final billing = await _cycles.forMember(member.id);
      if (billing == null) continue;

      final target = _targetFor(billing, today);
      if (target == null) continue;

      final rows = await _reminderRows(
        memberId: member.id,
        dueDate: target.dueDate,
      );
      final retryFailed = _recipientFor(member) != null;
      final decision = decideReminder(
        settings: settings,
        dueDate: target.dueDate,
        today: today,
        alreadyHandled: {
          for (final MapEntry(:key, :value) in rows.entries)
            if (value != ReminderSendStatus.failed || !retryFailed) key,
        },
      );

      for (final skipped in decision.superseded) {
        await _recordOutcome(
          member: member,
          periodId: target.periodId,
          cycleDueDate: target.dueDate,
          scheduled: skipped,
          amountDueMinor: target.amountMinor,
          status: ReminderSendStatus.skipped,
        );
      }

      final toSend = decision.send;
      if (toSend == null) continue;

      candidates.add(ReminderCandidate(
        member: member,
        periodId: target.periodId,
        dueDate: target.dueDate,
        amountDueMinor: target.amountMinor,
        scheduled: toSend,
        asOf: today,
        retry: rows[toSend.key] == ReminderSendStatus.failed,
      ));
    }

    candidates.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return candidates;
  }

  /// Clears a reminder without sending it.
  ///
  /// For a queue the owner has already dealt with off the screen: the members
  /// were caught at the counter, or chased on the phone, and sending each of
  /// them a template anyway costs money and reads as nagging.
  ///
  /// Recorded as `skipped` rather than deleted. The row is what stops the
  /// reminder coming back — [buildQueue] counts any row for the stage that is
  /// not a failure — and it still answers "what happened to this one"
  /// afterwards, which a deleted row could not. Nothing about the member's
  /// cycle changes, so the next one to fall due raises a fresh reminder.
  Future<void> dismiss(ReminderCandidate candidate, {int? actorId}) async {
    await _recordOutcome(
      member: candidate.member,
      periodId: candidate.periodId,
      cycleDueDate: candidate.dueDate,
      scheduled: candidate.scheduled,
      amountDueMinor: candidate.amountDueMinor,
      status: ReminderSendStatus.skipped,
    );

    await _audit.record(
      category: AuditCategory.reminder,
      action: AuditAction.reminderSkipped,
      outcome: AuditOutcome.success,
      actorId: actorId,
      memberId: candidate.member.id,
      memberName: candidate.member.fullName,
      amountMinor: candidate.amountDueMinor,
      summary: '${candidate.scheduled.stage.label} reminder for '
          '${candidate.member.fullName} cleared without sending',
      detail: ['Due: ${formatDayMonthYear(candidate.dueDate)}'],
    );
  }

  /// The reminder for one member, whatever the schedule says.
  ///
  /// Deliberately not routed through [decideReminder], which is what separates
  /// it from [buildQueue]. An owner who has turned the automatic run off has no
  /// queue at all, and the button on the member's own screen is then the only
  /// way to chase anybody — so gating it on the configured offsets would make
  /// it useless in exactly the setup it exists for. Sending a second time in
  /// one day is a decision the owner is entitled to make while looking at the
  /// member.
  ///
  /// Null where there is nobody to remind: the member has left, or has no
  /// enrolment to owe anything against. Whether they are *due* is the calling
  /// screen's question, answered by `MemberStatus.isOwing` beside the badge.
  Future<ReminderCandidate?> candidateForMember(
    int memberId, {
    DateTime? now,
  }) async {
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(memberId)))
        .getSingleOrNull();
    if (member == null || member.deactivatedAt != null) return null;

    final billing = await _cycles.forMember(memberId);
    if (billing == null) return null;

    final at = (now ?? DateTime.now()).toUtc();
    final today = DateTime.utc(at.year, at.month, at.day);

    final target = _targetFor(billing, today);
    if (target == null) return null;
    final dueDate = target.dueDate;

    // Named for where today sits against the cycle's due date, so the message
    // and the audit trail read the same as a scheduled one would.
    final days = today.difference(dueDate).inDays;
    final key = days < 0
        ? ReminderKey(ReminderStage.beforeDue, -days)
        : days == 0
            ? const ReminderKey(ReminderStage.onDue, 0)
            : ReminderKey(ReminderStage.overdue, days);

    return ReminderCandidate(
      member: member,
      periodId: target.periodId,
      dueDate: dueDate,
      amountDueMinor: target.amountMinor,
      scheduled: ScheduledReminder(key: key, on: today),
      asOf: today,
      byHand: true,
    );
  }

  /// Sends [candidate]'s message and records what happened. Never throws: a
  /// reminder run must not be able to take the whole queue down over one bad
  /// number or a broken token.
  ///
  /// The candidate may have been built minutes ago, on a screen the owner has
  /// had open since, so it is checked again first — see [_recheck] — and a
  /// reminder that is no longer wanted comes back as [ReminderNotNeeded]
  /// without anything being sent.
  Future<ReminderOutcome> send(
    ReminderCandidate candidate, {
    int? actorId,
  }) async {
    final memberId = candidate.member.id;

    // Claimed before the first await, so two sends started in the same turn
    // of the event loop cannot both get past it.
    if (!_inFlight.add(memberId)) {
      _log.info('A reminder to member $memberId is already being sent');
      return const ReminderNotNeeded(
          'A reminder to this member is already being sent.');
    }

    try {
      return await _send(candidate, actorId: actorId);
    } catch (error, stack) {
      // Belt and braces: nothing below is meant to throw, and the caller is
      // usually a loop that must carry on to the next member.
      _log.severe('Sending a reminder failed unexpectedly', error, stack);
      return ReminderFailed('$error');
    } finally {
      _inFlight.remove(memberId);
    }
  }

  Future<ReminderOutcome> _send(
    ReminderCandidate prepared, {
    int? actorId,
  }) async {
    final (candidate, refused) = await _recheck(prepared);
    if (refused != null) {
      _log.info('Reminder to member ${prepared.member.id} not sent: '
          '${refused.error}');
      return refused;
    }
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

    final to = _recipientFor(member);
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

  /// Whether [prepared] should still go out, and with what figures.
  ///
  /// Returns the candidate to send — carrying the member and the amount as
  /// they stand now, so a part-payment made since is reflected in the
  /// message — and, when it must not go at all, a [ReminderNotNeeded] saying
  /// why not:
  ///
  ///  * the member has left;
  ///  * a scheduled reminder has meanwhile been sent or cleared (by the
  ///    automatic run, the screen, or Clear all) — a failure does not count,
  ///    since re-trying one is the point;
  ///  * the member has paid since, so the cycle the reminder is about is no
  ///    longer the one they owe for, or they owe nothing at all.
  Future<(ReminderCandidate, ReminderNotNeeded?)> _recheck(
    ReminderCandidate prepared,
  ) async {
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(prepared.member.id)))
        .getSingleOrNull();
    if (member == null || member.deactivatedAt != null) {
      return (
        prepared,
        const ReminderNotNeeded('This member is no longer active.'),
      );
    }

    if (!prepared.byHand) {
      final rows = await _reminderRows(
        memberId: member.id,
        dueDate: prepared.dueDate,
      );
      final status = rows[prepared.scheduled.key];
      if (status != null && status != ReminderSendStatus.failed) {
        return (
          prepared,
          ReminderNotNeeded(status == ReminderSendStatus.sent
              ? 'This reminder has already been sent.'
              : 'This reminder has already been cleared.'),
        );
      }
    }

    final billing = await _cycles.forMember(member.id);
    final asOf = prepared.asOf ?? prepared.scheduled.on;
    final target = billing == null
        ? null
        : _targetFor(billing, DateTime.utc(asOf.year, asOf.month, asOf.day));
    if (target == null || target.dueDate != prepared.dueDate) {
      return (
        prepared,
        ReminderNotNeeded(
            '${member.fullName} has paid since this reminder was prepared.'),
      );
    }

    final refreshed = prepared._refreshed(
      member: member,
      periodId: target.periodId,
      amountDueMinor: target.amountMinor,
    );
    return (refreshed, null);
  }

  /// Sends as many of [candidates] as the gym's own configuration allows right
  /// now: only inside sending hours, and never more than [maxPerRun] per call
  /// — a fortnight's backlog must not land on the membership in one burst.
  ///
  /// Safe to call as often as the app likes — at launch, on Reload, from a
  /// timer: a call while one is already running sends nothing, every send is
  /// re-checked against the member's billing and against what has already
  /// gone out, and the cap applies to each run. Reminders never tried before
  /// go first; re-offers of failed ones fill whatever room is left. Never
  /// throws, because nobody is waiting on it to report a failure to.
  ///
  /// Returns the outcomes for whatever was actually attempted; a call outside
  /// sending hours or with auto-send off attempts nothing and returns empty.
  Future<List<ReminderOutcome>> runAutoSend({DateTime? now}) {
    if (_autoRun != null) {
      _log.fine('An automatic reminder run is already in progress');
      return Future.value(const []);
    }
    final run = _runAutoSend(now: now);
    _autoRun = run;
    return run.whenComplete(() => _autoRun = null);
  }

  Future<List<ReminderOutcome>> _runAutoSend({DateTime? now}) async {
    final outcomes = <ReminderOutcome>[];
    try {
      final settings = await loadSettings();
      if (!settings.autoSend) return outcomes;

      final at = now ?? DateTime.now();
      if (!withinSendingWindow(at, settings)) return outcomes;

      final queue = await buildQueue(now: at);
      final fresh = queue.where((c) => !c.retry);
      final retries = queue.where((c) => c.retry);
      final batch = [...fresh, ...retries].take(settings.maxPerRun);

      var failedInARow = 0;
      for (final candidate in batch) {
        final outcome = await send(candidate);
        outcomes.add(outcome);

        if (outcome is ReminderNotNeeded) continue;
        failedInARow = outcome is ReminderFailed ? failedInARow + 1 : 0;
        if (failedInARow >= _maxConsecutiveAutoFailures) {
          _log.warning('Automatic reminder run stopped after '
              '$failedInARow failures in a row');
          break;
        }
      }
    } catch (error, stack) {
      _log.severe('The automatic reminder run failed', error, stack);
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
  ///
  /// One upsert rather than a read followed by an insert: two queue builds at
  /// once — the automatic run and the Reminders screen — used to both read
  /// "no row yet" and the second insert then died on the unique key. Which
  /// existing row a write may replace is decided in the same statement:
  ///
  ///  * `sent` always wins. A reminder sent by hand over one already sent is
  ///    the owner's decision, and the row then says when the latest went.
  ///  * `failed` and `skipped` replace only a failure. A failed attempt must
  ///    never turn a reminder that was delivered back into one the queue
  ///    offers again, and a stage superseded or cleared after it went out
  ///    still went out.
  ///
  /// [cycleDueDate] is the cycle's own due date — what a reminder is *about*
  /// — kept distinct from [scheduled]'s own `on` day: the two coincide for a
  /// due-date reminder but not for a before-due nudge or an overdue chase,
  /// and it is [cycleDueDate] that ties every stage for one cycle together so
  /// [_reminderRows] can ask "what has this cycle already had?" in one query.
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
    final sentAt =
        status == ReminderSendStatus.sent ? DateTime.now().toUtc() : null;
    final table = db.paymentReminders;

    await db.into(table).insert(
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
            sentAt: Value(sentAt),
          ),
          onConflict: DoUpdate(
            (old) => switch (status) {
              // A superseded or cleared failure keeps its error and its
              // attempt count: they are the history of what was tried.
              ReminderSendStatus.skipped => PaymentRemindersCompanion.custom(
                  status: Constant(status.name),
                ),
              _ => PaymentRemindersCompanion.custom(
                  status: Constant(status.name),
                  membershipPeriodId: Variable(periodId),
                  amountMinor: Variable(amountDueMinor),
                  externalMessageId: Variable(messageId),
                  errorMessage: Variable(error),
                  attempts: old.attempts + const Constant(1),
                  sentAt: sentAt == null ? null : Variable(sentAt),
                ),
            },
            target: [
              table.memberId,
              table.stage,
              table.offsetDays,
              table.dueDate,
            ],
            where: status == ReminderSendStatus.sent
                ? null
                : ($PaymentRemindersTable old) =>
                    old.status.equalsValue(ReminderSendStatus.failed),
          ),
        );
  }

  /// Every reminder already recorded against the cycle due on [dueDate], and
  /// what became of it.
  Future<Map<ReminderKey, ReminderSendStatus>> _reminderRows({
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
        ): row.status,
    };
  }

  /// The number a reminder goes to, or null when the member has none
  /// WhatsApp could use.
  static String? _recipientFor(Member member) =>
      normalizePhone(member.phoneRaw ?? member.phone) ??
      normalizePhone(member.phone);

  /// Which cycle [billing]'s reminder is about as of [today], and what to ask
  /// for. Null when nothing is owed.
  ///
  /// The newest unpaid cycle that has already started, when there is one —
  /// see the class note on members in arrears — asking for everything owed up
  /// to and including it. A cycle further ahead that happens to be part-paid
  /// is left out of that figure: it is not due yet, and a reminder is about
  /// money that is.
  ///
  /// With nothing started and unpaid, the next cycle to fall due: an unpaid
  /// one already billed ahead of time, or else the one the paid-up run ends
  /// at, which is not billed yet and is quoted at the fee it would be opened
  /// at.
  static _ReminderTarget? _targetFor(MemberBilling billing, DateTime today) {
    SettleableCycle? latestStarted;
    for (final cycle in billing.cycles) {
      if (cycle.isSettled || cycle.start.isAfter(today)) continue;
      latestStarted = cycle;
    }

    final _ReminderTarget target;
    if (latestStarted != null) {
      final upTo = latestStarted.start;
      target = _ReminderTarget(
        dueDate: upTo,
        periodId: latestStarted.periodId,
        amountMinor: billing.cycles
            .where((c) => !c.start.isAfter(upTo))
            .fold(0, (sum, c) => sum + c.outstandingMinor),
      );
    } else {
      final unsettled = billing.nextUnsettled;
      target = _ReminderTarget(
        dueDate: billing.nextDueDate,
        periodId: unsettled?.periodId,
        amountMinor: unsettled?.outstandingMinor ?? billing.feeMinor,
      );
    }

    return target.amountMinor > 0 ? target : null;
  }
}
