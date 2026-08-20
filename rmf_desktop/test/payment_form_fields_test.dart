import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/payments/payment_form_fields.dart';

/// Record Payment and Edit Payment share these fields. The point of the shared
/// widget is that the validation, the defaults and the period label are written
/// once — so these are the guards that the extraction did not quietly drop any
/// of them.
void main() {
  late PaymentFormController form;
  final formKey = GlobalKey<FormState>();

  tearDown(() => form.dispose());

  Future<void> pump(
    WidgetTester tester, {
    int planDurationMonths = 1,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Form(
          key: formKey,
          child: PaymentFormFields(
            controller: form,
            planDurationMonths: planDurationMonths,
            enabled: enabled,
            autofocus: false,
          ),
        ),
      ),
    ));
  }

  testWidgets('opens on the plan fee, formatted without decimals',
      (tester) async {
    form = PaymentFormController(
      billingMonth: '2026-08',
      initialAmountMinor: 300000,
    );
    await pump(tester);

    expect(find.text('3000'), findsOneWidget);
    expect(form.amountMinor, 300000);
  });

  testWidgets('rejects a blank, zero or negative amount', (tester) async {
    form = PaymentFormController(billingMonth: '2026-08');
    await pump(tester);

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter an amount greater than zero'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '0');
    expect(formKey.currentState!.validate(), isFalse);

    await tester.enterText(find.byType(TextFormField).first, '-5');
    expect(formKey.currentState!.validate(), isFalse);

    await tester.enterText(find.byType(TextFormField).first, '2500');
    expect(formKey.currentState!.validate(), isTrue);
    expect(form.amountMinor, 250000);
  });

  testWidgets('a one-month plan names one month', (tester) async {
    form = PaymentFormController(billingMonth: '2026-08');
    await pump(tester);

    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('a quarterly plan names both ends of the cycle', (tester) async {
    form = PaymentFormController(billingMonth: '2026-08');
    await pump(tester, planDurationMonths: 3);

    expect(find.text('August 2026 - October 2026'), findsOneWidget,
        reason: 'the label must follow the plan length, not assume one month');
    expect(find.text('August 2026'), findsNothing);
  });

  testWidgets('an annual plan crosses the year correctly', (tester) async {
    form = PaymentFormController(billingMonth: '2026-08');
    await pump(tester, planDurationMonths: 12);

    expect(find.text('August 2026 - July 2027'), findsOneWidget);
  });

  testWidgets('nothing can be edited while a save is in flight',
      (tester) async {
    form = PaymentFormController(
      billingMonth: '2026-08',
      initialAmountMinor: 300000,
    );
    await pump(tester, enabled: false);

    for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField))) {
      expect(field.enabled, isFalse);
    }

    // The pickers stop responding too, so a date cannot change mid-submit.
    await tester.tap(find.text('August 2026'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
  });

  testWidgets('carries the existing values through when editing',
      (tester) async {
    form = PaymentFormController(
      billingMonth: '2026-03',
      initialAmountMinor: 450000,
      method: PaymentMethod.easypaisa,
      paymentDate: DateTime(2026, 3, 5),
      referenceNumber: 'TRX-77',
      notes: 'paid at the counter',
    );
    await pump(tester);

    expect(find.text('4500'), findsOneWidget);
    expect(find.text('TRX-77'), findsOneWidget);
    expect(find.text('paid at the counter'), findsOneWidget);
    expect(find.text('05 Mar 2026'), findsOneWidget);
    expect(find.text('March 2026'), findsOneWidget);
    expect(find.text('Easypaisa'), findsOneWidget);

    expect(form.referenceOrNull, 'TRX-77');
    expect(form.notesOrNull, 'paid at the counter');
  });

  testWidgets('blank optional fields read as absent, not as empty strings',
      (tester) async {
    form = PaymentFormController(billingMonth: '2026-08');
    await pump(tester);

    await tester.enterText(find.byType(TextFormField).at(1), '   ');

    expect(form.referenceOrNull, isNull);
    expect(form.notesOrNull, isNull);
  });
}
