import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/domain/member_status.dart';
import 'package:rich_man_fitness/domain/payment_errors.dart';
import 'package:rich_man_fitness/domain/payment_timing.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

/// The story the owner got wrong, end to end.
///
/// A member joins on 6 July and is anchored to the 6th. He pays on 6 July, on
/// 6 August, and then — five days early — on **1 September**. The third
/// payment must buy 6 Sep - 6 Oct and be filed under September, exactly like
/// the two before it. It must not shorten his cycle to 1 Sep - 1 Oct, and it
/// must not move his billing day to the 1st.
///
/// The billing arithmetic already did the right thing, because it never sees a
/// payment date. What it could not do was *say* so: the ledger showed a
/// receipt dated 1 September against a September cycle, and nothing anywhere
/// explained the mismatch. These tests pin down the explanation.
class _FakeRenderer extends ReceiptRenderer {
  ReceiptData? lastData;

  @override
  Future<RenderedReceipt> render(ReceiptData data) async {
    lastData = data;
    return RenderedReceipt(pdf: Uint8List(0), png: Uint8List.fromList([1]));
  }
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;
  @override
  Future<Directory> root() async => _dir;
}

void main() {
  late Directory workspace;
  late AppDatabase db;
  late RecordPaymentService payments;
  late MemberRepository members;
  late _FakeRenderer renderer;
  late int memberId;
  late int adminId;
  var counter = 0;

  const monthlyFee = 300000;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-timing');
    db = AppDatabase.forTesting(NativeDatabase.memory());

    adminId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(const GymSettingsCompanion());

    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: monthlyFee));

    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ali Raza',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 7, 6),
        ));

    await db.into(db.memberships).insert(MembershipsCompanion.insert(
          memberId: memberId,
          planId: planId,
          startDate: DateTime.utc(2026, 7, 6),
        ));

    renderer = _FakeRenderer();
    members = MemberRepository(db);
    payments = RecordPaymentService(
      db: db,
      renderer: renderer,
      storage: _FakeStorage(Directory(p.join(workspace.path, 'receipts'))),
      clientFactory: () async => MockWhatsAppClient(),
      cycles: BillingCycleService(db),
    );
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  Future<RecordPaymentResult> pay(
    DateTime on, {
    int amountMinor = monthlyFee,
    bool confirmedAdvance = false,
  }) =>
      payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: amountMinor,
        method: PaymentMethod.cash,
        paymentDate: on,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'timing-${counter++}',
        confirmedAdvance: confirmedAdvance,
      ));

  Future<List<MembershipPeriod>> periods() => (db.select(db.membershipPeriods)
        ..orderBy([(p) => OrderingTerm(expression: p.periodStart)]))
      .get();

  group('the 1 September advance payment', () {
    setUp(() async {
      await pay(DateTime.utc(2026, 7, 6));
      await pay(DateTime.utc(2026, 8, 6));
    });

    test('buys the anchored September cycle, not one starting 1 September',
        () async {
      await pay(DateTime.utc(2026, 9, 1));

      final september = (await periods()).last;
      expect(september.periodStart.toUtc(), DateTime.utc(2026, 9, 6));
      expect(september.periodEnd.toUtc(), DateTime.utc(2026, 10, 6));
    });

    test('leaves the anchor day on the 6th', () async {
      await pay(DateTime.utc(2026, 9, 1));

      // The next cycle after it must still be anchored to the 6th. If the
      // payment date had leaked into the arithmetic this would be 1 Oct.
      await pay(DateTime.utc(2026, 10, 6));
      expect((await periods()).last.periodStart.toUtc(),
          DateTime.utc(2026, 10, 6));
    });

    test('is labelled an advance payment', () async {
      final result = await pay(DateTime.utc(2026, 9, 1));
      expect(result.timing, PaymentTiming.advance);
    });

    test('says so on the receipt, beside the period it bought', () async {
      await pay(DateTime.utc(2026, 9, 1));

      expect(renderer.lastData!.billingPeriod, contains('September 2026'));
      expect(renderer.lastData!.billingPeriod.toLowerCase(),
          contains('advance'));
    });

    test('keeps the payment date as the day the money actually arrived',
        () async {
      await pay(DateTime.utc(2026, 9, 1));

      final payment = (await db.select(db.payments).get()).last;
      expect(payment.paymentDate.toUtc().day, 1,
          reason: 'paid_at is a fact about the money, not about the cycle');
    });

    test('does not make the member read overdue', () async {
      await pay(DateTime.utc(2026, 9, 1));

      final row = await members.byId(memberId, now: DateTime.utc(2026, 9, 20));
      expect(row!.status, MemberStatus.paid);
    });

    test('does not fall due again until the paid cycle actually runs out',
        () async {
      await pay(DateTime.utc(2026, 9, 1));

      final inside =
          await members.byId(memberId, now: DateTime.utc(2026, 10, 5));
      expect(inside!.status, MemberStatus.paid,
          reason: 'he paid for this day five weeks ago');

      // The cycle he bought ends on the 6th, exclusive. Opening the app that
      // day rolls the next cycle into existence — which is the only reason he
      // reads DUE rather than EXPIRED, since "expired" is what this app calls
      // a member no cycle covers at all.
      await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 10, 6));

      final after = await members.byId(memberId, now: DateTime.utc(2026, 10, 6));
      expect(after!.status, MemberStatus.due);
    });

    test('is not carried into the next cycle by the maintenance roll', () async {
      // Materialising the October cycle must not inherit September's
      // settlement: the money bought one cycle, not a standing credit.
      await pay(DateTime.utc(2026, 9, 1));
      await BillingMaintenance(db)
          .ensureCurrentPeriods(now: DateTime.utc(2026, 10, 6));

      final october = (await periods()).last;
      expect(october.periodStart.toUtc(), DateTime.utc(2026, 10, 6));
      expect(october.settledAt, isNull);
    });
  });

  group('timing labels', () {
    test('a payment on the due day is unremarkable', () async {
      final result = await pay(DateTime.utc(2026, 7, 6));
      expect(result.timing, PaymentTiming.onTime);
      expect(renderer.lastData!.billingPeriod, 'July 2026',
          reason: 'the ordinary case gets no badge at all');
    });

    test('a payment chased weeks later is labelled late', () async {
      final result = await pay(DateTime.utc(2026, 7, 28));
      expect(result.timing, PaymentTiming.late);
      expect(renderer.lastData!.billingPeriod.toLowerCase(), contains('late'));
    });

    test('clearing arrears is judged against the cycle it clears', () async {
      // He misses July and August entirely and settles up on 20 September.
      // Arrears first: the money buys July, so the label describes the July
      // cycle being paid late — not a September payment arriving on time.
      await pay(DateTime.utc(2026, 9, 20), amountMinor: monthlyFee);

      final all = await periods();
      expect(all.single.periodStart.toUtc(), DateTime.utc(2026, 7, 6));
      expect(renderer.lastData!.billingPeriod, contains('July 2026'));
      expect(renderer.lastData!.billingPeriod.toLowerCase(), contains('late'));
    });
  });

  group('how far ahead one payment may reach', () {
    test('a month ahead is recorded without a question', () async {
      // Two months' fee on the due day: this cycle and the next.
      final result = await pay(DateTime.utc(2026, 7, 6),
          amountMinor: monthlyFee * 2);
      expect(result.paymentId, greaterThan(0));
      expect((await periods()).length, 2);
    });

    test('a quarter upfront asks the owner to confirm first', () async {
      await expectLater(
        pay(DateTime.utc(2026, 7, 6), amountMinor: monthlyFee * 4),
        throwsA(isA<AdvanceConfirmationRequired>()),
      );

      expect(await periods(), isEmpty,
          reason: 'nothing is written while the question is outstanding');
    });

    test('and records it once the owner confirms', () async {
      final result = await pay(DateTime.utc(2026, 7, 6),
          amountMinor: monthlyFee * 4, confirmedAdvance: true);

      expect(result.paymentId, greaterThan(0));
      expect((await periods()).length, 4);
    });

    test('refuses a payment reaching past the ceiling even if confirmed',
        () async {
      await expectLater(
        pay(DateTime.utc(2026, 7, 6),
            amountMinor: monthlyFee * 20, confirmedAdvance: true),
        throwsA(isA<PaymentRuleException>()),
      );

      expect(await periods(), isEmpty);
    });

    test('never interrogates a member clearing a backlog', () async {
      // Four months of arrears settled at once is four cycles, none of them in
      // the future. It must not need confirming.
      final result = await pay(DateTime.utc(2026, 10, 20),
          amountMinor: monthlyFee * 4);

      expect(result.paymentId, greaterThan(0));
      expect((await periods()).length, 4);
    });
  });

  group('the payment history row', () {
    test('names the cycle the money bought instead of a dash', () async {
      // The row the owner actually reads. A payment whose cycle link is null
      // shows "—" in the PERIOD column on the dashboard, the payments screen
      // and the member's own profile — three places at once, which is what
      // makes this worth pinning down.
      await pay(DateTime.utc(2026, 7, 6));

      final rows = await PaymentRepository(db).history(memberId: memberId);
      expect(rows.single.periodLabel, 'July 2026');
    });

    test('links the payment to the cycle it settled', () async {
      await pay(DateTime.utc(2026, 7, 6));

      final payment = await db.select(db.payments).getSingle();
      final period = await db.select(db.membershipPeriods).getSingle();

      expect(payment.membershipPeriodId, period.id,
          reason: 'the importer, the editor and the history table all read '
              'a payment\'s period as this single value');
    });

    test('carries the advance label onto the row', () async {
      await pay(DateTime.utc(2026, 7, 6));
      await pay(DateTime.utc(2026, 8, 6));
      await pay(DateTime.utc(2026, 9, 1));

      final rows = await PaymentRepository(db).history(memberId: memberId);
      final september =
          rows.firstWhere((r) => r.periodLabel == 'September 2026');
      expect(september.timing, PaymentTiming.advance);
    });

    test('points a multi-cycle payment at the first cycle it touched',
        () async {
      await pay(DateTime.utc(2026, 7, 6), amountMinor: monthlyFee * 2);

      final payment = await db.select(db.payments).getSingle();
      final first = (await periods()).first;

      expect(payment.membershipPeriodId, first.id);
    });
  });
}
