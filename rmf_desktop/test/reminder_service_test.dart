import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/domain/reminder_schedule.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/reminder_service.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// A client that records every template send and can be told to fail.
class _RecordingClient implements WhatsAppClient {
  _RecordingClient({this.fails = false});
  final bool fails;
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
    if (fails) return const WhatsAppSendFailure('simulated failure');
    return WhatsAppSendSuccess('msg-${sent.length}');
  }
}

/// The reminder detection, sending and duplicate-guard behaviour — the
/// automated half of the feature: detect upcoming dues, detect overdue
/// members, and send without ever double-messaging one.
void main() {
  late AppDatabase db;
  late ReminderService service;
  late _RecordingClient client;
  late int memberId;

  const monthlyFee = 300000;

  Future<void> setReminderSettings(GymSettingsCompanion changes) async {
    await (db.update(db.gymSettings)..where((s) => s.id.equals(1)))
        .write(changes);
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = _RecordingClient();
    service = ReminderService(db: db, clientFactory: () async => client);

    await db.into(db.users).insert(UsersCompanion.insert(
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

  group('buildQueue', () {
    test('offers nothing well before the due date', () async {
      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 1));
      expect(queue, isEmpty);
    });

    test('detects an upcoming due date ahead of time', () async {
      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 3));

      expect(queue, hasLength(1));
      expect(queue.single.member.id, memberId);
      expect(queue.single.stage, ReminderStage.beforeDue);
      expect(queue.single.dueDate, DateTime.utc(2026, 9, 6));
      expect(queue.single.amountDueMinor, monthlyFee,
          reason: 'nothing has been billed yet, so the full fee is quoted');
      expect(queue.single.periodId, isNull,
          reason: 'a projected cycle is not materialised just to be nudged');
    });

    test('detects an overdue member', () async {
      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 13));

      expect(queue.single.stage, ReminderStage.overdue);
      expect(queue.single.offsetDays, 7);
    });

    test('excludes a deactivated member', () async {
      await (db.update(db.members)..where((m) => m.id.equals(memberId)))
          .write(MembersCompanion(deactivatedAt: Value(DateTime.utc(2026, 8, 1))));

      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 13));
      expect(queue, isEmpty);
    });

    test('offers nothing once every configured stage has fired', () async {
      await setReminderSettings(const GymSettingsCompanion(
        reminderDaysBefore: Value(''),
        reminderOnDueDate: Value(false),
        reminderDaysAfter: Value(''),
      ));

      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 13));
      expect(queue, isEmpty);
    });

    test('a settled cycle is not chased', () async {
      final cycles = BillingCycleService(db);
      final billing = await cycles.forMember(memberId);
      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: monthlyFee);
      final period = await cycles.materialise(
          membershipId: billing.membership.id, cycle: offered.single);

      final paymentId = await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              memberId: memberId,
              membershipPeriodId: Value(period.id),
              amountMinor: monthlyFee,
              method: PaymentMethod.cash,
              paymentDate: DateTime.utc(2026, 9, 6),
              recordedById: 1,
              idempotencyKey: 'pay-1',
            ),
          );
      await db.into(db.paymentAllocations).insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              membershipPeriodId: period.id,
              amountMinor: monthlyFee,
            ),
          );
      await cycles.refreshSettlement(period.id);

      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 13));
      expect(queue, isEmpty);
    });

    test('quotes the outstanding balance for a partly paid cycle', () async {
      final cycles = BillingCycleService(db);
      final billing = await cycles.forMember(memberId);
      final offered =
          cycles.settleableFor(billing: billing!, amountMinor: monthlyFee);
      final period = await cycles.materialise(
          membershipId: billing.membership.id, cycle: offered.single);

      final paymentId = await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              memberId: memberId,
              membershipPeriodId: Value(period.id),
              amountMinor: 100000,
              method: PaymentMethod.cash,
              paymentDate: DateTime.utc(2026, 9, 6),
              recordedById: 1,
              idempotencyKey: 'pay-1',
            ),
          );
      await db.into(db.paymentAllocations).insert(
            PaymentAllocationsCompanion.insert(
              paymentId: paymentId,
              membershipPeriodId: period.id,
              amountMinor: 100000,
            ),
          );
      await cycles.refreshSettlement(period.id);

      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 13));
      expect(queue.single.amountDueMinor, 200000);
      expect(queue.single.periodId, period.id);
    });

    test('a reopened app skips stale stages and offers only the latest',
        () async {
      // Nothing sent while the app was closed from 3 Sep to 13 Sep — every
      // stage in between must be marked skipped, not queued.
      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 13));
      expect(queue, hasLength(1));
      expect(queue.single.stage, ReminderStage.overdue);

      final rows = await db.select(db.paymentReminders).get();
      final skipped = rows.where((r) => r.status == ReminderSendStatus.skipped);
      // Every stage that came due before the 7-day-overdue chase — the
      // before-due nudge, the on-the-day reminder and the 3-day chase — is
      // superseded by it, and only it goes out.
      expect(skipped, hasLength(3));
    });

    test('does not re-offer a reminder already queued on an earlier call',
        () async {
      final first = await service.buildQueue(now: DateTime.utc(2026, 9, 3));
      await service.send(first.single);

      final second = await service.buildQueue(now: DateTime.utc(2026, 9, 3));
      expect(second, isEmpty);
    });
  });

  group('send', () {
    test('sends the template with the right parameters', () async {
      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 6));
      final outcome = await service.send(queue.single);

      expect(outcome, isA<ReminderSent>());
      expect(client.sent.single.templateName, 'payment_reminder');
      expect(client.sent.single.bodyParams[0], 'Ali Raza');
      expect(client.sent.single.to, '+923000000022');
    });

    test('records the send so it is never repeated', () async {
      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 6));
      await service.send(queue.single);

      // buildQueue itself also recorded the superseded before-due nudge, so
      // two rows exist; only the one this test is about is asserted on.
      final row = await (db.select(db.paymentReminders)
            ..where((r) => r.stage.equals('onDue')))
          .getSingle();
      expect(row.status, ReminderSendStatus.sent);

      final again = await service.buildQueue(now: DateTime.utc(2026, 9, 6));
      expect(again, isEmpty);
    });

    test('a failed send is recorded and can be retried', () async {
      client = _RecordingClient(fails: true);
      service = ReminderService(db: db, clientFactory: () async => client);

      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 6));
      final outcome = await service.send(queue.single);
      expect(outcome, isA<ReminderFailed>());

      Future<PaymentReminder> onDueRow() => (db.select(db.paymentReminders)
            ..where((r) => r.stage.equals('onDue')))
          .getSingle();

      final row = await onDueRow();
      expect(row.status, ReminderSendStatus.failed);
      expect(row.attempts, 1);

      client = _RecordingClient();
      service = ReminderService(db: db, clientFactory: () async => client);
      await service.send(queue.single);

      final retried = await onDueRow();
      expect(retried.status, ReminderSendStatus.sent);
      expect(retried.attempts, 2);
    });

    test('refuses to send with no template configured', () async {
      await setReminderSettings(
          const GymSettingsCompanion(whatsappReminderTemplate: Value(null)));

      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 6));
      final outcome = await service.send(queue.single);

      expect(outcome, isA<ReminderFailed>());
      expect(client.sent, isEmpty);
    });

    test('writes an audit event for a sent reminder', () async {
      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 6));
      await service.send(queue.single, actorId: 1);

      final event = await db.select(db.auditEvents).getSingle();
      expect(event.action, 'reminder.sent');
      expect(event.memberId, memberId);
    });
  });

  group('runAutoSend', () {
    test('sends nothing when auto-send is off', () async {
      final outcomes = await service.runAutoSend(now: DateTime.utc(2026, 9, 6, 12));
      expect(outcomes, isEmpty);
      expect(client.sent, isEmpty);
    });

    test('sends when auto-send is on and inside the gym\'s hours', () async {
      await setReminderSettings(const GymSettingsCompanion(
        reminderAutoSend: Value(true),
        reminderSendFromHour: Value(9),
        reminderSendUntilHour: Value(21),
      ));

      final outcomes =
          await service.runAutoSend(now: DateTime.utc(2026, 9, 6, 12));
      expect(outcomes, hasLength(1));
      expect(client.sent, hasLength(1));
    });

    test('sends nothing outside the gym\'s own hours', () async {
      await setReminderSettings(const GymSettingsCompanion(
        reminderAutoSend: Value(true),
        reminderSendFromHour: Value(9),
        reminderSendUntilHour: Value(21),
      ));

      final outcomes =
          await service.runAutoSend(now: DateTime.utc(2026, 9, 6, 6, 30));
      expect(outcomes, isEmpty);
      expect(client.sent, isEmpty);
    });

    test('never sends more than the configured cap in one run', () async {
      // A second, third and fourth member, all overdue at once.
      for (var i = 2; i <= 4; i++) {
        final planId = (await db.select(db.membershipPlans).getSingle()).id;
        final id = await db.into(db.members).insert(MembersCompanion.insert(
              memberCode: i,
              fullName: 'Member $i',
              phone: '+92300000${1000 + i}',
              joiningDate: DateTime.utc(2026, 9, 6),
            ));
        await db.into(db.memberships).insert(MembershipsCompanion.insert(
              memberId: id,
              planId: planId,
              startDate: DateTime.utc(2026, 9, 6),
            ));
      }

      await setReminderSettings(const GymSettingsCompanion(
        reminderAutoSend: Value(true),
        reminderMaxPerRun: Value(2),
      ));

      final outcomes =
          await service.runAutoSend(now: DateTime.utc(2026, 9, 13, 12));
      expect(outcomes, hasLength(2));
      expect(client.sent, hasLength(2));
    });
  });
}
