import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

/// What is and is not held open while a receipt is being produced.
///
/// Rendering a receipt rasterises a PDF through the platform, and saving it is
/// real disk I/O. Both used to happen inside the transaction that records the
/// payment. Drift serialises everything on one connection, so for as long as
/// the rasteriser took — or, if it wedged, forever — no other query in the app
/// could run and the whole window sat frozen.
class _BlockingRenderer extends ReceiptRenderer {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<RenderedReceipt> render(ReceiptData data) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return RenderedReceipt(pdf: Uint8List(0), png: Uint8List(0));
  }
}

class _FailingRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      throw StateError('the rasteriser is unavailable');
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
  late int memberId;
  late int adminId;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('rmf-payment-tx');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);

    adminId = (await db.select(db.users).getSingle()).id;
    final planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    memberId = await MemberRepository(db).create(
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: planId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() async {
    await db.close();
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  RecordPaymentInput input({String key = 'pay-1'}) => RecordPaymentInput(
        memberId: memberId,
        amountMinor: 300000,
        method: PaymentMethod.cash,
        paymentDate: DateTime(2026, 8, 15),
        billingMonth: '2026-08',
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: key,
      );

  RecordPaymentService serviceWith(ReceiptRenderer renderer) =>
      RecordPaymentService(
        db: db,
        renderer: renderer,
        storage: _FakeStorage(workspace),
        clientFactory: MockWhatsAppClient.new,
      );

  test('the rest of the app keeps working while a receipt renders', () async {
    final renderer = _BlockingRenderer();
    final recording = serviceWith(renderer).call(input());

    await renderer.started.future;

    // The whole point: this must not deadlock waiting for a transaction that
    // is parked on the rasteriser.
    final members = await (db.select(db.members).get()).timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw StateError(
          'the database was locked while the receipt was rendering'),
    );
    expect(members, hasLength(1));

    renderer.release.complete();
    await recording;
  });

  test('a receipt that cannot be rendered records no payment', () async {
    await expectLater(
        serviceWith(_FailingRenderer()).call(input()), throwsStateError);

    expect(await db.select(db.payments).get(), isEmpty,
        reason: 'a payment without its receipt is worse than no payment: the '
            'owner has no paperwork and no signal that anything went wrong');
    expect(await db.select(db.receipts).get(), isEmpty);
  });

  test('and leaves no orphaned files behind', () async {
    final renderer = _BlockingRenderer();
    final service = serviceWith(renderer);

    // The render succeeds and writes both files. While it was working, the key
    // this submit is holding got taken, so the commit that follows fails.
    final recording = service.call(input());
    await renderer.started.future;
    await db.into(db.payments).insert(PaymentsCompanion.insert(
          memberId: memberId,
          amountMinor: 300000,
          method: PaymentMethod.cash,
          paymentDate: DateTime(2026, 8, 15),
          recordedById: adminId,
          idempotencyKey: 'pay-1',
        ));
    renderer.release.complete();

    await expectLater(recording, throwsA(anything));

    final leftovers = workspace
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList();
    expect(leftovers, isEmpty,
        reason: 'images for a receipt that was never committed');
  });

  test('a payment and its receipt still commit together', () async {
    final result = await serviceWith(_BlockingRenderer()..release.complete())
        .call(input());

    final payment = await db.select(db.payments).getSingle();
    final receipt = await db.select(db.receipts).getSingle();

    expect(receipt.paymentId, payment.id);
    expect(result.receiptNumber, receipt.receiptNumber);
  });

  test('submitting the same form twice records one payment', () async {
    final service = serviceWith(_BlockingRenderer()..release.complete());

    final first = await service.call(input());
    final second = await service.call(input());

    expect(second.paymentId, first.paymentId);
    expect(await db.select(db.payments).get(), hasLength(1));
  });

  test('two submits racing each other record one payment', () async {
    final service = serviceWith(_BlockingRenderer()..release.complete());

    // Both get past the "already recorded?" check before either commits. The
    // unique index settles it; the loser must return the winner's receipt
    // rather than surfacing a SQLite error to somebody holding cash.
    final results = await Future.wait([
      service.call(input()),
      service.call(input()),
    ]);

    expect(results.first.paymentId, results.last.paymentId);
    expect(await db.select(db.payments).get(), hasLength(1));
  });
}
