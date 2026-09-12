import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/billing_cycle.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

/// Skips rasterising, which needs platform channels.
class _FakeRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      RenderedReceipt(pdf: await buildPdf(data), png: Uint8List(0));
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  @override
  Future<Directory> root() async => _dir;
}

/// Billing a member for a month they had not joined yet.
///
/// The second, independent cause of the gym's "payment is always due" report,
/// and the one re-pricing does not touch. A member signed up at the counter on
/// the 6th, in an app that had been opened on the 3rd, was given a cycle for
/// **6 December – 6 January** — a month that ended the day they walked in —
/// and read DUE before they had been a member for an hour.
///
/// `cycleContaining` backs up to the previous occurrence of the anchor day
/// whenever today falls earlier in the month than the anchor. That is right
/// for a member who has been on the books for years and has simply never had a
/// cycle recorded. It is wrong for somebody who joined this month, because
/// there was no membership to bill before they joined.
///
/// With `payDay == joinDay` it also costs an extra cycle: the phantom month
/// makes thirteen cycles over a year lived, which is the same permanent
/// arrears the fee re-pricing work removed by a different route.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late int adminId;
  late int monthlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    final workspace = await Directory.systemTemp.createTemp('rmf-prejoin');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
  });

  tearDown(() async => db.close());

  Future<int> joinOn(DateTime joiningDate) => members.create(
        fullName: 'Ali Khan',
        phone: '+923000000001',
        planId: monthlyId,
        joiningDate: joiningDate,
      );

  Future<void> runMaintenanceOn(DateTime day) =>
      BillingMaintenance(db).ensureCurrentPeriods(now: day);

  Future<List<MembershipPeriod>> cyclesOf(int memberId) =>
      periodsForMember(db, memberId);

  test('a member is never billed for a month before they joined', () async {
    final joining = DateTime.utc(2026, 1, 6);
    final memberId = await joinOn(joining);

    // The owner opened the app on the 3rd; the member signs up on the 6th.
    await runMaintenanceOn(DateTime.utc(2026, 1, 3));

    final cycles = await cyclesOf(memberId);
    for (final cycle in cycles) {
      expect(cycle.periodStart.toUtc().isBefore(joining), isFalse,
          reason: 'a cycle starting ${cycle.periodStart} bills them for time '
              'they were not a member');
    }
  });

  test('what they owe on joining is one month, starting the day they joined',
      () async {
    final joining = DateTime.utc(2026, 1, 6);
    final memberId = await joinOn(joining);
    await runMaintenanceOn(DateTime.utc(2026, 1, 3));

    final row = await members.byId(memberId, now: DateTime.utc(2026, 1, 3));
    // DUE is right — they have enrolled and not paid. What must not happen is
    // their first bill covering a month that ended before they walked in.
    expect(row!.status, MemberStatus.due);
    expect(row.outstandingMinor, 300000,
        reason: 'one month of the monthly fee, not two');

    final cycles = await cyclesOf(memberId);
    expect(cycles, hasLength(1));
    expect(cycles.single.periodStart.toUtc(), joining);
    expect(cycles.single.periodEnd.toUtc(), DateTime.utc(2026, 2, 6));
  });

  test('a year lived is twelve cycles, not thirteen', () async {
    final joining = DateTime.utc(2026, 1, 6);
    final memberId = await joinOn(joining);

    // The app is opened a few days before the member joins, which is what
    // conjures the phantom month.
    await runMaintenanceOn(DateTime.utc(2026, 1, 3));

    // Then a full year of billing on their own day, paid in full each month.
    for (var month = 1; month <= 12; month++) {
      final on = DateTime.utc(2026, month, 6);
      await runMaintenanceOn(on);
      await payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: 300000,
        method: PaymentMethod.cash,
        paymentDate: on,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'pay-$month',
      ));
    }

    final cycles = await cyclesOf(memberId);
    expect(cycles.length, 12,
        reason: 'twelve months lived is twelve cycles; a thirteenth is the '
            'month before they joined');

    final row = await members.byId(memberId, now: DateTime.utc(2027, 1, 5));
    expect(row!.outstandingMinor, isNull,
        reason: 'they paid the full fee twelve times');
    expect(cycles.where((c) => c.settledAt == null), isEmpty);
  });

  test('a dormant member with no cycles is still billed from this month',
      () async {
    // Joined years ago, never had a cycle recorded. The clamp must not reach
    // back and start their cycle at a joining date in 2020.
    final memberId = await joinOn(DateTime.utc(2020, 3, 15));
    await db.delete(db.membershipPeriods).go();

    await runMaintenanceOn(DateTime.utc(2026, 1, 3));

    final cycles = await cyclesOf(memberId);
    expect(cycles, hasLength(1));
    expect(cycles.single.periodStart.toUtc(), DateTime.utc(2025, 12, 15),
        reason: 'backfilling every month since 2020 would invent debt the '
            'owner never recorded — see cycleContaining');
  });

  group('cycleContaining', () {
    test('will not start a cycle before the member joined', () {
      final cycle = cycleContaining(
        today: DateTime.utc(2026, 1, 3),
        anchorDay: 6,
        durationMonths: 1,
        joiningDate: DateTime.utc(2026, 1, 6),
      );

      expect(cycle.start, DateTime.utc(2026, 1, 6));
      expect(cycle.end, DateTime.utc(2026, 2, 6));
    });

    test('still backs up to the previous anchor for a long-standing member',
        () {
      final cycle = cycleContaining(
        today: DateTime.utc(2026, 1, 3),
        anchorDay: 6,
        durationMonths: 1,
        joiningDate: DateTime.utc(2020, 3, 15),
      );

      expect(cycle.start, DateTime.utc(2025, 12, 6));
    });
  });
}
