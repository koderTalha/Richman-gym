import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/payment_settlement.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

class _FakeRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      RenderedReceipt(pdf: Uint8List(0), png: Uint8List.fromList([1, 2, 3]));
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;
  @override
  Future<Directory> root() async => _dir;
}

/// The whole-roster reads that replaced a query per member must give exactly
/// the per-member answer, for every kind of member the gym has: paid ahead,
/// part-paid, moved to another plan with the paid months left on the old
/// enrolment, on their own fee, deactivated, never billed.
void main() {
  late Directory workspace;
  late AppDatabase db;
  late MemberRepository members;
  late BillingCycleService cycles;
  late RecordPaymentService payments;
  late int adminId;
  late int monthlyId;
  late int quarterlyId;
  var keys = 0;

  final now = DateTime.utc(2026, 9, 15, 9);

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-bulk');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Test Monthly', durationMonths: 1, priceMinor: 300000));
    quarterlyId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Test Quarterly', durationMonths: 3, priceMinor: 800000));
    members = MemberRepository(db);
    cycles = BillingCycleService(db);
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(Directory(p.join(workspace.path, 'r'))),
      clientFactory: () async => MockWhatsAppClient(),
      cycles: cycles,
    );
  });

  tearDown(() async {
    await db.close();
    await workspace.delete(recursive: true);
  });

  Future<int> join(String name, DateTime joined, {int? fee}) => members.create(
        fullName: name,
        phone: '+92300${1000000 + keys++}',
        planId: monthlyId,
        feeOverrideMinor: fee,
        joiningDate: joined,
      );

  Future<void> pay(int memberId, int amount, DateTime on) =>
      payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: amount,
        method: PaymentMethod.cash,
        paymentDate: on,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'bulk-${keys++}',
        confirmedAdvance: true,
      ));

  Future<void> buildRoster() async {
    final ahead = await join('Test Ahead', DateTime.utc(2026, 6, 3));
    await pay(ahead, 1200000, DateTime.utc(2026, 6, 3));

    final partial = await join('Test Partial', DateTime.utc(2026, 7, 10));
    await pay(partial, 300000, DateTime.utc(2026, 7, 10));
    await pay(partial, 100000, DateTime.utc(2026, 8, 12));

    final moved = await join('Test Moved', DateTime.utc(2026, 5, 1));
    await pay(moved, 900000, DateTime.utc(2026, 5, 1));
    final m = (await members.byId(moved))!.member;
    await members.update(
      id: moved,
      fullName: m.fullName,
      phone: m.phone,
      planId: quarterlyId,
      joiningDate: m.joiningDate,
      now: DateTime.utc(2026, 8, 1),
    );

    final ownFee = await join('Test Own Fee', DateTime.utc(2026, 8, 20),
        fee: 250000);
    await pay(ownFee, 250000, DateTime.utc(2026, 8, 20));

    final gone = await join('Test Gone', DateTime.utc(2026, 4, 1));
    await pay(gone, 300000, DateTime.utc(2026, 4, 1));
    await members.setActive(gone, false);

    await join('Test Never Billed', DateTime.utc(2026, 9, 14));
  }

  test('forMembers gives every member exactly what forMember does', () async {
    await buildRoster();
    final all = await db.select(db.members).get();

    final bulk = await cycles.forMembers(all);
    for (final member in all) {
      final one = await cycles.forMember(member.id);
      final many = bulk[member.id];
      expect(many == null, one == null, reason: member.fullName);
      if (one == null) continue;
      expect(many!.membership.id, one.membership.id, reason: member.fullName);
      expect(many.plan.id, one.plan.id);
      expect(many.anchorDay, one.anchorDay);
      expect(many.feeMinor, one.feeMinor);
      String shape(List<SettleableCycle> c) => [
            for (final x in c)
              '${x.periodId}:${x.start}:${x.end}:${x.expectedMinor}:'
                  '${x.collectedMinor}',
          ].join('|');
      expect(shape(many.cycles), shape(one.cycles), reason: member.fullName);
    }
  });

  test('the whole roster at once reads every member as they read alone',
      () async {
    await buildRoster();

    final roster = await members.list(now: now);
    expect(roster, hasLength(6));
    for (final row in roster) {
      final alone = (await members.byId(row.id, now: now))!;
      expect(
        [row.status, row.paidUntil, row.outstandingMinor, row.arrearsMinor,
            row.feeMinor, row.membership?.id],
        [alone.status, alone.paidUntil, alone.outstandingMinor,
            alone.arrearsMinor, alone.feeMinor, alone.membership?.id],
        reason: row.member.fullName,
      );
    }

    // And a search, which still names its members, agrees with both.
    final searched = await members.list(search: 'Test Partial', now: now);
    final fromRoster = roster.firstWhere((r) => r.member.fullName == 'Test Partial');
    expect(searched.single.status, fromRoster.status);
    expect(searched.single.arrearsMinor, fromRoster.arrearsMinor);
  });
}
