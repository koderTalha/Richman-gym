import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/diagnostics/send_to_developer.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/send_to_developer_dialog.dart';

/// The dialog the owner fills in when something is wrong, from Settings or
/// from the screen shown when the data would not open.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Future<DiagnosticsResult> Function(String note) send,
    bool configured = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  SendToDeveloperDialog(send: send, configured: configured),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sends the note and shows the reference', (tester) async {
    String? sentNote;
    final reply = Completer<DiagnosticsResult>();
    await pump(tester, send: (note) {
      sentNote = note;
      return reply.future;
    });

    await tester.enterText(find.byType(TextField), '  Payment shows due  ');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sentNote, 'Payment shows due');
    expect(find.text('Sending…'), findsOneWidget);
    // Not closable half way through a send.
    expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull);

    reply.complete(
        const DiagnosticsSent(reference: 'RMF-20261001-1432', bytes: 231240));
    await tester.pumpAndSettle();

    expect(find.textContaining('RMF-20261001-1432'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SendToDeveloperDialog), findsNothing);
  });

  testWidgets('a failure is shown, the note is kept, and it can be retried',
      (tester) async {
    var attempts = 0;
    await pump(tester, send: (_) async {
      attempts++;
      return attempts == 1
          ? const DiagnosticsFailed('Could not reach Google. Check this '
              'computer is connected to the internet, then try again.')
          : const DiagnosticsSent(reference: 'RMF-20261001-1433', bytes: 1);
    });

    await tester.enterText(find.byType(TextField), 'App is slow');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach Google'), findsOneWidget);
    expect(find.text('App is slow'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.textContaining('RMF-20261001-1433'), findsOneWidget);
  });

  testWidgets('a build that cannot send says so and offers no Send button',
      (tester) async {
    var called = false;
    await pump(tester, configured: false, send: (_) async {
      called = true;
      return const DiagnosticsSent(reference: 'x', bytes: 0);
    });

    expect(find.textContaining('built without'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(called, isFalse);
  });
}
