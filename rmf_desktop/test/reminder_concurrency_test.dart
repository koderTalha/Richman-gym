import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/reminder_service.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

class _Client implements WhatsAppClient {
  /// When set, every template send waits on it — a slow network.
  Completer<void>? gate;
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
    if (gate != null) await gate!.future;
    return WhatsAppSendSuccess('msg-${sent.length}');
  }
}

/// The automatic run and the Reminders screen working on the same members at
/// the same time.
///
/// Both send through one `ReminderService`, and the row that stops a reminder
/// going twice used to be written only after the provider answered — so the
/// owner pressing Send during the automatic run sent the same paid template
/// twice, a member who paid mid-run was still chased for the old amount, and
/// two queue builds at once crashed on the unique key and left the screen's
/// spinner turning for good.
void main() {
  late AppDatabase db;
  late _Client client;
  late ReminderService service;
  late int memberId;
  const fee = 300000;

  /// Hour 12 on whatever clock the test passes: inside the 9–21 window.
  final at = DateTime.utc(2026, 8, 6, 12);

  Future<void> turnOnAutoSend() =>
      (db.update(db.gymSettings)..where((s) => s.id.equals(1))).write(
          const GymSettingsCompanion(reminderAutoSend: Value(true)));

  /// Records [amount] against the member's first cycle, opening it if needed.
  Future<void> pay(int amount) async {
    final cycles = BillingCycleService(db);
    final billing = await cycles.forMember(memberId);
    final offered = cycles.settleableFor(billing: billing!, amountMinor: fee);
    final period = offered.first.periodId != null
        ? offered.first.periodId!
        : (await cycles.materialise(
                membershipId: billing.membership.id, cycle: offered.first))
            .id;
    final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            membershipPeriodId: Value(period),
            amountMinor: amount,
            method: PaymentMethod.cash,
            paymentDate: DateTime.utc(2026, 8, 6),
            recordedById: 1,
            idempotencyKey: 'pay-$amount',
          ),
        );
    await db.into(db.paymentAllocations).insert(
          PaymentAllocationsCompanion.insert(
            paymentId: paymentId,
            membershipPeriodId: period,
            amountMinor: amount,
          ),
        );
    await cycles.refreshSettlement(period);
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
  });

  tearDown(() => db.close());

  test('a reminder already being sent by the automatic run is not offered '
      'again by the Reminders screen', () async {
    await turnOnAutoSend();

    client.gate = Completer<void>();
    final autoRun = service.runAutoSend(now: at);
    // Let the auto run reach the network call.
    while (client.sent.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Owner opens Reminders while the send is in flight and presses Send.
    final screenQueue = await service.buildQueue(now: at);
    for (final c in screenQueue) {
      unawaited(service.send(c));
    }
    client.gate!.complete();
    await autoRun;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(client.sent, hasLength(1),
        reason: 'the member must receive one on-due reminder, not two');
  });

  test('a copy the screen built before the automatic run sent it is refused',
      () async {
    final screenQueue = await service.buildQueue(now: at);
    await turnOnAutoSend();
    await service.runAutoSend(now: at);
    expect(client.sent, hasLength(1));

    final outcome = await service.send(screenQueue.single);
    expect(outcome, isA<ReminderNotNeeded>());
    expect(client.sent, hasLength(1));
  });

  test('the same reminder sent twice at once goes out once', () async {
    final candidate = (await service.buildQueue(now: at)).single;
    final outcomes = await Future.wait(
        [service.send(candidate), service.send(candidate)]);

    expect(client.sent, hasLength(1));
    expect(outcomes.whereType<ReminderSent>(), hasLength(1));
    expect(outcomes.whereType<ReminderNotNeeded>(), hasLength(1));
  });

  test('two automatic runs at once send once', () async {
    await turnOnAutoSend();
    await Future.wait(
        [service.runAutoSend(now: at), service.runAutoSend(now: at)]);
    expect(client.sent, hasLength(1));
  });

  test('two queue builds at once do not crash on the duplicate guard',
      () async {
    // App reopened after a week: three superseded stages get written.
    final week = DateTime.utc(2026, 8, 13, 7);
    await expectLater(
      Future.wait(
          [service.buildQueue(now: week), service.buildQueue(now: week)]),
      completes,
    );
    final skipped = await (db.select(db.paymentReminders)
          ..where((r) => r.status.equalsValue(ReminderSendStatus.skipped)))
        .get();
    expect(skipped, hasLength(3), reason: 'one row per stage, not two');
  });

  test('a member who paid after the queue was built is not reminded',
      () async {
    final candidate = (await service.buildQueue(now: at)).single;
    await pay(fee);

    final outcome = await service.send(candidate);
    expect(outcome, isA<ReminderNotNeeded>());
    expect(client.sent, isEmpty);
    // Only the before-due nudge buildQueue superseded is on record.
    final rows = await db.select(db.paymentReminders).get();
    expect(rows.where((r) => r.status != ReminderSendStatus.skipped), isEmpty,
        reason: 'nothing failed, so nothing is recorded as failing');
  });

  test('a part-payment made after the queue was built is reflected in the '
      'amount sent', () async {
    final candidate = (await service.buildQueue(now: at)).single;
    expect(candidate.amountDueMinor, fee);
    await pay(100000);

    expect(await service.send(candidate), isA<ReminderSent>());
    final row = await (db.select(db.paymentReminders)
          ..where((r) => r.status.equalsValue(ReminderSendStatus.sent)))
        .getSingle();
    expect(row.amountMinor, 200000);
    expect(client.sent.single.bodyParams[1], contains('2,000'));
  });
}
