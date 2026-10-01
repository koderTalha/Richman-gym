import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/domain/reminder_schedule.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/reminder_service.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

class _Client implements WhatsAppClient {
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

/// A member who stays unpaid into a second cycle.
///
/// Reminders used to be keyed by the *oldest* unpaid cycle. Once its stages
/// had fired, the next cycle never got a reminder of its own, so the members
/// furthest behind were the ones who stopped being chased — and a manual
/// reminder asked for one month's fee when two were owed.
void main() {
  late AppDatabase db;
  late _Client client;
  late ReminderService service;
  late int memberId;
  const fee = 300000;

  Future<void> sendWhateverIsDue(DateTime at) async {
    for (final c in await service.buildQueue(now: at)) {
      await service.send(c);
    }
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = _Client();
    service = ReminderService(db: db, clientFactory: () async => client);

    await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(GymSettingsCompanion.insert(
          whatsappReminderTemplate: const Value('payment_reminder'),
        ));
    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: fee));
    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ali Raza',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 8, 6),
        ));
    await db.into(db.memberships).insert(MembershipsCompanion.insert(
          memberId: memberId,
          planId: planId,
          startDate: DateTime.utc(2026, 8, 6),
        ));

    final maintenance = BillingMaintenance(db);
    await maintenance.ensureCurrentPeriods(now: DateTime.utc(2026, 8, 6));
    // August's stages all go out as scheduled.
    for (final day in [3, 6, 9, 13]) {
      await sendWhateverIsDue(DateTime.utc(2026, 8, day, 7));
    }
  });

  tearDown(() => db.close());

  test('one cycle behind, the reminder is still about that cycle', () async {
    // Before September has been billed: nothing about this changes.
    final c = await service.candidateForMember(memberId,
        now: DateTime.utc(2026, 8, 20));
    expect(c!.dueDate, DateTime.utc(2026, 8, 6));
    expect(c.amountDueMinor, fee);
  });

  group('once September is billed with August still unpaid', () {
    setUp(() async {
      await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 9, 6));
      final billing = await BillingCycleService(db).forMember(memberId);
      expect(billing!.cycles.where((c) => !c.isSettled), hasLength(2));
      client.sent.clear();
    });

    test('is still chased once September falls due', () async {
      for (final day in [3, 6, 9, 13]) {
        await sendWhateverIsDue(DateTime.utc(2026, 9, day, 7));
      }
      expect(client.sent, isNotEmpty,
          reason: 'the member owes two months and has had no reminder since '
              '13 August');
    });

    test('every September stage goes out, as August\'s did', () async {
      for (final day in [6, 9, 13]) {
        await sendWhateverIsDue(DateTime.utc(2026, 9, day, 7));
      }
      expect(client.sent, hasLength(3));
    });

    test('a manual reminder quotes everything owed, not one month', () async {
      final c = await service.candidateForMember(memberId,
          now: DateTime.utc(2026, 9, 13, 7));
      expect(c!.amountDueMinor, 2 * fee);
    });

    test('the scheduled reminder is keyed by September and quotes both '
        'months', () async {
      final queue = await service.buildQueue(now: DateTime.utc(2026, 9, 6));
      final billing = await BillingCycleService(db).forMember(memberId);

      expect(queue.single.stage, ReminderStage.onDue);
      expect(queue.single.dueDate, DateTime.utc(2026, 9, 6));
      expect(queue.single.amountDueMinor, 2 * fee);
      expect(queue.single.periodId, billing!.cycles.last.periodId);

      await service.send(queue.single);
      expect(client.sent.single.bodyParams[1], contains('6,000'));
    });
  });
}
