import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/revenue_visibility_cubit.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/report_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/reports/reports_screen.dart';
import 'package:rich_man_fitness/ui/widgets/revenue_visibility.dart';

import 'support/still_motion.dart';

/// The Reports screen with real rows behind it: that it lays out at every
/// width from a phone-narrow window up, that the eye hides its money, and that
/// its sorting, filters and month navigation do what they say.
void main() {
  late AppDatabase db;
  final today = DateTime(2026, 10, 15, 12);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    final admin = (await db.select(db.users).getSingle()).id;
    final plan = (await db.select(db.membershipPlans).get()).first.id;

    var key = 0;
    Future<void> member(String name, int code,
        {required DateTime joined, required List<(DateTime, int, PaymentMethod)> paid}) async {
      final id = await db.into(db.members).insert(MembersCompanion.insert(
            memberCode: code,
            fullName: name,
            phone: '+92300000${code.toString().padLeft(4, '0')}',
            joiningDate: joined,
          ));
      final membership = await db.into(db.memberships).insert(
          MembershipsCompanion.insert(
              memberId: id, planId: plan, startDate: joined));
      final period = await db.into(db.membershipPeriods).insert(
          MembershipPeriodsCompanion.insert(
            membershipId: membership,
            periodStart: DateTime.utc(2026, 10, 1),
            periodEnd: DateTime.utc(2026, 11, 1),
            expectedAmountMinor: 300000,
          ));
      for (final (on, amount, method) in paid) {
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              memberId: id,
              membershipPeriodId: Value(period),
              amountMinor: amount,
              method: method,
              paymentDate: on,
              recordedById: admin,
              idempotencyKey: 'k${key++}',
            ));
      }
    }

    await member('Test Member With A Rather Long Name', 1,
        joined: DateTime.utc(2026, 3, 1),
        paid: [(DateTime(2026, 10, 3, 10), 300000, PaymentMethod.cash)]);
    await member('Test Payer', 2,
        joined: DateTime.utc(2026, 10, 2),
        paid: [(DateTime(2026, 10, 9, 10), 750000, PaymentMethod.easypaisa)]);
    await member('Test September', 3,
        joined: DateTime.utc(2026, 5, 1),
        paid: [(DateTime(2026, 9, 9, 10), 120000, PaymentMethod.cash)]);
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, double width,
      {double height = 1400}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<MemberRepository>(
            create: (_) => MemberRepository(db)),
        RepositoryProvider<SettingsRepository>(
            create: (_) => SettingsRepository(db, audit: AuditRepository(db))),
      ],
      child: BlocProvider(
        create: (_) => RevenueVisibilityCubit(),
        child: MaterialApp(
          theme: buildDarkTheme(),
          builder: stillMotion,
          home: Scaffold(
            body: ReportsScreen(
              repository: ReportRepository(db, clock: () => today),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // The brief's widths, from a phone-narrow window to a wide monitor. The
  // owner runs it on a desktop, but a window dragged narrow must not break.
  for (final width in const [320.0, 375.0, 768.0, 1024.0, 1440.0, 1920.0]) {
    testWidgets('lays out at ${width.toInt()}px with nothing overflowing',
        (tester) async {
      await pump(tester, width);
      expect(tester.takeException(), isNull);
      expect(find.text('Reports & Analytics'), findsOneWidget);
      expect(find.text('October 2026'), findsWidgets);

      // The other half of the detail section lays out too.
      await tester.scrollUntilVisible(find.text('Membership'), 400,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Membership'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the month\'s revenue is on the card, and the eye hides it',
      (tester) async {
    await pump(tester, 1440);

    ObscuredText revenueFigure() => tester
        .widgetList<ObscuredText>(find.byType(ObscuredText))
        .firstWhere((w) => w.text == 'Rs. 10,500');
    expect(revenueFigure().obscured, isFalse);

    await tester.tap(find.byTooltip('Hide revenue'));
    await tester.pumpAndSettle();
    expect(revenueFigure().obscured, isTrue);
    expect(find.text('Rs. 7,500'), findsNothing,
        reason: 'the table\'s amounts are masked too');
  });

  testWidgets('sorting the payments by amount puts the largest first',
      (tester) async {
    await pump(tester, 1440);
    final amount = find.text('AMOUNT');
    await tester.scrollUntilVisible(amount, 400,
        scrollable: find.byType(Scrollable).first);

    // Newest first by default: the 9th above the 3rd.
    double y(String text) => tester.getTopLeft(find.text(text).last).dy;
    expect(y('09 Oct 2026'), lessThan(y('03 Oct 2026')));

    await tester.tap(amount);
    await tester.pumpAndSettle();
    expect(y('Rs. 7,500'), lessThan(y('Rs. 3,000')));

    await tester.tap(amount);
    await tester.pumpAndSettle();
    expect(y('Rs. 3,000'), lessThan(y('Rs. 7,500')),
        reason: 'a second tap reverses the order');
  });

  testWidgets('a method filter narrows the figures and Reset brings them back',
      (tester) async {
    await pump(tester, 1440);
    expect(find.text('Reset filters'), findsOneWidget);

    await tester.tap(find.text('All methods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easypaisa').last);
    await tester.pumpAndSettle();

    expect(find.text('Method: Easypaisa'), findsOneWidget,
        reason: 'the active filter is shown');
    expect(
      tester
          .widgetList<ObscuredText>(find.byType(ObscuredText))
          .any((w) => w.text == 'Rs. 7,500'),
      isTrue,
    );
    expect(
      tester
          .widgetList<ObscuredText>(find.byType(ObscuredText))
          .any((w) => w.text == 'Rs. 10,500'),
      isFalse,
    );

    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    expect(find.text('Method: Easypaisa'), findsNothing);
    expect(
      tester
          .widgetList<ObscuredText>(find.byType(ObscuredText))
          .any((w) => w.text == 'Rs. 10,500'),
      isTrue,
    );
  });

  testWidgets('the previous month is a click away, and the next is not '
      'beyond today', (tester) async {
    await pump(tester, 1440);
    expect(
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
        isNull);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsWidgets);
    expect(find.text('This month'), findsOneWidget);
    expect(
      tester
          .widgetList<ObscuredText>(find.byType(ObscuredText))
          .any((w) => w.text == 'Rs. 1,200'),
      isTrue,
    );
  });
}
