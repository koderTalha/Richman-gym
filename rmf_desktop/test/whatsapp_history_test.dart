import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';

/// The WhatsApp screen lists receipts, not send attempts.
///
/// Chasing one stubborn receipt used to fill the screen with the same member
/// and receipt number over and over, each row offering its own Retry button for
/// the one thing there was to retry.
void main() {
  late AppDatabase db;
  late ReceiptRepository receipts;
  late int memberId;
  late int adminId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    receipts = ReceiptRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    memberId = await MemberRepository(db).create(
      fullName: 'Talha Rauf',
      phone: '+923256851835',
      planId: (await (db.select(db.membershipPlans)
                ..where((p) => p.name.equals('Monthly')))
              .getSingle())
          .id,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() => db.close());

  var nextKey = 0;

  /// A receipt with a payment behind it, the way the app creates them.
  Future<int> newReceipt(String number) async {
    final paymentId = await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            amountMinor: 300000,
            method: PaymentMethod.cash,
            paymentDate: DateTime(2026, 8, 15),
            recordedById: adminId,
            idempotencyKey: 'pay-${nextKey++}',
          ),
        );

    return db.into(db.receipts).insert(ReceiptsCompanion.insert(
          receiptNumber: number,
          paymentId: paymentId,
          pngPath: '$number.png',
        ));
  }

  Future<void> attempt(
    int receiptId, {
    required int number,
    required WhatsAppStatus status,
    String? error,
    String? messageId,
  }) =>
      db.into(db.whatsAppMessages).insert(WhatsAppMessagesCompanion.insert(
            receiptId: receiptId,
            memberId: memberId,
            phone: '+923256851835',
            provider: WhatsAppProviderKind.meta,
            status: Value(status),
            errorMessage: Value(error),
            externalMessageId: Value(messageId),
            attemptNumber: Value(number),
          ));

  /// The situation from the screenshot: one receipt chased seven times, and one
  /// that went first time.
  Future<(int, int)> theScatteredCase() async {
    final second = await newReceipt('RMF-2026-000001');
    await attempt(second, number: 1, status: WhatsAppStatus.sent,
        messageId: 'mock.397f2076');

    final first = await newReceipt('RMF-2026-000002');
    await attempt(first, number: 1, status: WhatsAppStatus.sent,
        messageId: 'mock.b3be4fd1');
    for (var n = 2; n <= 5; n++) {
      await attempt(first,
          number: n,
          status: WhatsAppStatus.failed,
          error: '(#133010) Account not registered');
    }
    await attempt(first,
        number: 6,
        status: WhatsAppStatus.failed,
        error: '(#100) Param file must be a file with one of the following '
            'types: … Received file of type \'application/octet-stream\'.');
    await attempt(first,
        number: 7,
        status: WhatsAppStatus.sent,
        messageId: 'wamid.HBgMOTIzMjU2ODUxODM1');

    return (first, second);
  }

  test('eight attempts across two receipts read as two entries', () async {
    await theScatteredCase();

    final history = await receipts.sendHistory();

    expect(history, hasLength(2));
    expect(
      history.map((t) => t.receipt.receiptNumber),
      ['RMF-2026-000002', 'RMF-2026-000001'],
      reason: 'the receipt with the most recent activity comes first',
    );
    expect(history.first.attemptCount, 7);
    expect(history.last.attemptCount, 1);
  });

  test('a receipt that eventually went through reads as sent', () async {
    await theScatteredCase();

    final chased = (await receipts.sendHistory()).first;

    expect(chased.status, WhatsAppStatus.sent,
        reason: 'six failures then a success is a receipt the member has');
    expect(chased.needsRetry, isFalse,
        reason: 'and therefore offers no Retry button');
    expect(chased.failedAttempts, 5);
    expect(chased.latest.externalMessageId, 'wamid.HBgMOTIzMjU2ODUxODM1');
  });

  test('the full attempt history is kept, newest first', () async {
    await theScatteredCase();

    final chased = (await receipts.sendHistory()).first;

    expect(chased.attempts.map((a) => a.attemptNumber), [7, 6, 5, 4, 3, 2, 1]);
    expect(chased.attempts[1].errorMessage, contains('#100'));
    expect(chased.attempts.last.externalMessageId, 'mock.b3be4fd1');
  });

  test('a receipt still failing offers exactly one retry', () async {
    final receiptId = await newReceipt('RMF-2026-000003');
    await attempt(receiptId, number: 1, status: WhatsAppStatus.failed,
        error: 'first try');
    await attempt(receiptId, number: 2, status: WhatsAppStatus.failed,
        error: 'second try');
    await attempt(receiptId, number: 3, status: WhatsAppStatus.failed,
        error: 'third try');

    final history = await receipts.sendHistory();

    expect(history, hasLength(1), reason: 'three rows became one card');
    expect(history.single.needsRetry, isTrue);
    expect(history.single.latest.errorMessage, 'third try');
  });

  group('the Failed filter', () {
    test('hides a receipt whose latest attempt succeeded', () async {
      await theScatteredCase();

      final failing = await receipts.sendHistory(
          status: WhatsAppStatus.failed);

      expect(failing, isEmpty,
          reason: 'nothing here still needs the owner to do anything');
    });

    test('shows a receipt whose latest attempt failed, with its history',
        () async {
      await theScatteredCase();
      final stuck = await newReceipt('RMF-2026-000004');
      await attempt(stuck, number: 1, status: WhatsAppStatus.sent,
          messageId: 'mock.aaa');
      await attempt(stuck, number: 2, status: WhatsAppStatus.failed,
          error: 'still broken');

      final failing =
          await receipts.sendHistory(status: WhatsAppStatus.failed);

      expect(failing, hasLength(1));
      expect(failing.single.receipt.receiptNumber, 'RMF-2026-000004');
      expect(failing.single.attemptCount, 2,
          reason: 'the successful earlier attempt is still part of the story');
      expect(failing.single.needsRetry, isTrue);
    });
  });

  test('the limit bounds receipts shown, not attempts read', () async {
    for (var r = 0; r < 5; r++) {
      final receiptId = await newReceipt('RMF-2026-10000$r');
      for (var n = 1; n <= 4; n++) {
        await attempt(receiptId, number: n, status: WhatsAppStatus.failed,
            error: 'nope');
      }
    }

    final history = await receipts.sendHistory(limit: 2);

    expect(history, hasLength(2));
    expect(history.every((t) => t.attemptCount == 4), isTrue,
        reason: 'a shown receipt is shown whole, never half its attempts');
  });

  test('a receipt nobody has tried to send does not appear', () async {
    await newReceipt('RMF-2026-000009');

    expect(await receipts.sendHistory(), isEmpty,
        reason: 'this is the send log, not the receipt list');
  });

  test('the dashboard failure count still counts receipts, not attempts',
      () async {
    await theScatteredCase();
    final stuck = await newReceipt('RMF-2026-000004');
    await attempt(stuck, number: 1, status: WhatsAppStatus.failed,
        error: 'still broken');

    expect(await receipts.failedCount(), 1,
        reason: 'five failed attempts on a since-delivered receipt are not '
            'five problems');
  });
}
