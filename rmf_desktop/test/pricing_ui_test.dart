import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/members/pricing_summary.dart';
import 'package:rich_man_fitness/ui/settings/plan_price_change_dialog.dart';

/// Telling the owner what a pricing change is about to do, before it does it.
///
/// Both screens could move money silently: the fee field is one number in a
/// form of eleven, and the plan price field re-prices the open bills of every
/// member on that plan. Neither said so.
///
/// The wording is load-bearing and easy to get subtly wrong. "Future unpaid
/// bills will use the new fee" reads as *next* month, and an owner who
/// believes it will collect the old fee for the month in front of them — which
/// is the exact sequence that left the leftover money spilling into an
/// early-opened cycle and a member in permanent arrears. The change reaches
/// the cycle they are standing in, and the copy has to say so.
void main() {
  Future<void> pumpSummary(
    WidgetTester tester, {
    required int planPriceMinor,
    int? customFeeMinor,
    int? billedNowMinor,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: PricingSummary(
          planPriceMinor: planPriceMinor,
          customFeeMinor: customFeeMinor,
          billedNowMinor: billedNowMinor,
        ),
      ),
    ));
  }

  group('the Edit Member pricing summary', () {
    testWidgets('shows the plan price and says the member follows it',
        (tester) async {
      await pumpSummary(tester, planPriceMinor: 150000);

      expect(find.textContaining('Rs. 1,500'), findsWidgets);
      expect(find.textContaining('Follows the plan price'), findsOneWidget);
    });

    testWidgets('shows a custom fee winning over the plan price',
        (tester) async {
      await pumpSummary(tester,
          planPriceMinor: 150000, customFeeMinor: 180000);

      expect(find.textContaining('Rs. 1,800'), findsWidgets);
      expect(find.textContaining('Billed each cycle'), findsOneWidget);
    });

    testWidgets('says nothing about a change when the fee has not moved',
        (tester) async {
      await pumpSummary(tester,
          planPriceMinor: 150000, billedNowMinor: 150000);

      expect(find.textContaining('change'), findsNothing);
    });

    testWidgets('warns that the current bill moves, not just future ones',
        (tester) async {
      await pumpSummary(tester,
          planPriceMinor: 150000,
          customFeeMinor: 200000,
          billedNowMinor: 150000);

      final warning = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      expect(warning, contains('Rs. 1,500'));
      expect(warning, contains('Rs. 2,000'));
      expect(warning.toLowerCase(), contains('this month'),
          reason: 'saying only "future bills" invites the owner to collect '
              'the old fee for the month in front of them');
      expect(warning.toLowerCase(), contains('already paid'),
          reason: 'the reassurance that history is safe is the other half');
    });

    testWidgets('warns when a custom fee is removed, naming the plan price',
        (tester) async {
      await pumpSummary(tester,
          planPriceMinor: 150000,
          customFeeMinor: null,
          billedNowMinor: 200000);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      expect(text, contains('Rs. 2,000'));
      expect(text, contains('Rs. 1,500'),
          reason: 'clearing the field drops them to the plan price, and the '
              'owner should see the number they are dropping to');
    });
  });

  group('the plan price change confirmation', () {
    Future<void> pumpDialog(
      WidgetTester tester, {
      required PlanPricingImpact impact,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: PlanPriceChangeDialog(
            planName: 'Monthly',
            previousPriceMinor: 150000,
            newPriceMinor: 250000,
            impact: impact,
          ),
        ),
      ));
    }

    testWidgets('names both prices and counts who moves', (tester) async {
      await pumpDialog(tester,
          impact: const PlanPricingImpact(
              followingPlanPrice: 23, onCustomFee: 4));

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      expect(text, contains('Monthly'));
      expect(text, contains('Rs. 1,500'));
      expect(text, contains('Rs. 2,500'));
      expect(text, contains('23'));
      expect(text, contains('4'));
      expect(text.toLowerCase(), contains('custom fee'),
          reason: 'the owner needs to know the override holders stay put');
    });

    testWidgets('does not mention custom fees when nobody has one',
        (tester) async {
      await pumpDialog(tester,
          impact: const PlanPricingImpact(followingPlanPrice: 5));

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      expect(text.toLowerCase(), isNot(contains('custom fee')));
    });

    testWidgets('says so plainly when the plan has no members', (tester) async {
      await pumpDialog(tester, impact: const PlanPricingImpact());

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');

      expect(text.toLowerCase(), contains('no members'));
    });

    testWidgets('offers a way out', (tester) async {
      await pumpDialog(tester,
          impact: const PlanPricingImpact(followingPlanPrice: 5));

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Change price'), findsOneWidget);
    });
  });
}
