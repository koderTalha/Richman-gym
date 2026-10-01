// An advance payment that settles several cycles records its money in
// payment_allocations, but `payments.membership_period_id` names only the
// FIRST cycle. The "has this cycle been paid?" checks on the record and edit
// paths used to read that column alone, so cycles 2..n of an advance payment
// looked unpaid: no duplicate warning, a false "earlier month unpaid" warning,
// and an edit allowed to land on a month already settled.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/domain/billing_month_check.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_month_checker.dart';
import 'package:rich_man_fitness/services/payment_edit_service.dart';
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

void main() {
  late Directory workspace;
  late AppDatabase db;
  late RecordPaymentService payments;
  late PaymentEditService editor;
  late BillingMonthChecker checker;
  late int memberId;
  late int adminId;
  var counter = 0;

  const fee = 300000;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-audit-advance');
    db = AppDatabase.forTesting(NativeDatabase.memory());

    adminId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(const GymSettingsCompanion());

    final planId = await db.into(db.membershipPlans).insert(
        MembershipPlansCompanion.insert(
            name: 'Monthly', durationMonths: 1, priceMinor: fee));

    memberId = await db.into(db.members).insert(MembersCompanion.insert(
          memberCode: 1,
          fullName: 'Ali Raza',
          phone: '+923000000022',
          joiningDate: DateTime.utc(2026, 1, 6),
        ));
    await db.into(db.memberships).insert(MembershipsCompanion.insert(
        memberId: memberId,
        planId: planId,
        startDate: DateTime.utc(2026, 1, 6)));

    final storage = _FakeStorage(Directory(p.join(workspace.path, 'r')));
    final cycles = BillingCycleService(db);
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: storage,
      clientFactory: () async => MockWhatsAppClient(),
      cycles: cycles,
    );
    editor = PaymentEditService(
      db: db,
      renderer: _FakeRenderer(),
      storage: storage,
      audit: AuditRepository(db),
      payments: payments,
      cycles: cycles,
    );
    checker = BillingMonthChecker(db);
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  Future<RecordPaymentResult> advance(int amountMinor, DateTime on) =>
      payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: memberId,
        amountMinor: amountMinor,
        method: PaymentMethod.cash,
        paymentDate: on,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'k-${counter++}',
        confirmedAdvance: true,
      ));

  Future<MembershipPeriod> cycleStarting(DateTime start) async =>
      (await periodForMemberStarting(db,
          memberId: memberId, periodStart: start))!;

  test('precondition: one advance payment settles Jan, Feb and Mar', () async {
    await advance(3 * fee, DateTime.utc(2026, 1, 6));
    for (final m in [1, 2, 3]) {
      final c = await cycleStarting(DateTime.utc(2026, m, 6));
      expect(c.settledAt, isNotNull, reason: 'cycle $m should be settled');
    }
  });

  test(
      'naming March after an advance payment already covered it warns about a '
      'duplicate payment', () async {
    await advance(3 * fee, DateTime.utc(2026, 1, 6));

    final check = await checker.check(
      memberId: memberId,
      billingMonth: '2026-03',
      now: DateTime.utc(2026, 3, 6),
    );

    expect(check.period?.periodStart.toUtc(), DateTime.utc(2026, 3, 6));
    expect(check.review.issues, contains(BillingMonthIssue.duplicatePayment),
        reason: 'March is fully paid by the advance payment; recording it '
            'again silently double-charges the member');
  });

  test('cycles settled by an advance payment are not reported as unpaid',
      () async {
    await advance(3 * fee, DateTime.utc(2026, 1, 6));
    // Open April with its own ordinary payment so there is a cycle after
    // the advance-covered ones.
    await advance(fee, DateTime.utc(2026, 4, 6));

    final check = await checker.check(
      memberId: memberId,
      billingMonth: '2026-05',
      now: DateTime.utc(2026, 5, 6),
    );

    expect(check.review.issues,
        isNot(contains(BillingMonthIssue.unpaidEarlierCycles)),
        reason: 'Feb and Mar are settled; warning that they are unpaid is '
            'false');
  });

  test(
      'editing another payment onto a cycle an advance payment already settled '
      'is refused', () async {
    await advance(3 * fee, DateTime.utc(2026, 1, 6));
    final april = await advance(fee, DateTime.utc(2026, 4, 6));

    final result = await editor.edit(EditPaymentInput(
      paymentId: april.paymentId,
      amountMinor: fee,
      method: PaymentMethod.cash,
      paymentDate: DateTime.utc(2026, 4, 6),
      billingMonth: '2026-03',
      editedById: adminId,
    ));

    final march = await cycleStarting(DateTime.utc(2026, 3, 6));
    final collected = (await collectedByPeriod(db, [march.id]))[march.id];

    expect(result, isA<PaymentEditRefused>(),
        reason: 'March already holds a full fee from the advance payment');
    expect(collected, fee,
        reason: 'March must not end up holding two fees');
  });
}
