import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/settings/backup_card.dart';

/// A restore is staged only once the signed-in account's password has been
/// typed (audit SEC-002): the session outlives the app, so being signed in
/// says nothing about who is at the keyboard now.
void main() {
  /// Opens the dialog the way the Backup card does and reports what it
  /// answered. [verify] stands in for the bcrypt check.
  Future<bool? Function()> open(
    WidgetTester tester, {
    required Future<bool> Function(String) verify,
  }) async {
    bool? answer;
    var answered = false;

    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              answer = await showDialog<bool>(
                context: context,
                builder: (_) => RestoreConfirmDialog(verify: verify),
              );
              answered = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    return () => answered ? answer : null;
  }

  testWidgets('the right password confirms the restore', (tester) async {
    final tried = <String>[];
    final answer = await open(tester, verify: (pw) async {
      tried.add(pw);
      return pw == 'OwnersOwnSecret9';
    });

    await tester.enterText(
        find.byKey(restorePasswordFieldKey), 'OwnersOwnSecret9');
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(tried, ['OwnersOwnSecret9']);
    expect(answer(), isTrue);
    expect(find.byType(RestoreConfirmDialog), findsNothing);
  });

  testWidgets('a wrong password keeps the dialog open and stages nothing',
      (tester) async {
    final answer = await open(tester, verify: (_) async => false);

    await tester.enterText(find.byKey(restorePasswordFieldKey), 'guess');
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.byType(RestoreConfirmDialog), findsOneWidget);
    expect(find.textContaining('not the password'), findsOneWidget);
    expect(answer(), isNull, reason: 'the dialog has not answered at all');
  });

  testWidgets('one more click without a password is not enough',
      (tester) async {
    final tried = <String>[];
    await open(tester, verify: (pw) async {
      tried.add(pw);
      return false;
    });

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.byType(RestoreConfirmDialog), findsOneWidget);
    expect(tried, ['']);
  });

  testWidgets('cancel answers no', (tester) async {
    final answer = await open(tester, verify: (_) async => true);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answer(), isFalse);
  });

  testWidgets('a check that throws is a refusal, not a restore',
      (tester) async {
    final answer =
        await open(tester, verify: (_) async => throw StateError('db gone'));

    await tester.enterText(find.byKey(restorePasswordFieldKey), 'anything');
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.byType(RestoreConfirmDialog), findsOneWidget);
    expect(answer(), isNull);
  });
}
