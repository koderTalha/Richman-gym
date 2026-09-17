import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/services/update/connection_diagnostics.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/settings/connection_test_dialog.dart';

/// The dialog a non-technical owner — or whoever they are reading the screen
/// to down the phone — opens by pressing "Test Connection".
void main() {
  Future<void> pump(
    WidgetTester tester,
    Future<ConnectionTestReport> Function() run,
  ) async {
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
              builder: (_) => ConnectionTestDialog(run: run),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  ConnectionTestReport reportWith({required bool githubPasses}) =>
      ConnectionTestReport(
        at: DateTime(2026, 9, 16, 10, 30),
        layers: [
          const LayerResult(
              layer: ConnectivityLayer.adapter,
              label: 'Internet connection',
              passed: true),
          const LayerResult(
              layer: ConnectivityLayer.dns, label: 'DNS', passed: true),
          const LayerResult(
              layer: ConnectivityLayer.secureConnection,
              label: 'Secure connection',
              passed: true),
          const LayerResult(
              layer: ConnectivityLayer.proxy,
              label: 'Proxy',
              passed: true,
              applicable: false),
          LayerResult(
              layer: ConnectivityLayer.githubService,
              label: 'GitHub update service',
              passed: githubPasses),
        ],
        summary: githubPasses
            ? 'This computer can reach GitHub normally.'
            : 'GitHub could not be reached from this computer.',
      );

  testWidgets('shows a checkmark for every passing layer', (tester) async {
    await pump(tester, () async => reportWith(githubPasses: true));
    await tester.pump();

    expect(find.text('Internet connection'), findsOneWidget);
    expect(find.text('DNS'), findsOneWidget);
    expect(find.text('GitHub update service'), findsOneWidget);
    expect(find.text('This computer can reach GitHub normally.'),
        findsOneWidget);
  });

  testWidgets('names the failing layer when GitHub cannot be reached',
      (tester) async {
    await pump(tester, () async => reportWith(githubPasses: false));
    await tester.pump();

    expect(find.text('GitHub could not be reached from this computer.'),
        findsOneWidget);
  });

  testWidgets('shows a spinner while the test is still running',
      (tester) async {
    final completer = Completer<ConnectionTestReport>();
    await pump(tester, () => completer.future);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(reportWith(githubPasses: true));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Copy Details is offered once the result is in', (tester) async {
    await pump(tester, () async => reportWith(githubPasses: false));
    await tester.pump();

    expect(find.widgetWithText(TextButton, 'Copy Details'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await pump(tester, () async => reportWith(githubPasses: true));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}
