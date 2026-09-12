import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
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

/// Which months the Record Payment dialog claims a named month settles.
///
/// Naming a month does not mean the money lands on a cycle starting that
/// month: `periodForMemberContaining` resolves by containment, so on a
/// quarterly plan every month of the quarter resolves to the one cycle that
/// covers it. The money has always gone to the right place. The label was
/// built from the month the owner picked instead of the cycle it resolved to,
/// so it named a span that does not exist — which on a receipt query is the
/// difference between answering the member and arguing with them.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late RecordPaymentService payments;
  late int memberId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);

    final quarterlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Quarterly')))
            .getSingle())
        .id;

    // Joined at the start of August, so the quarter runs August to October and
    // September sits in the middle of it.
    memberId = await members.create(
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: quarterlyId,
      joiningDate: DateTime.utc(2026, 8, 1),
    );
    // Rolled forward while it was still August, so the quarter anchors there
    // and runs August to October. September — today — sits in the middle of
    // it, which is the case the label got wrong.
    await BillingMaintenance(db)
        .ensureCurrentPeriods(now: DateTime.utc(2026, 8, 12));

    final workspace = await Directory.systemTemp.createTemp('rmf-label');
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

  /// Names the current month in the picker — September 2026.
  Future<void> chooseThisMonth(WidgetTester tester) async {
    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('${DateTime.now().year}'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('a named month names the quarter it actually settles',
      (tester) async {
    await openDialog(tester);
    await chooseThisMonth(tester);

    expect(
      find.textContaining('August 2026 - October 2026'),
      findsWidgets,
      reason: 'September resolves to the August quarter, and that is the '
          'cycle this payment settles',
    );
    expect(
      find.textContaining('September 2026 - November 2026'),
      findsNothing,
      reason: 'no such cycle exists — the label was counting three months '
          'from the month picked rather than from the cycle it landed on',
    );
  });
}
