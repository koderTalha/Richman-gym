import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/branding_cubit.dart';
import 'package:rich_man_fitness/bloc/revenue_visibility_cubit.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/money.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:rich_man_fitness/ui/dashboard_screen.dart';
import 'package:rich_man_fitness/ui/widgets/revenue_visibility.dart';

import 'support/still_motion.dart';

/// The owner can hide the dashboard's revenue from whoever is standing at the
/// counter. One eye hides every revenue figure — the month's, today's and the
/// month's again in the greeting — and the figures come back unchanged.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
  });

  tearDown(() async => db.close());

  Future<RevenueVisibilityCubit> pumpDashboard(WidgetTester tester,
      {RevenueVisibilityCubit? visibility}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cubit = visibility ?? RevenueVisibilityCubit();
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => MemberRepository(db)),
        RepositoryProvider(create: (_) => PaymentRepository(db)),
        RepositoryProvider(create: (_) => ReceiptRepository(db)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => BrandingCubit(SettingsRepository(db),
                initial: const BrandingConfig()),
          ),
          BlocProvider.value(value: cubit),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          builder: stillMotion,
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return cubit;
  }

  /// How many copies of [text] are painted, as opposed to merely laid out:
  /// [ObscuredText] keeps both the amount and the mask in the tree and fades
  /// one of them to nothing.
  int painted(WidgetTester tester, String text) => tester
      .widgetList<Text>(find.text(text))
      .where((t) => tester
          .widgetList<AnimatedOpacity>(find.ancestor(
            of: find.byWidget(t),
            matching: find.byType(AnimatedOpacity),
          ))
          .every((o) => o.opacity == 1))
      .length;

  final amount = formatMinorUnits(0);

  testWidgets('figures are visible at first, with one eye to hide them',
      (tester) async {
    await pumpDashboard(tester);

    expect(painted(tester, amount), 3,
        reason: 'the month, today, and the month again in the greeting');
    expect(painted(tester, revenueMask), 0);
    expect(find.byTooltip('Hide revenue'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('the eye hides every figure, and brings them all back',
      (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.byTooltip('Hide revenue'));
    await tester.pumpAndSettle();

    expect(painted(tester, amount), 0);
    expect(painted(tester, revenueMask), 3);
    expect(find.byTooltip('Show revenue'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    await tester.tap(find.byTooltip('Show revenue'));
    await tester.pumpAndSettle();

    expect(painted(tester, amount), 3);
    expect(painted(tester, revenueMask), 0);
  });

  testWidgets('a hidden amount is not read out by a screen reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpDashboard(tester);

    /// Every label a screen reader could reach, from the live tree.
    List<String> labels() {
      final found = <String>[];
      bool visit(SemanticsNode node) {
        found.add(node.label);
        node.visitChildren(visit);
        return true;
      }

      visit(tester.getSemantics(find.byType(DashboardScreen)));
      return found;
    }

    expect(labels().where((l) => l.contains(amount)), isNotEmpty);

    await tester.tap(find.byTooltip('Hide revenue'));
    await tester.pumpAndSettle();

    expect(labels().where((l) => l.contains(amount)), isEmpty);
    semantics.dispose();
  });

  testWidgets('works from the keyboard', (tester) async {
    await pumpDashboard(tester);

    Focus.of(tester.element(find.byIcon(Icons.visibility_outlined)))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(painted(tester, revenueMask), 3);
  });

  testWidgets('hiding does not move anything beside the figure',
      (tester) async {
    await pumpDashboard(tester);
    final hint = find.text('· 0 payments');
    final before = tester.getTopLeft(hint);

    await tester.tap(find.byTooltip('Hide revenue'));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(hint), before);
  });

  testWidgets('the eye ends the stats row, after every figure',
      (tester) async {
    await pumpDashboard(tester);

    final eye = tester.getRect(find.byType(RevenueVisibilityButton));
    // StatFigure draws its labels in capitals.
    final today = tester.getRect(find.text('TODAY'));
    final members = tester.getRect(find.text('ACTIVE MEMBERS'));

    // On the stats row, not up in the header beside Refresh.
    expect(eye.bottom, greaterThan(today.top));
    expect(eye.top, lessThan(members.bottom + 40));
    // Past the last figure, at the row's right end.
    expect(eye.left, greaterThan(members.right));
    expect(find.descendant(
            of: find.ancestor(
                of: find.text('Refresh'), matching: find.byType(Row)),
            matching: find.byType(RevenueVisibilityButton)),
        findsNothing);
  });

  testWidgets('stays hidden when the dashboard is opened again',
      (tester) async {
    final cubit = await pumpDashboard(tester);
    cubit.toggle();
    await tester.pumpAndSettle();

    // Navigating away and back builds a new DashboardScreen.
    await tester.pumpWidget(const SizedBox());
    await pumpDashboard(tester, visibility: cubit);

    expect(painted(tester, revenueMask), 3);
    expect(painted(tester, amount), 0);
  });
}
