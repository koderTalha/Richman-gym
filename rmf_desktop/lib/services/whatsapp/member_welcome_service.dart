import 'package:logging/logging.dart';

import '../../data/audit_repository.dart';
import '../../data/database.dart';
import '../../data/membership_queries.dart';
import '../../domain/billing_cycle.dart';
import '../../domain/phone.dart';
import 'message_texts.dart';
import 'whatsapp_client.dart';

final _log = Logger('whatsapp');

sealed class WelcomeOutcome {
  const WelcomeOutcome();
}

class WelcomeSent extends WelcomeOutcome {
  const WelcomeSent(this.messageId);
  final String messageId;
}

/// Nothing was sent and nothing is wrong — the member already has their
/// welcome message, or one is being sent right now by the call before this one.
class WelcomeSkipped extends WelcomeOutcome {
  const WelcomeSkipped(this.reason);
  final String reason;
}

/// The member exists; the message did not go out.
class WelcomeFailed extends WelcomeOutcome {
  const WelcomeFailed(this.error);
  final String error;
}

/// Sends a new member their one welcome message.
///
/// Three rules shape this class:
///
///  1. **It runs after the member is committed, never inside the write.** A
///     member the gym has taken details for exists whether or not Meta is
///     reachable; rolling one back over a messaging failure would be the wrong
///     way round. This mirrors how a receipt is sent after the payment
///     transaction commits — see RecordPaymentService.
///  2. **It never throws.** Every failure comes back as [WelcomeFailed] and is
///     recorded, so a broken token cannot take the Add Member screen down with
///     it.
///  3. **Exactly one message per member, ever.** The audit log is the durable
///     record of that, and an in-process guard covers the window before the
///     first one has been written — which is what a double-clicked Save, a
///     rebuilt widget or a retried event would otherwise walk straight into.
class MemberWelcomeService {
  MemberWelcomeService({
    required this.db,
    required this.clientFactory,
    AuditRepository? audit,
  }) : _audit = audit ?? AuditRepository(db);

  final AppDatabase db;

  /// Resolved per send, so a provider or credential change in Settings takes
  /// effect without a restart. Same factory the payment flow uses.
  final Future<WhatsAppClient> Function() clientFactory;

  final AuditRepository _audit;

  /// Members with a send in flight in this process. The audit row is only
  /// written once the provider has answered, and two submits half a second
  /// apart would both read "not sent yet" without this.
  final Set<int> _inFlight = <int>{};

  Future<WelcomeOutcome> sendWelcome({
    required int memberId,
    int? actorId,
  }) async {
    if (_inFlight.contains(memberId)) {
      _log.info('Welcome message for member $memberId is already being sent');
      return const WelcomeSkipped('A welcome message is already being sent.');
    }
    _inFlight.add(memberId);

    try {
      return await _send(memberId: memberId, actorId: actorId);
    } catch (error, stack) {
      // Belt and braces. Nothing below is meant to throw, and a member who has
      // been saved must not be reported as a failure because of something that
      // happened after they were.
      _log.severe('Sending the welcome message failed unexpectedly',
          error, stack);
      return WelcomeFailed('$error');
    } finally {
      _inFlight.remove(memberId);
    }
  }

