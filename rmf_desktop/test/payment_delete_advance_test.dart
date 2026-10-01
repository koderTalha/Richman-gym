// Deleting an advance payment. recordAdvancePayment opens one cycle for each
// month the money reaches, and deleting the payment used to leave every one of
// them behind, empty and unsettled — eleven months of debt from a mistyped
// twelve-month payment. Cycles that have not started go with the payment;
// months already under way stay and read as due.
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
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

Future<
    ({
      AppDatabase db,
      int memberId,
      int paymentId,
      int adminId,
      PaymentEditService editor,
      BillingCycleService cycles,
    })> _twelveMonthsPaidOn6Jan() async {
  const fee = 300000;
  final workspace = await Directory.systemTemp.createTemp('rmf-del-advance');
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(() async {
    await db.close();
    await workspace.delete(recursive: true);
  });

  final adminId = await db.into(db.users).insert(UsersCompanion.insert(
      name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
  await db.into(db.gymSettings).insert(const GymSettingsCompanion());
  final planId = await db.into(db.membershipPlans).insert(
      MembershipPlansCompanion.insert(
          name: 'Monthly', durationMonths: 1, priceMinor: fee));
  final memberId = await db.into(db.members).insert(MembersCompanion.insert(
      memberCode: 1,
      fullName: 'Ali Raza',
      phone: '+923000000022',
      joiningDate: DateTime.utc(2026, 1, 6)));
  await db.into(db.memberships).insert(MembershipsCompanion.insert(
      memberId: memberId,
      planId: planId,
      startDate: DateTime.utc(2026, 1, 6)));

  final storage = _FakeStorage(Directory(p.join(workspace.path, 'r')));
  final cycles = BillingCycleService(db);
  final recorder = RecordPaymentService(
    db: db,
    renderer: _FakeRenderer(),
    storage: storage,
    clientFactory: () async => MockWhatsAppClient(),
    cycles: cycles,
  );
  final editor = PaymentEditService(
    db: db,
    renderer: _FakeRenderer(),
    storage: storage,
    audit: AuditRepository(db),
    payments: recorder,
    cycles: cycles,
  );

  final recorded = await recorder.recordAdvancePayment(AdvancePaymentInput(
    memberId: memberId,
    amountMinor: 12 * fee,
    method: PaymentMethod.cash,
    paymentDate: DateTime.utc(2026, 1, 6),
    sendWhatsApp: false,
    recordedById: adminId,
    idempotencyKey: 'k-1',
    confirmedAdvance: true,
  ));
  expect(await periodsForMember(db, memberId), hasLength(12));

  return (
    db: db,
    memberId: memberId,
    paymentId: recorded.paymentId,
    adminId: adminId,
    editor: editor,
    cycles: cycles,
  );
}

void main() {
  const fee = 300000;

  test('deleting a mistyped 12-month payment the same week leaves no future '
      'debt', () async {
    final f = await _twelveMonthsPaidOn6Jan();

    final deleted = await f.editor.delete(
        paymentId: f.paymentId,
        actorId: f.adminId,
        now: DateTime.utc(2026, 1, 8));
    expect(deleted, isA<PaymentDeleted>());

    final left = await periodsForMember(f.db, f.memberId);
    expect(left, hasLength(1));
    expect(left.single.periodStart.toUtc(), DateTime.utc(2026, 1, 6));
    expect(left.single.settledAt, isNull);

    final billing = await f.cycles.forMember(f.memberId);
    expect(billing!.outstandingMinor, fee);
  });

  test('deleting it months later keeps the months already under way',
      () async {
    final f = await _twelveMonthsPaidOn6Jan();

    await f.editor.delete(
        paymentId: f.paymentId,
        actorId: f.adminId,
        now: DateTime.utc(2026, 4, 20));

    // January to April have begun — the roll would have opened each of them
    // — so they stay, now unpaid. May onwards had not started.
    final left = await periodsForMember(f.db, f.memberId);
    expect([for (final c in left) c.periodStart.toUtc().month], [1, 2, 3, 4]);
    expect(left.every((c) => c.settledAt == null), isTrue);
  });
}
