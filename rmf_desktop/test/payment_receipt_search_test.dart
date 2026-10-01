import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/payments_bloc.dart';
import 'package:rich_man_fitness/bloc/receipts_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

/// Search and filters on the Payments and Receipts screens, beyond the page.
///
/// Both screens used to fetch the newest N rows (500 payments, 300 receipts)
/// and only then apply the search and the status filters in Dart. Anything
/// older than the cap was invisible: searching a member's name for a July
/// payment said "No payments match", the Receipts "WhatsApp failed" filter
/// showed nothing while the dashboard counted a failure, and the header total
/// covered only the capped rows. Search and filters now go into SQL before
/// the `LIMIT`. (Audit BUG-019.)
void main() {
  late AppDatabase db;
  late int adminId;
  late int zaraId;
  late int zaraReceiptId;

  const fee = 300000;
  const busyPayments = 500;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adminId = await db.into(db.users).insert(UsersCompanion.insert(
        name: 'Owner', email: 'o@x.local', passwordHash: 'x'));
    await db.into(db.gymSettings).insert(const GymSettingsCompanion());
    zaraId = await db.into(db.members).insert(MembersCompanion.insert(
        memberCode: 1,
        fullName: 'Zara Khan',
        phone: '+923001111111',
        joiningDate: DateTime.utc(2025, 1, 1)));
    final busyId = await db.into(db.members).insert(MembersCompanion.insert(
        memberCode: 2,
        fullName: 'Ali Raza',
        phone: '+923002222222',
        joiningDate: DateTime.utc(2025, 1, 1)));

    Future<int> pay(int member, DateTime on, int n,
        {PaymentMethod method = PaymentMethod.cash}) async {
      final id = await db.into(db.payments).insert(PaymentsCompanion.insert(
            memberId: member,
            amountMinor: fee,
            method: method,
            paymentDate: on,
            recordedById: adminId,
            idempotencyKey: 'k-$n',
          ));
      return db.into(db.receipts).insert(ReceiptsCompanion.insert(
            receiptNumber: 'RMF-2026-${n.toString().padLeft(6, '0')}',
            paymentId: id,
            pngPath: 'x$n.png',
          ));
    }

    // Zara's one payment is the oldest of all, and the only Easypaisa one:
    // outside the newest 500 payments and the newest 300 receipts.
    zaraReceiptId = await pay(zaraId, DateTime.utc(2026, 1, 2), 1,
        method: PaymentMethod.easypaisa);
    for (var i = 0; i < busyPayments; i++) {
      await pay(busyId, DateTime.utc(2026, 2, 1).add(Duration(hours: i)), i + 2);
    }
  });

  tearDown(() => db.close());

  Future<PaymentsState> paymentsAfter(PaymentsEvent event,
      bool Function(PaymentsState) settled) async {
    final bloc = PaymentsBloc(PaymentRepository(db));
    addTearDown(bloc.close);
    bloc.add(event);
    return bloc.stream.firstWhere(
        (s) => s.status == PaymentsStatus.ready && settled(s));
  }

  Future<ReceiptsState> receiptsAfter(ReceiptsEvent event,
      bool Function(ReceiptsState) settled) async {
    final bloc = ReceiptsBloc(
      repository: ReceiptRepository(db),
      service: RecordPaymentService(
        db: db,
        renderer: ReceiptRenderer(),
        storage: ReceiptStorage(),
        clientFactory: () async => MockWhatsAppClient(),
      ),
    );
    addTearDown(bloc.close);
    bloc.add(event);
    return bloc.stream.firstWhere(
        (s) => s.status == ReceiptsStatus.ready && settled(s));
  }

  Future<void> whatsApp(int receiptId, WhatsAppStatus status, int attempt) =>
      db.into(db.whatsAppMessages).insert(WhatsAppMessagesCompanion.insert(
            receiptId: receiptId,
            memberId: zaraId,
            phone: '+923001111111',
            provider: WhatsAppProviderKind.meta,
            status: Value(status),
            attemptNumber: Value(attempt),
          ));

  group('Payments screen', () {
    test('search finds an older member by name', () async {
      final ready = await paymentsAfter(
          const PaymentsSearchSubmitted('zara'), (s) => s.search == 'zara');

      expect(ready.rows, hasLength(1),
          reason: "Zara's payment exists but is outside the newest 500 rows");
      expect(ready.rows.single.member.fullName, 'Zara Khan');
    });

    test('search finds an older payment by its receipt number', () async {
      final rows = await PaymentRepository(db).history(search: 'RMF-2026-000001');
      expect(rows.map((r) => r.member.fullName), ['Zara Khan']);
    });

    for (final typed in [
      '03001111111',
      '0300-1111111',
      '0300 1111111',
      '+92 300 1111111',
      '00923001111111',
      '0300-111', // part of a number, as the owner remembers it
    ]) {
      test('search finds a member by phone typed as "$typed"', () async {
        final rows = await PaymentRepository(db).history(search: typed);
        expect(rows.map((r) => r.member.fullName), ['Zara Khan'],
            reason: 'phones are stored as +923001111111');
      });
    }

    test('a name with a digit in it is not a search for every phone', () async {
      final rows = await PaymentRepository(db).history(search: 'Zara 1');
      expect(rows, isEmpty);
    });

    test("a receipt number's digits find that receipt, not every phone "
        'sharing its last digits', () async {
      // All digits, so it is also tried as a phone; dropping every leading
      // zero would have searched phones for "1" and matched both members.
      final rows = await PaymentRepository(db).history(search: '000001');
      expect(rows.map((r) => r.receipt?.receiptNumber), ['RMF-2026-000001']);
    });

    test('a typed wildcard matches literally, not every payment', () async {
      expect(await PaymentRepository(db).history(search: '%'), isEmpty);
      expect(await PaymentRepository(db).history(search: '_'), isEmpty);
    });

    test('the method filter is applied before the page limit', () async {
      final ready = await paymentsAfter(
          const PaymentsMethodChanged(PaymentMethod.easypaisa),
          (s) => s.method == PaymentMethod.easypaisa);

      expect(ready.rows.map((r) => r.member.fullName), ['Zara Khan']);
      expect(ready.matchCount, 1);
      expect(ready.totalMinor, fee);
    });

    test('the header total covers every matching payment, not only the shown '
        'page', () async {
      final ready = await paymentsAfter(
          const PaymentsRequested(), (s) => true);

      expect(ready.rows, hasLength(500), reason: 'the page is still capped');
      expect(ready.matchCount, busyPayments + 1);
      expect(ready.isCapped, isTrue);
      expect(ready.totalMinor, (busyPayments + 1) * fee,
          reason: 'summing the 500 shown rows understated it by one payment');
    });

    test('the header total follows the search', () async {
      final ready = await paymentsAfter(
          const PaymentsSearchSubmitted('ali'), (s) => s.search == 'ali');

      expect(ready.matchCount, busyPayments);
      expect(ready.totalMinor, busyPayments * fee);
    });
  });

  group('Receipts screen', () {
    test('search finds an older receipt number', () async {
      final rows = await ReceiptRepository(db).list(search: 'RMF-2026-000001');
      expect(rows, hasLength(1),
          reason: 'receipt 000001 exists but is outside the newest 300');
    });

    test('search finds an older receipt by member name and by phone',
        () async {
      final receipts = ReceiptRepository(db);
      for (final term in ['zara', '0300-1111111', '+92 300 1111111']) {
        final rows = await receipts.list(search: term);
        expect(rows.map((r) => r.receipt.id), [zaraReceiptId], reason: term);
      }
    });

    test('the "WhatsApp failed" filter agrees with the dashboard count',
        () async {
      await whatsApp(zaraReceiptId, WhatsAppStatus.failed, 1);

      final receipts = ReceiptRepository(db);
      expect(await receipts.failedCount(), 1); // what the dashboard shows

      final ready = await receiptsAfter(
          const ReceiptsFilterChanged(ReceiptFilter.failed),
          (s) => s.filter == ReceiptFilter.failed);
      expect(ready.rows.map((r) => r.receipt.id), [zaraReceiptId],
          reason: 'dashboard says 1 failed WhatsApp; the filter must show it');
      expect(ready.matchCount, 1);
    });

    test('a failure followed by a successful retry reads as sent, not failed',
        () async {
      await whatsApp(zaraReceiptId, WhatsAppStatus.failed, 1);
      await whatsApp(zaraReceiptId, WhatsAppStatus.sent, 2);

      final receipts = ReceiptRepository(db);
      expect(await receipts.failedCount(), 0);
      expect(await receipts.list(filter: ReceiptFilter.failed), isEmpty);

      final sent = await receipts.list(filter: ReceiptFilter.sent);
      expect(sent.map((r) => r.receipt.id), [zaraReceiptId]);
      expect(sent.single.whatsAppStatus, WhatsAppStatus.sent);
    });

    test('"Not sent" lists receipts never attempted, counted beyond the page',
        () async {
      await whatsApp(zaraReceiptId, WhatsAppStatus.sent, 1);

      final ready = await receiptsAfter(
          const ReceiptsFilterChanged(ReceiptFilter.notSent),
          (s) => s.filter == ReceiptFilter.notSent);
      expect(ready.rows, hasLength(300));
      expect(ready.rows.every((r) => r.whatsAppStatus == null), isTrue);
      expect(ready.matchCount, busyPayments,
          reason: "every receipt but Zara's, sent one");
      expect(ready.isCapped, isTrue);
    });

    test('search and filter combine', () async {
      await whatsApp(zaraReceiptId, WhatsAppStatus.failed, 1);
      final receipts = ReceiptRepository(db);

      expect(
          await receipts.list(search: 'ali', filter: ReceiptFilter.failed),
          isEmpty);
      expect(
          await receipts.count(search: 'zara', filter: ReceiptFilter.failed),
          1);
    });
  });
}
