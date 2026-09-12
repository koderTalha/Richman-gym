import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
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
      RenderedReceipt(pdf: await buildPdf(data), png: Uint8List(0));
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  @override
  Future<Directory> root() async => _dir;
}

/// Choosing which month a payment is for, from the Record Payment dialog.
///
/// The service could always do this — `RecordPaymentService.call` takes the
/// billing month and opens that month's cycle if it is missing — but only Edit
/// Payment offered the field. Recording a back-dated payment therefore meant
/// letting it land on the wrong month first and correcting it afterwards,
/// which writes a wrong row to the ledger on the way to the right one.
///
/// Automatic stays the default: at the counter the owner takes what is owed
/// and should not have to think about months at all.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late int memberId;
  late int monthlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);

    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(150000)));

    memberId = await members.create(
      fullName: 'Talha',
      phone: '+923000000001',
      planId: monthlyId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );

    final workspace = await Directory.systemTemp.createTemp('rmf-monthpick');
    addTearDown(() => workspace.delete(recursive: true));
    payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
  });

  tearDown(() async => db.close());

  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final admin = await db.select(db.users).getSingle();
    final row = await members.byId(memberId);

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
                  onPressed: () =>
                      showAdvancePaymentDialog(context, member: row!),
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
  }

  /// Taps [button] and waits for the work behind it to finish.
  ///
  /// Recording a payment renders a receipt and writes it to disk. That is real
  /// I/O, and the test binding's fake async zone will not let it complete
  /// inside a plain `pump` — the dialog sits on "Recording…" for ever. Only
  /// `runAsync` gives the operation a real event loop.
  Future<void> tapAndSettle(WidgetTester tester, Finder button) async {
    // The dialog scrolls, and naming a month makes it taller. Confirm Payment
    // is then laid out below the visible area — present to the finder, but
    // clipped, so a tap at its centre lands on the modal barrier instead.
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(button);
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog offers a billing period, defaulting to Automatic',
      (tester) async {
    await openDialog(tester);

    expect(find.text('Billing period'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget,
        reason: 'the counter flow must not change — the owner takes what is '
            'owed without thinking about months');
  });

  testWidgets('Automatic still records through the oldest-unpaid path',
      (tester) async {
    await openDialog(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount received *'), '1500');
    await tester.pump();
    await tapAndSettle(tester, find.text('Confirm Payment'));

    expect(find.text('Payment recorded'), findsOneWidget);
    final cycles = await periodsForMember(db, memberId);
    expect(cycles, hasLength(1));
    expect(cycles.single.settledAt, isNotNull);
  });

  /// Drives the month picker back to [monthsBack] months before today.
  Future<void> chooseMonthBack(WidgetTester tester, int monthsBack) async {
    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();

    // Opens on the year grid, so the year is chosen before the month.
    await tester.tap(find.text('${DateTime.now().year}'));
    await tester.pumpAndSettle();

    for (var i = 0; i < monthsBack; i++) {
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
    }

    // Any day in the month will do — only the month is read off it.
    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('naming a past month asks what it cost and settles that month',
      (tester) async {
    await openDialog(tester);
    await chooseMonthBack(tester, 4); // September -> May

    expect(find.text('May 2026'), findsWidgets,
        reason: 'the summary names the month the money is for');
    expect(find.text('Fee for this month *'), findsOneWidget,
        reason: 'May has no cycle, so this payment opens one and its price is '
            'the owner\'s to state — not silently today\'s fee');
    expect(
      find.textContaining('No billing cycle exists for this period yet'),
      findsOneWidget,
    );

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount received *'), '2500');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fee for this month *'), '2500');
    await tester.pump();

    await tapAndSettle(tester, find.text('Confirm Payment'));
    expect(find.text('Payment recorded'), findsOneWidget);

    final cycles = await periodsForMember(db, memberId);
    expect(cycles, hasLength(1));
    expect(cycles.single.periodStart.toUtc(), DateTime.utc(2026, 5, 1),
        reason: 'the money went to May, not to the oldest unpaid cycle');
    expect(cycles.single.expectedAmountMinor, 250000);
    expect(cycles.single.settledAt, isNotNull);
  });

  /// The text sitting in the "Fee for this month" box, if it is on screen.
  String feeFieldText(WidgetTester tester) => tester
      .widget<TextField>(find.descendant(
        of: find.widgetWithText(TextFormField, 'Fee for this month *'),
        matching: find.byType(TextField),
      ))
      .controller!
      .text;

  testWidgets('a past month is not pre-filled with what the fee is today',
      (tester) async {
    await openDialog(tester);
    await chooseMonthBack(tester, 4); // September -> May

    expect(
      feeFieldText(tester),
      isEmpty,
      reason: 'today\'s fee is the one answer that is certainly wrong for a '
          'month in the past. A gym typing up last year\'s register after a '
          'price rise would accept it once per row, conjure every old month '
          'at the new price, mark it paid in full and leave it permanently '
          'short — and a cycle holding money is never re-priced, so nothing '
          'can put it back',
    );
  });

  testWidgets('the current month still opens with today\'s fee ready',
      (tester) async {
    await openDialog(tester);
    await chooseMonthBack(tester, 0);

    expect(
      feeFieldText(tester),
      '1500',
      reason: 'for the month in front of the owner today\'s fee is the right '
          'answer, and making them retype it is friction for nothing',
    );
  });

  testWidgets('a month before the member joined is refused', (tester) async {
    await openDialog(tester);
    // The member joined 01 Jan 2026; September minus 10 months is November
    // 2025, which no confirmation can make billable.
    await chooseMonthBack(tester, 10);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount received *'), '1500');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Fee for this month *'), '1500');
    await tester.pump();

    await tapAndSettle(tester, find.text('Confirm Payment'));

    expect(find.text('Payment recorded'), findsNothing);
    expect(find.textContaining('before their membership started'),
        findsWidgets);
    expect(await periodsForMember(db, memberId), isEmpty,
        reason: 'a blocked month must not leave a cycle behind');
  });

  testWidgets('clearing the month returns to Automatic', (tester) async {
    await openDialog(tester);
    await chooseMonthBack(tester, 4);
    expect(find.text('Fee for this month *'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to automatic'));
    await tester.pumpAndSettle();

    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Fee for this month *'), findsNothing);
  });
}
