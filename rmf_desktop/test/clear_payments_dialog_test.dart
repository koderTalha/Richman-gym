import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/payments/clear_payments_action.dart';

/// The guard on the most destructive button in the app.
///
/// Deleting one payment asks a yes/no question, because one row is a mistake
/// the owner can see and put back by hand. Deleting all of them cannot be put
/// back at all — every receipt the member was ever given stops existing — so
/// the question is answered by typing the member's name, not by pressing
/// Enter twice.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String memberName = 'Abdul Qadir',
    int count = 8,
    int totalMinor = 1700000,
    int receiptCount = 8,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: ClearPaymentsConfirmDialog(
          memberName: memberName,
          count: count,
          totalMinor: totalMinor,
          receiptCount: receiptCount,
        ),
      ),
    ));
  }

  final confirmButton =
      find.widgetWithText(FilledButton, 'Delete 8 payments');

  testWidgets('says exactly what is about to go', (tester) async {
    await pump(tester);

    expect(find.textContaining('Abdul Qadir'), findsWidgets);
    expect(find.text('8'), findsWidgets, reason: 'the payment count');
    expect(find.textContaining('Rs. 17,000'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
  });

  testWidgets('promises the billing months survive, and asks for a backup',
      (tester) async {
    await pump(tester);

    expect(find.textContaining('billing months are kept'), findsOneWidget);
    expect(find.textContaining('Take a backup first'), findsOneWidget);
  });

  testWidgets('the delete button starts disabled', (tester) async {
    await pump(tester);

    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
  });

  testWidgets('a wrong name leaves it disabled', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'Abdul');
    await tester.pump();

    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull,
        reason: 'half the name is not the name');
  });

  testWidgets('another member on the roster does not unlock it', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'Bilal Ahmed');
    await tester.pump();

    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
  });

  testWidgets('the exact name unlocks it', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'Abdul Qadir');
    await tester.pump();

    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
  });

  testWidgets('case and stray spacing are not the point', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '  abdul qadir  ');
    await tester.pump();

    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
  });

  testWidgets('Keep them is always available', (tester) async {
    await pump(tester);

    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Keep them'))
            .onPressed,
        isNotNull);
  });
}
