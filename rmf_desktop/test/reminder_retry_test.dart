import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/domain/reminder_schedule.dart';
import 'package:rich_man_fitness/services/reminder_service.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

/// A client that records every template send and can be told to fail.
class _Client implements WhatsAppClient {
  bool fails = false;
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
    if (fails) return const WhatsAppSendFailure('network unreachable');
    return WhatsAppSendSuccess('msg-${sent.length}');
  }
}

/// A reminder that could not be sent is offered again.
///
/// It used to vanish: any stored row counted as "handled", failures included,
/// so after "Sent 10, 2 could not be sent" those two members dropped off the
/// Reminders screen and out of every automatic run for good. This is not a
/// retry engine — nothing re-sends on its own schedule — it is the same
/// reminder still being on the list the next time somebody looks, under the
/// same per-run cap as everything else.
void main() {
  late AppDatabase db;
  late _Client client;
  late ReminderService service;
  late int planId;
  late int memberId;
  const fee = 300000;

  Future<int> addMember(int code, String phone, DateTime joined) async {
    final id = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: code,
          fullName: 'Member $code',
          phone: phone,
          joiningDate: joined,
        ));
    await db.into(db.memberships).insert(MembershipsCompanion.insert(
          memberId: id,
          planId: planId,
          startDate: joined,
        ));
    return id;
  }

  Future<PaymentReminder> rowFor(int member, ReminderStage stage) =>
      (db.select(db.paymentReminders)
            ..where((r) =>
                r.memberId.equals(member) & r.stage.equals(stage.name)))
          .getSingle();

  Future<void> turnOnAutoSend({int maxPerRun = 25}) =>
      (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
          GymSettingsCompanion(
              reminderAutoSend: const Value(true),
              reminderMaxPerRun: Value(maxPerRun)));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = _Client();
    service = ReminderService(db: db, clientFactory: () async => client);

    await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(GymSettingsCompanion.insert(
          whatsappReminderTemplate: const Value('payment_reminder'),
        ));
    planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: fee));
    memberId = await addMember(1, '+923000000022', DateTime.utc(2026, 8, 6));
  });

  tearDown(() => db.close());

  test('a reminder that failed to send is offered again, not silently dropped',
      () async {
    client.fails = true;
    final first = await service.buildQueue(now: DateTime.utc(2026, 8, 6, 6));
    expect(first, hasLength(1));
    expect(await service.send(first.single), isA<ReminderFailed>());

    // Network is back an hour later; the owner reopens Reminders.
    client.fails = false;
    final again = await service.buildQueue(now: DateTime.utc(2026, 8, 6, 7));
    expect(again, hasLength(1),
        reason: 'the failed on-due reminder must still be actionable; it was '
            'never delivered');
  });

  test('the re-offered reminder says it failed before, and sending it '
      'updates the same row', () async {
    client.fails = true;
    final first = await service.buildQueue(now: DateTime.utc(2026, 8, 6));
    expect(first.single.retry, isFalse);
    await service.send(first.single);

    client.fails = false;
    final again = await service.buildQueue(now: DateTime.utc(2026, 8, 6));
    expect(again.single.retry, isTrue);
    expect(await service.send(again.single), isA<ReminderSent>());

    final row = await rowFor(memberId, ReminderStage.onDue);
    expect(row.status, ReminderSendStatus.sent);
    expect(row.attempts, 2);
    expect(await service.buildQueue(now: DateTime.utc(2026, 8, 6)), isEmpty,
        reason: 'delivered now, so it is handled like any sent reminder');
  });

  test('a member with no usable number is not re-offered until the number '
      'is corrected', () async {
    await (db.update(db.members)..where((m) => m.id.equals(memberId)))
        .write(const MembersCompanion(phone: Value('12')));

    final first = await service.buildQueue(now: DateTime.utc(2026, 8, 6));
    expect(first, hasLength(1),
        reason: 'offered once, so the owner learns the number is unusable');
    final outcome = await service.send(first.single);
    expect(outcome, isA<ReminderFailed>());
    expect(client.sent, isEmpty);

    expect(await service.buildQueue(now: DateTime.utc(2026, 8, 6)), isEmpty,
        reason: 'retrying cannot fix a number that is not a number');

    await (db.update(db.members)..where((m) => m.id.equals(memberId)))
        .write(const MembersCompanion(phone: Value('+923000000022')));
    expect(await service.buildQueue(now: DateTime.utc(2026, 8, 6)),
        hasLength(1),
        reason: 'with a real number it is worth sending after all');
  });

  test('a failure overtaken by a later stage is recorded skipped, never sent '
      'late', () async {
    client.fails = true;
    final onDue = await service.buildQueue(now: DateTime.utc(2026, 8, 6));
    await service.send(onDue.single);

    client.fails = false;
    final later = await service.buildQueue(now: DateTime.utc(2026, 8, 9));
    expect(later.single.stage, ReminderStage.overdue);
    expect(later.single.offsetDays, 3);

    final row = await rowFor(memberId, ReminderStage.onDue);
    expect(row.status, ReminderSendStatus.skipped);
    expect(row.errorMessage, 'network unreachable',
        reason: 'the history of what was tried is kept');
  });

  test('a failed attempt never turns a delivered reminder back into one the '
      'queue offers', () async {
    final at = DateTime.utc(2026, 8, 13);
    final byHand = await service.candidateForMember(memberId, now: at);
    expect(await service.send(byHand!), isA<ReminderSent>());

    // The owner presses the member's button again and this time it fails.
    client.fails = true;
    final again = await service.candidateForMember(memberId, now: at);
    expect(await service.send(again!), isA<ReminderFailed>());

    final row = await (db.select(db.paymentReminders)
          ..where((r) =>
              r.stage.equals(ReminderStage.overdue.name) &
              r.offsetDays.equals(7)))
        .getSingle();
    expect(row.status, ReminderSendStatus.sent);

    client.fails = false;
    client.sent.clear();
    final queue = await service.buildQueue(now: at);
    expect(queue, isEmpty);
  });

  group('in an automatic run', () {
    test('never-tried reminders go before re-offers of failed ones',
        () async {
      // Member 1 fails on the 6th; member 2 is due on the 7th. Oldest due
      // date first would put the failure at the head of a one-message run
      // every time, and member 2 would never be reached.
      client.fails = true;
      await service.send(
          (await service.buildQueue(now: DateTime.utc(2026, 8, 6))).single);
      client.fails = false;
      client.sent.clear();

      await addMember(2, '+923000000033', DateTime.utc(2026, 8, 7));
      await turnOnAutoSend(maxPerRun: 1);

      final outcomes =
          await service.runAutoSend(now: DateTime.utc(2026, 8, 7, 12));
      expect(outcomes.single, isA<ReminderSent>());
      expect(client.sent.single.to, '+923000000033');
    });

    test('stops after three failures in a row rather than burning the whole '
        'cap on a broken connection', () async {
      for (var i = 2; i <= 6; i++) {
        await addMember(i, '+92300000${1000 + i}', DateTime.utc(2026, 8, 6));
      }
      await turnOnAutoSend();
      client.fails = true;

      final outcomes =
          await service.runAutoSend(now: DateTime.utc(2026, 8, 6, 12));
      expect(outcomes, hasLength(3));
      expect(client.sent, hasLength(3));

      // What was not attempted is simply still due on the next run.
      client.fails = false;
      final next = await service.runAutoSend(now: DateTime.utc(2026, 8, 6, 13));
      expect(next.whereType<ReminderSent>(), hasLength(6));
    });
  });
}
