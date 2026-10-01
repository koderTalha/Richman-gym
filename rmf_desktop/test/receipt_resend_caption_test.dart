// Re-sending a receipt carries the same words as the first send: every month
// the payment paid for, and how early or late it was. It used to name only the
// first month and drop the "(paid late)" the original caption carried.
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';
import 'package:rich_man_fitness/services/whatsapp/whatsapp_client.dart';

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

class _CapturingClient extends MockWhatsAppClient {
  final sent = <List<String>>[];

  @override
  Future<WhatsAppSendResult> sendTemplate(WhatsAppTemplateInput input) {
    sent.add(input.bodyParams);
    return super.sendTemplate(input);
  }
}

void main() {
  test('a re-sent three-month receipt names all three months and its timing',
      () async {
    const fee = 300000;
    final workspace = await Directory.systemTemp.createTemp('rmf-resend');
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

    final client = _CapturingClient();
    final recorder = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(Directory(p.join(workspace.path, 'r'))),
      clientFactory: () async => client,
      cycles: BillingCycleService(db),
    );

    // Three weeks after the cycle began: well past the grace window.
    final recorded = await recorder.recordAdvancePayment(AdvancePaymentInput(
      memberId: memberId,
      amountMinor: 3 * fee,
      method: PaymentMethod.cash,
      paymentDate: DateTime.utc(2026, 1, 27),
      sendWhatsApp: false,
      recordedById: adminId,
      idempotencyKey: 'k-1',
      confirmedAdvance: true,
    ));

    await recorder.resend(recorded.receiptId);

    expect(client.sent, hasLength(1));
    final period = client.sent.single.join(' | ');
    expect(period, contains('January 2026 - March 2026'));
    expect(period, contains('(paid late)'));
  });
}
