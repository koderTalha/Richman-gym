import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/domain/reminder_schedule.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/reminder_service.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// A client that records every template send.
class _RecordingClient implements WhatsAppClient {
  final sent = <WhatsAppTemplateInput>[];

  @override
  WhatsAppProviderKind get kind => WhatsAppProviderKind.mock;

  @override
  Future<WhatsAppSendResult> send(WhatsAppSendInput input) async =>
      const WhatsAppSendFailure('not used');

  @override
  Future<WhatsAppSendResult> sendText(WhatsAppTextInput input) async =>
      const WhatsAppSendFailure('not used');

  @override
  Future<WhatsAppSendResult> sendTemplate(WhatsAppTemplateInput input) async {
    sent.add(input);
    return WhatsAppSendSuccess('msg-${sent.length}');
  }
}

/// Clearing the queue without messaging anybody, and nudging one member by
/// hand.
///
/// Two things the Reminders screen could not do. Clearing is for a queue the
/// owner has already dealt with in person — the members were caught at the
/// counter, or chased on the phone — and sending them a template anyway is
/// both a cost and a nuisance. Sending by hand is for the owner who turns the
/// automatic run off entirely and would rather decide member by member; with
/// auto-send off there is no queue at all, so the button on the member's own
/// screen is the only way in.
///
/// Whether that button appears is the screen's decision, taken from the same
/// status its badge shows — see [MemberStatusOwing]. Everything else here is
/// about what happens once it is pressed.
void main() {
  late AppDatabase db;
  late ReminderService service;
  late _RecordingClient client;
  late int memberId;
  late int ownerId;

  const monthlyFee = 300000;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = _RecordingClient();
    service = ReminderService(db: db, clientFactory: () async => client);

    ownerId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(GymSettingsCompanion.insert(
          whatsappReminderTemplate: const Value('payment_reminder'),
        ));

    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: monthlyFee));

    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ali Raza',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 9, 6),
        ));

    await db.into(db.memberships).insert(MembershipsCompanion.insert(
          memberId: memberId,
          planId: planId,
          startDate: DateTime.utc(2026, 9, 6),
        ));
  });

  tearDown(() => db.close());

  /// A day the member is plainly overdue.
  final overdueOn = DateTime.utc(2026, 9, 13);

  group('clearing a reminder', () {
    test('takes it out of the queue', () async {
      final queue = await service.buildQueue(now: overdueOn);
      expect(queue, hasLength(1), reason: 'the fixture is due');

      await service.dismiss(queue.single, actorId: ownerId);

      expect(await service.buildQueue(now: overdueOn), isEmpty);
    });

    test('sends nothing', () async {
      final queue = await service.buildQueue(now: overdueOn);

      await service.dismiss(queue.single, actorId: ownerId);

      expect(client.sent, isEmpty);
    });

    test('is written down as skipped, not as sent', () async {
      final queue = await service.buildQueue(now: overdueOn);
      final candidate = queue.single;

      await service.dismiss(candidate, actorId: ownerId);

      // Specifically this reminder: `buildQueue` records superseded stages as
      // skipped on its own, so merely finding a skipped row proves nothing.
      final rows = await db.select(db.paymentReminders).get();
      final own = rows.where((r) =>
          r.stage == candidate.stage.name &&
          r.offsetDays == candidate.offsetDays &&
          r.dueDate.toUtc() == candidate.dueDate);

      expect(own, hasLength(1));
      expect(own.single.status, ReminderSendStatus.skipped);
      expect(rows.where((r) => r.status == ReminderSendStatus.sent), isEmpty);
    });

    test('says in the log who cleared it', () async {
      final queue = await service.buildQueue(now: overdueOn);

      await service.dismiss(queue.single, actorId: ownerId);

      final events = await db.select(db.auditEvents).get();
      expect(events.map((e) => e.action), contains('reminder.skipped'));
    });

    test('does not stop the member being reminded next month', () async {
      final queue = await service.buildQueue(now: overdueOn);
      await service.dismiss(queue.single, actorId: ownerId);
      expect(await service.buildQueue(now: overdueOn), isEmpty);

      // Clearing settles one reminder, not the member. Once the next cycle has
      // opened it is a new due date, and so a reminder of its own.
      final nextMonth = DateTime.utc(2026, 10, 13);
      await BillingMaintenance(db).ensureCurrentPeriods(now: nextMonth);

      expect(await service.buildQueue(now: nextMonth), hasLength(1));
    });
  });

  group('the reminder for one member', () {
    test('is offered while they owe money', () async {
      final candidate =
          await service.candidateForMember(memberId, now: overdueOn);

      expect(candidate, isNotNull);
      expect(candidate!.member.id, memberId);
      expect(candidate.amountDueMinor, monthlyFee);
      expect(candidate.stage, ReminderStage.overdue);
    });

    test('is not offered to a member on no plan at all', () async {
      final noPlan = await db.into(db.members).insert(MembersCompanion.insert(
            memberCode: 2,
            fullName: 'Never Enrolled',
            phone: '+923000000099',
            joiningDate: DateTime.utc(2026, 9, 6),
          ));

      expect(await service.candidateForMember(noPlan, now: overdueOn), isNull);
    });

    test('is offered with automatic reminders switched off entirely',
        () async {
      await (db.update(db.gymSettings)..where((s) => s.id.equals(1)))
          .write(const GymSettingsCompanion(
        reminderAutoSend: Value(false),
        reminderDaysBefore: Value(''),
        reminderOnDueDate: Value(false),
        reminderDaysAfter: Value(''),
      ));

      expect(await service.buildQueue(now: overdueOn), isEmpty,
          reason: 'nothing is scheduled, so the queue is empty');
      expect(await service.candidateForMember(memberId, now: overdueOn),
          isNotNull,
          reason: 'the owner sending by hand does not need a schedule');
    });

    test('is offered again after one has already gone out', () async {
      final first = await service.candidateForMember(memberId, now: overdueOn);
      await service.send(first!, actorId: ownerId);

      expect(await service.candidateForMember(memberId, now: overdueOn),
          isNotNull,
          reason: 'the owner decides when to chase again, not the schedule');
    });

    test('goes out like any other reminder when sent', () async {
      final candidate =
          await service.candidateForMember(memberId, now: overdueOn);

      final outcome = await service.send(candidate!, actorId: ownerId);

      expect(outcome, isA<ReminderSent>());
      expect(client.sent, hasLength(1));
      expect(client.sent.single.to, '+923000000022');

      final events = await db.select(db.auditEvents).get();
      expect(events.map((e) => e.action), contains('reminder.sent'));
    });

    test('is not offered for a member who has left', () async {
      await (db.update(db.members)..where((m) => m.id.equals(memberId)))
          .write(MembersCompanion(
              deactivatedAt: Value(DateTime.utc(2026, 8, 1))));

      expect(
          await service.candidateForMember(memberId, now: overdueOn), isNull);
    });

    test('calls it an upcoming reminder before the due date', () async {
      final candidate = await service.candidateForMember(
        memberId,
        now: DateTime.utc(2026, 9, 4),
      );

      expect(candidate!.stage, ReminderStage.beforeDue);
      expect(candidate.offsetDays, 2);
    });

    test('calls it due on the day itself', () async {
      final candidate = await service.candidateForMember(
        memberId,
        now: DateTime.utc(2026, 9, 6),
      );

      expect(candidate!.stage, ReminderStage.onDue);
      expect(candidate.offsetDays, 0);
    });
  });

  group('whether the button is offered at all', () {
    test('it is, for the two states that mean money is owed', () {
      expect(MemberStatus.due.isOwing, isTrue);
      expect(MemberStatus.expired.isOwing, isTrue);
    });

    test('it is not, for a member who is paid up or has left', () {
      expect(MemberStatus.paid.isOwing, isFalse);
      expect(MemberStatus.inactive.isOwing, isFalse);
    });
  });
}