  Future<WelcomeOutcome> _send({
    required int memberId,
    required int? actorId,
  }) async {
    final member = await (db.select(db.members)
          ..where((m) => m.id.equals(memberId)))
        .getSingleOrNull();

    if (member == null) {
      _log.warning('No welcome message sent: member $memberId does not exist');
      return const WelcomeFailed('That member no longer exists.');
    }

    final already = await _audit.hasSucceededFor(
      action: AuditAction.whatsAppWelcomeSent,
      memberId: memberId,
    );
    if (already) {
      _log.info('${member.fullName} already has a welcome message; '
          'not sending another');
      return const WelcomeSkipped(
          'This member has already been sent a welcome message.');
    }

    // Normalized again here rather than trusted from the row: the form does it
    // on the way in, but an imported or hand-edited row may hold anything, and
    // Meta needs E.164.
    final to = normalizePhone(member.phoneRaw ?? member.phone) ??
        normalizePhone(member.phone);
    if (to == null) {
      return _recordFailure(
        member: member,
        actorId: actorId,
        phone: member.phone,
        error: 'The number on this member is not usable for WhatsApp.',
      );
    }

    final WhatsAppClient client;
    try {
      client = await clientFactory();
    } catch (error, stack) {
      // StateError from an unconfigured Meta provider lands here. The message
      // names which field is missing and carries no credential.
      _log.severe('WhatsApp client could not be built', error, stack);
      return _recordFailure(
        member: member,
        actorId: actorId,
        phone: to,
        error: '$error',
      );
    }

    final settings =
        await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
            .getSingle();

    final template = settings.whatsappWelcomeTemplate;
    final result = (template == null || template.trim().isEmpty)
        // No template registered yet: the free-text message this app has
        // always sent. Meta only delivers this inside the 24-hour window a
        // member's own message opens, which a brand new member has almost
        // never done — see the template branch below for the fix.
        ? await client.sendText(WhatsAppTextInput(
            to: to,
            body: welcomeMessage(
              gymName: settings.gymName,
              memberName: member.fullName,
              memberCode: member.memberCode,
            ),
          ))
        : await _sendViaTemplate(
            client: client,
            to: to,
            template: template,
            language: settings.whatsappWelcomeTemplateLanguage,
            member: member,
          );

    switch (result) {
      case WhatsAppSendSuccess(:final externalMessageId):
        await _audit.record(
          category: AuditCategory.whatsapp,
          action: AuditAction.whatsAppWelcomeSent,
          outcome: AuditOutcome.success,
          actorId: actorId,
          memberId: member.id,
          memberName: member.fullName,
          summary: 'Welcome message sent to ${member.fullName} '
              '(${maskPhone(to)})',
          detail: [
            'Provider: ${client.kind.name}',
            'Message id: $externalMessageId',
          ],
        );
        return WelcomeSent(externalMessageId);

      case WhatsAppSendFailure(:final error):
        return _recordFailure(
          member: member,
          actorId: actorId,
          phone: to,
          error: error,
          provider: client.kind,
        );
    }
  }

  /// Sends the welcome message as the gym's registered template.
  ///
  /// Templates are not subject to the 24-hour customer-service window free
  /// text is, which is the entire reason this branch exists — a member who
  /// has just been added has essentially never messaged the gym's WhatsApp
  /// number first, so free text would otherwise be accepted by Meta and then
  /// silently fail to arrive. See [GymSettings.whatsappWelcomeTemplate].
  ///
  /// A member without an active plan cannot be given a "valid until" date, so
  /// that case comes back as a plain [WhatsAppSendFailure] — the same
  /// sealed-result contract the caller already switches on — rather than an
  /// exception.
  Future<WhatsAppSendResult> _sendViaTemplate({
    required WhatsAppClient client,
    required String to,
    required String template,
    required String language,
    required Member member,
  }) async {
    final membership = await openMembershipFor(db, member.id);
    if (membership == null) {
      return const WhatsAppSendFailure(
          'This member has no active plan yet, so a welcome template — '
          'which must say when the membership is valid until — cannot be '
          'filled in.');
    }

    final plan = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(membership.planId)))
        .getSingleOrNull();
    if (plan == null) {
      return const WhatsAppSendFailure(
          'This member\'s plan no longer exists.');
    }

    // The end of the very first cycle: a brand new member has no
    // MembershipPeriods yet, so this is computed the same way
    // `MemberBilling.nextBoundary` computes it for that same "no history yet"
    // case — see `BillingCycleService.forMember`.
    final firstCycle = firstCycleFor(
      joiningDate: member.joiningDate,
      durationMonths: plan.durationMonths,
      anchorDay: membership.billingAnchorDay,
    );
    // `end` is the exclusive start of the *next* cycle, so the last day this
    // membership actually covers is the day before it.
    final validUntil = firstCycle.end.subtract(const Duration(days: 1));

    return client.sendTemplate(WhatsAppTemplateInput(
      to: to,
      templateName: template,
      languageCode: language,
      bodyParams: welcomeTemplateParams(
        memberName: member.fullName,
        memberCode: member.memberCode,
        planName: plan.name,
        validUntil: validUntil,
      ),
    ));
  }

  /// Records the failure and hands it back.
  ///
  /// Only the last four digits of the number reach the log, and the detail
  /// lines carry the provider's own message — never a token, a header or a raw
  /// response body.
  Future<WelcomeOutcome> _recordFailure({
    required Member member,
    required int? actorId,
    required String phone,
    required String error,
    WhatsAppProviderKind? provider,
  }) async {
    await _audit.record(
      category: AuditCategory.whatsapp,
      action: AuditAction.whatsAppWelcomeFailed,
      outcome: AuditOutcome.failed,
      actorId: actorId,
      memberId: member.id,
      memberName: member.fullName,
      summary: 'Welcome message to ${member.fullName} '
          '(${maskPhone(phone)}) could not be sent',
      detail: [
        if (provider != null) 'Provider: ${provider.name}',
        error,
        '${member.fullName} was added successfully; only the message failed.',
      ],
    );
    return WelcomeFailed(error);
  }
}
