import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/payment_method.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_month_checker.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/payments/advance_payment_dialog.dart';

class _FakeRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      // Not empty: an empty image is refused before sending, and these tests
      // want the receipt to reach WhatsApp.
      RenderedReceipt(
          pdf: await buildPdf(data), png: Uint8List.fromList([1, 2, 3]));
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  @override
  Future<Directory> root() async => _dir;
}

/// The Record payment dialog as the handoff draws it: the member's number in
/// the header, the amount in the confirm button, methods as buttons, Escape
/// to close, and a success state that says what was recorded.
///
/// The billing logic behind the dialog is covered elsewhere; this is about the
/// owner being able to see what they are about to do and what they just did.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late int memberId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);

    final monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(250000)));

    memberId = await members.create(
      fullName: 'Test Payer',
      phone: '+923000000102',
      planId: monthlyId,
      joiningDate: DateTime.now().toUtc(),
    );

    final workspace = await Directory.systemTemp.createTemp('rmf-paydesign');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
  });

  tearDown(() async => db.close());

  /// Opens the dialog and returns a box that receives what it resolved to.
  Future<List<bool?>> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final admin = await db.select(db.users).getSingle();
    final row = await members.byId(memberId);
    final results = <bool?>[];

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<RecordPaymentService>.value(value: payments),
        RepositoryProvider<BillingCycleService>(
            create: (_) => BillingCycleService(db)),
        RepositoryProvider<BillingMonthChecker>(
            create: (_) => BillingMonthChecker(db)),
        RepositoryProvider<ReceiptStorage>(create: (_) => ReceiptStorage()),
      ],
      child: BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(db, restored: admin),
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async => results.add(
                      await showAdvancePaymentDialog(context, member: row!)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Finder confirm() => find.byKey(const Key('confirm-payment'));
  Finder amount() => find.byKey(const Key('payment-amount'));

  /// Recording renders and writes a real receipt, which needs a real event
  /// loop; see record_payment_month_picker_test.dart.
  Future<void> record(WidgetTester tester) async {
    await tester.ensureVisible(confirm());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(confirm());
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the header names the member and their number',
      (tester) async {
    await openDialog(tester);
    final code = (await members.byId(memberId))!.member.memberCode;

    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('Test Payer · #$code'), findsOneWidget);
  });

  testWidgets('the confirm button carries the amount as it is typed',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Confirm Rs. 2,500'), findsOneWidget,
        reason: 'pre-filled with the plan fee');

    await tester.enterText(amount(), '1,500');
    await tester.pump();
    expect(find.text('Confirm Rs. 1,500'), findsOneWidget);

    await tester.enterText(amount(), '');
    await tester.pump();
    expect(find.text('Confirm payment'), findsOneWidget,
        reason: 'no amount to state, so no amount in the label');
  });

  testWidgets('every payment method is a button, not a dropdown',
      (tester) async {
    await openDialog(tester);

    for (final method in PaymentMethod.values) {
      expect(
        find.widgetWithText(OutlinedButton, paymentMethodLabel(method)),
        findsOneWidget,
      );
    }
    expect(find.byType(DropdownButtonFormField<PaymentMethod>), findsNothing);

  });

  testWidgets('the method tapped is the method recorded', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'JazzCash'));
    await tester.pump();
    await record(tester);

    final payment = await db.select(db.payments).getSingle();
    expect(payment.method, PaymentMethod.jazzcash);
  });

  testWidgets('the settlement box says what the money covers and moves',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Covers'), findsOneWidget);
    expect(find.textContaining(' · from '), findsOneWidget,
        reason: 'the cycle the fee settles, with its start date');
    expect(find.text('Paid until'), findsOneWidget,
        reason: 'a full fee settles a cycle, so the date moves');
  });

  testWidgets('a part payment does not claim a new paid-until date',
      (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byKey(const Key('payment-amount')), '1000');
    await tester.pump();

    expect(find.text('Covers'), findsOneWidget);
    expect(find.text('Paid until'), findsNothing);
    expect(find.textContaining('Part payment: Rs. 1,500 will still be owing'),
        findsOneWidget);
  });

  testWidgets('an inactive member is told the payment will not reactivate them',
      (tester) async {
    // The prototype promised "This also reactivates the membership". Here a
    // payment does not, so the dialog must not say it does.
    await members.setActive(memberId, false);
    await openDialog(tester);

    expect(find.textContaining('does not reactivate'), findsOneWidget);
    expect(find.textContaining('also reactivates'), findsNothing);
  });

  testWidgets('labels sit above the fields, date beside billing period',
      (tester) async {
    await openDialog(tester);

    final amountLabel = tester.getRect(find.text('Amount received'));
    final amountField = tester.getRect(find.byKey(const Key('payment-amount')));
    expect(amountLabel.bottom, lessThanOrEqualTo(amountField.top));

    final date = tester.getRect(find.text('Payment date'));
    final period = tester.getRect(find.text('Billing period'));
    expect(date.top, period.top, reason: 'one row, as the handoff draws it');
    expect(date.left, lessThan(period.left));
    expect(find.text('Oldest unpaid first'), findsOneWidget);
  });

  testWidgets('the WhatsApp line shows the number as people read it',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Send receipt on WhatsApp'), findsOneWidget);
    expect(find.text('To +92 300 0000102'), findsOneWidget);
  });

  testWidgets('Escape closes it, saying nothing was recorded',
      (tester) async {
    final results = await openDialog(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Record payment'), findsNothing);
    expect(results, [false]);
  });

  testWidgets('a click outside does not close it', (tester) async {
    final results = await openDialog(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Record payment'), findsOneWidget,
        reason: 'a stray click must not lose the payment being typed');
    expect(results, isEmpty);
  });

  testWidgets('the success state says what was recorded', (tester) async {
    await openDialog(tester);
    await record(tester);

    expect(find.text('Payment recorded'), findsOneWidget);
    expect(find.textContaining('Rs. 2,500 from Test Payer · '),
        findsOneWidget);
    expect(find.text('Receipt sent on WhatsApp to +92 300 0000102'),
        findsOneWidget);
    expect(find.text('Print receipt'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('Escape after recording tells the caller to refresh',
      (tester) async {
    final results = await openDialog(tester);
    await record(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(results, [true],
        reason: 'the members list must show them as paid without a reload');
  });
}
